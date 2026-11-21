import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../config/app_constants.dart';
import '../../utils/tile_math.dart';

/// Unduh + baca tile peta tersimpan (offline, R-32/R-33).
///
/// Kebijakan tile dihormati: hanya tile yang TAMPIL di layar pada zoom
/// saat ini, maks 2 unduhan bersamaan (batas OSM), maks 400 tile per
/// area, tanpa prefetch multi-zoom. File tersimpan di
/// `<dokumen>/offline_areas/<id>/<basemap>/<z>/<x>/<y>.<ext>`.
class OfflineTileService {
  OfflineTileService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Maksimum tile per area (batas kebijakan + ukuran wajar).
  static const int maxTilesPerArea = 400;

  /// Unduhan bersamaan (maks 2 thread sesuai kebijakan tile OSM).
  static const int maxConcurrentDownloads = 2;

  static const Duration _tileTimeout = Duration(seconds: 20);

  /// Ekstensi file tile per basemap (Esri menyajikan JPEG).
  static String extensionForBasemap(String basemapName) {
    switch (basemapName) {
      case 'satellite':
      case 'ocean':
        return 'jpg';
      default:
        return 'png';
    }
  }

  Future<Directory> _areasDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'offline_areas'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Jalur direktori dasar area offline (untuk lookup sinkron
  /// SavedAreaTileProvider — direktori dibuat bila belum ada).
  Future<String> areasDirPath() async => (await _areasDir()).path;

  String _tileFileName(String areaId, String basemap, int z, int x, int y) =>
      p.join(
        areaId,
        basemap,
        '$z',
        '$x',
        '$y.${extensionForBasemap(basemap)}',
      );

  /// Jalur file tile tersimpan (sinkron — dipakai TileProvider tiap
  /// render). Mengembalikan null bila file tidak ada.
  /// Membutuhkan direktori dokumen yang sudah diketahui — dipakai
  /// bersama [tileFilePathAsync] saat pertama kali (lihat repository).
  Future<String?> tileFilePath({
    required String areaId,
    required String basemap,
    required int z,
    required int x,
    required int y,
  }) async {
    final dir = await _areasDir();
    final file = File(p.join(
        dir.path, _tileFileName(areaId, basemap, z, x, y)));
    return await file.exists() ? file.path : null;
  }

  /// Unduh semua tile dalam [range] dari [urlTemplate].
  /// Stream kemajuan (done/total/gagal) — UI menampilkan persen.
  /// Tile yang gagal dilewati (dicatat di failed, bukan menggagalkan
  /// seluruh simpan). Mengembalikan ringkasan akhir via stream terakhir.
  Stream<SaveProgress> downloadArea({
    required String areaId,
    required String basemap,
    required TileRange range,
    required String urlTemplate,
  }) async* {
    final dir = await _areasDir();
    final tiles = range.tiles.toList();
    final total = tiles.length;
    var done = 0;
    var failed = 0;
    var bytes = 0;
    var index = 0;

    yield SaveProgress(done: 0, total: total, failed: 0, bytes: 0);

    Future<void> worker() async {
      while (true) {
        (int, int)? tile;
        // Ambil tile berikutnya (single-threaded Dart: aman tanpa lock).
        if (index < tiles.length) {
          tile = tiles[index];
          index++;
        }
        if (tile == null) return;
        final (x, y) = tile;
        final url = TileMath.tileUrl(urlTemplate, range.zoom, x, y);
        try {
          final response = await _client
              .get(
                Uri.parse(url),
                headers: {'User-Agent': AppConstants.userAgent},
              )
              .timeout(_tileTimeout);
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            final file = File(p.join(
              dir.path,
              _tileFileName(areaId, basemap, range.zoom, x, y),
            ));
            await file.parent.create(recursive: true);
            await file.writeAsBytes(response.bodyBytes);
            bytes += response.bodyBytes.length;
          } else {
            failed++;
          }
        } catch (_) {
          failed++;
        }
        done++;
      }
    }

    // 2 worker berjalan bersamaan; kemajuan dilaporkan tiap ~300 ms
    // selagi menunggu semua worker selesai.
    final workers = List.generate(
      maxConcurrentDownloads,
      (_) => worker(),
    );
    final allDone = Future.wait(workers);
    while (true) {
      final finished = await Future.any([
        allDone.then((_) => true),
        Future.delayed(const Duration(milliseconds: 300), () => false),
      ]);
      yield SaveProgress(
        done: done,
        total: total,
        failed: failed,
        bytes: bytes,
      );
      if (finished) break;
    }
  }

  /// Hapus seluruh file satu area. Mengembalikan true bila ada yang dihapus.
  Future<bool> deleteAreaFiles(String areaId) async {
    final dir = await _areasDir();
    final areaDir = Directory(p.join(dir.path, areaId));
    if (await areaDir.exists()) {
      await areaDir.delete(recursive: true);
      return true;
    }
    return false;
  }

  /// Ukuran total file satu area (byte).
  Future<int> areaSizeBytes(String areaId) async {
    final dir = await _areasDir();
    final areaDir = Directory(p.join(dir.path, areaId));
    if (!await areaDir.exists()) return 0;
    var total = 0;
    await for (final entity in areaDir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  void dispose() => _client.close();
}

/// Kemajuan unduh satu area.
class SaveProgress {
  const SaveProgress({
    required this.done,
    required this.total,
    required this.failed,
    required this.bytes,
  });

  final int done;
  final int total;
  final int failed;
  final int bytes;

  double get fraction => total == 0 ? 0 : done / total;
  int get percent => (fraction * 100).round();
  bool get isComplete => done >= total;
}
