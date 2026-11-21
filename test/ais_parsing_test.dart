import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/domain/models/vessel.dart';

/// Fixture sesuai bentuk envelope AISStream (MessageType, MetaData,
/// Message: {PositionReport | ShipStaticData}, field PascalCase).
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

  const staticEnvelope = r'''{
    "MessageType": "ShipStaticData",
    "MetaData": {
      "MMSI": 525001234,
      "MMSI_String": "525001234",
      "ShipName": "KM NUSANTARA",
      "time_utc": "2026-11-21T06:01:00.000Z"
    },
    "Message": {
      "ShipStaticData": {
        "Callsign": "YB1234",
        "Destination": "SURABAYA",
        "Eta": "11-23 08:00",
        "ImoNumber": 9123456,
        "Name": "KM NUSANTARA",
        "Type": 70,
        "UserID": 525001234,
        "Valid": true
      }
    }
  }''';

  const notAvailableEnvelope = r'''{
    "MessageType": "PositionReport",
    "MetaData": {
      "MMSI": 525009999,
      "ShipName": "KM TANPA DATA",
      "time_utc": "2026-11-21T06:00:00.000Z"
    },
    "Message": {
      "PositionReport": {
        "Cog": 360.0,
        "Latitude": 91.0,
        "Longitude": 181.0,
        "Sog": 102.3,
        "TrueHeading": 511,
        "UserID": 525009999,
        "Valid": true
      }
    }
  }''';

  test('PositionReport -> posisi + kecepatan + haluan', () {
    final envelope =
        jsonDecode(positionEnvelope) as Map<String, dynamic>;
    final result = AisMessageParser.parse(envelope);
    expect(result, isNotNull);
    expect(result!.mmsi, 525001234);
    final vessel = result.updated;
    expect(vessel.name, 'KM NUSANTARA');
    expect(vessel.latitude, -3.5);
    expect(vessel.longitude, 114.7);
    expect(vessel.speedKnots, 12.3);
    expect(vessel.courseDeg, 95.5);
    expect(vessel.headingDeg, 96);
    expect(vessel.hasPosition, isTrue);
    expect(vessel.displayName, 'KM NUSANTARA');
  });

  test('ShipStaticData merge ke kapal yang sudah ada', () {
    final pos = AisMessageParser.parse(
      jsonDecode(positionEnvelope) as Map<String, dynamic>,
    )!;
    final result = AisMessageParser.parse(
      jsonDecode(staticEnvelope) as Map<String, dynamic>,
      existing: pos.updated,
    );
    expect(result, isNotNull);
    final vessel = result!.updated;
    // Posisi dari laporan sebelumnya tetap ada.
    expect(vessel.latitude, -3.5);
    expect(vessel.speedKnots, 12.3);
    // Data statis baru ditambahkan.
    expect(vessel.destination, 'SURABAYA');
    expect(vessel.eta, '11-23 08:00');
    expect(vessel.shipType, 70);
  });

  test('nilai "tidak tersedia" AIS -> null (bukan 91/181/102.3)', () {
    final envelope =
        jsonDecode(notAvailableEnvelope) as Map<String, dynamic>;
    final result = AisMessageParser.parse(envelope);
    expect(result, isNotNull);
    final vessel = result!.updated;
    expect(vessel.latitude, isNull);
    expect(vessel.longitude, isNull);
    expect(vessel.speedKnots, isNull);
    expect(vessel.courseDeg, isNull);
    expect(vessel.headingDeg, isNull);
    expect(vessel.hasPosition, isFalse);
  });

  test('tanpa MMSI -> null', () {
    final result = AisMessageParser.parse({'MessageType': 'PositionReport'});
    expect(result, isNull);
  });

  test('tanpa nama -> displayName memakai MMSI', () {
    final envelope = {
      'MetaData': {'MMSI': 123456789},
      'Message': {
        'PositionReport': {
          'Latitude': 1.0,
          'Longitude': 2.0,
          'Sog': 5.0,
          'Cog': 180.0,
          'TrueHeading': 180,
        },
      },
    };
    final result = AisMessageParser.parse(envelope);
    expect(result, isNotNull);
    expect(result!.updated.displayName, 'MMSI 123456789');
  });

  test('label status koneksi', () {
    expect(AisConnectionState.connected.label, 'Terhubung');
    expect(
      AisConnectionState.notConfigured.label,
      'Kunci AIS belum diisi',
    );
  });
}
