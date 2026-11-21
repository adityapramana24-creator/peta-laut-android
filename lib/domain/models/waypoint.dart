/// Fondasi navigasi Builder 2: waypoint, rute, track.
/// Model domain murni (tanpa dependensi Drift) — pemetaan ke tabel
/// Drift dilakukan di NavigationRepository.
class Waypoint {
  const Waypoint({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.createdAt,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final DateTime? createdAt;

  Waypoint copyWith({
    String? name,
    double? latitude,
    double? longitude,
  }) {
    return Waypoint(
      id: id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt,
    );
  }
}

/// Rute = urutan waypoint + kecepatan rencana (knot).
class RoutePlan {
  const RoutePlan({
    required this.id,
    required this.name,
    required this.waypointIds,
    this.speedKnots = 8.0,
    this.createdAt,
  });

  final String id;
  final String name;
  final List<String> waypointIds;
  final double speedKnots;
  final DateTime? createdAt;

  RoutePlan copyWith({
    String? name,
    List<String>? waypointIds,
    double? speedKnots,
  }) {
    return RoutePlan(
      id: id,
      name: name ?? this.name,
      waypointIds: waypointIds ?? this.waypointIds,
      speedKnots: speedKnots ?? this.speedKnots,
      createdAt: createdAt,
    );
  }
}

/// Satu titik jejak GPS yang direkam.
class TrackPoint {
  const TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.speedKnots,
  });

  final double latitude;
  final double longitude;
  final DateTime recordedAt;
  final double? speedKnots;
}

/// Jejak perjalanan (rekaman posisi kapal).
class Track {
  const Track({
    required this.id,
    required this.name,
    required this.startedAt,
    this.endedAt,
    this.points = const [],
  });

  final String id;
  final String name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<TrackPoint> points;

  bool get isActive => endedAt == null;
}
