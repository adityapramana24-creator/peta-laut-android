import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_constants.dart';
import 'config/dependencies.dart';
import 'config/theme.dart';
import 'data/local/app_database.dart';
import 'data/services/settings_service.dart';
import 'ui/map/widgets/map_screen.dart';
import 'ui/splash/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Konfigurasi cache tile SEKALI di awal (sebelum TileLayer pertama
  // dibuat) — konfigurasi tidak bisa diubah setelah instance dibuat.
  // Kesegaran tile mengikuti header HTTP server (default flutter_map).
  BuiltInMapCachingProvider.getOrCreateInstance(
    maxCacheSize: AppConstants.tileCacheMaxBytes,
  );

  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase();

  runApp(
    MultiProvider(
      providers: buildProviders(prefs: prefs, db: db),
      child: const PetaLautApp(),
    ),
  );
}

/// Root app: splash ~900 ms lalu peta (transisi fade).
class PetaLautApp extends StatefulWidget {
  const PetaLautApp({super.key});

  @override
  State<PetaLautApp> createState() => _PetaLautAppState();
}

class _PetaLautAppState extends State<PetaLautApp> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _showSplash
            ? const SplashScreen(key: ValueKey('splash'))
            : const MapScreen(key: ValueKey('map')),
      ),
    );
  }
}
