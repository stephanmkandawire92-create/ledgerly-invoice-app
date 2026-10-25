import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/item.dart';
import '../services/document_store.dart';

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({
    super.key,
    required this.items,
    required this.onItemsUpdated,
  });

  final List<Item> items;
  final ValueChanged<List<Item>> onItemsUpdated;

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final DocumentStore _store = DocumentStore();
  final Uuid _uuid = const Uuid();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Item> get _filteredItems {
    if (_searchQuery.isEmpty) return widget.items;
    return widget.items.where((i) {
      return i.name.toLowerCase().contains(_searchQuery) ||
          i.sku.toLowerCase().contains(_searchQuery) ||
          i.category.toLowerCase().contains(_searchQuery) ||
          i.description.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  Future<void> _openItemDialog({Item? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    final skuCtrl = TextEditingController(text: existing?.sku ?? '');
    final unitCtrl = TextEditingController(text: existing?.unit ?? 'pcs');
    final priceCtrl = TextEditingController(
        text: existing != null ? existing.unitPrice.toStringAsFixed(2) : '');
    final taxCtrl = TextEditingController(
        text: existing != null ? existing.taxRate.toStringAsFixed(1) : '15.0');
    final catCtrl = TextEditingController(text: existing?.category ?? 'Services');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Item>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New Product / Service' : 'Edit Item'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Item Name *'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Unit Price *'),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            final value = double.tryParse(v.trim());
                            if (value == null || !value.isFinite || value < 0 || value > 1e12) {
                              return 'Enter a valid non-negative price';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: unitCtrl,
                          decoration: const InputDecoration(labelText: 'Unit (e.g. hrs, pcs)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: skuCtrl,
                          decoration: const InputDecoration(labelText: 'SKU / Code'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: taxCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Tax Rate (%)'),
                          validator: (v) {
                            final value = double.tryParse((v ?? '').trim());
                            if (value == null || !value.isFinite || value < 0 || value > 100) {
                              return 'Enter a tax rate from 0 to 100';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: catCtrl,
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Default Description'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              final item = Item(
                id: existing?.id ?? _uuid.v4(),
                name: nameCtrl.text.trim(),
                description: descCtrl.text.trim(),
                sku: skuCtrl.text.trim(),
                unit: unitCtrl.text.trim().isEmpty ? 'pcs' : unitCtrl.text.trim(),
                unitPrice: double.tryParse(priceCtrl.text.trim()) ?? 0.0,
                taxRate: double.tryParse(taxCtrl.text.trim()) ?? 15.0,
                category: catCtrl.text.trim().isEmpty ? 'General' : catCtrl.text.trim(),
                createdAt: existing?.createdAt ?? DateTime.now(),
              );
              Navigator.pop(ctx, item);
            },
            child: Text(existing == null ? 'Add Item' : 'Save Changes'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final updatedList = List<Item>.from(widget.items);
    final idx = updatedList.indexWhere((i) => i.id == result.id);
    if (idx >= 0) {
      updatedList[idx] = result;
    } else {
      updatedList.add(result);
    }
    await _store.saveItems(updatedList);
    widget.onItemsUpdated(updatedList);
  }

  Future<void> _deleteItem(Item item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text('Are you sure you want to delete ${item.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    final updatedList = widget.items.where((i) => i.id != item.id).toList();
    await _store.saveItems(updatedList);
    widget.onItemsUpdated(updatedList);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(wide ? 34 : 18, 24, wide ? 34 : 18, 90),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Items & Catalog',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: const Color(0xFF172033), fontSize: wide ? 30 : 25),
                        ),
                        const SizedBox(height: 6),
                        const Text('Manage products, services, default unit prices and tax rates.'),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openItemDialog(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add item'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search items by name, SKU, category...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              if (_filteredItems.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF7B8497)),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty ? 'No matching items found' : 'No items saved yet',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          const Text('Add reusable products and services to auto-fill document line items.'),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _openItemDialog(),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add your first item'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Card(
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _filteredItems.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                          foregroundColor: const Color(0xFF4F46E5),
                          child: const Icon(Icons.shopping_bag_outlined, size: 20),
                        ),
                        title: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${item.category} • SKU: ${item.sku.isNotEmpty ? item.sku : 'N/A'} • Tax: ${item.taxRate}%'),
                            if (item.description.isNotEmpty)
                              Text(
                                item.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF7B8497)),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Unit Price', style: TextStyle(fontSize: 11, color: Color(0xFF7B8497))),
                                Text(
                                  'R ${item.unitPrice.toStringAsFixed(2)} / ${item.unit}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _openItemDialog(existing: item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFB42318)),
                              onPressed: () => _deleteItem(item),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
