import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/api.dart';
import '../core/theme.dart';

const kPad = 20.0;

// ---------------- Khung màn hình ----------------

/// Thanh trên kiểu mockup: "‹ Quay lại" bên trái, tiêu đề giữa, hành động bên phải
class TopBar extends StatelessWidget implements PreferredSizeWidget {
  final String? back;
  final String? title;
  final List<Widget> actions;
  final bool close;
  const TopBar({super.key, this.back, this.title, this.actions = const [], this.close = false});

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 52,
        child: Stack(alignment: Alignment.center, children: [
          if (title != null) Text(title!, style: T.body.copyWith(fontWeight: FontWeight.w600, fontSize: 16)),
          Align(
            alignment: Alignment.centerLeft,
            child: Press(
              onTap: () => Navigator.maybePop(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: close
                    ? Icon(LucideIcons.x, size: 22, color: c.ink)
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(LucideIcons.chevronLeft, size: 22, color: c.ink),
                        if (back != null) Text(back!, style: T.body.copyWith(fontSize: 16)),
                      ]),
              ),
            ),
          ),
          Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.only(right: 12), child: Row(mainAxisSize: MainAxisSize.min, children: actions))),
        ]),
      ),
    );
  }
}

/// Tiêu đề lớn đầu tab (Sản phẩm, Danh mục…) + nút tròn bên phải
class PageHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const PageHeader(this.title, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Row(children: [Expanded(child: Text(title, style: T.headline, overflow: TextOverflow.ellipsis)), ?trailing]),
      );
}

/// Logo "CN" vuông đen
class Logo extends StatelessWidget {
  final double size;
  const Logo({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: context.c.primary, borderRadius: BorderRadius.circular(size * .3)),
        child: Text('CN', style: TextStyle(color: context.c.onPrimary, fontWeight: FontWeight.w700, fontSize: size * .45, letterSpacing: -0.5)),
      );
}

// ---------------- Nhấn: scale 0.97 trong 160ms ----------------
class Press extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const Press({super.key, required this.child, this.onTap, this.onLongPress});
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: AnimatedScale(scale: _down ? .97 : 1, duration: const Duration(milliseconds: 160), curve: const Cubic(.23, 1, .32, 1), child: widget.child),
      );
}

// ---------------- Nút ----------------
enum BtnKind { primary, secondary, dangerSoft, text, dangerText }

class Btn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool loading;
  final bool expand;
  final double height;
  const Btn(this.label, {super.key, this.icon, this.onTap, this.kind = BtnKind.primary, this.loading = false, this.expand = true, this.height = 52});
  const Btn.secondary(this.label, {super.key, this.icon, this.onTap, this.loading = false, this.expand = true, this.height = 52}) : kind = BtnKind.secondary;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final disabled = onTap == null || loading;
    Color bg, fg;
    Border? border;
    switch (kind) {
      case BtnKind.primary:
        bg = disabled && !loading ? c.containerHigh : c.primary;
        fg = disabled && !loading ? c.faint : c.onPrimary;
      case BtnKind.secondary:
        bg = c.surface;
        fg = disabled ? c.faint : c.ink;
        border = Border.all(color: c.outline);
      case BtnKind.dangerSoft:
        bg = c.dangerContainer;
        fg = c.danger;
      case BtnKind.text:
        bg = Colors.transparent;
        fg = c.ink;
      case BtnKind.dangerText:
        bg = Colors.transparent;
        fg = c.danger;
    }
    final child = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: border),
      child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
        if (loading)
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
        else ...[
          if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600))),
        ],
      ]),
    );
    return Press(onTap: disabled ? null : onTap, child: child);
  }
}

/// Nút tròn 40 (thêm, chuông…)
class CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final bool dot;
  const CircleBtn(this.icon, {super.key, this.onTap, this.filled = true, this.dot = false});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Press(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: filled ? BoxDecoration(color: c.surface, shape: BoxShape.circle, border: Border.all(color: c.outline)) : null,
        child: Stack(alignment: Alignment.center, children: [
          Icon(icon, size: 20, color: c.ink),
          if (dot) Positioned(top: 8, right: 9, child: Container(width: 8, height: 8, decoration: BoxDecoration(color: c.dangerBar, shape: BoxShape.circle))),
        ]),
      ),
    );
  }
}

