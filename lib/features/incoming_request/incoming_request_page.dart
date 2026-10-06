import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../entities/app_user.dart';
import '../../entities/service_request.dart';

const Color _brandRed = Color(0xFFE30613);
const String _pickupPinPath = 'assets/images/pickup-point.png';
const String _appPackageName = 'com.example.roadside_assitance';

/// How long the provider has to answer (never longer than the request's own
/// expiry).
const int _maxRespondSeconds = 30;

/// Full-screen "new request" page shown to a provider. Accept or Decline.
/// Closes by itself when the time runs out or when another provider takes
/// the request. Pops `true` if this provider accepted it.
class IncomingRequestPage extends StatefulWidget {
  final ServiceRequest request;

  const IncomingRequestPage({super.key, required this.request});

  @override
  State<IncomingRequestPage> createState() => _IncomingRequestPageState();
}

class _IncomingRequestPageState extends State<IncomingRequestPage> {
  Timer? _timer;
  StreamSubscription<ServiceRequest?>? _sub;

  late final int _total;
  late int _left;
  bool _busy = false;
  bool _closing = false;
  double? _distanceKm;

  ServiceRequest get _r => widget.request;
  LatLng get _pickup => LatLng(_r.pickup.latitude, _r.pickup.longitude);
  LatLng? get _dropoff => _r.dropoff == null
      ? null
      : LatLng(_r.dropoff!.latitude, _r.dropoff!.longitude);

  @override
  void initState() {
    super.initState();
    final remaining = _r.expiresAt.difference(DateTime.now()).inSeconds;
    _total = remaining.clamp(5, _maxRespondSeconds);
    _left = _total;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) _decline();
    });

    // Close if someone else takes it, or the customer cancels.
    _sub = watchRequest(_r.id).listen((latest) {
      if (!mounted || _closing || latest == null) return;
      if (latest.status != RequestStatus.pending) {
        _close(false, 'This request is no longer available');
      }
    });

    _loadDistance();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadDistance() async {
    try {
      final p =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              timeLimit: Duration(seconds: 5),
            ),
          );
      final km = const Distance().as(
        LengthUnit.Kilometer,
        LatLng(p.latitude, p.longitude),
        _pickup,
      );
      if (mounted) setState(() => _distanceKm = km.toDouble());
    } catch (_) {}
  }

  // ---------------- actions ----------------
  void _close(bool accepted, [String? message]) {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
    Navigator.of(context).pop(accepted);
  }

  void _decline() => _close(false);

  Future<void> _accept() async {
    if (_busy || _closing) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _close(false);
      return;
    }
    setState(() => _busy = true);

    AcceptResult result;
    try {
      result = await acceptRequest(requestId: _r.id, providerUid: uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not accept. Try again.')),
      );
      return;
    }
    if (!mounted) return;

    switch (result) {
      case AcceptResult.success:
        _close(true, 'Request accepted');
      case AcceptResult.alreadyTaken:
        _close(false, 'Another provider already accepted this request');
      case AcceptResult.expired:
        _close(false, 'This request has expired');
      case AcceptResult.notFound:
        _close(false, 'This request is no longer available');
    }
  }

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
    final dropoff = _dropoff;
    return FlutterMap(
      options: MapOptions(
        initialCenter: _pickup,
        initialZoom: 15,
        initialCameraFit: dropoff == null
            ? null
            : CameraFit.coordinates(
                coordinates: [_pickup, dropoff],
                padding: const EdgeInsets.fromLTRB(50, 60, 50, 70),
              ),
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _appPackageName,
        ),
        if (dropoff != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [_pickup, dropoff],
                strokeWidth: 4,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: _pickup,
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
            if (dropoff != null)
              Marker(
                point: dropoff,
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
        maxHeight: MediaQuery.of(context).size.height * 0.62,
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'New ${serviceTypeTitle(_r.serviceType)} request',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _countdownPill(),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (_left / _total).clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: Colors.grey.shade300,
                valueColor: const AlwaysStoppedAnimation(_brandRed),
              ),
            ),
            const SizedBox(height: 14),
            // Only the details scroll; the buttons stay visible.
            Flexible(child: SingleChildScrollView(child: _buildDetails())),
            const SizedBox(height: 14),
            _buildButtons(),
          ],
        ),
      ),
    );
  }

  Widget _countdownPill() {
    final m = _left ~/ 60;
    final s = (_left % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$m:$s',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildDetails() {
    final rows = <Widget>[
      _infoRow(Icons.location_on_outlined, 'Pickup', _r.pickupAddress),
      if (_r.dropoffAddress != null && _r.dropoffAddress!.isNotEmpty)
        _infoRow(Icons.flag_outlined, 'Drop-off', _r.dropoffAddress!),
      if (_distanceKm != null)
        _infoRow(
          Icons.near_me_outlined,
          'Distance to customer',
          '${_distanceKm!.toStringAsFixed(1)} km away',
        ),
      if (_r.vehicleLabel != null)
        _infoRow(Icons.directions_car_outlined, 'Vehicle', _r.vehicleLabel!),
      if (_r.liters != null)
        _infoRow(
          Icons.local_gas_station_outlined,
          'Fuel',
          '${_r.liters} L · ${_r.fuelType ?? ''}'.trim(),
        ),
      if (_r.notes.isNotEmpty)
        _infoRow(Icons.note_alt_outlined, 'Notes', _r.notes),
      _infoRow(
        Icons.payments_outlined,
        'Payment',
        'Rs: ${_r.totalAmount.toStringAsFixed(2)} · '
            '${_r.paymentMethod == 'cash' ? 'Cash in Person' : 'Card'}',
      ),
    ];
    return Column(children: rows);
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: _busy ? null : _decline,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                side: BorderSide(color: Colors.grey.shade400),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Decline',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _accept,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandRed,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Accept',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
