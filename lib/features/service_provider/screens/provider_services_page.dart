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
      backgroundColor: const Color(0xFFF5F5F5),
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
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      _buildSectionHeader(services.length),
                      const SizedBox(height: 16),
                      ...services.map((service) => _ServiceCard(service: service)),
                      const SizedBox(height: 8),
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

  Widget _buildSectionHeader(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Services',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFFE30613),
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
                'My Services',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Manage your vehicles',
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
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
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
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Red left accent border
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: service.isActive
                          ? const Color(0xFFE30613)
                          : Colors.grey.shade400,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                  ),
                  // Service icon
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Image.asset(
                        _getIconAssetPath(service),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  // Service info
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  service.name.isEmpty ? service.displayType : service.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
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
                          const SizedBox(height: 4),
                          Text(
                            service.plateNumber.isEmpty
                                ? service.displayType
                                : service.plateNumber,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // More menu
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade600),
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
      ),
    );
  }

  /// Returns the correct icon asset path based on the service type.
  /// For tow trucks, differentiates between Wheel Lift and Flat Bed
  /// based on the vehicleTypes field.
  String _getIconAssetPath(ProviderService service) {
    switch (service.serviceType) {
      case ServiceType.towTruck:
        final vt = service.vehicleTypes.toLowerCase();
        if (vt.contains('flat')) {
          return 'assets/icon/icon-flatbed.png';
        }
        return 'assets/icon/icon-tow-truck.png';
      case ServiceType.mechanic:
        return 'assets/icon/icon-automobile.png';
      case ServiceType.fuelDelivery:
        return 'assets/icon/icon-gas-station.png';
      case ServiceType.flatTireChange:
        return 'assets/icon/icon-wheels.png';
      case ServiceType.batteryBoost:
        return 'assets/icon/icon-jump-start.png';
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFE30613),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Red circle with + icon
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFE30613),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            // Text content
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add New Service',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Register a new vehicle',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            // Chevron right
            Icon(
              Icons.chevron_right,
              color: Colors.grey.shade400,
              size: 28,
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
