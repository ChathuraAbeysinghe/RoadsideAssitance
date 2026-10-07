import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../entities/app_user.dart';
import '../../entities/service_request.dart';
import '../../entities/vehicle.dart';
import 'request_searching_page.dart'; // adjust path if needed

const Color _brandRed = Color(0xFFE30613);
const Color _dropoffOrange = Color(0xFFFF8C00);
const Color _editBlue = Color(0xFF1B7F9E);

const String _cartoonTruck = 'assets/images/cartoon-truck.png';
const String _cartoonMechanic = 'assets/images/cartoon-mechanic.png';
const String _cartoonFuel = 'assets/images/cartoon-fuel.png';
const String _cartoonTire = 'assets/images/cartoon-tire.png';
const String _cartoonBattery = 'assets/images/cartoon-cables.png';
const String _noteIcon = 'assets/images/note.png';
const String _cashIcon = 'assets/images/cash.png';
const String _cardIcon = 'assets/images/card.png';

/// Review screen shown after "Confirm" on the request page.
///
/// All five services have a layout (see [_buildServiceDetails]).
enum _PaymentMethod { cash, card }

class RequestSummaryPage extends StatefulWidget {
  final ServiceType serviceType;
  final String pickupAddress;
  final LatLng pickup;

  /// Towing only (null for single-location services).
  final String? dropoffAddress;
  final LatLng? dropoff;

  /// Fuel delivery only.
  final int? liters;
  final String? fuelType;

  final List<LatLng> routePoints;
  final double? distanceKm;
  final int? durationMin;
  final Vehicle? vehicle;
  final double searchRadiusKm;

  const RequestSummaryPage({
    super.key,
    required this.serviceType,
    required this.pickupAddress,
    required this.pickup,
    this.dropoffAddress,
    this.dropoff,
    this.liters,
    this.fuelType,
    this.routePoints = const [],
    this.distanceKm,
    this.durationMin,
    this.vehicle,
    this.searchRadiusKm = 5.0,
  });

  @override
  State<RequestSummaryPage> createState() => _RequestSummaryPageState();
}

class _RequestSummaryPageState extends State<RequestSummaryPage> {
  // PLACEHOLDER pricing: replace with your real fee calculation.
  static const double _baseFee = 500; // towing
  static const double _perKm = 150; // towing
  static const double _mechanicFee = 540;
  static const double _fuelServiceFee = 340;
  static const double _fuelPricePerLiter = 400; // same for petrol & diesel
  static const double _flatTireFee = 1530;
  static const double _batteryFee = 2340;

  String _notes = '';
  _PaymentMethod _paymentMethod = _PaymentMethod.cash; // cash is the default
  bool _submitting = false;

  bool get _isFuel => widget.serviceType == ServiceType.fuelDelivery;

  double get _serviceFee => switch (widget.serviceType) {
    ServiceType.towTruck => _baseFee + _perKm * (widget.distanceKm ?? 0),
    ServiceType.mechanic => _mechanicFee,
    ServiceType.fuelDelivery => _fuelServiceFee,
    ServiceType.flatTireChange => _flatTireFee,
    ServiceType.batteryBoost => _batteryFee,
  };

  double get _fuelCost =>
      _isFuel ? (widget.liters ?? 0) * _fuelPricePerLiter : 0;

  double get _totalAmount => _serviceFee + _fuelCost;

  String _money(double v) => 'Rs: ${v.toStringAsFixed(2)}';

