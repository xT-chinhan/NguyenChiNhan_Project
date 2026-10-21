import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../home/role_home.dart';
import 'product_form_screen.dart';

/// 30 Dashboard nhân viên
class StaffHome extends StatefulWidget {
  const StaffHome({super.key});
  @override
  State<StaffHome> createState() => _StaffHomeState();
}

class _StaffHomeState extends State<StaffHome> {
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
      final r = await Api.i.get('/dashboard/staff');
      if (mounted) setState(() => _d = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = Api.i.session.value;
    final d = _d;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.ink,
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 24), children: [
            const SizedBox(height: 48, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Logo(), RoleTag('Staff', withIcon: true)])),
            const SizedBox(height: 8),
            Text('Chào ${s?.firstName ?? ''}', style: T.headline),
            const SizedBox(height: 16),
            if (_error != null)
              LoadError(_error!, onRetry: _load)
            else ...[
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Sản phẩm đang bán', style: T.label.copyWith(color: c.muted)),
                  const SizedBox(height: 8),
                  d == null ? const Skeleton(width: 60, height: 40) : Text('${d['products']}', style: T.display),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: c.outlineVariant)),
                  IntrinsicHeight(
                    child: Row(children: [
                      Expanded(child: _mini(context, 'Danh mục', d?['categories'])),
                      VerticalDivider(width: 1, color: c.outlineVariant),
                      const SizedBox(width: 16),
                      Expanded(child: _mini(context, 'Bạn sửa hôm nay', d?['myEditsToday'])),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Btn('Thêm sản phẩm', icon: LucideIcons.plus, onTap: () async {
                final saved = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductFormScreen()));
                if (saved != null) {
                  _load();
                  if (context.mounted) toast(context, 'Đã thêm ${saved['name']}');
                }
              }),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Hoạt động gần đây', style: T.titleM),
                GestureDetector(onTap: () => TabSwitcher.of(context)?.go(1), child: Text('Xem sản phẩm', style: T.label.copyWith(color: c.muted))),
              ]),
              const SizedBox(height: 8),
              if (d == null)
                const ListSkeleton(rows: 3)
              else if ((d['recentActivities'] as List).isEmpty)
                AppCard(child: Text('Chưa có hoạt động. Thêm hoặc sửa một sản phẩm để bắt đầu.', style: T.bodyM.copyWith(color: c.muted)))
              else
                AppCard.flush(
                  child: Column(
                    children: withDividers([
                      for (final a in d['recentActivities'])
                        ListRow(
                          leading: Bubble(switch (a['action']) { 'create' => LucideIcons.plus, 'delete' => LucideIcons.trash2, _ => LucideIcons.pencil }),
                          title: a['title'],
                          subtitle: a['detail'] ?? relative(a['createdAt']),
                          trailing: Text(hm(a['createdAt']), style: T.bodyS.copyWith(color: c.faint, fontFeatures: T.num)),
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

  Widget _mini(BuildContext context, String k, dynamic v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: T.label.copyWith(color: context.c.muted)),
        const SizedBox(height: 2),
        v == null ? const Skeleton(width: 30, height: 16) : Text('$v', style: T.titleM.copyWith(fontFeatures: T.num)),
      ]);
}
