import 'dart:async';

import 'package:flutter/material.dart';

/// Notifikasi satu slot: pesan baru menggantikan yang lama,
/// hilang otomatis setelah ~5 detik (R-25).
class NoticeController extends ChangeNotifier {
  String? _notice;
  Timer? _timer;

  String? get notice => _notice;

  void show(String message) {
    _notice = message;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), clear);
    notifyListeners();
  }

  void clear() {
    if (_notice == null) return;
    _notice = null;
    _timer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// Banner notifikasi mengambang (di atas peta, bawah banner keselamatan).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.controller});

  final NoticeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final notice = controller.notice;
        if (notice == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          color: scheme.inverseSurface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: scheme.onInverseSurface),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    notice,
                    style: TextStyle(
                      color: scheme.onInverseSurface,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: controller.clear,
                  child: Icon(Icons.close,
                      size: 16, color: scheme.onInverseSurface),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
