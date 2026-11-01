import 'dart:io';

import 'package:flutter/material.dart';

import 'hike_recording.dart';
import 'trip_photos.dart';

const _forest = Color(0xFF3E8967);
const _ink = Color(0xFF292D2B);
const _paper = Color(0xFFF0F7F2);

class TripAlbumPage extends StatefulWidget {
  const TripAlbumPage({
    super.key,
    required this.trip,
    required this.store,
    this.picker,
  });

  final SavedHike trip;
  final TripPhotoStore store;
  final TripPhotoPicker? picker;

  @override
  State<TripAlbumPage> createState() => _TripAlbumPageState();
}

class _TripAlbumPageState extends State<TripAlbumPage> {
  late final TripPhotoPicker _picker;
  late final String _tripKey;
  List<TripPhoto> _photos = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _picker = widget.picker ?? ImagePickerTripPhotoPicker();
    _tripKey = tripKeyFor(widget.trip.startedAt);
    _load();
  }

  Future<void> _load() async {
    try {
      final photos = await widget.store.loadAll();
      if (!mounted) return;
      setState(() {
        _photos = photos.where((photo) => photo.tripKey == _tripKey).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Your photos could not be loaded.');
    }
  }

  Future<void> _addPhoto(TripPhotoSource source) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await _picker.pick(source);
      if (picked == null) return;
      await widget.store.add(
        tripKey: _tripKey,
        photo: picked,
        trailId: widget.trip.plannedTrailId,
        trailName: widget.trip.plannedTrailName,
      );
      await _load();
      if (!mounted) return;
      _showMessage('Photo saved to this trip.');
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        source == TripPhotoSource.camera
            ? 'The photo could not be taken. Check camera access and try again.'
            : 'The photo could not be added from your library.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePhoto(TripPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: const Text(
          'It will be removed from this trip and from your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB5483E),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.store.remove(photo);
      await _load();
      if (!mounted) return;
      _showMessage('Photo deleted.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('That photo could not be deleted.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _openPhoto(TripPhoto photo) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.file(
                  File(photo.path),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'This photo file is missing.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatMoment(photo.capturedAt),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _deletePhoto(photo);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFF1A79C),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close photo',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final title = trip.plannedTrailName ?? 'Trip album';
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        title: const Text(
          'Trip album',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Add from gallery',
            onPressed: _busy ? null : () => _addPhoto(TripPhotoSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _addPhoto(TripPhotoSource.camera),
        backgroundColor: _forest,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.photo_camera_rounded),
        label: const Text('Take photo'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontFamily: 'Georgia',
                fontSize: 26,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_formatDate(trip.startedAt)} · ${(trip.distanceMeters / 1000).toStringAsFixed(2)} km · ${trip.points.length} GPS points',
              style: const TextStyle(color: Color(0xFF777E79), fontSize: 12),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: _paper,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.photo_camera_back_outlined,
                    color: _forest,
                    size: 17,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _photos.isEmpty
                          ? 'Photos stay on this device with this trip.'
                          : '${_photos.length} ${_photos.length == 1 ? 'photo' : 'photos'} kept on this device with this trip.',
                      style: const TextStyle(
                        color: Color(0xFF4B544E),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_photos.isEmpty)
              _EmptyAlbum(onTakePhoto: () => _addPhoto(TripPhotoSource.camera))
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _photos.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemBuilder: (context, index) {
                  final photo = _photos[index];
                  return _PhotoTile(
                    photo: photo,
                    onTap: () => _openPhoto(photo),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.onTap});

  final TripPhoto photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Image.file(
          File(photo.path),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Color(0xFF9AA29C),
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyAlbum extends StatelessWidget {
  const _EmptyAlbum({required this.onTakePhoto});

  final VoidCallback onTakePhoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          const Icon(Icons.photo_outlined, color: Color(0xFF9AA29C), size: 34),
          const SizedBox(height: 10),
          const Text(
            'No photos in this album yet',
            style: TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Take a photo of the view, the summit or the trailhead — it is saved with this trip, not in a shared gallery.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF777E79),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onTakePhoto,
            icon: const Icon(Icons.photo_camera_rounded, size: 17),
            label: const Text('Take a photo'),
            style: FilledButton.styleFrom(
              backgroundColor: _forest,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

String _formatMoment(DateTime date) {
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${_formatDate(date)} · $hour:$minute';
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
