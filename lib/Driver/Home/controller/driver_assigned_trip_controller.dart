import 'dart:async';
import '../../../core/constants/snack_bar.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/osrm_route_client.dart';
import '../../../core/constants/driver_poll_intervals.dart';
import '../../../core/services/trip_api_service.dart';
import '../../../core/utils/app_alert_sound.dart';
import '../../../core/utils/driver_order_display.dart';
import '../../../core/utils/trip_completion_message.dart';
import '../../../core/widgets/trip_completion_screen.dart';
import '../../../core/widgets/trip_payment_panel.dart';
import '../../../core/utils/safe_lat_lng.dart';
import '../../../core/utils/trip_location_helpers.dart';
import '../service/driver_server_sync_service.dart';
import 'driver_location_controller.dart';
import 'driver_navigation_controller.dart';

/// تركيز الخريطة بعد تحديث الطلب (يُنفَّذ من الشاشة).
class DriverMapFocusEvent {
  const DriverMapFocusEvent.point(
    this.point, {
    this.zoom = 15,
    this.force = false,
  })  : fitPoints = null,
        padding = 56;
  const DriverMapFocusEvent.fit(
    this.fitPoints, {
    this.padding = 56,
    this.force = false,
  })  : point = null,
        zoom = null;

  final LatLng? point;
  final double? zoom;
  final List<LatLng>? fitPoints;
  final double padding;
  /// يتجاوز وضع التصفح اليدوي (مثل اختيار وجهة يدوياً).
  final bool force;
}

/// طلبات مُسندة، مسار، إشعارات السائق، وصول/إنهاء.
class DriverAssignedTripController extends GetxController {
  DriverAssignedTripController(this.driver);

  final DriverController driver;
  static final Distance _geoDist = Distance();

  final assignedRequest = Rxn<Map<String, dynamic>>();
  final upcomingScheduled = Rxn<Map<String, dynamic>>();
  final destination = Rxn<LatLng>();
  final destinationLabel = RxnString();
  final routePoints = <LatLng>[].obs;
  final routeKm = Rxn<double>();
  /// مدة المسار بالدقائق (من OSRM) — لتقدير التكلفة عند البحث عن وجهة.
  final routeMinutes = Rxn<double>();
  final routeLoading = false.obs;

  int? proximityArrivalDialogShownForRequestId;
  int? _appMeterStartedForRequestId;

  Future<void> _maybeStartAppTripMeter(Map<String, dynamic> order) async {
    final id = int.tryParse(order['id']?.toString() ?? '') ?? 0;
    if (id <= 0) return;
    if (_appMeterStartedForRequestId == id && driver.isAppTripMeterActive.value) {
      return;
    }
    final ok = await driver.startAppTripMeter(order);
    if (ok) {
      _appMeterStartedForRequestId = id;
    } else {
      AppSnackBar.notify(
        'عداد الرحلة',
        'تعذر تشغيل العداد — تحقق من أسعار فئة السيارة',
      );
    }
  }

  void _stopAppTripMeterIfNeeded() {
    if (_appMeterStartedForRequestId != null &&
        driver.isAppTripMeterActive.value) {
      driver.endAppTripMeter();
    }
    _appMeterStartedForRequestId = null;
  }
  Timer? _routeDebounce;
  Timer? _driverNotifPoll;
  final Set<int> _shownDriverNotificationIds = <int>{};
  LatLng? _lastRouteFetchFrom;
  String _lastRouteFetchKey = '';
  int _routeFetchGeneration = 0;

  /// يُستدعى من الشاشة لتحريك الخريطة.
  void Function(DriverMapFocusEvent event)? onMapFocus;

  /// حوار «الراكب جاهز» — يُمرَّر من الشاشة لأنه يحتاج BuildContext.
  Future<String?> Function()? showPassengerReadyDialog;

  /// حوار «انطلق للراكب» عند فتح نافذة الحجز المسبق أو حلول موعده.
  Future<String?> Function(int requestId, String title, String body)?
      showSchedAtTimeDialog;

