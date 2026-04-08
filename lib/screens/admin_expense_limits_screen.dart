import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/mqtt_handler.dart';
import '../utils/app_logger.dart';

class AdminExpenseLimitsScreen extends StatefulWidget {
  const AdminExpenseLimitsScreen({super.key});
  static const String id = 'admin_expense_limits_screen';

  @override
  State<AdminExpenseLimitsScreen> createState() =>
      _AdminExpenseLimitsScreenState();
}

class _AdminExpenseLimitsScreenState extends State<AdminExpenseLimitsScreen> {
  // Fuel Controllers
  final TextEditingController _fuelKmLimitController = TextEditingController();
  final TextEditingController _fuelAmtLimitController = TextEditingController();

  // Food Controllers
  final TextEditingController _foodAmtLimitController = TextEditingController();
  String _foodType = 'Standard';

  // Material Controllers
  final TextEditingController _materialAmtLimitController =
      TextEditingController();
  String _materialType = 'General';

  // Travel Controllers
  final TextEditingController _travelRapidoLimitController =
      TextEditingController();
  final TextEditingController _travelBusLimitController =
      TextEditingController();
  final TextEditingController _travelOwnVehicleLimitController =
      TextEditingController();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadLimits();
  }

  @override
  void dispose() {
    _fuelKmLimitController.dispose();
    _fuelAmtLimitController.dispose();
    _foodAmtLimitController.dispose();
    _materialAmtLimitController.dispose();
    _travelRapidoLimitController.dispose();
    _travelBusLimitController.dispose();
    _travelOwnVehicleLimitController.dispose();
    super.dispose();
  }

  Future<void> _loadLimits() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fuelKmLimitController.text =
          prefs.getDouble('fuel_km_limit')?.toString() ?? '0.0';
      _fuelAmtLimitController.text =
          prefs.getDouble('fuel_amt_limit')?.toString() ?? '0.0';
      _foodType = prefs.getString('food_type_limit') ?? 'Standard';
      _foodAmtLimitController.text =
          prefs.getDouble('food_amt_limit')?.toString() ?? '0.0';
      _materialType = prefs.getString('material_type_limit') ?? 'General';
      _materialAmtLimitController.text =
          prefs.getDouble('material_amt_limit')?.toString() ?? '0.0';
      _travelRapidoLimitController.text =
          prefs.getDouble('travel_rapido_limit')?.toString() ?? '0.0';
      _travelBusLimitController.text =
          prefs.getDouble('travel_bus_limit')?.toString() ?? '0.0';
      _travelOwnVehicleLimitController.text =
          prefs.getDouble('travel_own_vehicle_limit')?.toString() ?? '0.0';
    });
  }

  Future<void> _updateLimits() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();

      // Parse values
      final fuelKmLimit = double.tryParse(_fuelKmLimitController.text) ?? 0.0;
      final fuelAmtLimit = double.tryParse(_fuelAmtLimitController.text) ?? 0.0;
      final foodAmtLimit = double.tryParse(_foodAmtLimitController.text) ?? 0.0;
      final materialAmtLimit =
          double.tryParse(_materialAmtLimitController.text) ?? 0.0;
      final travelRapidoLimit =
          double.tryParse(_travelRapidoLimitController.text) ?? 0.0;
      final travelBusLimit =
          double.tryParse(_travelBusLimitController.text) ?? 0.0;
      final travelOwnVehicleLimit =
          double.tryParse(_travelOwnVehicleLimitController.text) ?? 0.0;

      // Save locally
      await prefs.setDouble('fuel_km_limit', fuelKmLimit);
      await prefs.setDouble('fuel_amt_limit', fuelAmtLimit);
      await prefs.setString('food_type_limit', _foodType);
      await prefs.setDouble('food_amt_limit', foodAmtLimit);
      await prefs.setString('material_type_limit', _materialType);
      await prefs.setDouble('material_amt_limit', materialAmtLimit);
      await prefs.setDouble('travel_rapido_limit', travelRapidoLimit);
      await prefs.setDouble('travel_bus_limit', travelBusLimit);
      await prefs.setDouble('travel_own_vehicle_limit', travelOwnVehicleLimit);

      // Prepare payload for MQTT
      final limitsPayload = {
        'fuel': {'km_limit': fuelKmLimit, 'amt_limit': fuelAmtLimit},
        'food': {'type': _foodType, 'amt_limit': foodAmtLimit},
        'material': {'type': _materialType, 'amt_limit': materialAmtLimit},
        'travel': {
          'rapido': travelRapidoLimit,
          'bus': travelBusLimit,
          'own_vehicle': travelOwnVehicleLimit,
        },
      };

      // Publish via MQTT
      MqttHandler().publishExpenseLimits(limitsPayload);
      AppLogger.log('Expense limits updated and published via MQTT');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Expense limits updated and broadcasted successfully!',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      AppLogger.log('Error updating expense limits: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: false,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Expense Limits'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Fuel Section
            _buildSection(
              title: 'Fuel Limits',
              icon: Icons.local_gas_station,
              color: Colors.orange,
              children: [
                _buildInputField(
                  label: 'KM Limit',
                  controller: _fuelKmLimitController,
                  hint: 'e.g., 500.0',
                ),
                _buildInputField(
                  label: 'Amount Limit (₹)',
                  controller: _fuelAmtLimitController,
                  hint: 'e.g., 5000.0',
                ),
              ],
            ),

            // Food Section
            _buildSection(
              title: 'Food Limits',
              icon: Icons.restaurant,
              color: Colors.green,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: DropdownButtonFormField<String>(
                    value: _foodType,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _foodType = value);
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                        value: 'Standard',
                        child: Text('Standard'),
                      ),
                      DropdownMenuItem(
                        value: 'Premium',
                        child: Text('Premium'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Food Type',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                _buildInputField(
                  label: 'Amount Limit (₹)',
                  controller: _foodAmtLimitController,
                  hint: 'e.g., 500.0',
                ),
              ],
            ),

            // Material Section
            _buildSection(
              title: 'Material Limits',
              icon: Icons.inventory_2,
              color: Colors.blue,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: DropdownButtonFormField<String>(
                    value: _materialType,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _materialType = value);
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                        value: 'General',
                        child: Text('General'),
                      ),
                      DropdownMenuItem(value: 'Office', child: Text('Office')),
                      DropdownMenuItem(value: 'Site', child: Text('Site')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Material Type',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                _buildInputField(
                  label: 'Amount Limit (₹)',
                  controller: _materialAmtLimitController,
                  hint: 'e.g., 2000.0',
                ),
              ],
            ),

            // Travel Section
            _buildSection(
              title: 'Travel Limits',
              icon: Icons.directions_car,
              color: Colors.purple,
              children: [
                _buildInputField(
                  label: 'Rapido Limit (₹)',
                  controller: _travelRapidoLimitController,
                  hint: 'e.g., 300.0',
                ),
                _buildInputField(
                  label: 'Bus Limit (₹)',
                  controller: _travelBusLimitController,
                  hint: 'e.g., 200.0',
                ),
                _buildInputField(
                  label: 'Own Vehicle Limit (₹)',
                  controller: _travelOwnVehicleLimitController,
                  hint: 'e.g., 1000.0',
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Update Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save_as, size: 22),
                label: const Text(
                  'Update Global Limits',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isSubmitting ? null : _updateLimits,
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