// ---------------- Card, bubble, nhãn ----------------
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color});
  const AppCard.flush({super.key, required this.child, this.color}) : padding = EdgeInsets.zero;
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.outline),
        boxShadow: const [BoxShadow(color: Color(0x08111111), blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: Color(0x09111111), blurRadius: 20, offset: Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

enum Tone { normal, ink, warn, danger, ok }

class Bubble extends StatelessWidget {
  final IconData icon;
  final double size;
  final Tone tone;
  const Bubble(this.icon, {super.key, this.size = 40, this.tone = Tone.normal});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg) = switch (tone) {
      Tone.normal => (c.container, c.ink.withValues(alpha: .85)),
      Tone.ink => (c.primary, c.onPrimary),
      Tone.warn => (c.warningContainer, c.warning),
      Tone.danger => (c.dangerContainer, c.danger),
      Tone.ok => (c.successContainer, c.income),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: size * .47, color: fg),
    );
  }
}

class Avatar extends StatelessWidget {
  final String text;
  final double size;
  final Color? color;
  const Avatar(this.text, {super.key, this.size = 48, this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color ?? const Color(0xFF2B2A27), shape: BoxShape.circle),
        child: Text(text, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: size * .35)),
      );
}

/// Badge viên thuốc (Đang đo, Chính xác ±8 m, Lạ…)
class Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Tone tone;
  final double height;
  const Pill(this.text, {super.key, this.icon, this.tone = Tone.normal, this.height = 26});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg) = switch (tone) {
      Tone.normal => (c.container, c.ink.withValues(alpha: .75)),
      Tone.ink => (c.primary, c.onPrimary),
      Tone.warn => (c.warningContainer, c.warning),
      Tone.danger => (c.dangerContainer, c.danger),
      Tone.ok => (c.successContainer, c.income),
    };
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 5)],
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}

/// Nhãn vai trò: Quản trị (đen), Nhân viên (viền), Khách hàng (xám)
class RoleTag extends StatelessWidget {
  final String role;
  final bool withIcon;
  const RoleTag(this.role, {super.key, this.withIcon = false});
  static String label(String r) => switch (r) { 'Admin' => 'Quản trị', 'Staff' => 'Nhân viên', _ => 'Khách hàng' };
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg, border) = switch (role) {
      'Admin' => (c.primary, c.onPrimary, null),
      'Staff' => (c.surface, c.ink, Border.all(color: c.outline)),
      _ => (c.container, c.ink.withValues(alpha: .75), null),
    };
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: border),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (withIcon) ...[Icon(role == 'Admin' ? LucideIcons.shieldCheck : LucideIcons.badgeCheck, size: 13, color: fg), const SizedBox(width: 4)],
        Text(label(role), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}

/// Ghi chú nền xám có icon
class Note extends StatelessWidget {
  final String text;
  final IconData icon;
  final Widget? trailing;
  const Note(this.text, {super.key, this.icon = LucideIcons.info, this.trailing});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: c.container, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 17, color: c.muted)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.5, color: c.ink.withValues(alpha: .72)))),
        ?trailing,
      ]),
    );
  }
}

class GroupLabel extends StatelessWidget {
  final String text;
  const GroupLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.c.muted)),
      );
}

/// Đường kẻ mảnh trong list, thụt sau icon
class InsetDivider extends StatelessWidget {
  final double indent;
  const InsetDivider({super.key, this.indent = 68});
  @override
  Widget build(BuildContext context) => Container(height: 1, margin: EdgeInsets.only(left: indent, right: 16), color: context.c.outlineVariant);
}

/// Ghép các dòng trong card có đường kẻ
List<Widget> withDividers(List<Widget> rows, {double indent = 68}) {
  final out = <Widget>[];
  for (var i = 0; i < rows.length; i++) {
    if (i > 0) out.add(InsetDivider(indent: indent));
    out.add(rows[i]);
  }
  return out;
}

/// Dòng list: bubble + tiêu đề + phụ đề + phần phải
class ListRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? background;
  const ListRow({super.key, required this.leading, required this.title, this.subtitle, this.trailing, this.onTap, this.background});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        color: background,
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.body),
              if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bodyS.copyWith(color: c.muted)),
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ]),
      ),
    );
  }
}

/// Dòng cài đặt: bubble nhỏ + nhãn + giá trị + chevron/switch
class SetRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  const SetRow({super.key, required this.icon, required this.label, this.sub, this.value, this.trailing, this.onTap, this.chevron = true});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Bubble(icon, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: T.body),
              if (sub != null) Text(sub!, style: T.bodyS.copyWith(color: c.muted)),
            ]),
          ),
          if (value != null) Text(value!, style: TextStyle(fontSize: 14.5, color: c.muted)),
          ?trailing,
          if (chevron && trailing == null) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(LucideIcons.chevronRight, size: 18, color: c.faint)),
        ]),
      ),
    );
  }
}

/// Công tắc kiểu iOS theo mockup
class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const AppSwitch(this.value, {super.key, this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46,
        height: 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: value ? c.primary : const Color(0xFFDAD8D2), borderRadius: BorderRadius.circular(14)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: const Cubic(.23, 1, .32, 1),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 24, height: 24, decoration: BoxDecoration(color: value ? c.onPrimary : Colors.white, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 3, offset: Offset(0, 1))])),
        ),
      ),
    );
  }
}

