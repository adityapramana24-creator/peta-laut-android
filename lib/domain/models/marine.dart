import '../../utils/nav_math.dart';

/// Satu jam data laut Open-Meteo Marine (timezone Asia/Jakarta).
/// Nilai null = tidak ada data untuk jam itu (mis. titik darat).
class MarineHour {
  const MarineHour({
    required this.time,
    this.waveHeightM,
    this.waveDirectionDeg,
    this.wavePeriodS,
    this.swellHeightM,
    this.swellDirectionDeg,
    this.swellPeriodS,
    this.currentVelocityKmh,
    this.currentDirectionDeg,
    this.seaTempC,
  });

  final DateTime time;
  final double? waveHeightM;
  final double? waveDirectionDeg;
  final double? wavePeriodS;
  final double? swellHeightM;
  final double? swellDirectionDeg;
  final double? swellPeriodS;
  final double? currentVelocityKmh;
  final double? currentDirectionDeg;
  final double? seaTempC;

  bool get hasWave => waveHeightM != null;

  double? get currentKnots => currentVelocityKmh == null
      ? null
      : NavMath.kmhToKnots(currentVelocityKmh!);

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'wave_height': waveHeightM,
        'wave_direction': waveDirectionDeg,
        'wave_period': wavePeriodS,
        'swell_wave_height': swellHeightM,
        'swell_wave_direction': swellDirectionDeg,
        'swell_wave_period': swellPeriodS,
        'ocean_current_velocity': currentVelocityKmh,
        'ocean_current_direction': currentDirectionDeg,
        'sea_surface_temperature': seaTempC,
      };

  factory MarineHour.fromJson(Map<String, dynamic> json) => MarineHour(
        time: DateTime.parse(json['time'] as String),
        waveHeightM: (json['wave_height'] as num?)?.toDouble(),
        waveDirectionDeg: (json['wave_direction'] as num?)?.toDouble(),
        wavePeriodS: (json['wave_period'] as num?)?.toDouble(),
        swellHeightM: (json['swell_wave_height'] as num?)?.toDouble(),
        swellDirectionDeg:
            (json['swell_wave_direction'] as num?)?.toDouble(),
        swellPeriodS: (json['swell_wave_period'] as num?)?.toDouble(),
        currentVelocityKmh:
            (json['ocean_current_velocity'] as num?)?.toDouble(),
        currentDirectionDeg:
            (json['ocean_current_direction'] as num?)?.toDouble(),
        seaTempC: (json['sea_surface_temperature'] as num?)?.toDouble(),
      );
}

/// Prakiraan laut Open-Meteo Marine untuk satu titik (3 hari, per jam).
class MarineForecast {
  const MarineForecast({
    required this.latitude,
    required this.longitude,
    required this.hours,
    required this.fetchedAt,
    this.isStale = false,
  });

  final double latitude;
  final double longitude;
  final List<MarineHour> hours;
  final DateTime fetchedAt;
  final bool isStale;

  MarineForecast copyWith({bool? isStale}) {
    return MarineForecast(
      latitude: latitude,
      longitude: longitude,
      hours: hours,
      fetchedAt: fetchedAt,
      isStale: isStale ?? this.isStale,
    );
  }

  /// false bila SEMUA jam tanpa data gelombang (titik darat/sungai).
  /// UI WAJIB menampilkan "tidak ada data", bukan 0.
  bool get hasData => hours.any((h) => h.hasWave);

  MarineHour? get current {
    if (hours.isEmpty) return null;
    final now = DateTime.now();
    MarineHour best = hours.first;
    var bestDiff = best.time.difference(now).abs();
    for (final h in hours) {
      final diff = h.time.difference(now).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = h;
      }
    }
    return best;
  }

  /// Jam per 3 jam untuk tampilan ringkas.
  List<MarineHour> get every3Hours {
    final result = <MarineHour>[];
    for (var i = 0; i < hours.length; i += 3) {
      result.add(hours[i]);
    }
    return result;
  }

  factory MarineForecast.fromJson(
    Map<String, dynamic> json, {
    required double latitude,
    required double longitude,
    required DateTime fetchedAt,
  }) {
    final hourly = json['hourly'];
    final hours = <MarineHour>[];
    if (hourly is Map<String, dynamic>) {
      final times = hourly['time'];
      if (times is List) {
        List<dynamic>? listOf(String key) {
          final v = hourly[key];
          return v is List ? v : null;
        }

        final waveHeight = listOf('wave_height');
        final waveDirection = listOf('wave_direction');
        final wavePeriod = listOf('wave_period');
        final swellHeight = listOf('swell_wave_height');
        final swellDirection = listOf('swell_wave_direction');
        final swellPeriod = listOf('swell_wave_period');
        final currentVelocity = listOf('ocean_current_velocity');
        final currentDirection = listOf('ocean_current_direction');
        final seaTemp = listOf('sea_surface_temperature');

        double? at(List<dynamic>? list, int i) {
          if (list == null || i >= list.length) return null;
          final v = list[i];
          return v is num ? v.toDouble() : null;
        }

        for (var i = 0; i < times.length; i++) {
          final rawTime = times[i];
          if (rawTime is! String) continue;
          final time = DateTime.tryParse(rawTime);
          if (time == null) continue;
          hours.add(MarineHour(
            time: time,
            waveHeightM: at(waveHeight, i),
            waveDirectionDeg: at(waveDirection, i),
            wavePeriodS: at(wavePeriod, i),
            swellHeightM: at(swellHeight, i),
            swellDirectionDeg: at(swellDirection, i),
            swellPeriodS: at(swellPeriod, i),
            currentVelocityKmh: at(currentVelocity, i),
            currentDirectionDeg: at(currentDirection, i),
            seaTempC: at(seaTemp, i),
          ));
        }
      }
    }
    return MarineForecast(
      latitude: latitude,
      longitude: longitude,
      hours: hours,
      fetchedAt: fetchedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'hours': hours.map((h) => h.toJson()).toList(),
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory MarineForecast.fromCacheJson(Map<String, dynamic> json) {
    final hours = <MarineHour>[];
    final raw = json['hours'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          hours.add(MarineHour.fromJson(item));
        }
      }
    }
    return MarineForecast(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      hours: hours,
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
    );
  }
}

