import 'dart:async';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/db_helper.dart';

class OTResult {
  final int payableMinutes; // Step 2: minutes within shift window
  final int dailyOTMinutes; // Step 3: minutes past 17:00 after grace
  final int weeklyOTMinutes; // Step 4: minutes beyond 40h weekly total
  final int doubleTimeMinutes; // Step 5: minutes beyond 12h or on 7th day
  final String
  otTier; // "REGULAR" | "DAILY_OT" | "WEEKLY_OT" | "DOUBLE_TIME" | "BELOW_THRESHOLD"
  final String payRateLabel; // Step 6: human-readable rate string
  final String dailyOTFormatted; // e.g. "45m OT", "1h 30m OT", "0h OT"
  final String weeklyOTFormatted; // same format
  final String doubleTimeFormatted;

  const OTResult({
    required this.payableMinutes,
    required this.dailyOTMinutes,
    required this.weeklyOTMinutes,
    required this.doubleTimeMinutes,
    required this.otTier,
    required this.payRateLabel,
    required this.dailyOTFormatted,
    required this.weeklyOTFormatted,
    required this.doubleTimeFormatted,
  });

  static OTResult zero() => const OTResult(
    payableMinutes: 0,
    dailyOTMinutes: 0,
    weeklyOTMinutes: 0,
    doubleTimeMinutes: 0,
    otTier: "REGULAR",
    payRateLabel: "1.0× Regular",
    dailyOTFormatted: "0h OT",
    weeklyOTFormatted: "0h OT",
    doubleTimeFormatted: "0h OT",
  );
}

class OvertimeCalculatorService {
  static const int fullDayMinutes =
      480; // 8 hours = payable threshold for full day
  static const int halfDayMinutes =
      240; // 4 hours = payable threshold for half day
  static const int gracePeriodMins = 25; // minutes after 17:00 before OT starts
  static const int dailyOTStartMins =
      480; // minutes worked beyond which daily OT begins
  static const int weeklyOTStartMins = 2400; // 40 hours in a workweek
  static const int doubleTimeMinutes = 720; // 12 hours in a single day