  @override
  void onInit() {
    super.onInit();
    driver.clearAppTripUiForFreeMeter = _clearAppTripUiForFreeMeter;
    _driverNotifPoll = Timer.periodic(DriverPollIntervals.notifications, (_) {
      pollDriverNotifications();
    });
    Future.microtask(pollDriverNotifications);
  }

  void _clearAppTripUiForFreeMeter() {
    assignedRequest.value = null;
    upcomingScheduled.value = null;
    destination.value = null;
    destinationLabel.value = null;
    routePoints.clear();
    routeKm.value = null;
    routeMinutes.value = null;
    proximityArrivalDialogShownForRequestId = null;
    _stopAppTripMeterIfNeeded();
  }

  /// طلب/رحلة عداد حر على السيرفر — ليست طلب تطبيق.
  static bool _isFreeMeterTripRow(Map<String, dynamic> r) {
    final bk = '${r['billing_kind'] ?? r['billingKind'] ?? ''}'
        .trim()
        .toLowerCase();
    if (bk.contains('free_meter') || bk.contains('freemeter')) return true;
    if (r['is_app_request'] == false || r['isAppRequest'] == false) {
      final desc =
          '${r['locationDesc'] ?? r['location_desc'] ?? r['description'] ?? ''}';
      if (desc.contains('عداد حر') || desc.toLowerCase().contains('free_meter')) {
        return true;
      }
    }
    return false;
  }

  @override
  void onClose() {
    if (identical(driver.clearAppTripUiForFreeMeter, _clearAppTripUiForFreeMeter)) {
      driver.clearAppTripUiForFreeMeter = null;
    }
    _routeDebounce?.cancel();
    _driverNotifPoll?.cancel();
    super.onClose();
  }

  void onAppResumed() {
    pollDriverNotifications();
    if (Get.isRegistered<DriverServerSyncService>()) {
      unawaited(Get.find<DriverServerSyncService>().syncNow(force: true));
    } else {
      pollAssignedRequests();
    }
  }

  void applyAcceptedTripPreview(Map<String, dynamic> preview) {
    final row = Map<String, dynamic>.from(preview);
    row.putIfAbsent('status', () => 'Reserved');
    if (requestIsScheduled(row) && scheduledInWaitingPhase(row)) {
      // الحجز المسبق لا يشغل السائق قبل نافذة الانطلاق — لا تمس الرحلة الحالية.
      upcomingScheduled.value = row;
      return;
    }
    final dest = TripLocationHelpers.extractLocation(preview, 'startLocation');
    if (dest == null) return;
    row.putIfAbsent('type', () => 'Immediate');
    upcomingScheduled.value = null;
    assignedRequest.value = row;
    destination.value = dest;
    destinationLabel.value = 'موقع الراكب — بانتظار تأكيد الزبون في التطبيق';
    scheduleRouteFetch(force: true);
    _focusPickupAfterAssign(dest);
  }

  void _clearRouteAndDestination() {
    destination.value = null;
    destinationLabel.value = null;
    routePoints.clear();
    routeKm.value = null;
    routeMinutes.value = null;
    proximityArrivalDialogShownForRequestId = null;
    if (Get.isRegistered<DriverNavigationController>()) {
      Get.find<DriverNavigationController>().stopNavigation();
    }
  }

