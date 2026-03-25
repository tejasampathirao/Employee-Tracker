import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import '../utils/app_logger.dart';

class MqttHandler {
  // Singleton Pattern
  static final MqttHandler _instance = MqttHandler._internal();
  factory MqttHandler() => _instance;

  late MqttServerClient client;
  final String broker =
      '10.0.2.2'; // Android Emulator alias for host machine's localhost
  final int port = 1883;
  final _uuid = const Uuid();

  // Standardized Topics
  final String attendanceTopic = 'employee/tracker';
  final String leaveTopic = 'employee/tracker/hr/leaves';
  final String locationTopic = 'employee/tracker/location';
  final String expensesTopic = 'employee/tracker/expenses';
  final String travelAttendanceTopic = 'employee/tracker/travel_attendance';

  // Admin Service Topics
  final String adminAttendanceTopic = 'admin/attendance';
  final String adminApprovalsTopic = 'admin/approvals';
  final String adminEmployeeDetailsTopic = 'admin/employee/details';

  // Expense Category Topics
  final String expenseFoodTopic = 'employee/tracker/expenses/food';
  final String expenseFuelTopic = 'employee/tracker/expenses/fuel';
  final String expenseTravelTopic = 'employee/tracker/expenses/travel';
  final String expenseMaterialTopic = 'employee/tracker/expenses/material';

  // Registration Topics
  final String registerCheckTopic = 'employee/register/check';
  final String registerResponseTopic = 'employee/register/response';

  MqttHandler._internal() {
    _initializeClient();
  }

