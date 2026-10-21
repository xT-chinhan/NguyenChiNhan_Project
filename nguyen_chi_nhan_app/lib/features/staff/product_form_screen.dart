import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// Định dạng số khi gõ: 1200000 -> 1.200.000
class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final t = vnd(int.parse(digits)).replaceAll('đ', '');
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

/// 32 Thêm / sửa sản phẩm (Nhân viên + Admin)
class ProductFormScreen extends StatefulWidget {
  final Map? product;
  const ProductFormScreen({super.key, this.product});
  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final _name = TextEditingController(text: widget.product?['name']);
  late final _price = TextEditingController(text: widget.product == null ? '' : vnd(widget.product!['price']).replaceAll('đ', ''));
  late final _desc = TextEditingController(text: widget.product?['description']);
  late int? _catId = widget.product?['categoryId'];
  List _cats = [];
  bool _saving = false;
  String? _error;

  bool get _isAdmin => Api.i.session.value?.role == 'Admin';
  int get _priceValue => int.tryParse(_price.text.replaceAll('.', '')) ?? 0;

  @override
  void initState() {
    super.initState();
    Api.i.get('/categories').then((r) {
      if (mounted) setState(() => _cats = r);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final picked = await showSheet<int>(
      context,
      (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Chọn danh mục', style: T.titleL),
        const SizedBox(height: 12),
        AppCard.flush(
          child: Column(
            children: withDividers([
              for (final x in _cats)
                SetRow(
                  icon: iconOf(x['icon']),
                  label: x['name'],
                  chevron: false,
                  trailing: RadioDot(x['id'] == _catId),
                  onTap: () => Navigator.pop(ctx, x['id'] as int),
                ),
              SetRow(icon: LucideIcons.circleDashed, label: 'Không thuộc danh mục', chevron: false, trailing: RadioDot(_catId == null), onTap: () => Navigator.pop(ctx, -1)),
            ], indent: 60),
          ),
        ),
      ]),
    );
    if (picked != null) setState(() => _catId = picked == -1 ? null : picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {'name': _name.text.trim(), 'price': _priceValue, 'description': _desc.text.trim(), 'categoryId': _catId};
    try {
      final r = widget.product == null ? await Api.i.post('/products', body) : await Api.i.put('/products/${widget.product!['id']}', body);
      if (mounted) Navigator.pop(context, r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    String catName = 'Chưa chọn';
    for (final x in _cats) {
      if (x['id'] == _catId) catName = x['name'];
    }
    if (_cats.isEmpty && widget.product?['categoryName'] != null) catName = widget.product!['categoryName'];
    return Scaffold(
      appBar: TopBar(close: true, title: widget.product == null ? 'Thêm sản phẩm' : 'Sửa sản phẩm'),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(kPad, 8, kPad, 16), children: [
              const FieldLabel('Tên sản phẩm'),
              AppInput(_name, hint: 'vd: Tai nghe Bluetooth', caps: TextCapitalization.sentences, action: TextInputAction.next),
              const SizedBox(height: 16),
              const FieldLabel('Giá bán'),
              AppInput(_price, keyboard: TextInputType.number, formatters: [_ThousandsFormatter()], suffixText: 'đ', hint: '0', onChanged: (_) => setState(() {})),
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 2),
                child: Text(_priceValue > 0 ? moneyWords(_priceValue) : ' ', style: T.bodyS.copyWith(color: c.muted)),
              ),
              const SizedBox(height: 12),
              AppCard.flush(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _pickCategory,
                  child: SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        Icon(LucideIcons.shapes, size: 20, color: c.muted),
                        const SizedBox(width: 12),
                        Text('Danh mục', style: TextStyle(fontSize: 15, color: c.muted)),
                        const Spacer(),
                        Text(catName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 4),
                        Icon(LucideIcons.chevronRight, size: 18, color: c.faint),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const FieldLabel('Mô tả'),
              AppInput(_desc, maxLines: 4, hint: 'Điểm nổi bật của sản phẩm', caps: TextCapitalization.sentences),
              if (_error != null) ErrorLine(_error!),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(kPad, 0, kPad, 16),
            child: Column(children: [
              if (!_isAdmin) ...[const Note('Nhân viên được thêm và sửa. Chỉ Quản trị viên xóa được sản phẩm.'), const SizedBox(height: 12)],
              Btn(widget.product == null ? 'Thêm sản phẩm' : 'Lưu thay đổi', loading: _saving, onTap: _save),
            ]),
          ),
        ]),
      ),
    );
  }
}
