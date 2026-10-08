import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../entities/app_user.dart';
import '../../../entities/service_request.dart';
import '../../_share/navbar/app_bottom_nav_bar.dart';
import 'provider_home_page.dart' show JobHistoryTile;
import 'provider_job_page.dart';
import 'provider_ui_helpers.dart';

const Color _brandRed = Color(0xFFE30613);

class ProviderJobsPage extends StatefulWidget {
  const ProviderJobsPage({super.key});

  @override
  State<ProviderJobsPage> createState() => _ProviderJobsPageState();
}

class _ProviderJobsPageState extends State<ProviderJobsPage> {
  late final String _uid;
  Stream<List<ServiceRequest>>? _stream;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (_uid.isNotEmpty) _stream = watchProviderJobs(_uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: _stream == null
                  ? const Center(child: Text('Please sign in again.'))
                  : StreamBuilder<List<ServiceRequest>>(
                      stream: _stream,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return const Center(child: Text('Unable to load jobs.'));
                        }
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator(color: _brandRed));
                        }
                        final jobs = snap.data!;
                        final active = jobs
                            .where((j) => kActiveStatuses.contains(j.status))
                            .toList();
                        final history = jobs
                            .where((j) =>
                                j.status == RequestStatus.completed ||
                                j.status == RequestStatus.cancelled)
                            .toList();

                        if (active.isEmpty && history.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.assignment_outlined,
                                        size: 80, color: Colors.grey.shade400),
                                  ),
                                  const SizedBox(height: 24),
                                  const Text(
                                    'No Jobs Yet',
                                    style: TextStyle(
                                        fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Accepted jobs and your history will appear here.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          children: [
                            if (active.isNotEmpty) ...[
                              _buildSectionLabel('ACTIVE JOBS', count: active.length),
                              const SizedBox(height: 14),
                              for (final j in active) _ActiveTile(job: j),
                              const SizedBox(height: 24),
                            ],
                            if (history.isNotEmpty) ...[
                              _buildSectionLabel('HISTORY', count: history.length),
                              const SizedBox(height: 14),
                              Builder(
                                builder: (context) {
                                  final historyByService = <ServiceType, List<ServiceRequest>>{};
                                  for (final j in history) {
                                    historyByService.putIfAbsent(j.serviceType, () => []).add(j);
                                  }
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      for (final entry in historyByService.entries) ...[
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 12, top: 8),
                                          child: Text(
                                            serviceTypeTitle(entry.key).toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.grey.shade400,
                                              letterSpacing: 1.0,
                                            ),
                                          ),
                                        ),
                                        for (final j in entry.value) JobHistoryTile(job: j),
                                        const SizedBox(height: 8),
                                      ],
                                    ],
                                  );
                                },
                              ),
                            ],
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNavBar(
        userType: UserType.assistanceProvider,
        activeIndex: 1,
      ),
    );
  }

  Widget _buildSectionLabel(String text, {int? count}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: Colors.grey.shade500,
          ),
        ),
        if (count != null)
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: text.contains('ACTIVE') ? _brandRed : Colors.grey.shade400,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Back button aligned left
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.chevron_left, color: Colors.black87, size: 24),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          // Centered title + subtitle
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'My Jobs',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Track your job history',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveTile extends StatelessWidget {
  final ServiceRequest job;
  const _ActiveTile({required this.job});

  String _iconForServiceType(ServiceType type) => switch (type) {
    ServiceType.towTruck => 'assets/icon/icon-tow-truck.png',
    ServiceType.mechanic => 'assets/icon/icon-automobile.png',
    ServiceType.fuelDelivery => 'assets/icon/icon-gas-station.png',
    ServiceType.flatTireChange => 'assets/icon/icon-wheels.png',
    ServiceType.batteryBoost => 'assets/icon/icon-jump-start.png',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _brandRed.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: _brandRed.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProviderJobPage(requestId: job.id)),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Red left accent border for active jobs
                  Container(
                    width: 4,
                    decoration: const BoxDecoration(
                      color: _brandRed,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                  ),
                  // Service icon
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Image.asset(
                        _iconForServiceType(job.serviceType),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.local_shipping_outlined, color: _brandRed, size: 28),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            serviceTypeTitle(job.serviceType),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.black87),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor(job.status).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  statusLabel(job.status).toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor(job.status),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  job.pickupAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
