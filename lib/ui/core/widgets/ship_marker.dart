import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/ais_target_status.dart';

/// Marker target AIS mengikuti simbologi ECDIS asli.
///
/// SUMBER (dicek 2026-11-21):
/// - IMO SN.1/Circ.243, "Guidelines for the Presentation of
///   Navigation-Related Symbols", Tabel 3 (AIS Symbols):
///   segitiga sama kaki lancip, puncak searah heading (atau COG bila
///   heading tidak ada), posisi di tengah + setengah tinggi segitiga;
///   target tidur LEBIH KECIL dari target aktif; tanpa heading/COG —
///   segitiga menghadap atas dengan satu garis melintang; target
///   berbahaya — merah, tebal, berkedip sampai diakui; target
///   terpilih — kotak putus-putus; target hilang — tanda X.
/// - IEC 62288 §5.5: target aktif menampilkan vektor COG/SOG,
///   garis haluan, dan indikasi ROT bila ada.
/// - IHO S-52 / IMO MSC.232(82) dirujuk IEC 62288 sebagai pustaka
///   presentasi ECDIS.
///
/// KEJUJURAN / BATAS:
/// - Simbol ECDIS asli adalah SEGITIGA, bukan siluet kapal — file ini
///   memakai segitiga (v1.1 memakai siluet; siluet tidak standar).
/// - Berkedip sampai diakui (ECDIS) tidak direplikasi: marker statis,
///   peringatan berbahaya disampaikan lewat banner notice satu-slot.
/// - Vektor digambar dalam piksel layar (bukan skala peta) kecuali
///   parent mengoper vectorLengthPx dari vectorPxFor().
/// - Garis haluan butuh heading; bila hanya COG, vektor memakai COG.
/// - Outline skala-nyata kapal (butuh dimensi A/B/C/D + zoom besar)
///   TIDAK digambar — data dimensi tidak selalu ada di pesan AIS.
/// - Rotasi heading dilakukan parent dengan Transform.rotate
///   (seperti sebelumnya).
class ShipMarker extends StatelessWidget {
  const ShipMarker({
    super.key,
    this.size = 28,
    this.color = const Color(0xFF1565C0),
    this.selected = false,
    this.status,
    this.headingDeg,
    this.courseDeg,
    this.speedKnots,
    this.rateOfTurn,
    this.vectorLengthPx,
  });

  final double size;
  final Color color;
  final bool selected;

  /// Status target (bila null: selected -> activated, lainnya tidur).
  final AisTargetStatus? status;
  final double? headingDeg;
  final double? courseDeg;
  final double? speedKnots;

  /// Indikator ROT mentah (null/0/-128 = tidak berbelok).
  final int? rateOfTurn;

  /// Panjang vektor kecepatan dalam piksel (dari vectorPxFor).
  /// Bila null, dipakai 1,2x size (bukan skala peta).
  final double? vectorLengthPx;

  AisTargetStatus get effectiveStatus =>
      status ??
      (selected ? AisTargetStatus.activated : AisTargetStatus.sleeping);

  /// Panjang vektor N menit dalam piksel pada zoom/lintang ini
  /// (vektor 6 menit adalah bawaan ECDIS).
  /// Rumus meter/piksel tile web: 156543.03392*cos(lat)/2^zoom.
  /// Dibatasi 120 px agar marker tidak raksasa di zoom tinggi.
  static double vectorPxFor({
    required double sogKnots,
    required double zoom,
    required double latitude,
    double minutes = 6,
  }) {
    final metersPerPx = 156543.03392 *
        math.cos(latitude * math.pi / 180) /
        math.pow(2, zoom);
    final meters = sogKnots * 1852 * minutes / 60;
    return (meters / metersPerPx).clamp(0.0, 120.0).toDouble();
  }

