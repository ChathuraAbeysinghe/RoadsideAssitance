import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../entities/app_user.dart';
import '../../../entities/service_request.dart';
import '../models/provider_service.dart';
import '../models/provider_station.dart';

/// A notification document in the top-level `notifications` collection:
/// { uid, title, body, type, requestId?, read, createdAt }
class AppNotification {
  final String id;
  final String title;
  final String body;
  final String type;
  final String? requestId;
  final bool read;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.requestId,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromMap(String id, Map<String, dynamic> m) {
    final ts = m['createdAt'];
    return AppNotification(
      id: id,
      title: m['title'] as String? ?? '',
      body: m['body'] as String? ?? '',
      type: m['type'] as String? ?? 'info',
      requestId: m['requestId'] as String?,
      read: m['read'] as bool? ?? false,
      // serverTimestamp is null for a moment on the device that wrote it.
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}

class ProviderRepository {
  final FirebaseFirestore _firestore;

  ProviderRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  // ------------------------------------------------------------------
  // Service listings (providerServices)
  //
  // `users/{uid}.services` is what request matching uses. A listing only
  // adds details (plate, vehicle types...). Pausing/removing a listing
  // removes that service type from `users.services` unless another active
  // listing of the same type still exists.
  // ------------------------------------------------------------------

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
    await _syncServiceType(service.providerUid, service.serviceType);
  }

  Future<void> updateService(ProviderService service) async {
    final ref = _firestore.collection('providerServices').doc(service.id);
    final old = await ref.get();
    final oldType = old.data()?['serviceType'] as String?;

    await ref.update(service.toMap());

    await _syncServiceType(service.providerUid, service.serviceType);
    if (oldType != null && oldType != service.serviceType.name) {
      await _syncServiceType(
        service.providerUid,
        ServiceTypeX.fromString(oldType),
      );
    }
  }

  Future<void> deleteService(ProviderService service) async {
    await _firestore.collection('providerServices').doc(service.id).delete();
    await _syncServiceType(service.providerUid, service.serviceType);
  }

  Future<void> _syncServiceType(String uid, ServiceType type) async {
    final snap = await _firestore
        .collection('providerServices')
        .where('providerUid', isEqualTo: uid)
        .where('serviceType', isEqualTo: type.name)
        .get();
    final hasActive = snap.docs.any(
      (d) => d.data()['isActive'] as bool? ?? true,
    );
    await _firestore.collection('users').doc(uid).set({
      'services': hasActive
          ? FieldValue.arrayUnion([type.name])
          : FieldValue.arrayRemove([type.name]),
    }, SetOptions(merge: true));
  }

  // ------------------------------------------------------------------
  // Jobs
  // ------------------------------------------------------------------

  static const Map<RequestStatus, (String, String)> _statusMessages = {
    RequestStatus.onTheWay: (
      'Provider is on the way',
      'Your assistance provider is heading to your location.',
    ),
    RequestStatus.arrived: (
      'Provider has arrived',
      'Your assistance provider has reached your location.',
    ),
    RequestStatus.inProgress: (
      'Service started',
      'Your assistance provider has started working.',
    ),
    RequestStatus.completed: (
      'Service completed',
      'Your job is complete. Thank you for using the app!',
    ),
    RequestStatus.cancelled: (
      'Provider cancelled the job',
      'Your provider could not complete this request. Please try again.',
    ),
  };

  /// Accepts a pending request (transaction in service_request.dart) and
  /// tells the customer.
  Future<AcceptResult> acceptJob(
    ServiceRequest request,
    String providerUid,
    String providerName,
  ) async {
    final result = await acceptRequest(
      requestId: request.id,
      providerUid: providerUid,
    );
    if (result == AcceptResult.success) {
      await sendNotification(
        uid: request.customerUid,
        title: 'Request accepted',
        body:
            '${providerName.isEmpty ? 'A provider' : providerName} accepted your request.',
        type: 'accepted',
        requestId: request.id,
      );
    }
    return result;
  }

  /// Moves a job to its next status and notifies the customer.
  Future<bool> setJobStatus(ServiceRequest job, RequestStatus next) async {
    final providerUid = job.providerUid;
    if (providerUid == null) return false;
    final ok = await updateJobStatus(
      requestId: job.id,
      providerUid: providerUid,
      next: next,
    );
    final msg = _statusMessages[next];
    if (ok && msg != null) {
      await sendNotification(
        uid: job.customerUid,
        title: msg.$1,
        body: msg.$2,
        type: next.name,
        requestId: job.id,
      );
    }
    return ok;
  }

  // ------------------------------------------------------------------
  // Notifications
  // ------------------------------------------------------------------

  Future<void> sendNotification({
    required String uid,
    required String title,
    required String body,
    String type = 'info',
    String? requestId,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'uid': uid,
        'title': title,
        'body': body,
        'type': type,
        'requestId': requestId,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // A failed notification must never break the main action.
    }
  }

  Stream<List<AppNotification>> watchNotifications(String uid) {
    return _firestore
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => AppNotification.fromMap(d.id, d.data()))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  Stream<int> watchUnreadCount(String uid) {
    return _firestore
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Future<void> markAllRead(String uid) async {
    final snap = await _firestore
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> deleteNotification(String id) async {
    await _firestore.collection('notifications').doc(id).delete();
  }

  // ------------------------------------------------------------------
  // Service Station listings (providerStations)
  // ------------------------------------------------------------------

  Stream<List<ProviderStation>> watchStations(String uid) {
    return _firestore
        .collection('providerStations')
        .where('providerUid', isEqualTo: uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ProviderStation.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> addStation(ProviderStation station) async {
    await _firestore.collection('providerStations').add(station.toMap());
  }

  Future<void> updateStation(ProviderStation station) async {
    await _firestore
        .collection('providerStations')
        .doc(station.id)
        .update(station.toMap());
  }

  Future<void> deleteStation(String stationId) async {
    await _firestore.collection('providerStations').doc(stationId).delete();
  }
}
