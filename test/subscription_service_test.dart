import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledgerly/services/subscription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SubscriptionService.instance.init();
  });

  test('Free tier allows up to five documents', () {
    final sub = SubscriptionService.instance;
    expect(sub.isPro, isFalse);
    expect(sub.canCreateDocument(0), isTrue);
    expect(sub.canCreateDocument(4), isTrue);
    expect(sub.canCreateDocument(5), isFalse);
    expect(sub.canCreateDocument(6), isFalse);
    expect(sub.remainingFreeDocuments(3), 2);
    expect(sub.remainingFreeDocuments(5), 0);
    expect(sub.remainingFreeDocuments(10), 0);
  });

  test('Premium cannot be enabled through local/manual activation', () async {
    final sub = SubscriptionService.instance;
    await expectLater(
      sub.activatePro(planType: 'monthly', subscriptionId: 'I-FAKE'),
      throwsUnsupportedError,
    );
    expect(sub.isPro, isFalse);
    expect(sub.canCreateDocument(5), isFalse);
  });

  test('Demo mode cannot grant premium access', () async {
    final sub = SubscriptionService.instance;
    await expectLater(sub.toggleDemoPro(), throwsUnsupportedError);
    expect(sub.isPro, isFalse);
  });

  test('Local cancel cannot alter provider-owned subscription state', () async {
    final sub = SubscriptionService.instance;
    await expectLater(sub.cancelSubscription(), throwsUnsupportedError);
    expect(sub.isPro, isFalse);
  });

  test('Backend error codes map to customer-safe messages', () {
    expect(subscriptionErrorMessage('billing_not_configured'),
        contains('not available yet'));
    expect(subscriptionErrorMessage('already_subscribed'),
        contains('already has an active Ledgerly Pro'));
    expect(subscriptionErrorMessage('payment_issue'),
        contains('unpaid balance'));
    expect(subscriptionErrorMessage('account_mismatch'),
        contains('different Ledgerly account'));
    expect(subscriptionErrorMessage('provider_unavailable'),
        contains('temporarily unavailable'));
    expect(subscriptionErrorMessage('checkout_failed'),
        contains('No payment has been taken'));
    expect(subscriptionErrorMessage('something_unexpected'),
        contains('could not confirm'));
  });

  test('Subscription errors are safe to display verbatim', () {
    const error =
        SubscriptionException('Sign in to continue.', code: 'sign_in_required');
    expect(error.toString(), 'Sign in to continue.');
    expect(error.toString().contains('Exception'), isFalse);
  });

  test('A build without a configured backend reports a friendly error',
      () async {
    final sub = SubscriptionService.instance;
    await expectLater(
      sub.launchPayPalSubscription(),
      throwsA(isA<SubscriptionException>()),
    );
    expect(sub.isPro, isFalse);
  });
}
