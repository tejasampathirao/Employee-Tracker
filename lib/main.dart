import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import './screens/home.dart';
import './screens/welcome_screen.dart';
import './screens/login_screen.dart';
import './screens/register_screen.dart';
import './screens/live_data_monitor_screen.dart';
import './screens/admin_dashboard.dart';
import './screens/admin_attendance_screen.dart';
import './screens/admin_approvals_screen.dart';
import './screens/admin_location_screen.dart';
import './screens/admin_expenses_list_screen.dart';
import './screens/employee_list_screen.dart';
import './screens/employee_edit_screen.dart';
import './screens/travel_attendance_screen.dart';
import './screens/additional_expenses_screen.dart';
import './screens/employee_expense_submission_screen.dart';
import 'database/db_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-Edge Display Configuration
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Ensure drawing behind the system bars
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
  // Initialize Database in background
  DatabaseHelper.instance.database.then((db) {
    DatabaseHelper.instance.seedData();
  });

  // Set window size for Desktop platforms ONLY
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(400, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: "Employee Tracker",
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(false);
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Employee Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, primary: Colors.blue[800]!),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      initialRoute: WelcomeScreen.id,
      routes: {
        WelcomeScreen.id: (context) => const WelcomeScreen(),
        LoginScreen.id: (context) => const LoginScreen(),
        RegisterScreen.id: (context) => const RegisterScreen(),
        LiveDataMonitorScreen.id: (context) => const LiveDataMonitorScreen(),
        AdminDashboard.id: (context) => const AdminDashboard(),
        AdminAttendanceScreen.id: (context) => const AdminAttendanceScreen(),
        AdminApprovalsScreen.id: (context) => const AdminApprovalsScreen(),
        AdminLocationScreen.id: (context) => const AdminLocationScreen(),
        AdminExpensesListScreen.id: (context) => const AdminExpensesListScreen(),
        EmployeeListScreen.id: (context) => const EmployeeListScreen(),
        EmployeeEditScreen.id: (context) => const EmployeeEditScreen(),
        TravelAttendanceScreen.id: (context) => const TravelAttendanceScreen(),
        AdditionalExpensesScreen.id: (context) => const AdditionalExpensesScreen(),
        EmployeeExpenseSubmissionScreen.id: (context) => const EmployeeExpenseSubmissionScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == HomePage.id) {
          return MaterialPageRoute(
            builder: (context) => const HomePage(),
          );
        }
        return null;
      },
    );
  }
}
