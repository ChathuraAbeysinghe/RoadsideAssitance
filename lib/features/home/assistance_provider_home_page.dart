import 'package:flutter/material.dart';

/// Home page shown to assistance providers (mechanic, tow truck, fuel
/// delivery, flat tire, battery boost) after they complete their profile.
///
/// Layout: a yellow-gradient hero section holds everything the provider
/// needs at a glance (profile, greeting, date/time, an online/offline
/// toggle beside the notification bell, today's stats, and their active
/// vehicle). Below it, a white sheet with a curved top edge and a soft
/// shadow holds the scrollable recent-request history.
class AssistanceProviderHomePage extends StatefulWidget {
  final String userName;
  final String profileImagePath;

  const AssistanceProviderHomePage({
    super.key,
    this.userName = 'Assistant',
    this.profileImagePath = '',
  });

  @override
  State<AssistanceProviderHomePage> createState() =>
      _AssistanceProviderHomePageState();
}

/// Centralized palette. The hero section sits on a warm yellow gradient, so
/// its text/icon colors are tuned for contrast against that background; the
/// bottom sheet uses a separate neutral set for the request list.
class _Palette {
  // Hero gradient.
  static const gradientStart = Color(0xFFFFC343);
  static const gradientEnd = Color(0xFFFFEDA8);

  // Text/icon colors used on top of the gradient.
  static const onGradientPrimary = Color(0xFF20160A);
  static const onGradientSecondary = Color(0xFF6B5A34);

  // Status colors (used on both the hero card and the request list).
  static const success = Color(0xFF15803D);
  static const successSoft = Color(0xFFEAF7EE);
  static const danger = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFCECEC);
  static const warning = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFDF3E7);

  // Bottom-sheet neutrals.
  static const textPrimary = Color(0xFF1F2937);
  static const textSecondary = Color(0xFF6B7280);
  static const textTertiary = Color(0xFF9CA3AF);
  static const border = Color(0xFFEDEFF2);
  static const surface = Color(0xFFFFFFFF);
}

