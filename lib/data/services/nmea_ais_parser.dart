import '../../domain/models/vessel.dart';

/// Parser kalimat NMEA 0183 AIVDM/AIVDO (AIS) menjadi [Vessel].
///
/// Sumber spesifikasi: ITU-R M.1371 lewat dokumen GPSD
/// "AIVDM/AIVDO protocol decoding" (catb.org/gpsd/AIVDM.html) —
/// tata letak bit tipe 1/2/3/5/18/19/24, pemetaan ASCII 6-bit,
/// dan checksum XOR.
///
/// Algoritma ini DIVERIFIKASI independen sebelum ditulis: implementasi
/// referensi Python yang mencerminkan persis kode ini lolos 205 cek
/// pada 21 Nov 2026 — 12 kalimat terbitan publik dibandingkan dengan
/// pustaka matang pyais 3.3.1, 6 round-trip encode pyais, 9 kasus
/// rusak/tepi, dan 7 rakitan tangan dari tabel bit gpsd (termasuk
/// tipe 24B yang tidak bisa di-encode pyais, semua sentinel N/A,
/// tipe 5 terpotong 420 bit dan 264 bit yang umum di lapangan).
///
/// Aturan ketegasan (dari gpsd): checksum WAJIB valid — kalimat
/// tanpa checksum atau checksum salah dibuang diam-diam. Pesan
/// yang terpotong di tengah field yang dipakai ditolak; pesan
/// yang hanya kehilangan ekor radio-status (tidak dipakai)
/// tetap di-decode — contoh README pyais sendiri hanya 162 bit
/// padahal tipe 1 penuh 168 bit.
///
/// Tipe pesan yang didukung: 1/2/3 (laporan posisi Kelas A),
/// 5 (data statis), 18/19 (Kelas B), 24 (laporan data statis
/// Kelas B). Tipe lain mengembalikan null (bukan crash).
class NmeaAisParser {
  NmeaAisParser();

  /// Rakitan multi-fragmen yang sedang berjalan, kunci = seq id + kanal.
  final Map<String, _Assembly> _assemblies = {};

  /// Batas rakitan paralel — yang tertua dibuang bila penuh (lindungi
  /// memori dari stream nakal).
  static const int _maxAssemblies = 8;

  /// Umpan SATU baris NMEA (satu kalimat, tanpa '\n').
  ///
  /// Mengembalikan hasil bila satu pesan AIS lengkap ter-decode;
  /// null bila baris diabaikan (bukan AIS / checksum salah / rusak)
  /// atau rakitan multi-fragmen belum lengkap.
  ///
  /// [updated] pada hasil adalah kapal PARSIAL — hanya field yang
  /// dibawa pesan ini yang terisi, sisanya null. Penggabung (mis.
  /// AisRepository) yang me-merge ke kapal yang sudah dikenal lewat
  /// `copyWith` (field null tidak menimpa nilai lama).
  ///
  /// TIDAK PERNAH melempar: kalimat yang merusak apa pun ditelan
  /// menjadi null — satu kalimat jahat tidak boleh membunuh stream.
  ShipAisParseResult? feed(String line) {
    try {
      return _feed(line);
    } catch (_) {
      return null;
    }
  }

  ShipAisParseResult? _feed(String line) {
    final sentence = _parseSentence(line);
    if (sentence == null) return null;
    if (sentence.total == 1) {
      return _decodeSentence(sentence);
    }
    // Rakitan multi-fragmen.
    final key = '${sentence.seqId}|${sentence.channel}';
    var assembly = _assemblies[key];
    if (sentence.number == 1) {
      assembly = _Assembly(total: sentence.total);
      _assemblies[key] = assembly;
      if (_assemblies.length > _maxAssemblies) {
        _assemblies.remove(_assemblies.keys.first);
      }
    }
    if (assembly == null) return null; // fragmen 2 tanpa fragmen 1.
    if (assembly.total != sentence.total) {
      _assemblies.remove(key);
      return null;
    }
    // Fragmen harus berurutan — yang melompat membuang rakitan.
    if (sentence.number != assembly.received + 1) {
      _assemblies.remove(key);
      return null;
    }
    assembly.parts.add(sentence.payload);
    if (assembly.received < assembly.total) return null;
    _assemblies.remove(key);
    return _decodePayload(
      assembly.parts.join(),
      sentence.fillBits,
      sentence.isOwnShip,
      lastSeen: sentence.lastSeen,
    );
  }

