import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../entities/app_user.dart';
import '../../../entities/service_request.dart';
import '../../../entities/vehicle.dart';
import '../../request_service/request_service.dart';
import '../models/fault_prediction.dart';
import '../services/ai_fault_service.dart';
import '../services/provider_recommendation_service.dart';

class AiFaultAssistantPage extends StatefulWidget {
  final UserType userType;

  const AiFaultAssistantPage({super.key, this.userType = UserType.driver});

  @override
  State<AiFaultAssistantPage> createState() => _AiFaultAssistantPageState();
}

class _AiFaultAssistantPageState extends State<AiFaultAssistantPage> {
  static const Color _brandRed = Color(0xFFE30613);
  static const Color _warningOrange = Color(0xFFEA580C);
  static const Color _successGreen = Color(0xFF16A34A);

  final _textController = TextEditingController();
  final _aiService = AiFaultService();
  final _recommendationService = ProviderRecommendationService();

  bool _analyzing = false;
  String? _errorMessage;
  FaultPrediction? _prediction;
  ServiceType? _confirmedServiceType;

  List<Vehicle> _userVehicles = [];
  Vehicle? _selectedVehicle;

  LatLng? _driverLocation;
  List<RecommendedProvider> _recommendedProviders = [];
  bool _loadingProviders = false;

  final List<String> _quickChips = const [
    'Car won\'t start, rapid clicking',
    'Flat tyre with puncture',
    'Ran out of petrol',
    'Engine knocking & overheating',
    'Accident damage, need tow truck',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserVehicles();
    _detectLocation();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadUserVehicles() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final vehicles = await fetchVehiclesForUser(uid);
      if (mounted) {
        setState(() {
          _userVehicles = vehicles;
          if (vehicles.isNotEmpty) {
            _selectedVehicle = vehicles.first;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _detectLocation() async {
    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm != LocationPermission.denied &&
            perm != LocationPermission.deniedForever) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          ).timeout(const Duration(seconds: 6));
          if (mounted) {
            setState(() {
              _driverLocation = LatLng(pos.latitude, pos.longitude);
            });
          }
        }
      }
    } catch (_) {
      // Fallback location Colombo if GPS unavailable
      _driverLocation = const LatLng(6.9271, 79.8612);
    }
  }

