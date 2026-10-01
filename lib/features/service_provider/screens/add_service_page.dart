import 'package:flutter/material.dart';

import '../../../entities/app_user.dart';
import '../models/provider_service.dart';
import '../services/provider_repository.dart';

class AddServicePage extends StatefulWidget {
  final String uid;
  const AddServicePage({super.key, required this.uid});
  @override
  State<AddServicePage> createState() => _AddServicePageState();
}

class _AddServicePageState extends State<AddServicePage> {
  ServiceType _type = ServiceType.towTruck;
  bool _saving = false;
  final _name = TextEditingController();
  final _vehicles = TextEditingController();
  final _plate = TextEditingController();
  final _location = TextEditingController();
  final _details = TextEditingController();

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
        _plate.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your name and plate number.')),
      );
      return;
    }
    setState(() => _saving = true);
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
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Add Service',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      centerTitle: true,
      leading: const BackButton(),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const Text(
          'Service Type',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: ServiceType.values
              .map(
                (type) => ChoiceChip(
                  label: Text(_label(type)),
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                  selectedColor: Colors.black,
                  labelStyle: TextStyle(
                    color: _type == type ? Colors.white : Colors.black,
                    fontSize: 16,
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 28),
        const Text(
          'Details',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        _field(_location, 'Location'),
        _field(_name, 'Your Name *'),
        _field(_vehicles, 'Truck Types'),
        _field(_plate, 'Plate NO *'),
        _field(_details, 'Details *', maxLines: 3),
        const SizedBox(height: 20),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
            ),
            child: _saving
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
                    'Confirm',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    ),
  );

  Widget _field(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
      ),
    ),
  );
}

String _label(ServiceType type) => switch (type) {
  ServiceType.towTruck => 'Vehicle Tow',
  ServiceType.mechanic => 'Mechanic',
  ServiceType.fuelDelivery => 'Fuel Delivery',
  ServiceType.flatTireChange => 'Flat Tire',
  ServiceType.batteryBoost => 'Battery Boost',
};
