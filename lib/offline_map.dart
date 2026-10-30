import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;

const tourOfflineMapName = 'Tour du Portillon';
const tourOfflineMapStyle = maplibre.MapLibreStyles.openfreemapLiberty;

class OfflineMapRegion {
  const OfflineMapRegion({required this.id, required this.isComplete});

  final int id;
  final bool isComplete;
}

abstract interface class OfflineMapRepository {
  Future<OfflineMapRegion?> findTourRegion();
  Future<int> downloadTourRegion({
    required void Function(double progress, int downloadedBytes) onProgress,
    required void Function() onComplete,
    required void Function(String message) onError,
  });
  Future<void> deleteRegion(int id);
}

class MapLibreOfflineMapRepository implements OfflineMapRepository {
  static const _metadataKey = 'trailoffRegion';
  static const _maxTiles = 3000;

  static final _definition = maplibre.OfflineRegionDefinition(
    bounds: maplibre.LatLngBounds(
      southwest: const maplibre.LatLng(42.66, 0.47),
      northeast: const maplibre.LatLng(42.73, 0.56),
    ),
    minZoom: 9,
    maxZoom: 14,
    mapStyleUrl: tourOfflineMapStyle,
  );

  @override
  Future<OfflineMapRegion?> findTourRegion() async {
    final regions = await maplibre.getListOfRegions();
    for (final region in regions) {
      if (region.metadata[_metadataKey] != tourOfflineMapName) continue;
      final status = await maplibre.getOfflineRegionStatus(region.id);
      return OfflineMapRegion(id: region.id, isComplete: status.isComplete);
    }
    return null;
  }

  @override
  Future<int> downloadTourRegion({
    required void Function(double progress, int downloadedBytes) onProgress,
    required void Function() onComplete,
    required void Function(String message) onError,
  }) async {
    await maplibre.setOfflineTileCountLimit(_maxTiles);
    final region = await maplibre.downloadOfflineRegion(
      _definition,
      metadata: {_metadataKey: tourOfflineMapName},
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
