// Opens every teacher dialog, types into each field, taps Save or Cancel and
// pumps until the dialog route is completely gone. Any framework error during
// the close animation (for example a TextEditingController disposed while its
// TextField is still on screen) fails the test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyanify/src/backend.dart';
import 'package:gyanify/src/dialogs.dart';

/// Pumps a page with an "open" button that awaits [open] and records the result.
class _Harness<T> {
  T? result;
  bool closed = false;

  Future<void> start(
    WidgetTester tester,
    Future<T?> Function(BuildContext context) open,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await open(context);
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  }

  /// Taps [button] inside the dialog and waits until the route has fully left.
  Future<void> close(WidgetTester tester, String button) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(button),
      ),
    );
    // Pump frame by frame through the whole exit animation, then settle.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ModalBarrier), findsOneWidget); // only the page's own
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  }
}

Future<void> _type(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextField, label);
  expect(field, findsOneWidget, reason: 'field "$label"');
  await tester.enterText(field, text);
  await tester.pump();
}

const _batches = [
  LearningBatch(
    id: 'b1',
    courseId: 'c1',
    title: 'Morning batch',
    courseTitle: 'Hindi',
  ),
];

void main() {
  group('course / batch / PDF form (showTextForm without link)', () {
    Future<(String, String)?> open(BuildContext context) => showTextForm(
      context,
      title: 'Create course',
      nameLabel: 'Course title',
    );

    testWidgets('Save returns the typed values and closes cleanly', (
      tester,
    ) async {
      final h = _Harness<(String, String)>();
      await h.start(tester, open);
      await _type(tester, 'Course title', '  Hindi Class 10 ');
      await _type(tester, 'Description (optional)', 'Grammar and writing');
      await h.close(tester, 'Save');
      expect(h.result, ('Hindi Class 10', 'Grammar and writing'));
    });

    testWidgets('Cancel returns null and closes cleanly', (tester) async {
      final h = _Harness<(String, String)>();
      await h.start(tester, open);
      await _type(tester, 'Course title', 'Will be cancelled');
      await _type(tester, 'Description (optional)', 'x');
      await h.close(tester, 'Cancel');
      expect(h.result, isNull);
    });

    testWidgets('Save with an empty title keeps the dialog open', (
      tester,
    ) async {
      final h = _Harness<(String, String)>();
      await h.start(tester, open);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
      await h.close(tester, 'Cancel');
    });
  });

  group('PDF / video form (showMaterialForm)', () {
    const folders = [
      MaterialFolder(
        id: 'f1',
        batchId: 'b1',
        title: 'Chapter 1',
        displayOrder: 0,
      ),
      MaterialFolder(
        id: 'f2',
        batchId: 'b1',
        title: 'Chapter 2',
        displayOrder: 1,
      ),
    ];

    Future<MaterialFormResult?> Function(BuildContext) video(
      Future<String?> Function(String id) lookup, {
      List<String>? calls,
    }) =>
        (context) => showMaterialForm(
          context,
          isVideo: true,
          folders: folders,
          initialFolderId: 'f1',
          lookupTitle: (id) {
            calls?.add(id);
            return lookup(id);
          },
        );

    testWidgets('pasting a link fills the title from YouTube', (tester) async {
      final calls = <String>[];
      final h = _Harness<MaterialFormResult>();
      await h.start(
        tester,
        video((id) async => 'Lesson 1: Namaste', calls: calls),
      );
      await _type(
        tester,
        'YouTube link (Unlisted is fine)',
        'https://youtu.be/dQw4w9WgXcQ?si=abc',
      );
      await tester.pumpAndSettle();
      expect(calls, ['dQw4w9WgXcQ']);
      final title = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Video title'),
      );
      expect(title.controller!.text, 'Lesson 1: Namaste');
      expect(find.byType(VideoThumbnail), findsOneWidget);
      await _type(tester, 'Description (optional)', 'Greetings');
      await h.close(tester, 'Save');
      expect(h.result!.title, 'Lesson 1: Namaste');
      expect(h.result!.videoId, 'dQw4w9WgXcQ');
      expect(h.result!.folderId, 'f1');
      expect(h.result!.description, 'Greetings');
    });

    testWidgets('if YouTube gives no title, the teacher types it', (
      tester,
    ) async {
      final h = _Harness<MaterialFormResult>();
      await h.start(tester, video((id) async => null));
      await _type(
        tester,
        'YouTube link (Unlisted is fine)',
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Could not get the title. Please type it.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      await _type(tester, 'Video title', 'My own title');
      await h.close(tester, 'Save');
      expect(h.result!.title, 'My own title');
    });

    testWidgets('a title the teacher already typed is not overwritten', (
      tester,
    ) async {
      final h = _Harness<MaterialFormResult>();
      await h.start(tester, video((id) async => 'From YouTube'));
      await _type(tester, 'Video title', 'Typed first');
      await _type(
        tester,
        'YouTube link (Unlisted is fine)',
        'https://youtu.be/dQw4w9WgXcQ',
      );
      await tester.pumpAndSettle();
      await h.close(tester, 'Save');
      expect(h.result!.title, 'Typed first');
    });

    testWidgets('a bad link is refused; folder can be changed; Cancel', (
      tester,
    ) async {
      final h = _Harness<MaterialFormResult>();
      await h.start(tester, video((id) async => 'x'));
      await _type(tester, 'YouTube link (Unlisted is fine)', 'not a link');
      await _type(tester, 'Video title', 'Lesson');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Paste a YouTube video link'), findsOneWidget);
      expect(find.byType(VideoThumbnail), findsNothing);
      await tester.tap(find.text('Chapter 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chapter 2').last);
      await tester.pumpAndSettle();
      expect(find.text('Chapter 2'), findsOneWidget);
      await h.close(tester, 'Cancel');
      expect(h.result, isNull);
    });

    testWidgets('PDF form: title prefilled, folder "No folder", Save', (
      tester,
    ) async {
      final h = _Harness<MaterialFormResult>();
      await h.start(
        tester,
        (context) => showMaterialForm(
          context,
          isVideo: false,
          folders: folders,
          initialFolderId: null,
          initialTitle: 'chapter1 notes',
        ),
      );
      expect(find.text('No folder'), findsOneWidget);
      await _type(tester, 'Description (optional)', 'Print this');
      await h.close(tester, 'Choose PDF');
      expect(h.result!.title, 'chapter1 notes');
      expect(h.result!.folderId, isNull);
      expect(h.result!.videoId, isNull);
    });
  });

  group('folder name dialog', () {
    testWidgets('rename keeps the old name until changed, then Save', (
      tester,
    ) async {
      final h = _Harness<String>();
      await h.start(
        tester,
        (context) => showNameDialog(
          context,
          title: 'Rename folder',
          label: 'Folder name',
          initial: 'Chapter 1',
        ),
      );
      expect(find.text('Chapter 1'), findsOneWidget);
      await _type(tester, 'Folder name', ' Chapter 1 – Greetings ');
      await h.close(tester, 'Save');
      expect(h.result, 'Chapter 1 – Greetings');
    });

    testWidgets('Cancel returns null', (tester) async {
      final h = _Harness<String>();
      await h.start(
        tester,
        (context) =>
            showNameDialog(context, title: 'New folder', label: 'Folder name'),
      );
      await _type(tester, 'Folder name', 'x');
      await h.close(tester, 'Cancel');
      expect(h.result, isNull);
    });
  });

  group('move dialog', () {
    const folders = [
      MaterialFolder(
        id: 'f1',
        batchId: 'b1',
        title: 'Chapter 1',
        displayOrder: 0,
      ),
      MaterialFolder(
        id: 'f2',
        batchId: 'b1',
        title: 'Chapter 2',
        displayOrder: 1,
      ),
    ];

    Future<void> openMove(WidgetTester tester, _Harness<FolderChoice> h) =>
        tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  h.result = await showMoveDialog(
                    context,
                    folders: folders,
                    currentFolderId: 'f1',
                  );
                  h.closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        );

    testWidgets('choosing another folder returns it', (tester) async {
      final h = _Harness<FolderChoice>();
      await openMove(tester, h);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Chapter 1 (here now)'), findsOneWidget);
      await tester.tap(find.text('Chapter 2'));
      await tester.pumpAndSettle();
      expect(h.closed, isTrue);
      expect(h.result!.folderId, 'f2');
    });

    testWidgets('"No folder" and Cancel are different', (tester) async {
      final h = _Harness<FolderChoice>();
      await openMove(tester, h);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No folder'));
      await tester.pumpAndSettle();
      expect(h.result, isNotNull);
      expect(h.result!.folderId, isNull);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.result, isNull);
    });
  });

  group('schedule live class dialog', () {
    Future<LiveClassInput?> open(BuildContext context) =>
        showDialog<LiveClassInput>(
          context: context,
          builder: (_) => const ScheduleClassDialog(batches: _batches),
        );

    Future<void> fillAll(WidgetTester tester) async {
      await _type(tester, 'Class title', 'Doubt class');
      await _type(
        tester,
        'Google Meet or Zoom link',
        'https://meet.google.com/abc-defg-hij',
      );
      await _type(tester, 'Note for students (optional)', 'Bring notebook');
      await tester.tap(find.text('Date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('Save returns the class and closes cleanly', (tester) async {
      final h = _Harness<LiveClassInput>();
      await h.start(tester, open);
      await fillAll(tester);
      await h.close(tester, 'Save');
      final input = h.result!;
      expect(input.batchId, 'b1');
      expect(input.title, 'Doubt class');
      expect(input.meetingUrl, 'https://meet.google.com/abc-defg-hij');
      expect(input.description, 'Bring notebook');
    });

    testWidgets('Cancel after filling everything closes cleanly', (
      tester,
    ) async {
      final h = _Harness<LiveClassInput>();
      await h.start(tester, open);
      await fillAll(tester);
      await h.close(tester, 'Cancel');
      expect(h.result, isNull);
    });
  });

  group('delete confirmation', () {
    Future<bool?> open(BuildContext context) =>
        showConfirmDialog(context, title: 'Delete this?', detail: 'Sure?');

    testWidgets('Delete returns true', (tester) async {
      final h = _Harness<bool>();
      await h.start(tester, open);
      await h.close(tester, 'Delete');
      expect(h.result, isTrue);
    });

    testWidgets('Cancel returns false', (tester) async {
      final h = _Harness<bool>();
      await h.start(tester, open);
      await h.close(tester, 'Cancel');
      expect(h.result, isFalse);
    });
  });
}
