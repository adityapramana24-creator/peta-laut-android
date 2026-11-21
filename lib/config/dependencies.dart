import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local/app_database.dart';
import '../data/repositories/ais_repository.dart';
import '../data/repositories/depth_repository.dart';
import '../data/repositories/map_data_repository.dart';
import '../data/repositories/marine_repository.dart';
import '../data/repositories/navigation_repository.dart';
import '../data/repositories/offline_repository.dart';
import '../data/repositories/safety_repository.dart';
import '../data/repositories/tides_repository.dart';
import '../data/repositories/weather_repository.dart';
import '../data/repositories/windy_repository.dart';
import '../data/services/compass_service.dart';
import '../data/services/location_service.dart';
import '../data/services/notification_service.dart';
import '../data/services/settings_service.dart';
import '../ui/core/widgets/notice_banner.dart';
import '../ui/map/view_models/map_viewmodel.dart';
import '../ui/navigation/view_models/navigation_viewmodel.dart';
import '../ui/offline/view_models/offline_viewmodel.dart';
import '../ui/windy/view_models/windy_viewmodel.dart';

/// Satu-satunya tempat wiring dependensi aplikasi.
/// Panel view-model (pasang/cuaca/gelombang/AIS) dibuat per-buka-panel
/// dari repository yang sudah tersedia di sini.
List<SingleChildWidget> buildProviders({
  required SharedPreferences prefs,
  required AppDatabase db,
}) {
  final settings = SettingsService(prefs);
  final tidesRepository = TidesRepository(db: db);
  final weatherRepository = WeatherRepository(db: db);
  final marineRepository = MarineRepository(db: db);
  final depthRepository = DepthRepository(db: db);
  final aisRepository = AisRepository();
  final mapDataRepository = MapDataRepository();
  final navigationRepository = NavigationRepository(db: db);
  final locationService = LocationService();
  final compassService = CompassService();
  final noticeController = NoticeController();
  // Builder 2: notifikasi lokal dipakai bersama (alarm jangkar +
  // peringatan cuaca) — satu instance, init malas.
  final notificationService = NotificationService();
  final safetyRepository = SafetyRepository(prefs: prefs);
  final windyRepository = WindyRepository(
    weatherRepository: weatherRepository,
    marineRepository: marineRepository,
    prefs: prefs,
    notificationService: notificationService,
  );
  final offlineRepository = OfflineRepository(prefs: prefs);
  final navigationViewModel = NavigationViewModel(
    repository: navigationRepository,
    safetyRepository: safetyRepository,
    noticeController: noticeController,
    notificationService: notificationService,
  );
  final windyViewModel = WindyViewModel(
    repository: windyRepository,
    noticeController: noticeController,
  );
  final offlineViewModel = OfflineViewModel(
    repository: offlineRepository,
    noticeController: noticeController,
  );

  return [
    Provider<AppDatabase>.value(value: db),
    ChangeNotifierProvider<SettingsService>.value(value: settings),
    ChangeNotifierProvider<NoticeController>.value(value: noticeController),
    Provider<TidesRepository>.value(value: tidesRepository),
    Provider<WeatherRepository>.value(value: weatherRepository),
    Provider<MarineRepository>.value(value: marineRepository),
    Provider<DepthRepository>.value(value: depthRepository),
    Provider<AisRepository>.value(value: aisRepository),
    Provider<MapDataRepository>.value(value: mapDataRepository),
    Provider<NavigationRepository>.value(value: navigationRepository),
    Provider<SafetyRepository>.value(value: safetyRepository),
    Provider<WindyRepository>.value(value: windyRepository),
    Provider<OfflineRepository>.value(value: offlineRepository),
    Provider<NotificationService>.value(value: notificationService),
    Provider<LocationService>.value(value: locationService),
    Provider<CompassService>.value(value: compassService),
    ChangeNotifierProvider<NavigationViewModel>.value(
      value: navigationViewModel,
    ),
    ChangeNotifierProvider<WindyViewModel>.value(value: windyViewModel),
    ChangeNotifierProvider<OfflineViewModel>.value(value: offlineViewModel),
    ChangeNotifierProvider<MapViewModel>(
      create: (_) => MapViewModel(
        locationService: locationService,
        compassService: compassService,
        settingsService: settings,
        aisRepository: aisRepository,
        depthRepository: depthRepository,
        mapDataRepository: mapDataRepository,
        noticeController: noticeController,
        navigationViewModel: navigationViewModel,
      ),
    ),
  ];
}