  Future<void> _analyzeProblem() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe your vehicle problem first.')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _analyzing = true;
      _errorMessage = null;
      _prediction = null;
      _recommendedProviders = [];
    });

    try {
      final result = await _aiService.predictFault(
        description: text,
        vehicleType: _selectedVehicle?.vehicleType.name,
      );

      if (!mounted) return;
      setState(() {
        _prediction = result;
        _confirmedServiceType = result.serviceType ?? ServiceType.mechanic;
      });

      // Load recommended providers for the confirmed service
      if (_confirmedServiceType != null) {
        _fetchProviderRecommendations(_confirmedServiceType!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Could not connect to the AI Assistant. You can retry or proceed directly by selecting a service manually.';
        // Offline fallback
        _prediction = FaultPrediction.offlineFallback(text);
        _confirmedServiceType = ServiceType.mechanic;
      });
      _fetchProviderRecommendations(_confirmedServiceType!);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _fetchProviderRecommendations(ServiceType service) async {
    final loc = _driverLocation ?? const LatLng(6.9271, 79.8612);
    setState(() => _loadingProviders = true);
    try {
      final recs = await _recommendationService.recommendProviders(
        service: service,
        driverLocation: loc,
        maxRadiusKm: 15.0,
      );
      if (mounted) {
        setState(() => _recommendedProviders = recs);
      }
    } catch (_) {
      if (mounted) setState(() => _recommendedProviders = []);
    } finally {
      if (mounted) setState(() => _loadingProviders = false);
    }
  }

  void _onCategoryChanged(ServiceType newType) {
    setState(() {
      _confirmedServiceType = newType;
    });
    _fetchProviderRecommendations(newType);
  }

  void _proceedToBooking() {
    final service = _confirmedServiceType ?? ServiceType.mechanic;
    final notes = _textController.text.trim();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RequestServicePage(
          serviceType: service,
          userType: widget.userType,
          initialNotes: notes.isNotEmpty ? notes : null,
          initialVehicle: _selectedVehicle,
          aiProblemDescription: notes,
          aiSuggestedCategory: _prediction?.rawCategoryString,
          aiConfidence: _prediction?.confidence,
          aiModelVersion: _prediction?.modelVersion,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'AI Vehicle Problem Assistant',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildIntroductionCard(),
            const SizedBox(height: 16),
            _buildInputSection(),
            const SizedBox(height: 16),
            if (_userVehicles.isNotEmpty) _buildVehicleSelector(),
            if (_userVehicles.isNotEmpty) const SizedBox(height: 16),
            _buildActionButtons(),
            if (_analyzing) ...[
              const SizedBox(height: 24),
              _buildLoadingState(),
            ],
            if (_errorMessage != null && !_analyzing) ...[
              const SizedBox(height: 16),
              _buildErrorBanner(),
            ],
            if (_prediction != null && !_analyzing) ...[
              const SizedBox(height: 24),
              _buildPredictionSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIntroductionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _brandRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome, color: _brandRed, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart Roadside Triage',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'Describe your car or motorbike problem in your own words. '
                  'The AI will identify the required assistance, alert on safety hazards, '
                  'and recommend the closest qualified providers.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What seems to be the problem?',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _textController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'e.g., My car won\'t start, battery clicks when turning key, and headlights are dim...',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _brandRed, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Quick examples:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _quickChips.map((chip) {
              return ActionChip(
                label: Text(chip, style: const TextStyle(fontSize: 12)),
                backgroundColor: Colors.grey.shade100,
                side: BorderSide(color: Colors.grey.shade300),
                onPressed: () {
                  _textController.text = chip;
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car_outlined, color: Colors.black54),
          const SizedBox(width: 12),
          const Text('Vehicle:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Vehicle>(
                value: _selectedVehicle,
                isExpanded: true,
                items: _userVehicles.map((v) {
                  return DropdownMenuItem<Vehicle>(
                    value: v,
                    child: Text(
                      '${v.make} ${v.model} (${v.plateNumber})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _selectedVehicle = v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return ElevatedButton.icon(
      onPressed: _analyzing ? null : _analyzeProblem,
      icon: _analyzing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.auto_awesome, color: Colors.white),
      label: Text(
        _analyzing ? 'Analyzing Symptoms...' : 'Analyze Problem with AI',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _brandRed,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        children: [
          const CircularProgressIndicator(color: _brandRed),
          const SizedBox(height: 14),
          Text(
            'Evaluating symptom description against roadside service taxonomy...',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: _brandRed, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _analyzeProblem,
                icon: const Icon(Icons.refresh, size: 16, color: _brandRed),
                label: const Text('Retry Analysis', style: TextStyle(color: _brandRed)),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildPredictionSection() {
    final pred = _prediction!;
    final isUncertain = pred.requiresClarification || pred.serviceType == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Safety Alert Banner (if critical)
        if (pred.safetyAlert != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SAFETY ALERT',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pred.safetyAlert!,
                        style: const TextStyle(
                          color: Color(0xFF7F1D1D),
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 2. Primary Recommendation Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUncertain ? _warningOrange.withValues(alpha: 0.5) : _brandRed.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isUncertain
                          ? _warningOrange.withValues(alpha: 0.12)
                          : _successGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isUncertain ? Icons.help_outline : Icons.check_circle_outline,
                          size: 14,
                          color: isUncertain ? _warningOrange : _successGreen,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isUncertain ? 'Needs Confirmation' : 'AI Match',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isUncertain ? _warningOrange : _successGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Confidence: ${(pred.confidence * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _confirmedServiceType != null
                    ? serviceTypeTitle(_confirmedServiceType!)
                    : pred.displayTitle,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                pred.explanation,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
              ),
              if (pred.suggestedQuestions.isNotEmpty && isUncertain) ...[
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Questions to check:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ...pred.suggestedQuestions.map(
                  (q) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Text(q, style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 3. Category Override Section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Change Service Category (Manual Override):',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ServiceType.values.map((type) {
                  final isSelected = _confirmedServiceType == type;
                  return ChoiceChip(
                    label: Text(
                      serviceTypeTitle(type),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: _brandRed,
                    backgroundColor: Colors.grey.shade100,
                    showCheckmark: false,
                    onSelected: (_) => _onCategoryChanged(type),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 4. Smart Provider Recommendations Section
        _buildProviderRecommendationsSection(),

        const SizedBox(height: 20),

        // 5. Booking Flow Action Button
        ElevatedButton(
          onPressed: _proceedToBooking,
          style: ElevatedButton.styleFrom(
            backgroundColor: _brandRed,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Proceed with ${_confirmedServiceType != null ? serviceTypeTitle(_confirmedServiceType!) : 'Selected Service'}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
            ],
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildProviderRecommendationsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Smart Provider Recommendations',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              if (_loadingProviders)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _brandRed),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ranked by distance and verified ratings from existing provider records.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          if (_recommendedProviders.isEmpty && !_loadingProviders)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: Colors.grey.shade500),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No providers currently online for this service within 15 km. '
                      'Proceeding with booking will automatically broadcast your request.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recommendedProviders.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final p = _recommendedProviders[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: _brandRed.withValues(alpha: 0.1),
                            child: const Icon(Icons.person, color: _brandRed, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.star, color: Colors.amber, size: 14),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${p.rating.toStringAsFixed(1)} (${p.ratingCount} reviews)',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                    ),
                                    const SizedBox(width: 10),
                                    const Icon(Icons.location_on, color: Colors.grey, size: 13),
                                    Text(
                                      '${p.distanceKm.toStringAsFixed(1)} km',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: p.recommendationReasons.map((r) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              r,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
