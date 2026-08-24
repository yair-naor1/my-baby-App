import 'package:flutter/material.dart';

import '../../data/repositories/memory_repository.dart';

class AddMemoryScreen extends StatefulWidget {
  final String bookId;

  const AddMemoryScreen({
    super.key,
    required this.bookId,
  });

  @override
  State<AddMemoryScreen> createState() => _AddMemoryScreenState();
}

class _AddMemoryScreenState extends State<AddMemoryScreen> {
  final _textController = TextEditingController();
  final _memoryRepository = MemoryRepository();

  DateTime? _memoryDate;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _selectDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _memoryDate ?? DateTime.now(),
      firstDate: DateTime(2000),
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
      await _memoryRepository.createMemory(
        bookId: widget.bookId,
        text: text,
        memoryDate: _memoryDate,
      );

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
        title: const Text('Add Memory'),
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
                    : 'Date: ${_memoryDate!.day}/${_memoryDate!.month}/${_memoryDate!.year}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDate,
            ),

            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveMemory,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Save Memory'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}