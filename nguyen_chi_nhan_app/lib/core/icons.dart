import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Tên icon (API trả về, cùng tên với Lucide trên mockup) -> IconData
const _map = <String, IconData>{
  'laptop': LucideIcons.laptop,
  'keyboard': LucideIcons.keyboard,
  'mouse': LucideIcons.mouse,
  'shirt': LucideIcons.shirt,
  'cooking-pot': LucideIcons.cookingPot,
  'air-vent': LucideIcons.airVent,
  'book': LucideIcons.book,
  'shapes': LucideIcons.shapes,
  'package': LucideIcons.package,
  'smartphone': LucideIcons.smartphone,
  'tag': LucideIcons.tag,
  'shopping-bag': LucideIcons.shoppingBag,
};

IconData iconOf(String? name) => _map[name] ?? LucideIcons.package;

/// Icon chọn được khi thêm/sửa danh mục
const categoryIcons = ['laptop', 'shirt', 'cooking-pot', 'book', 'smartphone', 'shopping-bag', 'tag', 'shapes'];
