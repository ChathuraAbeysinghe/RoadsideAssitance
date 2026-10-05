import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../entities/app_user.dart';
import '../../entities/service_request.dart';
import '../../entities/vehicle.dart';
import '../_share/navbar/app_bottom_nav_bar.dart';

const Color _brandRed = Color(0xFFE30613);
const Color _green = Color(0xFF16A34A);
const Color _blue = Color(0xFF2563EB);
const Color _amber = Color(0xFFF59E0B);

// ============================================================
// Status helpers
// ============================================================

/// A request that is still `pending` in Firestore but past its expiry time
/// is shown as expired (the customer app may have been closed before it
/// could mark it).
RequestStatus _effectiveStatus(ServiceRequest r) {
  if (r.status == RequestStatus.pending &&
      r.expiresAt.isBefore(DateTime.now())) {
    return RequestStatus.expired;
  }
  return r.status;
}

bool _isOngoing(RequestStatus s) => switch (s) {
  RequestStatus.pending ||
  RequestStatus.accepted ||
  RequestStatus.onTheWay ||
  RequestStatus.arrived ||
  RequestStatus.inProgress => true,
  _ => false,
};

String _statusLabel(RequestStatus s) => switch (s) {
  RequestStatus.pending => 'Searching',
  RequestStatus.accepted => 'Accepted',
  RequestStatus.onTheWay => 'On the way',
  RequestStatus.arrived => 'Arrived',
  RequestStatus.inProgress => 'In progress',
  RequestStatus.completed => 'Completed',
  RequestStatus.cancelled => 'Cancelled',
  RequestStatus.expired => 'Expired',
};

Color _statusColor(RequestStatus s) => switch (s) {
  RequestStatus.pending => _amber,
  RequestStatus.accepted ||
  RequestStatus.onTheWay ||
  RequestStatus.arrived ||
  RequestStatus.inProgress => _blue,
  RequestStatus.completed => _green,
  RequestStatus.cancelled => _brandRed,
  RequestStatus.expired => Colors.grey.shade600,
};

// ============================================================
// Formatting helpers
// ============================================================

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatDate(DateTime? d) {
  if (d == null) return 'Just now';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  return '${d.day} ${_months[d.month - 1]} ${d.year} · $h:$m $ampm';
}

const List<String> _monthsLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// e.g. "29 September 2026"
String _formatDateLong(DateTime? d) =>
    d == null ? 'Just now' : '${d.day} ${_monthsLong[d.month - 1]} ${d.year}';

