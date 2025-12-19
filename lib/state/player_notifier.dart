import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:path/path.dart' as p;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:smtc_windows/smtc_windows.dart';

import '../models/track.dart' as app;
import '../services/google_drive_service.dart';
import '../services/lyrics_service.dart';

enum PlaybackTheme { vinyl, cd, artwork }

class PlayerNotifier extends ChangeNotifier {
  PlayerNotifier({required this.driveService, required this.lyricsService}) {
    _init();
  }

  final GoogleDriveService driveService;
  final LyricsService lyricsService;
  auth.AuthClient? _authClient;

  final Player _player = Player();
  List<app.Track> _queue = [];
  app.Track? _current;
  LyricsResult? _lyrics;
  bool _isLoading = false;
  bool _wasapiExclusive = false;
  double? _volumeBeforeExclusive;
  SMTCWindows? _smtc;
  int _lastSmtcPositionMs = -1;
  final Map<String, String> _smtcArtworkCache = {};
  PlaybackTheme _playbackTheme = PlaybackTheme.vinyl;
  double _preampDb = 0;
  final Map<int, double> _eqGains = {60: 0, 230: 0, 910: 0, 3600: 0, 14000: 0};
  final Set<String> _audioExts = {
    '.mp3',
    '.flac',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.opus',
  };
  List<AudioDevice> _devices = const [];
  AudioDevice? _selectedDevice;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  bool _playing = false;
  int _currentIndex = 0;
  final Map<String, String?> _artworkCache = {};
  final Map<String, Uint8List?> _sidecarArtCache = {};
  bool _isHiRes = false;
  AudioParams _audioParams = const AudioParams();
  bool _isShuffle = false;
  List<app.Track> _originalQueue = [];
  PlaylistMode _repeatMode = PlaylistMode.none;
  double _volume = 70.0;
  double _speed = 1.0;
  Timer? _sleepTimer;
  Duration? _loopA;
  Duration? _loopB;
  final List<app.Track> _history = [];
  final List<app.Track> _library = [];
  final List<String> _pinnedFolders = [];
  final Map<String, List<app.Track>> _playlists = {};
  String _searchQuery = '';
  String? _driveAccessToken;
  String? _driveEmail;
  bool _driveSigningIn = false;
  String? _driveError;
  final Map<String, LyricsResult> _lyricsStore = {};
  LyricsSource _lyricsSource = LyricsSource.auto;

  bool get isLoading => _isLoading;
  app.Track? get current => _current;
  List<app.Track> get queue => _queue;
  List<app.Track> get library => List.unmodifiable(_library);
  LyricsResult? get lyrics => _lyrics;
  bool get wasapiExclusive => _wasapiExclusive;
  PlaybackTheme get playbackTheme => _playbackTheme;
  double get preampDb => _preampDb;
  Map<int, double> get eqGains => Map.unmodifiable(_eqGains);
  List<AudioDevice> get devices => _devices;
  AudioDevice? get selectedDevice => _selectedDevice;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration get buffered => _buffered;
  bool get playing => _playing;
  bool get hasPrevious => _queue.isNotEmpty && _currentIndex > 0;
  bool get hasNext => _queue.isNotEmpty && _currentIndex < _queue.length - 1;
  bool get isHiRes => _isHiRes;
  AudioParams get audioParams => _audioParams;
  bool get isShuffle => _isShuffle;
  PlaylistMode get repeatMode => _repeatMode;
  double get volume => _volume;
  double get speed => _speed;
  Duration? get loopA => _loopA;
  Duration? get loopB => _loopB;
  bool get isLoopingAB => _loopA != null && _loopB != null;
  List<app.Track> get history => List.unmodifiable(_history);
  List<String> get pinnedFolders => List.unmodifiable(_pinnedFolders);
  Map<String, List<app.Track>> get playlists => _playlists;
  String get searchQuery => _searchQuery;
  bool get driveSignedIn => _driveAccessToken != null;
  String? get driveEmail => _driveEmail;
  bool get driveSigningIn => _driveSigningIn;
  String? get driveError => _driveError;
  LyricsSource get lyricsSource => _lyricsSource;

  Stream<Duration> get positionStream => _player.stream.position;

  StreamSubscription? _playlistSub;
  StreamSubscription? _deviceSub;
  StreamSubscription? _selectedDeviceSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _bufferSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _audioParamsSub;
  StreamSubscription? _shuffleSub;
  StreamSubscription? _repeatSub;
  StreamSubscription? _volumeSub;
  StreamSubscription? _rateSub;

