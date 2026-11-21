import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Cache payload API generik: kunci = "scope|parameter|...".
/// dipakai pasang surut, cuaca BMKG, gelombang, dan kedalaman.
@DataClassName('CachedPayload')
class CachedPayloads extends Table {
  TextColumn get cacheKey => text()();
  TextColumn get scope => text()();
  TextColumn get payload => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {cacheKey};
}

/// Waypoint (fondasi Builder 2).
@DataClassName('WaypointEntry')
class WaypointEntries extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Rute = urutan ID waypoint (JSON) + kecepatan rencana (fondasi Builder 2).
@DataClassName('RouteEntry')
class RouteEntries extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get waypointIdsJson => text()();
  RealColumn get speedKnots => real().withDefault(const Constant(8.0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Jejak perjalanan (fondasi Builder 2).
@DataClassName('TrackEntry')
class TrackEntries extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Titik jejak GPS (fondasi Builder 2).
@DataClassName('TrackPointEntry')
class TrackPointEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackId => text().references(TrackEntries, #id)();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  DateTimeColumn get recordedAt => dateTime()();
  RealColumn get speedKnots => real().nullable()();
}

@DriftDatabase(tables: [
  CachedPayloads,
  WaypointEntries,
  RouteEntries,
  TrackEntries,
  TrackPointEntries,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Untuk test / tooling: database in-memory.
  AppDatabase.forTesting() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'petalaut.db'));
      return NativeDatabase.createInBackground(file);
    });
  }

  // -- Cache payload generik --

  Future<CachedPayload?> getCached(String key) {
    return (select(cachedPayloads)
          ..where((t) => t.cacheKey.equals(key)))
        .getSingleOrNull();
  }

  Future<void> putCached({
    required String key,
    required String scope,
    required String payload,
    required DateTime fetchedAt,
  }) {
    return into(cachedPayloads).insertOnConflictUpdate(
      CachedPayloadsCompanion.insert(
        cacheKey: key,
        scope: scope,
        payload: payload,
        fetchedAt: fetchedAt,
      ),
    );
  }

  Future<void> deleteCached(String key) {
    return (delete(cachedPayloads)..where((t) => t.cacheKey.equals(key)))
        .go();
  }

  Future<void> clearScope(String scope) {
    return (delete(cachedPayloads)..where((t) => t.scope.equals(scope)))
        .go();
  }

  Future<void> clearAllCache() {
    return delete(cachedPayloads).go();
  }

  // -- Waypoint (fondasi Builder 2) --

  Future<List<WaypointEntry>> getWaypoints() => select(waypointEntries).get();

  Stream<List<WaypointEntry>> watchWaypoints() =>
      select(waypointEntries).watch();

  Future<void> insertWaypoint(WaypointEntriesCompanion entry) =>
      into(waypointEntries).insertOnConflictUpdate(entry);

  Future<void> deleteWaypoint(String id) =>
      (delete(waypointEntries)..where((t) => t.id.equals(id))).go();

  // -- Rute (fondasi Builder 2) --

  Future<List<RouteEntry>> getRoutes() => select(routeEntries).get();

  Stream<List<RouteEntry>> watchRoutes() => select(routeEntries).watch();

  Future<void> insertRoute(RouteEntriesCompanion entry) =>
      into(routeEntries).insertOnConflictUpdate(entry);

  Future<void> deleteRoute(String id) =>
      (delete(routeEntries)..where((t) => t.id.equals(id))).go();

  // -- Track (fondasi Builder 2) --

  Future<List<TrackEntry>> getTracks() => select(trackEntries).get();

  Stream<List<TrackEntry>> watchTracks() => select(trackEntries).watch();

  Future<void> insertTrack(TrackEntriesCompanion entry) =>
      into(trackEntries).insertOnConflictUpdate(entry);

  Future<void> insertTrackPoint(TrackPointEntriesCompanion entry) =>
      into(trackPointEntries).insert(entry);

  Future<List<TrackPointEntry>> getTrackPoints(String trackId) {
    return (select(trackPointEntries)
          ..where((t) => t.trackId.equals(trackId))
          ..orderBy([(t) => OrderingTerm(expression: t.recordedAt)]))
        .get();
  }

  Future<void> deleteTrack(String trackId) async {
    await (delete(trackPointEntries)
          ..where((t) => t.trackId.equals(trackId)))
        .go();
    await (delete(trackEntries)..where((t) => t.id.equals(trackId))).go();
  }
}
