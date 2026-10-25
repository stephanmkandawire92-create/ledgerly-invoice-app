import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/subscription_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({
    super.key,
    this.featurePrompt,
  });

  /// Optional prompt indicating what triggered the paywall (e.g. "Free Document Limit Reached")
  final String? featurePrompt;

  static Future<bool?> showPaywall(BuildContext context, {String? featurePrompt}) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PaywallScreen(featurePrompt: featurePrompt),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final SubscriptionService _subService = SubscriptionService.instance;
  bool _isYearly = true;
  bool _startFreeTrial = true;
  bool _launching = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _subService,
      builder: (context, _) {
        final isPro = _subService.isPro;

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              onPressed: () => Navigator.pop(context, isPro),
            ),
            actions: [
              if (isPro)
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.workspace_premium_rounded, color: Color(0xFFF59E0B), size: 16),
                      SizedBox(width: 6),
                      Text(
                        'PRO ACTIVE',
                        style: TextStyle(
                          color: Color(0xFFF59E0B),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Column(
                  children: [
                    // Glowing Crown Header
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                            blurRadius: 30,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.workspace_premium_rounded, size: 44, color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Upgrade to Ledgerly Pro',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.featurePrompt ??
                          'Power your business with limitless professional invoicing & PayPal subscriptions',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.75),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (isPro) ...[
                      _buildActiveSubscriptionCard(),
                      const SizedBox(height: 24),
                    ],

                    // Feature highlights table
                    _buildFeatureList(),

                    const SizedBox(height: 28),

                    if (!isPro) ...[
                      // 7-day free trial switch
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _startFreeTrial ? const Color(0xFF6366F1) : const Color(0xFF334155),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.stars_rounded, color: Color(0xFFF59E0B), size: 24),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Include 7-Day Free Trial',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Free for 7 days, cancel anytime in PayPal',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _startFreeTrial,
                              activeThumbColor: const Color(0xFF6366F1),
                              onChanged: (val) => setState(() => _startFreeTrial = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Plan Selector
                      Row(
                        children: [
                          Expanded(
                            child: _buildPlanOption(
                              title: 'Monthly',
                              price: '\$4.99',
                              subtext: '/ month',
                              selected: !_isYearly,
                              onTap: () => setState(() => _isYearly = false),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _buildPlanOption(
                              title: 'Yearly Plan',
                              price: '\$39.99',
                              subtext: '/ year (\$3.33/mo)',
                              badge: 'SAVE 33%',
                              selected: _isYearly,
                              onTap: () => setState(() => _isYearly = true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // PayPal Subscribe Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _launching ? null : _handlePayPalCheckout,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC439), // Official PayPal Gold
                            foregroundColor: const Color(0xFF003087), // PayPal Dark Navy
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _launching
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF003087)),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.payment_rounded, color: Color(0xFF003087), size: 22),
                                    const SizedBox(width: 10),
                                    Text(
                                      _startFreeTrial
                                          ? 'Start 7-Day Free Trial with PayPal'
                                          : 'Subscribe with PayPal (${_isYearly ? '\$39.99/yr' : '\$4.99/mo'})',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Secondary options (Manual ID verification & Demo Mode)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: _showManualActivationDialog,
                            child: const Text(
                              'Already subscribed? Enter PayPal ID',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 13,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          const Text(' • ', style: TextStyle(color: Color(0xFF64748B))),
                          TextButton(
                            onPressed: () => _subService.toggleDemoPro(),
                            child: const Text(
                              'Instant Demo Mode',
                              style: TextStyle(
                                color: Color(0xFF6366F1),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 20),
                    // Trust badges
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_outline_rounded, size: 14, color: Color(0xFF64748B)),
                        const SizedBox(width: 6),
                        Text(
                          'Secured via PayPal Subscriptions. Cancel anytime.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveSubscriptionCard() {
    final sub = _subService;
    final exp = sub.expiresAt != null ? DateFormat('d MMM yyyy').format(sub.expiresAt!) : 'Auto-renewing';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22),
              const SizedBox(width: 10),
              Text(
                'You are currently on Ledgerly Pro ${sub.isTrial ? '(Free Trial)' : ''}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Plan: ${sub.planType?.toUpperCase() ?? 'PRO'} • ID: ${sub.subscriptionId ?? 'Active'}',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          Text(
            'Renews / Expires: $exp',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await _subService.cancelSubscription();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Subscription downgraded to Free Tier.')),
                    );
                  }
                },
                icon: const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFF87171)),
                label: const Text('Cancel / Downgrade', style: TextStyle(color: Color(0xFFF87171))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureList() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          _buildFeatureRow(
            icon: Icons.all_inclusive_rounded,
            title: 'Unlimited Invoices & Quotes',
            subtitle: 'Free tier is limited to 5 total documents',
            isPro: true,
          ),
          const Divider(height: 1, color: Color(0xFF334155)),
          _buildFeatureRow(
            icon: Icons.branding_watermark_rounded,
            title: 'No "Ledgerly" Watermark on PDFs',
            subtitle: 'Export clean, 100% white-label documents to clients',
            isPro: true,
          ),
          const Divider(height: 1, color: Color(0xFF334155)),
          _buildFeatureRow(
            icon: Icons.insights_rounded,
            title: 'Advanced Financial Analytics',
            subtitle: 'Client revenue rankings, payment methods & forecast insights',
            isPro: true,
          ),
          const Divider(height: 1, color: Color(0xFF334155)),
          _buildFeatureRow(
            icon: Icons.support_agent_rounded,
            title: 'Priority Support & Cloud Backup',
            subtitle: 'Get instant email support and one-click JSON data export',
            isPro: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isPro,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF818CF8), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
        ],
      ),
    );
  }

  Widget _buildPlanOption({
    required String title,
    required String price,
    required String subtext,
    String? badge,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF6366F1).withValues(alpha: 0.15) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF6366F1) : const Color(0xFF334155),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF94A3B8),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              price,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 24,
              ),
            ),
            Text(
              subtext,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePayPalCheckout() async {
    setState(() => _launching = true);
    try {
      final launched = await _subService.launchPayPalSubscription(
        isYearly: _isYearly,
        startTrial: _startFreeTrial,
      );

      if (mounted) {
        if (!launched) {
          // If URL launch failed or fallback to dialog
          _showLaunchFallbackDialog();
        } else {
          _showPostCheckoutPrompt();
        }
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  void _showLaunchFallbackDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('PayPal Checkout', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'We opened PayPal in your browser. Complete your subscription there, then confirm below:',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 14),
            Text(
              'Link: ${_isYearly ? _subService.paypalYearlyUrl : _subService.paypalMonthlyUrl}',
              style: const TextStyle(color: Color(0xFF6366F1), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _subService.activatePro(
                planType: _isYearly ? 'yearly' : 'monthly',
                isTrial: _startFreeTrial,
              );
              if (mounted) Navigator.pop(context, true);
            },
            child: const Text('Confirm Pro Activation'),
          ),
        ],
      ),
    );
  }

  void _showPostCheckoutPrompt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.open_in_new_rounded, color: Color(0xFF6366F1)),
            SizedBox(width: 10),
            Text('PayPal Opened', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Please complete the subscription in PayPal. Once completed, tap "Activate Pro" below to unlock all features immediately.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('I will finish later', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () async {
              Navigator.pop(ctx);
              await _subService.activatePro(
                planType: _isYearly ? 'yearly' : 'monthly',
                isTrial: _startFreeTrial,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Color(0xFF10B981),
                    content: Text('🎉 Congratulations! Ledgerly Pro is now active!'),
                  ),
                );
                Navigator.pop(context, true);
              }
            },
            child: const Text('Activate Pro Now'),
          ),
        ],
      ),
    );
  }

  void _showManualActivationDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Enter PayPal Subscription ID', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your PayPal Subscription ID (starts with I-...) or payment confirmation code:',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. I-BW452966XX',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                filled: true,
                fillColor: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          FilledButton(
            onPressed: () async {
              final id = controller.text.trim();
              if (id.isEmpty) return;
              Navigator.pop(ctx);
              await _subService.activatePro(
                planType: 'paypal_verified',
                subscriptionId: id,
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Pro activated with Subscription ID: $id')),
                );
                Navigator.pop(context, true);
              }
            },
            child: const Text('Verify & Unlock'),
          ),
        ],
      ),
    );
  }
}
