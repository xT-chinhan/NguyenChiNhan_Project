import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/otp.dart';
import '../../widgets/ui.dart';
import '../home/role_home.dart';
import 'login_screen.dart';

enum OtpMode { verifyEmail, login, reset }

/// 03 / 04 / 05: nhập OTP 6 số (xác thực email, đăng nhập bước 2, đặt lại mật khẩu)
class OtpScreen extends StatefulWidget {
  final OtpMode mode;
  final Map<String, dynamic> info; // username, maskedEmail, resendAfter
  const OtpScreen({super.key, required this.mode, required this.info});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _code = '';
  String? _error;
  bool _loading = false;
  int _wait = 0;
  Timer? _timer;
  late String? _masked = widget.info['maskedEmail'];

  String get _username => widget.info['username'];
  String get _purpose => switch (widget.mode) { OtpMode.verifyEmail => 'verify_email', OtpMode.login => 'login', OtpMode.reset => 'reset' };

  @override
  void initState() {
    super.initState();
    _startCountdown((widget.info['resendAfter'] as num?)?.toInt() ?? 45);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown(int s) {
    _timer?.cancel();
    setState(() => _wait = s);
    if (s <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  void _digit(String d) {
    if (_code.length >= 6 || _loading) return;
    setState(() {
      if (_error != null) {
        _error = null;
        _code = '';
      }
      _code += d;
    });
    if (_code.length == 6 && widget.mode != OtpMode.reset) _submit();
  }

  Future<void> _resend() async {
    try {
      final r = await Api.i.post('/auth/resend', {'username': _username, 'purpose': _purpose});
      if (!mounted) return;
      setState(() {
        _masked = r['maskedEmail'] ?? _masked;
        _code = '';
        _error = null;
      });
      toast(context, 'Đã gửi mã mới tới ${_masked ?? 'email'}.');
      _startCountdown((r['resendAfter'] as num?)?.toInt() ?? 45);
    } on ApiException catch (e) {
      if (!mounted) return;
      toast(context, e.message, error: true);
      final w = (e.data['resendAfter'] as num?)?.toInt();
      if (w != null) _startCountdown(w);
    }
  }

  Future<void> _submit() async {
    if (_code.length != 6) return;
    if (widget.mode == OtpMode.reset) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => NewPasswordScreen(username: _username, code: _code)));
      return;
    }
    setState(() => _loading = true);
    try {
      if (widget.mode == OtpMode.verifyEmail) {
        final r = await Api.i.post('/auth/verify-email', {'username': _username, 'code': _code});
        if (!mounted) return;
        toast(context, r['message']);
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
      } else {
        final r = await Api.i.post('/auth/login/verify', {'username': _username, 'code': _code});
        await Api.i.saveSession(r['token'], r['role'], Map<String, dynamic>.from(r['user']));
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const RoleHome()), (_) => false);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (title, lead, action) = switch (widget.mode) {
      OtpMode.verifyEmail => ('Xác thực email', 'để kích hoạt tài khoản.', 'Kích hoạt tài khoản'),
      OtpMode.login => ('Nhập mã đăng nhập', ', hiệu lực 5 phút.', 'Đăng nhập'),
      OtpMode.reset => ('Mã đặt lại mật khẩu', 'để đặt mật khẩu mới.', 'Tiếp tục'),
    };
    return Scaffold(
      appBar: TopBar(
        back: widget.mode == OtpMode.login ? 'Đăng nhập' : 'Quay lại',
        actions: [if (widget.mode == OtpMode.login) Text('Bước 2/2', style: T.bodyS.copyWith(color: c.muted, fontWeight: FontWeight.w500))],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 12),
            Text(title, style: T.headline),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: widget.mode == OtpMode.login ? 'Mật khẩu đúng. Mã 6 số đã gửi tới ' : 'Nhập mã 6 số đã gửi tới '),
                TextSpan(text: _masked ?? 'email của bạn', style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                TextSpan(text: lead.startsWith(',') ? lead : ' $lead'),
              ]),
              style: T.bodyM.copyWith(color: c.muted),
            ),
            const SizedBox(height: 32),
            OtpBoxes(_code, error: _error != null),
            if (_error != null) ErrorLine(_error!),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Chưa nhận được mã?', style: T.bodyS.copyWith(color: c.muted)),
              _wait > 0
                  ? Text('Gửi lại sau 00:${_wait.toString().padLeft(2, '0')}', style: T.bodyS.copyWith(color: c.muted, fontFeatures: T.num))
                  : GestureDetector(onTap: _resend, child: Text('Gửi lại mã', style: T.bodyS.copyWith(fontWeight: FontWeight.w600))),
            ]),
            const Spacer(),
            Keypad(
              onDigit: _digit,
              onDelete: () => setState(() {
                _error = null;
                if (_code.isNotEmpty) _code = _code.substring(0, _code.length - 1);
              }),
            ),
            const SizedBox(height: 12),
            Btn(action, loading: _loading, onTap: _code.length == 6 && _error == null ? _submit : null),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }
}

/// Đặt mật khẩu mới (sau Quên mật khẩu hoặc sau “Không phải tôi”)
class NewPasswordScreen extends StatefulWidget {
  final String username;
  final String code;
  const NewPasswordScreen({super.key, required this.username, required this.code});
  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_p1.text != _p2.text) {
      setState(() => _error = 'Hai mật khẩu chưa khớp.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.i.post('/auth/reset', {'username': widget.username, 'code': widget.code, 'newPassword': _p1.text});
      if (!mounted) return;
      toast(context, r['message']);
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code?.startsWith('OTP') == true) {
        toast(context, e.message, error: true);
        Navigator.pop(context);
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const TopBar(back: 'Quay lại'),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPad),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 12),
              const Text('Đặt mật khẩu mới', style: T.headline),
              const SizedBox(height: 8),
              Text('Mọi thiết bị khác sẽ phải đăng nhập lại.', style: T.bodyM.copyWith(color: context.c.muted)),
              const SizedBox(height: 28),
              const FieldLabel('Mật khẩu mới'),
              AppInput(_p1, icon: LucideIcons.lockKeyhole, password: true, autofocus: true),
              const SizedBox(height: 14),
              const FieldLabel('Nhập lại'),
              AppInput(_p2, icon: LucideIcons.lockKeyhole, password: true, onSubmitted: (_) => _submit()),
              if (_error != null) ErrorLine(_error!),
              const Spacer(),
              Btn('Lưu mật khẩu mới', loading: _loading, onTap: _submit),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      );
}
