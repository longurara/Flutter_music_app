import 'dart:typed_data';

class Track {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final Uint8List? artworkBytes;
  final Uri source;
  final bool isFromDrive;
  final DateTime addedAt;
  final String? genre;
  final int? year;
  final int? trackNumber;
  final Duration? duration;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.source,
    this.album,
    this.artworkUrl,
    this.artworkBytes,
    this.isFromDrive = false,
    DateTime? addedAt,
    this.genre,
    this.year,
    this.trackNumber,
    this.duration,
  }) : addedAt = addedAt ?? DateTime.now();
}
