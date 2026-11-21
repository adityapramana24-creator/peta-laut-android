import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/data/services/nmea_ais_parser.dart';

/// Parser NMEA 0183 AIVDM/AIVDO — kalimat nyata + rakitan tangan.
///
/// Nilai harapan DIVERIFIKASI independen sebelum test ini ditulis:
/// implementasi referensi Python yang mencerminkan persis algoritma
/// parser lolos 205 cek pada 21 Nov 2026 (12 kalimat terbitan vs
/// pustaka pyais 3.3.1, 6 round-trip encode pyais, 9 kasus rusak,
/// 7 rakitan tangan dari tabel bit gpsd). Setiap vektor di bawah
/// mencantumkan sumbernya.
void main() {
  /// Feed satu kalimat ke parser baru; gagal bila hasilnya null.
  ShipAisParseResult feedOne(String line) {
    final result = NmeaAisParser().feed(line);
    expect(result, isNotNull, reason: 'gagal decode: $line');
    return result!;
  }

  /// Feed beberapa kalimat (multi-fragmen) ke satu parser.
  ShipAisParseResult feedMany(List<String> lines) {
    final parser = NmeaAisParser();
    ShipAisParseResult? result;
    for (final line in lines) {
      result = parser.feed(line) ?? result;
    }
    expect(result, isNotNull, reason: 'gagal decode: $lines');
    return result!;
  }

  void expectPosition(
    ShipAisParseResult result, {
    required int mmsi,
    required double? lat,
    required double? lon,
    required double? sog,
    required double? cog,
    required double? heading,
  }) {
    final v = result.updated;
    expect(result.mmsi, mmsi);
    expect(v.mmsi, mmsi);
    if (lat == null) {
      expect(v.latitude, isNull);
    } else {
      expect(v.latitude, closeTo(lat, 0.0001));
    }
    if (lon == null) {
      expect(v.longitude, isNull);
    } else {
      expect(v.longitude, closeTo(lon, 0.0001));
    }
    if (sog == null) {
      expect(v.speedKnots, isNull);
    } else {
      expect(v.speedKnots, closeTo(sog, 0.0001));
    }
    if (cog == null) {
      expect(v.courseDeg, isNull);
    } else {
      expect(v.courseDeg, closeTo(cog, 0.0001));
    }
    if (heading == null) {
      expect(v.headingDeg, isNull);
    } else {
      expect(v.headingDeg, closeTo(heading, 0.0001));
    }
  }

  group('kalimat terbitan (vs pyais 3.3.1)', () {
    test('gpsd tipe 1', () {
      // Dokumen GPSD AIVDM (catb.org/gpsd/AIVDM.html).
      final r = feedOne(
        '!AIVDM,1,1,,B,177KQJ5000G?tO`K>RA1wUbN0TKH,0*5C',
      );
      expect(r.messageType, 1);
      expect(r.isOwnShip, isFalse);
      expectPosition(
        r,
        mmsi: 477553000,
        lat: 47.58283333333333,
        lon: -122.34583333333333,
        sog: 0.0,
        cog: 51.0,
        heading: 181.0,
      );
      expect(r.updated.navStatus, 5);
      expect(r.updated.rateOfTurn, 0);
    });

    test('gpsd tipe 5 multi-fragmen', () {
      // Dokumen GPSD AIVDM — 2 fragmen, seq 3, kanal B.
      final r = feedMany([
        '!AIVDM,2,1,3,B,55P5TL01VIaAL@7WKO@mBplU@<PDhh000000001S;AJ::4A80?4i@E53,0*3E',
        '!AIVDM,2,2,3,B,1@0000000000000,2*55',
      ]);
      expect(r.messageType, 5);
      expect(r.mmsi, 369190000);
      expect(r.updated.name, 'MT.MITCHELL');
      expect(r.updated.destination, 'SEATTLE');
      expect(r.updated.eta, '01-02 08:00');
      expect(r.updated.shipType, 99);
      expect(r.updated.imoNumber, 6710932);
      expect(r.updated.callsign, 'WDA9674');
      expect(r.updated.lengthM, 180.0);
      expect(r.updated.beamM, 20.0);
      // Data statis tidak membawa posisi.
      expect(r.updated.latitude, isNull);
      expect(r.updated.longitude, isNull);
    });

    test('pyais README tipe 1 (checksum dikoreksi *0E)', () {
      // README pyais — kalimat aslinya *4E (checksum SALAH, lihat
      // test negatif di bawah); *0E adalah XOR yang benar.
      // Payload hanya 162 bit (bukan 168) — ekor radio-status
      // hilang; parser tetap decode karena semua field yang
      // dipakai masih lengkap.
      final r = feedOne(
        '!AIVDM,1,1,,B,15MwkT1P37G?fl0EJbR0OwT0@MS,0*0E',
      );
      expectPosition(
        r,
        mmsi: 366998416,
        lat: 37.42828,
        lon: -122.392533,
        sog: 19.9,
        cog: 12.7,
        heading: 498.0,
      );
    });

    test('pyais README tipe 1 kedua (heading 511 -> null)', () {
      // README pyais — heading mentah 511 (tidak tersedia).
      final r = feedOne(
        '!AIVDM,1,1,,B,15NG6V0P01G?cFhE`R2IU?wn28R>,0*05',
      );
      expectPosition(
        r,
        mmsi: 367380120,
        lat: 37.80694833333333,
        lon: -122.40433333333333,
        sog: 0.1,
        cog: 245.2,
        heading: null,
      );
      expect(r.updated.navStatus, 0);
      expect(r.updated.rateOfTurn, -128);
    });

    test('marine_ais README tipe 18', () {
      // README pub.dev marine_ais — nilai harapan terbit di sana.
      final r = feedOne(
        '!AIVDM,1,1,,A,B52MJh00A6Kg@85wK40N4FhP0000,0*26',
      );
      expect(r.messageType, 18);
      expectPosition(
        r,
        mmsi: 338123456,
        lat: 41.88,
        lon: -87.61,
        sog: 6.8,
        cog: 48.1,
        heading: 45.0,
      );
    });

    test('AisParser tipe 1', () {
      // Test suite AisParser (github.com/morphic-ai/AisParser).
      final r = feedOne(
        '!AIVDM,1,1,,B,14`c;d002grD>PH50hr7RVE000SG,0*74',
      );
      expectPosition(
        r,
        mmsi: 311086000,
        lat: 8.759,
        lon: -79.4675,
        sog: 17.5,
        cog: 193.0,
        heading: 202.0,
      );
    });

    test('AisParser tipe 3', () {
      // Test suite AisParser.
      final r = feedOne(
        '!AIVDM,1,1,,B,34hwN60Oh3rCwib56`qJtbL<0000,0*12',
      );
      expect(r.messageType, 3);
      expectPosition(
        r,
        mmsi: 319807000,
        lat: 8.919421666666667,
        lon: -79.51777833333334,
        sog: 0.3,
        cog: 280.2,
        heading: 334.0,
      );
    });

    test('AisParser AIVDO tipe 18 (kapal sendiri)', () {
      // Test suite AisParser — AIVDO = own-ship.
      final r = feedOne(
        '!AIVDO,1,1,,,B39i>1000nTu;gQAlBj:wwS5kP06,0*5D',
      );
      expect(r.messageType, 18);
      expect(r.isOwnShip, isTrue);
      expectPosition(
        r,
        mmsi: 211570180,
        lat: 8.936606666666666,
        lon: -79.55546833333334,
        sog: 0.3,
        cog: 222.3,
        heading: null,
      );
    });

    test('dokumen GPSD: field trailing USCG ditoleransi', () {
      // Dokumen GPSD AIVDM — field `,s...,d...,T...,r...` setelah
      // checksum (format stasiun pantai USCG).
      final r = feedOne(
        '!AIVDM,1,1,,B,15Cjtd0Oj;Jp7ilG7=UkKBoB0<06,0*63,'
        's1234,d-119,T12.34567123,r003669958,1085889680',
      );
      expectPosition(
        r,
        mmsi: 356302000,
        lat: 40.392358333333334,
        lon: -71.62614333333333,
        sog: 13.9,
        cog: 87.7,
        heading: 91.0,
      );
      expect(r.updated.rateOfTurn, 127);
    });

    test('pyais tipe 5 multi-fragmen (tanpa tujuan/ETA)', () {
      // Test suite pyais — tujuan + ETA kosong -> null.
      final r = feedMany([
        '!AIVDM,2,1,4,A,55O0W7`00001L@gCWGA2uItLth@DqtL5@F22220j1h742t0Ht0000000,0*08',
        '!AIVDM,2,2,4,A,000000000000000,2*20',
      ]);
      expect(r.mmsi, 368060190);
      expect(r.updated.name, 'P/V_GOLDEN_GATE');
      expect(r.updated.shipType, 50);
      expect(r.updated.destination, isNull);
      expect(r.updated.eta, isNull);
    });

    test('tag block NMEA 4.10 + stempel waktu c:', () {
      // Dokumen GPSD AIVDM — tag block `\s:...,c:...*\!AIVDM...`.
      // c:1671620143 = stempel waktu Unix -> lastSeen.
      final r = feedOne(
        r'\s:2573135,c:1671620143*0B\!AIVDM,1,1,,A,16:=?;0P00`SstvFnFbeGH6L088h,0*44',
      );
      expectPosition(
        r,
        mmsi: 413355820,
        lat: 39.93201666666667,
        lon: 119.69861166666666,
        sog: 0.0,
        cog: 342.1,
        heading: 259.0,
      );
      expect(
        r.updated.lastSeen?.millisecondsSinceEpoch,
        1671620143000,
      );
    });

    test('pyais stream tipe 1', () {
      // Test suite pyais (test_decode.py).
      final r = feedOne(
        '!AIVDM,1,1,,A,13HOI:0P0000VOHLCnHQKwvL05Ip,0*23',
      );
      expectPosition(
        r,
        mmsi: 227006760,
        lat: 49.47557666666667,
        lon: 0.13138,
        sog: 0.0,
        cog: 36.7,
        heading: null,
      );
    });
  });

  group('round-trip encode pyais -> decode parser', () {
    test('tipe 2', () {
      final r = feedOne(
        '!AIVDO,1,1,,A,17lcR4gP1s7Wem1tOhB3fk01P000,0*29',
      );
      expect(r.messageType, 2);
      expectPosition(
        r,
        mmsi: 525001234,
        lat: -6.1234,
        lon: 106.5432,
        sog: 12.3,
        cog: 95.5,
        heading: 96.0,
      );
    });

    test('tipe 18', () {
      final r = feedOne(
        '!AIVDO,1,1,,A,B5MwqD00=mkwNT5J5W295f000000,0*4F',
      );
      expectPosition(
        r,
        mmsi: 366999888,
        lat: 37.802,
        lon: -122.341,
        sog: 5.5,
        cog: 219.3,
        heading: 220.0,
      );
    });

    test('tipe 19 (posisi + nama + tipe)', () {
      final r = feedOne(
        '!AIVDO,1,1,,A,C69?UCP0D1o0Ap0;CEhL8F00FK0`:Va0V:J4BH2L0000?0000000,0*64',
      );
      expect(r.messageType, 19);
      expectPosition(
        r,
        mmsi: 412345678,
        lat: 1.2345,
        lon: 103.9876,
        sog: 8.0,
        cog: 45.0,
        heading: 44.0,
      );
      expect(r.updated.name, 'KM TEST SEMBILAN');
      expect(r.updated.shipType, 30);
    });

    test('tipe 24 Bagian A', () {
      final r = feedOne(
        '!AIVDO,1,1,,A,H7`W6CPdn0AD60Dm05B040000000,0*2A',
      );
      expect(r.messageType, 24);
      expect(r.mmsi, 512345678);
      expect(r.updated.name, 'KM DUA EMPAT A');
    });

    test('tipe 5 multi-fragmen (dengan ETA)', () {
      final r = feedMany([
        '!AIVDO,2,1,0,A,57ld4Ch2;=`1T;WWWT0dn0qE<4q@5860`5T40016000002s`0=lmDP@PF@@0,0*5A',
        '!AIVDO,2,2,0,A,00000000000,2*26',
      ]);
      expect(r.mmsi, 525009999);
      expect(r.updated.name, 'KM NUSANTARA JAYA');
      expect(r.updated.destination, 'SURABAYA');
      expect(r.updated.shipType, 70);
      expect(r.updated.eta, '11-23 08:00');
    });
  });

  group('rakitan tangan dari tabel bit gpsd', () {
    test('tipe 24 Bagian B (ship_type + callsign)', () {
      // pyais 3.3.1 TIDAK bisa meng-encode tipe 24 — kalimat ini
      // dirakit bit-per-bit dari tabel gpsd dan diverifikasi
      // decode-nya oleh implementasi referensi Python.
      final r = feedOne(
        '!AIVDM,1,1,,A,H7`W6CTTAE5430qI2ijkl0000000,0*23',
      );
      expect(r.messageType, 24);
      expect(r.mmsi, 512345678);
      expect(r.updated.shipType, 36);
      expect(r.updated.callsign, 'YB1234');
    });

    test('tipe 24 Bagian A 160 bit (tanpa spare akhir)', () {
      // Varian 160 bit umum di lapangan (gpsd).
      final r = feedOne(
        '!AIVDM,1,1,,A,H7`W6Chdn1<E85AE>0Dp4n11DiD,2*33',
      );
      expect(r.mmsi, 512345679);
      expect(r.updated.name, 'KM SERATUS ENAM PULU');
    });

    test('tipe 1 semua sentinel N/A -> null', () {
      // SOG 1023, COG 3600, heading 511, lat 91, lon 181.
      final r = feedOne(
        '!AIVDM,1,1,,A,1>qTGR@0?w<tSF0l4Q@>4?v00000,0*76',
      );
      expect(r.mmsi, 999888777);
      expect(r.updated.latitude, isNull);
      expect(r.updated.longitude, isNull);
      expect(r.updated.speedKnots, isNull);
      expect(r.updated.courseDeg, isNull);
      expect(r.updated.headingDeg, isNull);
    });

    test('SOG 1022 -> 102.2 knot (bukan null)', () {
      final r = feedOne(
        '!AIVDM,1,1,,A,11b4N?@0?v000000000000000000,0*38',
      );
      expect(r.updated.speedKnots, closeTo(102.2, 0.0001));
    });

    test('tipe 5 terpotong 420 bit (umum di lapangan)', () {
      // gpsd: ~0,3% pesan di AISHub panjangnya salah; tipe 5
      // 420/422 bit umum — nama/tipe/ETA/tujuan tetap terbaca.
      final r = feedMany([
        '!AIVDM,2,1,7,A,57ld4Ch2;=`1T;WWWT0dn0qE<4q@5860`5T40016<Pj::2s`004mDP@PF@@0,0*3C',
        '!AIVDM,2,2,7,A,0000000000,0*11',
      ]);
      expect(r.mmsi, 525009999);
      expect(r.updated.name, 'KM NUSANTARA JAYA');
      expect(r.updated.destination, 'SURABAYA');
      expect(r.updated.eta, '11-23 08:00');
      expect(r.updated.shipType, 70);
      expect(r.updated.imoNumber, 9123456);
      expect(r.updated.callsign, 'YB9999');
      expect(r.updated.lengthM, 150.0);
      expect(r.updated.beamM, 20.0);
    });

    test('tipe 5 terpotong 264 bit (di tengah dimensi): aman', () {
      // Nama/tipe tetap terbaca; dimensi + ETA null (bukan crash,
      // bukan nol palsu).
      final r = feedOne(
        '!AIVDM,1,1,,A,57ld4Ch2;=`1T;WWWT0dn0qE<4q@5860`5T40016<Pj:,0*38',
      );
      expect(r.mmsi, 525009999);
      expect(r.updated.name, 'KM NUSANTARA JAYA');
      expect(r.updated.shipType, 70);
      expect(r.updated.imoNumber, 9123456);
      expect(r.updated.callsign, 'YB9999');
      expect(r.updated.lengthM, isNull);
      expect(r.updated.beamM, isNull);
      expect(r.updated.eta, isNull);
      expect(r.updated.destination, isNull);
    });

    test('tipe 1 terpotong parah (100 bit) ditolak', () {
      expect(
        NmeaAisParser().feed(
          '!AIVDM,1,1,,A,11b4N?@0000000000,0*41',
        ),
        isNull,
      );
    });
  });

  group('kasus rusak / tepi — diabaikan aman, bukan crash', () {
    test('checksum salah ditolak', () {
      expect(
        NmeaAisParser().feed(
          '!AIVDM,1,1,,B,177KQJ5000G?tO`K>RA1wUbN0TKH,0*5D',
        ),
        isNull,
      );
    });

    test('checksum README pyais yang salah (*4E) ditolak', () {
      // XOR yang benar untuk kalimat ini adalah 0E, bukan 4E.
      expect(
        NmeaAisParser().feed(
          '!AIVDM,1,1,,B,15MwkT1P37G?fl0EJbR0OwT0@MS,0*4E',
        ),
        isNull,
      );
    });

    test('tanpa checksum ditolak', () {
      expect(
        NmeaAisParser().feed(
          '!AIVDM,1,1,,B,177KQJ5000G?tO`K>RA1wUbN0TKH,0',
        ),
        isNull,
      );
    });

    test('bukan AIS (GPGGA) diabaikan', () {
      expect(
        NmeaAisParser().feed(
          '\$GPGGA,123519,4807.038,N,01131.000,E,1,08,0.9,545.4,M,46.9,M,,*47',
        ),
        isNull,
      );
    });

    test('baris kosong dan sampah diabaikan', () {
      final parser = NmeaAisParser();
      expect(parser.feed(''), isNull);
      expect(parser.feed('hello world'), isNull);
      expect(parser.feed('!AIVDM'), isNull);
    });

    test('fragmen 2 tanpa fragmen 1 diabaikan', () {
      expect(
        NmeaAisParser().feed(
          '!AIVDM,2,2,3,B,1@0000000000000,2*55',
        ),
        isNull,
      );
    });

    test('fragmen seq id tidak cocok dibuang; yang benar melengkapi', () {
      final parser = NmeaAisParser();
      expect(
        parser.feed(
          '!AIVDM,2,1,3,B,55P5TL01VIaAL@7WKO@mBplU@<PDhh000000001S;AJ::4A80?4i@E53,0*3E',
        ),
        isNull,
      );
      // Fragmen 2 dengan seq id 9 (bukan 3) — dibuang.
      expect(
        parser.feed('!AIVDM,2,2,9,B,1@0000000000000,2*55'),
        isNull,
      );
      // Fragmen 2 yang benar melengkapi rakitan seq 3.
      final result = parser.feed(
        '!AIVDM,2,2,3,B,1@0000000000000,2*55',
      );
      expect(result, isNotNull);
      expect(result!.mmsi, 369190000);
    });

    test('tipe 4 (tidak didukung) -> null aman', () {
      // Di-encode pyais: stasiun basis tipe 4.
      expect(
        NmeaAisParser().feed(
          '!AIVDO,1,1,,A,47lcM@As8@P007U>d1tTAP000000,0*07',
        ),
        isNull,
      );
    });

    test('MMSI 0 ditolak', () {
      expect(
        NmeaAisParser().feed(
          '!AIVDM,1,1,,A,100000001T000000000000000000,0*42',
        ),
        isNull,
      );
    });

    test('decodeLine: satu kalimat OK, multi-fragmen null', () {
      expect(
        NmeaAisParser.decodeLine(
          '!AIVDM,1,1,,B,177KQJ5000G?tO`K>RA1wUbN0TKH,0*5C',
        ),
        isNotNull,
      );
      expect(
        NmeaAisParser.decodeLine(
          '!AIVDM,2,1,3,B,55P5TL01VIaAL@7WKO@mBplU@<PDhh000000001S;AJ::4A80?4i@E53,0*3E',
        ),
        isNull,
      );
    });
  });
}
