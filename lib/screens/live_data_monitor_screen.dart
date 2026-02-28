import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import '../services/mqtt_handler.dart';

class LiveDataMonitorScreen extends StatefulWidget {
  const LiveDataMonitorScreen({super.key});
  static const String id = 'live_monitor';

  @override
  State<LiveDataMonitorScreen> createState() => _LiveDataMonitorScreenState();
}

class _LiveDataMonitorScreenState extends State<LiveDataMonitorScreen> {
  final List<Map<String, dynamic>> _messageHistory = [];
  StreamSubscription? _subscription;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() {
    // Access the existing MQTT stream
    _subscription = MqttHandler().updates?.listen((List<MqttReceivedMessage<MqttMessage>>? messages) {
      if (messages == null || messages.isEmpty) return;

      for (final message in messages) {
        final recMess = message.payload as MqttPublishMessage;
        final String content = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

        try {
          final dynamic decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic>) {
            setState(() {
              // Add to history at index 0 so newest shows first
              _messageHistory.insert(0, {
                'topic': message.topic,
                'data': decoded,
                'arrival_time': DateTime.now().toLocal().toString().split('.')[0],
              });
            });
          }
        } catch (e) {
          debugPrint("Live Monitor Error: Failed to decode MQTT payload - $e");
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Live MQTT Monitor', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => setState(() => _messageHistory.clear()),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear History',
          ),
        ],
      ),
      body: _messageHistory.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messageHistory.length,
              itemBuilder: (context, index) {
                final item = _messageHistory[index];
                return _buildMessageCard(item);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rss_feed, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Waiting for live MQTT payloads...',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(Map<String, dynamic> item) {
    final data = item['data'] as Map<String, dynamic>;
    // Try to determine a friendly title from the "type" field in your JSON
    final String type = (data['type'] ?? 'Unknown Payload').toString().replaceAll('_', ' ').toUpperCase();
    final String topic = item['topic'];
    final String time = item['arrival_time'];

    // Format JSON neatly with indentation
    const encoder = JsonEncoder.withIndent('  ');
    final String prettyJson = encoder.convert(data);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(
          _getIconForType(data['type'] ?? ''),
          color: _getColorForType(data['type'] ?? ''),
        ),
        title: Text(type, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text('Topic: $topic • $time', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                prettyJson,
                style: const TextStyle(
                  color: Colors.lightGreenAccent,
                  fontFamily: 'Courier',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForType(String type) {
    if (type.contains('attendance')) return Icons.location_on;
    if (type.contains('expense')) return Icons.receipt_long;
    if (type.contains('work')) return Icons.assignment;
    if (type.contains('location')) return Icons.gps_fixed;
    return Icons.message;
  }

  Color _getColorForType(String type) {
    if (type.contains('attendance')) return Colors.green;
    if (type.contains('expense')) return Colors.orange;
    if (type.contains('work')) return Colors.indigo;
    if (type.contains('location')) return Colors.blue;
    return Colors.grey;
  }
}
