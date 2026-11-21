import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/waypoint.dart';
import '../local/app_database.dart';

/// CRUD waypoint / rute / track (fondasi Builder 2 — UI lengkap oleh
/// Builder 2). Pemetaan entri Drift -> model domain dilakukan di sini,
/// menjaga model domain tetap murni.
class NavigationRepository {
  NavigationRepository({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  // -- Waypoint --

  Stream<List<Waypoint>> watchWaypoints() {
    return _db.watchWaypoints().map(
          (entries) => entries.map(_toWaypoint).toList(),
        );
  }

  Future<List<Waypoint>> getWaypoints() async {
    final entries = await _db.getWaypoints();
    return entries.map(_toWaypoint).toList();
  }

  Future<void> saveWaypoint(Waypoint waypoint) {
    return _db.insertWaypoint(WaypointEntriesCompanion.insert(
      id: waypoint.id,
      name: waypoint.name,
      latitude: waypoint.latitude,
      longitude: waypoint.longitude,
      createdAt: waypoint.createdAt ?? DateTime.now(),
    ));
  }

  Future<void> deleteWaypoint(String id) => _db.deleteWaypoint(id);

  Waypoint _toWaypoint(WaypointEntry e) => Waypoint(
        id: e.id,
        name: e.name,
        latitude: e.latitude,
        longitude: e.longitude,
        createdAt: e.createdAt,
      );

  // -- Rute --

  Stream<List<RoutePlan>> watchRoutes() {
    return _db.watchRoutes().map(
          (entries) => entries.map(_toRoute).toList(),
        );
  }

  Future<List<RoutePlan>> getRoutes() async {
    final entries = await _db.getRoutes();
    return entries.map(_toRoute).toList();
  }

  Future<void> saveRoute(RoutePlan route) {
    return _db.insertRoute(RouteEntriesCompanion.insert(
      id: route.id,
      name: route.name,
      waypointIdsJson: jsonEncode(route.waypointIds),
      speedKnots: Value(route.speedKnots),
      createdAt: route.createdAt ?? DateTime.now(),
    ));
  }

  Future<void> deleteRoute(String id) => _db.deleteRoute(id);

  RoutePlan _toRoute(RouteEntry e) {
    List<String> ids = const [];
    try {
      final decoded = jsonDecode(e.waypointIdsJson);
      if (decoded is List) {
        ids = decoded.map((v) => '$v').toList();
      }
    } catch (_) {
      // JSON rusak -> rute kosong (tetap tampil, bisa dihapus).
    }
    return RoutePlan(
      id: e.id,
      name: e.name,
      waypointIds: ids,
      speedKnots: e.speedKnots,
      createdAt: e.createdAt,
    );
  }

  // -- Track --

  Stream<List<Track>> watchTracks() {
    return _db.watchTracks().map(
          (entries) => entries
              .map((e) => Track(
                    id: e.id,
                    name: e.name,
                    startedAt: e.startedAt,
                    endedAt: e.endedAt,
                  ))
              .toList(),
        );
  }

  Future<void> saveTrack(Track track) {
    return _db.insertTrack(TrackEntriesCompanion.insert(
      id: track.id,
      name: track.name,
      startedAt: track.startedAt,
      endedAt: Value(track.endedAt),
    ));
  }

  Future<void> addTrackPoint(String trackId, TrackPoint point) {
    return _db.insertTrackPoint(TrackPointEntriesCompanion.insert(
      trackId: trackId,
      latitude: point.latitude,
      longitude: point.longitude,
      recordedAt: point.recordedAt,
      speedKnots: Value(point.speedKnots),
    ));
  }

  Future<Track?> getTrackWithPoints(String trackId) async {
    final tracks = await _db.getTracks();
    TrackEntry? entry;
    for (final t in tracks) {
      if (t.id == trackId) {
        entry = t;
        break;
      }
    }
    if (entry == null) return null;
    final points = await _db.getTrackPoints(trackId);
    return Track(
      id: entry.id,
      name: entry.name,
      startedAt: entry.startedAt,
      endedAt: entry.endedAt,
      points: points
          .map((p) => TrackPoint(
                latitude: p.latitude,
                longitude: p.longitude,
                recordedAt: p.recordedAt,
                speedKnots: p.speedKnots,
              ))
          .toList(),
    );
  }

  Future<void> deleteTrack(String trackId) => _db.deleteTrack(trackId);
}
