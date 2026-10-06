import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../Driver/Home/controller/driver_location_controller.dart';
import 'meter_zone_badge.dart';

/// عرض العداد الحي (كم + زمن + وقوف + التكلفة) — نفس الواجهة للسائق والراكب.
class TripLiveMeterPanel extends StatelessWidget {
  const TripLiveMeterPanel({
    super.key,
    this.meter,
    this.compact = false,
    this.title = 'التكلفة الحالية',
    this.forceShow = false,
    this.costOnly = false,
  });

  /// من Redis عبر تتبع الراكب، أو null لاستخدام [DriverController] مباشرة.
  final Map<String, dynamic>? meter;
  final bool compact;
  final String title;
  final bool forceShow;
  /// للراكب: عرض التكلفة فقط بدون كم/ثواني.
  final bool costOnly;

  @override
  Widget build(BuildContext context) {
    if (meter != null) {
      return _CustomerLiveMeter(
        meter: meter!,
        compact: compact,
        title: title,
        costOnly: costOnly,
      );
    }
    return _DriverMeterObx(
      compact: compact,
      title: title,
      forceShow: forceShow,
    );
  }
}

/// عداد الراكب — لقطة السائق تُكمَّل محلياً من `_anchorMs` بنفس قواعد محرك السائق:
/// الزمن يمشي دائماً، والوقوف يمشي عند التوقف ويضيف سعر الدقيقة كل 60 ثانية.
class _CustomerLiveMeter extends StatefulWidget {
  const _CustomerLiveMeter({
    required this.meter,
    required this.compact,
    required this.title,
    required this.costOnly,
  });

  final Map<String, dynamic> meter;
  final bool compact;
  final String title;
  final bool costOnly;

  @override
  State<_CustomerLiveMeter> createState() => _CustomerLiveMeterState();
}

class _CustomerLiveMeterState extends State<_CustomerLiveMeter> {
  Timer? _timer;
  int _shownElapsed = 0;
  double _shownCost = 0;

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int _int(dynamic v) => (_num(v) ?? 0).toInt();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.meter;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final anchorMs = _int(m['_anchorMs']);
    final delta = anchorMs > 0 ? ((nowMs - anchorMs) ~/ 1000).clamp(0, 86400) : 0;

    final moving = m['isMoving'] == true;
    final baseElapsed =
        _int(m['meterElapsedSeconds'] ?? m['meter_elapsed_seconds']);
    final waitMin =
        _int(m['billedWaitingMinutes'] ?? m['billed_waiting_minutes']);
    final waitSec = _int(m['waitingSeconds'] ?? m['waiting_seconds']);
    final timePrice = _num(m['timePrice'] ?? m['time_price']) ?? 0;
    final km =
        _num(m['distanceTraveledKm'] ?? m['distance_traveled_km']) ?? 0;
    final open = (_num(
              m['openPrice'] ??
                  m['open_price'] ??
                  m['baseFare'] ??
                  m['base_fare'],
            ) ??
            0)
        .round();

    var cost = _num(m['finalCost'] ?? m['final_cost']) ?? 0;
    final zoneMult = _num(m['zoneMultiplier']) ?? 1.0;
    final zoneLabel = '${m['zoneLabel'] ?? ''}';
    final minutePrice = timePrice * (zoneMult > 0 ? zoneMult : 1.0);
    final baseWait = waitMin * 60 + waitSec;
    final waitTotal = moving ? baseWait : baseWait + delta;
    if (!moving && minutePrice > 0) {
      cost += (waitTotal ~/ 60 - waitMin) * minutePrice;
    }

    var elapsed = baseElapsed + delta;
    if (elapsed < _shownElapsed && _shownElapsed - elapsed <= 3) {
      elapsed = _shownElapsed;
    }
    _shownElapsed = elapsed;

    if (cost < _shownCost && _shownCost - cost <= minutePrice + 1) {
      cost = _shownCost;
    }
    _shownCost = cost;

