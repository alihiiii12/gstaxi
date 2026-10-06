import 'dart:async';
import '../../core/constants/snack_bar.dart';
import '../../core/constants/app_button_dims.dart';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../Driver/Auth/auth_session.dart';
import '../../core/maps/app_map_controller.dart';
import '../../core/controllers/map_theme_controller.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/http_timeouts.dart';
import '../../core/widgets/sos_countdown_dialog.dart';
import '../../core/services/sos_live_reporter.dart';
import '../../core/utils/utf8_text.dart';
import '../../core/services/account_deletion_service.dart';
import '../../core/services/app_permissions_service.dart';
import '../../core/services/car_types_service.dart';
import '../../core/services/photon_search_service.dart';
import '../../core/services/trip_api_service.dart';
import '../../core/services/customer_presence_reporter.dart';
import '../../core/services/nominatim_reverse_geocode.dart';
import '../../core/utils/category_trip_fare_client.dart';
import '../../core/utils/osrm_route_client.dart';
import '../../core/models/trip_stop.dart';
import '../../core/utils/phone_call_launcher.dart';
import '../../core/utils/request_route_label.dart';
import '../../Driver/Home/view/offline_maps_screen.dart';
import '../../core/widgets/favorite_places_sheet.dart';
import 'customer_nearby_drivers_sheet.dart';
import 'customer_waiting_driver_accept_sheet.dart';
import '../controller/customer_active_trip_controller.dart';
import '../Wallet/customer_wallet_screen.dart';
import '../../core/utils/customer_trip_map_state.dart';
import '../../core/utils/car_category_visual.dart';
import '../../core/utils/customer_trip_status_helpers.dart';
import '../../core/utils/driver_order_display.dart';
import '../../core/utils/trip_request_place_label.dart';
import '../../core/utils/safe_lat_lng.dart';
import '../../core/utils/trip_live_phase_helpers.dart';
import '../../core/utils/trip_location_helpers.dart';
import '../../core/utils/trip_completion_message.dart';
import '../../core/widgets/trip_completion_screen.dart';
import '../../core/theme/app_text_style.dart';
import '../../core/widgets/trip_live_meter_panel.dart';
import 'widgets/customer_active_trip_strip.dart';
import 'widgets/customer_booking_ui.dart';
import 'widgets/customer_ui_theme.dart';
import 'widgets/customer_drawer.dart';
import 'widgets/customer_my_trips_tab.dart';
import 'widgets/customer_request_card.dart';
import 'widgets/customer_request_route_map_dialog.dart';
import 'widgets/customer_action_sheets.dart';
import 'widgets/customer_map_loading_overlay.dart';
import 'widgets/pickup_destination_map_picker.dart';
import '../../core/widgets/gst_booking_ui.dart';

/// نتيجة بحث Google Places.
class _PlaceHit {
  _PlaceHit({required this.displayName, required this.point});

  final String displayName;
  final LatLng point;
}


