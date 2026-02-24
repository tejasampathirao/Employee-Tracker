import 'package:flutter/material.dart'; // THIS LINE FIXES THE ERRORS
import '../network/mqtt.dart';
import 'dart:async';

class ReusableCard extends StatefulWidget {
  const ReusableCard({
    super.key,
    required this.colour,
    required this.text,
    required this.mqttClient,
    required this.topics,
  });

  final Color colour;
  final String text;
  final MQTTClientWrapper mqttClient;
  final List<String> topics;

  @override
  State<ReusableCard> createState() => _ReusableCardState();
}

class _ReusableCardState extends State<ReusableCard> {
  Timer? _timer;
  Map<String, String> _messages = {};

  @override
  void initState() {
    super.initState();
    // Poll for messages every 500ms for real-time "No-HR" automation
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {
          _messages = {};
          for (final topic in widget.topics) {
            final message = widget.mqttClient.getMessageForTopic(topic);
            if (message != null) {
              _messages[topic] = message;
            }
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Helper function to pick an icon to match Zoho Screenshot (85)
  IconData _getIconForText(String text) {
    if (text.contains('Attendance')) return Icons.people_alt;
    if (text.contains('Leave')) return Icons.calendar_today;
    if (text.contains('Payroll')) return Icons.account_balance_wallet;
    return Icons.analytics;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12.0),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: widget.colour,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.text,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800]),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                if (_messages.isEmpty)
                  const Text(
                    '0',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  )
                else
                  ..._messages.entries.map((entry) {
                    return Text(
                      entry.value,
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                      overflow: TextOverflow.ellipsis,
                    );
                  }),
              ],
            ),
          ),
          Icon(
            _getIconForText(widget.text),
            size: 40,
            color: Colors.black12,
          ),
        ],
      ),
    );
  }
}