import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'otp_screen.dart';

/// 02 Đăng ký qua email -> 03 OTP xác thực email
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _user, _email, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.i.post('/auth/register', {
        'fullName': _name.text.trim(),
        'username': _user.text.trim().toLowerCase(),
        'email': _email.text.trim(),
        'password': _pass.text,
      });
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => OtpScreen(mode: OtpMode.verifyEmail, info: r)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      appBar: const TopBar(back: 'Đăng nhập'),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(kPad, 4, kPad, 16), children: [
              const Text('Tạo tài khoản', style: T.headline),
              const SizedBox(height: 8),
              Text('Mã xác thực sẽ được gửi tới email này.', style: T.bodyM.copyWith(color: c.muted)),
              const SizedBox(height: 20),
              const FieldLabel('Họ và tên'),
              AppInput(_name, icon: LucideIcons.user, hint: 'Nguyễn Văn A', caps: TextCapitalization.words, action: TextInputAction.next),
              const SizedBox(height: 12),
              const FieldLabel('Tên đăng nhập'),
              AppInput(_user, icon: LucideIcons.atSign, hint: 'chữ thường, số, dấu chấm', action: TextInputAction.next),
              const SizedBox(height: 12),
              const FieldLabel('Email'),
              AppInput(_email, icon: LucideIcons.mail, hint: 'ban@gmail.com', keyboard: TextInputType.emailAddress, action: TextInputAction.next),
              const SizedBox(height: 12),
              const FieldLabel('Mật khẩu'),
              AppInput(_pass, icon: LucideIcons.lockKeyhole, password: true, action: TextInputAction.done, onSubmitted: (_) => _submit()),
              Padding(padding: const EdgeInsets.only(top: 8, left: 2), child: Text('Ít nhất 6 ký tự.', style: T.bodyS.copyWith(color: c.muted))),
              if (_error != null) ErrorLine(_error!),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 16),
            child: Column(children: [
              const Note('Tài khoản mới là Khách hàng. Quản trị viên cấp quyền Nhân viên sau.'),
              const SizedBox(height: 12),
              Btn('Gửi mã xác thực', loading: _loading, onTap: _submit),
            ]),
          ),
        ]),
      ),
    );
  }
}
