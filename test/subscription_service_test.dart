import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ledgerly/services/subscription_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SubscriptionService.instance.init();
    await SubscriptionService.instance.cancelSubscription();
  });

  test('Free tier allows up to 5 documents', () async {
    final sub = SubscriptionService.instance;
    expect(sub.isPro, isFalse);

    expect(sub.canCreateDocument(0), isTrue);
    expect(sub.canCreateDocument(4), isTrue);
    expect(sub.canCreateDocument(5), isFalse);
    expect(sub.canCreateDocument(6), isFalse);

    expect(sub.remainingFreeDocuments(3), equals(2));
    expect(sub.remainingFreeDocuments(5), equals(0));
    expect(sub.remainingFreeDocuments(10), equals(0));
  });

  test('Activating Pro unlocks unlimited documents', () async {
    final sub = SubscriptionService.instance;

    await sub.activatePro(
      planType: 'monthly',
      subscriptionId: 'I-TEST123456',
    );

    expect(sub.isPro, isTrue);
    expect(sub.planType, equals('monthly'));
    expect(sub.subscriptionId, equals('I-TEST123456'));
    expect(sub.canCreateDocument(5), isTrue);
    expect(sub.canCreateDocument(100), isTrue);
  });

  test('Toggling Demo Pro switches between Pro and Free', () async {
    final sub = SubscriptionService.instance;
    expect(sub.isPro, isFalse);

    await sub.toggleDemoPro();
    expect(sub.isPro, isTrue);

    await sub.toggleDemoPro();
    expect(sub.isPro, isFalse);
  });
}
