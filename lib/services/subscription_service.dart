import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'entitlement_evaluator.dart';

/// A customer-safe failure raised by the subscription service.
///
/// The message is written for a business owner, never for a developer: no
/// status codes, no stack traces, no provider internals.
class SubscriptionException implements Exception {
  const SubscriptionException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Maps a backend error code to copy the customer can act on.
String subscriptionErrorMessage(String? code) {
  switch (code) {
    case 'billing_not_configured':
    case 'plan_misconfigured':
      return 'Subscription payments are not available yet. Ledgerly remains in Free mode and no payment has been taken.';
    case 'sign_in_required':
    case 'session_expired':
      return 'Sign in to your Ledgerly account to continue.';
    case 'already_subscribed':
      return 'Your account already has an active Ledgerly Pro subscription. Tap "Check payment status" to refresh it.';
    case 'payment_issue':
      return 'Your Ledgerly Pro subscription has an unpaid balance. Update your payment method in PayPal, then check your status again.';
    case 'account_mismatch':
      return 'That PayPal subscription is linked to a different Ledgerly account. Sign in with the account you used to subscribe.';
    case 'provider_unavailable':
      return 'PayPal is temporarily unavailable. No payment has been taken. Please try again in a moment.';
    case 'checkout_failed':
    case 'internal_error':
      return 'PayPal could not start the subscription. No payment has been taken. Please try again.';
    default:
      return 'We could not confirm your subscription. If you completed a payment, wait a moment and check your status again.';
  }
}

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService instance = SubscriptionService._internal();
  SubscriptionService._internal();

  static const int maxFreeDocuments = 5;
  static const String proEntitlement = 'ledgerly_pro';

  bool _isPro = false;
  bool _initialized = false;
  bool _backendReady = false;
  bool _revenueCatConfigured = false;
  bool _pendingApproval = false;
  bool _syncing = false;
  String? _planType;
  String? _subscriptionId;
  String? _status;
  DateTime? _expiresAt;
  DateTime? _lastCheckedAt;
  String? _errorMessage;

  bool get isPro => _isPro;
  bool get isInitialized => _initialized;
  bool get isBackendReady => _backendReady;

  /// True after a PayPal approval page was opened and before the backend has
  /// verified the payment. The UI must show "verification pending", never a
  /// success state, while this is true.
  bool get hasPendingApproval => _pendingApproval;
  bool get isSyncing => _syncing;
  bool get isSignedIn =>
      _backendReady && Supabase.instance.client.auth.currentUser != null;
  String? get currentUserId =>
      _backendReady ? Supabase.instance.client.auth.currentUser?.id : null;
  String? get planType => _planType;
  String? get subscriptionId => _subscriptionId;
  String? get status => _status;
  DateTime? get expiresAt => _expiresAt;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  String? get errorMessage => _errorMessage;

  Future<void> init() async {
    if (_initialized) return;
    try {
      _backendReady = Supabase.instance.client.auth.currentSession == null ||
          Supabase.instance.client.auth.currentUser != null;
    } catch (_) {
      _backendReady = false;
      _errorMessage = 'Subscription backend is not configured.';
    }
    _initialized = true;
    if (_backendReady && Supabase.instance.client.auth.currentUser != null) {
      await refreshEntitlement();
    }
    notifyListeners();
  }

  bool canCreateDocument(int totalExistingDocuments) =>
      _isPro || totalExistingDocuments < maxFreeDocuments;

  int remainingFreeDocuments(int totalExistingDocuments) {
    if (_isPro) return 999999;
    final remaining = maxFreeDocuments - totalExistingDocuments;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> signIn({required String email, required String password}) async {
    _requireBackend();
    await Supabase.instance.client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    await _onAuthenticated();
  }

  Future<void> createAccount(
      {required String email, required String password}) async {
    _requireBackend();
    final redirectTo = _resolveSignUpRedirectUrl();
    await Supabase.instance.client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: redirectTo,
    );
    if (Supabase.instance.client.auth.currentUser != null) {
      await _onAuthenticated();
    }
  }

