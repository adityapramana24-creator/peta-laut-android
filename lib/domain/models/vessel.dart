/// Model kapal AIS (AISStream WebSocket).
/// Envelope: MessageType, MetaData (MMSI, ShipName, time_utc),
/// Message: {PositionReport | ShipStaticData} (field PascalCase).
/// Nilai "tidak tersedia" AIS: Lat 91, Lon 181, Sog 102.3,
/// Cog 360, TrueHeading 511 -> null.
class Vessel {
  const Vessel({
    required this.mmsi,
    this.name,
    this.latitude,
    this.longitude,
    this.speedKnots,
    this.courseDeg,
    this.headingDeg,
    this.destination,
    this.eta,
    this.lastSeen,
    this.shipType,
  });

  final int mmsi;
  final String? name;
  final double? latitude;
  final double? longitude;
  final double? speedKnots;
  final double? courseDeg;
  final double? headingDeg;
  final String? destination;
  final String? eta;
  final DateTime? lastSeen;
  final int? shipType;

  bool get hasPosition => latitude != null && longitude != null;

  String get displayName {
    final n = name?.trim();
    if (n == null || n.isEmpty) return 'MMSI $mmsi';
    return n;
  }

  Vessel copyWith({
    String? name,
    double? latitude,
    double? longitude,
    double? speedKnots,
    double? courseDeg,
    double? headingDeg,
    String? destination,
    String? eta,
    DateTime? lastSeen,
    int? shipType,
  }) {
    return Vessel(
      mmsi: mmsi,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      speedKnots: speedKnots ?? this.speedKnots,
      courseDeg: courseDeg ?? this.courseDeg,
      headingDeg: headingDeg ?? this.headingDeg,
      destination: destination ?? this.destination,
      eta: eta ?? this.eta,
      lastSeen: lastSeen ?? this.lastSeen,
      shipType: shipType ?? this.shipType,
    );
  }
}

/// Hasil parse satu pesan AISStream.
/// `updated` = kapal setelah merge; `mmsi` selalu terisi bila pesan
/// AIS dikenali (meski tanpa posisi, mis. static data murni).
class AisParseResult {
  const AisParseResult({required this.mmsi, required this.updated});

  final int mmsi;
  final Vessel updated;
}

/// Parser pesan AISStream — pure function, ditutup unit test.
class AisMessageParser {
  AisMessageParser._();

  static double? _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Parse envelope AISStream ke Vessel baru/di-merge.
  /// `existing` = kapal yang sudah dikenal (merge field baru ke sana).
  /// Mengembalikan null bila pesan bukan AIS / MMSI tidak valid.
  static AisParseResult? parse(
    Map<String, dynamic> envelope, {
    Vessel? existing,
  }) {
    final meta = envelope['MetaData'];
    int? mmsi;
    String? shipName;
    DateTime? timeUtc;
    if (meta is Map<String, dynamic>) {
      mmsi = _parseInt(meta['MMSI']);
      final rawName = meta['ShipName'];
      if (rawName is String && rawName.trim().isNotEmpty) {
        shipName = rawName.trim();
      }
      final rawTime = meta['time_utc'];
      if (rawTime is String) timeUtc = DateTime.tryParse(rawTime);
    }
    if (mmsi == null) return null;

    final message = envelope['Message'];
    if (message is! Map<String, dynamic>) return null;

    Vessel vessel = existing ?? Vessel(mmsi: mmsi, lastSeen: timeUtc);
    if (shipName != null) vessel = vessel.copyWith(name: shipName);
    if (timeUtc != null) vessel = vessel.copyWith(lastSeen: timeUtc);

    final position = message['PositionReport'];
    if (position is Map<String, dynamic>) {
      final lat = _parseDouble(position['Latitude']);
      final lon = _parseDouble(position['Longitude']);
      final sog = _parseDouble(position['Sog']);
      final cog = _parseDouble(position['Cog']);
      final heading = _parseDouble(position['TrueHeading']);
      vessel = vessel.copyWith(
        latitude: (lat != null && lat != 91.0) ? lat : vessel.latitude,
        longitude: (lon != null && lon != 181.0) ? lon : vessel.longitude,
        speedKnots: (sog != null && sog != 102.3) ? sog : vessel.speedKnots,
        courseDeg: (cog != null && cog != 360.0) ? cog : vessel.courseDeg,
        headingDeg:
            (heading != null && heading != 511.0) ? heading : vessel.headingDeg,
      );
    }

    final staticData = message['ShipStaticData'];
    if (staticData is Map<String, dynamic>) {
      final name = staticData['Name'];
      final destination = staticData['Destination'];
      final eta = staticData['Eta'];
      final type = _parseInt(staticData['Type']);
      vessel = vessel.copyWith(
        name: (name is String && name.trim().isNotEmpty)
            ? name.trim()
            : vessel.name,
        destination: (destination is String && destination.trim().isNotEmpty)
            ? destination.trim()
            : vessel.destination,
        eta: (eta is String && eta.trim().isNotEmpty)
            ? eta.trim()
            : vessel.eta,
        shipType: type ?? vessel.shipType,
      );
    }

    return AisParseResult(mmsi: mmsi, updated: vessel);
  }
}

/// Status koneksi AISStream untuk chip status di panel AIS.
enum AisConnectionState {
  notConfigured,
  connecting,
  connected,
  reconnecting,
  error,
}

extension AisConnectionStateLabel on AisConnectionState {
  String get label {
    switch (this) {
      case AisConnectionState.notConfigured:
        return 'Kunci AIS belum diisi';
      case AisConnectionState.connecting:
        return 'Menghubungkan…';
      case AisConnectionState.connected:
        return 'Terhubung';
      case AisConnectionState.reconnecting:
        return 'Menyambung ulang…';
      case AisConnectionState.error:
        return 'Koneksi gagal';
    }
  }
}
