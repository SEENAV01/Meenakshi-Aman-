import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  final parsedSupabaseUrl = Uri.tryParse(supabaseUrl);
  final isConfigured =
      parsedSupabaseUrl?.scheme == 'https' &&
      parsedSupabaseUrl?.host.isNotEmpty == true &&
      supabasePublishableKey.isNotEmpty &&
      !supabaseUrl.contains('example') &&
      !supabasePublishableKey.contains('example');

  if (isConfigured) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  runApp(ProviderScope(child: GyanifyApp(isBackendConfigured: isConfigured)));
}
