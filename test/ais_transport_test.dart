import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/data/services/ais_service.dart';
import 'package:peta_laut/domain/models/vessel.dart';

/// Test lapisan TRANSPORT AISStream — BUKAN hanya parser.
///
/// Bug v1.1: server mengirim frame BINER (List<int> berisi JSON UTF-8
/// — dokumen resmi aisstream.io/documentation), tapi listener hanya
/// menerima `data is String`, sehingga SEMUA pesan dibuang diam-diam
/// dan peta kapal kosong meski kunci valid. Test parser yang lama
/// lolos karena mengumpan String langsung ke parser — test ini
/// mengumpan frame biner ke decoder, seperti yang tiba dari socket.
void main() {
  const positionEnvelope = r'''{
    "MessageType": "PositionReport",
    "MetaData": {
      "MMSI": 525001234,
      "MMSI_String": "525001234",
      "ShipName": "KM NUSANTARA",
      "latitude": -3.5,
      "longitude": 114.7,
      "time_utc": "2026-11-21T06:00:00.000Z"
    },
    "Message": {
      "PositionReport": {
        "Cog": 95.5,
        "Latitude": -3.5,
        "Longitude": 114.7,
        "NavigationalStatus": 0,
        "RateOfTurn": 0,
        "Sog": 12.3,
        "TrueHeading": 96,
        "UserID": 525001234,
        "Valid": true
      }
    }
  }''';

  const confirmationEnvelope = r'''{
    "MessageType": "SubscriptionConfirmation",
    "Message": {"CompressionEnabled": false}
  }''';

  test('frame teks (String) ter-decode', () {
    final decoded = AisService.decodeFrame(positionEnvelope);
    expect(decoded, isNotNull);
    expect(decoded!['MessageType'], 'PositionReport');
  });

  test('frame biner (List<int>) ter-decode — REGRESI v1.1', () {
    // Persis bentuk yang dikirim server: frame biner berisi JSON.
    final bytes = utf8.encode(positionEnvelope);
    final decoded = AisService.decodeFrame(bytes);
    expect(decoded, isNotNull);
    expect(decoded!['MessageType'], 'PositionReport');
    final meta = decoded['MetaData'] as Map<String, dynamic>;
    expect(meta['MMSI'], 525001234);
  });

  test('frame biner -> parse -> kapal (ujung ke ujung)', () {
    final decoded =
        AisService.decodeFrame(utf8.encode(positionEnvelope))!;
    final result = AisMessageParser.parse(decoded);
    expect(result, isNotNull);
    final vessel = result!.updated;
    expect(vessel.latitude, -3.5);
    expect(vessel.longitude, 114.7);
    expect(vessel.speedKnots, 12.3);
    expect(vessel.courseDeg, 95.5);
    expect(vessel.headingDeg, 96);
    expect(vessel.hasPosition, isTrue);
  });

  test('frame biner konfirmasi langganan ter-decode + dikenali', () {
    final decoded =
        AisService.decodeFrame(utf8.encode(confirmationEnvelope));
    expect(decoded, isNotNull);
    expect(AisService.isSubscriptionConfirmation(decoded!), isTrue);
    // Konfirmasi bukan pesan AIS (tanpa MetaData.MMSI).
    expect(AisService.isAisMessage(decoded), isFalse);
  });

  test('pesan AIS dikenali dari MetaData.MMSI', () {
    final decoded = AisService.decodeFrame(positionEnvelope)!;
    expect(AisService.isAisMessage(decoded), isTrue);
    expect(AisService.isSubscriptionConfirmation(decoded), isFalse);
  });

  test('byte bukan JSON / tipe lain -> null (tidak crash)', () {
    expect(AisService.decodeFrame(utf8.encode('bukan json{{')), isNull);
    // Byte UTF-8 tidak valid.
    expect(AisService.decodeFrame([0, 1, 2, 255]), isNull);
    expect(AisService.decodeFrame(12345), isNull);
    expect(AisService.decodeFrame(null), isNull);
    // JSON valid tapi bukan objek.
    expect(AisService.decodeFrame('[1,2,3]'), isNull);
  });
}
