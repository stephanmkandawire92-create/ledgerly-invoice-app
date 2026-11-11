import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/business_document.dart';
import '../models/currency_helper.dart';
import '../models/customer.dart';
import '../models/item.dart';

const _ink = Color(0xFF172033);
const _muted = Color(0xFF7B8497);

String dateLabel(DateTime date) => DateFormat('d MMM yyyy').format(date);

class DocumentEditorDialog extends StatefulWidget {
  const DocumentEditorDialog({
    super.key,
    required this.kind,
    required this.nextNumber,
    this.currencyLocked = false,
    this.existing,
    this.customers = const [],
    this.items = const [],
    required this.currencyCode,
    required this.langCode,
    this.existingNumbers = const [],
  });

  final DocumentKind kind;
  final String nextNumber;
  final bool currencyLocked;
  final BusinessDocument? existing;
  final List<Customer> customers;
  final List<Item> items;
  final String currencyCode;
  final String langCode;
  final List<String> existingNumbers;

  @override
  State<DocumentEditorDialog> createState() => _DocumentEditorDialogState();
}

class _DocumentEditorDialogState extends State<DocumentEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _number;
  late final TextEditingController _client;
  late final TextEditingController _email;
  late final TextEditingController _discount;
  late final TextEditingController _tax;
  late final TextEditingController _notes;
  late DateTime _issueDate;
  late DateTime _dueDate;
  late String _status;
  late String _currency;
  late List<_LineDraft> _lines;
  String _customerId = '';
  String _customerNameSnapshot = '';

  @override
  void initState() {
    super.initState();
    final old = widget.existing;
    _number = TextEditingController(text: old?.number ?? widget.nextNumber);
    _client = TextEditingController(text: old?.clientName ?? '');
    _email = TextEditingController(text: old?.clientEmail ?? '');
    _discount = TextEditingController(text: (old?.discount ?? 0).toString());
    _tax = TextEditingController(text: (old?.taxPercent ?? 15).toString());
    _notes = TextEditingController(text: old?.notes ?? '');
    _issueDate = old?.issueDate ?? DateTime.now();
    _dueDate = old?.dueDate ?? DateTime.now().add(const Duration(days: 14));
    _status = old?.status ?? 'Draft';
    _currency = old?.currencyCode ?? widget.currencyCode;
    _customerId = old?.customerId ?? '';
    _customerNameSnapshot = old?.clientName ?? '';
    _lines = (old?.lines ?? []).map(_LineDraft.fromLine).toList();
    if (_lines.isEmpty) _lines = [_LineDraft()];
  }

  @override
  void dispose() {
    _number.dispose();
    _client.dispose();
    _email.dispose();
    _discount.dispose();
    _tax.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  double get _subtotal =>
      roundMoney(_lines.fold<double>(0.0, (sum, line) => sum + line.amount));
  double get _discountValue {
    final value = double.tryParse(_discount.text) ?? 0;
    if (!value.isFinite || value <= 0) return 0;
    return roundMoney(value.clamp(0.0, _subtotal).toDouble());
  }

  double get _taxValue {
    final value = double.tryParse(_tax.text) ?? 0;
    return value.isFinite ? value.clamp(0.0, 100.0).toDouble() : 0.0;
  }

  double get _total {
    final taxable =
        (_subtotal - _discountValue).clamp(0.0, double.infinity).toDouble();
    final tax = roundMoney(taxable * _taxValue / 100);
    return roundMoney(taxable + tax);
  }

  Future<DateTime?> _chooseDate(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );

  Future<void> _pickCustomer() async {
    final selected = await showDialog<Customer>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Client from Directory'),
        content: SizedBox(
          width: 400,
          height: 350,
          child: widget.customers.isEmpty
              ? const Center(
                  child: Text('No saved clients. Add clients in Clients tab.'))
              : ListView.separated(
                  itemCount: widget.customers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final c = widget.customers[idx];
                    return ListTile(
                      title: Text(c.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(c.email.isNotEmpty ? c.email : c.phone),
                      onTap: () => Navigator.pop(ctx, c),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );

    if (selected != null) {
      setState(() {
        _client.text = selected.name;
        _email.text = selected.email;
        _customerId = selected.id;
        _customerNameSnapshot = selected.name;
      });
    }
  }

  Future<void> _pickCatalogItem(_LineDraft line) async {
    final selected = await showDialog<Item>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Item from Catalog'),
        content: SizedBox(
          width: 400,
          height: 350,
          child: widget.items.isEmpty
              ? const Center(
                  child: Text(
                      'No saved items. Add products/services in Items tab.'))
              : ListView.separated(
                  itemCount: widget.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final item = widget.items[idx];
                    return ListTile(
                      title: Text(item.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${item.category} • ${CurrencyHelper.format(item.unitPrice, _currency)} / ${item.unit}'),
                      onTap: () => Navigator.pop(ctx, item),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );

    if (selected != null) {
      final hasOtherDescription = _lines.any((other) =>
          !identical(other, line) && other.description.text.trim().isNotEmpty);
      setState(() {
        line.description.text = selected.name;
        line.price.text = selected.unitPrice.toStringAsFixed(2);
        if (!hasOtherDescription) {
          _tax.text = selected.taxRate.toStringAsFixed(1);
        }
      });
      if (hasOtherDescription &&
          (double.tryParse(_tax.text) ?? 0) != selected.taxRate &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'This document applies one tax rate to all lines. Review the tax rate in Totals and terms.')),
        );
      }
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final old = widget.existing;
    if (widget.currencyLocked && old != null && _currency != old.currencyCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Currency cannot be changed after payments have been recorded.')),
      );
      return;
    }
    if (_dueDate.isBefore(
        DateTime(_issueDate.year, _issueDate.month, _issueDate.day))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Due date cannot be earlier than the issue date.')),
      );
      return;
    }
    final doc = BusinessDocument(
      id: old?.id ?? const Uuid().v4(),
      number: _number.text.trim(),
      kind: old?.kind ?? widget.kind,
      clientName: _client.text.trim(),
      clientEmail: _email.text.trim(),
      issueDate: _issueDate,
      dueDate: _dueDate,
      status: _status,
      currencyCode: _currency,
      lines: _lines
          .map((line) => DocumentLine(
                id: line.id,
                description: line.description.text.trim(),
                quantity: double.tryParse(line.quantity.text) ?? 1,
                unitPrice: double.tryParse(line.price.text) ?? 0,
              ))
          .toList(),
      taxPercent: _taxValue,
      discount: _discountValue,
      notes: _notes.text.trim(),
      customerId: _customerId,
    );
    Navigator.of(context).pop(doc);
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
            title: Text(
                '${widget.existing == null ? 'New' : 'Edit'} ${widget.kind == DocumentKind.invoice ? 'invoice' : 'quote'}'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Save document'),
                  ),
                ),
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('Document details',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                  ),
                                  if (widget.customers.isNotEmpty)
                                    OutlinedButton.icon(
                                      onPressed: _pickCustomer,
                                      icon: const Icon(
                                          Icons.person_search_outlined,
                                          size: 16),
                                      label: const Text('Pick saved client'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final cols =
                                      constraints.maxWidth > 650 ? 2 : 1;
                                  return _ResponsiveFields(
                                      columns: cols,
                                      children: [
                                        TextFormField(
                                          controller: _number,
                                          decoration: const InputDecoration(
                                              labelText: 'Document number'),
                                          validator: (v) {
                                            final value = v?.trim() ?? '';
                                            if (value.isEmpty) {
                                              return 'Required';
                                            }
                                            if (widget.existingNumbers.contains(
                                                value.toLowerCase())) {
                                              return 'This document number is already in use';
                                            }
                                            return null;
                                          },
                                        ),
                                        DropdownButtonFormField<String>(
                                          initialValue: _status,
                                          decoration: const InputDecoration(
                                              labelText: 'Status'),
                                          items: (widget.kind ==
                                                      DocumentKind.invoice
                                                  ? [
                                                      'Draft',
                                                      'Sent',
                                                      'Pending',
                                                      'Paid',
                                                      'Overdue',
                                                      'Void'
                                                    ]
                                                  : [
                                                      'Draft',
                                                      'Sent',
                                                      'Pending',
                                                      'Accepted',
                                                      'Declined'
                                                    ])
                                              .map((value) => DropdownMenuItem(
                                                  value: value,
                                                  child: Text(value)))
                                              .toList(),
                                          onChanged: (value) => setState(
                                              () => _status = value ?? 'Draft'),
                                        ),
                                        TextFormField(
                                          controller: _client,
                                          decoration: const InputDecoration(
                                              labelText:
                                                  'Client / business name'),
                                          onChanged: (value) {
                                            if (_customerId.isNotEmpty &&
                                                value.trim() !=
                                                    _customerNameSnapshot) {
                                              _customerId = '';
                                              _customerNameSnapshot = '';
                                            }
                                          },
                                          validator: (v) =>
                                              v == null || v.trim().isEmpty
                                                  ? 'Enter a client name'
                                                  : null,
                                        ),
                                        TextFormField(
                                          controller: _email,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          decoration: const InputDecoration(
                                              labelText:
                                                  'Client email (optional)'),
                                          validator: (v) {
                                            if (v == null || v.trim().isEmpty) {
                                              return null;
                                            }
                                            return RegExp(
                                                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                                    .hasMatch(v.trim())
                                                ? null
                                                : 'Enter a valid email';
                                          },
                                        ),
                                        DropdownButtonFormField<String>(
                                          initialValue: _currency,
                                          decoration: const InputDecoration(
                                              labelText: 'Currency'),
                                          items: CurrencyHelper.currencies
                                              .map((c) => DropdownMenuItem(
                                                  value: c.code,
                                                  child: Text(
                                                      '${c.code} (${c.symbol})')))
                                              .toList(),
                                          onChanged: (value) => setState(
                                              () => _currency = value ?? 'USD'),
                                        ),
                                        _DateButton(
                                          label: 'Issue date',
                                          date: _issueDate,
                                          onTap: () async {
                                            final date =
                                                await _chooseDate(_issueDate);
                                            if (date != null) {
                                              setState(() => _issueDate = date);
                                            }
                                          },
                                        ),
                                        _DateButton(
                                          label: 'Due date',
                                          date: _dueDate,
                                          onTap: () async {
                                            final date =
                                                await _chooseDate(_dueDate);
                                            if (date != null) {
                                              setState(() => _dueDate = date);
                                            }
                                          },
                                        ),
                                      ]);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('Line items',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => setState(
                                        () => _lines.add(_LineDraft())),
                                    icon: const Icon(Icons.add, size: 17),
                                    label: const Text('Add item'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              ..._lines.asMap().entries.map((entry) {
                                final index = entry.key;
                                final line = entry.value;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text('Item ${index + 1}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ),
                                          if (widget.items.isNotEmpty)
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _pickCatalogItem(line),
                                              icon: const Icon(
                                                  Icons.inventory_2_outlined,
                                                  size: 15),
                                              label: const Text('Catalog Item'),
                                            ),
                                          if (_lines.length > 1)
                                            IconButton(
                                              tooltip: 'Remove item',
                                              onPressed: () => setState(() {
                                                line.dispose();
                                                _lines.remove(line);
                                              }),
                                              icon: const Icon(
                                                  Icons.delete_outline,
                                                  color: Color(0xFFB42318)),
                                            ),
                                        ],
                                      ),
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          final cols =
                                              constraints.maxWidth > 650
                                                  ? 3
                                                  : 1;
                                          return _ResponsiveFields(
                                              columns: cols,
                                              children: [
                                                TextFormField(
                                                  controller: line.description,
                                                  decoration:
                                                      const InputDecoration(
                                                          labelText:
                                                              'Description'),
                                                  validator: (v) => v == null ||
                                                          v.trim().isEmpty
                                                      ? 'Required'
                                                      : null,
                                                ),
                                                TextFormField(
                                                  controller: line.quantity,
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                          decimal: true),
                                                  decoration:
                                                      const InputDecoration(
                                                          labelText:
                                                              'Quantity'),
                                                  validator: (v) {
                                                    final n = double.tryParse(
                                                        v ?? '');
                                                    return n == null ||
                                                            !n.isFinite ||
                                                            n <= 0 ||
                                                            n > 1e9
                                                        ? 'Enter a quantity above zero (maximum 1,000,000,000)'
                                                        : null;
                                                  },
                                                  onChanged: (_) =>
                                                      setState(() {}),
                                                ),
                                                TextFormField(
                                                  controller: line.price,
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                          decimal: true),
                                                  decoration:
                                                      const InputDecoration(
                                                          labelText:
                                                              'Unit price'),
                                                  validator: (v) {
                                                    final n = double.tryParse(
                                                        v ?? '');
                                                    return n == null ||
                                                            !n.isFinite ||
                                                            n < 0 ||
                                                            n > 1e12
                                                        ? 'Enter a valid price (maximum 1,000,000,000,000)'
                                                        : null;
                                                  },
                                                  onChanged: (_) =>
                                                      setState(() {}),
                                                ),
                                              ]);
                                        },
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          'Line total: ${CurrencyHelper.format(line.amount, _currency)}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Totals and terms',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 16),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final cols =
                                      constraints.maxWidth > 650 ? 2 : 1;
                                  return _ResponsiveFields(
                                      columns: cols,
                                      children: [
                                        TextFormField(
                                          controller: _discount,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(
                                              labelText: 'Discount amount'),
                                          onChanged: (_) => setState(() {}),
                                          validator: (v) {
                                            final n = double.tryParse(v ?? '');
                                            return n == null ||
                                                    !n.isFinite ||
                                                    n < 0
                                                ? 'Enter zero or more'
                                                : null;
                                          },
                                        ),
                                        TextFormField(
                                          controller: _tax,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(
                                              labelText: 'Tax rate (%)'),
                                          onChanged: (_) => setState(() {}),
                                          validator: (v) {
                                            final n = double.tryParse(v ?? '');
                                            return n == null ||
                                                    !n.isFinite ||
                                                    n < 0 ||
                                                    n > 100
                                                ? 'Use 0–100%'
                                                : null;
                                          },
                                        ),
                                      ]);
                                },
                              ),
                              const SizedBox(height: 16),
                              _TotalLine(
                                  label: 'Subtotal',
                                  value: CurrencyHelper.format(
                                      _subtotal, _currency)),
                              _TotalLine(
                                  label: 'Discount',
                                  value:
                                      '-${CurrencyHelper.format(_discountValue, _currency)}'),
                              _TotalLine(
                                  label: 'Tax',
                                  value: CurrencyHelper.format(
                                      _total - (_subtotal - _discountValue),
                                      _currency)),
                              const Divider(height: 24),
                              _TotalLine(
                                  label: 'Total due',
                                  value:
                                      CurrencyHelper.format(_total, _currency),
                                  bold: true),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _notes,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                    labelText: 'Notes and terms',
                                    alignLabelWithHint: true),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _submit,
                          icon: const Icon(Icons.check),
                          label: const Text('Save document'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _LineDraft {
  _LineDraft(
      {String? id,
      String description = '',
      String quantity = '1',
      String price = '0'})
      : id = id ?? const Uuid().v4(),
        description = TextEditingController(text: description),
        quantity = TextEditingController(text: quantity),
        price = TextEditingController(text: price);

  final String id;
  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController price;

  double get amount {
    final q = double.tryParse(quantity.text) ?? 0;
    final p = double.tryParse(price.text) ?? 0;
    final quantityValue = q.isFinite ? q.clamp(0.0, 1e9).toDouble() : 0.0;
    final priceValue = p.isFinite ? p.clamp(0.0, 1e12).toDouble() : 0.0;
    return roundMoney(quantityValue * priceValue);
  }

  factory _LineDraft.fromLine(DocumentLine line) => _LineDraft(
        id: line.id,
        description: line.description,
        quantity: line.quantity.toString(),
        price: line.unitPrice.toString(),
      );

  void dispose() {
    description.dispose();
    quantity.dispose();
    price.dispose();
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.columns, required this.children});
  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (columns == 1) {
      return Column(
          children: children
              .map((child) => Padding(
                  padding: const EdgeInsets.only(bottom: 12), child: child))
              .toList());
    }
    return Column(
      children: [
        for (var i = 0; i < children.length; i += columns)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = i;
                    j <
                        (i + columns < children.length
                            ? i + columns
                            : children.length);
                    j++) ...[
                  if (j > i) const SizedBox(width: 12),
                  Expanded(child: children[j]),
                ],
                if ((children.length - i) < columns)
                  for (var pad = 0;
                      pad < columns - (children.length - i);
                      pad++)
                    const Expanded(child: SizedBox()),
              ],
            ),
          ),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton(
      {required this.label, required this.date, required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
              labelText: label,
              suffixIcon: const Icon(Icons.calendar_month_outlined, size: 18)),
          child: Text(dateLabel(date)),
        ),
      );
}

class _TotalLine extends StatelessWidget {
  const _TotalLine(
      {required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: bold ? _ink : _muted,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
            ),
            Text(value,
                style: TextStyle(
                    color: _ink,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    fontSize: bold ? 19 : 14)),
          ],
        ),
      );
}
