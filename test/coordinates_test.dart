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
}
