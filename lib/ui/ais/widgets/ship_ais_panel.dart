import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/app_constants.dart';
import '../../../data/services/ship_ais_bluetooth_service.dart';
import '../../../data/services/ship_ais_service.dart';
import '../../../utils/result.dart';

/// Panel sumber AIS OFFLINE — AIS kapal sungguhan via WiFi (TCP/UDP
/// NMEA 0183) dan/atau Bluetooth Serial (SPP).
///
/// Ini adalah sisi OFFLINE dari pemilih sumber AIS (Internet /
/// Offline-kapal). Pemilih gabungan dipasang koordinator di
/// `ais_panel.dart` saat sintesis — panel ini dibuka dari sana
/// (atau dari Settings) dengan service WiFi yang sudah di-wire
/// di `dependencies.dart`.
///
/// [bluetoothService] opsional: seksi Bluetooth HANYA tampil bila
/// service-nya diberikan (butuh package + izin dari koordinator —
/// lihat `bluetooth_spp_transport.dart`). Bila null, panel murni
/// WiFi tanpa tombol mati.
Future<void> showShipAisPanel(
  BuildContext context, {
  required ShipAisService service,
  ShipAisBluetoothService? bluetoothService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ShipAisPanel(
      service: service,
      bluetoothService: bluetoothService,
    ),
  );
}

class ShipAisPanel extends StatefulWidget {
  const ShipAisPanel({
    super.key,
    required this.service,
    this.bluetoothService,
  });

  final ShipAisService service;
  final ShipAisBluetoothService? bluetoothService;

  @override
  State<ShipAisPanel> createState() => _ShipAisPanelState();
}