  String _resolveSignUpRedirectUrl() {
    const configured = String.fromEnvironment('SUPABASE_AUTH_REDIRECT_URL');
    if (configured.trim().isNotEmpty) return configured.trim();
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.startsWith('http://') || origin.startsWith('https://')) {
        return origin;
      }
    }
    throw StateError(
      'Set SUPABASE_AUTH_REDIRECT_URL to a registered Ledgerly confirmation-return URL before creating accounts in this desktop build.',
    );
  }

  Future<void> signOut() async {
    if (!_backendReady) return;
    await Supabase.instance.client.auth.signOut();
    _clearEntitlement();
    _pendingApproval = false;
    notifyListeners();
  }

  void _requireBackend() {
    if (!_backendReady) {
      throw const SubscriptionException(
        'Accounts are not configured in this build. Ledgerly remains in Free mode.',
        code: 'billing_not_configured',
      );
    }
  }

  void _clearEntitlement() {
    _isPro = false;
    _planType = null;
    _subscriptionId = null;
    _status = null;
    _expiresAt = null;
  }

  Future<void> _onAuthenticated() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await _configureRevenueCat(user.id);
    await refreshEntitlement();
  }

  Future<void> _configureRevenueCat(String userId) async {
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      return;
    }
    const androidKey = String.fromEnvironment('REVENUECAT_ANDROID_API_KEY');
    const iosKey = String.fromEnvironment('REVENUECAT_IOS_API_KEY');
    final key =
        defaultTargetPlatform == TargetPlatform.android ? androidKey : iosKey;
    if (key.isEmpty) return;
    if (!_revenueCatConfigured) {
      await Purchases.configure(
          PurchasesConfiguration(key)..appUserID = userId);
      _revenueCatConfigured = true;
    } else {
      await Purchases.logIn(userId);
    }
  }

  /// Reads the entitlement rows Supabase exposes through row level security.
  /// No provider call is made here, so it is safe to call on every screen.
  Future<void> refreshEntitlement() async {
    if (!_backendReady) {
      _clearEntitlement();
      notifyListeners();
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _clearEntitlement();
      _pendingApproval = false;
      notifyListeners();
      return;
    }

    try {
      final rows = await Supabase.instance.client
          .from('subscription_entitlements')
          .select(
              'provider, external_subscription_id, status, current_period_end, product_id')
          .eq('user_id', user.id)
          .order('updated_at', ascending: false);
      final entitlement = evaluateSubscriptionRows(
        rows.map((row) => Map<String, dynamic>.from(row)).toList(),
        DateTime.now().toUtc(),
      );
      _applyEntitlement(entitlement);
      if (_isPro) _pendingApproval = false;
      _errorMessage = null;
      _lastCheckedAt = DateTime.now().toUtc();
    } catch (error) {
      _clearEntitlement();
      _errorMessage =
          'Could not verify subscription status. Please check your connection and try again.';
      debugPrint('Subscription verification failed: $error');
    }
    notifyListeners();
  }

  void _applyEntitlement(SubscriptionEntitlement entitlement) {
    _isPro = entitlement.isPro;
    _planType = entitlement.provider;
    _subscriptionId = entitlement.subscriptionId;
    _status = entitlement.status;
    _expiresAt = entitlement.periodEnd;
  }

  /// Asks Supabase to reconcile the outstanding PayPal checkout with PayPal's
  /// canonical subscription record, then applies the server's decision.
  ///
  /// This is the only path that can turn "pending" into "Pro" after a return
  /// from PayPal, and it never trusts the browser redirect by itself.
  Future<SubscriptionEntitlement> syncPayPalSubscription() async {
    _requireBackend();
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw const SubscriptionException(
        'Sign in to your Ledgerly account to check your subscription.',
        code: 'sign_in_required',
      );
    }
    if (_syncing) {
      return SubscriptionEntitlement(
        isPro: _isPro,
        provider: _planType,
        subscriptionId: _subscriptionId,
        status: _status,
        periodEnd: _expiresAt,
      );
    }
    _syncing = true;
    notifyListeners();
    try {
      final response = await Supabase.instance.client.functions
          .invoke('paypal-sync-subscription');
      final data = response.data;
      if (data is! Map) {
        throw const SubscriptionException(
          'We could not read your subscription status. Please try again.',
        );
      }
      final isPro = data['isPro'] == true;
      final status = data['status'] as String?;
      final periodEnd = data['currentPeriodEnd'] as String?;
      final subscriptionId = data['subscriptionId'] as String?;
      final entitlement = isPro
          ? SubscriptionEntitlement(
              isPro: true,
              provider: 'paypal',
              subscriptionId: subscriptionId,
              status: status,
              periodEnd: periodEnd == null ? null : DateTime.tryParse(periodEnd),
            )
          : SubscriptionEntitlement(
              isPro: false,
              status: status,
              subscriptionId: subscriptionId,
              periodEnd: periodEnd == null ? null : DateTime.tryParse(periodEnd),
            );
      _applyEntitlement(entitlement);
      if (_isPro) _pendingApproval = false;
      _lastCheckedAt = DateTime.now().toUtc();
      _errorMessage = null;
      return entitlement;
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['code'] as String? : null;
      // A project that has not deployed the sync function yet still has a
      // readable entitlement table; fall back to it rather than blocking.
      if (error.status == 404) {
        await refreshEntitlement();
        return SubscriptionEntitlement(
          isPro: _isPro,
          provider: _planType,
          subscriptionId: _subscriptionId,
          status: _status,
          periodEnd: _expiresAt,
        );
      }
      throw SubscriptionException(subscriptionErrorMessage(code), code: code);
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Polls the backend a few times so a slightly delayed webhook does not turn
  /// into a support ticket. Never reports success before the server does.
  Future<bool> awaitVerifiedSubscription({
    int attempts = 5,
    Duration interval = const Duration(seconds: 3),
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final entitlement = await syncPayPalSubscription();
        if (entitlement.isPro) return true;
        if (entitlement.status == 'past_due' ||
            entitlement.status == 'expired' ||
            entitlement.status == 'suspended') {
          return false;
        }
      } on SubscriptionException {
        if (attempt == attempts - 1) rethrow;
      }
      if (attempt < attempts - 1) await Future<void>.delayed(interval);
    }
    return _isPro;
  }

  Future<bool> purchaseMobilePro() async {
    _requireBackend();
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw const SubscriptionException(
        'Sign in to your Ledgerly account before subscribing.',
        code: 'sign_in_required',
      );
    }
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      throw const SubscriptionException(
          'App Store and Google Play purchases are only available on iOS and Android.');
    }
    await _configureRevenueCat(user.id);
    if (!_revenueCatConfigured) {
      throw const SubscriptionException(
          'Store purchases are not configured in this build.');
    }
    final offerings = await Purchases.getOfferings();
    final package = offerings.current?.monthly;
    if (package == null) {
      throw const SubscriptionException(
          'The monthly subscription is not available in the store right now.');
    }
    final result = await Purchases.purchase(PurchaseParams.package(package));
    final active =
        result.customerInfo.entitlements.active.containsKey(proEntitlement);
    if (!active) {
      throw const SubscriptionException(
        'The store did not confirm the Ledgerly Pro entitlement. Nothing has been unlocked.',
      );
    }
    // RevenueCat webhooks are asynchronous. Supabase remains the authority:
    // never grant premium from client-side CustomerInfo alone.
    for (var attempt = 0; attempt < 8; attempt++) {
      await refreshEntitlement();
      if (_isPro) return true;
      if (attempt < 7) await Future.delayed(const Duration(seconds: 2));
    }
    throw const SubscriptionException(
      'The store confirmed your purchase, but Ledgerly has not received the verified subscription update yet. '
      'Your payment is not lost; wait a moment and refresh payment status.',
    );
  }

  Future<void> restoreMobilePurchases() async {
    _requireBackend();
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw const SubscriptionException(
        'Sign in to your Ledgerly account before restoring purchases.',
        code: 'sign_in_required',
      );
    }
    await _configureRevenueCat(user.id);
    if (!_revenueCatConfigured) {
      throw const SubscriptionException(
          'Store purchases are not configured in this build.');
    }
    final info = await Purchases.restorePurchases();
    final hasProviderEntitlement =
        info.entitlements.active.containsKey(proEntitlement);
    // A restore proves the store purchase exists, but access is granted only
    // after RevenueCat writes the matching account entitlement to Supabase.
    for (var attempt = 0; attempt < 8; attempt++) {
      await refreshEntitlement();
      if (_isPro) return;
      if (attempt < 7) await Future.delayed(const Duration(seconds: 2));
    }
    if (hasProviderEntitlement) {
      throw const SubscriptionException(
        'Your store purchase was found, but the verified Ledgerly entitlement has not synced yet. '
        'Please wait and refresh again.',
      );
    }
    throw const SubscriptionException(
        'No active Ledgerly Pro purchase was found for this store account.');
  }

  /// Opens PayPal's approval page for a server-created subscription.
  ///
  /// Returns true when a browser or window was opened. Opening the page is not
  /// proof of payment: [hasPendingApproval] is set so the UI keeps asking the
  /// backend for the verified result.
  Future<bool> launchPayPalSubscription() async {
    _requireBackend();
    if (Supabase.instance.client.auth.currentUser == null) {
      throw const SubscriptionException(
        'Sign in to your Ledgerly account before subscribing.',
        code: 'sign_in_required',
      );
    }
    try {
      final response = await Supabase.instance.client.functions
          .invoke('paypal-create-subscription');
      final data = response.data;
      if (data is! Map || data['approvalUrl'] is! String) {
        final code = data is Map ? data['code'] as String? : null;
        throw SubscriptionException(subscriptionErrorMessage(code), code: code);
      }
      final uri = Uri.tryParse(data['approvalUrl'] as String);
      const paypalHosts = {
        'www.paypal.com',
        'www.sandbox.paypal.com',
        'paypal.com',
        'sandbox.paypal.com',
      };
      if (uri == null ||
          uri.scheme != 'https' ||
          !paypalHosts.contains(uri.host)) {
        throw const SubscriptionException(
            'PayPal returned an invalid checkout address. No payment has been taken.');
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened) {
        _pendingApproval = true;
        _errorMessage = null;
        notifyListeners();
      }
      return opened;
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['code'] as String? : null;
      throw SubscriptionException(subscriptionErrorMessage(code), code: code);
    }
  }

  /// Clears a stale "payment pending" banner after the customer dismisses it.
  void dismissPendingApproval() {
    if (!_pendingApproval) return;
    _pendingApproval = false;
    notifyListeners();
  }

  Future<void> activatePro({
    required String planType,
    String? subscriptionId,
    bool isTrial = false,
    Duration? customDuration,
  }) async {
    throw UnsupportedError(
        'Manual Pro activation is disabled for payment security.');
  }

  Future<void> toggleDemoPro() async {
    throw UnsupportedError('Demo Pro activation is disabled.');
  }

  Future<void> cancelSubscription() async {
    throw UnsupportedError(
        'Manage or cancel your subscription with the original payment provider.');
  }
}
