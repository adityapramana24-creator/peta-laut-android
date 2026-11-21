/// Rambu laut (alat bantu navigasi) dari tag `seamark:*` OpenStreetMap.
///
/// SUMBER + BATAS KEJUJURAN (ronde 2, butir 20 — riset live 21 Nov 2026):
/// - Sebagian besar rambu Indonesia di OSM berasal dari impor US NGA
///   Pub. 112 (List of Lights) 2009/2023 — cukup kaya atribut
///   (karakter, warna, periode, tinggi, jangkauan, nomor referensi)
///   tapi BISA BASI atau SALAH. Contoh nyata: satu rambu Surabaya
///   ("Pisang") bertag IALA-B padahal Indonesia memakai IALA-A.
/// - Model ini menampilkan tag APA ADANYA — tidak pernah "memperbaiki"
///   data diam-diam. Bila tag bilang IALA-B, UI bilang IALA-B
///   (dengan label "sesuai tag OSM").
/// - Cakupan OSM di Indonesia JARANG dan tidak merata (Tanjung Priok 4
///   rambu, Surabaya/Tj. Perak 4, muara Barito 0, Laut Jawa 0).
///   Rambu yang tidak ada datanya TIDAK ditampilkan — jangan pernah
///   mengarang rambu. Teks kejujuran cakupan: [Seamark.coverageNote]
///   — wajib tampil di panel/lapisan rambu.
class Seamark {
  const Seamark({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.tags,
    this.name,
    required this.kind,
    this.lateralSide = LateralSide.unknown,
    this.cardinalQuadrant = CardinalQuadrant.unknown,
    this.colour,
    this.ialaSystem,
    this.lightCharacter,
    this.lightColour,
    this.lightGroup,
    this.lightPeriodSec,
    this.lightHeightM,
    this.lightRangeNm,
    this.lightReference,
    this.source,
  });

  /// Id unik OSM: "node/123", "way/456", "relation/789".
  final String id;
  final double latitude;
  final double longitude;

  /// Nilai mentah `seamark:type` (mis. "beacon_lateral").
  final String type;

  /// Semua tag OSM mentah (disimpan untuk cache + transparansi).
  final Map<String, String> tags;

  /// Nama — sering hanya ada di `seamark:name`, bukan `name`.
  final String? name;

  final SeamarkKind kind;
  final LateralSide lateralSide;
  final CardinalQuadrant cardinalQuadrant;

  /// Warna RAMBU (bukan cahaya), mentah dari tag
  /// (`seamark:<type>:colour`, mis. "red", "red;white").
  final String? colour;

  /// Sistem lateral mentah dari tag ("iala-a" / "iala-b") —
  /// ditampilkan apa adanya, TIDAK pernah "diperbaiki".
  final String? ialaSystem;

  // -- Karakteristik cahaya (`seamark:light:*`) --
  final String? lightCharacter;
  final String? lightColour;
  final String? lightGroup;
  final double? lightPeriodSec;
  final double? lightHeightM;
  final double? lightRangeNm;
  final String? lightReference;

  /// Sumber tag (`seamark:source` / `source`), mis. "NGA Pub. 112".
  final String? source;

  /// Catatan kejujuran cakupan — teks persis dari butir 20, wajib
  /// tampil di panel/lapisan rambu (lembar Lapisan + lembar detail).
  static const String coverageNote =
      'Data OpenStreetMap — cakupan di Indonesia belum merata; rambu '
      'yang tidak ada datanya tidak tampil. Data sebagian dari impor '
      'NGA Pub. 112 (2009/2023), bisa basi — selalu cek BPI '
      'Pushidrosal dan ENC resmi.';

