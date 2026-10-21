import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// 41–43 Danh mục (Admin): thêm, sửa (chạm), xóa (vuốt trái + xác nhận)
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Api.i.get('/categories');
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit([Map? cat]) async {
    final saved = await showSheet<Map>(context, (ctx) => _CategoryForm(cat: cat));
    if (saved == null || !mounted) return;
    toast(context, cat == null ? 'Đã thêm danh mục ${saved['name']}' : 'Đã lưu ${saved['name']}');
    _load();
  }

  Future<bool> _delete(Map cat) async {
    final n = cat['productCount'] as int;
    final ok = await confirmDanger(
      context,
      title: 'Xóa danh mục ${cat['name']}?',
      text: n > 0 ? '$n sản phẩm sẽ không còn thuộc danh mục nào. Sản phẩm không bị xóa.' : 'Danh mục chưa có sản phẩm nào.',
      action: 'Xóa danh mục',
    );
    if (!ok || !mounted) return false;
    final r = await guard(context, () => Api.i.delete('/categories/${cat['id']}'));
    if (r == null || !mounted) return false;
    toast(context, r['message']);
    setState(() => _items!.removeWhere((x) => x['id'] == cat['id']));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.ink,
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 24), children: [
            PageHeader('Danh mục', trailing: CircleBtn(LucideIcons.plus, onTap: () => _edit())),
            Text('Chạm để sửa, vuốt trái để xóa.', style: T.bodyS.copyWith(color: c.muted)),
            const SizedBox(height: 12),
            if (_error != null)
              LoadError(_error!, onRetry: _load)
            else if (_items == null)
              const ListSkeleton(rows: 3)
            else if (_items!.isEmpty)
              EmptyState(icon: LucideIcons.shapes, title: 'Chưa có danh mục', top: 32, action: Btn('Thêm danh mục', icon: LucideIcons.plus, expand: false, onTap: () => _edit()))
            else
              AppCard.flush(
                child: Column(
                  children: withDividers([
                    for (final x in _items!)
                      Dismissible(
                        key: ValueKey(x['id']),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _delete(x),
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
                        child: ListRow(
                          leading: Bubble(iconOf(x['icon'])),
                          title: x['name'],
                          subtitle: (x['description'] ?? '').toString().isEmpty ? 'Chưa có mô tả' : x['description'],
                          trailing: Text('${x['productCount']} SP', style: T.bodyS.copyWith(color: c.muted)),
                          onTap: () => _edit(x),
                        ),
                      ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _CategoryForm extends StatefulWidget {
  final Map? cat;
  const _CategoryForm({this.cat});
  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  late final _name = TextEditingController(text: widget.cat?['name']);
  late final _desc = TextEditingController(text: widget.cat?['description']);
  late String _icon = widget.cat?['icon'] ?? 'shapes';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {'name': _name.text.trim(), 'description': _desc.text.trim(), 'icon': _icon};
    try {
      final r = widget.cat == null ? await Api.i.post('/categories', body) : await Api.i.put('/categories/${widget.cat!['id']}', body);
      if (mounted) Navigator.pop(context, r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.cat == null ? 'Thêm danh mục' : 'Sửa danh mục', style: T.titleL),
      const SizedBox(height: 16),
      const FieldLabel('Tên danh mục'),
      AppInput(_name, autofocus: widget.cat == null, hint: 'vd: Sách', caps: TextCapitalization.sentences),
      const SizedBox(height: 16),
      const FieldLabel('Mô tả', hint: '(không bắt buộc)'),
      AppInput(_desc, hint: 'Ví dụ: Sách giáo trình, truyện', caps: TextCapitalization.sentences),
      const SizedBox(height: 16),
      const FieldLabel('Biểu tượng'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final ic in categoryIcons)
          GestureDetector(onTap: () => setState(() => _icon = ic), child: Bubble(iconOf(ic), tone: ic == _icon ? Tone.ink : Tone.normal)),
      ]),
      if (_error != null) ErrorLine(_error!),
      const SizedBox(height: 24),
      Btn(widget.cat == null ? 'Thêm danh mục' : 'Lưu thay đổi', loading: _saving, onTap: _save),
    ]);
  }
}
