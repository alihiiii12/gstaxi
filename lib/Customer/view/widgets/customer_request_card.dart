import 'package:flutter/material.dart';

import '../../../core/utils/customer_trip_map_state.dart';
import '../../../core/utils/customer_trip_status_helpers.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/request_route_label.dart';
import '../../../core/widgets/resolved_place_label_row.dart';
import 'customer_ui_theme.dart';

/// إجراءات بطاقة طلب في «طلباتي».
class CustomerRequestCardActions {
  const CustomerRequestCardActions({
    required this.onTap,
    required this.onConfirmDriverArrived,
    required this.onSetDestination,
    required this.onRateTrip,
    required this.onCancel,
  });

  final void Function(Map<String, dynamic> request) onTap;
  final void Function(int requestId) onConfirmDriverArrived;
  final void Function(int requestId) onSetDestination;
  final void Function(Map<String, dynamic> request) onRateTrip;
  final void Function(Map<String, dynamic> request) onCancel;
}

/// بطاقة طلب واحد في قائمة الزبون — تصميم حديث.
class CustomerRequestCard extends StatelessWidget {
  const CustomerRequestCard({
    super.key,
    required this.request,
    required this.showRating,
    required this.actions,
  });

  final Map<String, dynamic> request;
  final bool showRating;
  final CustomerRequestCardActions actions;

  static dynamic _locField(Map<String, dynamic> r, bool destination) {
    if (destination) return r['destLocation'] ?? r['dest_location'];
    return r['startLocation'] ?? r['start_location'];
  }

  static String _driverTitle(Map<String, dynamic> r) {
    final dr = r['driver'];
    if (dr is! Map) {
      if (CustomerTripStatusHelpers.requestIsScheduled(r) &&
          CustomerTripStatusHelpers.normTripStatus(r) == 'Pending') {
        return 'قيد الانتظار';
      }
      return 'في انتظار السائق';
    }
    final dm = Map<String, dynamic>.from(dr);
    final u = dm['user'];
    if (u is Map) {
      final um = Map<String, dynamic>.from(u);
      final n = '${um['firstName'] ?? ''} ${um['lastName'] ?? ''}'.trim();
      if (n.isNotEmpty) return n;
    }
    final id = dm['id'];
    if (id != null) return 'سائق #$id';
    return 'السائق';
  }

