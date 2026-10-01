import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/provider_service.dart';
import '../models/service_request.dart';

class ProviderRepository {
  final FirebaseFirestore _firestore;

  ProviderRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<ProviderService>> watchServices(String uid) {
    return _firestore
        .collection('providerServices')
        .where('providerUid', isEqualTo: uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ProviderService.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> addService(ProviderService service) async {
    await _firestore.collection('providerServices').add(service.toMap());
    await _firestore.collection('users').doc(service.providerUid).set({
      'services': FieldValue.arrayUnion([service.serviceType.name]),
    }, SetOptions(merge: true));
  }

  Future<void> deleteService(ProviderService service) async {
    await _firestore.collection('providerServices').doc(service.id).delete();
  }

  Stream<List<ServiceRequest>> watchRequests(String uid) {
    return _firestore
        .collection('serviceRequests')
        .where('providerUid', isEqualTo: uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(ServiceRequest.fromSnapshot)
              .where(
                (request) =>
                    request.status == 'pending' || request.status == 'accepted',
              )
              .toList(),
        );
  }

  Stream<List<ServiceRequest>> watchCompletedRequests(String uid) {
    return _firestore
        .collection('serviceRequests')
        .where('providerUid', isEqualTo: uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(ServiceRequest.fromSnapshot)
              .where((request) => request.status == 'completed')
              .toList(),
        );
  }

  Future<void> updateRequestStatus(String requestId, String status) {
    return _firestore.collection('serviceRequests').doc(requestId).update({
      'status': status,
      '${status}At': FieldValue.serverTimestamp(),
    });
  }
}
