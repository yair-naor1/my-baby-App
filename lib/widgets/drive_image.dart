import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/google_drive_service.dart';

class DriveImage extends StatefulWidget {
  final String fileId;
  final double? width;
  final double? height;
  final BoxFit fit;

  const DriveImage({
    super.key,
    required this.fileId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<DriveImage> createState() => _DriveImageState();
}

class _DriveImageState extends State<DriveImage> {
  final _driveService = GoogleDriveService();

  late final Future<Uint8List> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = _driveService.downloadPhoto(widget.fileId);
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
