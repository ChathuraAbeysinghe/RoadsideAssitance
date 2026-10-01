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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 25,
              backgroundColor: Color(0xfff1f3f5),
              child: Icon(Icons.person_outline, color: Colors.grey),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'Colombo, SL',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
            const Icon(Icons.notifications_none_rounded, size: 28),
          ],
        ),
        const SizedBox(height: 20),
        if (urgent != null)
          _RequestCard(request: urgent, repository: repository)
        else
          const _EmptyRequest(),
        const SizedBox(height: 24),
        const Text(
          "TODAY'S SUMMARY",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Summary(label: 'Completed', value: '${completed.length} Jobs'),
            const SizedBox(width: 12),
            _Summary(label: 'Earnings', value: 'LKR $earnings', red: true),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          "TODAY'S COMPLETED LOG",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (completed.isEmpty)
          const Text(
            'No completed jobs yet.',
            style: TextStyle(color: Colors.grey),
          )
        else
          ...completed.map((request) => _CompletedCard(request: request)),
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
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Colors.red, width: 2),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NEW URGENT DISPATCH',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${request.serviceName} • ${request.driverName}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'LKR ${request.price}',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            request.location,
            style: const TextStyle(color: Colors.grey, fontSize: 15),
          ),
          const SizedBox(height: 14),
          Text(
            request.vehicleLabel,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      repository.updateRequestStatus(request.id, 'declined'),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      repository.updateRequestStatus(request.id, 'accepted'),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
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
  const _Summary({required this.label, required this.value, this.red = false});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: red ? Colors.red : Colors.black,
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
    child: ListTile(
      leading: const Icon(Icons.star_outline, color: Colors.red),
      title: Text(
        '${request.serviceName} • ${request.driverName}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text('LKR ${request.price}'),
      trailing: const Text(
        'Completed',
        style: TextStyle(color: Colors.green, fontWeight: FontWeight.w700),
      ),
    ),
  );
}