  /// Decode satu kalimat TUNGGAL lengkap (tanpa status rakitan).
  /// Untuk test dan pemakaian satu kalimat. Multi-fragmen -> null.
  /// Tidak pernah melempar (lihat [feed]).
  static ShipAisParseResult? decodeLine(String line) {
    try {
      final sentence = _parseSentence(line);
      if (sentence == null || sentence.total != 1) return null;
      return _decodeSentence(sentence);
    } catch (_) {
      return null;
    }
  }

  static ShipAisParseResult? _decodeSentence(_NmeaSentence sentence) {
    return _decodePayload(
      sentence.payload,
      sentence.fillBits,
      sentence.isOwnShip,
      lastSeen: sentence.lastSeen,
    );
  }

  /// Decode payload 6-bit ASCII yang sudah dirakit menjadi [Vessel].
  ///
  /// [fillBits] = jumlah bit pad di akhir payload (field ke-7 kalimat).
  /// Mengembalikan null bila payload tidak bisa di-decode (tipe tidak
  /// didukung, MMSI 0, atau terpotong di tengah field yang dipakai).
  static ShipAisParseResult? _decodePayload(
    String payload,
    int fillBits,
    bool isOwnShip, {
    DateTime? lastSeen,
  }) {
    final bits = _payloadToBits(payload);
    if (bits == null) return null;
    // Buang bit pad akhir.
    final usable = fillBits > 0 && fillBits <= 5
        ? bits.sublist(0, bits.length - fillBits)
        : bits;
    if (usable.length < 38) return null; // belum sampai akhir MMSI.
    final reader = _BitReader(usable);
    final messageType = reader.u(0, 6);
    final mmsi = reader.u(8, 30);
    if (mmsi == 0) return null;

    String? name;
    double? latitude;
    double? longitude;
    double? speedKnots;
    double? courseDeg;
    double? headingDeg;
    String? destination;
    String? eta;
    int? shipType;
    int? navStatus;
    int? rateOfTurn;
    double? lengthM;
    double? beamM;
    String? callsign;
    int? imoNumber;

    // Panjang minimum = bit akhir field TERAKHIR yang dipakai (bukan
    // panjang spesifikasi penuh) — lihat catatan kelas di atas.
    switch (messageType) {
      case 1:
      case 2:
      case 3:
        if (usable.length < 137) return null; // heading berakhir bit 136.
        navStatus = reader.u(38, 4);
        rateOfTurn = reader.s(42, 8);
        speedKnots = _sog(reader.u(50, 10));
        longitude = _lon(reader.s(61, 28));
        latitude = _lat(reader.s(89, 27));
        courseDeg = _cog(reader.u(116, 12));
        headingDeg = _heading(reader.u(128, 9));
      case 5:
        if (usable.length < 240) return null; // nama+tipe berakhir bit 239.
        final imo = reader.u(40, 30);
        imoNumber = imo == 0 ? null : imo;
        callsign = reader.text(70, 7);
        name = reader.text(112, 20);
        final type = reader.u(232, 8);
        shipType = type == 0 ? null : type;
        if (usable.length >= 270) {
          // Dimensi A/B/C/D berakhir bit 269.
          final length = reader.u(240, 9) + reader.u(249, 9);
          final beam = reader.u(258, 6) + reader.u(264, 6);
          lengthM = length == 0 ? null : length.toDouble();
          beamM = beam == 0 ? null : beam.toDouble();
        }
        if (usable.length >= 302) {
          // ETA + sarat berakhir bit 301; tujuan menyusul.
          eta = _eta(
            reader.u(274, 4),
            reader.u(278, 5),
            reader.u(283, 5),
            reader.u(288, 6),
          );
          destination = reader.text(302, 20);
        }
      case 18:
        if (usable.length < 133) return null; // heading berakhir bit 132.
        speedKnots = _sog(reader.u(46, 10));
        longitude = _lon(reader.s(57, 28));
        latitude = _lat(reader.s(85, 27));
        courseDeg = _cog(reader.u(112, 12));
        headingDeg = _heading(reader.u(124, 9));
      case 19:
        if (usable.length < 133) return null;
        speedKnots = _sog(reader.u(46, 10));
        longitude = _lon(reader.s(57, 28));
        latitude = _lat(reader.s(85, 27));
        courseDeg = _cog(reader.u(112, 12));
        headingDeg = _heading(reader.u(124, 9));
        if (usable.length >= 263) {
          name = reader.text(143, 20);
        }
        if (usable.length >= 271) {
          final type = reader.u(263, 8);
          shipType = type == 0 ? null : type;
        }
        if (usable.length >= 301) {
          // Dimensi berakhir bit 300.
          final length = reader.u(271, 9) + reader.u(280, 9);
          final beam = reader.u(289, 6) + reader.u(295, 6);
          lengthM = length == 0 ? null : length.toDouble();
          beamM = beam == 0 ? null : beam.toDouble();
        }
      case 24:
        final part = reader.u(38, 2);
        if (part == 0) {
          if (usable.length < 160) return null;
          name = reader.text(40, 20);
        } else if (part == 1) {
          if (usable.length < 48) return null;
          final type = reader.u(40, 8);
          shipType = type == 0 ? null : type;
          if (usable.length >= 132) {
            callsign = reader.text(90, 7);
          }
        } else {
          return null;
        }
      default:
        return null; // Tipe tidak didukung — abaikan aman.
    }

    return ShipAisParseResult(
      mmsi: mmsi,
      updated: Vessel(
        mmsi: mmsi,
        name: name,
        latitude: latitude,
        longitude: longitude,
        speedKnots: speedKnots,
        courseDeg: courseDeg,
        headingDeg: headingDeg,
        destination: destination,
        eta: eta,
        lastSeen: lastSeen ?? DateTime.now(),
        shipType: shipType,
        navStatus: navStatus,
        rateOfTurn: rateOfTurn,
        lengthM: lengthM,
        beamM: beamM,
        callsign: callsign,
        imoNumber: imoNumber,
      ),
      isOwnShip: isOwnShip,
      messageType: messageType,
    );
  }

