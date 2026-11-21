import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/data/services/rainviewer_service.dart';

/// Template tile RainViewer (F-R3): format resmi
/// {host}{path}/{size}/{z}/{x}/{y}/{color}/{options}.png —
/// "256" HARUS sebelum z/x/y, kalau tidak semua tile 404.
void main() {
  group('RainViewerService.parseTileTemplate', () {
    Map<String, dynamic> manifest(String path) => {
          'host': 'https://tilecache.rainviewer.com',
          'radar': {
            'past': [
              {'time': 1763700000, 'path': '/v2/radar/1763700000'},
              {'time': 1763700600, 'path': path},
            ],
          },
        };

    test('F-R3: susunan resmi 256/{z}/{x}/{y}/2/1_1.png', () {
      final template = RainViewerService.parseTileTemplate(
        manifest('/v2/radar/1763700600'),
      );
      expect(
        template,
        'https://tilecache.rainviewer.com'
        '/v2/radar/1763700600/256/{z}/{x}/{y}/2/1_1.png',
      );
    });

    test('frame terakhir yang dipakai', () {
      final template = RainViewerService.parseTileTemplate(
        manifest('/v2/radar/999'),
      );
      expect(template, contains('/v2/radar/999/256/'));
    });

    test('manifest rusak -> null', () {
      expect(RainViewerService.parseTileTemplate({}), isNull);
      expect(
        RainViewerService.parseTileTemplate({
          'host': 'https://tilecache.rainviewer.com',
          'radar': {'past': []},
        }),
        isNull,
      );
      expect(
        RainViewerService.parseTileTemplate({
          'host': 'https://tilecache.rainviewer.com',
          'radar': {'past': [{}]},
        }),
        isNull,
      );
    });
  });
}