  Future<void> pollAssignedRequests({
    List<Map<String, dynamic>>? prefetched,
  }) async {
    final driverId = driver.box.read('driver_id');
    final did =
        driverId is int ? driverId : int.tryParse(driverId?.toString() ?? '');
    if (did == null) {
      final previewOnly = driver.acceptedTripPreview.value;
      if (previewOnly != null) applyAcceptedTripPreview(previewOnly);
      return;
    }
    try {
      final list = prefetched ?? await TripApiService.fetchDriverRequests(did);
      if (list.isEmpty &&
          assignedRequest.value == null &&
          upcomingScheduled.value == null &&
          driver.acceptedTripPreview.value == null) {
        return;
      }
      Map<String, dynamic>? active;
      Map<String, dynamic>? upcoming;
      int? prevAssignedId;
      final prevIdRaw =
          assignedRequest.value?['id'] ?? upcomingScheduled.value?['id'];
      if (prevIdRaw != null) {
        prevAssignedId = int.tryParse(prevIdRaw.toString()) ?? 0;
        if (prevAssignedId <= 0) prevAssignedId = null;
      }
      for (final r in list) {
        final row = Map<String, dynamic>.from(r);
        // رحلة العداد الحر على السيرفر ليست «طلب تطبيق» — تجاهلها هنا.
        if (_isFreeMeterTripRow(row)) continue;

        final st = row['status']?.toString();
        final typ = row['type']?.toString() ?? '';
        final reqDriverId = int.tryParse(
              row['driverId']?.toString() ?? row['driver_id']?.toString() ?? '') ??
            0;
        final targetDid = int.tryParse(
              row['targetDriverId']?.toString() ??
                  row['target_driver_id']?.toString() ??
                  '') ??
            0;
        if (st == 'Reserved' &&
            requestIsScheduled(row) &&
            scheduledInWaitingPhase(row)) {
          upcoming ??= row;
          continue;
        }
        if (st == 'Reserved' ||
            st == 'DriverArrived' ||
            st == 'AwaitingDestination' ||
            st == 'Running') {
          active ??= row;
          continue;
        }
        if (st == 'Pending' &&
            typ == 'Immediate' &&
            (reqDriverId == did || targetDid == did)) {
          // لا تعتبره مسنداً قبل القبول، ولا تشغّل الصوت هنا —
          // حوار الطلب الفوري يعرضه مرة واحدة فقط حتى القبول/التجاهل.
          continue;
        }
      }

      // أثناء العداد الحر: لا استقبال/عرض طلبات التطبيق ولا إيقاف العداد
      // (يبقى الحجز المسبق المقبول ظاهراً كأيقونة).
      if (driver.isTripActive.value) {
        upcomingScheduled.value = upcoming;
        if (assignedRequest.value != null) {
          assignedRequest.value = null;
          _clearRouteAndDestination();
          _stopAppTripMeterIfNeeded();
        }
        return;
      }

      if (active == null) {
        final preview = driver.acceptedTripPreview.value;
        if (preview != null && scheduledTripLiveOnMap(preview)) {
          final pid = int.tryParse(preview['id']?.toString() ?? '') ?? 0;
          final stillActiveOnServer = pid > 0 &&
              list.any((raw) {
                if (raw is! Map) return false;
                final row = Map<String, dynamic>.from(raw);
                if (_isFreeMeterTripRow(row)) return false;
                if ((int.tryParse(row['id']?.toString() ?? '') ?? 0) != pid) {
                  return false;
                }
                final st = normTripStatusForOrder(row);
                return st == 'Reserved' ||
                    st == 'DriverArrived' ||
                    st == 'AwaitingDestination' ||
                    st == 'Running' ||
                    (st == 'Pending' && requestIsImmediate(row));
              });
          if (stillActiveOnServer) {
            applyAcceptedTripPreview(preview);
            return;
          }
          driver.clearAcceptedTripPreviewIfIdsMatch(pid);
        }
        if (upcoming != null) {
          upcomingScheduled.value = upcoming;
          assignedRequest.value = null;
          routePoints.clear();
          routeKm.value = null;
          routeMinutes.value = null;
          destination.value = null;
          destinationLabel.value = null;
          proximityArrivalDialogShownForRequestId = null;
          return;
        }
        if (assignedRequest.value != null || upcomingScheduled.value != null) {
          final cancelledByCustomer = prevAssignedId != null &&
              TripLocationHelpers.requestAppearsRemovedInDriverList(
                list,
                prevAssignedId,
              );
          if (prevAssignedId != null) {
            driver.clearAcceptedTripPreviewIfIdsMatch(prevAssignedId);
          }
          assignedRequest.value = null;
          upcomingScheduled.value = null;
          _clearRouteAndDestination();
          _stopAppTripMeterIfNeeded();
          if (cancelledByCustomer) {
            AppSnackBar.notify(
              'تم إلغاء الطلب',
              'أُلغي الطلب #$prevAssignedId',
              duration: const Duration(seconds: 5),
            );
          }
        }
        return;
      }

      upcomingScheduled.value = upcoming;
      driver.clearAcceptedTripPreview();

      final activeOrder = active;
      final st = activeOrder['status']?.toString() ?? '';
      final tripType = activeOrder['type']?.toString() ?? '';
      LatLng? dest;
      String? label;
      if (st == 'Running') {
        dest = TripLocationHelpers.extractLocation(activeOrder, 'destLocation') ??
            TripLocationHelpers.extractLocation(activeOrder, 'startLocation');
        label = TripLocationHelpers.extractLocation(activeOrder, 'destLocation') !=
                null
            ? 'وجهة الراكب — التوجيه على الخريطة'
            : 'موقع الراكب';
      } else if (st == 'AwaitingDestination') {
        dest = TripLocationHelpers.extractLocation(activeOrder, 'startLocation');
        label = 'موقع الراكب — بانتظار تأكيد الوجهة من الراكب';
      } else if (st == 'Pending' && tripType == 'Immediate') {
        dest = TripLocationHelpers.extractLocation(activeOrder, 'startLocation');
        label = 'طلب موجّه إليك — جاري المزامنة (إن ضغطت قبول انتظر ثانية)';
      } else if (st == 'Reserved' || st == 'DriverArrived') {
        dest = TripLocationHelpers.extractLocation(activeOrder, 'startLocation');
        if (scheduledInWaitingPhase(activeOrder)) {
          final when = formatScheduledRequestDate(activeOrder);
          label = when != null
              ? 'حجز مسبق — الموعد $when'
              : 'حجز مسبق — بانتظار وقت الرحلة';
        } else {
          label = 'موقع الراكب — التوجيه إليه أولاً';
        }
      } else {
        dest = TripLocationHelpers.extractLocation(activeOrder, 'startLocation');
        label = 'موقع الراكب';
      }

      assignedRequest.value = activeOrder;
      destination.value = dest;
      destinationLabel.value = label;
      scheduleRouteFetch(force: true);

      if (st == 'Running') {
        unawaited(_maybeStartAppTripMeter(activeOrder));
      } else if (_appMeterStartedForRequestId != null) {
        _stopAppTripMeterIfNeeded();
      }

      if (TripLocationHelpers.shouldNavigateToPickup(activeOrder, st, tripType) &&
          dest != null) {
        final pickupPin = dest;
        if (scheduledInWaitingPhase(activeOrder)) {
          onMapFocus?.call(DriverMapFocusEvent.point(pickupPin, zoom: 13));
          return;
        }
        _focusPickupAfterAssign(pickupPin);
        if (st == 'Reserved' &&
            TripLocationHelpers.shouldPromptProximityForOrder(activeOrder)) {
          maybePromptProximityArrival(
            safeLatLngFrom(driver.currentPosition.value),
          );
        }
      }
    } catch (_) {}
  }

