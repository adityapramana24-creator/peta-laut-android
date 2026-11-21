import '../../config/app_constants.dart';

/// Jenis basemap (R-05). Setiap jenis punya template tile + atribusi.
/// Fallback tile: OSM.de (fallbackUrl pada TileLayer) — bila tile
/// basemap non-standar gagal, flutter_map menampilkan tile OSM.de.
enum BasemapKind { standard, satellite, ocean, topo }

extension BasemapKindInfo on BasemapKind {
  String get label {
    switch (this) {
      case BasemapKind.standard:
        return 'Standar';
      case BasemapKind.satellite:
        return 'Satelit';
      case BasemapKind.ocean:
        return 'Laut (Esri)';
      case BasemapKind.topo:
        return 'Topo';
    }
  }

  String get urlTemplate {
    switch (this) {
      case BasemapKind.standard:
        return AppConstants.osmDeTemplate;
      case BasemapKind.satellite:
        return AppConstants.esriSatelliteTemplate;
      case BasemapKind.ocean:
        return AppConstants.esriOceanTemplate;
      case BasemapKind.topo:
        return AppConstants.topoTemplate;
    }
  }

  /// Zoom native tertinggi penyedia (di atas ini tile diperbesar).
  int get maxNativeZoom {
    switch (this) {
      case BasemapKind.standard:
        return 19;
      case BasemapKind.satellite:
        return 18;
      case BasemapKind.ocean:
        return 18;
      case BasemapKind.topo:
        return 17;
    }
  }

  String get attribution {
    switch (this) {
      case BasemapKind.standard:
        return '© OpenStreetMap contributors';
      case BasemapKind.satellite:
        return '© Esri, Maxar, Earthstar Geographics';
      case BasemapKind.ocean:
        return '© Esri, GEBCO, NOAA, National Geographic';
      case BasemapKind.topo:
        return '© OpenTopoMap (CC-BY-SA)';
    }
  }

  /// Atribusi lengkap untuk RichAttributionWidget.
  String get fullAttribution {
    switch (this) {
      case BasemapKind.standard:
        return '© OpenStreetMap contributors';
      case BasemapKind.satellite:
        return 'Esri, Maxar, Earthstar Geographics, dan komunitas GIS';
      case BasemapKind.ocean:
        return 'Esri, GEBCO, NOAA, National Geographic, DeLorme, HERE, Geonames.org';
      case BasemapKind.topo:
        return 'Map data: © OpenStreetMap contributors, SRTM | style: © OpenTopoMap (CC-BY-SA)';
    }
  }
}

/// Pengaturan lapisan overlay + basemap (disimpan SharedPreferences).
class LayerSettings {
  const LayerSettings({
    this.basemap = BasemapKind.standard,
    this.showGebco = true,
    this.showSeamark = true,
    this.showRain = false,
    this.showGibs = false,
    this.showAis = true,
  });

  final BasemapKind basemap;
  final bool showGebco;
  final bool showSeamark;
  final bool showRain;
  final bool showGibs;
  final bool showAis;

  LayerSettings copyWith({
    BasemapKind? basemap,
    bool? showGebco,
    bool? showSeamark,
    bool? showRain,
    bool? showGibs,
    bool? showAis,
  }) {
    return LayerSettings(
      basemap: basemap ?? this.basemap,
      showGebco: showGebco ?? this.showGebco,
      showSeamark: showSeamark ?? this.showSeamark,
      showRain: showRain ?? this.showRain,
      showGibs: showGibs ?? this.showGibs,
      showAis: showAis ?? this.showAis,
    );
  }
}
