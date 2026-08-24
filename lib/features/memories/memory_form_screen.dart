import 'package:flutter/material.dart';

import '../../data/repositories/memory_repository.dart';
import '../../models/memory.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../models/photo_reference.dart';
import '../../services/google_drive_service.dart';
import '../../widgets/drive_image.dart';

enum _ExitChoice { keepEditing, saveAndExit, exitWithoutSaving }

class MemoryFormScreen extends StatefulWidget {
  final String bookId;
  final Memory? memory;

  const MemoryFormScreen({super.key, required this.bookId, this.memory});

  bool get isEditing => memory != null;

  @override
  State<MemoryFormScreen> createState() => _MemoryFormScreenState();
}

class _MemoryFormScreenState extends State<MemoryFormScreen> {
  final _textController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _googleDriveService = GoogleDriveService();
  final List<XFile> _newPhotos = [];
  final List<PhotoReference> _existingPhotos = [];
  final _memoryRepository = MemoryRepository();
  late String _initialText;
  late DateTime _initialDate;
  late List<String> _initialPhotoIds;

  bool _allowPop = false;

  DateTime? _memoryDate;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    if (widget.memory != null) {
      _textController.text = widget.memory!.text;
      _memoryDate = widget.memory!.memoryDate;
      _existingPhotos.addAll(widget.memory!.photoRefs);
    }
    _initialText = _textController.text.trim();
    _initialDate = widget.memory?.memoryDate ?? DateTime.now();
    _initialPhotoIds = _existingPhotos
        .map((photo) => photo.originalFileId)
        .toList();
  }

  Future<void> _deleteMemory() async {
    if (!widget.isEditing || _isLoading) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete memory?'),
          content: const Text(
            'This memory will be permanently removed from the book.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _memoryRepository.deleteMemory(
        bookId: widget.bookId,
        memoryId: widget.memory!.memoryId,
      );

      if (!mounted) return;

      _popWithoutCheck();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Could not delete memory: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
              onPressed: () {
                Navigator.pop(context, _ExitChoice.keepEditing);
              },
              child: const Text('Keep Editing'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, _ExitChoice.exitWithoutSaving);
              },
              child: const Text('Exit Without Saving'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, _ExitChoice.saveAndExit);
              },
              child: const Text('Save and Exit'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    switch (choice) {
      case _ExitChoice.saveAndExit:
        final saved = await _saveMemory(exitAfterSave: false);

        if (saved) {
          _popWithoutCheck();
        }
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

    setState(() {
      _allowPop = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  bool get _hasUnsavedChanges {
    if (_textController.text.trim() != _initialText) {
      return true;
    }

    final currentDate = _memoryDate ?? _initialDate;

    if (currentDate.year != _initialDate.year ||
        currentDate.month != _initialDate.month ||
        currentDate.day != _initialDate.day) {
      return true;
    }

    if (_newPhotos.isNotEmpty) {
      return true;
    }

    final currentPhotoIds = _existingPhotos
        .map((photo) => photo.originalFileId)
        .toList();

    if (currentPhotoIds.length != _initialPhotoIds.length) {
      return true;
    }

    for (var i = 0; i < currentPhotoIds.length; i++) {
      if (currentPhotoIds[i] != _initialPhotoIds[i]) {
        return true;
      }
    }

    return false;
  }

  Future<void> _pickPhotos() async {
    final photos = await _imagePicker.pickMultiImage();

    if (photos.isEmpty) return;

    setState(() {
      _newPhotos.addAll(photos);
    });
  }

  Future<void> _selectDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _memoryDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (selectedDate != null) {
      setState(() {
        _memoryDate = selectedDate;
      });
    }
  }

  Future<bool> _saveMemory({bool exitAfterSave = true}) async {
    final text = _textController.text.trim();

    if (text.isEmpty && _newPhotos.isEmpty && _existingPhotos.isEmpty) {
      setState(() {
        _errorMessage = 'Add some text or at least one photo';
      });
      return false;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final uploadedPhotos = <PhotoReference>[];

    try {
      for (var i = 0; i < _newPhotos.length; i++) {
        final photo = _newPhotos[i];

        final uploaded = await _googleDriveService.uploadPhoto(
          bookId: widget.bookId,
          photo: File(photo.path),
          fileName: '${DateTime.now().millisecondsSinceEpoch}-$i-${photo.name}',
        );

        uploadedPhotos.add(uploaded);
      }

      final allPhotos = [..._existingPhotos, ...uploadedPhotos];

      if (widget.isEditing) {
        await _memoryRepository.updateMemory(
          bookId: widget.bookId,
          memoryId: widget.memory!.memoryId,
          text: text,
          memoryDate: _memoryDate!,
          photoRefs: allPhotos,
        );
      } else {
        await _memoryRepository.createMemory(
          bookId: widget.bookId,
          text: text,
          memoryDate: _memoryDate,
          photoRefs: allPhotos,
        );
      }

      if (!mounted) return false;

      if (exitAfterSave) {
        _popWithoutCheck();
      }

      return true;
    } catch (e) {
      if (!mounted) return false;

      setState(() {
        _errorMessage = e.toString();
      });

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
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
        appBar: AppBar(title: Text(widget.isEditing ? 'Memory' : 'Add Memory')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Show selected photos visually before saving
            // Put this above the text field:
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Photos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            if (_existingPhotos.isNotEmpty)
              ..._existingPhotos.map(
                (photo) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: DriveImage(
                          key: ValueKey(photo.originalFileId),
                          fileId: photo.originalFileId,
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                        ),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: IconButton.filled(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  setState(() {
                                    _existingPhotos.remove(photo);
                                  });
                                },
                          icon: const Icon(Icons.close),
                          tooltip: 'Remove photo from memory',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_newPhotos.isNotEmpty)
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _newPhotos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final photo = _newPhotos[index];

                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(photo.path),
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: IconButton(
                            onPressed: () {
                              setState(() {
                                _newPhotos.removeAt(index);
                              });
                            },
                            icon: const Icon(Icons.cancel),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            OutlinedButton.icon(
              onPressed: _isLoading ? null : _pickPhotos,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Add Photos'),
            ),

            const SizedBox(height: 20),

            // So while creating a memory, you can already visually see every newly selected photo.
            TextField(
              controller: _textController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'What happened?',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _memoryDate == null
                    ? 'Date: Today'
                    : 'Date: ${_memoryDate!.day}/'
                          '${_memoryDate!.month}/'
                          '${_memoryDate!.year}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDate,
            ),
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveMemory,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : Text(widget.isEditing ? 'Save Changes' : 'Save Memory'),
              ),
            ),
            if (widget.isEditing) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _isLoading ? null : _deleteMemory,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete Memory'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
