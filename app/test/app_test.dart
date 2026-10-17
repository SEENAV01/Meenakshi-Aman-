import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyanify/src/app.dart';

void main() {
  testWidgets('shows a clear notice when Supabase is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(const GyanifyApp(isBackendConfigured: false));

    expect(find.text('Meenakshi Amman Hindi Classes'), findsOneWidget);
    expect(
      find.textContaining('Backend configuration is missing'),
      findsOneWidget,
    );
    expect(find.textContaining('SUPABASE_PUBLISHABLE_KEY'), findsOneWidget);
  });

  testWidgets('app title is the full name', (tester) async {
    await tester.pumpWidget(const GyanifyApp(isBackendConfigured: false));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Meenakshi Amman Hindi Classes');
  });

  for (final isTeacher in [true, false]) {
    testWidgets('header shows the full name uncut on a 360dp phone '
        '(${isTeacher ? 'teacher' : 'student'})', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: AppHeaderTitle(isTeacher: isTeacher)),
          ),
        ),
      );
      final name = tester.renderObject<RenderParagraph>(
        find.text('Meenakshi Amman Hindi Classes'),
      );
      expect(name.didExceedMaxLines, isFalse);
      expect(find.text(isTeacher ? 'Teacher' : 'Student'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
