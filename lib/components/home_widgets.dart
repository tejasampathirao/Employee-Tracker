import 'package:flutter/material.dart';
import 'dart:async';
import '../network/mqtt.dart';
import '../screens/login_screen.dart';
import 'attendance_card.dart';
import 'attendance_history_view.dart';
import '../database/db_helper.dart';
import '../network/report_service.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../screens/profile_edit_screen.dart';

Widget getDrawerWidget(
  int index,
  BuildContext context,
  MQTTClientWrapper mqttClient,
  Function updateState,
) {
  switch (index) {
    case 0:
      return homeListView(context, mqttClient, updateState);
    case 1:
      return servicesView(context, mqttClient, updateState);
    case 2:
      return const AttendanceHistoryView();
    case 3:
      return profileView(context, mqttClient, updateState);
    default:
      return const Center(child: Text('Page under construction'));
  }
}


// --- HOME VIEW (DASHBOARD) ---
class RealTimeTimeLogs extends StatefulWidget {
  const RealTimeTimeLogs({super.key});

  @override
  State<RealTimeTimeLogs> createState() => _RealTimeTimeLogsState();
}

class _RealTimeTimeLogsState extends State<RealTimeTimeLogs> {
  Timer? _ticker;
  Map<String, double> _stats = {'today': 0.0, 'week': 0.0, 'month': 0.0};
  DateTime? _checkInTime;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_checkInTime != null) {
        if (mounted) setState(() {});
      }
    });
  }

  Future<void> _loadInitialData() async {
    final stats = await DatabaseHelper.instance.getTimeLogStats();
    final lastAttendance = await DatabaseHelper.instance.getLastAttendance();
    if (mounted) {
      setState(() {
        _stats = stats;
        if (lastAttendance != null && lastAttendance['checkOutTime'] == null) {
          _checkInTime = DateTime.parse(lastAttendance['checkInTime']);
        }
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _format(double hours) {
    int h = hours.floor();
    int m = ((hours - h) * 60).round();
    return '$h h $m m';
  }

  @override
  Widget build(BuildContext context) {
    double activeHours = 0.0;
    if (_checkInTime != null) {
      activeHours = DateTime.now().difference(_checkInTime!).inSeconds / 3600.0;
    }
    double totalToday = _stats['today']! + activeHours;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Today', _format(totalToday), Icons.today),
          _buildStatItem('This Week', _format(_stats['week']! + activeHours), Icons.calendar_view_week),
          _buildStatItem('This Month', _format(_stats['month']! + activeHours), Icons.calendar_month),
        ],
      ),
    );
  }
}

// Update homeListView to use RealTimeTimeLogs
Widget homeListView(
  BuildContext context,
  MQTTClientWrapper mqttClient,
  Function updateState,
) {
  return SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    padding: const EdgeInsets.all(16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(mqttClient, updateState),
        const SizedBox(height: 20),
        _buildGreetingSection(),
        const SizedBox(height: 20),
        AttendanceCard(
          mqttClient: mqttClient, 
          onActionComplete: () => updateState(),
        ),
        const SizedBox(height: 24),
        _buildDashboardSectionTitle('Additional Expenses', Icons.fact_check_outlined),
        const SizedBox(height: 12),
        _buildExpenseApprovalsList(),
        const SizedBox(height: 24),
        _buildDashboardSectionTitle('Time Logs', Icons.timer_outlined),
        const SizedBox(height: 12),
        const RealTimeTimeLogs(),
      ],
    ),
  );
}

Widget _buildHeader(MQTTClientWrapper mqttClient, Function updateState) {
  final List<String> hrTopics = ['/attendance/live', '/leave/updates', '/payroll/status', '/expenses/updates', 'hr/leaves'];
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const Text(
        'Dashboard',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      _buildSystemControls(mqttClient, hrTopics, updateState),
    ],
  );
}


Widget _buildGreetingSection() {
  return FutureBuilder<Map<String, dynamic>?>(
    future: DatabaseHelper.instance.getUser(),
    builder: (context, snapshot) {
      final String name = snapshot.data?['name'] ?? 'Srinivas Reddy';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hi, $name 👋',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.blueGrey[800]),
          ),
          const Text(
            'Here\'s what\'s happening today.',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      );
    }
  );
}

