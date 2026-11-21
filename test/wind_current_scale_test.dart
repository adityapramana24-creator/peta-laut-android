import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/ui/windy/widgets/wind_legend.dart';

/// Skala warna angin + arus (ronde 2, item 4): titik henti harus
/// persis (legenda dan garis memakai nilai yang sama); nilai
/// tengah dicek rentangnya saja (pembulatan lerp tidak dijamin).
void main() {
  group('WindColorScale', () {
    test('titik henti mengembalikan warna persis', () {
      expect(
        WindColorScale.colorForKmh(0),
        const Color(0xFFB8E3F5),
      );
      expect(
        WindColorScale.colorForKmh(10),
        const Color(0xFF6FC7E8),
      );
      expect(
        WindColorScale.colorForKmh(20),
        const Color(0xFF3AA655),
      );
      expect(
        WindColorScale.colorForKmh(30),
        const Color(0xFFF5D90A),
      );
      expect(
        WindColorScale.colorForKmh(40),
        const Color(0xFFF59E0B),
      );
      expect(
        WindColorScale.colorForKmh(50),
        const Color(0xFFE84B3C),
      );
      expect(
        WindColorScale.colorForKmh(65),
        const Color(0xFF8E44AD),
      );
    });

    test('di luar rentang dijepit ke ujung', () {
      expect(
        WindColorScale.colorForKmh(-5),
        const Color(0xFFB8E3F5),
      );
      expect(
        WindColorScale.colorForKmh(100),
        const Color(0xFF8E44AD),
      );
    });

    test('nilai tengah berada di antara kedua henti', () {
      // 15 km/jam: di antara (10, #6FC7E8) dan (20, #3AA655).
      final mid = WindColorScale.colorForKmh(15);
      expect(mid.red, greaterThan(58));
      expect(mid.red, lessThan(111));
      expect(mid.green, greaterThan(166));
      expect(mid.green, lessThan(199));
      expect(mid.blue, greaterThan(85));
      expect(mid.blue, lessThan(232));
    });

    test('kecepatan berbeda -> warna berbeda', () {
      expect(
        WindColorScale.colorForKmh(5),
        isNot(WindColorScale.colorForKmh(45)),
      );
    });
  });

  group('CurrentColorScale', () {
    test('titik henti mengembalikan warna persis', () {
      expect(
        CurrentColorScale.colorForKnots(0),
        const Color(0xFF7FB8E8),
      );
      expect(
        CurrentColorScale.colorForKnots(0.5),
        const Color(0xFF3AA655),
      );
      expect(
        CurrentColorScale.colorForKnots(1.0),
        const Color(0xFFF5D90A),
      );
      expect(
        CurrentColorScale.colorForKnots(2.0),
        const Color(0xFFF59E0B),
      );
      expect(
        CurrentColorScale.colorForKnots(3.0),
        const Color(0xFFE84B3C),
      );
    });

    test('di luar rentang dijepit ke ujung', () {
      expect(
        CurrentColorScale.colorForKnots(-1),
        const Color(0xFF7FB8E8),
      );
      expect(
        CurrentColorScale.colorForKnots(9),
        const Color(0xFFE84B3C),
      );
    });

    test('nilai tengah berada di antara kedua henti', () {
      // 1,5 kt: di antara (1, #F5D90A) dan (2, #F59E0B).
      final mid = CurrentColorScale.colorForKnots(1.5);
      expect(mid.red, 245);
      expect(mid.green, greaterThan(158));
      expect(mid.green, lessThan(217));
      expect(mid.blue, greaterThanOrEqualTo(10));
      expect(mid.blue, lessThanOrEqualTo(11));
    });
  });
}