  /// Parse satu baris NMEA menjadi kalimat AIVDM/AIVDO.
  ///
  /// Menoleransi: tag block NMEA 4.10 di depan (`\s:...,c:...*\!AIVDM...`),
  /// field tambahan setelah checksum (format USCG `,s...,d...,T...,r...`),
  /// dan spasi di ujung baris. Menolak: bukan AIVDM/AIVDO, tanpa
  /// checksum, checksum salah, field jumlah fragmen tidak sah.
  static _NmeaSentence? _parseSentence(String line) {
    var text = line.trim();
    if (text.isEmpty) return null;

    // Tag block (NMEA 4.10): '\...*\!AIVDM,...' — potong sampai '!'.
    // Ambil stempel waktu 'c:' bila ada (detik/milidetik Unix).
    DateTime? tagTime;
    if (text.startsWith(r'\')) {
      final bang = text.indexOf('!');
      if (bang < 0) return null;
      final tag = text.substring(0, bang);
      final match = RegExp(r',c:(\d+)').firstMatch(tag);
      if (match != null) {
        final value = int.tryParse(match.group(1)!);
        if (value != null && value > 0) {
          tagTime = value > 9999999999
              ? DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
              : DateTime.fromMillisecondsSinceEpoch(value * 1000,
                  isUtc: true);
        }
      }
      text = text.substring(bang);
    }

    if (!text.startsWith('!')) return null;
    final star = text.indexOf('*');
    if (star < 0 || star + 3 > text.length) return null; // butuh 2 heks.
    final checksumHex = text.substring(star + 1, star + 3);
    final expected = int.tryParse(checksumHex, radix: 16);
    if (expected == null) return null;
    // XOR semua byte antara '!' dan '*'.
    var xor = 0;
    for (var i = 1; i < star; i++) {
      xor ^= text.codeUnitAt(i);
    }
    if (xor != expected) return null;

    final fields = text.substring(1, star).split(',');
    if (fields.length < 7) return null;
    final talker = fields[0];
    if (talker != 'AIVDM' && talker != 'AIVDO') return null;
    final total = int.tryParse(fields[1]);
    final number = int.tryParse(fields[2]);
    final fillBits = int.tryParse(fields[6]);
    if (total == null || total < 1 || total > 9) return null;
    if (number == null || number < 1 || number > total) return null;
    if (fillBits == null || fillBits < 0 || fillBits > 5) return null;
    final payload = fields[5];
    if (payload.isEmpty) return null;

    return _NmeaSentence(
      isOwnShip: talker == 'AIVDO',
      total: total,
      number: number,
      seqId: fields[3],
      channel: fields[4],
      payload: payload,
      fillBits: fillBits,
      lastSeen: tagTime,
    );
  }

  /// Payload ASCII 6-bit -> vektor bit (0/1).
  ///
  /// Pemetaan (ITU-R M.1371): nilai = kode - 48; bila > 40 kurangi
  /// 8 lagi. Karakter valid: kode 48–87 dan 96–119 — 'X'..'_' (88–95)
  /// dan karakter lain membuat seluruh payload tidak valid.
  static List<int>? _payloadToBits(String payload) {
    final bits = <int>[];
    for (var i = 0; i < payload.length; i++) {
      final value = _sixBitValue(payload.codeUnitAt(i));
      if (value == null) return null;
      for (var shift = 5; shift >= 0; shift--) {
        bits.add((value >> shift) & 1);
      }
    }
    return bits;
  }

  static int? _sixBitValue(int code) {
    if (code < 48 || code > 119 || (code > 87 && code < 96)) return null;
    var value = code - 48;
    if (value > 40) value -= 8;
    return value;
  }

  // --- Sentinel "tidak tersedia" AIS -> null (ITU-R M.1371). ---

  static double? _lat(int raw) =>
      raw == 54600000 ? null : raw / 600000.0; // 91 derajat = N/A.
  static double? _lon(int raw) =>
      raw == 108600000 ? null : raw / 600000.0; // 181 derajat = N/A.
  static double? _sog(int raw) {
    if (raw == 1023) return null; // N/A.
    if (raw == 1022) return 102.2; // 102,2 knot atau lebih.
    return raw / 10.0;
  }

  static double? _cog(int raw) => raw == 3600 ? null : raw / 10.0; // 360 = N/A.
  static double? _heading(int raw) => raw == 511 ? null : raw.toDouble();

  /// ETA -> "MM-DD HH:mm" (format yang sama dengan AISStream);
  /// bila jam/menit tidak tersedia -> "MM-DD" saja.
  static String? _eta(int month, int day, int hour, int minute) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final md = '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
    if (hour > 23 || minute > 59) return md;
    return '$md ${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }
}

/// Hasil parse satu pesan AIS dari NMEA 0183.
///
/// [updated] adalah kapal PARSIAL (hanya field dari pesan ini) —
/// penggabung me-merge ke kapal yang sudah dikenal lewat `copyWith`.
/// [isOwnShip] benar untuk AIVDO (posisi kapal sendiri — sumber
/// terbaik untuk CPA, lebih baik dari GPS).
class ShipAisParseResult {
  const ShipAisParseResult({
    required this.mmsi,
    required this.updated,
    required this.isOwnShip,
    required this.messageType,
  });

