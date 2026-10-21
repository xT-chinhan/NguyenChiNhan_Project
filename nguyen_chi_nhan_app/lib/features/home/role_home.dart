import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../account/account_screen.dart';
import '../admin/admin_home.dart';
import '../admin/categories_screen.dart';
import '../admin/users_screen.dart';
import '../attendance/attendance_screen.dart';
import '../shop/shop_screen.dart';
import '../staff/products_manage_screen.dart';
import '../staff/staff_home.dart';
import '../tools/tools_screen.dart';

typedef TabItem = (IconData icon, String label, Widget page);

/// Yêu cầu 3: phân quyền theo vai trò API trả về
/// Admin -> trang quản trị, Staff -> Dashboard nhân viên, User -> Cửa hàng
class RoleHome extends StatelessWidget {
  const RoleHome({super.key});

  @override
  Widget build(BuildContext context) {
    final role = Api.i.session.value?.role ?? 'User';
    final tabs = switch (role) {
      'Admin' => <TabItem>[
          (LucideIcons.layoutDashboard, 'Tổng quan', const AdminHome()),
          (LucideIcons.shapes, 'Danh mục', const CategoriesScreen()),
          (LucideIcons.package, 'Sản phẩm', const ProductsManageScreen()),
          (LucideIcons.users, 'Người dùng', const UsersScreen()),
          (LucideIcons.circleUser, 'Tài khoản', const AccountScreen()),
        ],
      'Staff' => <TabItem>[
          (LucideIcons.layoutDashboard, 'Tổng quan', const StaffHome()),
          (LucideIcons.package, 'Sản phẩm', const ProductsManageScreen()),
          (LucideIcons.clock, 'Chấm công', const AttendanceScreen()),
          (LucideIcons.layoutGrid, 'Tiện ích', const ToolsScreen()),
          (LucideIcons.circleUser, 'Tài khoản', const AccountScreen()),
        ],
      _ => <TabItem>[
          (LucideIcons.store, 'Cửa hàng', const ShopScreen()),
          (LucideIcons.layoutGrid, 'Tiện ích', const ToolsScreen()),
          (LucideIcons.circleUser, 'Tài khoản', const AccountScreen()),
        ],
    };
    return TabShell(key: ValueKey(role), tabs: tabs);
  }
}

/// Đổi tab từ màn con (vd: Tổng quan -> Sản phẩm)
class TabSwitcher extends InheritedWidget {
  final ValueChanged<int> go;
  const TabSwitcher({super.key, required this.go, required super.child});
  static TabSwitcher? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TabSwitcher>();
  @override
  bool updateShouldNotify(TabSwitcher old) => false;
}

class TabShell extends StatefulWidget {
  final List<TabItem> tabs;
  const TabShell({super.key, required this.tabs});
  @override
  State<TabShell> createState() => _TabShellState();
}

class _TabShellState extends State<TabShell> {
  int _i = 0;
  final _visited = <int>{0};

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TabSwitcher(
      go: (i) => setState(() {
        _i = i;
        _visited.add(i);
      }),
      child: Scaffold(
        body: IndexedStack(
          index: _i,
          children: [for (var k = 0; k < widget.tabs.length; k++) _visited.contains(k) ? widget.tabs[k].$3 : const SizedBox()],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(color: c.surface.withValues(alpha: .96), border: Border(top: BorderSide(color: c.outline))),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 58,
              child: Row(children: [
                for (var k = 0; k < widget.tabs.length; k++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() {
                        _i = k;
                        _visited.add(k);
                      }),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(widget.tabs[k].$1, size: 23, color: k == _i ? c.ink : const Color(0xFF9C9A94)),
                        const SizedBox(height: 3),
                        Text(
                          widget.tabs[k].$2,
                          style: TextStyle(fontSize: 10.5, fontWeight: k == _i ? FontWeight.w600 : FontWeight.w500, color: k == _i ? c.ink : const Color(0xFF9C9A94)),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
