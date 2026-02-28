import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_logger.dart';

class DebugLogsScreen extends StatefulWidget {
  const DebugLogsScreen({super.key});

  @override
  State<DebugLogsScreen> createState() => _DebugLogsScreenState();
}

class _RealTimeLogsView extends StatelessWidget {
  const _RealTimeLogsView();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: AppLogger.logs,
      builder: (context, logList, _) {
        if (logList.isEmpty) {
          return const Center(child: Text('No logs found.', style: TextStyle(color: Colors.grey)));
        }
        return ListView.builder(
          itemCount: logList.length,
          padding: const EdgeInsets.all(8),
          itemBuilder: (context, index) {
            return Card(
              color: Colors.black87,
              margin: const EdgeInsets.only(bottom: 4),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SelectableText(
                  logList[index],
                  style: const TextStyle(
                    color: Colors.lightGreenAccent,
                    fontFamily: 'Courier', // Monospace font
                    fontSize: 12,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DebugLogsScreenState extends State<DebugLogsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Logs'),
        actions: [
          IconButton(
            onPressed: () {
              final allLogs = AppLogger.logs.value.join('\n');
              Clipboard.setData(ClipboardData(text: allLogs));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All logs copied to clipboard')),
              );
            },
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy All',
          ),
          IconButton(
            onPressed: () => AppLogger.clear(),
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear Logs',
          ),
        ],
      ),
      body: const _RealTimeLogsView(),
    );
  }
}
