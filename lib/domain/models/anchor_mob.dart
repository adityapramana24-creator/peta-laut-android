/// Pengaturan alarm jangkar (R-28): titik jangkar + radius.
/// Disimpan di SharedPreferences (JSON). Alarm aktif selama aplikasi
/// terbuka — tanpa foreground service, alarm tidak berjalan saat
/// aplikasi ditutup (batas ini ditulis di UI).
class AnchorSettings {
  const AnchorSettings({
    required this.latitude,
    required this.longitude,
    required this.radiusM,
    required this.armed,
    this.setAt,
  });

  final double latitude;
  final double longitude;

  /// Radius lingkaran jangkar (meter).
  final double radiusM;

  final bool armed;
  final DateTime? setAt;

  AnchorSettings copyWith({bool? armed, double? radiusM}) {
    return AnchorSettings(
      latitude: latitude,
      longitude: longitude,
      radiusM: radiusM ?? this.radiusM,
      armed: armed ?? this.armed,
      setAt: setAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'radiusM': radiusM,
        'armed': armed,
        'setAt': setAt?.toIso8601String(),
      };

  factory AnchorSettings.fromJson(Map<String, dynamic> json) {
    final setRaw = json['setAt'] as String?;
    return AnchorSettings(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      radiusM: (json['radiusM'] as num?)?.toDouble() ?? 50,
      armed: json['armed'] as bool? ?? false,
      setAt: setRaw == null ? null : DateTime.tryParse(setRaw),
    );
  }
}

/// Tanda MOB (Man Overboard, R-28): posisi + waktu saat tombol MOB
/// ditekan. Disimpan di SharedPreferences (JSON).
class MobMark {
  const MobMark({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
  });

  final String id;
  final double latitude;
  final double longitude;
  final DateTime recordedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'recordedAt': recordedAt.toIso8601String(),
      };

  factory MobMark.fromJson(Map<String, dynamic> json) => MobMark(
        id: json['id'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        recordedAt:
            DateTime.tryParse(json['recordedAt'] as String? ?? '') ??
                DateTime.now(),
      );
}