Widget _buildDashboardSectionTitle(String title, IconData icon) {
  return Row(
    children: [
      Icon(icon, size: 20, color: Colors.blue),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const Spacer(),
      TextButton(onPressed: () {}, child: const Text('View All')),
    ],
  );
}

Widget _buildAnimatedCard(Widget child) {
  return TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0, end: 1),
    duration: const Duration(milliseconds: 500),
    builder: (context, value, child) {
      return Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: child,
        ),
      );
    },
    child: child,
  );
}

Widget _buildExpenseApprovalsList() {
  return FutureBuilder<List<Map<String, dynamic>>>(
    future: DatabaseHelper.instance.getExpenses(),
    builder: (context, snapshot) {
      if (!snapshot.hasData || snapshot.data!.isEmpty) {
        return _buildEmptyState('No pending expense approvals');
      }
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: snapshot.data!.length > 3 ? 3 : snapshot.data!.length,
        itemBuilder: (context, index) {
          final item = snapshot.data![index];
          return _buildAnimatedCard(
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: Colors.blue[50], child: const Icon(Icons.description, color: Colors.blue)),
                title: Text(item['category'] ?? 'Expense', style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text('${item['description']} • ₹${item['amount']}'),
                trailing: Text(item['status'], style: TextStyle(color: item['status'] == 'Pending' ? Colors.orange : Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _buildStatItem(String label, String value, IconData icon) {
  return Column(
    children: [
      Icon(icon, color: Colors.blue, size: 24),
      const SizedBox(height: 8),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    ],
  );
}


Widget _buildEmptyState(String message) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    ),
  );
}

// --- SERVICES VIEW ---
Widget servicesView(BuildContext context, MQTTClientWrapper mqttClient, Function updateState) {
  final List<Map<String, dynamic>> services = [
    {'title': 'Attendance', 'icon': Icons.location_on, 'color': Colors.green, 'desc': 'Check-in and history'},
    {'title': 'Work', 'icon': Icons.work, 'color': Colors.indigo, 'desc': 'Log daily work and meetings'},
    {'title': 'Time Tracker', 'icon': Icons.timer, 'color': Colors.orange, 'desc': 'Log your work hours'},
    {'title': 'Travel Expenses', 'icon': Icons.directions_car, 'color': Colors.teal, 'desc': 'Onsite and Office logs'},
    {'title': 'Additional Expenses', 'icon': Icons.done_all, 'color': Colors.purple, 'desc': 'Manage your requests'},
  ];

  return Scaffold(
    backgroundColor: Colors.transparent,
    floatingActionButton: FloatingActionButton(
      onPressed: () => _showChatbotService(context),
      backgroundColor: Colors.blue,
      child: const Icon(Icons.chat_bubble, color: Colors.white),
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('HR Services', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.9,
            ),
            itemCount: services.length,
            itemBuilder: (context, index) {
              final service = services[index];
              return _buildServiceCard(context, service, mqttClient, updateState);
            },
          ),
        ],
      ),
    ),
  );
}

// --- Detailed Service Views ---

void _showAttendanceService(BuildContext context, MQTTClientWrapper mqttClient, Function updateState) {
  final now = DateTime.now();
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final firstDayOffset = DateTime(now.year, now.month, 1).weekday % 7;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios, size: 20),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Attendance: ${DateFormat('MMMM yyyy').format(now)}', 
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showLeaveService(context, mqttClient, updateState),
                icon: const Icon(Icons.calendar_today, size: 16),
                label: const Text('Manage Leaves'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[50],
                  foregroundColor: Colors.blue,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: DatabaseHelper.instance.getAllAttendance(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();

              final currentMonthStr = DateFormat('yyyy-MM').format(now);
              final monthlyData = snapshot.data!.where((e) => e['date'].startsWith(currentMonthStr)).toList();
              final presentDates = monthlyData.map((e) => e['date']).toSet();
              
              int daysPresent = presentDates.length;
              int totalDaysPassed = now.day;
              int daysAbsent = totalDaysPassed - daysPresent;
              if (daysAbsent < 0) daysAbsent = 0;

              double presentPct = totalDaysPassed > 0 ? (daysPresent / totalDaysPassed) * 100 : 0;
              double absentPct = 100 - presentPct;

              return Column(
                children: [
                  SizedBox(
                    height: 180,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 4,
                        centerSpaceRadius: 40,
                        sections: [
                          PieChartSectionData(
                            color: Colors.green,
                            value: presentPct,
                            title: '${presentPct.toStringAsFixed(0)}%',
                            radius: 50,
                            titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          PieChartSectionData(
                            color: Colors.orange,
                            value: absentPct,
                            title: '${absentPct.toStringAsFixed(0)}%',
                            radius: 50,
                            titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _LegendItem(color: Colors.green, label: 'Present: $daysPresent'),
                      const SizedBox(width: 20),
                      _LegendItem(color: Colors.orange, label: 'Absent: $daysAbsent'),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              );
            },
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper.instance.getAllAttendance(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final presentDates = snapshot.data!
                    .map((e) => DateFormat('yyyy-MM-dd').format(DateTime.parse(e['date'])))
                    .toSet();

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: daysInMonth + firstDayOffset,
                  itemBuilder: (context, index) {
                    if (index < firstDayOffset) return const SizedBox();
                    
                    final day = index - firstDayOffset + 1;
                    final date = DateTime(now.year, now.month, day);
                    final dateStr = DateFormat('yyyy-MM-dd').format(date);
                    final isPresent = presentDates.contains(dateStr);
                    final isToday = date.day == now.day && date.month == now.month && date.year == now.year;

                    return Container(
                      decoration: BoxDecoration(
                        color: isPresent ? Colors.green : Colors.orange.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
                        border: isToday ? Border.all(color: Colors.blue, width: 2) : null,
                      ),
                      child: Center(
                        child: Text(
                          '$day',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _LegendItem(color: Colors.green, label: 'Present'),
                _LegendItem(color: Colors.orange, label: 'Absent'),
                _LegendItem(color: Colors.blue, label: 'Today', isBorder: true),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool isBorder;
  const _LegendItem({required this.color, required this.label, this.isBorder = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 16, height: 16,
          decoration: BoxDecoration(
            color: isBorder ? Colors.transparent : color,
            borderRadius: BorderRadius.circular(4),
            border: isBorder ? Border.all(color: color, width: 2) : null,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

void _showTravelExpenseService(BuildContext context, MQTTClientWrapper mqttClient) {
  final TextEditingController descController = TextEditingController();
  final TextEditingController amtController = TextEditingController();
  String selectedCategory = 'Onsite';

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios, size: 20),
                    ),
                    const Text('Travel Expenses', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amtController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ ', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                const Text('Location Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(value: 'Onsite', label: Text('Onsite'), icon: Icon(Icons.location_on_outlined)),
                      ButtonSegment<String>(value: 'Office', label: Text('Office'), icon: Icon(Icons.business_outlined)),
                    ],
                    selected: {selectedCategory},
                    onSelectionChanged: (Set<String> newSelection) {
                      setModalState(() => selectedCategory = newSelection.first);
                    },
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (descController.text.isEmpty || amtController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
                        return;
                      }

                      final expense = {
                        'type': 'Travel',
                        'category': selectedCategory,
                        'description': descController.text,
                        'amount': double.tryParse(amtController.text) ?? 0.0,
                        'date': DateTime.now().toIso8601String(),
                        'status': 'Pending'
                      };

                      await DatabaseHelper.instance.insertExpense(expense);
                      mqttClient.publishMessage('Travel Expense: $selectedCategory - ${descController.text}', topic: '/expenses/updates');

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Travel Expense Logged Successfully!')));
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Submit Travel Log', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void _showWorkService(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.5,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios, size: 20),
                ),
                const Text('Daily Work Log', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 20),
            const TextField(
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'Enter your work details...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Client Meet',
                hintText: 'Meeting details...',
                border: OutlineInputBorder(),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Work details submitted successfully!'))
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Submit', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _showTimeTrackerService(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios, size: 20),
          ),
          const SizedBox(height: 10),
          const Text('Time Tracker', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          const RealTimeTimeLogs(),
          const SizedBox(height: 20),

          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper.instance.getTimeLogs(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                if (snapshot.data!.isEmpty) return _buildEmptyState('No non-office time logs yet.');
                
                return ListView.builder(
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final log = snapshot.data![index];
                    return _buildAnimatedCard(
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(log['task'] ?? 'Task'),
                          subtitle: Text('${log['description']} • ${log['date']}'),
                          trailing: Text('${log['hours']}h', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

void _showExpenseApprovalsService(BuildContext context, MQTTClientWrapper mqttClient) {
  final Map<String, TextEditingController> controllers = {};
  
  void saveExpense(String type, String category, String description, String amount) async {
    double? amt = double.tryParse(amount);
    if (amt == null || amt <= 0) return;

    final Map<String, dynamic> expense = {
      'type': type,
      'category': category,
      'description': description,
      'amount': amt,
      'date': DateTime.now().toIso8601String(),
      'status': 'Pending'
    };

    int id = await DatabaseHelper.instance.insertExpense(expense);
    
    // Append to Report File on device
    expense['id'] = id;
    await ReportService.appendExpenseToReport(expense);
    
    // Publish via MQTT
    mqttClient.publishMessage(
      'New Expense: $category - ₹$amt for $description', 
      topic: '/expenses/updates'
    );
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios, size: 20),
                  ),
                  const Text('Additional Expenses', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 48), // Spacer to balance the arrow
                ],
              ),
              const SizedBox(height: 24),
              _buildExpenseSection(context, 'Material Expenses', 'Material', controllers, (cat, desc, amt) {
                saveExpense('Material', cat, desc, amt);
              }),
              const SizedBox(height: 24),
              _buildExpenseSection(context, 'Fuel Expenses', 'Fuel', controllers, (cat, desc, amt) {
                saveExpense('Fuel', cat, desc, amt);
              }),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All bills submitted successfully!')));
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _buildExpenseSection(
  BuildContext context, 
  String title, 
  String typeKey,
  Map<String, TextEditingController> controllers,
  Function(String category, String desc, String amount) onAdd,
  {List<String>? subTypes}
) {
  // Use unique keys for controllers
  final descKey = '${typeKey}_desc';
  final amtKey = '${typeKey}_amt';
  
  controllers.putIfAbsent(descKey, () => TextEditingController());
  controllers.putIfAbsent(amtKey, () => TextEditingController());
  
  if (subTypes != null) {
    for (var sub in subTypes) {
      controllers.putIfAbsent('${typeKey}_$sub', () => TextEditingController());
    }
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          TextButton.icon(
            onPressed: () {
              if (subTypes != null) {
                for (var sub in subTypes) {
                  final subAmt = controllers['${typeKey}_$sub']?.text ?? '';
                  if (subAmt.isNotEmpty) {
                    onAdd(sub, 'Auto-added $sub', subAmt);
                    controllers['${typeKey}_$sub']?.clear();
                  }
                }
              } else {
                onAdd(title, controllers[descKey]?.text ?? '', controllers[amtKey]?.text ?? '');
                controllers[descKey]?.clear();
                controllers[amtKey]?.clear();
              }
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title added to records')));
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (subTypes != null) ...[
        ...subTypes.map((sub) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: controllers['${typeKey}_$sub'],
            decoration: InputDecoration(
                          labelText: sub,
                          hintText: 'Enter $sub amount',
                          prefixText: '₹ ',
                          filled: true,
              
              fillColor: Colors.grey[50],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
            ),
            keyboardType: TextInputType.number,
          ),
        )),
      ] else ...[
        TextField(
          controller: controllers[descKey],
          decoration: InputDecoration(
            labelText: 'Description',
            hintText: 'Enter $title details',
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controllers[amtKey],
          decoration: InputDecoration(
            labelText: 'Amount',
            hintText: 'Enter amount',
            prefixText: '₹ ',
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[300]!)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey[200]!)),
          ),
          keyboardType: TextInputType.number,
        ),
      ],
    ],
  );
}

void _showChatbotService(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.8,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios, size: 20),
              ),
              const Expanded(
                child: Center(
                  child: Text('HR Helpdesk Bot', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const Divider(),
          Expanded(
            child: ListView(
              children: [
                _buildChatBubble('Hello! How can I help you with HR queries today?', false),
                _buildChatBubble('How many leaves do I have left?', true),
                _buildChatBubble('You have 12 Casual leaves and 15 Earned leaves remaining.', false),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Ask a question...',
                suffixIcon: Icon(Icons.send),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildChatBubble(String text, bool isUser) {
  return Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUser ? Colors.blue : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: isUser ? Colors.white : Colors.black)),
    ),
  );
}

Widget _buildServiceCard(BuildContext context, Map<String, dynamic> service, MQTTClientWrapper mqttClient, Function updateState) {
  return InkWell(
    onTap: () {
      switch (service['title']) {
        case 'Attendance':
          _showAttendanceService(context, mqttClient, updateState);
          break;
        case 'Time Tracker':
          _showTimeTrackerService(context);
          break;
        case 'Work':
          _showWorkService(context);
          break;
        case 'Travel Expenses':
          _showTravelExpenseService(context, mqttClient);
          break;
        case 'Additional Expenses':
          _showExpenseApprovalsService(context, mqttClient);
          break;
        default:
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${service['title']} service coming soon!')));
      }
    },
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: service['color'].withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(service['icon'], color: service['color'], size: 32),
          ),
          const SizedBox(height: 12),
          Text(service['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            service['desc'],
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}


void _showLeaveService(BuildContext context, MQTTClientWrapper mqttClient, Function updateState) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) => _leaveTrackerView(context, mqttClient, updateState),
    ),
  );
}

// --- SYSTEM CONTROLS ---
Widget _buildSystemControls(MQTTClientWrapper mqttClient, List<String> hrTopics, Function updateState) {
  return Row(
    children: [
      if (mqttClient.connectionState == MqttCurrentConnectionState.connecting)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      if (mqttClient.connectionState != MqttCurrentConnectionState.connected && mqttClient.connectionState != MqttCurrentConnectionState.connecting)
        IconButton(
          onPressed: () async {
            // Update UI to show loading state
            updateState(); 
            await mqttClient.connectClient();
            if (mqttClient.connectionState == MqttCurrentConnectionState.connected) {
              mqttClient.subscribeToTopics(hrTopics);
            }
            // Update UI with final result
            updateState();
          },
          icon: Icon(
            Icons.link, 
            color: mqttClient.connectionState == MqttCurrentConnectionState.errorWhenConnecting ? Colors.orange : const Color(0xff21b409)
          ),
        ),
      if (mqttClient.connectionState == MqttCurrentConnectionState.connected) ...[
        IconButton(
          onPressed: () {
            mqttClient.subscribeToTopics(hrTopics);
            updateState();
          },
          icon: const Icon(Icons.sync, color: Colors.blue),
        ),
        IconButton(
          onPressed: () {
            mqttClient.client.disconnect();
            updateState();
          },
          icon: const Icon(Icons.link_off, color: Colors.red),
        ),
      ]
    ],
  );
}


// --- PROFILE VIEW ---
Widget profileView(BuildContext context, MQTTClientWrapper mqttClient, Function onUpdate) {
  return FutureBuilder<Map<String, dynamic>?>(
    future: DatabaseHelper.instance.getUser(),
    builder: (context, snapshot) {
      final user = snapshot.data ?? {
        'name': 'Srinivas Reddy',
        'details': 'Chief Financial Officer'
      };
      
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
                const SizedBox(height: 16),
                Text(user['name'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                Text(user['details'], style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ListTile(
            leading: const Icon(Icons.edit_outlined, color: Colors.blue),
            title: const Text('Edit Profile'),
            subtitle: const Text('Update your name and job details'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final updated = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileEditScreen(
                    currentName: user['name'],
                    currentDetails: user['details'],
                  ),
                ),
              );
              if (updated == true) {
                onUpdate(); // Trigger refresh on Home Page
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showSettings(context),
          ),
          ListTile(
            leading: const Icon(Icons.power_settings_new, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () {
              mqttClient.client.disconnect();
              Navigator.pushNamedAndRemoveUntil(context, LoginScreen.id, (route) => false);
            },
          ),
        ],
      );
    },
  );
}

void _showSettings(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 15),
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios, size: 20),
              ),
              const Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                _buildSettingsSection('Account'),
                _buildSettingsTile(Icons.lock_outline, 'Password & Security', 'Change password, 2FA'),
                const Divider(),
                _buildSettingsSection('App Settings'),
                _buildGeofenceSettingTile(context),
                _buildOfficeLocationSettingTile(context),
                const Divider(),
                _buildSettingsSection('Support'),
                _buildSettingsTile(Icons.description_outlined, 'Terms & Policies', 'Usage terms, Privacy policy'),
                _buildSettingsTile(Icons.info_outline, 'About App', 'Version 1.0.0 (Latest)'),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {},
                  child: const Text('Deactivate Account', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildSettingsSection(String title) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
    ),
  );
}

Widget _buildSettingsTile(IconData icon, String title, String subtitle) {
  return ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: Colors.blueGrey, size: 20),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
    subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: () {},
  );
}

Widget _buildGeofenceSettingTile(BuildContext context) {
  return FutureBuilder<String?>(
    future: DatabaseHelper.instance.getSetting('geofence_radius'),
    builder: (context, snapshot) {
      String radius = snapshot.data ?? '100';
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.radar, color: Colors.blueGrey, size: 20),
        ),
        title: const Text('Tolerable Range (Geofence)', style: TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text('$radius meters', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => _showGeofenceDialog(context),
      );
    },
  );
}

Widget _buildOfficeLocationSettingTile(BuildContext context) {
  return FutureBuilder<List<String?>>(
    future: Future.wait([
      DatabaseHelper.instance.getSetting('office_latitude'),
      DatabaseHelper.instance.getSetting('office_longitude'),
    ]),
    builder: (context, snapshot) {
      String location = 'Not set (using default)';
      if (snapshot.hasData && snapshot.data![0] != null && snapshot.data![1] != null) {
        double lat = double.parse(snapshot.data![0]!);
        double lng = double.parse(snapshot.data![1]!);
        location = '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
      }
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.location_on, color: Colors.blueGrey, size: 20),
        ),
        title: const Text('Office Location', style: TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(location, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => _showOfficeLocationDialog(context),
      );
    },
  );
}

void _showOfficeLocationDialog(BuildContext context) {
  LatLng? pickedLocation;
  
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios, size: 20),
                    ),
                    const Text('Set Office Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    FutureBuilder<Position>(
                      future: Geolocator.getCurrentPosition(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                        
                        final initialPos = LatLng(snapshot.data!.latitude, snapshot.data!.longitude);
                        pickedLocation ??= initialPos;

                        return GoogleMap(
                          initialCameraPosition: CameraPosition(target: initialPos, zoom: 17),
                          myLocationEnabled: true,
                          myLocationButtonEnabled: true,
                          mapType: MapType.normal,
                          onCameraMove: (position) {
                            setModalState(() {
                              pickedLocation = position.target;
                            });
                          },
                        );
                      },
                    ),
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 30),
                        child: Icon(Icons.location_on, color: Colors.red, size: 40),
                      ),
                    ),
                    Positioned(
                      bottom: 20,
                      left: 20,
                      right: 20,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'Center the red marker on your office desk',
                                  style: TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500),
                                ),
                                if (pickedLocation != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${pickedLocation!.latitude.toStringAsFixed(6)}, ${pickedLocation!.longitude.toStringAsFixed(6)}',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                if (pickedLocation != null) {
                                  await DatabaseHelper.instance.updateSetting('office_latitude', pickedLocation!.latitude.toString());
                                  await DatabaseHelper.instance.updateSetting('office_longitude', pickedLocation!.longitude.toString());
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Office set to: ${pickedLocation!.latitude.toStringAsFixed(4)}, ${pickedLocation!.longitude.toStringAsFixed(4)}'))
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Confirm Office Location', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    ),
  );
}

