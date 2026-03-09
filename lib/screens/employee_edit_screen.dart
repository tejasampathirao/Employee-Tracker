import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../database/db_helper.dart';

class EmployeeEditScreen extends StatefulWidget {
  final Map<String, dynamic>? employee;
  const EmployeeEditScreen({super.key, this.employee});
  static const String id = 'employee_edit_screen';

  @override
  State<EmployeeEditScreen> createState() => _EmployeeEditScreenState();
}

class _EmployeeEditScreenState extends State<EmployeeEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _empIdController = TextEditingController();
  final _nameController = TextEditingController();
  final _panController = TextEditingController();
  final _aadharController = TextEditingController();
  final _bankAccController = TextEditingController();
  final _ifscController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _motherNameController = TextEditingController();
  final _salaryController = TextEditingController();
  
  String _selectedRole = 'Employee';
  File? _imageFile;
  bool _isLoading = false;
  int? _sqliteId;

  @override
  void initState() {
    super.initState();
    if (widget.employee != null) {
      _sqliteId = widget.employee!['id'];
      _empIdController.text = widget.employee!['emp_id'] ?? '';
      _nameController.text = widget.employee!['name'] ?? '';
      _panController.text = widget.employee!['pan_no'] ?? '';
      _aadharController.text = widget.employee!['aadhar_no'] ?? '';
      _bankAccController.text = widget.employee!['bank_acc_no'] ?? '';
      _ifscController.text = widget.employee!['ifsc_code'] ?? '';
      _fatherNameController.text = widget.employee!['father_name'] ?? '';
      _motherNameController.text = widget.employee!['mother_name'] ?? '';
      _salaryController.text = widget.employee!['salary']?.toString() ?? '';
      _selectedRole = widget.employee!['role'] ?? 'Employee';
      if (widget.employee!['photo_path'] != null) {
        _imageFile = File(widget.employee!['photo_path']);
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final employeeData = {
      if (_sqliteId != null) 'id': _sqliteId,
      'emp_id': _empIdController.text.trim(),
      'name': _nameController.text,
      'pan_no': _panController.text,
      'aadhar_no': _aadharController.text,
      'bank_acc_no': _bankAccController.text,
      'ifsc_code': _ifscController.text,
      'father_name': _fatherNameController.text,
      'mother_name': _motherNameController.text,
      'salary': double.tryParse(_salaryController.text) ?? 0.0,
      'role': _selectedRole,
      'photo_path': _imageFile?.path,
    };

    try {
      // 1. Save to SQLite
      await DatabaseHelper.instance.updateEmployee(employeeData);

      // 2. Save/Update in Excel
      await _updateExcel(employeeData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employee Data & Excel updated successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateExcel(Map<String, dynamic> data) async {
    const String fileName = "Employee_Database.xlsx";
    const String sheetName = "EmployeeDetails";
    
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(directory.path, fileName);
    final file = File(path);

    Excel excel;
    if (await file.exists()) {
      var bytes = file.readAsBytesSync();
      excel = Excel.decodeBytes(bytes);
    } else {
      excel = Excel.createExcel();
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }
    }

    Sheet sheet = excel[sheetName];
    
    if (sheet.maxRows == 0) {
      sheet.appendRow([
        'Emp ID', 'Name', 'Role', 'PAN No', 'Aadhar No', 'Bank Acc No', 
        'IFSC Code', 'Father Name', 'Mother Name', 'Salary'
      ].map((e) => TextCellValue(e)).toList());
    }

    final String empId = data['emp_id'].toString();
    int? targetRowIndex;

    for (int i = 0; i < sheet.maxRows; i++) {
      var cellValue = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i)).value;
      if (cellValue?.toString() == empId) {
        targetRowIndex = i;
        break;
      }
    }

    final rowData = [
      data['emp_id'].toString(),
      data['name'],
      data['role'],
      data['pan_no'],
      data['aadhar_no'],
      data['bank_acc_no'],
      data['ifsc_code'],
      data['father_name'],
      data['mother_name'],
      data['salary'].toString(),
    ].map((e) => TextCellValue(e?.toString() ?? "")).toList();

    if (targetRowIndex != null) {
      for (int i = 0; i < rowData.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: targetRowIndex)).value = rowData[i];
      }
    } else {
      sheet.appendRow(rowData);
    }

    var fileBytes = excel.save();
    if (fileBytes != null) {
      await file.writeAsBytes(fileBytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.employee == null ? 'New Employee' : 'Edit Employee'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildPhotoPicker(),
                  const SizedBox(height: 30),
                  _buildTextField(_empIdController, 'Employee ID (e.g., AMP-001)', Icons.badge_outlined, isNumber: false, isEnabled: widget.employee == null),
                  const SizedBox(height: 15),
                  _buildTextField(_nameController, 'Full Name', Icons.person),
                  const SizedBox(height: 15),
                  _buildRoleDropdown(),
                  const SizedBox(height: 15),
                  _buildTextField(_panController, 'PAN Card No', Icons.credit_card),
                  const SizedBox(height: 15),
                  _buildTextField(_aadharController, 'Aadhar Card No', Icons.badge_outlined, isNumber: true),
                  const SizedBox(height: 15),
                  _buildTextField(_bankAccController, 'Bank Account No', Icons.account_balance_wallet, isNumber: true),
                  const SizedBox(height: 15),
                  _buildTextField(_ifscController, 'IFSC Code', Icons.code),
                  const SizedBox(height: 15),
                  _buildTextField(_fatherNameController, 'Father Name', Icons.family_restroom),
                  const SizedBox(height: 15),
                  _buildTextField(_motherNameController, 'Mother Name', Icons.family_restroom_outlined),
                  const SizedBox(height: 15),
                  _buildTextField(_salaryController, 'Salary', Icons.payments, isNumber: true),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: _saveData,
                      icon: const Icon(Icons.save),
                      label: const Text('SAVE DATA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildPhotoPicker() {
    return Column(
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            height: 120,
            width: 120,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blue[800]!, width: 2),
              image: _imageFile != null 
                ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover)
                : null,
            ),
            child: _imageFile == null 
              ? Icon(Icons.person, size: 60, color: Colors.grey[400])
              : null,
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.camera_alt),
          label: const Text('Select Passport Size Photo'),
        ),
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isNumber = false, bool isEnabled = true}) {
    return TextFormField(
      controller: controller,
      enabled: isEnabled,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      validator: (value) => value == null || value.isEmpty ? 'This field is required' : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.blue[800]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        filled: true,
        fillColor: isEnabled ? Colors.white : Colors.grey[100],
      ),
    );
  }

  Widget _buildRoleDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedRole,
      decoration: InputDecoration(
        labelText: 'Role',
        prefixIcon: Icon(Icons.work_outline, color: Colors.blue[800]),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      ),
      items: ['Employee', 'Admin', 'Trainee'].map((role) {
        return DropdownMenuItem(value: role, child: Text(role));
      }).toList(),
      onChanged: (value) {
        if (value != null) setState(() => _selectedRole = value);
      },
    );
  }
}
