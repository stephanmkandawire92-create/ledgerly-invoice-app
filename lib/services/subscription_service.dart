import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService instance = SubscriptionService._internal();
  SubscriptionService._internal();

  static const int maxFreeDocuments = 5;
  static const String proEntitlement = 'ledgerly_pro';

  bool _isPro = false;
  bool _initialized = false;
  bool _backendReady = false;
  bool _revenueCatConfigured = false;
  String? _planType;
  String? _subscriptionId;
  DateTime? _expiresAt;
  String? _errorMessage;

  bool get isPro => _isPro;
  bool get isInitialized => _initialized;
  bool get isBackendReady => _backendReady;
  bool get isSignedIn =>
      _backendReady && Supabase.instance.client.auth.currentUser != null;
  String? get currentUserId =>
      _backendReady ? Supabase.instance.client.auth.currentUser?.id : null;
  String? get planType => _planType;
  String? get subscriptionId => _subscriptionId;
  DateTime? get expiresAt => _expiresAt;
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
    _isPro = false;
    _planType = null;
    _subscriptionId = null;
    _expiresAt = null;
    notifyListeners();
  }

  void _requireBackend() {
    if (!_backendReady) {
      throw StateError(
          'Supabase is not configured. Add SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY at build time.');
    }
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

  Future<void> refreshEntitlement() async {
    if (!_backendReady) {
      _isPro = false;
      notifyListeners();
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _isPro = false;
      _planType = null;
      _subscriptionId = null;
      _expiresAt = null;
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
      final now = DateTime.now().toUtc();
      Map<String, dynamic>? eligible;
      for (final row in rows) {
        final status = row['status'] as String?;
        final rawEnd = row['current_period_end'] as String?;
        final end = rawEnd == null ? null : DateTime.tryParse(rawEnd)?.toUtc();
        final withinPeriod = end != null && end.isAfter(now);
        if ((status == 'active' || status == 'cancelled') && withinPeriod) {
          eligible = Map<String, dynamic>.from(row);
          break;
        }
      }
      _isPro = eligible != null;
      _planType = eligible?['provider'] as String?;
      _subscriptionId = eligible?['external_subscription_id'] as String?;
      _expiresAt = eligible?['current_period_end'] == null
          ? null
          : DateTime.tryParse(eligible!['current_period_end'] as String);
      _errorMessage = null;
    } catch (error) {
      _isPro = false;
      _errorMessage = 'Could not verify subscription status. Please try again.';
      debugPrint('Subscription verification failed: $error');
    }
    notifyListeners();
  }

  Future<bool> purchaseMobilePro() async {
    _requireBackend();
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw StateError('Sign in before subscribing.');
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      throw UnsupportedError(
          'App-store purchases are only supported on iOS and Android.');
    }
    await _configureRevenueCat(user.id);
    if (!_revenueCatConfigured) {
      throw StateError('RevenueCat is not configured for this platform.');
    }
    final offerings = await Purchases.getOfferings();
    final package = offerings.current?.monthly;
    if (package == null) {
      throw StateError('No monthly product is configured in RevenueCat.');
    }
    final result = await Purchases.purchase(PurchaseParams.package(package));
    final active =
        result.customerInfo.entitlements.active.containsKey(proEntitlement);
    if (!active) {
      throw StateError(
          'The purchase completed but the Ledgerly Pro entitlement is not active.');
    }
    // RevenueCat webhooks are asynchronous. Supabase remains the authority:
    // never grant premium from client-side CustomerInfo alone.
    for (var attempt = 0; attempt < 8; attempt++) {
      await refreshEntitlement();
      if (_isPro) return true;
      if (attempt < 7) await Future.delayed(const Duration(seconds: 2));
    }
    throw StateError(
      'The store confirmed your purchase, but Ledgerly has not received the verified subscription update yet. '
      'Your payment is not lost; wait a moment and refresh payment status.',
    );
  }

  Future<void> restoreMobilePurchases() async {
    _requireBackend();
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw StateError('Sign in before restoring purchases.');
    await _configureRevenueCat(user.id);
    if (!_revenueCatConfigured) {
      throw StateError('RevenueCat is not configured for this platform.');
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
      throw StateError(
        'Your store purchase was found, but the verified Ledgerly entitlement has not synced yet. '
        'Please wait and refresh again.',
      );
    }
    throw StateError(
        'No active Ledgerly Pro purchase was found for this store account.');
  }

  Future<bool> launchPayPalSubscription() async {
    _requireBackend();
    if (Supabase.instance.client.auth.currentUser == null) {
      throw StateError('Sign in before subscribing.');
    }
    final response = await Supabase.instance.client.functions
        .invoke('paypal-create-subscription');
    final data = response.data;
    if (response.status < 200 ||
        response.status >= 300 ||
        data is! Map ||
        data['approvalUrl'] is! String) {
      throw StateError(data is Map && data['error'] is String
          ? data['error'] as String
          : 'PayPal checkout is not configured.');
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
      throw StateError('PayPal returned an invalid checkout URL.');
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
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