  void _initializeClient() {
    final String clientId = 'flutter_app_${Random().nextInt(100000)}';
    client = MqttServerClient.withPort(broker, clientId, port);
    client.connectTimeoutPeriod =
        3000; // Stop trying to connect after 3 seconds

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
      "request_id": _uuid.v4(),
      "leave_type": leaveType,
      "from_date": fromDate,
      "to_date": toDate,
      "reason": reason,
      "employee_id": employeeId,
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
      "request_id": _uuid.v4(),
      "status": status,
      "employee_id": employeeId,
      "timestamp": DateTime.now().toIso8601String(),
      "location": {"lat": lat, "lng": lng},
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
      "request_id": _uuid.v4(),
      "lat": lat,
      "lng": lng,
      "employee_id": employeeId,
      "timestamp": DateTime.now().toIso8601String(),
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Location]: Sending Payload: $jsonString');
    publish(locationTopic, jsonString);
  }

  /// Function 4: Publishes an expense claim
  void publishExpense(
    String category,
    String description,
    double amount,
    String employeeId,
  ) {
    final Map<String, dynamic> payload = {
      "type": "expense_claim",
      "request_id": _uuid.v4(),
      "category": category,
      "description": description,
      "amount": amount,
      "timestamp": DateTime.now().toIso8601String(),
      "employee_id": employeeId,
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
      "request_id": _uuid.v4(),
      "amount": amount,
      "description": description,
      "visit_type": visitType,
      "timestamp": DateTime.now().toIso8601String(),
      "employee_id": employeeId,
      "route_info": {
        "source": {"lat": srcLat, "lng": srcLng},
        "destination": {"lat": destLat, "lng": destLng},
        "distance_km": distanceKm,
      },
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
      "request_id": _uuid.v4(),
      "description": description,
      "amount": amount,
      "employee_id": employeeId,
      "timestamp": DateTime.now().toIso8601String(),
      "bill_image_path": billImagePath,
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log(
      'MQTT DEBUG [Additional Expense]: Sending Payload: $jsonString',
    );
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
      "request_id": _uuid.v4(),
      "description": description,
      "work_type": workType,
      "employee_id": employeeId,
      "timestamp": DateTime.now().toIso8601String(),
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Work Log]: Sending Payload: $jsonString');
    publish(
      attendanceTopic,
      jsonString,
    ); // Using attendance topic for work logs
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
      "request_id": _uuid.v4(),
      "employee_id": employeeId,
      "from_date": fromDate,
      "to_date": toDate,
      "total_worked": totalWorked,
      "timestamp": DateTime.now().toIso8601String(),
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Work Report]: Sending Payload: $jsonString');
    publish(
      attendanceTopic,
      jsonString,
    ); // Using attendance topic for report events
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
      "request_id": _uuid.v4(),
      "action": action,
      "lat": lat,
      "lng": lng,
      "employee_id": employeeId,
      "timestamp": DateTime.now().toIso8601String(),
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log(
      'MQTT DEBUG [Travel Attendance]: Sending Payload: $jsonString',
    );
    publish(travelAttendanceTopic, jsonString);
  }

  /// Function 10: Publishes a combined expense request
  void publishExpenseReport({
    required String employeeId,
    required Map<String, dynamic> expenses,
  }) {
    final Map<String, dynamic> payload = {
      "type": "expense_request",
      "request_id": _uuid.v4(),
      "employee_id": employeeId,
      "status": "Pending",
      "timestamp": DateTime.now().toIso8601String(),
      ...expenses,
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Expense Request]: Sending Payload: $jsonString');
    publish(expensesTopic, jsonString, retain: true);
  }

  // --- Admin Service Publish Functions ---

  /// Publishes admin attendance data when an employee checks in
  void publishAdminAttendance({
    required String employeeId,
    required String checkInTime,
    required String date,
  }) {
    final Map<String, dynamic> payload = {
      "type": "admin_attendance",
      "request_id": _uuid.v4(),
      "employee_id": employeeId,
      "check_in_time": checkInTime,
      "date": date,
      "timestamp": DateTime.now().toIso8601String(),
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log(
      'MQTT DEBUG [Admin Attendance]: Sending Payload: $jsonString',
    );
    publish(adminAttendanceTopic, jsonString);
  }

  /// Publishes admin approval data when admin approves a request
  void publishAdminApproval({
    required String employeeId,
    required String approvalType,
    required String requestId,
    required String approvedBy,
    required String status,
    Map<String, dynamic>? additionalData,
  }) {
    final Map<String, dynamic> payload = {
      "type": "admin_approval",
      "request_id": requestId,
      "employee_id": employeeId,
      "approval_type": approvalType,
      "approved_by": approvedBy,
      "status": status,
      "timestamp": DateTime.now().toIso8601String(),
      if (additionalData != null) ...additionalData,
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Admin Approval]: Sending Payload: $jsonString');
    publish(adminApprovalsTopic, jsonString);
  }

  /// Publishes employee details when admin saves/updates employee data
  void publishEmployeeDetails({
    required String empId,
    required String name,
    required String role,
    String? panNo,
    String? aadharNo,
    String? bankAccNo,
    String? ifscCode,
    String? fatherName,
    String? motherName,
    double? salary,
  }) {
    final Map<String, dynamic> payload = {
      "type": "employee_details",
      "request_id": _uuid.v4(),
      "emp_id": empId,
      "name": name,
      "role": role,
      "pan_no": panNo ?? '',
      "aadhar_no": aadharNo ?? '',
      "bank_acc_no": bankAccNo ?? '',
      "ifsc_code": ifscCode ?? '',
      "father_name": fatherName ?? '',
      "mother_name": motherName ?? '',
      "salary": salary ?? 0.0,
      "timestamp": DateTime.now().toIso8601String(),
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log(
      'MQTT DEBUG [Employee Details]: Sending Payload: $jsonString',
    );
    publish(adminEmployeeDetailsTopic, jsonString);
  }

  void publishFoodExpense({
    required String employeeId,
    required double amount,
    required String description,
  }) {
    final Map<String, dynamic> payload = {
      "type": "food_expense",
      "request_id": _uuid.v4(),
      "employee_id": employeeId,
      "amount": amount,
      "description": description,
      "timestamp": DateTime.now().toIso8601String(),
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Food Expense]: Sending Payload: $jsonString');
    publish(expenseFoodTopic, jsonString);
  }

  /// Publishes fuel expense data
  void publishFuelExpense({
    required String employeeId,
    required double amount,
    required String description,
  }) {
    final Map<String, dynamic> payload = {
      "type": "fuel_expense",
      "request_id": _uuid.v4(),
      "employee_id": employeeId,
      "amount": amount,
      "description": description,
      "timestamp": DateTime.now().toIso8601String(),
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Fuel Expense]: Sending Payload: $jsonString');
    publish(expenseFuelTopic, jsonString);
  }

  /// Publishes travel expense data
  void publishTravelCategoryExpense({
    required String employeeId,
    required double amount,
    required String description,
    double? distanceKm,
  }) {
    final Map<String, dynamic> payload = {
      "type": "travel_category_expense",
      "request_id": _uuid.v4(),
      "employee_id": employeeId,
      "amount": amount,
      "description": description,
      "distance_km": distanceKm,
      "timestamp": DateTime.now().toIso8601String(),
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log(
      'MQTT DEBUG [Travel Category Expense]: Sending Payload: $jsonString',
    );
    publish(expenseTravelTopic, jsonString);
  }

  /// Publishes material expense data
  void publishMaterialExpense({
    required String employeeId,
    required double amount,
    required String description,
  }) {
    final Map<String, dynamic> payload = {
      "type": "material_expense",
      "request_id": _uuid.v4(),
      "employee_id": employeeId,
      "amount": amount,
      "description": description,
      "timestamp": DateTime.now().toIso8601String(),
    };

    final String jsonString = jsonEncode(payload);
    AppLogger.log(
      'MQTT DEBUG [Material Expense]: Sending Payload: $jsonString',
    );
    publish(expenseMaterialTopic, jsonString);
  }

  /// Sends emp_id to server for registration validation.
  /// Returns a Future that completes with the server response.
  /// Response map contains: {status: "allowed"/"denied"/"error", reason: "...", emp_id: "..."}
  Future<Map<String, dynamic>> checkRegistration({
    required String empId,
    required String name,
  }) async {
    final String requestId = _uuid.v4();
    final Map<String, dynamic> payload = {
      "type": "register_check",
      "request_id": requestId,
      "emp_id": empId,
      "name": name,
      "timestamp": DateTime.now().toIso8601String(),
    };

    // Ensure connected
    bool isConnected = await connect();
    if (!isConnected) {
      return {
        "status": "error",
        "reason": "Cannot connect to server. Please check your network.",
      };
    }

    // Subscribe to response topic if not already
    subscribe(registerResponseTopic);

    // Set up a completer to wait for the response
    final completer = Completer<Map<String, dynamic>>();

    // Listen for the response matching our request_id
    StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? responseSub;
    responseSub = client.updates?.listen((
      List<MqttReceivedMessage<MqttMessage>>? messages,
    ) {
      if (messages == null) return;
      for (final message in messages) {
        if (message.topic == registerResponseTopic) {
          final recMess = message.payload as MqttPublishMessage;
          final content = MqttPublishPayload.bytesToStringAsString(
            recMess.payload.message,
          );
          try {
            final response = jsonDecode(content) as Map<String, dynamic>;
            if (response['request_id'] == requestId && !completer.isCompleted) {
              completer.complete(response);
              responseSub?.cancel();
            }
          } catch (_) {}
        }
      }
    });

    // Publish the check request
    final String jsonString = jsonEncode(payload);
    AppLogger.log('MQTT DEBUG [Register Check]: Sending Payload: $jsonString');
    publish(registerCheckTopic, jsonString);

    // Wait for response with a timeout
    try {
      final result = await completer.future.timeout(
        const Duration(seconds: 10),
      );
      return result;
    } on TimeoutException {
      responseSub?.cancel();
      return {
        "status": "error",
        "reason": "Server did not respond in time. Please try again.",
      };
    }
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
      await client.connect().timeout(const Duration(seconds: 5));
      // Removed redundant _setupMessageListener() call here as it's triggered in _onConnected()
      return true;
    } catch (e) {
      AppLogger.log('MQTT: Connection failed - $e');
      return false;
    }
  }

  void _setupMessageListener() {
    _subscription?.cancel();
    _subscription = client.updates?.listen((
      List<MqttReceivedMessage<MqttMessage>>? messages,
    ) async {
      if (messages == null || messages.isEmpty) return;

      for (final message in messages) {
        final recMess = message.payload as MqttPublishMessage;
        final content = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );
        final topic = message.topic;

        topicMessages[topic] = content;

        try {
          final payload = jsonDecode(content);
          final String type = payload['type'] ?? '';
          final String requestId = payload['request_id'] ?? '';

          AppLogger.log('MQTT Master Router: Received $type from $topic');

          switch (type) {
            case 'status_update':
              await DatabaseHelper.instance.updateRequestStatus(
                payload['category'] ?? '',
                payload['id']?.toString() ?? '',
                payload['status'] ?? 'Pending',
              );
              AppLogger.log(
                'MQTT Sync: Status update saved for ${payload['category']} ${payload['id']}',
              );
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
                if (payload['${cat}_amount'] != null &&
                    (payload['${cat}_amount'] as num) > 0) {
                  await DatabaseHelper.instance.insertExpenseRecord({
                    'request_id': requestId.isNotEmpty
                        ? '${requestId}_$cat'
                        : null,
                    'type': cat[0].toUpperCase() + cat.substring(1),
                    'employee_id': payload['employee_id'],
                    'amount': payload['${cat}_amount'],
                    'description': payload['${cat}_desc'] ?? '',
                    'timestamp': payload['timestamp'],
                    'latitude': payload['latitude'] ?? payload['lat'],
                    'longitude': payload['longitude'] ?? payload['lng'],
                    'distance': payload['distance'] ?? payload['distance_km'],
                  });
                }
              }
              AppLogger.log('MQTT Sync: Combined $type split and saved.');
              break;

            case 'expense_claim':
            case 'additional_expense':
            case 'material_expense':
              await DatabaseHelper.instance.insertExpenseRecord(payload);
              AppLogger.log('MQTT Sync: $type saved.');
              break;

            case 'travel_expense':
              // Extract nested coordinates so the SQLite DB can read them
              if (payload['route_info'] != null) {
                payload['latitude'] =
                    payload['latitude'] ??
                    payload['route_info']['source']?['lat'];
                payload['longitude'] =
                    payload['longitude'] ??
                    payload['route_info']['source']?['lng'];
                payload['distance'] =
                    payload['distance'] ?? payload['route_info']['distance_km'];
              }
              AppLogger.log(
                'MQTT DEBUG: Attempting to insert travel expense...',
              );
              try {
                await DatabaseHelper.instance.insertExpenseRecord(payload);
              } catch (dbError) {
                AppLogger.log(
                  'MQTT ERROR: Database rejected expense: $dbError',
                );
              }
              break;

            case 'location_update':
            case 'live_location':
              await DatabaseHelper.instance.insertLocationRecord(payload);
              AppLogger.log('MQTT Sync: Location update saved.');
              break;

            default:
              AppLogger.log(
                'MQTT Router: Unknown payload type received: $type',
              );
          }
        } catch (e) {
          AppLogger.log(
            'MQTT Router Error: Failed to parse or save payload: $e',
          );
        }
      }
    });
  }

  String? getMessageForTopic(String topic) {
    return topicMessages[topic];
  }

  void publish(String topic, String message, {bool retain = false}) async {
    // Changed to false
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      AppLogger.log(
        'MQTT: Client not connected. Attempting to connect before publishing...',
      );
      bool connected = await connect();
      if (!connected) {
        AppLogger.log('MQTT Error: Reconnect failed. Message dropped.');
        return;
      }
    }

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      client.publishMessage(
        topic,
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: retain,
      );
      AppLogger.log('MQTT: Successfully published to $topic');
    } catch (e) {
      AppLogger.log('MQTT Error: Failed to publish - $e');
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
    subscribe('admin/#');
    subscribe('employee/tracker/expenses/food');
    subscribe('employee/tracker/expenses/fuel');
    subscribe('employee/tracker/expenses/travel');
    subscribe('employee/tracker/expenses/material');

    // Subscribe to employee specific status topic
    final user = await DatabaseHelper.instance.getUser();
    if (user != null && user['emp_id'] != null) {
      final String empId = user['emp_id'];
      subscribe('employee/tracker/status/$empId');
      AppLogger.log(
        'MQTT: Subscribed to employee status topic: employee/tracker/status/$empId',
      );
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
