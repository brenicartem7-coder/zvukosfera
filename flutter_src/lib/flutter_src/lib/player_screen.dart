import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'audio_player_manager.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final AudioPlayerManager _playerManager = AudioPlayerManager.instance;
  double? _dragValue;

  String _formatDuration(Duration duration) {
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
        leading: IconButton(
          tooltip: 'Назад к трекам',
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: const Text(
          'Звукосфера',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          StreamBuilder<int?>(
            stream: _playerManager.sleepTimerStream,
            initialData: _playerManager.sleepTimerRemainingSeconds,
            builder: (context, timerSnapshot) {
              final remaining = timerSnapshot.data;
              return IconButton(
                tooltip: 'Таймер сна (15, 30, 60 мин)',
                icon: Icon(
                  Icons.timer_rounded,
                  color: remaining != null ? theme.colorScheme.primary : null,
                ),
                onPressed: () => _showSleepTimerDialog(context),
              );
            },
          ),
          StreamBuilder<void>(
            stream: _playerManager.equalizerStream,
            builder: (context, _) {
              final isEqActive = _playerManager.equalizerEnabled && _playerManager.currentPreset != 'flat';
              return IconButton(
                tooltip: 'Эквалайзер звука',
                icon: Icon(
                  Icons.tune_rounded,
                  color: isEqActive ? theme.colorScheme.primary : null,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _showEqualizerModal(context);
                },
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<SongModel?>(
          stream: _playerManager.currentSongStream,
          initialData: _playerManager.currentSong,
          builder: (context, songSnapshot) {
            final song = songSnapshot.data;

            if (song == null) {
              return const Center(
                child: Text(
                  'Трек не выбран',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  const SizedBox(height: 8),

                  // Обложка трека (заглушка или изображение из метаданных)
                  Center(
                    child: Container(
                      width: 270,
                      height: 270,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.4 : 0.12),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: QueryArtworkWidget(
                          id: song.id,
                          type: ArtworkType.AUDIO,
                          artworkWidth: 270,
                          artworkHeight: 270,
                          artworkFit: BoxFit.cover,
                          nullArtworkWidget: _buildArtPlaceholder(isDark, theme),
                        ),
                      ),
                    ),
                  ),

                  // Название трека и Исполнитель
                  Column(
                    children: [
                      Text(
                        song.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (song.artist == null || song.artist == '<unknown>')
                            ? 'Неизвестный исполнитель'
                            : song.artist!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),

                  // Ползунок прогресса и метки времени
                  StreamBuilder<Duration>(
                    stream: _playerManager.positionStream,
                    builder: (context, posSnapshot) {
                      final position = posSnapshot.data ?? Duration.zero;

                      return StreamBuilder<Duration?>(
                        stream: _playerManager.durationStream,
                        builder: (context, durSnapshot) {
                          final duration = durSnapshot.data ??
                              Duration(milliseconds: song.duration ?? 0);

                          final totalMs = duration.inMilliseconds > 0
                              ? duration.inMilliseconds.toDouble()
                              : 1.0;
                          final currentMs = position.inMilliseconds
                              .toDouble()
                              .clamp(0.0, totalMs);

                          final sliderValue = (_dragValue ?? currentMs)
                              .clamp(0.0, totalMs);

                          return Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14,
                                  ),
                                  activeTrackColor: theme.colorScheme.primary,
                                  inactiveTrackColor: isDark
                                      ? Colors.white12
                                      : Colors.black12,
                                  thumbColor: theme.colorScheme.primary,
                                ),
                                child: Slider(
                                  min: 0.0,
                                  max: totalMs,
                                  value: sliderValue,
                                  onChanged: (value) {
                                    HapticFeedback.selectionClick();
                                    setState(() {
                                      _dragValue = value;
                                    });
                                  },
                                  onChangeEnd: (value) {
                                    _playerManager.seek(
                                      Duration(milliseconds: value.round()),
                                    );
                                    setState(() {
                                      _dragValue = null;
                                    });
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(position),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                      ),
                                    ),
                                    Text(
                                      _formatDuration(duration),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),

                  // Кнопки управления (повтор, предыдущий, пауза/воспроизведение, следующий)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Кнопка: Повтор (выкл / весь список / один трек)
                      StreamBuilder<LoopMode>(
                        stream: _playerManager.loopModeStream,
                        initialData: _playerManager.loopMode,
                        builder: (context, loopSnapshot) {
                          final loopMode = loopSnapshot.data ?? LoopMode.off;
                          final isLoopActive = loopMode != LoopMode.off;

                          return IconButton(
                            tooltip: loopMode == LoopMode.one
                                ? 'Повтор: один трек'
                                : loopMode == LoopMode.all
                                    ? 'Повтор: весь список'
                                    : 'Повтор выключен',
                            iconSize: 28,
                            color: isLoopActive ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.5),
                            icon: Icon(
                              loopMode == LoopMode.one
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded,
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _playerManager.toggleLoopMode();
                            },
                          );
                        },
                      ),
                      const SizedBox(width: 8),

                      // Кнопка: Предыдущий
                      IconButton(
                        tooltip: 'Предыдущий трек',
                        iconSize: 42,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _playerManager.playPrevious();
                        },
                      ),
                      const SizedBox(width: 14),

                      // Кнопка: Пауза / Воспроизведение
                      StreamBuilder<bool>(
                        stream: _playerManager.isPlayingStream,
                        builder: (context, playSnapshot) {
                          final isPlaying = playSnapshot.data ?? false;

                          return Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.colorScheme.primary,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withOpacity(0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: IconButton(
                              tooltip: isPlaying ? 'Пауза' : 'Воспроизведение',
                              iconSize: 52,
                              color: Colors.white,
                              icon: Icon(
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                _playerManager.togglePlayPause();
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 14),
