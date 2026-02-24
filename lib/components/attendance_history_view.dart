import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/db_helper.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

class AttendanceHistoryView extends StatefulWidget {
  const AttendanceHistoryView({super.key});

  @override
  State<AttendanceHistoryView> createState() => _AttendanceHistoryViewState();
}

class _AttendanceHistoryViewState extends State<AttendanceHistoryView> {
  List<Map<String, dynamic>> _historyData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getAllAttendance();
    setState(() {
      _historyData = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildUnifiedSummary(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _historyData.isEmpty
                  ? const Center(child: Text('No history records found.'))
                  : ListView.builder(
                      itemCount: _historyData.length,
                      padding: const EdgeInsets.all(12),
                      itemBuilder: (context, index) {
                        final data = _historyData[index];
                        return _buildUnifiedListItem(data);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildUnifiedSummary() {
    if (_historyData.isEmpty) return const SizedBox.shrink();

    int officeCount = _historyData.where((item) => item['type'] == 'Office').length;
    int awayCount = _historyData.where((item) => item['type'] == 'Away').length;
    int failedCount = _historyData.where((item) => item['status'] == 'Failed').length;
    
    return Card(
      margin: const EdgeInsets.all(16),
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildSummaryItem('Office', '$officeCount', Colors.green),
            _buildSummaryItem('Away', '$awayCount', Colors.blue),
            _buildSummaryItem('Failed', '$failedCount', Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedListItem(Map<String, dynamic> data) {
    final checkIn = data['checkInTime'] != null ? DateTime.parse(data['checkInTime']) : null;
    final checkOut = data['checkOutTime'] != null ? DateTime.parse(data['checkOutTime']) : null;
    final type = data['type'] ?? 'Office';
    final status = data['status'] ?? 'Completed';
    final lat = data['latitude'] as double?;
    final lng = data['longitude'] as double?;
    final dateString = data['date'];
    final date = DateTime.tryParse(dateString) ?? DateTime.now();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEE, MMM d, yyyy').format(date),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (type == 'Office' ? Colors.green : Colors.blue).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            type.toUpperCase(),
                            style: TextStyle(
                              color: type == 'Office' ? Colors.green : Colors.blue,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (status == 'Failed')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'LOCATION MISMATCH',
                              style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (lat != null && lng != null)
                  IconButton(
                    icon: const Icon(Icons.location_on, color: Colors.red, size: 20),
                    onPressed: () => _showAttendanceMap(context, lat, lng, dateString),
                  ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTimeInfo('IN', checkIn != null ? DateFormat('hh:mm a').format(checkIn) : '--:--'),
                _buildTimeInfo('OUT', checkOut != null ? DateFormat('hh:mm a').format(checkOut) : '--:--'),
                _buildStatusBadge(checkOut == null ? 'Active' : status),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildTimeInfo(String label, String time) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(time, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == 'Completed' ? Colors.green : (status == 'Active' ? Colors.orange : Colors.red);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showAttendanceMap(BuildContext context, double lat, double lng, String date) {
    GoogleMapController? mapController;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Check-in Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Text('Recorded: $date', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  GoogleMap(
                    onMapCreated: (controller) => mapController = controller,
                    initialCameraPosition: CameraPosition(
                      target: LatLng(lat, lng),
                      zoom: 15,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    markers: {
                      Marker(
                        markerId: const MarkerId('attendance_loc'),
                        position: LatLng(lat, lng),
                        infoWindow: InfoWindow(title: 'Check-in Location', snippet: date),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                      ),
                    },
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'recenter_checkin',
                          onPressed: () {
                            mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15));
                          },
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.history, color: Colors.red),
                        ),
                        const SizedBox(height: 8),
                        FloatingActionButton.small(
                          heroTag: 'show_live',
                          onPressed: () async {
                            try {
                              final pos = await Geolocator.getCurrentPosition();
                              mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15));
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not get live location')));
                              }
                            }
                          },
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.my_location, color: Colors.blue),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    right: 20,
                    left: 20,
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
                              if (await canLaunchUrl(Uri.parse(url))) {
                                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: const Icon(Icons.directions, color: Colors.white),
                            label: const Text('Directions', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
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
      ),
    );
  }
}