  /// Parse satu elemen OSM. Null bila tidak ada tag `seamark:type`
  /// (bukan rambu — elemen dilewati, bukan error).
  static Seamark? fromOsmTags({
    required String id,
    required double latitude,
    required double longitude,
    required Map<String, String> tags,
  }) {
    final type = tags['seamark:type'];
    if (type == null || type.isEmpty) return null;
    final kind = _kindOf(type);

    final lateralRaw = _firstTag(tags, [
      'seamark:$type:category',
      'seamark:beacon_lateral:category',
      'seamark:buoy_lateral:category',
      'seamark:lateral:category',
    ]);
    final lateralSide = switch (lateralRaw?.toLowerCase()) {
      'port' => LateralSide.port,
      'starboard' => LateralSide.starboard,
      _ => LateralSide.unknown,
    };
    final cardinalRaw = _firstTag(tags, [
      'seamark:$type:category',
      'seamark:beacon_cardinal:category',
      'seamark:buoy_cardinal:category',
      'seamark:cardinal:category',
    ]);
    final cardinalQuadrant = switch (cardinalRaw?.toLowerCase()) {
      'north' => CardinalQuadrant.north,
      'south' => CardinalQuadrant.south,
      'east' => CardinalQuadrant.east,
      'west' => CardinalQuadrant.west,
      _ => CardinalQuadrant.unknown,
    };

    return Seamark(
      id: id,
      latitude: latitude,
      longitude: longitude,
      type: type,
      tags: Map<String, String>.unmodifiable(tags),
      // Nama sering hanya di `seamark:name`, bukan `name`.
      name: _firstTag(tags, ['seamark:name', 'name']),
      kind: kind,
      lateralSide: lateralSide,
      cardinalQuadrant: cardinalQuadrant,
      colour: _firstTag(tags, ['seamark:$type:colour', 'seamark:colour']),
      ialaSystem:
          _firstTag(tags, ['seamark:$type:system', 'seamark:system']),
      // Cahaya: tag utama dulu, lalu varian `:1:` (rambu berlampu
      // ganda menaruh cahaya pertama di `seamark:light:1:*`).
      lightCharacter: _firstTag(tags, [
        'seamark:light:character',
        'seamark:light:1:character',
      ]),
      lightColour: _firstTag(tags, [
        'seamark:light:colour',
        'seamark:light:1:colour',
      ]),
      lightGroup: _firstTag(tags, [
        'seamark:light:group',
        'seamark:light:1:group',
      ]),
      lightPeriodSec: _parseDouble(_firstTag(tags, [
        'seamark:light:period',
        'seamark:light:1:period',
      ])),
      lightHeightM: _parseDouble(_firstTag(tags, [
        'seamark:light:height',
        'seamark:light:1:height',
      ])),
      lightRangeNm: _parseDouble(_firstTag(tags, [
        'seamark:light:range',
        'seamark:light:1:range',
      ])),
      lightReference: _firstTag(tags, [
        'seamark:light:reference',
        'seamark:light:1:reference',
      ]),
      source: _firstTag(tags, ['seamark:source', 'source']),
    );
  }

