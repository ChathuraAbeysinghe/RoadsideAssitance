import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../entities/app_user.dart';
import '../../entities/vehicle.dart';

const Color _brandRed = Color(0xFFE30613);
const Color _editBlue = Color(0xFF1B7F9E);

const String _truckPinIcon = 'assets/images/icon-towtruck.png';
const String _cartoonTruck = 'assets/images/cartoon-truck.png';
const String _noteIcon = 'assets/images/note.png';
const String _cashIcon = 'assets/images/cash.png';
const String _cardIcon = 'assets/images/card.png';
const String _pickupPinPath = 'assets/images/pickup-point.png';

const String _appPackageName = 'com.example.roadside_assitance';

/// Review screen shown after "Confirm" on the request page.
///
/// Only the towing layout is built for now. Other services will get their
/// own details sections later (see [_buildServiceDetails]).
enum _PaymentMethod { cash, card }

class RequestSummaryPage extends StatefulWidget {
  final ServiceType serviceType;
  final String pickupAddress;
  final String dropoffAddress;
  final LatLng pickup;
  final LatLng dropoff;
  final List<LatLng> routePoints;
  final double? distanceKm;
  final int? durationMin;
  final Vehicle? vehicle;

  const RequestSummaryPage({
    super.key,
    required this.serviceType,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.pickup,
    required this.dropoff,
    this.routePoints = const [],
    this.distanceKm,
    this.durationMin,
    this.vehicle,
  });

  @override
  State<RequestSummaryPage> createState() => _RequestSummaryPageState();
}

class _RequestSummaryPageState extends State<RequestSummaryPage> {
  // PLACEHOLDER pricing: replace with your real fee calculation.
  static const double _baseFee = 500;
  static const double _perKm = 150;

  String _notes = '';
  _PaymentMethod _paymentMethod = _PaymentMethod.cash; // cash is the default

  double get _serviceFee => _baseFee + _perKm * (widget.distanceKm ?? 0);
  double get _totalAmount => _serviceFee;

  String _money(double v) => 'Rs: ${v.toStringAsFixed(2)}';

  String get _serviceTitle => switch (widget.serviceType) {
    ServiceType.towTruck => 'Tow Truck Delivery',
    ServiceType.mechanic => 'Mechanic Service',
    ServiceType.batteryBoost => 'Battery Boosting',
    ServiceType.flatTireChange => 'Flat Tire Change',
    ServiceType.fuelDelivery => 'Fuel Delivery',
  };

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: -30,
                  child: _buildMap(),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, top: 8),
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).pop(),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.chevron_left,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // OpenStreetMap requires visible attribution.
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      margin: const EdgeInsets.only(top: 4, right: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      color: Colors.white.withValues(alpha: 0.75),
                      child: const Text(
                        '© OpenStreetMap contributors',
                        style: TextStyle(fontSize: 10, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildSheet(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final fitPoints = widget.routePoints.isNotEmpty
        ? widget.routePoints
        : [widget.pickup, widget.dropoff];

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: fitPoints,
          padding: const EdgeInsets.fromLTRB(50, 90, 50, 60),
        ),
        // Read-only preview of the route.
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _appPackageName,
        ),
        if (widget.routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.routePoints,
                strokeWidth: 5,
                color: Colors.black,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: widget.pickup,
              width: 40,
              height: 48,
              alignment: Alignment.topCenter,
              child: Image.asset(
                _pickupPinPath,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.location_on,
                  color: Colors.green,
                  size: 40,
                ),
              ),
            ),
            Marker(
              point: widget.dropoff,
              width: 40,
              height: 40,
              alignment: Alignment.topCenter,
              child: const Icon(
                Icons.location_on,
                color: Colors.black,
                size: 40,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSheet() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomInset),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 15,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Center(
              child: Text(
                'Request Summary',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 18),
            // Only the details scroll; header and Confirm stay fixed.
            Flexible(
              child: SingleChildScrollView(child: _buildServiceDetails()),
            ),
            const SizedBox(height: 16),
            _buildConfirmButton(),
          ],
        ),
      ),
    );
  }

  /// Each service gets its own summary layout here. Towing only for now.
  Widget _buildServiceDetails() {
    switch (widget.serviceType) {
      case ServiceType.towTruck:
        return _buildTowingSummary();
      case ServiceType.mechanic:
      case ServiceType.batteryBoost:
      case ServiceType.flatTireChange:
      case ServiceType.fuelDelivery:
        // TODO: summary layouts for the other services.
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('Summary for this service is coming soon')),
        );
    }
  }

  // ---------------- Towing ----------------
  Widget _buildTowingSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
        ),
        const SizedBox(height: 10),
        _card(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Column(
                children: [
                  Image.asset(
                    _truckPinIcon,
                    width: 24,
                    height: 24,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.local_shipping_outlined, size: 24),
                  ),
                  ...List.generate(
                    4,
                    (_) => Container(
                      width: 1.5,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: Colors.black87,
                    ),
                  ),
                  const Icon(Icons.location_on_outlined, size: 24),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    _addressText(widget.pickupAddress),
                    Divider(height: 1, color: Colors.grey.shade400),
                    _addressText(widget.dropoffAddress),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _sectionLabel('Service Details'),
        const SizedBox(height: 10),
        _card(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _serviceTitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.vehicle?.displayLabel ?? 'No vehicle selected',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Image.asset(
                _cartoonTruck,
                width: 64,
                height: 52,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.local_shipping, size: 48),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildNotesButton(),
        const SizedBox(height: 20),
        _sectionLabel('Payment Details'),
        const SizedBox(height: 10),
        _card(
          child: Column(
            children: [
              _paymentRow('Service Fee', _money(_serviceFee), bold: false),
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
      ],
    );
  }

  // ---------------- Pieces ----------------
  String _methodLabel(_PaymentMethod m) => switch (m) {
    _PaymentMethod.cash => 'Cash on Delivery',
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
        onPressed: _onConfirm,
        style: ElevatedButton.styleFrom(
          backgroundColor: _brandRed,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: const Text(
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

  void _onConfirm() {
    // TODO: create the service request (service type, pickup/dropoff,
    // addresses, vehicle, distance, duration, notes, fee, payment method).
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Request submission coming soon')),
      );
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
            SizedBox(
              width: double.infinity,
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
