import 'package:flutter/material.dart'; // THIS LINE FIXES THE "UNDEFINED WIDGET" ERRORS
import 'dart:async';
import '../network/mqtt.dart';
import '../components/home_widgets.dart';
import '../components/attendance_history_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.mqttClient});
  static const String id = 'home';
  final MQTTClientWrapper mqttClient;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  late StreamSubscription<Map<String, String>> _mqttSubscription;

  @override
  void initState() {
    super.initState();
    // Listen to MQTT messages to update UI in real-time
    _mqttSubscription = widget.mqttClient.messageStream.listen((data) {
      if (mounted) {
        String topic = data.keys.first;
        String message = data.values.first;

        // Visual Feedback for Closed-Loop Test
        if (topic == 'hr/leaves') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('MQTT RECEIVED: $message'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (topic == '/expenses/updates') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.blue,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        setState(() {}); // Refresh dashboard on any message
      }
    });
  }

  @override
  void dispose() {
    _mqttSubscription.cancel();
    super.dispose();
  }

  void updateState() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
          });
        } else {
          // Show exit confirmation or just pop
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Exit App?'),
              content: const Text('Do you want to exit Employee Tracker?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
              ],
            ),
          );
          if (shouldPop ?? false) {
            if (context.mounted) Navigator.pop(context);
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              homeListView(context, widget.mqttClient, () => setState(() {})),
              servicesView(context, widget.mqttClient, () => setState(() {})),
              const AttendanceHistoryView(),
              profileView(context, widget.mqttClient, () => setState(() {})),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (int index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xff21b409),
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.grid_view_outlined), activeIcon: Icon(Icons.grid_view), label: 'Services'),
            BottomNavigationBarItem(icon: Icon(Icons.history_outlined), activeIcon: Icon(Icons.history), label: 'History'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

