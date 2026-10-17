// Link checks shared by the teacher forms. The database enforces the same
// rules (see supabase/migrations/202610170001_youtube_meet_links_hardening.sql),
// so a link that passes here is also accepted by Supabase.

final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _meetingPattern = RegExp(
  r'^https://([a-z0-9-]+\.)*(meet\.google\.com|zoom\.us|zoom\.com)(/|$)',
  caseSensitive: false,
);

/// Returns the 11-character YouTube video id, or null if [input] is not a
/// YouTube video link. Accepts watch, youtu.be, shorts, live and embed links.
String? youtubeVideoId(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  String? id;
  if (host == 'youtu.be') {
    id = segments.isEmpty ? null : segments.first;
  } else if (host == 'youtube.com' ||
      host == 'www.youtube.com' ||
      host == 'm.youtube.com' ||
      host == 'music.youtube.com') {
    if (segments.length == 1 && segments.first == 'watch') {
      id = uri.queryParameters['v'];
    } else if (segments.length >= 2 &&
        const {'shorts', 'live', 'embed'}.contains(segments.first)) {
      id = segments[1];
    }
  }
  return id != null && _videoId.hasMatch(id) ? id : null;
}

/// The one URL format stored for every video.
String canonicalYoutubeUrl(String videoId) =>
    'https://www.youtube.com/watch?v=$videoId';

/// True for an https Google Meet or Zoom link.
bool isMeetingUrl(String input) {
  final value = input.trim();
  final uri = Uri.tryParse(value);
  return uri != null &&
      value.length <= 500 &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      _meetingPattern.hasMatch(value);
}
