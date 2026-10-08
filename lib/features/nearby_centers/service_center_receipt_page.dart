import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../entities/service_center.dart';
import 'service_center_details_page.dart';


class ServiceCenterReceiptPage extends StatelessWidget {
  final ServiceCenter center;
  final LatLng userLocation;
  final String userAddress;

  const ServiceCenterReceiptPage({
    super.key,
    required this.center,
    required this.userLocation,
    required this.userAddress,
  });

  static const Color _red = Color(0xFFE30613);
  static const Color _green = Color(0xFF1E9E4A);

  // ---------- helpers ----------
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  String _time(DateTime d) {
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h12:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// Average city speed of 30 km/h.
  int get _etaMinutes => (center.distanceKm / 30 * 60).ceil().clamp(1, 9999);

  String get _etaLabel {
    final m = _etaMinutes;
    if (m < 60) return '$m minutes';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '$h hours' : '$h hours $r minutes';
  }

  Future<void> _call() async {
    await launchUrl(Uri(scheme: 'tel', path: center.phone));
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final arrival = now.add(Duration(minutes: _etaMinutes));
    final open = center.isOpenNow;
    final statusColor = open ? _green : _red;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new, size: 16),
                ),
              ),
              const SizedBox(height: 16),

              // ID + name/phone
              Text(
                'ID ${center.id.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${center.name}  ${center.phone}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 14),

              // Service type + date
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDE8EA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.car_repair, color: _red, size: 20),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Full Service',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _date(now),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _time(now),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(color: Colors.grey.shade300, height: 1),
              const SizedBox(height: 8),

              // Status + stars
              Row(
                children: [
                  Text(
                    open ? 'Open Now' : 'Closed',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                  const Spacer(),
                  ...List.generate(5, (i) {
                    final filled = i < center.rating.round();
                    return Icon(
                      filled ? Icons.star : Icons.star_border,
                      size: 18,
                      color: Colors.amber,
                    );
                  }),
                ],
              ),
              const SizedBox(height: 16),

              // Centre card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: const Color(0xFFFDE8EA),
                      child: Text(
                        center.name.isNotEmpty
                            ? center.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: _red,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            center.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Service center',
                            style: TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(
                                Icons.star,
                                size: 13,
                                color: Colors.amber,
                              ),
                              Text(
                                ' ${center.rating.toStringAsFixed(1)} '
                                '(${center.reviewCount} reviews)',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _call,
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
              ),
              const SizedBox(height: 22),

              // Route: your location -> centre
              _routeRow(
                icon: Icons.my_location,
                title: userAddress.isEmpty ? 'Your location' : userAddress,
                time: _time(now),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 11),
                child: Column(
                  children: List.generate(
                    3,
                    (_) => Container(
                      width: 2,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
              _routeRow(
                icon: Icons.location_on_outlined,
                title: center.address,
                time: '${_time(arrival)} (estimated arrival)',
              ),
              const SizedBox(height: 24),

              // Receipt
              const Text(
                'Receipt',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              _line('Full Service Price',
                  'LKR ${center.fullServicePrice.toStringAsFixed(2)}',
                  strong: true),
              const SizedBox(height: 8),
              _line('Estimated Duration', _etaLabel),
              const SizedBox(height: 8),
              _line('Estimated Distance',
                  '${center.distanceKm.toStringAsFixed(2)} km'),
              const SizedBox(height: 8),
              _line('Working Hours', center.hoursLabel),
              const SizedBox(height: 8),
              _line('Status', open ? 'Open' : 'Closed',
                  valueColor: statusColor, strong: true),
              const SizedBox(height: 8),
              _line('Rating',
                  '${center.rating.toStringAsFixed(1)} / 5.0'),
              const SizedBox(height: 8),
              _line('Contact', center.phone),
              const SizedBox(height: 12),
              Divider(color: Colors.grey.shade300, height: 1),
              const SizedBox(height: 12),
              _line('Total Service Fare',
                  'LKR ${center.fullServicePrice.toStringAsFixed(2)}',
                  strong: true, dark: true),
              const SizedBox(height: 28),

              // Actions
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ServiceCenterDetailsPage(
                          center: center,
                          userLatitude: userLocation.latitude,
                          userLongitude: userLocation.longitude,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.navigation, size: 18),
                  label: const Text(
                    'View on Map & Navigate',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: const BorderSide(color: _red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: _call,
                  icon: const Icon(Icons.phone, size: 18),
                  label: const Text(
                    'Call Service Center',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _routeRow({
    required IconData icon,
    required String title,
    required String time,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: Colors.black87),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                time,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _line(
    String label,
    String value, {
    bool strong = false,
    bool dark = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: dark ? FontWeight.w800 : FontWeight.w500,
            color: dark ? Colors.black : Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              color: valueColor ?? (dark ? Colors.black : Colors.grey.shade700),
            ),
          ),
        ),
      ],
    );
  }
}