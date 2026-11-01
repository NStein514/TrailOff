import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

import 'trail_catalogue.dart';

const tourOfflineMapStyle = maplibre.MapLibreStyles.openfreemapLiberty;

/// A map area that can be kept on the device. The hiker's planned trail decides
/// which area is current, so downloads follow the route they picked.
class OfflineArea {
  const OfflineArea({
    required this.id,
    required this.name,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  /// A box around the trailhead, roughly 11 km tall by 11 km wide. The catalogue
  /// has no route geometry yet, so this is an area around the start rather than
  /// a per-route trace.
  factory OfflineArea.forTrail(Trail trail) => OfflineArea(
    id: trail.id,
    name: trail.name,
    south: trail.trailheadLatitude - _latitudeSpan,
    north: trail.trailheadLatitude + _latitudeSpan,
    west: trail.trailheadLongitude - _longitudeSpan,
    east: trail.trailheadLongitude + _longitudeSpan,
  );

  static const _latitudeSpan = 0.05;
  static const _longitudeSpan = 0.065;

  final String id;
  final String name;
  final double south;
  final double west;
  final double north;
  final double east;
}

/// The whole tour, used while no trail is planned.
const defaultOfflineArea = OfflineArea(
  id: 'tour-du-portillon',
  name: 'Tour du Portillon',
  south: 42.66,
  west: 0.47,
  north: 42.73,
  east: 0.56,
);

class OfflineMapRegion {
  const OfflineMapRegion({required this.id, required this.isComplete});

  final int id;
  final bool isComplete;
}

abstract interface class OfflineMapRepository {
  Future<OfflineMapRegion?> findRegion(OfflineArea area);
  Future<int> downloadRegion({
    required OfflineArea area,
    required void Function(double progress, int downloadedBytes) onProgress,
    required void Function() onComplete,
    required void Function(String message) onError,
  });
  Future<void> deleteRegion(int id);
}

class MapLibreOfflineMapRepository implements OfflineMapRepository {
  static const _metadataKey = 'trailoffArea';
  static const _legacyMetadataKey = 'trailoffRegion';
  static const _maxTiles = 3000;

  @override
  Future<OfflineMapRegion?> findRegion(OfflineArea area) async {
    final regions = await maplibre.getListOfRegions();
    for (final region in regions) {
      if (!_isArea(region.metadata, area)) continue;
      final status = await maplibre.getOfflineRegionStatus(region.id);
      return OfflineMapRegion(id: region.id, isComplete: status.isComplete);
    }
    return null;
  }

  /// The tour used to be stored under its display name, so an existing download
  /// is still recognised instead of being downloaded twice.
  bool _isArea(Map<String, dynamic> metadata, OfflineArea area) {
    if (metadata[_metadataKey] == area.id) return true;
    return area.id == defaultOfflineArea.id &&
        metadata[_legacyMetadataKey] == defaultOfflineArea.name;
  }

  @override
  Future<int> downloadRegion({
    required OfflineArea area,
    required void Function(double progress, int downloadedBytes) onProgress,
    required void Function() onComplete,
    required void Function(String message) onError,
  }) async {
    await maplibre.setOfflineTileCountLimit(_maxTiles);
    final definition = maplibre.OfflineRegionDefinition(
      bounds: maplibre.LatLngBounds(
        southwest: maplibre.LatLng(area.south, area.west),
        northeast: maplibre.LatLng(area.north, area.east),
      ),
      minZoom: 9,
      maxZoom: 14,
      mapStyleUrl: tourOfflineMapStyle,
    );
    final region = await maplibre.downloadOfflineRegion(
      definition,
      metadata: {_metadataKey: area.id},
      onEvent: (event) {
        if (event is maplibre.InProgress) {
          onProgress(event.progress, event.completedResourceSize);
        } else if (event is maplibre.Success) {
          onComplete();
        } else if (event is maplibre.Error) {
          onError(event.cause.message ?? 'Map download failed.');
        }
      },
    );
    return region.id;
  }

  @override
  Future<void> deleteRegion(int id) => maplibre.deleteOfflineRegion(id);
}
