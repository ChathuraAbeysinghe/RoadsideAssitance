import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../entities/app_user.dart';
import '../../../entities/service_request.dart';
import '../../_share/navbar/app_bottom_nav_bar.dart';
import 'provider_home_page.dart' show JobHistoryTile;
import 'provider_job_page.dart';
import 'provider_ui_helpers.dart';

const Color _brandRed = Color(0xFFE30613);

/// "Job" tab: the active job on top, then completed / cancelled history.
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Text(
                    'My Jobs',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
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
            ),
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
                          return const Center(child: CircularProgressIndicator());
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
                                  Icon(Icons.assignment_outlined,
                                      size: 90, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No jobs yet',
                                    style: TextStyle(
                                        fontSize: 19, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Accepted jobs will appear here.',
                                    style: TextStyle(color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                          children: [
                            if (active.isNotEmpty) ...[
                              const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 10),
                              for (final j in active) _ActiveTile(job: j),
                              const SizedBox(height: 16),
                            ],
                            if (history.isNotEmpty) ...[
                              const Text(
                                'HISTORY',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 10),
                              for (final j in history) JobHistoryTile(job: j),
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
}

class _ActiveTile extends StatelessWidget {
  final ServiceRequest job;
  const _ActiveTile({required this.job});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _brandRed, width: 1.5),
      ),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProviderJobPage(requestId: job.id)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.local_shipping_outlined, color: _brandRed, size: 30),
        title: Text(
          serviceTypeTitle(job.serviceType),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        subtitle: Text(
          '${statusLabel(job.status)} - ${job.pickupAddress}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
