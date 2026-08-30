import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../../models/book.dart';
import '../../models/photo_reference.dart';
import '../../services/photo_storage_service.dart';
import '../repositories/book_repository.dart';
import '../repositories/memory_repository.dart';

/// Coordinates a book's Firestore document with its own photos (cover +
/// birth/hospital photos, spec §7.1) and with cleaning up every photo file —
/// book-level and per-memory — when the book itself is deleted.
class BookService {
  BookService({
    required BookRepository bookRepository,
    required MemoryRepository memoryRepository,
    required PhotoStorageService photoStorage,
  }) // Fields stay private while constructor params stay public-named, so
  // an initializing formal (which would force them to share a name) isn't
  // usable here.
  : _bookRepository = bookRepository, // ignore: prefer_initializing_formals
    // ignore: prefer_initializing_formals
    _memoryRepository = memoryRepository,
    _photoStorage = photoStorage; // ignore: prefer_initializing_formals

  final BookRepository _bookRepository;
  final MemoryRepository _memoryRepository;
  final PhotoStorageService _photoStorage;

  /// Uploads any [newBirthPhotos], then writes the book. If the Firestore
  /// write fails after some photos were uploaded, those uploads are rolled
  /// back — same shape as [MemoryService.saveMemory].
  ///
  /// Pass [editingBook] to update it in place; omit it to create a new book.
  /// [coverPhotoKey] selects which photo is the cover: either an existing
  /// photo's `originalFileId`, or a new photo's [XFile.path]. If null (or
  /// not found), the first photo in the combined list becomes the cover.
  Future<void> saveBookInfo({
    Book? editingBook,
    required String childName,
    required DateTime birthDate,
    String? birthPlace,
    String? birthTime,
    double? birthWeightKg,
    double? birthHeightCm,
    String? birthStory,
    required List<PhotoReference> existingBirthPhotos,
    required List<XFile> newBirthPhotos,
    String? coverPhotoKey,
    void Function(int uploaded, int total)? onUploadProgress,
  }) async {
    final bookId = editingBook?.bookId ?? _bookRepository.reserveBookId();
    final uploadedPhotos = <PhotoReference>[];
    final uploadedByPath = <String, PhotoReference>{};

    try {
      for (var i = 0; i < newBirthPhotos.length; i++) {
        final photo = newBirthPhotos[i];

        final uploaded = await _photoStorage.uploadPhoto(
          bookId: bookId,
          photo: File(photo.path),
          fileName: '${DateTime.now().millisecondsSinceEpoch}-$i-${photo.name}',
        );

        uploadedPhotos.add(uploaded);
        uploadedByPath[photo.path] = uploaded;
        onUploadProgress?.call(i + 1, newBirthPhotos.length);
      }

      final allBirthPhotos = [...existingBirthPhotos, ...uploadedPhotos];

      final coverPhoto =
          _findByFileId(existingBirthPhotos, coverPhotoKey) ??
          (coverPhotoKey != null ? uploadedByPath[coverPhotoKey] : null) ??
          (allBirthPhotos.isNotEmpty ? allBirthPhotos.first : null);

      if (editingBook != null) {
        await _bookRepository.updateBookInfo(
          bookId: bookId,
          childName: childName,
          birthDate: birthDate,
          birthPlace: birthPlace,
          birthTime: birthTime,
          birthWeightKg: birthWeightKg,
          birthHeightCm: birthHeightCm,
          birthStory: birthStory,
          coverPhoto: coverPhoto,
          birthPhotos: allBirthPhotos,
        );

        final removedPhotos = editingBook.birthPhotos
            .where(
              (old) => !allBirthPhotos.any(
                (kept) => kept.originalFileId == old.originalFileId,
              ),
            )
            .toList();

        if (removedPhotos.isNotEmpty) {
          // The book is already saved without these photos; a cleanup
          // failure here shouldn't be reported as a failed save.
          try {
            await _photoStorage.deletePhotos(removedPhotos);
          } catch (_) {
            // Best-effort: worst case is a harmless orphaned file.
          }
        }
      } else {
        await _bookRepository.createBook(
          bookId: bookId,
          childName: childName,
          birthDate: birthDate,
          birthPlace: birthPlace,
          birthTime: birthTime,
          birthWeightKg: birthWeightKg,
          birthHeightCm: birthHeightCm,
          birthStory: birthStory,
          coverPhoto: coverPhoto,
          birthPhotos: allBirthPhotos,
        );
      }
    } catch (e) {
      if (uploadedPhotos.isNotEmpty) {
        try {
          await _photoStorage.deletePhotos(uploadedPhotos);
        } catch (_) {
          // The original error is what the caller needs to see.
        }
      }
      rethrow;
    }
  }

  PhotoReference? _findByFileId(List<PhotoReference> photos, String? fileId) {
    if (fileId == null) return null;

    for (final photo in photos) {
      if (photo.originalFileId == fileId) return photo;
    }

    return null;
  }

  Future<void> deleteBook(String bookId) async {
    final book = await _bookRepository.getBook(bookId);
    final memories = await _memoryRepository.getMemoriesOnce(bookId);

    final photosById = <String, PhotoReference>{
      for (final photo in memories.expand((memory) => memory.photoRefs))
        photo.originalFileId: photo,
      if (book != null)
        for (final photo in book.birthPhotos) photo.originalFileId: photo,
      if (book?.coverPhoto != null)
        book!.coverPhoto!.originalFileId: book.coverPhoto!,
    };

    await _bookRepository.deleteBook(bookId);

    if (photosById.isNotEmpty) {
      try {
        await _photoStorage.deletePhotos(photosById.values.toList());
      } catch (_) {
        // The book and its memories are already gone; a leftover Drive
        // file is a lesser harm than reporting a failed delete that
        // actually succeeded.
      }
    }
  }
}