  /// Ruang ekstra (px) di atas/bawah segitiga untuk vektor +
  /// garis haluan. Nol untuk tidur/hilang (tanpa vektor).
  static double _extension(
    double size,
    AisTargetStatus status,
    double? vectorLengthPx,
  ) {
    if (status != AisTargetStatus.activated &&
        status != AisTargetStatus.dangerous) {
      return 0;
    }
    final v = vectorLengthPx ?? size * 1.2;
    const h = 0.8; // garis haluan 0,8x size
    return math.max(v, size * h);
  }

  /// Ukuran kanvas total — parent WAJIB memakai ini untuk Marker
  /// width/height agar vektor tidak terpotong. Segitiga selalu di
  /// TENGAH kanvas (jangkar marker = tengah).
  static Size canvasSize({
    required double size,
    AisTargetStatus status = AisTargetStatus.sleeping,
    double? vectorLengthPx,
  }) {
    final ext = _extension(size, status, vectorLengthPx);
    return Size(size + ext, size * 1.4 + 2 * ext);
  }

  @override
  Widget build(BuildContext context) {
    final st = effectiveStatus;
    final paintColor = switch (st) {
      AisTargetStatus.dangerous => Colors.red.shade700,
      AisTargetStatus.lost => Colors.grey.shade600,
      _ => color,
    };
    return CustomPaint(
      size: canvasSize(
        size: size,
        status: st,
        vectorLengthPx: vectorLengthPx,
      ),
      painter: _AisTargetPainter(
        color: paintColor,
        status: st,
        size: size,
        headingDeg: headingDeg,
        courseDeg: courseDeg,
        speedKnots: speedKnots,
        rateOfTurn: rateOfTurn,
        vectorLengthPx: vectorLengthPx ?? size * 1.2,
      ),
    );
  }
}

class _AisTargetPainter extends CustomPainter {
  _AisTargetPainter({
    required this.color,
    required this.status,
    required this.size,
    this.headingDeg,
    this.courseDeg,
    this.speedKnots,
    this.rateOfTurn,
    this.vectorLengthPx = 0,
  });

  final Color color;
  final AisTargetStatus status;
  final double size;
  final double? headingDeg;
  final double? courseDeg;
  final double? speedKnots;
  final int? rateOfTurn;
  final double vectorLengthPx;

  bool get _hasVector =>
      (status == AisTargetStatus.activated ||
          status == AisTargetStatus.dangerous) &&
      courseDeg != null &&
      speedKnots != null &&
      speedKnots! > 0;

  bool get _hasHeadingLine =>
      (status == AisTargetStatus.activated ||
          status == AisTargetStatus.dangerous) &&
      headingDeg != null;

