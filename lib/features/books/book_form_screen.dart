import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/repositories/book_repository.dart';
import '../../data/repositories/memory_repository.dart';
import '../../data/services/book_service.dart';
import '../../models/book.dart';
import '../../models/photo_reference.dart';
import '../../services/google_drive_service.dart';
import '../../utils/date_format.dart';
import '../../utils/error_messages.dart';
import '../../widgets/drive_image.dart';

enum _ExitChoice { keepEditing, saveAndExit, exitWithoutSaving }

/// Create a book (spec §7.1) or edit its info afterwards — same form for
/// both, following the Add/Edit Memory pattern (§7.4): pass [book] to edit
/// it in place, omit it to create a new one.
class BookFormScreen extends StatefulWidget {
  const BookFormScreen({super.key, this.book, this.bookService});

  final Book? book;
  final BookService? bookService;

  bool get isEditing => book != null;

  @override
  State<BookFormScreen> createState() => _BookFormScreenState();
}

class _BookFormScreenState extends State<BookFormScreen> {
  final _childNameController = TextEditingController();
  final _birthPlaceController = TextEditingController();
  final _birthWeightController = TextEditingController();
  final _birthHeightController = TextEditingController();
  final _birthStoryController = TextEditingController();
  final _imagePicker = ImagePicker();

  final List<XFile> _newBirthPhotos = [];
  final List<PhotoReference> _existingBirthPhotos = [];

  late final BookService _bookService =
      widget.bookService ??
      BookService(
        bookRepository: BookRepository(),
        memoryRepository: MemoryRepository(),
        photoStorage: GoogleDriveService(),
      );

  DateTime? _birthDate;
  TimeOfDay? _birthTime;
  String? _coverKey;
  bool _allowPop = false;
  bool _isLoading = false;
  String? _uploadProgressText;
  String? _errorMessage;

  late final String _initialChildName;
  late final DateTime? _initialBirthDate;

  @override
  void initState() {
    super.initState();

    final book = widget.book;

    if (book != null) {
      _childNameController.text = book.childName;
      _birthPlaceController.text = book.birthPlace ?? '';
      _birthWeightController.text = book.birthWeightKg?.toString() ?? '';
      _birthHeightController.text = book.birthHeightCm?.toString() ?? '';
      _birthStoryController.text = book.birthStory ?? '';
      _birthDate = book.birthDate;
      _birthTime = _parseTime(book.birthTime);
      _existingBirthPhotos.addAll(book.birthPhotos);
      _coverKey = book.coverPhoto?.originalFileId;
    }

    _initialChildName = _childNameController.text.trim();
    _initialBirthDate = _birthDate;
  }

