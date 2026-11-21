import 'dart:convert';
import 'dart:math' as math;

import '../../utils/formatters.dart';

enum TideType { high, low }

/// Satu titik ekstremum pasang surut (pasang tertinggi / surut terendah).
class TideExtremum {
  const TideExtremum({
    required this.type,
    required this.timeUtc,
    required this.heightM,
  });

  final TideType type;
  final DateTime timeUtc;
  final double heightM;

  DateTime get timeWib => IdFormat.toWib(timeUtc);
  bool get isHigh => type == TideType.high;

  factory TideExtremum.fromJson(Map<String, dynamic> json) {
    final extrema = (json['extrema'] as String?)?.toLowerCase();
    return TideExtremum(
      type: extrema == 'high' ? TideType.high : TideType.low,
      timeUtc: DateTime.parse(json['time'] as String).toUtc(),
      heightM: (json['height'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'extrema': isHigh ? 'high' : 'low',
        'time': timeUtc.toIso8601String(),
        'height': heightM,
      };
}

/// Satu titik kurva pasang surut (rangkaian waktu).
class TideCurvePoint {
  const TideCurvePoint({required this.timeUtc, required this.heightM});

  final DateTime timeUtc;
  final double heightM;

  DateTime get timeWib => IdFormat.toWib(timeUtc);

  Map<String, dynamic> toJson() => {
        'time': timeUtc.toIso8601String(),
        'height': heightM,
      };

  factory TideCurvePoint.fromJson(Map<String, dynamic> json) =>
      TideCurvePoint(
        timeUtc: DateTime.parse(json['time'] as String).toUtc(),
        heightM: (json['height'] as num).toDouble(),
      );
}

/// Prakiraan pasang surut untuk satu lokasi + rentang 2 hari.
/// Sumber: model harmonik global hamandmore (BUKAN gauge lokal).
class TideForecast {
  const TideForecast({
    required this.latitude,
    required this.longitude,
    required this.extrema,
    required this.curve,
    required this.fetchedAt,
    this.lowWaterLevel,
    this.highWaterLevel,
    this.isStale = false,
  });

  final double latitude;
  final double longitude;
  final List<TideExtremum> extrema;
  final List<TideCurvePoint> curve;
  final DateTime fetchedAt;
  final double? lowWaterLevel;
  final double? highWaterLevel;

  /// true bila data ini cache lama yang dipakai karena fetch gagal.
  final bool isStale;

  TideForecast copyWith({
    List<TideCurvePoint>? curve,
    bool? isStale,
  }) {
    return TideForecast(
      latitude: latitude,
      longitude: longitude,
      extrema: extrema,
      curve: curve ?? this.curve,
      fetchedAt: fetchedAt,
      lowWaterLevel: lowWaterLevel,
      highWaterLevel: highWaterLevel,
      isStale: isStale ?? this.isStale,
    );
  }

  /// Ekstremum pada satu hari WIB (perbandingan tanggal WIB).
  List<TideExtremum> extremaForDay(DateTime wibDay) {
    return extrema.where((e) {
      final t = e.timeWib;
      return t.year == wibDay.year &&
          t.month == wibDay.month &&
          t.day == wibDay.day;
    }).toList();
  }

  /// Kurva untuk grafik: bila tides_array gagal, interpolasi kosinus
  /// antar-ekstremum (cukup akurat untuk tampilan; pasang surut
  /// mendekati gelombang sinus antar titik ekstremum).
  List<TideCurvePoint> get curveOrInterpolated {
    if (curve.isNotEmpty) return curve;
    return interpolateCurve(extrema);
  }

  /// Interpolasi kosinus antar ekstremum berurutan, tiap 15 menit.
  static List<TideCurvePoint> interpolateCurve(List<TideExtremum> extrema) {
    final points = <TideCurvePoint>[];
    if (extrema.length < 2) return points;
    const step = Duration(minutes: 15);
    for (var i = 0; i + 1 < extrema.length; i++) {
      final a = extrema[i];
      final b = extrema[i + 1];
      final span = b.timeUtc.difference(a.timeUtc);
      if (span <= Duration.zero) continue;
      final mean = (a.heightM + b.heightM) / 2;
      final amp = (a.heightM - b.heightM) / 2;
      var t = a.timeUtc;
      // Titik awal segmen ikut; titik akhir jadi awal segmen berikut.
      while (t.isBefore(b.timeUtc)) {
        final frac =
            t.difference(a.timeUtc).inSeconds / span.inSeconds;
        // Kosinus: 1 di awal segmen -> -1 di akhir segmen.
        final height = mean + amp * math.cos(math.pi * frac);
        points.add(TideCurvePoint(timeUtc: t, heightM: height));
        t = t.add(step);
      }
    }
    final last = extrema.last;
    points.add(
      TideCurvePoint(timeUtc: last.timeUtc, heightM: last.heightM),
    );
    return points;
  }

  // -- Parsing respons MCP hamandmore (terverifikasi live 21 Nov 2026) --

  /// Ekstrak payload dari envelope JSON-RPC tools/call:
  /// utamakan result.structuredContent, fallback ke
  /// result.content[0].text (string JSON).
  static Map<String, dynamic>? extractPayload(
    Map<String, dynamic> envelope,
  ) {
    final result = envelope['result'];
    if (result is! Map<String, dynamic>) return null;
    final structured = result['structuredContent'];
    if (structured is Map<String, dynamic>) return structured;
    final content = result['content'];
    if (content is List && content.isNotEmpty) {
      final first = content.first;
      if (first is Map<String, dynamic>) {
        final text = first['text'];
        if (text is String) {
          try {
            final decoded = jsonDecode(text);
            if (decoded is Map<String, dynamic>) return decoded;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// Bangun dari payload tides_extrema (+ kurva opsional).
  factory TideForecast.fromExtremaPayload({
    required Map<String, dynamic> payload,
    required double latitude,
    required double longitude,
    required DateTime fetchedAt,
    List<TideCurvePoint> curve = const [],
  }) {
    final rawList = payload['tideExtrema'];
    final extrema = <TideExtremum>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          try {
            extrema.add(TideExtremum.fromJson(item));
          } catch (_) {
            // Lewati satu ekstremum rusak; sisanya tetap dipakai.
          }
        }
      }
    }
    extrema.sort((a, b) => a.timeUtc.compareTo(b.timeUtc));
    return TideForecast(
      latitude: latitude,
      longitude: longitude,
      extrema: extrema,
      curve: curve,
      fetchedAt: fetchedAt,
      lowWaterLevel: (payload['lowWaterLevel'] as num?)?.toDouble(),
      highWaterLevel: (payload['highWaterLevel'] as num?)?.toDouble(),
    );
  }

  /// Parse payload tides_array: tideHeights = list string angka.
  /// Langkah waktu diturunkan dari (end-start)/(n-1) agar tidak
  /// bergantung pada asumsi interval server (saat ini 15 menit).
  static List<TideCurvePoint> parseArrayPayload({
    required Map<String, dynamic> payload,
    required DateTime startUtc,
    required DateTime endUtc,
  }) {
    final raw = payload['tideHeights'];
    if (raw is! List || raw.isEmpty) return const [];
    final heights = <double>[];
    for (final item in raw) {
      final value =
          item is num ? item.toDouble() : double.tryParse('$item');
      if (value == null) return const [];
      heights.add(value);
    }
    if (heights.length == 1) {
      return [TideCurvePoint(timeUtc: startUtc, heightM: heights.first)];
    }
    final spanMs =
        endUtc.difference(startUtc).inMilliseconds / (heights.length - 1);
    final points = <TideCurvePoint>[];
    for (var i = 0; i < heights.length; i++) {
      points.add(TideCurvePoint(
        timeUtc:
            startUtc.add(Duration(milliseconds: (spanMs * i).round())),
        heightM: heights[i],
      ));
    }
    return points;
  }

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'extrema': extrema.map((e) => e.toJson()).toList(),
        'curve': curve.map((c) => c.toJson()).toList(),
        'fetchedAt': fetchedAt.toIso8601String(),
        'lowWaterLevel': lowWaterLevel,
        'highWaterLevel': highWaterLevel,
      };

  factory TideForecast.fromJson(Map<String, dynamic> json) {
    return TideForecast(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      extrema: (json['extrema'] as List)
          .map((e) => TideExtremum.fromJson(e as Map<String, dynamic>))
          .toList(),
      curve: (json['curve'] as List)
          .map((c) => TideCurvePoint.fromJson(c as Map<String, dynamic>))
          .toList(),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      lowWaterLevel: (json['lowWaterLevel'] as num?)?.toDouble(),
      highWaterLevel: (json['highWaterLevel'] as num?)?.toDouble(),
    );
  }
}
