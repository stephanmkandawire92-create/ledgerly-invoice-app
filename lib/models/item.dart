import 'dart:convert';

class Item {
  final String id;
  final String name;
  final String description;
  final String sku;
  final String unit;
  final double unitPrice;
  final double taxRate;
  final String category;
  final DateTime createdAt;

  Item({
    required this.id,
    required this.name,
    this.description = '',
    this.sku = '',
    this.unit = 'pcs',
    required this.unitPrice,
    this.taxRate = 15.0,
    this.category = 'General',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'sku': sku,
        'unit': unit,
        'unitPrice': unitPrice,
        'taxRate': taxRate,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Item.fromJson(Map<String, dynamic> json) => Item(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        sku: json['sku'] as String? ?? '',
        unit: json['unit'] as String? ?? 'pcs',
        unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
        taxRate: (json['taxRate'] as num?)?.toDouble() ?? 15.0,
        category: json['category'] as String? ?? 'General',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  Item copyWith({
    String? id,
    String? name,
    String? description,
    String? sku,
    String? unit,
    double? unitPrice,
    double? taxRate,
    String? category,
    DateTime? createdAt,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      sku: sku ?? this.sku,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      taxRate: taxRate ?? this.taxRate,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static String encodeList(List<Item> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<Item> decodeList(String source) {
    if (source.trim().isEmpty) return [];
    final List<dynamic> jsonList = jsonDecode(source) as List<dynamic>;
    return jsonList
        .map((e) => Item.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
