import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:roadside_assitance/entities/app_user.dart';
import 'package:roadside_assitance/entities/service_request.dart';
import 'package:roadside_assitance/features/ai_assistant/models/fault_prediction.dart';
import 'package:roadside_assitance/features/ai_assistant/services/provider_recommendation_service.dart';

void main() {
  group('AI Fault Classification - Model & Serialization Tests', () {
    test('parses high-confidence battery boost prediction correctly', () {
      final json = {
        'predicted_category': 'batteryBoost',
        'raw_label': 'battery_boost',
        'confidence': 0.88,
        'requires_clarification': false,
        'explanation': 'Reported symptoms indicate a drained battery or starter issue.',
        'suggested_questions': ['Does it click when starting?'],
        'safety_alert': null,
        'model_version': 'Logistic Regression',
      };

      final prediction = FaultPrediction.fromJson(json);

      expect(prediction.serviceType, ServiceType.batteryBoost);
      expect(prediction.rawCategoryString, 'batteryBoost');
      expect(prediction.rawLabel, 'battery_boost');
      expect(prediction.confidence, 0.88);
      expect(prediction.requiresClarification, isFalse);
      expect(prediction.safetyAlert, isNull);
      expect(prediction.displayTitle, 'Battery Jump-Start');
    });

    test('parses uncertain and ambiguous prediction with questions', () {
      final json = {
        'predicted_category': 'uncertain',
        'raw_label': 'uncertain',
        'confidence': 0.22,
        'requires_clarification': true,
        'explanation': 'Symptom description is ambiguous.',
        'suggested_questions': [
          'Does the engine crank?',
          'Is any tyre punctured?',
        ],
        'safety_alert': null,
        'model_version': 'TFIDF-LogReg-v1.0',
      };

      final prediction = FaultPrediction.fromJson(json);

      expect(prediction.serviceType, isNull);
      expect(prediction.requiresClarification, isTrue);
      expect(prediction.suggestedQuestions.length, 2);
      expect(prediction.displayTitle, 'Uncertain / Please Select');
    });

    test('parses safety hazard alert properly when present', () {
      final json = {
        'predicted_category': 'mechanic',
        'raw_label': 'mechanic',
        'confidence': 0.75,
        'requires_clarification': false,
        'explanation': 'Severe engine overheating.',
        'suggested_questions': [],
        'safety_alert': 'FIRE HAZARD: Evacuate the vehicle immediately and do not start the engine.',
        'model_version': 'TFIDF-LogReg-v1.0',
      };

      final prediction = FaultPrediction.fromJson(json);

      expect(prediction.serviceType, ServiceType.mechanic);
      expect(prediction.safetyAlert, contains('FIRE HAZARD'));
    });

    test('offline fallback initializes with safe defaults', () {
      final fallback = FaultPrediction.offlineFallback('My car broke down');

      expect(fallback.serviceType, isNull);
      expect(fallback.requiresClarification, isTrue);
      expect(fallback.confidence, 0.0);
      expect(fallback.suggestedQuestions.isNotEmpty, isTrue);
    });
  });

  group('Smart Provider Recommendation - Ranking & Eligibility Tests', () {
    final driverLoc = LatLng(6.9271, 79.8612); // Colombo

    final providerA = AssistanceProvider(
      uid: 'p1',
      phoneNumber: '0771234567',
      name: 'Nearby Mechanic Pro',
      services: {ServiceType.mechanic, ServiceType.batteryBoost},
      isAvailable: true,
      currentLocation: GeoLocation(latitude: 6.9300, longitude: 79.8650), // ~0.5 km
      rating: const Rating(totalStars: 48, count: 10), // 4.8 stars
    );

    final providerB = AssistanceProvider(
      uid: 'p2',
      phoneNumber: '0779876543',
      name: 'Faraway Mechanic',
      services: {ServiceType.mechanic},
      isAvailable: true,
      currentLocation: GeoLocation(latitude: 7.0200, longitude: 79.9100), // ~11 km
      rating: const Rating(totalStars: 50, count: 10), // 5.0 stars
    );

    final offlineProvider = AssistanceProvider(
      uid: 'p3',
      phoneNumber: '0770000000',
      name: 'Offline Tech',
      services: {ServiceType.mechanic},
      isAvailable: false,
      currentLocation: GeoLocation(latitude: 6.9280, longitude: 79.8620), // 0.2 km
      rating: const Rating(totalStars: 25, count: 5),
    );

    final wrongService = AssistanceProvider(
      uid: 'p4',
      phoneNumber: '0771112222',
      name: 'Towing Company Only',
      services: {ServiceType.towTruck},
      isAvailable: true,
      currentLocation: GeoLocation(latitude: 6.9275, longitude: 79.8615),
      rating: const Rating(totalStars: 50, count: 10),
    );

    test('filters out offline providers and incompatible services', () {
      final ranked = ProviderRecommendationService.rankLocalCandidates(
        providers: [providerA, providerB, offlineProvider, wrongService],
        service: ServiceType.mechanic,
        driverLocation: driverLoc,
        maxRadiusKm: 15.0,
      );

      final uids = ranked.map((r) => r.uid).toList();
      expect(uids, contains('p1'));
      expect(uids, contains('p2'));
      expect(uids, isNot(contains('p3'))); // offline
      expect(uids, isNot(contains('p4'))); // wrong service
    });

    test('ranks closer provider higher when distance weight is dominant', () {
      final ranked = ProviderRecommendationService.rankLocalCandidates(
        providers: [providerA, providerB],
        service: ServiceType.mechanic,
        driverLocation: driverLoc,
        maxRadiusKm: 15.0,
      );

      expect(ranked.first.uid, 'p1'); // 0.5 km vs 11 km
      expect(ranked.first.distanceKm, lessThan(ranked.last.distanceKm));
      expect(ranked.first.compositeScore, greaterThan(ranked.last.compositeScore));
      expect(ranked.first.recommendationReasons, anyElement(contains('Closest to your location')));
    });

    test('returns empty list when no providers match criteria within radius', () {
      final ranked = ProviderRecommendationService.rankLocalCandidates(
        providers: [providerA, providerB],
        service: ServiceType.fuelDelivery, // Neither offers fuelDelivery
        driverLocation: driverLoc,
        maxRadiusKm: 15.0,
      );

      expect(ranked, isEmpty);
    });
  });

  group('ServiceRequest AI Metadata & Data Integrity Tests', () {
    test('stores and recovers AI metadata without breaking legacy fields', () {
      final request = ServiceRequest(
        customerUid: 'cust-101',
        serviceType: ServiceType.batteryBoost,
        pickup: const GeoLocation(latitude: 6.90, longitude: 79.85),
        pickupAddress: 'Galle Road, Colombo',
        serviceFee: 2340.0,
        totalAmount: 2340.0,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        aiProblemDescription: 'Car clicks rapidly and headlights are off',
        aiSuggestedCategory: 'batteryBoost',
        aiConfirmedCategory: 'batteryBoost',
        aiConfidence: 0.89,
        aiModelVersion: 'Logistic Regression v1.0',
      );

      final map = request.toMap();

      expect(map['customerUid'], 'cust-101');
      expect(map['serviceType'], 'batteryBoost');
      expect(map['aiProblemDescription'], 'Car clicks rapidly and headlights are off');
      expect(map['aiSuggestedCategory'], 'batteryBoost');
      expect(map['aiConfidence'], 0.89);
      expect(map['aiModelVersion'], 'Logistic Regression v1.0');

      // Simulate restoring from Firestore document
      final restored = ServiceRequest.fromMap('req-999', map);

      expect(restored.id, 'req-999');
      expect(restored.serviceType, ServiceType.batteryBoost);
      expect(restored.aiProblemDescription, 'Car clicks rapidly and headlights are off');
      expect(restored.aiSuggestedCategory, 'batteryBoost');
      expect(restored.aiConfidence, 0.89);
      expect(restored.aiModelVersion, 'Logistic Regression v1.0');
    });

    test('maintains backward compatibility with documents lacking AI fields', () {
      final legacyMap = <String, dynamic>{
        'customerUid': 'legacy-cust-001',
        'serviceType': 'towTruck',
        'status': 'pending',
        'pickup': {'latitude': 6.91, 'longitude': 79.86},
        'pickupAddress': 'Kandy Road',
        'serviceFee': 500.0,
        'totalAmount': 500.0,
        'paymentMethod': 'cash',
        'searchRadiusKm': 5.0,
        // No AI fields in legacy doc
      };

      final restored = ServiceRequest.fromMap('leg-1', legacyMap);

      expect(restored.customerUid, 'legacy-cust-001');
      expect(restored.serviceType, ServiceType.towTruck);
      expect(restored.aiProblemDescription, isNull);
      expect(restored.aiSuggestedCategory, isNull);
      expect(restored.aiConfidence, isNull);
      expect(restored.aiModelVersion, isNull);
    });
  });
}
