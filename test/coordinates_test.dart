import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/utils/coordinates.dart';

void main() {
  test('desimal titik, koma pemisah', () {
    final result = CoordinateInput.parseLatLon('-3.32, 114.59');
    expect(result, isNotNull);
    expect(result!.$1, closeTo(-3.32, 0.0001));
    expect(result.$2, closeTo(114.59, 0.0001));
  });

  test('koma desimal Indonesia', () {
    final result = CoordinateInput.parseLatLon('-3,32, 114,59');
    expect(result, isNotNull);
    expect(result!.$1, closeTo(-3.32, 0.0001));
    expect(result.$2, closeTo(114.59, 0.0001));
  });

  test('dipisah spasi / titik koma', () {
    expect(
      CoordinateInput.parseLatLon('-3.32 114.59')!.$2,
      closeTo(114.59, 0.0001),
    );
    expect(
      CoordinateInput.parseLatLon('-3,32; 114,59')!.$1,
      closeTo(-3.32, 0.0001),
    );
  });

  test('bilangan bulat diterima', () {
    final result = CoordinateInput.parseLatLon('-3, 114');
    expect(result, (-3.0, 114.0));
  });

  test('satu angka saja -> null', () {
    expect(CoordinateInput.parseLatLon('-3.32'), isNull);
    expect(CoordinateInput.parseLatLon(''), isNull);
    expect(CoordinateInput.parseLatLon('abc'), isNull);
  });

  test('di luar rentang -> null', () {
    expect(CoordinateInput.parseLatLon('91, 114.59'), isNull);
    expect(CoordinateInput.parseLatLon('-3.32, 181'), isNull);
    expect(CoordinateInput.parseLatLon('-91, 0'), isNull);
  });

  test('teks di sekitar angka diabaikan', () {
    final result =
        CoordinateInput.parseLatLon('lat -3.32 lon 114.59');
    expect(result, isNotNull);
    expect(result!.$1, closeTo(-3.32, 0.0001));
  });

  group('parseCoordinate — desimal', () {
    test('titik dan koma desimal', () {
      expect(
        CoordinateInput.parseCoordinate('-6.1234', isLatitude: true)
            .value,
        closeTo(-6.1234, 0.000001),
      );
      expect(
        CoordinateInput.parseCoordinate('-6,1234', isLatitude: true)
            .value,
        closeTo(-6.1234, 0.000001),
      );
      expect(
        CoordinateInput.parseCoordinate('106,825', isLatitude: false)
            .value,
        closeTo(106.825, 0.000001),
      );
    });

    test('desimal + huruf belahan', () {
      expect(
        CoordinateInput.parseCoordinate('6.1234°S', isLatitude: true)
            .value,
        closeTo(-6.1234, 0.000001),
      );
      expect(
        CoordinateInput.parseCoordinate('6.1234 S', isLatitude: true)
            .value,
        closeTo(-6.1234, 0.000001),
      );
      expect(
        CoordinateInput.parseCoordinate('106.825 T', isLatitude: false)
            .value,
        closeTo(106.825, 0.000001),
      );
    });
  });

  group('parseCoordinate — DMS', () {
    test('akhiran, awalan, dan spasi saja', () {
      for (final input in [
        "6°07'24\"S",
        "S 6°07'24\"",
        '6 07 24 S',
        "6°07'24\" S",
      ]) {
        final result =
            CoordinateInput.parseCoordinate(input, isLatitude: true);
        expect(result.isOk, isTrue, reason: input);
        expect(result.value, closeTo(-6.1233333, 0.000001));
      }
    });

    test('huruf Indonesia U/T/B', () {
      expect(
        CoordinateInput.parseCoordinate(
          "U 6°07'24\"",
          isLatitude: true,
        ).value,
        closeTo(6.1233333, 0.000001),
      );
      expect(
        CoordinateInput.parseCoordinate(
          "106°49'30\"T",
          isLatitude: false,
        ).value,
        closeTo(106.825, 0.000001),
      );
      expect(
        CoordinateInput.parseCoordinate(
          "106°49'30\"B",
          isLatitude: false,
        ).value,
        closeTo(-106.825, 0.000001),
      );
    });

    test('derajat-menit, menit desimal, DMS negatif tanpa huruf', () {
      expect(
        CoordinateInput.parseCoordinate("6°07'S", isLatitude: true)
            .value,
        closeTo(-6.1166667, 0.000001),
      );
      expect(
        CoordinateInput.parseCoordinate("6°07.5'S", isLatitude: true)
            .value,
        closeTo(-6.125, 0.000001),
      );
      expect(
        CoordinateInput.parseCoordinate("-6°07'24\"", isLatitude: true)
            .value,
        closeTo(-6.1233333, 0.000001),
      );
    });

    test('bujur DMS', () {
      expect(
        CoordinateInput.parseCoordinate(
          "106°49'30\"E",
          isLatitude: false,
        ).value,
        closeTo(106.825, 0.000001),
      );
    });
  });

  group('parseCoordinate — tidak valid -> null + pesan', () {
    test('kosong / bukan angka', () {
      final empty =
          CoordinateInput.parseCoordinate('', isLatitude: true);
      expect(empty.value, isNull);
      expect(empty.error, contains('kosong'));
      final garbage =
          CoordinateInput.parseCoordinate('abc', isLatitude: true);
      expect(garbage.value, isNull);
      expect(garbage.error, isNotNull);
    });

    test('di luar rentang', () {
      final lat =
          CoordinateInput.parseCoordinate('91', isLatitude: true);
      expect(lat.value, isNull);
      expect(lat.error, contains('-90'));
      final lon =
          CoordinateInput.parseCoordinate('181', isLatitude: false);
      expect(lon.value, isNull);
      expect(lon.error, contains('-180'));
    });

    test('menit/detik 60 ditolak', () {
      expect(
        CoordinateInput.parseCoordinate("6°60'00\"S", isLatitude: true)
            .error,
        contains('Menit'),
      );
      expect(
        CoordinateInput.parseCoordinate("6°07'60\"S", isLatitude: true)
            .error,
        contains('Detik'),
      );
    });

    test('huruf sumbu yang salah ditolak', () {
      expect(
        CoordinateInput.parseCoordinate(
          "106°49'30\"E",
          isLatitude: true,
        ).error,
        contains('bujur'),
      );
      expect(
        CoordinateInput.parseCoordinate(
          "6°07'24\"S",
          isLatitude: false,
        ).error,
        contains('lintang'),
      );
    });

    test('terlalu banyak angka', () {
      expect(
        CoordinateInput.parseCoordinate('6 07 24 30', isLatitude: true)
            .error,
        contains('Terlalu banyak'),
      );
    });
  });

  group('parseDms — ketat', () {
    test('DMS diterima, desimal polos ditolak', () {
      expect(
        CoordinateInput.parseDms("6°07'24\"S", isLatitude: true).value,
        closeTo(-6.1233333, 0.000001),
      );
      expect(
        CoordinateInput.parseDms('6.12 S', isLatitude: true).value,
        closeTo(-6.12, 0.000001),
      );
      final decimal =
          CoordinateInput.parseDms('-6.1234', isLatitude: true);
      expect(decimal.value, isNull);
      expect(decimal.error, contains('DMS'));
    });
  });

  group('parseLatLon — pasangan DMS', () {
    test('gaya akhiran dan awalan', () {
      final suffix =
          CoordinateInput.parseLatLon("6°07'24\"S 106°49'30\"E");
      expect(suffix, isNotNull);
      expect(suffix!.$1, closeTo(-6.1233333, 0.000001));
      expect(suffix.$2, closeTo(106.825, 0.000001));
      final prefix =
          CoordinateInput.parseLatLon("S 6°07'24\" E 106°49'30\"");
      expect(prefix, isNotNull);
      expect(prefix!.$1, closeTo(-6.1233333, 0.000001));
      expect(prefix.$2, closeTo(106.825, 0.000001));
    });

    test('desimal + huruf, koma pemisah', () {
      final result =
          CoordinateInput.parseLatLon('6.12 S, 106.5 E');
      expect(result, isNotNull);
      expect(result!.$1, closeTo(-6.12, 0.000001));
      expect(result.$2, closeTo(106.5, 0.000001));
      final comma =
          CoordinateInput.parseLatLon("3°19'12\"S, 114°35'24\"E");
      expect(comma, isNotNull);
      expect(comma!.$1, closeTo(-3.32, 0.000001));
      expect(comma.$2, closeTo(114.59, 0.000001));
    });

    test('satu huruf saja / tanpa huruf', () {
      final noLonHemi =
          CoordinateInput.parseLatLon("6°07'24\"S 106°49'30\"");
      expect(noLonHemi, isNotNull);
      expect(noLonHemi!.$2, closeTo(106.825, 0.000001));
      final noLatHemi =
          CoordinateInput.parseLatLon("6°07'24\" 106°49'30\"E");
      expect(noLatHemi, isNotNull);
      expect(noLatHemi!.$1, closeTo(6.1233333, 0.000001));
      final noHemi =
          CoordinateInput.parseLatLon("6°07'24\" 106°49'30\"");
      expect(noHemi, isNotNull);
      expect(noHemi!.$1, closeTo(6.1233333, 0.000001));
      expect(noHemi.$2, closeTo(106.825, 0.000001));
    });

    test('gaya campuran berpemisah tetap terbaca', () {
      final mixed =
          CoordinateInput.parseLatLon("S 6°07'24\" 106°49'30\"E");
      expect(mixed, isNotNull);
      expect(mixed!.$1, closeTo(-6.1233333, 0.000001));
      expect(mixed.$2, closeTo(106.825, 0.000001));
      final noSpace =
          CoordinateInput.parseLatLon("6°07'24\"S106°49'30\"E");
      expect(noSpace, isNotNull);
      expect(noSpace!.$1, closeTo(-6.1233333, 0.000001));
      expect(noSpace.$2, closeTo(106.825, 0.000001));
    });

    test('gaya campuran tanpa pemisah dan DMS rusak -> null', () {
      expect(
        CoordinateInput.parseLatLon("S6°07'24\"106°49'30\"E"),
        isNull,
      );
      expect(
        CoordinateInput.parseLatLon("6°07'24\"S 106°49'30\"X"),
        isNull,
      );
      expect(
        CoordinateInput.parseLatLon("6°60'00\"S 106°49'30\"E"),
        isNull,
      );
    });
  });

  group('isInAsean', () {
    test('di dalam dan di tepi bbox', () {
      expect(CoordinateInput.isInAsean(-3.32, 114.59), isTrue);
      expect(CoordinateInput.isInAsean(-6.12, 106.82), isTrue);
      expect(CoordinateInput.isInAsean(-11.0, 92.0), isTrue);
      expect(CoordinateInput.isInAsean(29.0, 141.0), isTrue);
    });

    test('di luar bbox', () {
      expect(CoordinateInput.isInAsean(30.0, 116.0), isFalse);
      expect(CoordinateInput.isInAsean(-12.0, 116.0), isFalse);
      expect(CoordinateInput.isInAsean(0, 91.9), isFalse);
      expect(CoordinateInput.isInAsean(0, 141.1), isFalse);
      expect(CoordinateInput.isInAsean(51.5, -0.12), isFalse);
    });
  });
}
