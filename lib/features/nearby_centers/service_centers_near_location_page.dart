import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../entities/service_center.dart';
import 'service_center_details_page.dart';
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

  // Sample data (4 centres). Replace names/phones/coordinates with real ones.
  static const List<ServiceCenter> _centers = [
    ServiceCenter(
      id: 'sc1',
      name: 'Malabe Auto Care',
      phone: '0112345601',
      address: 'Kaduwela Road, Malabe',
      latitude: 6.9071,
      longitude: 79.9650,
      fullServicePrice: 12500,
      rating: 4.6,
      reviewCount: 128,
      openHour: 8,
      closeHour: 18,
    ),
    ServiceCenter(
      id: 'sc2',
      name: 'Speedway Service Station',
      phone: '0112345602',
      address: 'New Kandy Road, Malabe',
      latitude: 6.9140,
      longitude: 79.9720,
      fullServicePrice: 14800,
      rating: 4.3,
      reviewCount: 86,
      openHour: 7,
      closeHour: 20,
    ),
    ServiceCenter(
      id: 'sc3',
      name: 'Pro Motors Garage',
      phone: '0112345603',
      address: 'Athurugiriya Road, Malabe',
      latitude: 6.8990,
      longitude: 79.9580,
      fullServicePrice: 11200,
      rating: 4.0,
      reviewCount: 54,
      openHour: 9,
      closeHour: 17,
    ),
    ServiceCenter(
      id: 'sc4',
      name: 'City 24H Auto Service',
      phone: '0112345604',
      address: 'Battaramulla Road, Thalahena',
      latitude: 6.9200,
      longitude: 79.9500,
      fullServicePrice: 16500,
      rating: 4.8,
      reviewCount: 203,
      openHour: 0,
      closeHour: 24,
    ),
  ];

  List<ServiceCenter> _sorted() {
    final list = _centers
        .map(
          (c) => c.copyWith(
            distanceKm: Geolocator.distanceBetween(
                  location.latitude,
                  location.longitude,
                  c.latitude,
                  c.longitude,
                ) /
                1000,
          ),
        )
        .toList();
    list.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return list;
  }

  Future<void> _call(String phone) async {
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  @override
  Widget build(BuildContext context) {
    final centers = _sorted();

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
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: centers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final c = centers[i];
                return _card(context, c);
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
                            const Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.amber,
                            ),
                            Text(
                              ' ${c.rating.toStringAsFixed(1)} (${c.reviewCount})',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Open / Closed badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
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
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
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
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
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