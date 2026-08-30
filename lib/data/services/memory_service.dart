import 'dart:io';

import 'package:image_picker/image_picker.dart';

import '../../models/memory.dart';
import '../../models/photo_reference.dart';
import '../../services/photo_storage_service.dart';
import '../repositories/memory_repository.dart';

/// Coordinates a memory's Firestore document with its photo files.
///
/// [MemoryRepository] only knows about Firestore; [PhotoStorageService] only
/// knows about photo storage. This class is the one place that has to know
/// about both, so screens don't have to orchestrate durability/cleanup logic
/// themselves. See docs/CODE_REVIEW.md §4/§8 for the bugs this fixes:
/// orphaned Drive files on delete/edit, and uploads left dangling when the
/// Firestore write that should reference them fails.
class MemoryService {
  MemoryService({
    required PhotoStorageService photoStorage,
    required MemoryRepository memoryRepository,
  }) // Fields stay private while constructor params stay public-named, so
  // an initializing formal (which would force them to share a name) isn't
  // usable here.
  : _photoStorage = photoStorage, // ignore: prefer_initializing_formals
    // ignore: prefer_initializing_formals
    _memoryRepository = memoryRepository;

  final PhotoStorageService _photoStorage;
  final MemoryRepository _memoryRepository;

  /// Uploads any [newPhotos], then writes the memory. If the Firestore write
  /// fails after some photos were uploaded, those uploads are rolled back
  /// (deleted) rather than left orphaned — so a retry re-uploads cleanly
  /// instead of creating duplicates.
  ///
  /// Pass [editingMemory] to update it in place; omit it to create a new
  /// memory. When editing, any photo present in [editingMemory] but absent
  /// from [existingPhotos] is treated as removed by the user and is deleted
  /// from storage only after the updated document has saved successfully.
  Future<void> saveMemory({
    required String bookId,
    required String text,
    DateTime? memoryDate,
    required List<PhotoReference> existingPhotos,
    required List<XFile> newPhotos,
    Memory? editingMemory,
    void Function(int uploaded, int total)? onUploadProgress,
  }) async {
    final uploadedPhotos = <PhotoReference>[];

    try {
      for (var i = 0; i < newPhotos.length; i++) {
        final photo = newPhotos[i];

        final uploaded = await _photoStorage.uploadPhoto(
          bookId: bookId,
          photo: File(photo.path),
          fileName: '${DateTime.now().millisecondsSinceEpoch}-$i-${photo.name}',
        );

        uploadedPhotos.add(uploaded);
        onUploadProgress?.call(i + 1, newPhotos.length);
      }

      final allPhotos = [...existingPhotos, ...uploadedPhotos];

      if (editingMemory != null) {
        await _memoryRepository.updateMemory(
          bookId: bookId,
          memoryId: editingMemory.memoryId,
          text: text,
          memoryDate: memoryDate ?? editingMemory.memoryDate,
          photoRefs: allPhotos,
        );

        final removedPhotos = editingMemory.photoRefs
            .where(
              (old) => !allPhotos.any(
                (kept) => kept.originalFileId == old.originalFileId,
              ),
            )
            .toList();

        if (removedPhotos.isNotEmpty) {
          // The memory is already saved without these photos; a cleanup
          // failure here shouldn't be reported as a failed save.
          try {
            await _photoStorage.deletePhotos(removedPhotos);
          } catch (_) {
            // Best-effort: worst case is a harmless orphaned file, not a
            // dangling reference.
          }
        }
      } else {
        await _memoryRepository.createMemory(
          bookId: bookId,
          text: text,
          memoryDate: memoryDate,
          photoRefs: allPhotos,
        );
      }
    } catch (e) {
      if (uploadedPhotos.isNotEmpty) {
        try {
          await _photoStorage.deletePhotos(uploadedPhotos);
        } catch (_) {
          // The original error is what the caller needs to see; a failed
          // rollback attempt shouldn't replace it.
        }
      }
      rethrow;
    }
  }

  /// Deletes the memory's Firestore document first, then its photo files —
  /// that order means a failure while deleting photos never leaves a
  /// document referencing files that no longer exist.
  Future<void> deleteMemory({
    required String bookId,
    required Memory memory,
  }) async {
    await _memoryRepository.deleteMemory(
      bookId: bookId,
      memoryId: memory.memoryId,
    );

    if (memory.photoRefs.isNotEmpty) {
      try {
        await _photoStorage.deletePhotos(memory.photoRefs);
      } catch (_) {
        // The memory is already gone from the timeline; a leftover Drive
        // file is a lesser harm than reporting a failed delete that
        // actually succeeded.
      }
    }
  }
}
