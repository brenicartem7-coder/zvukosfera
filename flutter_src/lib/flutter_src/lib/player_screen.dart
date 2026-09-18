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
                      const SizedBox(width: 14),                      // Кнопка: Следующий
                      IconButton(
                        tooltip: 'Следующий трек',
                        iconSize: 42,
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _playerManager.playNext();
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // Обложка-заглушка «Звукосфера»
  Widget _buildArtPlaceholder(bool isDark, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.12),
              ),
              child: Icon(
                Icons.music_note_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'ЗВУКОСФЕРА',
              style: TextStyle(
                fontSize: 13,
                letterSpacing: 2.0,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Диалог выбора времени таймера сна (15, 30, 60 минут)
  void _showSleepTimerDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StreamBuilder<int?>(
          stream: _playerManager.sleepTimerStream,
          initialData: _playerManager.sleepTimerRemainingSeconds,
          builder: (context, snapshot) {
            final remaining = snapshot.data;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.timer_rounded, size: 24),
                            SizedBox(width: 12),
                            Text(
                              'Таймер сна',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (remaining != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Осталось: ${(remaining ~/ 60).toString().padLeft(2, '0')}:${(remaining % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            TextButton(
                              onPressed: () {
                                _playerManager.cancelSleepTimer();
                                Navigator.of(ctx).pop();
                              },
                              child: const Text('Отключить'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: const Icon(Icons.alarm),
                      title: const Text('15 минут'),
                      onTap: () {
                        _playerManager.setSleepTimer(15);
                        Navigator.of(ctx).pop();
                      },
                    ),
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: const Icon(Icons.alarm),
                      title: const Text('30 минут'),
                      onTap: () {
                        _playerManager.setSleepTimer(30);
                        Navigator.of(ctx).pop();
                      },
                    ),
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: const Icon(Icons.alarm),
                      title: const Text('60 минут'),
                      onTap: () {
                        _playerManager.setSleepTimer(60);
                        Navigator.of(ctx).pop();
                      },
                    ),
                    if (remaining != null)
                      ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        leading: const Icon(Icons.timer_off_rounded, color: Colors.redAccent),
                        title: const Text('Выключить таймер', style: TextStyle(color: Colors.redAccent)),
                        onTap: () {
                          _playerManager.cancelSleepTimer();
                          Navigator.of(ctx).pop();
                        },
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

  // Панель настройки эквалайзера с предустановками (Классика, Рок, Басы, Обычный, Вокал)
  void _showEqualizerModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final bandLabels = ['60 Гц', '230 Гц', '910 Гц', '3.6 кГц', '14 кГц'];
        final presetTitles = {
          'flat': 'Обычный',
          'classical': 'Классика',
          'rock': 'Рок',
          'bass': 'Басы',
          'vocal': 'Вокал',
        };

        return StreamBuilder<void>(
          stream: _playerManager.equalizerStream,
          builder: (context, _) {
            final gains = _playerManager.bandGains;
            final isEnabled = _playerManager.equalizerEnabled;
            final activePreset = _playerManager.currentPreset;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.tune_rounded, size: 24),
                            SizedBox(width: 12),
                            Text(
                              'Эквалайзер',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Switch(
                          value: isEnabled,
                          onChanged: (val) {
                            HapticFeedback.mediumImpact();
                            _playerManager.toggleEqualizer(val);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'ПРЕДУСТАНОВКИ',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: presetTitles.entries.map((entry) {
                        final isSelected = activePreset == entry.key;
                        return ChoiceChip(
                          label: Text(entry.value),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              HapticFeedback.selectionClick();
                              _playerManager.setEqualizerPreset(entry.key);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    // 5-полосные регуляторы частот
                    Opacity(
                      opacity: isEnabled ? 1.0 : 0.4,
                      child: Column(
                        children: List.generate(5, (index) {
                          final gain = gains[index];
                          return Row(
                            children: [
                              SizedBox(
                                width: 60,
                                child: Text(
                                  bandLabels[index],
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  min: -12.0,
                                  max: 12.0,
                                  divisions: 24,
                                  value: gain,
                                  onChanged: isEnabled
                                      ? (val) {
                                          HapticFeedback.selectionClick();
                                          _playerManager.setBandGain(index, val);
                                        }
                                      : null,
                                ),
                              ),
                              SizedBox(
                                width: 45,
                                child: Text(
                                  '${gain > 0 ? "+" : ""}${gain.toStringAsFixed(0)} дБ',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: const Text('Сбросить (0 дБ)'),
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            _playerManager.resetEqualizer();
                          },
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Готово'),
                        ),
                      ],
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
