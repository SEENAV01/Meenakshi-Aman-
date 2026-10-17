// The teacher's Requests tab (and every other list) must show new data
// without restarting the app: on tab switch, on resume, by pulling down
// (even when the list is empty) and with a Refresh button.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyanify/src/app.dart';
import 'package:gyanify/src/backend.dart';

import 'support/fake_backend.dart';

Future<void> _shell(
  WidgetTester tester,
  FakeBackend backend,
  String role,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MainShell(backend: backend, role: role, displayName: 'Meenakshi'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// Pulls the visible list down far enough to trigger RefreshIndicator.
Future<void> _pull(WidgetTester tester) async {
  final list = find.byType(Scrollable).hitTestable().first;
  await tester.fling(list, const Offset(0, 400), 1200);
  await tester.pumpAndSettle();
}

/// The number shown in the Requests tab badge, or null if no badge.
String? _badge(WidgetTester tester) {
  final badges = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.byType(Badge),
  );
  for (final element in badges.evaluate()) {
    final badge = element.widget as Badge;
    if (badge.isLabelVisible && badge.label is Text) {
      return (badge.label! as Text).data;
    }
  }
  return null;
}

void main() {
  group('teacher Requests tab', () {
    testWidgets('a request made after start shows when I open the tab', (
      tester,
    ) async {
      final backend = FakeBackend();
      await _shell(tester, backend, 'teacher_admin');
      backend.addRequest('Asha'); // a student asks to join meanwhile
      await _tab(tester, 'Requests');
      expect(find.text('Asha'), findsOneWidget);
      expect(_badge(tester), '1');
    });

    testWidgets('pull down on the EMPTY list loads the new request', (
      tester,
    ) async {
      final backend = FakeBackend();
      await _shell(tester, backend, 'teacher_admin');
      await _tab(tester, 'Requests');
      expect(find.text('No enrollment requests'), findsOneWidget);
      backend.addRequest('Ravi');
      await _pull(tester);
      expect(find.text('Ravi'), findsOneWidget);
    });

    testWidgets('the Refresh button loads the new request', (tester) async {
      final backend = FakeBackend();
      await _shell(tester, backend, 'teacher_admin');
      await _tab(tester, 'Requests');
      backend.addRequest('Meera');
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Meera'), findsOneWidget);
    });

    testWidgets('coming back to the app updates the badge', (tester) async {
      final backend = FakeBackend();
      await _shell(tester, backend, 'teacher_admin');
      expect(_badge(tester), isNull);
      backend
        ..addRequest('Asha')
        ..addRequest('Ravi');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(_badge(tester), '2');
    });

    testWidgets('approving clears the badge', (tester) async {
      final backend = FakeBackend()..addRequest('Asha');
      await _shell(tester, backend, 'teacher_admin');
      expect(_badge(tester), '1');
      await _tab(tester, 'Requests');
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(find.text('Approved'), findsOneWidget);
      expect(_badge(tester), isNull);
    });
  });

  // Every tab: empty list can be pulled, switching to it reloads it.
  for (final (role, tab, loader) in [
    ('teacher_admin', 'Courses', 'loadTeacherCourses'),
    ('teacher_admin', 'Requests', 'loadEnrollmentRequests'),
    ('teacher_admin', 'Live Classes', 'loadLiveClasses'),
    ('student', 'Courses', 'loadCatalog'),
    ('student', 'My learning', 'loadApprovedBatches'),
    ('student', 'Live Classes', 'loadLiveClasses'),
  ]) {
    final who = role == 'student' ? 'student' : 'teacher';
    testWidgets('$who $tab: reload on switch, pull and button when empty', (
      tester,
    ) async {
      final backend = FakeBackend();
      await _shell(tester, backend, role);
      await _tab(tester, 'Profile');
      final before = backend.count(loader);
      await _tab(tester, tab);
      expect(backend.count(loader), before + 1, reason: 'switching to $tab');
      await _pull(tester);
      expect(backend.count(loader), before + 2, reason: 'pull on empty $tab');
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(backend.count(loader), before + 3, reason: 'Refresh button');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('batch and folder pages: pull when empty and Refresh button', (
    tester,
  ) async {
    const batch = LearningBatch(
      id: 'b1',
      courseId: 'c1',
      title: 'Morning batch',
      courseTitle: 'Hindi',
    );
    final backend = FakeBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: BatchPage(backend: backend, batch: batch, isTeacher: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No chapters yet'), findsOneWidget);
    final start = backend.count('loadFolders');
    await _pull(tester);
    expect(backend.count('loadFolders'), start + 1);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(backend.count('loadFolders'), start + 2);

    backend.folders.add(
      const MaterialFolder(
        id: 'f1',
        batchId: 'b1',
        title: 'Chapter 1',
        displayOrder: 0,
      ),
    );
    await _pull(tester);
    await tester.tap(find.text('Chapter 1'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing here yet'), findsOneWidget);
    final inFolder = backend.count('loadFolders');
    await _pull(tester);
    expect(backend.count('loadFolders'), inFolder + 1);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(backend.count('loadFolders'), inFolder + 2);
  });
}