class _ShipAisPanelState extends State<ShipAisPanel> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  ShipAisProtocol _protocol = ShipAisProtocol.tcp;
  bool _autoReconnect = false;
  bool _prefilled = false;
  bool _testing = false;
  late final Future<ShipAisConfig> _configFuture;

  // Bluetooth (hanya bila service tersedia).
  ShipAisBluetoothDevice? _selectedBtDevice;
  final List<ShipAisBluetoothDevice> _discovered = [];
  StreamSubscription<ShipAisBluetoothDevice>? _discoverySubscription;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _configFuture = widget.service.loadConfig();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _discoverySubscription?.cancel();
    widget.bluetoothService?.cancelDiscovery();
    super.dispose();
  }

  void _prefill(ShipAisConfig config) {
    if (_prefilled) return;
    _prefilled = true;
    _hostController.text = config.host;
    _portController.text = config.port.toString();
    _protocol = config.protocol;
    _autoReconnect = config.autoReconnect;
  }

  ShipAisConfig _currentConfig() {
    return ShipAisConfig(
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 0,
      protocol: _protocol,
      autoReconnect: _autoReconnect,
    );
  }

  Future<void> _connectWifi() async {
    final config = _currentConfig();
    if (!config.isValid) {
      _snack('Host atau port tidak valid.');
      return;
    }
    final result = await widget.service.connect(config);
    if (!mounted) return;
    if (result is Error) {
      _snack('Gagal tersambung: ${result.error}');
    }
  }

  Future<void> _testConnection() async {
    final config = _currentConfig();
    if (!config.isValid) {
      _snack('Host atau port tidak valid.');
      return;
    }
    setState(() => _testing = true);
    final result = await widget.service.testConnection(config);
    if (!mounted) return;
    setState(() => _testing = false);
    switch (result) {
      case Ok(value: true):
        _snack('Data NMEA diterima — sambungan OK.');
      case Ok(value: false):
        _snack(
          'Tersambung tapi tidak ada data NMEA dalam 10 detik — '
          'periksa port / gateway.',
        );
      case Error(error: final error):
        _snack('Uji gagal: $error');
    }
  }

  Future<void> _toggleAutoReconnect(bool value) async {
    setState(() => _autoReconnect = value);
    await widget.service.saveConfig(_currentConfig());
  }

  Future<void> _toggleDiscovery() async {
    final bt = widget.bluetoothService;
    if (bt == null) return;
    if (_scanning) {
      await bt.cancelDiscovery();
      await _discoverySubscription?.cancel();
      if (mounted) setState(() => _scanning = false);
      return;
    }
    setState(() {
      _scanning = true;
      _discovered.clear();
    });
    _discoverySubscription = bt.startDiscovery().listen(
      (device) {
        if (!_discovered.contains(device)) {
          setState(() => _discovered.add(device));
        }
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
      onError: (_) {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  Future<void> _connectBluetooth() async {
    final bt = widget.bluetoothService;
    final device = _selectedBtDevice;
    if (bt == null || device == null) return;
    final result = await bt.connect(device.address);
    if (!mounted) return;
    if (result is Error) {
      _snack('Bluetooth gagal: ${result.error}');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.of(context).size.height * 0.85;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FutureBuilder<ShipAisConfig>(
          future: _configFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData) _prefill(snapshot.data!);
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(scheme),
                  const SizedBox(height: 12),
                  _sourceNote(scheme),
                  const SizedBox(height: 16),
                  _wifiSection(scheme),
                  if (widget.bluetoothService != null) ...[
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),
                    _bluetoothSection(scheme),
                  ],
                  const SizedBox(height: 16),
                  _safetyBox(scheme),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    return Row(
      children: [
        Icon(Icons.sailing, color: scheme.primary),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'AIS Kapal (Offline)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        StreamBuilder<ShipAisConnectionState>(
          stream: widget.service.connectionStateStream,
          initialData: widget.service.connectionState,
          builder: (context, snapshot) {
            final state =
                snapshot.data ?? ShipAisConnectionState.disconnected;
            final color = state == ShipAisConnectionState.connected
                ? Colors.green
                : state == ShipAisConnectionState.error
                    ? Colors.red
                    : scheme.primary;
            return Chip(
              label: Text(state.label),
              backgroundColor: color.withValues(alpha: 0.15),
              side: BorderSide(color: color),
            );
          },
        ),
      ],
    );
  }

  Widget _sourceNote(ColorScheme scheme) {
    return Text(
      'Data langsung dari antena AIS kapal sendiri lewat WiFi atau '
      'Bluetooth — bekerja tanpa internet di laut. Bila tersambung, '
      'sumber ini yang utama; AISStream internet menjadi cadangan.',
      style: TextStyle(color: scheme.onSurfaceVariant),
    );
  }

  Widget _wifiSection(ColorScheme scheme) {
    return StreamBuilder<ShipAisConnectionState>(
      stream: widget.service.connectionStateStream,
      initialData: widget.service.connectionState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? ShipAisConnectionState.disconnected;
        final busy = state == ShipAisConnectionState.connecting ||
            state == ShipAisConnectionState.reconnecting;
        final connected = state == ShipAisConnectionState.connected;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WiFi · NMEA 0183',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _hostController,
                    decoration: const InputDecoration(
                      labelText: 'Host / IP gateway',
                      hintText: '192.168.1.100',
                      border: OutlineInputBorder(),
                    ),
                    autocorrect: false,
                    enabled: !connected,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _portController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      hintText: '2000',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    enabled: !connected,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SegmentedButton<ShipAisProtocol>(
              segments: const [
                ButtonSegment(
                  value: ShipAisProtocol.tcp,
                  label: Text('TCP'),
                ),
                ButtonSegment(
                  value: ShipAisProtocol.udp,
                  label: Text('UDP'),
                ),
              ],
              selected: {_protocol},
              onSelectionChanged: connected
                  ? null
                  : (selected) => setState(
                        () => _protocol = selected.first,
                      ),
            ),
            if (_protocol == ShipAisProtocol.udp)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'UDP: HP mendengarkan di port ini — gateway mengirim '
                  'datagram ke IP HP. Host diabaikan, kecuali alamat '
                  'multicast (224.x–239.x).',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('Quark-Elec A027'),
                  onPressed: connected
                      ? null
                      : () => setState(() {
                            _hostController.text = '192.168.1.100';
                            _portController.text = '2000';
                            _protocol = ShipAisProtocol.tcp;
                          }),
                ),
                ActionChip(
                  label: const Text('Standar NMEA (10110)'),
                  onPressed: connected
                      ? null
                      : () => setState(() {
                            _portController.text = '10110';
                            _protocol = ShipAisProtocol.tcp;
                          }),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              title: const Text('Sambung ulang otomatis'),
              subtitle: const Text(
                'Mati secara default. Bila aktif, aplikasi menyambung '
                'lagi sendiri saat koneksi putus.',
              ),
              value: _autoReconnect,
              onChanged: _toggleAutoReconnect,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        (busy || connected) ? null : _connectWifi,
                    icon: const Icon(Icons.wifi),
                    label: Text(
                      busy ? 'Menghubungkan…' : 'SAMBUNGKAN',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (connected || busy)
                        ? () => widget.service.disconnect()
                        : null,
                    icon: const Icon(Icons.link_off),
                    label: const Text('PUTUSKAN KONEKSI'),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    (connected || busy || _testing) ? null : _testConnection,
                icon: const Icon(Icons.network_check),
                label: Text(
                  _testing ? 'Menguji… (maks 10 detik)' : 'Uji sambungan',
                ),
              ),
            ),
            const SizedBox(height: 12),
            _statsBox(widget.service.statsStream, widget.service.stats),
          ],
        );
      },
    );
  }

  Widget _bluetoothSection(ColorScheme scheme) {
    final bt = widget.bluetoothService!;
    return StreamBuilder<ShipAisConnectionState>(
      stream: bt.connectionStateStream,
      initialData: bt.connectionState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? ShipAisConnectionState.disconnected;
        final busy = state == ShipAisConnectionState.connecting ||
            state == ShipAisConnectionState.reconnecting;
        final connected = state == ShipAisConnectionState.connected;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bluetooth · Serial (SPP)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Jalur cadangan jarak pendek (±10 m) — mis. bridge '
              'Bluetooth ke output NMEA unit AIS.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<ShipAisBluetoothDevice>>(
              future: bt.bondedDevices(),
              builder: (context, bondedSnapshot) {
                final bonded = bondedSnapshot.data ?? const [];
                final all = <ShipAisBluetoothDevice>[
                  ...bonded,
                  ..._discovered.where((d) => !bonded.contains(d)),
                ];
                if (all.isEmpty) {
                  return Text(
                    bondedSnapshot.connectionState ==
                            ConnectionState.waiting
                        ? 'Memuat perangkat yang dipasangkan…'
                        : 'Belum ada perangkat Bluetooth. Pasangkan dulu '
                            'di Pengaturan HP, atau pindai di bawah.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  );
                }
                return DropdownButtonFormField<ShipAisBluetoothDevice>(
                  value: _selectedBtDevice != null &&
                          all.contains(_selectedBtDevice)
                      ? _selectedBtDevice
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Perangkat Bluetooth',
                    border: OutlineInputBorder(),
                  ),
                  items: all
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(d.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: connected
                      ? null
                      : (d) => setState(() => _selectedBtDevice = d),
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: connected ? null : _toggleDiscovery,
                    icon: Icon(
                      _scanning ? Icons.stop : Icons.bluetooth_searching,
                    ),
                    label: Text(_scanning ? 'Berhenti memindai' : 'Pindai'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (busy || connected || _selectedBtDevice == null)
                        ? null
                        : _connectBluetooth,
                    icon: const Icon(Icons.bluetooth),
                    label: const Text('SAMBUNGKAN'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (connected || busy)
                        ? () => bt.disconnect()
                        : null,
                    icon: const Icon(Icons.link_off),
                    label: const Text('PUTUSKAN'),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Sambung ulang otomatis (Bluetooth)'),
              value: bt.autoReconnect,
              onChanged: (value) {
                bt.setAutoReconnect(value);
                setState(() {});
              },
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            _statsBox(bt.statsStream, bt.stats),
          ],
        );
      },
    );
  }

  Widget _statsBox(Stream<ShipAisStats> stream, ShipAisStats initial) {
    return StreamBuilder<ShipAisStats>(
      stream: stream,
      initialData: initial,
      builder: (context, snapshot) {
        final stats = snapshot.data ?? initial;
        final last = stats.lastMessageAt;
        final lastText = last == null
            ? '—'
            : '${last.hour.toString().padLeft(2, '0')}:'
                '${last.minute.toString().padLeft(2, '0')}:'
                '${last.second.toString().padLeft(2, '0')}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kalimat diterima: ${stats.sentencesReceived} · '
              'Pesan ter-decode: ${stats.messagesDecoded} · '
              'Kapal terlihat: ${stats.vesselsSeen}',
            ),
            Text('Pesan terakhir: $lastText'),
            if (stats.lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Error terakhir: ${stats.lastError}',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _safetyBox(ColorScheme scheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        AppConstants.safetyWarning,
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}