  void _focusPickupAfterAssign(LatLng pickup) {
    final driverHere = safeLatLngFrom(driver.currentPosition.value);
    if (!isFiniteLatLng(pickup) || !isFiniteLatLng(driverHere)) return;
    final gap = _geoDist.as(LengthUnit.Meter, driverHere, pickup);
    if (gap <= 150) {
      onMapFocus?.call(DriverMapFocusEvent.point(pickup, zoom: 16));
      return;
    }
    onMapFocus?.call(
      DriverMapFocusEvent.fit([driverHere, pickup]),
    );
  }

  bool _driverMovedEnoughForRouteRefetch(LatLng from) {
    final last = _lastRouteFetchFrom;
    if (last == null) return true;
    // لا نعيد جلب المسار إلا بعد تحرك ملموس (~200م).
    return _geoDist.as(LengthUnit.Meter, last, from) > 200;
  }

  void onDriverPositionUpdated(LatLng pos) {
    if (!isFiniteLatLng(pos)) return;
    final ar = assignedRequest.value;
    final st = ar?['status']?.toString() ?? '';
    // لا نُرجع الكاميرا للموقع تلقائياً أثناء التصفح — المتابعة فقط عبر
    // followMode وكاميرا التنقّل في الشاشة الرئيسية.
    scheduleRouteFetch();
    if (Get.isRegistered<DriverNavigationController>()) {
      final nav = Get.find<DriverNavigationController>();
      unawaited(nav.onDriverMoved(pos).then((needReroute) {
        if (needReroute) scheduleRouteFetch(force: true);
      }));
    }
    if (st == 'Reserved' &&
        ar != null &&
        TripLocationHelpers.shouldPromptProximityForOrder(ar)) {
      maybePromptProximityArrival(pos);
    }
  }

