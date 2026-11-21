/// Wilayah peta tersimpan (offline, R-32/R-33): metadata satu area
/// yang tile-nya diunduh ke penyimpanan lokal. Metadata disimpan di
/// SharedPreferences (JSON); file tile di
/// `<dokumen>/offline_areas/<id>/<basemap>/<z>/<x>/<y>.<ext>`.
class SavedArea {
  const SavedArea({
    required this.id,
    required this.name,
    required this.centerLat,
    required this.centerLon,
    required this.zoom,
    required this.basemap,
    required this.tileCount,
    required this.sizeBytes,
    required this.savedAt,
    this.failedTiles = 0,
  });

  final String id;
  final String name;
  final double centerLat;
  final double centerLon;

  /// Zoom saat area disimpan (tile hanya tersedia di zoom ini).
  final int zoom;

  /// Nama basemap (BasemapKind.name) saat disimpan.
  final String basemap;

  final int tileCount;
  final int sizeBytes;
  final DateTime savedAt;

  /// Tile yang gagal diunduh (tetap dicatat jujur).
  final int failedTiles;

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'centerLat': centerLat,
        'centerLon': centerLon,
        'zoom': zoom,
        'basemap': basemap,
        'tileCount': tileCount,
        'sizeBytes': sizeBytes,
        'savedAt': savedAt.toIso8601String(),
        'failedTiles': failedTiles,
      };

  factory SavedArea.fromJson(Map<String, dynamic> json) => SavedArea(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Area tersimpan',
        centerLat: (json['centerLat'] as num?)?.toDouble() ?? 0,
        centerLon: (json['centerLon'] as num?)?.toDouble() ?? 0,
        zoom: (json['zoom'] as num?)?.toInt() ?? 0,
        basemap: json['basemap'] as String? ?? 'standard',
        tileCount: (json['tileCount'] as num?)?.toInt() ?? 0,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ??
            DateTime.now(),
        failedTiles: (json['failedTiles'] as num?)?.toInt() ?? 0,
      );
}
