import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/subscription_service.dart';

class PaypalConfigScreen extends StatelessWidget {
  const PaypalConfigScreen({super.key});

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = SubscriptionService.instance;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription status'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.workspace_premium_outlined,
                              color: theme.colorScheme.onPrimaryContainer,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Ledgerly Pro', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text('Manage your plan and billing status.', style: theme.textTheme.bodyMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      ListenableBuilder(
                        listenable: service,
                        builder: (context, _) {
                          final active = service.isPro;
                          final configured = service.isBackendReady;
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: theme.colorScheme.outlineVariant),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  active ? Icons.check_circle : configured ? Icons.lock_outline : Icons.cloud_off_outlined,
                                  color: active ? Colors.green.shade700 : theme.colorScheme.onSurfaceVariant,
                                  size: 26,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        active ? 'Pro is active' : 'Free plan',
                                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        !configured
                                            ? 'This build is not connected to Supabase.'
                                            : active
                                                ? 'Your premium access has been verified.'
                                                : service.isSignedIn
                                                    ? 'No active premium subscription was found for this account.'
                                                    : 'Sign in to link a subscription to your account.',
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                      if (service.errorMessage != null) ...[
                                        const SizedBox(height: 6),
                                        Text(service.errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
                                      ],
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Refresh subscription status',
                                  onPressed: () async {
                                    await service.refreshEntitlement();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Subscription status refreshed.')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.refresh),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      Text('Included with Pro', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      const _FeatureRow('Unlimited quotes and invoices'),
                      const _FeatureRow('Watermark-free PDF exports'),
                      const _FeatureRow('Advanced business analytics'),
                      const _FeatureRow('Cloud backup where configured'),
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
                      Text('Billing support', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        'Payment credentials and internal plan identifiers are never displayed here. Payments are verified securely by the server before Pro access is granted.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => _open(context, 'https://www.paypal.com/myaccount/autopay/'),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Manage PayPal subscriptions'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _open(context, 'https://www.paypal.com/businessmanage/account/aboutBusiness'),
                        icon: const Icon(Icons.business_outlined),
                        label: const Text('Open PayPal Business'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _open(context, 'https://app.revenuecat.com/'),
                        icon: const Icon(Icons.phone_iphone),
                        label: const Text('Open RevenueCat dashboard'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Never share your PayPal client secret, access tokens, webhook credentials, or Supabase service-role key. Configure these only in trusted server-side secrets.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xFF15803D), size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
          ],
        ),
      );
}
