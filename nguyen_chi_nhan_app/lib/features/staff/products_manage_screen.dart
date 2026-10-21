import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'product_form_screen.dart';

/// 31 / 33 / 44 Sản phẩm: Nhân viên thêm + sửa; Admin thêm vuốt trái để xóa
class ProductsManageScreen extends StatefulWidget {
  const ProductsManageScreen({super.key});
  @override
  State<ProductsManageScreen> createState() => _ProductsManageScreenState();
}

class _ProductsManageScreenState extends State<ProductsManageScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List _cats = [];
  List? _items;
  Object? _error;
  int? _cat;
  int? _justSaved;

  bool get _isAdmin => Api.i.session.value?.role == 'Admin';

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
      final q = Uri(queryParameters: {
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
        if (_cat != null) 'categoryId': '$_cat',
        'sort': 'newest',
      }).query;
      final r = await Future.wait([Api.i.get('/categories'), Api.i.get('/products?$q')]);
      if (mounted) {
        setState(() {
          _cats = r[0] as List;
          _items = r[1] as List;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _open([Map? p]) async {
    final saved = await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductFormScreen(product: p)));
    if (saved == null || !mounted) return;
    setState(() => _justSaved = saved['id']);
    toast(context, 'Đã lưu ${saved['name']}');
    await _load();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _justSaved = null);
    });
  }

  Future<bool> _delete(Map p) async {
    final ok = await confirmDanger(context, title: 'Xóa ${p['name']}?', text: 'Sản phẩm sẽ bị xóa khỏi cửa hàng, không thể khôi phục.', action: 'Xóa sản phẩm');
    if (!ok || !mounted) return false;
    final r = await guard(context, () => Api.i.delete('/products/${p['id']}'));
    if (r == null || !mounted) return false;
    toast(context, r['message']);
    setState(() => _items!.removeWhere((x) => x['id'] == p['id']));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final total = _cats.fold<int>(0, (s, x) => s + (x['productCount'] as int));
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
                PageHeader('Sản phẩm', trailing: CircleBtn(LucideIcons.plus, onTap: () => _open())),
                const SizedBox(height: 8),
                SearchBox(_search, hint: 'Tìm theo tên…', onChanged: (_) {
                  setState(() {});
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), _load);
                }),
                const SizedBox(height: 12),
              ]),
            ),
            ChipBar<int?>(
              items: [(null, 'Tất cả${_cats.isEmpty ? '' : ' $total'}'), for (final x in _cats) (x['id'] as int, '${x['name']} ${x['productCount']}')],
              selected: _cat,
              onSelect: (id) {
                setState(() => _cat = id);
                _load();
              },
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPad),
              child: _error != null
                  ? LoadError(_error!, onRetry: _load)
                  : _items == null
                      ? const ListSkeleton(rows: 5)
                      : _items!.isEmpty
                          ? EmptyState(icon: LucideIcons.package, title: 'Chưa có sản phẩm', top: 32, action: Btn('Thêm sản phẩm', icon: LucideIcons.plus, expand: false, onTap: () => _open()))
                          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              if (_isAdmin) Padding(padding: const EdgeInsets.only(bottom: 8, left: 2), child: Text('Chạm để sửa, vuốt trái để xóa.', style: T.bodyS.copyWith(color: c.muted))),
                              AppCard.flush(
                                child: Column(
                                  children: withDividers([
                                    for (final p in _items!) _row(p),
                                  ]),
                                ),
                              ),
                            ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(Map p) {
    final c = context.c;
    final row = ListRow(
      background: p['id'] == _justSaved ? c.successContainer : null,
      leading: Bubble(iconOf(p['icon'])),
      title: p['name'],
      subtitle: '${p['categoryName'] ?? 'Chưa có danh mục'}${p['id'] == _justSaved ? ' · vừa sửa' : ''}',
      trailing: Text(vnd(p['price']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, fontFeatures: T.num)),
      onTap: () => _open(p),
    );
    if (!_isAdmin) return row;
    return Dismissible(
      key: ValueKey(p['id']),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _delete(p),
      background: Container(
        color: c.dangerContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.trash2, size: 18, color: c.danger),
          const SizedBox(height: 3),
          Text('Xóa', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.danger)),
        ]),
      ),
      child: row,
    );
  }
}
