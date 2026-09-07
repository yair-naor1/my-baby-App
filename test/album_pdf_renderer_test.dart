import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/models/album_design.dart';
import 'package:my_app/models/book.dart';
import 'package:my_app/models/memory.dart';
import 'package:my_app/models/photo_reference.dart';
import 'package:my_app/services/album_layout_builder.dart';
import 'package:my_app/services/album_pdf_renderer.dart';
import 'package:my_app/services/photo_storage_service.dart';

// A valid 1x1 black PNG, just enough for pw.MemoryImage/Image.memory to
// decode — the point of this test is layout/bidi correctness, not photo
// content.
final _testPhotoBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUB'
  'AScY42YAAAAASUVORK5CYII=',
);

class _FakePhotoStorage implements PhotoStorageService {
  @override
  Future<Uint8List> downloadPhoto(String fileId) async => _testPhotoBytes;

  @override
  Future<PhotoReference> uploadPhoto({
    required String bookId,
    required File photo,
    required String fileName,
  }) => throw UnimplementedError();

  @override
  Future<void> deletePhotos(List<PhotoReference> photos) =>
      throw UnimplementedError();
}

PhotoReference _photoRef(String id) => PhotoReference(
  provider: 'test',
  originalFileId: id,
  ownerUid: 'test-uid',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders a full album PDF for Hebrew and English books', () async {
    final book = Book(
      bookId: 'book1',
      childName: 'איתי',
      birthDate: DateTime(2026, 1, 1),
      ownerIds: const ['u1'],
      language: 'he',
      dateDisplay: 'gregorian',
      createdAt: DateTime(2026, 1, 1),
      schemaVersion: 1,
      coverPhoto: _photoRef('cover'),
    );

    final memories = [
      Memory(
        memoryId: 'm1',
        memoryDate: DateTime(2026, 2, 1),
        text: 'טקסט בלבד, בלי תמונות. גיל חודש בדיוק.',
        photoRefs: const [],
        createdBy: 'u1',
        createdAt: DateTime(2026, 2, 1),
        updatedAt: DateTime(2026, 2, 1),
        hiddenFromBook: false,
        schemaVersion: 1,
      ),
      Memory(
        memoryId: 'm2',
        memoryDate: DateTime(2026, 3, 1),
        text: 'תמונה אחת עם טקסט מתחת, בתאריך 1/3/2026 בשעה 10:00.',
        photoRefs: [_photoRef('single')],
        createdBy: 'u1',
        createdAt: DateTime(2026, 3, 1),
        updatedAt: DateTime(2026, 3, 1),
        hiddenFromBook: false,
        schemaVersion: 1,
      ),
      Memory(
        memoryId: 'm3',
        memoryDate: DateTime(2026, 4, 1),
        text: 'כמה תמונות ביחד ברשת.',
        photoRefs: [_photoRef('grid1'), _photoRef('grid2'), _photoRef('grid3')],
        createdBy: 'u1',
        createdAt: DateTime(2026, 4, 1),
        updatedAt: DateTime(2026, 4, 1),
        hiddenFromBook: false,
        schemaVersion: 1,
      ),
      // Hidden — must not appear in the plan or the rendered PDF.
      Memory(
        memoryId: 'm4',
        memoryDate: DateTime(2026, 5, 1),
        text: 'זה לא אמור להופיע באלבום.',
        photoRefs: const [],
        createdBy: 'u1',
        createdAt: DateTime(2026, 5, 1),
        updatedAt: DateTime(2026, 5, 1),
        hiddenFromBook: true,
        schemaVersion: 1,
      ),
    ];

    final builder = AlbumLayoutBuilder();
    final pages = builder.build(book: book, memories: memories);

    // Cover + (divider, memory) for each of the 3 distinct months the 3
    // visible memories fall in; the hidden one is excluded entirely.
    expect(pages.length, 7);

    // The real bug this guards against: BookRepository.createBook hardcodes
    // language: 'en' always, so nothing ever actually sets 'he' — detection
    // has to work from a book whose language field is wrong/default too.
    final bookWithWrongLanguageField = Book(
      bookId: book.bookId,
      childName: book.childName,
      birthDate: book.birthDate,
      ownerIds: book.ownerIds,
      language: 'en',
      dateDisplay: 'gregorian',
      createdAt: book.createdAt,
      schemaVersion: book.schemaVersion,
      coverPhoto: book.coverPhoto,
    );
    expect(
      builder.detectIsRtl(
        book: bookWithWrongLanguageField,
        memories: memories,
      ),
      isTrue,
    );

    final bytes = await const AlbumPdfRenderer().render(
      pages: pages,
      design: AlbumDesign.softPastel,
      isRtl: builder.detectIsRtl(book: book, memories: memories),
      photoStorage: _FakePhotoStorage(),
    );

    expect(bytes.length, greaterThan(100));
    expect(utf8.decode(bytes.take(5).toList(), allowMalformed: true), '%PDF-');

    // English sanity pass too, since Directionality shouldn't break LTR —
    // with actual English content, not Hebrew text under language: 'en'
    // (that would just prove bidi reversal happens, not that LTR works).
    final enBook = Book(
      bookId: 'book2',
      childName: 'Itai',
      birthDate: DateTime(2026, 1, 1),
      ownerIds: const ['u1'],
      language: 'en',
      dateDisplay: 'gregorian',
      createdAt: DateTime(2026, 1, 1),
      schemaVersion: 1,
      coverPhoto: _photoRef('cover'),
    );
    final enMemories = [
      Memory(
        memoryId: 'm1',
        memoryDate: DateTime(2026, 3, 1),
        text: 'One photo with text below, on 1/3/2026 at 10:00.',
        photoRefs: [_photoRef('single')],
        createdBy: 'u1',
        createdAt: DateTime(2026, 3, 1),
        updatedAt: DateTime(2026, 3, 1),
        hiddenFromBook: false,
        schemaVersion: 1,
      ),
    ];
    final enPages = builder.build(book: enBook, memories: enMemories);
    expect(
      builder.detectIsRtl(book: enBook, memories: enMemories),
      isFalse,
    );
    final enBytes = await const AlbumPdfRenderer().render(
      pages: enPages,
      design: AlbumDesign.softPastel,
      isRtl: false,
      photoStorage: _FakePhotoStorage(),
    );
    expect(enBytes.length, greaterThan(100));

    // Written for manual visual inspection, not part of the assertion.
    final outDir = Directory.systemTemp.createTempSync('album_pdf_test');
    File('${outDir.path}/he.pdf').writeAsBytesSync(bytes);
    File('${outDir.path}/en.pdf').writeAsBytesSync(enBytes);
    // ignore: avoid_print
    print('Wrote PDFs to ${outDir.path}');
  });

  test('renders every cover decoration without error', () async {
    final book = Book(
      bookId: 'book3',
      childName: 'איתי',
      birthDate: DateTime(2026, 1, 1),
      ownerIds: const ['u1'],
      language: 'he',
      dateDisplay: 'gregorian',
      createdAt: DateTime(2026, 1, 1),
      schemaVersion: 1,
      coverPhoto: _photoRef('cover'),
    );
    final builder = AlbumLayoutBuilder();
    final pages = builder.build(book: book, memories: const []);

    final outDir = Directory.systemTemp.createTempSync('album_pdf_decoration_test');

    for (final design in AlbumDesign.values) {
      final bytes = await const AlbumPdfRenderer().render(
        pages: pages,
        design: design,
        isRtl: true,
        photoStorage: _FakePhotoStorage(),
      );

      expect(bytes.length, greaterThan(100));
      expect(
        utf8.decode(bytes.take(5).toList(), allowMalformed: true),
        '%PDF-',
      );

      File('${outDir.path}/${design.name}.pdf').writeAsBytesSync(bytes);
    }

    // ignore: avoid_print
    print('Wrote decoration PDFs to ${outDir.path}');
  });
}
