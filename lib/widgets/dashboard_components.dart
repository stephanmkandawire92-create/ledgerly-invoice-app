import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/business_document.dart';
import '../models/currency_helper.dart';
import '../services/app_translations.dart';
import '../services/subscription_service.dart';
import '../screens/paywall_screen.dart';

const _brand = Color(0xFF4F46E5);
const _ink = Color(0xFF172033);
const _muted = Color(0xFF7B8497);
const _line = Color(0xFFE9ECF3);

class LedgerlyTopBar extends StatelessWidget {
  const LedgerlyTopBar({
    required this.wide,
    required this.searchController,
    required this.langCode,
    required this.onNewInvoice,
    required this.onNewQuote,
    required this.onMenu,
  });

  final bool wide;
  final TextEditingController searchController;
  final String langCode;
  final VoidCallback onNewInvoice;
  final VoidCallback onNewQuote;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: wide ? 34 : 18, vertical: 16),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _line))),
        child: Row(
          children: [
            if (!wide)
              IconButton(
                  onPressed: onMenu, icon: const Icon(Icons.menu_rounded)),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: _brand, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white, size: 21),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ledgerly',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                        color: _ink,
                        letterSpacing: -0.5)),
                Text('GLOBAL INVOICING & ANALYTICS',
                    style: TextStyle(
                        fontSize: 8,
                        letterSpacing: 1.1,
                        color: _muted,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const Spacer(),
            ListenableBuilder(
              listenable: SubscriptionService.instance,
              builder: (context, _) {
                final isPro = SubscriptionService.instance.isPro;
                return InkWell(
                  onTap: () => PaywallScreen.showPaywall(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isPro
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isPro
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF6366F1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.workspace_premium_rounded,
                          color: isPro
                              ? const Color(0xFFD97706)
                              : const Color(0xFF4F46E5),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isPro ? 'PRO' : 'UPGRADE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isPro
                                ? const Color(0xFFB45309)
                                : const Color(0xFF4F46E5),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (wide)
              SizedBox(
                width: 260,
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: AppTranslations.get('searchDocuments', langCode),
                    prefixIcon: const Icon(Icons.search, size: 19),
                    isDense: true,
                  ),
                ),
              ),
            if (wide) const SizedBox(width: 12),
            if (wide)
              PopupMenuButton<String>(
                tooltip: AppTranslations.get('create', langCode),
                onSelected: (value) =>
                    value == 'invoice' ? onNewInvoice() : onNewQuote(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'invoice',
                      child: Text(AppTranslations.get('newInvoice', langCode))),
                  PopupMenuItem(
                      value: 'quote',
                      child: Text(AppTranslations.get('newQuote', langCode))),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                      color: _brand, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 18, color: Colors.white),
                      const SizedBox(width: 7),
                      Text(AppTranslations.get('create', langCode),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              )
            else
              IconButton(
                tooltip: AppTranslations.get('newInvoice', langCode),
                onPressed: onNewInvoice,
                icon: const Icon(Icons.add_circle, color: _brand, size: 28),
              ),
          ],
        ),
      );
}

class LedgerlySideNavigation extends StatelessWidget {
  const LedgerlySideNavigation({
    required this.section,
    required this.langCode,
    required this.documentCount,
    required this.onSelect,
  });

  final String section;
  final String langCode;
  final int documentCount;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Container(
        width: 245,
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: _line))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 16, 12, 20),
              child: Text('WORKSPACE',
                  style: TextStyle(
                      fontSize: 10,
                      color: _muted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4)),
            ),
            ...[
              ('Overview', Icons.space_dashboard_outlined),
              ('Invoices', Icons.receipt_long_outlined),
              ('Quotes', Icons.request_quote_outlined),
              ('Follow-ups', Icons.notifications_none),
              ('Clients', Icons.people_outline),
              ('Items', Icons.inventory_2_outlined),
              ('Payments', Icons.payments_outlined),
              ('Analytics', Icons.analytics_outlined),
              ('Settings', Icons.settings_outlined),
            ].map((item) {
              final selected = section == item.$1;
              final label = item.$1 == 'Analytics'
                  ? 'Analytics'
                  : item.$1 == 'Follow-ups'
                      ? AppTranslations.get('followUps', langCode)
                      : AppTranslations.get(item.$1.toLowerCase(), langCode);
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  selected: selected,
                  selectedTileColor: const Color(0xFFEEEDFF),
                  selectedColor: _brand,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                  leading: Icon(item.$2, size: 20),
                  title: Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500)),
                  onTap: () => onSelect(item.$1),
                ),
              );
            }),
            const Spacer(),
            ListenableBuilder(
              listenable: SubscriptionService.instance,
              builder: (context, _) {
                final isPro = SubscriptionService.instance.isPro;
                final remaining = SubscriptionService.instance
                    .remainingFreeDocuments(documentCount);
                final used = documentCount > 5 ? 5 : documentCount;

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isPro
                        ? const Color(0xFFF0FDF4)
                        : const Color(0xFFF7F7FF),
                    border: Border.all(
                      color: isPro
                          ? const Color(0xFFBBF7D0)
                          : const Color(0xFFE8E6FF),
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isPro
                                ? Icons.workspace_premium_rounded
                                : Icons.shield_outlined,
                            color: isPro ? const Color(0xFF16A34A) : _brand,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isPro ? 'Ledgerly Pro' : 'Free Plan',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isPro ? const Color(0xFF166534) : _ink,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (isPro) ...[
                        const Text(
                          'Unlimited invoices & quotes, no watermark, PayPal subscribed.',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF166534),
                              height: 1.4),
                        ),
                      ] else ...[
                        Text(
                          '$used of 5 free documents used ($remaining left)',
                          style: const TextStyle(fontSize: 11, color: _muted),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (used / 5).clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: const Color(0xFFE2E8F0),
                            color: _brand,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFFFFC439), // PayPal Gold
                              foregroundColor: const Color(0xFF003087),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => PaywallScreen.showPaywall(context),
                            child: const Text('Upgrade Pro',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 12)),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      );
}

