import 'package:cloud_firestore/cloud_firestore.dart';

/// Service type: default (preset), custom (user-created), or combo (bundle)
enum ServiceType { defaultService, custom, combo }

/// BarberService — A service offered by a barber.
///
/// Stored in Firestore at:  barberServices/{serviceId}
///
/// Three flavours:
///   1. **Default** — Haircut, Beard, Haircut+Beard (created from presets)
///   2. **Custom**  — Barber-defined (name + price + optional category)
///   3. **Combo**   — 2+ existing services bundled at one unique price
class BarberService {
  final String id;
  final String barberId;
  final String name;
  final int pricePKR;
  final ServiceType type;

  /// Optional grouping label (e.g. "Hair", "Face", "Grooming")
  final String? category;

  /// Emoji icon for visual flair (default: ✂️)
  final String emoji;

  /// Estimated duration in minutes (default: 30)
  final int durationMinutes;

  /// Whether the service is currently offered to customers
  final bool isEnabled;

  /// For combo services: the IDs of included child services
  final List<String> comboServiceIds;

  /// For combo services: readable names cached for display
  final List<String> comboServiceNames;

  final DateTime createdAt;
  final DateTime updatedAt;

  const BarberService({
    required this.id,
    required this.barberId,
    required this.name,
    required this.pricePKR,
    required this.type,
    this.category,
    this.emoji = '✂️',
    this.durationMinutes = 30,
    this.isEnabled = true,
    this.comboServiceIds = const [],
    this.comboServiceNames = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  // ─────────────────────── Serialisation ───────────────────────

  Map<String, dynamic> toMap() {
    return {
      'barberId': barberId,
      'name': name,
      'pricePKR': pricePKR,
      'type': type.name,
      'category': category,
      'emoji': emoji,
      'durationMinutes': durationMinutes,
      'isEnabled': isEnabled,
      'comboServiceIds': comboServiceIds,
      'comboServiceNames': comboServiceNames,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory BarberService.fromMap(Map<String, dynamic> map, String docId) {
    return BarberService(
      id: docId,
      barberId: map['barberId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      pricePKR: (map['pricePKR'] as num?)?.toInt() ?? 0,
      type: ServiceType.values.firstWhere(
        (t) => t.name == (map['type'] as String?),
        orElse: () => ServiceType.custom,
      ),
      category: map['category'] as String?,
      emoji: map['emoji'] as String? ?? '✂️',
      durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 30,
      isEnabled: map['isEnabled'] as bool? ?? true,
      comboServiceIds: List<String>.from(map['comboServiceIds'] ?? []),
      comboServiceNames: List<String>.from(map['comboServiceNames'] ?? []),
      createdAt: _parseTimestamp(map['createdAt']),
      updatedAt: _parseTimestamp(map['updatedAt']),
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.now();
  }

  // ─────────────────────── Copy helpers ───────────────────────

  BarberService copyWith({
    String? name,
    int? pricePKR,
    ServiceType? type,
    String? category,
    String? emoji,
    int? durationMinutes,
    bool? isEnabled,
    List<String>? comboServiceIds,
    List<String>? comboServiceNames,
  }) {
    return BarberService(
      id: id,
      barberId: barberId,
      name: name ?? this.name,
      pricePKR: pricePKR ?? this.pricePKR,
      type: type ?? this.type,
      category: category ?? this.category,
      emoji: emoji ?? this.emoji,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      isEnabled: isEnabled ?? this.isEnabled,
      comboServiceIds: comboServiceIds ?? this.comboServiceIds,
      comboServiceNames: comboServiceNames ?? this.comboServiceNames,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  // ─────────────────────── Display helpers ───────────────────────

  String get typeLabel {
    switch (type) {
      case ServiceType.defaultService:
        return 'Default';
      case ServiceType.custom:
        return 'Custom';
      case ServiceType.combo:
        return 'Combo';
    }
  }

  String get formattedPrice => 'Rs. $pricePKR';

  String get formattedDuration => '$durationMinutes min';

  bool get isCombo => type == ServiceType.combo;

  // ─────────────────────── Default presets ───────────────────────

  /// The three default services every barber starts with.
  /// Call with the barber's UID to generate ready-to-save instances.
  static List<BarberService> defaultPresets(String barberId) {
    final now = DateTime.now();
    return [
      BarberService(
        id: '', // Firestore will assign
        barberId: barberId,
        name: 'Haircut',
        pricePKR: 500,
        type: ServiceType.defaultService,
        category: 'Hair',
        emoji: '✂️',
        durationMinutes: 30,
        createdAt: now,
        updatedAt: now,
      ),
      BarberService(
        id: '',
        barberId: barberId,
        name: 'Beard Trim',
        pricePKR: 300,
        type: ServiceType.defaultService,
        category: 'Face',
        emoji: '🧔',
        durationMinutes: 15,
        createdAt: now,
        updatedAt: now,
      ),
      BarberService(
        id: '',
        barberId: barberId,
        name: 'Haircut + Beard',
        pricePKR: 700,
        type: ServiceType.defaultService,
        category: 'Combo',
        emoji: '💈',
        durationMinutes: 45,
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }
}
