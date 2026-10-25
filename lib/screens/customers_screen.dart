import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/business_document.dart';
import '../models/customer.dart';
import '../services/document_store.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({
    super.key,
    required this.documents,
    required this.customers,
    required this.onCustomersUpdated,
  });

  final List<BusinessDocument> documents;
  final List<Customer> customers;
  final ValueChanged<List<Customer>> onCustomersUpdated;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
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

  List<Customer> get _filteredCustomers {
    if (_searchQuery.isEmpty) return widget.customers;
    return widget.customers.where((c) {
      return c.name.toLowerCase().contains(_searchQuery) ||
          c.email.toLowerCase().contains(_searchQuery) ||
          c.phone.toLowerCase().contains(_searchQuery) ||
          c.taxNumber.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  double _totalBilledForCustomer(Customer customer) {
    return widget.documents
        .where((doc) =>
            doc.customerId == customer.id ||
            doc.clientName.toLowerCase() == customer.name.toLowerCase())
        .fold(0.0, (sum, doc) => sum + doc.total);
  }

  Future<void> _openCustomerDialog({Customer? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final billingCtrl = TextEditingController(text: existing?.billingAddress ?? '');
    final shippingCtrl = TextEditingController(text: existing?.shippingAddress ?? '');
    final taxCtrl = TextEditingController(text: existing?.taxNumber ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Customer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New Client' : 'Edit Client'),
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
                    decoration: const InputDecoration(labelText: 'Client / Company Name *'),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email Address'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone Number'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: taxCtrl,
                    decoration: const InputDecoration(labelText: 'VAT / Tax Number'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: billingCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Billing Address'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: shippingCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Shipping Address'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Internal Notes'),
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
              final customer = Customer(
                id: existing?.id ?? _uuid.v4(),
                name: nameCtrl.text.trim(),
                email: emailCtrl.text.trim(),
                phone: phoneCtrl.text.trim(),
                billingAddress: billingCtrl.text.trim(),
                shippingAddress: shippingCtrl.text.trim(),
                taxNumber: taxCtrl.text.trim(),
                notes: notesCtrl.text.trim(),
                createdAt: existing?.createdAt ?? DateTime.now(),
              );
              Navigator.pop(ctx, customer);
            },
            child: Text(existing == null ? 'Add Client' : 'Save Changes'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final updatedList = List<Customer>.from(widget.customers);
    final idx = updatedList.indexWhere((c) => c.id == result.id);
    if (idx >= 0) {
      updatedList[idx] = result;
    } else {
      updatedList.add(result);
    }
    await _store.saveCustomers(updatedList);
    widget.onCustomersUpdated(updatedList);
  }

  Future<void> _deleteCustomer(Customer customer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Client?'),
        content: Text('Are you sure you want to delete ${customer.name}?'),
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
    final updatedList = widget.customers.where((c) => c.id != customer.id).toList();
    await _store.saveCustomers(updatedList);
    widget.onCustomersUpdated(updatedList);
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
                          'Clients & Directory',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: const Color(0xFF172033), fontSize: wide ? 30 : 25),
                        ),
                        const SizedBox(height: 6),
                        const Text('Manage client contact details, addresses, and transaction history.'),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openCustomerDialog(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add client'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search clients by name, email, phone...',
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
              if (_filteredCustomers.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_outline, size: 48, color: Color(0xFF7B8497)),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty ? 'No matching clients found' : 'No clients saved yet',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          const Text('Add client details to easily select them when generating invoices.'),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _openCustomerDialog(),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add your first client'),
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
                    itemCount: _filteredCustomers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final customer = _filteredCustomers[index];
                      final billed = _totalBilledForCustomer(customer);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                          foregroundColor: const Color(0xFF4F46E5),
                          child: Text(
                            customer.name.isNotEmpty ? customer.name[0].toUpperCase() : 'C',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          customer.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (customer.email.isNotEmpty || customer.phone.isNotEmpty)
                              Text([
                                if (customer.email.isNotEmpty) customer.email,
                                if (customer.phone.isNotEmpty) customer.phone
                              ].join(' • ')),
                            if (customer.billingAddress.isNotEmpty)
                              Text(
                                customer.billingAddress,
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
                                const Text('Total Billed', style: TextStyle(fontSize: 11, color: Color(0xFF7B8497))),
                                Text(
                                  'R ${billed.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _openCustomerDialog(existing: customer),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFB42318)),
                              onPressed: () => _deleteCustomer(customer),
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
