class PhotoReference {
  final String provider;
  final String originalFileId;
  final String? thumbnailFileId;
  final String ownerUid;
  final int? width;
  final int? height;

  const PhotoReference({
    required this.provider,
    required this.originalFileId,
    required this.ownerUid,
    this.thumbnailFileId,
    this.width,
    this.height,
  });

  Map<String, dynamic> toMap() {
    return {
      'provider': provider,
      'originalFileId': originalFileId,
      'thumbnailFileId': thumbnailFileId,
      'ownerUid': ownerUid,
      'width': width,
      'height': height,
    };
  }

  factory PhotoReference.fromMap(Map<String, dynamic> map) {
    return PhotoReference(
      provider: map['provider'] as String,
      originalFileId: (map['originalFileId'] ?? map['fileId']) as String,
      thumbnailFileId: map['thumbnailFileId'] as String?,
      ownerUid: map['ownerUid'] as String,
      width: map['width'] as int?,
      height: map['height'] as int?,
    );
  }
}
