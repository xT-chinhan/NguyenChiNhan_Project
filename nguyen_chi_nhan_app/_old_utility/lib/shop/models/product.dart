class Product {
  final int id;
  final String name;
  final double price;
  final String? description;
  final String? imageUrl;
  final int? categoryId;
  final String? categoryName;

  Product({
    required this.id,
    required this.name,
    required this.price,
    this.description,
    this.imageUrl,
    this.categoryId,
    this.categoryName,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? '',
      price: (json['price'] is num)
          ? (json['price'] as num).toDouble()
          : double.tryParse(json['price']?.toString() ?? '0.0') ?? 0.0,
      description: json['description']?.toString(),
      imageUrl: (json['imageUrl'] ?? json['image'])?.toString(),
      categoryId: json['categoryId'] != null
          ? int.tryParse(json['categoryId'].toString())
          : null,
      categoryName: json['categoryName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'description': description,
      'imageUrl': imageUrl,
      'categoryId': categoryId,
      'categoryName': categoryName,
    };
  }
}
