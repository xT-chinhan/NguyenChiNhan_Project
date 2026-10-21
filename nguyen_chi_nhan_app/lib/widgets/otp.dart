import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme.dart';

/// 6 ô OTP: ô đang nhập viền đậm + con trỏ, lỗi thì viền đỏ
class OtpBoxes extends StatelessWidget {
  final String value;
  final bool error;
  const OtpBoxes(this.value, {super.key, this.error = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(children: [
      for (var i = 0; i < 6; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: error ? c.dangerBar : (i == value.length ? c.ink : c.outline),
                width: error || i == value.length ? 1.4 : 1,
              ),
            ),
            child: i < value.length
                ? Text(value[i], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, fontFeatures: T.num))
                : (i == value.length && !error ? Container(width: 2, height: 24, color: c.ink) : null),
          ),
        ),
      ],
    ]);
  }
}

/// Bàn phím số lớn ở đáy màn hình (vùng ngón cái)
class Keypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  const Keypad({super.key, required this.onDigit, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback? onTap) => Expanded(
          child: InkResponse(
            onTap: onTap,
            radius: 36,
            child: SizedBox(height: 58, child: Center(child: child)),
          ),
        );
    Widget row(List<String> ds) => Row(children: [
          for (final d in ds) key(Text(d, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500)), () => onDigit(d)),
        ]);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      row(['1', '2', '3']),
      row(['4', '5', '6']),
      row(['7', '8', '9']),
      Row(children: [
        key(const SizedBox(), null),
        key(const Text('0', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w500)), () => onDigit('0')),
        key(Icon(LucideIcons.delete, size: 24, color: context.c.ink), onDelete),
      ]),
    ]);
  }
}
