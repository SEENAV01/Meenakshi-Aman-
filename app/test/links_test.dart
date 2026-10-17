import 'package:flutter_test/flutter_test.dart';
import 'package:gyanify/src/links.dart';

void main() {
  group('youtubeVideoId', () {
    test('accepts the usual YouTube link shapes', () {
      const id = 'dQw4w9WgXcQ';
      for (final url in [
        'https://www.youtube.com/watch?v=$id',
        'https://youtube.com/watch?v=$id&t=42',
        'https://m.youtube.com/watch?v=$id',
        'https://youtu.be/$id',
        'https://youtu.be/$id?si=abc123',
        'https://www.youtube.com/shorts/$id',
        'https://www.youtube.com/live/$id?feature=share',
        'https://www.youtube.com/embed/$id',
        '  https://youtu.be/$id  ',
      ]) {
        expect(youtubeVideoId(url), id, reason: url);
      }
    });

    test('rejects anything that is not a YouTube video', () {
      for (final url in [
        '',
        'dQw4w9WgXcQ',
        'https://evil.example/watch?v=dQw4w9WgXcQ',
        'https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ',
        'https://www.youtube.com/watch?v=short',
        'https://www.youtube.com/channel/UC1234567890',
        'https://drive.google.com/file/d/abc/view',
        'javascript:alert(1)',
      ]) {
        expect(youtubeVideoId(url), isNull, reason: url);
      }
    });

    test('canonical link matches the database rule', () {
      final url = canonicalYoutubeUrl('dQw4w9WgXcQ');
      expect(url, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      expect(
        RegExp(
          r'^https://((www|m)\.)?(youtube\.com|youtu\.be)/',
          caseSensitive: false,
        ).hasMatch(url),
        isTrue,
      );
    });
  });

  group('isMeetingUrl', () {
    test('accepts Google Meet and Zoom links', () {
      for (final url in [
        'https://meet.google.com/abc-defg-hij',
        'https://us05web.zoom.us/j/123456789?pwd=xyz',
        'https://zoom.us/j/123456789',
        'https://zoom.com/j/123',
        ' https://meet.google.com/abc-defg-hij ',
      ]) {
        expect(isMeetingUrl(url), isTrue, reason: url);
      }
    });

    test('rejects Jitsi, http and look-alike hosts', () {
      for (final url in [
        'https://meet.jit.si/room',
        'http://meet.google.com/abc-defg-hij',
        'https://meet.google.com.evil.example/abc',
        'https://evilzoom.us/j/1',
        'https://user@meet.google.com/abc',
        'meet.google.com/abc-defg-hij',
        '',
      ]) {
        expect(isMeetingUrl(url), isFalse, reason: url);
      }
    });
  });
}
