// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;

import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:smtc_windows/smtc_windows.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'models/track.dart' as app;
import 'services/google_drive_service.dart';
import 'services/lyrics_service.dart';
import 'state/player_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await SMTCWindows.initialize();
  }
  await windowManager.ensureInitialized();
  MediaKit.ensureInitialized();

  const windowOptions = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MusicApp());
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => PlayerNotifier(
            driveService: const GoogleDriveService(
              clientId:
                  '394968286344-5nn71cjvr9mt8t9snsm2479vfthj8q32.apps.googleusercontent.com',
            ),
            lyricsService: const LyricsService(),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Music Player',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.grey.shade800,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF121212),
          useMaterial3: true,
        ),
        home: const PlayerScreen(),
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  final _driveController = TextEditingController();
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _folderController = TextEditingController();
  final _streamController = TextEditingController(text: '');
  PaletteGenerator? _palette;
  String? _paletteTrackId;
  String? _paletteLoadingId;
  final Map<String, List<Color>> _paletteCache = {};
  final Map<String, List<_LyricLine>> _lyricsCache = {};
  late final AnimationController _discController;
  bool _discSpinning = false;
  bool _lyricsOverlay = false;
  final ScrollController _lyricsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _discController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );
  }

  Future<void> _openThemeSheet(PlayerNotifier notifier) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18191f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Consumer<PlayerNotifier>(
          builder: (context, state, _) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  RadioListTile<PlaybackTheme>(
                    value: PlaybackTheme.vinyl,
                    groupValue: state.playbackTheme,
                    title: const Text('Vinyl turntable'),
                    subtitle:
                        const Text('Hi-fi vibe with spinning vinyl + cover'),
                    onChanged: (_) =>
                        state.setPlaybackTheme(PlaybackTheme.vinyl),
                  ),
                  RadioListTile<PlaybackTheme>(
                    value: PlaybackTheme.cd,
                    groupValue: state.playbackTheme,
                    title: const Text('CD deck'),
                    subtitle: const Text(
                        'Show disc + head unit, hide cover art overlay'),
                    onChanged: (_) => state.setPlaybackTheme(PlaybackTheme.cd),
                  ),
                  RadioListTile<PlaybackTheme>(
                    value: PlaybackTheme.artwork,
                    groupValue: state.playbackTheme,
                    title: const Text('Artwork only'),
                    subtitle: const Text('Just the cover — no spinning disc'),
                    onChanged: (_) =>
                        state.setPlaybackTheme(PlaybackTheme.artwork),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _discController.dispose();
    _driveController.dispose();
    _titleController.dispose();
    _artistController.dispose();
    _folderController.dispose();
    _streamController.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<PlayerNotifier>();
    final track = notifier.current;
    _syncDiscSpin(notifier.playing);
    _ensurePalette(track);

    return Scaffold(
      body: Stack(
        children: [
          _buildBlurredBackground(track),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Column(
                children: [
                  _buildTopActions(notifier),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final minHeight = constraints.maxHeight > 80
                            ? constraints.maxHeight - 80
                            : constraints.maxHeight;
                        if (_lyricsOverlay && track != null) {
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            child: Row(
                              key: const ValueKey('lyrics-overlay'),
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: ConstrainedBox(
                                      constraints:
                                          BoxConstraints(minHeight: minHeight),
                                      child: Center(
                                        child: _buildNowPlaying(
                                            context, notifier, track),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  flex: 5,
                                  child: _buildLyricsPanel(
                                    notifier,
                                    track,
                                    minHeight,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: minHeight),
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 240),
                                child: track == null
                                    ? _buildEmptyState(notifier)
                                    : _buildNowPlaying(context, notifier, track),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopActions(PlayerNotifier notifier) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => _dragWindow(),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Add music',
            icon: const Icon(Icons.add),
            onPressed: () => _openAddMenu(notifier),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Library',
            icon: const Icon(Icons.library_music_outlined),
            onPressed: () => _openLibrarySheet(notifier),
          ),
          IconButton(
            tooltip: 'Queue',
            icon: const Icon(Icons.queue_music),
            onPressed: () => _openQueueSheet(notifier),
          ),
          IconButton(
            tooltip: 'Devices',
            icon: const Icon(Icons.cast),
            onPressed: () => _openDeviceSheet(notifier),
          ),
          IconButton(
            tooltip: 'Minimize',
            icon: const Icon(Icons.minimize),
            onPressed: _minimizeWindow,
          ),
          IconButton(
            tooltip: 'Maximize / Restore',
            icon: const Icon(Icons.crop_square),
            onPressed: _toggleMaximize,
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
    );
  }

  Future<void> _dragWindow() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    try {
      await windowManager.startDragging();
    } catch (_) {
      // ignore drag failures
    }
  }

  Future<void> _minimizeWindow() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    try {
      await windowManager.minimize();
    } catch (_) {
      // ignore minimize failures
    }
  }

  void _syncDiscSpin(bool playing) {
    if (playing == _discSpinning) return;
    _discSpinning = playing;
    if (playing) {
      _discController.repeat();
    } else {
      _discController.stop();
    }
  }

  Future<void> _toggleMaximize() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    try {
      final isMax = await windowManager.isMaximized();
      if (isMax) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {
      // ignore maximize failures
    }
  }

  Widget _buildNowPlaying(
    BuildContext context,
    PlayerNotifier notifier,
    app.Track track,
  ) {
    final size = MediaQuery.of(context).size;
    final artSize = size.width < 520
        ? size.width - 80
        : size.width < 900
            ? 340.0
            : 360.0;
    final subtitleParts = <String>[
      track.artist,
      if ((track.album ?? '').trim().isNotEmpty) track.album!.trim(),
    ];
    final subtitle = subtitleParts.where((p) => p.trim().isNotEmpty).join(' - ');
    final isCd = notifier.playbackTheme == PlaybackTheme.cd;
    final isArtworkOnly = notifier.playbackTheme == PlaybackTheme.artwork;

    return Column(
      key: ValueKey(track.id),
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 35,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: isCd
              ? _buildCdDeck(track, notifier.playing, artSize)
              : isArtworkOnly
                  ? _buildArtworkOnly(track, artSize)
                  : _buildVinylArt(track, notifier.playing, artSize),
        ),
        const SizedBox(height: 20),
        Text(
          track.title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
        ),
        const SizedBox(height: 6),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white70,
                ),
          ),
        const SizedBox(height: 10),
        _buildQualityBadge(notifier),
        const SizedBox(height: 16),
        _buildTimeline(notifier),
        const SizedBox(height: 12),
        _buildControlsRow(notifier),
      ],
    );
  }

  Widget _buildVinylArt(app.Track track, bool playing, double artSize) {
    final discSize = artSize * 0.9;
    final pullOut = artSize * 0.62;
    final leftOffset = playing ? -discSize * 0.45 : -pullOut;
    final height = artSize;
    return SizedBox(
      width: artSize,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOut,
            left: leftOffset,
            top: (height - discSize) / 2,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              opacity: playing ? 1.0 : 0.0,
              child: AnimatedBuilder(
                animation: _discController,
                builder: (_, child) => Transform.rotate(
                  angle: _discController.value * 2 * math.pi,
                  child: child,
                ),
                child: _buildVinylDisc(track, discSize),
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: artSize,
                height: artSize,
                child: _buildArtwork(track),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtworkOnly(app.Track track, double artSize) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: artSize,
        height: artSize,
        child: _buildArtwork(track),
      ),
    );
  }

  Widget _buildCdDeck(app.Track track, bool playing, double artSize) {
    final discSize = artSize * 0.86;
    final deckHeight = artSize * 1.05;
    final discKey = ValueKey('cd-${track.id}');
    return SizedBox(
      width: artSize * 1.1,
      height: deckHeight,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.06),
                    Colors.black.withOpacity(0.12),
                  ],
                ),
                border: Border.all(color: Colors.white10, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 28,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(
                    color: Colors.black.withOpacity(0.16),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: artSize * 0.06,
            top: deckHeight * 0.22,
            bottom: deckHeight * 0.22,
            child: Opacity(
              opacity: 0.7,
              child: Container(
                width: artSize * 0.14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFcfd3da), Color(0xFFa7adb6)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(2, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 1000),
            reverseDuration: const Duration(milliseconds: 800),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) => Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                ...previous,
                if (current != null) current,
              ],
            ),
            transitionBuilder: (child, animation) {
              final isIncoming = child.key == discKey;
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              );
              final slide = isIncoming
                  ? Tween<Offset>(
                      begin: const Offset(1.5, 0),
                      end: Offset.zero,
                    ).animate(curved)
                  : Tween<Offset>(
                      begin: const Offset(-1.5, 0),
                      end: Offset.zero,
                    ).animate(curved);
              return SlideTransition(
                position: slide,
                child: FadeTransition(opacity: curved, child: child),
              );
            },
            child: AnimatedOpacity(
              key: discKey,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              opacity: 1.0,
              child: AnimatedBuilder(
                animation: _discController,
                builder: (_, child) => Transform.rotate(
                  angle: _discController.value * 2 * math.pi,
                  child: child,
                ),
                child: _buildVinylDisc(track, discSize),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVinylDisc(app.Track track, double size) {
    final label = _artworkProvider(track);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const SweepGradient(
          colors: [
            Color(0xFF0f0f12),
            Color(0xFF1b1c22),
            Color(0xFF0f0f12),
          ],
          stops: [0.0, 0.6, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.92,
            height: size * 0.92,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color(0xFF1d1e24),
                  Color(0xFF0e0f13),
                  Color(0xFF0b0c10),
                ],
                stops: [0.25, 0.65, 1],
              ),
            ),
          ),
          Container(
            width: size * 0.38,
            height: size * 0.38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black,
              border: Border.all(color: Colors.white12, width: 1.2),
              image: label != null
                  ? DecorationImage(image: label, fit: BoxFit.cover)
                  : null,
            ),
            child: label == null
                ? const Icon(Icons.music_note, color: Colors.white54)
                : null,
          ),
          Container(
            width: size * 0.08,
            height: size * 0.08,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityBadge(PlayerNotifier notifier) {
    final label = notifier.isHiRes ? 'Hi-Res' : 'Lossless';
    final color = notifier.isHiRes ? const Color(0xFFFFD700) : Colors.white70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.asset(
              'hi-res_logo.jpg',
              width: 18,
              height: 18,
              fit: BoxFit.cover,
              color: notifier.isHiRes ? null : Colors.white38,
              colorBlendMode:
                  notifier.isHiRes ? BlendMode.srcIn : BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(PlayerNotifier notifier) {
    final pos = notifier.position;
    final total = notifier.duration;
    final remaining = total - pos;
    final safeRemaining =
        remaining.isNegative ? Duration.zero : remaining;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              _formatDuration(pos),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Expanded(
            child: ProgressBar(
              barHeight: 6,
              baseBarColor: Colors.white24,
              bufferedBarColor: Colors.white38,
              progressBarColor: Colors.white,
              thumbColor: Colors.white,
              timeLabelLocation: TimeLabelLocation.none,
              progress: pos,
              buffered: notifier.buffered,
              total: total,
              onSeek: notifier.seek,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              '-${_formatDuration(safeRemaining)}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsRow(PlayerNotifier notifier) {
    final iconColor = Colors.white;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.volume_up),
          color: iconColor.withOpacity(0.8),
          onPressed: () => _openVolumeSheet(notifier),
        ),
        IconButton(
          icon: const Icon(Icons.more_horiz),
          color: iconColor.withOpacity(0.8),
          onPressed: () => _openSettingsSheet(notifier),
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded),
          color: iconColor,
          iconSize: 32,
          onPressed: notifier.hasPrevious ? notifier.previous : null,
        ),
        IconButton(
          icon: Icon(
            notifier.playing
                ? Icons.pause_circle_filled
                : Icons.play_circle_fill,
          ),
          color: iconColor,
          iconSize: 48,
          onPressed: notifier.togglePlay,
        ),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded),
          color: iconColor,
          iconSize: 32,
          onPressed: notifier.hasNext ? notifier.next : null,
        ),
        IconButton(
          icon: Icon(
            Icons.shuffle,
            color: notifier.isShuffle ? Colors.white : Colors.white70,
          ),
          onPressed: notifier.toggleShuffle,
        ),
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline),
          color: _lyricsOverlay ? Colors.white : iconColor.withOpacity(0.8),
          onPressed: () {
            if (notifier.current == null) return;
            setState(() => _lyricsOverlay = !_lyricsOverlay);
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState(PlayerNotifier notifier) {
    return Column(
      key: const ValueKey('empty-state'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.music_note, size: 48, color: Colors.white70),
        const SizedBox(height: 12),
        const Text(
          'Add music to start listening',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => _openDriveSheet(notifier),
              icon: const Icon(Icons.cloud_download),
              label: const Text('Drive'),
            ),
            FilledButton.icon(
              onPressed: () => _openFolderSheet(notifier),
              icon: const Icon(Icons.folder_open),
              label: const Text('Folder'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openStreamSheet(notifier),
              icon: const Icon(Icons.link),
              label: const Text('URL / Stream'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBlurredBackground(app.Track? track) {
    final colors = _paletteColors();
    final provider = track != null ? _artworkProvider(track) : null;

    return Positioned.fill(
      child: Stack(
        children: [
          if (provider != null)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 35, sigmaY: 35),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(0.45),
                    BlendMode.darken,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: provider,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors[0],
                  colors[1],
                  Colors.black.withOpacity(0.9),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _ensurePalette(app.Track? track) {
    if (track == null) {
      if (_palette != null || _paletteTrackId != null) {
        setState(() {
          _palette = null;
          _paletteTrackId = null;
          _paletteLoadingId = null;
        });
      }
      return;
    }
    final cached = _paletteCache[track.id];
    if (_paletteTrackId == track.id && (cached != null || _palette != null)) {
      return;
    }
    _paletteTrackId = track.id;
    if (cached != null) {
      // Reuse cached colors immediately to avoid UI hitching.
      setState(() {});
    }
    final provider = _paletteProvider(track);
    if (provider == null) return;
    _paletteLoadingId = track.id;
    PaletteGenerator.fromImageProvider(
      provider,
      maximumColorCount: 8,
      size: const Size(96, 96),
    ).then((value) {
      if (!mounted || _paletteLoadingId != track.id) return;
      final colors = _colorsFromPalette(value);
      setState(() {
        _palette = value;
        _paletteCache[track.id] = colors;
      });
    }).catchError((_) {
      // ignore palette failures
    });
  }

  List<Color> _paletteColors() {
    final cached = _paletteTrackId != null
        ? _paletteCache[_paletteTrackId!]
        : null;
    if (cached != null) return cached;
    return _colorsFromPalette(_palette);
  }

  ImageProvider? _artworkProvider(app.Track track) {
    final bytes = track.artworkBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return MemoryImage(bytes);
    }
    final url = track.artworkUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImageProvider(url);
    }
    return null;
  }

  ImageProvider? _paletteProvider(app.Track track) {
    final bytes = track.artworkBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return ResizeImage.resizeIfNeeded(160, 160, MemoryImage(bytes));
    }
    final url = track.artworkUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImageProvider(url);
    }
    return null;
  }

  List<Color> _colorsFromPalette(PaletteGenerator? palette) {
    final primary = palette?.dominantColor?.color;
    final secondary =
        palette?.vibrantColor?.color ?? palette?.mutedColor?.color;
    final start = primary ?? const Color(0xFF1c191c);
    final end = secondary ?? const Color(0xFF0f0d10);
    return [
      start.withOpacity(0.95),
      end.withOpacity(0.9),
    ];
  }

  Future<void> _openAddMenu(PlayerNotifier notifier) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18191f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_download),
                title: const Text('Add from Google Drive'),
                onTap: () {
                  Navigator.pop(context);
                  _openDriveSheet(notifier);
                },
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Add URL / Stream'),
                onTap: () {
                  Navigator.pop(context);
                  _openStreamSheet(notifier);
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Folder'),
                onTap: () {
                  Navigator.pop(context);
                  _openFolderSheet(notifier);
                },
              ),
              ListTile(
                leading: const Icon(Icons.equalizer),
                title: const Text('Equalizer / Preamp'),
                onTap: () {
                  Navigator.pop(context);
                  _openEqSheet(notifier);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openLibrarySheet(PlayerNotifier notifier) async {
    final albums = _groupAlbums(notifier.library);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF18191f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: DefaultTabController(
            length: 2,
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Albums'),
                      Tab(text: 'Songs'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildAlbumList(context, notifier, albums),
                        _buildSongList(context, notifier, notifier.library),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumList(
    BuildContext context,
    PlayerNotifier notifier,
    Map<String, List<app.Track>> albums,
  ) {
    if (albums.isEmpty) {
      return const Center(child: Text('No albums yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: albums.length,
      separatorBuilder: (_, index) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (context, index) {
        final entry = albums.entries.elementAt(index);
        final title = entry.key;
        final tracks = entry.value;
        final lead = tracks.first;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: _buildArtwork(lead),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${lead.artist} - ${tracks.length} track${tracks.length == 1 ? '' : 's'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () async {
                  await notifier.setQueue(tracks, startIndex: 0);
                  await notifier.playTrack(tracks.first);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSongList(
    BuildContext context,
    PlayerNotifier notifier,
    List<app.Track> tracks,
  ) {
    if (tracks.isEmpty) {
      return const Center(child: Text('No songs yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: tracks.length,
      separatorBuilder: (_, index) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (context, index) {
        final t = tracks[index];
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: _buildArtwork(t),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${t.artist}${t.album != null ? ' - ${t.album}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatDuration(t.duration),
                style: const TextStyle(color: Colors.white70),
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () async {
                  await notifier.setQueue(tracks, startIndex: index);
                  await notifier.playTrack(t);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArtwork(app.Track track) {
    final artBytes = track.artworkBytes;
    if (artBytes != null && artBytes.isNotEmpty) {
      return Image.memory(artBytes, fit: BoxFit.cover);
    }
    final art = track.artworkUrl;
    if (art != null && art.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: art,
        fit: BoxFit.cover,
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2a2b32), Color(0xFF1c1d22)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.album, size: 42, color: Colors.white70),
      ),
    );
  }

  Map<String, List<app.Track>> _groupAlbums(List<app.Track> tracks) {
    final map = <String, List<app.Track>>{};
    for (final t in tracks) {
      final key = (t.album?.trim().isNotEmpty ?? false)
          ? t.album!.trim()
          : 'Unknown Album';
      map.putIfAbsent(key, () => []).add(t);
    }
    return map;
  }

  Future<void> _openDriveSheet(PlayerNotifier notifier) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18191f),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add from Google Drive',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      notifier.driveSignedIn
                          ? 'Signed in as ${notifier.driveEmail}'
                          : 'Not signed in to Drive (OAuth)',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  FilledButton.icon(
                    icon: Icon(
                      notifier.driveSignedIn ? Icons.logout : Icons.login,
                    ),
                    label: Text(
                      notifier.driveSignedIn ? 'Sign out' : 'Sign in',
                    ),
                    onPressed: notifier.driveSigningIn
                        ? null
                        : () async {
                            if (notifier.driveSignedIn) {
                              await notifier.signOutDrive();
                            } else {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await notifier.signInDrive();
                              if (!ok) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Sign-in failed. Check client id / consent, then try again.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                  ),
                ],
              ),
              if (notifier.driveError != null) ...[
                const SizedBox(height: 8),
                Text(
                  notifier.driveError!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
              const SizedBox(height: 6),
              FilledButton.icon(
                icon: const Icon(Icons.search),
                label: const Text('Scan my Drive (audio files)'),
                onPressed: notifier.driveSigningIn
                    ? null
                    : notifier.scanDriveLibrary,
              ),
              const Divider(height: 24),
              const SizedBox(height: 12),
              TextField(
                controller: _driveController,
                decoration: const InputDecoration(
                  labelText: 'Share link or file id',
                  hintText: 'https://drive.google.com/file/d/.../view',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title (optional)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _artistController,
                      decoration: const InputDecoration(
                        labelText: 'Artist (optional)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: const Icon(Icons.cloud_download),
                  label: const Text('Stream from Drive'),
                  onPressed: () {
                    final link = _driveController.text.trim();
                    if (link.isEmpty) return;
                    notifier.addDriveTrack(
                      link,
                      title: _titleController.text,
                      artist: _artistController.text,
                    );
                    Navigator.pop(context);
                  },
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: const Icon(Icons.folder_shared),
                  label: const Text('Add shared folder'),
                  onPressed: () async {
                    final link = _driveController.text.trim();
                    if (link.isEmpty) return;
                    await notifier.addDriveFolder(link);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openStreamSheet(PlayerNotifier notifier) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18191f),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add stream URL',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _streamController,
                decoration: const InputDecoration(
                  labelText: 'URL stream (HLS/MP3/FLAC)',
                  hintText: 'https://example.com/song.mp3',
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Add to queue'),
                  onPressed: () {
                    final value = _streamController.text.trim();
                    if (value.isEmpty) return;
                    final uri = Uri.tryParse(value);
                    if (uri != null) {
                      notifier.addDirectStream(
                        uri,
                        title: _titleController.text,
                        artist: _artistController.text,
                      );
                    }
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openFolderSheet(PlayerNotifier notifier) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18191f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add offline folder',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _folderController,
                decoration: const InputDecoration(
                  labelText: 'Folder path',
                  hintText: r'C:\Music\HiFi',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Browse'),
                    onPressed: () async {
                      final path = await FilePicker.platform.getDirectoryPath();
                      if (path != null) {
                        _folderController.text = path;
                        await notifier.addFolderTracks(path);
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    icon: const Icon(Icons.queue_music),
                    label: const Text('Add folder'),
                    onPressed: () async {
                      final path = _folderController.text.trim();
                      if (path.isNotEmpty) {
                        await notifier.addFolderTracks(path);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Supported: mp3, flac, m4a, aac, wav, ogg, opus (recursive).',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openDeviceSheet(PlayerNotifier notifier) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18191f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Audio output devices',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: notifier.refreshDevices,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (notifier.devices.isEmpty) const Text('No devices found yet.'),
              ...notifier.devices.map(
                (e) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.headphones),
                  title: Text(_formatDeviceName(e)),
                  trailing: notifier.selectedDevice == e
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    notifier.setAudioDevice(e);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openEqSheet(PlayerNotifier notifier) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18191f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final isWindows = Platform.isWindows;
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Consumer<PlayerNotifier>(
            builder: (context, state, _) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Equalizer & preamp',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text('Preamp'),
                        Expanded(
                          child: Slider(
                            value: state.preampDb,
                            min: -12,
                            max: 12,
                            divisions: 24,
                            label: '${state.preampDb.toStringAsFixed(1)} dB',
                            onChanged: state.setPreamp,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: state.eqGains.entries.map((entry) {
                        return SizedBox(
                          width: 140,
                          child: Column(
                            children: [
                              Text('${entry.key} Hz'),
                              Slider(
                                value: entry.value,
                                min: -12,
                                max: 12,
                                divisions: 24,
                                label: '${entry.value.toStringAsFixed(1)} dB',
                                onChanged: (v) =>
                                    state.updateEqBand(entry.key, v),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    if (isWindows)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'WASAPI Exclusive / bypass Windows resampler',
                        ),
                        subtitle: Text(
                          state.wasapiExclusive
                              ? 'Exclusive requested: ON (Windows only)'
                              : 'Exclusive: OFF',
                        ),
                        value: state.wasapiExclusive,
                        onChanged: (_) =>
                            notifier.setWasapiExclusive(!state.wasapiExclusive),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openSettingsSheet(PlayerNotifier notifier) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18191f),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final bottomPadding = MediaQuery.of(context).viewInsets.bottom + 20;
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Settings', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.graphic_eq),
                  title: const Text('Equalizer & preamp'),
                  onTap: () {
                    Navigator.pop(context);
                    _openEqSheet(notifier);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.headphones),
                  title: const Text('Audio devices'),
                  onTap: () {
                    Navigator.pop(context);
                    _openDeviceSheet(notifier);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.timer),
                  title: const Text('Sleep timer'),
                  onTap: () {
                    Navigator.pop(context);
                    _openSleepSheet(notifier);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.speed),
                  title: const Text('Playback speed'),
                  onTap: () {
                    Navigator.pop(context);
                    _openSpeedSheet(notifier);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.palette),
                  title: const Text('Theme'),
                  subtitle: Text(
                    notifier.playbackTheme == PlaybackTheme.vinyl
                        ? 'Vinyl turntable'
                        : 'CD deck',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _openThemeSheet(notifier);
                  },
                ),
                const Divider(),
                Text(
                  'Lyrics source',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Consumer<PlayerNotifier>(
                  builder: (context, state, _) {
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: LyricsSource.values.map((src) {
                        final label = switch (src) {
                          LyricsSource.auto => 'Auto (lrclib -> lyrics.ovh)',
                          LyricsSource.lrclib => 'lrclib (synced)',
                          LyricsSource.lyricsOvh => 'lyrics.ovh (plain)',
                        };
                        return ChoiceChip(
                          label: Text(label),
                          selected: state.lyricsSource == src,
                          onSelected: (_) => notifier.setLyricsSource(src),
                        );
                      }).toList(),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Listening history'),
                  onTap: () {
                    Navigator.pop(context);
                    _openHistorySheet(notifier);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.cloud_download),
                  title: const Text('Add from Drive'),
                  onTap: () {
                    Navigator.pop(context);
                    _openDriveSheet(notifier);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('Add stream URL'),
                  onTap: () {
                    Navigator.pop(context);
                    _openStreamSheet(notifier);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: const Text('Add folder'),
                  onTap: () {
                    Navigator.pop(context);
                    _openFolderSheet(notifier);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openVolumeSheet(PlayerNotifier notifier) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18191f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Consumer<PlayerNotifier>(
            builder: (context, state, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Volume', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Slider(
                    value: state.volume,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: state.volume.toStringAsFixed(0),
                    onChanged: state.setVolume,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildLyricsPanel(
    PlayerNotifier notifier,
    app.Track track,
    double minHeight,
  ) {
    final result = notifier.lyrics;
    final syncedLines = (result != null && result.isSynced)
        ? _getSyncedLines(track, result)
        : const <_LyricLine>[];
    final hasSynced = syncedLines.isNotEmpty;

    Widget buildSyncedView() {
      return StreamBuilder<Duration>(
        stream: notifier.positionStream,
        builder: (context, snapshot) {
          final pos = snapshot.data ?? notifier.position;
          final active = _currentLyricIndex(syncedLines, pos);
          final lines = <Widget>[];
          for (int offset = -2; offset <= 2; offset++) {
            final idx = active + offset;
            if (idx < 0 || idx >= syncedLines.length) continue;
            final line = syncedLines[idx];
            final isCurrent = offset == 0;
            final opacity = switch (offset.abs()) {
              0 => 1.0,
              1 => 0.68,
              _ => 0.42,
            };
            final size = switch (offset.abs()) {
              0 => 30.0,
              1 => 22.0,
              _ => 18.0,
            };
            lines.add(
              Opacity(
                opacity: opacity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    line.text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: size,
                      fontWeight:
                          isCurrent ? FontWeight.w800 : FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            );
          }
          final key = ValueKey<int>(active);
          return SizedBox(
            height: 280,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 360),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    ...previous,
                    if (current != null) current,
                  ],
                );
              },
              transitionBuilder: (child, anim) {
                final isIncoming = child.key == ValueKey(active);
                final curve = CurvedAnimation(
                  parent: anim,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                final tween = Tween<Offset>(
                  begin: isIncoming ? const Offset(0, 0.28) : Offset.zero,
                  end: isIncoming ? Offset.zero : const Offset(0, -0.28),
                );
                return ClipRect(
                  child: SlideTransition(
                    position: tween.animate(curve),
                    child: FadeTransition(opacity: curve, child: child),
                  ),
                );
              },
              child: Column(
                key: key,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: lines,
              ),
            ),
          );
        },
      );
    }

    Widget buildStaticView() {
      return SingleChildScrollView(
        controller: _lyricsScrollController,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          result?.lyrics ?? 'No lyrics yet. Play a track to fetch.',
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: 22,
            height: 1.4,
            color: Colors.white,
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (result != null) ...[
              const SizedBox(height: 2),
              Center(
                child: Text(
                  'Source: ${result.source}${result.isSynced ? ' (synced)' : ''}',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: Colors.white70),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: hasSynced ? buildSyncedView() : buildStaticView(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_LyricLine> _getSyncedLines(app.Track? track, LyricsResult result) {
    final key = track?.id ?? '${result.source}-${result.lyrics.hashCode}';
    if (_lyricsCache.containsKey(key)) return _lyricsCache[key]!;
    final parsed = _parseSyncedLyrics(result.lyrics);
    _lyricsCache[key] = parsed;
    return parsed;
  }

  List<_LyricLine> _parseSyncedLyrics(String raw) {
    final regex = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]');
    final lines = <_LyricLine>[];
    for (final row in raw.split('\n')) {
      final matches = regex.allMatches(row);
      if (matches.isEmpty) continue;
      final text = row.replaceAll(regex, '').trim();
      if (text.isEmpty) continue;
      for (final m in matches) {
        final minutes = int.tryParse(m.group(1) ?? '') ?? 0;
        final seconds = int.tryParse(m.group(2) ?? '') ?? 0;
        final millisStr = m.group(3) ?? '0';
        final millis = (double.tryParse('0.$millisStr') ?? 0) * 1000;
        final dur = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: millis.round(),
        );
        lines.add(_LyricLine(timestamp: dur, text: text));
      }
    }
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }

  int _currentLyricIndex(List<_LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;
    var idx = 0;
    for (var i = 0; i < lines.length; i++) {
      final current = lines[i];
      final next = i + 1 < lines.length ? lines[i + 1].timestamp : null;
      if (position >= current.timestamp &&
          (next == null || position < next)) {
        idx = i;
        break;
      }
      if (position >= current.timestamp) {
        idx = i;
      }
    }
    return idx;
  }

  Future<void> _openQueueSheet(PlayerNotifier notifier) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18191f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SizedBox(
          height: 360,
          child: notifier.queue.isEmpty
              ? const Center(child: Text('Queue is empty'))
              : ListView(
                  children: notifier.queue
                      .map(
                        (t) => ListTile(
                          leading: t.artworkUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: CachedNetworkImage(
                                      imageUrl: t.artworkUrl!,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.music_note),
                          title: Text(t.title),
                          subtitle: Text(t.artist),
                          trailing: notifier.current?.id == t.id
                              ? const Icon(Icons.play_arrow)
                              : null,
                          onTap: () => notifier.playTrack(t),
                        ),
                      )
                      .toList(),
                ),
        );
      },
    );
  }

  Future<void> _openSleepSheet(PlayerNotifier notifier) {
    const options = [
      Duration(minutes: 15),
      Duration(minutes: 30),
      Duration(minutes: 60),
    ];
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18191f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Sleep timer'),
              trailing: TextButton(
                onPressed: () {
                  notifier.setSleepTimer(null);
                  Navigator.pop(context);
                },
                child: const Text('Off'),
              ),
            ),
            ...options.map(
              (d) => ListTile(
                title: Text('${d.inMinutes} minutes'),
                onTap: () {
                  notifier.setSleepTimer(d);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSpeedSheet(PlayerNotifier notifier) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18191f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Consumer<PlayerNotifier>(
            builder: (context, state, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Playback speed',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: state.speed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: '${state.speed.toStringAsFixed(2)}x',
                    onChanged: state.setSpeed,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openHistorySheet(PlayerNotifier notifier) {
    final history = notifier.history;
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF18191f),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SizedBox(
          height: 360,
          child: history.isEmpty
              ? const Center(child: Text('No history yet'))
              : ListView(
                  children: history
                      .map(
                        (t) => ListTile(
                          leading: t.artworkUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: CachedNetworkImage(
                                      imageUrl: t.artworkUrl!,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.history),
                          title: Text(t.title),
                          subtitle: Text(t.artist),
                          onTap: () {
                            Navigator.pop(context);
                            notifier.playTrack(t);
                          },
                        ),
                      )
                      .toList(),
                ),
        );
      },
    );
  }

  String _formatDeviceName(AudioDevice device) {
    final desc = device.description.trim();
    final name = device.name.trim();
    final chosen = desc.isNotEmpty ? desc : name;
    final cleaned = chosen.replaceAll(RegExp(r'[{}]'), '').trim();
    return cleaned.isNotEmpty ? cleaned : name;
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '--:--';
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _LyricLine {
  final Duration timestamp;
  final String text;

  const _LyricLine({required this.timestamp, required this.text});
}
