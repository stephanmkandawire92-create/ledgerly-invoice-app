import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/business_document.dart';
import '../models/business_profile.dart';
import '../models/currency_helper.dart';
import '../models/customer.dart';
import '../models/item.dart';
import '../models/payment.dart';
import '../services/app_translations.dart';
import '../services/document_store.dart';
import 'analytics_screen.dart';
import 'business_profile_screen.dart';
import 'document_editor_screen.dart';
import 'customers_screen.dart';
import 'items_screen.dart';
import 'payments_screen.dart';
import '../services/subscription_service.dart';
import '../widgets/dashboard_components.dart';
import 'paywall_screen.dart';

const _brand = Color(0xFF4F46E5);
const _ink = Color(0xFF172033);

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
        _loadError =
            'Saved data could not be read. Your local data was not overwritten.';
      });
    }
  }

  Future<bool> _persist() async {
    try {
      await _store.save(_documents);
      if (mounted) setState(() => _loadError = null);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not save to this device. Check available storage and try again.')),
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
                  ? doc.kind == DocumentKind.quote &&
                      !['Accepted', 'Declined'].contains(doc.status)
                  : true;
      final status = effectiveInvoiceStatus(doc, _payments);
      final filterMatch = _filter == 'All' || status == _filter;
      final queryMatch = _query.isEmpty ||
          [doc.number, doc.clientName, doc.clientEmail, status]
              .any((value) => value.toLowerCase().contains(_query));
      return sectionMatch && filterMatch && queryMatch;
    }).toList()
      ..sort((a, b) => b.issueDate.compareTo(a.issueDate));
  }

  double get _paidTotal => _payments.fold<double>(0, (sum, payment) {
        BusinessDocument? invoice;
        for (final d in _documents) {
          if (d.id == payment.invoiceId && d.kind == DocumentKind.invoice) {
            invoice = d;
            break;
          }
        }
        if (invoice == null ||
            invoice.currencyCode.toUpperCase() !=
                _profile.currencyCode.toUpperCase() ||
            !payment.amount.isFinite ||
            payment.amount <= 0) {
          return sum;
        }
        return sum + payment.amount;
      });

  double get _outstandingTotal => _documents
          .where((doc) =>
              doc.kind == DocumentKind.invoice &&
              doc.currencyCode.toUpperCase() ==
                  _profile.currencyCode.toUpperCase() &&
              !['Draft', 'Void'].contains(doc.status))
          .fold<double>(0, (sum, doc) {
        final paid = _payments
            .where((p) =>
                p.invoiceId == doc.id && p.amount.isFinite && p.amount > 0)
            .fold<double>(0, (amount, p) => amount + p.amount);
        return sum + (doc.total - paid).clamp(0.0, doc.total).toDouble();
      });

  double get _quoteTotal => _documents
      .where((doc) =>
          doc.kind == DocumentKind.quote &&
          doc.currencyCode.toUpperCase() ==
              _profile.currencyCode.toUpperCase() &&
          !['Accepted', 'Declined'].contains(doc.status))
      .fold(0, (sum, doc) => sum + doc.total);

  Future<void> _createDocument(DocumentKind kind,
      {BusinessDocument? existing}) async {
    if (_loadError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Resolve the local data issue before creating or changing records.')),
      );
      return;
    }
    if (existing == null &&
        !SubscriptionService.instance.canCreateDocument(_documents.length)) {
      final upgraded = await PaywallScreen.showPaywall(
        context,
        featurePrompt:
            'You have reached the Free Tier limit of 5 documents. Subscribe with PayPal to unlock unlimited quotes and invoices.',
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
        currencyLocked: kind == DocumentKind.invoice &&
            existing != null &&
            _payments.any((payment) => payment.invoiceId == existing.id),
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
    if (kind == DocumentKind.invoice) {
      result.status = effectiveInvoiceStatus(result, _payments);
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
        SnackBar(
            content: Text(
                '${kind == DocumentKind.invoice ? 'Invoice' : 'Quote'} saved on this device.')),
      );
    }
  }

  String _nextNumber(DocumentKind kind) {
    final prefix = kind == DocumentKind.invoice
        ? _profile.invoicePrefix
        : _profile.quotePrefix;
    final stem = '$prefix${DateTime.now().year}-';
    var highest = 0;
    for (final doc in _documents
        .where((d) => d.kind == kind && d.number.startsWith(stem))) {
      final sequence = int.tryParse(doc.number.substring(stem.length));
      if (sequence != null && sequence > highest) highest = sequence;
    }
    return '$stem${(highest + 1).toString().padLeft(4, '0')}';
  }

  Future<Uint8List> _makePdf(BusinessDocument doc) async {
    final pdf = pw.Document();
    final currency = doc.currencyCode;
    final docPayments = _payments
        .where((payment) => payment.invoiceId == doc.id)
        .toList()
      ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    if (doc.kind != DocumentKind.invoice && docPayments.isNotEmpty) {
      throw const FormatException('Quotes cannot contain recorded invoice payments.');
    }
    if (docPayments.any((payment) =>
        !payment.amount.isFinite ||
        payment.amount <= 0 ||
        roundMoney(payment.amount) != payment.amount)) {
      throw const FormatException('This document has invalid payment records.');
    }
    final totalPaid =
        roundMoney(docPayments.fold(0.0, (sum, payment) => sum + payment.amount));
    if (totalPaid > doc.total + 0.004) {
      throw const FormatException(
          'Recorded payments exceed this invoice total. Correct the payment records before creating a PDF.');
    }
    final remaining =
        (doc.total - totalPaid).clamp(0.0, double.infinity).toDouble();

    // Find matching customer details
    Customer? matchedCustomer;
    if (doc.customerId.isNotEmpty) {
      matchedCustomer = _customers.firstWhere((c) => c.id == doc.customerId,
          orElse: () => Customer(id: '', name: ''));
    }
    if (matchedCustomer == null || matchedCustomer.name.isEmpty) {
      matchedCustomer = _customers.firstWhere(
        (c) => c.name.toLowerCase() == doc.clientName.toLowerCase(),
        orElse: () =>
            Customer(id: '', name: doc.clientName, email: doc.clientEmail),
      );
    }

    final custName = doc.clientName.isNotEmpty
        ? doc.clientName
        : (matchedCustomer.name.isNotEmpty
            ? matchedCustomer.name
            : 'Valued Client');
    final custEmail =
        doc.clientEmail.isNotEmpty ? doc.clientEmail : matchedCustomer.email;
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
                  style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: navyColor),
                ),
                pw.SizedBox(height: 2),
                pw.Text('Document #: ${doc.number}',
                    style: const pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800)),
                pw.Text('Date: ${dateLabel(doc.issueDate)}',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey700)),
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
                  pw.Text('Billing Information:',
                      style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: navyColor)),
                  pw.SizedBox(height: 6),
                  _kvRow(
                      'Company Name:',
                      _profile.businessName.isNotEmpty
                          ? _profile.businessName
                          : 'My Company'),
                  if (_profile.ownerName.isNotEmpty)
                    _kvRow('Owner / Contact:', _profile.ownerName),
                  if (_profile.address.isNotEmpty)
                    _kvRow('Company Address:', _profile.address),
                  if (_profile.phone.isNotEmpty)
                    _kvRow('Phone Number:', _profile.phone),
                  if (_profile.email.isNotEmpty)
                    _kvRow('Email:', _profile.email),
                  if (_profile.taxNumber.isNotEmpty)
                    _kvRow('VAT / Tax No:', _profile.taxNumber),
                  if (_profile.website.isNotEmpty)
                    _kvRow('Website:', _profile.website),
                ],
              ),
            ),
            pw.SizedBox(width: 20),
            // Right Column: Customer Details
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Bill To:',
                      style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: navyColor)),
                  pw.SizedBox(height: 6),
                  _kvRow('Customer Name:', custName),
                  if (custAddress.isNotEmpty)
                    _kvRow('Billing Address:', custAddress),
                  if (custPhone.isNotEmpty) _kvRow('Phone:', custPhone),
                  if (custEmail.isNotEmpty) _kvRow('Email:', custEmail),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 20),

        // Service Details Section
        pw.Text('Service Details:',
            style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: navyColor)),
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
                    line.quantity.toStringAsFixed(
                        line.quantity.truncateToDouble() == line.quantity
                            ? 0
                            : 2),
                    alignRight: true,
                  ),
                  _tableCell(CurrencyHelper.format(line.unitPrice, currency),
                      alignRight: true),
                  _tableCell(CurrencyHelper.format(line.amount, currency),
                      alignRight: true, bold: true),
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
              _navyTotalRow(
                  'Subtotal', CurrencyHelper.format(doc.subtotal, currency)),
              if (doc.safeDiscount > 0)
                _navyTotalRow('Discount',
                    '-${CurrencyHelper.format(doc.safeDiscount, currency)}'),
              _navyTotalRow('Sales Tax (${doc.safeTaxPercent.toStringAsFixed(1)}%)',
                  CurrencyHelper.format(doc.taxAmount, currency)),
              pw.Divider(color: PdfColors.grey600, height: 10),
              _navyTotalRow('Total Amount Due',
                  CurrencyHelper.format(doc.total, currency),
                  isLarge: true),
              if (doc.kind == DocumentKind.invoice &&
                  docPayments.isNotEmpty) ...[
                _navyTotalRow('Total Paid',
                    '-${CurrencyHelper.format(totalPaid, currency)}'),
                _navyTotalRow('Remaining Balance',
                    CurrencyHelper.format(remaining, currency),
                    isLarge: true),
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
                  pw.Text('Billing Information:',
                      style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: navyColor)),
                  pw.SizedBox(height: 6),
                  _kvRow(
                      'Payment Method:',
                      docPayments.isNotEmpty
                          ? docPayments.last.method
                          : 'Bank Transfer / EFT'),
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
                  pw.Text('Terms and Conditions:',
                      style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: navyColor)),
                  pw.SizedBox(height: 6),
                  if (_profile.paymentTerms.isNotEmpty)
                    pw.Text(_profile.paymentTerms,
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey800))
                  else ...[
                    pw.Text('• Payment is due upon receipt of this invoice.',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey800)),
                    pw.Text('• Late payments may incur additional charges.',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey800)),
                    if (_profile.businessName.isNotEmpty)
                      pw.Text(
                          '• Please make payments to ${_profile.businessName}.',
                          style: const pw.TextStyle(
                              fontSize: 9, color: PdfColors.grey800)),
                  ],
                  if (doc.notes.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text('Notes: ${doc.notes}',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey800)),
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
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: pw.BoxDecoration(
                color: navyColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                children: [
                  if (_profile.phone.isNotEmpty) ...[
                    pw.Text(_profile.phone,
                        style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(width: 14),
                  ],
                  if (_profile.email.isNotEmpty)
                    pw.Text(_profile.email,
                        style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            // Bottom Right Signature Block
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('Date : ${dateLabel(DateTime.now())}',
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey800)),
                pw.SizedBox(height: 24),
                pw.Container(
                  width: 140,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                        top: pw.BorderSide(color: PdfColors.grey800, width: 1)),
                  ),
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Text(
                      _profile.businessName.isNotEmpty
                          ? _profile.businessName
                          : 'Authorized Signature',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: navyColor),
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
              border: pw.Border(
                  top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
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
              style: const pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                  color: PdfColors.grey900),
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
        style: const pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
            fontSize: 9),
      ),
    );
  }

  pw.Widget _tableCell(String text,
      {bool alignRight = false, bool bold = false}) {
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
        await Printing.layoutPdf(
            onLayout: (_) async => bytes, name: '${doc.number}.pdf');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('PDF could not be prepared. Please try again.')),
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
        subject:
            '${doc.kind == DocumentKind.invoice ? 'Invoice' : 'Quotation'} ${doc.number}',
        body:
            'Hi ${doc.clientName}, please find attached your ${doc.kind == DocumentKind.invoice ? 'invoice' : 'quotation'} ${doc.number} for ${CurrencyHelper.format(doc.total, doc.currencyCode)}. Thank you!',
      );
    } catch (_) {
      try {
        final bytes = await _makePdf(doc);
        await Share.shareXFiles(
          [
            XFile.fromData(bytes,
                mimeType: 'application/pdf', name: '${doc.number}.pdf')
          ],
          subject:
              '${doc.kind == DocumentKind.invoice ? 'Invoice' : 'Quotation'} ${doc.number}',
          text:
              'Hi ${doc.clientName}, here is your ${doc.kind == DocumentKind.invoice ? 'invoice' : 'quotation'} ${doc.number} for ${CurrencyHelper.format(doc.total, doc.currencyCode)}.',
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Document could not be shared. Please try again.')),
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
        content: Text(doc.kind == DocumentKind.invoice &&
                _payments.any((p) => p.invoiceId == doc.id)
            ? 'Delete ${doc.number} for ${doc.clientName} and its linked payment records? This cannot be undone on this device.'
            : 'Delete ${doc.number} for ${doc.clientName}? This cannot be undone on this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB42318)),
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
      await _store.saveDocumentsAndPayments(_documents, _payments);
    } catch (_) {
      setState(() {
        _documents = previousDocuments;
        _payments = previousPayments;
      });
      try {
        await _store.saveDocumentsAndPayments(_documents, _payments);
      } catch (_) {
        // Best-effort rollback; the failure notification below is intentional.
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'The document deletion could not be saved. Your previous records were restored where possible.')),
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
              LedgerlySideNavigation(
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
                  LedgerlyTopBar(
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
                _section = [
                  'Overview',
                  'Invoices',
                  'Quotes',
                  'Analytics',
                  'Settings'
                ][index];
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
                leading: const Icon(Icons.workspace_premium_rounded,
                    color: Color(0xFFF59E0B)),
                title: const Text('Ledgerly Pro (PayPal Subscription)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF4F46E5))),
                subtitle: Text(SubscriptionService.instance.isPro
                    ? 'Pro Active'
                    : 'Upgrade for unlimited invoices & clean PDFs'),
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
              ].map((label) => ListTile(
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
                const Text('Local data needs attention',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 18),
                OutlinedButton(
                    onPressed: _loadAllData, child: const Text('Try again')),
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
        currencyCode: _profile.currencyCode,
        onCustomersUpdated: (c) => setState(() => _customers = c),
      );
    }
    if (_section == 'Items') {
      return ItemsScreen(
        items: _items,
        currencyCode: _profile.currencyCode,
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
    final recent = _documents.toList()
      ..sort((a, b) => b.issueDate.compareTo(a.issueDate));
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.phone_android_outlined,
                        color: Color(0xFF4338CA), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Semantics(
                        label: AppTranslations.get('localStorageNotice', _lang),
                        child: Text(
                          AppTranslations.get('localStorageNotice', _lang),
                          style: const TextStyle(
                            color: Color(0xFF312E81),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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
                      LedgerlyMetricCard(
                          title: AppTranslations.get('paidInvoices', _lang),
                          value: CurrencyHelper.format(
                              _paidTotal, _profile.currencyCode),
                          icon: Icons.check_circle_outline,
                          color: const Color(0xFF0E9F6E),
                          caption: 'Marked as paid'),
                      LedgerlyMetricCard(
                          title: AppTranslations.get('outstanding', _lang),
                          value: CurrencyHelper.format(
                              _outstandingTotal, _profile.currencyCode),
                          icon: Icons.account_balance_wallet_outlined,
                          color: const Color(0xFFB54708),
                          caption: 'Invoices not yet paid'),
                      LedgerlyMetricCard(
                          title: AppTranslations.get('openQuotes', _lang),
                          value: CurrencyHelper.format(
                              _quoteTotal, _profile.currencyCode),
                          icon: Icons.request_quote_outlined,
                          color: _brand,
                          caption: 'Awaiting a decision'),
                      LedgerlyMetricCard(
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
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: _ink),
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
                LedgerlyEmptyState(
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
                        .map((doc) => LedgerlyDocumentRow(
                              document: doc,
                              displayStatus:
                                  effectiveInvoiceStatus(doc, _payments),
                              onOpen: () =>
                                  _createDocument(doc.kind, existing: doc),
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
                                ?.copyWith(
                                    color: _ink, fontSize: wide ? 30 : 25)),
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
                        .map((status) => DropdownMenuItem(
                            value: status, child: Text(status)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _filter = value ?? 'All'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (docs.isEmpty)
                LedgerlyEmptyState(
                  icon: _section == 'Quotes'
                      ? Icons.request_quote_outlined
                      : Icons.receipt_long_outlined,
                  title: _query.isNotEmpty
                      ? 'No matching documents'
                      : 'Nothing here yet',
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
                    _section == 'Quotes' || _section == 'Follow-ups'
                        ? DocumentKind.quote
                        : DocumentKind.invoice,
                  ),
                )
              else
                Card(
                  child: Column(
                    children: docs
                        .map(
                          (doc) => LedgerlyDocumentRow(
                            document: doc,
                            displayStatus:
                                effectiveInvoiceStatus(doc, _payments),
                            onOpen: () =>
                                _createDocument(doc.kind, existing: doc),
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

