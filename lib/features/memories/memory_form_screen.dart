import 'package:flutter/material.dart';

import '../../data/repositories/memory_repository.dart';
import '../../models/memory.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../models/photo_reference.dart';
import '../../services/google_drive_service.dart';

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

  Future<void> _saveMemory() async {
    final text = _textController.text.trim();

    if (text.isEmpty && _newPhotos.isEmpty && _existingPhotos.isEmpty) {
      setState(() {
        _errorMessage = 'Add some text or at least one photo';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uploadedPhotos = <PhotoReference>[];

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

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString();
      });
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Memory' : 'Add Memory'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
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
          ],
        ),
      ),
    );
  }
}
