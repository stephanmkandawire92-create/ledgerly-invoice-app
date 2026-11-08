import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly/services/entitlement_evaluator.dart';

void main() {
  final now = DateTime.utc(2026, 11, 8, 12);

  Map<String, dynamic> row({
    String status = 'active',
    String? periodEnd = '2026-12-08T12:00:00Z',
    String provider = 'paypal',
    String id = 'I-1',
  }) =>
      {
        'provider': provider,
        'external_subscription_id': id,
        'status': status,
        'current_period_end': periodEnd,
      };

  group('evaluateSubscriptionRows', () {
    test('an active subscription inside its period grants Pro', () {
      final result = evaluateSubscriptionRows([row()], now);
      expect(result.isPro, isTrue);
      expect(result.provider, 'paypal');
      expect(result.subscriptionId, 'I-1');
      expect(result.periodEnd, DateTime.utc(2026, 12, 8, 12));
    });

    test('an active subscription with no period end grants Pro', () {
      expect(evaluateSubscriptionRows([row(periodEnd: null)], now).isPro, isTrue);
    });

    test('an active subscription past its period end does not grant Pro', () {
      expect(
        evaluateSubscriptionRows(
            [row(periodEnd: '2026-10-01T00:00:00Z')], now).isPro,
        isFalse,
      );
    });

    test('a cancelled subscription keeps Pro until the paid-through date', () {
      expect(evaluateSubscriptionRows([row(status: 'cancelled')], now).isPro,
          isTrue);
      expect(
        evaluateSubscriptionRows(
                [row(status: 'cancelled', periodEnd: '2026-10-01T00:00:00Z')],
                now)
            .isPro,
        isFalse,
      );
      expect(
        evaluateSubscriptionRows([row(status: 'cancelled', periodEnd: null)], now)
            .isPro,
        isFalse,
      );
    });

    test('pending, past_due, suspended and expired never grant Pro', () {
      for (final status in ['pending', 'past_due', 'suspended', 'expired']) {
        expect(evaluateSubscriptionRows([row(status: status)], now).isPro,
            isFalse,
            reason: status);
      }
    });

    test('an empty list means no entitlement', () {
      final result = evaluateSubscriptionRows([], now);
      expect(result.isPro, isFalse);
      expect(result.status, isNull);
    });

    test('malformed timestamps are treated as unusable', () {
      expect(evaluateSubscriptionRows([row(periodEnd: 'not-a-date')], now).isPro,
          isFalse);
    });

    test('a valid row wins over an invalid but newer-looking row', () {
      final result = evaluateSubscriptionRows([
        row(status: 'expired', id: 'I-EXPIRED'),
        row(status: 'active', id: 'I-ACTIVE'),
      ], now);
      expect(result.isPro, isTrue);
      expect(result.subscriptionId, 'I-ACTIVE');
    });

    test('an active row is preferred over a cancelled one', () {
      final result = evaluateSubscriptionRows([
        row(status: 'cancelled', id: 'I-CANCELLED'),
        row(status: 'active', id: 'I-ACTIVE'),
      ], now);
      expect(result.subscriptionId, 'I-ACTIVE');
      expect(result.status, 'active');
    });

    test('the later expiry wins between two valid rows', () {
      final result = evaluateSubscriptionRows([
        row(periodEnd: '2026-11-20T00:00:00Z', id: 'I-SOON'),
        row(periodEnd: '2026-12-20T00:00:00Z', id: 'I-LATER'),
      ], now);
      expect(result.subscriptionId, 'I-LATER');
    });

    test('a RevenueCat row is evaluated the same way as PayPal', () {
      final result = evaluateSubscriptionRows(
        [row(provider: 'revenuecat', id: 'rc-1')],
        now,
      );
      expect(result.isPro, isTrue);
      expect(result.provider, 'revenuecat');
    });
  });

  group('describePayPalReturn', () {
    test('recognises the return destination', () {
      expect(
        describePayPalReturn(
            Uri.parse('https://app.ledgerly.test/billing/paypal/return?token=I-1')),
        PayPalReturnSignal.approved,
      );
    });

    test('recognises the cancel destination', () {
      expect(
        describePayPalReturn(
            Uri.parse('https://app.ledgerly.test/billing/paypal/cancel')),
        PayPalReturnSignal.cancelled,
      );
      expect(
        describePayPalReturn(
            Uri.parse('https://app.ledgerly.test/checkout?paypal=cancelled')),
        PayPalReturnSignal.cancelled,
      );
    });

    test('ignores unrelated routes', () {
      expect(describePayPalReturn(Uri.parse('https://app.ledgerly.test/')),
          PayPalReturnSignal.none);
      expect(
        describePayPalReturn(Uri.parse('https://app.ledgerly.test/invoices/12')),
        PayPalReturnSignal.none,
      );
    });

    test('does not treat a query token as a status', () {
      expect(
        describePayPalReturn(
            Uri.parse('https://app.ledgerly.test/?token=I-1&ba_token=BA-1')),
        PayPalReturnSignal.none,
      );
    });
  });

  group('subscriptionStatusLabel', () {
    test('labels every documented status', () {
      expect(subscriptionStatusLabel('active'), 'Active');
      expect(subscriptionStatusLabel('cancelled'), contains('Cancelled'));
      expect(subscriptionStatusLabel('past_due'), 'Payment failed');
      expect(subscriptionStatusLabel('suspended'), 'Suspended');
      expect(subscriptionStatusLabel('expired'), 'Expired');
      expect(subscriptionStatusLabel('pending'), contains('Awaiting'));
      expect(subscriptionStatusLabel(null), 'No subscription');
    });
  });
}
