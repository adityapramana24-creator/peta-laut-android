/// Model kapal AIS (AISStream WebSocket).
/// Envelope: MessageType, MetaData (MMSI, ShipName, time_utc,
/// Latitude/Longitude terakhir yang diketahui), Message:
/// {PositionReport | StandardClassBPositionReport |
/// ExtendedClassBPositionReport | ShipStaticData | StaticDataReport}
/// (field PascalCase — aisstream.io/documentation, dicek 2026-11-21).
/// Nilai "tidak tersedia" AIS: Lat 91, Lon 181, Sog 102.3,
/// Cog 360, TrueHeading 511, ROT -128 -> null.
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
    this.navStatus,
    this.rateOfTurn,
    this.lengthM,
    this.beamM,
    this.callsign,
    this.imoNumber,
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

  /// Status navigasi AIS (PositionReport.NavigationalStatus, 0–15).
  final int? navStatus;

  /// Indikator laju belok mentah (PositionReport.RateOfTurn);
  /// -128 = tidak ada info, 0 = tidak berbelok.
  final int? rateOfTurn;

  /// Panjang/lebar kapal (meter) dari Dimension A+B / C+D
  /// ShipStaticData; null bila data statis belum diterima.
  final double? lengthM;
  final double? beamM;
  final String? callsign;
  final int? imoNumber;

  bool get hasPosition => latitude != null && longitude != null;
  bool get hasDimensions => lengthM != null && beamM != null;

  /// Berbelok (indikator ROT, untuk simbol ECDIS).
  bool get isTurning =>
      rateOfTurn != null && rateOfTurn != 0 && rateOfTurn != -128;

  String get displayName {
    final n = name?.trim();
    if (n == null || n.isEmpty) return 'MMSI $mmsi';
    return n;
  }

  /// Label status navigasi (ITU-R M.1371) dalam Bahasa Indonesia.
  String? get navStatusLabel {
    switch (navStatus) {
      case null:
        return null;
      case 0:
        return 'Berlayar';
      case 1:
        return 'Jangkar';
      case 2:
        return 'Tidak terkendali';
      case 3:
        return 'Manuver terbatas';
      case 4:
        return 'Dibatasi draf';
      case 5:
        return 'Tambat';
      case 6:
        return 'Kandas';
      case 7:
        return 'Menangkap ikan';
      case 8:
        return 'Berlayar dengan layar';
      case 14:
        return 'AIS-SART aktif';
      case 15:
        return 'Tidak diketahui';
      default:
        return 'Kode $navStatus';
    }
  }

  /// Label tipe kapal (ITU-R M.1371) dalam Bahasa Indonesia.
  String? get shipTypeLabel {
    final t = shipType;
    if (t == null) return null;
    if (t == 30) return 'Kapal ikan';
    if (t == 31 || t == 32) return 'Kapal tunda (tow)';
    if (t == 33) return 'Kapal keruk';
    if (t == 34) return 'Kapal penyelam';
    if (t == 35) return 'Kapal militer';
    if (t == 36) return 'Kapal layar';
    if (t == 37) return 'Kapal pesiar';
    if (t >= 40 && t <= 49) return 'Kapal cepat (HSC)';
    if (t == 50) return 'Kapal pandu';
    if (t == 51) return 'Kapal SAR';
    if (t == 52) return 'Kapal tunda';
    if (t == 53) return 'Kapal pelabuhan';
    if (t == 54) return 'Kapal anti-polusi';
    if (t == 55) return 'Kapal penegak hukum';
    if (t == 58) return 'Kapal medis';
    if (t >= 60 && t <= 69) return 'Kapal penumpang';
    if (t >= 70 && t <= 79) return 'Kapal kargo';
    if (t >= 80 && t <= 89) return 'Kapal tanker';
    if (t >= 90 && t <= 99) return 'Kapal lain';
    return 'Tipe $t';
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
    int? navStatus,
    int? rateOfTurn,
    double? lengthM,
    double? beamM,
    String? callsign,
    int? imoNumber,
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
      navStatus: navStatus ?? this.navStatus,
      rateOfTurn: rateOfTurn ?? this.rateOfTurn,
      lengthM: lengthM ?? this.lengthM,
      beamM: beamM ?? this.beamM,
      callsign: callsign ?? this.callsign,
      imoNumber: imoNumber ?? this.imoNumber,
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
    double? metaLat;
    double? metaLon;
    if (meta is Map<String, dynamic>) {
      mmsi = _parseInt(meta['MMSI']);
      final rawName = meta['ShipName'];
      if (rawName is String && rawName.trim().isNotEmpty) {
        shipName = rawName.trim();
      }
      final rawTime = meta['time_utc'];
      if (rawTime is String) timeUtc = DateTime.tryParse(rawTime);
      // MetaData membawa posisi terakhir yang diketahui (dokumen
      // resmi §Consume) — dipakai sebagai cadangan bila laporan
      // posisi tidak membawa lat/lon. Terima ejaan PascalCase
      // (dokumen) maupun huruf kecil (yang terlihat di lapangan).
      metaLat = _parseDouble(meta['Latitude']) ??
          _parseDouble(meta['latitude']);
      metaLon = _parseDouble(meta['Longitude']) ??
          _parseDouble(meta['longitude']);
    }
    if (mmsi == null) return null;

    final message = envelope['Message'];
    if (message is! Map<String, dynamic>) return null;

    Vessel vessel = existing ?? Vessel(mmsi: mmsi, lastSeen: timeUtc);
    if (shipName != null) vessel = vessel.copyWith(name: shipName);
    if (timeUtc != null) vessel = vessel.copyWith(lastSeen: timeUtc);

    // Laporan posisi: Kelas A + Kelas B (bentuk field sama).
    Map<String, dynamic>? position;
    for (final key in [
      'PositionReport',
      'StandardClassBPositionReport',
      'ExtendedClassBPositionReport',
    ]) {
      final candidate = message[key];
      if (candidate is Map<String, dynamic>) {
        position = candidate;
        break;
      }
    }
    if (position != null) {
      final lat = _parseDouble(position['Latitude']);
      final lon = _parseDouble(position['Longitude']);
      final sog = _parseDouble(position['Sog']);
      final cog = _parseDouble(position['Cog']);
      final heading = _parseDouble(position['TrueHeading']);
      final navStatus = _parseInt(position['NavigationalStatus']);
      final rot = _parseInt(position['RateOfTurn']);
      vessel = vessel.copyWith(
        latitude: _resolveCoord(lat, 91.0, 90.0, metaLat, vessel.latitude),
        longitude:
            _resolveCoord(lon, 181.0, 180.0, metaLon, vessel.longitude),
        speedKnots: (sog != null && sog != 102.3) ? sog : vessel.speedKnots,
        courseDeg: (cog != null && cog != 360.0) ? cog : vessel.courseDeg,
        headingDeg:
            (heading != null && heading != 511.0) ? heading : vessel.headingDeg,
        navStatus: navStatus ?? vessel.navStatus,
        rateOfTurn: rot ?? vessel.rateOfTurn,
      );
    }

    final staticData = message['ShipStaticData'];
    if (staticData is Map<String, dynamic>) {
      final name = staticData['Name'];
      final destination = staticData['Destination'];
      final eta = staticData['Eta'];
      final type = _parseInt(staticData['Type']);
      final callsign =
          staticData['Callsign'] ?? staticData['CallSign'];
      final imo = _parseInt(staticData['ImoNumber']);
      // Dimensi A/B/C/D (meter dari titik referensi ke haluan/
      // buritan/kiri/kanan) -> panjang = A+B, lebar = C+D.
      double? lengthM;
      double? beamM;
      final dimension = staticData['Dimension'];
      if (dimension is Map<String, dynamic>) {
        final a = _parseDouble(dimension['A']);
        final b = _parseDouble(dimension['B']);
        final c = _parseDouble(dimension['C']);
        final d = _parseDouble(dimension['D']);
        if (a != null && b != null) lengthM = a + b;
        if (c != null && d != null) beamM = c + d;
      }
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
        lengthM: lengthM ?? vessel.lengthM,
        beamM: beamM ?? vessel.beamM,
        callsign: (callsign is String && callsign.trim().isNotEmpty)
            ? callsign.trim()
            : vessel.callsign,
        imoNumber: imo ?? vessel.imoNumber,
      );
    }

    // StaticDataReport (Kelas B, pesan 24): nama/tipe bila ada.
    final staticB = message['StaticDataReport'];
    if (staticB is Map<String, dynamic>) {
      final name = staticB['Name'];
      final type = _parseInt(staticB['Type']);
      final callsign = staticB['CallSign'] ?? staticB['Callsign'];
      vessel = vessel.copyWith(
        name: (name is String && name.trim().isNotEmpty)
            ? name.trim()
            : vessel.name,
        shipType: type ?? vessel.shipType,
        callsign: (callsign is String && callsign.trim().isNotEmpty)
            ? callsign.trim()
            : vessel.callsign,
      );
    }

    return AisParseResult(mmsi: mmsi, updated: vessel);
  }

  /// Pilih koordinat: laporan posisi dulu; bila tidak tersedia,
  /// pakai posisi MetaData; bila keduanya kosong, pertahankan lama.
  /// `notAvailable` = nilai "tidak tersedia" AIS (91 lat / 181 lon),
  /// `maxAbs` = batas rentang yang sah (90 lat / 180 lon).
  static double? _resolveCoord(
    double? report,
    double notAvailable,
    double maxAbs,
    double? meta,
    double? current,
  ) {
    if (report != null &&
        report != notAvailable &&
        report.abs() <= maxAbs) {
      return report;
    }
    if (meta != null && meta != notAvailable && meta.abs() <= maxAbs) {
      return meta;
    }
    return current;
  }
}

/// Status koneksi AISStream untuk chip status di panel AIS.
/// `disconnected` = diputuskan manual oleh pengguna (tombol Putuskan)
/// — kunci tetap tersimpan, sambung lagi dari panel.
enum AisConnectionState {
  notConfigured,
  connecting,
  connected,
  reconnecting,
  error,
  disconnected,
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
      case AisConnectionState.disconnected:
        return 'Terputus';
    }
  }
}
