import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';

class AudioPlayerManager {
  static final AudioPlayerManager _instance = AudioPlayerManager._internal();
  static AudioPlayerManager get instance => _instance;

  final AudioPlayer _player = AudioPlayer();

  List<SongModel> _playlist = [];
  int _currentIndex = -1;

  final _currentSongController = StreamController<SongModel?>.broadcast();
  Stream<SongModel?> get currentSongStream => _currentSongController.stream;

  Timer? _sleepTimer;
  int? _sleepTimerRemainingSeconds;
  final _sleepTimerController = StreamController<int?>.broadcast();
  Stream<int?> get sleepTimerStream => _sleepTimerController.stream;
  int? get sleepTimerRemainingSeconds => _sleepTimerRemainingSeconds;

  void setSleepTimer(int minutes) {
    cancelSleepTimer();
    _sleepTimerRemainingSeconds = minutes * 60;
    _sleepTimerController.add(_sleepTimerRemainingSeconds);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sleepTimerRemainingSeconds != null && _sleepTimerRemainingSeconds! > 1) {
        _sleepTimerRemainingSeconds = _sleepTimerRemainingSeconds! - 1;
        _sleepTimerController.add(_sleepTimerRemainingSeconds);
      } else {
        _player.pause();
        cancelSleepTimer();
      }
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerRemainingSeconds = null;
    _sleepTimerController.add(null);
  }

  SongModel? get currentSong =>
      (_currentIndex >= 0 && _currentIndex < _playlist.length)
          ? _playlist[_currentIndex]
          : null;

  List<SongModel> get playlist => _playlist;
  int get currentIndex => _currentIndex;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<bool> get isPlayingStream => _player.playingStream;

  AudioPlayerManager._internal() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        playNext();
      }
    });
  }

  Future<void> playPlaylist(List<SongModel> songs, int startIndex) async {
    if (songs.isEmpty) return;
    _playlist = List.from(songs);
    _currentIndex = startIndex;
    await _loadAndPlayCurrent();
  }

  Future<void> _loadAndPlayCurrent() async {
    if (_currentIndex < 0 || _currentIndex >= _playlist.length) return;

    final song = _playlist[_currentIndex];
    _currentSongController.add(song);

    try {
      final filePath = song.data;
      await _player.setFilePath(filePath);
      await _player.play();
    } catch (e) {
      try {
        if (song.uri != null) {
          await _player.setAudioSource(AudioSource.uri(Uri.parse(song.uri!)));
          await _player.play();
        }
      } catch (uriError) {
        // Ошибка воспроизведения файла
      }
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> playNext() async {
    if (_playlist.isEmpty) return;
    if (_currentIndex < _playlist.length - 1) {
      _currentIndex++;
    } else {
      _currentIndex = 0;
    }
    await _loadAndPlayCurrent();
  }

  Future<void> playPrevious() async {
    if (_playlist.isEmpty) return;
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (_currentIndex > 0) {
      _currentIndex--;
    } else {
      _currentIndex = _playlist.length - 1;
    }
    await _loadAndPlayCurrent();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  static const Map<String, List<double>> equalizerPresets = {
    'flat': [0.0, 0.0, 0.0, 0.0, 0.0],
    'bass': [7.0, 5.0, 2.0, 0.0, -1.0],
    'rock': [5.0, 3.0, -1.0, 3.0, 5.0],
    'classical': [4.0, 2.0, 0.0, 2.0, 3.0],
    'vocal': [-1.0, 1.0, 4.0, 3.0, 1.0],
  };

  bool _equalizerEnabled = true;
  String _currentPreset = 'flat';
  List<double> _bandGains = [0.0, 0.0, 0.0, 0.0, 0.0];
  final _equalizerController = StreamController<void>.broadcast();
  Stream<void> get equalizerStream => _equalizerController.stream;

  bool get equalizerEnabled => _equalizerEnabled;
  String get currentPreset => _currentPreset;
  List<double> get bandGains => List.unmodifiable(_bandGains);

  void toggleEqualizer(bool enabled) {
    _equalizerEnabled = enabled;
    _equalizerController.add(null);
  }

  void setEqualizerPreset(String presetId) {
    if (equalizerPresets.containsKey(presetId)) {
      _currentPreset = presetId;
      _bandGains = List.from(equalizerPresets[presetId]!);
      _equalizerController.add(null);
    }
  }

  void setBandGain(int index, double gain) {
    if (index >= 0 && index < _bandGains.length) {
      _bandGains[index] = gain.clamp(-12.0, 12.0);
      _currentPreset = 'custom';
      _equalizerController.add(null);
    }
  }

  void resetEqualizer() {
    _currentPreset = 'flat';
    _bandGains = [0.0, 0.0, 0.0, 0.0, 0.0];
    _equalizerController.add(null);
  }

  LoopMode _loopMode = LoopMode.off;
  final _loopModeController = StreamController<LoopMode>.broadcast();
  Stream<LoopMode> get loopModeStream => _loopModeController.stream;
  LoopMode get loopMode => _loopMode;

  Future<void> toggleLoopMode() async {
    if (_loopMode == LoopMode.off) {
      _loopMode = LoopMode.all;
    } else if (_loopMode == LoopMode.all) {
      _loopMode = LoopMode.one;
    } else {
      _loopMode = LoopMode.off;
    }
    await _player.setLoopMode(_loopMode);
    _loopModeController.add(_loopMode);
  }

  void dispose() {
    _player.dispose();
    _currentSongController.close();
    _equalizerController.close();
    _loopModeController.close();
  }
}