  Future<OTResult> calculateDailyOT(
    String? checkInStr,
    String? checkOutStr,
    List<Map<String, dynamic>> allEmployeeRecords,
  ) async {
    // Step 1: Time Capture
    if (checkInStr == null || checkOutStr == null) return OTResult.zero();

    DateTime checkIn;
    DateTime checkOut;
    try {
      checkIn = DateTime.parse(checkInStr);
      checkOut = DateTime.parse(checkOutStr);
    } catch (e) {
      return OTResult.zero();
    }

    // Load dynamic shift times
    final shiftFromTime = await DatabaseHelper.instance.getShiftFromTime();
    final shiftToTime = await DatabaseHelper.instance.getShiftToTime();
    final fromParts = shiftFromTime.split(':');
    final toParts = shiftToTime.split(':');
    final shiftStartHour = int.parse(fromParts[0]);
    final shiftStartMinute = int.parse(fromParts[1]);
    final shiftEndHour = int.parse(toParts[0]);
    final shiftEndMinute = int.parse(toParts[1]);

    // Step 2: Shift Definition and Payable Hours
    final shiftStart = DateTime(
      checkIn.year,
      checkIn.month,
      checkIn.day,
      shiftStartHour,
      shiftStartMinute,
    );
    final shiftEnd = DateTime(
      checkIn.year,
      checkIn.month,
      checkIn.day,
      shiftEndHour,
      shiftEndMinute,
    );

    final effectiveStart = checkIn.isBefore(shiftStart) ? shiftStart : checkIn;
    final effectiveEnd = checkOut.isAfter(shiftEnd) ? shiftEnd : checkOut;

    int payableMinutes = effectiveEnd.difference(effectiveStart).inMinutes;
    if (payableMinutes < 0) payableMinutes = 0;

    if (payableMinutes < halfDayMinutes) {
      return OTResult(
        payableMinutes: payableMinutes,
        dailyOTMinutes: 0,
        weeklyOTMinutes: 0,
        doubleTimeMinutes: 0,
        otTier: "BELOW_THRESHOLD",
        payRateLabel: "Below Payable Threshold",
        dailyOTFormatted: "0h OT",
        weeklyOTFormatted: "0h OT",
        doubleTimeFormatted: "0h OT",
      );
    }

    String otTier = "REGULAR";
    int dailyOTMinutes = 0;
    int doubleTimeMinutesVal = 0;

    // Step 3: Daily OT with dynamic OT buffer
    final prefs = await SharedPreferences.getInstance();
    final otBufferMins = prefs.getInt('ot_buffer') ?? gracePeriodMins;

    if (payableMinutes >= fullDayMinutes) {
      final minutesAfterShiftEnd = checkOut.isAfter(shiftEnd)
          ? checkOut.difference(shiftEnd).inMinutes
          : 0;

      if (minutesAfterShiftEnd > otBufferMins) {
        dailyOTMinutes = minutesAfterShiftEnd - otBufferMins;
        otTier = "DAILY_OT";
      }
    }

    // Step 5: Double Time
    // Condition A: Over 12h in a day
    final totalWorkedMinutes = checkOut.difference(checkIn).inMinutes;
    if (totalWorkedMinutes > doubleTimeMinutes) {
      doubleTimeMinutesVal = totalWorkedMinutes - doubleTimeMinutes;
      otTier = "DOUBLE_TIME";
    }

    // Condition B: 7th consecutive workday
    if (_isSeventhConsecutiveDay(checkIn, allEmployeeRecords)) {
      // Entire OT component (from Step 3) becomes Double Time
      doubleTimeMinutesVal = dailyOTMinutes > 0
          ? dailyOTMinutes
          : totalWorkedMinutes;
      otTier = "DOUBLE_TIME";
    }

    // Step 6: Pay Rate Label
    String payRateLabel = "1.0× Regular";
    switch (otTier) {
      case "DAILY_OT":
        payRateLabel = "1.5× OT Rate";
        break;
      case "DOUBLE_TIME":
        payRateLabel = "2.0× Double Time";
        break;
      case "BELOW_THRESHOLD":
        payRateLabel = "Below Payable Threshold";
        break;
    }

    return OTResult(
      payableMinutes: payableMinutes,
      dailyOTMinutes: dailyOTMinutes,
      weeklyOTMinutes: 0, // Weekly OT is calculated separately for summaries
      doubleTimeMinutes: doubleTimeMinutesVal,
      otTier: otTier,
      payRateLabel: payRateLabel,
      dailyOTFormatted: formatOT(dailyOTMinutes),
      weeklyOTFormatted: "0h OT",
      doubleTimeFormatted: formatOT(doubleTimeMinutesVal),
    );
  }

  bool _isSeventhConsecutiveDay(
    DateTime currentDate,
    List<Map<String, dynamic>> allRecords,
  ) {
    if (allRecords.isEmpty) return false;

    // Filter records with checkout and sort by date
    final sortedDates = allRecords
        .where((r) => r['checkOutTime'] != null)
        .map((r) => DateTime.parse(r['date'] as String))
        .toSet()
        .toList();
    sortedDates.sort();

    if (sortedDates.isEmpty) return false;

    int streak = 0;
    DateTime? lastDate;

    for (final date in sortedDates) {
      if (lastDate == null || date.difference(lastDate).inDays == 1) {
        streak++;
      } else if (date.difference(lastDate).inDays > 1) {
        streak = 1;
      }

      if (date.year == currentDate.year &&
          date.month == currentDate.month &&
          date.day == currentDate.day) {
        return streak >= 7;
      }

      lastDate = date;
    }

    return false;
  }

  Future<int> calculateWeeklyOTMinutes(
    List<Map<String, dynamic>> weekRecords,
  ) async {
    int totalPayableMinutes = 0;
    for (final record in weekRecords) {
      final res = await calculateDailyOT(
        record['checkInTime'],
        record['checkOutTime'],
        [],
      );
      totalPayableMinutes += res.payableMinutes;
    }
    return totalPayableMinutes > weeklyOTStartMins
        ? totalPayableMinutes - weeklyOTStartMins
        : 0;
  }

