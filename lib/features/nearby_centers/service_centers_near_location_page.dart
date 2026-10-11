import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../entities/service_center.dart';
import '../service_provider/models/provider_station.dart';
import 'service_center_receipt_page.dart';

class ServiceCentersNearLocationPage extends StatelessWidget {
  final LatLng location;
  final String address;

  const ServiceCentersNearLocationPage({
    super.key,
    required this.location,
    required this.address,
  });

  static const Color _red = Color(0xFFE30613);
  static const Color _green = Color(0xFF1E9E4A);

  /// Only centers within this distance are shown.
  static const double radiusKm = 50;

  /// Builds the list from provider-registered stations.
  List<ServiceCenter> _parse(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = <ServiceCenter>[];
    for (final doc in snap.docs) {
      try {
        final s = ProviderStation.fromMap(doc.id, doc.data());
        if (!s.isActive || !s.hasLocation || s.name.isEmpty) continue;
        if (s.stationType.toLowerCase().contains('fuel')) continue;

        final km = Geolocator.distanceBetween(
              location.latitude,
              location.longitude,
              s.latitude,
              s.longitude,
            ) /
            1000;
        if (km > radiusKm) continue;

        list.add(
          ServiceCenter(
            id: s.id,
            name: s.name,
            phone: s.phone,
            address: s.address,
            latitude: s.latitude,
            longitude: s.longitude,
            fullServicePrice: s.fullServicePrice,
            rating: s.rating,
            reviewCount: s.reviewCount,
            distanceKm: km,
            openHour: s.openHour,
            closeHour: s.closeHour,
            ownerId: s.providerUid,
            manuallyClosed: s.manuallyClosed,
          ),
        );
      } catch (_) {
        // skip documents with wrong field types
      }
    }
    list.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return list;
  }

  Future<void> _call(String phone) async {
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text(
          'Nearby Service Centers',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: _red, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    address.isEmpty ? 'Selected location' : address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('providerStations')
                  .where('isActive', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Unable to load service centers.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _red),
                  );
                }
                final centers = _parse(snapshot.data!);
                if (centers.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_off_outlined, color: _red, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            'No service centers within ${radiusKm.toStringAsFixed(0)} km',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Service stations are available in other areas. You can try moving to a different location.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: centers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _card(context, centers[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, ServiceCenter c) {
    final open = c.isOpenNow;
    final statusColor = open ? _green : _red;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ServiceCenterReceiptPage(
                center: c,
                userLocation: location,
                userAddress: address,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDE8EA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.car_repair, color: _red),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.star, size: 14, color: Colors.amber),
                            Text(
                              ' ${c.rating.toStringAsFixed(1)} (${c.reviewCount})',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      open ? 'Open' : 'Closed',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: Colors.grey.shade200, height: 1),
              const SizedBox(height: 12),
              _info(Icons.place_outlined, c.address),
              const SizedBox(height: 6),
              _info(Icons.access_time, c.hoursLabel),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Full Service',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        Text(
                          'LKR ${c.fullServicePrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Distance',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      Text(
                        '${c.distanceKm.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _call(c.phone),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFAD1D4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.phone, color: _red, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _info(Icons.phone_outlined, c.phone),
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
      ],
    );
  }
}