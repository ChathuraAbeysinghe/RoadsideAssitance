import '../../../entities/app_user.dart';

/// Represents the structured fault classification result returned by the AI backend.
class FaultPrediction {
  /// The mapped Flutter ServiceType, or null if the prediction is uncertain/unclear.
  final ServiceType? serviceType;

  /// The raw category string returned from the backend (e.g. 'batteryBoost', 'uncertain').
  final String rawCategoryString;

  /// The underlying ML model class label (e.g. 'battery_boost').
  final String rawLabel;

  /// Prediction confidence score between 0.0 and 1.0.
  final double confidence;

  /// Flag indicating if the description was ambiguous, low-confidence, or required clarification.
  final bool requiresClarification;

  /// Clear, human-understandable explanation of why this service was selected.
  final String explanation;

  /// List of contextual follow-up questions when clarification is required.
  final List<String> suggestedQuestions;

  /// Immediate safety hazard warning (fire, smoke, fuel leak) if detected.
  final String? safetyAlert;

  /// Identifier of the model version that generated this prediction.
  final String modelVersion;

  const FaultPrediction({
    required this.serviceType,
    required this.rawCategoryString,
    required this.rawLabel,
    required this.confidence,
    required this.requiresClarification,
    required this.explanation,
    this.suggestedQuestions = const [],
    this.safetyAlert,
    required this.modelVersion,
  });

  factory FaultPrediction.fromJson(Map<String, dynamic> json) {
    final catStr = json['predicted_category'] as String? ?? 'uncertain';
    ServiceType? parsedService;
    try {
      if (catStr != 'uncertain') {
        parsedService = ServiceTypeX.fromString(catStr);
      }
    } catch (_) {
      parsedService = null;
    }

    final questionsRaw = json['suggested_questions'] as List<dynamic>? ?? [];
    final questions = questionsRaw.map((e) => e.toString()).toList();

    return FaultPrediction(
      serviceType: parsedService,
      rawCategoryString: catStr,
      rawLabel: json['raw_label'] as String? ?? 'uncertain',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      requiresClarification: json['requires_clarification'] as bool? ?? false,
      explanation: json['explanation'] as String? ?? '',
      suggestedQuestions: questions,
      safetyAlert: json['safety_alert'] as String?,
      modelVersion: json['model_version'] as String? ?? 'Unknown',
    );
  }

  /// Fallback prediction used when the backend is offline or network fails.
  factory FaultPrediction.offlineFallback(String description) {
    return FaultPrediction(
      serviceType: null,
      rawCategoryString: 'uncertain',
      rawLabel: 'offline_fallback',
      confidence: 0.0,
      requiresClarification: true,
      explanation:
          'AI service is currently offline or unreachable. You can select your required service category manually below.',
      suggestedQuestions: const [
        'Does your engine turn over when starting?',
        'Is any tire visibly flat or punctured?',
        'Did you run out of fuel on the road?',
        'Is the vehicle immobilized and needing a tow truck?',
      ],
      safetyAlert: null,
      modelVersion: 'OfflineFallback-v1.0',
    );
  }

  /// Human-friendly display title for the predicted service.
  String get displayTitle {
    final s = serviceType;
    if (s == null) return 'Uncertain / Please Select';
    return switch (s) {
      ServiceType.towTruck => 'Emergency Towing',
      ServiceType.mechanic => 'Request a Mechanic',
      ServiceType.fuelDelivery => 'Emergency Fuel Delivery',
      ServiceType.flatTireChange => 'Flat Tire Replacement',
      ServiceType.batteryBoost => 'Battery Jump-Start',
    };
  }
}
