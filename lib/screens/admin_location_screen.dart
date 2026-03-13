import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../database/db_helper.dart';

class AdminLocationScreen extends StatefulWidget {
  const AdminLocationScreen({super.key});
  static const String id = 'admin_location_screen';

  @override
  State<AdminLocationScreen> createState() => _AdminLocationScreenState();
}

class _AdminLocationScreenState extends State<AdminLocationScreen> {
  Future<void> _openMap(double lat, double lng) async {
    final String googleMapsUrl = "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
    final Uri url = Uri.parse(googleMapsUrl);
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Location Logs'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseHelper.instance.getAllLiveLocations(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No location logs found.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                ],
              ),
            );
          }

          final logs = snapshot.data!;

          return ListView.builder(
            itemCount: logs.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final log = logs[index];
              final double lat = log['latitude'] ?? 0.0;
              final double lng = log['longitude'] ?? 0.0;
              final String timestamp = log['timestamp'] ?? 'N/A';
              
              // Format timestamp if possible
              String displayTime = timestamp;
              try {
                final dt = DateTime.parse(timestamp);
                displayTime = DateFormat('MMM dd, hh:mm a').format(dt);
              } catch (_) {}

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                    child: Icon(Icons.person_pin_circle, color: theme.colorScheme.primary),
                  ),
                  title: Text(
                    log['employee_id'] ?? 'Unknown Employee',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text('Time: $displayTime', style: TextStyle(color: Colors.grey[600])),
                      Text('Coords: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}', 
                        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.map_outlined, color: Colors.blue),
                    onPressed: () => _openMap(lat, lng),
                    tooltip: 'View on Map',
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
