import 'dart:async';
import '../../../core/constants/snack_bar.dart';
import '../../../core/constants/app_button_dims.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../service/driver_server_sync_service.dart';
import '../controller/driver_assigned_trip_controller.dart';
import '../controller/driver_location_controller.dart';
import '../controller/driver_navigation_controller.dart';
import '../../Order/controller/immediate_bookings_controller.dart';
import '../../Order/controller/bookings_controller.dart';
import '../../Order/view/screen/order_screen.dart';
import '../../../core/maps/app_map_controller.dart';
import '../../../core/controllers/map_theme_controller.dart';
import '../../../core/services/app_permissions_service.dart';
import '../../../core/services/photon_search_service.dart';
import '../../../core/utils/driver_order_display.dart';
import '../../../core/utils/trip_live_phase_helpers.dart';
import '../../../core/utils/safe_lat_lng.dart';
import '../../../core/utils/trip_location_helpers.dart';
import '../../../core/widgets/favorite_places_sheet.dart';
import '../../../core/widgets/meter_zone_badge.dart';
import 'drawer.dart';
import 'offline_maps_screen.dart';
import 'widgets/driver_immediate_request_dialog.dart';
import 'widgets/driver_sos_countdown_dialog.dart';
import 'widgets/driver_scheduled_cancel_dialog.dart';
import 'widgets/driver_cancel_en_route_dialog.dart';
import 'widgets/driver_trip_strip.dart';
import '../../../Customer/view/widgets/customer_booking_ui.dart';
import '../../../Customer/view/widgets/customer_ui_theme.dart';
import 'widgets/driver_slide_to_toggle.dart';
import '../../../core/widgets/gst_booking_ui.dart';
import '../../../core/utils/category_trip_fare_client.dart';
import '../../../core/utils/utf8_text.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late final DriverController controller;
  late final ImmediateBookingsController immediate;
  late final DriverAssignedTripController trip;
  late final DriverServerSyncService sync;
  late final DriverNavigationController nav;
  late final MapThemeController mapTheme;

  final AppMapController _mapController = AppMapController();
  late final ValueNotifier<AppMapOverlay> _mapOverlay;
  bool _mapReady = false;
  /// بعد أول تمركز على GPS عند فتح الشاشة.
  bool _didInitialLocate = false;

  final TextEditingController _destinationSearch = TextEditingController();
  Timer? _searchDebounce;
  Timer? _welcomeBannerTimer;
  bool _searchLoading = false;
  bool _searchExpanded = false;
  bool _showWelcomeBanner = true;
  bool _mapToolsExpanded = false;
  bool _navToolsExpanded = false;
  /// إخفاء شريطي الإرشاد الأزرقين أثناء الرحلة لإظهار الخريطة أوضح.
  bool _navBannersHidden = false;
  List<_PlaceHit> _placeHits = <_PlaceHit>[];

  int? _lastImmediateNotifiedId;
  int? _openImmediateDialogRequestId;
  bool _immediateSheetVisible = false;
  /// أُغلق الحوار بقبول أو تجاهل — لا تُعد فتحه تلقائياً.
  bool _immediateClosedByDecision = false;
  /// يمنع فتح فاتورة العداد الحر مرتين عند السحب للإنهاء.
  bool _freeMeterReceiptOpen = false;
  /// تصغير لوحة العداد الحر لتصفح الخريطة مع استمرار العدّ.
  bool _freeMeterMinimized = false;
  /// تصغير لوحة العداد الحر لتصفح الخريطة مع استمرار العد.
  bool _freeMeterPanelMinimized = false;
  Worker? _immediateWorker;
  Worker? _assignRefreshWorker;
  Worker? _posWorker;
  Worker? _headingWorker;
  Worker? _mapOverlayWorker;
  Worker? _onlineImmediateWorker;
  Timer? _immediateDialogRetryTimer;
  Timer? _mapOverlayDebounce;
  /// نبضة دورية لإعادة تقييم فتح نافذة «انطلق للراكب» بين الاستطلاعات.
  final RxInt _schedClock = 0.obs;
  Timer? _schedClockTimer;

  @override
  void initState() {
    super.initState();
    _schedClockTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _schedClock.value++,
    );
    _mapOverlay = ValueNotifier(AppMapOverlay.empty);
    WidgetsBinding.instance.addObserver(this);
    controller = Get.put(DriverController(), permanent: true);
    immediate = Get.put(ImmediateBookingsController(), permanent: true);
    if (!Get.isRegistered<BookingsController>()) {
      Get.put(BookingsController(), permanent: true);
    }
    trip = Get.put(DriverAssignedTripController(controller), permanent: true);
    sync = Get.put(DriverServerSyncService(), permanent: true);
    nav = Get.put(DriverNavigationController(), permanent: true);
    mapTheme = Get.put(MapThemeController(), permanent: true);

    _welcomeBannerTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() => _showWelcomeBanner = false);
    });

    trip.onMapFocus = _handleMapFocus;
    trip.showPassengerReadyDialog = _showPassengerReadyDialog;
    trip.showSchedAtTimeDialog = _showSchedAtTimeDialog;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      controller.onApplyTripPreviewUi = (map) {
        if (!mounted) return;
        trip.applyAcceptedTripPreview(map);
      };
      await AppPermissionsService.ensureCorePermissions(forDriver: true);
      if (!mounted) return;
      await controller.bootstrapCurrentLocation();
      if (!mounted) return;
      _goToMyLocationOnOpen();
    });

    _destinationSearch.addListener(_onDestinationSearchChanged);

    _posWorker = ever<LatLng>(controller.currentPosition, (pos) {
      if (!mounted || !_mapReady || !isFiniteLatLng(pos)) return;
      trip.onDriverPositionUpdated(pos);
      final kph = controller.currentSpeedKph.value;
      unawaited(_mapController.updateDriverPose(
        pos,
        controller.currentHeading.value,
        tripActive: _isTripIconActive,
        speedMps: kph.isFinite ? kph / 3.6 : null,
      ));
      if (!_didInitialLocate) {
        _goToMyLocationOnOpen(force: true);
      }
      _updateNavigationCamera(pos: pos);
    });

    _headingWorker = ever<double>(controller.currentHeading, (deg) {
      if (!mounted) return;
      if (!_mapReady) return;
      if (!deg.isFinite) return;
      unawaited(_mapController.updateDriverPose(
        safeLatLngFrom(controller.currentPosition.value),
        deg,
        tripActive: _isTripIconActive,
      ));
      _updateNavigationCamera(bearing: deg);
    });

    ever<bool>(nav.followMode, (follow) {
      if (!follow) _mapController.setDriverFollow(enabled: false);
    });

    // عند دخول وضع التنقّل (بدء الرحلة) نفعّل كاميرا خلف السيارة فوراً بقرب كبير.
    ever(nav.active, (active) {
      if (!mounted || !_mapReady) return;
      if (active) {
        if (_navBannersHidden) {
          setState(() => _navBannersHidden = false);
        }
        nav.followMode.value = true;
        _snapBehindCar(force: true, tripStarted: true);
        unawaited(_mapController.updateDriverPose(
          safeLatLngFrom(controller.currentPosition.value),
          controller.currentHeading.value,
          tripActive: true,
        ));
      } else {
        if (_navBannersHidden) {
          setState(() => _navBannersHidden = false);
        }
        unawaited(_mapController.updateDriverPose(
          safeLatLngFrom(controller.currentPosition.value),
          controller.currentHeading.value,
          tripActive: false,
        ));
        unawaited(_mapController.setNavigationCamera(
          point: safeLatLngFrom(controller.currentPosition.value),
          bearing: controller.currentHeading.value,
          zoom: MapStyleConfig.mapDefaultZoom,
          tilt: MapStyleConfig.mapDefaultTilt,
          lookAheadMeters: 0,
          animate: true,
        ));
      }
    });

    // عند تحول الحالة إلى Running (بدء الرحلة) — نفس اللقطة خلف السيارة.
    String? prevTripStatusForCam;
    ever(trip.assignedRequest, (req) {
      if (!mounted || !_mapReady) return;
      if (req == null) {
        unawaited(_mapController.updateDriverPose(
          safeLatLngFrom(controller.currentPosition.value),
          controller.currentHeading.value,
          tripActive: false,
        ));
        prevTripStatusForCam = null;
        return;
      }
      final st = normTripStatusForOrder(req);
      if (st == 'Running' && prevTripStatusForCam != 'Running') {
        nav.followMode.value = true;
        _snapBehindCar(force: true, tripStarted: true);
        unawaited(_mapController.updateDriverPose(
          safeLatLngFrom(controller.currentPosition.value),
          controller.currentHeading.value,
          tripActive: true,
        ));
      } else if (st != 'Running' && prevTripStatusForCam == 'Running') {
        unawaited(_mapController.updateDriverPose(
          safeLatLngFrom(controller.currentPosition.value),
          controller.currentHeading.value,
          tripActive: false,
        ));
      }
      prevTripStatusForCam = st;
    });

    _assignRefreshWorker = ever<int>(controller.assignRefreshSignal, (_) {
      if (!mounted) return;
      sync.syncNow(force: true);
    });

    _mapOverlayWorker =     ever(trip.routePoints, (_) => _scheduleMapOverlayRefresh());
    ever(trip.destination, (_) => _scheduleMapOverlayRefresh());
    ever(trip.assignedRequest, (_) => _scheduleMapOverlayRefresh());
    // موقع السائق يُحدَّث عبر updateDriverPose فقط — لا نعيد رسم المسار كل GPS.

    // راقب وصول طلبات فورية جديدة وأظهر نافذة.
    _immediateWorker = ever<List<Map<String, dynamic>>>(immediate.bookings, (list) {
      _processImmediateBookings(list);
    });
    _onlineImmediateWorker = ever<bool>(controller.isOnline, (online) {
      if (!online) {
        _immediateDialogRetryTimer?.cancel();
        _closeImmediateBottomSheet();
        _openImmediateDialogRequestId = null;
        _lastImmediateNotifiedId = null;
        return;
      }
      _processImmediateBookings(immediate.bookings);
    });
  }

  void _closeImmediateBottomSheet() {
    if (!_immediateSheetVisible || !mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
    }
    _immediateSheetVisible = false;
  }

  void _processImmediateBookings(List<Map<String, dynamic>> list) {
    if (!mounted) return;
    if (!controller.isOnline.value) return;
    // العداد الحر: لا استقبال طلبات التطبيق.
    if (controller.isTripActive.value) return;
    // أثناء رحلة تطبيق: السماح بطلبات جديدة فقط قبل الوجهة بدقيقة تقريباً.
    if (!_canReceiveOffersNearDestination()) return;

    final pendingOnly = list
        .map((r) => Map<String, dynamic>.from(r))
        .where((r) {
          if (normTripStatusForOrder(r) != 'Pending') return false;
          final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
          if (id > 0 && immediate.isIgnored(id)) return false;
          return true;
        })
        .toList()
      ..sort(compareDriverOrdersRecentFirst);

    if (pendingOnly.isEmpty) return;

    final displayed = pendingOnly.first;
    final hasOtherImmediate = pendingOnly.length > 1;
    final ridRaw = displayed['id'];
    final rid = ridRaw is int ? ridRaw : int.tryParse(ridRaw?.toString() ?? '');
    if (rid == null) return;

    final openId = _openImmediateDialogRequestId;

    // حوار مفتوح — ثبّته حتى قبول/تجاهل (لا تستبدله ولا تعِد فتحه).
    if (_immediateSheetVisible) return;

    // نفس الطلب سبق عرضه وما زال معلقاً — لا تُظهره مرتين بصوت جديد.
    if (_lastImmediateNotifiedId == rid) {
      // إن أُغلق بالخطأ دون قرار، أعد فتحه بدون صوت.
      if (!_immediateClosedByDecision && openId == null) {
        _showImmediateRequestSheet(
          displayed,
          rid,
          hasOtherImmediate: hasOtherImmediate,
          playSound: false,
        );
      }
      return;
    }

    _showImmediateRequestSheet(
      displayed,
      rid,
      hasOtherImmediate: hasOtherImmediate,
    );
  }

  /// لا طلبات جديدة أثناء الانشغال؛ عند Running فقط إذا المتبقي ≤ دقيقة للوجهة.
  bool _canReceiveOffersNearDestination() {
    final ar = trip.assignedRequest.value;
    if (ar == null) return true;
    final st = normTripStatusForOrder(ar);
    if (st == 'Finished' || st == 'Removed' || st == 'Pending') return true;
    if (st != 'Running') return false;
    if (!nav.active.value) return false;
    final remain = nav.remainingMin.value;
    return remain > 0 && remain <= 1.05;
  }

  void _showImmediateRequestSheet(
    Map<String, dynamic> displayed,
    int rid, {
    required bool hasOtherImmediate,
    bool playSound = true,
  }) {
    if (!mounted || _immediateSheetVisible) return;
    _immediateClosedByDecision = false;
    _lastImmediateNotifiedId = rid;
    _openImmediateDialogRequestId = rid;
    _immediateSheetVisible = true;
    DriverImmediateRequestDialog.show(
      order: displayed,
      immediate: immediate,
      trip: trip,
      hasOtherImmediate: hasOtherImmediate,
      playSound: playSound,
      setOpenDialogRequestId: (id) => _openImmediateDialogRequestId = id,
      getOpenDialogRequestId: () => _openImmediateDialogRequestId,
      setLastNotifiedId: (id) => _lastImmediateNotifiedId = id,
      getLastNotifiedId: () => _lastImmediateNotifiedId,
      onDecision: () {
        _immediateClosedByDecision = true;
      },
      onSheetClosed: () {
        _immediateSheetVisible = false;
        _openImmediateDialogRequestId = null;
        // بدون قرار: أعد تثبيتها إن بقي الطلب معلقاً (بدون إعادة الصوت).
        if (!_immediateClosedByDecision &&
            _lastImmediateNotifiedId != null &&
            mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _immediateSheetVisible) return;
            _processImmediateBookings(immediate.bookings);
          });
        }
      },
    );
  }

  void _handleMapFocus(DriverMapFocusEvent event) {
    if (!mounted) return;
    // أثناء التصفح اليدوي لا نُرجع الكاميرا عند تحديث المسار/الطلب.
    if (!event.force && !nav.followMode.value) return;
    final fit = event.fitPoints;
    if (fit != null && fit.length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.fitPoints(fit, padding: event.padding);
        } catch (_) {
          _ensureMapShows(fit.last, zoom: 14);
        }
      });
      return;
    }
    if (event.point != null) {
      _ensureMapShows(event.point!, zoom: event.zoom ?? 15);
    }
  }

  Future<String?> _showPassengerReadyDialog() {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('الراكب جاهز'),
        content: const Text(
          'أكّد الراكب جاهزيته للرحلة (حجز مسبق).\n'
          'اضغط «ابدأ الرحلة» خلال 15 دقيقة، أو «ليس الآن» ليصله إشعار «السائق مشغول».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'defer'),
            child: const Text('ليس الآن'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'start'),
            child: const Text('ابدأ الرحلة'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showSchedAtTimeDialog(
    int requestId,
    String title,
    String body,
  ) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(
          '$body\n\n'
          'حجز #$requestId — بعد الضغط يظهر للراكب «السائق بالطريق إليك» '
          'وتكمل بنفس مراحل الطلب الفوري.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('لاحقاً'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: CustomerUiTheme.amber,
              foregroundColor: CustomerUiTheme.navy,
            ),
            onPressed: () => Navigator.pop(ctx, 'start'),
            icon: const Icon(Icons.navigation_rounded),
            label: const Text(
              'انطلق للراكب',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmGoToScheduled(Map<String, dynamic> request) async {
    final id = int.tryParse(request['id']?.toString() ?? '') ?? 0;
    if (id <= 0) return;
    final when = formatScheduledRequestDate(request);
    final action = await _showSchedAtTimeDialog(
      id,
      'انطلق للراكب',
      when != null
          ? 'موعد الحجز المسبق: $when.'
          : 'حان وقت الحجز المسبق.',
    );
    if (action == 'start') await trip.goToScheduledPassenger(id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      sync.onAppResumed();
      if (mounted) {
        trip.onAppResumed();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _welcomeBannerTimer?.cancel();
    _destinationSearch.removeListener(_onDestinationSearchChanged);
    _destinationSearch.dispose();
    _searchDebounce?.cancel();
    _immediateDialogRetryTimer?.cancel();
    _mapOverlayDebounce?.cancel();
    _schedClockTimer?.cancel();
    _onlineImmediateWorker?.dispose();
    trip.onMapFocus = null;
    trip.showPassengerReadyDialog = null;
    trip.showSchedAtTimeDialog = null;
    controller.onAssignedTripUiRefresh = null;
    _immediateWorker?.dispose();
    _assignRefreshWorker?.dispose();
    _posWorker?.dispose();
    _headingWorker?.dispose();
    _mapOverlayWorker?.dispose();
    _mapOverlay.dispose();
    controller.onApplyTripPreviewUi = null;
    _mapController.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      endDrawer: const Sidebar(),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            // 1. الخريطة — MapLibre / OSM (أسلوب MAPS.ME)
            RepaintBoundary(
              child: ValueListenableBuilder<AppMapOverlay>(
                valueListenable: _mapOverlay,
                builder: (context, overlay, _) {
                  final mapCenter =
                      safeLatLngFrom(controller.currentPosition.value);
                  return Obx(() {
                    final night = mapTheme.nightMode.value;
                    return AppMapView(
                      controller: _mapController,
                      initialCenter: mapCenter,
                      initialZoom: MapStyleConfig.mapDefaultZoom,
                      initialBearing: 0,
                      initialTilt: MapStyleConfig.mapDefaultTilt,
                      overlay: overlay,
                      nightMode: night,
                      onMapReady: () {
                        _mapReady = true;
                        _refreshMapOverlay();
                        unawaited(_mapController.updateDriverPose(
                          safeLatLngFrom(controller.currentPosition.value),
                          controller.currentHeading.value,
                          tripActive: _isTripIconActive,
                        ));
                        if (nav.followMode.value) {
                          final st = trip.assignedRequest.value != null
                              ? normTripStatusForOrder(
                                  trip.assignedRequest.value!,
                                )
                              : '';
                          if (nav.active.value || st == 'Running') {
                            _didInitialLocate = true;
                            _snapBehindCar(force: true, tripStarted: true);
                            return;
                          }
                        }
                        _goToMyLocationOnOpen(force: true);
                      },
                      onUserGesture: () {
                        // التصفح اليدوي يوقف المتابعة حتى يُضغط زر المتابعة.
                        nav.followMode.value = false;
                        _mapController.setDriverFollow(enabled: false);
                      },
                    );
                  });
                },
              ),
            ),

            // شريط تنقّل — تقريب واجهة MAPS.ME (+ زر إخفاء)
            Obx(() {
              if (!nav.active.value) return const SizedBox.shrink();
              final top = MediaQuery.paddingOf(context).top + 8;
              if (_navBannersHidden) {
                return Positioned(
                  top: top,
                  right: 10,
                  child: Material(
                    elevation: 4,
                    color: const Color(0xFF0D47A1),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _navBannersHidden = false),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                children: [
                            Icon(
                              Icons.navigation_rounded,
                              color: Color(0xFFFFC107),
                              size: 20,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'إظهار الإرشاد',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                  ),
                ],
              ),
            ),
                    ),
                  ),
                );
              }
              final dist = nav.distanceToManeuverM.value;
              // أمتار حقيقية → كم فقط عند ≥ 1000م (لا نعرض طول خطوة OSRM).
              final distLabel = !dist.isFinite || dist < 0
                  ? '—'
                  : dist >= 1000
                      ? '${(dist / 1000).toStringAsFixed(dist >= 10000 ? 0 : 1)} كم'
                      : '${dist.round()} م';
              final remainKm = nav.remainingKm.value;
              final eta = nav.remainingMin.value > 0
                  ? ' · ${nav.remainingMin.value.round()} د'
                  : '';
              final remain = remainKm > 0
                  ? (remainKm >= 1
                      ? 'متبقي ${remainKm.toStringAsFixed(1)} كم$eta'
                      : 'متبقي ${(remainKm * 1000).round()} م$eta')
                  : '';
              final instr = nav.currentInstruction.value;
              return Positioned(
                top: top,
                left: 10,
                right: 10,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      key: ValueKey(
                        'nav_banner_${nav.stepIndex.value}_${distLabel}_$instr',
                      ),
                      elevation: 6,
                      borderRadius: BorderRadius.circular(16),
                      color: const Color(0xFF0D47A1),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                nav.maneuverIcon,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    distLabel,
                                    style: const TextStyle(
                                      color: Color(0xFFFFC107),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 22,
                                    ),
                                  ),
                                  Text(
                                    instr,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (remain.isNotEmpty)
                                    Text(
                                      remain,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'إخفاء الإرشاد',
                              onPressed: () =>
                                  setState(() => _navBannersHidden = true),
                              icon: const Icon(
                                Icons.keyboard_arrow_up_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // السرعة + الكم تحت شريط الإرشاد
                    const SizedBox(height: 8),
                    Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xFF11215B),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.speed_rounded,
                              color: Color(0xFFFFC107),
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${controller.currentSpeedKph.value.clamp(0, 220).round()} كم/س',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.route_rounded,
                              color: Color(0xFFFFC107),
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              nav.remainingKm.value > 0
                                  ? (nav.remainingKm.value >= 1
                                      ? '${nav.remainingKm.value.toStringAsFixed(1)} كم'
                                      : '${(nav.remainingKm.value * 1000).round()} م')
                                  : '—',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

            // أدوات التنقّل — قائمة منسدلة (مطوية افتراضياً)
            if (!_searchExpanded)
              Obx(() {
                if (!_driverChromeUnlocked) return const SizedBox.shrink();
                final st = trip.assignedRequest.value != null
                    ? normTripStatusForOrder(trip.assignedRequest.value!)
                    : '';
                final showNavControls = nav.active.value ||
                    st == 'Reserved' ||
                    st == 'DriverArrived' ||
                    st == 'Running' ||
                    st == 'AwaitingDestination';
                if (!showNavControls) return const SizedBox.shrink();
                final topPad = MediaQuery.paddingOf(context).top;
                // أثناء الإرشاد الظاهر انزل القائمة تحت الشريطين الزرقين.
                final topOffset = nav.active.value && !_navBannersHidden
                    ? topPad + 168
                    : topPad + 64;
                return Positioned(
                  top: topOffset,
                  left: 16,
                  child: CustomerMapToolsMenu(
                    expanded: _navToolsExpanded,
                    onToggle: () => setState(
                      () => _navToolsExpanded = !_navToolsExpanded,
                    ),
                    items: [
                      CustomerMapToolItem(
                        icon: Icons.navigation_rounded,
                        highlight: true,
                        onTap: () {
                          nav.followMode.value = true;
                          _updateNavigationCamera(force: true);
                          setState(() => _navToolsExpanded = false);
                        },
                      ),
                      CustomerMapToolItem(
                        icon: Icons.explore_rounded,
                        onTap: () {
                          nav.followMode.value = true;
                          unawaited(_mapController.resetNorth(
                            at: safeLatLngFrom(controller.currentPosition.value),
                          ));
                          Future.delayed(const Duration(milliseconds: 400), () {
                            if (!mounted) return;
                            _updateNavigationCamera(force: true);
                          });
                          setState(() => _navToolsExpanded = false);
                        },
                      ),
                      CustomerMapToolItem(
                        icon: nav.voiceEnabled.value
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        onTap: () {
                          nav.toggleVoice();
                          setState(() => _navToolsExpanded = false);
                        },
                      ),
                    ],
                  ),
                );
              }),

            if (!_searchExpanded)
              Obx(() {
                if (!_driverChromeUnlocked) return const SizedBox.shrink();
                final hide = nav.active.value ||
                    driverShouldHideDestinationSearch(
                      assignedRequest: trip.assignedRequest.value,
                      freeMeterActive: controller.isTripActive.value,
                      navigationActive: nav.active.value,
                    );
                return Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CustomerBookingMenuButton(
                            onTap: () =>
                                _scaffoldKey.currentState?.openEndDrawer(),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: hide
                                ? const SizedBox.shrink()
                                : (_showWelcomeBanner
                                    ? const CustomerBookingWelcomeBanner()
                                    : (!controller.isOnline.value
                                        ? const SizedBox.shrink()
                                        : _buildDestinationSearchChip())),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

            // أدوات الخريطة
            if (!_searchExpanded)
              Obx(() {
                if (!_driverChromeUnlocked) return const SizedBox.shrink();
                final buttonBottom = _driverOverlayButtonsBaseBottom(context);
                // قراءة المراقبات لإعادة البناء عند تغيّر الوضع دون تحريك الأزرار
                mapTheme.nightMode.value;
                nav.voiceEnabled.value;
                return Positioned(
                  bottom: buttonBottom,
                  right: 16,
                  child: CustomerMapToolsMenu(
                    expanded: _mapToolsExpanded,
                    expandUpward: true,
                    onToggle: () =>
                        setState(() => _mapToolsExpanded = !_mapToolsExpanded),
                    items: [
                      CustomerMapToolItem(
                        icon: Icons.my_location_rounded,
                        highlight: true,
                        onTap: () {
                          final ll =
                              safeLatLngFrom(controller.currentPosition.value);
                          _ensureMapShows(ll, zoom: 16);
                        },
                      ),
                      CustomerMapToolItem(
                        icon: mapTheme.nightMode.value
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        onTap: () => mapTheme.toggle(),
                      ),
                      CustomerMapToolItem(
                        icon: Icons.download_for_offline_rounded,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const OfflineMapsScreen(),
                            ),
                          );
                        },
                      ),
                      CustomerMapToolItem(
                        icon: Icons.bookmark_rounded,
                        onTap: () {
                          FavoritePlacesSheet.show(
                            context,
                            currentPoint: safeLatLngFrom(
                              controller.currentPosition.value,
                            ),
                            onPick: (p, title) {
                              trip.setManualDestination(p, title);
                              _ensureMapShows(p, zoom: 15);
                            },
                          );
                        },
                      ),
                      CustomerMapToolItem(
                        icon: nav.voiceEnabled.value
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        onTap: () => nav.toggleVoice(),
                      ),
                    ],
                  ),
                );
              }),

            // نطاق استقبال الطلبات (1 / 2 / 3 كم)
            if (!_searchExpanded)
              Obx(() {
                if (!_driverChromeUnlocked) return const SizedBox.shrink();
                if (controller.isTripActive.value ||
                    controller.isAppTripMeterActive.value) {
                  return const SizedBox.shrink();
                }
                final pad = MediaQuery.viewPaddingOf(context).bottom;
                final km = controller.receiveRadiusKm.value;
                return Positioned(
                  bottom: 128 + pad,
                  left: 16,
                  child: Material(
                    color: CustomerUiTheme.navy,
                    elevation: 4,
                    borderRadius: BorderRadius.circular(28),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        unawaited(controller.cycleReceiveRadius());
                      },
                      onLongPress: () => _showReceiveRadiusPicker(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.radar_rounded,
                              color: CustomerUiTheme.amber,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'نطاق $km كم',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),

            if (_searchExpanded)
              Positioned.fill(child: _buildDriverSearchOverlay()),

            // شريط الطلب النشط أو الحجز المسبق القادم
            if (!_searchExpanded)
              Obx(() {
                _schedClock.value;
                if (controller.isTripActive.value) return const SizedBox.shrink();
                final active = trip.assignedRequest.value;
                // قبل نافذة الـ 30 دقيقة: السائق حرّ — الحجز يبقى أيقونة فقط.
                final rawUpcoming = trip.upcomingScheduled.value;
                final upcoming =
                    rawUpcoming != null && scheduledGoWindowOpen(rawUpcoming)
                        ? rawUpcoming
                        : null;
                if (active == null && upcoming == null) {
                  return const SizedBox.shrink();
                }
                return _DriverBottomTripSheet(
                  key: ValueKey('driver_trip_sheet_${active?['id'] ?? upcoming?['id']}'),
                  active: active,
                  upcoming: upcoming,
                  trip: trip,
                  reservedBottom: _driverTripSheetReservedBottom(context),
                  initialSize: _driverTripSheetInitialSize(
                    active: active,
                    upcoming: upcoming,
                  ),
                  minSize: _driverTripSheetMinSize(
                    active: active,
                    upcoming: upcoming,
                  ),
                  maxSize: _driverTripSheetMaxSize(
                    active: active,
                    upcoming: upcoming,
                  ),
                  title: _driverTripSheetTitle(active ?? upcoming!),
                  subtitle: _driverTripSheetSubtitle(active ?? upcoming!),
                  onCancelScheduled: _driverCancelScheduled,
                  onCancelEnRoute: _driverCancelEnRoute,
                  onGoToPassenger: _confirmGoToScheduled,
                );
              }),

            if (!_searchExpanded)
              Obx(() {
                if (!_driverChromeUnlocked) return const SizedBox.shrink();
                final buttonBottom = _driverOverlayButtonsBaseBottom(context);
                return Positioned(
                  bottom: buttonBottom + 8,
              left: 20,
                  child: Tooltip(
                    message: 'طوارئ — عدّ تنازلي 15 ثانية ثم إبلاغ الإدارة (يمكنك الإلغاء)',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          _openSosConfirmDialog();
                        },
                        child: Ink(
                  padding: const EdgeInsets.all(15),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                  ),
                  child: const Column(
                            mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sos_rounded, color: Colors.white, size: 30),
                              Text(
                                'SOS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                    ],
                  ),
                ),
              ),
            ),
                  ),
                );
              }),

            // 4b. أيقونة ثابتة للحجوزات المسبقة
            if (!_searchExpanded)
            Obx(() {
                _schedClock.value;
                if (!_driverChromeUnlocked) return const SizedBox.shrink();
                final upcoming = trip.upcomingScheduled.value;
                if (upcoming != null && scheduledGoWindowOpen(upcoming)) {
                  // النافذة مفتوحة: لوحة الحجز تحوي الزر إن لم تكن هناك رحلة أخرى.
                  final sheetShowsIt = trip.assignedRequest.value == null &&
                      !controller.isTripActive.value;
                  if (sheetShowsIt) return const SizedBox.shrink();
                  return _buildScheduledGoFab(upcoming);
                }
                final pendingSched = immediate.bookings
                    .where((r) =>
                        requestIsScheduled(r) &&
                        normTripStatusForOrder(r) == 'Pending')
                    .length;
                var count = pendingSched + (upcoming != null ? 1 : 0);
                if (Get.isRegistered<BookingsController>()) {
                  final reserved = Get.find<BookingsController>().bookings.where((r) {
                    final st = normTripStatusForOrder(r);
                    return requestIsScheduled(r) &&
                        (st == 'Reserved' || st == 'Pending');
                  }).length;
                  if (reserved > count) count = reserved;
                }
                if (count <= 0) return const SizedBox.shrink();
                return _buildScheduledFab(count);
              }),

            // 4. لوحة العداد (الشرط هنا هو الأهم)
            if (!_searchExpanded)
              Obx(() {
                if (!controller.isTripActive.value) {
                return const SizedBox.shrink();
              }
                return _buildActiveMeterPanel(showSlideToStop: true);
            }),

            // 5. زر العداد الحر (يظهر فقط إذا لم تكن هناك رحلة)
            if (!_searchExpanded)
              Obx(
                () {
                  if (!_driverChromeUnlocked) return const SizedBox.shrink();
                  if (controller.isTripActive.value ||
                      controller.isAppTripMeterActive.value) {
                    return const SizedBox.shrink();
                  }
                  _schedClock.value;
                  final upcoming = trip.upcomingScheduled.value;
                  if (trip.assignedRequest.value != null ||
                      (upcoming != null && scheduledGoWindowOpen(upcoming))) {
                    return const SizedBox.shrink();
                  }
                  final pad = MediaQuery.viewPaddingOf(context).bottom;
                  // فوق زر الحالة (ارتفاع ~68 + هامش) دون تراكب.
                  return Positioned(
                    bottom: 128 + pad,
                      right: 20,
                      child: FloatingActionButton.extended(
                        backgroundColor: const Color(0xFFFFC107),
                        onPressed: () => _showFreeMeterOptions(),
                        icon: const Icon(
                          Icons.speed_rounded,
                          color: Color(0xFF11215B),
                        ),
                        label: const Text(
                          "العداد الحر",
                          style: TextStyle(
                            color: Color(0xFF11215B),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  );
                },
              ),

            // 6. زر الحالة — يُخفى أثناء البحث / العداد / الرحلة الحية
            if (!_searchExpanded)
              Obx(() {
                if (controller.isTripActive.value ||
                    controller.isAppTripMeterActive.value) {
                  return const SizedBox.shrink();
                }
                final active = trip.assignedRequest.value;
                if (active != null && _driverInLiveTripPhase(active)) {
                  return const SizedBox.shrink();
                }
                return _buildBottomStatusButton();
              }),
          ],
        ),
      ),
    );
  }

  /// أيقونة الحجز المسبق «مفتوحة» (≤ 30 د قبل الموعد) — تنقل لـ«انطلق للراكب».
  Widget _buildScheduledGoFab(Map<String, dynamic> upcoming) {
    final pad = MediaQuery.viewPaddingOf(context).bottom;
    final when = formatScheduledRequestDate(upcoming);
    return Positioned(
      bottom: 200 + pad,
      left: 16,
      child: Material(
        color: CustomerUiTheme.amber,
        elevation: 6,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => _confirmGoToScheduled(upcoming),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.event_available_rounded,
                  color: CustomerUiTheme.navy,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'انطلق للراكب',
                      style: TextStyle(
                        color: CustomerUiTheme.navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    if (when != null)
                      Text(
                        'حجز مسبق — $when',
                        style: const TextStyle(
                          color: CustomerUiTheme.navy,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// أيقونة ثابتة تفتح قائمة الحجوزات المسبقة.
  Widget _buildScheduledFab(int count) {
    final pad = MediaQuery.viewPaddingOf(context).bottom;
    return Positioned(
      bottom: 200 + pad,
      left: 16,
      child: Material(
        color: CustomerUiTheme.navy,
        elevation: 4,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            if (!Get.isRegistered<BookingsController>()) {
              Get.put(BookingsController());
            } else {
              Get.find<BookingsController>().load();
            }
            Get.to(() => const OrderScreen(initialSegmentIndex: 1));
          },
          child: SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Center(
                  child: Icon(
                    Icons.event_available_rounded,
                    color: CustomerUiTheme.amber,
                    size: 26,
                  ),
                ),
                if (count > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        count > 9 ? '9+' : '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// بعد «اسحب للبدء» (متصل) أو أثناء رحلة/عداد — تظهر أدوات الخريطة.
  bool get _driverChromeUnlocked {
    return controller.isOnline.value ||
        controller.isTripActive.value ||
        controller.isAppTripMeterActive.value ||
        trip.assignedRequest.value != null ||
        trip.upcomingScheduled.value != null;
  }

  void _scheduleMapOverlayRefresh() {
    _mapOverlayDebounce?.cancel();
    // تأخير أطول يقلل إعادة بناء علامات الخريطة أثناء القيادة (وميض أبيض).
    _mapOverlayDebounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) _refreshMapOverlay();
    });
  }

  void _refreshMapOverlay() {
    if (!mounted) return;
    _mapOverlay.value = AppMapOverlay(
      markers: _buildMapMarkers(),
      polylines: _buildMapPolylines(),
    );
  }

  List<LatLng> _lastDrawnRoutePts = const [];

  List<AppMapPolyline> _buildMapPolylines() {
    final routePts = trip.routePoints;
    // لا تمسح المسار أثناء فراغ لحظي لـ assignAll/clear قبل إعادة الجلب.
    if (routePts.length >= 2) {
      _lastDrawnRoutePts = List<LatLng>.from(routePts);
    } else if (trip.assignedRequest.value == null) {
      _lastDrawnRoutePts = const [];
    }
    final pts =
        routePts.length >= 2 ? List<LatLng>.from(routePts) : _lastDrawnRoutePts;
    if (pts.length < 2) return const [];
    return [
      AppMapPolyline(
        id: 'trip_route',
        points: pts,
        color: const Color(MapStyleConfig.routeColor),
        width: 7,
        alpha: 0.95,
        cased: true,
      ),
    ];
  }

  List<AppMapMarker> _buildMapMarkers() {
    final markers = <AppMapMarker>[];
    // أيقونة السائق تُحدَّث فقط عبر updateDriverPose — لا تُدرج في الـ overlay
    // حتى لا تتكرر عند إعادة رسم المسار عند بدء الرحلة.

    final ar = trip.assignedRequest.value;
    final driverPos = safeLatLngFrom(controller.currentPosition.value);
    if (ar != null) {
      final st = ar['status']?.toString();
      if (st == 'Running') {
        final pickup = TripLocationHelpers.extractLocation(ar, 'startLocation');
        final drop = TripLocationHelpers.extractLocation(ar, 'destLocation');
        if (pickup != null &&
            drop != null &&
            (pickup.latitude != drop.latitude ||
                pickup.longitude != drop.longitude)) {
          // لا تضع دائرة الراكب تحت سيارة السائق عند القرب.
          final nearDriver = Geolocator.distanceBetween(
                driverPos.latitude,
                driverPos.longitude,
                pickup.latitude,
                pickup.longitude,
              ) <
              45;
          if (!nearDriver) {
            markers.add(AppMapMarker(
              id: 'passenger_pickup',
              point: pickup,
              kind: AppMapMarkerKind.passenger,
            ));
          }
        }
      }
    }

    final dest = trip.destination.value;
    if (dest != null) {
      final stNorm = ar != null ? normTripStatusForOrder(ar) : '';
      final typ = ar?['type']?.toString() ?? '';
      final isPassengerTarget = ar != null &&
          TripLocationHelpers.shouldNavigateToPickup(ar, stNorm, typ);
      final nearDriver = Geolocator.distanceBetween(
            driverPos.latitude,
            driverPos.longitude,
            dest.latitude,
            dest.longitude,
          ) <
          45;
      if (!(isPassengerTarget && nearDriver)) {
        markers.add(AppMapMarker(
          id: 'destination',
          point: dest,
          kind: isPassengerTarget
              ? AppMapMarkerKind.passenger
              : AppMapMarkerKind.destination,
        ));
      }
    }

    return markers;
  }


  Widget _buildDestinationSearchChip() {
    return Obx(() {
      final rawLabel = trip.destinationLabel.value?.trim();
      final hasDest = trip.destination.value != null;
      final hint = (rawLabel != null && rawLabel.isNotEmpty)
          ? repairUtf8Mojibake(rawLabel)
          : 'ابحث عن وجهة الراكب…';
      final estimate = hasDest ? _driverDestinationEstimateLabel() : null;
      return GestureDetector(
        onTap: () {
          setState(() {
            _showWelcomeBanner = false;
            _searchExpanded = true;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: CustomerUiTheme.glassCard(radius: 18),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: CustomerUiTheme.amber.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.search_rounded,
                  color: CustomerUiTheme.navy,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CustomerUiTheme.navy.withValues(
                          alpha: hasDest ? 1 : 0.72,
                        ),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (estimate != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        estimate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CustomerUiTheme.navy.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ] else if (hasDest && trip.routeLoading.value) ...[
                      const SizedBox(height: 3),
                      Text(
                        'جاري حساب المسافة والتكلفة…',
                        style: TextStyle(
                          color: CustomerUiTheme.muted.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasDest)
                GestureDetector(
                  onTap: () {
                    trip.clearManualDestination();
                    _destinationSearch.clear();
                    setState(() => _placeHits = []);
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: CustomerUiTheme.navy.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      color: CustomerUiTheme.navy.withValues(alpha: 0.65),
                      size: 18,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.chevron_left_rounded,
                  color: CustomerUiTheme.navy.withValues(alpha: 0.35),
                  size: 22,
                ),
            ],
          ),
        ),
      );
    });
  }

  /// مسافة + تكلفة تقديرية لوجهة البحث الحر (أسعار المتر/الفئة).
  String? _driverDestinationEstimateLabel({
    double? kmOverride,
    double? minutesOverride,
  }) {
    final km = kmOverride ?? trip.routeKm.value;
    if (km == null || km <= 0) return null;
    final mins = minutesOverride ??
        trip.routeMinutes.value ??
        (km / 25.0) * 60.0;
    final fare = categoryTripFareKmMinutesOnly(
      {
        'openPrice': controller.baseFare.value,
        'KMPrice': controller.pricePerKm.value,
        'timePrice': controller.pricePerMinute.value,
      },
      km,
      mins,
    );
    final kmTxt = km < 10 ? km.toStringAsFixed(1) : km.toStringAsFixed(0);
    if (fare == null || fare <= 0) {
      return '~ $kmTxt كم';
    }
    return '~ $kmTxt كم · ~ ${fare.round()} ل.س';
  }

  Widget _buildDriverSearchOverlay() {
    return TripBookingSearchOverlay(
      pickupLabel: 'موقعك الحالي',
      destinationController: _destinationSearch,
      hasSelectedDestination: trip.destination.value != null,
      onClose: () {
        FocusScope.of(context).unfocus();
        setState(() {
          _searchExpanded = false;
          _placeHits = [];
        });
      },
      onSearchSubmitted: (v) => _fetchPlaces(v.trim()),
      onSetOnMap: () {
        setState(() {
          _searchExpanded = false;
          _placeHits = [];
        });
        AppSnackBar.notify(
          'تحديد على الخريطة',
          'ابحث بالاسم لتحديد الوجهة ثم يظهر المسار على الخريطة',
        );
      },
      searchLoading: _searchLoading,
      placeHits: _placeHits
          .map(
            (h) => TripBookingPlaceHit(
              displayName: h.displayName,
              point: h.point,
              meta: h.meta,
            ),
          )
          .toList(),
      onPlaceSelected: (h) {
        final point = h.point is LatLng
            ? h.point as LatLng
            : LatLng(
                (h.point as dynamic).latitude as double,
                (h.point as dynamic).longitude as double,
              );
        final hit = _placeHits.firstWhere(
          (e) => e.displayName == h.displayName,
          orElse: () => _PlaceHit(
            displayName: h.displayName,
            point: point,
          ),
        );
        _applyDestination(hit.point, label: hit.displayName);
        setState(() {
          _searchExpanded = false;
          _placeHits = [];
        });
        _destinationSearch.clear();
        final from = safeLatLngFrom(controller.currentPosition.value);
        unawaited(
          _mapController.fitPoints([from, hit.point], padding: 72, animate: true),
        );
      },
      onClearDestination: () {
        _destinationSearch.clear();
        setState(() => _placeHits = []);
        trip.clearManualDestination();
      },
    );
  }

  void _onDestinationSearchChanged() {
    final q = _destinationSearch.text.trim();
    _searchDebounce?.cancel();
    if (q.length < 2) {
      if (mounted) {
        setState(() {
          _placeHits = [];
          _searchLoading = false;
        });
      }
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _fetchPlaces(q);
    });
  }

  Future<void> _fetchPlaces(String query) async {
    if (query.isEmpty) return;
    if (!mounted) return;
    setState(() => _searchLoading = true);
    try {
      final from = safeLatLngFrom(controller.currentPosition.value);
      final hits = await PhotonSearchService.search(
        query,
        near: from,
        limit: 10,
      );
      if (!mounted) return;
      const geo = Distance();
      setState(() {
        _placeHits = hits.map((h) {
          final straightKm =
              geo.as(LengthUnit.Kilometer, from, h.point).toDouble();
          // تقريب طريق ≈ خط مستقيم × 1.25 عند غياب OSRM في القائمة.
          final estKm = straightKm > 0.05 ? straightKm * 1.25 : null;
          final mins =
              estKm == null ? null : (estKm / 25.0) * 60.0;
          return _PlaceHit(
            displayName: h.subtitle.isEmpty
                ? h.name
                : '${h.name} — ${h.subtitle}',
            point: h.point,
            meta: estKm == null
                ? null
                : _driverDestinationEstimateLabel(
                    kmOverride: estKm,
                    minutesOverride: mins,
                  ),
          );
        }).toList();
        _searchLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _placeHits = [];
          _searchLoading = false;
        });
      }
    }
  }

  void _applyDestination(LatLng ll, {required String label}) {
    setState(() => _placeHits = []);
    trip.setManualDestination(ll, repairUtf8Mojibake(label));
  }

  void _goToMyLocationOnOpen({bool force = false}) {
    if (!_mapReady || !mounted) return;
    if (_didInitialLocate && !force) return;
    final pos = controller.currentPosition.value;
    if (!isFiniteLatLng(pos)) return;
    // تجاهل المركز الافتراضي (دمشق) حتى يصل GPS حقيقي.
    final isDefault = (pos.latitude - kDefaultMapCenter.latitude).abs() < 1e-6 &&
        (pos.longitude - kDefaultMapCenter.longitude).abs() < 1e-6;
    if (isDefault) return;

    _didInitialLocate = true;
    unawaited(
      _mapController.setNavigationCamera(
        point: pos,
        bearing: controller.currentHeading.value,
        zoom: MapStyleConfig.mapDefaultZoom,
        tilt: MapStyleConfig.mapDefaultTilt,
        lookAheadMeters: 0,
        animate: true,
      ),
    );
    unawaited(_mapController.updateDriverPose(
      pos,
      controller.currentHeading.value,
      tripActive: _isTripIconActive,
    ));
  }

  void _ensureMapShows(LatLng ll, {double zoom = 15}) {
    if (!isFiniteLatLng(ll)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _mapController.move(ll, zoom, animate: false);
      } catch (_) {}
    });
  }

  /// أيقونة خلفية ثلاثية فقط أثناء الرحلة الجارية (Running / عداد نشط).
  bool get _isTripIconActive {
    if (nav.active.value) return true;
    final ar = trip.assignedRequest.value;
    if (ar == null) return false;
    return normTripStatusForOrder(ar) == 'Running';
  }

  /// هل السيارة تتحرك بما يكفي لمتابعة الكاميرا؟
  LatLng? _lastFollowPos;
  bool get _isVehicleMovingForFollow {
    if (controller.isMoving.value) return true;
    final kph = controller.currentSpeedKph.value;
    if (kph.isFinite && kph >= 1.5) return true;
    return false;
  }

  bool _positionMovedEnough(LatLng? pos) {
    if (pos == null || !isFiniteLatLng(pos)) return false;
    final prev = _lastFollowPos;
    if (prev == null) {
      _lastFollowPos = pos;
      return true;
    }
    final meters = Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      pos.latitude,
      pos.longitude,
    );
    if (meters >= 3.0) {
      _lastFollowPos = pos;
      return true;
    }
    return false;
  }

  /// متابعة عند الحركة؛ عند السحب اليدوي يمكن تصفح الخريطة.
  DateTime? _lastNavCamAt;
  void _updateNavigationCamera({
    LatLng? pos,
    double? bearing,
    bool force = false,
  }) {
    if (!_mapReady || !mounted) return;

    final moving = _isVehicleMovingForFollow || _positionMovedEnough(pos);
    if (!force) {
      // لا استئناف تلقائي بعد السحب — المتابعة فقط بزر المتابعة / بدء الرحلة.
      if (!nav.followMode.value) return;
      if (!moving) return;
    } else {
      nav.followMode.value = true;
      if (pos != null) _lastFollowPos = pos;
    }

    final st = trip.assignedRequest.value != null
        ? normTripStatusForOrder(trip.assignedRequest.value!)
        : '';
    final tripStarted = nav.active.value || st == 'Running';
    final navigating = tripStarted ||
        st == 'Reserved' ||
        st == 'DriverArrived' ||
        st == 'AwaitingDestination' ||
        controller.isTripActive.value;

    final now = DateTime.now();
    if (!force &&
        _lastNavCamAt != null &&
        now.difference(_lastNavCamAt!) < const Duration(milliseconds: 220)) {
      return;
    }
    _snapBehindCar(
      pos: pos,
      bearing: bearing,
      force: force,
      tripStarted: tripStarted,
      navigating: navigating,
    );
  }

  void _snapBehindCar({
    LatLng? pos,
    double? bearing,
    bool force = false,
    bool tripStarted = true,
    bool navigating = true,
  }) {
    final now = DateTime.now();
    _lastNavCamAt = now;

    final point = pos ?? safeLatLngFrom(controller.currentPosition.value);
    final brg = bearing ?? controller.currentHeading.value;
    if (!isFiniteLatLng(point) || !brg.isFinite) return;

    final tilt = !navigating
        ? MapStyleConfig.mapDefaultTilt
        : (tripStarted
            ? MapStyleConfig.navFollowTiltActive
            : MapStyleConfig.navFollowTiltEnRoute);
    final lookAhead = !navigating
        ? 0.0
        : (tripStarted
            ? MapStyleConfig.navFollowLookAheadActive
            : MapStyleConfig.navFollowLookAheadEnRoute);
    // عند المتابعة المستمرة نحافظ على زوم المستخدم؛ الافتراضي فقط عند force.
    final preferredZoom = !navigating
        ? MapStyleConfig.mapDefaultZoom
        : (tripStarted
            ? MapStyleConfig.navFollowZoom
            : MapStyleConfig.mapDefaultZoom);
    if (!force) {
      // المتابعة المستمرة: الكاميرا تلحق السيارة المعروضة إطاراً بإطار.
      _mapController.setDriverFollow(
        enabled: true,
        tilt: tilt,
        lookAheadMeters: lookAhead,
      );
      return;
    }

    const snapDuration = Duration(milliseconds: 520);
    unawaited(
      _mapController.setNavigationCamera(
        point: point,
        bearing: brg,
        zoom: preferredZoom,
        tilt: tilt,
        lookAheadMeters: lookAhead,
        animate: true,
        duration: snapDuration,
      ),
    );
    _mapController.setDriverFollow(
      enabled: true,
      tilt: tilt,
      lookAheadMeters: lookAhead,
      hold: snapDuration,
    );
  }

  bool _driverInLiveTripPhase(Map<String, dynamic>? request) {
    if (request == null) return false;
    final st = normTripStatusForOrder(request);
    return st == 'Reserved' ||
        st == 'DriverArrived' ||
        st == 'AwaitingDestination' ||
        st == 'Running';
  }

  String _driverTripSheetTitle(Map<String, dynamic> request) {
    final id = request['id']?.toString() ?? '';
    final st = normTripStatusForOrder(request);
    if (scheduledInWaitingPhase(request)) {
      return scheduledGoWindowOpen(request)
          ? 'حان وقت الانطلاق — حجز #$id'
          : 'حجز مسبق #$id';
    }
    switch (st) {
      case 'Reserved':
        return 'متجه إلى الراكب';
      case 'DriverArrived':
        return 'بانتظار تأكيد الراكب';
      case 'AwaitingDestination':
        return 'بانتظار تحديد الوجهة';
      case 'Running':
        return 'الرحلة جارية';
      default:
        return 'طلب #$id';
    }
  }

  String _driverTripSheetSubtitle(Map<String, dynamic> request) {
    final st = normTripStatusForOrder(request);
    if (scheduledInWaitingPhase(request)) {
      final when = formatScheduledRequestDate(request);
      return when == null
          ? 'اضغط «انطلق للراكب» عندما تكون جاهزاً.'
          : 'موعد الرحلة: $when — اضغط «انطلق للراكب».';
    }
    switch (st) {
      case 'Reserved':
        return 'اسحب للأعلى لرؤية بيانات الراكب وإجراءات الرحلة.';
      case 'DriverArrived':
        return 'اللوحة مطوية لتبقى الخريطة واضحة. اسحب للأعلى عند الحاجة.';
      case 'AwaitingDestination':
        return 'بانتظار أن يحدد الراكب الوجهة.';
      case 'Running':
        return 'اسحب للأعلى لرؤية بيانات الراكب والوجهة وإنهاء الرحلة.';
      default:
        return 'اسحب للأعلى لرؤية كامل تفاصيل الطلب.';
    }
  }

  double _driverTripSheetMinSize({
    required Map<String, dynamic>? active,
    required Map<String, dynamic>? upcoming,
  }) {
    if (active != null && _driverInLiveTripPhase(active)) return 0.28;
    if (active != null) return 0.28;
    if (upcoming != null) return 0.22;
    return 0.0;
  }

  double _driverTripSheetInitialSize({
    required Map<String, dynamic>? active,
    required Map<String, dynamic>? upcoming,
  }) {
    if (active != null) {
      final st = normTripStatusForOrder(active);
      if (st == 'Running') return 0.52;
      if (_driverInLiveTripPhase(active)) return 0.46;
      return 0.42;
    }
    if (upcoming != null) return 0.34;
    return 0.0;
  }

  double _driverTripSheetMaxSize({
    required Map<String, dynamic>? active,
    required Map<String, dynamic>? upcoming,
  }) {
    if (active != null && _driverInLiveTripPhase(active)) return 0.72;
    if (active != null) return 0.62;
    if (upcoming != null) return 0.52;
    return 0.0;
  }

  double _driverTripSheetReservedBottom(BuildContext context) {
    final pad = MediaQuery.viewPaddingOf(context).bottom;
    final active = trip.assignedRequest.value;
    // أثناء الرحلة الحية: الصق اللوحة بأسفل الشاشة (زر الحالة مخفي).
    if (active != null && _driverInLiveTripPhase(active)) {
      return pad;
    }
    // اترك مساحة لشريط «اسحب للبدء/الإيقاف».
    return 104 + pad;
  }

  double _driverOverlayButtonsBaseBottom(BuildContext context) {
    final pad = MediaQuery.viewPaddingOf(context).bottom;
    // العداد الحر له لوحة كبيرة — ارفع الأدوات فوقها فقط.
    if (controller.isTripActive.value) {
      if (_freeMeterMinimized) return 88 + pad;
      return 280 + pad;
    }
    if (controller.isAppTripMeterActive.value) {
      return 220 + pad;
    }
    // فوق زر الحالة + زر العداد الحر دون تراكب.
    return 200 + pad;
  }

  // --- الويدجت الخاصة بالعداد ---
  Widget _buildActiveMeterPanel({bool showSlideToStop = true}) {
    if (_freeMeterMinimized && showSlideToStop) {
      return _buildMinimizedFreeMeterBar();
    }

    return Positioned(
      top: 72,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF11215B),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [const BoxShadow(color: Colors.black45, blurRadius: 15)],
        ),
        child: Column(
          children: [
            if (showSlideToStop)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'تصغير وتصفح الخريطة',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _freeMeterMinimized = true);
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(40, 40),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
                ),
              ),
            if (!showSlideToStop)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'عداد رحلة التطبيق — أنهِ من لوحة الطلب',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            // المؤشر الذكي (يتغير حسب الحالة)
            Obx(
              () => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: controller.isMoving.value
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  controller.isMoving.value
                      ? "جاري الحركة — يُحسب الكيلومتر"
                      : "متوقف — يُحسب الوقوف بالثانية",
                  style: TextStyle(
                    color: controller.isMoving.value
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),

            // السعر الأساسي
            Obx(
              () => Text(
                "${controller.meterCost.value.toInt()} ل.س",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 45,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Obx(() => MeterZoneBadge(label: controller.meterZoneLabel.value)),

            const Divider(color: Colors.white12, height: 30),

            Obx(
              () => Text(
                'فتح ${controller.baseFare.value.toInt()} ل.س · '
                'كم ${controller.pricePerKm.value.toInt()} · '
                'د ${controller.pricePerMinute.value.toInt()}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
            Obx(
              () {
                final kmPart = controller.meterKmCostComponent;
                final waitPart = controller.meterWaitingCostComponent;
                return Text(
                  'من الكيلو: ${kmPart.toInt()} ل.س · '
                  'من الوقوف: ${waitPart.toInt()} ل.س · '
                  'فتح: ${controller.baseFare.value.toInt()} ل.س',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                  textAlign: TextAlign.center,
                );
              },
            ),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Obx(
                  () => _buildMeterSubStat(
                    "الكيلومتر",
                    "${controller.distanceTraveled.value.toStringAsFixed(2)} كم",
                    Icons.map_rounded,
                  ),
                ),
                Obx(
                  () => _buildMeterSubStat(
                    "الزمن",
                    DriverController.formatMeterElapsed(
                      controller.isMoving.value
                          ? controller.meterElapsedSeconds.value
                          : controller.meterWaitingDisplaySeconds,
                    ),
                    Icons.schedule_rounded,
                  ),
                ),
                Obx(
                  () => _buildMeterSubStat(
                    "وقوف",
                    DriverController.formatMeterElapsed(
                      controller.meterWaitingDisplaySeconds,
                    ),
                    Icons.pause_circle_outline_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (showSlideToStop) _buildSlideToStopButton(),
          ],
        ),
      ),
    );
  }

  /// شريط مضغوط أسفل الشاشة — العداد يعمل والخريطة قابلة للتصفح.
  Widget _buildMinimizedFreeMeterBar() {
    final pad = MediaQuery.viewPaddingOf(context).bottom;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16 + pad,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _freeMeterMinimized = false);
          },
          child: Ink(
      decoration: BoxDecoration(
              color: const Color(0xFF11215B),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
        children: [
                  Obx(
                    () => Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: controller.isMoving.value
                            ? Colors.greenAccent
                            : Colors.orangeAccent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Obx(
                          () => Text(
                            '${controller.meterCost.value.toInt()} ل.س',
                            style: const TextStyle(
                color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
              ),
            ),
          ),
                        const SizedBox(height: 2),
                        Obx(
                          () => Text(
                            '${controller.distanceTraveled.value.toStringAsFixed(2)} كم · '
                            '${DriverController.formatMeterElapsed(
                              controller.isMoving.value
                                  ? controller.meterElapsedSeconds.value
                                  : controller.meterWaitingDisplaySeconds,
                            )}'
                            '${controller.isMoving.value ? '' : ' (وقوف)'}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Obx(
                          () => MeterZoneBadge(
                            label: controller.meterZoneLabel.value,
                            dense: true,
            ),
          ),
        ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'تكبير اللوحة',
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _freeMeterMinimized = false);
                    },
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 28),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlideToStopButton() {
    return SizedBox(
      width: double.infinity,
      height: AppButtonDims.heightLg,
      child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent,
          foregroundColor: Colors.white,
          minimumSize: AppButtonDims.minSizeFullLg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        onPressed: _freeMeterReceiptOpen
            ? null
            : () {
                unawaited(_finishFreeMeterWithReceipt());
              },
        icon: const Icon(Icons.stop_rounded),
        label: const Text(
          'إنهاء العداد وعرض الفاتورة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// إنهاء على السيرفر أولاً ثم فاتورة واحدة فقط (بدون طلب إنهاء ثانٍ).
  Future<void> _finishFreeMeterWithReceipt() async {
    if (_freeMeterReceiptOpen) return;
    _freeMeterReceiptOpen = true;
    if (_freeMeterMinimized) {
      setState(() => _freeMeterMinimized = false);
    }

    final activeController = Get.find<DriverController>();
    final costSnap = activeController.meterCost.value;
    final zoneLabelSnap = activeController.meterZoneLabel.value;
    final kmSnap = activeController.distanceTraveled.value;
    final elapsedSnap = activeController.meterElapsedSeconds.value;
    final waitSnap = activeController.meterWaitingDisplaySeconds;

    // مؤشر تحميل قصير أثناء الحفظ على السيرفر
    unawaited(
      Get.dialog<void>(
        const Center(child: CircularProgressIndicator()),
        barrierDismissible: false,
      ),
    );

    final ok = await controller.endTrip();
    if (Get.isDialogOpen == true) {
      Get.back(); // أغلق التحميل
    }

    if (!ok) {
      _freeMeterReceiptOpen = false;
      return;
    }

    try {
      await Get.dialog<void>(
        barrierDismissible: false,
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                size: 60,
                color: Color(0xFF11215B),
              ),
              const SizedBox(height: 15),
              const Text(
                  'إجمالي التكلفة',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
                Text(
                  '${costSnap.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} ل.س',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF11215B),
                  ),
                ),
                MeterZoneBadge(label: zoneLabelSnap, onDark: false),
              const SizedBox(height: 10),
                Text(
                  'الكيلومتر: ${kmSnap.toStringAsFixed(2)} كم',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  'الزمن: ${DriverController.formatMeterElapsed(elapsedSnap)} · '
                  'وقوف: ${DriverController.formatMeterElapsed(waitSnap)}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF11215B),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                      if (Get.isDialogOpen ?? false) Get.back();
                  },
                  child: const Text(
                      'موافق',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    } finally {
      _freeMeterReceiptOpen = false;
    }
  }

  Future<void> _showReceiveRadiusPicker() async {
    final current = controller.receiveRadiusKm.value;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'نطاق استقبال الطلبات',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF11215B),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'ستصلك الطلبات الفورية ضمن هذه المسافة عن الزبون',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                for (final km in DriverController.receiveRadiusOptions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: km == current
                            ? const Color(0xFF11215B)
                            : const Color(0xFFF1F5F9),
                        foregroundColor:
                            km == current ? Colors.white : const Color(0xFF11215B),
                        elevation: 0,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, km),
                      child: Text(
                        '$km كم',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen != null && chosen != current) {
      await controller.setReceiveRadiusKm(chosen);
    }
  }

  Future<void> _showFreeMeterOptions() async {
    if (trip.assignedRequest.value != null) {
      AppSnackBar.notify('تنبيه', 'لا يمكن تشغيل العداد الحر أثناء وجود طلب عبر التطبيق');
      return;
    }
    // لا نحبس الواجهة على الشبكة — نفتح الشيت فوراً ونحدّث الأسعار بالخلفية.
    unawaited(controller.fetchPricingFromServer(showError: true));
    final bottomSafe = MediaQuery.paddingOf(Get.context ?? context).bottom;
    Get.bottomSheet(
      isScrollControlled: true,
      ignoreSafeArea: false,
      Container(
        padding: EdgeInsets.fromLTRB(
          25,
          28,
          25,
          28 + bottomSafe + 24,
        ),
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Text(
              "ابدأ العداد الحر",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Obx(
              () => Text(
                'فتح ${controller.baseFare.value.toInt()} ل.س · '
                'كل كم ${controller.pricePerKm.value.toInt()} · '
                'كل دقيقة وقوف ${controller.pricePerMinute.value.toInt()}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF11215B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'يُعرض أثناء الرحلة: الكيلومتر + الزمن + دقائق الوقوف المحسوبة',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Obx(
              () => Text(
                controller.meterPricingUpdatedAt.value == null
                    ? 'جاري مزامنة الأسعار من لوحة التحكم…'
                    : 'آخر تحديث: ${controller.meterPricingUpdatedAt.value!.hour.toString().padLeft(2, '0')}:${controller.meterPricingUpdatedAt.value!.minute.toString().padLeft(2, '0')}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              height: AppButtonDims.heightLg,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF11215B),
                  elevation: 4,
                  minimumSize: AppButtonDims.minSizeFullLg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppButtonDims.radius),
                  ),
                ),
                onPressed: () async {
                  if (trip.assignedRequest.value != null) {
                    AppSnackBar.notify('تنبيه', 'لا يمكن تشغيل العداد الحر أثناء وجود طلب عبر التطبيق');
                    return;
                  }
                  final started = await controller.startTrip();
                  if (started) {
                    // startTrip يوقف الاستقبال ويحفظ استئناف الاتصال بعد الإيقاف.
                    if (mounted) setState(() => _freeMeterMinimized = false);
                    _closeImmediateBottomSheet();
                    _openImmediateDialogRequestId = null;
                    _lastImmediateNotifiedId = null;
                    Get.back();
                  }
                },
                child: const Text(
                  "بدء الرحلة",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // --- مكونات مساعدة ---
  Widget _buildBottomStatusButton() {
    final pad = MediaQuery.viewPaddingOf(context).bottom;
    return Positioned(
      bottom: 28 + pad,
      left: 24,
      right: 24,
    child: Obx(
        () => DriverSlideToToggle(
          key: ValueKey(controller.isOnline.value),
          isOnline: controller.isOnline.value,
          hint: controller.isOnline.value
              ? 'اسحب لإيقاف استقبال الطلبات'
              : 'اسحب لبدء استقبال الطلبات',
          onToggle: () {
            final goingOnline = !controller.isOnline.value;
            if (goingOnline && controller.isTripActive.value) {
              AppSnackBar.notify(
                'العداد الحر',
                'أوقف العداد الحر أولاً لاستقبال طلبات التطبيق',
                duration: const Duration(seconds: 4),
              );
              return;
            }
          controller.isOnline.toggle();
            controller.setDriverAvailability(controller.isOnline.value);
        },
      ),
    ),
  );
  }

  Widget _buildMeterSubStat(String label, String value, IconData icon) =>
      Column(
        children: [
          Icon(icon, color: Colors.white54, size: 16),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      );

  Future<void> _driverCancelScheduled(int requestId) async {
    await showDriverScheduledCancelDialog(
      requestId: requestId,
      onSuccess: trip.pollAssignedRequests,
    );
  }

  Future<void> _driverCancelEnRoute(int requestId) async {
    await showDriverCancelEnRouteDialog(
      requestId: requestId,
      onSuccess: trip.pollAssignedRequests,
    );
  }

  void _openSosConfirmDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DriverSosCountdownDialog(
        onSend: () => controller.sendSOS(),
      ),
    );
  }
}


class _DriverBottomTripSheet extends StatelessWidget {
  const _DriverBottomTripSheet({
    super.key,
    required this.active,
    required this.upcoming,
    required this.trip,
    required this.reservedBottom,
    required this.initialSize,
    required this.minSize,
    required this.maxSize,
    required this.title,
    required this.subtitle,
    required this.onCancelScheduled,
    required this.onCancelEnRoute,
    required this.onGoToPassenger,
  });

  final Map<String, dynamic>? active;
  final Map<String, dynamic>? upcoming;
  final DriverAssignedTripController trip;
  final double reservedBottom;
  final double initialSize;
  final double minSize;
  final double maxSize;
  final String title;
  final String subtitle;
  final Future<void> Function(int requestId) onCancelScheduled;
  final Future<void> Function(int requestId) onCancelEnRoute;
  final Future<void> Function(Map<String, dynamic> request) onGoToPassenger;

  Widget _sheetHandle() {
    return const CustomerBookingSheetHandle();
  }

  @override
  Widget build(BuildContext context) {
    final icon = active != null
        ? Icons.local_taxi_rounded
        : Icons.event_available_rounded;
    final iconColor =
        active != null ? TripBookingTheme.navy : Colors.orange.shade800;
    final liveTrip = active != null &&
        const {
          'Reserved',
          'DriverArrived',
          'Running',
          'AwaitingDestination',
        }.contains(normTripStatusForOrder(active!));
    final sidePad = liveTrip ? 0.0 : 12.0;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad, reservedBottom),
        child: DraggableScrollableSheet(
          expand: false,
          snap: true,
          initialChildSize: initialSize,
          minChildSize: minSize,
          maxChildSize: maxSize,
          builder: (context, scrollController) {
            return Container(
              decoration: liveTrip
                  ? CustomerBookingSheetStyle.decoration().copyWith(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    )
                  : CustomerBookingSheetStyle.decoration(),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                children: [
                  _sheetHandle(),
                  if (active != null)
                    Obx(
                      () => DriverAssignedTripStrip(
                        request: active!,
                        routeKm: trip.routeKm.value,
                        onMarkArrived: trip.markArrived,
                        onStartTrip: trip.startAssignedTrip,
                        onFinishTrip: trip.finishTrip,
                        onCancelScheduled: onCancelScheduled,
                        onCancelEnRoute: onCancelEnRoute,
                      ),
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: TripBookingTheme.addressBoxDecoration(),
                      child: Row(
                        children: [
                          Icon(icon, color: iconColor, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: TripBookingTheme.navy,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    DriverUpcomingScheduledStrip(
                      request: upcoming!,
                      onCancelScheduled: onCancelScheduled,
                      onGoToPassenger: () => onGoToPassenger(upcoming!),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PlaceHit {
  final String displayName;
  final LatLng point;
  final String? meta;

  _PlaceHit({
    required this.displayName,
    required this.point,
    this.meta,
  });
}
