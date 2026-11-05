import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/subscription_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.featurePrompt});
  final String? featurePrompt;

  static Future<bool?> showPaywall(BuildContext context,
      {String? featurePrompt}) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PaywallScreen(featurePrompt: featurePrompt),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final SubscriptionService _service = SubscriptionService.instance;
  bool _busy = false;
  String? _message;

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _isWebOrWindows =>
      kIsWeb || (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows);

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      if (mounted) {
        setState(() => _message ??=
            'Request completed. Ledgerly Pro appears after the subscription is verified.');
      }
      if (mounted && _service.isPro) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _message = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('not configured') || text.contains('not initialized')) {
      return 'Payments are not configured yet. Ledgerly remains in Free mode until the backend and provider credentials are set up.';
    }
    if (text.contains('Sign in')) {
      return 'Sign in or create a Ledgerly account before subscribing.';
    }
    return text
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
  }

  Future<void> _signInWithGoogle() async {
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'io.supabase.ledgerly://login-callback',
      );
    } catch (e) {
      if (mounted) setState(() => _message = 'Google sign-in error: $e');
    }
  }

  Future<void> _showAccountDialog() async {
    if (!_service.isBackendReady) {
      setState(() => _message =
          'Supabase is not configured. Build with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY first.');
      return;
    }
    final email = TextEditingController();
    final password = TextEditingController();
    bool create = false;
    bool submitting = false;
    String? errorText;
    await showDialog<void>(
      context: context,
      barrierDismissible: !submitting,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title:
              Text(create ? 'Create Ledgerly account' : 'Sign in to Ledgerly'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Your account securely links purchases across supported devices.'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: submitting ? null : () async {
                    Navigator.pop(dialogContext);
                    await _signInWithGoogle();
                  },
                  icon: const Icon(Icons.g_mobiledata, size: 28, color: Color(0xFF4285F4)),
                  label: const Text('Continue with Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('OR', style: TextStyle(color: Colors.grey, fontSize: 12))),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email address'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: password,
                  obscureText: true,
                  autofillHints: [
                    create ? AutofillHints.newPassword : AutofillHints.password
                  ],
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(errorText!, style: const TextStyle(color: Colors.red)),
                ],
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => setDialogState(() {
                            create = !create;
                            errorText = null;
                          }),
                  child: Text(create
                      ? 'Already have an account? Sign in'
                      : 'New here? Create account'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed:
                    submitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (!email.text.contains('@') ||
                          password.text.length < 8) {
                        setDialogState(() => errorText =
                            'Enter a valid email and a password of at least 8 characters.');
                        return;
                      }
                      setDialogState(() {
                        submitting = true;
                        errorText = null;
                      });
                      try {
                        if (create) {
                          await _service.createAccount(
                              email: email.text, password: password.text);
                          if (_service.isSignedIn) {
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            if (mounted) {
                              setState(() =>
                                  _message = 'Account created and signed in.');
                            }
                          } else {
                            setDialogState(() {
                              submitting = false;
                              errorText =
                                  'Account created. Check your email to confirm it, then sign in.';
                            });
                          }
                        } else {
                          await _service.signIn(
                              email: email.text, password: password.text);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          if (mounted) {
                            setState(
                                () => _message = 'Signed in successfully.');
                          }
                        }
                      } on AuthException catch (e) {
                        setDialogState(() {
                          submitting = false;
                          errorText = e.message;
                        });
                      } catch (e) {
                        setDialogState(() {
                          submitting = false;
                          errorText = e.toString();
                        });
                      }
                    },
              child: Text(create ? 'Create account' : 'Sign in'),
            ),
          ],
        ),
      ),
    );
    email.dispose();
    password.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _subscribeMobile() => _run(() async {
        if (!_service.isSignedIn) {
          await _showAccountDialog();
          if (!_service.isSignedIn) return;
        }
        final activated = await _service.purchaseMobilePro();
        if (!activated) {
          throw StateError('Ledgerly Pro is not active on this account yet.');
        }
      });

  Future<void> _subscribePayPal() => _run(() async {
        if (!_service.isSignedIn) {
          await _showAccountDialog();
          if (!_service.isSignedIn) return;
        }
        final launched = await _service.launchPayPalSubscription();
        if (!launched) {
          throw StateError('Could not open PayPal checkout. Please try again.');
        }
        if (mounted) {
          setState(() => _message =
              'PayPal checkout opened. Pro will unlock only after the verified payment webhook updates your account. Return here and refresh after payment.');
        }
      });

  Future<void> _restore() => _run(() async {
        await _service.restoreMobilePurchases();
      });

  Future<void> _manageSubscription() async {
    final url = _isMobile && defaultTargetPlatform == TargetPlatform.android
        ? 'https://play.google.com/store/account/subscriptions'
        : _isMobile && defaultTargetPlatform == TargetPlatform.iOS
            ? 'https://apps.apple.com/account/subscriptions'
            : 'https://www.paypal.com/myaccount/autopay/';
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      setState(() => _message = 'Could not open subscription management.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final pro = _service.isPro;
        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: const Text('Ledgerly Pro'),
            actions: [
              if (_service.isSignedIn)
                TextButton(
                    onPressed: _service.signOut,
                    child: const Text('Sign out',
                        style: TextStyle(color: Colors.white70))),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.workspace_premium_rounded,
                        color: Color(0xFFFBBF24), size: 64),
                    const SizedBox(height: 16),
                    const Text('Upgrade to Ledgerly Pro',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                        widget.featurePrompt ??
                            'Unlimited professional invoicing and advanced business tools.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFFCBD5E1), height: 1.5)),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFF475569))),
                      child: Column(
                        children: [
                          const Text('USD 3',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w800)),
                          const Text('per month • recurring subscription',
                              style: TextStyle(color: Color(0xFFCBD5E1))),
                          const SizedBox(height: 20),
                          for (final feature in const [
                            'Unlimited invoices and quotations',
                            'Remove Ledgerly watermark from PDFs',
                            'Advanced financial analytics',
                          ])
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(children: [
                                const Icon(Icons.check_circle,
                                    color: Color(0xFF34D399), size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(feature,
                                        style: const TextStyle(
                                            color: Colors.white))),
                              ]),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (pro) ...[
                      const Text('Your Ledgerly Pro entitlement is active.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Color(0xFF34D399),
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                          onPressed: _manageSubscription,
                          child: const Text('Manage subscription')),
                      OutlinedButton(
                          onPressed: () => _run(_service.refreshEntitlement),
                          child: const Text('Refresh status')),
                    ] else ...[
                      if (_isMobile)
                        FilledButton.icon(
                          onPressed: _busy ? null : _subscribeMobile,
                          icon: const Icon(Icons.phone_iphone),
                          label: const Text(
                              'Subscribe with App Store / Google Play'),
                        ),
                      if (_isWebOrWindows)
                        FilledButton.icon(
                          onPressed: _busy ? null : _subscribePayPal,
                          icon: const Icon(Icons.payment),
                          label: const Text('Subscribe securely with PayPal'),
                          style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFFC439),
                              foregroundColor: const Color(0xFF003087)),
                        ),
                      if (_isMobile)
                        TextButton(
                            onPressed: _busy ? null : _restore,
                            child: const Text('Restore purchases',
                                style: TextStyle(color: Color(0xFFCBD5E1)))),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(_service.refreshEntitlement),
                        child: const Text('Refresh payment status',
                            style: TextStyle(color: Color(0xFFCBD5E1))),
                      ),
                      if (!_isMobile && !_isWebOrWindows)
                        const Text(
                            'Purchases are not supported on this platform yet.',
                            style: TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center),
                      OutlinedButton(
                        onPressed: _busy ? null : _showAccountDialog,
                        child: Text(_service.isSignedIn
                            ? 'Account signed in'
                            : 'Sign in / Create account'),
                      ),
                    ],
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFF334155),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text(_message!,
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ],
                    if (_service.errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(_service.errorMessage!,
                          style: const TextStyle(color: Color(0xFFFCA5A5)),
                          textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 18),
                    const Text(
                        'Secure billing • Cancel through your payment provider • Premium access requires verified payment',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
