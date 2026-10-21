import 'package:flutter/material.dart';
import '../../../models/alarm_model.dart';
import '../../../services/alarm_manager.dart';

class AlarmRingDialog extends StatefulWidget {
  final AlarmModel alarm;

  const AlarmRingDialog({super.key, required this.alarm});

  @override
  State<AlarmRingDialog> createState() => _AlarmRingDialogState();
}

class _AlarmRingDialogState extends State<AlarmRingDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _bellController;
  late Animation<double> _bellAnimation;

  @override
  void initState() {
    super.initState();
    _bellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _bellAnimation = Tween<double>(begin: -0.15, end: 0.15).animate(
      CurvedAnimation(parent: _bellController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bellController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        elevation: 16,
        backgroundColor: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ringing Animated Bell
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withAlpha(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withAlpha(50),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Center(
                  child: AnimatedBuilder(
                    animation: _bellAnimation,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _bellAnimation.value,
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: Colors.redAccent,
                          size: 48,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title & Time
              Text(
                'BÁO THỨC ĐANG REO!',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.alarm.formattedTime,
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.alarm.label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Action Buttons
              Row(
                children: [
                  // Snooze Button
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(color: theme.colorScheme.primary),
                      ),
                      onPressed: () {
                        AlarmManager.instance.snoozeRinging(minutes: 5);
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.snooze_rounded),
                      label: const Text(
                        'Báo lại (5p)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Dismiss Button
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      onPressed: () {
                        AlarmManager.instance.dismissRinging();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.alarm_off_rounded),
                      label: const Text(
                        'Tắt chuông',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