  Future<void> _init() async {
    _playlistSub = _player.stream.playlist.listen((playlist) {
      final index = playlist.index;
      _currentIndex = index;
      if (_currentIndex >= 0 && _currentIndex < _queue.length) {
        final nextTrack = _queue[_currentIndex];
        if (_current?.id != nextTrack.id) {
          _lyrics = _lyricsStore[nextTrack.id];
        }
        _current = nextTrack;
        fetchLyricsForCurrent();
        _pushSmtcMetadata();
        _updateSmtcTimeline(force: true);
        _updateSmtcStatus(_playing);
        notifyListeners();
      }
    });
    _deviceSub = _player.stream.audioDevices.listen((devices) {
      _devices = devices;
      notifyListeners();
    });
    _selectedDeviceSub = _player.stream.audioDevice.listen((device) {
      _selectedDevice = device;
      notifyListeners();
    });
    _positionSub = _player.stream.position.listen((pos) {
      _position = pos;
      if (_loopA != null &&
          _loopB != null &&
          _loopA! < _loopB! &&
          pos >= _loopB!) {
        _player.seek(_loopA!);
      }
      _updateSmtcPosition(pos);
      notifyListeners();
    });
    _durationSub = _player.stream.duration.listen((dur) {
      _duration = dur;
      _updateSmtcTimeline(force: true);
      notifyListeners();
    });
    _bufferSub = _player.stream.buffer.listen((dur) {
      _buffered = dur;
      notifyListeners();
    });
    _playingSub = _player.stream.playing.listen((playing) {
      _playing = playing;
      _updateSmtcStatus(playing);
      notifyListeners();
    });
    _audioParamsSub = _player.stream.audioParams.listen((params) {
      _audioParams = params;
      _isHiRes = _detectHiRes(params);
      notifyListeners();
    });
    _shuffleSub = _player.stream.shuffle.listen((value) {
      _isShuffle = value;
      _smtc?.setShuffleEnabled(value);
      notifyListeners();
    });
      _repeatSub = _player.stream.playlistMode.listen((mode) {
        _repeatMode = mode;
      _smtc?.setRepeatMode(
        switch (mode) {
          PlaylistMode.single => RepeatMode.track,
          PlaylistMode.loop => RepeatMode.list,
          _ => RepeatMode.none,
        },
      );
        notifyListeners();
      });
    _volumeSub = _player.stream.volume.listen((value) {
      _volume = value;
      notifyListeners();
    });
    _rateSub = _player.stream.rate.listen((value) {
      _speed = value;
      notifyListeners();
    });
    await _initSmtc();
    await refreshDevices();
  }

  Future<void> setQueue(List<app.Track> tracks, {int startIndex = 0}) async {
    _queue = tracks;
    _originalQueue = List<app.Track>.from(tracks);
    _isShuffle = false;
    try {
      await _player.setShuffle(false);
    } catch (_) {
      // ignore
    }
    _isLoading = true;
    notifyListeners();
    await _openPlaylist(_queue, startIndex, play: false);
  }

  Future<void> playTrack(app.Track track) async {
    final index = _queue.indexWhere((t) => t.id == track.id);
    if (index == -1) return;
    await _player.jump(index);
    await _player.play();
    fetchLyricsForCurrent();
    _registerHistory(track);
  }

  Future<void> _initSmtc() async {
    if (!Platform.isWindows) return;
    try {
      _smtc = SMTCWindows(
        config: const SMTCConfig(
          playEnabled: true,
          pauseEnabled: true,
          stopEnabled: true,
          nextEnabled: true,
          prevEnabled: true,
          fastForwardEnabled: false,
          rewindEnabled: false,
        ),
        shuffleEnabled: _isShuffle,
        repeatMode: switch (_repeatMode) {
          PlaylistMode.single => RepeatMode.track,
          PlaylistMode.loop => RepeatMode.list,
          _ => RepeatMode.none,
        },
      );
      _smtc?.buttonPressStream.listen(_handleSmtcButton);
      _smtc?.shuffleChangeStream.listen((value) {
        unawaited(_applyShuffle(value));
      });
      _smtc?.repeatModeChangeStream.listen((mode) {
        final playlistMode = switch (mode) {
          RepeatMode.track => PlaylistMode.single,
          RepeatMode.list => PlaylistMode.loop,
          _ => PlaylistMode.none,
        };
        unawaited(_player.setPlaylistMode(playlistMode));
      });
      _pushSmtcMetadata();
      _updateSmtcTimeline(force: true);
      _updateSmtcStatus(_playing);
    } catch (_) {
      _smtc = null;
    }
  }

  void _handleSmtcButton(PressedButton event) {
    switch (event) {
      case PressedButton.play:
        unawaited(_player.play());
        break;
      case PressedButton.pause:
        unawaited(_player.pause());
        break;
      case PressedButton.next:
        unawaited(_player.next());
        break;
      case PressedButton.previous:
        unawaited(_player.previous());
        break;
      case PressedButton.stop:
        unawaited(_player.stop());
        break;
      default:
        break;
    }
  }