  Future<int> calculateMonthlyOTMinutes(
    List<Map<String, dynamic>> monthRecords,
  ) async {
    // Sum of all weekly OT in that month
    // Split into weeks (Mon-Sun)
    int totalMonthlyWeeklyOT = 0;

    // Group by ISO week
    final Map<int, List<Map<String, dynamic>>> weeklyGroups = {};
    for (final record in monthRecords) {
      try {
        final date = DateTime.parse(record['date'] as String);
        final weekNum = _getWeekNumber(date);
        weeklyGroups.putIfAbsent(weekNum, () => []).add(record);
      } catch (_) {}
    }

    for (final weekList in weeklyGroups.values) {
      totalMonthlyWeeklyOT += await calculateWeeklyOTMinutes(weekList);
    }

    return totalMonthlyWeeklyOT;
  }

  int _getWeekNumber(DateTime date) {
    // ISO-8601 week number logic
    int dayOfYear = int.parse(DateFormat("D").format(date));
    int woy = ((dayOfYear - date.weekday + 10) / 7).floor();
    if (woy < 1) {
      woy = _getWeekNumber(DateTime(date.year - 1, 12, 31));
    } else if (woy > 52) {
      if (DateTime(date.year, 12, 31).weekday < 4) {
        woy = 1;
      }
    }
    return woy;
  }

  String formatOT(int minutes) {
    if (minutes <= 0) return "0h OT";
    final h = minutes ~/ 60;
    final m = minutes % 60;

    String res = "";
    if (h > 0) res += "${h}h ";
    if (m > 0) res += "${m}m ";
    return "${res.trim()} OT";
  }

  Future<Map<String, dynamic>> getWeeklyOTSummary(
    List<Map<String, dynamic>> records,
  ) async {
    // Get records for the CURRENT week
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final currentWeekRecords = records.where((r) {
      try {
        final d = DateTime.parse(r['date']);
        return d.isAfter(weekStart.subtract(const Duration(seconds: 1)));
      } catch (_) {
        return false;
      }
    }).toList();

    int totalPayable = 0;
    int doubleTime = 0;
    for (final r in currentWeekRecords) {
      final res = await calculateDailyOT(
        r['checkInTime'],
        r['checkOutTime'],
        records,
      );
      totalPayable += res.payableMinutes;
      doubleTime += res.doubleTimeMinutes;
    }

    final weeklyOT = await calculateWeeklyOTMinutes(currentWeekRecords);

    return {
      'totalPayableMinutes': totalPayable,
      'weeklyOTMinutes': weeklyOT,
      'weeklyOTFormatted': formatOT(weeklyOT),
      'doubleTimeMinutes': doubleTime,
      'otByDay':
          <
            String,
            OTResult
          >{}, // Not explicitly required for summary UI but part of contract
    };
  }

  Future<Map<String, dynamic>> getMonthlyOTSummary(
    List<Map<String, dynamic>> records,
  ) async {
    final now = DateTime.now();
    final currentMonthRecords = records.where((r) {
      try {
        final d = DateTime.parse(r['date']);
        return d.year == now.year && d.month == now.month;
      } catch (_) {
        return false;
      }
    }).toList();

    int totalPayable = 0;
    int doubleTime = 0;
    for (final r in currentMonthRecords) {
      final res = await calculateDailyOT(
        r['checkInTime'],
        r['checkOutTime'],
        records,
      );
      totalPayable += res.payableMinutes;
      doubleTime += res.doubleTimeMinutes;
    }

    final monthlyWeeklyOT = await calculateMonthlyOTMinutes(
      currentMonthRecords,
    );

    return {
      'totalPayableMinutes': totalPayable,
      'weeklyOTMinutes': monthlyWeeklyOT,
      'weeklyOTFormatted': formatOT(monthlyWeeklyOT),
      'doubleTimeMinutes': doubleTime,
      'otByDay': <String, OTResult>{},
    };
  }
}
