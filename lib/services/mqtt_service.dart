import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  // Singleton Pattern
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;

  late MqttServerClient client;
  final String broker = '13.203.2.58';
  final int port = 1883;
  
  // Topics
  final String attendanceTopic = 'employee/tracker';
  final String leaveTopic = 'employee/tracker/hr/leaves';
  final String locationTopic = 'employee/tracker/attendance/location';
  final String expensesTopic = 'employee/tracker/additional expenses/material expenses';
  final String workTopic = 'employee/tracker/work updates';


  MqttService._internal() {
    _initializeClient();
  }

  void _initializeClient() {
    final String clientId = 'flutter_app_${Random().nextInt(100000)}';
    client = MqttServerClient.withPort(broker, clientId, port);

    client.keepAlivePeriod = 20;
    client.onDisconnected = _onDisconnected;
    client.onConnected = _onConnected;
    client.onSubscribed = _onSubscribed;
    client.logging(on: false);

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMess;
  }

  final Map<String, String> topicMessages = {};
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _subscription;

  Future<bool> connect() async {
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      return true;
    }
    
    try {
      print('MQTT: Connecting to $broker:$port...');
      await client.connect();
      _setupMessageListener();
      return true;
    } catch (e) {
      print('MQTT: Connection failed - $e');
      return false;
    }
  }

  void _setupMessageListener() {
    _subscription?.cancel();
    _subscription = client.updates?.listen((List<MqttReceivedMessage<MqttMessage>>? messages) {
      if (messages == null || messages.isEmpty) return;

      for (final message in messages) {
        final recMess = message.payload as MqttPublishMessage;
        final content = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        topicMessages[message.topic] = content;
      }
    });
  }

  String? getMessageForTopic(String topic) {
    return topicMessages[topic];
  }

  void publish(String topic, String message) {
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      print('MQTT: Published to $topic: $message');
    } else {
      print('MQTT: Cannot publish to $topic, client not connected (Current State: ${client.connectionStatus?.state})');
      // Attempt auto-reconnect if disconnected
      connect();
    }
  }

  void subscribe(String topic) {
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      client.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  Stream<List<MqttReceivedMessage<MqttMessage>>>? get updates => client.updates;

  void _onConnected() {
    print('MQTT: Connected Successfully');
    subscribe(attendanceTopic);
    subscribe(leaveTopic);
    _setupMessageListener();
  }

  void _onDisconnected() {
    print('MQTT: Disconnected');
  }

  void _onSubscribed(String topic) {
    print('MQTT: Subscribed to $topic');
  }

  void disconnect() {
    _subscription?.cancel();
    client.disconnect();
  }
}
