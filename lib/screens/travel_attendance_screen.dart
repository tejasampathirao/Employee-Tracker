import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/mqtt_handler.dart';
import '../database/db_helper.dart';
import '../constants.dart';

class TravelAttendanceScreen extends StatefulWidget {
  const TravelAttendanceScreen({super.key});
  static const String id = 'travel_attendance_screen';

  @override
  State<TravelAttendanceScreen> createState() => _TravelAttendanceScreenState();
}

class _TravelAttendanceScreenState extends State<TravelAttendanceScreen> {
  // 1. Geofence Constants & State
  final double officeLat = kOfficeLatitude;
  final double officeLng = kOfficeLongitude;
  final double geofenceRadius = 10000; // 10 km in meters

  bool isBeyond10km = false;
  bool isTravelCheckedIn = false;
  double currentDistance = 0.0;
  int? currentRecordId;

  StreamSubscription<Position>? _positionStream;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
    _startLocationStream();
  }

  Future<void> _loadInitialState() async {
    final lastRecord = await DatabaseHelper.instance.getLastTravelAttendance();
    if (mounted) {
      setState(() {
        if (lastRecord != null && lastRecord['status'] == 'Checked-In') {
          isTravelCheckedIn = true;
          currentRecordId = lastRecord['id'];
        }
        _isLoading = false;
      });
    }
  }

  // 2. Continuous Location Stream
  void _startLocationStream() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50, // Updated: Send tracking payload every 50 meters
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) async {
        double distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          officeLat,
          officeLng,
        );

        if (mounted) {
          setState(() {
            currentDistance = distance;
            isBeyond10km = distance > geofenceRadius;
          });

          // Fetch user info for MQTT payloads
          final user = await DatabaseHelper.instance.getUser();
          final String empId = user != null ? (user['emp_id'] ?? 'Unknown') : 'Unknown';

          // 2. Live Tracking Payload (Only if actively checked-in for travel)
          if (isTravelCheckedIn) {
            MqttHandler().publishLocationUpdate(
              lat: position.latitude,
              lng: position.longitude,
              employeeId: empId,
            );
          }

          // 3. Auto Check-out Logic
          if (isTravelCheckedIn && distance <= geofenceRadius) {
            _handleCheckout(auto: true);
          }
        }
      },
    );
  }

  Future<void> _handleCheckIn() async {
    setState(() => _isLoading = true);
    try {
      Position position = await Geolocator.getCurrentPosition();
      final user = await DatabaseHelper.instance.getUser();
      String empId = user != null ? (user['emp_id'] ?? 'Unknown') : 'Unknown';
      String now = DateTime.now().toIso8601String();
      String date = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Save to SQLite
      int id = await DatabaseHelper.instance.checkInTravel(
        now, date, position.latitude, position.longitude, empId
      );

      // Publish to MQTT with "action": "check-in"
      MqttHandler().publishTravelAttendance(
        action: "check-in",
        lat: position.latitude,
        lng: position.longitude,
        employeeId: empId,
      );

      setState(() {
        isTravelCheckedIn = true;
        currentRecordId = id;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Travel Check-In Successful!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Check-In Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCheckout({bool auto = false}) async {
    if (currentRecordId == null) return;
    
    setState(() => _isLoading = true);
    try {
      Position position = await Geolocator.getCurrentPosition();
      final user = await DatabaseHelper.instance.getUser();
      String empId = user != null ? (user['emp_id'] ?? 'Unknown') : 'Unknown';
      String now = DateTime.now().toIso8601String();

      // Update SQLite
      await DatabaseHelper.instance.checkOutTravel(now, currentRecordId!);

      // Publish to MQTT with "action": "check-out"
      MqttHandler().publishTravelAttendance(
        action: "check-out",
        lat: position.latitude,
        lng: position.longitude,
        employeeId: empId,
      );

      setState(() {
        isTravelCheckedIn = false;
        currentRecordId = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(auto ? 'Auto Check-Out Triggered (Returned to Office zone)' : 'Manual Check-Out Successful!'),
            backgroundColor: auto ? Colors.orange : Colors.blue,
          ),
        );
      }
    } catch (e) {
      debugPrint("Check-Out Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Travel Attendance'),
        backgroundColor: Colors.blueAccent,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Distance Info
              Text(
                "Distance from Office: ${(currentDistance / 1000).toStringAsFixed(2)} km",
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              
              // 4. Travel Attendance UI
              if (_isLoading)
                const CircularProgressIndicator()
              else
                _buildActionButton(),

              if (isTravelCheckedIn)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Text(
                    "Auto check-out will trigger upon returning within 10km of the office.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    if (!isTravelCheckedIn && !isBeyond10km) {
      return ElevatedButton(
        onPressed: null, // Disabled
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        ),
        child: const Text("Check-In Disabled (Within 10km)", style: TextStyle(color: Colors.white)),
      );
    }

    if (!isTravelCheckedIn && isBeyond10km) {
      return ElevatedButton(
        onPressed: _handleCheckIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20),
        ),
        child: const Text("Travel Check-In", style: TextStyle(fontSize: 18, color: Colors.white)),
      );
    }

    // isTravelCheckedIn == true
    return ElevatedButton(
      onPressed: () => _handleCheckout(auto: false),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20),
      ),
      child: const Text("Manual Check-Out", style: TextStyle(fontSize: 18, color: Colors.white)),
    );
  }
}
