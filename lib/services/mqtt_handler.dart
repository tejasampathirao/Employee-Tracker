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
  final String travelAttendanceTopic = 'employee/tracker/travel_attendance';

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
  void publishAttendance({
    required String status,
    required double lat,
    required double lng,
    required String employeeId,
  }) {
    final Map<String, dynamic> payload = {
      "type": "attendance",
      "status": status,
      "employee_id": employeeId,
      "timestamp": DateTime.now().toIso8601String(),
      "location": {"lat": lat, "lng": lng}
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Attendance]: Sending Payload: $jsonString');
    publish(attendanceTopic, jsonString);
  }

  /// Function 3: Publishes live location updates
  void publishLocationUpdate({
    required double lat,
    required double lng,
    required String employeeId,
  }) {
    final Map<String, dynamic> payload = {
      "type": "location_update",
      "lat": lat,
      "lng": lng,
      "employee_id": employeeId,
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

  /// Function 9: Publishes travel attendance data
  void publishTravelAttendance({
    required String action,
    required double lat,
    required double lng,
    required String employeeId,
  }) {
    final Map<String, dynamic> payload = {
      "type": "travel_attendance",
      "action": action,
      "lat": lat,
      "lng": lng,
      "employee_id": employeeId,
      "timestamp": DateTime.now().toIso8601String(),
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Travel Attendance]: Sending Payload: $jsonString');
    publish(travelAttendanceTopic, jsonString);
  }

  /// Function 10: Publishes a combined expense request
  void publishExpenseReport({
    required String employeeId,
    required Map<String, dynamic> expenses,
  }) {
    final Map<String, dynamic> payload = {
      "type": "expense_request",
      "employee_id": employeeId,
      "status": "Pending",
      "timestamp": DateTime.now().toIso8601String(),
      ...expenses
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Expense Request]: Sending Payload: $jsonString');
    publish(expensesTopic, jsonString, retain: true);
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
      // Removed redundant _setupMessageListener() call here as it's triggered in _onConnected()
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
        final topic = message.topic;
        
        topicMessages[topic] = content;

        try {
          final payload = jsonDecode(content);
          final String type = payload['type'] ?? '';

          AppLogger.log('MQTT Master Router: Received $type from $topic');

          switch (type) {
            case 'status_update':
              await DatabaseHelper.instance.updateRequestStatus(
                payload['category'] ?? '',
                payload['id']?.toString() ?? '',
                payload['status'] ?? 'Pending'
              );
              AppLogger.log('MQTT Sync: Status update saved for ${payload['category']} ${payload['id']}');
              break;

            case 'leave_request':
              await DatabaseHelper.instance.insertLeaveRequest(payload);
              AppLogger.log('MQTT Sync: Leave request saved.');
              break;

            case 'attendance':
              await DatabaseHelper.instance.insertAttendance(payload);
              AppLogger.log('MQTT Sync: Office attendance saved.');
              break;

            case 'travel_attendance':
              await DatabaseHelper.instance.insertTravelAttendance(payload);
              AppLogger.log('MQTT Sync: Travel attendance saved.');
              break;

            case 'expense_report':
            case 'expense_request':
              // Handle combined report/request by splitting it into individual records for DatabaseHelper
              final categories = ['food', 'fuel', 'travel', 'material'];
              for (var cat in categories) {
                if (payload['${cat}_amount'] != null && (payload['${cat}_amount'] as num) > 0) {
                  await DatabaseHelper.instance.insertExpenseRecord({
                    'type': cat[0].toUpperCase() + cat.substring(1),
                    'employee_id': payload['employee_id'],
                    'amount': payload['${cat}_amount'],
                    'description': payload['${cat}_desc'] ?? '',
                    'timestamp': payload['timestamp']
                  });
                }
              }
              AppLogger.log('MQTT Sync: Combined $type split and saved.');
              break;

            case 'expense_claim':
            case 'travel_expense':
            case 'additional_expense':
            case 'material_expense':
              await DatabaseHelper.instance.insertExpenseRecord(payload);
              AppLogger.log('MQTT Sync: $type saved.');
              break;

            case 'location_update':
            case 'live_location':
              await DatabaseHelper.instance.insertLocationRecord(payload);
              AppLogger.log('MQTT Sync: Location update saved.');
              break;

            default:
              AppLogger.log('MQTT Router: Unknown payload type received: $type');
          }
        } catch (e) {
          AppLogger.log('MQTT Router Error: Failed to parse or save payload: $e');
        }
      }
    });
  }

  String? getMessageForTopic(String topic) {
    return topicMessages[topic];
  }

  void publish(String topic, String message, {bool retain = false}) {
    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!, retain: retain);
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

  void _onConnected() async {
    AppLogger.log('MQTT: Connected Successfully');
    subscribe('employee/tracker/#');
    
    // Subscribe to employee specific status topic
    final user = await DatabaseHelper.instance.getUser();
    if (user != null && user['emp_id'] != null) {
      final String empId = user['emp_id'];
      subscribe('employee/tracker/status/$empId');
      AppLogger.log('MQTT: Subscribed to employee status topic: employee/tracker/status/$empId');
    }

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

