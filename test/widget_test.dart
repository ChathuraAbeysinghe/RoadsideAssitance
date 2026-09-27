// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:roadside_assitance/entities/app_user.dart';
import 'package:roadside_assitance/features/service_provider/models/provider_service.dart';

void main() {
  test('provider service serializes and restores its Firestore fields', () {
    const service = ProviderService(
      id: 'service-1',
      providerUid: 'provider-1',
      serviceType: ServiceType.towTruck,
      name: 'Flat bed',
      vehicleTypes: 'Cars and vans',
      plateNumber: 'NG-9865',
      location: 'Colombo',
      details: '24 hour towing',
    );

    final restored = ProviderService.fromMap(service.id, service.toMap());

    expect(restored.id, service.id);
    expect(restored.providerUid, service.providerUid);
    expect(restored.serviceType, ServiceType.towTruck);
    expect(restored.plateNumber, 'NG-9865');
  });
}
