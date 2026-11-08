import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly/screens/paywall_screen.dart';
import 'package:ledgerly/services/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpPaywall(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: PaywallScreen()));
  await tester.pumpAndSettle();
}

/// Runs a test body with a simulated platform and always restores the
/// foundation override, even when an expectation fails.
Future<void> withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SubscriptionService.instance.init();
  });

  testWidgets('paywall shows the USD 3 monthly offer', (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      await pumpPaywall(tester);

      expect(find.text('USD 3'), findsOneWidget);
      expect(find.text('per month • recurring subscription'), findsOneWidget);
      expect(find.text('Upgrade to Ledgerly Pro'), findsOneWidget);
      expect(find.text('Unlimited invoices and quotations'), findsOneWidget);
    });
  });

  testWidgets('web and Windows customers are offered PayPal checkout',
      (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      await pumpPaywall(tester);

      expect(find.text('Subscribe securely with PayPal'), findsOneWidget);
      expect(find.text('Subscribe with App Store / Google Play'), findsNothing);
    });
  });

  testWidgets('mobile keeps the app-store flow and drops PayPal',
      (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      await pumpPaywall(tester);

      expect(find.text('Subscribe with App Store / Google Play'), findsOneWidget);
      expect(find.text('Restore purchases'), findsOneWidget);
      expect(find.text('Subscribe securely with PayPal'), findsNothing);
    });
  });

  testWidgets('the paywall never claims success without a verified entitlement',
      (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      await pumpPaywall(tester);

      expect(SubscriptionService.instance.isPro, isFalse);
      expect(find.textContaining('Payment verified'), findsNothing);
      expect(find.text('Your Ledgerly Pro entitlement is active.'), findsNothing);
      expect(find.textContaining('Payment verification pending'), findsNothing);
    });
  });

  testWidgets('an unconfigured backend produces a clear message, not a crash',
      (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      await pumpPaywall(tester);

      await tapVisible(tester, find.text('Subscribe securely with PayPal'));

      expect(find.textContaining('Supabase is not configured'), findsOneWidget);
      expect(find.textContaining('Payment verified'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('checking payment status while signed out asks for sign-in',
      (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      await pumpPaywall(tester);

      await tapVisible(tester, find.text('Check payment status'));

      expect(find.textContaining('Sign in'), findsWidgets);
      expect(find.textContaining('Payment verified'), findsNothing);
    });
  });
}
