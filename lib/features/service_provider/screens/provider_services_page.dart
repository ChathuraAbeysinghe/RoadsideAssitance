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
      backgroundColor: const Color(0xfff8fafc),
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
                    return const Center(child: CircularProgressIndicator(color: Color(0xFFE30613)));
                  }
                  final services = snapshot.data!;
                  if (services.isEmpty) {
                    return _EmptyServices(uid: _resolvedUid);
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      ...services.map((service) => _ServiceCard(service: service)),
                      const SizedBox(height: 12),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.chevron_left, color: Colors.black87),
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'My Services',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
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
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFE30613).withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/icon/icon-add_service_emppage.png',
              height: 100,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Your services will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          Text(
            'You don\'t have any active services yet. Add a new service to start receiving requests.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () => _openAdd(context, uid),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add New Service',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE30613),
                elevation: 4,
                shadowColor: const Color(0xFFE30613).withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
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
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddServicePage(
                  uid: service.providerUid,
                  existingService: service,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: service.isActive 
                        ? const Color(0xFFE30613).withValues(alpha: 0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _getIconForType(service.serviceType),
                    color: service.isActive ? const Color(0xFFE30613) : Colors.grey.shade500,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
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
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: service.isActive ? Colors.black87 : Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!service.isActive) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: const Text(
                                'Paused',
                                style: TextStyle(fontSize: 10, color: Colors.deepOrange, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        service.plateNumber.isEmpty
                            ? service.displayType
                            : service.plateNumber,
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  position: PopupMenuPosition.under,
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
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 20, color: Colors.grey.shade700),
                          const SizedBox(width: 12),
                          const Text('Edit service'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(
                        children: [
                          Icon(service.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 20, color: Colors.grey.shade700),
                          const SizedBox(width: 12),
                          Text(service.isActive ? 'Pause service' : 'Restart service'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 20, color: Colors.red),
                          SizedBox(width: 12),
                          Text('Remove service', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIconForType(ServiceType type) {
    switch (type) {
      case ServiceType.towTruck:
        return Icons.local_shipping_outlined;
      case ServiceType.mechanic:
        return Icons.build_outlined;
      case ServiceType.fuelDelivery:
        return Icons.local_gas_station_outlined;
      case ServiceType.flatTireChange:
        return Icons.tire_repair_outlined;
      case ServiceType.batteryBoost:
        return Icons.battery_charging_full_outlined;
    }
  }
}

class _AddServiceCard extends StatelessWidget {
  final String uid;
  const _AddServiceCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openAdd(context, uid),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFE30613).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFE30613).withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, size: 24, color: Color(0xFFE30613)),
            SizedBox(width: 12),
            Text(
              'Add New Service',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFFE30613),
              ),
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
  Widget build(BuildContext context) => Center(child: Text(message, style: const TextStyle(color: Colors.grey)));
}

void _openAdd(BuildContext context, String uid) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => AddServicePage(uid: uid)),
  );
}