/// حجوزات الزبون مع خريطة تفاعلية (اختيار الانطلاق والوجهة، خط مسار تقريبي، موقعي).
class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AppMapController _mapController = AppMapController();
  late final ValueNotifier<AppMapOverlay> _mapOverlay;
  late final MapThemeController _mapTheme;
  bool _mapToolsExpanded = false;

  final _destinationSearch = TextEditingController();

  LatLng _pickup = LatLng(33.5138, 36.2765);
  LatLng _dropoff = LatLng(33.5138, 36.2765);
  String _pickupDisplayName = '';
  String _destDisplayName = '';
  /// وجهات مرتّبة (واحدة أو أكثر). الأخيرة = [_dropoff].
  List<TripStop> _destStops = [];
  LatLng? _userGps;
  bool _gpsInitialized = false;
  StreamSubscription<Position>? _gpsStream;

  /// يظهر خطّ الأحمر والوجهة فقط بعد أن يختار الزبون أين يريد الذهاب.
  bool _hasDestination = false;

  /// عند التفعيل لا يُستبدل [_pickup] بموقع GPS — نقطة الانطلاق التي يحددها الزبون للسائق.
  bool _pickupLockedToCustom = false;

  /// طلب فوري نشط قبل بدء الرحلة: نقطة الالتقاء تتبع موقع الراكب ويُبلَّغ السيرفر.
  int? _pickupFollowDecidedFor;
  bool _pickupFollowAllowed = false;
  LatLng? _lastSyncedPickup;
  DateTime? _lastPickupSyncAt;
  bool _pickupSyncInFlight = false;

  /// جاري حلّ اسم نقطة الانطلاق بعد التأكيد.
  bool _resolvingPickup = false;

  Timer? _searchDebounce;
  Timer? _routeSummaryDebounce;
  double? _routeKmRoad;
  /// مدة القيادة التقريبية من OSRM (دقائق)، إن وُجدت.
  double? _routeMinutesRoad;
  /// نقاط مسار الطريق من الخادم (GeoJSON: [lng, lat] لكل نقطة).
  List<LatLng> _routeRoadPoints = [];
  String _lastRouteFetchKey = '';
  int _routeFetchGeneration = 0;
  LatLng? _lastRouteFetchPickup;
  final DraggableScrollableController _bookingSheetController =
      DraggableScrollableController();

  static const Distance _geoDistance = Distance();
  List<_PlaceHit> _placeHits = [];
  bool _searchLoading = false;

  List<Map<String, dynamic>> _carTypes = [];
  /// الفئة المختارة لعرض السعر وتصفية السائقين القريبين وإرسال الطلب.
  int? _selectedCarTypeId;
  DateTime _when = DateTime.now().add(const Duration(hours: 2));
  bool _loadingTypes = false;
  String? _carTypesLoadError;

  List<Map<String, dynamic>> _myRequests = [];
  bool _loadingRequests = false;
  /// طلبات أنهى فيها الزبون إرسال شكوى/تقييم (يُحدَّث من الخادم).
  Set<int> _requestIdsWithComplaint = {};

  final _discountCode = TextEditingController();
  String _discountHint = '';

  /// قاعدة الكوبون (type/amount/max_discount) — الخصم يُحسب دائماً من السعر الحالي للوجهة والفئة.
  Map<String, dynamic>? _discountRule;
  String _discountRuleCode = '';

  Map<String, dynamic>? get _activeDiscountRule =>
      _discountRule != null && _discountCode.text.trim() == _discountRuleCode
          ? _discountRule
          : null;

  double? get _discountSavedAmount {
    final rule = _activeDiscountRule;
    if (rule == null) return null;
    final base = _basePriceForDiscount();
    if (base <= 0) return null;
    final amount = double.tryParse('${rule['amount']}') ?? 0;
    var value = amount;
    if (rule['type']?.toString() == 'Percentage') {
      value = base * amount / 100;
      final cap = double.tryParse('${rule['max_discount']}');
      if (cap != null && cap > 0 && value > cap) value = cap;
    }
    return value.clamp(0, base).toDouble();
  }

  double? get _discountNewPrice {
    final saved = _discountSavedAmount;
    if (saved == null) return null;
    return _basePriceForDiscount() - saved;
  }

  void _applyDiscountRuleFromResponse(Object? data, String code) {
    final rule = data is Map ? data['discount'] : null;
    if (rule is! Map) return;
    _discountRule = Map<String, dynamic>.from(rule);
    _discountRuleCode = code;
    final label = _discountRule!['value_label']?.toString().trim() ?? '';
    _discountHint = label.isNotEmpty
        ? 'تم تفعيل الكوبون — خصم $label'
        : 'تم تفعيل الكوبون';
  }

  /// معامل منطقة التسعير (مدينة ← ريف …) من الخادم لنقطتي الانطلاق والوجهة.
  double _zoneMultiplier = 1.0;
  String _zoneLabel = '';
  String _zoneQuoteKey = '';

  late final CustomerActiveTripController tripCtrl;

  /// بعد أول `onMapReady` يمكن استدعاء `move` بأمان.
  bool _mapReady = false;
  static const double _gpsMapZoom = 15.0;
  bool _didInitialLocate = false;

  /// متابعة الكاميرا خلف سيارة السائق أثناء الرحلة (مثل شاشة السائق).
  bool _followDriverCam = true;
  /// متابعة موقع الراكب عندما لا توجد رحلة نشطة.
  bool _followSelfCam = true;
  double _driverHeadingDeg = 0;
  LatLng? _lastDriverCamPos;
  DateTime? _lastCustNavCamAt;
  /// آخر مسافة معتبرة لحركة السائق (لاستئناف المتابعة).
  bool _driverMovingForFollow = false;
  String? _prevCustomerTripStatus;
  Timer? _mapOverlayDebounce;
  List<LatLng> _lastDrawnRoutePts = const [];

  /// واجهة الحجز جاهزة مباشرة — بدون «اسحب للبدء».
  bool _started = true;
  int _bookingFreshKey = 0;
  /// فوري أو حجز مسبق داخل تبويب الحجز الموحّد.
  bool _bookingScheduled = false;
  bool _searchExpanded = false;
  /// شريط الترحيب يظهر عند الفتح ثم يُستبدل بشريط البحث.
  bool _showWelcomeBanner = true;
  Timer? _welcomeBannerTimer;
  /// نبضة دورية لإعادة تقييم فتح نافذة الحجز المسبق (30 د قبل الموعد).
  final RxInt _schedClock = 0.obs;
  Timer? _schedClockTimer;

  static const Color _navy = Color(0xFF11215B);

  @override
  void initState() {
    super.initState();
    SosLiveReporter.instance.resumeIfActive();
    _schedClockTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _schedClock.value++,
    );
    _mapOverlay = ValueNotifier(AppMapOverlay.empty);
    _mapTheme = Get.put(MapThemeController(), permanent: true);
    final cachedTypes = CarTypesService.readCached();
    if (cachedTypes.isNotEmpty) {
      _carTypes = List<Map<String, dynamic>>.from(cachedTypes);
      CarTypesService.sortInPlace(_carTypes);
      _ensureSelectedCarTypeId();
    }
    WidgetsBinding.instance.addObserver(this);
    _welcomeBannerTimer?.cancel();
    _welcomeBannerTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() => _showWelcomeBanner = false);
    });
    tripCtrl = Get.put(CustomerActiveTripController(), permanent: true);
    tripCtrl.onMapUpdate = _applyTripMapUpdate;
    tripCtrl.onScheduleRouteFetch = () {
      if (_hasDestination) _scheduleDrivingRouteFetch();
    };
    tripCtrl.onTripSurvey = _showTripSurveyDialog;
    tripCtrl.onTripCompleted = _showTripCompletionScreen;
    CustomerPresenceReporter.instance.start();
    tripCtrl.onBookingUiReset = _resetBookingUiToInitialState;
    ever(tripCtrl.activeTrip, (trip) {
      if (!mounted) return;
      setState(() {});
      final st = trip == null
          ? null
          : CustomerTripStatusHelpers.normTripStatus(trip);
      if (st == 'Running' && _prevCustomerTripStatus != 'Running') {
        _followDriverCam = true;
        final pos = tripCtrl.driverLivePos.value;
        if (pos != null) {
          _updateCustomerTripCamera(pos, force: true, tripStarted: true);
        }
      }
      if (st == null) {
        _followDriverCam = true;
        _lastDriverCamPos = null;
        _mapController.setDriverFollow(enabled: false);
      }
      _prevCustomerTripStatus = st;
    });
    ever(tripCtrl.driverLivePos, (pos) {
      if (!mounted) return;
      _scheduleCustomerOverlayRefresh();
      if (pos != null) {
        _onDriverLivePosForCamera(pos);
      } else {
        unawaited(_mapController.clearDriverPose());
      }
    });
    tripCtrl.onReloadMyRequests = _loadMyRequests;
    tripCtrl.showSchedT5ReadyDialog = _showSchedT5ReadyDialog;
    tripCtrl.showSchedDriverBusyDialog = _showSchedDriverBusyDialog;
    tripCtrl.onSchedRejectedRechoose = _onSchedRejectedRechoose;

    _loadCarTypes();
    _destinationSearch.addListener(_onDestinationSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await AppPermissionsService.ensureCorePermissions(forDriver: false);
      if (!mounted) return;
      await _initPickupFromGps();
      await _startLiveGps();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      tripCtrl.onAppResumed();
    }
  }

  Future<void> _startLiveGps() async {
    if (!mounted) return;
    try {
      final ok = await AppPermissionsService.ensureForCustomerLocation();
      if (!ok || !mounted) return;

      _gpsStream?.cancel();
      _gpsStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((pos) {
        if (!mounted) return;
        final ll = LatLng(pos.latitude, pos.longitude);
        unawaited(CustomerPresenceReporter.instance.reportOnce(
          latitude: pos.latitude,
          longitude: pos.longitude,
        ));
        setState(() {
          _userGps = ll;
          // Keep pickup real/live when no active trip in progress
          if (tripCtrl.activeTrip.value == null) {
            if (!_pickupLockedToCustom) {
              _pickup = ll;
              if (!_hasDestination) {
                _dropoff = ll;
              }
            } else if (!_hasDestination) {
              _dropoff = _pickup;
            }
          } else if (_activePickupFollowsGps()) {
            _pickup = ll;
          }
          if (!_gpsInitialized) _gpsInitialized = true;
        });
        _refreshMapOverlay();
        if (tripCtrl.activeTrip.value != null && _activePickupFollowsGps()) {
          unawaited(_maybeSyncActivePickup(ll));
        }

          // متابعة موقع الراكب عند الحركة فقط؛ عند التوقف يمكن التصفح.
          if (_mapReady) {
            final trip = tripCtrl.activeTrip.value;
            final st = trip == null
                ? null
                : CustomerTripStatusHelpers.normTripStatus(trip);
            final trackingDriver = trip != null &&
                (st == 'Running' ||
                    st == 'Reserved' ||
                    st == 'DriverArrived' ||
                    st == 'AwaitingDestination');
            if (!trackingDriver) {
              if (!_didInitialLocate) {
                _goToMyLocationOnOpen(ll, force: true);
              } else if (_followSelfCam) {
                // متابعة الموقع فقط إذا فعّلها المستخدم — لا استئناف تلقائي بعد السحب.
                final speed = pos.speed;
                final moving = speed.isFinite && speed >= 1.0; // ≈ 3.6 كم/س
                if (moving) {
                  _followPassengerSelfCamera(ll);
                }
              }
            }
          }
        if (_hasDestination && _pickupMovedEnoughForRouteRefetch()) {
          _scheduleDrivingRouteFetch();
        }
      });
    } catch (_) {}
  }

  void _ensureSelectedCarTypeId() {
    if (_carTypes.isEmpty) {
      _selectedCarTypeId = null;
      return;
    }
    final ids = _carTypes
        .map((e) => int.tryParse(e['id']?.toString() ?? '') ?? 0)
        .where((id) => id > 0)
        .toSet();
    if (_selectedCarTypeId == null || !ids.contains(_selectedCarTypeId)) {
      _selectedCarTypeId = int.tryParse(_carTypes.first['id']?.toString() ?? '');
    }
  }

  Map<String, dynamic>? _selectedCarTypeMap() {
    if (_carTypes.isEmpty) return null;
    final sid = _selectedCarTypeId;
    if (sid != null) {
      for (final e in _carTypes) {
        if (int.tryParse(e['id']?.toString() ?? '') == sid) {
          return Map<String, dynamic>.from(e);
        }
      }
    }
    return Map<String, dynamic>.from(_carTypes.first);
  }

  int? _resolvedCarTypeId() {
    final m = _selectedCarTypeMap();
    if (m == null) return null;
    return int.tryParse(m['id']?.toString() ?? '');
  }

  /// كيلومترات فعّالة للتعرفة: OSRM إن وُجد، وإلا مجموع المسافات بين المحطات.
  double? _effectiveRouteKmForFare() {
    if (_routeKmRoad != null && _routeKmRoad! > 0) return _routeKmRoad;
    if (!_hasDestination) return null;
    return _straightLineStopsKm();
  }

  /// دقائق فعّالة لتقدير التعرفة عند غياب مدة OSRM (تقريب ~25 كم/س).
  double? _effectiveRouteMinutesForFare() {
    if (_routeMinutesRoad != null && _routeMinutesRoad! > 0) {
      return _routeMinutesRoad;
    }
    final km = _effectiveRouteKmForFare();
    if (km == null || km <= 0) return null;
    return (km / 25.0) * 60.0;
  }

  bool _shouldShowCategoryPickerInBottomSheet() {
    if (!_hasDestination || _effectiveRouteKmForFare() == null) return false;
    final trip = tripCtrl.activeTrip.value;
    if (trip == null) return true;
    final st = CustomerTripStatusHelpers.normTripStatus(trip);
    return st == 'Pending' || st == 'AwaitingDestination';
  }

  /// تقدير تعرفة طلب التطبيق: افتتاحي + (كم × سعر الكيلو) + (دقائق × سعر الدقيقة).
  /// يُشارك مع واجهة السائق عبر [categoryTripFareKmMinutesOnly].
  double? _estimatedFareForTrip(
    Map<String, dynamic> carType,
    double km,
    double? durationMinutes,
  ) {
    final base = categoryTripFareKmMinutesOnly(carType, km, durationMinutes);
    if (base == null || _zoneMultiplier == 1.0) return base;
    return base * _zoneMultiplier;
  }

  /// يطلب معامل المنطقة مرة لكل زوج (انطلاق، وجهة).
  void _ensureZoneQuote() {
    if (!_hasDestination) return;
    final a = _pickup;
    final b = _dropoff;
    final key =
        '${a.latitude.toStringAsFixed(4)},${a.longitude.toStringAsFixed(4)}>'
        '${b.latitude.toStringAsFixed(4)},${b.longitude.toStringAsFixed(4)}';
    if (key == _zoneQuoteKey) return;
    _zoneQuoteKey = key;
    unawaited(_fetchZoneQuote(key, a, b));
  }

  Future<void> _fetchZoneQuote(String key, LatLng a, LatLng b) async {
    try {
      final uri = Uri.parse(ApiEndpoints.pricingZoneQuote).replace(
        queryParameters: {
          'pickup_lat': '${a.latitude}',
          'pickup_lng': '${a.longitude}',
          'dest_lat': '${b.latitude}',
          'dest_lng': '${b.longitude}',
        },
      );
      final res = await http
          .get(uri, headers: await ApiEndpoints.headers())
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        if (_zoneQuoteKey == key) _zoneQuoteKey = '';
        return;
      }
      final map = json.decode(res.body);
      final d = map is Map ? map['data'] : null;
      if (d is! Map) return;
      final m = double.tryParse('${d['multiplier']}') ?? 1.0;
      final label = d['label']?.toString() ?? '';
      if (!mounted || _zoneQuoteKey != key) return;
      if (m == _zoneMultiplier && label == _zoneLabel) return;
      setState(() {
        _zoneMultiplier = m > 0 ? m : 1.0;
        _zoneLabel = label;
      });
    } catch (e) {
      debugPrint('[zone-quote] $e');
      if (_zoneQuoteKey == key) _zoneQuoteKey = '';
    }
  }

  /// سعر أساس لاختبار كوبون الخصم: تقدير من المسار والفئة المختارة.
  double _basePriceForDiscount() {
    final km = _effectiveRouteKmForFare();
    if (km != null && _carTypes.isNotEmpty) {
      final e = _selectedCarTypeMap();
      if (e != null) {
        final est = _estimatedFareForTrip(
          e,
          km,
          _effectiveRouteMinutesForFare(),
        );
        if (est != null && est > 0) return est;
      }
    }
    return 0;
  }

  String _pickupLabelForUi() {
    if (_pickupDisplayName.trim().isNotEmpty) return _pickupDisplayName.trim();
    if (_pickupLockedToCustom) return 'نقطة الانطلاق المحددة';
    return 'موقعك الحالي';
  }

  void _syncDropoffFromStops() {
    if (_destStops.isEmpty) {
      _hasDestination = false;
      _destDisplayName = '';
      _dropoff = _userGps ?? _pickup;
      return;
    }
    _hasDestination = true;
    _dropoff = _destStops.last.point;
    _destDisplayName = TripStop.routeLabel(_destStops);
  }

  List<LatLng> _routeWaypoints() => [
        _pickup,
        ..._destStops.map((s) => s.point),
      ];

  double? _straightLineStopsKm() {
    if (_destStops.isEmpty) return null;
    var total = 0.0;
    var prev = _pickup;
    for (final s in _destStops) {
      total += _geoDistance.as(LengthUnit.Kilometer, prev, s.point);
      prev = s.point;
    }
    return total >= 0.05 ? total : null;
  }

  String? _composePrimaryPriceLabel() {
    if (_discountNewPrice != null && _discountNewPrice! > 0) {
      return '~ ${_discountNewPrice!.round()} ل.س';
    }
    final km = _effectiveRouteKmForFare();
    if (km == null) return null;
    final ct = _selectedCarTypeMap();
    if (ct == null) return null;
    final fare = _estimatedFareForTrip(ct, km, _effectiveRouteMinutesForFare());
    if (fare == null || fare <= 0) return null;
    return '~ ${fare.round()} ل.س';
  }

  void _openSearchOverlay() {
    setState(() {
      _showWelcomeBanner = false;
      _searchExpanded = true;
    });
  }

  void _closeSearchOverlay() {
    FocusScope.of(context).unfocus();
    setState(() {
      _searchExpanded = false;
      _placeHits = [];
    });
  }


  void _applyTripMapUpdate(CustomerTripMapUpdate u) {
    if (!mounted) return;
    setState(() {
      // نقطة الالتقاء تتبع GPS محلياً — لا نرجعها لقيمة السيرفر الأقدم.
      if (u.pickup != null && !(_userGps != null && _activePickupFollowsGps())) {
        _pickup = u.pickup!;
      }
      if (u.dropoff != null) {
        _dropoff = u.dropoff!;
        if (u.hasDestination == true && _destStops.isEmpty) {
          _destStops = [
            TripStop(
              point: u.dropoff!,
              label: _destDisplayName.trim().isEmpty
                  ? 'وجهة'
                  : _destDisplayName.trim(),
            ),
          ];
          _syncDropoffFromStops();
        }
      }
      if (u.hasDestination != null) {
        _hasDestination = u.hasDestination!;
        if (!u.hasDestination!) {
          _destStops = [];
          _destDisplayName = '';
        }
      }
      if (u.started != null) _started = true;
    });
    _refreshMapOverlay();
  }

  void _onDriverLivePosForCamera(LatLng pos) {
    final prev = _lastDriverCamPos;
    var movedMeters = 0.0;
    if (prev != null) {
      movedMeters = _geoDistance.as(LengthUnit.Meter, prev, pos);
      if (movedMeters >= 5) {
        final brg = _geoDistance.bearing(prev, pos);
        if (brg.isFinite) _driverHeadingDeg = brg;
        _lastDriverCamPos = pos;
      }
    } else {
      _lastDriverCamPos = pos;
    }
    _driverMovingForFollow = movedMeters >= 8;

    final trip = tripCtrl.activeTrip.value;
    if (trip == null) return;
    final st = CustomerTripStatusHelpers.normTripStatus(trip);
    final tripStarted = st == 'Running';
    final followPhase = tripStarted ||
        st == 'Reserved' ||
        st == 'DriverArrived';
    if (!followPhase) return;

    // لا استئناف تلقائي بعد التصفح — المتابعة فقط بزر «متابعة السائق».
    if (!_followDriverCam) return;
    if (!_driverMovingForFollow) return;
    _updateCustomerTripCamera(pos, tripStarted: tripStarted);
  }

  DateTime? _lastSelfCamAt;
  void _followPassengerSelfCamera(LatLng pos) {
    if (!_mapReady || !mounted) return;
    if (!pos.latitude.isFinite || !pos.longitude.isFinite) return;
    if (!_followSelfCam) return;
    _mapController.setDriverFollow(enabled: false);
    final now = DateTime.now();
    if (_lastSelfCamAt != null &&
        now.difference(_lastSelfCamAt!) < const Duration(milliseconds: 450)) {
      return;
    }
    _lastSelfCamAt = now;
    unawaited(
      _mapController.setNavigationCamera(
        point: pos,
        bearing: _mapController.currentBearing,
        zoom: _gpsMapZoom,
        tilt: MapStyleConfig.mapDefaultTilt,
        lookAheadMeters: 0,
        animate: true,
        duration: const Duration(milliseconds: 280),
      ),
    );
  }

  void _updateCustomerTripCamera(
    LatLng driverPos, {
    bool force = false,
    bool tripStarted = false,
  }) {
    if (!_mapReady || !mounted) return;
    if (!force && !_followDriverCam) return;
    if (force) _followDriverCam = true;

    final now = DateTime.now();
    if (!force &&
        _lastCustNavCamAt != null &&
        now.difference(_lastCustNavCamAt!) < const Duration(milliseconds: 220)) {
      return;
    }
    _lastCustNavCamAt = now;

    final tilt = tripStarted
        ? MapStyleConfig.navFollowTiltActive
        : MapStyleConfig.navFollowTiltEnRoute;
    final lookAhead = tripStarted
        ? MapStyleConfig.navFollowLookAheadActive
        : MapStyleConfig.navFollowLookAheadEnRoute;
    if (!force) {
      // المتابعة المستمرة: الكاميرا تلحق السيارة المعروضة (المنعَّمة) إطاراً بإطار.
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
        point: driverPos,
        bearing: _driverHeadingDeg,
        zoom: MapStyleConfig.navFollowZoom,
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

  Future<bool?> _showSchedT5ReadyDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('هل أنت جاهز للرحلة؟'),
        content: const Text(
          'اقترب موعد رحلتك. اضغط «نعم» ليصل السائق إشعاراً بأنك جاهز.\n'
          'إن لم ترد خلال 15 دقيقة يُلغى الطلب تلقائياً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ليس الآن'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، جاهز'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showSchedDriverBusyDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('السائق مشغول'),
        content: const Text(
          'السائق غير متاح الآن. يمكنك إلغاء الحجز واختيار سائق آخر،\n'
          'أو الانتظار 15 دقيقة لإعادة التواصل معه.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء الطلب'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('الانتظار'),
          ),
        ],
      ),
    );
  }

  /// بعد رفض السائق للحجز المسبق: اختيار سائق آخر لنفس الطلب والموعد.
  Future<void> _onSchedRejectedRechoose(int requestId) async {
    if (!mounted) return;
    await _loadMyRequests();
    if (!mounted) return;

    Map<String, dynamic>? req;
    for (final r in _myRequests) {
      final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
      if (id == requestId) {
        req = r;
        break;
      }
    }
    req ??= tripCtrl.activeTrip.value;
    if (req == null) {
      AppSnackBar.notify('تنبيه', 'اختر سائقاً من شاشة الطلبات أو أنشئ الحجز مجدداً');
      return;
    }

    final start = req['start_location'] ?? req['startLocation'];
    final dest = req['dest_location'] ?? req['destLocation'];
    double? pLat;
    double? pLng;
    double? dLat;
    double? dLng;
    if (start is Map) {
      pLat = (start['latitude'] as num?)?.toDouble() ??
          (start['lat'] as num?)?.toDouble();
      pLng = (start['longitude'] as num?)?.toDouble() ??
          (start['lng'] as num?)?.toDouble();
    }
    if (dest is Map) {
      dLat = (dest['latitude'] as num?)?.toDouble() ??
          (dest['lat'] as num?)?.toDouble();
      dLng = (dest['longitude'] as num?)?.toDouble() ??
          (dest['lng'] as num?)?.toDouble();
    }
    pLat ??= _pickup.latitude;
    pLng ??= _pickup.longitude;
    dLat ??= _dropoff.latitude;
    dLng ??= _dropoff.longitude;

    final carTypeId = int.tryParse(
          req['carTypeId']?.toString() ?? req['car_type_id']?.toString() ?? '',
        ) ??
        0;

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختيار سائق آخر'),
        content: const Text(
          'رفض السائق السابق الحجز. هل تريد اختيار سائقاً قريباً ومتاحاً لنفس الموعد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لاحقاً'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('اختيار سائق'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.72,
          child: CustomerNearbyDriversSheet(
            pickupLat: pLat!,
            pickupLng: pLng!,
            destLat: dLat!,
            destLng: dLng!,
            carTypes: List<Map<String, dynamic>>.from(_carTypes),
            initialCarTypeId: carTypeId > 0 ? carTypeId : null,
            estimatedDurationMinutes: _routeMinutesRoad,
            estimatedTripKm: _effectiveRouteKmForFare(),
            dialogTitle: 'اختيار سائق بديل للحجز',
            selectionHint:
                'اختر سائقاً قريباً ومتاحاً. سيُرسل له نفس الحجز بانتظار قبوله.',
            onSendToDriver: (driverId, sendCarTypeId) async {
              try {
                final res = await http.post(
                  Uri.parse(ApiEndpoints.selectDriver(requestId)),
                  headers: await ApiEndpoints.headers(),
                  body: jsonEncode({
                    'driverId': driverId,
                    if (_routeMinutesRoad != null && _routeMinutesRoad! > 0)
                      'estimatedDurationMinutes': _routeMinutesRoad,
                  }),
                );
                final map = json.decode(res.body) as Map<String, dynamic>;
                if (res.statusCode == 200 && map['success'] == true) {
                  AppSnackBar.notify(
                    'تم',
                    map['message']?.toString() ??
                        'تم إرسال الحجز للسائق — بانتظار قبوله',
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadMyRequests();
                  return requestId;
                }
                AppSnackBar.notify(
                  'تعذر الإرسال',
                  map['message']?.toString() ?? res.body,
                );
              } catch (e) {
                AppSnackBar.notify('خطأ', '$e');
              }
              return null;
            },
          ),
        ),
      ),
    );
  }

  Future<void> _resetBookingUiToInitialState() async {
    if (!mounted) return;
    tripCtrl.clearActive();
    _destinationSearch.clear();
    _discountCode.clear();
    _discountHint = '';
    final base = _userGps ?? _pickup;
    setState(() {
      _hasDestination = false;
      _destStops = [];
      _destDisplayName = '';
      _routeRoadPoints = [];
      _routeKmRoad = null;
      _routeMinutesRoad = null;
      _placeHits = [];
      _discountRule = null;
      _discountRuleCode = '';
      _pickupLockedToCustom = false;
      _pickupDisplayName = '';
      _pickup = base;
      _dropoff = base;
      _started = true;
      _bookingFreshKey++;
    });
    _refreshMapOverlay();
    unawaited(_mapController.clearDriverPose());
    if (_mapReady && _userGps != null) {
      try {
        _mapController.rotate(0);
        _mapController.move(_userGps!, _gpsMapZoom, animate: false);
      } catch (_) {}
    }
  }

  Future<void> _openRatingDialog(Map<String, dynamic> trip) =>
      _showTripSurveyDialog(trip);

  Future<void> _showTripCompletionScreen(Map<String, dynamic> trip) async {
    if (!mounted) return;
    final rid = int.tryParse(trip['id']?.toString() ?? '') ?? 0;
    final hist = trip['history'];
    Map<String, dynamic>? histMap;
    if (hist is Map) histMap = Map<String, dynamic>.from(hist);
    final fc = histMap?['finalCost'] ?? histMap?['final_cost'] ?? trip['finalCost'];
    await TripCompletionScreen.show(
      summary: buildTripCompletionMessage(
        tripRow: trip,
        apiFinalCost: fc?.toString(),
      ),
      requestIdLabel: rid > 0 ? 'رحلة #$rid' : null,
      paymentRequestId: rid > 0 ? rid : null,
    );
    // إعادة الواجهة الأولى مباشرة بعد النتيجة (قبل استطلاع الرأي).
    await _resetBookingUiToInitialState();
  }

  Future<void> _showTripSurveyDialog(Map<String, dynamic> trip) async {
    if (!mounted) return;
    final rid = int.tryParse(trip['id']?.toString() ?? '') ?? 0;
    if (rid <= 0) return;

    final did = CustomerTripStatusHelpers.driverIdFromTrip(trip);
    final detailC = TextEditingController();
    var stars = 5;

    const title = 'استطلاع رأي عن الرحلة';
    const subtitle =
        'شاركنا تقييم السائق، والتعليق اختياري. يظهر للإدارة في «رأي الراكبين».';

    try {
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade800)),
                  const SizedBox(height: 14),
                  if (did != null && did > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) {
                        final v = i + 1;
                        return IconButton(
                          icon: Icon(
                            v <= stars ? Icons.star : Icons.star_border,
                            color: Colors.amber.shade700,
                            size: 36,
                          ),
                          onPressed: () => setLocal(() => stars = v),
                        );
                      }),
                    ),
                    Text(
                      'التقييم: $stars من 5',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'لم يُعيَّن سائق لهذا الطلب — يمكنك إرسال ملاحظة للإدارة فقط.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade900),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: detailC,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'رأيك أو ملاحظاتك (اختياري)',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'skip'),
                child: const Text('تخطّي'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, 'send'),
                child: const Text('إرسال'),
              ),
            ],
          ),
        ),
      );
      if (!mounted) {
        detailC.dispose();
        return;
      }
      if (action != 'send') {
        detailC.dispose();
        return;
      }

      final rawComment = detailC.text.trim();
      final prefix = CustomerTripStatusHelpers.completedTripSurveyDetailPrefix();
      final detail = rawComment.isEmpty
          ? '$prefix بدون تعليق إضافي من الراكب.'
          : '$prefix$rawComment';

      if (did == null || did <= 0) {
        AppSnackBar.notify(
          'تنبيه',
          'لا يمكن حفظ تقييم رقمي بدون سائق مرتبط. يمكنك الإبلاغ للإدارة عبر القنوات المعتادة.',
        );
        return;
      }

      final out = await TripApiService.storeComplaint(
        requestId: rid,
        driverId: did,
        detail: detail,
        rating: stars,
      );
      if (out.ok) {
        AppSnackBar.notify('شكراً لك', 'تم حفظ رأيك لدى الإدارة');
        await _loadMyRequests();
      } else {
        AppSnackBar.notify(
          'تعذر الإرسال',
          out.message ?? 'تعذر الإرسال',
        );
      }
    } catch (e) {
      if (mounted) AppSnackBar.notify('خطأ', '$e');
    } finally {
      detailC.dispose();
    }
  }

  Future<void> _validateDiscountCode() async {
    final code = _discountCode.text.trim();
    if (code.isEmpty) {
      AppSnackBar.notify('تنبيه', 'أدخل كود الخصم');
      return;
    }
    final box = GetStorage();
    final uid = box.read('user_id');
    final userId = uid is int ? uid : int.tryParse('$uid');
    if (userId == null) {
      AppSnackBar.notify('تنبيه', 'تعذر تحديد المستخدم');
      return;
    }
    final base = _basePriceForDiscount();
    if (base <= 0) {
      AppSnackBar.notify(
        'تنبيه',
        'حدّد وجهة الرحلة على الخريطة ليُحسب التقدير ويُفعَّل التحقق من الكوبون.',
      );
      return;
    }
    try {
      final res = await http.post(
        Uri.parse(ApiEndpoints.discountValidate),
        headers: await ApiEndpoints.headers(),
        body: jsonEncode({
          'code': code,
          'userId': userId,
          'originalPrice': base,
        }),
      );
      final map = json.decode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && map['success'] == true) {
        setState(() => _applyDiscountRuleFromResponse(map['data'], code));
        AppSnackBar.notify(
          'تم',
          map['message']?.toString() ?? 'تم الخصم بنجاح باستخدام الكوبون',
        );
        if (mounted) Navigator.of(context).maybePop();
      } else {
        AppSnackBar.notify('فشل', map['message']?.toString() ?? 'تعذر التحقق من الكوبون');
      }
    } catch (e) {
      AppSnackBar.notify('خطأ', '$e');
    }
  }

  Future<void> _callDriver(String raw) => launchPhoneCall(raw);

  void _scheduleCustomerOverlayRefresh() {
    _mapOverlayDebounce?.cancel();
    _mapOverlayDebounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) _refreshMapOverlay();
    });
  }

  void _refreshMapOverlay() {
    _mapOverlay.value = AppMapOverlay(
      markers: _buildMapMarkers(),
      polylines: _buildMapPolylines(),
    );
  }

  bool _pickupMovedEnoughForRouteRefetch() {
    final last = _lastRouteFetchPickup;
    if (last == null) return true;
    return _geoDistance.as(LengthUnit.Meter, _pickup, last) > 60;
  }

  /// طلب فوري (بانتظار/بالطريق/وصل) بنقطة انطلاق = موقع الراكب: تتبع GPS.
  /// نقطة اختارها الراكب يدوياً أو بعيدة عن موقعه (طلب لشخص آخر) تبقى ثابتة.
  bool _activePickupFollowsGps() {
    final trip = tripCtrl.activeTrip.value;
    if (trip == null || _pickupLockedToCustom) return false;
    final st = CustomerTripStatusHelpers.normTripStatus(trip);
    if (st != 'Pending' && st != 'Reserved' && st != 'DriverArrived') {
      return false;
    }
    if ((trip['type']?.toString() ?? '') != 'Immediate') return false;
    final id = int.tryParse(trip['id']?.toString() ?? '') ?? 0;
    if (id <= 0) return false;
    if (_pickupFollowDecidedFor != id) {
      final gps = _userGps;
      final serverPickup =
          TripLocationHelpers.extractLocation(trip, 'startLocation');
      if (gps == null || serverPickup == null) return false;
      _pickupFollowDecidedFor = id;
      _pickupFollowAllowed =
          _geoDistance.as(LengthUnit.Meter, serverPickup, gps) <= 150;
      _lastSyncedPickup = serverPickup;
    }
    return _pickupFollowAllowed;
  }

  Future<void> _maybeSyncActivePickup(LatLng ll) async {
    final trip = tripCtrl.activeTrip.value;
    final id = int.tryParse(trip?['id']?.toString() ?? '') ?? 0;
    if (id <= 0 || _pickupSyncInFlight) return;
    final last = _lastSyncedPickup;
    if (last != null && _geoDistance.as(LengthUnit.Meter, last, ll) < 25) {
      return;
    }
    final now = DateTime.now();
    if (_lastPickupSyncAt != null &&
        now.difference(_lastPickupSyncAt!) < const Duration(seconds: 8)) {
      return;
    }
    _pickupSyncInFlight = true;
    _lastPickupSyncAt = now;
    try {
      final res = await http
          .post(
            Uri.parse(ApiEndpoints.updatePickup(id)),
            headers: await ApiEndpoints.headers(),
            body: jsonEncode(<String, dynamic>{
              'latitude': ll.latitude,
              'longitude': ll.longitude,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        _lastSyncedPickup = ll;
      } else if (res.statusCode == 400) {
        // الحالة تغيّرت (بدأت الرحلة مثلاً) — توقف عن المتابعة لهذا الطلب.
        _pickupFollowAllowed = false;
      }
    } catch (_) {
    } finally {
      _pickupSyncInFlight = false;
    }
  }

  void _expandBookingSheet([double size = 0.56]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_bookingSheetController.isAttached) return;
      try {
        _bookingSheetController.animateTo(
          size,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      } catch (_) {}
    });
  }

  void _scheduleDrivingRouteFetch() {
    _routeSummaryDebounce?.cancel();
    if (!_hasDestination) {
      setState(() {
        _routeKmRoad = null;
        _routeMinutesRoad = null;
        _routeRoadPoints = [];
      });
      _refreshMapOverlay();
      return;
    }
    _routeSummaryDebounce =
        Timer(const Duration(milliseconds: 350), _fetchDrivingRoute);
  }

  Future<({double? km, double? mins, List<LatLng> points})?> _fetchServerRouteSummary() async {
    // المحطات الوسيطة بالترتيب — المسافة والزمن لكامل الرحلة لا لآخر وجهة فقط.
    final middle = _destStops.length > 1
        ? _destStops.sublist(0, _destStops.length - 1)
        : const <TripStop>[];
    final body = jsonEncode({
      'from_lat': _pickup.latitude,
      'from_lng': _pickup.longitude,
      'to_lat': _dropoff.latitude,
      'to_lng': _dropoff.longitude,
      if (middle.isNotEmpty)
        'waypoints': [
          for (final s in middle)
            {'lat': s.point.latitude, 'lng': s.point.longitude},
        ],
    });
    final res = await http.post(
      Uri.parse(ApiEndpoints.drivingSummary),
      headers: await ApiEndpoints.headers(),
      body: body,
    );
    final map = json.decode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || map['success'] != true) return null;
    final d = map['data'];
    if (d is! Map<String, dynamic>) return null;
    return (
      km: (d['distance_km'] as num?)?.toDouble(),
      mins: (d['duration_minutes'] as num?)?.toDouble(),
      points: OsrmRouteClient.parseRoutePointsGeoJson(d['route_points']),
    );
  }

  Future<void> _fetchDrivingRoute() async {
    if (!_hasDestination || !mounted) return;

    final key = _routeWaypoints()
        .map(
          (p) =>
              '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}',
        )
        .join('|');
    if (key == _lastRouteFetchKey && _routeRoadPoints.length >= 2) return;

    final gen = ++_routeFetchGeneration;
    _lastRouteFetchPickup = _pickup;

    final route = await OsrmRouteClient.fetchRouteThrough(_routeWaypoints());
    if (!mounted || gen != _routeFetchGeneration) return;

    if (route != null && route.points.length >= 2) {
      _lastRouteFetchKey = key;
      _routeRoadPoints = route.points;
      if (route.distanceKm != null && route.distanceKm! > 0) {
        _routeKmRoad = double.parse(route.distanceKm!.toStringAsFixed(2));
      }
      if (route.durationMinutes != null && route.durationMinutes! > 0) {
        _routeMinutesRoad =
            double.parse(route.durationMinutes!.toStringAsFixed(1));
      }
      _refreshMapOverlay();
      setState(() {});
      // أثناء متابعة السائق لا نستخدم fitPoints حتى لا يلغي الزوم خلف السيارة.
      final active = tripCtrl.activeTrip.value;
      final st = active == null
          ? null
          : CustomerTripStatusHelpers.normTripStatus(active);
      final followingTrip = _followDriverCam &&
          (st == 'Running' ||
              st == 'Reserved' ||
              st == 'DriverArrived' ||
              st == 'AwaitingDestination');
      // لا تُرجع الكاميرا بـ fitPoints إذا كان المستخدم يتصفح يدوياً.
      if (_mapReady && !followingTrip && _followSelfCam) {
        unawaited(
          _mapController.fitPoints(route.points, padding: 56, animate: true),
        );
      }
      if (followingTrip && tripCtrl.driverLivePos.value != null) {
        _updateCustomerTripCamera(
          tripCtrl.driverLivePos.value!,
          force: true,
          tripStarted: st == 'Running',
        );
      }
    }

    unawaited(_applyServerRouteSummary(gen));
  }

  Future<void> _applyServerRouteSummary(int gen) async {
    try {
      final server = await _fetchServerRouteSummary().timeout(
        const Duration(seconds: 3),
      );
      if (!mounted || gen != _routeFetchGeneration || server == null) return;
      setState(() {
        if (server.km != null && server.km! > 0) _routeKmRoad = server.km;
        if (server.mins != null && server.mins! > 0) {
          _routeMinutesRoad = server.mins;
        }
      });
    } catch (_) {}
  }

  void _onDestinationSearchChanged() {
    final q = _destinationSearch.text.trim();
    _searchDebounce?.cancel();
    if (q.length < 2) {
      setState(() {
        _placeHits = [];
        _searchLoading = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _fetchPlaces(q);
    });
  }

  /// نقطة المرجع لترتيب نتائج البحث (الموقع الحالي إن وُجد، وإلا نقطة الانطلاق).
  LatLng get _referencePointForSearch => _userGps ?? _pickup;

  Future<void> _fetchPlaces(String query) async {
    setState(() => _searchLoading = true);
    try {
      final hits = await PhotonSearchService.search(
        query,
        near: _referencePointForSearch,
        limit: 10,
      );
      if (!mounted) return;
      setState(() {
        _placeHits = hits
            .map(
              (h) => _PlaceHit(
                displayName: h.subtitle.isEmpty
                    ? h.name
                    : '${h.name} — ${h.subtitle}',
                point: h.point,
              ),
            )
            .toList();
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

  /// تمركز الخريطة على موقعي عند فتح التطبيق (مرة واحدة).
  void _goToMyLocationOnOpen(LatLng ll, {bool force = false}) {
    if (!_mapReady || !mounted) return;
    if (_didInitialLocate && !force) return;
    if (!isFiniteLatLng(ll)) return;
    final isDefault =
        (ll.latitude - kDefaultMapCenter.latitude).abs() < 1e-6 &&
            (ll.longitude - kDefaultMapCenter.longitude).abs() < 1e-6;
    if (isDefault) return;

    _didInitialLocate = true;
    unawaited(
      _mapController.setNavigationCamera(
        point: ll,
        bearing: 0,
        zoom: MapStyleConfig.mapDefaultZoom,
        tilt: MapStyleConfig.mapDefaultTilt,
        lookAheadMeters: 0,
        animate: true,
      ),
    );
  }

  /// يمرّر الخريطة على نقطة بعد أن يكون الـ [MapController] جاهزاً (إطاران).
  void _ensureMapShows(LatLng ll) {
    void once() {
      if (!mounted) return;
      try {
        _mapController.move(ll, _gpsMapZoom);
      } catch (_) {}
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      once();
      WidgetsBinding.instance.addPostFrameCallback((_) => once());
    });
  }

  Future<void> _initPickupFromGps() async {
    if (_gpsInitialized || !mounted) return;
    try {
      final ok = await AppPermissionsService.ensureForCustomerLocation();
      if (!ok) {
        if (mounted) setState(() => _gpsInitialized = true);
        return;
      }

      void applyFromGps(LatLng ll, {required bool done}) {
        if (!mounted) return;
        setState(() {
          _userGps = ll;
          // أثناء رحلة نشطة تأتي الانطلاق/الوجهة من الخادم — لا تعُد إلى «بدون وجهة» بعد جلب GPS.
          if (tripCtrl.activeTrip.value == null) {
            if (!_pickupLockedToCustom) {
              _pickup = ll;
              _dropoff = ll;
              _hasDestination = false;
            }
          }
          if (done) _gpsInitialized = true;
        });
        if (_mapReady && !_pickupLockedToCustom) {
          _goToMyLocationOnOpen(ll);
        }
        if (!_pickupLockedToCustom) {
          _ensureMapShows(ll);
        }
      }

      // موقع مخزّن سابقاً يظهر فوراً دون انتظار تحديد GPS الحالي
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        applyFromGps(LatLng(last.latitude, last.longitude), done: false);
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final ll = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      applyFromGps(ll, done: true);
      if (_hasDestination) {
        _scheduleDrivingRouteFetch();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _gpsInitialized = true);
        if (_userGps != null) _ensureMapShows(_userGps!);
      }
    }
  }

  void _applyDestinationHit(_PlaceHit hit) {
    FocusScope.of(context).unfocus();
    _destinationSearch.clear();
    final label = hit.displayName.split(',').first.trim();
    setState(() {
      _destStops = [
        ..._destStops,
        TripStop(point: hit.point, label: label.isEmpty ? 'وجهة' : label),
      ];
      _syncDropoffFromStops();
      _placeHits = [];
      // يبقى البحث مفتوحاً لإضافة وجهة أخرى؛ الإغلاق عبر «متابعة».
      _routeRoadPoints = [];
      _routeKmRoad = null;
      _routeMinutesRoad = null;
      _lastRouteFetchKey = '';
    });
    _refreshMapOverlay();
    if (_mapReady) {
      unawaited(
        _mapController.fitPoints(
          _routeWaypoints(),
          padding: 72,
          animate: false,
        ),
      );
    }
    if (_carTypes.isEmpty) _loadCarTypes(force: true);
    _fetchDrivingRoute();
    HapticFeedback.mediumImpact();
  }

  void _removeDestStopAt(int index) {
    if (index < 0 || index >= _destStops.length) return;
    setState(() {
      _destStops = List<TripStop>.from(_destStops)..removeAt(index);
      _syncDropoffFromStops();
      _routeRoadPoints = [];
      _routeKmRoad = null;
      _routeMinutesRoad = null;
      _lastRouteFetchKey = '';
      _lastDrawnRoutePts = const [];
    });
    _refreshMapOverlay();
    if (_hasDestination) {
      _scheduleDrivingRouteFetch();
    }
  }

  Future<void> _clearCustomPickup() async {
    try {
      LatLng ll = _userGps ?? _pickup;
      if (_userGps == null) {
        final ok = await AppPermissionsService.ensureForCustomerLocation();
        if (ok) {
          final pos = await Geolocator.getCurrentPosition();
          ll = LatLng(pos.latitude, pos.longitude);
        }
      }
      if (!mounted) return;
      setState(() {
        _pickupLockedToCustom = false;
        _pickupDisplayName = '';
        _userGps = ll;
        _pickup = ll;
        if (!_hasDestination) {
          _dropoff = ll;
        }
      });
      if (_mapReady) {
        try {
          _followPassengerSelfCamera(ll);
        } catch (_) {}
      }
      _ensureMapShows(ll);
      _scheduleDrivingRouteFetch();
      _refreshMapOverlay();
    } catch (e) {
      AppSnackBar.notify('الموقع', '$e');
    }
  }

  @override
  void dispose() {
    CustomerPresenceReporter.instance.stop();
    _welcomeBannerTimer?.cancel();
    _schedClockTimer?.cancel();
    _mapOverlayDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _mapController.detach();
    _destinationSearch.removeListener(_onDestinationSearchChanged);
    _destinationSearch.dispose();
    _searchDebounce?.cancel();
    _routeSummaryDebounce?.cancel();
    _gpsStream?.cancel();
    _discountCode.dispose();
    _bookingSheetController.dispose();
    _mapOverlay.dispose();
    super.dispose();
  }

  Future<void> _loadCarTypes({bool force = false}) async {
    if (_loadingTypes && !force) return;
    if (!mounted) return;
    setState(() {
      _loadingTypes = true;
      _carTypesLoadError = null;
    });
    try {
      final list = await CarTypesService.fetchWithCacheFirst();
      if (!mounted) return;
      CarTypesService.sortInPlace(list);
      setState(() {
        _carTypes = list;
        _carTypesLoadError = null;
        _ensureSelectedCarTypeId();
      });
    } on CarTypesLoadException catch (e) {
      if (!mounted) return;
      setState(() {
        if (_carTypes.isEmpty) _carTypesLoadError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_carTypes.isEmpty) {
          _carTypesLoadError = 'تحقق من الاتصال (${ApiEndpoints.baseUrl})';
        }
      });
    } finally {
      if (mounted) setState(() => _loadingTypes = false);
    }
  }


  Future<void> _openPickupAndDestinationOnMap() async {
    FocusScope.of(context).unfocus();
    final initial = _userGps ?? _pickup;
    final picked = await showModalBottomSheet<PickupMapPick?>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final maxH = MediaQuery.sizeOf(ctx).height * 0.92;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: maxH,
                width: double.infinity,
                child: PickupDestinationMapPicker(
                  initialCenter: initial,
                  seedPickup: _pickupLockedToCustom ? _pickup : null,
                ),
              ),
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;

    final point = picked.point;
    var pickupLabel = (picked.label ?? '').trim();

    // حدّث الخريطة واللوحة فوراً — لا ننتظر اسم المكان.
    setState(() {
      _pickup = point;
      _pickupLockedToCustom = true;
      if (pickupLabel.isNotEmpty) _pickupDisplayName = pickupLabel;
      _resolvingPickup = pickupLabel.isEmpty;
    });
    _refreshMapOverlay();
    if (_hasDestination) {
      _scheduleDrivingRouteFetch();
      _expandBookingSheet(
        _shouldShowCategoryPickerInBottomSheet() ? 0.56 : 0.48,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _fitRouteOnMap();
        } catch (_) {}
      });
    } else {
      _ensureMapShows(point);
      _expandBookingSheet(0.38);
    }

    if (pickupLabel.isEmpty) {
      try {
        final rev = await NominatimReverseGeocode.displayNameForLatLng(
          point.latitude,
          point.longitude,
        ).timeout(const Duration(seconds: 4));
        if (rev != null && rev.trim().isNotEmpty) {
          pickupLabel = rev.split(',').first.trim();
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        if (pickupLabel.isNotEmpty) _pickupDisplayName = pickupLabel;
        _resolvingPickup = false;
      });
      if (_hasDestination) {
        _expandBookingSheet(
          _shouldShowCategoryPickerInBottomSheet() ? 0.56 : 0.48,
        );
      }
    }

    if (!mounted) return;
    AppSnackBar.notify(
      'الخريطة',
      pickupLabel.isNotEmpty
          ? 'تم تحديد نقطة الانطلاق: $pickupLabel'
          : 'تم تحديد نقطة الانطلاق',
    );
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (!mounted || d == null) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (!mounted || t == null) return;
    setState(() {
      _when = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _centerOnMyLocation() async {
    try {
      final ok = await AppPermissionsService.ensureForCustomerLocation();
      if (!ok) {
        AppSnackBar.notify('الموقع', 'لم يُمنح إذن الوصول للموقع');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _followDriverCam = true;
        _followSelfCam = true;
        _userGps = ll;
        _pickupLockedToCustom = false;
        _pickupDisplayName = '';
        _pickup = ll;
        if (!_hasDestination) {
          _dropoff = ll;
        }
      });
      if (_mapReady) {
        try {
          _followPassengerSelfCamera(ll);
        } catch (_) {}
      }
      _ensureMapShows(ll);
      _scheduleDrivingRouteFetch();
    } catch (e) {
      AppSnackBar.notify('الموقع', '$e');
    }
  }

  void _fitRouteOnMap() {
    // المتابعة تبقى مفعّلة؛ أثناء الرحلة نعيد التمركز خلف السائق.
    _followDriverCam = true;
    final trip = tripCtrl.activeTrip.value;
    final st = trip == null
        ? null
        : CustomerTripStatusHelpers.normTripStatus(trip);
    final trackingDriver = trip != null &&
        (st == 'Running' ||
            st == 'Reserved' ||
            st == 'DriverArrived' ||
            st == 'AwaitingDestination');
    final driver = tripCtrl.driverLivePos.value;
    if (trackingDriver && driver != null) {
      _updateCustomerTripCamera(
        driver,
        force: true,
        tripStarted: st == 'Running',
      );
      return;
    }
    if (!_hasDestination) {
      final me = _userGps ?? _pickup;
      _followPassengerSelfCamera(me);
      AppSnackBar.notify('الخريطة', 'حدّد وجهة الرحلة من البحث أعلاه أولاً');
      return;
    }
    if (_routeRoadPoints.length < 2) {
      _fetchDrivingRoute();
      AppSnackBar.notify('الخريطة', 'جاري حساب المسار…');
      return;
    }
    // خارج الرحلة: عرض المسار ثم المتابعة تستمر من GPS.
    _mapController.fitPoints(_routeRoadPoints, padding: 48, animate: false);
  }

  /// تحديث أسعار الخصم قبل إنشاء الطلب (إن وُجد كود).
  Future<void> _validateDiscountIfNeeded() async {
    final dc = _discountCode.text.trim();
    if (dc.isEmpty) return;
    try {
      final box = GetStorage();
      final uid = box.read('user_id');
      final userId = uid is int ? uid : int.tryParse('$uid');
      final base = _basePriceForDiscount();
      if (userId != null && base > 0) {
        final vr = await http.post(
          Uri.parse(ApiEndpoints.discountValidate),
          headers: await ApiEndpoints.headers(),
          body: jsonEncode({
            'code': dc,
            'userId': userId,
            'originalPrice': base,
          }),
        );
        final vm = json.decode(vr.body) as Map<String, dynamic>;
        if (vr.statusCode == 200 && vm['success'] == true) {
          _applyDiscountRuleFromResponse(vm['data'], dc);
        }
      }
    } catch (_) {}
  }

  Future<void> _ensureLocationNamesForRequest() async {
    if (_pickupDisplayName.trim().isEmpty) {
      final n = await NominatimReverseGeocode.displayNameForLatLng(
        _pickup.latitude,
        _pickup.longitude,
      );
      if (n != null && n.trim().isNotEmpty) {
        _pickupDisplayName = n.split(',').first.trim();
      }
    }
    if (_hasDestination && _destDisplayName.trim().isEmpty) {
      final n = await NominatimReverseGeocode.displayNameForLatLng(
        _dropoff.latitude,
        _dropoff.longitude,
      );
      if (n != null && n.trim().isNotEmpty) {
        _destDisplayName = n.split(',').first.trim();
      }
    }
  }

  void _appendLocationNamesToRequestBody(Map<String, dynamic> body) {
    final pickup = _pickupDisplayName.trim();
    final dest = _destDisplayName.trim();
    if (pickup.isNotEmpty) {
      body['startLocationName'] = pickup;
      if ((body['locationDesc']?.toString().trim() ?? '').isEmpty) {
        body['locationDesc'] = pickup;
      }
    }
    if (dest.isNotEmpty) {
      body['destLocationName'] = dest;
    }
    if (_destStops.isNotEmpty) {
      body['waypoints'] = _destStops.map((s) => s.toJson()).toList();
    }
  }

  /// يُرسل للباك نفس التعرفة الظاهرة على بطاقة الفئة (كم + دقيقة من OSRM).
  void _appendCategoryQuotedFareToBody(
    Map<String, dynamic> body,
    int carTypeId,
  ) {
    final km = _effectiveRouteKmForFare();
    if (km == null || km <= 0) return;
    Map<String, dynamic>? ct;
    for (final e in _carTypes) {
      if ((int.tryParse(e['id']?.toString() ?? '') ?? 0) == carTypeId) {
        ct = Map<String, dynamic>.from(e);
        break;
      }
    }
    if (ct == null) return;
    final fare = _estimatedFareForTrip(ct, km, _effectiveRouteMinutesForFare());
    if (fare == null || fare <= 0) return;
    final rounded = fare.round();
    body['customerQuotedFare'] = rounded;
    // اسم الحقل في Laravel غالباً predectedCost (إملاء المشروع)
    body['predectedCost'] = rounded;
    body['zone_multiplier_applied'] = true;
    body['zone_multiplier'] = _zoneMultiplier;
  }

  /// إنشاء طلب فوري — بث لجميع السائقين القريبين النشطين (بدون اختيار سائق).
  Future<int?> _postBroadcastImmediateRequest({
    required int carTypeId,
    bool quiet = false,
  }) async {
    try {
      await _ensureLocationNamesForRequest();
      final body = <String, dynamic>{
        'carTypeId': carTypeId,
        'type': 'Immediate',
        // بث لكل السائقين القريبين النشطين من نفس الفئة (وليس سائق واحد).
        'broadcast': true,
        'notifyAllNearby': true,
        'assignMode': 'broadcast',
        'startLocationLongitude': _pickup.longitude,
        'startLocationLatitude': _pickup.latitude,
        'locationDesc': _pickupDisplayName,
        'destLocationLongitude': _dropoff.longitude,
        'destLocationLatitude': _dropoff.latitude,
      };
      _appendLocationNamesToRequestBody(body);
      final dc = _discountCode.text.trim();
      if (dc.isNotEmpty) body['discountCode'] = dc;
      final rm = _routeMinutesRoad;
      if (rm != null && rm > 0) body['estimatedDurationMinutes'] = rm;
      final roadKm = _routeKmRoad;
      if (roadKm != null && roadKm > 0) {
        body['estimatedTripKm'] = roadKm;
      }
      _appendCategoryQuotedFareToBody(body, carTypeId);

      final res = await http.post(
        Uri.parse(ApiEndpoints.storeRequest),
        headers: await ApiEndpoints.headers(),
        body: jsonEncode(body),
      );
      final map = json.decode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 201 && map['success'] == true) {
        final dcSn = _discountCode.text.trim();
        final px = _discountNewPrice;
        final saved = _discountSavedAmount;
        if (!quiet && dcSn.isNotEmpty && px != null) {
          final savedPart = saved != null
              ? ' (وفّرت: ${saved.toStringAsFixed(0)} ل.س)'
              : '';
          final msg =
              'تم إرسال الطلب للسائقين القريبين. السعر بعد الخصم: ${px.toStringAsFixed(0)} ل.س$savedPart';
          AppSnackBar.notify('تم', msg);
        } else if (!quiet) {
          AppSnackBar.notify(
            'تم',
            'تم إرسال الطلب لجميع السائقين القريبين النشطين — بانتظار قبول أحدها',
          );
        }
        final raw = map['data'];
        if (raw is Map<String, dynamic>) {
          return int.tryParse(raw['id']?.toString() ?? '');
        }
        return null;
      }
      AppSnackBar.notify('فشل', _storeFailureMessage(map, res.body));
      return null;
    } catch (e) {
      AppSnackBar.notify('خطأ', '$e');
      return null;
    }
  }

  /// حجز مسبق — بث لجميع السائقين القريبين (مثل الفوري).
  Future<int?> _postBroadcastScheduledRequest({
    required int carTypeId,
  }) async {
    try {
      await _ensureLocationNamesForRequest();
      final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
      final body = <String, dynamic>{
        'carTypeId': carTypeId,
        'type': 'Schedual',
        'broadcast': true,
        'startLocationLongitude': _pickup.longitude,
        'startLocationLatitude': _pickup.latitude,
        'locationDesc': _pickupDisplayName,
        'destLocationLongitude': _dropoff.longitude,
        'destLocationLatitude': _dropoff.latitude,
        'requestDate': fmt.format(_when),
      };
      _appendLocationNamesToRequestBody(body);
      final dc = _discountCode.text.trim();
      if (dc.isNotEmpty) body['discountCode'] = dc;
      final rmSched = _routeMinutesRoad;
      if (rmSched != null && rmSched > 0) {
        body['estimatedDurationMinutes'] = rmSched;
      }
      final roadKmSched = _routeKmRoad;
      if (roadKmSched != null && roadKmSched > 0) {
        body['estimatedTripKm'] = roadKmSched;
      }
      _appendCategoryQuotedFareToBody(body, carTypeId);

      final res = await http.post(
        Uri.parse(ApiEndpoints.storeRequest),
        headers: await ApiEndpoints.headers(),
        body: jsonEncode(body),
      );
      final map = json.decode(res.body) as Map<String, dynamic>;
      final httpOk = res.statusCode >= 200 && res.statusCode < 300;
      final apiOk = httpOk && (map['success'] == true || map['state'] == true);
      if (apiOk) {
        AppSnackBar.notify(
          'تم',
          'جاري البحث عن سائق متاح للحجز المسبق — نُرسل رنة لكل السائقين المتصلين من نفس الفئة.',
          duration: const Duration(seconds: 4),
        );
        final raw = map['data'];
        if (raw is Map<String, dynamic>) {
          return int.tryParse(raw['id']?.toString() ?? '');
        }
        return null;
      }
      final err = _storeFailureMessage(map, res.body);
      AppSnackBar.notify('فشل', err, duration: const Duration(seconds: 6));
      return null;
    } catch (e) {
      AppSnackBar.notify('خطأ', '$e');
      return null;
    }
  }

  String _storeFailureMessage(Map<String, dynamic> map, String fallback) {
    final errors = map['errors'];
    if (errors is String && errors.trim().isNotEmpty) return errors.trim();
    if (errors is Map && errors.isNotEmpty) {
      final parts = <String>[];
      for (final v in errors.values) {
        if (v is List) {
          parts.addAll(v.map((e) => e.toString()));
        } else if (v != null) {
          parts.add(v.toString());
        }
      }
      if (parts.isNotEmpty) return parts.join(' — ');
    }
    final msg = map['message']?.toString().trim() ?? '';
    if (msg.isNotEmpty && msg.toLowerCase() != 'failed to validate data') {
      return msg;
    }
    return msg.isNotEmpty ? msg : fallback;
  }

  Future<void> _submit({required bool scheduled}) async {
    final carTypeId = _resolvedCarTypeId();
    if (carTypeId == null) {
      AppSnackBar.notify('تنبيه', 'تعذر تحميل فئات الرحلة. أعد المحاولة لاحقاً.');
      return;
    }
    // خيار A: الفوري أيضاً يتطلب تحديد الوجهة قبل الإرسال
    if (!_hasDestination) {
      AppSnackBar.notify('تنبيه', 'حدّد وجهة الرحلة من البحث أعلاه');
      return;
    }
    final routeMeters =
        _geoDistance.as(LengthUnit.Meter, _pickup, _dropoff);
    if (scheduled && routeMeters < 35) {
      AppSnackBar.notify('تنبيه', 'الوجهة قريبة جداً من موقعك — اختر مكاناً أوضح');
      return;
    }

    await _validateDiscountIfNeeded();
    if (!mounted) return;

    int? rid;

    if (scheduled) {
      // حجز مسبق: بث لكل السائقين الأونلاين (بدون تقييد القرب) + شاشة «جاري البحث».
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إرسال حجز مسبق'),
          content: Text(
            'سيُرسل الحجز المسبق (${DateFormat('yyyy-MM-dd HH:mm').format(_when)}) '
            'إلى جميع السائقين المتصلين من نفس الفئة مع رنة — '
            'حتى لو لم يكونوا قريبين الآن (الموعد قد يكون لاحقاً).\n'
            'أول سائق يقبل يحجز الموعد.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إرسال'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
      rid = await _postBroadcastScheduledRequest(carTypeId: carTypeId);
    } else {
      // فوري: بث مباشر لجميع السائقين القريبين دون اختيار سائق.
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إرسال الطلب'),
          content: const Text(
            'سيُرسل طلبك فوراً إلى جميع السائقين القريبين والنشطين من نفس الفئة.\n'
            'أول سائق يقبل سيتولى رحلتك.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إرسال'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
      rid = await _postBroadcastImmediateRequest(carTypeId: carTypeId);
    }

    if (rid == null || !mounted) return;

    if (scheduled) {
      final wait = await CustomerWaitingDriverAcceptSheet.show(
        context,
        requestId: rid,
        radarTitle: 'جاري البحث عن سائق...',
        radarSubtitle:
            'نبحث عن سائق متاح للحجز المسبق — بدون اشتراط القرب الآن',
      );
      if (!mounted) return;
      if (wait == CustomerImmediateWaitResult.declinedOrCancelled ||
          wait == CustomerImmediateWaitResult.dismissed) {
        if (wait == CustomerImmediateWaitResult.declinedOrCancelled) {
          AppSnackBar.notify(
            'تنبيه',
            'لم يُقبل الحجز أو أُلغي. يمكنك إعادة الإرسال.',
            duration: const Duration(seconds: 9),
          );
        } else {
          AppSnackBar.notify('تم', 'أُلغي البحث والطلب');
        }
        _resetBookingUiToInitialState();
      } else if (wait == CustomerImmediateWaitResult.accepted) {
        AppSnackBar.notify('تم', 'قبل سائق الحجز المسبق');
        await _loadMyRequests();
      }
      await tripCtrl.refreshActiveTrip();
      return;
    }

    if (!scheduled) {
      var currentId = rid;
      var wait = await CustomerWaitingDriverAcceptSheet.show(
        context,
        requestId: currentId,
        searchWithTimeout: true,
      );
      while (mounted && wait == CustomerImmediateWaitResult.retry) {
        final next = await _postBroadcastImmediateRequest(
          carTypeId: carTypeId,
          quiet: true,
        );
        if (next == null || !mounted) {
          wait = null;
          break;
        }
        currentId = next;
        wait = await CustomerWaitingDriverAcceptSheet.show(
          context,
          requestId: currentId,
          searchWithTimeout: true,
        );
      }
      if (!mounted) return;
      if (wait == CustomerImmediateWaitResult.noDriverFound) {
        AppSnackBar.notify(
          'لم نجد سائقاً',
          'لا يوجد سائق متاح قربك الآن — يمكنك إعادة الإرسال بعد قليل.',
          duration: const Duration(seconds: 6),
        );
      } else if (wait == CustomerImmediateWaitResult.declinedOrCancelled ||
          wait == CustomerImmediateWaitResult.dismissed) {
        if (wait == CustomerImmediateWaitResult.declinedOrCancelled) {
          AppSnackBar.notify(
            'تنبيه',
            'لم يُقبل الطلب أو أُلغي. يمكنك إعادة الإرسال.',
            duration: const Duration(seconds: 9),
          );
        } else {
          AppSnackBar.notify('تم', 'أُلغي البحث والطلب');
        }
        _resetBookingUiToInitialState();
      }
    }
    if (scheduled) await _loadMyRequests();
    await tripCtrl.refreshActiveTrip();
  }

  Future<void> _loadMyRequests({bool lightweight = false}) async {
    final box = GetStorage();
    final uid = box.read('user_id');
    final userId = uid is int ? uid : int.tryParse('$uid');
    if (userId == null) {
      AppSnackBar.notify('تنبيه', 'تعذر تحديد المستخدم');
      return;
    }
    setState(() => _loadingRequests = true);
    try {
      _myRequests = await TripApiService.fetchUserRequests(userId);

      final withComplaint = <int>{};
      if (!lightweight) {
        final needComplaintFetch = <int>[];
        for (final r in _myRequests) {
          final rid = int.tryParse(r['id'].toString()) ?? 0;
          if (rid <= 0) continue;
          if (r.containsKey('has_complaint')) {
            final hc = r['has_complaint'];
            if (hc == true || hc == 1) withComplaint.add(rid);
          } else if (r['status']?.toString() == 'Finished') {
            needComplaintFetch.add(rid);
          }
        }
        if (needComplaintFetch.isNotEmpty) {
          await Future.wait(needComplaintFetch.map((rid) async {
            try {
              if (await TripApiService.requestHasComplaint(rid)) {
                withComplaint.add(rid);
              }
            } catch (_) {}
          }));
        }
      } else {
        for (final r in _myRequests) {
          final rid = int.tryParse(r['id'].toString()) ?? 0;
          if (rid <= 0) continue;
          if (r.containsKey('has_complaint')) {
            final hc = r['has_complaint'];
            if (hc == true || hc == 1) withComplaint.add(rid);
          }
        }
        withComplaint.addAll(_requestIdsWithComplaint);
      }
      if (!mounted) return;
      setState(() {
        _requestIdsWithComplaint = withComplaint;
        _loadingRequests = false;
      });
    } catch (_) {}
    if (mounted) {
      setState(() => _loadingRequests = false);
    }
  }

  Future<void> _cancelRequest(Map<String, dynamic> row) async {
    final id = int.tryParse(row['id'].toString()) ?? 0;
    if (id <= 0) return;
    final typ = row['type']?.toString() ?? '';
    final st = CustomerTripStatusHelpers.normTripStatus(row);
    final isSched = typ.toLowerCase().contains('schedual') ||
        typ.toLowerCase().contains('schedule');
    final rd = row['requestDate'] ?? row['request_date'];

    if (isSched && rd != null) {
      try {
        final tripAt = DateTime.parse(rd.toString());
        final until = tripAt.difference(DateTime.now());
        if (tripAt.isAfter(DateTime.now()) &&
            until.inHours < 24 &&
            until.inHours >= 0) {
          final proceed = await CustomerActionSheets.confirm(
            context,
            title: 'سياسة الإلغاء',
            message:
                'يُفضّل إبلاغ الإلغاء قبل 24 ساعة من موعد الرحلة.\nهل تريد المتابعة؟',
            confirmLabel: 'نعم، إلغاء',
            cancelLabel: 'لا',
            destructive: true,
            icon: Icons.schedule_rounded,
          );
          if (proceed != true || !mounted) return;
        }
      } catch (_) {}
    }

    if (!mounted) return;

    String reason = '';
    if (st == 'Pending' && !isSched) {
      final ok = await CustomerActionSheets.confirm(
        context,
        title: 'إلغاء البحث',
        message: 'هل تريد إيقاف البحث عن سائق وإلغاء هذا الطلب؟',
        confirmLabel: 'إلغاء البحث',
        cancelLabel: 'متابعة',
        destructive: true,
        icon: Icons.radar_rounded,
      );
      if (ok != true || !mounted) return;
    } else {
      final prompt = await CustomerActionSheets.cancelWithReason(
        context,
        title: 'إلغاء الطلب',
        message: 'اذكر سبب الإلغاء إن رغبت (اختياري).',
        confirmLabel: 'إلغاء الطلب',
        cancelLabel: 'رجوع',
      );
      if (prompt == null || !prompt.confirmed || !mounted) return;
      reason = prompt.reason;
    }

    if (!mounted) return;
    unawaited(CustomerActionSheets.showBusy(context));

    try {
      var r = await TripApiService.cancelCustomerRequest(id, reason: reason);
      if (!r.ok &&
          (r.statusCode >= 500 || r.statusCode == 408 || r.statusCode == 0)) {
        r = await TripApiService.abortActiveTrip(id, reason: reason);
      }

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(); // busy
      }

      if (r.ok) {
        tripCtrl.clearActive();
        unawaited(_resetBookingUiToInitialState());
        AppSnackBar.notify('تم', 'أُلغي الطلب');
        unawaited(_loadMyRequests(lightweight: true));
        unawaited(tripCtrl.refreshActiveTrip());
      } else {
        AppSnackBar.notify('فشل', r.message ?? 'تعذر الإلغاء');
      }
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      AppSnackBar.notify('خطأ', '$e');
    }
  }

  Future<void> _logout() async {
    await AuthSession.signOut();
  }

  Widget _buildDrawer(BuildContext context) {
    return CustomerDrawer(
      discountController: _discountCode,
      discountHint: _discountHint,
      discountNewPrice: _discountNewPrice,
      discountSavedAmount: _discountSavedAmount,
      onBookRide: () {
        setState(() => _bookingScheduled = false);
      },
      onBookScheduled: () {
        setState(() {
          _bookingScheduled = true;
          if (!_started) _started = true;
        });
      },
      onMyTrips: _openMyTripsPage,
      onWallet: () => Get.to(() => const CustomerWalletScreen()),
      onValidateDiscount: _validateDiscountCode,
      onPrivacyPolicy: AccountDeletionService.openPrivacyPolicy,
      onDeleteAccount: () =>
          AccountDeletionService.confirmAndDeleteAccount(context),
      onLogout: _logout,
    );
  }

  Future<void> _openMyTripsPage() async {
    unawaited(_loadMyRequests());
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              return Scaffold(
                body: Directionality(
                  textDirection: ui.TextDirection.rtl,
                  child: CustomerMyTripsTab(
                    requests: _myRequests,
                    loading: _loadingRequests,
                    requestIdsWithComplaint: _requestIdsWithComplaint,
                    leadingIsBack: true,
                    onRefresh: () async {
                      await _loadMyRequests();
                      setLocal(() {});
                    },
                    onMenuTap: () => Navigator.of(ctx).pop(),
                    cardActions: CustomerRequestCardActions(
                      onTap: _openCustomerRequestRouteMap,
                      onConfirmDriverArrived: tripCtrl.confirmDriverArrived,
                      onSetDestination: _openSetDestinationDialog,
                      onRateTrip: _openRatingDialog,
                      onCancel: _cancelRequest,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  dynamic _requestLocField(Map<String, dynamic> r, bool destination) {
    if (destination) return r['destLocation'] ?? r['dest_location'];
    return r['startLocation'] ?? r['start_location'];
  }

  Future<void> _openCustomerRequestRouteMap(Map<String, dynamic> r) async {
    final start = _requestLocField(r, false);
    final dest = _requestLocField(r, true);
    final pickup = CustomerTripMapUpdate.latLngFromLooseMap(start);
    final destination = CustomerTripMapUpdate.latLngFromLooseMap(dest);
    var pickupLabel =
        areaLabelFromRequestForPoint(r, start, destination: false);
    var destLabel = areaLabelFromRequestForPoint(r, dest, destination: true);
    if (looksLikeMissingPlaceLabel(pickupLabel) && pickup != null) {
      final n = await NominatimReverseGeocode.displayNameForLatLng(
        pickup.latitude,
        pickup.longitude,
      );
      if (n != null && n.isNotEmpty) pickupLabel = n;
    }
    if (looksLikeMissingPlaceLabel(destLabel) && destination != null) {
      final n = await NominatimReverseGeocode.displayNameForLatLng(
        destination.latitude,
        destination.longitude,
      );
      if (n != null && n.isNotEmpty) destLabel = n;
    }
    if (!mounted) return;
    final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
    await showCustomerRequestRouteMapDialog(
      context,
      pickup: pickup,
      destination: destination,
      pickupName: pickupLabel,
      destinationName: destLabel,
      requestId: id > 0 ? id : null,
    );
  }

  List<AppMapMarker> _buildMapMarkers() {
    final markers = <AppMapMarker>[];

    final personPoint = _userGps ?? _pickup;
    final driverPos = tripCtrl.driverLivePos.value;
    final hidePersonUnderTaxi = driverPos != null &&
        _geoDistance.as(LengthUnit.Meter, personPoint, driverPos) < 40;

    // لا تضع دائرة الصفراء تحت سيارة السائق عند القرب.
    if (!hidePersonUnderTaxi) {
      markers.add(AppMapMarker(
        id: 'gps_person',
        point: personPoint,
        kind: AppMapMarkerKind.passenger,
      ));
    }

    final pickupMoved = _userGps != null &&
        _geoDistance.as(LengthUnit.Meter, _pickup, _userGps!) > 40;
    if (pickupMoved || _pickupLockedToCustom) {
      markers.add(AppMapMarker(
        id: 'pickup',
        point: _pickup,
        kind: AppMapMarkerKind.pickup,
      ));
    }

    // دبابيس الوجهات (محطات متعددة).
    if (_hasDestination) {
      for (var i = 0; i < _destStops.length; i++) {
        final isLast = i == _destStops.length - 1;
        markers.add(AppMapMarker(
          id: isLast ? 'dropoff' : 'stop_$i',
          point: _destStops[i].point,
          kind: AppMapMarkerKind.destination,
        ));
      }
    }

    // موقع السائق عبر updateDriverPose فقط — لا يُدرج هنا حتى لا يتكرر.
    final driverPosForPose = tripCtrl.driverLivePos.value;
    if (driverPosForPose != null) {
      unawaited(_mapController.updateDriverPose(
        driverPosForPose,
        _driverHeadingDeg,
        remote: true,
      ));
    } else {
      // انتهت الرحلة / لا تتبع — أزل أيقونة السيارة فوراً.
      unawaited(_mapController.clearDriverPose());
    }

    return markers;
  }

  Widget _buildDestinationSearchPanel() {
    final hint = _hasDestination && _destDisplayName.isNotEmpty
        ? _destDisplayName
        : 'إلى أين تريد الذهاب؟';
    return CustomerBookingSearchBar(
      hint: hint,
      hasDestination: _hasDestination,
      onTap: _openSearchOverlay,
      onClear: _hasDestination ? _clearSelectedDestination : null,
    );
  }

  void _clearSelectedDestination() {
    _destinationSearch.clear();
    setState(() {
      _placeHits = [];
      _destStops = [];
      _syncDropoffFromStops();
      _routeRoadPoints = [];
      _routeKmRoad = null;
      _routeMinutesRoad = null;
      _lastDrawnRoutePts = const [];
      _lastRouteFetchKey = '';
    });
    _refreshMapOverlay();
  }

  void _finishDestinationSearch() {
    FocusScope.of(context).unfocus();
    setState(() {
      _searchExpanded = false;
      _placeHits = [];
    });
    if (_hasDestination) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _expandBookingSheet();
      });
    }
  }

  Widget _buildSearchOverlay() {
    return TripBookingSearchOverlay(
      pickupLabel: _pickupLabelForUi(),
      destinationController: _destinationSearch,
      hasSelectedDestination: _hasDestination,
      hasCustomPickup: _pickupLockedToCustom,
      confirmedStops: _destStops,
      onClose: _closeSearchOverlay,
      onDone: _finishDestinationSearch,
      onSearchSubmitted: (v) => _fetchPlaces(v.trim()),
      onSetOnMap: () {
        _closeSearchOverlay();
        _openPickupAndDestinationOnMap();
      },
      onEditPickup: () {
        _closeSearchOverlay();
        _openPickupAndDestinationOnMap();
      },
      onClearPickup: _clearCustomPickup,
      searchLoading: _searchLoading,
      placeHits: _placeHits
          .map((h) => TripBookingPlaceHit(displayName: h.displayName, point: h.point))
          .toList(),
      onPlaceSelected: (h) {
        final hit = _placeHits.firstWhere(
          (e) => e.displayName == h.displayName,
          orElse: () => _PlaceHit(
            displayName: h.displayName,
            point: h.point as LatLng,
          ),
        );
        _applyDestinationHit(hit);
      },
      onRemoveStop: _removeDestStopAt,
      onClearDestination: _clearSelectedDestination,
    );
  }

  List<AppMapPolyline> _buildMapPolylines() {
    if (!_hasDestination) {
      _lastDrawnRoutePts = const [];
      return const [];
    }
    if (_routeRoadPoints.length >= 2) {
      _lastDrawnRoutePts = List<LatLng>.from(_routeRoadPoints);
    }
    final pts = _routeRoadPoints.length >= 2
        ? List<LatLng>.from(_routeRoadPoints)
        : _lastDrawnRoutePts;
    if (pts.length < 2) return const [];
    return [
      AppMapPolyline(
        id: 'route',
        points: pts,
        color: const Color(MapStyleConfig.routeColor),
        width: 7,
        alpha: 0.95,
        cased: true,
      ),
    ];
  }

  /// محتوى اللوحة السفلى أثناء رحلة نشطة.
  List<Widget> _bookingSheetActiveTripChildren(bool scheduled) {
    final t = tripCtrl.activeTrip.value!;
    final id = int.tryParse(t['id']?.toString() ?? '') ?? 0;
    final st = CustomerTripStatusHelpers.normTripStatus(t);
    final typ = t['type']?.toString() ?? '';

    if (st == 'Pending' && !typ.toLowerCase().contains('schedual') &&
        !typ.toLowerCase().contains('schedule')) {
      // رادار البحث يظهر فقط بعد إرسال الطلب (push). هنا لوحة انتظار خفيفة.
      return [
        TripBookingWaitingPanel(
          title: 'بانتظار قبول السائق',
          subtitle: 'طلب #$id — يمكنك المتابعة من هنا أو إلغاء الانتظار.',
          onCancel: _canCancel(st) ? () => _cancelRequest(t) : null,
          cancelLabel: 'إلغاء الطلب',
        ),
      ];
    }

    final isSched = typ.toLowerCase().contains('schedual') ||
        typ.toLowerCase().contains('schedule');
    final hint = switch (st) {
      'Pending' => isSched
          ? 'تم تسجيل الحجز المسبق. تابع الحالة من «طلباتي».'
          : 'بانتظار قبول السائق.',
      'Reserved' => 'السائق في الطريق إليك.',
      'DriverArrived' => 'وصل السائق — بانتظار صعودك وبدء الرحلة.',
      'AwaitingDestination' => 'بانتظار تحديد الوجهة.',
      'Running' => 'الرحلة جارية — يمكنك متابعة التكلفة أدناه.',
      _ => 'تفاصيل الطلب أدناه.',
    };

    final showCancel = _canCancel(st);

    return [
      const CustomerBookingSheetHandle(),
      CustomerActiveTripStrip(
        trip: t,
        onCallDriver: _callDriver,
      ),
      if (st == 'Running')
        Obx(
          () => Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: TripLiveMeterPanel(
              meter: tripCtrl.liveTripMeter.value,
              compact: true,
              title: 'التكلفة الحالية',
            ),
          ),
        )
      else ...[
        Builder(
          builder: (context) {
            final est = requestCategoryFareLirasRounded(t);
            if (est == null || est <= 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(
                'التكلفة التقديرية: $est ل.س',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: TripBookingTheme.navy,
                  fontSize: 14,
                ),
              ),
            );
          },
        ),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          hint,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey.shade800,
            height: 1.4,
            fontSize: 13,
          ),
        ),
      ),
      if (_shouldShowCategoryPickerInBottomSheet()) ...[
        _buildExpectedTripAndCategoryPanel(),
        const SizedBox(height: 8),
      ],
      if (st == 'AwaitingDestination' && _hasDestination && id > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CustomerBookingPrimaryButton(
            label: 'تأكيد الوجهة',
            onPressed: () => _setDestinationForTrip(id, _dropoff),
          ),
        ),
      if (showCancel)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => _cancelRequest(t),
              icon: const Icon(Icons.cancel_outlined, size: 20),
              label: const Text(
                'إلغاء الطلب',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15.5,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB91C1C),
                backgroundColor: const Color(0xFFFEF2F2),
                side: const BorderSide(color: Color(0xFFFECACA), width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  List<Widget> _bookingSheetComposeChildren(bool scheduled) {
    final priceLabel = _composePrimaryPriceLabel();
    return [
      const CustomerBookingSheetHandle(),
      // بعد تحديد الوجهة: زر الإرسال فوق الفئات، وبدون زري الطلب السفليين.
      if (_hasDestination) ...[
        CustomerBookingPrimaryButton(
          label: 'إرسال الطلب',
          priceLabel: priceLabel,
          enabled: true,
          onPressed: () => _submit(scheduled: scheduled),
        ),
        const SizedBox(height: 12),
      ],
      if (_shouldShowCategoryPickerInBottomSheet()) ...[
        _buildCategoryPickerRow(),
        const SizedBox(height: 12),
      ],
      if (_hasDestination) ...[
        TripBookingAddressCard(
          pickupLabel: _pickupLabelForUi(),
          destinationLabel: _destDisplayName,
          destinationStops: _destStops.map((s) => s.label).toList(),
          onEditPickup: _openPickupAndDestinationOnMap,
          onEditDestination: _openSearchOverlay,
        ),
        const SizedBox(height: 12),
      ],
      if (_shouldShowCategoryPickerInBottomSheet()) ...[
        _buildExpectedTripSummary(),
        const SizedBox(height: 12),
      ],
      if (_hasDestination && scheduled) ...[
        GestureDetector(
          onTap: _pickDateTime,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: CustomerUiTheme.sheetBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: CustomerUiTheme.navy.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_month_rounded,
                  size: 20,
                  color: CustomerUiTheme.navy.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    DateFormat('yyyy-MM-dd HH:mm').format(_when),
                    style: const TextStyle(
                      color: CustomerUiTheme.navy,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                Icon(
                  Icons.edit_calendar_outlined,
                  size: 18,
                  color: CustomerUiTheme.navy.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (_hasDestination) ...[
        TextField(
          controller: _discountCode,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'كود الخصم (اختياري)',
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.verified_outlined, size: 20),
              onPressed: _validateDiscountCode,
            ),
          ),
        ),
        if (_discountHint.isNotEmpty && _activeDiscountRule != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _discountNewPrice != null
                  ? '$_discountHint — السعر بعد الخصم: ${_discountNewPrice!.round()} ل.س'
                  : _discountHint,
              style: TextStyle(fontSize: 12, color: Colors.green.shade800),
            ),
          ),
        const SizedBox(height: 10),
      ],
      if (!_pickupLockedToCustom && _hasDestination)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit_location_alt_outlined, size: 20),
            label: const Text('تحديد نقطة الانطلاق على الخريطة'),
            style: OutlinedButton.styleFrom(
              foregroundColor: TripBookingTheme.navy,
              side: BorderSide(color: TripBookingTheme.navy.withValues(alpha: 0.35)),
              minimumSize: Size(double.infinity, AppButtonDims.heightSm),
            ),
            onPressed: _openPickupAndDestinationOnMap,
          ),
        ),
      // قبل تحديد الوجهة فقط: اختيار فوري / مسبق بدون فتح صفحة البحث.
      if (!_hasDestination)
        CustomerBookingSegment(
          scheduled: scheduled,
          immediateLabel: 'طلب فوري',
          scheduledLabel: 'طلب مسبق',
          onImmediate: () => setState(() => _bookingScheduled = false),
          onScheduled: () async {
            setState(() => _bookingScheduled = true);
            await _pickDateTime();
          },
          scheduleSubtitle: scheduled
              ? DateFormat('dd/MM HH:mm').format(_when)
              : 'طلب مسبق',
          onPickSchedule: null,
        ),
    ];
  }

  bool _customerInLiveTripPhase() =>
      customerInLiveTripPhase(tripCtrl.activeTrip.value);

  double _customerTripSheetInitialSize({
    required bool active,
    required bool liveTrip,
  }) {
    if (liveTrip) return 0.16;
    if (active) {
      final t = tripCtrl.activeTrip.value;
      if (t != null &&
          _shouldShowCategoryPickerInBottomSheet()) {
        return 0.42;
      }
      return 0.24;
    }
    if (_shouldShowCategoryPickerInBottomSheet()) return 0.56;
    // بدون شريط الوجهة السفلي: يكفي مقبض + زرّا الطلب.
    return _hasDestination ? 0.34 : 0.20;
  }

  double _customerTripSheetMinSize({
    required bool active,
    required bool liveTrip,
  }) {
    if (liveTrip) return 0.11;
    if (active) return 0.16;
    return _hasDestination ? 0.22 : 0.16;
  }

  double _customerTripSheetMaxSize({
    required bool active,
    required bool liveTrip,
  }) {
    if (liveTrip) return 0.82;
    if (active) return 0.86;
    return 0.88;
  }

  Widget _bookingSheet({required bool scheduled}) {
    final active = tripCtrl.activeTrip.value != null;
    final liveTrip = _customerInLiveTripPhase();
    final initial = _customerTripSheetInitialSize(
      active: active,
      liveTrip: liveTrip,
    );
    final min = _customerTripSheetMinSize(active: active, liveTrip: liveTrip);
    final max = _customerTripSheetMaxSize(active: active, liveTrip: liveTrip);
    return DraggableScrollableSheet(
      controller: _bookingSheetController,
      expand: false,
      snap: true,
      initialChildSize: initial,
      minChildSize: min,
      maxChildSize: max,
      builder: (context, scrollController) {
        return Container(
          decoration: CustomerBookingSheetStyle.decoration(),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: active
                ? _bookingSheetActiveTripChildren(scheduled)
                : _bookingSheetComposeChildren(scheduled),
          ),
        );
      },
    );
  }

  /// ملخص المسار المتوقع + بطاقات اختيار الفئة التسعيرية (أسعار من إعدادات الفئة).
  Widget _buildExpectedTripAndCategoryPanel() {
    if (!_hasDestination || _effectiveRouteKmForFare() == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildExpectedTripSummary(),
          _buildCategoryPickerRow(),
        ],
      ),
    );
  }

  Widget _buildExpectedTripSummary() {
    if (!_hasDestination) return const SizedBox.shrink();
    final km = _effectiveRouteKmForFare();
    if (km == null) return const SizedBox.shrink();
    final roadKm = _routeKmRoad;
    final isApproxKm = roadKm == null || roadKm <= 0;
    final osrmMin = _routeMinutesRoad;
    final approxMin = _effectiveRouteMinutesForFare();
    final minsRounded = (osrmMin != null && osrmMin > 0 ? osrmMin : approxMin)
            ?.round() ??
        0;
    final timeLine = osrmMin != null && osrmMin > 0
        ? 'الزمن: $minsRounded دقيقة'
        : 'الزمن: $minsRounded دقيقة (تقريبي)';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureZoneQuote();
    });

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: CustomerUiTheme.glassCard(radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تفاصيل الرحلة المتوقعة:',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _navy,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isApproxKm
                  ? 'المسافة: ${km.toStringAsFixed(1)} كم (تقريبي)'
                  : 'المسافة: ${km.toStringAsFixed(1)} كم',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              timeLine,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
                fontSize: 11,
              ),
            ),
            if (_zoneLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: TripBookingTheme.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: TripBookingTheme.amber.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.map_outlined, size: 13, color: TripBookingTheme.navy),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _zoneLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: TripBookingTheme.navy,
                          fontSize: 10.5,
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
    );
  }

  Widget _buildCategoryPickerRow() {
    if (!_hasDestination) return const SizedBox.shrink();
    final km = _effectiveRouteKmForFare();
    if (km == null) return const SizedBox.shrink();

    if (_loadingTypes) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_carTypes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          children: [
            Text(
              _carTypesLoadError ?? 'تعذر تحميل فئات الرحلة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
              ),
            ),
            TextButton(
              onPressed: () => _loadCarTypes(force: true),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _carTypes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final ct = Map<String, dynamic>.from(_carTypes[i]);
          final id = int.tryParse(ct['id']?.toString() ?? '') ?? 0;
          final selected = id == _selectedCarTypeId;
          final fare = _estimatedFareForTrip(
            ct,
            km,
            _effectiveRouteMinutesForFare(),
          );
          final name = ct['name']?.toString().trim() ?? 'فئة';
          final priceLabel = fare != null && fare > 0
              ? '~ ${fare.round()} ل.س'
              : '—';
          return GestureDetector(
            onTap: id <= 0
                ? null
                : () {
                    setState(() => _selectedCarTypeId = id);
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 118,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? TripBookingTheme.amber.withValues(alpha: 0.18)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? TripBookingTheme.navy : Colors.grey.shade300,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CarCategoryVisual.pickerGraphic(ct, iconSize: 26),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                      color: TripBookingTheme.navy,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    priceLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMapBookingTab() {
    return Stack(
      children: [
        ValueListenableBuilder<AppMapOverlay>(
          valueListenable: _mapOverlay,
          builder: (context, overlay, _) {
            return RepaintBoundary(
              child: Obx(() {
                return AppMapView(
                  controller: _mapController,
                  initialCenter:
                      _userGps ?? const LatLng(33.5138, 36.2765),
                  initialZoom: MapStyleConfig.mapDefaultZoom,
                  initialTilt: MapStyleConfig.mapDefaultTilt,
                  overlay: overlay,
                  nightMode: _mapTheme.nightMode.value,
                  onMapReady: () {
                    if (!mounted) return;
                    setState(() => _mapReady = true);
                    _refreshMapOverlay();
                    final driver = tripCtrl.driverLivePos.value;
                    final trip = tripCtrl.activeTrip.value;
                    final st = trip == null
                        ? null
                        : CustomerTripStatusHelpers.normTripStatus(trip);
                    if (driver != null &&
                        _followDriverCam &&
                        (st == 'Running' ||
                            st == 'Reserved' ||
                            st == 'DriverArrived')) {
                      _didInitialLocate = true;
                      _updateCustomerTripCamera(
                        driver,
                        force: true,
                        tripStarted: st == 'Running',
                      );
                    } else {
                      final center = _userGps ?? _pickup;
                      _goToMyLocationOnOpen(center, force: true);
                    }
                  },
                  onUserGesture: () {
                    // التصفح يوقف المتابعة حتى يضغط زر موقعي / متابعة السائق.
                    _followDriverCam = false;
                    _followSelfCam = false;
                    _mapController.setDriverFollow(enabled: false);
                  },
                );
              }),
            );
          },
        ),
        if (!_mapReady) const CustomerMapLoadingOverlay(),
        if (_resolvingPickup) const _PickupResolvingOverlay(),
        if (_started) ...[
          // متابعة خلف سيارة السائق أثناء الرحلة
          if (!_searchExpanded)
            Obx(() {
              final trip = tripCtrl.activeTrip.value;
              if (trip == null) return const SizedBox.shrink();
              final st = CustomerTripStatusHelpers.normTripStatus(trip);
              if (st != 'Running' &&
                  st != 'Reserved' &&
                  st != 'DriverArrived') {
                return const SizedBox.shrink();
              }
              return Positioned(
                top: MediaQuery.paddingOf(context).top + 72,
                left: 16,
                child: FloatingActionButton.small(
                  heroTag: 'cust_follow_driver',
                  backgroundColor: const Color(0xFF1E88E5),
                  foregroundColor: Colors.white,
                  tooltip: 'متابعة السائق',
                  onPressed: () {
                    setState(() {
                      _followDriverCam = true;
                      _followSelfCam = true;
                    });
                    final pos = tripCtrl.driverLivePos.value;
                    if (pos != null) {
                      _updateCustomerTripCamera(
                        pos,
                        force: true,
                        tripStarted: st == 'Running',
                      );
                    }
                  },
                  child: const Icon(Icons.navigation),
                ),
              );
            }),
          if (!_searchExpanded)
            Positioned(
            // أسفل شريط البحث مباشرة حتى لا تتداخل معه.
            top: _customerOverlayHeaderExtent(context) + 62,
            left: 16,
            child: Obx(
              () => CustomerMapToolsMenu(
                expanded: _mapToolsExpanded,
                onToggle: () =>
                    setState(() => _mapToolsExpanded = !_mapToolsExpanded),
                items: [
                  CustomerMapToolItem(
                    icon: Icons.my_location_rounded,
                    highlight: true,
                    onTap: _centerOnMyLocation,
                  ),
                  CustomerMapToolItem(
                    icon: _mapTheme.nightMode.value
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    onTap: () => _mapTheme.toggle(),
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
                        currentPoint: _userGps ?? _pickup,
                        onPick: (p, title) {
                          setState(() {
                            _destStops = [
                              ..._destStops,
                              TripStop(
                                point: p,
                                label: title.trim().isEmpty ? 'وجهة' : title.trim(),
                              ),
                            ];
                            _syncDropoffFromStops();
                          });
                          _scheduleDrivingRouteFetch();
                          _mapController.move(p, 14);
                          _refreshMapOverlay();
                        },
                      );
                    },
                  ),
                  CustomerMapToolItem(
                    icon: Icons.fit_screen_rounded,
                    onTap: _fitRouteOnMap,
                  ),
                ],
              ),
            ),
          ),
          if (!_searchExpanded)
            Align(
              alignment: Alignment.bottomCenter,
              child: _bookingSheet(scheduled: _bookingScheduled),
            ),
          if (!_searchExpanded)
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 210,
              left: 20,
              child: Tooltip(
                message:
                    'طوارئ — عدّ تنازلي 15 ثانية ثم إبلاغ الإدارة (يمكنك الإلغاء)',
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
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 10),
                        ],
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
            ),
          if (!_searchExpanded)
            Obx(() {
              _schedClock.value;
              final list = tripCtrl.upcomingScheduled;
              if (list.isEmpty || tripCtrl.activeTrip.value != null) {
                return const SizedBox.shrink();
              }
              return Positioned(
                bottom: MediaQuery.paddingOf(context).bottom + 292,
                left: 20,
                child: _buildScheduledBookingIcon(list.first, list.length),
              );
            }),
          if (_searchExpanded)
            Positioned.fill(child: _buildSearchOverlay()),
        ],
      ],
    );
  }

  /// أيقونة الحجز المسبق المقبول — تُفتح (كهرماني) قبل الموعد بنصف ساعة.
  Widget _buildScheduledBookingIcon(Map<String, dynamic> next, int count) {
    final open = scheduledGoWindowOpen(next);
    final bg = open ? CustomerUiTheme.amber : _navy;
    final fg = open ? _navy : CustomerUiTheme.amber;
    return Material(
      color: bg,
      elevation: 6,
      borderRadius: BorderRadius.circular(open ? 26 : 30),
      child: InkWell(
        borderRadius: BorderRadius.circular(open ? 26 : 30),
        onTap: () => _showScheduledBookingsSheet(),
        child: Padding(
          padding: open
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
              : const EdgeInsets.all(14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.event_available_rounded, color: fg, size: 28),
                  if (count > 1)
                    Positioned(
                      top: -6,
                      right: -8,
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
                          '$count',
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
              if (open) ...[
                const SizedBox(width: 8),
                Text(
                  'سيبدأ طلبك المسبق',
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showScheduledBookingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.paddingOf(ctx).bottom,
        ),
        child: Obx(() {
          final list = tripCtrl.upcomingScheduled;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CustomerBookingSheetHandle(),
              const SizedBox(height: 8),
              const Text(
                'طلباتك المسبقة المقبولة',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 10),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('لا توجد طلبات مسبقة مقبولة حالياً'),
                ),
              for (final r in list) _scheduledBookingTile(r),
            ],
          );
        }),
      ),
    );
  }

  Widget _scheduledBookingTile(Map<String, dynamic> r) {
    final open = scheduledGoWindowOpen(r);
    final when = formatScheduledRequestDate(r);
    final driverName = (r['driver_name'] ?? '').toString().trim();
    final category = (r['car_category_name'] ?? '').toString().trim();
    final pickup = pickupPlaceLabelForRequest(r);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: open
            ? CustomerUiTheme.amber.withValues(alpha: 0.15)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: open ? CustomerUiTheme.amber : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                open ? Icons.directions_car_rounded : Icons.check_circle_rounded,
                color: open ? Colors.orange.shade800 : Colors.green.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  open ? 'سيبدأ طلبك المسبق قريباً' : 'تم قبول الطلب',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _navy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (when != null) Text('الموعد: $when'),
          if (driverName.isNotEmpty)
            Text(
              category.isNotEmpty
                  ? 'السائق: $driverName — $category'
                  : 'السائق: $driverName',
            ),
          if (pickup.isNotEmpty) Text('الانطلاق: $pickup'),
          const SizedBox(height: 6),
          Text(
            open
                ? 'سيتوجه السائق إليك خلال دقائق — ستظهر لك شاشة «السائق بالطريق إليك».'
                : 'قبل الموعد بنصف ساعة سنرسل لك إشعاراً ويتوجه السائق إليك.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _openSosConfirmDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => SosCountdownDialog(onSend: _sendCustomerSos),
    );
  }

  Future<void> _sendCustomerSos() async {
    final pos = _userGps ?? _pickup;
    try {
      final headers = await ApiEndpoints.headers();
      final response = await http
          .post(
            Uri.parse(ApiEndpoints.emergencySos),
            headers: headers,
            body: jsonEncode({
              'latitude': pos.latitude,
              'longitude': pos.longitude,
            }),
          )
          .timeout(HttpTimeouts.api);
      final decoded = decodeJsonUtf8(response);
      final map = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      if (response.statusCode == 200 && map['state'] == true) {
        SosLiveReporter.instance.start();
        AppSnackBar.notify(
          'تنبيه طوارئ',
          map['message']?.toString() ?? 'تم إبلاغ الإدارة',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
        );
      } else {
        AppSnackBar.notify(
          'فشل الإرسال',
          map['message']?.toString() ?? 'خطأ ${response.statusCode}',
          backgroundColor: Colors.orange.shade800,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      AppSnackBar.notify('خطأ', 'تعذر إرسال SOS: $e');
    }
  }

  bool _canCancel(String? status) {
    final st = CustomerTripStatusHelpers.normTripStatus({'status': status});
    return st == 'Pending' ||
        st == 'Reserved' ||
        st == 'DriverArrived' ||
        st == 'AwaitingDestination';
  }


  Future<void> _openSetDestinationDialog(int requestId) async {
    if (!mounted) return;

    final qC = TextEditingController();
    var loading = false;
    var hits = <Map<String, dynamic>>[];

    Future<void> fetch(String query, void Function(void Function()) setLocal) async {
      final q = query.trim();
      if (q.length < 2) {
        setLocal(() {
          hits = [];
          loading = false;
        });
        return;
      }
      setLocal(() => loading = true);
      try {
        final results = await PhotonSearchService.search(
          q,
          near: _userGps ?? _pickup,
          limit: 15,
        );
        final out = results
            .map((h) => {
                  'name': h.subtitle.isEmpty
                      ? h.name
                      : '${h.name} — ${h.subtitle}',
                  'lat': h.point.latitude,
                  'lon': h.point.longitude,
                })
            .toList();
        setLocal(() {
          hits = out;
          loading = false;
        });
      } catch (_) {
        setLocal(() {
          hits = [];
          loading = false;
        });
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('تحديد وجهة الرحلة'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qC,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'ابحث داخل سوريا…',
                    suffixIcon: loading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search_rounded),
                            onPressed: () => fetch(qC.text, setLocal),
                          ),
                  ),
                  onSubmitted: (v) => fetch(v, setLocal),
                ),
                const SizedBox(height: 10),
                if (hits.isEmpty) const Text('اكتب اسم المكان ثم ابحث.'),
                if (hits.isNotEmpty)
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: hits.length,
                      itemBuilder: (_, i) {
                        final h = hits[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(
                            h['name']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () async {
                            final lat = (h['lat'] as double?) ?? 0;
                            final lon = (h['lon'] as double?) ?? 0;
                            Navigator.pop(ctx);
                            await _setDestinationForTrip(requestId, LatLng(lat, lon));
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ],
        ),
      ),
    );
  }

  /// نفس أسلوب شاشة السائق: زر قائمة دائري كهرماني + شريط عنوان بجانبه.
  Widget _buildCustomerRoundMenuButton() => CustomerBookingMenuButton(
        onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
      );

  Widget _buildCustomerHeaderBanner() => const CustomerBookingWelcomeBanner();

  Widget _buildCustomerTopBarRow() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomerRoundMenuButton(),
            const SizedBox(width: 12),
            Expanded(
              child: _showWelcomeBanner
                  ? _buildCustomerHeaderBanner()
                  : (_started
                      ? _buildDestinationSearchPanel()
                      : const SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }

  /// أسفل الشريط العلوي (زر + ترحيب) عند تراكبه على الخريطة كما في شاشة السائق.
  double _customerOverlayHeaderExtent(BuildContext context) {
    final pad = MediaQuery.paddingOf(context).top;
    return pad + 70;
  }

  Future<void> _setDestinationForTrip(int requestId, LatLng dest) async {
    try {
      final res = await http.post(
        Uri.parse(ApiEndpoints.setDestination(requestId)),
        headers: await ApiEndpoints.headers(),
        body: jsonEncode(<String, dynamic>{
          'destLocationLongitude': dest.longitude,
          'destLocationLatitude': dest.latitude,
        }),
      );
      final map = json.decode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && map['success'] == true) {
        AppSnackBar.notify('تم', 'تم تحديد الوجهة');
        await _loadMyRequests();
        await tripCtrl.refreshActiveTrip();
      } else {
        AppSnackBar.notify('فشل', map['message']?.toString() ?? res.body);
      }
    } catch (e) {
      AppSnackBar.notify('خطأ', '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      extendBody: true,
      backgroundColor: Colors.transparent,
      endDrawer: _buildDrawer(context),
      body: Directionality(
        textDirection: ui.TextDirection.rtl,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: _buildMapBookingTab(),
            ),
            if (_started && !_searchExpanded)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildCustomerTopBarRow(),
              ),
          ],
        ),
      ),
    );
  }
}

/// طبقة خفيفة أثناء جلب اسم نقطة الانطلاق.
class _PickupResolvingOverlay extends StatelessWidget {
  const _PickupResolvingOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: CustomerUiTheme.navy.withValues(alpha: 0.42),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 36),
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: CustomerUiTheme.amber.withValues(alpha: 0.45),
                ),
                boxShadow: [
                  BoxShadow(
                    color: CustomerUiTheme.navy.withValues(alpha: 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: CustomerUiTheme.amber.withValues(alpha: 0.22),
                    ),
                    child: const Icon(
                      Icons.add_location_alt_rounded,
                      color: CustomerUiTheme.navy,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'جاري تحديد نقطة الانطلاق…',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: CustomerUiTheme.navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'لحظة ونثبّت الموقع على الخريطة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12.5,
                      color: CustomerUiTheme.navy.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: CustomerUiTheme.navy,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
