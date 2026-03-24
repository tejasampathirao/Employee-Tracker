import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';

class HolidayCalendarScreen extends StatefulWidget {
  static const String id = 'holiday_calendar_screen';
  const HolidayCalendarScreen({super.key});

  @override
  State<HolidayCalendarScreen> createState() => _HolidayCalendarScreenState();
}

class _HolidayCalendarScreenState extends State<HolidayCalendarScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Map<String, dynamic>>> _holidays = {};
  List<Map<String, dynamic>> _allHolidays = [];
  bool _isAdmin = false;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _checkRole();
    _loadHolidays();
  }

  Future<void> _checkRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role');
    setState(() => _isAdmin = role == 'Admin');
  }

  Future<void> _loadHolidays() async {
    final holidays = await _db.getHolidaysForYear(_selectedYear);
    final Map<DateTime, List<Map<String, dynamic>>> mapped = {};
    for (final h in holidays) {
      final date = DateTime.parse(h['date'] as String);
      final key = DateTime(date.year, date.month, date.day);
      mapped.putIfAbsent(key, () => []).add(h);
    }
    setState(() {
      _holidays = mapped;
      _allHolidays = holidays;
    });
  }

  List<Map<String, dynamic>> _getHolidaysForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _holidays[key] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Company Holidays'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          // Year selector
          PopupMenuButton<int>(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Select Year',
            onSelected: (year) {
              setState(() {
                _selectedYear = year;
                _focusedDay = DateTime(year, _focusedDay.month, 1);
              });
              _loadHolidays();
            },
            itemBuilder: (_) => [2025, 2026, 2027, 2028]
                .map(
                  (y) => PopupMenuItem(
                    value: y,
                    child: Text(
                      '$y',
                      style: TextStyle(
                        fontWeight: y == _selectedYear ? FontWeight.bold : null,
                        color: y == _selectedYear ? Colors.deepOrange : null,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showAddHolidayDialog(),
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add Holiday'),
            )
          : null,
      body: Column(
        children: [
          // Calendar
          TableCalendar(
            firstDay: DateTime(_selectedYear, 1, 1),
            lastDay: DateTime(_selectedYear, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: _getHolidaysForDay,
            calendarFormat: CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: 'Month'},
            startingDayOfWeek: StartingDayOfWeek.monday,
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() => _focusedDay = focusedDay);
            },
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              selectedDecoration: const BoxDecoration(
                color: Colors.deepOrange,
                shape: BoxShape.circle,
              ),
              markerDecoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              markerSize: 6,
              markersMaxCount: 1,
              weekendTextStyle: const TextStyle(color: Colors.red),
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                final holidays = _getHolidaysForDay(day);
                if (holidays.isNotEmpty) {
                  return Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.red, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${day.day}',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }
                return null;
              },
            ),
          ),
          const Divider(height: 1),
          // Holiday list
          Expanded(
            child: _allHolidays.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.beach_access,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No holidays for $_selectedYear',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _allHolidays.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final h = _allHolidays[index];
                      final date = DateTime.parse(h['date'] as String);
                      final dayName = DateFormat('EEEE').format(date);
                      final dateStr = DateFormat('dd MMM yyyy').format(date);
                      final isPast = date.isBefore(
                        DateTime.now().subtract(const Duration(days: 1)),
                      );
                      final isRecurring = h['is_recurring'] == 1;

                      return ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isPast
                                ? Colors.grey.shade100
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                DateFormat('dd').format(date),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isPast ? Colors.grey : Colors.red,
                                ),
                              ),
                              Text(
                                DateFormat('MMM').format(date),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isPast
                                      ? Colors.grey
                                      : Colors.red.shade300,
                                ),
                              ),
                            ],
                          ),
                        ),
                        title: Text(
                          h['name'] as String,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isPast ? Colors.grey : null,
                            decoration: isPast
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          '$dayName  •  $dateStr',
                          style: TextStyle(
                            fontSize: 12,
                            color: isPast ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                        trailing: _isAdmin
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isRecurring)
                                    Tooltip(
                                      message: 'Yearly recurring',
                                      child: Icon(
                                        Icons.repeat,
                                        size: 16,
                                        color: Colors.deepOrange.shade300,
                                      ),
                                    ),
                                  if (!isRecurring)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      onPressed: () => _confirmDelete(
                                        h['id'] as int,
                                        h['name'] as String,
                                      ),
                                    ),
                                ],
                              )
                            : isRecurring
                            ? Icon(
                                Icons.repeat,
                                size: 16,
                                color: Colors.deepOrange.shade300,
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddHolidayDialog() async {
    DateTime? pickedDate;
    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Holiday'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Date picker
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime(_selectedYear, 1, 1),
                      firstDate: DateTime(2025),
                      lastDate: DateTime(2030, 12, 31),
                    );
                    if (date != null) {
                      setDialogState(() => pickedDate = date);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      prefixIcon: Icon(Icons.calendar_today),
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      pickedDate != null
                          ? DateFormat('dd MMM yyyy').format(pickedDate!)
                          : 'Select date',
                      style: TextStyle(
                        color: pickedDate != null ? null : Colors.grey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Holiday Name',
                    prefixIcon: Icon(Icons.celebration),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter name' : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (pickedDate == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Please select a date')),
                  );
                  return;
                }
                if (!formKey.currentState!.validate()) return;

                final dateStr = DateFormat('yyyy-MM-dd').format(pickedDate!);
                await _db.addHoliday(dateStr, nameController.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                _loadHolidays();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Holiday added successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Holiday'),
        content: Text('Remove "$name" from the holiday list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _db.deleteHoliday(id);
      _loadHolidays();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Holiday removed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
