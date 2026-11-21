import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_constants.dart';
import '../../../domain/models/seamark.dart';
import '../../../utils/nav_math.dart';
import '../../core/widgets/seamark_marker.dart';

/// Lembar detail satu rambu laut (dari marker peta): nama, jenis
/// Bahasa Indonesia, karakteristik cahaya, posisi desimal + DMS,
/// sumber data + catatan cakupan, dan tautan "Cek BPI terbaru".
/// Semua nilai tampil APA ADANYA dari tag OSM — tidak pernah
/// "diperbaiki" diam-diam (lihat seamark.dart).
Future<void> showSeamarkSheet(BuildContext context, Seamark seamark) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SeamarkSheet(seamark: seamark),
  );
}

class SeamarkSheet extends StatelessWidget {
  const SeamarkSheet({super.key, required this.seamark});

  final Seamark seamark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lightSummary = seamark.lightSummary;
    // Baris sisi lateral: sisi + sistem IALA SESUAI TAG (bila ada).
    // Contoh nyata: "Pisang" Surabaya bertag IALA-B — ditampilkan
    // apa adanya, bukan diubah jadi IALA-A.
    final sideLabel = seamark.lateralSideLabel;
    final system = seamark.ialaSystem;
    final sideText = [
      if (sideLabel != null) sideLabel,
      if (system != null)
        'sistem ${system.toUpperCase()} (sesuai tag OSM)',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SeamarkMarker(seamark: seamark, size: 32),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    seamark.displayName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Row(label: 'Jenis', value: seamark.typeLabel),
            if (sideText.isNotEmpty)
              _Row(label: 'Sisi', value: sideText),
            if (seamark.cardinalQuadrantLabel != null)
              _Row(
                label: 'Kuartal',
                value: seamark.cardinalQuadrantLabel!,
              ),
            _Row(
              label: 'Cahaya',
              value: lightSummary ?? 'Tidak ada data cahaya',
            ),
            if (seamark.lightReference != null)
              _Row(
                label: 'Nomor referensi',
                value: seamark.lightReference!,
              ),
            _Row(
              label: 'Posisi',
              value:
                  '${NavMath.formatDecimal(seamark.latitude)}, '
                  '${NavMath.formatDecimal(seamark.longitude)}',
            ),
            _Row(
              label: '',
              value: NavMath.formatLatLonDms(
                seamark.latitude,
                seamark.longitude,
              ),
            ),
            _Row(label: 'Jenis OSM', value: seamark.type),
            _Row(
              label: 'Sumber',
              value: seamark.source ?? 'OpenStreetMap',
            ),
            const SizedBox(height: 12),
            Text(
              Seamark.coverageNote,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            const _BpiWebLink(),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tautan web BPI Pushidrosal (halaman resmi unduhan Berita Pelaut
/// Indonesia, mingguan). Pola gagal-jujur yang sama seperti tombol
/// BMKG: bila browser tidak bisa dibuka, tampilkan URL-nya agar user
/// bisa membuka manual — jangan pernah gagal diam-diam.
class _BpiWebLink extends StatelessWidget {
  const _BpiWebLink();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.open_in_new, size: 16),
      label: const Text('Cek BPI terbaru'),
      onPressed: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    const url = AppConstants.bpiUrl;
    final uri = Uri.parse(url);
    bool opened = false;
    try {
      // launchUrl langsung tanpa gate canLaunchUrl: canLaunchUrl bisa
      // false di perangkat tanpa browser default terdaftar, padahal
      // launchUrl sendiri masih bisa membuka chooser browser.
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Tidak bisa membuka browser. Salin alamat ini dan buka manual:\n$url',
        ),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Salin',
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: url));
          },
        ),
      ),
    );
  }
}
