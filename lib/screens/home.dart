import 'package:flutter/material.dart'; // THIS LINE FIXES THE "UNDEFINED WIDGET" ERRORS
import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import '../services/mqtt_handler.dart';
import '../components/home_widgets.dart';
import '../components/attendance_history_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  static const String id = 'home';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _mqttSubscription;
  final MqttHandler mqttClient = MqttHandler();

  @override
  void initState() {
    super.initState();
    _connectAndListen();
  }

  void _connectAndListen() async {
    await mqttClient.connect();
    
    // Listen to MQTT messages to update UI in real-time
    _mqttSubscription = mqttClient.updates?.listen((messages) {
      if (mounted && messages.isNotEmpty) {
        for (final message in messages) {
          final String topic = message.topic;
          final MqttPublishMessage recMess = message.payload as MqttPublishMessage;
          final String content = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

          // Visual Feedback for Closed-Loop Test
          if (topic == 'hr/leaves') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('MQTT RECEIVED: $content'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else if (topic == '/expenses/updates' || topic == 'employee/tracker') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('MQTT Update ($topic): $content'),
                backgroundColor: Colors.blue,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        setState(() {}); // Refresh dashboard on any message
      }
    });
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
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
              homeListView(context, mqttClient, () => setState(() {})),
              servicesView(context, mqttClient, () => setState(() {})),
              const AttendanceHistoryView(),
              profileView(context, mqttClient, () => setState(() {})),
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

