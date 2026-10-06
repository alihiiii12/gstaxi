import 'dart:async';

import 'package:flutter/material.dart';

import '../services/trip_api_service.dart';
import 'wallet_view.dart';

enum TripPaymentRole { customer, driver }

/// اختيار/عرض طريقة دفع الرحلة على شاشة النتيجة.
/// الراكب: يختار «من المحفظة» أو «كاش». السائق: يرى النتيجة مباشرة عند اختيار الراكب.
class TripPaymentPanel extends StatefulWidget {
  const TripPaymentPanel({
    super.key,
    required this.requestId,
    required this.role,
    required this.canDismiss,
  });

  final int requestId;
  final TripPaymentRole role;

  /// يصبح true عندما يُسمح بإغلاق شاشة النتيجة (بعد الاختيار أو عند تعذر التحميل).
  final ValueNotifier<bool> canDismiss;

  @override
  State<TripPaymentPanel> createState() => _TripPaymentPanelState();
}

class _TripPaymentPanelState extends State<TripPaymentPanel> {
  static const Color _amber = Color(0xFFF5B301);
  static const Duration _driverPollEvery = Duration(seconds: 3);

  Map<String, dynamic>? _payment;
  String? _message;
  bool _loading = true;
  bool _busy = false;
  Timer? _poll;

  bool get _isDriver => widget.role == TripPaymentRole.driver;

  @override
  void initState() {
    super.initState();
    if (_isDriver) widget.canDismiss.value = true;
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  bool get _settled => _payment?['status']?.toString() == 'settled';

  double _num(String key) =>
      double.tryParse('${_payment?[key] ?? 0}') ?? 0.0;

  String _money(double v) => '${formatWalletMoney(v)} ${walletCurrencyLabel('SYP')}';

  Future<void> _load() async {
    final r = await TripApiService.fetchTripPayment(widget.requestId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok && r.dataMap != null) {
        _payment = r.dataMap;
      } else if (_payment == null) {
        _message = 'تعذر تحميل خيارات الدفع — الدفع كاش';
      }
    });
    if (_payment == null || _settled) {
      widget.canDismiss.value = true;
      _poll?.cancel();
      return;
    }
    if (_isDriver) {
      _poll ??= Timer.periodic(_driverPollEvery, (_) => _load());
    }
  }

  Future<void> _pay(String method) async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await TripApiService.payTrip(widget.requestId, method);
    if (!mounted) return;
    setState(() {
      _busy = false;
      final data = r.dataMap;
      if (data != null) _payment = data;
      _message = r.message;
    });
    if (_settled || !r.ok) widget.canDismiss.value = true;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: _loading
          ? const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(color: _amber, strokeWidth: 3),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _settled || _payment == null
                  ? _buildResult()
                  : (_isDriver ? _buildDriverWaiting() : _buildCustomerChoice()),
            ),
    );
  }

  List<Widget> _buildResult() {
    final method = _payment?['method']?.toString() ?? 'cash';
    final walletPaid = _num('wallet_paid');
    final cashDue = _num('cash_due');

    final String headline;
    final String? detail;
    final IconData icon;
    if (_payment == null) {
      icon = Icons.payments_outlined;
      headline = _message ?? 'الدفع كاش';
      detail = null;
    } else if (method == 'wallet') {
      icon = Icons.account_balance_wallet_rounded;
      headline = _isDriver
          ? 'مدفوعة من محفظة الراكب'
          : 'تم الدفع من المحفظة';
      detail = _isDriver
          ? 'أُضيف ${_money(walletPaid)} إلى محفظتك — لا تستلم كاش'
          : 'دُفع ${_money(walletPaid)} من رصيدك';
    } else if (method == 'mixed') {
      icon = Icons.account_balance_wallet_rounded;
      headline = _isDriver
          ? 'استلم كاش: ${_money(cashDue)}'
          : 'ادفع للسائق كاش: ${_money(cashDue)}';
      detail = _isDriver
          ? 'ودُفع ${_money(walletPaid)} من محفظة الراكب وأُضيف لمحفظتك'
          : 'ودُفع ${_money(walletPaid)} من رصيد محفظتك';
    } else {
      icon = Icons.payments_outlined;
      headline = _isDriver
          ? 'استلم كاش: ${_money(cashDue)}'
          : 'الدفع كاش: ${_money(cashDue)}';
      detail = null;
    }

    return [
      Row(
        children: [
          Icon(icon, color: _amber, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              headline,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      if (detail != null) ...[
        const SizedBox(height: 6),
        Text(
          detail,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
      if (_payment != null &&
          _message != null &&
          _message!.isNotEmpty &&
          !_isDriver) ...[
        const SizedBox(height: 6),
        Text(
          _message!,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12.5,
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildDriverWaiting() {
    return [
      Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: _amber, strokeWidth: 2.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'بانتظار اختيار الراكب لطريقة الدفع…',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'إن لم يختر الراكب تُحسب الرحلة كاش',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.65),
          fontSize: 12.5,
        ),
      ),
    ];
  }

  List<Widget> _buildCustomerChoice() {
    final finalCost = _num('final_cost');
    final balance = _num('wallet_balance');
    final covers = balance >= finalCost;
    final walletLabel = balance <= 0
        ? 'الدفع من المحفظة (الرصيد 0)'
        : covers
            ? 'الدفع من المحفظة'
            : 'من المحفظة ${_money(balance)} والباقي كاش';

    return [
      Text(
        'اختر طريقة الدفع',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.95),
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'رصيد محفظتك: ${_money(balance)}',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.75),
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 50,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.white.withValues(alpha: 0.12),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _busy || balance <= 0 ? null : () => _pay('wallet'),
          icon: const Icon(Icons.account_balance_wallet_rounded),
          label: Text(
            walletLabel,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 50,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _busy ? null : () => _pay('cash'),
          icon: const Icon(Icons.payments_outlined),
          label: const Text(
            'الدفع كاش',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      if (_busy) ...[
        const SizedBox(height: 10),
        const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(color: _amber, strokeWidth: 2.5),
          ),
        ),
      ],
    ];
  }
}