  static String? _firstTag(Map<String, String> tags, List<String> keys) {
    for (final key in keys) {
      final value = tags[key];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static double? _parseDouble(String? raw) {
    if (raw == null) return null;
    return double.tryParse(raw.trim());
  }

  static SeamarkKind _kindOf(String type) {
    if (type.contains('lateral')) return SeamarkKind.lateral;
    if (type.contains('cardinal')) return SeamarkKind.cardinal;
    if (type.contains('isolated_danger')) {
      return SeamarkKind.isolatedDanger;
    }
    if (type.contains('safe_water')) return SeamarkKind.safeWater;
    if (type.contains('special_purpose')) {
      return SeamarkKind.specialPurpose;
    }
    switch (type) {
      case 'light_major':
        return SeamarkKind.lightMajor;
      case 'light_minor':
        return SeamarkKind.lightMinor;
      case 'landmark':
        return SeamarkKind.landmark;
      default:
        return SeamarkKind.other;
    }
  }

  /// Pelampung (`buoy_*`) vs rambu suar (`beacon_*`) — memengaruhi
  /// label Bahasa Indonesia ("Pelampung ..." vs "Rambu Suar ...").
  bool get isBuoy => type.startsWith('buoy_');

  /// Nama tampil: nama tag bila ada, else label jenis.
  String get displayName => name ?? typeLabel;

  /// Label jenis Bahasa Indonesia.
  String get typeLabel {
    final buoy = isBuoy;
    switch (kind) {
      case SeamarkKind.lateral:
        final side = switch (lateralSide) {
          LateralSide.port => 'Sisi Kiri (Port)',
          LateralSide.starboard => 'Sisi Kanan (Starboard)',
          LateralSide.unknown => 'Lateral',
        };
        return buoy ? 'Pelampung $side' : 'Rambu Suar $side';
      case SeamarkKind.cardinal:
        final quadrant = switch (cardinalQuadrant) {
          CardinalQuadrant.north => ' Utara',
          CardinalQuadrant.south => ' Selatan',
          CardinalQuadrant.east => ' Timur',
          CardinalQuadrant.west => ' Barat',
          CardinalQuadrant.unknown => '',
        };
        return buoy
            ? 'Pelampung Kardinal$quadrant'
            : 'Rambu Suar Kardinal$quadrant';
      case SeamarkKind.isolatedDanger:
        return buoy
            ? 'Pelampung Bahaya Terisolasi'
            : 'Rambu Bahaya Terisolasi';
      case SeamarkKind.safeWater:
        return buoy ? 'Pelampung Air Aman' : 'Rambu Air Aman';
      case SeamarkKind.specialPurpose:
        return buoy
            ? 'Pelampung Tujuan Khusus'
            : 'Rambu Tujuan Khusus';
      case SeamarkKind.lightMajor:
        return 'Mercusuar (Lampu Utama)';
      case SeamarkKind.lightMinor:
        return 'Lampu Kecil';
      case SeamarkKind.landmark:
        return 'Tanda Darat';
      case SeamarkKind.other:
        if (type == 'light_vessel') return 'Kapal Lampu';
        if (type == 'harbour') return 'Pelabuhan';
        return 'Rambu Laut';
    }
  }

  /// Label sisi lateral ("Kiri (Port)" / "Kanan (Starboard)").
  String? get lateralSideLabel => switch (lateralSide) {
        LateralSide.port => 'Kiri (Port)',
        LateralSide.starboard => 'Kanan (Starboard)',
        LateralSide.unknown => null,
      };

  /// Label kuartal kardinal ("Utara" / "Selatan" / "Timur" / "Barat").
  String? get cardinalQuadrantLabel => switch (cardinalQuadrant) {
        CardinalQuadrant.north => 'Utara',
        CardinalQuadrant.south => 'Selatan',
        CardinalQuadrant.east => 'Timur',
        CardinalQuadrant.west => 'Barat',
        CardinalQuadrant.unknown => null,
      };

  /// Warna rambu sebagai daftar token ("red;white" -> ["red", "white"]).
  List<String> get colours {
    final raw = colour;
    if (raw == null) return const [];
    return raw
        .split(';')
        .map((c) => c.trim().toLowerCase())
        .where((c) => c.isNotEmpty)
        .toList();
  }

  static const _characterLabels = <String, String>{
    'F': 'Tetap',
    'Fl': 'Berkedip',
    'LFl': 'Kilatan panjang',
    'Q': 'Kilatan cepat',
    'VQ': 'Kilatan sangat cepat',
    'UQ': 'Kilatan ultra cepat',
    'Iso': 'Isophase',
    'Oc': 'Okultasi',
    'Mo': 'Morse',
    'Al': 'Bergantian',
  };

  static const _colourLabels = <String, String>{
    'white': 'Putih',
    'red': 'Merah',
    'green': 'Hijau',
    'yellow': 'Kuning',
    'orange': 'Oranye',
    'blue': 'Biru',
    'violet': 'Ungu',
  };

  /// Ringkasan karakteristik cahaya satu baris, mis.
  /// "Berkedip (Fl) · Putih · 10 dtk · tinggi 46 m · jangkauan 18 nm".
  /// Null bila TIDAK ADA data cahaya sama sekali (bukan karangan).
  /// Kode asli selalu ditampilkan agar bisa dicocokkan dengan DSI/BPI.
  String? get lightSummary {
    if (lightCharacter == null &&
        lightColour == null &&
        lightPeriodSec == null &&
        lightHeightM == null &&
        lightRangeNm == null) {
      return null;
    }
    final parts = <String>[];
    final character = lightCharacter;
    if (character != null) {
      final label = _characterLabels[character] ?? character;
      final group = lightGroup;
      final code = group == null || group.isEmpty
          ? character
          : '$character($group)';
      final groupText = group == null || group.isEmpty
          ? ''
          : ' kelompok $group';
      parts.add('$label$groupText ($code)');
    }
    final colour = lightColour;
    if (colour != null) {
      parts.add(_colourLabels[colour.toLowerCase()] ?? colour);
    }
    final period = lightPeriodSec;
    if (period != null) parts.add('${_fmtNum(period)} dtk');
    final height = lightHeightM;
    if (height != null) parts.add('tinggi ${_fmtNum(height)} m');
    final range = lightRangeNm;
    if (range != null) parts.add('jangkauan ${_fmtNum(range)} nm');
    return parts.join(' · ');
  }

  /// Angka tanpa ".0" bila bulat ("10", bukan "10.0").
  static String _fmtNum(double value) => value == value.truncateToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  /// Serialisasi cache: simpan tag mentah + koordinat; baca kembali
  /// lewat [fromOsmTags] agar logika parsing tetap satu sumber.
  Map<String, dynamic> toJson() => {
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'tags': tags,
      };

  static Seamark? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final lat = json['latitude'];
    final lon = json['longitude'];
    final tags = json['tags'];
    if (id is! String || lat is! num || lon is! num || tags is! Map) {
      return null;
    }
    return fromOsmTags(
      id: id,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      tags: tags.map((k, v) => MapEntry(k.toString(), v.toString())),
    );
  }
}

/// Keluarga simbol rambu (menentukan bentuk + warna marker).
enum SeamarkKind {
  lateral,
  cardinal,
  isolatedDanger,
  safeWater,
  specialPurpose,
  lightMajor,
  lightMinor,
  landmark,
  other,
}

/// Sisi lateral (IALA): kiri = port, kanan = starboard.
enum LateralSide { port, starboard, unknown }

/// Kuartal kardinal.
enum CardinalQuadrant { north, south, east, west, unknown }