  static _StatusStyle _statusStyle(String status) {
    switch (status) {
      case 'Pending':
        return _StatusStyle(
          bg: CustomerUiTheme.amber.withValues(alpha: 0.22),
          fg: CustomerUiTheme.navy,
          icon: Icons.hourglass_top_rounded,
        );
      case 'Reserved':
      case 'DriverArrived':
        return _StatusStyle(
          bg: const Color(0xFFDBEAFE),
          fg: const Color(0xFF1D4ED8),
          icon: Icons.navigation_rounded,
        );
      case 'AwaitingDestination':
        return _StatusStyle(
          bg: const Color(0xFFEDE9FE),
          fg: const Color(0xFF6D28D9),
          icon: Icons.edit_location_alt_rounded,
        );
      case 'Running':
        return _StatusStyle(
          bg: const Color(0xFFD1FAE5),
          fg: const Color(0xFF047857),
          icon: Icons.local_taxi_rounded,
        );
      case 'Finished':
        return _StatusStyle(
          bg: const Color(0xFFE5E7EB),
          fg: CustomerUiTheme.charcoal,
          icon: Icons.check_circle_outline_rounded,
        );
      case 'Removed':
        return _StatusStyle(
          bg: const Color(0xFFFEE2E2),
          fg: const Color(0xFFB91C1C),
          icon: Icons.cancel_outlined,
        );
      default:
        return _StatusStyle(
          bg: CustomerUiTheme.sheetBg,
          fg: CustomerUiTheme.muted,
          icon: Icons.info_outline_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse(request['id']?.toString() ?? '') ?? 0;
    final st = request['status']?.toString() ?? '';
    final immediate = CustomerTripStatusHelpers.requestIsImmediate(request);
    final dateRaw = immediate
        ? (request['created_at'] ?? request['createdAt'] ?? '').toString()
        : (request['requestDate'] ?? request['request_date'] ?? '').toString();
    final dateStr = AppFormatters.requestCardDateTimeDisplay(dateRaw);
    final start = _locField(request, false);
    final dest = _locField(request, true);
    final fromStr =
        areaLabelFromRequestForPoint(request, start, destination: false);
    final toStr =
        areaLabelFromRequestForPoint(request, dest, destination: true);
    final statusLabel =
        CustomerTripStatusHelpers.customerRequestStatusLabel(request);
    final statusStyle = _statusStyle(st);

    final showCancel = st == 'Pending' ||
        st == 'Reserved' ||
        st == 'DriverArrived' ||
        st == 'AwaitingDestination';
    final showSetDestination = st == 'AwaitingDestination' && id > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => actions.onTap(request),
        child: Ink(
          decoration: CustomerUiTheme.glassCard(radius: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusStyle.bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusStyle.icon, size: 14, color: statusStyle.fg),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusStyle.fg,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _TypeChip(immediate: immediate),
                    const SizedBox(width: 8),
                    Text(
                      '#$id',
                      style: TextStyle(
                        color: CustomerUiTheme.navy.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: CustomerUiTheme.iconOrb(),
                      child: const Icon(
                        Icons.person_rounded,
                        color: CustomerUiTheme.navy,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _driverTitle(request),
                            style: const TextStyle(
                              color: CustomerUiTheme.navy,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            immediate ? 'تاريخ الإنشاء' : 'موعد الرحلة',
                            style: TextStyle(
                              color: CustomerUiTheme.muted.withValues(alpha: 0.85),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (dateStr.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: CustomerUiTheme.sheetBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          dateStr,
                          style: const TextStyle(
                            color: CustomerUiTheme.navy,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  decoration: BoxDecoration(
                    color: CustomerUiTheme.sheetBg.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: CustomerUiTheme.navy.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Column(
                    children: [
                      ResolvedPlaceLabelRow(
                        icon: Icons.trip_origin,
                        label: 'نقطة الانطلاق',
                        initialValue: fromStr,
                        point: CustomerTripMapUpdate.latLngFromLooseMap(start),
                        iconColor: const Color(0xFF3B82F6),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 1,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF3B82F6).withValues(alpha: 0.25),
                                      const Color(0xFFEF4444).withValues(alpha: 0.25),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ResolvedPlaceLabelRow(
                        icon: Icons.flag_outlined,
                        label: 'الوجهة',
                        initialValue: toStr,
                        point: CustomerTripMapUpdate.latLngFromLooseMap(dest),
                        iconColor: const Color(0xFFEF4444),
                      ),
                    ],
                  ),
                ),
                if (showSetDestination ||
                    showRating ||
                    showCancel) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0xFFE8ECF4)),
                  const SizedBox(height: 12),
                  if (showSetDestination) ...[
                    _ActionButton(
                      label: 'تحديد الوجهة',
                      filled: true,
                      onPressed: () => actions.onSetDestination(id),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (showRating) ...[
                    _ActionButton(
                      label: 'تقييم الرحلة',
                      filled: true,
                      onPressed: () => actions.onRateTrip(request),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (showCancel)
                    _ActionButton(
                      label: 'إلغاء الطلب',
                      filled: false,
                      onPressed: id > 0 ? () => actions.onCancel(request) : null,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusStyle {
  const _StatusStyle({
    required this.bg,
    required this.fg,
    required this.icon,
  });

  final Color bg;
  final Color fg;
  final IconData icon;
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.immediate});

  final bool immediate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: immediate
              ? [CustomerUiTheme.amber, const Color(0xFFFFB300)]
              : [
                  CustomerUiTheme.navy.withValues(alpha: 0.12),
                  CustomerUiTheme.navy.withValues(alpha: 0.08),
                ],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            immediate ? Icons.flash_on_rounded : Icons.event_rounded,
            size: 13,
            color: immediate ? CustomerUiTheme.navy : CustomerUiTheme.navy,
          ),
          const SizedBox(width: 4),
          Text(
            immediate ? 'فوري' : 'مسبق',
            style: TextStyle(
              color: CustomerUiTheme.navy,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final bool filled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: filled
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: onPressed == null
                    ? null
                    : LinearGradient(
                        colors: [
                          CustomerUiTheme.navy,
                          CustomerUiTheme.navy.withValues(alpha: 0.88),
                        ],
                      ),
                color: onPressed == null ? Colors.grey.shade300 : null,
                borderRadius: BorderRadius.circular(14),
                boxShadow: onPressed == null
                    ? null
                    : [
                        BoxShadow(
                          color: CustomerUiTheme.navy.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPressed,
                  borderRadius: BorderRadius.circular(14),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: onPressed == null
                            ? Colors.grey.shade600
                            : CustomerUiTheme.amber,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB91C1C),
                side: BorderSide(
                  color: const Color(0xFFB91C1C).withValues(alpha: 0.35),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onPressed,
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
    );
  }
}