void _showGeofenceDialog(BuildContext context) async {
  String? currentRadius = await DatabaseHelper.instance.getSetting('geofence_radius');
  final controller = TextEditingController(text: currentRadius ?? '100');
  
  if (!context.mounted) return;
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Set Geofence Radius'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Radius in meters',
          suffixText: 'm',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            await DatabaseHelper.instance.updateSetting('geofence_radius', controller.text);
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Radius updated!')));
            }
          }, 
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

// --- LEAVE TRACKER (Used by Services) ---
Widget _leaveTrackerView(BuildContext context, MQTTClientWrapper mqttClient, Function updateState) {
  return Padding(
    padding: const EdgeInsets.all(16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Leave Tracker', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: () => _showApplyLeaveForm(context, mqttClient),
              icon: const Icon(Icons.add),
              label: const Text('Apply'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _buildLeaveBalanceCard('Casual', 12, 0, Colors.blue)),
            const SizedBox(width: 12),
            Expanded(child: _buildLeaveBalanceCard('Sick', 12, 0, Colors.red)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildLeaveBalanceCard('Earned', 15, 2, Colors.green)),
            const SizedBox(width: 12),
            const Expanded(child: SizedBox()),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Pending Requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Expanded(child: _buildEmptyState('No pending leave requests')),
      ],
    ),
  );
}