  Future<void> _startOrUpdateNavigation(
    RoadRouteResult route,
    LatLng to,
  ) async {
    final nav = Get.isRegistered<DriverNavigationController>()
        ? Get.find<DriverNavigationController>()
        : Get.put(DriverNavigationController());
    final pos = safeLatLngFrom(driver.currentPosition.value);
    if (nav.active.value) {
      await nav.updateNavigation(
        routePoints: route.points,
        steps: route.steps,
        destination: to,
        distanceKm: route.distanceKm,
        durationMin: route.durationMinutes,
        driverPos: pos,
      );
    } else {
      await nav.startNavigation(
        routePoints: route.points,
        steps: route.steps,
        destination: to,
        distanceKm: route.distanceKm,
        durationMin: route.durationMinutes,
        driverPos: pos,
      );
    }
  }

  void scheduleRouteFetch({bool force = false}) {
    if (destination.value == null) return;
    if (!force && routeLoading.value) return;
    final from = safeLatLngFrom(driver.currentPosition.value);
    if (!force && !_driverMovedEnoughForRouteRefetch(from)) return;
    _routeDebounce?.cancel();
    _routeDebounce =
        Timer(const Duration(milliseconds: 350), fetchRoute);
  }

  Future<void> fetchRoute() async {
    final to = destination.value;
    if (to == null || !isFiniteLatLng(to)) return;
    final from = safeLatLngFrom(driver.currentPosition.value);
    final key =
        '${from.latitude.toStringAsFixed(5)},${from.longitude.toStringAsFixed(5)}|'
        '${to.latitude.toStringAsFixed(5)},${to.longitude.toStringAsFixed(5)}';
    if (key == _lastRouteFetchKey && routePoints.length >= 2) return;

    final meters = _geoDist.as(LengthUnit.Meter, from, to);
    if (meters < 45) {
      final bumpLat = meters < 12 ? 0.00012 : 0.0;
      final toDraw =
          bumpLat > 0 ? LatLng(to.latitude + bumpLat, to.longitude) : to;
      routeLoading.value = false;
      routeKm.value = meters / 1000.0;
      routeMinutes.value = ((meters / 1000.0) / 25.0) * 60.0;
      routePoints.assignAll([from, toDraw]);
      _lastRouteFetchFrom = from;
      _lastRouteFetchKey = key;
      return;
    }

    final gen = ++_routeFetchGeneration;
    _lastRouteFetchFrom = from;
    routeLoading.value = true;
    try {
      final needSteps =
          assignedRequest.value?['status']?.toString() == 'Running';
      final route = await OsrmRouteClient.fetchRoute(
        from,
        to,
        withSteps: needSteps,
      );
      if (gen != _routeFetchGeneration) return;
      if (route != null && route.points.length >= 2) {
        _lastRouteFetchKey = key;
        routePoints.assignAll(route.points);
        if (route.distanceKm != null && route.distanceKm! > 0) {
          routeKm.value = route.distanceKm;
        }
        if (route.durationMinutes != null && route.durationMinutes! > 0) {
          routeMinutes.value = route.durationMinutes;
        } else if (routeKm.value != null && routeKm.value! > 0) {
          routeMinutes.value = (routeKm.value! / 25.0) * 60.0;
        }
        if (needSteps) {
          unawaited(_startOrUpdateNavigation(route, to));
        }
      }
    } catch (_) {
    } finally {
      if (gen == _routeFetchGeneration) {
        routeLoading.value = false;
      }
    }

    if (routeKm.value == null || routeKm.value! <= 0) {
      unawaited(_applyServerRouteSummary(gen, from, to));
    }
  }