/// Ô radio theo mockup
class RadioDot extends StatelessWidget {
  final bool on;
  const RadioDot(this.on, {super.key});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 22,
        height: 22,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? context.c.primary : const Color(0xFFCFCDC7), width: on ? 6.5 : 1.5)),
      );
}

// ---------------- Ô nhập ----------------
class FieldLabel extends StatelessWidget {
  final String text;
  final String? hint;
  const FieldLabel(this.text, {super.key, this.hint});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: text),
          if (hint != null) TextSpan(text: ' $hint', style: TextStyle(color: context.c.faint, fontWeight: FontWeight.w400)),
        ]), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.c.muted)),
      );
}

class AppInput extends StatefulWidget {
  final TextEditingController controller;
  final String? hint;
  final IconData? icon;
  final bool password;
  final TextInputType? keyboard;
  final String? error;
  final int maxLines;
  final String? suffixText;
  final TextInputAction? action;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextCapitalization caps;
  final List<TextInputFormatter>? formatters;
  const AppInput(this.controller,
      {super.key,
      this.formatters,
      this.hint,
      this.icon,
      this.password = false,
      this.keyboard,
      this.error,
      this.maxLines = 1,
      this.suffixText,
      this.action,
      this.onChanged,
      this.onSubmitted,
      this.autofocus = false,
      this.caps = TextCapitalization.none});
  @override
  State<AppInput> createState() => _AppInputState();
}

class _AppInputState extends State<AppInput> {
  final _focus = FocusNode();
  bool _obscure = true;
  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final focused = _focus.hasFocus;
    final err = widget.error != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: BoxConstraints(minHeight: widget.maxLines > 1 ? 84 : 52),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: widget.maxLines > 1 ? 6 : 0),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: err ? c.dangerBar : (focused ? c.ink : c.outline), width: focused || err ? 1.2 : 1),
          boxShadow: focused || err ? [BoxShadow(color: (err ? c.dangerBar : c.ink).withValues(alpha: .07), spreadRadius: 3)] : null,
        ),
        child: Row(crossAxisAlignment: widget.maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
          if (widget.icon != null) ...[Icon(widget.icon, size: 20, color: c.muted), const SizedBox(width: 10)],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              obscureText: widget.password && _obscure,
              inputFormatters: widget.formatters,
              keyboardType: widget.keyboard,
              textInputAction: widget.action,
              textCapitalization: widget.caps,
              maxLines: widget.password ? 1 : widget.maxLines,
              minLines: 1,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: TextStyle(fontSize: 15.5, color: c.ink, letterSpacing: widget.password && _obscure ? 2 : 0),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: TextStyle(color: c.faint, letterSpacing: 0),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (widget.suffixText != null) Text(widget.suffixText!, style: TextStyle(color: c.muted, fontSize: 15.5)),
          if (widget.password)
            GestureDetector(
              onTap: () => setState(() => _obscure = !_obscure),
              child: Icon(_obscure ? LucideIcons.eyeOff : LucideIcons.eye, size: 20, color: c.muted),
            ),
        ]),
      ),
      if (err) ErrorLine(widget.error!),
    ]);
  }
}

class ErrorLine extends StatelessWidget {
  final String text;
  const ErrorLine(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(LucideIcons.circleAlert, size: 15, color: context.c.danger)),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.45, color: context.c.danger))),
        ]),
      );
}

class SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  const SearchBox(this.controller, {super.key, required this.hint, this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: controller.text.isEmpty ? c.outline : c.ink)),
      child: Row(children: [
        Icon(LucideIcons.search, size: 18, color: controller.text.isEmpty ? c.faint : c.ink),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: TextStyle(fontSize: 14.5, color: c.ink),
            decoration: InputDecoration(isDense: true, border: InputBorder.none, hintText: hint, hintStyle: TextStyle(color: c.faint)),
          ),
        ),
        if (controller.text.isNotEmpty)
          GestureDetector(
            onTap: () {
              controller.clear();
              onChanged?.call('');
            },
            child: Icon(LucideIcons.x, size: 18, color: c.muted),
          ),
      ]),
    );
  }
}

/// Dải chip lọc cuộn ngang (tràn mép phải như mockup)
class ChipBar<K> extends StatelessWidget {
  final List<(K, String)> items;
  final K selected;
  final ValueChanged<K> onSelect;
  const ChipBar({super.key, required this.items, required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kPad),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final on = items[i].$1 == selected;
          return Press(
            onTap: () => onSelect(items[i].$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: on ? c.primary : c.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: on ? c.primary : c.outline)),
              child: Text(items[i].$2, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: on ? c.onPrimary : c.ink)),
            ),
          );
        },
      ),
    );
  }
}

