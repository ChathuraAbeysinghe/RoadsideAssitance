import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../entities/app_user.dart';
import '../../../entities/service_request.dart';
import '../../../services/provider_location_service.dart';
import '../../_share/navbar/app_bottom_nav_bar.dart';
import '../services/provider_repository.dart';
import '../../incoming_request/incoming_request_page.dart';
import 'provider_job_page.dart';
import 'provider_jobs_page.dart';
import 'provider_notifications_page.dart';
import 'provider_ui_helpers.dart';
import '../models/provider_service.dart';

const Color _brandRed = Color(0xFFE30613);

class ProviderHomePage extends StatefulWidget {
  final UserType userType;
  // Kept so existing callers still compile; the page reads live data itself.
  final String userName;
  final String profileImagePath;
  final String uid;

  const ProviderHomePage({
    super.key,
    this.userType = UserType.assistanceProvider,
    this.userName = '',
    this.profileImagePath = '',
    this.uid = '',
  });

  @override
  State<ProviderHomePage> createState() => _ProviderHomePageState();
}

class _ProviderHomePageState extends State<ProviderHomePage> {
  final _repo = ProviderRepository();
  final Set<String> _declined = {};

  late final String _uid;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userStream;
  Stream<List<ServiceRequest>>? _jobsStream;
  Stream<int>? _unreadStream;