  Future<void> _applyServerRouteSummary(
    int gen,
    LatLng from,
    LatLng to,
  ) async {
    try {
      final r = await TripApiService.fetchDrivingSummary(from: from, to: to);
      if (gen != _routeFetchGeneration) return;
      if (!r.ok || r.dataMap == null) return;
      final km = (r.dataMap!['distance_km'] as num?)?.toDouble();
      if (km != null && km > 0) {
        routeKm.value = km;
        final mins = (r.dataMap!['duration_minutes'] as num?)?.toDouble() ??
            (r.dataMap!['duration_min'] as num?)?.toDouble();
        routeMinutes.value =
            (mins != null && mins > 0) ? mins : (km / 25.0) * 60.0;
      }
    } catch (_) {}
  }

  Future<void> markArrived(int requestId) async {
    try {
      final r = await TripApiService.driverArrived(requestId);
      if (r.ok) {
        AppSnackBar.notify('تم', 'اضغط «بدء الرحلة» عندما يصعد الراكب');
        await _refreshAssignedAfterAction();
      } else {
        AppSnackBar.notify('فشل', r.message ?? 'تعذر التسجيل');
      }
    } catch (e) {
      AppSnackBar.notify('خطأ', '$e');
    }
  }

  Future<void> startAssignedTrip(int requestId) async {
    try {
      var r = await TripApiService.startTrip(requestId);
      if (!r.ok) {
        await _refreshAssignedAfterAction();
        r = await TripApiService.startTrip(requestId);
      }
      if (r.ok) {
        unawaited(AppAlertSound.playTripStarted());
        AppSnackBar.notify('تم', 'بدأت الرحلة');
        scheduleRouteFetch(force: true);
        unawaited(_refreshAssignedAfterAction());
      } else {
        AppSnackBar.notify(
          'فشل',
          r.message ?? 'تعذر بدء الرحلة — جرّب «إلغاء الطلب»',
        );
      }
    } catch (e) {
      AppSnackBar.notify('خطأ', '$e');
    }
  }

  Future<void> finishTrip(int requestId) async {
    Map<String, dynamic>? tripSnap;
    final ar = assignedRequest.value;
    if (ar != null &&
        (int.tryParse(ar['id']?.toString() ?? '') ?? 0) == requestId) {
      tripSnap = Map<String, dynamic>.from(ar);
    }
    // التقط قراءة العداد قبل إيقافه.
    final hadMeter = driver.isAppTripMeterActive.value;
    final meterCostSnap = driver.meterCost.value;
    final meterKmSnap = driver.distanceTraveled.value;
    final meterWaitSnap = driver.meterBilledMinutes.value;
    final meterElapsedSnap = driver.meterElapsedSeconds.value;
    try {
      final r = await TripApiService.finishTrip(
        requestId,
        body: driver.buildAppTripFinishPayload(),
      );
      if (r.ok) {
        driver.endAppTripMeter();
        _appMeterStartedForRequestId = null;
        assignedRequest.value = null;
        _clearRouteAndDestination();
        final dataMap = r.dataMap;
        final raw = r.raw;
        final apiCost = '${raw?['finalCost'] ?? dataMap?['finalCost'] ?? ''}'
            .trim();
        final mergedData = <String, dynamic>{
          if (raw != null) ...raw,
          if (dataMap != null) ...dataMap,
          if (hadMeter) ...{
            'distanceTraveledKm': meterKmSnap,
            'billedWaitingMinutes': meterWaitSnap,
            'meterElapsedSeconds': meterElapsedSnap,
            'finalCost': meterCostSnap.round(),
          },
        };
        await TripCompletionScreen.show(
          summary: buildTripCompletionMessage(
            tripRow: tripSnap,
            apiData: mergedData.isEmpty ? dataMap ?? raw : mergedData,
            apiFinalCost: apiCost,
            meterFinalCost: hadMeter ? meterCostSnap : null,
          ),
          requestIdLabel: 'طلب #$requestId',
          paymentRequestId:
              '${raw?['billing_kind'] ?? ''}' == 'free_meter' ? null : requestId,
          paymentRole: TripPaymentRole.driver,
        );
        await _refreshAssignedAfterAction();
      } else {
        AppSnackBar.notify('فشل', r.message ?? 'تعذر الإنهاء');
      }
    } catch (e) {
      AppSnackBar.notify('خطأ', '$e');
    }
  }

