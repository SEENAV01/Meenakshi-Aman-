// Opens every teacher dialog, types into each field, taps Save or Cancel and
// pumps until the dialog route is completely gone. Any framework error during
// the close animation (for example a TextEditingController disposed while its
// TextField is still on screen) fails the test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyanify/src/backend.dart';
import 'package:gyanify/src/dialogs.dart';
import 'package:gyanify/src/links.dart';

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
    Future<(String, String, String)?> open(BuildContext context) =>
        showTextForm(
          context,
          title: 'Create course',
          nameLabel: 'Course title',
        );

    testWidgets('Save returns the typed values and closes cleanly', (
      tester,
    ) async {
      final h = _Harness<(String, String, String)>();
      await h.start(tester, open);
      await _type(tester, 'Course title', '  Hindi Class 10 ');
      await _type(tester, 'Description (optional)', 'Grammar and writing');
      await h.close(tester, 'Save');
      expect(h.result, ('Hindi Class 10', 'Grammar and writing', ''));
    });

    testWidgets('Cancel returns null and closes cleanly', (tester) async {
      final h = _Harness<(String, String, String)>();
      await h.start(tester, open);
      await _type(tester, 'Course title', 'Will be cancelled');
      await _type(tester, 'Description (optional)', 'x');
      await h.close(tester, 'Cancel');
      expect(h.result, isNull);
    });

    testWidgets('Save with an empty title keeps the dialog open', (
      tester,
    ) async {
      final h = _Harness<(String, String, String)>();
      await h.start(tester, open);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
      await h.close(tester, 'Cancel');
    });
  });

  group('YouTube video form (showTextForm with link)', () {
    Future<(String, String, String)?> open(BuildContext context) =>
        showTextForm(
          context,
          title: 'Add a YouTube video',
          nameLabel: 'Video title',
          linkLabel: 'YouTube link (Unlisted is fine)',
          linkValidator: (value) => youtubeVideoId(value) == null
              ? 'Paste a YouTube video link'
              : null,
        );

    testWidgets('Save returns title, description and link', (tester) async {
      final h = _Harness<(String, String, String)>();
      await h.start(tester, open);
      await _type(tester, 'Video title', 'Lesson 1');
      await _type(
        tester,
        'YouTube link (Unlisted is fine)',
        'https://youtu.be/dQw4w9WgXcQ',
      );
      await _type(tester, 'Description (optional)', 'Intro');
      await h.close(tester, 'Save');
      expect(h.result, ('Lesson 1', 'Intro', 'https://youtu.be/dQw4w9WgXcQ'));
    });

    testWidgets('a bad link is refused, then Cancel closes cleanly', (
      tester,
    ) async {
      final h = _Harness<(String, String, String)>();
      await h.start(tester, open);
      await _type(tester, 'Video title', 'Lesson 1');
      await _type(tester, 'YouTube link (Unlisted is fine)', 'not a link');
      await _type(tester, 'Description (optional)', 'Intro');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Paste a YouTube video link'), findsOneWidget);
      await h.close(tester, 'Cancel');
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
