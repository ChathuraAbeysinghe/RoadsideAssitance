import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

import '../../../entities/app_user.dart';
import '../../../entities/service_request.dart';

/// Represents a scored and explained provider recommendation.
class RecommendedProvider {
  final String uid;
  final String name;
  final String phoneNumber;
  final String profileImagePath;
  final double distanceKm;
  final double rating;
  final int ratingCount;
  final double compositeScore;
  final List<String> recommendationReasons;
  final ServiceType serviceType;

  const RecommendedProvider({
    required this.uid,
    required this.name,
    required this.phoneNumber,
    this.profileImagePath = '',
    required this.distanceKm,
    required this.rating,
    required this.ratingCount,
    required this.compositeScore,
    required this.recommendationReasons,
    required this.serviceType,
  });
}

class ProviderRecommendationService {
  final FirebaseFirestore _firestore;

  ProviderRecommendationService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Weights for multi-criteria transparent ranking (normalized sum = 1.0).
  static const double distanceWeight = 0.60;
  static const double ratingWeight = 0.40;

  /// Finds and ranks available providers matching the confirmed [service] near [driverLocation].
  Future<List<RecommendedProvider>> recommendProviders({
    required ServiceType service,
    required LatLng driverLocation,
    double maxRadiusKm = 15.0,
  }) async {
    // 1. Strict Eligibility Query: providers that offer the service and are online
    final snapshot = await _firestore
        .collection('users')
        .where('userType', isEqualTo: UserType.assistanceProvider.name)
        .where('isAvailable', isEqualTo: true)
        .where('services', arrayContains: service.name)
        .get();

    final List<RecommendedProvider> ranked = [];
    const distanceCalc = Distance();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final provider = userFromMap(doc.id, data);
      if (provider is! AssistanceProvider) continue;

      // Location resolution (matches existing watchNearbyProviders logic)
      GeoLocation providerGeo = provider.currentLocation;
      try {
        final psSnap = await _firestore
            .collection('providerServices')
            .where('providerUid', isEqualTo: doc.id)
            .where('serviceType', isEqualTo: service.name)
            .where('isActive', isEqualTo: true)
            .get();

        if (psSnap.docs.isNotEmpty) {
          final locMap = psSnap.docs.first.data()['locationGeo'] as Map<String, dynamic>?;
          if (locMap != null) {
            final parsed = GeoLocation.fromMap(locMap);
            if (parsed.latitude != 0 || parsed.longitude != 0) {
              providerGeo = parsed;
            }
          }
        }
      } catch (_) {}

      if (providerGeo.latitude == 0 && providerGeo.longitude == 0) continue;

      // Distance calculation in kilometers
      final distKm = distanceCalc.as(
        LengthUnit.Kilometer,
        driverLocation,
        LatLng(providerGeo.latitude, providerGeo.longitude),
      );

      // Distance eligibility constraint
      if (distKm > maxRadiusKm) continue;

      // 2. Multi-Criteria Transparent Ranking
      final distScore = math.max(0.0, 1.0 - (distKm / maxRadiusKm));

      // Damped rating score (Bayesian prior: 3.5 stars, weight 3)
      const priorStars = 3.5;
      const priorWeight = 3;
      final rawRating = provider.rating.average;
      final count = provider.rating.count;

      double ratingScore;
      if (count > 0) {
        final dampedRating =
            ((rawRating * count) + (priorStars * priorWeight)) /
                (count + priorWeight);
        ratingScore = (dampedRating / 5.0).clamp(0.0, 1.0);
      } else {
        ratingScore = priorStars / 5.0;
      }

      final composite = (distanceWeight * distScore) + (ratingWeight * ratingScore);

      // 3. Transparent explainability tags
      final List<String> reasons = [
        'Offers ${serviceTypeTitle(service)}',
      ];
      if (distKm <= 3.0) {
        reasons.add('Closest to your location (${distKm.toStringAsFixed(1)} km)');
      } else if (distKm <= 7.0) {
        reasons.add('Nearby provider (${distKm.toStringAsFixed(1)} km)');
      } else {
        reasons.add('${distKm.toStringAsFixed(1)} km away');
      }

      if (rawRating >= 4.5 && count >= 2) {
        reasons.add('Top-rated (${rawRating.toStringAsFixed(1)} ★)');
      } else if (rawRating >= 4.0 && count >= 1) {
        reasons.add('Well-rated (${rawRating.toStringAsFixed(1)} ★)');
      } else if (count == 0) {
        reasons.add('New verified provider');
      }

      ranked.add(
        RecommendedProvider(
          uid: provider.uid,
          name: provider.name.isNotEmpty ? provider.name : 'Service Provider',
          phoneNumber: provider.phoneNumber,
          profileImagePath: provider.profileImagePath,
          distanceKm: distKm,
          rating: rawRating,
          ratingCount: count,
          compositeScore: composite,
          recommendationReasons: reasons,
          serviceType: service,
        ),
      );
    }

    // Sort descending by transparent composite score
    ranked.sort((a, b) => b.compositeScore.compareTo(a.compositeScore));
    return ranked;
  }

  /// Pure ranking function for local list evaluation and offline/unit testing.
  static List<RecommendedProvider> rankLocalCandidates({
    required List<AssistanceProvider> providers,
    required ServiceType service,
    required LatLng driverLocation,
    double maxRadiusKm = 15.0,
  }) {
    const distanceCalc = Distance();
    final List<RecommendedProvider> ranked = [];

    for (final p in providers) {
      if (!p.isAvailable || !p.services.contains(service)) continue;
      if (p.currentLocation.latitude == 0 && p.currentLocation.longitude == 0) continue;

      final distKm = distanceCalc.as(
        LengthUnit.Kilometer,
        driverLocation,
        LatLng(p.currentLocation.latitude, p.currentLocation.longitude),
      );
      if (distKm > maxRadiusKm) continue;

      final distScore = math.max(0.0, 1.0 - (distKm / maxRadiusKm));
      final count = p.rating.count;
      final rawRating = p.rating.average;

      double ratingScore;
      if (count > 0) {
        final damped = ((rawRating * count) + (3.5 * 3)) / (count + 3);
        ratingScore = (damped / 5.0).clamp(0.0, 1.0);
      } else {
        ratingScore = 3.5 / 5.0;
      }

      final composite = (distanceWeight * distScore) + (ratingWeight * ratingScore);
      final List<String> reasons = ['Offers ${serviceTypeTitle(service)}'];
      if (distKm <= 3.0) {
        reasons.add('Closest to your location (${distKm.toStringAsFixed(1)} km)');
      } else {
        reasons.add('${distKm.toStringAsFixed(1)} km away');
      }
      if (rawRating >= 4.5 && count >= 2) {
        reasons.add('Top-rated (${rawRating.toStringAsFixed(1)} ★)');
      }

      ranked.add(
        RecommendedProvider(
          uid: p.uid,
          name: p.name,
          phoneNumber: p.phoneNumber,
          profileImagePath: p.profileImagePath,
          distanceKm: distKm,
          rating: rawRating,
          ratingCount: count,
          compositeScore: composite,
          recommendationReasons: reasons,
          serviceType: service,
        ),
      );
    }

    ranked.sort((a, b) => b.compositeScore.compareTo(a.compositeScore));
    return ranked;
  }
}
