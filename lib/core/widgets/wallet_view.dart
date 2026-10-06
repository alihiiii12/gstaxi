import 'package:flutter/material.dart';

import '../../Customer/view/widgets/customer_ui_theme.dart';

String formatWalletMoney(num v) {
  final s = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
  return s.replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
}

String walletCurrencyLabel(String c) => c == 'SYP' ? 'ل.س' : c;

/// محتوى شاشة المحفظة (الرصيد + ملاحظة + سجل الحركات) — مشترك بين السائق والراكب.
class WalletView extends StatelessWidget {
  const WalletView({
    super.key,
    required this.loading,
    required this.error,
    required this.balance,
    required this.currency,
    required this.note,
    required this.transactions,
    required this.onRefresh,
  });

  final bool loading;
  final String error;
  final double balance;
  final String currency;
  final String note;
  final List<Map<String, dynamic>> transactions;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (loading && transactions.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: CustomerUiTheme.navy),
      );
    }
    if (error.isNotEmpty && transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: CustomerUiTheme.navy),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onRefresh,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: CustomerUiTheme.navy,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            decoration: CustomerUiTheme.glassCard(radius: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'الرصيد الحالي',
                  style: TextStyle(
                    color: CustomerUiTheme.muted.withValues(alpha: 0.95),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatWalletMoney(balance)} ${walletCurrencyLabel(currency)}',
                  style: const TextStyle(
                    color: CustomerUiTheme.navy,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: CustomerUiTheme.amber.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: CustomerUiTheme.navy,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            note,
                            style: const TextStyle(
                              color: CustomerUiTheme.navy,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'سجل الحركات',
            style: TextStyle(
              color: CustomerUiTheme.navy,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: CustomerUiTheme.glassCard(radius: 20),
                child: const Text(
                  'لا توجد حركات بعد',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: CustomerUiTheme.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            ...transactions.map((tx) => _WalletTxTile(tx: tx)),
        ],
      ),
    );
  }
}

class _WalletTxTile extends StatelessWidget {
  const _WalletTxTile({required this.tx});

  final Map<String, dynamic> tx;

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse('${tx['amount']}') ?? 0.0;
    final positive = amount >= 0;
    final label = tx['type_label']?.toString() ?? tx['type']?.toString() ?? '';
    final note = tx['note']?.toString() ?? '';
    final party = tx['counterparty_label']?.toString() ?? '';
    final after = double.tryParse('${tx['balance_after']}') ?? 0.0;
    final created = tx['created_at']?.toString() ?? '';
    DateTime? dt;
    try {
      if (created.isNotEmpty) dt = DateTime.parse(created).toLocal();
    } catch (_) {}
    final dateStr = dt == null
        ? created
        : '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: CustomerUiTheme.glassCard(radius: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (positive
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFEF4444))
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                positive
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: positive
                    ? const Color(0xFF15803D)
                    : const Color(0xFFB91C1C),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: CustomerUiTheme.navy,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  if (party.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 15,
                          color: CustomerUiTheme.navy.withValues(alpha: 0.75),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            party,
                            style: TextStyle(
                              color: CustomerUiTheme.navy.withValues(alpha: 0.9),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: TextStyle(
                        color: CustomerUiTheme.muted.withValues(alpha: 0.95),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (dateStr.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: TextStyle(
                        color: CustomerUiTheme.muted.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${positive ? '+' : ''}${formatWalletMoney(amount)}',
                  style: TextStyle(
                    color: positive
                        ? const Color(0xFF15803D)
                        : const Color(0xFFB91C1C),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'رصيد ${formatWalletMoney(after)}',
                  style: TextStyle(
                    color: CustomerUiTheme.muted.withValues(alpha: 0.85),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
