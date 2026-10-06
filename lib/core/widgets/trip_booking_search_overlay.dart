import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../Customer/view/widgets/customer_ui_theme.dart';
import '../models/trip_stop.dart';
import '../services/recent_destinations_service.dart';

/// نتيجة اختيار مكان من بحث الوجهة.
class TripBookingPlaceHit {
  const TripBookingPlaceHit({
    required this.displayName,
    required this.point,
    this.meta,
  });

  final String displayName;
  final dynamic point;
  /// سطر فرعي اختياري (مثل المسافة والتكلفة التقديرية).
  final String? meta;
}

/// طبقة بحث الوجهة — انطلاق قابل للإلغاء + وجهات متعددة.
class TripBookingSearchOverlay extends StatefulWidget {
  const TripBookingSearchOverlay({
    super.key,
    required this.pickupLabel,
    required this.destinationController,
    required this.onClose,
    required this.onSearchSubmitted,
    required this.onSetOnMap,
    this.searchLoading = false,
    this.placeHits = const [],
    this.onPlaceSelected,
    this.onClearDestination,
    this.hasSelectedDestination = false,
    this.hasCustomPickup = false,
    this.onClearPickup,
    this.onEditPickup,
    this.confirmedStops = const [],
    this.onRemoveStop,
    this.onDone,
  });

  final String pickupLabel;
  final TextEditingController destinationController;
  final VoidCallback onClose;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onSetOnMap;
  final bool searchLoading;
  final List<TripBookingPlaceHit> placeHits;
  final ValueChanged<TripBookingPlaceHit>? onPlaceSelected;
  final VoidCallback? onClearDestination;
  /// يظهر زر X حتى لو حقل النص فارغ بعد اختيار وجهة.
  final bool hasSelectedDestination;
  final bool hasCustomPickup;
  final VoidCallback? onClearPickup;
  final VoidCallback? onEditPickup;
  final List<TripStop> confirmedStops;
  final ValueChanged<int>? onRemoveStop;
  /// إغلاق البحث والمتابعة للحجز بعد اختيار وجهة واحدة على الأقل.
  final VoidCallback? onDone;

  @override
  State<TripBookingSearchOverlay> createState() =>
      _TripBookingSearchOverlayState();
}

class _TripBookingSearchOverlayState extends State<TripBookingSearchOverlay> {
  late final RecentDestinationsService _recentSvc;

