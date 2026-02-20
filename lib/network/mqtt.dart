import 'dart:async';
import 'dart:math';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

// Connection states for easy identification
enum MqttCurrentConnectionState {
  IDLE,
  CONNECTING,
  CONNECTED,
  DISCONNECTED,
  ERROR_WHEN_CONNECTING,
}

enum MqttSubscriptionState { IDLE, SUBSCRIBED }

class MQTTClientWrapper {
  // Singleton Pattern
  static final MQTTClientWrapper _instance = MQTTClientWrapper._internal();
  factory MQTTClientWrapper() => _instance;
  MQTTClientWrapper._internal() {
    _initializeClient();
  }

  late MqttServerClient client;
  MqttCurrentConnectionState connectionState = MqttCurrentConnectionState.IDLE;
  MqttSubscriptionState subscriptionState = MqttSubscriptionState.IDLE;
  String? errorMessage;

  // Stream for incoming messages
  final _messageStreamController = StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get messageStream => _messageStreamController.stream;

  // Store messages for each topic
  final Map<String, String> topicMessages = {};
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _subscription;

  void _initializeClient() {
    final clientId = 'employee_tracker_${Random().nextInt(100000)}';
    client = MqttServerClient.withPort('13.203.2.58', clientId, 1883);

    client.keepAlivePeriod = 20;
    client.onDisconnected = _onDisconnected;
    client.onConnected = _onConnected;
    client.onSubscribed = _onSubscribed;
    client.logging(on: false);
  }

  Future<void> connectClient() async {
    if (connectionState == MqttCurrentConnectionState.CONNECTED) return;

    try {
      connectionState = MqttCurrentConnectionState.CONNECTING;
      errorMessage = null;
      await client.connect();
    } on Exception catch (e) {
      connectionState = MqttCurrentConnectionState.ERROR_WHEN_CONNECTING;
      
      errorMessage = 'Exception: $e';
      client.disconnect();
      return;
    }

    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      connectionState = MqttCurrentConnectionState.CONNECTED;
      _setupMessageListener();
    } else {
      connectionState = MqttCurrentConnectionState.ERROR_WHEN_CONNECTING;
      client.disconnect();
    }
  }

  void _setupMessageListener() {
    _subscription?.cancel();
    _subscription = client.updates!.listen((List<MqttReceivedMessage<MqttMessage>>? messages) {
      if (messages == null || messages.isEmpty) return;

      for (final message in messages) {
        final recMess = message.payload as MqttPublishMessage;
        final content = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        
        topicMessages[message.topic] = content;
        _messageStreamController.add({message.topic: content});
      }
    });
  }

  void subscribeToTopic(String topic) {
    if (connectionState != MqttCurrentConnectionState.CONNECTED) return;
    client.subscribe(topic, MqttQos.atMostOnce);
  }

  void subscribeToTopics(List<String> topics) {
    for (final topic in topics) {
      subscribeToTopic(topic);
    }
  }

  String? getMessageForTopic(String topic) {
    return topicMessages[topic];
  }

  void publishMessage(String message, {required String topic}) {
    if (connectionState != MqttCurrentConnectionState.CONNECTED) return;
    
    final MqttClientPayloadBuilder builder = MqttClientPayloadBuilder();
    builder.addString(message);

    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void disconnect() {
    client.disconnect();
    _onDisconnected();
  }

  void _onSubscribed(String topic) {
    subscriptionState = MqttSubscriptionState.SUBSCRIBED;
  }

  void _onDisconnected() {
    connectionState = MqttCurrentConnectionState.DISCONNECTED;
    subscriptionState = MqttSubscriptionState.IDLE;
  }

  void _onConnected() {
    connectionState = MqttCurrentConnectionState.CONNECTED;
  }

  void dispose() {
    _subscription?.cancel();
    _messageStreamController.close();
  }
}
