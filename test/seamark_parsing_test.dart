import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/data/services/seamark_service.dart';
import 'package:peta_laut/domain/models/seamark.dart';

/// Parsing rambu laut dari tag seamark OpenStreetMap (ronde 2, butir 20).
///
/// TAG-nya adalah data NYATA dari riset live 21 Nov 2026 (respons OSM API
/// — lihat DAFTAR-PERBAIKAN-R2.md butir 20). Koordinat + id OSM di bawah
/// ini adalah FIXTURE TEST (perkiraan, bukan koordinat persis rambu) —
/// yang diuji adalah parsing TAG, bukan posisi rambu.
void main() {
  group('Seamark.fromOsmTags — contoh nyata Tanjung Priok', () {
    test('Tanjung Priok Inner Harbor: landmark + cahaya Fl putih', () {
      final seamark = Seamark.fromOsmTags(
        id: 'node/test-priok-inner-harbor',
        latitude: -6.10,
        longitude: 106.88,
        tags: const {
          'seamark:type': 'landmark',
          'seamark:name': 'Tanjung Priok Inner Harbor',
          'seamark:light:character': 'Fl',
          'seamark:light:colour': 'white',
          'seamark:light:period': '10',
          'seamark:light:height': '46',
          'seamark:light:range': '18',
          'seamark:light:reference': 'Q 1073.5',
          'seamark:source': 'NGA Pub. 112 2023',
        },
      )!;
      expect(seamark.kind, SeamarkKind.landmark);
      expect(seamark.typeLabel, 'Tanda Darat');
      expect(seamark.displayName, 'Tanjung Priok Inner Harbor');
      expect(seamark.lightCharacter, 'Fl');
      expect(seamark.lightColour, 'white');
      expect(seamark.lightPeriodSec, 10);
      expect(seamark.lightHeightM, 46);
      expect(seamark.lightRangeNm, 18);
      expect(seamark.lightReference, 'Q 1073.5');
      expect(seamark.source, 'NGA Pub. 112 2023');
      final summary = seamark.lightSummary!;
      expect(summary, contains('Berkedip (Fl)'));
      expect(summary, contains('Putih'));
      expect(summary, contains('10 dtk'));
      expect(summary, contains('tinggi 46 m'));
      expect(summary, contains('jangkauan 18 nm'));
    });

    test('Beacon lateral Priok: port merah IALA-A, tanpa nama', () {
      final seamark = Seamark.fromOsmTags(
        id: 'node/test-priok-lateral',
        latitude: -6.10,
        longitude: 106.87,
        tags: const {
          'seamark:type': 'beacon_lateral',
          'seamark:beacon_lateral:category': 'port',
          'seamark:beacon_lateral:colour': 'red',
          'seamark:beacon_lateral:system': 'iala-a',
          'seamark:light:character': 'Fl',
          'seamark:light:colour': 'red',
          'seamark:light:period': '3',
          'seamark:light:height': '10',
          'seamark:light:range': '12',
          'seamark:light:reference': 'K 1076.9',
        },
      )!;
      expect(seamark.kind, SeamarkKind.lateral);
      expect(seamark.lateralSide, LateralSide.port);
      expect(seamark.colour, 'red');
      expect(seamark.ialaSystem, 'iala-a');
      expect(seamark.typeLabel, 'Rambu Suar Sisi Kiri (Port)');
      // Tanpa nama -> nama tampil jatuh ke label jenis.
      expect(seamark.displayName, 'Rambu Suar Sisi Kiri (Port)');
      expect(seamark.lightReference, 'K 1076.9');
      final summary = seamark.lightSummary!;
      expect(summary, contains('Berkedip (Fl)'));
      expect(summary, contains('Merah'));
      expect(summary, contains('3 dtk'));
      expect(summary, contains('tinggi 10 m'));
      expect(summary, contains('jangkauan 12 nm'));
    });
  });

  group('Seamark.fromOsmTags — contoh nyata Surabaya', () {
    test('"Pisang": nama hanya di seamark:name; tag IALA-B DITAMPILKAN '
        'apa adanya (tidak "diperbaiki" jadi IALA-A)', () {
      final seamark = Seamark.fromOsmTags(
        id: 'node/test-surabaya-pisang',
        latitude: -7.20,
        longitude: 112.72,
        tags: const {
          'seamark:type': 'beacon_lateral',
          // Nama HANYA di seamark:name (tanpa tag `name`).
          'seamark:name': 'Pisang',
          'seamark:beacon_lateral:category': 'port',
          'seamark:beacon_lateral:colour': 'green',
          // PATUT DICURIGAI: Indonesia memakai IALA-A, tapi tag ini
          // bilang IALA-B. Model TIDAK BOLEH mengubahnya diam-diam.
          'seamark:beacon_lateral:system': 'iala-b',
          'seamark:light:character': 'Fl',
          'seamark:light:colour': 'green',
          'seamark:light:period': '5',
          'seamark:light:height': '12',
          'seamark:light:range': '10',
          'seamark:light:reference': 'K 1168',
        },
      )!;
      expect(seamark.name, 'Pisang');
      expect(seamark.displayName, 'Pisang');
      expect(seamark.kind, SeamarkKind.lateral);
      expect(seamark.lateralSide, LateralSide.port);
      expect(seamark.colour, 'green');
      expect(seamark.ialaSystem, 'iala-b');
      expect(seamark.typeLabel, 'Rambu Suar Sisi Kiri (Port)');
      expect(seamark.lightReference, 'K 1168');
      final summary = seamark.lightSummary!;
      expect(summary, contains('Hijau'));
      expect(summary, contains('5 dtk'));
      expect(summary, contains('tinggi 12 m'));
      expect(summary, contains('jangkauan 10 nm'));
    });
  });

  group('Seamark.fromOsmTags — nama, tag hilang, tag parsial', () {
    test('nama dari tag `name` bila `seamark:name` tidak ada; '
        '`seamark:name` menang bila keduanya ada', () {
      final fromName = Seamark.fromOsmTags(
        id: 'node/test-name',
        latitude: 0,
        longitude: 0,
        tags: const {
          'seamark:type': 'light_minor',
          'name': 'Lampu Tanjung',
        },
      )!;
      expect(fromName.name, 'Lampu Tanjung');
      final both = Seamark.fromOsmTags(
        id: 'node/test-both-names',
        latitude: 0,
        longitude: 0,
        tags: const {
          'seamark:type': 'light_minor',
          'seamark:name': 'Nama Seamark',
          'name': 'Nama Biasa',
        },
      )!;
      expect(both.name, 'Nama Seamark');
    });

    test('tanpa nama + tanpa cahaya: nama jatuh ke label jenis, '
        'lightSummary null (bukan karangan)', () {
      final seamark = Seamark.fromOsmTags(
        id: 'node/test-minimal',
        latitude: 0,
        longitude: 0,
        tags: const {'seamark:type': 'buoy_lateral'},
      )!;
      expect(seamark.kind, SeamarkKind.lateral);
      expect(seamark.lateralSide, LateralSide.unknown);
      expect(seamark.typeLabel, 'Pelampung Lateral');
      expect(seamark.displayName, 'Pelampung Lateral');
      expect(seamark.lightSummary, isNull);
      expect(seamark.lightReference, isNull);
    });

    test('tanpa tag seamark:type -> null (bukan rambu)', () {
      expect(
        Seamark.fromOsmTags(
          id: 'node/test-not-seamark',
          latitude: 0,
          longitude: 0,
          tags: const {'name': 'Bukan Rambu'},
        ),
        isNull,
      );
    });

    test('cahaya parsial: hanya karakter + warna -> ringkasan hanya '
        'menyebut yang ada', () {
      final seamark = Seamark.fromOsmTags(
        id: 'node/test-partial-light',
        latitude: 0,
        longitude: 0,
        tags: const {
          'seamark:type': 'light_minor',
          'seamark:light:character': 'Iso',
          'seamark:light:colour': 'white',
        },
      )!;
      expect(seamark.lightSummary, 'Isophase (Iso) · Putih');
    });

    test('kelompok kilatan: Fl(2) -> "Berkedip kelompok 2 (Fl(2))"', () {
      final seamark = Seamark.fromOsmTags(
        id: 'node/test-group',
        latitude: 0,
        longitude: 0,
        tags: const {
          'seamark:type': 'buoy_cardinal',
          'seamark:buoy_cardinal:category': 'north',
          'seamark:light:character': 'Fl',
          'seamark:light:group': '2',
          'seamark:light:period': '10',
        },
      )!;
      expect(
        seamark.lightSummary,
        'Berkedip kelompok 2 (Fl(2)) · 10 dtk',
      );
    });
  });

  group('Seamark.typeLabel — mapping kategori ke Bahasa Indonesia', () {
    test('lateral starboard pelampung + kardinal + bahaya + air aman + '
        'tujuan khusus + lampu + kapal lampu + pelabuhan', () {
      Seamark make(String type, {Map<String, String> extra = const {}}) {
        return Seamark.fromOsmTags(
          id: 'node/test-label-$type',
          latitude: 0,
          longitude: 0,
          tags: {'seamark:type': type, ...extra},
        )!;
      }

      expect(
        make('buoy_lateral', extra: {
          'seamark:buoy_lateral:category': 'starboard',
        }).typeLabel,
        'Pelampung Sisi Kanan (Starboard)',
      );
      expect(
        make('buoy_cardinal', extra: {
          'seamark:buoy_cardinal:category': 'north',
        }).typeLabel,
        'Pelampung Kardinal Utara',
      );
      expect(
        make('beacon_cardinal', extra: {
          'seamark:beacon_cardinal:category': 'south',
        }).typeLabel,
        'Rambu Suar Kardinal Selatan',
      );
      expect(
        make('beacon_cardinal').typeLabel,
        'Rambu Suar Kardinal',
      );
      expect(
        make('beacon_isolated_danger').typeLabel,
        'Rambu Bahaya Terisolasi',
      );
      expect(
        make('buoy_safe_water').typeLabel,
        'Pelampung Air Aman',
      );
      expect(
        make('buoy_special_purpose').typeLabel,
        'Pelampung Tujuan Khusus',
      );
      expect(make('light_major').typeLabel, 'Mercusuar (Lampu Utama)');
      expect(make('light_minor').typeLabel, 'Lampu Kecil');
      expect(make('landmark').typeLabel, 'Tanda Darat');
      expect(make('light_vessel').typeLabel, 'Kapal Lampu');
      expect(make('harbour').typeLabel, 'Pelabuhan');
      expect(make('fog_signal').typeLabel, 'Rambu Laut');
    });
  });

  group('SeamarkService.buildQuery', () {
    test('query memuat seamark:type, bbox urutan S,W,U,T, dan '
        'out center', () {
      final query = SeamarkService.buildQuery(
        south: -6.2,
        west: 106.8,
        north: -6.0,
        east: 107.0,
      );
      expect(query, contains('[out:json]'));
      expect(query, contains('node["seamark:type"]'));
      expect(query, contains('way["seamark:type"]'));
      expect(query, contains('relation["seamark:type"]'));
      expect(
        query,
        contains('(-6.200000,106.800000,-6.000000,107.000000)'),
      );
      expect(query, contains('out center;'));
    });
  });

  group('SeamarkService.parseOverpassResponse', () {
    test('node + way (center) ter-parse; elemen tanpa koordinat / '
        'tanpa seamark:type / relation tanpa center dilewati', () {
      final body = jsonEncode({
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': -6.10,
            'lon': 106.88,
            'tags': {
              'seamark:type': 'beacon_lateral',
              'seamark:beacon_lateral:category': 'port',
              'seamark:beacon_lateral:colour': 'red',
            },
          },
          {
            'type': 'way',
            'id': 2,
            'center': {'lat': -7.20, 'lon': 112.72},
            'tags': {
              'seamark:type': 'beacon_lateral',
              'seamark:name': 'Pisang',
            },
          },
          // Node tanpa koordinat -> dilewati.
          {
            'type': 'node',
            'id': 3,
            'tags': {'seamark:type': 'light_minor'},
          },
          // Node tanpa seamark:type -> dilewati.
          {
            'type': 'node',
            'id': 4,
            'lat': -6.0,
            'lon': 106.0,
            'tags': {'name': 'Bukan Rambu'},
          },
          // Relation tanpa center -> dilewati.
          {
            'type': 'relation',
            'id': 5,
            'tags': {'seamark:type': 'light_major'},
          },
        ],
      });
      final seamarks = SeamarkService.parseOverpassResponse(body);
      expect(seamarks.length, 2);
      expect(seamarks[0].id, 'node/1');
      expect(seamarks[0].lateralSide, LateralSide.port);
      expect(seamarks[1].id, 'way/2');
      expect(seamarks[1].name, 'Pisang');
    });

    test('cap 200 marker: 250 elemen -> 200, yang terdekat dari '
        'tengah bbox dipertahankan', () {
      final elements = List.generate(250, (i) {
        // Jarak dari tengah (0,0) membesar seiring i.
        final offset = 0.001 * (i + 1);
        return {
          'type': 'node',
          'id': i,
          'lat': offset,
          'lon': 0.0,
          'tags': {'seamark:type': 'light_minor'},
        };
      });
      final body = jsonEncode({'elements': elements});
      final seamarks = SeamarkService.parseOverpassResponse(
        body,
        centerLat: 0,
        centerLon: 0,
      );
      expect(seamarks.length, SeamarkService.maxMarkers);
      expect(seamarks.length, 200);
      // Terdekat dulu: id 0 (offset terkecil) pertama, id 249 dibuang.
      expect(seamarks.first.id, 'node/0');
      expect(seamarks.last.id, 'node/199');
      expect(seamarks.any((s) => s.id == 'node/249'), isFalse);
    });

    test('JSON bukan Overpass -> FormatException (endpoint gagal, '
        'BUKAN hasil kosong)', () {
      expect(
        () => SeamarkService.parseOverpassResponse('bukan json'),
        throwsFormatException,
      );
      expect(
        () => SeamarkService.parseOverpassResponse('{"foo": 1}'),
        throwsFormatException,
      );
      // JSON valid tapi 0 elemen = hasil kosong yang sah.
      expect(
        SeamarkService.parseOverpassResponse('{"elements": []}'),
        isEmpty,
      );
    });
  });

  group('Seamark JSON cache round-trip', () {
    test('toJson -> fromJson mempertahankan semua field', () {
      final original = Seamark.fromOsmTags(
        id: 'node/test-roundtrip',
        latitude: -6.10,
        longitude: 106.88,
        tags: const {
          'seamark:type': 'beacon_lateral',
          'seamark:name': 'Pisang',
          'seamark:beacon_lateral:category': 'port',
          'seamark:beacon_lateral:colour': 'green',
          'seamark:beacon_lateral:system': 'iala-b',
          'seamark:light:character': 'Fl',
          'seamark:light:colour': 'green',
          'seamark:light:period': '5',
          'seamark:light:height': '12',
          'seamark:light:range': '10',
          'seamark:light:reference': 'K 1168',
        },
      )!;
      final restored = Seamark.fromJson(
        jsonDecode(jsonEncode(original.toJson()))
            as Map<String, dynamic>,
      )!;
      expect(restored.id, original.id);
      expect(restored.latitude, original.latitude);
      expect(restored.longitude, original.longitude);
      expect(restored.type, original.type);
      expect(restored.name, 'Pisang');
      expect(restored.kind, SeamarkKind.lateral);
      expect(restored.lateralSide, LateralSide.port);
      expect(restored.ialaSystem, 'iala-b');
      expect(restored.lightSummary, original.lightSummary);
      expect(restored.lightReference, 'K 1168');
    });

    test('fromJson dengan JSON rusak -> null', () {
      expect(Seamark.fromJson({}), isNull);
      expect(Seamark.fromJson({'id': 'node/1'}), isNull);
    });
  });

  group('Seamark.coverageNote', () {
    test('teks kejujuran cakupan persis seperti butir 20', () {
      expect(
        Seamark.coverageNote,
        'Data OpenStreetMap — cakupan di Indonesia belum merata; rambu '
        'yang tidak ada datanya tidak tampil. Data sebagian dari impor '
        'NGA Pub. 112 (2009/2023), bisa basi — selalu cek BPI '
        'Pushidrosal dan ENC resmi.',
      );
    });
  });
}
