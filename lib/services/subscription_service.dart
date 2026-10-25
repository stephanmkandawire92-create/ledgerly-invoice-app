import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionService extends ChangeNotifier {
  static final SubscriptionService instance = SubscriptionService._internal();

  SubscriptionService._internal();

  static const String _keyIsPro = 'ledgerly.pro.is_active';
  static const String _keyPlanType = 'ledgerly.pro.plan_type';
  static const String _keySubscriptionId = 'ledgerly.pro.subscription_id';
  static const String _keySubscribedAt = 'ledgerly.pro.subscribed_at';
  static const String _keyExpiresAt = 'ledgerly.pro.expires_at';
  static const String _keyIsTrial = 'ledgerly.pro.is_trial';
  static const String _keyTrialEndsAt = 'ledgerly.pro.trial_ends_at';
  static const String _keyMonthlyUrl = 'ledgerly.pro.paypal_monthly_url';
  static const String _keyYearlyUrl = 'ledgerly.pro.paypal_yearly_url';
  static const String _keyPayPalAccount = 'ledgerly.pro.paypal_account';

  // Constants
  static const int maxFreeDocuments = 5;
  static const String defaultMonthlyUrl = 'https://www.paypal.com/webapps/billing/plans/subscribe?plan_id=P-MONTHLY-LEDGERLY';
  static const String defaultYearlyUrl = 'https://www.paypal.com/webapps/billing/plans/subscribe?plan_id=P-YEARLY-LEDGERLY';

  bool _isPro = false;
  String? _planType;
  String? _subscriptionId;
  DateTime? _subscribedAt;
  DateTime? _expiresAt;
  bool _isTrial = false;
  DateTime? _trialEndsAt;
  String _paypalMonthlyUrl = defaultMonthlyUrl;
  String _paypalYearlyUrl = defaultYearlyUrl;
  String _paypalAccount = '';
  bool _initialized = false;

  bool get isPro => _isPro;
  String? get planType => _planType;
  String? get subscriptionId => _subscriptionId;
  DateTime? get subscribedAt => _subscribedAt;
  DateTime? get expiresAt => _expiresAt;
  bool get isTrial => _isTrial;
  DateTime? get trialEndsAt => _trialEndsAt;
  String get paypalMonthlyUrl => _paypalMonthlyUrl;
  String get paypalYearlyUrl => _paypalYearlyUrl;
  String get paypalAccount => _paypalAccount;
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();

    _isPro = prefs.getBool(_keyIsPro) ?? false;
    _planType = prefs.getString(_keyPlanType);
    _subscriptionId = prefs.getString(_keySubscriptionId);
    _isTrial = prefs.getBool(_keyIsTrial) ?? false;

    final subStr = prefs.getString(_keySubscribedAt);
    if (subStr != null) _subscribedAt = DateTime.tryParse(subStr);

    final expStr = prefs.getString(_keyExpiresAt);
    if (expStr != null) _expiresAt = DateTime.tryParse(expStr);

    final trialStr = prefs.getString(_keyTrialEndsAt);
    if (trialStr != null) _trialEndsAt = DateTime.tryParse(trialStr);

    _paypalMonthlyUrl = prefs.getString(_keyMonthlyUrl) ?? defaultMonthlyUrl;
    _paypalYearlyUrl = prefs.getString(_keyYearlyUrl) ?? defaultYearlyUrl;
    _paypalAccount = prefs.getString(_keyPayPalAccount) ?? '';

    // Check if trial or subscription has expired
    if (_isPro && _expiresAt != null && DateTime.now().isAfter(_expiresAt!)) {
      _isPro = false;
      await prefs.setBool(_keyIsPro, false);
    }

    _initialized = true;
    notifyListeners();
  }

  bool canCreateDocument(int totalExistingDocuments) {
    if (_isPro) return true;
    return totalExistingDocuments < maxFreeDocuments;
  }

  int remainingFreeDocuments(int totalExistingDocuments) {
    if (_isPro) return 999999;
    final remaining = maxFreeDocuments - totalExistingDocuments;
    return remaining < 0 ? 0 : remaining;
  }

  /// Launch PayPal subscription URL in external browser
  Future<bool> launchPayPalSubscription({
    required bool isYearly,
    bool startTrial = false,
  }) async {
    final baseUrl = isYearly ? _paypalYearlyUrl : _paypalMonthlyUrl;
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return false;

    if (await canLaunchUrl(uri)) {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return launched;
    }
    return false;
  }

  /// Activate Pro access (called after PayPal confirmation or manual ID entry)
  Future<void> activatePro({
    required String planType,
    String? subscriptionId,
    bool isTrial = false,
    Duration? customDuration,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    DateTime expiry;
    if (isTrial) {
      expiry = now.add(const Duration(days: 7));
    } else if (customDuration != null) {
      expiry = now.add(customDuration);
    } else if (planType == 'yearly') {
      expiry = now.add(const Duration(days: 365));
    } else {
      expiry = now.add(const Duration(days: 30));
    }

    _isPro = true;
    _planType = planType;
    _subscriptionId = subscriptionId ?? 'PAYPAL-${now.millisecondsSinceEpoch}';
    _subscribedAt = now;
    _expiresAt = expiry;
    _isTrial = isTrial;
    _trialEndsAt = isTrial ? expiry : null;

    await prefs.setBool(_keyIsPro, true);
    await prefs.setString(_keyPlanType, _planType!);
    await prefs.setString(_keySubscriptionId, _subscriptionId!);
    await prefs.setString(_keySubscribedAt, _subscribedAt!.toIso8601String());
    await prefs.setString(_keyExpiresAt, _expiresAt!.toIso8601String());
    await prefs.setBool(_keyIsTrial, _isTrial);
    if (_trialEndsAt != null) {
      await prefs.setString(_keyTrialEndsAt, _trialEndsAt!.toIso8601String());
    } else {
      await prefs.remove(_keyTrialEndsAt);
    }

    notifyListeners();
  }

  /// Cancel or downgrade subscription
  Future<void> cancelSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    _isPro = false;
    _planType = null;
    _subscriptionId = null;
    _expiresAt = null;
    _isTrial = false;
    _trialEndsAt = null;

    await prefs.setBool(_keyIsPro, false);
    await prefs.remove(_keyPlanType);
    await prefs.remove(_keySubscriptionId);
    await prefs.remove(_keyExpiresAt);
    await prefs.remove(_keyIsTrial);
    await prefs.remove(_keyTrialEndsAt);

    notifyListeners();
  }

  /// Save custom PayPal Plan links and optional account handle/email
  Future<void> savePayPalConfig({
    required String monthlyUrl,
    required String yearlyUrl,
    String? paypalAccount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _paypalMonthlyUrl = monthlyUrl.trim().isEmpty ? defaultMonthlyUrl : monthlyUrl.trim();
    _paypalYearlyUrl = yearlyUrl.trim().isEmpty ? defaultYearlyUrl : yearlyUrl.trim();
    if (paypalAccount != null) {
      _paypalAccount = paypalAccount.trim();
      await prefs.setString(_keyPayPalAccount, _paypalAccount);
    }

    await prefs.setString(_keyMonthlyUrl, _paypalMonthlyUrl);
    await prefs.setString(_keyYearlyUrl, _paypalYearlyUrl);
    notifyListeners();
  }

  /// Automatically generate standard PayPal checkout / subscription URLs from an email or PayPal.Me handle
  static Map<String, String> generatePayPalLinksFromAccount(String input) {
    final clean = input.trim().replaceAll(RegExp(r'^https?://(www\.)?paypal\.me/'), '');
    if (clean.isEmpty) {
      return {'monthly': defaultMonthlyUrl, 'yearly': defaultYearlyUrl};
    }
    if (clean.contains('@')) {
      // Standard PayPal subscription checkout
      final monthly = 'https://www.paypal.com/cgi-bin/webscr?cmd=_xclick-subscriptions&business=${Uri.encodeComponent(clean)}&item_name=Ledgerly%20Pro%20Monthly&a3=4.99&p3=1&t3=M&src=1';
      final yearly = 'https://www.paypal.com/cgi-bin/webscr?cmd=_xclick-subscriptions&business=${Uri.encodeComponent(clean)}&item_name=Ledgerly%20Pro%20Yearly&a3=39.99&p3=1&t3=Y&src=1';
      return {'monthly': monthly, 'yearly': yearly};
    } else {
      // PayPal.Me direct link
      final monthly = 'https://www.paypal.com/paypalme/$clean/4.99USD';
      final yearly = 'https://www.paypal.com/paypalme/$clean/39.99USD';
      return {'monthly': monthly, 'yearly': yearly};
    }
  }

  /// Quick toggle for testing/demo mode
  Future<void> toggleDemoPro() async {
    if (_isPro) {
      await cancelSubscription();
    } else {
      await activatePro(
        planType: 'demo_pro',
        subscriptionId: 'DEMO-${DateTime.now().millisecondsSinceEpoch}',
        customDuration: const Duration(days: 365),
      );
    }
  }
}
