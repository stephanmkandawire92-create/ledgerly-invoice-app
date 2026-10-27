import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/subscription_service.dart';

class PaypalConfigScreen extends StatelessWidget {
  const PaypalConfigScreen({super.key});

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final service = SubscriptionService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription Setup')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.verified_user_outlined, size: 48, color: Color(0xFF4F46E5)),
          const SizedBox(height: 12),
          Text('Secure subscription configuration', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Payment credentials and active plan IDs must be stored in Supabase Edge Function secrets. They must never be entered into or saved by the client app.'),
          const SizedBox(height: 18),
          ListenableBuilder(
            listenable: service,
            builder: (context, _) => Card(
              child: ListTile(
                leading: Icon(service.isPro ? Icons.verified : Icons.lock_outline,
                  color: service.isPro ? Colors.green : Colors.orange),
                title: Text(service.isPro ? 'Ledgerly Pro is active' : 'Free tier'),
                subtitle: Text(service.isBackendReady
                  ? (service.isSignedIn ? 'Account signed in. Subscription status is checked against Supabase.' : 'Sign in from the upgrade screen to link purchases to your account.')
                  : 'Supabase is not configured in this build.'),
                trailing: IconButton(
                  tooltip: 'Refresh verified status',
                  icon: const Icon(Icons.refresh),
                  onPressed: service.refreshEntitlement,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Before accepting live payments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 10),
          const _Step('1', 'Activate the correct Supabase project and apply supabase/subscription-schema.sql in a development project first.'),
          const _Step('2', 'Deploy paypal-create-subscription, paypal-webhook and revenuecat-webhook Edge Functions.'),
          const _Step('3', 'Set `PAYPAL_MONTHLY_PLAN_ID` to `P-3WT24403GG2655600NLQM6EA` in Supabase Edge Function secrets. Confirm this plan is ACTIVE at USD 3.00/month in the same PayPal environment as `PAYPAL_ENV`; keep client ID, client secret and webhook ID server-side.'),
          const _Step('4', 'Configure RevenueCat with Google Play and App Store products mapped to the ledgerly_pro entitlement.'),
          const _Step('5', 'Run sandbox tests for purchase, renewal, cancellation, expiry, refunds, duplicate events and forged webhooks.'),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _open('https://www.paypal.com/businessmanage/account/aboutBusiness'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open PayPal Business'),
          ),
          OutlinedButton.icon(
            onPressed: () => _open('https://app.revenuecat.com/'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open RevenueCat'),
          ),
          const SizedBox(height: 14),
          const Text('No payment is considered successful merely because checkout opened or a customer returned to Ledgerly. Only verified provider events can grant server-side access.',
            style: TextStyle(color: Colors.redAccent, height: 1.4)),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(radius: 13, child: Text(number, style: const TextStyle(fontSize: 12))),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
    ]),
  );
}
