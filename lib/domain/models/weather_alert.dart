/// Peringatan cuaca kustom (paket Windy, R-30): ambang angin /
/// gelombang / hujan. Dievaluasi terhadap prakiraan titik saat aplikasi
/// terbuka; bila terlampaui, notifikasi lokal dikirim (maks 1x per 6 jam
/// per peringatan). Disimpan di SharedPreferences (JSON).
class WeatherAlert {
  const WeatherAlert({
    required this.id,
    required this.name,
    this.windKnots,
    this.waveM,
    this.rainMmPerHour,
    this.enabled = true,
    this.lastTriggeredAt,
  });

  final String id;
  final String name;

  /// Ambang: angin melebihi ini (knot). null = tidak dipakai.
  final double? windKnots;

  /// Ambang: tinggi gelombang melebihi ini (meter).
  final double? waveM;

  /// Ambang: hujan per jam melebihi ini (mm).
  final double? rainMmPerHour;

  final bool enabled;

  /// Terakhir kali peringatan ini memicu notifikasi.
  final DateTime? lastTriggeredAt;

  bool get hasAnyThreshold =>
      windKnots != null || waveM != null || rainMmPerHour != null;

  WeatherAlert copyWith({
    String? name,
    double? windKnots,
    double? waveM,
    double? rainMmPerHour,
    bool? enabled,
    DateTime? lastTriggeredAt,
    bool clearWind = false,
    bool clearWave = false,
    bool clearRain = false,
  }) {
    return WeatherAlert(
      id: id,
      name: name ?? this.name,
      windKnots: clearWind ? null : (windKnots ?? this.windKnots),
      waveM: clearWave ? null : (waveM ?? this.waveM),
      rainMmPerHour:
          clearRain ? null : (rainMmPerHour ?? this.rainMmPerHour),
      enabled: enabled ?? this.enabled,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'windKnots': windKnots,
        'waveM': waveM,
        'rainMmPerHour': rainMmPerHour,
        'enabled': enabled,
        'lastTriggeredAt': lastTriggeredAt?.toIso8601String(),
      };

  factory WeatherAlert.fromJson(Map<String, dynamic> json) {
    final lastRaw = json['lastTriggeredAt'] as String?;
    return WeatherAlert(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Peringatan',
      windKnots: (json['windKnots'] as num?)?.toDouble(),
      waveM: (json['waveM'] as num?)?.toDouble(),
      rainMmPerHour: (json['rainMmPerHour'] as num?)?.toDouble(),
      enabled: json['enabled'] as bool? ?? true,
      lastTriggeredAt:
          lastRaw == null ? null : DateTime.tryParse(lastRaw),
    );
  }
}
