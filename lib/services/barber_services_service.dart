import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/barber_service.dart';

/// Firestore CRUD for the `barberServices` collection.
///
/// Each document belongs to a single barber (field: `barberId`).
/// Security: Firestore rules ensure barbers can only touch their own services.
class BarberServicesService {
  static final BarberServicesService _instance = BarberServicesService._internal();
  factory BarberServicesService() => _instance;
  BarberServicesService._internal();

  final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('barberServices');

  // ─────────────────────── READ ───────────────────────

  /// Real-time stream of all services for a barber, newest first.
  ///
  /// Sorted in memory so the list updates without a composite index. An
  /// `orderBy('createdAt')` query fails (and looks empty) until that index
  /// is deployed.
  Stream<List<BarberService>> streamServices(String barberId) {
    return _col
        .where('barberId', isEqualTo: barberId)
        .snapshots()
        .map((snap) {
          final services = snap.docs
              .map((doc) => BarberService.fromMap(doc.data(), doc.id))
              .toList();
          services.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return services;
        });
  }

  /// One-shot fetch (useful for initial checks).
  Future<List<BarberService>> getServices(String barberId) async {
    final snap = await _col.where('barberId', isEqualTo: barberId).get();
    final services = snap.docs
        .map((doc) => BarberService.fromMap(doc.data(), doc.id))
        .toList();
    services.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return services;
  }

  // ─────────────────────── CREATE ───────────────────────

  /// Add a single service. Returns the created document's ID.
  Future<String> addService(BarberService service) async {
    final doc = await _col.add(service.toMap());
    debugPrint('✅ BarberServicesService: Created service ${service.name} → ${doc.id}');
    return doc.id;
  }

  /// Seed the three default services if the barber has zero services.
  /// Safe to call multiple times — it checks first.
  Future<void> seedDefaultsIfEmpty(String barberId) async {
    final existing = await _col
        .where('barberId', isEqualTo: barberId)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      debugPrint('ℹ️ BarberServicesService: Barber $barberId already has services, skipping seed');
      return;
    }

    debugPrint('🌱 BarberServicesService: Seeding defaults for $barberId');
    final defaults = BarberService.defaultPresets(barberId);
    final batch = FirebaseFirestore.instance.batch();
    for (final svc in defaults) {
      batch.set(_col.doc(), svc.toMap());
    }
    await batch.commit();
    debugPrint('✅ BarberServicesService: Seeded ${defaults.length} default services');
  }

  // ─────────────────────── UPDATE ───────────────────────

  /// Update any fields on an existing service.
  Future<void> updateService(String serviceId, Map<String, dynamic> fields) async {
    await _col.doc(serviceId).update({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('✅ BarberServicesService: Updated service $serviceId');
  }

  /// Toggle the `isEnabled` flag (show/hide from customers).
  Future<void> toggleEnabled(String serviceId, bool isEnabled) async {
    await updateService(serviceId, {'isEnabled': isEnabled});
  }

  // ─────────────────────── DELETE ───────────────────────

  /// Permanently delete a service document.
  Future<void> deleteService(String serviceId) async {
    await _col.doc(serviceId).delete();
    debugPrint('🗑️ BarberServicesService: Deleted service $serviceId');
  }
}
