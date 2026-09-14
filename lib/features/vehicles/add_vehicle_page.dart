import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../entities/vehicle.dart';

/// Form for adding a new vehicle, or editing an existing one when
/// [vehicleToEdit] is passed. Matches the "Add Vehicle" reference design:
/// vehicle type chips, make/model fields, plate code/number fields, and a
/// Confirm button that writes the Vehicle document to Firestore.
class AddVehiclePage extends StatefulWidget {
  final String ownerUid;

  /// When non-null, the page opens in edit mode: fields are pre-filled
  /// from this vehicle, the header/button read "Edit Vehicle" / "Save",
  /// and Confirm updates this vehicle's existing doc instead of creating
  /// a new one.
  final Vehicle? vehicleToEdit;

  const AddVehiclePage({super.key, required this.ownerUid, this.vehicleToEdit});

  bool get _isEditing => vehicleToEdit != null;

  @override
  State<AddVehiclePage> createState() => _AddVehiclePageState();
}

class _AddVehiclePageState extends State<AddVehiclePage> {
  late VehicleType _selectedType;

  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _plateCodeController = TextEditingController();
  final _plateNumberController = TextEditingController();

  bool _isSaving = false;

  static const _typeOrder = [
    VehicleType.car,
    VehicleType.motorbike,
    VehicleType.bus,
    VehicleType.truck,
    VehicleType.van,
    VehicleType.threeWheeler,
  ];

  String _labelFor(VehicleType type) => switch (type) {
    VehicleType.car => 'Car',
    VehicleType.motorbike => 'Motorcycle',
    VehicleType.bus => 'Bus',
    VehicleType.truck => 'Truck',
    VehicleType.van => 'Van',
    VehicleType.threeWheeler => 'Three Wheeler',
  };

  @override
  void initState() {
    super.initState();

    final existing = widget.vehicleToEdit;
    _selectedType = existing?.vehicleType ?? VehicleType.car;

    if (existing != null) {
      _makeController.text = existing.make;
      _modelController.text = existing.model;

      // Plate is stored as a single "$plateCode - $plateNumber" string
      // (see _onConfirm), so split it back apart for the two fields.
      // Falls back to putting the whole thing in plateNumber if it
      // doesn't match the expected "CODE - NUMBER" shape (e.g. legacy
      // data saved a different way).
      final parts = existing.plateNumber.split(' - ');
      if (parts.length == 2) {
        _plateCodeController.text = parts[0];
        _plateNumberController.text = parts[1];
      } else {
        _plateNumberController.text = existing.plateNumber;
      }
    }
  }

  @override
  void dispose() {
    _makeController.dispose();
    _modelController.dispose();
    _plateCodeController.dispose();
    _plateNumberController.dispose();
    super.dispose();
  }

  Future<void> _onConfirm() async {
    final make = _makeController.text.trim();
    final model = _modelController.text.trim();
    final plateCode = _plateCodeController.text.trim();
    final plateNumber = _plateNumberController.text.trim();

    if (make.isEmpty ||
        model.isEmpty ||
        plateCode.isEmpty ||
        plateNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final vehiclesRef = FirebaseFirestore.instance.collection('vehicles');
      final existing = widget.vehicleToEdit;

      final docRef = existing != null
          ? vehiclesRef.doc(existing.id)
          : vehiclesRef.doc();

      final vehicle = Vehicle(
        id: docRef.id,
        ownerUid: widget.ownerUid,
        vehicleType: _selectedType,
        make: make,
        model: model,
        plateNumber: '$plateCode - $plateNumber',
        // Preserve fields the form doesn't touch when editing (color,
        // photoPath) rather than wiping them back to defaults.
        color: existing?.color ?? '',
        photoPath: existing?.photoPath ?? '',
      );

      if (existing != null) {
        await docRef.update(vehicle.toMap());
      } else {
        await docRef.set(vehicle.toMap());

        // If this is the user's first vehicle, set it as their active
        // one. Only relevant when creating — an edit never changes
        // which vehicle is active.
        final ownedVehicles = await vehiclesRef
            .where('ownerUid', isEqualTo: widget.ownerUid)
            .limit(2)
            .get();
        if (ownedVehicles.docs.length <= 1) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.ownerUid)
              .update({'activeVehicleId': docRef.id});
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(vehicle);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget._isEditing
                ? 'Failed to save changes. Try again.'
                : 'Failed to save vehicle. Try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
                      'Vehicle Type',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildTypeChips(),
                    const SizedBox(height: 28),
                    const Text(
                      'Vehicle Details',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildLabeledField(
                      controller: _makeController,
                      label: 'Make',
                      hint: 'e.g. Toyota',
                    ),
                    const SizedBox(height: 14),
                    _buildLabeledField(
                      controller: _modelController,
                      label: 'Model',
                      hint: 'e.g. Aqua',
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Plate',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildLabeledField(
                      controller: _plateCodeController,
                      label: 'Plate Code',
                      hint: 'e.g. TB',
                    ),
                    const SizedBox(height: 14),
                    _buildLabeledField(
                      controller: _plateNumberController,
                      label: 'Plate Number',
                      hint: 'e.g. 5342',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 44),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _onConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE30613),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                widget._isEditing ? 'Save' : 'Confirm',
                                style: const TextStyle(
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
            widget._isEditing ? 'Edit Vehicle' : 'Add Vehicle',
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
          final isSelected = type == _selectedType;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              label: Text(_labelFor(type)),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedType = type),
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
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        label: RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            children: [
              TextSpan(text: label),
              const TextSpan(
                text: ' *',
                style: TextStyle(color: Color(0xFFE30613)),
              ),
            ],
          ),
        ),
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
