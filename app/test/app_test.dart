import 'package:flutter_test/flutter_test.dart';
import 'package:gyanify/src/app.dart';

void main() {
  testWidgets('shows a clear notice when Supabase is not configured', (
    tester,
  ) async {
    await tester.pumpWidget(const GyanifyApp(isBackendConfigured: false));

    expect(find.text('GYANIFY'), findsOneWidget);
    expect(
      find.textContaining('Backend configuration is missing'),
      findsOneWidget,
    );
    expect(find.textContaining('SUPABASE_PUBLISHABLE_KEY'), findsOneWidget);
  });
}
