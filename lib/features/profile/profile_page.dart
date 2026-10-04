import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../cloudinary_service.dart';
import '../../entities/app_user.dart';
import '../../entities/service_request.dart'; // serviceTypeTitle

const Color _brandRed = Color(0xFFE30613);

/// Profile for the logged-in user. Works for both roles:
///  - driver:             photo, name, phone, rating
///  - assistanceProvider: the above + availability and services offered
///
/// Tap the photo any time to change it. Phone is read-only (it's the
/// login identifier).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _picker = ImagePicker();

  AppUser? _user;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  bool _editing = false;
  String? _error;

  // Editable copy of the services while in edit mode.
  Set<ServiceType> _editServices = {};

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  bool get _isProvider => _user?.userType == UserType.assistanceProvider;

  AssistanceProvider? get _provider =>
      _user is AssistanceProvider ? _user as AssistanceProvider : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ---------------- Data ----------------
  Future<void> _load() async {
    final doc = _doc;
    if (doc == null) {
      setState(() {
        _loading = false;
        _error = 'You are not logged in.';
      });
      return;
    }
    try {
      final snap = await doc.get();
      final data = snap.data();
      if (data == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Profile not found.';
        });
        return;
      }
      final user = userFromMap(doc.id, data);
      if (!mounted) return;
      setState(() {
        _user = user;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your profile.';
      });
    }
  }

  // ---------------- Photo ----------------
  Future<void> _changePhoto() async {
    if (_uploadingPhoto) return;
    final doc = _doc;
    if (doc == null) return;

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 512,
    );
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final url = await CloudinaryService.uploadImage(picked);
      if (url == null) {
        _snack('Image upload failed. Try again.');
        return;
      }
      await doc.update({'profileImagePath': url});
      await _load();
      _snack('Photo updated');
    } catch (_) {
      _snack('Could not update your photo');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ---------------- Edit ----------------
  void _startEdit() {
    final user = _user;
    if (user == null) return;
    _nameController.text = user.name;
    _editServices = Set.of(_provider?.services ?? const <ServiceType>{});
    setState(() => _editing = true);
  }

  void _cancelEdit() {
    FocusScope.of(context).unfocus();
    setState(() => _editing = false);
  }

  Future<void> _save() async {
    final doc = _doc;
    if (doc == null || _saving) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _snack('Please enter your name');
      return;
    }
    if (_isProvider && _editServices.isEmpty) {
      _snack('Select at least one service');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await doc.update({
        'name': name,
        if (_isProvider) 'services': _editServices.map((s) => s.name).toList(),
      });
      await _load();
      if (!mounted) return;
      setState(() => _editing = false);
      _snack('Profile updated');
    } catch (_) {
      _snack('Could not save changes');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setAvailability(bool value) async {
    final doc = _doc;
    final provider = _provider;
    if (doc == null || provider == null) return;

    final previous = provider;
    setState(() => _user = provider.copyWith(isAvailable: value));
    try {
      await doc.update({'isAvailable': value});
    } catch (_) {
      if (!mounted) return;
      setState(() => _user = previous);
      _snack('Could not update availability');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Profile',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _brandRed));
    }
    final user = _user;
    if (user == null) return _buildError();

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                _buildHeader(user),
                const SizedBox(height: 32),
                _buildInfo(user),
                if (_isProvider) ...[
                  const SizedBox(height: 8),
                  _buildAvailabilityRow(),
                  const SizedBox(height: 20),
                  _buildServices(),
                ],
              ],
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? 'Something went wrong.'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Header: photo, name, role, rating ----
  Widget _buildHeader(AppUser user) {
    final fallback = ColoredBox(
      color: Colors.grey.shade200,
      child: Icon(Icons.person, size: 56, color: Colors.grey.shade500),
    );
    final rating = user.rating;

    return Column(
      children: [
        GestureDetector(
          onTap: _changePhoto,
          child: SizedBox(
            width: 116,
            height: 116,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipOval(
                    child: user.profileImagePath.isNotEmpty
                        ? Image.network(
                            user.profileImagePath,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => fallback,
                            loadingBuilder: (context, child, progress) =>
                                progress == null ? child : fallback,
                          )
                        : fallback,
                  ),
                ),
                if (_uploadingPhoto)
                  Positioned.fill(
                    child: ClipOval(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.45),
                        child: const Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _brandRed,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          user.name.isEmpty ? 'Your name' : user.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isProvider ? 'Assistance Provider' : 'Driver',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const Icon(Icons.star_rounded, size: 17, color: Colors.amber),
            const SizedBox(width: 3),
            Text(
              rating.count > 0
                  ? '${rating.average.toStringAsFixed(1)} (${rating.count})'
                  : 'No ratings yet',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ],
    );
  }

  // ---- Name + phone ----
  Widget _buildInfo(AppUser user) {
    return Column(
      children: [
        _row(
          label: 'Name',
          child: _editing
              ? TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Enter your name',
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                    border: InputBorder.none,
                  ),
                )
              : Text(
                  user.name.isEmpty ? '—' : user.name,
                  style: const TextStyle(fontSize: 16),
                ),
        ),
        _divider(),
        _row(
          label: 'Phone',
          child: Text(
            user.phoneNumber.isEmpty ? '—' : user.phoneNumber,
            style: TextStyle(
              fontSize: 16,
              color: _editing ? Colors.grey.shade500 : Colors.black87,
            ),
          ),
          trailing: _editing
              ? Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade400)
              : null,
        ),
      ],
    );
  }

  Widget _row({
    required String label,
    required Widget child,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(child: child),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.grey.shade200);

  // ---- Provider only ----
  Widget _buildAvailabilityRow() {
    final available = _provider?.isAvailable ?? false;
    return Column(
      children: [
        _divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: _brandRed,
          title: const Text(
            'Available for requests',
            style: TextStyle(fontSize: 16),
          ),
          subtitle: Text(
            available
                ? 'Customers can see you on the map'
                : 'You are hidden from customers',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          value: available,
          onChanged: _setAvailability,
        ),
        _divider(),
      ],
    );
  }

  Widget _buildServices() {
    final current = _provider?.services ?? const <ServiceType>{};
    final shown = _editing ? _editServices : current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Services offered',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        if (_editing)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in ServiceType.values)
                FilterChip(
                  label: Text(serviceTypeTitle(s)),
                  selected: shown.contains(s),
                  showCheckmark: false,
                  backgroundColor: Colors.white,
                  selectedColor: _brandRed.withValues(alpha: 0.12),
                  side: BorderSide(
                    color: shown.contains(s) ? _brandRed : Colors.grey.shade300,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: shown.contains(s) ? _brandRed : Colors.black87,
                  ),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _editServices.add(s);
                    } else {
                      _editServices.remove(s);
                    }
                  }),
                ),
            ],
          )
        else if (shown.isEmpty)
          Text(
            'No services selected',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in shown)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    serviceTypeTitle(s),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  // ---- Bottom bar (pinned) ----
  Widget _buildBottomBar() {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(30),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: _editing
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _brandRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: shape,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Save changes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _saving ? null : _cancelEdit,
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
              ],
            )
          : SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _startEdit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandRed,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: shape,
                ),
                child: const Text(
                  'Edit profile',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
    );
  }
}
