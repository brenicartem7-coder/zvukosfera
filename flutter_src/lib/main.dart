import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'audio_player_manager.dart';
import 'player_screen.dart';

// Глобальный уведомитель темы (темная / светлая)
final ValueNotifier<ThemeMode> appThemeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ZvukosferaApp());
}

class ZvukosferaApp extends StatelessWidget {
  const ZvukosferaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeModeNotifier,
      builder: (context, currentThemeMode, _) {
        return MaterialApp(
          title: 'Звукосфера',
          debugShowCheckedModeBanner: false,
          themeMode: currentThemeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: const Color(0xFF2563EB),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF8FAFC),
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: const Color(0xFF3B82F6),
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF0F172A),
              elevation: 0,
              scrolledUnderElevation: 0,
            ),
          ),
          home: const MainTrackListScreen(),
        );
      },
    );
  }
}

class MainTrackListScreen extends StatefulWidget {
  const MainTrackListScreen({super.key});

  @override
  State<MainTrackListScreen> createState() => _MainTrackListScreenState();
}

class _MainTrackListScreenState extends State<MainTrackListScreen> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayerManager _playerManager = AudioPlayerManager.instance;
  final TextEditingController _searchController = TextEditingController();

  List<SongModel> _allSongs = [];
  List<SongModel> _filteredSongs = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _requestPermissionAndFetchSongs();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
      if (_searchQuery.isEmpty) {
        _filteredSongs = List.from(_allSongs);
      } else {
        _filteredSongs = _allSongs.where((song) {
          final title = song.title.toLowerCase();
          final artist = (song.artist ?? '').toLowerCase();
          return title.contains(_searchQuery) || artist.contains(_searchQuery);
        }).toList();
      }
    });
  }

  Future<void> _requestPermissionAndFetchSongs() async {
    setState(() => _isLoading = true);

    // Запрос разрешения на чтение медиа/хранилища
    bool permissionGranted = false;

    if (await Permission.audio.status.isGranted ||
        await Permission.storage.status.isGranted) {
      permissionGranted = true;
    } else {
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) {
        permissionGranted = true;
      } else {
        final storageStatus = await Permission.storage.request();
        permissionGranted = storageStatus.isGranted;
      }
    }

    if (!permissionGranted) {
      // Запасной встроенный запрос on_audio_query
      permissionGranted = await _audioQuery.permissionsRequest();
    }

    if (!mounted) return;

    if (permissionGranted) {
      setState(() => _hasPermission = true);
      _fetchSongs();
    } else {
      setState(() {
        _hasPermission = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchSongs() async {
    try {
      final rawSongs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      // Реальный поиск только аудиофайлов формата .mp3 и .wav
      final songs = rawSongs.where((s) {
        final ext = s.fileExtension.toLowerCase();
        final path = (s.data).toLowerCase();
        return ext == 'mp3' || ext == 'wav' || path.endsWith('.mp3') || path.endsWith('.wav');
      }).toList();

      if (!mounted) return;

      setState(() {
        _allSongs = songs;
        _filteredSongs = List.from(songs);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сканирования: $e')),
      );
    }
  }

  String _formatDuration(int? milliseconds) {
    if (milliseconds == null || milliseconds <= 0) return '--:--';
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Звукосфера',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              _isLoading
                  ? 'Сканирование памяти...'
                  : '${_allSongs.length} треков в памяти',
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Настройки темы',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showSettingsDialog,
          ),
          IconButton(
            tooltip: 'Обновить список',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _requestPermissionAndFetchSongs,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Поисковая строка
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Поиск по трекам и исполнителям...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),

            // Основная область: Загрузка / Ошибка разрешения / Список
            Expanded(
              child: _buildBody(theme),
            ),

            // Мини-плеер внизу экрана
            _buildMiniPlayer(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Поиск локальных аудиофайлов...',
              style: TextStyle(fontSize: 15),
            ),
          ],
        ),
      );
    }

    if (!_hasPermission) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_shared_outlined, size: 64, color: Color(0xFF3B82F6)),
              const SizedBox(height: 16),
              const Text(
                'Доступ к музыке',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Приложению «Звукосфера» требуется разрешение на чтение памяти устройства (READ_MEDIA_AUDIO / READ_EXTERNAL_STORAGE) для сканирования и воспроизведения ваших аудиофайлов.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _requestPermissionAndFetchSongs,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Предоставить доступ к музыке'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredSongs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.music_off_rounded,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isNotEmpty
                    ? 'Ничего не найдено'
                    : 'На устройстве пока нет музыки',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isNotEmpty
                    ? 'По запросу «$_searchQuery» треки не обнаружены'
                    : 'Аудиофайлы форматов .mp3 или .wav не обнаружены в памяти устройства.',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              if (_searchQuery.isEmpty) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _requestPermissionAndFetchSongs,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Сканировать заново'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: _filteredSongs.length,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemBuilder: (context, index) {
        final song = _filteredSongs[index];

        return StreamBuilder<SongModel?>(
          stream: _playerManager.currentSongStream,
          builder: (context, snapshot) {
            final isPlayingThis = snapshot.data?.id == song.id;
            final ext = (song.fileExtension.isNotEmpty ? song.fileExtension.toUpperCase() : 'MP3');
            final artistText = (song.artist == null || song.artist == '<unknown>')
                ? 'Неизвестный исполнитель'
                : song.artist!;

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 2,
              ),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isPlayingThis ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 15,
                  color: isPlayingThis ? theme.colorScheme.primary : null,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '$artistText • $ext',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ),
              trailing: Text(
                _formatDuration(song.duration),
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: isPlayingThis ? theme.colorScheme.primary : (isDark ? Colors.white54 : Colors.black45),
                ),
              ),
              onTap: () {
                HapticFeedback.selectionClick();
                _playerManager.playPlaylist(_filteredSongs, index);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const PlayerScreen(),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMiniPlayer(ThemeData theme) {
    return StreamBuilder<SongModel?>(
      stream: _playerManager.currentSongStream,
      builder: (context, snapshot) {
        final currentSong = snapshot.data;
        if (currentSong == null) return const SizedBox.shrink();

        final isDark = theme.brightness == Brightness.dark;

        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const PlayerScreen(),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white10 : Colors.black12,
                ),
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: QueryArtworkWidget(
                      id: currentSong.id,
                      type: ArtworkType.AUDIO,
                      artworkFit: BoxFit.cover,
                      nullArtworkWidget: Container(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                        child: Icon(
                          Icons.music_note_rounded,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currentSong.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        (currentSong.artist == null || currentSong.artist == '<unknown>')
                            ? 'Неизвестный исполнитель'
                            : currentSong.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                StreamBuilder<bool>(
                  stream: _playerManager.isPlayingStream,
                  builder: (context, isPlayingSnap) {
                    final isPlaying = isPlayingSnap.data ?? false;
                    return IconButton(
                      icon: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 28,
                      ),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        _playerManager.togglePlayPause();
                      },
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, size: 28),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _playerManager.playNext();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSettingsDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: appThemeModeNotifier,
          builder: (context, currentMode, _) {
            final isLight = currentMode == ThemeMode.light;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.settings_rounded, size: 24),
                            SizedBox(width: 12),
                            Text(
                              'Настройки',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ТЕМА ОФОРМЛЕНИЯ',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      leading: const Icon(Icons.dark_mode_rounded),
                      title: const Text('Настройки', fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
