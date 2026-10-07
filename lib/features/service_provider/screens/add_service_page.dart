import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../entities/app_user.dart';
import '../models/provider_service.dart';
import '../services/provider_repository.dart';
import '../../request_service/request_service.dart' show MapApi;
import 'location_picker_page.dart';

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
  GeoLocation? _locationGeo;
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

  IconData _iconFor(ServiceType type) => switch (type) {
    ServiceType.towTruck => Icons.local_shipping_outlined,
    ServiceType.mechanic => Icons.build_outlined,
    ServiceType.fuelDelivery => Icons.local_gas_station_outlined,
    ServiceType.flatTireChange => Icons.tire_repair_outlined,
    ServiceType.batteryBoost => Icons.battery_charging_full_outlined,
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
      _locationGeo = s.locationGeo;
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
    bool isValid = widget.uid.isNotEmpty && _location.text.trim().isNotEmpty;
    if (_type == ServiceType.towTruck) {
      if (_vehicles.text.trim().isEmpty || _plate.text.trim().isEmpty)
        isValid = false;
    } else if (_type == ServiceType.mechanic) {
      if (_details.text.trim().isEmpty) isValid = false;
    } else if (_type == ServiceType.fuelDelivery) {
      if (_details.text.trim().isEmpty ||
          _vehicles.text.trim().isEmpty ||
          _plate.text.trim().isEmpty)
        isValid = false;
    }

    if (!isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    if (_type == ServiceType.batteryBoost ||
        _type == ServiceType.flatTireChange) {
      _name.clear();
      _vehicles.clear();
      _plate.clear();
      _details.clear();
    } else if (_type == ServiceType.mechanic) {
      _name.clear();
      _vehicles.clear();
      _plate.clear();
    } else if (_type == ServiceType.towTruck) {
      _name.clear();
      _details.clear();
    } else if (_type == ServiceType.fuelDelivery) {
      _name.clear();
    }
    setState(() => _saving = true);

    GeoLocation? locationGeo = _locationGeo;
    final locText = _location.text.trim();
    if (locText.isNotEmpty && locationGeo == null) {
      final latLng = await MapApi.geocode(locText);
      if (latLng != null) {
        locationGeo = GeoLocation(
          latitude: latLng.latitude,
          longitude: latLng.longitude,
        );
      }
    }

    try {
      final s = widget.existingService;
      if (s != null) {
        await ProviderRepository().updateService(
          s.copyWith(
            serviceType: _type,
            name: _name.text.trim(),
            vehicleTypes: _vehicles.text.trim(),
            plateNumber: _plate.text.trim(),
            location: locText,
            locationGeo: locationGeo,
            details: _details.text.trim(),
          ),
        );
      } else {
        await ProviderRepository().addService(
          ProviderService(
            id: '',
            providerUid: widget.uid,
            serviceType: _type,
            name: _name.text.trim(),
            vehicleTypes: _vehicles.text.trim(),
            plateNumber: _plate.text.trim(),
            location: locText,
            locationGeo: locationGeo,
            details: _details.text.trim(),
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save service. Try again.'), behavior: SnackBarBehavior.floating),
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Service Type',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildTypeChips(),
                    const SizedBox(height: 32),
                    const Text(
                      'Service Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._buildDynamicFields(),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE30613),
                          elevation: 4,
                          shadowColor: const Color(0xFFE30613).withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              )
                            : const Text(
                                'Save Service',
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.chevron_left, color: Colors.black87),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            widget.existingService != null ? 'Edit Service' : 'Add Service',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDynamicFields() {
    List<Widget> fields = [];

    fields.add(
      _buildLabeledField(
        controller: _location,
        label: 'Operating Location',
        hint: 'e.g. Colombo, Sri Lanka',
        isRequired: true,
        icon: Icons.location_on_outlined,
        suffixIcon: IconButton(
          icon: const Icon(Icons.map, color: Color(0xFFE30613)),
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LocationPickerPage()),
            );
            if (result != null && result is Map) {
              final LatLng latLng = result['latLng'];
              final String addr = result['address'];
              setState(() {
                _location.text = addr;
                _locationGeo = GeoLocation(
                  latitude: latLng.latitude,
                  longitude: latLng.longitude,
                );
              });
            }
          },
        ),
      ),
    );

    if (_type == ServiceType.towTruck) {
      fields.addAll([
        const SizedBox(height: 20),
        _buildLabeledField(
          controller: _vehicles,
          label: 'Towing Truck Type',
          hint: 'e.g. Flatbed or Wheel-Lift',
          isRequired: true,
          icon: Icons.local_shipping_outlined,
        ),
        const SizedBox(height: 20),
        _buildLabeledField(
          controller: _plate,
          label: 'Plate Number',
          hint: 'e.g. WP CAA-9081',
          isRequired: true,
          icon: Icons.pin_outlined,
        ),
      ]);
    } else if (_type == ServiceType.mechanic) {
      fields.addAll([
        const SizedBox(height: 20),
        _buildLabeledField(
          controller: _details,
          label: 'Number of Technicians/Mechanics',
          hint: 'e.g. 2',
          isRequired: true,
          icon: Icons.people_outline,
          keyboardType: TextInputType.number,
        ),
      ]);
    } else if (_type == ServiceType.fuelDelivery) {
      fields.addAll([
        const SizedBox(height: 20),
        _buildLabeledField(
          controller: _details,
          label: 'Fuel Quantity Available',
          hint: 'e.g. 10 Liters',
          isRequired: true,
          icon: Icons.opacity_outlined,
        ),
        const SizedBox(height: 20),
        _buildLabeledField(
          controller: _vehicles,
          label: 'Vehicle Type',
          hint: 'e.g. Tanker',
          isRequired: true,
          icon: Icons.directions_car_outlined,
        ),
        const SizedBox(height: 20),
        _buildLabeledField(
          controller: _plate,
          label: 'Plate Number',
          hint: 'e.g. WP CAA-9081',
          isRequired: true,
          icon: Icons.pin_outlined,
        ),
      ]);
    }

    return fields;
  }

  Widget _buildTypeChips() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _typeOrder.map((type) {
        final isSelected = type == _type;
        return InkWell(
          onTap: () => setState(() => _type = type),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFE30613) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? const Color(0xFFE30613) : Colors.grey.shade200,
                width: 1.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE30613).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _iconFor(type),
                  size: 20,
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  _labelFor(type),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLabeledField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isRequired = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
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
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.normal),
            prefixIcon: Icon(icon, color: Colors.grey.shade500),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE30613), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }
}
