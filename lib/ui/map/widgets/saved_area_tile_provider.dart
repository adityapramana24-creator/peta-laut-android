import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../../data/repositories/offline_repository.dart';

/// TileProvider lapisan area tersimpan (offline, R-32/R-33).
/// Tile lokal dipakai bila file-nya ada; bila tidak ada, tile
/// transparan dikembalikan sehingga basemap jaringan di bawahnya
/// tetap tampil. Basemap aktif dibaca lewat [basemapGetter] tiap
/// render (area hanya berlaku untuk basemap saat disimpan).
class SavedAreaTileProvider extends TileProvider {
  SavedAreaTileProvider({
    required OfflineRepository repository,
    required ValueGetter<String> basemapGetter,
  })  : _repository = repository,
        _basemapGetter = basemapGetter;

  final OfflineRepository _repository;
  final ValueGetter<String> _basemapGetter;

  /// PNG transparan 1x1 (tile kosong — basemap di bawah tampil).
  static final Uint8List _transparentPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final path = _repository.localTilePath(
      basemap: _basemapGetter(),
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
    );
    if (path != null) return FileImage(File(path));
    return MemoryImage(_transparentPng);
  }
}
