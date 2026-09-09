import 'package:flutter/material.dart';

import '../../data/repositories/memory_repository.dart';
import '../../data/services/memory_service.dart';
import '../../models/memory.dart';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../../models/photo_reference.dart';
import '../../services/ai_text_enhancement_service.dart';
import '../../services/r2_photo_storage_service.dart';
import '../../utils/date_format.dart';
import '../../utils/error_messages.dart';
import '../../widgets/hebrew_aware_date_picker.dart';
import '../../widgets/photo_viewer_screen.dart';
import '../../widgets/stored_photo_image.dart';

enum _ExitChoice { keepEditing, saveAndExit, exitWithoutSaving }

class MemoryFormScreen extends StatefulWidget {
  final String bookId;
  final Memory? memory;
  final MemoryService? memoryService;

  /// 'male', 'female', or null — passed through to AI text enhancement so
  /// Hebrew grammatical gender comes out right. Never shown in this UI.
  final String? childGender;

  /// The owning book's date-display preference (spec §7.1/§13) —
  /// 'gregorian', 'hebrew', or 'both'. Only affects how the picked date is
  /// *shown* here, never the date picker itself.
  final String dateDisplay;

  /// The owning book's language preference (spec §7.1/§13) — 'en' or 'he'.
  /// Drives every piece of this screen's own chrome (labels, buttons,
  /// dialogs); never applied to the memory text itself, which the parent
  /// writes in whatever language they choose.
  final String language;

  const MemoryFormScreen({
    super.key,
    required this.bookId,
    this.memory,
    this.memoryService,
    this.childGender,
    this.dateDisplay = 'gregorian',
    this.language = 'en',
  });

  bool get isEditing => memory != null;

  @override
  State<MemoryFormScreen> createState() => _MemoryFormScreenState();
}

class _MemoryFormScreenState extends State<MemoryFormScreen> {
  final _textController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _aiTextEnhancementService = AiTextEnhancementService();
  bool _isEnhancingText = false;
  final List<XFile> _newPhotos = [];
  final List<PhotoReference> _existingPhotos = [];
  late final MemoryService _memoryService =
      widget.memoryService ??
      MemoryService(
        photoStorage: R2PhotoStorageService(),
        memoryRepository: MemoryRepository(),
      );
  late String _initialText;
  late DateTime _initialDate;
  late List<String> _initialPhotoIds;

  bool _allowPop = false;

  DateTime? _memoryDate;
  bool _isLoading = false;
  String? _uploadProgressText;
  String? _errorMessage;

  bool get _isHebrew => widget.language == 'he';

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

