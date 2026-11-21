import '../../utils/nav_math.dart';

/// Satu slot prakiraan BMKG (per 3 jam).
/// `localTime` adalah waktu lokal lokasi prakiraan (local_datetime BMKG).
class BmkgSlot {
  const BmkgSlot({
    required this.localTime,
    this.tempC,
    this.condition,
    this.windFrom,
    this.windFromDeg,
    this.windKmh,
    this.humidity,
    this.cloudCover,
    this.rainMm,
  });

  final DateTime localTime;
  final double? tempC;
  final String? condition;
  final String? windFrom;
  final double? windFromDeg;
  final double? windKmh;
  final int? humidity;
  final int? cloudCover;
  final double? rainMm;

  double? get windKnots =>
      windKmh == null ? null : NavMath.kmhToKnots(windKmh!);

  factory BmkgSlot.fromJson(Map<String, dynamic> json) {
    DateTime? parseTime(String? raw) {
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    final local = parseTime(json['local_datetime'] as String?) ??
        parseTime(json['datetime'] as String?);
    return BmkgSlot(
      localTime: local ?? DateTime.now(),
      tempC: (json['t'] as num?)?.toDouble(),
      condition: json['weather_desc'] as String?,
      windFrom: json['wd'] as String?,
      windFromDeg: (json['wd_deg'] as num?)?.toDouble(),
      windKmh: (json['ws'] as num?)?.toDouble(),
      humidity: (json['hu'] as num?)?.toInt(),
      cloudCover: (json['tcc'] as num?)?.toInt(),
      rainMm: (json['tp'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'local_datetime': localTime.toIso8601String(),
        't': tempC,
        'weather_desc': condition,
        'wd': windFrom,
        'wd_deg': windFromDeg,
        'ws': windKmh,
        'hu': humidity,
        'tcc': cloudCover,
        'tp': rainMm,
      };
}

/// Prakiraan cuaca BMKG: 3 hari ke depan, per 3 jam.
/// Struktur respons: data[0].cuaca = [hari1, hari2, hari3] (list of list).
class BmkgForecast {
  const BmkgForecast({
    required this.adm4,
    required this.locationName,
    required this.days,
    required this.fetchedAt,
    this.analysisDate,
    this.isStale = false,
  });

  final String adm4;
  final String locationName;
  final List<List<BmkgSlot>> days;
  final DateTime fetchedAt;
  final DateTime? analysisDate;
  final bool isStale;

  BmkgForecast copyWith({bool? isStale}) {
    return BmkgForecast(
      adm4: adm4,
      locationName: locationName,
      days: days,
      fetchedAt: fetchedAt,
      analysisDate: analysisDate,
      isStale: isStale ?? this.isStale,
    );
  }

  List<BmkgSlot> get allSlots => days.expand((d) => d).toList();

  /// Slot terdekat dengan waktu sekarang (dibanding jam lokal slot).
  BmkgSlot? get current {
    final slots = allSlots;
    if (slots.isEmpty) return null;
    final now = DateTime.now();
    BmkgSlot best = slots.first;
    var bestDiff = (best.localTime.difference(now)).abs();
    for (final slot in slots) {
      final diff = slot.localTime.difference(now).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = slot;
      }
    }
    return best;
  }

  factory BmkgForecast.fromJson(
    Map<String, dynamic> json, {
    required String adm4,
    required DateTime fetchedAt,
  }) {
    String locationName = '';
    DateTime? analysisDate;
    final days = <List<BmkgSlot>>[];

    final lokasi = json['lokasi'];
    if (lokasi is Map<String, dynamic>) {
      final kotkab = lokasi['kotkab'] as String?;
      final kecamatan = lokasi['kecamatan'] as String?;
      locationName = [kecamatan, kotkab]
          .where((s) => s != null && s.isNotEmpty)
          .join(', ');
    }

    DateTime? parseAnalysis(dynamic raw) {
      if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
      return null;
    }

    analysisDate = parseAnalysis(json['analysis_date']);

    final data = json['data'];
    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map<String, dynamic>) {
        analysisDate ??= parseAnalysis(first['analysis_date']);
        final cuaca = first['cuaca'];
        if (cuaca is List) {
          for (final day in cuaca) {
            if (day is List) {
              final slots = <BmkgSlot>[];
              for (final item in day) {
                if (item is Map<String, dynamic>) {
                  try {
                    slots.add(BmkgSlot.fromJson(item));
                  } catch (_) {
                    // Lewati satu slot rusak.
                  }
                }
              }
              slots.sort((a, b) => a.localTime.compareTo(b.localTime));
              if (slots.isNotEmpty) days.add(slots);
            }
          }
        }
      }
    }

    return BmkgForecast(
      adm4: adm4,
      locationName: locationName,
      days: days,
      fetchedAt: fetchedAt,
      analysisDate: analysisDate,
    );
  }

  Map<String, dynamic> toJson() => {
        'adm4': adm4,
        'locationName': locationName,
        'days': days
            .map((d) => d.map((s) => s.toJson()).toList())
            .toList(),
        'fetchedAt': fetchedAt.toIso8601String(),
        'analysisDate': analysisDate?.toIso8601String(),
      };

  factory BmkgForecast.fromCacheJson(Map<String, dynamic> json) {
    final days = <List<BmkgSlot>>[];
    final rawDays = json['days'];
    if (rawDays is List) {
      for (final day in rawDays) {
        if (day is List) {
          days.add(day
              .map((s) => BmkgSlot.fromJson(s as Map<String, dynamic>))
              .toList());
        }
      }
    }
    final analysisRaw = json['analysisDate'] as String?;
    return BmkgForecast(
      adm4: json['adm4'] as String? ?? '',
      locationName: json['locationName'] as String? ?? '',
      days: days,
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      analysisDate:
          analysisRaw == null ? null : DateTime.tryParse(analysisRaw),
    );
  }
}
