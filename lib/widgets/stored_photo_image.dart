import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/photo_storage_service.dart';
import '../services/r2_photo_storage_service.dart';

/// Small in-memory cache so scrolling a timeline doesn't re-download the
/// same thumbnail every time `ListView.builder` recycles the widget.
/// Capped so it can't grow unbounded over a long session.
class _PhotoBytesCache {
  static const _maxEntries = 150;
  static final Map<String, Uint8List> _entries = {};

  static Uint8List? get(String fileId) => _entries[fileId];

  static void put(String fileId, Uint8List bytes) {
    if (_entries.length >= _maxEntries && !_entries.containsKey(fileId)) {
      _entries.remove(_entries.keys.first);
    }
    _entries[fileId] = bytes;
  }
}

class StoredPhotoImage extends StatefulWidget {
  final String fileId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final PhotoStorageService? photoStorage;

  const StoredPhotoImage({
    super.key,
    required this.fileId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.photoStorage,
  });

  @override
  State<StoredPhotoImage> createState() => _StoredPhotoImageState();
}

class _StoredPhotoImageState extends State<StoredPhotoImage> {
  late final PhotoStorageService _photoStorage =
      widget.photoStorage ?? R2PhotoStorageService();

  late Future<Uint8List> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = _loadPhoto(widget.fileId);
  }

  @override
  void didUpdateWidget(covariant StoredPhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.fileId != widget.fileId) {
      _imageFuture = _loadPhoto(widget.fileId);
    }
  }

  Future<Uint8List> _loadPhoto(String fileId) async {
    final cached = _PhotoBytesCache.get(fileId);

    if (cached != null) return cached;

    final bytes = await _photoStorage.downloadPhoto(fileId);

    _PhotoBytesCache.put(fileId, bytes);

    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            width: widget.width,
            height: widget.height ?? 180,
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return SizedBox(
            width: widget.width,
            height: widget.height ?? 180,
            child: const Center(child: Icon(Icons.broken_image)),
          );
        }

        return Image.memory(
          snapshot.data!,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
        );
      },
    );
  }
}
