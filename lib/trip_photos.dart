import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where a photo comes from. Both paths go through the same picker interface so
/// the album can be driven by a fake in tests.
enum TripPhotoSource { camera, gallery }

class PickedTripPhoto {
  const PickedTripPhoto(this.path);

  final String path;
}

abstract interface class TripPhotoPicker {
  /// Returns the chosen image's path, or null when the hiker cancels.
  Future<PickedTripPhoto?> pick(TripPhotoSource source);
}

class ImagePickerTripPhotoPicker implements TripPhotoPicker {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<PickedTripPhoto?> pick(TripPhotoSource source) async {
    final file = await _picker.pickImage(
      source: source == TripPhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2000,
    );
    return file == null ? null : PickedTripPhoto(file.path);
  }
}

/// A photo kept on the device and attached to one saved trip.
class TripPhoto {
  const TripPhoto({
    required this.id,
    required this.path,
    required this.tripKey,
    required this.capturedAt,
    this.trailId,
    this.trailName,
  });

  final String id;
  final String path;

  /// Identifies the saved hike this photo belongs to.
  final String tripKey;
  final DateTime capturedAt;
  final String? trailId;
  final String? trailName;

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'tripKey': tripKey,
    'capturedAt': capturedAt.toIso8601String(),
    'trailId': trailId,
    'trailName': trailName,
  };

  factory TripPhoto.fromJson(Map<String, dynamic> json) => TripPhoto(
    id: json['id'] as String,
    path: json['path'] as String,
    tripKey: json['tripKey'] as String,
    capturedAt: DateTime.parse(json['capturedAt'] as String),
    trailId: json['trailId'] as String?,
    trailName: json['trailName'] as String?,
  );
}

/// Stable identifier for a saved trip, derived from when it started.
String tripKeyFor(DateTime startedAt) => startedAt.toUtc().toIso8601String();

abstract interface class TripPhotoStore {
  Future<List<TripPhoto>> loadAll();
  Future<TripPhoto> add({
    required String tripKey,
    required PickedTripPhoto photo,
    String? trailId,
    String? trailName,
  });
  Future<void> remove(TripPhoto photo);
}

/// Keeps copies of captured photos in the app's documents directory and their
/// metadata in shared preferences, so albums survive app restarts without any
/// network or account.
class FileTripPhotoStore implements TripPhotoStore {
  static const _metadataKey = 'trailoff.trip_photos.v1';
  static const _directoryName = 'trip-photos';

  @override
  Future<List<TripPhoto>> loadAll() async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList(_metadataKey) ?? const [];
    final photos =
        stored
            .map(
              (entry) =>
                  TripPhoto.fromJson(jsonDecode(entry) as Map<String, dynamic>),
            )
            .toList()
          ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return List.unmodifiable(photos);
  }

  @override
  Future<TripPhoto> add({
    required String tripKey,
    required PickedTripPhoto photo,
    String? trailId,
    String? trailName,
  }) async {
    final capturedAt = DateTime.now();
    final directory = await _photoDirectory();
    final extension = _extensionOf(photo.path);
    final id = 'photo-${capturedAt.microsecondsSinceEpoch}';
    final destination = File('${directory.path}/$id$extension');
    await File(photo.path).copy(destination.path);

    final stored = TripPhoto(
      id: id,
      path: destination.path,
      tripKey: tripKey,
      capturedAt: capturedAt,
      trailId: trailId,
      trailName: trailName,
    );
    final preferences = await SharedPreferences.getInstance();
    final entries = preferences.getStringList(_metadataKey) ?? <String>[];
    entries.insert(0, jsonEncode(stored.toJson()));
    await preferences.setStringList(_metadataKey, entries);
    return stored;
  }

  @override
  Future<void> remove(TripPhoto photo) async {
    final file = File(photo.path);
    if (await file.exists()) await file.delete();
    final preferences = await SharedPreferences.getInstance();
    final entries = preferences.getStringList(_metadataKey) ?? <String>[];
    entries.removeWhere((entry) {
      final decoded = jsonDecode(entry) as Map<String, dynamic>;
      return decoded['id'] == photo.id;
    });
    await preferences.setStringList(_metadataKey, entries);
  }

  Future<Directory> _photoDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/$_directoryName');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '.jpg' : name.substring(dot);
  }
}
