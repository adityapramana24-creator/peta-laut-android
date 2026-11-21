import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/utils/sun_moon.dart';

/// Nilai referensi publik 21 Nov 2026 (dicari 21 Nov 2026):
/// - Jakarta terbit 05:25 WIB, terbenam 17:50/17:51 WIB (weather.com).
/// - Bulan: Waxing Gibbous, iluminasi 86–89%, umur 11,6–12,0 hari
///   (moongiant/lunarly/timeanddate).
/// - Purnama 24 Nov 2026 15:59 UTC; bulan baru 9 Des 2026 01:53 UTC.
/// Toleransi matahari ±3 menit (algoritma NOAA ±1 menit + pembulatan
/// referensi ke menit).
void main() {
  group('sunTimes Jakarta 21 Nov 2026', () {
    test('terbit ~05:26 WIB, terbenam ~17:51 WIB', () {
      final (rise, set) = SunMoon.sunTimes(
        latitude: -6.20,
        longitude: 106.85,
        date: DateTime(2026, 11, 21),
      );
      expect(rise, isNotNull);
      expect(set, isNotNull);
      final refRise = DateTime(2026, 11, 21, 5, 25);
      final refSet = DateTime(2026, 11, 21, 17, 51);
      expect(
        rise!.difference(refRise).abs(),
        lessThanOrEqualTo(const Duration(minutes: 3)),
      );
      expect(
        set!.difference(refSet).abs(),
        lessThanOrEqualTo(const Duration(minutes: 3)),
      );
    });

    test('siang lebih panjang dari 12 jam di khatulistiwa', () {
      final (rise, set) = SunMoon.sunTimes(
        latitude: -6.20,
        longitude: 106.85,
        date: DateTime(2026, 11, 21),
      );
      final dayLength = set!.difference(rise!);
      expect(dayLength.inHours, 12);
      expect(dayLength.inMinutes, greaterThan(12 * 60));
    });
  });

  group('sunTimes zona lain', () {
    test('Banjarmasin (WITA) terbit ~05:59, terbenam ~18:16', () {
      final (rise, set) = SunMoon.sunTimes(
        latitude: -3.32,
        longitude: 114.59,
        date: DateTime(2026, 11, 21),
      );
      expect(rise, isNotNull);
      expect(set, isNotNull);
      // Nilai dari implementasi Python yang sama (NOAA), ±3 menit.
      expect(
        rise!.difference(DateTime(2026, 11, 21, 5, 59)).abs(),
        lessThanOrEqualTo(const Duration(minutes: 3)),
      );
      expect(
        set!.difference(DateTime(2026, 11, 21, 18, 16)).abs(),
        lessThanOrEqualTo(const Duration(minutes: 3)),
      );
    });

    test('kutub: matahari tidak terbit di musim dingin', () {
      final (rise, set) = SunMoon.sunTimes(
        latitude: 78.0,
        longitude: 16.0,
        date: DateTime(2026, 1, 15),
      );
      expect(rise, isNull);
      expect(set, isNull);
    });
  });

  group('timezoneOffsetHours', () {
    test('bujur Indonesia -> WIB/WITA/WIT', () {
      expect(SunMoon.timezoneOffsetHours(106.85), 7);
      expect(SunMoon.timezoneOffsetHours(114.59), 8);
      expect(SunMoon.timezoneOffsetHours(140.72), 9);
      expect(SunMoon.timezoneLabel(7), 'WIB');
      expect(SunMoon.timezoneLabel(8), 'WITA');
      expect(SunMoon.timezoneLabel(9), 'WIT');
    });
  });

  group('moonPhase 21 Nov 2026', () {
    test('umur ~11,6 hari, iluminasi ~89%, Benjol awal', () {
      final phase = SunMoon.moonPhase(DateTime.utc(2026, 11, 21, 12));
      expect(phase.ageDays, closeTo(11.58, 0.5));
      expect(phase.illumination, closeTo(0.89, 0.05));
      expect(phase.phaseIndex, 3);
      expect(phase.name, 'Benjol awal');
      expect(phase.isWaxing, isTrue);
    });

    test('purnama 24 Nov 2026 ~100%', () {
      final phase = SunMoon.moonPhase(DateTime.utc(2026, 11, 24, 15, 59));
      expect(phase.illumination, closeTo(1.0, 0.02));
      expect(phase.phaseIndex, 4);
      expect(phase.name, 'Purnama');
    });

    test('bulan baru 9 Des 2026 ~0%', () {
      final phase = SunMoon.moonPhase(DateTime.utc(2026, 12, 9, 1, 53));
      expect(phase.illumination, closeTo(0.0, 0.02));
      expect(phase.phaseIndex, 0);
      expect(phase.name, 'Bulan baru');
    });

    test('nama fase 8 buah, indeks 0..7', () {
      expect(MoonPhase.phaseNames.length, 8);
      for (var day = 0; day < 30; day++) {
        final phase = SunMoon.moonPhase(
          DateTime.utc(2026, 11, 1).add(Duration(days: day)),
        );
        expect(phase.phaseIndex, inInclusiveRange(0, 7));
        expect(phase.illumination, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}