  double _galleryPhotoWidth(PhotoReference photo) {
    const rowHeight = 90.0;

    if (photo.width == null ||
        photo.height == null ||
        photo.width == 0 ||
        photo.height == 0) {
      return rowHeight;
    }

    final aspectRatio = photo.width! / photo.height!;

    return (rowHeight * aspectRatio).clamp(65.0, 160.0);
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
          title: Text(_isHebrew ? 'שינויים שלא נשמרו' : 'Unsaved changes'),
          content: Text(
            _isHebrew
                ? 'יש לכם שינויים שלא נשמרו. האם אתם בטוחים שברצונכם לצאת?'
                : 'You have unsaved changes. Are you sure you want to exit?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, _ExitChoice.keepEditing);
              },
              child: Text(_isHebrew ? 'המשך עריכה' : 'Keep Editing'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, _ExitChoice.exitWithoutSaving);
              },
              child: Text(
                _isHebrew ? 'יציאה ללא שמירה' : 'Exit Without Saving',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, _ExitChoice.saveAndExit);
              },
              child: Text(_isHebrew ? 'שמירה ויציאה' : 'Save and Exit'),
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

    // Only worth reading EXIF off the first photo of the memory: once a
    // date is already set (picked by the user, loaded from an existing
    // memory, or accepted from an earlier photo), later adds must never
    // move the memory's date, silently or otherwise.
    final shouldInferDate =
        _memoryDate == null && _newPhotos.isEmpty && _existingPhotos.isEmpty;

    final inferredDate = shouldInferDate
        ? await _photoCapturedDate(photos.first)
        : null;

    if (!mounted) return;

    setState(() {
      _newPhotos.addAll(photos);
    });

    if (inferredDate == null) return;

    final useInferredDate = await _confirmInferredDate(inferredDate);

    if (useInferredDate && mounted) {
      setState(() {
        _memoryDate = inferredDate;
      });
    }
  }

  /// Asks before applying a date read from a photo's EXIF data — never
  /// silent, since a photo pulled from the gallery for a memory written
  /// today (or the outlier in a freshly-taken batch) would otherwise set
  /// the wrong date with no visible cause.
  Future<bool> _confirmInferredDate(DateTime date) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_isHebrew ? 'להשתמש בתאריך התמונה?' : 'Use photo date?'),
          content: Text(
            _isHebrew
                ? 'התמונה צולמה בתאריך '
                      '${formatDate(date, widget.dateDisplay)}. להשתמש בתאריך '
                      'זה עבור הזיכרון?'
                : 'This photo was taken on ${formatDate(date, widget.dateDisplay)}. '
                      'Use this date for the memory?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_isHebrew ? 'לא, השאירו היום' : 'No, keep today'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                _isHebrew ? 'השתמשו בתאריך התמונה' : 'Use photo date',
              ),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  /// Reads the EXIF capture date off a picked photo, spec-free: falls back
  /// silently to null (leaving the memory's date to default to today, same
  /// as before this existed) for screenshots, downloaded images, or any
  /// photo missing/malformed EXIF data. Clamped to "not in the future"
  /// since [_selectDate]'s picker caps at `DateTime.now()` — a bad camera
  /// clock must never leave `_memoryDate` in a state that picker can't open.
  Future<DateTime?> _photoCapturedDate(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) return null;

      final exif = decoded.exif;
      final raw =
          exif.exifIfd['DateTimeOriginal']?.toString() ??
          exif.imageIfd['DateTime']?.toString();

      if (raw == null) return null;

      final match = RegExp(
        r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
      ).firstMatch(raw);

      if (match == null) return null;

      final captured = DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );

      if (captured.isAfter(DateTime.now())) return null;

      return captured;
    } catch (_) {
      return null;
    }
  }

  void _openPhotoViewer({
    required int itemCount,
    required int initialIndex,
    required Widget Function(BuildContext context, int index) imageBuilder,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          itemCount: itemCount,
          initialIndex: initialIndex,
          imageBuilder: imageBuilder,
        ),
      ),
    );
  }

  /// Opens the full-screen viewer across *every* photo this memory has —
  /// already-saved ([_existingPhotos]) and just-picked-this-session
  /// ([_newPhotos]) alike, existing ones first — so swiping never runs into
  /// an invisible boundary between the two.
  void _openCombinedPhotoViewer({required int initialIndex}) {
    _openPhotoViewer(
      itemCount: _existingPhotos.length + _newPhotos.length,
      initialIndex: initialIndex,
      imageBuilder: (context, i) {
        if (i < _existingPhotos.length) {
          return StoredPhotoImage(
            fileId: _existingPhotos[i].originalFileId,
            fit: BoxFit.contain,
          );
        }

        final newPhoto = _newPhotos[i - _existingPhotos.length];

        return Image.file(File(newPhoto.path), fit: BoxFit.contain);
      },
    );
  }

  /// One photo tile shared by both the existing-photo and new-photo halves
  /// of the combined gallery `Wrap` — same size, same remove-button
  /// placement, same tap-to-view-full-screen behavior, regardless of which
  /// underlying list the photo actually lives in.
  Widget _photoThumbnail({
    required Key key,
    required double width,
    required Widget image,
    required VoidCallback onTap,
    required VoidCallback? onRemove,
  }) {
    return Stack(
      key: key,
      children: [
        GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: width, height: 90, child: image),
          ),
        ),
        Positioned.directional(
          textDirection: Directionality.of(context),
          end: 2,
          top: 2,
          child: IconButton.filled(
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ),
      ],
    );
  }

  Future<void> _selectDate() async {
    final selectedDate = widget.dateDisplay == 'gregorian'
        ? await showDatePicker(
            context: context,
            initialDate: _memoryDate ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime.now(),
          )
        : await showDatePickerWithHebrew(
            context: context,
            initialDate: _memoryDate ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime.now(),
            isHebrew: _isHebrew,
          );

    if (selectedDate != null) {
      setState(() {
        _memoryDate = selectedDate;
      });
    }
  }

  /// Opens the AI Editor panel — a single sheet where Translate/Style/Fix
  /// switch which suggestion is shown without ever closing the panel, per
  /// the reference the user shared. Applying (or dismissing, at any point)
  /// is the only way it affects the text field — spec §15's "never applied
  /// automatically" still holds.
  Future<void> _enhanceText() async {
    final text = _textController.text.trim();

    if (text.isEmpty) return;

    setState(() => _isEnhancingText = true);

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EnhancePanel(
        originalText: text,
        childGender: widget.childGender,
        service: _aiTextEnhancementService,
        isHebrew: _isHebrew,
      ),
    );

    if (mounted) setState(() => _isEnhancingText = false);

    if (result != null) {
      _textController.text = result;
    }
  }

  Future<bool> _saveMemory({bool exitAfterSave = true}) async {
    final text = _textController.text.trim();

    if (text.isEmpty && _newPhotos.isEmpty && _existingPhotos.isEmpty) {
      setState(() {
        _errorMessage = _isHebrew
            ? 'יש להוסיף טקסט או לפחות תמונה אחת'
            : 'Add some text or at least one photo';
      });
      return false;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _uploadProgressText = null;
    });

    try {
      await _memoryService.saveMemory(
        bookId: widget.bookId,
        text: text,
        memoryDate: _memoryDate,
        existingPhotos: _existingPhotos,
        newPhotos: _newPhotos,
        editingMemory: widget.memory,
        onUploadProgress: (uploaded, total) {
          if (!mounted || total <= 1) return;

          setState(() {
            _uploadProgressText = _isHebrew
                ? 'מעלה תמונה $uploaded מתוך $total…'
                : 'Uploading photo $uploaded of $total…';
          });
        },
      );

      if (!mounted) return false;

      if (exitAfterSave) {
        _popWithoutCheck();
      }

      return true;
    } catch (e) {
      if (!mounted) return false;

      setState(() {
        _errorMessage = friendlyErrorMessage(e);
      });

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
      child: Directionality(
        textDirection: _isHebrew ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              widget.isEditing
                  ? (_isHebrew ? 'זיכרון' : 'Memory')
                  : (_isHebrew ? 'הוספת זיכרון' : 'Add Memory'),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // Show selected photos visually before saving
              // Put this above the text field:
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _isHebrew ? 'תמונות' : 'Photos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              // One flowing gallery for both already-saved photos and photos
              // just picked this session — previously these were two separate
              // lists/rows with two separate full-screen viewers, which read as
              // "some photos are somewhere else" the moment a memory had both
              // (found on-device, 2026-09-07). A single Wrap + a single
              // combined viewer (_openCombinedPhotoViewer) fixes both the
              // visual split and the swipe-between-photos gap.
              if (_existingPhotos.isNotEmpty || _newPhotos.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var index = 0; index < _existingPhotos.length; index++)
                      _photoThumbnail(
                        key: ValueKey(
                          _existingPhotos[index].thumbnailFileId ??
                              _existingPhotos[index].originalFileId,
                        ),
                        width: _galleryPhotoWidth(_existingPhotos[index]),
                        image: StoredPhotoImage(
                          fileId:
                              _existingPhotos[index].thumbnailFileId ??
                              _existingPhotos[index].originalFileId,
                          fit: BoxFit.cover,
                        ),
                        onTap: () =>
                            _openCombinedPhotoViewer(initialIndex: index),
                        onRemove: _isLoading
                            ? null
                            : () => setState(
                                () => _existingPhotos.removeAt(index),
                              ),
                      ),
                    for (var index = 0; index < _newPhotos.length; index++)
                      _photoThumbnail(
                        key: ValueKey(_newPhotos[index].path),
                        width: 90,
                        image: Image.file(
                          File(_newPhotos[index].path),
                          fit: BoxFit.cover,
                        ),
                        onTap: () => _openCombinedPhotoViewer(
                          initialIndex: _existingPhotos.length + index,
                        ),
                        onRemove: _isLoading
                            ? null
                            : () => setState(() => _newPhotos.removeAt(index)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              OutlinedButton.icon(
                onPressed: _isLoading ? null : _pickPhotos,
                icon: const Icon(Icons.add_photo_alternate),
                label: Text(_isHebrew ? 'הוספת תמונות' : 'Add Photos'),
              ),

              const SizedBox(height: 20),

              // So while creating a memory, you can already visually see every newly selected photo.
              TextField(
                controller: _textController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: _isHebrew ? 'מה קרה?' : 'What happened?',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textController,
                  builder: (context, value, _) {
                    final canEnhance =
                        value.text.trim().isNotEmpty && !_isLoading;

                    return TextButton.icon(
                      onPressed: (canEnhance && !_isEnhancingText)
                          ? _enhanceText
                          : null,
                      icon: _isEnhancingText
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(_isHebrew ? 'שיפור טקסט' : 'Enhance text'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _memoryDate == null
                      ? (_isHebrew ? 'תאריך: היום' : 'Date: Today')
                      : '${_isHebrew ? 'תאריך' : 'Date'}: '
                            '${formatDate(_memoryDate!, widget.dateDisplay)}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: _selectDate,
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
              if (_errorMessage != null)
                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveMemory,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : Text(
                          widget.isEditing
                              ? (_isHebrew ? 'שמירת שינויים' : 'Save Changes')
                              : (_isHebrew ? 'שמירת זיכרון' : 'Save Memory'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single persistent panel: Translate/Style/Fix switch which suggestion
/// is shown without ever closing it (matches the reference the user
/// shared) — Apply is the only thing that returns a result to the caller;
/// closing any other way (X, back gesture, tap outside) returns null and
/// leaves the original text untouched.
class _EnhancePanel extends StatefulWidget {
  const _EnhancePanel({
    required this.originalText,
    required this.childGender,
    required this.service,
    required this.isHebrew,
  });

  final String originalText;
  final String? childGender;
  final AiTextEnhancementService service;
  final bool isHebrew;

  @override
  State<_EnhancePanel> createState() => _EnhancePanelState();
}

class _EnhancePanelState extends State<_EnhancePanel> {
  static const _styles = {
    'short': 'Short',
    'warm': 'Warm',
    'playful': 'Playful',
  };
  static const _stylesHe = {'short': 'קצר', 'warm': 'חם', 'playful': 'משעשע'};

  String? _mode;
  String? _style;
  String? _result;
  bool _isLoading = false;
  String? _error;

  Future<void> _selectMode(String mode) async {
    setState(() {
      _mode = mode;
      _style = null;
      _result = null;
      _error = null;
    });

    if (mode != 'style') {
      await _generate(mode: mode, style: null);
    }
  }

  Future<void> _selectStyle(String style) async {
    setState(() => _style = style);
    await _generate(mode: 'style', style: style);
  }

  Future<void> _generate({required String mode, String? style}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await widget.service.enhance(
        widget.originalText,
        mode: mode,
        style: style,
        childGender: widget.childGender,
      );

      if (!mounted) return;

      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = friendlyErrorMessage(
          e,
          fallback: widget.isHebrew
              ? 'לא ניתן היה לקבל הצעה. נסו שוב.'
              : 'Could not get a suggestion. Please try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.isHebrew ? 'עורך AI' : 'AI Editor',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _ModeButton(
                    icon: Icons.translate,
                    label: widget.isHebrew ? 'תרגום' : 'Translate',
                    selected: _mode == 'translate',
                    onTap: () => _selectMode('translate'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeButton(
                    icon: Icons.auto_awesome,
                    label: widget.isHebrew ? 'סגנון' : 'Style',
                    selected: _mode == 'style',
                    onTap: () => _selectMode('style'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeButton(
                    icon: Icons.spellcheck,
                    label: widget.isHebrew ? 'תיקון' : 'Fix',
                    selected: _mode == 'fix',
                    onTap: () => _selectMode('fix'),
                  ),
                ),
              ],
            ),
            if (_mode == 'style') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: (widget.isHebrew ? _stylesHe : _styles).entries
                    .map(
                      (entry) => ChoiceChip(
                        label: Text(entry.value),
                        selected: _style == entry.key,
                        onSelected: (_) => _selectStyle(entry.key),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              )
            else if (_result != null) ...[
              Text(
                widget.isHebrew ? 'תוצאה' : 'Result',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(child: Text(_result!)),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  widget.isHebrew
                      ? 'בחרו אפשרות למעלה כדי לראות הצעה.'
                      : 'Pick an option above to see a suggestion.',
                  style: TextStyle(color: colorScheme.outline),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _result == null
                    ? null
                    : () => Navigator.pop(context, _result),
                child: Text(widget.isHebrew ? 'החלה' : 'Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: foreground, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