  TimeOfDay? _parseTime(String? value) {
    if (value == null) return null;

    final parts = value.split(':');
    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  bool get _hasUnsavedChanges {
    if (_childNameController.text.trim() != _initialChildName) return true;

    final currentDate = _birthDate;
    final initialDate = _initialBirthDate;

    if ((currentDate == null) != (initialDate == null)) return true;

    if (currentDate != null &&
        initialDate != null &&
        (currentDate.year != initialDate.year ||
            currentDate.month != initialDate.month ||
            currentDate.day != initialDate.day)) {
      return true;
    }

    if (_newBirthPhotos.isNotEmpty) return true;

    final book = widget.book;
    if (book == null) {
      return _birthPlaceController.text.trim().isNotEmpty ||
          _birthWeightController.text.trim().isNotEmpty ||
          _birthHeightController.text.trim().isNotEmpty ||
          _birthStoryController.text.trim().isNotEmpty ||
          _birthTime != null ||
          _existingBirthPhotos.isNotEmpty;
    }

    if (_birthPlaceController.text.trim() != (book.birthPlace ?? '')) {
      return true;
    }
    if (_birthStoryController.text.trim() != (book.birthStory ?? '')) {
      return true;
    }
    if (_existingBirthPhotos.length != book.birthPhotos.length) return true;
    if (_coverKey != book.coverPhoto?.originalFileId) return true;

    return false;
  }

  Future<void> _handleExit() async {
    if (_isLoading) return;

    if (!_hasUnsavedChanges) {
      _popWithoutCheck();
      return;
    }

    final choice = await showDialog<_ExitChoice>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Unsaved changes'),
          content: const Text(
            'You have unsaved changes. Are you sure you want to exit?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _ExitChoice.keepEditing),
              child: const Text('Keep Editing'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, _ExitChoice.exitWithoutSaving),
              child: const Text('Exit Without Saving'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _ExitChoice.saveAndExit),
              child: const Text('Save and Exit'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    switch (choice) {
      case _ExitChoice.saveAndExit:
        final saved = await _save(exitAfterSave: false);
        if (saved) _popWithoutCheck();
        return;
      case _ExitChoice.exitWithoutSaving:
        _popWithoutCheck();
        return;
      case _ExitChoice.keepEditing:
      case null:
        return;
    }
  }

  void _popWithoutCheck() {
    if (!mounted) return;

    setState(() => _allowPop = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _selectBirthDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (selectedDate != null) {
      setState(() => _birthDate = selectedDate);
    }
  }

  Future<void> _selectBirthTime() async {
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: _birthTime ?? TimeOfDay.now(),
    );

    if (selectedTime != null) {
      setState(() => _birthTime = selectedTime);
    }
  }

  Future<void> _pickPhotos() async {
    final photos = await _imagePicker.pickMultiImage();
    if (photos.isEmpty) return;

    setState(() {
      _newBirthPhotos.addAll(photos);
      // First photo added becomes the cover by default if none is set yet.
      _coverKey ??= photos.first.path;
    });
  }

  double? _parseDouble(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  Future<bool> _save({bool exitAfterSave = true}) async {
    final childName = _childNameController.text.trim();

    if (childName.isEmpty || _birthDate == null) {
      setState(() => _errorMessage = 'Please enter a name and birth date');
      return false;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _uploadProgressText = null;
    });

    try {
      await _bookService.saveBookInfo(
        editingBook: widget.book,
        childName: childName,
        birthDate: _birthDate!,
        birthPlace: _birthPlaceController.text.trim().isEmpty
            ? null
            : _birthPlaceController.text.trim(),
        birthTime: _birthTime == null ? null : _formatTime(_birthTime!),
        birthWeightKg: _parseDouble(_birthWeightController.text),
        birthHeightCm: _parseDouble(_birthHeightController.text),
        birthStory: _birthStoryController.text.trim().isEmpty
            ? null
            : _birthStoryController.text.trim(),
        existingBirthPhotos: _existingBirthPhotos,
        newBirthPhotos: _newBirthPhotos,
        coverPhotoKey: _coverKey,
        onUploadProgress: (uploaded, total) {
          if (!mounted || total <= 1) return;

          setState(() {
            _uploadProgressText = 'Uploading photo $uploaded of $total…';
          });
        },
      );

      if (!mounted) return false;

      if (exitAfterSave) _popWithoutCheck();

      return true;
    } catch (e) {
      if (!mounted) return false;

      setState(() => _errorMessage = friendlyErrorMessage(e));

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _uploadProgressText = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _childNameController.dispose();
    _birthPlaceController.dispose();
    _birthWeightController.dispose();
    _birthHeightController.dispose();
    _birthStoryController.dispose();
    super.dispose();
  }

  Widget _photoThumbnail({
    required String key,
    required Widget image,
    required VoidCallback onRemove,
  }) {
    final isCover = _coverKey == key;

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 100, height: 100, child: image),
        ),
        if (isCover)
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Cover',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 11,
                ),
              ),
            ),
          )
        else
          Positioned(
            left: 2,
            bottom: 2,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Set as cover',
              onPressed: () => setState(() => _coverKey = key),
              icon: const Icon(Icons.star_border, color: Colors.white),
            ),
          ),
        Positioned(
          right: 2,
          top: 2,
          child: IconButton.filled(
            visualDensity: VisualDensity.compact,
            onPressed: _isLoading ? null : onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isEditing ? 'Edit Book Info' : 'Create Book'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _childNameController,
              decoration: const InputDecoration(labelText: "Child's name"),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _birthDate == null
                    ? 'Select birth date'
                    : formatShortDate(_birthDate!),
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectBirthDate,
            ),
            const Divider(height: 32),
            Text(
              'The following are optional — add what you\'d like.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _birthPlaceController,
              decoration: const InputDecoration(labelText: 'Birth place'),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _birthTime == null
                    ? 'Birth time'
                    : 'Birth time: ${_formatTime(_birthTime!)}',
              ),
              trailing: const Icon(Icons.access_time),
              onTap: _selectBirthTime,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _birthWeightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Weight (kg)',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _birthHeightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Height (cm)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _birthStoryController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Birth story',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'Birth / hospital photos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap the star on a photo to make it the cover shown for this '
              'book.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._existingBirthPhotos.map((photo) {
                  final imageId = photo.thumbnailFileId ?? photo.originalFileId;

                  return _photoThumbnail(
                    key: photo.originalFileId,
                    image: DriveImage(
                      key: ValueKey(imageId),
                      fileId: imageId,
                      fit: BoxFit.cover,
                    ),
                    onRemove: () {
                      setState(() {
                        _existingBirthPhotos.remove(photo);
                        if (_coverKey == photo.originalFileId) {
                          _coverKey = null;
                        }
                      });
                    },
                  );
                }),
                ..._newBirthPhotos.map((photo) {
                  return _photoThumbnail(
                    key: photo.path,
                    image: Image.file(File(photo.path), fit: BoxFit.cover),
                    onRemove: () {
                      setState(() {
                        _newBirthPhotos.remove(photo);
                        if (_coverKey == photo.path) _coverKey = null;
                      });
                    },
                  );
                }),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _pickPhotos,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Add Photos'),
            ),
            if (_uploadProgressText != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(_uploadProgressText!),
                ],
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Text(widget.isEditing ? 'Save Changes' : 'Create Book'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
