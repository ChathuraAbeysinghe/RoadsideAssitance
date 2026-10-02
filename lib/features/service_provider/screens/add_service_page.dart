import 'package:flutter/material.dart';

import '../../../entities/app_user.dart';
import '../models/provider_service.dart';
import '../services/provider_repository.dart';

class AddServicePage extends StatefulWidget {
  final String uid;
  final ProviderService? existingService;

  const AddServicePage({super.key, required this.uid, this.existingService});
  @override
  State<AddServicePage> createState() => _AddServicePageState();
}

class _AddServicePageState extends State<AddServicePage> {
  late ServiceType _type;
  bool _saving = false;
  final _name = TextEditingController();
  final _vehicles = TextEditingController();
  final _plate = TextEditingController();
  final _location = TextEditingController();
  final _details = TextEditingController();

  static const _typeOrder = [
    ServiceType.towTruck,
    ServiceType.mechanic,
    ServiceType.fuelDelivery,
    ServiceType.flatTireChange,
    ServiceType.batteryBoost,
  ];

  String _labelFor(ServiceType type) => switch (type) {
        ServiceType.towTruck => 'Vehicle Tow',
        ServiceType.mechanic => 'Mechanic',
        ServiceType.fuelDelivery => 'Fuel Delivery',
        ServiceType.flatTireChange => 'Flat Tire',
        ServiceType.batteryBoost => 'Battery Boost',
      };

  @override
  void initState() {
    super.initState();
    final s = widget.existingService;
    _type = s?.serviceType ?? ServiceType.towTruck;
    if (s != null) {
      _name.text = s.name;
      _vehicles.text = s.vehicleTypes;
      _plate.text = s.plateNumber;
      _location.text = s.location;
      _details.text = s.details;
    }
  }

  @override
  void dispose() {
    for (final controller in [_name, _vehicles, _plate, _location, _details]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (widget.uid.isEmpty ||
        _name.text.trim().isEmpty ||
        _plate.text.trim().isEmpty ||
        _details.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final s = widget.existingService;
      if (s != null) {
        await ProviderRepository().updateService(s.copyWith(
          serviceType: _type,
          name: _name.text.trim(),
          vehicleTypes: _vehicles.text.trim(),
          plateNumber: _plate.text.trim(),
          location: _location.text.trim(),
          details: _details.text.trim(),
        ));
      } else {
        await ProviderRepository().addService(
          ProviderService(
            id: '',
            providerUid: widget.uid,
            serviceType: _type,
            name: _name.text.trim(),
            vehicleTypes: _vehicles.text.trim(),
            plateNumber: _plate.text.trim(),
            location: _location.text.trim(),
            details: _details.text.trim(),
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save service. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Service Type',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildTypeChips(),
                    const SizedBox(height: 28),
                    const Text(
                      'Details',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildLabeledField(
                      controller: _location,
                      label: 'Location',
                      hint: 'e.g. Colombo',
                    ),
                    const SizedBox(height: 14),
                    _buildLabeledField(
                      controller: _name,
                      label: 'Your Name',
                      hint: 'e.g. Nuwan Perera',
                      isRequired: true,
                    ),
                    const SizedBox(height: 14),
                    _buildLabeledField(
                      controller: _vehicles,
                      label: 'Truck Types',
                      hint: 'e.g. Flatbed',
                    ),
                    const SizedBox(height: 14),
                    _buildLabeledField(
                      controller: _plate,
                      label: 'Plate NO',
                      hint: 'e.g. WP CAA-9081',
                      isRequired: true,
                    ),
                    const SizedBox(height: 14),
                    _buildLabeledField(
                      controller: _details,
                      label: 'Details',
                      hint: 'Describe your service',
                      isRequired: true,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 44),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE30613),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Confirm',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
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
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            widget.existingService != null ? 'Edit Service' : 'Add Service',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.chevron_left),
              style: IconButton.styleFrom(
                side: BorderSide(color: Colors.grey.shade300),
                shape: const CircleBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _typeOrder.map((type) {
          final isSelected = type == _type;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              label: Text(_labelFor(type)),
              selected: isSelected,
              onSelected: (_) => setState(() => _type = type),
              showCheckmark: false,
              selectedColor: Colors.black,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.black87,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
                side: BorderSide(
                  color: isSelected ? Colors.black : Colors.grey.shade400,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLabeledField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool isRequired = false,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        label: RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            children: [
              TextSpan(text: label),
              if (isRequired)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: Color(0xFFE30613)),
                ),
            ],
          ),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

