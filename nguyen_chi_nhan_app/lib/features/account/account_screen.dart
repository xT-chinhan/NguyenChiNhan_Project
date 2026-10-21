import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../main.dart' show setDark, themeMode;
import '../../widgets/ui.dart';
import '../attendance/attendance_screen.dart';
import '../auth/login_screen.dart';
import '../shop/shop_screen.dart';
import '../tools/tools_screen.dart';
import 'login_history_screen.dart';

/// 13 / 47 Tài khoản: bật/tắt email cảnh báo đăng nhập (mục 6), lịch sử đăng nhập, đổi mật khẩu
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  int? _devices;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final me = await Api.i.get('/me');
      await Api.i.updateUser(Map<String, dynamic>.from(me));
      final s = await Api.i.get('/me/sessions');
      final active = (s['items'] as List).where((x) => x['revoked'] != true).map((x) => x['device']).toSet().length;
      if (mounted) setState(() => _devices = active);
    } catch (_) {}
  }

  Future<void> _toggleAlert(bool v) async {
    final r = await guard(context, () => Api.i.patch('/me', {'loginAlert': v}));
    if (r == null || !mounted) return;
    await Api.i.updateUser(Map<String, dynamic>.from(r));
    setState(() {});
    if (mounted) toast(context, v ? 'Đã bật email cảnh báo đăng nhập' : 'Đã tắt email cảnh báo đăng nhập');
  }

  Future<void> _logout() async {
    try {
      await Api.i.post('/auth/logout');
    } catch (_) {}
    await Api.i.clearSession();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = Api.i.session.value;
    if (s == null) return const SizedBox();
    final isAdmin = s.role == 'Admin';
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.ink,
          onRefresh: _refresh,
          child: ListView(padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 24), children: [
            const PageHeader('Tài khoản'),
            const SizedBox(height: 8),
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Avatar(s.initials),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.fullName, style: T.titleM),
                    Text(s.user['email'] ?? '', style: T.bodyS.copyWith(color: c.muted), overflow: TextOverflow.ellipsis),
                  ]),
                ),
                RoleTag(s.role),
              ]),
            ),
            if (isAdmin) ...[
              const GroupLabel('Công cụ'),
              AppCard.flush(
                child: Column(
                  children: withDividers([
                    SetRow(icon: LucideIcons.layoutGrid, label: 'Tiện ích', value: '3', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ToolsScreen(standalone: true)))),
                    SetRow(icon: LucideIcons.clock, label: 'Chấm công nhân viên', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceAdminScreen()))),
                    SetRow(icon: LucideIcons.mapPin, label: 'Vị trí chấm công', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceSiteScreen()))),
                    SetRow(icon: LucideIcons.store, label: 'Xem cửa hàng như khách', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopScreen(standalone: true)))),
                  ], indent: 60),
                ),
              ),
            ],
            const GroupLabel('Bảo mật'),
            AppCard.flush(
              child: Column(
                children: withDividers([
                  SetRow(icon: LucideIcons.shieldAlert, label: 'Email cảnh báo đăng nhập', trailing: AppSwitch(s.user['loginAlert'] == true, onChanged: _toggleAlert)),
                  SetRow(
                    icon: LucideIcons.monitorSmartphone,
                    label: 'Lịch sử đăng nhập',
                    value: _devices == null ? null : '$_devices thiết bị',
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginHistoryScreen()));
                      _refresh();
                    },
                  ),
                  SetRow(icon: LucideIcons.lockKeyhole, label: 'Đổi mật khẩu', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()))),
                ], indent: 60),
              ),
            ),
            const GroupLabel('Ứng dụng'),
            AppCard.flush(
              child: Column(
                children: withDividers([
                  ValueListenableBuilder(
                    valueListenable: themeMode,
                    builder: (_, m, _) => SetRow(icon: LucideIcons.moon, label: 'Giao diện tối', trailing: AppSwitch(m == ThemeMode.dark, onChanged: setDark)),
                  ),
                  SetRow(
                    icon: LucideIcons.info,
                    label: 'Giới thiệu',
                    value: 'v1.0.0',
                    onTap: () => showAboutDialog(
                      context: context,
                      applicationName: 'Chí Nhân Store',
                      applicationVersion: '1.0.0',
                      applicationLegalese: 'Đồ án Lập trình di động · Nguyễn Chí Nhân\nAPI: $apiUrl',
                    ),
                  ),
                ], indent: 60),
              ),
            ),
            const SizedBox(height: 20),
            Btn.secondary('Đăng xuất', icon: LucideIcons.logOut, onTap: _logout),
          ]),
        ),
      ),
    );
  }
}

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await Api.i.post('/me/password', {'currentPassword': _old.text, 'newPassword': _new.text});
      if (!mounted) return;
      toast(context, r['message']);
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(back: 'Tài khoản'),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 4),
              const Text('Đổi mật khẩu', style: T.headline),
              const SizedBox(height: 24),
              const FieldLabel('Mật khẩu hiện tại'),
              AppInput(_old, icon: LucideIcons.lockKeyhole, password: true),
              const SizedBox(height: 14),
              const FieldLabel('Mật khẩu mới'),
              AppInput(_new, icon: LucideIcons.lockKeyhole, password: true, onSubmitted: (_) => _save()),
              if (_error != null) ErrorLine(_error!),
              const Spacer(),
              Btn('Lưu mật khẩu', loading: _saving, onTap: _save),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      );
}
