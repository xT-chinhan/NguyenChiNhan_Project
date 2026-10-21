import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class AudioAlarmService {
  static final AudioAlarmService instance = AudioAlarmService._internal();
  AudioAlarmService._internal();

  AudioPlayer? _playerInstance;
  bool _isPlaying = false;
  bool isEnabled = true;

  AudioPlayer get _player {
    _playerInstance ??= AudioPlayer();
    return _playerInstance!;
  }

  bool get isPlaying => _isPlaying;

  Future<void> init() async {
    if (!isEnabled) return;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
    } catch (e) {
      debugPrint('AudioAlarmService init error: $e');
    }
  }

  /// Plays alarm sound in loop
  Future<void> startAlarmSound() async {
    if (!isEnabled || _isPlaying) return;
    try {
      _isPlaying = true;
      _playerInstance ??= AudioPlayer();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/alarm.wav'));
    } catch (e) {
      debugPrint('Error playing alarm sound: $e');
      _isPlaying = false;
    }
  }

  /// Stops the alarm sound
  Future<void> stopAlarmSound() async {
    try {
      _isPlaying = false;
      await _player.stop();
    } catch (e) {
      debugPrint('Error stopping alarm sound: $e');
    }
  }

  AudioPlayer? _beepPlayer;

  /// Plays a short beep sound for button click or lap
  Future<void> playBeep() async {
    if (!isEnabled) return;
    try {
      _beepPlayer ??= AudioPlayer();
      await _beepPlayer!.stop();
      await _beepPlayer!.play(AssetSource('sounds/beep.wav'));
    } catch (e) {
      debugPrint('AudioAlarmService playBeep skipped or platform unavailable: $e');
    }
  }

  void dispose() {
    _player.dispose();
    _beepPlayer?.dispose();
  }
}
