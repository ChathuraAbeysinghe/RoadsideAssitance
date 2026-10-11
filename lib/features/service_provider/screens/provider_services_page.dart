import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../entities/app_user.dart';
import '../../_share/navbar/app_bottom_nav_bar.dart';
import '../models/provider_service.dart';
import '../models/provider_station.dart';
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildServicesTab(),
                    _buildStationsTab(context),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar:
            AppBottomNavBar(userType: userType, activeIndex: 2),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F2F4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TabBar(
          indicator: BoxDecoration(
            color: const Color(0xFFE30613),
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE30613).withValues(alpha: 0.25),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey.shade700,
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: 'Services'),
            Tab(text: 'Service Stations'),
          ],
        ),
      ),
    );
  }

  Widget _buildServicesTab() {
    return StreamBuilder<List<ProviderService>>(
      stream: ProviderRepository().watchServices(_resolvedUid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _Message(message: 'Unable to load services.');
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFE30613)),
          );
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
    );
  }

  Widget _buildStationsTab(BuildContext context) {
    return StreamBuilder<List<ProviderStation>>(
      stream: ProviderRepository().watchStations(_resolvedUid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _Message(message: 'Unable to load service stations.');
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFE30613)),
          );
        }
        final stations = snapshot.data!;
        if (stations.isEmpty) {
          return _EmptyStations(
            uid: _resolvedUid,
            onAdd: () => _openAddStationSheet(context, _resolvedUid),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _buildStationSectionHeader(stations.length),
            const SizedBox(height: 16),
            ...stations.map(
              (station) => _StationCard(
                station: station,
                onEdit: () => _openAddStationSheet(
                  context,
                  _resolvedUid,
                  existingStation: station,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _AddStationCard(
              onTap: () => _openAddStationSheet(context, _resolvedUid),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStationSectionHeader(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Service Stations',
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

  void _openAddStationSheet(
    BuildContext context,
    String uid, {
    ProviderStation? existingStation,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _StationFormSheet(uid: uid, existingStation: existingStation),
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
                icon: const Icon(
                  Icons.chevron_left,
                  color: Colors.black87,
                  size: 24,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
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
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 18,
                    ),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Image.asset(
                        _getIconAssetPath(service),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
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
                                  service.name.isEmpty
                                      ? service.displayType
                                      : service.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: service.isActive
                                        ? Colors.black87
                                        : Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!service.isActive) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.orange.shade200,
                                    ),
                                  ),
                                  child: const Text(
                                    'Paused',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.deepOrange,
                                      fontWeight: FontWeight.w700,
                                    ),
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
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: Colors.grey.shade600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                            Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: Colors.grey.shade700,
                            ),
                            const SizedBox(width: 12),
                            const Text('Edit service'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Row(
                          children: [
                            Icon(
                              service.isActive
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              size: 20,
                              color: Colors.grey.shade700,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              service.isActive
                                  ? 'Pause service'
                                  : 'Restart service',
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.red,
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Remove service',
                              style: TextStyle(color: Colors.red),
                            ),
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
          border: Border.all(color: const Color(0xFFE30613), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFE30613),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
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
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 28),
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
  Widget build(BuildContext context) => Center(
        child: Text(message, style: const TextStyle(color: Colors.grey)),
      );
}

void _openAdd(BuildContext context, String uid) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => AddServicePage(uid: uid)),
  );
}

class _EmptyStations extends StatelessWidget {
  final String uid;
  final VoidCallback onAdd;

  const _EmptyStations({required this.uid, required this.onAdd});

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
            child: const Icon(
              Icons.storefront_rounded,
              size: 80,
              color: Color(0xFFE30613),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Your service stations will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You haven\'t added any service stations yet. Add your garage, repair shop, or service center so nearby drivers can find it.',
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
              onPressed: onAdd,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Service Station',
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

class _StationCard extends StatelessWidget {
  final ProviderStation station;
  final VoidCallback onEdit;

  const _StationCard({required this.station, required this.onEdit});

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
            onTap: onEdit,
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: station.isActive
                          ? const Color(0xFFE30613)
                          : Colors.grey.shade400,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 18,
                    ),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: station.isActive
                            ? const Color(0xFFE30613).withValues(alpha: 0.08)
                            : Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getStationIcon(station.stationType),
                        color: station.isActive
                            ? const Color(0xFFE30613)
                            : Colors.grey.shade500,
                        size: 24,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  station.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: station.isActive
                                        ? Colors.black87
                                        : Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (!station.isActive) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.orange.shade200,
                                    ),
                                  ),
                                  child: const Text(
                                    'Paused',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.deepOrange,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            station.stationType,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (station.address.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 14,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    station.address,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 14,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                station.operatingHours,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          if (!station.hasLocation) ...[
                            const SizedBox(height: 4),
                            const Text(
                              'Location not set. Edit to appear for drivers.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: Colors.grey.shade600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    position: PopupMenuPosition.under,
                    onSelected: (value) async {
                      if (value == 'edit') {
                        onEdit();
                      } else if (value == 'toggle') {
                        await ProviderRepository().updateStation(
                          station.copyWith(isActive: !station.isActive),
                        );
                      } else if (value == 'delete') {
                        await ProviderRepository().deleteStation(station.id);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: Colors.grey.shade700,
                            ),
                            const SizedBox(width: 12),
                            const Text('Edit station'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Row(
                          children: [
                            Icon(
                              station.isActive
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              size: 20,
                              color: Colors.grey.shade700,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              station.isActive
                                  ? 'Pause station'
                                  : 'Restart station',
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.red,
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Remove station',
                              style: TextStyle(color: Colors.red),
                            ),
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

  IconData _getStationIcon(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('fuel') || lower.contains('gas')) {
      return Icons.local_gas_station_rounded;
    }
    if (lower.contains('tire') || lower.contains('battery')) {
      return Icons.build_circle_rounded;
    }
    if (lower.contains('wash')) {
      return Icons.local_car_wash_rounded;
    }
    return Icons.garage_rounded;
  }
}

class _AddStationCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddStationCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE30613), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFE30613),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Service Station',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Register a garage or service center',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 28),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------
// Add / edit station form
// -----------------------------------------------
class _StationFormSheet extends StatefulWidget {
  final String uid;
  final ProviderStation? existingStation;

  const _StationFormSheet({required this.uid, this.existingStation});

  @override
  State<_StationFormSheet> createState() => _StationFormSheetState();
}

class _StationFormSheetState extends State<_StationFormSheet> {
  static const Color _red = Color(0xFFE30613);
  static const LatLng _fallback = LatLng(6.9271, 79.8612);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _priceController;
  final MapController _map = MapController();

  late String _selectedType;
  LatLng? _point;
  bool _is24h = false;
  int _open = 8;
  int _close = 18;
  bool _accepting = true;
  bool _saving = false;
  bool _locating = false;
  bool _mapExpanded = false;
  bool _submitted = false; // show inline errors after first Save tap
  Set<String> _selectedServices = {};

  final List<String> _stationTypes = const [
    'Service Station & Wash',
    'Only Body Wash',
    'Engine oil Change',
    'Multi service',
  ];

  final List<String> _availableServices = const [
    'Full Inspection',
    'Oil Change',
    'Tire Replacement',
    'Battery Service',
    'Car Wash',
    'Engine Repair',
    'Brake Service',
    'Air Filter Change',
    'Coolant Flush',
    'Transmission Repair',
  ];

  @override
  void initState() {
    super.initState();
    final s = widget.existingStation;
    _nameController = TextEditingController(text: s?.name ?? '');
    _addressController = TextEditingController(text: s?.address ?? '');
    _phoneController = TextEditingController(text: s?.phone ?? '');
    _priceController = TextEditingController(
      text: (s != null && s.fullServicePrice > 0)
          ? s.fullServicePrice.toStringAsFixed(0)
          : '',
    );
    // Ensure the selected type exists in the new list
    final stationType = s?.stationType ?? _stationTypes.first;
    _selectedType =
        _stationTypes.contains(stationType) ? stationType : _stationTypes.first;
    _selectedServices = s?.services.toSet() ?? {};
    if (s != null) {
      if (s.hasLocation) _point = LatLng(s.latitude, s.longitude);
      _is24h = s.is24h;
      if (!_is24h) {
        _open = s.openHour.clamp(0, 23);
        _close = s.closeHour.clamp(1, 24);
      }
      _accepting = !s.manuallyClosed;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _priceController.dispose();
    _map.dispose();
    super.dispose();
  }

  void _toast(String m, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), backgroundColor: color));
  }

  void _moveMap(LatLng p) {
    try {
      _map.move(p, 16);
    } catch (_) {}
  }

  Future<String> _addressOf(LatLng p) async {
    try {
      final list = await placemarkFromCoordinates(p.latitude, p.longitude);
      if (list.isNotEmpty) {
        final m = list.first;
        final parts = <String>[
          m.name ?? '',
          m.street ?? '',
          m.subLocality ?? '',
          m.locality ?? '',
        ].where((s) => s.trim().isNotEmpty).toSet().toList();
        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (_) {}
    return '';
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('Please turn on location services.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('Location permission is required.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));
      final p = LatLng(pos.latitude, pos.longitude);
      setState(() => _point = p);
      _moveMap(p);
      final a = await _addressOf(p);
      if (mounted && a.isNotEmpty) _addressController.text = a;
    } catch (_) {
      _toast('Could not get your current location.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _findAddressOnMap() async {
    final q = _addressController.text.trim();
    if (q.isEmpty) {
      _toast('Type the address first.');
      return;
    }
    FocusScope.of(context).unfocus();
    try {
      final res = await locationFromAddress(q);
      if (res.isEmpty) {
        _toast('Address not found. Try a more specific address.');
        return;
      }
      final p = LatLng(res.first.latitude, res.first.longitude);
      setState(() => _point = p);
      _moveMap(p);
    } catch (_) {
      _toast('Address not found. Try a more specific address.');
    }
  }

  Future<void> _onMapTap(LatLng p) async {
    setState(() => _point = p);
    final a = await _addressOf(p);
    if (mounted && a.isNotEmpty) _addressController.text = a;
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);

    final formOk = _formKey.currentState!.validate();
    final servicesOk = _selectedServices.isNotEmpty;
    final pinOk = _point != null;

    if (!formOk || !servicesOk || !pinOk) {
      _toast('Please fill in all required fields.');
      return;
    }
    if (!_is24h && _open >= _close) {
      _toast('Closing time must be after opening time.');
      return;
    }

    final price = double.parse(_priceController.text.trim());

    setState(() => _saving = true);

    try {
      LatLng? p = _point;
      if (p == null) {
        try {
          final res = await locationFromAddress(_addressController.text.trim());
          if (res.isNotEmpty) {
            p = LatLng(res.first.latitude, res.first.longitude);
          }
        } catch (_) {}
      }
      if (p == null) {
        _toast(
          'Set the location: tap the map, use current location, or find the address.',
        );
        if (mounted) setState(() => _saving = false);
        return;
      }

      final serviceList = _selectedServices.toList();
      final openHour = _is24h ? 0 : _open;
      final closeHour = _is24h ? 24 : _close;

      if (widget.existingStation != null) {
        await ProviderRepository().updateStation(
          widget.existingStation!.copyWith(
            name: _nameController.text.trim(),
            stationType: _selectedType,
            address: _addressController.text.trim(),
            phone: _phoneController.text.trim(),
            latitude: p.latitude,
            longitude: p.longitude,
            fullServicePrice: price,
            openHour: openHour,
            closeHour: closeHour,
            manuallyClosed: !_accepting,
            services: serviceList,
          ),
        );
      } else {
        await ProviderRepository().addStation(
          ProviderStation(
            id: '',
            providerUid: widget.uid,
            name: _nameController.text.trim(),
            stationType: _selectedType,
            address: _addressController.text.trim(),
            phone: _phoneController.text.trim(),
            latitude: p.latitude,
            longitude: p.longitude,
            fullServicePrice: price,
            openHour: openHour,
            closeHour: closeHour,
            manuallyClosed: !_accepting,
            services: serviceList,
            isActive: true,
            rating: 5.0,
            reviewCount: 0,
          ),
        );
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existingStation != null
                  ? 'Service station updated successfully.'
                  : 'Service station added successfully.',
            ),
            backgroundColor: const Color(0xFF1E9E4A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('Failed to save: $e', color: _red);
      }
    }
  }

  InputDecoration _dec(String hint, {IconData? icon}) => InputDecoration(
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _red),
        ),
      );

  Widget _label(String t, {bool required = true}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(
          TextSpan(
            text: t,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            children: [
              if (required)
                const TextSpan(text: ' *', style: TextStyle(color: _red)),
            ],
          ),
        ),
      );

  Widget _hourDropdown(
    String label,
    int value,
    List<int> options,
    ValueChanged<int> onChanged,
  ) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: options
          .map(
            (h) => DropdownMenuItem(
              value: h,
              child: Text(ProviderStation.hourLabel(h)),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(top: 60, bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.existingStation != null
                          ? 'Edit Service Station'
                          : 'Add Service Station',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Open / Closed quick switch
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_accepting ? const Color(0xFF1E9E4A) : _red)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _accepting
                              ? 'Open for customers (during working hours)'
                              : 'Marked as Closed',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _accepting
                                ? const Color(0xFF1E9E4A)
                                : _red,
                          ),
                        ),
                      ),
                      Switch(
                        value: _accepting,
                        activeThumbColor: const Color(0xFF1E9E4A),
                        onChanged: (v) => setState(() => _accepting = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                _label('Station Category'),
                DropdownButtonFormField<String>(
                  initialValue: _selectedType,
                  decoration: _dec(''),
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'Please select a station category'
                      : null,
                  items: _stationTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedType = val);
                  },
                ),
                const SizedBox(height: 14),

                _label('Station Name'),
                TextFormField(
                  controller: _nameController,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Please enter station name'
                      : null,
                  decoration: _dec('e.g., Apex Auto Care & Garage'),
                ),
                const SizedBox(height: 14),

                _label('Contact Phone'),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter contact number';
                    }
                    final digits = v.trim().replaceAll(RegExp(r'\D'), '');
                    if (digits.length != 10) {
                      return 'Phone number must be exactly 10 digits';
                    }
                    return null;
                  },
                  decoration: _dec(
                    'e.g., 0112345678',
                    icon: Icons.phone_outlined,
                  ).copyWith(counterText: ''),
                ),
                const SizedBox(height: 14),

                _label('Full Service Price (LKR)'),
                TextFormField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter the price';
                    }
                    final value = double.tryParse(v.trim());
                    if (value == null || value <= 0) {
                      return 'Price must be greater than 0';
                    }
                    return null;
                  },
                  decoration:
                      _dec('e.g., 12500', icon: Icons.payments_outlined),
                ),
                const SizedBox(height: 14),

                _label('Address / Location'),
                TextFormField(
                  controller: _addressController,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Please enter address'
                      : null,
                  decoration: _dec(
                    'e.g., Kandy Road, Malabe',
                    icon: Icons.location_on_outlined,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _findAddressOnMap,
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text(
                          'Find on map',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _locating ? null : _useCurrentLocation,
                        icon: _locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location, size: 18),
                        label: const Text(
                          'Use current',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: _mapExpanded ? 300 : 170,
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _map,
                          options: MapOptions(
                            initialCenter: _point ?? _fallback,
                            initialZoom: _point == null ? 11 : 16,
                            onTap: (_, p) => _onMapTap(p),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName:
                                  'com.example.roadside_assitance',
                            ),
                            if (_point != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _point!,
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.topCenter,
                                    child: const Icon(
                                      Icons.location_on,
                                      size: 44,
                                      color: _red,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: FloatingActionButton.small(
                            backgroundColor: Colors.white,
                            foregroundColor: _red,
                            onPressed: () =>
                                setState(() => _mapExpanded = !_mapExpanded),
                            child: Icon(
                              _mapExpanded
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _point == null
                      ? (_submitted
                          ? 'Please select a location on the map'
                          : 'Tap the map to drop a pin on your exact shop location.')
                      : 'Pin set. Tap the map to move it.',
                  style: TextStyle(
                    fontSize: 11,
                    color: (_submitted && _point == null)
                        ? _red
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 14),

                _label('Working Hours', required: false),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: _red,
                  title: const Text('Open 24 hours'),
                  value: _is24h,
                  onChanged: (v) => setState(() => _is24h = v),
                ),
                if (!_is24h)
                  Row(
                    children: [
                      Expanded(
                        child: _hourDropdown(
                          'Opens',
                          _open,
                          List.generate(24, (i) => i),
                          (v) => setState(() => _open = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _hourDropdown(
                          'Closes',
                          _close,
                          List.generate(24, (i) => i + 1),
                          (v) => setState(() => _close = v),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),

                _label('Services Offered'),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: (_submitted && _selectedServices.isEmpty)
                          ? _red
                          : Colors.grey.shade300,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    children: [
                      for (int i = 0; i < _availableServices.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            _availableServices[i],
                            style: const TextStyle(fontSize: 13),
                          ),
                          value:
                              _selectedServices.contains(_availableServices[i]),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedServices.add(_availableServices[i]);
                              } else {
                                _selectedServices.remove(_availableServices[i]);
                              }
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                if (_submitted && _selectedServices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Please select at least one service',
                      style: TextStyle(fontSize: 12, color: _red),
                    ),
                  ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            widget.existingStation != null
                                ? 'Update Station'
                                : 'Save Station',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}