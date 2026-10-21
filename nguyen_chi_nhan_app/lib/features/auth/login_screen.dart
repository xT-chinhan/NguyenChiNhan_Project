import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'otp_screen.dart';
import 'register_screen.dart';

/// 01 Đăng nhập bước 1: tên đăng nhập + mật khẩu
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _user.text.trim().toLowerCase();
    if (username.isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Nhập tên đăng nhập và mật khẩu.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.i.post('/auth/login', {'username': username, 'password': _pass.text});
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => OtpScreen(mode: OtpMode.login, info: r)));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'EMAIL_NOT_VERIFIED') {
        toast(context, e.message);
        Navigator.push(context, MaterialPageRoute(builder: (_) => OtpScreen(mode: OtpMode.verifyEmail, info: {...e.data, 'username': username})));
      } else if (e.code == 'MUST_RESET') {
        toast(context, e.message);
        Navigator.push(context, MaterialPageRoute(builder: (_) => OtpScreen(mode: OtpMode.reset, info: {'username': username, 'resendAfter': 0})));
      } else {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgot() async {
    final username = _user.text.trim().toLowerCase();
    if (username.isEmpty) {
      setState(() => _error = 'Nhập tên đăng nhập trước, mã đặt lại sẽ gửi về email của tài khoản đó.');
      return;
    }
    final r = await guard(context, () => Api.i.post('/auth/forgot', {'username': username}));
    if (r == null || !mounted) return;
    if (r['maskedEmail'] == null) {
      toast(context, r['message']);
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => OtpScreen(mode: OtpMode.reset, info: r)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: kPad),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 36),
                  const Align(alignment: Alignment.centerLeft, child: Logo(size: 56)),
                  const SizedBox(height: 24),
                  const Text('Chào mừng trở lại', style: T.headline),
                  const SizedBox(height: 8),
                  Text('Đăng nhập Chí Nhân Store. Bước sau sẽ cần mã OTP gửi về email của bạn.', style: T.bodyM.copyWith(color: c.muted)),
                  const SizedBox(height: 32),
                  const FieldLabel('Tên đăng nhập'),
                  AppInput(_user, icon: LucideIcons.user, hint: 'vd: baongoc', action: TextInputAction.next),
                  const SizedBox(height: 16),
                  const FieldLabel('Mật khẩu'),
                  AppInput(_pass, icon: LucideIcons.lockKeyhole, password: true, action: TextInputAction.done, onSubmitted: (_) => _submit()),
                  if (_error != null) ErrorLine(_error!),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgot,
                      style: TextButton.styleFrom(foregroundColor: c.ink, padding: const EdgeInsets.symmetric(vertical: 12)),
                      child: const Text('Quên mật khẩu?', style: TextStyle(fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const Spacer(),
                  Btn('Tiếp tục', loading: _loading, onTap: _submit),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: Divider(color: c.outline)),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('chưa có tài khoản?', style: TextStyle(fontSize: 13, color: c.faint))),
                    Expanded(child: Divider(color: c.outline)),
                  ]),
                  const SizedBox(height: 16),
                  Btn.secondary('Tạo tài khoản mới', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen()))),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
