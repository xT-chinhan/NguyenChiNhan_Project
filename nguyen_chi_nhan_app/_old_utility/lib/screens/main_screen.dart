import 'package:flutter/material.dart';
import '../services/alarm_manager.dart';
import '../shop/screens/login_screen.dart';
import '../shop/screens/main_screen.dart' as shop;
import '../shop/utils/auth.dart';
import '../theme/app_theme.dart';
import 'alarm/alarm_screen.dart';
import 'alarm/widgets/alarm_ring_dialog.dart';
import 'profile/profile_screen.dart';
import 'team/team_screen.dart';
import 'translator/translator_screen.dart';
import 'voice/voice_screen.dart';

class MainScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDarkMode;

  const MainScreen({
    super.key,
    required this.onToggleTheme,
    required this.isDarkMode,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _isShowingAlarmDialog = false;

  @override
  void initState() {
    super.initState();
    AlarmManager.instance.ringingAlarmNotifier.addListener(_onAlarmRinging);
  }

  @override
  void dispose() {
    AlarmManager.instance.ringingAlarmNotifier.removeListener(_onAlarmRinging);
    super.dispose();
  }

  void _onAlarmRinging() {
    final ringing = AlarmManager.instance.ringingAlarmNotifier.value;
    if (ringing != null && !_isShowingAlarmDialog && mounted) {
      _isShowingAlarmDialog = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlarmRingDialog(alarm: ringing),
      ).then((_) {
        _isShowingAlarmDialog = false;
      });
    }
  }

  void _switchTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đăng xuất')),
        ],
      ),
    );
    if (confirm != true) return;
    await Auth.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showArchitectureDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.hub_rounded, color: AppTheme.primaryBlue),
            SizedBox(width: 10),
            Text('Kiến Trúc 10 Agent Swarm'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '🧠 5 Agent Phân Tích & Kịch Bản (Planning Swarm):',
                style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
              ),
              SizedBox(height: 4),
              Text('1. System & Platform Architect: Quyền AndroidManifest & BottomNavigationBar.'),
              Text('2. Profile & Deep Link Architect: Kịch bản gọi điện thoại & mở app YouTube.'),
              Text('3. Multilingual NLP Architect: Parser song ngữ Việt - Anh & Intent đồng hồ thật.'),
              Text('4. ML Kit Vision & NLP Architect: Pipeline Text, Voice, OCR Scanner, Realtime Camera.'),
              Text('5. Team Showcase & QA Lead: Đặc tả thẻ thành viên HUTECH & Barem điểm 10+.'),
              SizedBox(height: 12),
              Text(
                '⚡ 5 Agent Thực Thi & Code (Execution Swarm):',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
              ),
              SizedBox(height: 4),
              Text('6. Core Config Engineer: Cài dependencies, cấp quyền & cấu hình minSdk 21.'),
              Text('7. Profile Screen Developer: Triển khai màn hình Cá Nhân & url_launcher.'),
              Text('8. Voice Alarm Engineer: Bộ nhận diện giọng nói & MethodChannel AlarmClock.'),
              Text('9. ML Kit Developer: Triển khai 4 cấp độ dịch thuật Google ML Kit On-Device.'),
              Text('10. Team Slider & Live QA: Triển khai PageView thẻ thành viên & Kiểm thử.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const ProfileScreen(),
      VoiceScreen(onSwitchTab: _switchTab),
      const TranslatorScreen(),
      const TeamScreen(),
      const AlarmScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _getTabColor(_currentIndex).withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _getTabIcon(_currentIndex),
                color: _getTabColor(_currentIndex),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _getTabTitle(_currentIndex),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_rounded),
            tooltip: 'Cửa hàng',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const shop.MainScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.hub_outlined),
            tooltip: 'Kiến trúc 10 Agent Swarm',
            onPressed: _showArchitectureDialog,
          ),
          IconButton(
            icon: Icon(widget.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            tooltip: widget.isDarkMode ? 'Chuyển Chế độ Sáng' : 'Chuyển Chế độ Tối',
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Đăng xuất',
            onPressed: _handleLogout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      // IndexedStack preserves state of camera, inputs, and timer across tabs!
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _switchTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: AppTheme.primaryBlue),
            label: 'Cá Nhân',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none_rounded),
            selectedIcon: Icon(Icons.mic_rounded, color: AppTheme.voiceColor),
            label: 'Báo Thức Voice',
          ),
          NavigationDestination(
            icon: Icon(Icons.translate_rounded),
            selectedIcon: Icon(Icons.g_translate_rounded, color: Colors.purple),
            label: 'Dịch ML Kit',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded, color: Colors.pink),
            label: 'Nhóm SV',
          ),
          NavigationDestination(
            icon: Icon(Icons.alarm_rounded),
            selectedIcon: Icon(Icons.alarm_on_rounded, color: AppTheme.alarmColor),
            label: 'Quản Lý Báo Thức',
          ),
        ],
      ),
    );
  }

  IconData _getTabIcon(int idx) {
    switch (idx) {
      case 0: return Icons.person_rounded;
      case 1: return Icons.mic_rounded;
      case 2: return Icons.g_translate_rounded;
      case 3: return Icons.groups_rounded;
      case 4: return Icons.alarm_rounded;
      default: return Icons.dashboard_rounded;
    }
  }

  Color _getTabColor(int idx) {
    switch (idx) {
      case 0: return AppTheme.primaryBlue;
      case 1: return AppTheme.voiceColor;
      case 2: return Colors.purple;
      case 3: return Colors.pink;
      case 4: return AppTheme.alarmColor;
      default: return AppTheme.primaryBlue;
    }
  }

  String _getTabTitle(int idx) {
    switch (idx) {
      case 0: return 'Cá Nhân (YC2 - 3.5đ)';
      case 1: return 'Báo Thức Voice (YC3 - 5đ)';
      case 2: return 'Dịch ML Kit (7đ - 10đ+)';
      case 3: return 'Thông Tin Nhóm (YC6)';
      case 4: return 'Quản Lý Báo Thức';
      default: return 'NguyenChiNhan App';
    }
  }
}
