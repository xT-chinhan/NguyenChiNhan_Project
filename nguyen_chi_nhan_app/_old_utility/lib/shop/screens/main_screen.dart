import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../services/api_client.dart';
import '../utils/auth.dart';
import 'login_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final ApiClient _apiClient = ApiClient();

  List<Category> _categories = [];
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  int? _selectedCategoryId; // null = Tất cả

  bool _isLoading = false;
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _fetchData();
  }

  Future<void> _loadUserRole() async {
    final role = await Auth.getRole();
    if (mounted) {
      setState(() => _currentUserRole = role ?? 'User');
    }
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _fetchCategories(),
      _fetchProducts(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchCategories() async {
    try {
      final response = await _apiClient.get('Category');
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _categories = data.map((json) => Category.fromJson(json)).toList();
          });
        }
      } else {
        _setFallbackCategories();
      }
    } catch (_) {
      _setFallbackCategories();
    }
  }

  void _setFallbackCategories() {
    if (_categories.isEmpty && mounted) {
      setState(() {
        _categories = [
          Category(id: 1, name: 'Điện thoại'),
          Category(id: 2, name: 'Laptop'),
          Category(id: 3, name: 'Thời trang'),
        ];
      });
    }
  }

  Future<void> _fetchProducts() async {
    try {
      final response = await _apiClient.get('Product');
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _allProducts = data.map((json) => Product.fromJson(json)).toList();
            _applyFilter();
          });
        }
      } else {
        _setFallbackProducts();
      }
    } catch (_) {
      _setFallbackProducts();
    }
  }

  void _setFallbackProducts() {
    if (_allProducts.isEmpty && mounted) {
      setState(() {
        _allProducts = [
          Product(
            id: 1,
            name: 'iPhone 15 Pro Max',
            price: 29990000,
            description: 'Thiết kế khung titan sang trọng, camera zoom 5x sắc nét.',
            categoryId: 1,
            categoryName: 'Điện thoại',
          ),
          Product(
            id: 2,
            name: 'MacBook Air M2 13-inch',
            price: 24500000,
            description: 'Chip M2 mỏng nhẹ, thời lượng pin cả ngày.',
            categoryId: 2,
            categoryName: 'Laptop',
          ),
          Product(
            id: 3,
            name: 'Tai nghe AirPods Pro 2',
            price: 5490000,
            description: 'Chống ồn chủ động gấp đôi, âm thanh không gian.',
            categoryId: 1,
            categoryName: 'Điện thoại',
          ),
          Product(
            id: 4,
            name: 'Áo khoác thể thao RunPro',
            price: 450000,
            description: 'Chất liệu thoáng khí, chống nước nhẹ.',
            categoryId: 3,
            categoryName: 'Thời trang',
          ),
        ];
        _applyFilter();
      });
    }
  }

  void _applyFilter() {
    if (_selectedCategoryId == null) {
      _filteredProducts = List.from(_allProducts);
    } else {
      _filteredProducts = _allProducts
          .where((p) => p.categoryId == _selectedCategoryId)
          .toList();
    }
  }

  void _onCategorySelected(int? categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;
      _applyFilter();
    });
  }

  /// Đăng xuất tài khoản người dùng
  /// Đáp ứng yêu cầu: "Thêm chức năng đăng xuất (xóa token khỏi SharePreference là xong)"
  Future<void> _handleLogout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận đăng xuất'),
        content: const Text('Bạn có muốn đăng xuất khỏi tài khoản không?'),
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
      await Auth.logout(); // Xóa token và vai trò
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cửa hàng trực tuyến',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Xin chào (${_currentUserRole ?? "User"})',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: _fetchData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Đăng xuất',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchData,
        child: Column(
          children: [
            // Thanh lọc theo danh mục
            _buildCategoryFilterBar(),
            // Danh sách sản phẩm
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredProducts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 12),
                              const Text(
                                'Không có sản phẩm nào trong danh mục này',
                                style: TextStyle(color: Colors.grey, fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = _filteredProducts[index];
                            return _buildProductCard(product);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('Tất cả'),
              selected: _selectedCategoryId == null,
              selectedColor: Colors.blue[700],
              labelStyle: TextStyle(
                color: _selectedCategoryId == null ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
              onSelected: (_) => _onCategorySelected(null),
            ),
            const SizedBox(width: 8),
            ..._categories.map((cat) {
              final isSelected = _selectedCategoryId == cat.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(cat.name),
                  selected: isSelected,
                  selectedColor: Colors.blue[700],
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (_) => _onCategorySelected(cat.id),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.shopping_bag_outlined,
                size: 40,
                color: Colors.blue[700],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (product.description != null)
                    Text(
                      product.description!,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${product.price.toStringAsFixed(0)} đ',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      Chip(
                        label: Text(
                          product.categoryName ?? 'Chưa phân loại',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue[900],
                          ),
                        ),
                        backgroundColor: Colors.blue[50],
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
