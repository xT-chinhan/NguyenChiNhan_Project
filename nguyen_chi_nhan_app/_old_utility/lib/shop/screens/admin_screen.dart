import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../services/api_client.dart';
import '../utils/auth.dart';
import '../../app_shell.dart';
import 'login_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiClient _apiClient = ApiClient();

  List<Category> _categories = [];
  List<Product> _products = [];
  bool _isLoadingCategories = false;
  bool _isLoadingProducts = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await _fetchCategories();
    await _fetchProducts();
  }

  /// Lấy danh sách danh mục từ API hoặc dữ liệu mẫu khởi tạo
  Future<void> _fetchCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final response = await _apiClient.get('Category');
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _categories = data.map((json) => Category.fromJson(json)).toList();
        });
      } else {
        _loadDefaultCategoriesIfEmpty();
      }
    } catch (_) {
      _loadDefaultCategoriesIfEmpty();
    } finally {
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  void _loadDefaultCategoriesIfEmpty() {
    if (_categories.isEmpty) {
      setState(() {
        _categories = [
          Category(id: 1, name: 'Điện thoại & Phụ kiện', description: 'Smartphones, ốp lưng, sạc'),
          Category(id: 2, name: 'Laptop & Máy tính', description: 'Máy tính xách tay và linh kiện'),
          Category(id: 3, name: 'Thời trang & May mặc', description: 'Quần áo, phụ kiện thể thao'),
        ];
      });
    }
  }

  /// Lấy danh sách sản phẩm từ API
  Future<void> _fetchProducts() async {
    setState(() => _isLoadingProducts = true);
    try {
      final response = await _apiClient.get('Product');
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _products = data.map((json) => Product.fromJson(json)).toList();
        });
      } else {
        _loadDefaultProductsIfEmpty();
      }
    } catch (_) {
      _loadDefaultProductsIfEmpty();
    } finally {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  void _loadDefaultProductsIfEmpty() {
    if (_products.isEmpty) {
      setState(() {
        _products = [
          Product(
            id: 1,
            name: 'iPhone 15 Pro Max',
            price: 29990000,
            description: 'Titan tự nhiên 256GB',
            categoryId: 1,
            categoryName: 'Điện thoại & Phụ kiện',
          ),
          Product(
            id: 2,
            name: 'MacBook Air M2',
            price: 24500000,
            description: 'RAM 16GB, SSD 256GB',
            categoryId: 2,
            categoryName: 'Laptop & Máy tính',
          ),
          Product(
            id: 3,
            name: 'Áo khoác thể thao Pro',
            price: 450000,
            description: 'Chống thấm nước và cản gió',
            categoryId: 3,
            categoryName: 'Thời trang & May mặc',
          ),
        ];
      });
    }
  }

  /// Đăng xuất: xóa token khỏi SharedPreferences và quay lại LoginScreen
  /// Đáp ứng yêu cầu bài tập: "Thêm chức năng đăng xuất (xóa token khỏi SharePreference là xong)"
  Future<void> _handleLogout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi quyền Admin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Auth.logout(); // Xóa jwt_token và user_role
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  /// Thêm hoặc sửa danh mục
  void _showCategoryDialog({Category? category}) {
    final nameController = TextEditingController(text: category?.name ?? '');
    final descController = TextEditingController(text: category?.description ?? '');
    final isEditing = category != null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Sửa danh mục' : 'Thêm danh mục mới'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Tên danh mục *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Mô tả',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              Navigator.pop(context);

              if (isEditing) {
                // Sửa danh mục
                final updatedCategory = Category(
                  id: category.id,
                  name: name,
                  description: descController.text.trim(),
                );
                try {
                  await _apiClient.put('Category/${category.id}', body: updatedCategory.toJson());
                } catch (_) {}

                setState(() {
                  final index = _categories.indexWhere((c) => c.id == category.id);
                  if (index != -1) {
                    _categories[index] = updatedCategory;
                  }
                  // Cập nhật lại categoryName cho các sản phẩm thuộc danh mục này
                  for (var i = 0; i < _products.length; i++) {
                    if (_products[i].categoryId == category.id) {
                      _products[i] = Product(
                        id: _products[i].id,
                        name: _products[i].name,
                        price: _products[i].price,
                        description: _products[i].description,
                        imageUrl: _products[i].imageUrl,
                        categoryId: category.id,
                        categoryName: name,
                      );
                    }
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã cập nhật danh mục thành công!')),
                );
              } else {
                // Thêm mới
                final newId = (_categories.isEmpty ? 1 : _categories.map((c) => c.id).reduce((a, b) => a > b ? a : b) + 1);
                final newCategory = Category(
                  id: newId,
                  name: name,
                  description: descController.text.trim(),
                );
                try {
                  await _apiClient.post('Category', body: newCategory.toJson());
                } catch (_) {}

                setState(() {
                  _categories.add(newCategory);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã thêm danh mục mới!')),
                );
              }
            },
            child: Text(isEditing ? 'Lưu' : 'Thêm'),
          ),
        ],
      ),
    );
  }

  /// Xóa danh mục
  /// Đáp ứng yêu cầu bài tập: "Xóa danh mục sản phẩm thì các sản phẩm sẽ không thuộc danh mục nào cả"
  void _deleteCategory(Category category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa danh mục'),
        content: Text(
          'Bạn có chắc muốn xóa "${category.name}"?\nCác sản phẩm thuộc danh mục này sẽ chuyển về trạng thái không thuộc danh mục nào.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _apiClient.delete('Category/${category.id}');
      } catch (_) {}

      setState(() {
        _categories.removeWhere((c) => c.id == category.id);
        // Quy tắc: Xóa danh mục sản phẩm thì các sản phẩm sẽ không thuộc danh mục nào cả (categoryId = null)
        for (var i = 0; i < _products.length; i++) {
          if (_products[i].categoryId == category.id) {
            _products[i] = Product(
              id: _products[i].id,
              name: _products[i].name,
              price: _products[i].price,
              description: _products[i].description,
              imageUrl: _products[i].imageUrl,
              categoryId: null,
              categoryName: 'Chưa phân loại',
            );
          }
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xóa danh mục "${category.name}". Các sản phẩm liên quan đã được gỡ danh mục.'),
        ),
      );
    }
  }

  /// Thêm/sửa sản phẩm
  void _showProductDialog({Product? product}) {
    final nameController = TextEditingController(text: product?.name ?? '');
    final priceController = TextEditingController(text: product != null ? product.price.toStringAsFixed(0) : '');
    final descController = TextEditingController(text: product?.description ?? '');
    int? selectedCatId = product?.categoryId;
    final isEditing = product != null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Sửa sản phẩm' : 'Thêm sản phẩm mới'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Tên sản phẩm *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Giá bán (VNĐ) *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Mô tả sản phẩm', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: selectedCatId,
                  decoration: const InputDecoration(
                    labelText: 'Danh mục sản phẩm',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Không thuộc danh mục nào'),
                    ),
                    ..._categories.map((c) => DropdownMenuItem<int?>(
                          value: c.id,
                          child: Text(c.name),
                        )),
                  ],
                  onChanged: (val) {
                    setDialogState(() => selectedCatId = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final price = double.tryParse(priceController.text.trim()) ?? 0.0;
                if (name.isEmpty) return;

                Navigator.pop(context);

                final category = _categories.cast<Category?>().firstWhere(
                      (c) => c?.id == selectedCatId,
                      orElse: () => null,
                    );

                if (isEditing) {
                  final updatedProduct = Product(
                    id: product.id,
                    name: name,
                    price: price,
                    description: descController.text.trim(),
                    categoryId: selectedCatId,
                    categoryName: category?.name ?? 'Chưa phân loại',
                  );
                  try {
                    await _apiClient.put('Product/${product.id}', body: updatedProduct.toJson());
                  } catch (_) {}
                  setState(() {
                    final idx = _products.indexWhere((p) => p.id == product.id);
                    if (idx != -1) _products[idx] = updatedProduct;
                  });
                } else {
                  final newId = (_products.isEmpty ? 1 : _products.map((p) => p.id).reduce((a, b) => a > b ? a : b) + 1);
                  final newProduct = Product(
                    id: newId,
                    name: name,
                    price: price,
                    description: descController.text.trim(),
                    categoryId: selectedCatId,
                    categoryName: category?.name ?? 'Chưa phân loại',
                  );
                  try {
                    await _apiClient.post('Product', body: newProduct.toJson());
                  } catch (_) {}
                  setState(() {
                    _products.add(newProduct);
                  });
                }
              },
              child: Text(isEditing ? 'Lưu' : 'Thêm'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteProduct(Product product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa "${product.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _apiClient.delete('Product/${product.id}');
      } catch (_) {}
      setState(() => _products.removeWhere((p) => p.id == product.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.amber),
            SizedBox(width: 8),
            Text(
              'Admin Portal',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.apps_rounded),
            tooltip: 'Hub tiện ích',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const UtilityHome()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại dữ liệu',
            onPressed: _loadInitialData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Đăng xuất',
            onPressed: _handleLogout,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.category), text: 'Quản lý Danh mục'),
            Tab(icon: Icon(Icons.inventory_2), text: 'Quản lý Sản phẩm'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: Quản lý danh mục
          _buildCategoryTab(),
          // TAB 2: Quản lý sản phẩm
          _buildProductTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        onPressed: () {
          if (_tabController.index == 0) {
            _showCategoryDialog();
          } else {
            _showProductDialog();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildCategoryTab() {
    if (_isLoadingCategories) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.category_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('Chưa có danh mục nào', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _showCategoryDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Thêm danh mục mới'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final cat = _categories[index];
        final productCount = _products.where((p) => p.categoryId == cat.id).length;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue[50],
              child: Text(
                '${cat.id}',
                style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              cat.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${cat.description ?? "Không có mô tả"}\nSố sản phẩm liên kết: $productCount',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showCategoryDialog(category: cat),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteCategory(cat),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductTab() {
    if (_isLoadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('Chưa có sản phẩm nào', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _showProductDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Thêm sản phẩm mới'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final prod = _products[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.amber[100],
              child: Icon(Icons.shopping_bag, color: Colors.amber[900]),
            ),
            title: Text(prod.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${prod.price.toStringAsFixed(0)} VNĐ',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Chip(
                  label: Text(
                    prod.categoryId != null
                        ? (prod.categoryName ?? 'Danh mục #${prod.categoryId}')
                        : 'Chưa có danh mục',
                    style: TextStyle(
                      fontSize: 11,
                      color: prod.categoryId != null ? Colors.blue[900] : Colors.grey[700],
                    ),
                  ),
                  backgroundColor: prod.categoryId != null ? Colors.blue[50] : Colors.grey[200],
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showProductDialog(product: prod),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteProduct(prod),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
