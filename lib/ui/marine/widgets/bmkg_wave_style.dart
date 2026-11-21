import 'package:flutter/material.dart';

/// Warna kategori gelombang BMKG (skala 7 tingkat — lihat
/// bmkgWaveCategory di sea_regions.dart). Satu sumber kebenaran
/// untuk marker peta + chip panel agar warnanya konsisten.
///
/// Ramp hijau -> kuning -> oranye -> merah -> ungu (makin tinggi
/// gelombang, makin "bahaya" warnanya). Kategori tak dikenal -> abu-abu
/// (jangan menebak warna untuk kategori yang tidak dikenal).
Color bmkgWaveCategoryColor(String? category) {
  switch (category) {
    case 'Tenang':
      return const Color(0xFF2E7D32);
    case 'Rendah':
      return const Color(0xFF66BB6A);
    case 'Sedang':
      return const Color(0xFFF9A825);
    case 'Tinggi':
      return const Color(0xFFEF6C00);
    case 'Sangat Tinggi':
      return const Color(0xFFE64A19);
    case 'Ekstrem':
      return const Color(0xFFC62828);
    case 'Sangat Ekstrem':
      return const Color(0xFF4A148C);
    default:
      return Colors.grey;
  }
}
