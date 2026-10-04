import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../cloudinary_service.dart';
import '../../entities/app_user.dart';

const Color _brandRed = Color(0xFFE30613);
const Color _availableGreen = Color(0xFF16A34A);

/// Static content describing what a service involves (same copy as provider
/// onboarding).
class _ServiceInfo {
  final String label;
  final String summary;
  final String description;
  final List<String> requirements;
  final String iconAsset;

  const _ServiceInfo({
    required this.label,
    required this.summary,
    required this.description,
    required this.requirements,
    required this.iconAsset,
  });
}

const Map<ServiceType, _ServiceInfo> _serviceInfo = {
  ServiceType.mechanic: _ServiceInfo(
    label: 'Mechanic',
    summary: 'On-site diagnosis and minor repairs',
    description:
        'Diagnose the issue at the customer\'s location and carry out minor '
        'repairs that get the vehicle running again, without needing a full '
        'workshop visit.',
    requirements: [
      'Basic mechanic tool kit',
      'Experience with common vehicle faults',
      'Valid ID for verification',
    ],
    iconAsset: 'assets/images/icon-mechanic.png',
  ),
  ServiceType.towTruck: _ServiceInfo(
    label: 'Tow Truck',
    summary: 'Transport a non-drivable vehicle',
    description:
        'Recover a vehicle that cannot be driven and transport it to a '
        'garage, home, or other safe location using a tow vehicle or flatbed.',
    requirements: [
      'Registered tow vehicle or flatbed',
      'Valid driving license for the vehicle class',
      'Towing straps / winch equipment',
    ],
    iconAsset: 'assets/images/icon-towtruck.png',
  ),
  ServiceType.fuelDelivery: _ServiceInfo(
    label: 'Fuel Delivery',
    summary: 'Deliver fuel to a stranded vehicle',
    description:
        'Bring a small, safe quantity of fuel directly to a customer who has '
        'run out, so they can get to the nearest fuel station.',
    requirements: [
      'Approved fuel container',
      'Safe fuel handling practice',
      'Own transport to reach the customer',
    ],
    iconAsset: 'assets/images/icon-jerrycan.png',
  ),
  ServiceType.flatTireChange: _ServiceInfo(
    label: 'Flat Tire Change',
    summary: 'Replace a flat tire with the spare',
    description:
        'Safely jack up the vehicle and swap a flat tire for the customer\'s '
        'spare, so they can continue their journey or reach a tire shop.',
    requirements: [
      'Jack and lug wrench',
      'Basic tire-changing tools',
      'Reflective safety gear',
    ],
    iconAsset: 'assets/images/icon-flattire.png',
  ),
  ServiceType.batteryBoost: _ServiceInfo(
    label: 'Battery Boost',
    summary: 'Jump-start a dead battery',
    description:
        'Use jumper cables or a portable jump-starter to get a vehicle with '
        'a dead battery running again on the spot.',
    requirements: [
      'Jumper cables or portable jump-starter',
      'Basic understanding of vehicle electrics',
    ],
    iconAsset: 'assets/images/icon-battery.png',
  ),
};

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

  // Which service cards are expanded to show full details.
  final Set<ServiceType> _expandedServices = {};

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
        actions: [if (!_loading && _isProvider) _buildAvailabilityToggle()],
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
                  const SizedBox(height: 28),
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
                // Providers get a ring (green = online, grey = offline) with a
                // small gap between the ring and the photo.
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(_isProvider ? 7 : 0),
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
                ),
                if (_uploadingPhoto)
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.all(_isProvider ? 7 : 0),
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
                  ),
                if (_isProvider)
                  Positioned.fill(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (_provider?.isAvailable ?? false)
                              ? _availableGreen
                              : Colors.grey.shade400,
                          width: 4,
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
                      color: Colors.grey.shade600,
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

  // ---- Name + phone (outlined fields with the label on the border) ----
  OutlineInputBorder _outline(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  InputDecoration _fieldDecoration(String label, {Widget? suffix}) {
    final labelStyle = TextStyle(fontSize: 16, color: Colors.grey.shade600);
    return InputDecoration(
      labelText: label,
      labelStyle: labelStyle,
      floatingLabelStyle: labelStyle,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      suffixIcon: suffix,
      border: _outline(Colors.grey.shade400),
      enabledBorder: _outline(Colors.grey.shade400),
      focusedBorder: _outline(Colors.black, 1.5),
    );
  }

  /// Display only: +94712345678 -> +94 71 234 5678. Anything that doesn't
  /// match the Sri Lankan mobile pattern is shown unchanged.
  String _formatPhone(String raw) {
    final m = RegExp(r'^\+94(\d{2})(\d{3})(\d{4})$')
        .firstMatch(raw.replaceAll(' ', ''));
    if (m == null) return raw;
    return '+94 ${m[1]} ${m[2]} ${m[3]}';
  }

  Widget _buildInfo(AppUser user) {
    return Column(
      children: [
        if (_editing)
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 16),
            decoration: _fieldDecoration('Name'),
          )
        else
          InputDecorator(
            decoration: _fieldDecoration('Name'),
            child: Text(
              user.name.isEmpty ? '—' : user.name,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        const SizedBox(height: 18),
        InputDecorator(
          decoration: _fieldDecoration(
            'Phone number',
            suffix: _editing
                ? Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: Colors.grey.shade400,
                  )
                : null,
          ),
          child: Text(
            user.phoneNumber.isEmpty ? '—' : _formatPhone(user.phoneNumber),
            style: TextStyle(
              fontSize: 16,
              color: _editing ? Colors.grey.shade500 : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  // ---- Provider only: availability toggle (app bar, top right) ----
  Widget _buildAvailabilityToggle() {
    final available = _provider?.isAvailable ?? false;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Tooltip(
        message: available ? 'Available for requests' : 'Not available',
        child: Switch(
          value: available,
          onChanged: _setAvailability,
          thumbColor: const WidgetStatePropertyAll(Colors.white),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? _availableGreen
                : Colors.grey.shade400,
          ),
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
    );
  }

  // ---- Provider only: services ----
  IconData _fallbackServiceIcon(ServiceType s) {
    switch (s) {
      case ServiceType.mechanic:
        return Icons.build_rounded;
      case ServiceType.towTruck:
        return Icons.local_shipping_rounded;
      case ServiceType.fuelDelivery:
        return Icons.local_gas_station_rounded;
      case ServiceType.flatTireChange:
        return Icons.tire_repair_rounded;
      case ServiceType.batteryBoost:
        return Icons.battery_charging_full_rounded;
      default:
        return Icons.handyman_rounded;
    }
  }

  void _toggleExpanded(ServiceType s) {
    setState(() {
      if (!_expandedServices.remove(s)) _expandedServices.add(s);
    });
  }

  void _toggleSelected(ServiceType s) {
    setState(() {
      if (!_editServices.remove(s)) _editServices.add(s);
    });
  }

  Widget _buildServices() {
    final current = _provider?.services ?? const <ServiceType>{};
    final shown = _editing ? _editServices : current;
    // Keep a stable (enum) order in both modes.
    final items = _editing
        ? ServiceType.values
        : ServiceType.values.where(shown.contains).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Services offered',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${shown.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _editing
              ? 'Tap a card to select it. Tap the arrow to see what\'s '
                    'involved and what you\'ll need.'
              : 'What customers can request from you. Tap the arrow for '
                    'details.',
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.handyman_outlined, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text(
                  'No services selected yet',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
          )
        else
          for (final s in items)
            _serviceCard(s, selected: shown.contains(s), editable: _editing),
      ],
    );
  }

  /// Same card as provider onboarding: icon, name + summary, selection
  /// check (edit mode only) and an expandable "what's involved" section.
  Widget _serviceCard(
    ServiceType service, {
    required bool selected,
    required bool editable,
  }) {
    final info = _serviceInfo[service]!;
    final isExpanded = _expandedServices.contains(service);
    final highlighted = editable && selected;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? Colors.black : Colors.grey.shade300,
          width: highlighted ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () =>
                editable ? _toggleSelected(service) : _toggleExpanded(service),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.black,
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        info.iconAsset,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          _fallbackServiceIcon(service),
                          size: 30,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          info.summary,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (editable) ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? Colors.black : Colors.transparent,
                        border: Border.all(
                          color: selected ? Colors.black : Colors.grey.shade400,
                          width: 1.6,
                        ),
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ],
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _toggleExpanded(service),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: AnimatedRotation(
                        duration: const Duration(milliseconds: 180),
                        turns: isExpanded ? 0.5 : 0,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: isExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Text(
                    info.description,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'What you\'ll need',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...info.requirements.map(
                    (req) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 15,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              req,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
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
