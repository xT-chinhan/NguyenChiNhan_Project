import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/alarm_model.dart';
import '../../services/alarm_manager.dart';
import '../../theme/app_theme.dart';

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  late Timer _timer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _showAddAlarmDialog() async {
    final now = TimeOfDay.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: now,
      helpText: 'CHỌN GIỜ BÁO THỨC',
      cancelText: 'HỦY',
      confirmText: 'CHỌN',
    );

    if (pickedTime == null || !mounted) return;

    final labelController = TextEditingController(text: 'Báo thức');
    List<int> selectedDays = [];

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.alarmColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.alarm_add_rounded, color: AppTheme.alarmColor),
                  ),
                  const SizedBox(width: 12),
                  const Text('Thêm Báo Thức'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.alarmColor,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: labelController,
                      decoration: InputDecoration(
                        labelText: 'Nhãn báo thức',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Lặp lại các ngày:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: List.generate(7, (i) {
                        final dayNum = i + 1;
                        const labels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
                        final isSel = selectedDays.contains(dayNum);
                        return FilterChip(
                          label: Text(labels[i]),
                          selected: isSel,
                          selectedColor: AppTheme.alarmColor,
                          labelStyle: TextStyle(
                            color: isSel ? Colors.white : null,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          ),
                          onSelected: (selected) {
                            setDialogState(() {
                              if (selected) {
                                selectedDays.add(dayNum);
                              } else {
                                selectedDays.remove(dayNum);
                              }
                            });
                          },
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.alarmColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    AlarmManager.instance.addAlarm(
                      time: pickedTime,
                      label: labelController.text.trim().isEmpty ? 'Báo thức' : labelController.text.trim(),
                      repeatDays: selectedDays,
                    );
                    Navigator.of(dialogCtx).pop();

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã đặt báo thức lúc ${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}',
                        ),
                        backgroundColor: AppTheme.alarmColor,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: const Text('Lưu Báo Thức'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFormat = DateFormat('HH:mm:ss');
    const viDayNames = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
    final dayName = viDayNames[_currentTime.weekday - 1];
    final dayStr = _currentTime.day.toString().padLeft(2, '0');
    final monthStr = _currentTime.month.toString().padLeft(2, '0');
    final formattedDate = '$dayName, $dayStr/$monthStr/${_currentTime.year}';

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.alarmColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('Thêm Báo Thức', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _showAddAlarmDialog,
      ),
      body: ValueListenableBuilder<List<AlarmModel>>(
        valueListenable: AlarmManager.instance.alarmsNotifier,
        builder: (context, alarms, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Digital Real-time Clock Banner
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C3AED).withAlpha(80),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        timeFormat.format(_currentTime),
                        style: const TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withAlpha(200),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(40),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'Đang giám sát ${alarms.where((a) => a.isEnabled).length} báo thức đang bật',
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Alarms List Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Danh Sách Báo Thức (${alarms.length})',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Chuông WAV',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.alarmColor),
                    ),
                  ],
                ), const SizedBox(height: 12),

                if (alarms.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(Icons.alarm_off_rounded, size: 64, color: theme.hintColor.withAlpha(100)),
                        const SizedBox(height: 12),
                        Text(
                          'Chưa có báo thức nào',
                          style: TextStyle(color: theme.hintColor, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Nhấn nút bên dưới để tạo báo thức mới',
                          style: TextStyle(color: theme.hintColor, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: alarms.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final alarm = alarms[index];
                      return Card(
                        elevation: alarm.isEnabled ? 2 : 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: alarm.isEnabled
                                ? AppTheme.alarmColor.withAlpha(80)
                                : theme.dividerColor.withAlpha(40),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              // Time display
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                     FittedBox(
                                       fit: BoxFit.scaleDown,
                                       alignment: Alignment.centerLeft,
                                       child: Row(
                                         crossAxisAlignment: CrossAxisAlignment.baseline,
                                         textBaseline: TextBaseline.alphabetic,
                                         children: [
                                           Text(
                                             alarm.formattedTime,
                                             style: TextStyle(
                                               fontSize: 32,
                                               fontWeight: FontWeight.bold,
                                               fontFamily: 'monospace',
                                               color: alarm.isEnabled
                                                   ? theme.textTheme.titleLarge?.color
                                                   : theme.hintColor,
                                             ),
                                           ),
                                           const SizedBox(width: 6),
                                           Text(
                                             alarm.period,
                                             style: TextStyle(
                                               fontSize: 14,
                                               fontWeight: FontWeight.w700,
                                               color: alarm.isEnabled
                                                   ? AppTheme.alarmColor
                                                   : theme.hintColor,
                                             ),
                                           ),
                                           if (alarm.isSnoozed) ...[
                                             const SizedBox(width: 8),
                                             Container(
                                               padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                               decoration: BoxDecoration(
                                                 color: Colors.amber.withAlpha(40),
                                                 borderRadius: BorderRadius.circular(6),
                                               ),
                                               child: const Text(
                                                 'Snoozed',
                                                 style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold),
                                               ),
                                             ),
                                           ],
                                         ],
                                       ),
                                     ),
                                     const SizedBox(height: 4),
                                     Row(
                                       children: [
                                         Icon(
                                           Icons.label_outline_rounded,
                                           size: 14,
                                           color: alarm.isEnabled ? AppTheme.alarmColor : theme.hintColor,
                                         ),
                                         const SizedBox(width: 4),
                                         Expanded(
                                           child: Text(
                                             '${alarm.label} • ${alarm.repeatText}',
                                             maxLines: 1,
                                             overflow: TextOverflow.ellipsis,
                                             style: TextStyle(
                                               fontSize: 12,
                                               fontWeight: FontWeight.w500,
                                               color: alarm.isEnabled ? null : theme.hintColor,
                                             ),
                                           ),
                                         ),
                                       ],
                                     ),
                                   ],
                                 ),
                               ),

                               // Test Audio Button
                               IconButton(
                                 visualDensity: VisualDensity.compact,
                                 padding: EdgeInsets.zero,
                                 constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                 icon: const Icon(Icons.volume_up_rounded, size: 22),
                                 color: AppTheme.alarmColor,
                                 tooltip: 'Thử chuông ngay lập tức',
                                 onPressed: () {
                                   AlarmManager.instance.testTriggerAlarm(alarm);
                                 },
                               ),

                               // Switch
                               Switch(
                                 value: alarm.isEnabled,
                                 activeThumbColor: AppTheme.alarmColor,
                                 onChanged: (val) {
                                   AlarmManager.instance.toggleAlarm(alarm.id, val);
                                 },
                               ),

                               // Delete Button
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.grey, size: 20),
                                tooltip: 'Xóa báo thức',
                                onPressed: () {
                                  AlarmManager.instance.deleteAlarm(alarm.id);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }
}
