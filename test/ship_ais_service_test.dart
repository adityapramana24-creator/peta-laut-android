import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peta_laut/data/services/nmea_ais_parser.dart';
import 'package:peta_laut/data/services/ship_ais_service.dart';
import 'package:peta_laut/utils/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service AIS kapal WiFi — diuji dengan socket loopback nyata
/// (flutter test berjalan di VM host, dart:io tersedia).
///
/// Kalimat NMEA di bawah sama dengan yang diuji di
/// nmea_ais_parser_test.dart (nilai harapan terverifikasi vs pyais).
void main() {
  const gpsdType1 =
      '!AIVDM,1,1,,B,177KQJ5000G?tO`K>RA1wUbN0TKH,0*5C';
  const gpsdType5Frag1 =
      '!AIVDM,2,1,3,B,55P5TL01VIaAL@7WKO@mBplU@<PDhh000000001S;AJ::4A80?4i@E53,0*3E';
  const gpsdType5Frag2 = '!AIVDM,2,2,3,B,1@0000000000000,2*55';
  const aivdoType18 =
      '!AIVDO,1,1,,,B39i>1000nTu;gQAlBj:wwS5kP06,0*5D';

  late ShipAisService service;

  setUp(() {
    service = ShipAisService();
    addTearDown(service.dispose);
  });

  group('pemrosesan baris (tanpa socket)', () {
    test('handleLine: satu kalimat -> satu hasil + statistik', () async {
      final results = <ShipAisParseResult>[];
      service.resultsStream.listen(results.add);
      service.handleLine(gpsdType1);
      await Future<void>.delayed(Duration.zero);
      expect(results, hasLength(1));
      expect(results.first.mmsi, 477553000);
      expect(results.first.updated.latitude, closeTo(47.5828, 0.0001));
      expect(service.stats.sentencesReceived, 1);
      expect(service.stats.messagesDecoded, 1);
      expect(service.stats.vesselsSeen, 1);
      expect(service.stats.lastMessageAt, isNotNull);
    });

    test('handleLine: multi-fragmen dirakit lewat dua baris', () async {
      final results = <ShipAisParseResult>[];
      service.resultsStream.listen(results.add);
      service.handleLine(gpsdType5Frag1);
      await Future<void>.delayed(Duration.zero);
      expect(results, isEmpty); // belum lengkap
      service.handleLine(gpsdType5Frag2);
      await Future<void>.delayed(Duration.zero);
      expect(results, hasLength(1));
      expect(results.first.mmsi, 369190000);
      expect(results.first.updated.name, 'MT.MITCHELL');
      expect(service.stats.sentencesReceived, 2);
      expect(service.stats.messagesDecoded, 1);
    });

    test('handleLine: AIVDO masuk stream own-ship juga', () async {
      final ownShips = <int>[];
      service.ownShipStream.listen((v) => ownShips.add(v.mmsi));
      service.handleLine(aivdoType18);
      service.handleLine(gpsdType1); // AIVDM — bukan own-ship
      await Future<void>.delayed(Duration.zero);
      expect(ownShips, [211570180]);
    });

    test('handleLine: kalimat rusak menambah kalimat, bukan pesan', () {
      service.handleLine(gpsdType1);
      service.handleLine('!AIVDM,1,1,,B,177KQJ5000G?tO`K>RA1wUbN0TKH,0*5D');
      service.handleLine('sampah');
      expect(service.stats.sentencesReceived, 3);
      expect(service.stats.messagesDecoded, 1);
      expect(service.stats.vesselsSeen, 1);
    });

    test('handleBytes: kalimat terbelah dua chunk tetap ter-decode',
        () async {
      final results = <ShipAisParseResult>[];
      service.resultsStream.listen(results.add);
      final bytes = ascii.encode('$gpsdType1\r\n');
      service.handleBytes(bytes.sublist(0, 20));
      await Future<void>.delayed(Duration.zero);
      expect(results, isEmpty);
      service.handleBytes(bytes.sublist(20));
      await Future<void>.delayed(Duration.zero);
      expect(results, hasLength(1));
      expect(results.first.mmsi, 477553000);
    });

    test('handleBytes: beberapa kalimat dalam satu chunk', () async {
      final results = <ShipAisParseResult>[];
      service.resultsStream.listen(results.add);
      service.handleBytes(
        ascii.encode('$gpsdType1\r\n$aivdoType18\r\n'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(results, hasLength(2));
      expect(service.stats.vesselsSeen, 2);
    });
  });

  group('konfigurasi', () {
    test('default = Quark-Elec A027 (192.168.1.100:2000 TCP)', () {
      expect(service.config.host, '192.168.1.100');
      expect(service.config.port, 2000);
      expect(service.config.protocol, ShipAisProtocol.tcp);
      expect(service.config.autoReconnect, isFalse);
    });

    test('save/load round-trip via SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final withPrefs = ShipAisService(prefs: prefs);
      addTearDown(withPrefs.dispose);
      await withPrefs.saveConfig(
        const ShipAisConfig(
          host: '10.0.0.5',
          port: 10110,
          protocol: ShipAisProtocol.tcp,
          autoReconnect: true,
        ),
      );
      // Instance baru membaca nilai tersimpan.
      final reloaded = ShipAisService(prefs: prefs);
      addTearDown(reloaded.dispose);
      final config = await reloaded.loadConfig();
      expect(config.host, '10.0.0.5');
      expect(config.port, 10110);
      expect(config.autoReconnect, isTrue);
    });

    test('konfigurasi tidak valid ditolak connect()', () async {
      final result = await service.connect(
        const ShipAisConfig(host: '', port: 0),
      );
      expect(result, isA<Error<void>>());
      expect(
        service.connectionState,
        ShipAisConnectionState.error,
      );
      expect(service.stats.lastError, isNotNull);
    });
  });

  group('TCP loopback', () {
    test('tersambung, menerima kalimat, lalu putus manual', () async {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(server.close);
      final clientCompleter = Completer<Socket>();
      server.listen(clientCompleter.complete);

      final states = <ShipAisConnectionState>[];
      service.connectionStateStream.listen(states.add);
      final results = <ShipAisParseResult>[];
      service.resultsStream.listen(results.add);

      final result = await service.connect(
        ShipAisConfig(
          host: '127.0.0.1',
          port: server.port,
          protocol: ShipAisProtocol.tcp,
        ),
      );
      expect(result, isA<Ok<void>>());
      expect(service.isConnected, isTrue);
      // Pompa antrean event sekali: event 'connected' di-emit ke
      // broadcast stream secara asinkron dan belum tentu terkirim
      // saat connect() kembali (event 'connecting' sempat terkirim
      // karena ada jeda I/O Socket.connect di antaranya). Pola yang
      // sama dipakai test lain di file ini sebelum assert atas nilai
      // dari stream. Bukan bug state — field isConnected sudah true.
      await Future<void>.delayed(Duration.zero);
      expect(states, contains(ShipAisConnectionState.connected));

      final client = await clientCompleter.future;
      addTearDown(client.close);
      client.writeln(gpsdType1);
      client.writeln(aivdoType18);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(results.map((r) => r.mmsi), [477553000, 211570180]);
      expect(service.stats.messagesDecoded, 2);

      await service.disconnect();
      expect(service.connectionState, ShipAisConnectionState.disconnected);
    });

    test('host tidak merespons -> error, bukan hang', () async {
      // Port 1 di loopback hampir pasti tertutup.
      final result = await service.connect(
        const ShipAisConfig(
          host: '127.0.0.1',
          port: 1,
          protocol: ShipAisProtocol.tcp,
        ),
      );
      expect(result, isA<Error<void>>());
      expect(service.connectionState, ShipAisConnectionState.error);
      expect(service.stats.lastError, isNotNull);
    });

    test('server menutup koneksi + auto-reconnect MATI -> error, diam',
        () async {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(server.close);
      final clientCompleter = Completer<Socket>();
      server.listen(clientCompleter.complete);

      final states = <ShipAisConnectionState>[];
      service.connectionStateStream.listen(states.add);
      await service.connect(
        ShipAisConfig(
          host: '127.0.0.1',
          port: server.port,
          protocol: ShipAisProtocol.tcp,
          autoReconnect: false,
        ),
      );
      expect(service.isConnected, isTrue);
      final client = await clientCompleter.future;
      await client.close();
      // Tunggu status error muncul (maks 5 detik).
      final sawError = Completer<void>();
      service.connectionStateStream.listen((s) {
        if (s == ShipAisConnectionState.error && !sawError.isCompleted) {
          sawError.complete();
        }
      });
      await sawError.future.timeout(const Duration(seconds: 5));
      expect(
        states,
        isNot(contains(ShipAisConnectionState.reconnecting)),
      );
      // Diam: tidak ada percobaan sambung ulang setelah 2 detik.
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(service.connectionState, ShipAisConnectionState.error);
    });
  });

  group('UDP loopback', () {
    test('menerima datagram NMEA di port listen', () async {
      // Cari port bebas lewat bind sementara.
      final probe = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = probe.port;
      probe.close();

      final result = await service.connect(
        ShipAisConfig(
          host: '127.0.0.1',
          port: port,
          protocol: ShipAisProtocol.udp,
        ),
      );
      expect(result, isA<Ok<void>>());
      expect(service.isConnected, isTrue);
      expect(service.localPort, port);

      final results = <ShipAisParseResult>[];
      service.resultsStream.listen(results.add);
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(sender.close);
      sender.send(
        ascii.encode('$gpsdType1\r\n'),
        InternetAddress.loopbackIPv4,
        port,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(results, hasLength(1));
      expect(results.first.mmsi, 477553000);
    });
  });

  group('testConnection', () {
    test('TCP + data NMEA -> Ok(true)', () async {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(server.close);
      server.listen((client) {
        addTearDown(client.close);
        client.writeln(gpsdType1);
      });
      final result = await service.testConnection(
        ShipAisConfig(host: '127.0.0.1', port: server.port),
      );
      expect(result, isA<Ok<bool>>());
      expect((result as Ok<bool>).value, isTrue);
    });

    test('TCP diam -> Ok(false)', () async {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(server.close);
      server.listen((client) => addTearDown(client.close));
      final result = await service.testConnection(
        ShipAisConfig(host: '127.0.0.1', port: server.port),
        timeout: const Duration(seconds: 1),
      );
      expect(result, isA<Ok<bool>>());
      expect((result as Ok<bool>).value, isFalse);
    });

    test('TCP tidak tersambung -> Error', () async {
      final result = await service.testConnection(
        const ShipAisConfig(host: '127.0.0.1', port: 1),
      );
      expect(result, isA<Error<bool>>());
    });

    test('ditolak saat sesi aktif', () async {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(server.close);
      server.listen((client) => addTearDown(client.close));
      await service.connect(
        ShipAisConfig(host: '127.0.0.1', port: server.port),
      );
      expect(service.isConnected, isTrue);
      final result = await service.testConnection(
        ShipAisConfig(host: '127.0.0.1', port: server.port),
      );
      expect(result, isA<Error<bool>>());
    });
  });
}