    return _MeterCard(
      compact: widget.compact,
      title: widget.title,
      cost: cost.round(),
      zoneLabel: zoneLabel,
      openPrice: open,
      km: km,
      elapsedLabel:
          DriverController.formatMeterElapsed(moving ? elapsed : waitTotal),
      waitLabel: DriverController.formatMeterElapsed(waitTotal),
      moving: moving,
      costOnly: widget.costOnly,
    );
  }
}

class _DriverMeterObx extends StatelessWidget {
  const _DriverMeterObx({
    required this.compact,
    required this.title,
    this.forceShow = false,
  });

  final bool compact;
  final String title;
  final bool forceShow;

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<DriverController>()) {
      if (!forceShow) return const SizedBox.shrink();
      return _MeterCard(
        compact: compact,
        title: title,
        cost: 0,
        openPrice: 0,
        km: 0,
        elapsedLabel: DriverController.formatMeterElapsed(0),
        waitLabel: DriverController.formatMeterElapsed(0),
        moving: false,
      );
    }
    final c = Get.find<DriverController>();

    return Obx(
      () {
        if (!c.isAppTripMeterActive.value && !forceShow) {
          return const SizedBox.shrink();
        }
        return _MeterCard(
          compact: compact,
          title: title,
          cost: c.isAppTripMeterActive.value
              ? c.meterCost.value.round()
              : c.baseFare.value.round(),
          zoneLabel: c.isAppTripMeterActive.value ? c.meterZoneLabel.value : '',
          openPrice: c.baseFare.value.round(),
          km: c.distanceTraveled.value,
          elapsedLabel: DriverController.formatMeterElapsed(
            c.isMoving.value
                ? c.meterElapsedSeconds.value
                : c.meterWaitingDisplaySeconds,
          ),
          waitLabel: DriverController.formatMeterElapsed(
            c.meterWaitingDisplaySeconds,
          ),
          moving: c.isMoving.value,
        );
      },
    );
  }
}

class _MeterCard extends StatelessWidget {
  const _MeterCard({
    required this.compact,
    required this.title,
    required this.cost,
    required this.openPrice,
    required this.km,
    required this.elapsedLabel,
    required this.waitLabel,
    required this.moving,
    this.costOnly = false,
    this.zoneLabel = '',
  });

  final bool compact;
  final String title;
  final int cost;
  final String zoneLabel;
  final int openPrice;
  final double km;
  final String elapsedLabel;
  final String waitLabel;
  final bool moving;
  final bool costOnly;

  @override
  Widget build(BuildContext context) {
    final pad = compact ? 10.0 : 14.0;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: const Color(0xFF11215B).withValues(alpha: compact ? 0.06 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF11215B).withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: compact ? 12 : 13,
              color: const Color(0xFF11215B),
            ),
          ),
          SizedBox(height: compact ? 6 : 8),
          Text(
            '$cost ل.س',
            style: TextStyle(
              fontSize: compact ? 22 : 28,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF11215B),
            ),
          ),
          MeterZoneBadge(label: zoneLabel, dense: compact, onDark: false),
          if (openPrice > 0) ...[
            SizedBox(height: compact ? 2 : 4),
            Text(
              'سعر الافتتاح: $openPrice ل.س',
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF11215B).withValues(alpha: 0.7),
              ),
            ),
          ],
          if (!costOnly) ...[
            SizedBox(height: compact ? 4 : 6),
            Text(
              moving ? 'جاري الحركة — يُحسب الكيلومتر' : 'متوقف — يُحسب الوقوف',
              style: TextStyle(
                fontSize: 11,
                color: moving ? Colors.green.shade800 : Colors.orange.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: compact ? 6 : 8),
            Row(
              children: [
                Expanded(
                  child: _chip('${km.toStringAsFixed(2)} كم', Icons.map_rounded),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _chip(elapsedLabel, Icons.schedule_rounded),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _chip(waitLabel, Icons.pause_circle_outline),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF11215B)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
