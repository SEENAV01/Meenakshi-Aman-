// Regression test: after creating something the list must refresh at once,
// without "setState() callback argument returned a Future".
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyanify/src/app.dart';

import 'support/fake_backend.dart';

Future<void> _fillAndSave(WidgetTester tester, String name) async {
  await tester.enterText(find.byType(TextField).first, name);
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('new course and batch appear immediately', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TeacherCoursesPage(backend: backend)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create your first course'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Course'));
    await tester.pumpAndSettle();
    await _fillAndSave(tester, 'Hindi Class 10');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('returned a Future'), findsNothing);
    expect(find.text('Hindi Class 10'), findsOneWidget);

    await tester.tap(find.text('Add batch'));
    await tester.pumpAndSettle();
    await _fillAndSave(tester, 'Morning batch');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('returned a Future'), findsNothing);
    expect(find.text('Morning batch'), findsOneWidget);
  });

  test('no setState callback in lib/ uses an arrow body', () {
    // `setState(() => _x = someFuture)` returns the Future and asserts at
    // runtime, so the whole app uses block bodies: setState(() { ... });
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'setState\(\s*\(\)\s*=>').hasMatch(lines[i])) {
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