  String get _serviceTitle {
    switch (widget.serviceType) {
      case ServiceType.towTruck:
        return 'Tow Truck Delivery';
      case ServiceType.mechanic:
        return 'Request a Mechanic';
      case ServiceType.fuelDelivery:
        final l = widget.liters ?? 0;
        return 'Request Fuel ($l ${l == 1 ? 'Liter' : 'Liters'})';
      case ServiceType.batteryBoost:
        return 'Battery Boosting';
      case ServiceType.flatTireChange:
        return 'Flat Tire';
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // The keyboard opens over a bottom sheet (which handles its own
      // insets). Without this, the page behind it gets re-laid out on every
      // keyboard animation frame, which causes lag.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.black87, size: 30),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Request Summary',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Only the details scroll; the Confirm button stays fixed.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: _buildServiceDetails(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: _buildConfirmButton(),
            ),
          ],
        ),
      ),
    );
  }

  /// Each service gets its own summary layout here.
  Widget _buildServiceDetails() {
    switch (widget.serviceType) {
      case ServiceType.towTruck:
        return _buildTowingSummary();
      case ServiceType.mechanic:
      case ServiceType.fuelDelivery:
      case ServiceType.flatTireChange:
      case ServiceType.batteryBoost:
        return _buildSingleLocationSummary();
    }
  }

  // ---------------- Towing ----------------
  Widget _buildTowingSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _locationHeader(),
        const SizedBox(height: 10),
        _card(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Column(
                children: [
                  // Pickup: red dot (same as the map).
                  const _LocationDot(color: _brandRed),
                  ...List.generate(
                    4,
                    (_) => Container(
                      width: 1.5,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: Colors.black87,
                    ),
                  ),
                  // Drop-off: orange dot (same as the map).
                  const _LocationDot(color: _dropoffOrange),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _addressText(widget.pickupAddress),
                    Divider(height: 1, color: Colors.grey.shade400),
                    _addressText(widget.dropoffAddress ?? ''),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _sectionLabel('Service Details'),
        const SizedBox(height: 10),
        _serviceDetailsCard(
          title: _serviceTitle,
          subtitle: widget.vehicle?.displayLabel ?? 'No vehicle selected',
          imagePath: _cartoonTruck,
          fallbackIcon: Icons.local_shipping,
        ),
        const SizedBox(height: 12),
        _buildNotesButton(),
        const SizedBox(height: 20),
        ..._paymentSections(),
      ],
    );
  }

  // --- Single-location services (mechanic, fuel, flat tire, battery) ---
  Widget _buildSingleLocationSummary() {
    final String subtitle;
    final String image;
    final IconData fallback;
    switch (widget.serviceType) {
      case ServiceType.fuelDelivery:
        subtitle = widget.fuelType ?? '';
        image = _cartoonFuel;
        fallback = Icons.local_gas_station;
      case ServiceType.flatTireChange:
        subtitle = 'Air it up or replace it with your Spare';
        image = _cartoonTire;
        fallback = Icons.tire_repair;
      case ServiceType.batteryBoost:
        subtitle = 'Jump start';
        image = _cartoonBattery;
        fallback = Icons.battery_charging_full;
      case ServiceType.mechanic:
      case ServiceType.towTruck:
        subtitle = 'On-Site Repair';
        image = _cartoonMechanic;
        fallback = Icons.build;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _locationHeader(),
        const SizedBox(height: 10),
        _card(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              const _LocationDot(color: _brandRed),
              const SizedBox(width: 16),
              Expanded(child: _addressText(widget.pickupAddress)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _sectionLabel('Service Details'),
        const SizedBox(height: 10),
        _serviceDetailsCard(
          title: _serviceTitle,
          subtitle: subtitle,
          imagePath: image,
          fallbackIcon: fallback,
        ),
        const SizedBox(height: 12),
        _buildNotesButton(),
        const SizedBox(height: 20),
        ..._paymentSections(),
      ],
    );
  }

  // ---------------- Shared sections ----------------
  Widget _locationHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _sectionLabel('Delivery Location'),
        GestureDetector(
          // Go back to the request page to change locations.
          onTap: () => Navigator.of(context).pop(),
          child: const Text(
            'Edit',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _editBlue,
            ),
          ),
        ),
      ],
    );
  }

  Widget _serviceDetailsCard({
    required String title,
    required String subtitle,
    required String imagePath,
    required IconData fallbackIcon,
  }) {
    return _card(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Image.asset(
            imagePath,
            width: 64,
            height: 52,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(fallbackIcon, size: 48),
          ),
        ],
      ),
    );
  }

  /// Payment Details + Payment Method sections.
  List<Widget> _paymentSections() {
    return [
      _sectionLabel('Payment Details'),
      const SizedBox(height: 10),
      _card(
        child: Column(
          children: [
            _paymentRow('Service Fee', _money(_serviceFee), bold: false),
            if (_isFuel) ...[
              const SizedBox(height: 8),
              _paymentRow('Fuel Cost', _money(_fuelCost), bold: false),
            ],
            const SizedBox(height: 8),
            _paymentRow('Total Amount', _money(_totalAmount), bold: true),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _sectionLabel('Payment Method'),
      const SizedBox(height: 10),
      InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _onPickPaymentMethod,
        child: _card(
          child: Row(
            children: [
              _methodIcon(_paymentMethod, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _methodLabel(_paymentMethod),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
            ],
          ),
        ),
      ),
    ];
  }

  // ---------------- Pieces ----------------
  String _methodLabel(_PaymentMethod m) => switch (m) {
    _PaymentMethod.cash => 'Cash in Person',
    _PaymentMethod.card => 'Card Payment',
  };

  Widget _methodIcon(_PaymentMethod m, {double size = 28}) {
    final isCash = m == _PaymentMethod.cash;
    return Image.asset(
      isCash ? _cashIcon : _cardIcon,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        isCash ? Icons.payments_outlined : Icons.credit_card,
        size: size,
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
  );

  Widget _card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 12,
    ),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: child,
    );
  }

  Widget _addressText(String text) {
    // Same look as the text fields on the request page: one line, 14pt.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }

  Widget _paymentRow(String label, String value, {required bool bold}) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: bold ? Colors.black : Colors.grey.shade600,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }

  Widget _buildNotesButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _onAddNotes,
      child: _card(
        child: Row(
          children: [
            Image.asset(
              _noteIcon,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.edit_note, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _notes.isEmpty ? 'Add Notes' : _notes,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _submitting ? null : _onConfirm,
        style: ElevatedButton.styleFrom(
          backgroundColor: _brandRed,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _brandRed.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: _submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Confirm',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
      ),
    );
  }

  // ---------------- Actions ----------------
  Future<void> _onPickPaymentMethod() async {
    final picked = await showModalBottomSheet<_PaymentMethod>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Payment Method',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: _methodIcon(_PaymentMethod.cash, size: 32),
              title: Text(_methodLabel(_PaymentMethod.cash)),
              trailing: _paymentMethod == _PaymentMethod.cash
                  ? const Icon(Icons.check_circle, color: _brandRed)
                  : null,
              onTap: () => Navigator.of(ctx).pop(_PaymentMethod.cash),
            ),
            // Card payments aren't available yet: shown greyed out and
            // not selectable.
            Opacity(
              opacity: 0.5,
              child: ListTile(
                enabled: false,
                leading: _methodIcon(_PaymentMethod.card, size: 32),
                title: Text(_methodLabel(_PaymentMethod.card)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Coming soon',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _paymentMethod = picked);
  }

  Future<void> _onAddNotes() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true, // lets the sheet rise above the keyboard
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _NotesSheet(initial: _notes),
    );
    if (result != null && mounted) setState(() => _notes = result);
  }

  /// Creates the request in Firestore, then opens the searching page.
  Future<void> _onConfirm() async {
    if (_submitting) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please sign in again')));
      return;
    }

    setState(() => _submitting = true);
    try {
      final dropoff = widget.dropoff;
      final request = ServiceRequest(
        customerUid: user.uid,
        serviceType: widget.serviceType,
        pickup: GeoLocation(
          latitude: widget.pickup.latitude,
          longitude: widget.pickup.longitude,
        ),
        pickupAddress: widget.pickupAddress,
        dropoff: dropoff == null
            ? null
            : GeoLocation(
                latitude: dropoff.latitude,
                longitude: dropoff.longitude,
              ),
        dropoffAddress: widget.dropoffAddress,
        vehicle: widget.vehicle?.toMap(), // needs Vehicle.toMap()
        notes: _notes,
        liters: widget.liters,
        fuelType: widget.fuelType,
        distanceKm: widget.distanceKm,
        durationMin: widget.durationMin,
        serviceFee: _serviceFee,
        fuelCost: _fuelCost,
        totalAmount: _totalAmount,
        paymentMethod: _paymentMethod.name,
        searchRadiusKm: widget.searchRadiusKm,
        expiresAt: DateTime.now().add(kSearchTimeout),
      );

      final requestId = await createServiceRequest(request);
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              RequestSearchingPage(requestId: requestId, pickup: widget.pickup),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send the request. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

/// Notes bottom sheet. It owns its own controller and disposes it in
/// [dispose], which only runs after the sheet has finished closing.
class _NotesSheet extends StatefulWidget {
  final String initial;
  const _NotesSheet({required this.initial});

  @override
  State<_NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends State<_NotesSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // Keep the content above the keyboard.
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Add Notes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 4,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: 'Anything the driver should know?',
                hintStyle: TextStyle(color: Colors.grey.shade500),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade400),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.black, width: 1.6),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_controller.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brandRed,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ring-style dot (same look as the confirmed-point dots on the map),
/// used as the location icon next to the address text.
class _LocationDot extends StatelessWidget {
  final Color color;
  final double size;

  const _LocationDot({required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Center(
        child: Container(
          width: size * 0.375,
          height: size * 0.375,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
