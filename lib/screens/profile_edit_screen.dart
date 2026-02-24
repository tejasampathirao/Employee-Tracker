import 'package:flutter/material.dart';
import '../database/db_helper.dart';

class ProfileEditScreen extends StatefulWidget {
  final String currentName;
  final String currentDetails;
  const ProfileEditScreen({super.key, required this.currentName, required this.currentDetails});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late TextEditingController _nameController;
  late TextEditingController _detailsController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
    _detailsController = TextEditingController(text: widget.currentDetails);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Profile Name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _detailsController,
              decoration: const InputDecoration(labelText: 'Details / Job Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () async {
                  await DatabaseHelper.instance.updateUserProfile(
                    _nameController.text,
                    _detailsController.text,
                  );
                  if (mounted) {
                    Navigator.pop(context, true); // Return true to indicate update
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('SAVE CHANGES', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
