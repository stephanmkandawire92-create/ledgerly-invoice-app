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
    expect(
      () => sub.activatePro(planType: 'monthly', subscriptionId: 'I-FAKE'),
      throwsUnsupportedError,
    );
    expect(sub.isPro, isFalse);
    expect(sub.canCreateDocument(5), isFalse);
  });

  test('Demo mode cannot grant premium access', () async {
    final sub = SubscriptionService.instance;
    expect(() => sub.toggleDemoPro(), throwsUnsupportedError);
    expect(sub.isPro, isFalse);
  });

  test('Local cancel cannot alter provider-owned subscription state', () async {
    final sub = SubscriptionService.instance;
    expect(() => sub.cancelSubscription(), throwsUnsupportedError);
    expect(sub.isPro, isFalse);
  });
}
