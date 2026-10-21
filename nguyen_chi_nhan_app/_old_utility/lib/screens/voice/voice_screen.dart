import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/voice_command.dart';
import '../../services/system_clock_service.dart';
import '../../services/voice_service.dart';
import '../../theme/app_theme.dart';

class VoiceScreen extends StatefulWidget {
  final Function(int)? onSwitchTab;

  const VoiceScreen({super.key, this.onSwitchTab});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _customCommandController = TextEditingController();
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    VoiceService.instance.isListeningNotifier.addListener(_onListeningChanged);
    VoiceService.instance.lastErrorNotifier.addListener(_onErrorChanged);
  }

  void _onListeningChanged() {
    if (VoiceService.instance.isListeningNotifier.value) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  void _onErrorChanged() {
    final err = VoiceService.instance.lastErrorNotifier.value;
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(err)),
            ],
          ),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    VoiceService.instance.isListeningNotifier.removeListener(_onListeningChanged);
    VoiceService.instance.lastErrorNotifier.removeListener(_onErrorChanged);
    _pulseController.dispose();
    _customCommandController.dispose();
    super.dispose();
  }

  void _toggleListening() async {
    final voice = VoiceService.instance;
    if (voice.isListeningNotifier.value) {
      await voice.stopListening();
    } else {
      await voice.startListening();
    }
  }

  void _executeCommand(String text) {
    if (text.trim().isEmpty) return;
    _customCommandController.clear();
    FocusScope.of(context).unfocus();

    final result = VoiceService.instance.processVoiceCommand(text);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              result.isSuccess ? Icons.check_circle_rounded : Icons.info_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(result.responseMessage)),
          ],
        ),
        backgroundColor: result.isSuccess ? AppTheme.voiceColor : Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<String> _getPresets(String locale) {
    if (locale.startsWith('en')) {
      return [
        'Set alarm at 7:30',
        'Alarm in 10 minutes',
        'Start',
        'Stop',
        'Lap',
        'Reset',
      ];
    }
    return [
      'Báo thức 7 giờ 30',
      'Sau 10 phút',
      'Bắt đầu',
      'Kết thúc',
      'Ghi vòng',
      'Đặt lại',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final voice = VoiceService.instance;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Requirement 3 Banner
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppTheme.alarmColor.withAlpha(50)),
            ),
            color: AppTheme.alarmColor.withAlpha(15),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.record_voice_over_rounded, color: AppTheme.alarmColor),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Yêu Cầu 3: Đặt giờ báo thức bằng giọng nói đa ngôn ngữ & đồng hồ thật (5đ)',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Responsive Language Selector Row (Zero pixel overflow)
          ValueListenableBuilder<String>(
            valueListenable: voice.currentLocaleNotifier,
            builder: (context, currentLocale, _) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900 : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.dividerColor.withAlpha(50)),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Ngôn ngữ:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: 'vi_VN',
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Tiếng Việt 🇻🇳', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          ButtonSegment(
                            value: 'en_US',
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('English 🇺🇸', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                        selected: {currentLocale},
                        onSelectionChanged: (newSelection) {
                          voice.switchLanguage(newSelection.first);
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

            const SizedBox(height: 12),

            // Real System Clock Option Switch
            ValueListenableBuilder<bool>(
              valueListenable: SystemClockService.instance.useSystemClockNotifier,
              builder: (context, useSystemClock, _) {
                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.alarm_on_rounded, color: AppTheme.alarmColor, size: 24),
                          title: const Text(
                            'Dùng Đồng Hồ Thật Của Máy',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          subtitle: const Text(
                            'Kích hoạt app Clock thật của hệ thống Android',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          value: useSystemClock,
                          onChanged: (val) {
                            SystemClockService.instance.useSystemClockNotifier.value = val;
                          },
                        ),
                        Divider(height: 1, color: Colors.grey.withAlpha(40)),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => SystemClockService.instance.openSystemClock(),
                              icon: const Icon(Icons.open_in_new_rounded, size: 16),
                              label: const Text('Mở App Đồng Hồ Thật', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Microphone Big Button with Acoustic Sound Wave Effect
            Center(
              child: ValueListenableBuilder<bool>(
                valueListenable: voice.isListeningNotifier,
                builder: (context, isListening, child) {
                  final isEn = voice.currentLocaleNotifier.value.startsWith('en');
                  return Column(
                    children: [
                      // Stable Mic Button with gentle glow
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: Center(
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, _) {
                              final glowAlpha = isListening ? (50 + (40 * _pulseController.value).round()) : 40;
                              return Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isListening ? Colors.redAccent : AppTheme.voiceColor,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isListening ? Colors.redAccent : AppTheme.voiceColor).withAlpha(glowAlpha),
                                      blurRadius: isListening ? 20 : 12,
                                      spreadRadius: isListening ? 4 : 1,
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _toggleListening,
                                    customBorder: const CircleBorder(),
                                    child: Icon(
                                      isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                                      color: Colors.white,
                                      size: 56,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Fixed-height Equalizer Area
                      SizedBox(
                        height: 32,
                        child: Center(
                          child: isListening
                              ? AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, _) {
                                    final p = _pulseController.value;
                                    final heights = [
                                      8.0 + 10.0 * math.sin(p * math.pi * 2).abs(),
                                      12.0 + 14.0 * math.sin((p + 0.2) * math.pi * 2).abs(),
                                      16.0 + 12.0 * math.sin((p + 0.4) * math.pi * 2).abs(),
                                      18.0 + 10.0 * math.sin((p + 0.6) * math.pi * 2).abs(),
                                      16.0 + 12.0 * math.sin((p + 0.8) * math.pi * 2).abs(),
                                      12.0 + 14.0 * math.sin((p + 0.3) * math.pi * 2).abs(),
                                      8.0 + 10.0 * math.sin((p + 0.5) * math.pi * 2).abs(),
                                    ];
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: heights.map((h) {
                                        return Container(
                                          margin: const EdgeInsets.symmetric(horizontal: 3),
                                          width: 4,
                                          height: h,
                                          decoration: BoxDecoration(
                                            color: Colors.redAccent,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  },
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(height: 6),

                      Text(
                        isListening
                            ? (isEn ? 'LISTENING (English en_US)...' : 'ĐANG LẮNG NGHE (Tiếng Việt vi_VN)...')
                            : (isEn ? 'Tap to Speak (English)' : 'Chạm để nói câu lệnh tiếng Việt'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isListening ? Colors.redAccent : AppTheme.voiceColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isListening
                            ? (isEn ? 'Say: "Set alarm at 7:30" or "Start"' : 'Nói: "Báo thức 7 giờ 30" hoặc "Bắt đầu"')
                            : (isEn
                                ? 'Say: "Set alarm at 7:30" • "Start" • "Stop"'
                                : 'Nói: "Báo thức 7 giờ 30" • "Bắt đầu" • "Kết thúc"'),
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Live recognized words card
            ValueListenableBuilder<String>(
              valueListenable: voice.spokenWordsNotifier,
              builder: (context, words, child) {
                if (words.isEmpty) return const SizedBox.shrink();

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.voiceColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.voiceColor.withAlpha(80)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.graphic_eq_rounded, color: AppTheme.voiceColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '"$words"',
                          style: const TextStyle(
                            fontSize: 15,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Quick Preset Command Chips
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.touch_app_rounded, color: AppTheme.voiceColor, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Thử Nhanh Câu Lệnh (1-Tap Test)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<String>(
                      valueListenable: voice.currentLocaleNotifier,
                      builder: (context, locale, _) {
                        final presets = _getPresets(locale);
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: presets.map((cmd) {
                            return ActionChip(
                              avatar: const Icon(Icons.volume_up_rounded, size: 16),
                              label: Text(cmd),
                              onPressed: () => _executeCommand(cmd),
                            );
                          }).toList(),
                        );
                      },
                    ),
                    const SizedBox(height: 14),

                    // Manual text input command test
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customCommandController,
                            decoration: InputDecoration(
                              hintText: 'Hoặc gõ câu lệnh vào đây để test...',
                              hintStyle: const TextStyle(fontSize: 13),
                              prefixIcon: const Icon(Icons.keyboard_outlined),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onSubmitted: _executeCommand,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: () => _executeCommand(_customCommandController.text),
                          icon: const Icon(Icons.send_rounded),
                          style: IconButton.styleFrom(backgroundColor: AppTheme.voiceColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // History Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Lịch Sử Nhận Diện & Thực Thi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                ValueListenableBuilder<List<VoiceCommandResult>>(
                  valueListenable: voice.commandHistoryNotifier,
                  builder: (context, history, child) {
                    if (history.isEmpty) return const SizedBox.shrink();
                    return TextButton.icon(
                      onPressed: () => voice.clearHistory(),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                      label: const Text('Xóa', style: TextStyle(fontSize: 12)),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 8),

            // History List
            ValueListenableBuilder<List<VoiceCommandResult>>(
              valueListenable: voice.commandHistoryNotifier,
              builder: (context, history, child) {
                if (history.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    alignment: Alignment.center,
                    child: Text(
                      'Chưa có câu lệnh nào được thực thi',
                      style: TextStyle(color: theme.hintColor, fontSize: 13),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: history.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final item = history[idx];
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: item.isSuccess
                              ? AppTheme.voiceColor.withAlpha(30)
                              : Colors.orange.withAlpha(30),
                          child: Icon(
                            item.isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                            color: item.isSuccess ? AppTheme.voiceColor : Colors.orange,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          '"${item.rawSpokenText}"',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text(
                          item.responseMessage,
                          style: TextStyle(
                            fontSize: 12,
                            color: item.isSuccess ? Colors.green.shade700 : Colors.orange.shade900,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 24),
          ],
        ),
      );
  }
}
