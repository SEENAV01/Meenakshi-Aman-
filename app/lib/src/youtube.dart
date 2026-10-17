// YouTube title lookup through the public oEmbed endpoint (no API key).
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'links.dart';

/// Looks up a video's title; returns null when it cannot (private video,
/// no internet, timeout). Tests pass their own function instead.
typedef YoutubeTitleLookup = Future<String?> Function(String videoId);

Future<String?> fetchYoutubeTitle(String videoId, {http.Client? client}) async {
  final uri = Uri.https('www.youtube.com', '/oembed', {
    'url': canonicalYoutubeUrl(videoId),
    'format': 'json',
  });
  final c = client ?? http.Client();
  try {
    final response = await c.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final title = body is Map ? body['title'] : null;
    return title is String && title.trim().isNotEmpty ? title.trim() : null;
  } on Exception {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// Small thumbnail (320x180) served by YouTube for every public/unlisted video.
String youtubeThumbnailUrl(String videoId) =>
    'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';
