import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/business_document.dart';
import '../models/business_profile.dart';
import '../models/currency_helper.dart';
import '../models/customer.dart';
import '../models/item.dart';
import '../models/payment.dart';
import '../services/app_translations.dart';
import '../services/document_store.dart';
import '../services/cloud_storage_service.dart';
import 'analytics_screen.dart';
import 'business_profile_screen.dart';
import 'customers_screen.dart';
import 'items_screen.dart';
import 'payments_screen.dart';
import '../services/subscription_service.dart';
import 'paywall_screen.dart';

const _brand = Color(0xFF4F46E5);
const _ink = Color(0xFF172033);
const _muted = Color(0xFF7B8497);
const _line = Color(0xFFE9ECF3);

String dateLabel(DateTime date) => DateFormat('d MMM yyyy').format(date);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DocumentStore _store = DocumentStore();
  final TextEditingController _searchController = TextEditingController();

  List<BusinessDocument> _documents = [];
  List<Customer> _customers = [];
  List<Item> _items = [];
  List<Payment> _payments = [];
  BusinessProfile _profile = BusinessProfile();

  bool _loading = true;
  String _section = 'Overview';
  String _query = '';
  String _filter = 'All';
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _lang => _profile.languageCode;

  Future<void> _loadAllData() async {
    try {
      final docs = await _store.load();
      final customers = await _store.loadCustomers();
      final items = await _store.loadItems();
      final payments = await _store.loadPayments();
      final profile = await _store.loadProfile();

      if (!mounted) return;
      setState(() {
        _documents = docs;
        _customers = customers;
        _items = items;
        _payments = payments;
        _profile = profile;
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Saved data could not be read. Your local data was not overwritten.';
      });
    }
  }

  Future<bool> _persist() async {
    try {
      await _store.save(_documents);
      if (mounted) setState(() => _loadError = null);
      return true;
    } catch (error) {
      final cloudMode = await CloudStorageService.instance.isCloudMode;
      if (mounted) {
        if (cloudMode) {
          setState(() => _loadError =
              'Cloud changes could not be saved. The cloud copy was not overwritten. Refresh the workspace before editing again.');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              cloudMode
                  ? 'Could not sync to cloud. Check the connection or refresh if another device changed these records.'
                  : 'Could not save to this device. Check available storage and try again.',
            ),
          ),
        );
      }
      return false;
    }
  }

  List<BusinessDocument> get _visibleDocuments {
    return _documents.where((doc) {
      final sectionMatch = _section == 'Quotes'
          ? doc.kind == DocumentKind.quote
          : _section == 'Invoices'
              ? doc.kind == DocumentKind.invoice
              : _section == 'Follow-ups'
                  ? doc.kind == DocumentKind.quote && !['Accepted', 'Declined'].contains(doc.status)
                  : true;
      final filterMatch = _filter == 'All' || doc.status == _filter;
      final queryMatch = _query.isEmpty ||
          [doc.number, doc.clientName, doc.clientEmail, doc.status]
              .any((value) => value.toLowerCase().contains(_query));
      return sectionMatch && filterMatch && queryMatch;
    }).toList()
      ..sort((a, b) => b.issueDate.compareTo(a.issueDate));
  }

  double get _paidTotal => _payments.fold<double>(0, (sum, payment) {
        BusinessDocument? invoice;
        for (final d in _documents) {
          if (d.id == payment.invoiceId && d.kind == DocumentKind.invoice) { invoice = d; break; }
        }
        if (invoice == null ||
            invoice.currencyCode.toUpperCase() != _profile.currencyCode.toUpperCase() ||
            !payment.amount.isFinite ||
            payment.amount <= 0) {
          return sum;
        }
        return sum + payment.amount;
      });

  double get _outstandingTotal => _documents
      .where((doc) =>
          doc.kind == DocumentKind.invoice &&
          doc.currencyCode.toUpperCase() == _profile.currencyCode.toUpperCase() &&
          !['Draft', 'Void'].contains(doc.status))
      .fold<double>(0, (sum, doc) {
        final paid = _payments.where((p) => p.invoiceId == doc.id && p.amount.isFinite && p.amount > 0)
            .fold<double>(0, (amount, p) => amount + p.amount);
        return sum + (doc.total - paid).clamp(0.0, doc.total).toDouble();
      });

  double get _quoteTotal => _documents
      .where((doc) =>
          doc.kind == DocumentKind.quote &&
          doc.currencyCode.toUpperCase() == _profile.currencyCode.toUpperCase() &&
          !['Accepted', 'Declined'].contains(doc.status))
      .fold(0, (sum, doc) => sum + doc.total);

  Future<void> _createDocument(DocumentKind kind, {BusinessDocument? existing}) async {
    if (_loadError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resolve the local data issue before creating or changing records.')),
      );
      return;
    }
    if (existing == null && !SubscriptionService.instance.canCreateDocument(_documents.length)) {
      final upgraded = await PaywallScreen.showPaywall(
        context,
        featurePrompt: 'You have reached the Free Tier limit of 5 documents. Subscribe with PayPal to unlock unlimited quotes and invoices.',
      );
      if (!mounted) return;
      if (upgraded != true && !SubscriptionService.instance.isPro) {
        return;
      }
    }
    final result = await showDialog<BusinessDocument>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DocumentEditorDialog(
        kind: kind,
        existing: existing,
        nextNumber: _nextNumber(kind),
        customers: _customers,
        items: _items,
        currencyCode: _profile.currencyCode,
        langCode: _lang,
        existingNumbers: _documents
            .where((doc) => doc.kind == kind && doc.id != existing?.id)
            .map((doc) => doc.number.trim().toLowerCase())
            .toList(),
      ),
    );
    if (result == null || !mounted) return;
    if (kind == DocumentKind.invoice && result.status != 'Void') {
      final paid = _payments.where((p) => p.invoiceId == result.id && p.amount.isFinite && p.amount > 0)
          .fold<double>(0, (sum, p) => sum + p.amount);
      if (paid > 0 && paid + 0.004 >= result.total) {
        result.status = 'Paid';
      } else if (paid > 0) {
        result.status = 'Pending';
      } else if (result.status == 'Paid' || result.status == 'Pending') {
        result.status = result.dueDate.isBefore(DateTime.now()) ? 'Overdue' : 'Sent';
      }
    }
    final previousDocuments = List<BusinessDocument>.from(_documents);
    setState(() {
      final index = _documents.indexWhere((doc) => doc.id == result.id);
      if (index >= 0) {
        _documents[index] = result;
      } else {
        _documents.add(result);
      }
    });
    final saved = await _persist();
    if (!saved && mounted) {
      setState(() {
        _documents = previousDocuments;
      });
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${kind == DocumentKind.invoice ? 'Invoice' : 'Quote'} saved on this device.')),
      );
    }
  }

  String _nextNumber(DocumentKind kind) {
    final prefix = kind == DocumentKind.invoice ? _profile.invoicePrefix : _profile.quotePrefix;
    final stem = '$prefix${DateTime.now().year}-';
    var highest = 0;
    for (final doc in _documents.where((d) => d.kind == kind && d.number.startsWith(stem))) {
      final sequence = int.tryParse(doc.number.substring(stem.length));
      if (sequence != null && sequence > highest) highest = sequence;
    }
    return '$stem${(highest + 1).toString().padLeft(4, '0')}';
  }

  Future<Uint8List> _makePdf(BusinessDocument doc) async {
    final pdf = pw.Document();
    final currency = doc.currencyCode;
    final docPayments = _payments.where((p) => p.invoiceId == doc.id).toList();
    final totalPaid = docPayments.fold(0.0, (sum, p) => sum + p.amount);
    final remaining = (doc.total - totalPaid).clamp(0.0, double.infinity);

    // Find matching customer details
    Customer? matchedCustomer;
    if (doc.customerId.isNotEmpty) {
      matchedCustomer = _customers.firstWhere((c) => c.id == doc.customerId, orElse: () => Customer(id: '', name: ''));
    }
    if (matchedCustomer == null || matchedCustomer.name.isEmpty) {
      matchedCustomer = _customers.firstWhere(
        (c) => c.name.toLowerCase() == doc.clientName.toLowerCase(),
        orElse: () => Customer(id: '', name: doc.clientName, email: doc.clientEmail),
      );
    }

    final custName = doc.clientName.isNotEmpty ? doc.clientName : (matchedCustomer.name.isNotEmpty ? matchedCustomer.name : 'Valued Client');
    final custEmail = doc.clientEmail.isNotEmpty ? doc.clientEmail : matchedCustomer.email;
    final custPhone = matchedCustomer.phone;
    final custAddress = matchedCustomer.billingAddress;

    pw.Widget? logoWidget;
    if (_profile.logoBase64.isNotEmpty) {
      try {
        var str = _profile.logoBase64.trim();
        if (str.contains(',')) {
          str = str.split(',').last;
        }
        final logoBytes = base64Decode(str);
        logoWidget = pw.Container(
          width: 100,
          height: 60,
          child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.contain),
        );
      } catch (_) {}
    }

    final tealColor = PdfColor.fromHex('#319795');
    final navyColor = PdfColor.fromHex('#0F2942');
    final rowBgColor = PdfColor.fromHex('#EDF2F7');

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        // Top Header: Logo + Document Title & Number
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoWidget != null) logoWidget else pw.SizedBox(),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  doc.kind == DocumentKind.invoice
                      ? AppTranslations.get('invoice', _lang)
                      : AppTranslations.get('quotation', _lang),
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: navyColor),
                ),
                pw.SizedBox(height: 2),
                pw.Text('Document #: ${doc.number}', style: const pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                pw.Text('Date: ${dateLabel(doc.issueDate)}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Divider(color: PdfColors.grey300, thickness: 1),
        pw.SizedBox(height: 12),

        // Billing Information (Left: User Company, Right: Bill To Customer)
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Left Column: User Company Details
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Billing Information:', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: navyColor)),
                  pw.SizedBox(height: 6),
                  _kvRow('Company Name:', _profile.businessName.isNotEmpty ? _profile.businessName : 'My Company'),
                  if (_profile.ownerName.isNotEmpty) _kvRow('Owner / Contact:', _profile.ownerName),
                  if (_profile.address.isNotEmpty) _kvRow('Company Address:', _profile.address),
                  if (_profile.phone.isNotEmpty) _kvRow('Phone Number:', _profile.phone),
                  if (_profile.email.isNotEmpty) _kvRow('Email:', _profile.email),
                  if (_profile.taxNumber.isNotEmpty) _kvRow('VAT / Tax No:', _profile.taxNumber),
                  if (_profile.website.isNotEmpty) _kvRow('Website:', _profile.website),
                ],
              ),
            ),
            pw.SizedBox(width: 20),
            // Right Column: Customer Details
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Bill To:', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: navyColor)),
                  pw.SizedBox(height: 6),
                  _kvRow('Customer Name:', custName),
                  if (custAddress.isNotEmpty) _kvRow('Billing Address:', custAddress),
                  if (custPhone.isNotEmpty) _kvRow('Phone:', custPhone),
                  if (custEmail.isNotEmpty) _kvRow('Email:', custEmail),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 20),

        // Service Details Section
        pw.Text('Service Details:', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: navyColor)),
        pw.SizedBox(height: 8),

        // Line Items Table
        pw.Table(
          columnWidths: {
            0: const pw.FixedColumnWidth(30),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(1.2),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(1.5),
          },
          children: [
            // Table Header
            pw.TableRow(
              decoration: pw.BoxDecoration(color: tealColor),
              children: [
                _tableHeaderCell('No'),
                _tableHeaderCell('Item Description'),
                _tableHeaderCell('Hours/Units', alignRight: true),
                _tableHeaderCell('Rate/Unit ($currency)', alignRight: true),
                _tableHeaderCell('Total ($currency)', alignRight: true),
              ],
            ),
            // Table Rows
            ...doc.lines.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final line = entry.value;
              final bg = idx % 2 == 1 ? rowBgColor : PdfColors.white;
              return pw.TableRow(
                decoration: pw.BoxDecoration(color: bg),
                children: [
                  _tableCell('$idx', bold: true),
                  _tableCell(line.description),
                  _tableCell(
                    line.quantity.toStringAsFixed(line.quantity.truncateToDouble() == line.quantity ? 0 : 2),
                    alignRight: true,
                  ),
                  _tableCell(CurrencyHelper.format(line.unitPrice, currency), alignRight: true),
                  _tableCell(CurrencyHelper.format(line.amount, currency), alignRight: true, bold: true),
                ],
              );
            }),
          ],
        ),
        pw.SizedBox(height: 12),

        // Totals Box (Dark Navy Background)
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: pw.BoxDecoration(
            color: navyColor,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            children: [
              _navyTotalRow('Subtotal', CurrencyHelper.format(doc.subtotal, currency)),
              if (doc.discount > 0)
                _navyTotalRow('Discount', '-${CurrencyHelper.format(doc.discount, currency)}'),
              _navyTotalRow('Sales Tax (${doc.taxPercent.toStringAsFixed(1)}%)', CurrencyHelper.format(doc.taxAmount, currency)),
              pw.Divider(color: PdfColors.grey600, height: 10),
              _navyTotalRow('Total Amount Due', CurrencyHelper.format(doc.total, currency), isLarge: true),
              if (doc.kind == DocumentKind.invoice && docPayments.isNotEmpty) ...[
                _navyTotalRow('Total Paid', '-${CurrencyHelper.format(totalPaid, currency)}'),
                _navyTotalRow('Remaining Balance', CurrencyHelper.format(remaining, currency), isLarge: true),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 20),

        // Bottom Payment & Terms Section (Two Columns)
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Left Column: Billing / Payment Information
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Billing Information:', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: navyColor)),
                  pw.SizedBox(height: 6),
                  _kvRow('Payment Method:', docPayments.isNotEmpty ? docPayments.last.method : 'Bank Transfer / EFT'),
                  _kvRow('Due Date:', dateLabel(doc.dueDate)),
                  if (_profile.bankDetails.isNotEmpty)
                    _kvRow('Bank Account:', _profile.bankDetails),
                ],
              ),
            ),
            pw.SizedBox(width: 20),
            // Right Column: Terms and Conditions
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Terms and Conditions:', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: navyColor)),
                  pw.SizedBox(height: 6),
                  if (_profile.paymentTerms.isNotEmpty)
                    pw.Text(_profile.paymentTerms, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800))
                  else ...[
                    pw.Text('• Payment is due upon receipt of this invoice.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
                    pw.Text('• Late payments may incur additional charges.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
                    if (_profile.businessName.isNotEmpty)
                      pw.Text('• Please make payments to ${_profile.businessName}.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
                  ],
                  if (doc.notes.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text('Notes: ${doc.notes}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
                  ],
                ],
              ),
            ),
          ],
        ),
        pw.Spacer(),

        // Signature & Footer Section
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            // Bottom Left Navy Contact Bar
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: pw.BoxDecoration(
                color: navyColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                children: [
                  if (_profile.phone.isNotEmpty) ...[
                    pw.Text(_profile.phone, style: const pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(width: 14),
                  ],
                  if (_profile.email.isNotEmpty)
                    pw.Text(_profile.email, style: const pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            // Bottom Right Signature Block
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('Date : ${dateLabel(DateTime.now())}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800)),
                pw.SizedBox(height: 24),
                pw.Container(
                  width: 140,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(top: pw.BorderSide(color: PdfColors.grey800, width: 1)),
                  ),
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Text(
                      _profile.businessName.isNotEmpty ? _profile.businessName : 'Authorized Signature',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: navyColor),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        if (!SubscriptionService.instance.isPro) ...[
          pw.SizedBox(height: 12),
          pw.Container(
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            child: pw.Text(
              'Generated with Ledgerly Free • Upgrade to Pro to remove this watermark',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey600,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    ));
    return pdf.save();
  }

  pw.Widget _kvRow(String label, String value) {
    if (value.trim().isEmpty) return pw.SizedBox();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label ',
              style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.grey900),
            ),
            pw.TextSpan(
              text: value,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _tableHeaderCell(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: const pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
      ),
    );
  }

  pw.Widget _tableCell(String text, {bool alignRight = false, bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: PdfColors.grey900,
        ),
      ),
    );
  }

  pw.Widget _navyTotalRow(String label, String value, {bool isLarge = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: isLarge ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: isLarge ? 11 : 9.5,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: isLarge ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: isLarge ? 11 : 9.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printPdf(BusinessDocument doc, {bool share = false}) async {
    try {
      final bytes = await _makePdf(doc);
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: '${doc.number}.pdf');
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${doc.number}.pdf');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF could not be prepared. Please try again.')),
        );
      }
    }
  }

  Future<void> _shareDocument(BusinessDocument doc) async {
    try {
      final bytes = await _makePdf(doc);
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${doc.number}.pdf',
        subject: '${doc.kind == DocumentKind.invoice ? 'Invoice' : 'Quotation'} ${doc.number}',
        body: 'Hi ${doc.clientName}, please find attached your ${doc.kind == DocumentKind.invoice ? 'invoice' : 'quotation'} ${doc.number} for ${CurrencyHelper.format(doc.total, doc.currencyCode)}. Thank you!',
      );
    } catch (_) {
      try {
        final bytes = await _makePdf(doc);
        await Share.shareXFiles(
          [XFile.fromData(bytes, mimeType: 'application/pdf', name: '${doc.number}.pdf')],
          subject: '${doc.kind == DocumentKind.invoice ? 'Invoice' : 'Quotation'} ${doc.number}',
          text: 'Hi ${doc.clientName}, here is your ${doc.kind == DocumentKind.invoice ? 'invoice' : 'quotation'} ${doc.number} for ${CurrencyHelper.format(doc.total, doc.currencyCode)}.',
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document could not be shared. Please try again.')),
          );
        }
      }
    }
  }

  Future<void> _deleteDocument(BusinessDocument doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(doc.kind == DocumentKind.invoice && _payments.any((p) => p.invoiceId == doc.id)
            ? 'Delete ${doc.number} for ${doc.clientName} and its linked payment records? This cannot be undone on this device.'
            : 'Delete ${doc.number} for ${doc.clientName}? This cannot be undone on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final previousDocuments = List<BusinessDocument>.from(_documents);
    final previousPayments = List<Payment>.from(_payments);
    setState(() {
      _documents.removeWhere((item) => item.id == doc.id);
      if (doc.kind == DocumentKind.invoice) {
        _payments.removeWhere((payment) => payment.invoiceId == doc.id);
      }
    });
    try {
      await _store.save(_documents);
      await _store.savePayments(_payments);
    } catch (_) {
      setState(() {
        _documents = previousDocuments;
        _payments = previousPayments;
      });
      try {
        await _store.save(_documents);
        await _store.savePayments(_payments);
      } catch (_) {
        // Best-effort rollback; the failure notification below is intentional.
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The document deletion could not be saved. Your previous records were restored where possible.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              _SideNavigation(
                section: _section,
                langCode: _lang,
                documentCount: _documents.length,
                onSelect: (value) => setState(() {
                  _section = value;
                  _filter = 'All';
                }),
              ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    wide: wide,
                    searchController: _searchController,
                    langCode: _lang,
                    onNewInvoice: () => _createDocument(DocumentKind.invoice),
                    onNewQuote: () => _createDocument(DocumentKind.quote),
                    onMenu: () => _openMobileNavigation(),
                  ),
                  Expanded(child: _buildBody(wide)),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: switch (_section) {
                'Invoices' => 1,
                'Quotes' => 2,
                'Analytics' => 3,
                'Settings' => 4,
                _ => 0,
              },
              onDestinationSelected: (index) => setState(() {
                _section = ['Overview', 'Invoices', 'Quotes', 'Analytics', 'Settings'][index];
                _filter = 'All';
              }),
              destinations: [
                NavigationDestination(
                    icon: const Icon(Icons.space_dashboard_outlined),
                    selectedIcon: const Icon(Icons.space_dashboard),
                    label: AppTranslations.get('overview', _lang)),
                NavigationDestination(
                    icon: const Icon(Icons.receipt_long_outlined),
                    selectedIcon: const Icon(Icons.receipt_long),
                    label: AppTranslations.get('invoices', _lang)),
                NavigationDestination(
                    icon: const Icon(Icons.request_quote_outlined),
                    selectedIcon: const Icon(Icons.request_quote),
                    label: AppTranslations.get('quotes', _lang)),
                const NavigationDestination(
                    icon: Icon(Icons.analytics_outlined),
                    selectedIcon: Icon(Icons.analytics),
                    label: 'Analytics'),
                NavigationDestination(
                    icon: const Icon(Icons.settings_outlined),
                    selectedIcon: const Icon(Icons.settings),
                    label: AppTranslations.get('settings', _lang)),
              ],
            ),
    );
  }

  void _openMobileNavigation() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFF59E0B)),
                title: const Text('Ledgerly Pro (PayPal Subscription)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
                subtitle: Text(SubscriptionService.instance.isPro ? 'Pro Active' : 'Upgrade for unlimited invoices & clean PDFs'),
                onTap: () {
                  Navigator.pop(context);
                  PaywallScreen.showPaywall(context);
                },
              ),
              const Divider(height: 1),
              ...[
                'Overview',
                'Invoices',
                'Quotes',
                'Follow-ups',
                'Clients',
                'Items',
                'Payments',
                'Analytics',
                'Settings'
              ]
                  .map((label) => ListTile(
                        leading: Icon(_iconFor(label)),
                        title: Text(label),
                        onTap: () {
                          Navigator.pop(context);
                          setState(() => _section = label);
                        },
                      )),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String label) => switch (label) {
        'Overview' => Icons.space_dashboard_outlined,
        'Invoices' => Icons.receipt_long_outlined,
        'Quotes' => Icons.request_quote_outlined,
        'Follow-ups' => Icons.notifications_none,
        'Clients' => Icons.people_outline,
        'Items' => Icons.inventory_2_outlined,
        'Payments' => Icons.payments_outlined,
        'Analytics' => Icons.analytics_outlined,
        _ => Icons.settings_outlined,
      };

  Widget _buildBody(bool wide) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_open_outlined, size: 42, color: _brand),
                const SizedBox(height: 12),
                const Text('Local data needs attention', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 18),
                OutlinedButton(onPressed: _loadAllData, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      );
    }
    if (_section == 'Analytics') {
      return AnalyticsScreen(
        documents: _documents,
        payments: _payments,
        currencyCode: _profile.currencyCode,
        langCode: _lang,
      );
    }
    if (_section == 'Settings') {
      return BusinessProfileScreen(
        profile: _profile,
        onProfileUpdated: (p) => setState(() => _profile = p),
        onDataImported: _loadAllData,
      );
    }
    if (_section == 'Clients') {
      return CustomersScreen(
        documents: _documents,
        customers: _customers,
        onCustomersUpdated: (c) => setState(() => _customers = c),
      );
    }
    if (_section == 'Items') {
      return ItemsScreen(
        items: _items,
        onItemsUpdated: (i) => setState(() => _items = i),
      );
    }
    if (_section == 'Payments') {
      return PaymentsScreen(
        documents: _documents,
        payments: _payments,
        onPaymentsUpdated: (p) => setState(() => _payments = p),
      );
    }
    if (_section == 'Overview') return _overview(wide);
    return _documentList(wide);
  }

  Widget _overview(bool wide) {
    final recent = _documents.toList()..sort((a, b) => b.issueDate.compareTo(a.issueDate));
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(wide ? 34 : 18, 24, wide ? 34 : 18, 100),
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
                          AppTranslations.get('businessOverview', _lang),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: _ink, fontSize: wide ? 30 : 25),
                        ),
                        const SizedBox(height: 6),
                        Text(AppTranslations.get('manageDesc', _lang)),
                      ],
                    ),
                  ),
                  if (wide)
                    FilledButton.icon(
                      onPressed: () => _createDocument(DocumentKind.invoice),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(AppTranslations.get('newInvoice', _lang)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth > 800
                      ? 4
                      : constraints.maxWidth > 520
                          ? 2
                          : 1;
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: columns == 1
                        ? 3.2
                        : columns == 2
                            ? 2.0
                            : 1.55,
                    children: [
                      _MetricCard(
                          title: AppTranslations.get('paidInvoices', _lang),
                          value: CurrencyHelper.format(_paidTotal, _profile.currencyCode),
                          icon: Icons.check_circle_outline,
                          color: const Color(0xFF0E9F6E),
                          caption: 'Marked as paid'),
                      _MetricCard(
                          title: AppTranslations.get('outstanding', _lang),
                          value: CurrencyHelper.format(_outstandingTotal, _profile.currencyCode),
                          icon: Icons.account_balance_wallet_outlined,
                          color: const Color(0xFFB54708),
                          caption: 'Invoices not yet paid'),
                      _MetricCard(
                          title: AppTranslations.get('openQuotes', _lang),
                          value: CurrencyHelper.format(_quoteTotal, _profile.currencyCode),
                          icon: Icons.request_quote_outlined,
                          color: _brand,
                          caption: 'Awaiting a decision'),
                      _MetricCard(
                          title: AppTranslations.get('savedClients', _lang),
                          value: _customers.length.toString(),
                          icon: Icons.people_outline,
                          color: const Color(0xFF475467),
                          caption: 'Client directory'),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppTranslations.get('recentDocuments', _lang),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _ink),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _section = 'Invoices'),
                    child: Text(AppTranslations.get('viewAll', _lang)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (recent.isEmpty)
                _EmptyState(
                  icon: Icons.description_outlined,
                  title: AppTranslations.get('workspaceReady', _lang),
                  message: AppTranslations.get('workspaceMessage', _lang),
                  actionLabel: AppTranslations.get('createFirstInvoice', _lang),
                  onAction: () => _createDocument(DocumentKind.invoice),
                  secondaryLabel: AppTranslations.get('createAQuote', _lang),
                  onSecondary: () => _createDocument(DocumentKind.quote),
                )
              else
                Card(
                  child: Column(
                    children: recent
                        .take(5)
                        .map((doc) => _DocumentRow(
                              document: doc,
                              onOpen: () => _createDocument(doc.kind, existing: doc),
                              onPdf: () => _printPdf(doc),
                              onShare: () => _shareDocument(doc),
                              onDelete: () => _deleteDocument(doc),
                            ))
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _documentList(bool wide) {
    final docs = _visibleDocuments;
    final title = _section == 'Follow-ups' ? 'Quote follow-ups' : _section;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(wide ? 34 : 18, 24, wide ? 34 : 18, 100),
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
                        Text(title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(color: _ink, fontSize: wide ? 30 : 25)),
                        const SizedBox(height: 6),
                        Text(
                          _section == 'Follow-ups'
                              ? 'Active quotes awaiting client response.'
                              : 'Manage and review your saved ${_section.toLowerCase()}.',
                        ),
                      ],
                    ),
                  ),
                  if (_section == 'Quotes')
                    FilledButton.icon(
                      onPressed: () => _createDocument(DocumentKind.quote),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(AppTranslations.get('newQuote', _lang)),
                    ),
                  if (_section == 'Invoices')
                    FilledButton.icon(
                      onPressed: () => _createDocument(DocumentKind.invoice),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(AppTranslations.get('newInvoice', _lang)),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String>(
                    value: _filter,
                    underline: const SizedBox.shrink(),
                    items: const [
                      'All',
                      'Draft',
                      'Sent',
                      'Pending',
                      'Paid',
                      'Overdue',
                      'Accepted',
                      'Declined',
                      'Void'
                    ]
                        .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                        .toList(),
                    onChanged: (value) => setState(() => _filter = value ?? 'All'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (docs.isEmpty)
                _EmptyState(
                  icon: _section == 'Quotes' ? Icons.request_quote_outlined : Icons.receipt_long_outlined,
                  title: _query.isNotEmpty ? 'No matching documents' : 'Nothing here yet',
                  message: _query.isNotEmpty
                      ? 'Try another search term or clear the status filter.'
                      : _section == 'Follow-ups'
                          ? 'Open quotes will appear here after you create them.'
                          : 'Create a document to see it listed here.',
                  actionLabel: _section == 'Quotes'
                      ? 'Create a quote'
                      : _section == 'Follow-ups'
                          ? 'Create a quote'
                          : 'Create an invoice',
                  onAction: () => _createDocument(
                    _section == 'Quotes' || _section == 'Follow-ups' ? DocumentKind.quote : DocumentKind.invoice,
                  ),
                )
              else
                Card(
                  child: Column(
                    children: docs
                        .map(
                          (doc) => _DocumentRow(
                            document: doc,
                            onOpen: () => _createDocument(doc.kind, existing: doc),
                            onPdf: () => _printPdf(doc),
                            onShare: () => _shareDocument(doc),
                            onDelete: () => _deleteDocument(doc),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.wide,
    required this.searchController,
    required this.langCode,
    required this.onNewInvoice,
    required this.onNewQuote,
    required this.onMenu,
  });

  final bool wide;
  final TextEditingController searchController;
  final String langCode;
  final VoidCallback onNewInvoice;
  final VoidCallback onNewQuote;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: wide ? 34 : 18, vertical: 16),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
        child: Row(
          children: [
            if (!wide) IconButton(onPressed: onMenu, icon: const Icon(Icons.menu_rounded)),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 21),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ledgerly',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 19, color: _ink, letterSpacing: -0.5)),
                Text('GLOBAL INVOICING & ANALYTICS',
                    style: TextStyle(
                        fontSize: 8, letterSpacing: 1.1, color: _muted, fontWeight: FontWeight.w700)),
              ],
            ),
            const Spacer(),
            ListenableBuilder(
              listenable: SubscriptionService.instance,
              builder: (context, _) {
                final isPro = SubscriptionService.instance.isPro;
                return InkWell(
                  onTap: () => PaywallScreen.showPaywall(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isPro ? const Color(0xFFFEF3C7) : const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isPro ? const Color(0xFFF59E0B) : const Color(0xFF6366F1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.workspace_premium_rounded,
                          color: isPro ? const Color(0xFFD97706) : const Color(0xFF4F46E5),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isPro ? 'PRO' : 'UPGRADE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isPro ? const Color(0xFFB45309) : const Color(0xFF4F46E5),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (wide)
              SizedBox(
                width: 260,
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: AppTranslations.get('searchDocuments', langCode),
                    prefixIcon: const Icon(Icons.search, size: 19),
                    isDense: true,
                  ),
                ),
              ),
            if (wide) const SizedBox(width: 12),
            if (wide)
              PopupMenuButton<String>(
                tooltip: AppTranslations.get('create', langCode),
                onSelected: (value) => value == 'invoice' ? onNewInvoice() : onNewQuote(),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'invoice', child: Text(AppTranslations.get('newInvoice', langCode))),
                  PopupMenuItem(value: 'quote', child: Text(AppTranslations.get('newQuote', langCode))),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 18, color: Colors.white),
                      const SizedBox(width: 7),
                      Text(AppTranslations.get('create', langCode),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              )
            else
              IconButton(
                tooltip: AppTranslations.get('newInvoice', langCode),
                onPressed: onNewInvoice,
                icon: const Icon(Icons.add_circle, color: _brand, size: 28),
              ),
          ],
        ),
      );
}

class _SideNavigation extends StatelessWidget {
  const _SideNavigation({
    required this.section,
    required this.langCode,
    required this.documentCount,
    required this.onSelect,
  });

  final String section;
  final String langCode;
  final int documentCount;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Container(
        width: 245,
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
        decoration: const BoxDecoration(color: Colors.white, border: Border(right: BorderSide(color: _line))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 16, 12, 20),
              child: Text('WORKSPACE',
                  style: TextStyle(
                      fontSize: 10, color: _muted, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            ),
            ...[
              ('Overview', Icons.space_dashboard_outlined),
              ('Invoices', Icons.receipt_long_outlined),
              ('Quotes', Icons.request_quote_outlined),
              ('Follow-ups', Icons.notifications_none),
              ('Clients', Icons.people_outline),
              ('Items', Icons.inventory_2_outlined),
              ('Payments', Icons.payments_outlined),
              ('Analytics', Icons.analytics_outlined),
              ('Settings', Icons.settings_outlined),
            ].map((item) {
              final selected = section == item.$1;
              final label = item.$1 == 'Analytics'
                  ? 'Analytics'
                  : item.$1 == 'Follow-ups'
                      ? AppTranslations.get('followUps', langCode)
                      : AppTranslations.get(item.$1.toLowerCase(), langCode);
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  selected: selected,
                  selectedTileColor: const Color(0xFFEEEDFF),
                  selectedColor: _brand,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                  leading: Icon(item.$2, size: 20),
                  title: Text(label,
                      style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                  onTap: () => onSelect(item.$1),
                ),
              );
            }),
            const Spacer(),
            ListenableBuilder(
              listenable: SubscriptionService.instance,
              builder: (context, _) {
                final isPro = SubscriptionService.instance.isPro;
                final remaining = SubscriptionService.instance.remainingFreeDocuments(documentCount);
                final used = documentCount > 5 ? 5 : documentCount;

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isPro ? const Color(0xFFF0FDF4) : const Color(0xFFF7F7FF),
                    border: Border.all(
                      color: isPro ? const Color(0xFFBBF7D0) : const Color(0xFFE8E6FF),
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isPro ? Icons.workspace_premium_rounded : Icons.shield_outlined,
                            color: isPro ? const Color(0xFF16A34A) : _brand,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isPro ? 'Ledgerly Pro' : 'Free Plan',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isPro ? const Color(0xFF166534) : _ink,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (isPro) ...[
                        const Text(
                          'Unlimited invoices & quotes, no watermark, PayPal subscribed.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF166534), height: 1.4),
                        ),
                      ] else ...[
                        Text(
                          '$used of 5 free documents used ($remaining left)',
                          style: const TextStyle(fontSize: 11, color: _muted),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (used / 5).clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: const Color(0xFFE2E8F0),
                            color: _brand,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFFC439), // PayPal Gold
                              foregroundColor: const Color(0xFF003087),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => PaywallScreen.showPaywall(context),
                            child: const Text('Upgrade Pro', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.title,
      required this.value,
      required this.icon,
      required this.color,
      required this.caption});

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String caption;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, color: color, size: 18)),
                  const Spacer(),
                  const Icon(Icons.more_horiz, color: Color(0xFFB0B7C5), size: 20),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -.6)),
                  const SizedBox(height: 3),
                  Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _ink)),
                  Text(caption, style: const TextStyle(fontSize: 10, color: _muted)),
                ],
              ),
            ],
          ),
        ),
      );
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow(
      {required this.document, required this.onOpen, required this.onPdf, required this.onShare, required this.onDelete});

  final BusinessDocument document;
  final VoidCallback onOpen;
  final VoidCallback onPdf;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  Color get _statusColor => switch (document.status) {
        'Paid' || 'Accepted' => const Color(0xFF027A48),
        'Overdue' || 'Declined' => const Color(0xFFB42318),
        'Sent' || 'Pending' => const Color(0xFFB54708),
        _ => const Color(0xFF667085),
      };

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: const Color(0xFFF0F2FF), borderRadius: BorderRadius.circular(11)),
                  child: Icon(
                      document.kind == DocumentKind.invoice
                          ? Icons.receipt_long_outlined
                          : Icons.request_quote_outlined,
                      color: _brand)),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        document.clientName.isEmpty ? 'Unnamed client' : document.clientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
                    const SizedBox(height: 4),
                    Text('${document.number} • ${dateLabel(document.issueDate)}',
                        style: const TextStyle(fontSize: 11, color: _muted)),
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width > 620)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _StatusPill(label: document.status, color: _statusColor),
                  ),
                ),
              Text(CurrencyHelper.format(document.total, document.currencyCode),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
              IconButton(
                tooltip: 'Share via WhatsApp, Email, etc.',
                icon: const Icon(Icons.share_rounded, size: 20, color: _brand),
                onPressed: onShare,
              ),
              PopupMenuButton<String>(
                tooltip: 'Document actions',
                onSelected: (value) {
                  if (value == 'edit') onOpen();
                  if (value == 'pdf') onPdf();
                  if (value == 'share') onShare();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'pdf', child: Text('View / Print PDF')),
                  PopupMenuItem(value: 'share', child: Text('Share via Email / WhatsApp')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                        color: _brand.withValues(alpha: .08), borderRadius: BorderRadius.circular(16)),
                    child: Icon(icon, color: _brand, size: 28),
                  ),
                  const SizedBox(height: 16),
                  Text(title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
                  const SizedBox(height: 6),
                  Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.4)),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: onAction,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(actionLabel),
                      ),
                      if (secondaryLabel != null && onSecondary != null)
                        OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class DocumentEditorDialog extends StatefulWidget {
  const DocumentEditorDialog({
    super.key,
    required this.kind,
    required this.nextNumber,
    this.existing,
    this.customers = const [],
    this.items = const [],
    required this.currencyCode,
    required this.langCode,
    this.existingNumbers = const [],
  });

  final DocumentKind kind;
  final String nextNumber;
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

  double get _subtotal => (_lines.fold<double>(0.0, (sum, line) => sum + line.amount) * 100).roundToDouble() / 100;
  double get _discountValue {
    final value = double.tryParse(_discount.text) ?? 0;
    if (!value.isFinite || value <= 0) return 0;
    return value.clamp(0.0, _subtotal).toDouble();
  }
  double get _taxValue {
    final value = double.tryParse(_tax.text) ?? 0;
    return value.isFinite ? value.clamp(0.0, 100.0).toDouble() : 0.0;
  }
  double get _total {
    final taxable = (_subtotal - _discountValue).clamp(0.0, double.infinity).toDouble();
    final tax = (taxable * _taxValue / 100 * 100).roundToDouble() / 100;
    return ((taxable + tax) * 100).roundToDouble() / 100;
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
              ? const Center(child: Text('No saved clients. Add clients in Clients tab.'))
              : ListView.separated(
                  itemCount: widget.customers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final c = widget.customers[idx];
                    return ListTile(
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(c.email.isNotEmpty ? c.email : c.phone),
                      onTap: () => Navigator.pop(ctx, c),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );

    if (selected != null) {
      setState(() {
        _client.text = selected.name;
        _email.text = selected.email;
        _customerId = selected.id;
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
              ? const Center(child: Text('No saved items. Add products/services in Items tab.'))
              : ListView.separated(
                  itemCount: widget.items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final item = widget.items[idx];
                    return ListTile(
                      title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${item.category} • ${CurrencyHelper.format(item.unitPrice, _currency)} / ${item.unit}'),
                      onTap: () => Navigator.pop(ctx, item),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );

    if (selected != null) {
      setState(() {
        line.description.text = selected.name;
        line.price.text = selected.unitPrice.toStringAsFixed(2);
        _tax.text = selected.taxRate.toStringAsFixed(1);
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_dueDate.isBefore(DateTime(_issueDate.year, _issueDate.month, _issueDate.day))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Due date cannot be earlier than the issue date.')),
      );
      return;
    }
    final old = widget.existing;
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
            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
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
                                    child: Text('Document details', style: Theme.of(context).textTheme.titleLarge),
                                  ),
                                  if (widget.customers.isNotEmpty)
                                    OutlinedButton.icon(
                                      onPressed: _pickCustomer,
                                      icon: const Icon(Icons.person_search_outlined, size: 16),
                                      label: const Text('Pick saved client'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final cols = constraints.maxWidth > 650 ? 2 : 1;
                                  return _ResponsiveFields(columns: cols, children: [
                                    TextFormField(
                                      controller: _number,
                                      decoration: const InputDecoration(labelText: 'Document number'),
                                      validator: (v) {
                                        final value = v?.trim() ?? '';
                                        if (value.isEmpty) return 'Required';
                                        if (widget.existingNumbers.contains(value.toLowerCase())) {
                                          return 'This document number is already in use';
                                        }
                                        return null;
                                      },
                                    ),
                                    DropdownButtonFormField<String>(
                                      initialValue: _status,
                                      decoration: const InputDecoration(labelText: 'Status'),
                                      items: (widget.kind == DocumentKind.invoice
                                              ? ['Draft', 'Sent', 'Pending', 'Paid', 'Overdue', 'Void']
                                              : ['Draft', 'Sent', 'Pending', 'Accepted', 'Declined'])
                                          .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                                          .toList(),
                                      onChanged: (value) => setState(() => _status = value ?? 'Draft'),
                                    ),
                                    TextFormField(
                                      controller: _client,
                                      decoration: const InputDecoration(labelText: 'Client / business name'),
                                      validator: (v) => v == null || v.trim().isEmpty ? 'Enter a client name' : null,
                                    ),
                                    TextFormField(
                                      controller: _email,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: const InputDecoration(labelText: 'Client email (optional)'),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) return null;
                                        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())
                                            ? null
                                            : 'Enter a valid email';
                                      },
                                    ),
                                    DropdownButtonFormField<String>(
                                      initialValue: _currency,
                                      decoration: const InputDecoration(labelText: 'Currency'),
                                      items: CurrencyHelper.currencies
                                          .map((c) => DropdownMenuItem(value: c.code, child: Text('${c.code} (${c.symbol})')))
                                          .toList(),
                                      onChanged: (value) => setState(() => _currency = value ?? 'USD'),
                                    ),
                                    _DateButton(
                                      label: 'Issue date',
                                      date: _issueDate,
                                      onTap: () async {
                                        final date = await _chooseDate(_issueDate);
                                        if (date != null) setState(() => _issueDate = date);
                                      },
                                    ),
                                    _DateButton(
                                      label: 'Due date',
                                      date: _dueDate,
                                      onTap: () async {
                                        final date = await _chooseDate(_dueDate);
                                        if (date != null) setState(() => _dueDate = date);
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
                                    child: Text('Line items', style: Theme.of(context).textTheme.titleLarge),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => setState(() => _lines.add(_LineDraft())),
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
                                                style: const TextStyle(fontWeight: FontWeight.w700)),
                                          ),
                                          if (widget.items.isNotEmpty)
                                            TextButton.icon(
                                              onPressed: () => _pickCatalogItem(line),
                                              icon: const Icon(Icons.inventory_2_outlined, size: 15),
                                              label: const Text('Catalog Item'),
                                            ),
                                          if (_lines.length > 1)
                                            IconButton(
                                              tooltip: 'Remove item',
                                              onPressed: () => setState(() {
                                                line.dispose();
                                                _lines.remove(line);
                                              }),
                                              icon: const Icon(Icons.delete_outline, color: Color(0xFFB42318)),
                                            ),
                                        ],
                                      ),
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          final cols = constraints.maxWidth > 650 ? 3 : 1;
                                          return _ResponsiveFields(columns: cols, children: [
                                            TextFormField(
                                              controller: line.description,
                                              decoration: const InputDecoration(labelText: 'Description'),
                                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                                            ),
                                            TextFormField(
                                              controller: line.quantity,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              decoration: const InputDecoration(labelText: 'Quantity'),
                                              validator: (v) {
                                                final n = double.tryParse(v ?? '');
                                                return n == null || !n.isFinite || n <= 0 || n > 1e9
                                                    ? 'Enter a quantity above zero (maximum 1,000,000,000)'
                                                    : null;
                                              },
                                              onChanged: (_) => setState(() {}),
                                            ),
                                            TextFormField(
                                              controller: line.price,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              decoration: const InputDecoration(labelText: 'Unit price'),
                                              validator: (v) {
                                                final n = double.tryParse(v ?? '');
                                                return n == null || !n.isFinite || n < 0 || n > 1e12
                                                    ? 'Enter a valid price (maximum 1,000,000,000,000)'
                                                    : null;
                                              },
                                              onChanged: (_) => setState(() {}),
                                            ),
                                          ]);
                                        },
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          'Line total: ${CurrencyHelper.format(line.amount, _currency)}',
                                          style: const TextStyle(fontWeight: FontWeight.w700),
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
                              Text('Totals and terms', style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 16),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final cols = constraints.maxWidth > 650 ? 2 : 1;
                                  return _ResponsiveFields(columns: cols, children: [
                                    TextFormField(
                                      controller: _discount,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(labelText: 'Discount amount'),
                                      onChanged: (_) => setState(() {}),
                                      validator: (v) {
                                        final n = double.tryParse(v ?? '');
                                        return n == null || !n.isFinite || n < 0 ? 'Enter zero or more' : null;
                                      },
                                    ),
                                    TextFormField(
                                      controller: _tax,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(labelText: 'Tax rate (%)'),
                                      onChanged: (_) => setState(() {}),
                                      validator: (v) {
                                        final n = double.tryParse(v ?? '');
                                        return n == null || !n.isFinite || n < 0 || n > 100 ? 'Use 0–100%' : null;
                                      },
                                    ),
                                  ]);
                                },
                              ),
                              const SizedBox(height: 16),
                              _TotalLine(label: 'Subtotal', value: CurrencyHelper.format(_subtotal, _currency)),
                              _TotalLine(label: 'Discount', value: '-${CurrencyHelper.format(_discountValue, _currency)}'),
                              _TotalLine(
                                  label: 'Tax',
                                  value: CurrencyHelper.format(_total - (_subtotal - _discountValue), _currency)),
                              const Divider(height: 24),
                              _TotalLine(label: 'Total due', value: CurrencyHelper.format(_total, _currency), bold: true),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _notes,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                    labelText: 'Notes and terms', alignLabelWithHint: true),
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
  _LineDraft({String? id, String description = '', String quantity = '1', String price = '0'})
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
    final value = quantityValue * priceValue;
    return value.isFinite ? (value * 100).roundToDouble() / 100 : 0.0;
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
              .map((child) => Padding(padding: const EdgeInsets.only(bottom: 12), child: child))
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
                for (var j = i; j < (i + columns < children.length ? i + columns : children.length); j++) ...[
                  if (j > i) const SizedBox(width: 12),
                  Expanded(child: children[j]),
                ],
                if ((children.length - i) < columns)
                  for (var pad = 0; pad < columns - (children.length - i); pad++)
                    const Expanded(child: SizedBox()),
              ],
            ),
          ),
      ],
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.date, required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
              labelText: label, suffixIcon: const Icon(Icons.calendar_month_outlined, size: 18)),
          child: Text(dateLabel(date)),
        ),
      );
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({required this.label, required this.value, this.bold = false});
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
                      color: bold ? _ink : _muted, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
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