class _AssistanceProviderHomePageState
    extends State<AssistanceProviderHomePage> {
  // TODO: back this with the provider's real isAvailable field in
  // Firestore (see AssistanceProvider.isAvailable) instead of local state.
  bool _isOnline = true;

  // TODO: replace with real counts from today's completed/active jobs.
  final int _jobsToday = 3;
  final double _earningsToday = 4250; // in LKR, adjust formatting as needed.

  // TODO: replace with the provider's real active vehicle, fetched from
  // Firestore (e.g. AssistanceProvider.activeVehicle).
  final String _vehicleMake = 'Isuzu Forward';
  final String _vehicleModel = 'NT 4752';
  final bool _vehicleActive = true;

  // (network URL or bundled asset) once available.
  final String _vehicleImagePath = 'assets/images/vehicle-flatbed.png';

  final int _vehicleTrips = 128;
  final double _vehicleDistanceKm = 4320;

  // TODO: replace with the provider's real recent job requests, most
  // recent first, fetched from Firestore.
  final List<_JobRequest> _recentRequests = const [
    _JobRequest(
      serviceLabel: 'Flat Tire Change',
      customerName: 'Nadeesha Perera',
      location: 'Nugegoda',
      time: 'Today, 2:40 PM',
      status: _JobStatus.completed,
      earnings: 1500,
    ),
    _JobRequest(
      serviceLabel: 'Battery Boost',
      customerName: 'Kasun Silva',
      location: 'Rajagiriya',
      time: 'Today, 11:05 AM',
      status: _JobStatus.completed,
      earnings: 1200,
    ),
    _JobRequest(
      serviceLabel: 'Tow Truck',
      customerName: 'Amaya Fernando',
      location: 'Battaramulla',
      time: 'Yesterday, 6:15 PM',
      status: _JobStatus.cancelled,
      earnings: 0,
    ),
    _JobRequest(
      serviceLabel: 'Mechanic',
      customerName: 'Ruwan Jayasuriya',
      location: 'Kotte',
      time: 'Yesterday, 9:30 AM',
      status: _JobStatus.completed,
      earnings: 2800,
    ),
  ];

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const List<String> _months = [
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

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// e.g. "Friday, 12 September · 10:42 AM" — no intl dependency required.
  String get _formattedDateTime {
    final now = DateTime.now();
    final weekday = _weekdays[now.weekday - 1];
    final month = _months[now.month - 1];
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    return '$weekday, ${now.day} $month · $hour12:$minute $period';
  }

  void _setOnline(bool value) {
    setState(() => _isOnline = value);
    // TODO: persist to Firestore, e.g.
    // FirebaseFirestore.instance.collection('users').doc(uid)
    //   .update({'isAvailable': value});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _Palette.gradientEnd,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_Palette.gradientStart, _Palette.gradientEnd],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHero(context),
              Expanded(child: _buildBottomSheet()),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Hero section (everything on the gradient).
  // ---------------------------------------------------------------------

  Widget _buildHero(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileRow(),
          const SizedBox(height: 4),
          Text(
            _formattedDateTime,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: _Palette.onGradientSecondary,
            ),
          ),
          const SizedBox(height: 18),
          _buildStatsRow(),
          const SizedBox(height: 14),
          _buildActiveVehicleCard(),
        ],
      ),
    );
  }

  Widget _buildProfileRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 2,
            ),
          ),
          child: ClipOval(
            child: widget.profileImagePath.isEmpty
                ? Image.asset(
                    'assets/images/profile.png',
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                  )
                : Image.network(
                    widget.profileImagePath,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Image.asset(
                      'assets/images/profile.png',
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
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
                _greeting,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: _Palette.onGradientSecondary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                widget.userName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _Palette.onGradientPrimary,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _buildOnlineToggle(),
        const SizedBox(width: 10),
        _buildNotificationButton(),
      ],
    );
  }

  /// Compact online/offline toggle, sized to sit directly beside the
  /// notification bell in the header row rather than as its own card.
  Widget _buildOnlineToggle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setOnline(!_isOnline),
      child: _CompactSwitch(value: _isOnline, onChanged: _setOnline),
    );
  }

  Widget _buildNotificationButton() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.55),
          ),
          child: const Icon(
            Icons.notifications_none_rounded,
            size: 23,
            color: _Palette.onGradientPrimary,
          ),
        ),
        // TODO: only show when there are unread notifications.
        Positioned(
          top: 2,
          right: 3,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _Palette.danger,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _HeroStatChip(
            icon: Icons.checklist_rounded,
            label: 'Jobs today',
            value: '$_jobsToday',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _HeroStatChip(
            icon: Icons.payments_outlined,
            label: 'Earnings today',
            value: 'Rs. ${_earningsToday.toStringAsFixed(0)}',
          ),
        ),
      ],
    );
  }

  Widget _buildActiveVehicleCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _vehicleActive
                            ? _Palette.success
                            : _Palette.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ACTIVE VEHICLE',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: _Palette.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _vehicleMake,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _Palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _vehicleModel,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _Palette.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 0),
                Row(
                  children: [
                    Text(
                      '$_vehicleTrips trips',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _Palette.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('·', style: TextStyle(color: _Palette.textTertiary)),
                    const SizedBox(width: 6),
                    Text(
                      '${_vehicleDistanceKm.toStringAsFixed(0)} km driven',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: _Palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            height: 120,
            // Plain image, no circular crop/border.
            child: Image.asset(
              _vehicleImagePath,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.local_shipping_rounded,
                size: 40,
                color: _Palette.onGradientPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Bottom sheet (curved top + shadow, holds the request history).
  // ---------------------------------------------------------------------

  Widget _buildBottomSheet() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _Palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent requests',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _Palette.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // TODO: navigate to full request history / Jobs tab.
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'View all',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_recentRequests.isEmpty)
                  _buildEmptyRequestsState()
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _Palette.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _Palette.border),
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < _recentRequests.length; i++)
                            _buildRequestTile(
                              _recentRequests[i],
                              isLast: i == _recentRequests.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: _ProviderBottomNavBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyRequestsState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: _Palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _Palette.border),
        ),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 36, color: _Palette.textTertiary),
            const SizedBox(height: 10),
            const Text(
              'No requests yet',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _Palette.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'New job requests will show up here',
              style: TextStyle(fontSize: 12.5, color: _Palette.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestTile(_JobRequest request, {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: _Palette.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFF8FAFC),
            ),
            child: Icon(
              _iconForService(request.serviceLabel),
              size: 19,
              color: _Palette.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.serviceLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _Palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${request.customerName} · ${request.location}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: _Palette.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  request.time,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: _Palette.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _StatusBadge(status: request.status),
              if (request.status == _JobStatus.completed) ...[
                const SizedBox(height: 6),
                Text(
                  'Rs. ${request.earnings.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _Palette.textPrimary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconForService(String serviceLabel) {
    switch (serviceLabel) {
      case 'Mechanic':
        return Icons.build_rounded;
      case 'Tow Truck':
        return Icons.local_shipping_rounded;
      case 'Fuel Delivery':
        return Icons.local_gas_station_rounded;
      case 'Flat Tire Change':
        return Icons.tire_repair_rounded;
      case 'Battery Boost':
        return Icons.battery_charging_full_rounded;
      default:
        return Icons.build_circle_outlined;
    }
  }
}

enum _JobStatus { completed, cancelled, inProgress }

class _JobRequest {
  final String serviceLabel;
  final String customerName;
  final String location;
  final String time;
  final _JobStatus status;
  final double earnings;

  const _JobRequest({
    required this.serviceLabel,
    required this.customerName,
    required this.location,
    required this.time,
    required this.status,
    required this.earnings,
  });
}

class _StatusBadge extends StatelessWidget {
  final _JobStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      _JobStatus.completed => (
        'Completed',
        _Palette.success,
        _Palette.successSoft,
      ),
      _JobStatus.cancelled => (
        'Cancelled',
        _Palette.danger,
        _Palette.dangerSoft,
      ),
      _JobStatus.inProgress => (
        'In progress',
        _Palette.warning,
        _Palette.warningSoft,
      ),
    };

    return _StatusPill(label: label, color: fg, bg: bg);
  }
}

/// Small reusable rounded status pill, used for both job status and the
/// active-vehicle status.
class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;

  const _StatusPill({
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// A small, header-friendly switch: same on/off semantics as [Switch], sized
/// down so it sits comfortably next to the notification bell.
class _CompactSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CompactSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 44,
        height: 25,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value
              ? _Palette.success
              : Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact stat card used inside the hero (jobs / earnings today).
class _HeroStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HeroStatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _Palette.onGradientPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _Palette.textPrimary,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: _Palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderBottomNavBar extends StatelessWidget {
  const _ProviderBottomNavBar();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      width: double.infinity,
      height: 78 + bottomInset,
      padding: EdgeInsets.only(top: 10, bottom: bottomInset),
      decoration: BoxDecoration(
        color: _Palette.surface,
        border: const Border(top: BorderSide(color: _Palette.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _NavItem(label: 'Home', icon: Icons.home_rounded, isActive: true),
          _NavItem(label: 'Jobs', icon: Icons.assignment_outlined),
          _NavItem(
            label: 'Earnings',
            icon: Icons.account_balance_wallet_outlined,
          ),
          _NavItem(label: 'More', icon: Icons.apps_rounded),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;

  const _NavItem({
    required this.label,
    required this.icon,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFFB45309) : _Palette.textTertiary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 23, color: color),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: color,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
