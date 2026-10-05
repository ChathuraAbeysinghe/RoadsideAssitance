import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Same identifying User-Agent you already use in request_service.dart.
/// (Move both to one shared constant when you get a chance.)
const String _userAgent = 'RoadsideAssistance/1.0';

class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin;

  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
  });
}

/// Driving route from [a] to [b] using the public OSRM demo server
/// (testing only, replace with your own OSRM / a paid router for production).
Future<RouteResult?> fetchRoute(LatLng a, LatLng b) async {
  try {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${a.longitude},${a.latitude};${b.longitude},${b.latitude}'
      '?overview=full&geometries=geojson',
    );
    final res = await http.get(uri, headers: {'User-Agent': _userAgent});
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;
    final first = routes[0] as Map<String, dynamic>;
    final coords = first['geometry']['coordinates'] as List;
    return RouteResult(
      points: coords
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList(),
      distanceKm: (first['distance'] as num).toDouble() / 1000,
      durationMin: ((first['duration'] as num).toDouble() / 60).round(),
    );
  } catch (_) {
    return null;
  }
}
