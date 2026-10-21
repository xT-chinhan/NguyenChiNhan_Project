import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../home/role_home.dart';

/// 40 Dashboard quản trị
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
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
      final r = await Api.i.get('/dashboard/admin');
      if (mounted) setState(() => _d = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = _d;
    final u = d?['users'];
    const staffColor = Color(0xFF787774);
    const userColor = Color(0xFFDAD8D2);
    Widget legend(Color col, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 5),
          Text(t, style: T.bodyS.copyWith(color: c.muted)),
        ]);
    Widget stat(String k, dynamic v, int tab) => Expanded(
          child: Press(
            onTap: () => TabSwitcher.of(context)?.go(tab),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(k, style: T.bodyS.copyWith(color: c.muted)),
                const SizedBox(height: 2),
                v == null ? const Skeleton(width: 30, height: 22) : Text('$v', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, fontFeatures: T.num)),
              ]),
            ),
          ),
        );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.ink,
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 24), children: [
            const SizedBox(height: 48, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Logo(), RoleTag('Admin', withIcon: true)])),
            const SizedBox(height: 8),
            Text('Chào ${Api.i.session.value?.firstName ?? ''}', style: T.headline),
            const SizedBox(height: 16),
            if (_error != null)
              LoadError(_error!, onRetry: _load)
            else ...[
              Press(
                onTap: () => TabSwitcher.of(context)?.go(3),
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Người dùng', style: T.label.copyWith(color: c.muted)),
                      Row(children: [Text('Quản lý', style: T.label.copyWith(color: c.muted)), Icon(LucideIcons.chevronRight, size: 16, color: c.muted)]),
                    ]),
                    const SizedBox(height: 8),
                    u == null ? const Skeleton(width: 80, height: 40) : Text('${u['total']}', style: T.display),
                    const SizedBox(height: 12),
                    if (u != null && u['total'] > 0)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 8,
                          child: Row(children: [
                            if (u['Admin'] > 0) Expanded(flex: u['Admin'], child: Container(color: c.ink)),
                            if (u['Staff'] > 0) ...[const SizedBox(width: 2), Expanded(flex: u['Staff'], child: Container(color: staffColor))],
                            if (u['User'] > 0) ...[const SizedBox(width: 2), Expanded(flex: u['User'], child: Container(color: userColor))],
                          ]),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 14, children: [
                      legend(c.ink, 'Quản trị ${u?['Admin'] ?? ''}'),
                      legend(staffColor, 'Nhân viên ${u?['Staff'] ?? ''}'),
                      legend(userColor, 'Khách ${u?['User'] ?? ''}'),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [stat('Sản phẩm', d?['products'], 2), const SizedBox(width: 12), stat('Danh mục', d?['categories'], 1)]),
              const SizedBox(height: 20),
              const Text('Đăng nhập gần đây', style: T.titleM),
              const SizedBox(height: 8),
              if (d == null)
                const ListSkeleton(rows: 2)
              else
                AppCard.flush(
                  child: Column(
                    children: withDividers([
                      for (final l in d['recentLogins'])
                        ListRow(
                          leading: Avatar(_initials(l['fullName']), size: 40, color: l['role'] == 'Admin' ? null : (l['role'] == 'Staff' ? staffColor : const Color(0xFFB9B7B0))),
                          title: l['fullName'],
                          subtitle: [l['platform'] ?? l['device'], l['city']].where((x) => x != null).join(' · '),
                          trailing: Text(relative(l['createdAt']) == 'Hôm nay' ? hm(l['createdAt']) : relative(l['createdAt']), style: T.bodyS.copyWith(color: c.faint)),
                        ),
                    ]),
                  ),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

String _initials(String name) {
  final p = name.trim().split(RegExp(r'\s+'));
  return p.length == 1 ? p.first[0].toUpperCase() : (p[p.length - 2][0] + p.last[0]).toUpperCase();
}