class LedgerlyMetricCard extends StatelessWidget {
  const LedgerlyMetricCard(
      {required this.title,
      required this.value,
      required this.icon,
      required this.color,
      required this.caption});

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
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, color: color, size: 18)),
                  const Spacer(),
                  const Icon(Icons.more_horiz,
                      color: Color(0xFFB0B7C5), size: 20),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          letterSpacing: -.6)),
                  const SizedBox(height: 3),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _ink)),
                  Text(caption,
                      style: const TextStyle(fontSize: 10, color: _muted)),
                ],
              ),
            ],
          ),
        ),
      );
}

class LedgerlyDocumentRow extends StatelessWidget {
  const LedgerlyDocumentRow({
    required this.document,
    required this.onOpen,
    required this.onPdf,
    required this.onShare,
    required this.onDelete,
    this.displayStatus,
  });

  final BusinessDocument document;
  final String? displayStatus;
  final VoidCallback onOpen;
  final VoidCallback onPdf;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  String get _status => displayStatus ?? document.status;

  Color get _statusColor => switch (_status) {
        'Paid' || 'Accepted' => const Color(0xFF027A48),
        'Overdue' || 'Declined' => const Color(0xFFB42318),
        'Sent' || 'Pending' => const Color(0xFFB54708),
        _ => const Color(0xFF667085),
      };

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: const Color(0xFFF0F2FF),
                      borderRadius: BorderRadius.circular(11)),
                  child: Icon(
                      document.kind == DocumentKind.invoice
                          ? Icons.receipt_long_outlined
                          : Icons.request_quote_outlined,
                      color: _brand)),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        document.clientName.isEmpty
                            ? 'Unnamed client'
                            : document.clientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: _ink)),
                    const SizedBox(height: 4),
                    Text(
                        '${document.number} • ${DateFormat('d MMM yyyy').format(document.issueDate)}',
                        style: const TextStyle(fontSize: 11, color: _muted)),
                  ],
                ),
              ),
              if (MediaQuery.sizeOf(context).width > 620)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: LedgerlyStatusPill(label: _status, color: _statusColor),
                  ),
                ),
              Text(CurrencyHelper.format(document.total, document.currencyCode),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: _ink)),
              IconButton(
                tooltip: 'Share via WhatsApp, Email, etc.',
                icon: const Icon(Icons.share_rounded, size: 20, color: _brand),
                onPressed: onShare,
              ),
              PopupMenuButton<String>(
                tooltip: 'Document actions',
                onSelected: (value) {
                  if (value == 'edit') onOpen();
                  if (value == 'pdf') onPdf();
                  if (value == 'share') onShare();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'pdf', child: Text('View / Print PDF')),
                  PopupMenuItem(
                      value: 'share',
                      child: Text('Share via Email / WhatsApp')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      );
}

class LedgerlyStatusPill extends StatelessWidget {
  const LedgerlyStatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 11),
        ),
      );
}

class LedgerlyEmptyState extends StatelessWidget {
  const LedgerlyEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                        color: _brand.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(16)),
                    child: Icon(icon, color: _brand, size: 28),
                  ),
                  const SizedBox(height: 16),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _ink)),
                  const SizedBox(height: 6),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _muted, height: 1.4)),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: onAction,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(actionLabel),
                      ),
                      if (secondaryLabel != null && onSecondary != null)
                        OutlinedButton(
                            onPressed: onSecondary,
                            child: Text(secondaryLabel!)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
