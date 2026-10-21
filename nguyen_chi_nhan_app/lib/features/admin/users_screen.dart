import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

const _roleColor = {'Admin': null, 'Staff': Color(0xFF787774), 'User': Color(0xFFB9B7B0)};
const _roles = [
  ('Admin', 'Quản trị viên', 'Toàn quyền, kể cả xóa', LucideIcons.shieldCheck),
  ('Staff', 'Nhân viên', 'Thêm, sửa sản phẩm', LucideIcons.badgeCheck),
  ('User', 'Khách hàng', 'Xem cửa hàng, tiện ích', LucideIcons.shoppingBag),
];

String initialsOf(String name) {
  final p = name.trim().split(RegExp(r'\s+'));
  if (p.isEmpty || p.first.isEmpty) return '?';
  return p.length == 1 ? p.first[0].toUpperCase() : (p[p.length - 2][0] + p.last[0]).toUpperCase();
}

/// 45 / 46 Người dùng (Admin): lọc vai trò, thêm, đổi vai trò, xóa
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  Map? _data;
  Object? _error;
  String? _role;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final q = Uri(queryParameters: {'role': ?_role, if (_search.text.trim().isNotEmpty) 'q': _search.text.trim()}).query;
      final r = await Api.i.get('/users?$q');
      if (mounted) setState(() => _data = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _openUser(Map u) async {
    final changed = await showSheet<bool>(context, (ctx) => _UserSheet(user: u));
    if (changed == true) _load();
  }

  Future<void> _create() async {
    final created = await showSheet<Map>(context, (ctx) => const _CreateUserSheet());
    if (created == null || !mounted) return;
    toast(context, 'Đã tạo ${created['fullName']}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final counts = _data?['counts'];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.ink,
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPad),
              child: Column(children: [
                PageHeader('Người dùng', trailing: CircleBtn(LucideIcons.userPlus, onTap: _create)),
                const SizedBox(height: 8),
                SearchBox(_search, hint: 'Tên, email, tên đăng nhập…', onChanged: (_) {
                  setState(() {});
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), _load);
                }),
                const SizedBox(height: 12),
              ]),
            ),
            ChipBar<String?>(
              items: [
                (null, 'Tất cả ${counts?['all'] ?? ''}'.trim()),
                ('Admin', 'Quản trị ${counts?['Admin'] ?? ''}'.trim()),
                ('Staff', 'Nhân viên ${counts?['Staff'] ?? ''}'.trim()),
                ('User', 'Khách ${counts?['User'] ?? ''}'.trim()),
              ],
              selected: _role,
              onSelect: (r) {
                setState(() => _role = r);
                _load();
              },
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPad),
              child: _error != null
                  ? LoadError(_error!, onRetry: _load)
                  : _data == null
                      ? const ListSkeleton(rows: 5)
                      : (_data!['items'] as List).isEmpty
                          ? const EmptyState(icon: LucideIcons.users, title: 'Không tìm thấy người dùng', top: 32)
                          : AppCard.flush(
                              child: Column(
                                children: withDividers([
                                  for (final u in _data!['items'])
                                    ListRow(
                                      leading: Avatar(initialsOf(u['fullName']), size: 40, color: _roleColor[u['role']]),
                                      title: u['fullName'],
                                      subtitle: u['isMe'] == true ? '${u['username']} · bạn' : u['email'],
                                      trailing: u['emailConfirmed'] == true ? RoleTag(u['role']) : const Pill('Chưa xác thực', tone: Tone.warn, height: 22),
                                      onTap: u['isMe'] == true ? null : () => _openUser(u),
                                    ),
                                ]),
                              ),
                            ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _UserSheet extends StatefulWidget {
  final Map user;
  const _UserSheet({required this.user});
  @override
  State<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends State<_UserSheet> {
  late String _role = widget.user['role'];
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await guard(context, () => Api.i.put('/users/${widget.user['id']}', {'role': _role}));
    if (!mounted) return;
    setState(() => _saving = false);
    if (r != null) {
      toast(context, 'Đã đổi ${r['fullName']} thành ${RoleTag.label(_role)}');
      Navigator.pop(context, true);
    }
  }

  Future<void> _delete() async {
    final nav = Navigator.of(context);
    final ok = await confirmDanger(context, title: 'Xóa ${widget.user['fullName']}?', text: 'Tài khoản và lịch sử đăng nhập sẽ bị xóa vĩnh viễn.', action: 'Xóa người dùng');
    if (!ok || !mounted) return;
    final r = await guard(context, () => Api.i.delete('/users/${widget.user['id']}'));
    if (r != null && mounted) {
      toast(context, r['message']);
      nav.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final u = widget.user;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Avatar(initialsOf(u['fullName']), color: _roleColor[u['role']]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u['fullName'], style: T.titleM),
            Text('${u['username']} · ${u['email']}', style: T.bodyS.copyWith(color: c.muted), overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
      const SizedBox(height: 20),
      Text('Vai trò', style: T.label.copyWith(color: c.muted)),
      const SizedBox(height: 8),
      AppCard.flush(
        child: Column(
          children: withDividers([
            for (final r in _roles) SetRow(icon: r.$4, label: r.$2, sub: r.$3, chevron: false, trailing: RadioDot(_role == r.$1), onTap: () => setState(() => _role = r.$1)),
          ], indent: 60),
        ),
      ),
      const SizedBox(height: 8),
      Text('Đổi vai trò sẽ đăng xuất người này khỏi mọi thiết bị.', style: T.bodyS.copyWith(color: c.muted)),
      const SizedBox(height: 16),
      Btn('Lưu vai trò', loading: _saving, onTap: _role == u['role'] ? null : _save),
      const SizedBox(height: 8),
      Btn('Xóa người dùng', kind: BtnKind.dangerText, onTap: _delete),
    ]);
  }
}

class _CreateUserSheet extends StatefulWidget {
  const _CreateUserSheet();
  @override
  State<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends State<_CreateUserSheet> {
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  String _role = 'Staff';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final x in [_name, _user, _email, _pass]) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await Api.i.post('/users', {
        'fullName': _name.text.trim(),
        'username': _user.text.trim(),
        'email': _email.text.trim(),
        'password': _pass.text,
        'role': _role,
      });
      if (mounted) Navigator.pop(context, r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Thêm người dùng', style: T.titleL),
        const SizedBox(height: 14),
        AppInput(_name, icon: LucideIcons.user, hint: 'Họ và tên', caps: TextCapitalization.words),
        const SizedBox(height: 10),
        AppInput(_user, icon: LucideIcons.atSign, hint: 'Tên đăng nhập'),
        const SizedBox(height: 10),
        AppInput(_email, icon: LucideIcons.mail, hint: 'Email', keyboard: TextInputType.emailAddress),
        const SizedBox(height: 10),
        AppInput(_pass, icon: LucideIcons.lockKeyhole, hint: 'Mật khẩu (≥ 6 ký tự)', password: true),
        const SizedBox(height: 14),
        Segmented(items: const ['Nhân viên', 'Khách hàng', 'Quản trị'], index: ['Staff', 'User', 'Admin'].indexOf(_role), onChanged: (i) => setState(() => _role = ['Staff', 'User', 'Admin'][i])),
        if (_error != null) ErrorLine(_error!),
        const SizedBox(height: 18),
        Btn('Tạo tài khoản', loading: _saving, onTap: _save),
      ]);
}
