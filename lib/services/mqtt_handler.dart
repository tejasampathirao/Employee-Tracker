import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../database/db_helper.dart';
import '../utils/app_logger.dart';

class MqttHandler {
  // Singleton Pattern
  static final MqttHandler _instance = MqttHandler._internal();
  factory MqttHandler() => _instance;

  late MqttServerClient client;
  final String broker = '13.203.2.58';
  final int port = 1883;
  
  // Standardized Topics
  final String attendanceTopic = 'employee/tracker';
  final String leaveTopic = 'employee/tracker/hr/leaves';
  final String locationTopic = 'employee/tracker/location';
  final String expensesTopic = 'employee/tracker/expenses';

  MqttHandler._internal() {
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

  // --- Standardized Publish Functions ---

  /// Function 1: Publishes a leave request with strict JSON formatting
  void publishLeaveRequest(
    String leaveType,
    String fromDate,
    String toDate,
    String reason,
    String employeeId,
  ) {
    final Map<String, dynamic> payload = {
      "type": "leave_request",
      "leave_type": leaveType,
      "from_date": fromDate,
      "to_date": toDate,
      "reason": reason,
      "employee_id": employeeId
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Leave]: Sending Payload: $jsonString');
    publish(leaveTopic, jsonString);
  }

  /// Function 2: Publishes attendance check-in/out data
  void publishAttendance(
    String status,
    double lat,
    double lng,
  ) {
    final Map<String, dynamic> payload = {
      "type": "attendance",
      "status": status,
      "timestamp": DateTime.now().toIso8601String(),
      "location": {"lat": lat, "lng": lng}
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Attendance]: Sending Payload: $jsonString');
    publish(attendanceTopic, jsonString);
  }

  /// Function 3: Publishes live location updates
  void publishLocationUpdate(
    double lat,
    double lng,
    double speed,
  ) {
    final Map<String, dynamic> payload = {
      "type": "live_location",
      "lat": lat, "lng": lng, "speed": speed,
      "timestamp": DateTime.now().toIso8601String()
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Location]: Sending Payload: $jsonString');
    publish(locationTopic, jsonString);
  }

  /// Function 4: Publishes an expense claim
  void publishExpense(String category, String description, double amount, String employeeId) {
    final Map<String, dynamic> payload = {
      "type": "expense_claim",
      "category": category,
      "description": description,
      "amount": amount,
      "timestamp": DateTime.now().toIso8601String(),
      "employee_id": employeeId
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Expense]: Sending Payload: $jsonString');
    publish(expensesTopic, jsonString);
  }

  /// Function 5: Publishes a travel expense with route information
  void publishTravelExpense({
    required double amount,
    required String description,
    required String visitType,
    required double srcLat,
    required double srcLng,
    required double destLat,
    required double destLng,
    required double distanceKm,
    required String employeeId,
  }) {
    final Map<String, dynamic> payload = {
      "type": "travel_expense",
      "amount": amount,
      "description": description,
      "visit_type": visitType,
      "timestamp": DateTime.now().toIso8601String(),
      "employee_id": employeeId,
      "route_info": {
        "source": {"lat": srcLat, "lng": srcLng},
        "destination": {"lat": destLat, "lng": destLng},
        "distance_km": distanceKm
      }
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Travel Expense]: Sending Payload: $jsonString');
    publish(expensesTopic, jsonString);
  }

  /// Function 6: Publishes an additional expense with optional bill image
  void publishAdditionalExpense({
    required String description,
    required double amount,
    required String employeeId,
    String? billImagePath,
  }) {
    final Map<String, dynamic> payload = {
      "type": "additional_expense",
      "description": description,
      "amount": amount,
      "employee_id": employeeId,
      "timestamp": DateTime.now().toIso8601String(),
      "bill_image_path": billImagePath
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Additional Expense]: Sending Payload: $jsonString');
    publish(expensesTopic, jsonString);
  }

  /// Function 7: Publishes a daily work log
  void publishDailyWorkLog({
    required String description,
    required String workType,
    required String employeeId,
  }) {
    final Map<String, dynamic> payload = {
      "type": "daily_work_log",
      "description": description,
      "work_type": workType,
      "employee_id": employeeId,
      "timestamp": DateTime.now().toIso8601String()
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Work Log]: Sending Payload: $jsonString');
    publish(attendanceTopic, jsonString); // Using attendance topic for work logs
  }

  /// Function 8: Publishes a work report generation event
  void publishWorkReport({
    required String employeeId,
    required String fromDate,
    required String toDate,
    required String totalWorked,
  }) {
    final Map<String, dynamic> payload = {
      "type": "work_report",
      "employee_id": employeeId,
      "from_date": fromDate,
      "to_date": toDate,
      "total_worked": totalWorked,
      "timestamp": DateTime.now().toIso8601String()
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Work Report]: Sending Payload: $jsonString');
    publish(attendanceTopic, jsonString); // Using attendance topic for report events
  }

  // --- Core MQTT Logic ---

  final Map<String, String> topicMessages = {};
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _subscription;

  Future<bool> connect() async {
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      return true;
    }
    
    try {
      AppLogger.log('MQTT: Connecting to $broker:$port...');
      await client.connect();
      _setupMessageListener();
      return true;
    } catch (e) {
      AppLogger.log('MQTT: Connection failed - $e');
      return false;
    }
  }

  void _setupMessageListener() {
    _subscription?.cancel();
    _subscription = client.updates?.listen((List<MqttReceivedMessage<MqttMessage>>? messages) async {
      if (messages == null || messages.isEmpty) return;

      for (final message in messages) {
        final recMess = message.payload as MqttPublishMessage;
        final content = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        
        topicMessages[message.topic] = content;

        // Handle Incoming Expenses
        if (message.topic == expensesTopic) {
          try {
            final data = jsonDecode(content);
            if (data['type'] == 'expense_claim') {
              // Standardize for local DB
              final expense = {
                'type': 'General', // Default type
                'category': data['category'],
                'description': data['description'],
                'amount': data['amount'],
                'date': data['timestamp'],
                'status': 'Approved' // Incoming claims from server are pre-approved or for syncing
              };
              await DatabaseHelper.instance.insertExpense(expense);
              AppLogger.log('MQTT: Sync - New Expense saved to DB');
            }
          } catch (e) {
            AppLogger.log('MQTT Error: Failed to parse expense sync data - $e');
          }
        }
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
    } else {
      AppLogger.log('MQTT Error: Cannot publish, client not connected');
      connect(); // Attempt auto-reconnect
    }
  }

  void subscribe(String topic) {
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      client.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  Stream<List<MqttReceivedMessage<MqttMessage>>>? get updates => client.updates;

  void _onConnected() {
    AppLogger.log('MQTT: Connected Successfully');
    subscribe(attendanceTopic);
    subscribe(leaveTopic);
    subscribe(locationTopic);
    subscribe(expensesTopic);
    _setupMessageListener();
  }

  void _onDisconnected() {
    AppLogger.log('MQTT: Disconnected');
  }

  void _onSubscribed(String topic) {
    AppLogger.log('MQTT: Subscribed to $topic');
  }

  void disconnect() {
    _subscription?.cancel();
    client.disconnect();
  }
}

