import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyanify/src/backend.dart';
import 'package:gyanify/src/youtube.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('fetchYoutubeTitle (oEmbed)', () {
    test('asks the public oEmbed URL and returns the title', () async {
      late Uri asked;
      final client = MockClient((request) async {
        asked = request.url;
        return http.Response(
          jsonEncode({'title': ' Namaste – Lesson 1 ', 'author_name': 'x'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      expect(
        await fetchYoutubeTitle('dQw4w9WgXcQ', client: client),
        'Namaste – Lesson 1',
      );
      expect(asked.host, 'www.youtube.com');
      expect(asked.path, '/oembed');
      expect(
        asked.queryParameters['url'],
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(asked.queryParameters['format'], 'json');
    });

    test('private / missing video (404) gives null', () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));
      expect(await fetchYoutubeTitle('AAAAAAAAAAA', client: client), isNull);
    });

    test('no internet gives null instead of an error', () async {
      final client = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      expect(await fetchYoutubeTitle('dQw4w9WgXcQ', client: client), isNull);
    });

    test('thumbnail URL', () {
      expect(
        youtubeThumbnailUrl('dQw4w9WgXcQ'),
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg',
      );
    });
  });

  group('requireMigration', () {
    // Codes seen from a real Supabase before the folders SQL was run:
    // PGRST205 (table missing), 42703 (column missing on read),
    // PGRST204 (column missing on write).
    for (final code in ['PGRST205', '42703', 'PGRST204', '42P01']) {
      test('$code means "run the SQL"', () async {
        await expectLater(
          requireMigration<void>(
            foldersMigration,
            () async => throw PostgrestException(message: 'x', code: code),
          ),
          throwsA(
            isA<SetupRequiredException>().having(
              (e) => e.toString(),
              'message',
              contains('supabase/migrations/202610180001_material_folders.sql'),
            ),
          ),
        );
      });
    }

    test('other errors (e.g. permission) pass through unchanged', () async {
      await expectLater(
        requireMigration<void>(
          foldersMigration,
          () async =>
              throw const PostgrestException(message: 'no', code: '42501'),
        ),
        throwsA(isA<PostgrestException>()),
      );
    });
  });
}
