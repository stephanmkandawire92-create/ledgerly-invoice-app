import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/subscription_service.dart';

class PaypalConfigScreen extends StatefulWidget {
  const PaypalConfigScreen({super.key});

  @override
  State<PaypalConfigScreen> createState() => _PaypalConfigScreenState();
}

class _PaypalConfigScreenState extends State<PaypalConfigScreen> {
  final SubscriptionService _subService = SubscriptionService.instance;
  late final TextEditingController _accountController;
  late final TextEditingController _monthlyController;
  late final TextEditingController _yearlyController;

  @override
  void initState() {
    super.initState();
    _accountController = TextEditingController(text: _subService.paypalAccount);
    _monthlyController = TextEditingController(text: _subService.paypalMonthlyUrl);
    _yearlyController = TextEditingController(text: _subService.paypalYearlyUrl);
  }

  @override
  void dispose() {
    _accountController.dispose();
    _monthlyController.dispose();
    _yearlyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _subService.savePayPalConfig(
      monthlyUrl: _monthlyController.text,
      yearlyUrl: _yearlyController.text,
      paypalAccount: _accountController.text,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PayPal subscription configuration saved.')),
      );
      Navigator.pop(context);
    }
  }

  void _applyAccountLinks() {
    final input = _accountController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your PayPal email or PayPal.Me handle.')),
      );
      return;
    }

    final links = SubscriptionService.generatePayPalLinksFromAccount(input);
    setState(() {
      _monthlyController.text = links['monthly']!;
      _yearlyController.text = links['yearly']!;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment URLs automatically generated! Review and tap Save.')),
    );
  }

  void _restoreDefaults() {
    setState(() {
      _accountController.clear();
      _monthlyController.text = SubscriptionService.defaultMonthlyUrl;
      _yearlyController.text = SubscriptionService.defaultYearlyUrl;
    });
  }

  Future<void> _testLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch the provided URL.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF4F46E5);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Your PayPal Account'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, color: brand, fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Option 1: Fast Setup Card
                Card(
                  color: const Color(0xFFEEF2FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFC7D2FE)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.bolt_rounded, color: brand, size: 24),
                            SizedBox(width: 8),
                            Text(
                              'Option 1: Quick Connect (Email or PayPal.Me)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E1B4B)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Enter your PayPal Email address or PayPal.Me username. We will automatically generate your monthly & yearly subscription checkout links.',
                          style: TextStyle(color: Color(0xFF3730A3), fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _accountController,
                                decoration: const InputDecoration(
                                  hintText: 'e.g. yourname@example.com or paypal.me/yourname',
                                  prefixIcon: Icon(Icons.alternate_email_rounded),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFFC439),
                                foregroundColor: const Color(0xFF003087),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                              ),
                              onPressed: _applyAccountLinks,
                              child: const Text('Generate Links', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Option 2: Step-by-Step Official Subscriptions Guide
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.repeat_rounded, color: brand, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Option 2: Official PayPal Recurring Billing Plans',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'If you have a PayPal Business account and want automated recurring subscriptions:',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                        const SizedBox(height: 14),
                        _buildStepRow('1', 'Go to paypal.com/billing/plans in your browser.'),
                        _buildStepRow('2', 'Click "Create Plan" and choose or create a product (e.g. "Ledgerly Pro").'),
                        _buildStepRow('3', 'Set Pricing: Monthly (\$4.99/mo) and Yearly (\$39.99/yr) with 7-day trial.'),
                        _buildStepRow('4', 'Click "Turn Plan On" and copy the subscribe link (starts with P-...).'),
                        _buildStepRow('5', 'Paste the links below and tap "Save".'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Manual URL Inputs
                const Text(
                  'Active Monthly Plan URL',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _monthlyController,
                  decoration: InputDecoration(
                    hintText: 'https://www.paypal.com/webapps/billing/plans/subscribe?plan_id=P-...',
                    prefixIcon: const Icon(Icons.link_rounded),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.open_in_new_rounded, size: 20),
                      tooltip: 'Test URL in browser',
                      onPressed: () => _testLink(_monthlyController.text),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                const Text(
                  'Active Yearly Plan URL',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _yearlyController,
                  decoration: InputDecoration(
                    hintText: 'https://www.paypal.com/webapps/billing/plans/subscribe?plan_id=P-...',
                    prefixIcon: const Icon(Icons.link_rounded),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.open_in_new_rounded, size: 20),
                      tooltip: 'Test URL in browser',
                      onPressed: () => _testLink(_yearlyController.text),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton(
                      onPressed: _restoreDefaults,
                      child: const Text('Reset to Defaults'),
                    ),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Save Settings'),
                    ),
                  ],
                ),
                const SizedBox(height: 36),

                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'Current Pro Status on this Device',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 10),
                ListenableBuilder(
                  listenable: _subService,
                  builder: (context, _) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Status:'),
                                Text(
                                  _subService.isPro ? 'PRO ACTIVE' : 'FREE TIER',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _subService.isPro ? const Color(0xFF10B981) : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            if (_subService.isPro) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Subscription ID:'),
                                  Text(_subService.subscriptionId ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                            const SizedBox(height: 14),
                            FilledButton.tonal(
                              onPressed: () => _subService.toggleDemoPro(),
                              child: Text(_subService.isPro ? 'Deactivate Pro (Test Free Tier)' : 'Activate Pro (Test Pro Tier)'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Color(0xFF4F46E5),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