/// Satu jam prakiraan Open-Meteo Forecast (paket Windy — data layer).
class ForecastHour {
  const ForecastHour({
    required this.time,
    this.tempC,
    this.windKmh,
    this.windDirDeg,
    this.gustsKmh,
    this.precipitationMm,
    this.cloudCoverPct,
    this.pressureHpa,
  });

  final DateTime time;
  final double? tempC;
  final double? windKmh;
  final double? windDirDeg;
  final double? gustsKmh;
  final double? precipitationMm;
  final double? cloudCoverPct;
  final double? pressureHpa;

  double? get windKnots =>
      windKmh == null ? null : NavMath.kmhToKnots(windKmh!);

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'temperature_2m': tempC,
        'wind_speed_10m': windKmh,
        'wind_direction_10m': windDirDeg,
        'wind_gusts_10m': gustsKmh,
        'precipitation': precipitationMm,
        'cloud_cover': cloudCoverPct,
        'pressure_msl': pressureHpa,
      };

  factory ForecastHour.fromJson(Map<String, dynamic> json) =>
      ForecastHour(
        time: DateTime.parse(json['time'] as String),
        tempC: (json['temperature_2m'] as num?)?.toDouble(),
        windKmh: (json['wind_speed_10m'] as num?)?.toDouble(),
        windDirDeg: (json['wind_direction_10m'] as num?)?.toDouble(),
        gustsKmh: (json['wind_gusts_10m'] as num?)?.toDouble(),
        precipitationMm: (json['precipitation'] as num?)?.toDouble(),
        cloudCoverPct: (json['cloud_cover'] as num?)?.toDouble(),
        pressureHpa: (json['pressure_msl'] as num?)?.toDouble(),
      );
}

/// Prakiraan titik gabungan (Forecast + Marine) — fondasi meteogram
/// + prakiraan titik Builder 2 (paket Windy).
class PointForecast {
  const PointForecast({
    required this.latitude,
    required this.longitude,
    required this.forecast,
    required this.marine,
    required this.model,
    required this.fetchedAt,
  });

  final double latitude;
  final double longitude;
  final List<ForecastHour> forecast;
  final List<MarineHour> marine;

  /// 'auto' | 'gfs' | 'icon' | 'ecmwf_ifs'
  final String model;
  final DateTime fetchedAt;

  static List<ForecastHour> parseForecastHourly(
    Map<String, dynamic> json,
  ) {
    final hourly = json['hourly'];
    final hours = <ForecastHour>[];
    if (hourly is Map<String, dynamic>) {
      final times = hourly['time'];
      if (times is List) {
        List<dynamic>? listOf(String key) {
          final v = hourly[key];
          return v is List ? v : null;
        }

        final temp = listOf('temperature_2m');
        final wind = listOf('wind_speed_10m');
        final windDir = listOf('wind_direction_10m');
        final gusts = listOf('wind_gusts_10m');
        final precip = listOf('precipitation');
        final cloud = listOf('cloud_cover');
        final pressure = listOf('pressure_msl');

        double? at(List<dynamic>? list, int i) {
          if (list == null || i >= list.length) return null;
          final v = list[i];
          return v is num ? v.toDouble() : null;
        }

        for (var i = 0; i < times.length; i++) {
          final rawTime = times[i];
          if (rawTime is! String) continue;
          final time = DateTime.tryParse(rawTime);
          if (time == null) continue;
          hours.add(ForecastHour(
            time: time,
            tempC: at(temp, i),
            windKmh: at(wind, i),
            windDirDeg: at(windDir, i),
            gustsKmh: at(gusts, i),
            precipitationMm: at(precip, i),
            cloudCoverPct: at(cloud, i),
            pressureHpa: at(pressure, i),
          ));
        }
      }
    }
    return hours;
  }
}
