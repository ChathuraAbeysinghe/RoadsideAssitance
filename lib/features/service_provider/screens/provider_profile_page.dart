import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../entities/app_user.dart';
import '../../_share/navbar/app_bottom_nav_bar.dart';

class ProviderProfilePage extends StatefulWidget {
  final String uid;
  const ProviderProfilePage({super.key, String? uid}) : uid = uid ?? '';
  @override
  State<ProviderProfilePage> createState() => _ProviderProfilePageState();
}

class _ProviderProfilePageState extends State<ProviderProfilePage> {
  late final String _uid;
  final _name = TextEditingController();
  bool _available = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _uid = widget.uid.isNotEmpty
        ? widget.uid
        : FirebaseAuth.instance.currentUser?.uid ?? '';
    _load();
  }

  Future<void> _load() async {
    if (_uid.isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .get();
    final data = doc.data() ?? {};
    if (!mounted) return;
    setState(() {
      _name.text = data['name'] as String? ?? '';
      _available = data['isAvailable'] as bool? ?? true;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await FirebaseFirestore.instance.collection('users').doc(_uid).set({
      'name': _name.text.trim(),
      'isAvailable': _available,
    }, SetOptions(merge: true));
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Profile updated')));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Profile',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      centerTitle: true,
      leading: const BackButton(),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const CircleAvatar(
                radius: 58,
                backgroundColor: Color(0xfff2f2f2),
                child: Icon(Icons.person_outline, size: 68, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Text(
                _name.text.isEmpty ? 'Provider profile' : _name.text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Assistance Provider',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Available for new jobs'),
                value: _available,
                onChanged: (value) => setState(() => _available = value),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    _saving ? 'Saving...' : 'Save Changes',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
    bottomNavigationBar: const AppBottomNavBar(
      userType: UserType.assistanceProvider,
      activeIndex: 3,
    ),
  );
}
