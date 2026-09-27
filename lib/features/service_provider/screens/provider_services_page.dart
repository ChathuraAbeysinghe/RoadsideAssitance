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
      appBar: AppBar(
        title: const Text(
          'Services',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        leading: const BackButton(),
      ),
      body: StreamBuilder<List<ProviderService>>(
        stream: ProviderRepository().watchServices(_resolvedUid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message(message: 'Unable to load services.');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final services = snapshot.data!;
          if (services.isEmpty) {
            return _EmptyServices(uid: _resolvedUid);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              ...services.map((service) => _ServiceCard(service: service)),
              _AddServiceCard(uid: _resolvedUid),
            ],
          );
        },
      ),
      bottomNavigationBar: AppBottomNavBar(userType: userType, activeIndex: 2),
    );
  }
}

class _EmptyServices extends StatelessWidget {
  final String uid;
  const _EmptyServices({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/icon/icon-add_service_emppage.png',
              height: 210,
            ),
            const SizedBox(height: 28),
            const Text(
              'Your service will appear here',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              'Add your vehicles and list the services you provide so customers can find and book you.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 28),
            _RedButton(
              label: 'Add New Service',
              onPressed: () => _openAdd(context, uid),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final ProviderService service;
  const _ServiceCard({required this.service});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Image.asset(
          _serviceIcon(service.serviceType),
          width: 56,
          height: 56,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.build_circle_outlined, size: 48),
        ),
        title: Text(
          service.name.isEmpty ? service.displayType : service.name,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          service.plateNumber.isEmpty
              ? service.displayType
              : service.plateNumber,
          style: const TextStyle(fontSize: 18, color: Colors.grey),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'delete') {
              await ProviderRepository().deleteService(service);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'delete', child: Text('Remove service')),
          ],
        ),
      ),
    );
  }
}

class _AddServiceCard extends StatelessWidget {
  final String uid;
  const _AddServiceCard({required this.uid});

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
      leading: const Icon(Icons.add, size: 38),
      title: const Text('Add Service', style: TextStyle(fontSize: 20)),
      onTap: () => _openAdd(context, uid),
    ),
  );
}

class _Message extends StatelessWidget {
  final String message;
  const _Message({required this.message});
  @override
  Widget build(BuildContext context) => Center(child: Text(message));
}

class _RedButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _RedButton({required this.label, required this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

void _openAdd(BuildContext context, String uid) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => AddServicePage(uid: uid)),
  );
}

String _serviceIcon(ServiceType type) => switch (type) {
  ServiceType.towTruck => 'assets/images/icon-towtruck.png',
  ServiceType.mechanic => 'assets/images/icon-mechanic.png',
  ServiceType.fuelDelivery => 'assets/images/icon-jerrycan.png',
  ServiceType.flatTireChange => 'assets/images/icon-flattire.png',
  ServiceType.batteryBoost => 'assets/images/icon-battery.png',
};