  @override
  void initState() {
    super.initState();
    _recentSvc = RecentDestinationsService.ensure();
    widget.destinationController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.destinationController.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  LatLng? _asLatLng(dynamic point) {
    if (point is LatLng) return point;
    try {
      final lat = (point as dynamic).latitude;
      final lng = (point as dynamic).longitude;
      if (lat is num && lng is num) {
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    } catch (_) {}
    return null;
  }

  Future<void> _remember(TripBookingPlaceHit hit) async {
    final p = _asLatLng(hit.point);
    if (p == null) return;
    await _recentSvc.add(title: hit.displayName, point: p);
  }

  void _selectHit(TripBookingPlaceHit hit) {
    unawaited(_remember(hit));
    widget.onPlaceSelected?.call(hit);
  }

  void _selectRecent(RecentDestination r) {
    final hit = TripBookingPlaceHit(
      displayName: r.title,
      point: r.point,
      meta: r.subtitle.isEmpty ? null : r.subtitle,
    );
    _selectHit(hit);
  }

  String get _nextStopLetter {
    final i = widget.confirmedStops.length + 1; // B=1 → index 1
    if (i < 26) return String.fromCharCode(65 + i);
    return '${i + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = widget.destinationController.text.trim().isNotEmpty;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = bottomInset > 0;
    final hasStops = widget.confirmedStops.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: CustomerUiTheme.screenGradient,
        child: SafeArea(
          bottom: false,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 16, 0),
                  child: Row(
                    children: [
                      _GlassIconButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: widget.onClose,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          hasStops
                              ? 'أضف وجهة أخرى أو تابع'
                              : 'إلى أين تريد الذهاب؟',
                          style: const TextStyle(
                            color: CustomerUiTheme.navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.97),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: CustomerUiTheme.navy.withValues(alpha: 0.10),
                          blurRadius: 24,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ListView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                            children: [
                              _SearchRouteCard(
                                pickupLabel: widget.pickupLabel,
                                destinationController:
                                    widget.destinationController,
                                searchLoading: widget.searchLoading,
                                onSearchSubmitted: widget.onSearchSubmitted,
                                onClearDestination: widget.onClearDestination,
                                hasSelectedDestination:
                                    widget.hasSelectedDestination,
                                hasCustomPickup: widget.hasCustomPickup,
                                onClearPickup: widget.onClearPickup,
                                onEditPickup: widget.onEditPickup,
                                confirmedStops: widget.confirmedStops,
                                onRemoveStop: widget.onRemoveStop,
                                nextStopLetter: _nextStopLetter,
                              ),
                              if (!keyboardOpen) ...[
                                const SizedBox(height: 12),
                                _MapPickRow(onTap: widget.onSetOnMap),
                              ],
                              const SizedBox(height: 16),
                              _SectionHeader(
                                hasQuery: hasQuery,
                                hasHits: widget.placeHits.isNotEmpty,
                                loading: widget.searchLoading,
                                showClearRecent: !hasQuery &&
                                    _recentSvc.items.isNotEmpty,
                                onClearRecent: () async {
                                  await _recentSvc.clear();
                                  if (mounted) setState(() {});
                                },
                              ),
                              const SizedBox(height: 8),
                              ..._buildResultTiles(hasQuery: hasQuery),
                            ],
                          ),
                        ),
                        if (hasStops && !keyboardOpen)
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: CustomerUiTheme.navy,
                                  minimumSize: const Size.fromHeight(48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: widget.onDone ?? widget.onClose,
                                child: Text(
                                  widget.confirmedStops.length == 1
                                      ? 'متابعة الحجز'
                                      : 'متابعة — ${widget.confirmedStops.length} وجهات',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ),
      ),
    );
  }

  List<Widget> _buildResultTiles({required bool hasQuery}) {
    if (widget.searchLoading && widget.placeHits.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: CircularProgressIndicator(color: CustomerUiTheme.navy),
          ),
        ),
      ];
    }

    if (hasQuery && widget.placeHits.isNotEmpty) {
      return [
        for (var i = 0; i < widget.placeHits.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _SearchResultTile(
            label: widget.placeHits[i].displayName,
            meta: widget.placeHits[i].meta,
            onTap: () => _selectHit(widget.placeHits[i]),
          ),
        ],
      ];
    }

    if (hasQuery && !widget.searchLoading && widget.placeHits.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'لا نتائج لهذا البحث',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CustomerUiTheme.navy.withValues(alpha: 0.45),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ];
    }

    final recent = _recentSvc.items;
    if (recent.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.confirmedStops.isEmpty
                ? 'ابحث عن وجهتك أو اختر من الخريطة'
                : 'ابحث لإضافة وجهة أخرى (مثلاً المزة ثم العودة للتل)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CustomerUiTheme.navy.withValues(alpha: 0.45),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ];
    }

    return [
      for (var i = 0; i < recent.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        _SearchResultTile(
          label: recent[i].title,
          meta: recent[i].subtitle.isEmpty ? null : recent[i].subtitle,
          icon: Icons.history_rounded,
          onTap: () => _selectRecent(recent[i]),
          onRemove: () async {
            await _recentSvc.removeAt(i);
            if (mounted) setState(() {});
          },
        ),
      ],
    ];
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.hasQuery,
    required this.hasHits,
    required this.loading,
    required this.showClearRecent,
    required this.onClearRecent,
  });

  final bool hasQuery;
  final bool hasHits;
  final bool loading;
  final bool showClearRecent;
  final Future<void> Function() onClearRecent;

  @override
  Widget build(BuildContext context) {
    final title = hasQuery
        ? (hasHits ? 'نتائج البحث' : (loading ? 'جاري البحث…' : 'نتائج البحث'))
        : 'أماكن حديثة';
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: CustomerUiTheme.navy,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const Spacer(),
        if (showClearRecent)
          TextButton(
            onPressed: () => onClearRecent(),
            child: Text(
              'مسح الكل',
              style: TextStyle(
                color: CustomerUiTheme.navy.withValues(alpha: 0.55),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}

class _SearchRouteCard extends StatelessWidget {
  const _SearchRouteCard({
    required this.pickupLabel,
    required this.destinationController,
    required this.searchLoading,
    required this.onSearchSubmitted,
    required this.nextStopLetter,
    this.onClearDestination,
    this.hasSelectedDestination = false,
    this.hasCustomPickup = false,
    this.onClearPickup,
    this.onEditPickup,
    this.confirmedStops = const [],
    this.onRemoveStop,
  });

  final String pickupLabel;
  final TextEditingController destinationController;
  final bool searchLoading;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback? onClearDestination;
  final bool hasSelectedDestination;
  final bool hasCustomPickup;
  final VoidCallback? onClearPickup;
  final VoidCallback? onEditPickup;
  final List<TripStop> confirmedStops;
  final ValueChanged<int>? onRemoveStop;
  final String nextStopLetter;

  String _letter(int stopIndex) {
    final i = stopIndex + 1;
    if (i < 26) return String.fromCharCode(65 + i);
    return '${i + 1}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: CustomerUiTheme.navy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: CustomerUiTheme.navy.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          // —— نقطة الانطلاق ——
          InkWell(
            onTap: onEditPickup,
            borderRadius: BorderRadius.circular(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _RouteDot(letter: 'A', fill: CustomerUiTheme.navy),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasCustomPickup
                            ? 'من — نقطة محددة'
                            : 'من — موقعك الحالي',
                        style: TextStyle(
                          fontSize: 11,
                          color: CustomerUiTheme.navy.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pickupLabel.isEmpty ? 'موقعك الحالي' : pickupLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CustomerUiTheme.navy,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasCustomPickup && onClearPickup != null)
                  IconButton(
                    tooltip: 'العودة لموقعي',
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: CustomerUiTheme.navy.withValues(alpha: 0.45),
                    ),
                    onPressed: onClearPickup,
                  )
                else if (onEditPickup != null)
                  Icon(
                    Icons.edit_location_alt_outlined,
                    size: 18,
                    color: CustomerUiTheme.navy.withValues(alpha: 0.35),
                  ),
              ],
            ),
          ),
          // —— وجهات مؤكدة ——
          for (var i = 0; i < confirmedStops.length; i++) ...[
            _RouteConnector(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RouteDot(letter: _letter(i), fill: CustomerUiTheme.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i == confirmedStops.length - 1 &&
                                confirmedStops.length == 1
                            ? 'إلى'
                            : 'توقف ${i + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          color: CustomerUiTheme.navy.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        confirmedStops[i].label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CustomerUiTheme.navy,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onRemoveStop != null)
                  IconButton(
                    tooltip: 'إزالة',
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: CustomerUiTheme.navy.withValues(alpha: 0.45),
                    ),
                    onPressed: () => onRemoveStop!(i),
                  ),
              ],
            ),
          ],
          _RouteConnector(),
          // —— حقل الوجهة التالية ——
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _RouteDot(letter: nextStopLetter, fill: CustomerUiTheme.amber),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: destinationController,
                  autofocus: true,
                  style: const TextStyle(
                    color: CustomerUiTheme.navy,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  cursorColor: CustomerUiTheme.navy,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: confirmedStops.isEmpty
                        ? 'اكتب اسم المكان أو الحي…'
                        : 'أضف وجهة أخرى…',
                    hintStyle: TextStyle(
                      color: CustomerUiTheme.navy.withValues(alpha: 0.35),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: CustomerUiTheme.navy.withValues(alpha: 0.12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: CustomerUiTheme.navy,
                        width: 1.5,
                      ),
                    ),
                    suffixIcon: searchLoading
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: CustomerUiTheme.navy.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          )
                        : (destinationController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 20,
                                  color: CustomerUiTheme.navy.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                                onPressed: destinationController.clear,
                              )
                            : const Icon(
                                Icons.search_rounded,
                                color: CustomerUiTheme.navy,
                                size: 20,
                              )),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: onSearchSubmitted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteConnector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 11, top: 4, bottom: 4),
      child: Row(
        children: [
          Container(
            width: 2,
            height: 18,
            decoration: BoxDecoration(
              color: CustomerUiTheme.navy.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteDot extends StatelessWidget {
  const _RouteDot({required this.letter, required this.fill});

  final String letter;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final onAmber = fill == CustomerUiTheme.amber;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Text(
        letter,
        style: TextStyle(
          color: onAmber ? CustomerUiTheme.navy : Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.label,
    required this.onTap,
    this.meta,
    this.icon = Icons.place_outlined,
    this.onRemove,
  });

  final String label;
  final String? meta;
  final IconData icon;
  final VoidCallback onTap;
  final Future<void> Function()? onRemove;

  @override
  Widget build(BuildContext context) {
    final parts = label.split(',');
    final title = parts.first.trim();
    final subtitle = parts.length > 1
        ? parts.sublist(1).join(',').trim()
        : '';

    return Material(
      color: CustomerUiTheme.amber.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: CustomerUiTheme.navy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CustomerUiTheme.navy,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CustomerUiTheme.navy.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (meta != null && meta!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta!,
                        style: TextStyle(
                          color: CustomerUiTheme.navy.withValues(alpha: 0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: CustomerUiTheme.navy.withValues(alpha: 0.35),
                  ),
                  onPressed: () => onRemove!(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapPickRow extends StatelessWidget {
  const _MapPickRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CustomerUiTheme.navy.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CustomerUiTheme.amber.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.map_rounded,
                  color: CustomerUiTheme.navy,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'تحديد نقطة الانطلاق على الخريطة',
                  style: TextStyle(
                    color: CustomerUiTheme.navy,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                color: CustomerUiTheme.navy.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.7),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: CustomerUiTheme.navy),
        ),
      ),
    );
  }
}
