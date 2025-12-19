import 'dart:convert';

import 'package:http/http.dart' as http;

enum LyricsSource { auto, lrclib, lyricsOvh }

class LyricsResult {
  final String lyrics;
  final String source;
  final bool isSynced;

  const LyricsResult({
    required this.lyrics,
    required this.source,
    this.isSynced = false,
  });

  bool get isEmpty => lyrics.trim().isEmpty;
}

class LyricsService {
  const LyricsService();

  Future<LyricsResult?> fetch(
    String artist,
    String title, {
    String? album,
    Duration? duration,
    LyricsSource preferred = LyricsSource.auto,
  }) async {
    final cleanedArtist = artist.trim();
    final cleanedTitle = title.trim();
    final cleanedAlbum = (album ?? '').trim();
    switch (preferred) {
      case LyricsSource.lrclib:
        return _fromLrcLib(
          cleanedArtist,
          cleanedTitle,
          album: cleanedAlbum,
          duration: duration,
        );
      case LyricsSource.lyricsOvh:
        return _fromLyricsOvh(cleanedArtist, cleanedTitle);
      case LyricsSource.auto:
        final primary = await _fromLrcLib(
          cleanedArtist,
          cleanedTitle,
          album: cleanedAlbum,
          duration: duration,
        );
        if (primary != null && !primary.isEmpty) return primary;
        return _fromLyricsOvh(cleanedArtist, cleanedTitle);
    }
  }

  Future<LyricsResult?> _fromLyricsOvh(String artist, String title) async {
    final uri = Uri.parse('https://api.lyrics.ovh/v1/$artist/$title');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final map = jsonDecode(response.body) as Map<String, dynamic>;
        final body = (map['lyrics'] as String?)?.trim() ?? '';
        if (body.isNotEmpty) {
          return LyricsResult(lyrics: body, source: 'lyrics.ovh');
        }
      }
    } catch (_) {
      // Ignore and fallback.
    }
    return null;
  }

  Future<LyricsResult?> _fromLrcLib(
    String artist,
    String title, {
    String? album,
    Duration? duration,
  }) async {
    final uri = Uri.https('lrclib.net', '/api/get', {
      'track_name': title,
      'artist_name': artist,
      'album_name': album ?? '',
      'duration': duration?.inSeconds.toString() ?? '',
    });
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final map = jsonDecode(response.body) as Map<String, dynamic>;
        final body =
            (map['syncedLyrics'] as String? ??
                    map['plainLyrics'] as String? ??
                    '')
                .trim();
        if (body.isNotEmpty) {
          final synced = (map['syncedLyrics'] as String?)?.isNotEmpty ?? false;
          return LyricsResult(lyrics: body, source: 'lrclib', isSynced: synced);
        }
      }
    } catch (_) {
      // Ignore and fallback.
    }
    return null;
  }
}
