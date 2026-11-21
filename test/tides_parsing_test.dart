import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/domain/models/tide.dart';

/// Fixture = respons ASLI yang ditangkap live 21 Nov 2026 ~23:01 WIB
/// (Banjarmasin -3.32, 114.59). Disalin verbatim dari /tmp — file /tmp
/// bersifat sementara, jadi fixture hidup di test ini.
void main() {
  const extremaEnvelope = r'''{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"{\"currentTime\":\"2026-11-20T23:01:36.760783Z\",\"tideExtrema\":[{\"extrema\":\"low\",\"time\":\"2026-11-21T00:52:21.640786Z\",\"height\":0.3263858177725376},{\"extrema\":\"high\",\"time\":\"2026-11-21T07:17:38.359214Z\",\"height\":0.9962651986807503},{\"extrema\":\"low\",\"time\":\"2026-11-21T10:12:21.640786Z\",\"height\":0.9238226732540338},{\"extrema\":\"high\",\"time\":\"2026-11-21T17:12:21.640786Z\",\"height\":1.6194109869150444}],\"lowWaterLevel\":-0.879,\"highWaterLevel\":2.472}"}],"structuredContent":{"currentTime":"2026-11-20T23:01:36.760783Z","tideExtrema":[{"extrema":"low","time":"2026-11-21T00:52:21.640786Z","height":0.3263858177725376},{"extrema":"high","time":"2026-11-21T07:17:38.359214Z","height":0.9962651986807503},{"extrema":"low","time":"2026-11-21T10:12:21.640786Z","height":0.9238226732540338},{"extrema":"high","time":"2026-11-21T17:12:21.640786Z","height":1.6194109869150444}],"lowWaterLevel":-0.879,"highWaterLevel":2.472}}}''';

  const arrayEnvelope = r'''{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"{\"currentTime\":\"2026-11-20T23:01:45.801430Z\",\"tideHeights\":[\"0.365\",\"0.346\",\"0.334\",\"0.327\",\"0.327\",\"0.332\",\"0.343\",\"0.360\",\"0.381\",\"0.407\",\"0.438\",\"0.472\",\"0.510\",\"0.549\",\"0.591\",\"0.633\",\"0.676\",\"0.719\",\"0.760\",\"0.799\",\"0.836\",\"0.869\",\"0.899\",\"0.926\",\"0.948\"],\"lowWaterLevel\":-0.879,\"highWaterLevel\":2.472}"}],"structuredContent":{"currentTime":"2026-11-20T23:01:45.801430Z","tideHeights":["0.365","0.346","0.334","0.327","0.327","0.332","0.343","0.360","0.381","0.407","0.438","0.472","0.510","0.549","0.591","0.633","0.676","0.719","0.760","0.799","0.836","0.869","0.899","0.926","0.948"],"lowWaterLevel":-0.879,"highWaterLevel":2.472}}}''';

  group('extractPayload', () {
    test('utamakan structuredContent', () {
      final envelope =
          jsonDecode(extremaEnvelope) as Map<String, dynamic>;
      final payload = TideForecast.extractPayload(envelope);
      expect(payload, isNotNull);
      expect(payload!['lowWaterLevel'], -0.879);
      expect(payload['highWaterLevel'], 2.472);
      expect((payload['tideExtrema'] as List).length, 4);
    });

    test('fallback ke content[0].text bila structuredContent absen', () {
      final envelope =
          jsonDecode(extremaEnvelope) as Map<String, dynamic>;
      final result = Map<String, dynamic>.from(
        envelope['result'] as Map<String, dynamic>,
      );
      result.remove('structuredContent');
      envelope['result'] = result;
      final payload = TideForecast.extractPayload(envelope);
      expect(payload, isNotNull);
      expect((payload!['tideExtrema'] as List).length, 4);
    });

    test('envelope tanpa result -> null', () {
      expect(TideForecast.extractPayload({}), isNull);
    });
  });

  group('fromExtremaPayload', () {
    test('parse 4 ekstremum Banjarmasin', () {
      final envelope =
          jsonDecode(extremaEnvelope) as Map<String, dynamic>;
      final payload = TideForecast.extractPayload(envelope)!;
      final forecast = TideForecast.fromExtremaPayload(
        payload: payload,
        latitude: -3.32,
        longitude: 114.59,
        fetchedAt: DateTime.utc(2026, 11, 20, 23, 1),
      );
      expect(forecast.extrema.length, 4);
      expect(forecast.extrema[0].isHigh, isFalse);
      expect(forecast.extrema[0].heightM, closeTo(0.326, 0.001));
      // Waktu asli 00:52:21.640786Z — bandingkan jam/menit saja
      // (DateTime == juga membandingkan mikrodetik).
      expect(forecast.extrema[0].timeUtc.hour, 0);
      expect(forecast.extrema[0].timeUtc.minute, 52);
      expect(forecast.extrema[0].timeUtc.day, 21);
      expect(forecast.extrema[3].isHigh, isTrue);
      expect(forecast.extrema[3].heightM, closeTo(1.619, 0.001));
      expect(forecast.lowWaterLevel, -0.879);
      expect(forecast.highWaterLevel, 2.472);
    });

    test('ekstremum terurut waktu', () {
      final envelope =
          jsonDecode(extremaEnvelope) as Map<String, dynamic>;
      final payload = TideForecast.extractPayload(envelope)!;
      final forecast = TideForecast.fromExtremaPayload(
        payload: payload,
        latitude: -3.32,
        longitude: 114.59,
        fetchedAt: DateTime.now(),
      );
      for (var i = 0; i + 1 < forecast.extrema.length; i++) {
        expect(
          forecast.extrema[i].timeUtc
              .isBefore(forecast.extrema[i + 1].timeUtc),
          isTrue,
        );
      }
    });
  });

  group('parseArrayPayload', () {
    test('25 nilai string -> 25 titik, langkah diturunkan', () {
      final envelope =
          jsonDecode(arrayEnvelope) as Map<String, dynamic>;
      final payload = TideForecast.extractPayload(envelope)!;
      final start = DateTime.utc(2026, 11, 21, 0, 0);
      final end = DateTime.utc(2026, 11, 21, 6, 0);
      final points = TideForecast.parseArrayPayload(
        payload: payload,
        startUtc: start,
        endUtc: end,
      );
      expect(points.length, 25);
      expect(points.first.heightM, closeTo(0.365, 0.001));
      expect(points.last.heightM, closeTo(0.948, 0.001));
      expect(points.first.timeUtc, start);
      expect(points.last.timeUtc, end);
      // Langkah 6 jam / 24 = 15 menit.
      expect(
        points[1].timeUtc.difference(points[0].timeUtc),
        const Duration(minutes: 15),
      );
    });

    test('payload kosong -> list kosong', () {
      final points = TideForecast.parseArrayPayload(
        payload: {},
        startUtc: DateTime.utc(2026, 11, 21),
        endUtc: DateTime.utc(2026, 11, 21, 6),
      );
      expect(points, isEmpty);
    });
  });

  group('extremaForDay', () {
    test('pengelompokan per hari WIB', () {
      final envelope =
          jsonDecode(extremaEnvelope) as Map<String, dynamic>;
      final payload = TideForecast.extractPayload(envelope)!;
      final forecast = TideForecast.fromExtremaPayload(
        payload: payload,
        latitude: -3.32,
        longitude: 114.59,
        fetchedAt: DateTime.now(),
      );
      // 00:52 UTC = 07:52 WIB 21 Nov; 17:12 UTC = 00:12 WIB 22 Nov.
      final day21 = DateTime(2026, 11, 21);
      final day22 = DateTime(2026, 11, 22);
      expect(forecast.extremaForDay(day21).length, 3);
      expect(forecast.extremaForDay(day22).length, 1);
    });
  });

  group('interpolateCurve', () {
    test('interpolasi kosinus antar ekstremum', () {
      final extrema = [
        TideExtremum(
          type: TideType.low,
          timeUtc: DateTime.utc(2026, 11, 21, 0, 52),
          heightM: 0.33,
        ),
        TideExtremum(
          type: TideType.high,
          timeUtc: DateTime.utc(2026, 11, 21, 7, 17),
          heightM: 1.0,
        ),
      ];
      final points = TideForecast.interpolateCurve(extrema);
      expect(points, isNotEmpty);
      expect(points.first.heightM, closeTo(0.33, 0.001));
      expect(points.last.heightM, closeTo(1.0, 0.001));
      // Titik tengah ~ rata-rata kedua ekstremum.
      final mid = points[points.length ~/ 2];
      expect(mid.heightM, closeTo(0.665, 0.05));
    });

    test('kurang dari 2 ekstremum -> kosong', () {
      expect(TideForecast.interpolateCurve([]), isEmpty);
    });
  });

  group('toJson/fromJson round-trip', () {
    test('cache round-trip utuh', () {
      final envelope =
          jsonDecode(extremaEnvelope) as Map<String, dynamic>;
      final payload = TideForecast.extractPayload(envelope)!;
      final forecast = TideForecast.fromExtremaPayload(
        payload: payload,
        latitude: -3.32,
        longitude: 114.59,
        fetchedAt: DateTime.utc(2026, 11, 20, 23, 1),
      );
      final restored =
          TideForecast.fromJson(forecast.toJson());
      expect(restored.extrema.length, 4);
      expect(restored.lowWaterLevel, -0.879);
      expect(restored.latitude, -3.32);
    });
  });
}
