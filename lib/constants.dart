import 'package:flutter/material.dart';

const kTextFieldDecoration = InputDecoration(
  hintText: 'Enter a value',
  contentPadding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 20.0),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(16.0)),
  ),
  enabledBorder: OutlineInputBorder(
    borderSide: BorderSide(color: Colors.green, width: 1.0),
    borderRadius: BorderRadius.all(Radius.circular(16.0)),
  ),
  focusedBorder: OutlineInputBorder(
    borderSide: BorderSide(color: Colors.lightBlueAccent, width: 2.0),
    borderRadius: BorderRadius.all(Radius.circular(16.0)),
  ),
);

const kTextStyleForm = TextStyle(
  fontWeight: FontWeight.bold,
  color: Colors.lightBlue,
);

// Geofencing Constants
const double kOfficeLatitude = 13.0022; // Example:Office
const double kOfficeLongitude = 77.4965;
const double kGeofenceRadiusMeter = 100.0; // 100 meters radius