/// e.g. "02:14 AM"
String _formatTime(DateTime? d) {
  if (d == null) return '';
  final h = (d.hour % 12 == 0 ? 12 : d.hour % 12).toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String _money(double v) {
  final parts = v.toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return 'LKR $whole.${parts[1]}';
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _serviceIconAsset(ServiceType t) => switch (t) {
  ServiceType.mechanic => 'assets/images/cartoon-mechanic.png',
  ServiceType.towTruck => 'assets/images/cartoon-truck.png',
  ServiceType.fuelDelivery => 'assets/images/cartoon-fuel.png',
  ServiceType.flatTireChange => 'assets/images/cartoon-tire.png',
  ServiceType.batteryBoost => 'assets/images/cartoon-cables.png',
};

IconData _serviceFallbackIcon(ServiceType t) => switch (t) {
  ServiceType.mechanic => Icons.build_rounded,
  ServiceType.towTruck => Icons.local_shipping_rounded,
  ServiceType.fuelDelivery => Icons.local_gas_station_rounded,
  ServiceType.flatTireChange => Icons.tire_repair_rounded,
  ServiceType.batteryBoost => Icons.battery_charging_full_rounded,
};

// ============================================================
// Page
// ============================================================

/// All of the logged-in driver's requests, split into
/// Ongoing / Completed / Cancelled (expired requests are listed under
/// Cancelled with an "Expired" badge).
class RequestsPage extends StatefulWidget {
  final UserType userType;

  const RequestsPage({super.key, required this.userType});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  late final Stream<List<ServiceRequest>> _stream = _watchMine();

  /// Only filters by customerUid (no orderBy) so no composite index is
  /// needed; sorting newest-first happens on the device.
  Stream<List<ServiceRequest>> _watchMine() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const []);

    return FirebaseFirestore.instance
        .collection('service_requests')
        .where('customerUid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => ServiceRequest.fromMap(d.id, d.data()))
              .toList();
          final now = DateTime.now();
          list.sort(
            (a, b) => (b.createdAt ?? now).compareTo(a.createdAt ?? now),
          );
          return list;
        });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          title: const Text(
            'Requests',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          bottom: TabBar(
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.black,
            indicatorWeight: 2.5,
            dividerColor: Colors.grey.shade200,
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            tabs: const [
              Tab(text: 'Ongoing'),
              Tab(text: 'Completed'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        body: StreamBuilder<List<ServiceRequest>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _buildError();
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: _brandRed),
              );
            }

            final all = snapshot.data!;
            final ongoing = <ServiceRequest>[];
            final completed = <ServiceRequest>[];
            final cancelled = <ServiceRequest>[];
            for (final r in all) {
              final s = _effectiveStatus(r);
              if (_isOngoing(s)) {
                ongoing.add(r);
              } else if (s == RequestStatus.completed) {
                completed.add(r);
              } else {
                cancelled.add(r);
              }
            }

            return TabBarView(
              children: [
                _RequestList(
                  requests: ongoing,
                  emptyImage: 'assets/images/ongoing.png',
                  emptyIcon: Icons.hourglass_empty_rounded,
                  emptyTitle: 'No ongoing requests',
                  emptyMessage:
                      'Requests that are being processed will appear here.',
                ),
                _RequestList(
                  requests: completed,
                  emptyImage: 'assets/images/complete.png',
                  emptyIcon: Icons.task_alt_rounded,
                  emptyTitle: 'No completed requests',
                  emptyMessage: 'Finished requests will appear here.',
                ),
                _RequestList(
                  requests: cancelled,
                  emptyImage: 'assets/images/cancelled.png',
                  emptyIcon: Icons.cancel_outlined,
                  emptyTitle: 'No cancelled requests',
                  emptyMessage:
                      'Cancelled or expired requests will appear here.',
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: AppBottomNavBar(
          userType: widget.userType,
          activeIndex: 1, // "Requests" is the 2nd tab
        ),
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
            Icon(Icons.error_outline, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'Could not load your requests.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// List + empty state
// ============================================================

class _RequestList extends StatelessWidget {
  final List<ServiceRequest> requests;
  final String emptyImage;
  final IconData emptyIcon; // fallback if the image asset is missing
  final String emptyTitle;
  final String emptyMessage;

  const _RequestList({
    required this.requests,
    required this.emptyImage,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                emptyImage,
                height: 140,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(emptyIcon, size: 56, color: Colors.grey.shade300),
              ),
              const SizedBox(height: 14),
              Text(
                emptyTitle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _RequestCard(
        request: requests[i],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RequestDetailsPage(request: requests[i]),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Card
// ============================================================

class _ServiceIcon extends StatelessWidget {
  final ServiceType type;
  final double size;

  const _ServiceIcon(this.type, {this.size = 40});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        _serviceIconAsset(type),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          _serviceFallbackIcon(type),
          size: size * 0.7,
          color: Colors.black87,
        ),
      ),
    );
  }
}

const Color _pickupDot = Color(0xFF5C6BC0);
const Color _dropoffDot = Color(0xFFF57C00);

class _RouteDot extends StatelessWidget {
  final String asset;
  final Color fallbackColor;

  const _RouteDot({required this.asset, required this.fallbackColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        // Plain coloured dot if the image asset is missing.
        errorBuilder: (context, error, stackTrace) => Container(
          decoration: BoxDecoration(
            color: fallbackColor,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical dotted line that fills the height it is given, with the dots
/// centred both horizontally and vertically in that space.
class _DottedLine extends StatelessWidget {
  const _DottedLine();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _DottedLinePainter(Colors.grey.shade400));
  }
}

class _DottedLinePainter extends CustomPainter {
  final Color color;

  const _DottedLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 6.0; // distance between dot centres
    const margin = 4.0; // breathing room above/below the line
    final usable = size.height - margin * 2;
    if (usable < 0) return;

    final count = (usable / gap).floor() + 1;
    final span = (count - 1) * gap;
    final startY = (size.height - span) / 2;
    final paint = Paint()..color = color;

    for (var i = 0; i < count; i++) {
      canvas.drawCircle(Offset(size.width / 2, startY + i * gap), 1.2, paint);
    }
  }

  @override
  bool shouldRepaint(_DottedLinePainter old) => old.color != color;
}

class _RequestCard extends StatelessWidget {
  final ServiceRequest request;
  final VoidCallback onTap;

  const _RequestCard({required this.request, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final r = request;
    final status = _effectiveStatus(r);
    final vehicle = r.vehicleLabel;
    final hasDropoff = r.dropoffAddress != null && r.dropoffAddress!.isNotEmpty;
    final isTowing = r.serviceType == ServiceType.towTruck;

    final tripInfo = [
      if (r.distanceKm != null) '${r.distanceKm!.toStringAsFixed(1)} km',
      if (r.durationMin != null) '${r.durationMin} min',
    ].join(' · ');

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      shadowColor: Colors.black,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Header: service + date/time ----
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ServiceIcon(r.serviceType, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        serviceTypeTitle(r.serviceType),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatDateLong(r.createdAt),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(r.createdAt),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (vehicle != null && vehicle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'For $vehicle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: Colors.grey.shade800),
                ),
              ],
              const SizedBox(height: 14),
              Divider(height: 1, color: Colors.grey.shade200),

              // ---- Status ----
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _statusColor(status),
                  ),
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),

              // ---- Route ----
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Marker + dotted line running down to the next marker.
                    SizedBox(
                      width: 20,
                      child: Column(
                        children: [
                          // Towing starts at a pickup point; every other service
                          // happens at the customer's location (drop-off icon).
                          _RouteDot(
                            asset: isTowing
                                ? 'assets/images/pickup-point.png'
                                : 'assets/images/dropoff-point.png',
                            fallbackColor: isTowing ? _pickupDot : _dropoffDot,
                          ),
                          if (hasDropoff) const Expanded(child: _DottedLine()),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: hasDropoff ? 14 : 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.pickupAddress.isEmpty
                                  ? 'Pickup location'
                                  : r.pickupAddress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                height: 1.3,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatTime(r.createdAt),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasDropoff)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _RouteDot(
                      asset: 'assets/images/dropoff-point.png',
                      fallbackColor: _dropoffDot,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.dropoffAddress!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.3,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          if (tripInfo.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              tripInfo,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Divider(height: 1, color: Colors.grey.shade200),

              // ---- Footer: details + total ----
              const SizedBox(height: 14),
              Row(
                children: [
                  const Text(
                    'Details',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1E7CC1),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _money(r.totalAmount),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (r.paymentMethod == 'cash')
                    Image.asset(
                      'assets/images/cash.png',
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.payments_rounded,
                        size: 28,
                        color: _green,
                      ),
                    )
                  else
                    const Icon(
                      Icons.credit_card_rounded,
                      size: 28,
                      color: _green,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Request details / receipt page
// ============================================================

class _ProviderInfo {
  final AppUser user;
  final Vehicle? vehicle;

  const _ProviderInfo(this.user, this.vehicle);
}

String _vehicleImageAsset(VehicleType t) => switch (t) {
  VehicleType.car => 'assets/images/vehicle-car.png',
  VehicleType.van => 'assets/images/vehicle-van.png',
  VehicleType.motorbike => 'assets/images/vehicle-bike.png',
  VehicleType.threeWheeler => 'assets/images/vehicle-threewheel.png',
  VehicleType.truck => 'assets/images/vehicle-truck.png',
  VehicleType.bus => 'assets/images/vehicle-bus.png',
  VehicleType.towtruck => 'assets/images/vehicle-towtruck.png',
};

IconData _vehicleFallbackIcon(VehicleType t) => switch (t) {
  VehicleType.car => Icons.directions_car_rounded,
  VehicleType.van => Icons.airport_shuttle_rounded,
  VehicleType.motorbike => Icons.two_wheeler_rounded,
  VehicleType.threeWheeler => Icons.electric_rickshaw_rounded,
  VehicleType.truck => Icons.local_shipping_rounded,
  VehicleType.bus => Icons.directions_bus_rounded,
  VehicleType.towtruck => Icons.local_shipping_rounded,
};

String _providerRole(ServiceType t) => switch (t) {
  ServiceType.towTruck => 'Tow truck operator',
  ServiceType.mechanic => 'Mechanic',
  ServiceType.fuelDelivery => 'Fuel delivery provider',
  ServiceType.flatTireChange => 'Tire technician',
  ServiceType.batteryBoost => 'Battery boost technician',
};

String _formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  String unit(int n, String one, String many) => '$n ${n == 1 ? one : many}';
  if (h == 0) return unit(m, 'minute', 'minutes');
  if (m == 0) return unit(h, 'hour', 'hours');
  return '${unit(h, 'hour', 'hours')} ${unit(m, 'minute', 'minutes')}';
}

/// +94712345678 -> +94 71 234 5678 (display only).
String _formatPhone(String raw) {
  final m = RegExp(r'^\+94(\d{2})(\d{3})(\d{4})$')
      .firstMatch(raw.replaceAll(' ', ''));
  if (m == null) return raw;
  return '+94 ${m[1]} ${m[2]} ${m[3]}';
}

/// Receipt for a single request: provider, vehicle, route and fare.
/// Listens to the request so the status updates live while it is ongoing.
class RequestDetailsPage extends StatefulWidget {
  final ServiceRequest request;

  const RequestDetailsPage({super.key, required this.request});

  @override
  State<RequestDetailsPage> createState() => _RequestDetailsPageState();
}

class _RequestDetailsPageState extends State<RequestDetailsPage> {
  late final Stream<ServiceRequest?> _stream = watchRequest(widget.request.id);

  String? _providerUid;
  Future<_ProviderInfo?>? _providerFuture;

  /// Loads the provider's profile and their active vehicle (falls back to
  /// their first vehicle). Cached per provider uid.
  Future<_ProviderInfo?> _providerFor(String uid) {
    if (uid != _providerUid || _providerFuture == null) {
      _providerUid = uid;
      _providerFuture = _loadProvider(uid);
    }
    return _providerFuture!;
  }

  Future<_ProviderInfo?> _loadProvider(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = snap.data();
      if (data == null) return null;

      final user = userFromMap(uid, data);

      Vehicle? vehicle;
      try {
        final vehicles = await fetchVehiclesForUser(uid);
        final activeId = data['activeVehicleId'] as String?;
        if (vehicles.isNotEmpty) {
          vehicle = vehicles.firstWhere(
            (v) => v.id == activeId,
            orElse: () => vehicles.first,
          );
        }
      } catch (_) {}

      return _ProviderInfo(user, vehicle);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: StreamBuilder<ServiceRequest?>(
          stream: _stream,
          initialData: widget.request,
          builder: (context, snapshot) {
            final r = snapshot.data ?? widget.request;
            final providerUid = r.providerUid;

            return FutureBuilder<_ProviderInfo?>(
              future: providerUid == null ? null : _providerFor(providerUid),
              builder: (context, providerSnap) =>
                  _buildContent(r, providerSnap.data),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(ServiceRequest r, _ProviderInfo? provider) {
    final status = _effectiveStatus(r);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
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
        const SizedBox(height: 12),
        Text(
          'REQUEST ID-${r.id.length > 6 ? r.id.substring(0, 6).toUpperCase() : r.id.toUpperCase()}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        if (provider != null) ...[
          const SizedBox(height: 4),
          Text(
            '${provider.user.name} ${_formatPhone(provider.user.phoneNumber)}'
                .trim(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
            ),
          ),
        ],
        const SizedBox(height: 18),

        // ---- Service + date ----
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ServiceIcon(r.serviceType, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  serviceTypeTitle(r.serviceType),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatDateLong(r.createdAt),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(r.createdAt),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Divider(height: 1, color: Colors.grey.shade300),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            _statusLabel(status),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _statusColor(status),
            ),
          ),
        ),

        // ---- Provider + vehicle ----
        if (provider != null) ...[
          _providerCard(r, provider),
          const SizedBox(height: 28),
        ] else
          const SizedBox(height: 10),

        // ---- Route ----
        _buildRoute(r),
        const SizedBox(height: 28),

        // ---- Extra details ----
        ..._buildExtraDetails(r),

        // ---- Receipt ----
        const Text(
          'Receipt',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        _receiptRow('Service fee', _money(r.serviceFee)),
        if (r.fuelCost > 0) _receiptRow('Fuel cost', _money(r.fuelCost)),
        if (r.durationMin != null)
          _receiptRow(
            'Estimated duration',
            _formatDuration(r.durationMin!),
            muted: true,
          ),
        if (r.distanceKm != null)
          _receiptRow(
            'Estimated distance',
            '${r.distanceKm!.toStringAsFixed(2)} km',
            muted: true,
          ),
        _receiptRow('Payment', _capitalize(r.paymentMethod), muted: true),
        const SizedBox(height: 8),
        Divider(height: 1, color: Colors.grey.shade300),
        const SizedBox(height: 8),
        _receiptRow(
          'Total fare',
          _money(r.totalAmount),
          bold: true,
          trailing: r.paymentMethod == 'cash'
              ? Image.asset(
                  'assets/images/cash.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.payments_rounded,
                    size: 28,
                    color: _green,
                  ),
                )
              : const Icon(Icons.credit_card_rounded, size: 28, color: _green),
        ),
      ],
    );
  }

  // ---------------- Provider card ----------------
  Widget _providerCard(ServiceRequest r, _ProviderInfo info) {
    final u = info.user;
    final v = info.vehicle;
    final rating = u.rating;

    final avatarFallback = ColoredBox(
      color: Colors.grey.shade200,
      child: Icon(Icons.person, size: 30, color: Colors.grey.shade500),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: ClipOval(
              child: u.profileImagePath.isNotEmpty
                  ? Image.network(
                      u.profileImagePath,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => avatarFallback,
                      loadingBuilder: (context, child, progress) =>
                          progress == null ? child : avatarFallback,
                    )
                  : avatarFallback,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.name.isEmpty ? 'Provider' : u.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _providerRole(r.serviceType),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      rating.count > 0
                          ? '(${rating.average.toStringAsFixed(1)})'
                          : 'No ratings yet',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (v != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Image.asset(
                    _vehicleImageAsset(v.vehicleType),
                    width: 96,
                    height: 52,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      _vehicleFallbackIcon(v.vehicleType),
                      size: 44,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${v.make} ${v.model}'.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    v.plateNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------- Route ----------------
  Widget _buildRoute(ServiceRequest r) {
    final isTowing = r.serviceType == ServiceType.towTruck;
    final hasDropoff = r.dropoffAddress != null && r.dropoffAddress!.isNotEmpty;

    final addressStyle = TextStyle(
      fontSize: 15,
      height: 1.3,
      color: Colors.grey.shade800,
    );
    final timeStyle = TextStyle(fontSize: 13, color: Colors.grey.shade600);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 20,
                child: Column(
                  children: [
                    _RouteDot(
                      asset: isTowing
                          ? 'assets/images/pickup-point.png'
                          : 'assets/images/dropoff-point.png',
                      fallbackColor: isTowing ? _pickupDot : _dropoffDot,
                    ),
                    if (hasDropoff) const Expanded(child: _DottedLine()),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: hasDropoff ? 16 : 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.pickupAddress.isEmpty
                            ? 'Pickup location'
                            : r.pickupAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: addressStyle,
                      ),
                      const SizedBox(height: 4),
                      Text(_formatTime(r.createdAt), style: timeStyle),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasDropoff)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _RouteDot(
                asset: 'assets/images/dropoff-point.png',
                fallbackColor: _dropoffDot,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  r.dropoffAddress!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: addressStyle,
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ---------------- Extra details ----------------
  List<Widget> _buildExtraDetails(ServiceRequest r) {
    final vehicle = r.vehicleLabel;
    final rows = <(String, String)>[
      if (vehicle != null && vehicle.isNotEmpty) ('Your vehicle', vehicle),
      if (r.liters != null)
        (
          'Fuel',
          '${r.liters} L${r.fuelType != null ? ' · ${r.fuelType}' : ''}',
        ),
      if (r.notes.trim().isNotEmpty) ('Notes', r.notes.trim()),
    ];
    if (rows.isEmpty) return const [];

    return [
      const Text(
        'Details',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 12),
      for (final (label, value) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 28),
    ];
  }

  // ---------------- Receipt row ----------------
  Widget _receiptRow(
    String label,
    String value, {
    bool muted = false,
    bool bold = false,
    Widget? trailing,
  }) {
    final color = bold
        ? Colors.black
        : muted
        ? Colors.grey.shade600
        : Colors.grey.shade900;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 16 : 14.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                color: color,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 16 : 14.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: color,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing],
        ],
      ),
    );
  }
}
