import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/business_profile.dart';
import '../models/currency_helper.dart';
import '../services/app_translations.dart';
import '../services/document_store.dart';

class BusinessProfileScreen extends StatefulWidget {
  const BusinessProfileScreen({
    super.key,
    required this.profile,
    required this.onProfileUpdated,
    required this.onDataImported,
  });

  final BusinessProfile profile;
  final ValueChanged<BusinessProfile> onProfileUpdated;
  final VoidCallback onDataImported;

  @override
  State<BusinessProfileScreen> createState() => _BusinessProfileScreenState();
}

class _BusinessProfileScreenState extends State<BusinessProfileScreen> {
  final DocumentStore _store = DocumentStore();

  late TextEditingController _nameCtrl;
  late TextEditingController _ownerCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _websiteCtrl;
  late TextEditingController _taxCtrl;
  late TextEditingController _bankCtrl;
  late TextEditingController _termsCtrl;
  late TextEditingController _invPrefixCtrl;
  late TextEditingController _quoPrefixCtrl;

  late String _currencyCode;
  late String _languageCode;
  late String _logoBase64;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    _nameCtrl = TextEditingController(text: widget.profile.businessName);
    _ownerCtrl = TextEditingController(text: widget.profile.ownerName);
    _emailCtrl = TextEditingController(text: widget.profile.email);
    _phoneCtrl = TextEditingController(text: widget.profile.phone);
    _addressCtrl = TextEditingController(text: widget.profile.address);
    _websiteCtrl = TextEditingController(text: widget.profile.website);
    _taxCtrl = TextEditingController(text: widget.profile.taxNumber);
    _bankCtrl = TextEditingController(text: widget.profile.bankDetails);
    _termsCtrl = TextEditingController(text: widget.profile.paymentTerms);
    _invPrefixCtrl = TextEditingController(text: widget.profile.invoicePrefix);
    _quoPrefixCtrl = TextEditingController(text: widget.profile.quotePrefix);

