import 'package:flutter/material.dart';
import '../models/business_document.dart';
import '../models/currency_helper.dart';
import '../models/payment.dart';
import '../services/subscription_service.dart';
import 'paywall_screen.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({
    super.key,
    required this.documents,
    required this.payments,
    required this.currencyCode,
    required this.langCode,
  });

  final List<BusinessDocument> documents;
  final List<Payment> payments;
  final String currencyCode;
  final String langCode;

  bool _isReportableInvoice(BusinessDocument d) =>
      d.kind == DocumentKind.invoice &&
      d.currencyCode.toUpperCase() == currencyCode.toUpperCase() &&
      !['Void', 'Draft'].contains(d.status);

  BusinessDocument? _invoiceForPayment(Payment payment) {
    for (final document in documents) {
      if (document.id == payment.invoiceId &&
          document.kind == DocumentKind.invoice) {
        return document;
      }
    }
    return null;
  }

  double _paidForInvoice(String invoiceId) => payments
      .where(
          (p) => p.invoiceId == invoiceId && p.amount.isFinite && p.amount > 0)
      .fold<double>(0, (sum, p) => sum + p.amount);

  double get _totalInvoiced => documents
      .where(_isReportableInvoice)
      .fold(0.0, (sum, d) => sum + d.total);

  double get _totalCollected => payments.fold<double>(0, (sum, p) {
        final invoice = _invoiceForPayment(p);
        if (invoice == null ||
            invoice.currencyCode.toUpperCase() != currencyCode.toUpperCase() ||
            p.amount.isNaN ||
            p.amount.isInfinite ||
            p.amount <= 0) {
          return sum;
        }
        return sum + p.amount;
      });

  double get _totalOutstanding =>
      documents.where(_isReportableInvoice).fold<double>(0, (sum, d) {
        final remaining =
            (d.total - _paidForInvoice(d.id)).clamp(0.0, d.total).toDouble();
        return sum + remaining;
      });

  int get _overdueCount => documents
      .where((d) =>
          _isReportableInvoice(d) &&
          effectiveInvoiceStatus(d, payments) == 'Overdue')
      .length;

  int get _totalQuotes =>
      documents.where((d) => d.kind == DocumentKind.quote).length;

  int get _acceptedQuotes => documents
      .where((d) => d.kind == DocumentKind.quote && d.status == 'Accepted')
      .length;

  double get _conversionRate =>
      _totalQuotes > 0 ? (_acceptedQuotes / _totalQuotes) * 100 : 0.0;

  Map<String, double> get _clientRevenueMap {
    final Map<String, double> map = {};
    for (final doc in documents.where(_isReportableInvoice)) {
      final name = doc.clientName.trim().isEmpty
          ? 'Unnamed Client'
          : doc.clientName.trim();
      map[name] = (map[name] ?? 0.0) + doc.total;
    }
    return map;
  }

  Map<String, double> get _paymentMethodMap {
    final Map<String, double> map = {};
    for (final p in payments) {
      final invoice = _invoiceForPayment(p);
      if (invoice == null ||
          invoice.currencyCode.toUpperCase() != currencyCode.toUpperCase() ||
          !p.amount.isFinite ||
          p.amount <= 0) {
        continue;
      }
      map[p.method] = (map[p.method] ?? 0.0) + p.amount;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final topClients = _clientRevenueMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final paymentMethods = _paymentMethodMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListenableBuilder(
      listenable: SubscriptionService.instance,
      builder: (context, _) {
        final isPro = SubscriptionService.instance.isPro;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(wide ? 34 : 18, 24, wide ? 34 : 18, 90),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isPro)
                    Container(
                      margin: const EdgeInsets.only(bottom: 22),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4338CA), Color(0xFF6366F1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF4F46E5).withValues(alpha: 0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.workspace_premium_rounded,
                                color: Color(0xFFFBBF24), size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Unlock Full Financial Analytics with Pro',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Upgrade with PayPal Subscription for in-depth client velocity, payment trends, and unlimited invoices.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFFFFC439), // PayPal Gold
                              foregroundColor: const Color(0xFF003087),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                            onPressed: () => PaywallScreen.showPaywall(
                              context,
                              featurePrompt:
                                  'Unlock Advanced Financial & Client Analytics',
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bolt_rounded, size: 18),
                                SizedBox(width: 4),
                                Text('Upgrade',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    'Company Performance & Analytics',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: const Color(0xFF172033),
                        fontSize: wide ? 30 : 25),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                      'Real-time insights into revenue, conversion rates, client performance, and cash flow.'),
                  const SizedBox(height: 20),
                  // Top Metrics Cards
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth > 800
                          ? 4
                          : constraints.maxWidth > 520
                              ? 2
                              : 1;
                      return GridView.count(
                        crossAxisCount: cols,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: cols == 1
                            ? 3.0
                            : cols == 2
                                ? 1.9
                                : 1.5,
                        children: [
                          _AnalyticsCard(
                            title: 'Total Revenue Billed',
                            value: CurrencyHelper.format(
                                _totalInvoiced, currencyCode),
                            icon: Icons.trending_up_rounded,
                            color: const Color(0xFF4F46E5),
                            caption:
                                '${documents.where((d) => d.kind == DocumentKind.invoice && d.status != 'Void' && d.status != 'Draft' && d.currencyCode.toUpperCase() == currencyCode.toUpperCase()).length} Invoices',
                          ),
                          _AnalyticsCard(
                            title: 'Total Cash Collected',
                            value: CurrencyHelper.format(
                                _totalCollected, currencyCode),
                            icon: Icons.check_circle_outline_rounded,
                            color: const Color(0xFF0E9F6E),
                            caption: '${payments.length} Payments Received',
                          ),
                          _AnalyticsCard(
                            title: 'Outstanding Balance',
                            value: CurrencyHelper.format(
                                _totalOutstanding, currencyCode),
                            icon: Icons.account_balance_wallet_outlined,
                            color: const Color(0xFFB54708),
                            caption:
                                'Unpaid Receivables ($_overdueCount Overdue)',
                          ),
                          _AnalyticsCard(
                            title: 'Quote Conversion',
                            value: '${_conversionRate.toStringAsFixed(1)}%',
                            icon: Icons.pie_chart_outline_rounded,
                            color: const Color(0xFF7E22CE),
                            caption:
                                '$_acceptedQuotes of $_totalQuotes Quotes Accepted',
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  // Conversion & Overdue Stats Row
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Quotation Conversion Funnel',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                                const SizedBox(height: 12),
                                LinearProgressIndicator(
                                  value: _totalQuotes > 0
                                      ? _acceptedQuotes / _totalQuotes
                                      : 0.0,
                                  minHeight: 10,
                                  borderRadius: BorderRadius.circular(5),
                                  backgroundColor: const Color(0xFFE9ECF3),
                                  color: const Color(0xFF4F46E5),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Total Quotes: $_totalQuotes'),
                                    Text('Accepted: $_acceptedQuotes'),
                                    Text(
                                      'Conversion: ${_conversionRate.toStringAsFixed(1)}%',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF4F46E5)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 750;
                      return isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    child: _buildTopClientsCard(
                                        context, topClients,
                                        isPro: isPro)),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: _buildPaymentMethodsCard(
                                        context, paymentMethods,
                                        isPro: isPro)),
                              ],
                            )
                          : Column(
                              children: [
                                _buildTopClientsCard(context, topClients,
                                    isPro: isPro),
                                const SizedBox(height: 16),
                                _buildPaymentMethodsCard(
                                    context, paymentMethods,
                                    isPro: isPro),
                              ],
                            );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopClientsCard(
      BuildContext context, List<MapEntry<String, double>> topClients,
      {required bool isPro}) {
    final maxVal = topClients.isNotEmpty ? topClients.first.value : 1.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Top Billed Clients',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                if (!isPro)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 12, color: Color(0xFF6366F1)),
                        SizedBox(width: 4),
                        Text('PRO',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6366F1))),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (topClients.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('No invoice history available yet.'),
              )
            else if (!isPro)
              Column(
                children: [
                  // Show only 1 preview item
                  if (topClients.isNotEmpty) ...[
                    Builder(
                      builder: (_) {
                        final item = topClients.first;
                        final pct = (item.value / maxVal).clamp(0.0, 1.0);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(item.key,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                Text(CurrencyHelper.format(
                                    item.value, currencyCode)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: pct,
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(3),
                              backgroundColor: const Color(0xFFF0F2FF),
                              color: const Color(0xFF4F46E5),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.lock_rounded,
                            color: Color(0xFF6366F1), size: 24),
                        const SizedBox(height: 6),
                        const Text(
                          'Full client ranking is a Pro feature',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Subscribe with PayPal to see lifetime revenue, payment velocity, and repeat clients.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Color(0xFF64748B), fontSize: 11),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          onPressed: () => PaywallScreen.showPaywall(
                            context,
                            featurePrompt:
                                'Unlock Client Revenue Analytics with PayPal Subscription',
                          ),
                          child: const Text('Unlock Top Clients'),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: topClients.take(5).length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final item = topClients[idx];
                  final pct = (item.value / maxVal).clamp(0.0, 1.0);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(item.key,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text(CurrencyHelper.format(item.value, currencyCode)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                        backgroundColor: const Color(0xFFF0F2FF),
                        color: const Color(0xFF4F46E5),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodsCard(
      BuildContext context, List<MapEntry<String, double>> paymentMethods,
      {required bool isPro}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Collections by Payment Method',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                if (!isPro)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 12, color: Color(0xFF6366F1)),
                        SizedBox(width: 4),
                        Text('PRO',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6366F1))),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (paymentMethods.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('No payment collections recorded yet.'),
              )
            else if (!isPro)
              Column(
                children: [
                  // Show 1 item
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor:
                          const Color(0xFF0E9F6E).withValues(alpha: 0.1),
                      foregroundColor: const Color(0xFF0E9F6E),
                      child: const Icon(Icons.payments_outlined, size: 20),
                    ),
                    title: Text(paymentMethods.first.key,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: Text(
                      CurrencyHelper.format(
                          paymentMethods.first.value, currencyCode),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.pie_chart_outline_rounded,
                            color: Color(0xFF6366F1), size: 24),
                        const SizedBox(height: 6),
                        const Text(
                          'Payment distribution breakdown is locked',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Track cash vs bank transfer vs PayPal intake trends with Pro.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Color(0xFF64748B), fontSize: 11),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          onPressed: () => PaywallScreen.showPaywall(
                            context,
                            featurePrompt:
                                'Unlock Payment Method Distribution with PayPal Subscription',
                          ),
                          child: const Text('Unlock Breakdown'),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: paymentMethods.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final item = paymentMethods[idx];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor:
                          const Color(0xFF0E9F6E).withValues(alpha: 0.1),
                      foregroundColor: const Color(0xFF0E9F6E),
                      child: const Icon(Icons.payments_outlined, size: 20),
                    ),
                    title: Text(item.key,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: Text(
                      CurrencyHelper.format(item.value, currencyCode),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.caption,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String caption;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const Spacer(),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  Text(caption,
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF7B8497))),
                ],
              ),
            ],
          ),
        ),
      );
}
