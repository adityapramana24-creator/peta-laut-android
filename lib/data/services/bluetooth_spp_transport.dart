// ═════════════════════════════════════════════════════════════════════
//  FILE TERGATE — JANGAN PUSH TANPA ENTRI PUBSPEC + IZIN MANIFEST.
// ═════════════════════════════════════════════════════════════════════
//  File ini mengimpor package `flutter_bluetooth_serial_plus`
//  (Bluetooth Classic SPP di Android). Sampai koordinator menambahkan:
//    1. pubspec.yaml:
//         flutter_bluetooth_serial_plus: ^0.5.7
//    2. android/app/src/main/AndroidManifest.xml:
//         <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
//         <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
//         <uses-permission android:name="android.permission.BLUETOOTH" />
//         <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
//         <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
//       (ACCESS_FINE_LOCATION sudah ada; BLUETOOTH/BLUETOOTH_ADMIN
//       untuk Android ≤ 11; SCAN/CONNECT untuk Android 12+.)
//  ...file ini membuat `flutter analyze` / CI GAGAL. Itu sengaja:
//  WiFi TCP/UDP (ship_ais_service.dart) tetap ship tanpa file ini.
//  Bila koordinator memutuskan menunda Bluetooth, HAPUS file ini
//  dan panel menyembunyikan seksi Bluetooth sendiri (service null).
//
//  Status paket (dicek 21 Nov 2026 di pub.dev): fork terawat dari
//  flutter_bluetooth_serial (tidak dirawat sejak ~2021), versi
//  0.5.7, update terakhir 28 Okt 2026, API sama dengan plugin asli.
//  Dua panggilan di bawah (getBondedDevices, startDiscovery)
//  mengikuti API asli yang diwarisi fork — CI analyze akan
//  mengonfirmasi namanya; bila berubah, sesuaikan di sini saja.
// ═════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';

import 'ship_ais_bluetooth_service.dart';

/// Transport SPP konkret memakai `flutter_bluetooth_serial_plus`.
///
/// Catatan: `flutter_blue_plus` TIDAK bisa dipakai — plugin itu
/// hanya BLE, bukan SPP klasik (ditegaskan di README-nya).
class FlutterBluetoothSerialPlusTransport
    implements ShipAisBluetoothTransport {
  BluetoothConnection? _connection;

  @override
  Stream<Uint8List> get input {
    final connection = _connection;
    if (connection == null) {
      throw StateError('Bluetooth belum tersambung.');
    }
    return connection.input;
  }

  @override
  bool get isConnected => _connection != null;

  @override
  Future<void> connect(String address) async {
    // Meminta izin runtime (Android 12+: BLUETOOTH_SCAN +
    // BLUETOOTH_CONNECT; Android ≤ 11: lokasi) + memastikan
    // Bluetooth menyala.
    final granted =
        await FlutterBluetoothSerial.instance.ensurePermissions();
    if (!granted) {
      throw StateError(
        'Izin Bluetooth ditolak. Aktifkan "Perangkat terdekat" '
        'di pengaturan aplikasi.',
      );
    }
    await disconnect();
    _connection = await BluetoothConnection.toAddress(address);
  }

  @override
  Future<void> disconnect() async {
    final connection = _connection;
    _connection = null;
    await connection?.finish();
  }

  @override
  Future<List<ShipAisBluetoothDevice>> bondedDevices() async {
    final devices =
        await FlutterBluetoothSerial.instance.getBondedDevices();
    return devices
        .map(
          (d) => ShipAisBluetoothDevice(address: d.address, name: d.name),
        )
        .toList();
  }

  @override
  Stream<ShipAisBluetoothDevice> startDiscovery() {
    return FlutterBluetoothSerial.instance.startDiscovery().map(
          (r) => ShipAisBluetoothDevice(
            address: r.device.address,
            name: r.device.name,
          ),
        );
  }

  @override
  Future<void> cancelDiscovery() async {
    await FlutterBluetoothSerial.instance.cancelDiscovery();
  }
}
