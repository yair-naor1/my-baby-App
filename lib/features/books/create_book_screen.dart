import 'package:flutter/material.dart';

import '../../data/repositories/book_repository.dart';

class CreateBookScreen extends StatefulWidget {
  const CreateBookScreen({super.key});

  @override
  State<CreateBookScreen> createState() => _CreateBookScreenState();
}

class _CreateBookScreenState extends State<CreateBookScreen> {
  final _childNameController = TextEditingController();
  final _bookRepository = BookRepository();

  DateTime? _birthDate;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _selectBirthDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (selectedDate != null) {
      setState(() {
        _birthDate = selectedDate;
      });
    }
  }

  Future<void> _createBook() async {
    final childName = _childNameController.text.trim();

    if (childName.isEmpty || _birthDate == null) {
      setState(() {
        _errorMessage = 'Please enter a name and birth date';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _bookRepository.createBook(
        childName: childName,
        birthDate: _birthDate!,
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
    _childNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Book'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _childNameController,
              decoration: const InputDecoration(
                labelText: "Child's name",
              ),
            ),

            const SizedBox(height: 24),

            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _birthDate == null
                    ? 'Select birth date'
                    : '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectBirthDate,
            ),

            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _isLoading ? null : _createBook,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Create Book'),
            ),
          ],
        ),
      ),
    );
  }
}