  bool get _isTurning =>
      rateOfTurn != null && rateOfTurn != 0 && rateOfTurn != -128;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final cx = canvasSize.width / 2;
    final cy = canvasSize.height / 2;
    // Target tidur lebih kecil (IMO: "smaller than activated").
    final scale = status == AisTargetStatus.sleeping ? 0.75 : 1.0;
    final w = size * scale;
    final h = size * 1.4 * scale;
    // Segitiga sama kaki lancip, puncak di atas (arah haluan —
    // parent memutar seluruh widget mengikuti heading).
    final triangle = Path()
      ..moveTo(cx, cy - h / 2)
      ..lineTo(cx + w / 2, cy + h / 2)
      ..lineTo(cx - w / 2, cy + h / 2)
      ..close();

    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, w * 0.12);
    final bold = status == AisTargetStatus.dangerous;

    if (status == AisTargetStatus.sleeping) {
      // Tidur: garis luar saja (tanpa isi).
      canvas.drawPath(triangle, white);
      final outline = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, w * 0.07);
      canvas.drawPath(triangle, outline);
    } else {
      // Aktif/berbahaya/hilang: isi + tepi putih agar terbaca
      // di atas tile gelap/terang; berbahaya = tepi lebih tebal.
      final fill = Paint()
        ..color = status == AisTargetStatus.lost
            ? color.withValues(alpha: 0.45)
            : color
        ..style = PaintingStyle.fill;
      canvas.drawPath(triangle, fill);
      final outline = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            math.max(1.0, w * (bold ? 0.1 : 0.05));
      canvas.drawPath(triangle, outline);
    }

    // Garis haluan: garis lurus tipis dari posisi ke depan.
    if (_hasHeadingLine) {
      final line = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, w * 0.04);
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx, cy - h / 2 - size * 0.8),
        line,
      );
    }

    // Vektor COG/SOG: garis putus-putus dari posisi, searah COG.
    // Parent memutar widget mengikuti heading, jadi vektor digambar
    // pada sudut relatif (COG - heading); bila heading tidak ada,
    // parent memutar mengikuti COG sehingga sudut relatif = 0.
    if (_hasVector) {
      final rel = ((courseDeg! - (headingDeg ?? courseDeg!)) *
              math.pi /
              180);
      final length = h / 2 + vectorLengthPx;
      final end = Offset(
        cx + math.sin(rel) * length,
        cy - math.cos(rel) * length,
      );
      final dash = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, w * 0.06);
      _drawDashedLine(canvas, Offset(cx, cy), end, dash);
      // Indikasi ROT: kait kecil di ujung vektor, arah belok.
      // (ECDIS memakai panah melengkung; kait ini penyederhanaan
      // yang jujur — bukan panah lengkung penuh.)
      if (_isTurning) {
        final dir = rateOfTurn! > 0 ? 1.0 : -1.0;
        final perp = Offset(math.cos(rel) * dir, math.sin(rel) * dir);
        canvas.drawLine(end, end + perp * size * 0.3, dash);
      }
    }

    // Target terpilih/aktif: kotak putus-putus di sekeliling simbol.
    if (status == AisTargetStatus.activated) {
      final box = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, w * 0.05);
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: w + 8,
        height: h + 8,
      );
      _drawDashedRect(canvas, rect, box);
    }

    // Tanpa heading maupun COG: satu garis melintang simbol (IMO).
    if (headingDeg == null && courseDeg == null) {
      final cross = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, w * 0.07);
      canvas.drawLine(
        Offset(cx - w / 2, cy - h / 2),
        Offset(cx + w / 2, cy + h / 2),
        cross,
      );
    }

    // Target hilang: tanda X di atas simbol.
    if (status == AisTargetStatus.lost) {
      final xPaint = Paint()
        ..color = Colors.grey.shade800
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, w * 0.07);
      canvas.drawLine(
        Offset(cx - w / 2, cy - h / 2),
        Offset(cx + w / 2, cy + h / 2),
        xPaint,
      );
      canvas.drawLine(
        Offset(cx + w / 2, cy - h / 2),
        Offset(cx - w / 2, cy + h / 2),
        xPaint,
      );
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint,
  ) {
    const dash = 6.0;
    const gap = 4.0;
    final total = (to - from).distance;
    if (total <= 0) return;
    final dir = (to - from) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(from + dir * d, from + dir * end, paint);
      d = end + gap;
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    _drawDashedLine(canvas, rect.topLeft, rect.topRight, paint);
    _drawDashedLine(canvas, rect.topRight, rect.bottomRight, paint);
    _drawDashedLine(canvas, rect.bottomRight, rect.bottomLeft, paint);
    _drawDashedLine(canvas, rect.bottomLeft, rect.topLeft, paint);
  }

  @override
  bool shouldRepaint(covariant _AisTargetPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.status != status ||
      oldDelegate.size != size ||
      oldDelegate.headingDeg != headingDeg ||
      oldDelegate.courseDeg != courseDeg ||
      oldDelegate.speedKnots != speedKnots ||
      oldDelegate.rateOfTurn != rateOfTurn ||
      oldDelegate.vectorLengthPx != vectorLengthPx;
}
