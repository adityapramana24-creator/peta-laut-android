import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/services/settings_service.dart';
import '../../navigation/view_models/navigation_viewmodel.dart';
import '../../navigation/widgets/anchor_mob_sheet.dart';
import '../../navigation/widgets/navigation_sheet.dart';
import '../../navigation/widgets/ports_sheet.dart';
import '../../navigation/widgets/sun_moon_panel.dart';
import '../../offline/widgets/offline_sheet.dart';
import '../../windy/view_models/windy_viewmodel.dart';
import '../../windy/widgets/route_weather_sheet.dart';
import '../../windy/widgets/windy_panel.dart';

/// Menu "Lainnya" (item ke-6 bar bawah): semua fitur navigasi +
/// Windy + offline dalam satu daftar.
/// [parentContext] = konteks halaman peta (tetap hidup setelah
/// lembar ini ditutup) — dipakai untuk membuka lembar berikutnya.
Future<void> showMoreSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => MoreSheet(parentContext: context),
  );
}

class MoreSheet extends StatelessWidget {
  const MoreSheet({super.key, required this.parentContext});

  final BuildContext parentContext;

  void _open(void Function(BuildContext) show) {
    Navigator.of(parentContext).pop();
    show(parentContext);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final nav = context.watch<NavigationViewModel>();
    final isDark = settings.themeMode == ThemeMode.dark ||
        (settings.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _MenuItem(
            icon: Icons.place,
            title: 'Titik & Rute',
            subtitle: 'Waypoint, rute, dan jejak',
            onTap: () => _open(
              (c) => showNavigationSheet(c, initialTab: 0),
            ),
          ),
          _MenuItem(
            icon: Icons.timeline,
            title: 'Jejak',
            subtitle: 'Rekam perjalanan kapal',
            trailing: nav.isRecording
                ? const _RecordingDot()
                : null,
            onTap: () => _open(
              (c) => showNavigationSheet(c, initialTab: 2),
            ),
          ),
          _MenuItem(
            icon: Icons.anchor,
            title: 'Jangkar & MOB',
            subtitle: 'Alarm jangkar dan tanda darurat',
            onTap: () => _open(showAnchorMobSheet),
          ),
          _MenuItem(
            icon: Icons.wb_sunny,
            title: 'Matahari & Bulan',
            subtitle: 'Terbit, terbenam, dan fase bulan',
            onTap: () => _open(showSunMoonPanel),
          ),
          _MenuItem(
            icon: Icons.air,
            title: 'Angin & Prakiraan',
            subtitle: 'Partikel angin, meteogram, peringatan',
            onTap: () => _open(showWindyPanel),
          ),
          _MenuItem(
            icon: Icons.cloud,
            title: 'Cuaca di Rute',
            subtitle: 'Prakiraan di tiap titik rute',
            onTap: () => _open(
              (c) => showRouteWeatherSheet(c),
            ),
          ),
          _MenuItem(
            icon: Icons.sailing,
            title: 'Pelabuhan',
            subtitle: 'Lompat ke 15 pelabuhan',
            onTap: () => _open(showPortsSheet),
          ),
          _MenuItem(
            icon: Icons.straighten,
            title: 'Ukur Jarak',
            subtitle: nav.measureMode
                ? 'Aktif — ketuk peta untuk menambah titik'
                : 'Ketuk peta untuk mengukur jarak',
            trailing: nav.measureMode
                ? Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            onTap: () {
              Navigator.of(parentContext).pop();
              // Mode ukur dan mode pilih titik saling meniadakan.
              if (!nav.measureMode) {
                context.read<WindyViewModel>().setPickMode(false);
              }
              context.read<NavigationViewModel>().setMeasureMode(
                    !nav.measureMode,
                  );
            },
          ),
          _MenuItem(
            icon: Icons.download,
            title: 'Peta Offline',
            subtitle: 'Simpan area & wilayah tersimpan',
            onTap: () => _open(showOfflineSheet),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('Mode Malam'),
            subtitle: const Text('Tema gelap + peta diredupkan'),
            value: isDark,
            onChanged: (value) {
              context.read<SettingsService>().setThemeMode(
                    value ? ThemeMode.dark : ThemeMode.light,
                  );
            },
          ),
        ],
      ),
    );
  }
}

class _RecordingDot extends StatelessWidget {
  const _RecordingDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
