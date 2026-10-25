import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/business_document.dart';
import '../models/payment.dart';
import '../models/currency_helper.dart';
import '../services/document_store.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({
    super.key,
    required this.documents,
    required this.payments,
    required this.onPaymentsUpdated,
  });

  final List<BusinessDocument> documents;
  final List<Payment> payments;
  final ValueChanged<List<Payment>> onPaymentsUpdated;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final DocumentStore _store = DocumentStore();
  final Uuid _uuid = const Uuid();

  List<BusinessDocument> get _invoices =>
      widget.documents.where((d) => d.kind == DocumentKind.invoice).toList();

  List<BusinessDocument> get _payableInvoices => _invoices.where((d) {
        if (d.status == 'Void' || d.status == 'Draft') return false;
        return _totalPaidForInvoice(d.id) + 0.004 < d.total;
      }).toList();

  double get _totalCollected =>
      widget.payments.fold(0.0, (sum, p) => sum + p.amount);

  double _totalPaidForInvoice(String invoiceId) {
    return widget.payments
        .where((p) => p.invoiceId == invoiceId)
        .fold(0.0, (sum, p) => sum + p.amount);
  }

  Future<void> _recordPaymentDialog({BusinessDocument? preselectedInvoice}) async {
    if (_payableInvoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create an invoice first before recording payments.')),
      );
      return;
    }

    BusinessDocument selectedInvoice = _payableInvoices.any((d) => d.id == preselectedInvoice?.id)
        ? preselectedInvoice!
        : _payableInvoices.first;
    final paidSoFar = _totalPaidForInvoice(selectedInvoice.id);
    final remaining = (selectedInvoice.total - paidSoFar).clamp(0.0, double.infinity);

    final amountCtrl = TextEditingController(text: remaining.toStringAsFixed(2));
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String method = 'Bank Transfer';
    DateTime paymentDate = DateTime.now();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Payment>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentPaid = _totalPaidForInvoice(selectedInvoice.id);
          final currentRemaining = (selectedInvoice.total - currentPaid).clamp(0.0, double.infinity);

          return AlertDialog(
            title: const Text('Record Payment'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<BusinessDocument>(
                        initialValue: selectedInvoice,
                        decoration: const InputDecoration(labelText: 'Select Invoice *'),
                        items: _payableInvoices.map((inv) {
                          return DropdownMenuItem(
                            value: inv,
                            child: Text('${inv.number} - ${inv.clientName} (${inv.currencyCode} ${inv.total.toStringAsFixed(2)})'),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedInvoice = val;
                              final rem = (val.total - _totalPaidForInvoice(val.id)).clamp(0.0, double.infinity);
                              amountCtrl.text = rem.toStringAsFixed(2);
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE4E7EF)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Invoice Total: ${CurrencyHelper.format(selectedInvoice.total, selectedInvoice.currencyCode)}'),
                            Text(
                              'Remaining: ${CurrencyHelper.format(currentRemaining, selectedInvoice.currencyCode)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFB54708)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Payment Amount *'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Amount required';
                          final val = double.tryParse(v.trim());
                          if (val == null || !val.isFinite || val <= 0) return 'Enter valid amount';
                          if (val > currentRemaining + 0.004) {
                            return 'Amount cannot exceed the remaining balance';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: method,
                        decoration: const InputDecoration(labelText: 'Payment Method'),
                        items: ['Bank Transfer', 'Cash', 'Credit Card', 'EFT', 'Cheque', 'Other']
                            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
                        onChanged: (val) => setDialogState(() => method = val ?? 'Bank Transfer'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: refCtrl,
                        decoration: const InputDecoration(labelText: 'Reference / Transaction ID'),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: paymentDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => paymentDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Payment Date'),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(DateFormat('d MMM yyyy').format(paymentDate)),
                              const Icon(Icons.calendar_today, size: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'Notes / Comments'),
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
                  final p = Payment(
                    id: _uuid.v4(),
                    invoiceId: selectedInvoice.id,
                    paymentDate: paymentDate,
                    amount: double.tryParse(amountCtrl.text.trim()) ?? 0.0,
                    method: method,
                    reference: refCtrl.text.trim(),
                    notes: notesCtrl.text.trim(),
                  );
                  Navigator.pop(ctx, p);
                },
                child: const Text('Save Payment'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return;
    final invoice = widget.documents.firstWhere((d) => d.id == result.invoiceId);
    final updatedPayments = List<Payment>.from(widget.payments)..add(result);
    try {
      _reconcileInvoiceStatus(invoice, updatedPayments);
      await _store.savePayments(updatedPayments);
      await _store.save(widget.documents);
      if (!mounted) return;
      widget.onPaymentsUpdated(updatedPayments);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment could not be saved. Please try again; check storage before repeating.')),
        );
      }
    }
  }

  Future<void> _deletePayment(Payment payment) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Payment Record?'),
        content: Text('Are you sure you want to delete payment of ${CurrencyHelper.format(payment.amount, _currencyForInvoice(payment.invoiceId))}?'),
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
    final updated = widget.payments.where((p) => p.id != payment.id).toList();
    BusinessDocument? invoice;
    for (final document in widget.documents) {
      if (document.id == payment.invoiceId) { invoice = document; break; }
    }
    try {
      if (invoice != null) _reconcileInvoiceStatus(invoice, updated);
      await _store.savePayments(updated);
      if (invoice != null) await _store.save(widget.documents);
      if (!mounted) return;
      widget.onPaymentsUpdated(updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment deletion could not be saved. Please try again.')),
        );
      }
    }
  }

  String _currencyForInvoice(String invoiceId) {
    for (final document in widget.documents) {
      if (document.id == invoiceId) return document.currencyCode;
    }
    return 'ZAR';
  }

  void _reconcileInvoiceStatus(BusinessDocument invoice, List<Payment> payments) {
    if (invoice.kind != DocumentKind.invoice || invoice.status == 'Void' || invoice.status == 'Draft') return;
    final paid = payments.where((p) => p.invoiceId == invoice.id).fold<double>(0, (sum, p) => sum + p.amount);
    if (paid + 0.004 >= invoice.total) {
      invoice.status = 'Paid';
    } else if (paid > 0) {
      invoice.status = 'Pending';
    } else if (invoice.status == 'Paid' || invoice.status == 'Pending') {
      invoice.status = invoice.dueDate.isBefore(DateTime.now()) ? 'Overdue' : 'Sent';
    }
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
                          'Payments & Collections',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: const Color(0xFF172033), fontSize: wide ? 30 : 25),
                        ),
                        const SizedBox(height: 6),
                        const Text('Track client payments, partial payments, and payment methods.'),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _recordPaymentDialog(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Record payment'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Payments Recorded', style: TextStyle(color: Color(0xFF7B8497))),
                            const SizedBox(height: 4),
                            Text(
                              'R ${_totalCollected.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0E9F6E),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Payment Entries', style: TextStyle(color: Color(0xFF7B8497))),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.payments.length}',
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (widget.payments.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.payments_outlined, size: 48, color: Color(0xFF7B8497)),
                          const SizedBox(height: 12),
                          const Text(
                            'No payments recorded yet',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          const Text('Record payments when clients pay their invoices to update statuses automatically.'),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _recordPaymentDialog(),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Record first payment'),
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
                    itemCount: widget.payments.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final p = widget.payments[index];
                      final matchingInv = _invoices.firstWhere(
                        (i) => i.id == p.invoiceId,
                        orElse: () => BusinessDocument(
                          id: '',
                          number: 'N/A',
                          kind: DocumentKind.invoice,
                          clientName: 'Unknown Client',
                          clientEmail: '',
                          issueDate: DateTime.now(),
                          dueDate: DateTime.now(),
                          status: '',
                          currencyCode: 'ZAR',
                          lines: [],
                          taxPercent: 0,
                          discount: 0,
                          notes: '',
                        ),
                      );
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF0E9F6E).withValues(alpha: 0.1),
                          foregroundColor: const Color(0xFF0E9F6E),
                          child: const Icon(Icons.check, size: 20),
                        ),
                        title: Text(
                          '${CurrencyHelper.format(p.amount, matchingInv.currencyCode)} - ${p.method}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${matchingInv.number} • ${matchingInv.clientName}'),
                            Text(
                              'Date: ${DateFormat('d MMM yyyy').format(p.paymentDate)}${p.reference.isNotEmpty ? ' • Ref: ${p.reference}' : ''}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF7B8497)),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFB42318)),
                          onPressed: () => _deletePayment(p),
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