    _currencyCode = widget.profile.currencyCode;
    _languageCode = widget.profile.languageCode;
    _logoBase64 = widget.profile.logoBase64;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ownerCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _websiteCtrl.dispose();
    _taxCtrl.dispose();
    _bankCtrl.dispose();
    _termsCtrl.dispose();
    _invPrefixCtrl.dispose();
    _quoPrefixCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) return;
      final base64Str = base64Encode(bytes);
      setState(() => _logoBase64 = base64Str);
      await _saveProfile();
    } catch (e) {
      if (mounted) {
        _showBase64LogoDialog();
      }
    }
  }

  void _showBase64LogoDialog() {
    final logoCtrl = TextEditingController(text: _logoBase64);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste Your Logo'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Paste your logo image data or Base64 string below:'),
              const SizedBox(height: 12),
              TextField(
                controller: logoCtrl,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'data:image/png;base64,...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              var str = logoCtrl.text.trim();
              if (str.contains(',')) {
                str = str.split(',').last;
              }
              setState(() => _logoBase64 = str);
              Navigator.pop(ctx);
              _saveProfile();
            },
            child: const Text('Paste Your Logo'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    final updated = widget.profile.copyWith(
      businessName: _nameCtrl.text.trim(),
      ownerName: _ownerCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      website: _websiteCtrl.text.trim(),
      taxNumber: _taxCtrl.text.trim(),
      bankDetails: _bankCtrl.text.trim(),
      paymentTerms: _termsCtrl.text.trim(),
      invoicePrefix: _invPrefixCtrl.text.trim(),
      quotePrefix: _quoPrefixCtrl.text.trim(),
      currencyCode: _currencyCode,
      languageCode: _languageCode,
      logoBase64: _logoBase64,
    );
    await _store.saveProfile(updated);
    widget.onProfileUpdated(updated);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business details, logo, and bank account saved.')),
      );
    }
  }

  Future<void> _exportData() async {
    final backupJson = await _store.exportBackup();
    final jsonCtrl = TextEditingController(text: backupJson);

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup Workspace Data'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Copy the JSON backup content below or save it in a secure location.'),
              const SizedBox(height: 12),
              TextField(
                controller: jsonCtrl,
                maxLines: 8,
                readOnly: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _importData() async {
    final jsonCtrl = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore / Import Data'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Paste your JSON backup data below. WARNING: This will replace the current workspace data.'),
              const SizedBox(height: 12),
              TextField(
                controller: jsonCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: 'Paste backup JSON here...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import Backup'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      final input = jsonCtrl.text.trim();
      if (input.isEmpty) return;
      await _store.importBackup(input);
      widget.onDataImported();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data backup imported successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import failed: Invalid backup format.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    Uint8List? logoBytes;
    if (_logoBase64.isNotEmpty) {
      try {
        logoBytes = base64Decode(_logoBase64);
      } catch (_) {}
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(wide ? 34 : 18, 24, wide ? 34 : 18, 90),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
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
                          AppTranslations.get('settings', _languageCode),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: const Color(0xFF172033), fontSize: wide ? 30 : 25),
                        ),
                        const SizedBox(height: 6),
                        const Text('Set up your company info, logo, bank details, currency, and language for invoices.'),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _saveProfile,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(AppTranslations.get('saveSettings', _languageCode)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Company Logo & Language Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AppTranslations.get('companyLogo', _languageCode),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          if (_logoBase64.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0E9F6E).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text('Logo Active on Invoices',
                                  style: TextStyle(
                                      color: Color(0xFF0E9F6E), fontWeight: FontWeight.bold, fontSize: 11)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F8FC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE4E7EF), width: 1.5),
                            ),
                            child: logoBytes != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(logoBytes, fit: BoxFit.contain),
                                  )
                                : const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_photo_alternate_outlined, size: 36, color: Color(0xFF7B8497)),
                                      SizedBox(height: 4),
                                      Text('No Logo', style: TextStyle(fontSize: 11, color: Color(0xFF7B8497))),
                                    ],
                                  ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: _pickLogo,
                                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                                      label: Text(AppTranslations.get('uploadLogo', _languageCode)),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _showBase64LogoDialog,
                                      icon: const Icon(Icons.code_rounded, size: 18),
                                      label: const Text('Paste Your Logo'),
                                    ),
                                    if (_logoBase64.isNotEmpty)
                                      TextButton.icon(
                                        onPressed: () {
                                          setState(() => _logoBase64 = '');
                                          _saveProfile();
                                        },
                                        icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFB42318)),
                                        label: Text(
                                          AppTranslations.get('removeLogo', _languageCode),
                                          style: const TextStyle(color: Color(0xFFB42318)),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Your company logo will automatically be printed on the top left of all PDF invoices & quotes.',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF7B8497)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _languageCode,
                              decoration: InputDecoration(
                                labelText: AppTranslations.get('appLanguage', _languageCode),
                                prefixIcon: const Icon(Icons.language_rounded),
                              ),
                              items: AppTranslations.languages.map((l) {
                                return DropdownMenuItem(
                                  value: l['code']!,
                                  child: Text(l['name']!),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _languageCode = val);
                                  _saveProfile();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _currencyCode,
                              decoration: InputDecoration(
                                labelText: AppTranslations.get('defaultCurrency', _languageCode),
                                prefixIcon: const Icon(Icons.attach_money_rounded),
                              ),
                              items: CurrencyHelper.currencies.map((c) {
                                return DropdownMenuItem(
                                  value: c.code,
                                  child: Text('${c.code} (${c.symbol})'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _currencyCode = val);
                                  _saveProfile();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Company Details
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppTranslations.get('companyDetails', _languageCode),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: 'Company / Business Name *'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _ownerCtrl,
                              decoration: const InputDecoration(labelText: 'Owner / Contact Name'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _taxCtrl,
                              decoration: const InputDecoration(labelText: 'Tax / VAT Registration No.'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _emailCtrl,
                              decoration: const InputDecoration(labelText: 'Business Email'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneCtrl,
                              decoration: const InputDecoration(labelText: 'Phone Number'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addressCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'Company Physical / Postal Address'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _websiteCtrl,
                        decoration: const InputDecoration(labelText: 'Company Website URL'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Bank Account Details & Terms
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bank Account & Payment Details (Printed on Invoice)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text(
                        'Provide your bank name, account number, branch code, and SWIFT so clients can pay you directly.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF7B8497)),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _bankCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Bank Account Details *',
                          hintText: 'Bank Name: First National Bank\nAccount Name: My Business Pty Ltd\nAccount No: 62000000000\nBranch / SWIFT Code: 250655',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _termsCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Payment Terms / Instructions',
                          hintText: 'Payment due within 30 days of invoice date. Please use Invoice Number as payment reference.',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Document Numbering Defaults
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Document Numbering Defaults',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _invPrefixCtrl,
                              decoration: const InputDecoration(labelText: 'Invoice Number Prefix'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _quoPrefixCtrl,
                              decoration: const InputDecoration(labelText: 'Quote Number Prefix'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Backup & Data
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Backup & Data Management',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text(
                        'Your workspace data is saved locally on this device. You can export a JSON backup to keep your records safe or restore onto another device.',
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _exportData,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('Export JSON Backup'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _importData,
                            icon: const Icon(Icons.upload_outlined),
                            label: const Text('Restore Backup'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
