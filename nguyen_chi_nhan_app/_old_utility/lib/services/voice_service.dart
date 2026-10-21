import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/voice_command.dart';
import 'alarm_manager.dart';
import 'audio_alarm_service.dart';
import 'stopwatch_service.dart';
import 'system_clock_service.dart';

class VoiceService {
  static final VoiceService instance = VoiceService._internal();
  VoiceService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _hasProcessedCommand = false;

  final ValueNotifier<bool> isListeningNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> spokenWordsNotifier = ValueNotifier<String>('');
  final ValueNotifier<double> soundLevelNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<String?> lastErrorNotifier = ValueNotifier<String?>(null);
  final ValueNotifier<String> currentLocaleNotifier = ValueNotifier<String>('vi_VN'); // 'vi_VN' or 'en_US'
  final ValueNotifier<List<VoiceCommandResult>> commandHistoryNotifier =
      ValueNotifier<List<VoiceCommandResult>>([]);

  void clearHistory() {
    commandHistoryNotifier.value = [];
  }

  void switchLanguage(String locale) {
    currentLocaleNotifier.value = locale;
  }

  Future<bool> initSpeech() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (val) {
          debugPrint('Speech error: ${val.errorMsg}, permanent: ${val.permanent}');
          isListeningNotifier.value = false;
          soundLevelNotifier.value = 0.0;

          // If speech was recognized before error, process it!
          final currentWords = spokenWordsNotifier.value.trim();
          if (!_hasProcessedCommand && currentWords.isNotEmpty) {
            _hasProcessedCommand = true;
            processVoiceCommand(currentWords);
          } else {
            if (val.errorMsg == 'error_speech_timeout' || val.errorMsg.contains('timeout')) {
              lastErrorNotifier.value = currentLocaleNotifier.value == 'vi_VN'
                  ? 'Hết thời gian chờ. Hãy nói: "Báo thức 7 giờ" hoặc "Bắt đầu".'
                  : 'Listening timeout. Say: "Set alarm at 7:30" or "Start".';
            } else if (val.errorMsg == 'error_no_match' || val.errorMsg.contains('no_match')) {
              lastErrorNotifier.value = currentLocaleNotifier.value == 'vi_VN'
                  ? 'Chưa nghe rõ câu lệnh. Hãy thử nói lại gần mic hơn.'
                  : 'Speech not recognized. Please speak closer to mic.';
            } else if (val.errorMsg.contains('audio')) {
              lastErrorNotifier.value = 'Lỗi âm thanh mic. Vui lòng kiểm tra quyền mic.';
            } else {
              lastErrorNotifier.value = 'Lỗi nhận diện (${val.errorMsg}). Hãy thử lại.';
            }
          }
        },
        onStatus: (status) {
          debugPrint('Speech status: $status');
          if (status == 'done' || status == 'notListening') {
            isListeningNotifier.value = false;
            soundLevelNotifier.value = 0.0;

            final currentWords = spokenWordsNotifier.value.trim();
            if (!_hasProcessedCommand && currentWords.isNotEmpty) {
              _hasProcessedCommand = true;
              processVoiceCommand(currentWords);
            }
          }
        },
      );
    } catch (e) {
      debugPrint('Speech initialize exception: $e');
      _isInitialized = false;
    }
    return _isInitialized;
  }

  Future<void> startListening({Function(String)? onLiveResult}) async {
    final available = await initSpeech();
    if (!available) {
      debugPrint('Speech recognition not available on this platform/device');
      lastErrorNotifier.value = 'Máy ảo chưa hỗ trợ Google SpeechRecognizer hoặc mic bị tắt.';
      return;
    }

    spokenWordsNotifier.value = '';
    _hasProcessedCommand = false;
    lastErrorNotifier.value = null;
    isListeningNotifier.value = true;
    AudioAlarmService.instance.playBeep();

    final targetLocale = currentLocaleNotifier.value;

    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: targetLocale,
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          pauseFor: const Duration(seconds: 3),
          listenFor: const Duration(seconds: 8),
        ),
        onSoundLevelChange: (level) {
          soundLevelNotifier.value = level;
        },
        onResult: (val) {
          spokenWordsNotifier.value = val.recognizedWords;
          onLiveResult?.call(val.recognizedWords);

          if (val.finalResult && !_hasProcessedCommand && val.recognizedWords.trim().isNotEmpty) {
            _hasProcessedCommand = true;
            isListeningNotifier.value = false;
            soundLevelNotifier.value = 0.0;
            processVoiceCommand(val.recognizedWords);
          }
        },
      );
    } catch (e) {
      debugPrint('Listen call failed: $e');
      isListeningNotifier.value = false;
      lastErrorNotifier.value = 'Không thể bật thu âm: $e';
    }
  }

  Future<void> stopListening() async {
    await _speech.stop();
    isListeningNotifier.value = false;
    soundLevelNotifier.value = 0.0;

    final currentWords = spokenWordsNotifier.value.trim();
    if (!_hasProcessedCommand && currentWords.isNotEmpty) {
      _hasProcessedCommand = true;
      processVoiceCommand(currentWords);
    }
  }

  /// Removes Vietnamese accents for robust diacritics-insensitive matching
  static String stripVietnamese(String text) {
    var result = text.toLowerCase();
    result = result.replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a');
    result = result.replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e');
    result = result.replaceAll(RegExp(r'[ìíịỉĩ]'), 'i');
    result = result.replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o');
    result = result.replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u');
    result = result.replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y');
    result = result.replaceAll(RegExp(r'[đ]'), 'd');
    return result.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalize(String text) {
    return text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _matchesCommand(String rawText, List<String> keywords) {
    final text = _normalize(rawText);
    final stripped = stripVietnamese(rawText);

    for (final k in keywords) {
      final normK = _normalize(k);
      final stripK = stripVietnamese(k);
      if (text == normK || text.contains(normK)) return true;
      if (stripped == stripK || stripped.contains(stripK)) return true;
    }
    return false;
  }

  /// Processes text into intent and dispatches execution (Supports Vietnamese & English)
  VoiceCommandResult processVoiceCommand(String rawText) {
    final text = _normalize(rawText);
    VoiceCommandResult result;
    final isEn = currentLocaleNotifier.value.startsWith('en');

    // 1. Stopwatch START — Vietnamese & English
    if (_matchesCommand(text, [
      'bắt đầu', 'bat dau', 'chạy', 'bật', 'bắt đầu bấm giờ',
      'start', 'begin', 'run', 'start stopwatch', 'start timer',
    ])) {
      StopwatchService.instance.start();
      result = VoiceCommandResult(
        type: VoiceCommandType.startStopwatch,
        rawSpokenText: rawText,
        responseMessage: isEn ? '▶️ Stopwatch started!' : '▶️ Đã bắt đầu đồng hồ bấm giờ!',
        isSuccess: true,
      );
    }
    // 2. Stopwatch STOP — Vietnamese & English
    else if (_matchesCommand(text, [
      'kết thúc', 'ket thuc', 'kết thức', 'dừng', 'dừng lại', 'tạm dừng', 'ngừng',
      'stop', 'pause', 'halt', 'stop stopwatch', 'stop timer',
    ])) {
      StopwatchService.instance.pause();
      result = VoiceCommandResult(
        type: VoiceCommandType.stopStopwatch,
        rawSpokenText: rawText,
        responseMessage: isEn ? '⏸️ Stopwatch paused!' : '⏸️ Đã tạm dừng đồng hồ bấm giờ!',
        isSuccess: true,
      );
    }
    // 3. Stopwatch RESET — Vietnamese & English
    else if (_matchesCommand(text, [
      'đặt lại', 'dat lai', 'xóa', 'làm lại', 'về không', 'từ đầu',
      'reset', 'clear', 'restart', 'reset stopwatch',
    ])) {
      StopwatchService.instance.reset();
      result = VoiceCommandResult(
        type: VoiceCommandType.resetStopwatch,
        rawSpokenText: rawText,
        responseMessage: isEn ? '🔄 Stopwatch reset to 00:00:00!' : '🔄 Đã đặt lại đồng hồ bấm giờ về 00:00:00!',
        isSuccess: true,
      );
    }
    // 4. Stopwatch LAP — Vietnamese & English
    else if (_matchesCommand(text, [
      'vòng', 'vong', 'ghi vòng', 'bấm vòng', 'vòng mới',
      'lap', 'split', 'record lap',
    ])) {
      StopwatchService.instance.recordLap();
      result = VoiceCommandResult(
        type: VoiceCommandType.lapStopwatch,
        rawSpokenText: rawText,
        responseMessage: isEn ? '🏁 Lap recorded!' : '🏁 Đã ghi lại 1 vòng bấm giờ (Lap)!',
        isSuccess: true,
      );
    }
    // 5. Relative alarm (sau X phút / in X minutes)
    else if (text.contains('phút') || text.contains('minute') || text.contains('min')) {
      final minuteMatch = RegExp(r'(\d+)\s*(?:phút|minute|min)').firstMatch(text);
      if (minuteMatch != null) {
        final addMin = int.tryParse(minuteMatch.group(1) ?? '5') ?? 5;
        final target = DateTime.now().add(Duration(minutes: addMin));
        final tod = TimeOfDay(hour: target.hour, minute: target.minute);

        // 1. App internal alarm
        AlarmManager.instance.addAlarm(
          time: tod,
          label: isEn ? 'Voice alarm in $addMin min' : 'Hẹn giờ sau $addMin phút (Voice)',
        );

        // 2. Real System Clock if enabled
        if (SystemClockService.instance.useSystemClockNotifier.value) {
          SystemClockService.instance.setSystemAlarm(
            hour: tod.hour,
            minute: tod.minute,
            message: 'Smart Utility Voice Alarm',
          );
        }

        final timeStr = '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}';
        result = VoiceCommandResult(
          type: VoiceCommandType.setAlarm,
          rawSpokenText: rawText,
          responseMessage: isEn
              ? '⏰ Alarm set for $timeStr (in $addMin min) on System Clock!'
              : '⏰ Đã đặt báo thức lúc $timeStr (sau $addMin phút) trên Đồng hồ thật của máy!',
          isSuccess: true,
          alarmTime: tod,
        );
      } else {
        result = _fallbackResult(rawText);
      }
    }
    // 6. Absolute alarm (báo thức lúc X giờ Y phút / set alarm at X:Y)
    else if (_matchesCommand(text, [
      'báo thức', 'đặt giờ', 'hẹn giờ', 'báo thức lúc',
      'alarm', 'set alarm', 'wake up', 'wake me up',
    ])) {
      final parsedTime = _parseTimeFromText(text);
      if (parsedTime != null) {
        // 1. App internal alarm
        AlarmManager.instance.addAlarm(
          time: parsedTime,
          label: 'Voice (${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')})',
        );

        // 2. Real System Clock if enabled
        if (SystemClockService.instance.useSystemClockNotifier.value) {
          SystemClockService.instance.setSystemAlarm(
            hour: parsedTime.hour,
            minute: parsedTime.minute,
            message: 'Smart Utility Voice Alarm',
          );
        }

        final timeStr = '${parsedTime.hour.toString().padLeft(2, '0')}:${parsedTime.minute.toString().padLeft(2, '0')}';
        result = VoiceCommandResult(
          type: VoiceCommandType.setAlarm,
          rawSpokenText: rawText,
          responseMessage: isEn
              ? '⏰ Alarm set successfully for $timeStr on System Clock!'
              : '⏰ Đã đặt báo thức thành công lúc $timeStr trên Đồng hồ thật của máy!',
          isSuccess: true,
          alarmTime: parsedTime,
        );
      } else {
        result = VoiceCommandResult(
          type: VoiceCommandType.unknown,
          rawSpokenText: rawText,
          responseMessage: isEn
              ? 'Time not recognized. Try: "Set alarm at 7:30" or "Alarm at 6 am".'
              : 'Chưa nhận diện được thời gian. Nói VD: "báo thức 7 giờ 30" hoặc "báo thức 6h sáng".',
          isSuccess: false,
        );
      }
    } else {
      result = _fallbackResult(rawText);
    }

    commandHistoryNotifier.value = [result, ...commandHistoryNotifier.value];
    AudioAlarmService.instance.playBeep();
    return result;
  }

  TimeOfDay? _parseTimeFromText(String text) {
    // 1. Format: "7:30", "07:30", "7h30", "7h"
    final regexColon = RegExp(r'(\d{1,2})[:hH](\d{1,2})?');
    final matchColon = regexColon.firstMatch(text);

    int? hour;
    int minute = 0;

    if (matchColon != null) {
      hour = int.tryParse(matchColon.group(1) ?? '');
      if (matchColon.group(2) != null && matchColon.group(2)!.isNotEmpty) {
        minute = int.tryParse(matchColon.group(2)!) ?? 0;
      }
    } else {
      // 2. Format: "7 giờ 30", "7 o'clock", "7 am"
      final regexWord = RegExp(r"(\d{1,2})\s*(?:giờ|tiếng|o'clock)?\s*(\d{1,2})?");
      final matchWord = regexWord.firstMatch(text);
      if (matchWord != null) {
        hour = int.tryParse(matchWord.group(1) ?? '');
        if (matchWord.group(2) != null) {
          minute = int.tryParse(matchWord.group(2)!) ?? 0;
        }
      }
    }

    if (hour == null || hour < 0 || hour > 24) return null;
    if (minute < 0 || minute >= 60) minute = 0;

    final isPM = text.contains('chiều') || text.contains('tối') || text.contains('đêm') || text.contains('pm');
    final isAM = text.contains('sáng') || text.contains('am');

    if (isPM && hour < 12) {
      hour += 12;
    } else if (isAM && hour == 12) {
      hour = 0;
    }

    if (hour >= 24) hour = 0;

    return TimeOfDay(hour: hour, minute: minute);
  }

  VoiceCommandResult _fallbackResult(String raw) {
    final isEn = currentLocaleNotifier.value.startsWith('en');
    return VoiceCommandResult(
      type: VoiceCommandType.unknown,
      rawSpokenText: raw,
      responseMessage: isEn
          ? 'Not understood: "$raw". Try: "Set alarm at 7:30", "Start", "Stop".'
          : 'Chưa hiểu: "$raw". Thử nói: "Bắt đầu", "Kết thúc", "Báo thức 7 giờ 30".',
      isSuccess: false,
    );
  }
}
