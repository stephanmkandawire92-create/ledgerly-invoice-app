/// Pure helpers that turn server rows into a client-side entitlement view.
///
/// The backend is the authority: these helpers never grant access on their
/// own, they only read what Supabase already decided. Keeping them free of
/// Flutter and Supabase imports makes the access rules unit-testable.
library;

/// What the customer is entitled to according to the last server response.
class SubscriptionEntitlement {
  const SubscriptionEntitlement({
    required this.isPro,
    this.provider,
    this.subscriptionId,
    this.status,
    this.periodEnd,
  });

  /// The account has no usable subscription.
  static const SubscriptionEntitlement none = SubscriptionEntitlement(
    isPro: false,
  );

  final bool isPro;
  final String? provider;
  final String? subscriptionId;
  final String? status;
  final DateTime? periodEnd;

  bool get isCancelledButActive => isPro && status == 'cancelled';

  @override
  String toString() =>
      'SubscriptionEntitlement(isPro: $isPro, provider: $provider, status: $status, periodEnd: $periodEnd)';
}

/// A provider row as returned by `subscription_entitlements`.
typedef EntitlementRow = Map<String, dynamic>;

/// A period end that is absent, present, or present but unparseable. The
/// distinction matters: an `active` row with no period end is open-ended, but
/// an `active` row with a corrupt timestamp must never grant indefinite access.
({DateTime? value, bool malformed}) _readPeriodEnd(Object? raw) {
  if (raw == null) return (value: null, malformed: false);
  if (raw is! String || raw.trim().isEmpty) {
    return (value: null, malformed: false);
  }
  final parsed = DateTime.tryParse(raw)?.toUtc();
  return (value: parsed, malformed: parsed == null);
}

/// A row grants access when it is `active` (open-ended or within period) or
/// `cancelled` but still inside its paid-through window. `expired`,
/// `suspended`, `past_due` and `pending` never grant access.
bool rowGrantsAccess(EntitlementRow row, DateTime now) {
  final status = row['status'];
  if (status is! String) return false;
  final end = _readPeriodEnd(row['current_period_end']);
  if (end.malformed) return false;
  switch (status) {
    case 'active':
      return end.value == null || end.value!.isAfter(now);
    case 'cancelled':
      return end.value != null && end.value!.isAfter(now);
    default:
      return false;
  }
}

/// Picks the most favourable valid row. The server already orders rows newest
/// first, but the client must not depend on ordering for an access decision.
SubscriptionEntitlement evaluateSubscriptionRows(
  List<EntitlementRow> rows,
  DateTime now,
) {
  EntitlementRow? best;
  DateTime? bestEnd;
  for (final row in rows) {
    if (!rowGrantsAccess(row, now)) continue;
    final end = _readPeriodEnd(row['current_period_end']).value;
    if (best == null) {
      best = row;
      bestEnd = end;
      continue;
    }
    final status = row['status'];
    final bestStatus = best['status'];
    // Prefer an active subscription over a cancelled one, then the later end.
    if (status == 'active' && bestStatus != 'active') {
      best = row;
      bestEnd = end;
      continue;
    }
    if (status == bestStatus) {
      if (end != null && (bestEnd == null || end.isAfter(bestEnd))) {
        best = row;
        bestEnd = end;
      }
    }
  }
  if (best == null) return SubscriptionEntitlement.none;
  return SubscriptionEntitlement(
    isPro: true,
    provider: best['provider'] as String?,
    subscriptionId: best['external_subscription_id'] as String?,
    status: best['status'] as String?,
    periodEnd: bestEnd,
  );
}

/// What a browser/app return URL from PayPal means.
enum PayPalReturnSignal { none, approved, cancelled }

/// Recognises the return and cancel destinations configured in
/// `PAYPAL_RETURN_URL` / `PAYPAL_CANCEL_URL`. PayPal appends its own query
/// parameters (`subscription_id`, `ba_token`, `token`), so the router key is
/// the final path segment or an explicit `paypal` query parameter.
PayPalReturnSignal describePayPalReturn(Uri uri) {
  final explicit = uri.queryParameters['paypal']?.toLowerCase();
  if (explicit == 'return' || explicit == 'approved' || explicit == 'success') {
    return PayPalReturnSignal.approved;
  }
  if (explicit == 'cancel' || explicit == 'cancelled' || explicit == 'canceled') {
    return PayPalReturnSignal.cancelled;
  }
  final segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
  if (segments.isEmpty) return PayPalReturnSignal.none;
  final last = segments.last.toLowerCase();
  if (last == 'return' || last == 'approved') return PayPalReturnSignal.approved;
  if (last == 'cancel' || last == 'cancelled' || last == 'canceled') {
    return PayPalReturnSignal.cancelled;
  }
  return PayPalReturnSignal.none;
}

/// A customer-facing label for a stored provider status.
String subscriptionStatusLabel(String? status) {
  switch (status) {
    case 'active':
      return 'Active';
    case 'cancelled':
      return 'Cancelled — access until the paid-through date';
    case 'past_due':
      return 'Payment failed';
    case 'suspended':
      return 'Suspended';
    case 'expired':
      return 'Expired';
    case 'pending':
      return 'Awaiting payment confirmation';
    default:
      return 'No subscription';
  }
}
