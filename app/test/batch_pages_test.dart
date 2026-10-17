// Teacher and student views of a batch: folders (chapters) and their
// numbered materials, using the in-memory FakeBackend.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyanify/src/app.dart';
import 'package:gyanify/src/backend.dart';

import 'support/fake_backend.dart';

const _batch = LearningBatch(
  id: 'b1',
  courseId: 'c1',
  title: 'Morning batch',
  courseTitle: 'Hindi',
);

Future<void> _open(
  WidgetTester tester,
  FakeBackend backend,
  bool teacher,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BatchPage(
        backend: backend,
        batch: _batch,
        isTeacher: teacher,
        lookupTitle: (id) async => 'Title from YouTube',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _newFolder(WidgetTester tester, String name) async {
  await tester.tap(find.text('Add'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('New folder (chapter)'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField), name);
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

MaterialFolder _f(String id, String title, int order) =>
    MaterialFolder(id: id, batchId: 'b1', title: title, displayOrder: order);

LearningMaterial _video(String id, String title, String folder, int order) =>
    LearningMaterial(
      id: id,
      kind: 'youtube_video',
      title: title,
      description: '',
      youtubeUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      folderId: folder,
      displayOrder: order,
    );

double _y(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  group('teacher', () {
    testWidgets('create two folders, they show at once, reorder with up', (
      tester,
    ) async {
      final backend = FakeBackend();
      await _open(tester, backend, true);
      expect(find.text('No chapters yet'), findsOneWidget);

      await _newFolder(tester, 'Chapter 1 – Greetings');
      expect(find.text('Chapter 1 – Greetings'), findsOneWidget);
      await _newFolder(tester, 'Chapter 2 – Numbers');
      expect(find.text('Chapter 2 – Numbers'), findsOneWidget);
      expect(
        _y(tester, 'Chapter 1 – Greetings'),
        lessThan(_y(tester, 'Chapter 2 – Numbers')),
      );

      // "Move up" on the second folder puts it first.
      await tester.tap(find.byTooltip('Move up').at(1));
      await tester.pumpAndSettle();
      expect(
        _y(tester, 'Chapter 2 – Numbers'),
        lessThan(_y(tester, 'Chapter 1 – Greetings')),
      );
      expect(backend.folders.map((f) => (f.title, f.displayOrder)), [
        ('Chapter 1 – Greetings', 1),
        ('Chapter 2 – Numbers', 0),
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rename a folder', (tester) async {
      final backend = FakeBackend()..folders.add(_f('f1', 'Chapter 1', 0));
      await _open(tester, backend, true);
      await tester.tap(find.byTooltip('Folder options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'Chapter 1 – Greetings',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Chapter 1 – Greetings'), findsOneWidget);
    });

    testWidgets('a folder with items is not deleted; an empty one is', (
      tester,
    ) async {
      final backend = FakeBackend()
        ..folders.addAll([_f('f1', 'Full', 0), _f('f2', 'Empty', 1)])
        ..materials.add(_video('m1', 'Lesson', 'f1', 0));
      await _open(tester, backend, true);

      await tester.tap(find.byTooltip('Folder options').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('still has 1 item'), findsOneWidget);
      expect(find.text('Full'), findsOneWidget);

      await tester.tap(find.byTooltip('Folder options').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Empty'), findsNothing);
      expect(backend.folders.map((f) => f.id), ['f1']);
    });

    testWidgets('add a video inside a folder: title from YouTube, numbered', (
      tester,
    ) async {
      final backend = FakeBackend()..folders.add(_f('f1', 'Chapter 1', 0));
      await _open(tester, backend, true);
      await tester.tap(find.text('Chapter 1'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing here yet'), findsOneWidget);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add YouTube video link'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'YouTube link (Unlisted is fine)'),
        'https://youtu.be/dQw4w9WgXcQ',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('1.'), findsOneWidget);
      expect(find.text('Title from YouTube'), findsOneWidget);
      expect(backend.materials.single.folderId, 'f1');
      expect(
        backend.materials.single.youtubeUrl,
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );

      // Back on the batch page the count is up to date.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('1 item'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reorder items with down, move one to another folder', (
      tester,
    ) async {
      final backend = FakeBackend()
        ..folders.addAll([_f('f1', 'Chapter 1', 0), _f('f2', 'Chapter 2', 1)])
        ..materials.addAll([
          _video('m1', 'Alpha', 'f1', 0),
          _video('m2', 'Beta', 'f1', 1),
        ]);
      await _open(tester, backend, true);
      await tester.tap(find.text('Chapter 1'));
      await tester.pumpAndSettle();
      expect(_y(tester, 'Alpha'), lessThan(_y(tester, 'Beta')));

      await tester.tap(find.byTooltip('Move down').first);
      await tester.pumpAndSettle();
      expect(_y(tester, 'Beta'), lessThan(_y(tester, 'Alpha')));

      await tester.tap(find.byTooltip('Options').first); // Beta
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chapter 2'));
      await tester.pumpAndSettle();
      expect(find.text('Beta'), findsNothing);
      expect(find.text('Alpha'), findsOneWidget);
      expect(backend.materials.firstWhere((m) => m.id == 'm2').folderId, 'f2');
    });
  });

  group('student', () {
    testWidgets('sees folders first, then numbered items in teacher order', (
      tester,
    ) async {
      final backend = FakeBackend()
        ..folders.addAll([_f('f2', 'Chapter 2', 1), _f('f1', 'Chapter 1', 0)])
        ..materials.addAll([
          _video('m3', 'Third', 'f1', 2),
          _video('m1', 'First', 'f1', 0),
          _video('m2', 'Second', 'f1', 1),
        ]);
      await _open(tester, backend, false);
      expect(find.text('Add'), findsNothing);
      expect(find.byTooltip('Move up'), findsNothing);
      expect(find.byTooltip('Folder options'), findsNothing);
      expect(_y(tester, 'Chapter 1'), lessThan(_y(tester, 'Chapter 2')));
      expect(find.text('3 items'), findsOneWidget);

      await tester.tap(find.text('Chapter 1'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Options'), findsNothing);
      for (final (n, title) in [(1, 'First'), (2, 'Second'), (3, 'Third')]) {
        final row = find.ancestor(
          of: find.text(title),
          matching: find.byType(Card),
        );
        expect(
          find.descendant(of: row, matching: find.text('$n.')),
          findsOneWidget,
          reason: '$title should be number $n',
        );
      }
      expect(_y(tester, 'First'), lessThan(_y(tester, 'Second')));
      expect(_y(tester, 'Second'), lessThan(_y(tester, 'Third')));
    });
  });

  testWidgets('teacher rows fit a 360dp phone with long titles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const long = 'Chapter 12 – Muhavare aur Lokoktiyan (Idioms and Proverbs)';
    final backend = FakeBackend()
      ..folders.addAll([_f('f1', long, 0), _f('f2', 'Chapter 13', 1)])
      ..materials.addAll([
        _video('m1', '$long – Part 1 video lesson', 'f1', 0),
        _video('m2', 'Short', 'f1', 1),
      ]);
    await _open(tester, backend, true);
    expect(find.text(long), findsOneWidget);
    await tester.tap(find.text(long));
    await tester.pumpAndSettle();
    expect(find.text('1.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('before the folders SQL is run', () {
    testWidgets('teacher sees which SQL file to run, no crash', (tester) async {
      final backend = FakeBackend()..missingFoldersMigration = true;
      await _open(tester, backend, true);
      expect(
        find.textContaining(
          'supabase/migrations/202610180001_material_folders.sql',
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('student sees a friendly message, no crash', (tester) async {
      final backend = FakeBackend()..missingFoldersMigration = true;
      await _open(tester, backend, false);
      expect(
        find.textContaining('Your teacher is updating this class'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
