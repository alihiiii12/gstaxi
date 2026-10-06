import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'customer_request_card.dart';
import 'customer_ui_theme.dart';
import '../../../core/utils/customer_trip_status_helpers.dart';

/// تبويب «طلباتي» — تصميم حديث متناسق مع الشاشة الرئيسية.
class CustomerMyTripsTab extends StatefulWidget {
  const CustomerMyTripsTab({
    super.key,
    required this.requests,
    required this.loading,
    required this.requestIdsWithComplaint,
    required this.onRefresh,
    required this.cardActions,
    required this.onMenuTap,
    this.leadingIsBack = false,
  });

  final List<Map<String, dynamic>> requests;
  final bool loading;
  final Set<int> requestIdsWithComplaint;
  final Future<void> Function() onRefresh;
  final CustomerRequestCardActions cardActions;
  final VoidCallback onMenuTap;
  final bool leadingIsBack;

  @override
  State<CustomerMyTripsTab> createState() => _CustomerMyTripsTabState();
}

class _CustomerMyTripsTabState extends State<CustomerMyTripsTab> {
  int _segmentIndex = 0;

  void _selectSegment(int index) {
    if (_segmentIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() => _segmentIndex = index);
  }

  List<Map<String, dynamic>> _filtered({required bool immediate}) {
    return widget.requests
        .where(
          (r) => immediate
              ? CustomerTripStatusHelpers.requestIsImmediate(r)
              : !CustomerTripStatusHelpers.requestIsImmediate(r),
        )
        .toList();
  }

  Future<void> _refresh() async {
    HapticFeedback.lightImpact();
    await widget.onRefresh();
  }

  Widget _emptyState({required bool immediate}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
          decoration: CustomerUiTheme.glassCard(radius: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: CustomerUiTheme.iconOrb(
                  tint: CustomerUiTheme.navy.withValues(alpha: 0.85),
                ),
                child: Icon(
                  immediate
                      ? Icons.flash_on_rounded
                      : Icons.event_available_rounded,
                  color: CustomerUiTheme.amber,
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                immediate
                    ? 'لا توجد طلبات فورية'
                    : 'لا توجد حجوزات مسبقة',
                style: const TextStyle(
                  color: CustomerUiTheme.navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                immediate
                    ? 'عند طلب رحلة فورية ستظهر هنا'
                    : 'حجوزاتك المسبقة ستظهر هنا',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: CustomerUiTheme.muted.withValues(alpha: 0.9),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listBody({required bool immediate}) {
    final list = _filtered(immediate: immediate);

    if (widget.loading && widget.requests.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: CustomerUiTheme.glassCard(radius: 22),
          child: const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.8,
              color: CustomerUiTheme.navy,
            ),
          ),
        ),
      );
    }

    if (!widget.loading && list.isEmpty) {
      return _emptyState(immediate: immediate);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: CustomerUiTheme.navy,
      backgroundColor: Colors.white,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final r = list[i];
          final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
          final st = r['status']?.toString() ?? '';
          final showRating = st == 'Finished' &&
              id > 0 &&
              !widget.requestIdsWithComplaint.contains(id);

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: CustomerRequestCard(
              request: r,
              showRating: showRating,
              actions: widget.cardActions,
            ),
          );
        },
      ),
    );
  }

  Widget _segmentSwitcher() {
    final idx = _segmentIndex;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tabW = constraints.maxWidth / 2;
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: CustomerUiTheme.navy.withValues(alpha: 0.07),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
              AnimatedPositionedDirectional(
                duration: const Duration(milliseconds: 90),
                curve: Curves.easeOut,
                start: idx == 0 ? 4 : tabW + 4,
                top: 4,
                bottom: 4,
                width: tabW - 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        CustomerUiTheme.navy,
                        CustomerUiTheme.navy.withValues(alpha: 0.88),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: CustomerUiTheme.navy.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  _SegmentTab(
                    label: 'حجوزات مسبقة',
                    count: _filtered(immediate: false).length,
                    selected: idx == 0,
                    onTap: () => _selectSegment(0),
                  ),
                  _SegmentTab(
                    label: 'طلبات فورية',
                    count: _filtered(immediate: true).length,
                    selected: idx == 1,
                    onTap: () => _selectSegment(1),
                  ),
                ],
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final scheduledCount = _filtered(immediate: false).length;
    final immediateCount = _filtered(immediate: true).length;
    final total = scheduledCount + immediateCount;

    return DecoratedBox(
      decoration: CustomerUiTheme.screenGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: top + 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _HeaderIconButton(
                  icon: widget.leadingIsBack
                      ? Icons.arrow_forward_ios_rounded
                      : Icons.menu_rounded,
                  onTap: widget.onMenuTap,
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'طلباتي',
                        style: TextStyle(
                          color: CustomerUiTheme.navy,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        child: Text(
                          widget.loading
                              ? 'جاري التحديث…'
                              : '$total ${total == 1 ? 'طلب' : 'طلبات'} مسجّلة',
                          key: ValueKey('$total-${widget.loading}'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: CustomerUiTheme.muted.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _HeaderIconButton(
                  icon: Icons.refresh_rounded,
                  spinning: widget.loading,
                  onTap: widget.loading ? null : _refresh,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: _segmentSwitcher(),
          ),
          Expanded(
            child: IndexedStack(
              index: _segmentIndex,
              children: [
                _listBody(immediate: false),
                _listBody(immediate: true),
              ],
            ),
          ),
          SizedBox(height: 12 + MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
    this.spinning = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CustomerUiTheme.navy.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: CustomerUiTheme.navy.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: spinning
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: CustomerUiTheme.navy,
                ),
              )
            : Icon(icon, color: CustomerUiTheme.navy, size: 22),
      ),
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: 13,
      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
      color: selected ? Colors.white : CustomerUiTheme.navy,
      height: 1.2,
    );

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: labelStyle,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.24)
                        : CustomerUiTheme.amber.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : CustomerUiTheme.navy,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
