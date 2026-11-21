import '../../domain/models/port.dart';
import '../../utils/result.dart';
import '../services/gibs_service.dart';
import '../services/rainviewer_service.dart';

/// Data pendukung peta: template tile radar RainViewer (cache memori
/// 10 menit — frame radar diperbarui tiap 10 menit), template GIBS,
/// dan daftar pelabuhan.
class MapDataRepository {
  MapDataRepository({RainViewerService? rainViewerService})
      : _rainViewer = rainViewerService ?? RainViewerService();

  final RainViewerService _rainViewer;

  String? _rainTemplate;
  DateTime? _rainFetchedAt;
  static const _rainTtl = Duration(minutes: 10);

  List<Port> get ports => Port.all;

  Port nearestPort(double latitude, double longitude) =>
      Port.nearest(latitude, longitude);

  Future<Result<String>> getRainTemplate({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _rainTemplate != null &&
        _rainFetchedAt != null &&
        DateTime.now().difference(_rainFetchedAt!) < _rainTtl) {
      return Result.ok(_rainTemplate!);
    }
    final result = await _rainViewer.fetchLatestTileTemplate();
    switch (result) {
      case Ok(value: final template):
        _rainTemplate = template;
        _rainFetchedAt = DateTime.now();
        return Result.ok(template);
      case Error(error: final error):
        if (_rainTemplate != null) return Result.ok(_rainTemplate!);
        return Result.error(error);
    }
  }

  String get gibsTemplate => GibsService.tileTemplate();
}
