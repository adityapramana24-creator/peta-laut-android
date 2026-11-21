import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../utils/formatters.dart';
import '../../../utils/nav_math.dart';
import '../../../utils/sun_moon.dart';
import '../../map/view_models/map_viewmodel.dart';

/// Panel Matahari & Bulan: terbit/terbenam + fase bulan,
/// dihitung dari posisi + tanggal (tanpa API — algoritma NOAA).
/// Titik acuan = posisi sendiri bila ada, else tengah peta.
Future<void> showSunMoonPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const SunMoonPanel(),
  );
}

class SunMoonPanel extends StatefulWidget {
  const SunMoonPanel({super.key});

  @override
  State<SunMoonPanel> createState() => _SunMoonPanelState();
}

class _SunMoonPanelState extends State<SunMoonPanel> {
  int _dayOffset = 0;

  @override
  Widget build(BuildContext context) {
    final mapVm = context.watch<MapViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final point = mapVm.panelPoint;
    final date = DateTime.now().add(Duration(days: _dayOffset));
    final day = DateTime(date.year, date.month, date.day);
    final (rise, set) = SunMoon.sunTimes(
      latitude: point.latitude,
      longitude: point.longitude,
      date: day,
    );
    final moon = SunMoon.moonPhase(
      DateTime.utc(day.year, day.month, day.day, 12),
    );
    final tzLabel = SunMoon.timezoneLabel(
      SunMoon.timezoneOffsetHours(point.longitude),
    );

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
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
            const Text(
              'Matahari & Bulan',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Di titik acuan peta (${tzLabel})',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            Text(
              '${NavMath.formatDecimal(point.latitude)}, '
              '${NavMath.formatDecimal(point.longitude)}',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Hari sebelumnya',
                  onPressed: () => setState(() => _dayOffset--),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      _dayOffset == 0
                          ? 'Hari ini, ${IdFormat.dayDateLong(day)}'
                          : IdFormat.dayDateLong(day),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Hari berikutnya',
                  onPressed: () => setState(() => _dayOffset++),
                ),
              ],
            ),
            if (_dayOffset != 0)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _dayOffset = 0),
                  child: const Text('Kembali ke hari ini'),
                ),
              ),
            const SizedBox(height: 8),
            // -- Matahari --
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.wb_sunny, color: Colors.amber),
                        const SizedBox(width: 8),
                        const Text(
                          'Matahari',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (rise == null || set == null)
                      const Text(
                        'Matahari tidak terbit atau tidak terbenam '
                        'di tanggal ini (daerah kutub).',
                      )
                    else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _SunTime(
                            icon: Icons.wb_twilight,
                            label: 'Terbit',
                            time: IdFormat.timeHm(rise),
                          ),
                          _SunTime(
                            icon: Icons.nights_stay,
                            label: 'Terbenam',
                            time: IdFormat.timeHm(set),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Siang ${IdFormat.durationShort(set.difference(rise))}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // -- Bulan --
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: CustomPaint(
                        painter: _MoonPainter(
                          phaseAngle: moon.phaseAngle,
                          isWaxing: moon.isWaxing,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.nightlight_round),
                              SizedBox(width: 8),
                              Text(
                                'Bulan',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            moon.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Terang ${(moon.illumination * 100).toStringAsFixed(0)}%',
                          ),
                          Text(
                            'Umur ${moon.ageDays.toStringAsFixed(1)} hari',
                          ),
                          Text(
                            moon.isWaxing
                                ? 'Membesar (menuju purnama)'
                                : 'Mengecil (menuju bulan baru)',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Dihitung di HP dari posisi + tanggal (algoritma NOAA) '
              '— tanpa internet.',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SunTime extends StatelessWidget {
  const _SunTime({
    required this.icon,
    required this.label,
    required this.time,
  });

  final IconData icon;
  final String label;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 28),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
        Text(
          time,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Gambar fase bulan: lingkaran gelap + bagian terang.
/// Bagian terang = setengah lingkaran kanan + busur terminator
/// (elips). Untuk fase mengecil, gambar dicerminkan horizontal.
class _MoonPainter extends CustomPainter {
  const _MoonPainter({
    required this.phaseAngle,
    required this.isWaxing,
  });

  final double phaseAngle;
  final bool isWaxing;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 4;

    // Cakram gelap.
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFF2A2A33),
    );

    // Bagian terang (digambar sebagai fase membesar, lalu dicerminkan
    // bila mengecil).
    canvas.save();
    if (!isWaxing) {
      canvas.translate(center.dx, center.dy);
      canvas.scale(-1, 1);
      canvas.translate(-center.dx, -center.dy);
    }
    final cosA = math.cos(phaseAngle);
    final rx = radius * cosA.abs();
    final path = Path();
    // Setengah lingkaran kanan: atas -> bawah via kanan.
    path.addArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi,
    );
    if (rx < 0.5) {
      // Perbani: terminator garis lurus.
      path.lineTo(center.dx, center.dy - radius);
    } else if (cosA < 0) {
      // Benjol: terminator menonjol ke kiri.
      path.arcTo(
        Rect.fromCenter(center: center, width: 2 * rx, height: 2 * radius),
        math.pi / 2,
        math.pi,
        false,
      );
    } else {
      // Sabit: terminator menonjol ke kanan.
      path.arcTo(
        Rect.fromCenter(center: center, width: 2 * rx, height: 2 * radius),
        math.pi / 2,
        -math.pi,
        false,
      );
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFFFFF3C4),
    );
    canvas.restore();

    // Garis tepi.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF888888)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_MoonPainter oldDelegate) =>
      oldDelegate.phaseAngle != phaseAngle ||
      oldDelegate.isWaxing != isWaxing;
}
