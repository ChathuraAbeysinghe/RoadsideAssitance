import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../entities/app_user.dart';
import '../../../cloudinary_service.dart';
import '../../home/home_page.dart'; // TODO: replace with a real provider home page once it exists.

/// Static content describing what a service actually involves, so a
/// provider can make an informed choice before selecting it. Edit the
/// copy here — this is the single source of truth for service details
/// shown during provider onboarding.
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

class ServiceProviderCompleteProfilePage extends StatefulWidget {
  final String uid;
  final String phoneNumber;

  const ServiceProviderCompleteProfilePage({
    super.key,
    required this.uid,
    required this.phoneNumber,
  });

  @override
  State<ServiceProviderCompleteProfilePage> createState() =>
      _ServiceProviderCompleteProfilePageState();
}

class _ServiceProviderCompleteProfilePageState
    extends State<ServiceProviderCompleteProfilePage> {
  final _nameController = TextEditingController();
  final _picker = ImagePicker();

  XFile? _pickedImage;
  bool _isLoading = false;

  // Which services this provider offers. Nothing pre-selected;
  // user must pick at least one before submitting.
  final Set<ServiceType> _selectedServices = {};

  // Which service cards are currently expanded to show full details.
  // Independent of selection — a provider can read details without
  // opting in, and select without reading details.
  final Set<ServiceType> _expandedServices = {};

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 512,
    );
    if (picked != null) {
      setState(() => _pickedImage = picked);
    }
  }

  void _toggleService(ServiceType service) {
    setState(() {
      if (_selectedServices.contains(service)) {
        _selectedServices.remove(service);
      } else {
        _selectedServices.add(service);
      }
    });
  }

  void _toggleExpanded(ServiceType service) {
    setState(() {
      if (_expandedServices.contains(service)) {
        _expandedServices.remove(service);
      } else {
        _expandedServices.add(service);
      }
    });
  }

  Future<void> _onSubmit() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter your name')));
      return;
    }

    if (_selectedServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one service you offer'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    String imageUrl = '';
    if (_pickedImage != null) {
      final uploadedUrl = await CloudinaryService.uploadImage(_pickedImage!);
      if (uploadedUrl == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image upload failed. Try again.')),
        );
        return;
      }
      imageUrl = uploadedUrl;
    }

    // currentLocation and rating default sensibly (empty location,
    // zero rating) and can be updated later once the app starts
    // tracking the provider's live position and reviews.
    final provider = AssistanceProvider(
      uid: widget.uid,
      phoneNumber: widget.phoneNumber,
      name: _nameController.text.trim(),
      profileImagePath: imageUrl,
      services: _selectedServices,
    );

    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .set(provider.toMap());

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        // TODO: swap for a real provider home page (e.g.
        // AssistanceProviderHomePage) once it exists.
        builder: (_) => HomePage(
          userName: provider.name,
          profileImagePath: provider.profileImagePath,
        ),
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Widget _buildServiceCard(ServiceType service) {
    final info = _serviceInfo[service]!;
    final isSelected = _selectedServices.contains(service);
    final isExpanded = _expandedServices.contains(service);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 1),
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
          // Main row: icon, name/summary, selection check, expand chevron.
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _toggleService(service),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.grey.shade600,
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        info.iconAsset,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.build_rounded,
                          size: 30,
                          color: Colors.grey.shade600,
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
                  const SizedBox(width: 8),
                  // Selection indicator — filled black when selected.
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? Colors.black : Colors.transparent,
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.grey.shade400,
                        width: 1.6,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 4),
                  // Expand/collapse "learn more" — separate tap target
                  // from the selection tap above.
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
                  Text(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2,
                        ),
                        color: Colors.grey.shade200,
                      ),
                      child: CircleAvatar(
                        radius: 58,
                        backgroundColor: Colors.transparent,
                        backgroundImage: _pickedImage != null
                            ? FileImage(File(_pickedImage!.path))
                            : null,
                        child: _pickedImage == null
                            ? Icon(
                                Icons.camera_alt_rounded,
                                size: 38,
                                color: Colors.grey.shade600,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'Add profile photo',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Center(
                  child: Text(
                    'Complete Your Profile',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Tell us who you are and what services you offer',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Enter Your Full Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.black,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  'Services you offer',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap a card to select it. Tap the arrow to see what\'s '
                  'involved and what you\'ll need.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                ...ServiceType.values.map(_buildServiceCard),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _onSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE30613),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Get Started',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