/// Segmented control (Anh → Việt / Việt → Anh)
class Segmented extends StatelessWidget {
  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;
  const Segmented({super.key, required this.items, required this.index, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.container, borderRadius: BorderRadius.circular(999)),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                decoration: i == index
                    ? BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(999), boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1))])
                    : null,
                child: Text(items[i], style: TextStyle(fontSize: 14, fontWeight: i == index ? FontWeight.w600 : FontWeight.w500, color: i == index ? c.ink : c.muted)),
              ),
            ),
          ),
      ]),
    );
  }
}

// ---------------- Đang tải / rỗng / lỗi ----------------
class Skeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const Skeleton({super.key, this.width, this.height = 12, this.radius = 8});
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _a,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(c.containerHigh, c.container, reduce ? 0 : _a.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Skeleton một danh sách hàng (bubble + 2 dòng + số)
class ListSkeleton extends StatelessWidget {
  final int rows;
  const ListSkeleton({super.key, this.rows = 3});
  @override
  Widget build(BuildContext context) => AppCard.flush(
        child: Column(children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 64,
                child: Row(children: [
                  const Skeleton(width: 40, height: 40, radius: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      FractionallySizedBox(widthFactor: [.62, .54, .66, .5][i % 4], child: const Skeleton(height: 12)),
                      const SizedBox(height: 8),
                      FractionallySizedBox(widthFactor: [.3, .26, .34, .28][i % 4], child: const Skeleton(height: 10)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  const Skeleton(width: 72, height: 12),
                ]),
              ),
            ),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;
  final double top;
  const EmptyState({super.key, required this.icon, required this.title, this.text, this.action, this.top = 64});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top, left: 24, right: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Bubble(icon, size: 72),
          const SizedBox(height: 20),
          Text(title, textAlign: TextAlign.center, style: T.titleL),
          if (text != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 290), child: Text(text!, textAlign: TextAlign.center, style: T.bodyM.copyWith(color: context.c.muted))),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      );
}

/// Lỗi tải dữ liệu: mất mạng thì dùng màn "Không kết nối được máy chủ"
class LoadError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const LoadError(this.error, {super.key, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    final net = error is ApiException && (error as ApiException).code == 'NETWORK';
    return EmptyState(
      icon: net ? LucideIcons.wifiOff : LucideIcons.circleAlert,
      title: net ? 'Không kết nối được máy chủ' : 'Chưa tải được dữ liệu',
      text: net ? 'Kiểm tra mạng rồi thử lại. Tiện ích Đo tiếng ồn vẫn dùng được khi không có mạng.' : error.toString(),
      top: 96,
      action: Btn('Thử lại', icon: LucideIcons.refreshCw, expand: false, onTap: onRetry),
    );
  }
}

// ---------------- Sheet, toast ----------------
Future<R?> showSheet<R>(BuildContext context, Widget Function(BuildContext) builder) {
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: const Color(0x52111111),
    backgroundColor: context.c.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 36, height: 5, decoration: BoxDecoration(color: ctx.c.containerHigh, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 14),
            builder(ctx),
          ]),
        ),
      ),
    ),
  );
}

/// Sheet xác nhận nguy hiểm (xóa) theo mockup 43
Future<bool> confirmDanger(BuildContext context, {required String title, required String text, required String action, IconData icon = LucideIcons.trash2}) async {
  final ok = await showSheet<bool>(
    context,
    (ctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Bubble(icon, size: 56, tone: Tone.danger)),
      const SizedBox(height: 16),
      Text(title, textAlign: TextAlign.center, style: T.titleL),
      const SizedBox(height: 8),
      Text(text, textAlign: TextAlign.center, style: T.bodyM.copyWith(color: ctx.c.muted)),
      const SizedBox(height: 24),
      Btn(action, kind: BtnKind.dangerSoft, onTap: () => Navigator.pop(ctx, true)),
      const SizedBox(height: 8),
      Btn('Hủy', kind: BtnKind.text, onTap: () => Navigator.pop(ctx, false)),
    ]),
  );
  return ok == true;
}

void toast(BuildContext context, String text, {bool error = false}) {
  final c = context.c;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      elevation: 0,
      backgroundColor: c.surface,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.outline)),
      content: Row(children: [
        Icon(error ? LucideIcons.circleAlert : LucideIcons.check, size: 18, color: error ? c.danger : c.ink),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(color: c.ink, fontWeight: FontWeight.w500, fontSize: 14))),
      ]),
    ));
}

/// Chạy một lời gọi API, lỗi thì hiện toast
Future<R?> guard<R>(BuildContext context, Future<R> Function() fn) async {
  try {
    return await fn();
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message, error: true);
  }
  return null;
}
