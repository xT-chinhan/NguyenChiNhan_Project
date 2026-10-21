import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../account/login_history_screen.dart';

/// 10 Cửa hàng (Khách hàng): tìm, lọc danh mục, sắp xếp giá — API xử lý
class ShopScreen extends StatefulWidget {
  final bool standalone; // Admin "Xem cửa hàng như khách"
  const ShopScreen({super.key, this.standalone = false});
  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List _cats = [];
  List? _products;
  Object? _error;
  int? _cat;
  bool _asc = true;

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
        'sort': _asc ? 'price_asc' : 'price_desc',
      }).query;
      final r = await Future.wait([Api.i.get('/categories'), Api.i.get('/products?$q')]);
      if (mounted) {
        setState(() {
          _cats = r[0] as List;
          _products = r[1] as List;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _onSearch(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = Api.i.session.value;
    final body = RefreshIndicator(
      color: c.ink,
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 48,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                widget.standalone
                    ? GestureDetector(onTap: () => Navigator.pop(context), child: Row(children: [Icon(LucideIcons.chevronLeft, color: c.ink), const Text('Quản trị', style: T.body)]))
                    : const Logo(),
                CircleBtn(LucideIcons.bell, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginHistoryScreen()))),
              ]),
            ),
            const SizedBox(height: 8),
            Text('Chào ${s?.firstName ?? ''}', style: T.headline),
            const SizedBox(height: 16),
            SearchBox(_search, hint: 'Tìm sản phẩm…', onChanged: _onSearch),
            const SizedBox(height: 12),
          ]),
        ),
        if (_error == null && _products == null)
          const _ShopSkeleton()
        else if (_error != null)
          LoadError(_error!, onRetry: _load)
        else ...[
          ChipBar<int?>(
            items: [(null, 'Tất cả'), for (final x in _cats) (x['id'] as int, x['name'] as String)],
            selected: _cat,
            onSelect: (id) {
              setState(() => _cat = id);
              _load();
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kPad, 20, kPad, 0),
            child: _products!.isEmpty
                ? EmptyState(
                    icon: LucideIcons.search,
                    title: _search.text.trim().isEmpty ? 'Chưa có sản phẩm' : 'Không có “${_search.text.trim()}”',
                    text: 'Thử từ khóa ngắn hơn hoặc xem tất cả danh mục.',
                    top: 40,
                    action: Btn.secondary('Xem tất cả sản phẩm', expand: false, onTap: () {
                      _search.clear();
                      setState(() => _cat = null);
                      _load();
                    }),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('${_products!.length} sản phẩm', style: T.titleM),
                      GestureDetector(
                        onTap: () {
                          setState(() => _asc = !_asc);
                          _load();
                        },
                        child: Text(_asc ? 'Giá thấp → cao' : 'Giá cao → thấp', style: T.label.copyWith(color: c.muted)),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    AppCard.flush(
                      child: Column(
                        children: withDividers([
                          for (final p in _products!)
                            ListRow(
                              leading: Bubble(iconOf(p['icon'])),
                              title: p['name'],
                              subtitle: p['categoryName'] ?? 'Chưa có danh mục',
                              trailing: Text(vnd(p['price']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, fontFeatures: T.num)),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(id: p['id'], preview: p))),
                            ),
                        ]),
                      ),
                    ),
                  ]),
          ),
        ],
      ]),
    );
    return Scaffold(body: SafeArea(bottom: false, child: body));
  }
}

class _ShopSkeleton extends StatelessWidget {
  const _ShopSkeleton();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: kPad),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Skeleton(width: 72, height: 34, radius: 17),
            SizedBox(width: 8),
            Skeleton(width: 84, height: 34, radius: 17),
            SizedBox(width: 8),
            Skeleton(width: 100, height: 34, radius: 17),
          ]),
          SizedBox(height: 20),
          Skeleton(width: 96, height: 14),
          SizedBox(height: 8),
          ListSkeleton(rows: 4),
        ]),
      );
}

/// 11 Chi tiết sản phẩm
class ProductDetailScreen extends StatefulWidget {
  final int id;
  final Map? preview;
  const ProductDetailScreen({super.key, required this.id, this.preview});
  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Map? _p = widget.preview;

  @override
  void initState() {
    super.initState();
    guard(context, () => Api.i.get('/products/${widget.id}')).then((r) {
      if (r != null && mounted) setState(() => _p = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final p = _p;
    return Scaffold(
      appBar: const TopBar(back: 'Cửa hàng'),
      body: p == null
          ? const Center(child: Skeleton(width: 200, height: 20))
          : ListView(padding: const EdgeInsets.fromLTRB(kPad, 8, kPad, 24), children: [
              Center(child: Bubble(iconOf(p['icon']), size: 72)),
              const SizedBox(height: 16),
              Center(child: Pill(p['categoryName'] ?? 'Chưa có danh mục', icon: LucideIcons.shapes)),
              const SizedBox(height: 12),
              Text(p['name'], textAlign: TextAlign.center, style: T.titleL.copyWith(fontSize: 22)),
              const SizedBox(height: 8),
              Text(vnd(p['price']), textAlign: TextAlign.center, style: T.display),
              const SizedBox(height: 24),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Mô tả', style: T.label.copyWith(color: c.muted)),
                  const SizedBox(height: 8),
                  Text((p['description'] ?? '').toString().isEmpty ? 'Chưa có mô tả.' : p['description'], style: T.bodyM),
                ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(children: [
                  _kv(context, 'Mã', 'SP-${p['id'].toString().padLeft(3, '0')}'),
                  Divider(height: 1, color: c.outlineVariant),
                  _kv(context, 'Danh mục', p['categoryName'] ?? '—'),
                  if (p['updatedAt'] != null) ...[Divider(height: 1, color: c.outlineVariant), _kv(context, 'Cập nhật', relative(p['updatedAt'], withTime: true))],
                ]),
              ),
            ]),
    );
  }
}

Widget _kv(BuildContext context, String k, String v) => SizedBox(
      height: 48,
      child: Row(children: [
        SizedBox(width: 84, child: Text(k, style: TextStyle(fontSize: 14.5, color: context.c.muted))),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
      ]),
    );
