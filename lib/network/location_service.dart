import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/mqtt_handler.dart';
import 'dart:async';
import '../constants.dart';
import '../database/db_helper.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStreamSubscription;
  MqttHandler? _mqttClient;
  String? _empId;
  Function()? _onExitedOffice;
  double? _refLat;
  double? _refLng;

  Future<bool> handleLocationPermission(BuildContext context) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled. Please enable them.')),
        );
      }
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied.')),
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied. We cannot request permissions.'),
          ),
        );
      }
      return false;
    }

    return true;
  }

  void startTracking(MqttHandler mqttClient, BuildContext context, {double? centerLat, double? centerLng, Function()? onExitedOffice}) async {
    _mqttClient = mqttClient;
    _onExitedOffice = onExitedOffice;
    _refLat = centerLat;
    _refLng = centerLng;

    // Fetch employee ID once when tracking starts
    final user = await DatabaseHelper.instance.getUser();
    _empId = user != null ? (user['emp_id'] ?? 'Unknown') : 'Unknown';

    if (!context.mounted) return;
    final hasPermission = await handleLocationPermission(context);
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

  Future<bool> checkTravelEligibility() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      double distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        kOfficeLatitude,
        kOfficeLongitude,
      );

      // Rule: Distance > 10,000 meters (10 km) returns true
      return distanceInMeters > 10000;
    } catch (e) {
      debugPrint("Error checking travel eligibility: $e");
      return false;
    }
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
    if (_mqttClient != null) {
      _mqttClient!.publishLocationUpdate(
        lat: position.latitude,
        lng: position.longitude,
        employeeId: _empId ?? 'Unknown',
      );
    }
  }
}