  void _pushSmtcMetadata() {
    final smtc = _smtc;
    if (smtc == null) return;
    final track = _current;
    if (track == null) {
      unawaited(smtc.clearMetadata());
      return;
    }
    unawaited(() async {
      final thumb = await _resolveSmtcThumbnail(track);
      await smtc.updateMetadata(
        MusicMetadata(
          title: track.title,
          artist: track.artist,
          album: track.album,
          albumArtist: track.artist,
          thumbnail: thumb,
        ),
      );
    }());
  }

  void _updateSmtcStatus(bool playing) {
    final smtc = _smtc;
    if (smtc == null) return;
    final track = _current;
    final status = track == null
        ? PlaybackStatus.stopped
        : (playing ? PlaybackStatus.playing : PlaybackStatus.paused);
    unawaited(smtc.setPlaybackStatus(status));
  }

  void _updateSmtcPosition(Duration pos) {
    final smtc = _smtc;
    if (smtc == null) return;
    final ms = pos.inMilliseconds;
    if (_lastSmtcPositionMs != -1 &&
        (ms - _lastSmtcPositionMs).abs() < 400) {
      return;
    }
    _updateSmtcTimeline();
  }

  void _updateSmtcTimeline({bool force = false}) {
    final smtc = _smtc;
    if (smtc == null) return;
    final posMs = _position.inMilliseconds;
    final endMs = max(_duration.inMilliseconds, posMs);
    if (!force &&
        _lastSmtcPositionMs != -1 &&
        (posMs - _lastSmtcPositionMs).abs() < 400) {
      return;
    }
    _lastSmtcPositionMs = posMs;
    unawaited(
      smtc.updateTimeline(
        PlaybackTimeline(
          startTimeMs: 0,
          endTimeMs: endMs,
          positionMs: posMs,
        ),
      ),
    );
  }

  Future<String?> _resolveSmtcThumbnail(app.Track track) async {
    if (track.artworkUrl != null && track.artworkUrl!.isNotEmpty) {
      return track.artworkUrl;
    }
    final bytes = track.artworkBytes;
    if (bytes == null || bytes.isEmpty) return null;
    final cached = _smtcArtworkCache[track.id];
    if (cached != null && File(cached).existsSync()) return cached;
    try {
      final dir = Directory(p.join(Directory.systemTemp.path, 'music_smtc_art'));
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final file =
          File(p.join(dir.path, '${_sanitizeFileName(track.id)}.jpg'));
      await file.writeAsBytes(bytes, flush: true);
      _smtcArtworkCache[track.id] = file.path;
      return file.path;
    } catch (_) {
      return null;
    }
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\\\/:*?\"<>|]'), '_');
  }

