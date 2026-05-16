import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import '../constants.dart';

class BackgroundGeofenceService {
  static bool _initialized = false;

  /// Configure the service. Called lazily before first startMonitoring().
  static Future<void> initialize() async {
    // Create the notification channel BEFORE configure() — required on Android 8.0+
    final flnPlugin = FlutterLocalNotificationsPlugin();
    const channel = AndroidNotificationChannel(
      'geofence_channel',
      'Geofence Monitoring',
      description: 'Foreground service notification for geofence monitoring',
      importance: Importance.low,
    );
    await flnPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    final service = FlutterBackgroundService();

    await service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        isForegroundMode: true,
        autoStart: false,
        autoStartOnBoot: false,
        foregroundServiceTypes: [AndroidForegroundType.location],
        notificationChannelId: 'geofence_channel',
        initialNotificationTitle: 'Attendance Active',
        initialNotificationContent: 'Monitoring office geofence…',
      ),
    );
    _initialized = true;
  }

  /// Start the foreground service after a successful check-in.
  static Future<void> startMonitoring({
    required int attendanceId,
    required String employeeId,
  }) async {
    // Ensure service is configured before starting
    if (!_initialized) {
      await initialize();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bg_checked_in', true);
    await prefs.setInt('bg_attendance_id', attendanceId);
    await prefs.setString('bg_employee_id', employeeId);

    final service = FlutterBackgroundService();
    await service.startService();
  }

  /// Stop the foreground service (manual checkout or after auto-checkout).
  static Future<void> stopMonitoring() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bg_checked_in', false);

    final service = FlutterBackgroundService();
    service.invoke('stop');
  }
}

/// iOS background handler stub
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

/// Entry point for the background isolate — runs as an Android foreground service.
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();

    service.on('stop').listen((_) {
      service.stopSelf();
    });
  }

  // Poll every 30 seconds (reduced from 5s to save battery and prevent crashes)
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    final prefs = await SharedPreferences.getInstance();
    final isCheckedIn = prefs.getBool('bg_checked_in') ?? false;

    if (!isCheckedIn) {
      timer.cancel();
      if (service is AndroidServiceInstance) service.stopSelf();
      return;
    }

    await _checkGeofenceAndAutoCheckout(service);
  });
}

/// Core logic: check GPS, if outside geofence → auto-checkout via DB + MQTT + notification.
Future<void> _checkGeofenceAndAutoCheckout(ServiceInstance service) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final attendanceId = prefs.getInt('bg_attendance_id');
    if (attendanceId == null) return;

    // Check if already checked out in DB
    final lastAttendance = await DatabaseHelper.instance.getLastAttendance();
    if (lastAttendance == null || lastAttendance['checkOutTime'] != null) {
      await prefs.setBool('bg_checked_in', false);
      service.invoke('auto_checkout_done');
      if (service is AndroidServiceInstance) service.stopSelf();
      return;
    }

    final checkInTime = DateTime.parse(lastAttendance['checkInTime']);
    final now = DateTime.now();

    // Stale session from a previous day — skip
    if (checkInTime.day != now.day ||
        checkInTime.month != now.month ||
        checkInTime.year != now.year) {
      return;
    }

    // Get current position with timeout to prevent hanging
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 15));

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      kOfficeLatitude,
      kOfficeLongitude,
    );

    // Still inside geofence — no action
    if (distance <= kGeofenceRadiusMeter) return;

    // Outside geofence → perform auto-checkout
    final timeString = now.toIso8601String();
    final Duration worked = now.difference(checkInTime);
    final String finalStatus = worked.inHours >= 9
        ? 'Present'
        : 'Auto-Checkout';

    await DatabaseHelper.instance.updateCheckOut(
      timeString,
      attendanceId,
      status: finalStatus,
    );

    await prefs.setBool('bg_checked_in', false);

    final empId =
        prefs.getString('bg_employee_id') ??
        prefs.getString('employee_id') ??
        'Unknown';

    // Publish attendance via a short-lived MQTT connection
    await _publishAutoCheckoutMqtt(
      status: finalStatus,
      lat: position.latitude,
      lng: position.longitude,
      employeeId: empId,
    );

    // Show notification
    await _showAutoCheckoutNotification(finalStatus);

    // Tell the UI (if alive) that auto-checkout happened
    service.invoke('auto_checkout_done');

    // Stop the foreground service
    if (service is AndroidServiceInstance) service.stopSelf();
  } catch (e) {
    debugPrint("BG SERVICE ERROR: $e");
    // Best-effort — will retry on next tick
  }
}

/// Lightweight MQTT publish from the background isolate.
Future<void> _publishAutoCheckoutMqtt({
  required String status,
  required double lat,
  required double lng,
  required String employeeId,
}) async {
  try {
    final clientId = 'bg_checkout_${Random().nextInt(100000)}';
    // FIXED: Use correct broker IP
    final client = MqttServerClient.withPort('13.203.2.58', clientId, 1883);
    client.connectTimeoutPeriod = 5000;
    client.keepAlivePeriod = 10;
    client.logging(on: false);

    final connMsg = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMsg;

    await client.connect();

    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      final payload = jsonEncode({
        "type": "attendance",
        "request_id": const Uuid().v4(),
        "status": status,
        "empstatus": "checkout",
        "employee_id": employeeId,
        "timestamp": DateTime.now().toIso8601String(),
        "location": {"lat": lat, "lng": lng},
      });

      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);
      client.publishMessage(
        'employee/tracker',
        MqttQos.atLeastOnce,
        builder.payload!,
      );

      await Future.delayed(const Duration(milliseconds: 500));
      client.disconnect();
    }
  } catch (_) {
    // Best-effort — DB checkout already saved
  }
}

/// Show a local notification from the background isolate.
Future<void> _showAutoCheckoutNotification(String status) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await plugin.initialize(initSettings);

  await plugin.show(
    2,
    'Auto Checkout',
    'You left the office area. Status: $status',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'auto_checkout',
        'Auto Checkout',
        channelDescription: 'Notifications for automatic checkout',
        importance: Importance.max,
        priority: Priority.high,
      ),
    ),
  );
}