  @override
  void initState() {
    super.initState();
    _uid = widget.uid.isNotEmpty
        ? widget.uid
        : FirebaseAuth.instance.currentUser?.uid ?? '';
    if (_uid.isNotEmpty) {
      _userStream = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .snapshots();
      _jobsStream = watchProviderJobs(_uid);
      _unreadStream = _repo.watchUnreadCount(_uid);
      // Make sure location sharing matches availability / active job.
      ProviderLocationService.instance.refresh();
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Future<void> _setAvailable(bool value) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'isAvailable': value,
      });
      await ProviderLocationService.instance.refresh();
    } catch (_) {
      _snack('Could not update availability');
    }
  }

  Future<void> _accept(ServiceRequest r, String providerName) async {
    try {
      final result = await _repo.acceptJob(r, _uid, providerName);
      if (!mounted) return;
      switch (result) {
        case AcceptResult.success:
          await ProviderLocationService.instance.refresh();
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ProviderJobPage(requestId: r.id)),
          );
        case AcceptResult.alreadyTaken:
          _snack('Another provider already accepted this request');
        case AcceptResult.expired:
          _snack('This request has expired');
        case AcceptResult.notFound:
          _snack('This request is no longer available');
      }
    } catch (_) {
      _snack('Could not accept the request. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Please sign in again.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xfff8fafc),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _userStream,
        builder: (context, userSnap) {
          final data = userSnap.data?.data();
          if (data == null) {
            return userSnap.hasError
                ? const Center(child: Text('Unable to load your profile.'))
                : const Center(child: CircularProgressIndicator());
          }
          final user = userFromMap(_uid, data);
          if (user is! AssistanceProvider) {
            return const Center(
              child: Text('This account is not a service provider.'),
            );
          }

          return StreamBuilder<List<ServiceRequest>>(
            stream: _jobsStream,
            builder: (context, jobsSnap) {
              final jobs = jobsSnap.data ?? const <ServiceRequest>[];
              final active = jobs
                  .where((j) => kActiveStatuses.contains(j.status))
                  .toList();
              return _buildDashboard(
                user,
                jobs,
                active.isEmpty ? null : active.first,
              );
            },
          );
        },
      ),
      bottomNavigationBar: AppBottomNavBar(
        userType: widget.userType,
        activeIndex: 0,
      ),
    );
  }

  Widget _buildDashboard(
    AssistanceProvider user,
    List<ServiceRequest> jobs,
    ServiceRequest? active,
  ) {
    final completed = jobs
        .where((j) => j.status == RequestStatus.completed)
        .toList();
    final todayDone = completed.where((j) => isToday(j.completedAt)).toList();
    final todayEarnings = todayDone.fold<double>(
      0,
      (t, j) => t + j.totalAmount,
    );
    final rating = user.rating;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(user, active != null)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (active != null) ...[
                _ActiveJobBanner(job: active),
                const SizedBox(height: 24),
              ],
              _sectionLabel('NEW REQUESTS'),
              const SizedBox(height: 12),
              _PendingSection(
                provider: user,
                hasActiveJob: active != null,
                declined: _declined,
                onDecline: (id) => setState(() => _declined.add(id)),
                onAccept: (r) => _accept(r, user.name),
              ),
              const SizedBox(height: 24),
              _sectionLabel("TODAY'S SUMMARY"),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Summary(label: 'Completed Jobs', value: '${todayDone.length}'),
                  const SizedBox(width: 12),
                  _Summary(
                    label: 'Earnings',
                    value: 'Rs ${todayEarnings.toStringAsFixed(0)}',
                    red: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Summary(
                    label: 'Rating',
                    value: rating.count > 0
                        ? rating.average.toStringAsFixed(1)
                        : 'No ratings',
                    green: rating.count > 0,
                  ),
                  const SizedBox(width: 12),
                  _Summary(label: 'Total Jobs', value: '${completed.length}'),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _sectionLabel('RECENT JOBS'),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProviderJobsPage(),
                      ),
                    ),
                    child: const Text(
                      'See All',
                      style: TextStyle(
                        color: _brandRed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (completed.isEmpty)
                const Text(
                  'No completed jobs yet.',
                  style: TextStyle(color: Colors.grey),
                )
              else
                ...completed.take(3).map((j) => JobHistoryTile(job: j)),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: Colors.grey,
    ),
  );

  Widget _buildHeader(AssistanceProvider user, bool onJob) {
    final top = MediaQuery.of(context).padding.top;
    final hasPhoto = user.profileImagePath.isNotEmpty;

    final String availabilityTitle = onJob
        ? 'On a job'
        : user.isAvailable
        ? 'Online & Available'
        : 'Offline';
    final String availabilitySub = onJob
        ? 'Sharing your location with the customer'
        : user.isAvailable
        ? 'Ready to accept jobs'
        : 'You will not receive new requests';

    return Container(
      color: _brandRed,
      padding: EdgeInsets.fromLTRB(20, top + 20, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                backgroundImage: hasPhoto
                    ? NetworkImage(user.profileImagePath)
                    : null,
                child: hasPhoto
                    ? null
                    : const Icon(Icons.person_outline, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      user.name.isEmpty ? 'Provider' : user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              _buildBell(),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 5,
                  backgroundColor: user.isAvailable || onJob
                      ? Colors.teal
                      : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        availabilityTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        availabilitySub,
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: user.isAvailable,
                  onChanged: _setAvailable,
                  thumbColor: const WidgetStatePropertyAll(Colors.white),
                  trackColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected)
                        ? Colors.teal
                        : Colors.grey.shade400,
                  ),
                  trackOutlineColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBell() {
    return StreamBuilder<int>(
      stream: _unreadStream,
      builder: (context, snap) {
        final unread = snap.data ?? 0;
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProviderNotificationsPage(uid: _uid),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.white,
                ),
              ),
              if (unread > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      style: const TextStyle(
                        color: _brandRed,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Active job banner
// ---------------------------------------------------------------------------
class _ActiveJobBanner extends StatelessWidget {
  final ServiceRequest job;
  const _ActiveJobBanner({required this.job});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _brandRed, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProviderJobPage(requestId: job.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.local_shipping_outlined, color: _brandRed, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ACTIVE JOB',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _brandRed,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      serviceTypeTitle(job.serviceType),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      statusLabel(job.status),
                      style: TextStyle(color: statusColor(job.status)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending requests (live, filtered by distance / expiry / declined)
// ---------------------------------------------------------------------------
class _PendingSection extends StatefulWidget {
  final AssistanceProvider provider;
  final bool hasActiveJob;
  final Set<String> declined;
  final void Function(String id) onDecline;
  final Future<void> Function(ServiceRequest r) onAccept;

  const _PendingSection({
    required this.provider,
    required this.hasActiveJob,
    required this.declined,
    required this.onDecline,
    required this.onAccept,
  });

  @override
  State<_PendingSection> createState() => _PendingSectionState();
}

class _PendingSectionState extends State<_PendingSection> {
  // Cached so the Firestore listener isn't recreated on every rebuild
  // (the provider doc changes every few seconds with the GPS updates).
  late Stream<List<ServiceRequest>> _stream;
  late Stream<List<ProviderService>> _servicesStream;

  @override
  void initState() {
    super.initState();
    _stream = watchPendingRequests(widget.provider.services);
    _servicesStream = ProviderRepository().watchServices(widget.provider.uid);
  }

  @override
  void didUpdateWidget(covariant _PendingSection old) {
    super.didUpdateWidget(old);
    if (!setEquals(old.provider.services, widget.provider.services)) {
      _stream = watchPendingRequests(widget.provider.services);
    }
    if (old.provider.uid != widget.provider.uid) {
      _servicesStream = ProviderRepository().watchServices(widget.provider.uid);
    }
  }

  Widget _info(IconData icon, String title, String sub) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade500, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    if (!p.isAvailable) {
      return _info(
        Icons.power_settings_new,
        'You are offline',
        'Turn on availability to receive requests.',
      );
    }
    if (widget.hasActiveJob) {
      return _info(
        Icons.assignment_turned_in_outlined,
        'Finish your current job',
        'New requests appear once it is done.',
      );
    }
    if (p.services.isEmpty) {
      return _info(
        Icons.build_outlined,
        'No services selected',
        'Add a service in the Services tab to receive requests.',
      );
    }
    final loc = p.currentLocation;
    if (loc.latitude == 0 && loc.longitude == 0) {
      return _info(
        Icons.my_location,
        'Getting your location...',
        'Turn on location and allow permission for the app.',
      );
    }
    final here = LatLng(loc.latitude, loc.longitude);

    return StreamBuilder<List<ProviderService>>(
      stream: _servicesStream,
      builder: (context, servicesSnap) {
        final myServices = servicesSnap.data ?? [];
        
        return StreamBuilder<List<ServiceRequest>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError) {
              return _info(
                Icons.error_outline,
                'Unable to load requests',
                'Check your connection and try again.',
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            const distance = Distance();
            final now = DateTime.now();
            final items = <(ServiceRequest, double)>[];
            for (final r in snap.data!) {
              if (widget.declined.contains(r.id) || r.expiresAt.isBefore(now)) {
                continue;
              }
              
              LatLng baseLoc = here;
              final matched = myServices.where((s) => s.serviceType == r.serviceType && s.isActive).toList();
              if (matched.isNotEmpty) {
                final geo = matched.first.locationGeo;
                if (geo != null && (geo.latitude != 0 || geo.longitude != 0)) {
                  baseLoc = LatLng(geo.latitude, geo.longitude);
                }
              }

              final km =
                  distance.as(
                    LengthUnit.Meter,
                    baseLoc,
                    LatLng(r.pickup.latitude, r.pickup.longitude),
                  ) /
                  1000;
              // Customers widen their radius over time (5 -> 10 -> 15 km).
              if (km <= r.searchRadiusKm) items.add((r, km));
            }
            items.sort((a, b) => a.$2.compareTo(b.$2));

            if (items.isEmpty) {
              return _info(
                Icons.check_circle_outline,
                'No new requests',
                'Requests near you will show up here automatically.',
              );
            }
            return Column(
              children: [
                for (final it in items)
                  _RequestCard(
                    key: ValueKey(it.$1.id),
                    request: it.$1,
                    distanceKm: it.$2,
                    onDecline: () => widget.onDecline(it.$1.id),
                    onAccept: () => widget.onAccept(it.$1),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _RequestCard extends StatefulWidget {
  final ServiceRequest request;
  final double distanceKm;
  final VoidCallback onDecline;
  final Future<void> Function() onAccept;

  const _RequestCard({
    super.key,
    required this.request,
    required this.distanceKm,
    required this.onDecline,
    required this.onAccept,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await widget.onAccept();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final left = r.expiresAt.difference(DateTime.now());
    final expired = left.isNegative;
    final mm = left.inMinutes.clamp(0, 99).toString();
    final ss = (left.inSeconds % 60).clamp(0, 59).toString().padLeft(2, '0');

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shadowColor: Colors.red.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _brandRed, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: _brandRed,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'NEW REQUEST',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    expired ? 'Expired' : '$mm:$ss left',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        serviceTypeTitle(r.serviceType),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      money(r.totalAmount),
                      style: const TextStyle(
                        color: _brandRed,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_outlined, color: _brandRed, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${r.pickupAddress}\n${widget.distanceKm.toStringAsFixed(1)} km away',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                if (r.dropoffAddress != null && r.dropoffAddress!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.flag_outlined, size: 20, color: Colors.black87),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${r.dropoffAddress}'
                          '${r.distanceKm != null ? ' (${r.distanceKm!.toStringAsFixed(1)} km trip)' : ''}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ],
                if (r.serviceType == ServiceType.fuelDelivery && r.liters != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.local_gas_station_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text('${r.liters} L ${r.fuelType ?? ''}'),
                    ],
                  ),
                ],
                if (r.vehicleLabel != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xfff8fafc),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_car_outlined, color: Colors.grey, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            r.vehicleLabel!,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (r.notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Note: ${r.notes}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () async {
                      final result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (_) => IncomingRequestPage(request: r),
                        ),
                      );
                      if (result == false && mounted) {
                        widget.onDecline();
                      }
                    },
                    icon: const Icon(Icons.info_outline, color: _brandRed),
                    label: const Text(
                      'View Details',
                      style: TextStyle(
                        color: _brandRed,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _brandRed),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : widget.onDecline,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.grey.shade400),
                        ),
                        child: const Text(
                          'Decline',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_busy || expired) ? null : _accept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brandRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Accept Job',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared widgets
// ---------------------------------------------------------------------------
class _Summary extends StatelessWidget {
  final String label;
  final String value;
  final bool red;
  final bool green;
  const _Summary({
    required this.label,
    required this.value,
    this.red = false,
    this.green = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: red
                      ? _brandRed
                      : (green ? Colors.teal : Colors.black),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Used on the home page and the Jobs tab.
class JobHistoryTile extends StatelessWidget {
  final ServiceRequest job;
  const JobHistoryTile({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    final done = job.status == RequestStatus.completed;
    final when = done ? job.completedAt : job.createdAt;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: ListTile(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProviderJobPage(requestId: job.id),
            ),
          );
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            done ? Icons.check_circle_outline : Icons.cancel_outlined,
            color: _brandRed,
          ),
        ),
        title: Text(
          serviceTypeTitle(job.serviceType),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        subtitle: Text(
          '${formatWhen(when)} - ${money(job.totalAmount)}',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor(job.status).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            statusLabel(job.status),
            style: TextStyle(
              color: statusColor(job.status),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