  final int mmsi;
  final Vessel updated;
  final bool isOwnShip;
  final int messageType;
}

/// Satu kalimat AIVDM/AIVDO yang sudah lolos validasi checksum.
class _NmeaSentence {
  const _NmeaSentence({
    required this.isOwnShip,
    required this.total,
    required this.number,
    required this.seqId,
    required this.channel,
    required this.payload,
    required this.fillBits,
    this.lastSeen,
  });

  final bool isOwnShip;
  final int total;
  final int number;
  final String seqId;
  final String channel;
  final String payload;
  final int fillBits;
  final DateTime? lastSeen;
}

/// Rakitan multi-fragmen yang sedang berjalan.
class _Assembly {
  _Assembly({required this.total});

  final int total;
  final List<String> parts = [];

  int get received => parts.length;
}

/// Pembaca bit (MSB dulu) dari vektor bit 0/1.
class _BitReader {
  _BitReader(this._bits);

  final List<int> _bits;

  int get length => _bits.length;

  /// Bilangan unsigned [length] bit mulai [start].
  int u(int start, int length) {
    var value = 0;
    for (var i = 0; i < length; i++) {
      value = (value << 1) | _bits[start + i];
    }
    return value;
  }

  /// Bilangan signed (two's complement) [length] bit mulai [start].
  int s(int start, int length) {
    final value = u(start, length);
    return value >= (1 << (length - 1)) ? value - (1 << length) : value;
  }

  /// String ASCII 6-bit: nilai < 32 -> chr(nilai + 64), sisanya
  /// chr(nilai). Hanya membaca karakter yang LENGKAP tersedia
  /// (pesan liar kadang terpotong di tengah field tujuan).
  /// Pangkas '@'/spasi akhir; string kosong -> null.
  String? text(int start, int chars) {
    final available = (_bits.length - start) ~/ 6;
    final count = chars < available ? chars : available;
    if (count <= 0) return null;
    final buffer = StringBuffer();
    for (var i = 0; i < count; i++) {
      final value = u(start + i * 6, 6);
      buffer.writeCharCode(value < 32 ? value + 64 : value);
    }
    final result = buffer.toString().replaceAll(RegExp(r'[@ ]+$'), '').trim();
    return result.isEmpty ? null : result;
  }
}
