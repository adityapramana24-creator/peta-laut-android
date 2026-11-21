import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_constants.dart';
import '../../data/local/app_database.dart';
import '../../data/services/settings_service.dart';
import '../../domain/models/map_layers.dart';
import '../../domain/models/vessel.dart';
import '../ais/view_models/ais_viewmodel.dart';
import '../core/widgets/version_stamp.dart';
import '../map/view_models/map_viewmodel.dart';
import '../offline/widgets/offline_sheet.dart';

/// Layar Pengaturan: seksi AIS PALING ATAS dan jelas terlihat (R-18),
/// lalu basemap, lapisan, tema, cache, dan tentang.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AisViewModel _aisViewModel;
  final _keyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _aisViewModel = AisViewModel(repository: context.read());
    _aisViewModel.init();
  }

  @override
  void dispose() {
    _aisViewModel.dispose();
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final layers = settings.layerSettings;
    final scheme = Theme.of(context).colorScheme;

    return ChangeNotifierProvider<AisViewModel>.value(
      value: _aisViewModel,
      child: Scaffold(
        appBar: AppBar(title: const Text('Pengaturan')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _SectionTitle('Kunci AIS (AISStream)', Icons.key),
            const SizedBox(height: 4),
            _AisSection(
              controller: _keyController,
              viewModel: _aisViewModel,
            ),
            const SizedBox(height: 20),
            _SectionTitle('Peta', Icons.map),
            const SizedBox(height: 8),
            const Text('Basemap bawaan',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: BasemapKind.values.map((kind) {
                return ChoiceChip(
                  label: Text(kind.label),
                  selected: layers.basemap == kind,
                  onSelected: (_) => settings.setLayerSettings(
                    layers.copyWith(basemap: kind),
                  ),
                );
              }).toList(),
            ),
            SwitchListTile(
              title: const Text('Kedalaman GEBCO (warna laut)'),
              value: layers.showGebco,
              onChanged: (v) => settings.setLayerSettings(
                layers.copyWith(showGebco: v),
              ),
            ),
            SwitchListTile(
              title: const Text('Rambu laut (OpenSeaMap)'),
              value: layers.showSeamark,
              onChanged: (v) => settings.setLayerSettings(
                layers.copyWith(showSeamark: v),
              ),
            ),
            SwitchListTile(
              title: const Text('Radar hujan'),
              value: layers.showRain,
              onChanged: (v) => settings.setLayerSettings(
                layers.copyWith(showRain: v),
              ),
            ),
            SwitchListTile(
              title: const Text('Citra satelit NASA'),
              value: layers.showGibs,
              onChanged: (v) => settings.setLayerSettings(
                layers.copyWith(showGibs: v),
              ),
            ),
            SwitchListTile(
              title: const Text('Kapal AIS'),
              value: layers.showAis,
              onChanged: (v) => settings.setLayerSettings(
                layers.copyWith(showAis: v),
              ),
            ),
            const SizedBox(height: 12),
            _SectionTitle('Tampilan', Icons.palette),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('Sistem'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Terang'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Gelap'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (modes) {
                settings.setThemeMode(modes.first);
              },
            ),
            const SizedBox(height: 20),
            _SectionTitle('Penyimpanan', Icons.storage),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Wilayah peta tersimpan'),
              subtitle: const Text('Simpan area & kelola peta offline'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showOfflineSheet(context),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Hapus cache peta'),
              subtitle: const Text('Tile yang tersimpan akan diunduh ulang'),
              onTap: () => _clearTileCache(context),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Hapus cache data'),
              subtitle:
                  const Text('Pasang, cuaca, gelombang, kedalaman tersimpan'),
              onTap: () => _clearDataCache(context),
            ),
            const SizedBox(height: 20),
            _SectionTitle('Tentang', Icons.info_outline),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.sailing),
              title: const Text(AppConstants.appName),
              subtitle: Text(
                '${AppConstants.versionLabel}\n${AppConstants.credit}',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                AppConstants.safetyWarning,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Sumber data: OpenStreetMap, GEBCO, BMKG, Open-Meteo, '
                'hamandmore, RainViewer, NASA GIBS, AISStream.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: VersionStamp(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearTileCache(BuildContext context) async {
    try {
      await BuiltInMapCachingProvider.getOrCreateInstance()
          .destroy(deleteCache: true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache peta dihapus.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus cache peta: $e')),
        );
      }
    }
  }

  Future<void> _clearDataCache(BuildContext context) async {
    try {
      await context.read<AppDatabase>().clearAllCache();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache data dihapus.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus cache data: $e')),
        );
      }
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.icon);

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Seksi AIS di Pengaturan — kolom input kunci + simpan + status
/// selalu terlihat (R-18). Kunci yang tersimpan tidak pernah
/// ditampilkan kembali.
class _AisSection extends StatelessWidget {
  const _AisSection({required this.controller, required this.viewModel});

  final TextEditingController controller;
  final AisViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AisViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final mapVm = context.read<MapViewModel>();
    final saving = vm.saveKeyCommand.running;
    final testing = vm.testCommand.running;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  vm.hasKey ? Icons.check_circle : Icons.key_off,
                  size: 18,
                  color: vm.hasKey ? scheme.primary : scheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  vm.hasKey
                      ? 'Kunci tersimpan · ${vm.state.label}'
                      : 'Kunci belum diisi',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Kunci API AISStream',
                hintText: 'Tempel kunci baru di sini',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Simpan kunci'),
                  onPressed: saving || testing
                      ? null
                      : () {
                          viewModel.saveKeyCommand.execute(
                            (controller.text, mapVm.aisBounds),
                          );
                        },
                ),
                OutlinedButton(
                  onPressed: saving || testing
                      ? null
                      : () =>
                          viewModel.testCommand.execute(controller.text),
                  child: const Text('Uji sambungan'),
                ),
                if (vm.hasKey)
                  OutlinedButton(
                    onPressed: viewModel.deleteKey,
                    child: const Text('Hapus kunci'),
                  ),
              ],
            ),
            if (vm.statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                vm.statusMessage!,
                style: TextStyle(
                  fontSize: 13,
                  color: vm.statusIsError
                      ? scheme.error
                      : scheme.onSurface,
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label:
                  const Text('Daftar kunci gratis di aisstream.io'),
              onPressed: () async {
                final uri = Uri.parse(AppConstants.aisSignupUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
