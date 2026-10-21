import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../auth/otp_screen.dart';

/// 51 Lịch sử đăng nhập (mục 6): đánh dấu đăng nhập lạ, “Đúng là tôi” / “Không phải tôi”
class LoginHistoryScreen extends StatefulWidget {
  const LoginHistoryScreen({super.key});
  @override
  State<LoginHistoryScreen> createState() => _LoginHistoryScreenState();
}

class _LoginHistoryScreenState extends State<LoginHistoryScreen> {
  Map? _d;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Api.i.get('/me/sessions');
      if (mounted) setState(() => _d = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _trust(Map s) async {
    final r = await guard(context, () => Api.i.post('/me/sessions/${s['id']}/trust'));
    if (r != null && mounted) {
      toast(context, r['message']);
      _load();
    }
  }

  Future<void> _deny(Map s) async {
    final ok = await confirmDanger(
      context,
      icon: LucideIcons.shieldX,
      title: 'Không phải bạn?',
      text: 'Mọi thiết bị (kể cả máy này) sẽ bị đăng xuất. Mã đặt lại mật khẩu sẽ gửi tới email và Quản trị viên được báo.',
      action: 'Khóa tài khoản ngay',
    );
    if (!ok || !mounted) return;
    final s0 = Api.i.session.value;
    try {
      // API thu hồi mọi phiên -> lời gọi này vẫn thành công vì phiên hiện tại còn hợp lệ lúc gửi
      final r = await Api.i.post('/me/sessions/${s['id']}/deny');
      await Api.i.clearSession();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LockedScreen(result: {...r, 'username': r['username'] ?? s0?.user['username']})),
        (_) => false,
      );
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = _d;
    final strange = (d?['items'] as List?)?.where((x) => x['suspicious'] == true).toList() ?? [];
    return Scaffold(
      appBar: const TopBar(back: 'Quay lại'),
      body: RefreshIndicator(
        color: c.ink,
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 24), children: [
          const Text('Lịch sử đăng nhập', style: T.headline),
          const SizedBox(height: 16),
          if (_error != null)
            LoadError(_error!, onRetry: _load)
          else if (d == null)
            const ListSkeleton(rows: 3)
          else ...[
            if (strange.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.warningContainer, borderRadius: BorderRadius.circular(18)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Bubble(LucideIcons.shieldAlert, size: 32, tone: Tone.warn),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Có ${strange.length} đăng nhập lạ', style: TextStyle(fontWeight: FontWeight.w600, color: c.warning)),
                      const SizedBox(height: 2),
                      Text(
                        '${[strange.first['city'], hm(strange.first['createdAt'])].where((x) => x != null).join(', ')}. Nếu không phải bạn, khóa ngay để đăng xuất mọi thiết bị.',
                        style: T.bodyS.copyWith(color: c.warning.withValues(alpha: .85)),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            AppCard.flush(
              child: Column(
                children: withDividers([
                  for (final s in d['items']) _session(s),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                d['loginAlert'] == true
                    ? 'Mỗi lần đăng nhập thành công, email cảnh báo được gửi tới ${d['alertEmail']}.'
                    : 'Email cảnh báo đăng nhập đang tắt. Bật lại ở Tài khoản › Bảo mật.',
                style: T.bodyS.copyWith(color: c.muted),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _session(Map s) {
    final c = context.c;
    final phone = '${s['platform'] ?? ''}'.startsWith('Android') || '${s['platform'] ?? ''}'.startsWith('iOS');
    final where = [s['platform'], s['city']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    final when = s['current'] == true ? null : relative(s['createdAt'], withTime: true);
    Widget? badge;
    if (s['current'] == true) {
      badge = const Pill('Thiết bị này', tone: Tone.ok, height: 22);
    } else if (s['suspicious'] == true) {
      badge = const Pill('Lạ', tone: Tone.warn, height: 22);
    } else if (s['status'] == 'denied') {
      badge = const Pill('Đã chặn', tone: Tone.danger, height: 22);
    } else if (s['revoked'] == true) {
      badge = const Pill('Đã đăng xuất', height: 22);
    }
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Bubble(phone ? LucideIcons.smartphone : LucideIcons.monitor, tone: s['suspicious'] == true ? Tone.warn : Tone.normal),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(s['device'], maxLines: 1, overflow: TextOverflow.ellipsis, style: T.body)),
              ?badge,
            ]),
            const SizedBox(height: 1),
            Text([where, ?when].where((x) => x.isNotEmpty).join(' · '), style: T.bodyS.copyWith(color: c.muted)),
            if (s['suspicious'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  GestureDetector(onTap: () => _trust(s), child: const Text('Đúng là tôi', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  const SizedBox(width: 16),
                  GestureDetector(onTap: () => _deny(s), child: Text('Không phải tôi', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: c.danger))),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// 52 Sau “Không phải tôi”: đã khóa, đặt mật khẩu mới bằng mã trong email
class LockedScreen extends StatelessWidget {
  final Map result;
  const LockedScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget line(String t) => SizedBox(
          height: 48,
          child: Row(children: [Icon(LucideIcons.check, size: 20, color: c.income), const SizedBox(width: 12), Expanded(child: Text(t, style: const TextStyle(fontSize: 14.5)))]),
        );
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 48),
            const Center(child: Bubble(LucideIcons.shieldCheck, size: 72)),
            const SizedBox(height: 20),
            const Text('Đã bảo vệ tài khoản', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Mọi thiết bị đã bị đăng xuất. Đặt mật khẩu mới để đăng nhập lại.', textAlign: TextAlign.center, style: T.bodyM.copyWith(color: c.muted)),
            const SizedBox(height: 24),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: withDividers([
                  line('Đã đăng xuất ${result['revokedSessions'] ?? 0} thiết bị'),
                  line(result['resetCodeSent'] == false ? 'Mã đặt lại đã gửi trước đó, kiểm tra email' : 'Đã gửi mã đặt lại mật khẩu tới ${result['maskedEmail'] ?? 'email'}'),
                  if ((result['adminsNotified'] ?? 0) > 0) line('Quản trị viên được báo'),
                ], indent: 32),
              ),
            ),
            const Spacer(),
            Btn('Đặt mật khẩu mới', onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => OtpScreen(mode: OtpMode.reset, info: {'username': result['username'], 'maskedEmail': result['maskedEmail'], 'resendAfter': 45})),
              );
            }),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }
}
