import 'package:flutter/material.dart';

import '../../data/repositories/memory_repository.dart';
import '../../models/memory.dart';

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
    }
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

    if (text.isEmpty) {
      setState(() {
        _errorMessage = 'Please write something';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (widget.isEditing) {
        await _memoryRepository.updateMemory(
          bookId: widget.bookId,
          memoryId: widget.memory!.memoryId,
          text: text,
          memoryDate: _memoryDate!,
        );
      } else {
        await _memoryRepository.createMemory(
          bookId: widget.bookId,
          text: text,
          memoryDate: _memoryDate,
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