  Future<void> togglePlay() async {
    await _player.playOrPause();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> addDriveTrack(
    String link, {
    String? title,
    String? artist,
  }) async {
    final uri = driveService.toDirectUri(link);
    if (uri == null) return;
    final id =
        driveService.extractFileId(link) ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final resolvedArtist = artist?.trim().isNotEmpty == true
        ? artist!.trim()
        : 'Google Drive';
    final resolvedTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : 'Drive track $id';
    final cover = await _lookupArtwork(resolvedArtist, resolvedTitle);
    final track = app.Track(
      id: 'gdrive-$id',
      title: resolvedTitle,
      artist: resolvedArtist,
      artworkUrl:
          cover ??
          'https://images.unsplash.com/photo-1511379938547-c1f69419868d',
      source: uri,
      isFromDrive: true,
      addedAt: DateTime.now(),
    );
    _library.add(track);
    _queue = [..._queue, track];
    await setQueue(_queue, startIndex: _queue.length - 1);
    await _player.play();
    _registerHistory(track);
  }

  Future<void> addDirectStream(
    Uri uri, {
    String? title,
    String? artist,
    String? artworkUrl,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final resolvedTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : 'Stream $id';
    final resolvedArtist = artist?.trim().isNotEmpty == true
        ? artist!.trim()
        : 'Unknown artist';
    final cover =
        artworkUrl ?? await _lookupArtwork(resolvedArtist, resolvedTitle);
    final track = app.Track(
      id: 'custom-$id',
      title: resolvedTitle,
      artist: resolvedArtist,
      artworkUrl: cover,
      artworkBytes: null,
      source: uri,
      addedAt: DateTime.now(),
    );
    _library.add(track);
    _queue = [..._queue, track];
    await setQueue(_queue, startIndex: _queue.length - 1);
    await _player.play();
    _registerHistory(track);
  }

  Future<bool> signInDrive() async {
    final clientId = driveService.clientId;
    if (clientId == null || clientId.contains('YOUR_DESKTOP_CLIENT_ID')) {
      _driveError = 'Chua cau hinh client_id Desktop trong main.dart';
      notifyListeners();
      return false;
    }
    _driveSigningIn = true;
    _driveError = null;
    notifyListeners();
    try {
      final scopes = ['https://www.googleapis.com/auth/drive.readonly'];
      final client = auth.ClientId(clientId, '');
      _authClient = await auth.clientViaUserConsent(
        client,
        scopes,
        _launchConsentUrl,
      );
      final creds = _authClient?.credentials;
      _driveAccessToken = creds?.accessToken.data;
      _driveEmail = 'Drive user';
      _driveError = null;
      return _driveAccessToken != null;
    } catch (_) {
      _driveError = 'Dang nhap that bai (client_id hoac consent).';
      return false;
    } finally {
      _driveSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> signOutDrive() async {
    try {
      _authClient?.close();
    } catch (_) {}
    _authClient = null;
    _driveAccessToken = null;
    _driveEmail = null;
    _driveError = null;
    notifyListeners();
  }

  void _launchConsentUrl(String url) {
    try {
      if (Platform.isWindows) {
        // Use empty title so `start` treats the next arg as URL.
        Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        Process.run('open', [url]);
      } else {
        Process.run('xdg-open', [url]);
      }
    } catch (_) {
      // ignore launcher failures
    }
  }

  void launchExternal(String url) => _launchConsentUrl(url);

  Future<void> scanDriveLibrary() async {
    if (_driveAccessToken == null) {
      final ok = await signInDrive();
      if (!ok) return;
    }
    final token = _driveAccessToken;
    if (token == null) return;
    _isLoading = true;
    notifyListeners();
    final newTracks = <app.Track>[];
    String? page;
    do {
      final res = await driveService.fetchUserAudioFiles(
        token,
        pageToken: page,
      );
      for (final file in res.files) {
        final id = 'gdrive-${file.id}';
        final already = _library.any((t) => t.id == id);
        if (already) continue;
        final uri = driveService.authorizedMediaUri(file.id, token);
        final title = p.basenameWithoutExtension(file.name);
        newTracks.add(
          app.Track(
            id: id,
            title: title,
            artist: 'Google Drive',
            album: 'My Drive',
            artworkUrl:
                'https://images.unsplash.com/photo-1511379938547-c1f69419868d',
            source: uri,
            isFromDrive: true,
            addedAt: DateTime.now(),
          ),
        );
      }
      page = res.nextPageToken;
    } while (page != null);
    if (newTracks.isNotEmpty) {
      _library.addAll(newTracks);
      _queue = [..._queue, ...newTracks];
      await setQueue(_queue, startIndex: _queue.length - newTracks.length);
    }
    _isLoading = false;
    notifyListeners();
    if (newTracks.isNotEmpty) {
      _hydrateDriveArtwork(newTracks);
    }
  }

  Future<void> addDriveFolder(String link) async {
    _isLoading = true;
    notifyListeners();
    final sharedFiles = await driveService.fetchPublicFolderFiles(link);
    final audioFiles = sharedFiles
        .where((f) => _audioExts.contains(p.extension(f.name).toLowerCase()))
        .toList();
    if (audioFiles.isEmpty) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    final tracks = <app.Track>[];
    for (final file in audioFiles) {
      final uri = driveService.toDirectUri(file.id);
      if (uri == null) continue;
      final title = p.basenameWithoutExtension(file.name);
      tracks.add(
        app.Track(
          id: 'gdrive-${file.id}',
          title: title,
          artist: 'Google Drive',
          album: 'Shared folder',
          artworkUrl:
              'https://images.unsplash.com/photo-1511379938547-c1f69419868d',
          source: uri,
          isFromDrive: true,
          addedAt: DateTime.now(),
        ),
      );
    }
    _library.addAll(tracks);
    final updated = [..._queue, ...tracks];
    await setQueue(updated, startIndex: _queue.length);
    _isLoading = false;
    notifyListeners();
    _hydrateDriveArtwork(tracks);
  }

  Future<void> addFolderTracks(String folderPath) async {
    final dir = Directory(folderPath);
    if (!dir.existsSync()) return;
    final audioFiles = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File &&
          _audioExts.contains(p.extension(entity.path).toLowerCase())) {
        audioFiles.add(entity);
      }
    }
    if (audioFiles.isEmpty) return;
    audioFiles.sort((a, b) => a.path.compareTo(b.path));
    final newTracks = <app.Track>[];
    for (final file in audioFiles) {
      final filename = p.basenameWithoutExtension(file.path);
      final trackId = _localIdForPath(file.path);
      newTracks.add(
        app.Track(
          id: trackId,
          title: filename,
          artist: 'Local file',
          album: null,
          artworkBytes: _getSidecarArt(p.dirname(file.path)),
          artworkUrl: null,
          source: Uri.file(file.path),
          addedAt: DateTime.now(),
        ),
      );
      _enrichMetadataAsync(file.path);
    }
    _library.addAll(newTracks);
    final startIndex = _queue.length;
    final updated = [..._queue, ...newTracks];
    await setQueue(updated, startIndex: startIndex);
    await _player.play();
    _registerHistory(newTracks.first);
  }

  Future<void> _enrichMetadataAsync(String path) async {
    try {
      final trackId = _localIdForPath(path);
      final existing = _library.cast<app.Track?>().firstWhere(
        (t) => t?.id == trackId,
        orElse: () => null,
      );
      final meta = await MetadataRetriever.fromFile(File(path));
      String title = meta.trackName?.trim().isNotEmpty == true
          ? meta.trackName!.trim()
          : p.basenameWithoutExtension(path);
      String artist = 'Local file';
      if ((meta.trackArtistNames ?? const []).isNotEmpty) {
        artist = meta.trackArtistNames!.first.trim().isNotEmpty
            ? meta.trackArtistNames!.first.trim()
            : artist;
      } else if ((meta.albumArtistName ?? '').trim().isNotEmpty) {
        artist = meta.albumArtistName!.trim();
      }
      String? album = meta.albumName?.trim().isNotEmpty == true
          ? meta.albumName!.trim()
          : null;
      Uint8List? art =
          meta.albumArt ??
          _getSidecarArt(p.dirname(path)) ??
          existing?.artworkBytes;
      String? coverUrl = existing?.artworkUrl;
      if (art == null && coverUrl == null) {
        coverUrl = await _lookupArtwork(artist, title);
      }
      Duration? dur;
      if (meta.trackDuration != null) {
        dur = Duration(milliseconds: meta.trackDuration!.toInt());
      }
      final updated = app.Track(
        id: trackId,
        title: title,
        artist: artist,
        album: album ?? p.basename(p.dirname(path)),
        artworkBytes: art,
        artworkUrl: coverUrl,
        source: Uri.file(path),
        addedAt: existing?.addedAt ?? DateTime.now(),
        isFromDrive: existing?.isFromDrive ?? false,
        genre: meta.genre,
        year: meta.year,
        duration: dur ?? existing?.duration,
      );
      _replaceTrack(updated);
    } catch (_) {
      // ignore metadata failures
    }
  }

  void _replaceTrack(app.Track updated) {
    final currentBefore = _current;
    bool changed = false;
    for (var i = 0; i < _library.length; i++) {
      if (_library[i].id == updated.id) {
        _library[i] = updated;
        changed = true;
        break;
      }
    }
    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i].id == updated.id) {
        _queue[i] = updated;
        changed = true;
      }
    }
    for (var i = 0; i < _history.length; i++) {
      if (_history[i].id == updated.id) {
        _history[i] = updated;
        changed = true;
      }
    }
    if (changed) {
      if (_current?.id == updated.id) {
        _current = updated;
        if (currentBefore?.title != updated.title ||
            currentBefore?.artist != updated.artist) {
          fetchLyricsForCurrent();
        }
      }
      notifyListeners();
    }
  }

  void _requestMetadataIfNeeded(app.Track track) {
    if (track.album != null && track.artist != 'Local file') return;
    if (track.source.isScheme('file')) {
      final path = track.source.toFilePath();
      _enrichMetadataAsync(path);
    }
  }

  Future<void> fetchLyricsForCurrent() async {
    final track = _current;
    if (track == null) return;
    final previous = _lyrics ?? _lyricsStore[track.id];
    try {
      final dur = track.duration ?? _duration;
      LyricsResult? result;
      for (final query in _buildLyricQueries(track)) {
        result = await lyricsService.fetch(
          query.artist,
          query.title,
          album: track.album,
          duration: dur,
          preferred: _lyricsSource,
        );
        if (result != null && result.lyrics.trim().isNotEmpty) {
          break;
        }
      }
      if (result != null && result.lyrics.trim().isNotEmpty) {
        _lyrics = result;
        _lyricsStore[track.id] = result;
      } else if (previous != null) {
        // Keep existing lyrics if refresh fails or returns empty.
        _lyrics = previous;
      } else {
        _lyrics = null;
      }
      notifyListeners();
    } catch (_) {
      _lyrics = previous;
      notifyListeners();
    }
  }

  Future<void> setWasapiExclusive(bool value) async {
    _wasapiExclusive = value;
    await _applyWasapi();
    notifyListeners();
  }

  void setPlaybackTheme(PlaybackTheme theme) {
    if (_playbackTheme == theme) return;
    _playbackTheme = theme;
    notifyListeners();
  }

  void setPreamp(double db) {
    _preampDb = db;
    if (_wasapiExclusive) {
      notifyListeners();
      return;
    }
    final linear = _dbToLinear(db);
    final scaled = (linear * 70).clamp(0.0, 120.0);
    _player.setVolume(scaled);
    _applyEqFilters();
    notifyListeners();
  }

  void updateEqBand(int freq, double db) {
    _eqGains[freq] = db;
    if (_wasapiExclusive) {
      notifyListeners();
      return;
    }
    _applyEqFilters();
    notifyListeners();
  }

  double _dbToLinear(double db) {
    return (db <= -50) ? 0 : pow(10, db / 20).toDouble();
  }

  Future<void> refreshEndpoints() async {
    // kept for API compatibility; now delegates to media_kit device discovery.
    await refreshDevices();
  }

  @override
  void dispose() {
    _playlistSub?.cancel();
    _deviceSub?.cancel();
    _selectedDeviceSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferSub?.cancel();
    _playingSub?.cancel();
    _audioParamsSub?.cancel();
    _shuffleSub?.cancel();
    _repeatSub?.cancel();
    _volumeSub?.cancel();
    _rateSub?.cancel();
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _smtc?.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> refreshDevices() async {
    try {
      final devices = _player.state.audioDevices;
      _devices = devices;
      _selectedDevice = _player.state.audioDevice;
      if (_selectedDevice == null && devices.isNotEmpty) {
        _selectedDevice = devices.first;
      }
      await _applyWasapi();
      notifyListeners();
    } catch (_) {
      // ignore
    }
  }

  Future<void> setAudioDevice(AudioDevice device) async {
    await _player.setAudioDevice(device);
    _selectedDevice = device;
    await _applyWasapi();
    notifyListeners();
  }

  Future<void> previous() async {
    await _player.previous();
  }

  Future<void> next() async {
    await _player.next();
  }

  Future<void> _applyEqFilters() async {
    if (_wasapiExclusive) return;
    try {
      final parts = _eqGains.entries
          .where((e) => e.value.abs() > 0.01)
          .map(
            (e) =>
                'equalizer=f=${e.key}:width_type=q:width=1.0:g=${e.value.toStringAsFixed(1)}',
          )
          .toList();
      final filter = parts.join(',');
      final platform = _player.platform;
      if (platform != null) {
        await (platform as dynamic).setProperty('af', filter);
      }
    } catch (_) {
      // ignore failures to set filters
    }
  }

  Future<String?> _lookupArtwork(String artist, String title) async {
    final key = '$artist|$title';
    if (_artworkCache.containsKey(key)) return _artworkCache[key];
    final term = '$artist $title'.trim();
    if (term.isEmpty) return null;
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': term,
      'entity': 'song',
      'limit': '1',
    });
    try {
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final json = resp.body;
        if (json.contains('artworkUrl100')) {
          final idx = json.indexOf('artworkUrl100');
          if (idx != -1) {
            final start = json.indexOf('http', idx);
            final end = json.indexOf('"', start);
            if (start != -1 && end != -1) {
              final url100 = json.substring(start, end);
              final hiRes = url100.replaceAll('100x100', '600x600');
              _artworkCache[key] = hiRes;
              return hiRes;
            }
          }
        }
      }
    } catch (_) {
      // ignore lookup errors
    }
    _artworkCache[key] = null;
    return null;
  }

  Future<void> toggleShuffle() async {
    await _applyShuffle(!_isShuffle);
  }

  Future<void> _applyWasapi() async {
    if (!Platform.isWindows) return;
    try {
      final platform = _player.platform;
      if (platform == null) return;
      final backend = platform as dynamic;
      await backend.setProperty(
        'audio-exclusive',
        _wasapiExclusive ? 'yes' : 'no',
      );
      if (_selectedDevice != null) {
        await backend.setProperty(
          'audio-device',
          _selectedDevice!.name,
        );
      }
      if (_wasapiExclusive) {
        _volumeBeforeExclusive ??= _volume;
        await backend.setProperty('af', '');
        try {
          await backend.setProperty('audio-resample', 'no');
        } catch (_) {
          // best-effort: mpv may not expose this property
        }
        _volume = 100;
        notifyListeners();
        await _player.setVolume(100);
      } else {
        final restoreVolume = _volumeBeforeExclusive;
        _volumeBeforeExclusive = null;
        await _applyEqFilters();
        if (restoreVolume != null) {
          _volume = restoreVolume;
          notifyListeners();
          await _player.setVolume(restoreVolume);
        }
      }
    } catch (_) {
      // ignore failures silently for unsupported backends
    }
  }

  Future<void> _hydrateDriveArtwork(List<app.Track> tracks) async {
    for (final t in tracks) {
      try {
        final art = await _lookupArtwork(t.artist, t.title);
        if (art != null) {
          _replaceTrack(
            app.Track(
              id: t.id,
              title: t.title,
              artist: t.artist,
              album: t.album,
              artworkUrl: art,
              artworkBytes: t.artworkBytes,
              source: t.source,
              isFromDrive: t.isFromDrive,
              addedAt: t.addedAt,
              genre: t.genre,
              year: t.year,
            ),
          );
        }
      } catch (_) {
        // ignore lookup failures
      }
    }
  }

  String _localIdForPath(String path) {
    final normalized = p.normalize(path);
    final encoded = base64Url.encode(utf8.encode(normalized));
    return 'local-$encoded';
  }

  Uint8List? _getSidecarArt(String dir) {
    final key = p.normalize(dir);
    if (_sidecarArtCache.containsKey(key)) return _sidecarArtCache[key];
    final candidates = ['cover.jpg', 'cover.png', 'folder.jpg', 'folder.png'];
    for (final name in candidates) {
      final file = File(p.join(dir, name));
      if (file.existsSync()) {
        try {
          final bytes = file.readAsBytesSync();
          _sidecarArtCache[key] = bytes;
          return bytes;
        } catch (_) {
          // ignore broken images
        }
      }
    }
    _sidecarArtCache[key] = null;
    return null;
  }

  Future<void> cycleRepeat() async {
    final next = switch (_repeatMode) {
      PlaylistMode.none => PlaylistMode.loop,
      PlaylistMode.loop => PlaylistMode.single,
      PlaylistMode.single => PlaylistMode.none,
    };
    await _player.setPlaylistMode(next);
  }

  Future<void> setVolume(double value) async {
    if (_wasapiExclusive) {
      notifyListeners();
      return;
    }
    _volume = value.clamp(0, 100).toDouble();
    notifyListeners();
    await _player.setVolume(_volume);
  }

  Future<void> setSpeed(double value) async {
    _speed = value;
    notifyListeners();
    await _player.setRate(value);
  }

  Future<void> setSleepTimer(Duration? duration) async {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (duration != null) {
      _sleepTimer = Timer(duration, () async {
        try {
          await _player.pause();
        } catch (_) {
          // ignore pause failure
        } finally {
          _sleepTimer = null;
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  void setLoopA() {
    _loopA = _position;
    notifyListeners();
  }

  void setLoopB() {
    _loopB = _position;
    notifyListeners();
  }

  void setLyricsSource(LyricsSource source) {
    if (_lyricsSource == source) return;
    _lyricsSource = source;
    _lyricsStore.clear();
    _lyrics = null;
    fetchLyricsForCurrent();
    notifyListeners();
  }

  void clearLoopAB() {
    _loopA = null;
    _loopB = null;
    notifyListeners();
  }

  void _registerHistory(app.Track track) {
    _history.removeWhere((t) => t.id == track.id);
    _history.insert(0, track);
    if (_history.length > 50) {
      _history.removeLast();
    }
    notifyListeners();
  }

  void addPinnedFolder(String path) {
    if (!_pinnedFolders.contains(path)) {
      _pinnedFolders.add(path);
      addFolderTracks(path);
    }
  }

  void removePinnedFolder(String path) {
    _pinnedFolders.remove(path);
    notifyListeners();
  }

  List<app.Track> recentlyAdded([int limit = 20]) {
    final sorted = [..._library]
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return sorted.take(limit).toList();
  }

  List<app.Track> recentlyPlayed([int limit = 20]) {
    return history.take(limit).toList();
  }

  List<app.Track> search(String query) {
    _searchQuery = query;
    final lower = query.toLowerCase();
    return _library.where((t) {
      return t.title.toLowerCase().contains(lower) ||
          t.artist.toLowerCase().contains(lower) ||
          (t.album?.toLowerCase().contains(lower) ?? false);
    }).toList();
  }

  void createPlaylist(String name) {
    if (!_playlists.containsKey(name)) {
      _playlists[name] = [];
      notifyListeners();
    }
  }

  void deletePlaylist(String name) {
    _playlists.remove(name);
    notifyListeners();
  }

  void addToPlaylist(String name, app.Track track) {
    if (_playlists.containsKey(name)) {
      final list = _playlists[name]!;
      list.add(track);
      notifyListeners();
    }
  }

  void removeFromPlaylist(String name, int index) {
    if (_playlists.containsKey(name)) {
      final list = _playlists[name]!;
      if (index >= 0 && index < list.length) {
        list.removeAt(index);
        notifyListeners();
      }
    }
  }

  void moveInPlaylist(String name, int oldIndex, int newIndex) {
    if (_playlists.containsKey(name)) {
      final list = _playlists[name]!;
      if (oldIndex < newIndex) newIndex -= 1;
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
      notifyListeners();
    }
  }

  Future<void> playPlaylist(String name, {bool shuffle = false}) async {
    final list = _playlists[name];
    if (list == null || list.isEmpty) return;
    var playList = List<app.Track>.from(list);
    if (shuffle) {
      playList = _smartShuffle(playList);
    }
    await setQueue(playList, startIndex: 0);
    await _player.play();
  }

  List<app.Track> _smartShuffle(List<app.Track> tracks) {
    if (tracks.length <= 2) return tracks;
    final result = <app.Track>[];
    final byArtist = <String, List<app.Track>>{};
    for (final t in tracks) {
      byArtist.putIfAbsent(t.artist, () => []).add(t);
    }
    final artists = byArtist.keys.toList()..shuffle();
    while (result.length < tracks.length) {
      for (final artist in artists) {
        final bucket = byArtist[artist]!;
        if (bucket.isNotEmpty) {
          result.add(bucket.removeLast());
        }
      }
    }
    return result;
  }

  bool _detectHiRes(AudioParams params) {
    final format = (params.format ?? '').toLowerCase();
    final rate = params.sampleRate ?? 0;
    if (format.contains('24') ||
        format.contains('32') ||
        format.contains('float')) {
      return true;
    }
    if (rate >= 88200) return true;
    return false;
  }

  Future<void> _openPlaylist(
    List<app.Track> tracks,
    int startIndex, {
    required bool play,
  }) async {
    final playlist = Playlist(
      tracks
          .map(
            (t) => Media(
              t.source.toString(),
              extras: {
                'id': t.id,
                'title': t.title,
                'artist': t.artist,
                'album': t.album,
                'artwork': t.artworkUrl,
              },
            ),
          )
          .toList(),
      index: startIndex,
    );
    // Try to enrich missing metadata when we open a playlist.
    for (final t in tracks) {
      _requestMetadataIfNeeded(t);
    }
    await _player.open(playlist, play: play);
    if (play) {
      await _player.play();
    }
    _isLoading = false;
    final prevLyrics = _lyrics;
    final prevId = _current?.id;
    _currentIndex = startIndex;
    _current = tracks.isNotEmpty ? tracks[startIndex] : null;
    // Preserve lyrics if we reopen the same track (e.g., shuffle toggle).
    if (prevLyrics != null && _current?.id == prevId) {
      _lyrics = prevLyrics;
    } else {
      _lyrics = _current != null ? _lyricsStore[_current!.id] : null;
    }
    fetchLyricsForCurrent();
    _pushSmtcMetadata();
    _updateSmtcTimeline(force: true);
    _updateSmtcStatus(_playing);
    notifyListeners();
  }

  Future<void> _applyShuffle(bool enable) async {
    if (_queue.isEmpty) return;
    final currentTrack = _current ?? _queue[_currentIndex];
    final currentPos = _position;
    final wasPlaying = _playing;
    _isShuffle = enable;

    if (enable) {
      // Preserve original order for restore.
      _originalQueue = List<app.Track>.from(_queue);
      final others = List<app.Track>.from(_queue)
        ..removeWhere((t) => t.id == currentTrack.id);
      others.shuffle();
      _queue = [currentTrack, ...others];
      await _openPlaylist(_queue, 0, play: wasPlaying);
    } else {
      if (_originalQueue.isEmpty) return;
      final restored = List<app.Track>.from(_originalQueue);
      final newIndex = restored.indexWhere((t) => t.id == currentTrack.id);
      _queue = restored;
      await _openPlaylist(
        _queue,
        newIndex >= 0 ? newIndex : 0,
        play: wasPlaying,
      );
    }

    final hasCurrentInQueue =
        _queue.any((element) => element.id == currentTrack.id);
    if (hasCurrentInQueue && currentPos > Duration.zero) {
      await _player.seek(currentPos);
      _position = currentPos;
      notifyListeners();
    }

    // Keep mpv shuffle disabled; we manage order ourselves to keep UI and audio in sync.
    await _player.setShuffle(false);
  }

  ({String artist, String title}) _resolveLyricsQuery(app.Track track) {
    var artist = track.artist.trim();
    var title = track.title.trim();

    // If artist is generic, try to extract from "Artist - Title" filename pattern.
    final isGenericArtist =
        artist.isEmpty ||
        artist.toLowerCase() == 'local file' ||
        artist.toLowerCase() == 'google drive' ||
        artist.toLowerCase() == 'unknown artist';
    if (isGenericArtist && title.contains('-')) {
      final parts = title.split(RegExp(r'\\s*-\\s*'));
      if (parts.length >= 2) {
        artist = parts.first.trim();
        title = parts.sublist(1).join(' - ').trim();
      }
    }

    // Strip copy/numbering suffixes like "(1)".
    title = title.replaceAll(RegExp(r'\\s*\\(\\d+\\)\\s*$'), '').trim();
    // Collapse whitespace.
    title = title.replaceAll(RegExp(r'\\s+'), ' ').trim();
    if (artist.isEmpty) artist = 'Unknown';

    return (artist: artist, title: title);
  }

  List<({String artist, String title})> _buildLyricQueries(app.Track track) {
    final base = _resolveLyricsQuery(track);
    final variants = <({String artist, String title})>[base];

    // Swap artist/title as fallback for reversed tags.
    if (base.title.isNotEmpty && base.artist.isNotEmpty) {
      variants.add((artist: base.title, title: base.artist));
    }

    // If title contains a dash, try splitting both directions.
    if (track.title.contains('-')) {
      final parts = track.title.split(RegExp(r'\s*-\s*'));
      if (parts.length >= 2) {
        final altArtist = parts.first.trim();
        final altTitle = parts.sublist(1).join(' - ').trim();
        variants.add((artist: altArtist, title: altTitle));
        variants.add((artist: altTitle, title: altArtist));
      }
    }

    // Deduplicate while preserving order.
    final seen = <String>{};
    return variants.where((q) {
      final key = '${q.artist.toLowerCase()}|${q.title.toLowerCase()}';
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();
  }
}
