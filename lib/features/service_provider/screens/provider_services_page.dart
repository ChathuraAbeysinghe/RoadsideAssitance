import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../entities/app_user.dart';
import '../../_share/navbar/app_bottom_nav_bar.dart';
import '../models/provider_service.dart';
import '../services/provider_repository.dart';
import 'add_service_page.dart';

class ProviderServicesPage extends StatelessWidget {
  final String uid;
  final UserType userType;

  const ProviderServicesPage({
    super.key,
    String? uid,
    this.userType = UserType.assistanceProvider,
  }) : uid = uid ?? '';

  String get _resolvedUid =>
      uid.isNotEmpty ? uid : FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: StreamBuilder<List<ProviderService>>(
                stream: ProviderRepository().watchServices(_resolvedUid),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const _Message(message: 'Unable to load services.');
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final services = snapshot.data!;
                  if (services.isEmpty) {
                    return _EmptyServices(uid: _resolvedUid);
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      ...services.map((service) => _ServiceCard(service: service)),
                      _AddServiceCard(uid: _resolvedUid),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavBar(userType: userType, activeIndex: 2),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Text(
            'Services',
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
    );
  }
}

class _EmptyServices extends StatelessWidget {
  final String uid;
  const _EmptyServices({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/icon/icon-add_service_emppage.png',
            height: 120,
          ),
          const SizedBox(height: 20),
          const Text(
            'Your service will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'You don\'t have any service yet. Tap to add new service below',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () => _openAdd(context, uid),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE30613),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                'Add New Service',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final ProviderService service;
  const _ServiceCard({required this.service});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        service.name.isEmpty ? service.displayType : service.name,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: service.isActive ? Colors.black87 : Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!service.isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Paused',
                          style: TextStyle(fontSize: 10, color: Colors.deepOrange, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  service.plateNumber.isEmpty
                      ? service.displayType
                      : service.plateNumber,
                  style: TextStyle(fontSize: 13.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.black87),
            onSelected: (value) async {
              if (value == 'edit') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddServicePage(
                      uid: service.providerUid,
                      existingService: service,
                    ),
                  ),
                );
              } else if (value == 'toggle') {
                await ProviderRepository().updateService(
                  service.copyWith(isActive: !service.isActive),
                );
              } else if (value == 'delete') {
                await ProviderRepository().deleteService(service);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('Edit service'),
              ),
              PopupMenuItem(
                value: 'toggle',
                child: Text(service.isActive ? 'Pause service' : 'Restart service'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Remove service', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddServiceCard extends StatelessWidget {
  final String uid;
  const _AddServiceCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openAdd(context, uid),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Row(
          children: [
            Icon(Icons.add_rounded, size: 22, color: Colors.black87),
            SizedBox(width: 14),
            Text(
              'Add Service',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String message;
  const _Message({required this.message});
  @override
  Widget build(BuildContext context) => Center(child: Text(message));
}

void _openAdd(BuildContext context, String uid) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => AddServicePage(uid: uid)),
  );
}

