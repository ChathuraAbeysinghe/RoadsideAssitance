import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/fault_prediction.dart';

class AiFaultService {
  final http.Client _client;
  String? _customBaseUrl;

  AiFaultService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _customBaseUrl = baseUrl;

  /// Default API base URL.
  /// Uses 10.0.2.2 for Android emulators to communicate with host machine,
  /// and localhost / 127.0.0.1 for desktop, web, and test environments.
  String get baseUrl {
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }
    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  set baseUrl(String url) {
    _customBaseUrl = url;
  }

  /// Sends the driver's problem description and optional vehicle context to the AI microservice.
  Future<FaultPrediction> predictFault({
    required String description,
    String? vehicleType,
  }) async {
    final trimmed = description.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Problem description cannot be empty.');
    }

    final endpoint = Uri.parse('$baseUrl/predict-fault');
    final payload = {
      'description': trimmed,
      if (vehicleType != null && vehicleType.isNotEmpty)
        'vehicle_type': vehicleType,
    };

    try {
      final response = await _client
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return FaultPrediction.fromJson(data);
      } else {
        throw HttpException(
          'AI service responded with status ${response.statusCode}: ${response.body}',
        );
      }
    } on TimeoutException {
      throw const SocketException('AI assistant request timed out. Please check your connection.');
    } catch (e) {
      // Re-throw for UI to present retry or fallback
      rethrow;
    }
  }

  /// Checks if the backend AI microservice is responsive.
  Future<bool> checkHealth() async {
    try {
      final endpoint = Uri.parse('$baseUrl/health');
      final res = await _client
          .get(endpoint)
          .timeout(const Duration(seconds: 3));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