Widget _buildLeaveBalanceCard(String type, int available, int booked, Color color) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: 0.1)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(type, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$available', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Text('Available', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ],
    ),
  );
}

void _showApplyLeaveForm(BuildContext context, MQTTClientWrapper mqttClient) {
  final TextEditingController fromDateController = TextEditingController();
  final TextEditingController toDateController = TextEditingController();
  final TextEditingController reasonController = TextEditingController();
  String selectedLeaveType = 'Casual Leave';
  
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios, size: 20),
                    ),
                    const Text('Apply Leave', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: selectedLeaveType,
                  decoration: const InputDecoration(labelText: 'Leave type', border: OutlineInputBorder()),
                  items: ['Casual Leave', 'Earned Leave', 'Sick Leave']
                      .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) selectedLeaveType = value;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: fromDateController,
                  decoration: const InputDecoration(labelText: 'From Date', suffixIcon: Icon(Icons.calendar_month), border: OutlineInputBorder()),
                  readOnly: true,
                  onTap: () async {
                    DateTime? pickedDate = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2030),
                    );
                    if (pickedDate != null) {
                      setModalState(() {
                        fromDateController.text = DateFormat('yyyy-MM-dd').format(pickedDate);
                      });
                    }
                  }, 
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: toDateController,
                  decoration: const InputDecoration(labelText: 'To Date', suffixIcon: Icon(Icons.calendar_month), border: OutlineInputBorder()),
                  readOnly: true,
                  onTap: () async {
                    DateTime? pickedDate = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2030),
                    );
                    if (pickedDate != null) {
                      setModalState(() {
                        toDateController.text = DateFormat('yyyy-MM-dd').format(pickedDate);
                      });
                    }
                  }, 
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (fromDateController.text.isEmpty || toDateController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select dates')));
                        return;
                      }

                      final Map<String, dynamic> leaveData = {
                        'leaveType': selectedLeaveType,
                        'fromDate': fromDateController.text,
                        'toDate': toDateController.text,
                        'reason': reasonController.text,
                        'status': 'Pending',
                        'appliedDate': DateTime.now().toIso8601String(),
                      };

                      int id = await DatabaseHelper.instance.insertLeave(leaveData);
                      
                      // Append to Report File
                      leaveData['id'] = id;
                      await ReportService.appendLeaveToReport(leaveData);

                      // CLOSED-LOOP TEST: Publish message to be received by Dashboard
                      mqttClient.publishMessage('Leave Request Saved: $selectedLeaveType', topic: 'hr/leaves');

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave Application Submitted Successfully!')));
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Submit Application', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

