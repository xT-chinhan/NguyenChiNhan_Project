import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'location_screen.dart';
import 'noise_screen.dart';
import 'translate_camera_screen.dart';

/// 12 Tiện ích: 3 chức năng mục 5 (f, d, b)
class ToolsScreen extends StatelessWidget {
  final bool standalone; // mở từ Tài khoản (Admin)
  const ToolsScreen({super.key, this.standalone = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget feat(IconData icon, String t, String s, Widget page) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Bubble(icon, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(s, style: T.bodyS.copyWith(color: c.muted)),
                ]),
              ),
              Icon(LucideIcons.chevronRight, size: 18, color: c.faint),
            ]),
          ),
        );
    return Scaffold(
      appBar: standalone ? const TopBar(back: 'Tài khoản') : null,
      body: SafeArea(
        bottom: false,
        child: ListView(padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 24), children: [
          if (!standalone) const PageHeader('Tiện ích') else const Text('Tiện ích', style: T.headline),
          Text('Chạy ngay trên điện thoại, kết quả xử lý ở máy chủ.', style: T.bodyM.copyWith(color: c.muted)),
          const SizedBox(height: 16),
          AppCard.flush(
            child: Column(
              children: withDividers([
                feat(LucideIcons.languages, 'Dịch realtime', 'Hướng camera vào chữ hoặc chọn ảnh. Máy đọc chữ, máy chủ dịch.', const TranslateCameraScreen()),
                feat(LucideIcons.audioLines, 'Đo tiếng ồn', 'Đo dB bằng micro, so với mức an toàn cho tai.', const NoiseScreen()),
                feat(LucideIcons.mapPin, 'Chia sẻ vị trí', 'Gửi vị trí hiện tại qua Zalo, Messenger, SMS bằng link Google Maps.', const LocationScreen()),
              ], indent: 16),
            ),
          ),
          const SizedBox(height: 16),
          const Note('Micro, camera và vị trí chỉ bật khi bạn mở tiện ích, không chạy nền.', icon: LucideIcons.shieldCheck),
        ]),
      ),
    );
  }
}