  void maybePromptProximityArrival(LatLng driverPos) {
    final r = assignedRequest.value;
    if (r == null) return;
    if (!TripLocationHelpers.shouldPromptProximityForOrder(r)) return;
    if (r['status']?.toString() != 'Reserved') return;
    final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
    if (id <= 0) return;
    final pickup = TripLocationHelpers.extractLocation(r, 'startLocation');
    if (pickup == null) return;
    final meters = _geoDist.as(LengthUnit.Meter, driverPos, pickup);
    if (meters > 130) return;
    if (proximityArrivalDialogShownForRequestId == id) return;
    proximityArrivalDialogShownForRequestId = id;
    if (Get.isDialogOpen == true) return;
    Get.dialog(
      AlertDialog(
        title: const Text('هل وصلت للراكب؟'),
        content: Text(
          meters < 40
              ? 'أنت على مسافة قريبة جداً من موقع الراكب.\nهل وصلت إليه الآن؟'
              : 'أنت قريب من موقع الراكب.\nهل وصلت إليه؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('ليس بعد'),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              markArrived(id);
            },
            child: const Text('نعم، وصلت'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  void setManualDestination(LatLng ll, String label) {
    if (!isFiniteLatLng(ll)) return;
    destination.value = ll;
    destinationLabel.value = label;
    scheduleRouteFetch(force: true);
    onMapFocus?.call(DriverMapFocusEvent.point(ll, zoom: 15, force: true));
  }

  void clearManualDestination() {
    destination.value = null;
    destinationLabel.value = null;
    routePoints.clear();
    routeKm.value = null;
    routeMinutes.value = null;
    _lastRouteFetchKey = '';
    _lastRouteFetchFrom = null;
  }

  Future<void> postScheduledDriverResponse(int requestId, String action) async {
    try {
      final r = await TripApiService.scheduledDriverResponse(requestId, action);
      AppSnackBar.notify(
        r.ok ? 'تم' : 'تنبيه',
        r.ok ? (r.message ?? 'تم') : (r.message ?? 'تعذر الإرسال'),
      );
      if (r.ok) await _refreshAssignedAfterAction();
    } catch (e) {
      AppSnackBar.notify('خطأ', '$e');
    }
  }

  /// «انطلق للراكب» — ينقل الحجز المسبق لمرحلة «في الطريق» مثل الطلب الفوري.
  Future<void> goToScheduledPassenger(int requestId) async {
    if (driver.isTripActive.value) {
      AppSnackBar.notify('تنبيه', 'أوقف العداد الحر أولاً ثم اضغط «انطلق للراكب»');
      return;
    }
    final cur = assignedRequest.value;
    final curId = int.tryParse(cur?['id']?.toString() ?? '') ?? 0;
    if (cur != null && curId != requestId) {
      AppSnackBar.notify('تنبيه', 'أنهِ رحلتك الحالية أولاً ثم اضغط «انطلق للراكب»');
      return;
    }
    await postScheduledDriverResponse(requestId, 'start');
  }

  Future<void> _promptScheduledGo(
    Map<String, dynamic> row,
    int requestId, {
    required String fallbackTitle,
    required String fallbackBody,
  }) async {
    unawaited(AppAlertSound.playNewRequest());
    final title = row['title']?.toString() ?? fallbackTitle;
    final body = row['body']?.toString() ?? fallbackBody;
    final busyElsewhere = driver.isTripActive.value ||
        (assignedRequest.value != null &&
            (int.tryParse(assignedRequest.value?['id']?.toString() ?? '') ??
                    0) !=
                requestId);
    if (busyElsewhere || Get.isDialogOpen == true) {
      AppSnackBar.notify(
        title,
        '$body\nأنهِ رحلتك الحالية ثم اضغط أيقونة الحجز المسبق.',
        duration: const Duration(seconds: 10),
      );
      return;
    }
    final action = await showSchedAtTimeDialog?.call(requestId, title, body);
    if (action == 'start') {
      await goToScheduledPassenger(requestId);
    }
  }

  Future<void> _refreshAssignedAfterAction() async {
    if (Get.isRegistered<DriverServerSyncService>()) {
      await Get.find<DriverServerSyncService>().syncNow(force: true);
    } else {
      await pollAssignedRequests();
    }
  }

  static const Set<String> _silentDriverNotificationKinds = {
    'sched_assigned',
    'sched_no_ready_cancelled',
    'sched_accepted',
  };

  Map<String, dynamic>? _driverNotificationDataMap(Map<String, dynamic> row) {
    final d = row['data'];
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
    if (d is String && d.trim().isNotEmpty) {
      try {
        final j = json.decode(d);
        if (j is Map) return Map<String, dynamic>.from(j);
      } catch (_) {}
    }
    return null;
  }

  int? _driverNotificationRequestId(Map<String, dynamic>? data) {
    if (data == null) return null;
    final v = data['request_id'] ?? data['requestId'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  Future<void> _handleDriverNotificationRow(Map<String, dynamic> row) async {
    final data = _driverNotificationDataMap(row);
    final kind = data?['kind']?.toString() ?? '';
    final rid = _driverNotificationRequestId(data);

    if (_silentDriverNotificationKinds.contains(kind)) return;

    if (kind == 'sched_t30' && rid != null && rid > 0) {
      await _promptScheduledGo(
        row,
        rid,
        fallbackTitle: 'حان وقت الانطلاق للحجز المسبق',
        fallbackBody: 'حجزك المسبق يبدأ خلال نصف ساعة — اضغط «انطلق للراكب».',
      );
      return;
    }

    if (kind == 'sched_at_time' && rid != null && rid > 0) {
      await _promptScheduledGo(
        row,
        rid,
        fallbackTitle: 'حان موعد الحجز المسبق',
        fallbackBody: 'حان موعد الرحلة. اضغط «انطلق للراكب» الآن.',
      );
      return;
    }

    if (kind == 'sched_passenger_ready' && rid != null && rid > 0) {
      if (Get.isDialogOpen == true) return;
      final action = await showPassengerReadyDialog?.call();
      if (action == null) return;
      await postScheduledDriverResponse(
        rid,
        action == 'start' ? 'start' : 'defer',
      );
      return;
    }

    final title = row['title']?.toString() ?? 'إشعار';
    final body = row['body']?.toString() ?? '';
    AppSnackBar.notify(title, body, duration: const Duration(seconds: 6));
  }

  Future<void> pollDriverNotifications() async {
    final box = GetStorage();
    if (box.read('user_roll')?.toString() != 'Driver') return;
    try {
      final n = await TripApiService.driverNotificationsUnreadCount();
      if (n <= 0) return;
      final rows = await TripApiService.fetchDriverNotifications();
      var needsRefresh = false;
      for (final row in rows) {
        final nid = int.tryParse(row['id']?.toString() ?? '') ?? 0;
        if (nid <= 0) continue;
        if (row['read_at'] != null) continue;
        if (_shownDriverNotificationIds.contains(nid)) continue;
        _shownDriverNotificationIds.add(nid);
        await _handleDriverNotificationRow(row);
        await TripApiService.markDriverNotificationRead(nid);
        needsRefresh = true;
      }
      if (needsRefresh) {
        await _refreshAssignedAfterAction();
      }
    } catch (_) {}
  }

  void acceptImmediatePickup(LatLng? pickup) {
    if (pickup == null) return;
    destination.value = pickup;
    destinationLabel.value = 'موقع الراكب (طلب فوري)';
    onMapFocus?.call(DriverMapFocusEvent.point(pickup, zoom: 16));
    scheduleRouteFetch(force: true);
  }
}
