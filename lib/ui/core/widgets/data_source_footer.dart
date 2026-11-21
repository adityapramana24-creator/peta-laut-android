import 'package:flutter/material.dart';

import '../../../utils/formatters.dart';

/// Kaki panel data: sumber + waktu ambil + penanda data lama + refresh.
class DataSourceFooter extends StatelessWidget {
  const DataSourceFooter({
    super.key,
    required this.source,
    this.fetchedAt,
    this.isStale = false,
    this.onRefresh,
    this.refreshing = false,
  });

  final String source;
  final DateTime? fetchedAt;
  final bool isStale;
  final VoidCallback? onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sumber: $source', style: style),
                if (fetchedAt != null)
                  Text(
                    'Diambil ${IdFormat.dateTimeShort(IdFormat.toWib(fetchedAt!.toUtc()))} WIB'
                    '${isStale ? ' · DATA LAMA (offline)' : ''}',
                    style: style.copyWith(
                      color: isStale ? scheme.error : style.color,
                      fontWeight: isStale ? FontWeight.bold : null,
                    ),
                  ),
              ],
            ),
          ),
          if (onRefresh != null)
            IconButton(
              tooltip: 'Muat ulang',
              iconSize: 20,
              onPressed: refreshing ? null : onRefresh,
              icon: refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
        ],
      ),
    );
  }
}
