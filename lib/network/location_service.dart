import 'package:geolocator/geolocator.dart';
import 'mqtt.dart';
import 'dart:async';
import 'dart:convert';
import '../constants.dart';
import '../database/db_helper.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStreamSubscription;
  MQTTClientWrapper? _mqttClient;
  Function()? _onExitedOffice;
  double? _refLat;
  double? _refLng;

  Future<bool> handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  void startTracking(MQTTClientWrapper mqttClient, {double? centerLat, double? centerLng, Function()? onExitedOffice}) async {
    _mqttClient = mqttClient;
    _onExitedOffice = onExitedOffice;
    _refLat = centerLat;
    _refLng = centerLng;

    final hasPermission = await handleLocationPermission();
    if (!hasPermission) return;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position? position) {
        if (position != null) {
          _sendLocationUpdate(position);
          _checkGeofence(position);
        }
      },
    );
  }

  void stopTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _onExitedOffice = null;
    _refLat = null;
    _refLng = null;
  }

  void _checkGeofence(Position position) async {
    // Load office coordinates and radius from settings
    double refLat = _refLat ?? kOfficeLatitude;
    double refLng = _refLng ?? kOfficeLongitude;
    double radius = kGeofenceRadiusMeter;

    final savedLat = await DatabaseHelper.instance.getSetting('office_latitude');
    final savedLng = await DatabaseHelper.instance.getSetting('office_longitude');
    final savedRadius = await DatabaseHelper.instance.getSetting('geofence_radius');

    if (_refLat == null && savedLat != null && savedLng != null) {
      refLat = double.tryParse(savedLat) ?? kOfficeLatitude;
      refLng = double.tryParse(savedLng) ?? kOfficeLongitude;
    }
    
    if (savedRadius != null) {
      radius = double.tryParse(savedRadius) ?? kGeofenceRadiusMeter;
    }

    double distanceInMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      refLat,
      refLng,
    );

    if (distanceInMeters > radius) {
      if (_onExitedOffice != null) {
        _onExitedOffice!();
      }
    }
  }

  void _sendLocationUpdate(Position position) {
    if (_mqttClient != null && _mqttClient!.connectionState == MqttCurrentConnectionState.connected) {
      final data = {
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': DateTime.now().toIso8601String(),
        'userId': 'user_123', // Hardcoded for now
      };
      _mqttClient!.publishMessage(jsonEncode(data), topic: '/location/updates');
    }
  }
}
