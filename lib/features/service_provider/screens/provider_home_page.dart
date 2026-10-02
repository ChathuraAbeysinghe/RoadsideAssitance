import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../entities/app_user.dart';
import '../../_share/navbar/app_bottom_nav_bar.dart';
import '../models/service_request.dart';
import '../services/provider_repository.dart';

class ProviderHomePage extends StatelessWidget {
  final UserType userType;
  final String userName;
  final String profileImagePath;
  final String uid;

  const ProviderHomePage({
    super.key,
    this.userType = UserType.assistanceProvider,
    this.userName = 'Sangeeth',
    this.profileImagePath = '',
    this.uid = '',
  });

  String get _resolvedUid =>
      uid.isNotEmpty ? uid : FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    final repository = ProviderRepository();
    return Scaffold(
      backgroundColor: const Color(0xfff8fafc),
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<ServiceRequest>>(
          stream: repository.watchRequests(_resolvedUid),
          builder: (context, activeSnapshot) =>
              StreamBuilder<List<ServiceRequest>>(
                stream: repository.watchCompletedRequests(_resolvedUid),
                builder: (context, completedSnapshot) {
                  if (activeSnapshot.hasError || completedSnapshot.hasError) {
                    return const Center(child: Text('Unable to load jobs.'));
                  }
                  if (!activeSnapshot.hasData || !completedSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final active = activeSnapshot.data!;
                  final completed = completedSnapshot.data!;
                  return _Dashboard(
                    userName: userName,
                    requests: active,
                    completed: completed,
                    repository: repository,
                  );
                },
              ),
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(userType: userType, activeIndex: 0),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final String userName;
  final List<ServiceRequest> requests;
  final List<ServiceRequest> completed;
  final ProviderRepository repository;
  const _Dashboard({
    required this.userName,
    required this.requests,
    required this.completed,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    final pending = requests
        .where((request) => request.status == 'pending')
        .toList();
    final urgent = pending.isEmpty ? null : pending.first;
    final earnings = completed.fold<int>(
      0,
      (total, request) => total + request.price,
    );
    final topPadding = MediaQuery.of(context).padding.top;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            color: const Color(0xFFE30613),
            padding: EdgeInsets.fromLTRB(20, topPadding + 20, 20, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      child: const Icon(Icons.person_outline, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Good Morning',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            userName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    CircleAvatar(
                      backgroundColor: Colors.white.withOpacity(0.2),
                      child: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                    ),
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
                      const CircleAvatar(radius: 5, backgroundColor: Colors.teal),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Online & Available', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            Text('Ready to accept jobs', style: TextStyle(color: Colors.grey, fontSize: 14)),
                          ],
                        ),
                      ),
                      Switch(
                        value: true,
                        onChanged: (v) {},
                        activeColor: Colors.teal,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (urgent != null)
                _RequestCard(request: urgent, repository: repository)
              else
                const _EmptyRequest(),
              const SizedBox(height: 24),
              const Text(
                "TODAY'S SUMMARY",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Summary(label: 'Completed Jobs', value: '${completed.length}'),
                  const SizedBox(width: 12),
                  _Summary(label: 'Earnings', value: 'LKR $earnings', red: true),
                ],
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  _Summary(label: 'Acceptance Rate', value: '87%', green: true),
                  SizedBox(width: 12),
                  _Summary(label: 'Avg Response', value: '4 min'),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "RECENT JOBS",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.grey),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text('See All', style: TextStyle(color: Color(0xFFE30613), fontWeight: FontWeight.w700)),
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
                ...completed.map((request) => _CompletedCard(request: request)),
            ]),
          ),
        ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  final ServiceRequest request;
  final ProviderRepository repository;
  const _RequestCard({required this.request, required this.repository});
  @override
  Widget build(BuildContext context) => Card(
    elevation: 4,
    shadowColor: Colors.red.withOpacity(0.2),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFE30613), width: 1.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFFE30613),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  CircleAvatar(radius: 4, backgroundColor: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'NEW URGENT DISPATCH',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '2 min left',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.serviceName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          request.driverName,
                          style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'LKR ${request.price}',
                        style: const TextStyle(
                          color: Color(0xFFE30613),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Text(
                        'Estimated',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: Color(0xFFE30613), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${request.location} • 3.2 km away',
                    style: const TextStyle(color: Colors.black87, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                    Text(
                      request.vehicleLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.schedule, color: Color(0xFFE30613), size: 14),
                        SizedBox(width: 4),
                        Text('Urgent', style: TextStyle(color: Color(0xFFE30613), fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.star, color: Colors.green, size: 14),
                        SizedBox(width: 4),
                        Text('4.9 Customer', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.near_me, color: Colors.blue, size: 14),
                        SizedBox(width: 4),
                        Text('3.2 km', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          repository.updateRequestStatus(request.id, 'declined'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade400),
                      ),
                      child: const Text('Decline', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE30613),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () =>
                          repository.updateRequestStatus(request.id, 'accepted'),
                      child: const Text('Accept Job', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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

class _EmptyRequest extends StatelessWidget {
  const _EmptyRequest();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      children: [
        Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
        SizedBox(width: 12),
        Text(
          'No new dispatches',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _Summary extends StatelessWidget {
  final String label;
  final String value;
  final bool red;
  final bool green;
  const _Summary({required this.label, required this.value, this.red = false, this.green = false});
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
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: red ? const Color(0xFFE30613) : (green ? Colors.teal : Colors.black),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedCard extends StatelessWidget {
  final ServiceRequest request;
  const _CompletedCard({required this.request});
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.grey.shade200),
    ),
    color: Colors.white,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.star_outline, color: Color(0xFFE30613)),
      ),
      title: Text(
        '${request.serviceName} • ${request.driverName}',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
      subtitle: Text('Today, 10:20 AM • LKR ${request.price}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Completed',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ),
    ),
  );
}
