import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/constants/customer_poll_intervals.dart';
import '../../core/constants/dev_mock_flags.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_queue_worker.dart';
import '../../core/network/http_timeouts.dart';
import '../../core/services/trip_api_service.dart';
import '../../core/utils/app_alert_sound.dart';
import '../../core/utils/utf8_text.dart';
import '../controller/customer_active_trip_controller.dart';
import 'widgets/customer_action_sheets.dart';
import 'widgets/customer_searching_driver_radar.dart';
import 'package:http/http.dart' as http;

/// نتيجة إغلاق شاشة انتظار السائق (قبول / رفض السائق).
enum CustomerImmediateWaitResult {
  accepted,
  /// السائق رفض أو أُلغي الطلب — يُنصح الزبون بإعادة الإرسال أو اختيار سائق آخر.
  declinedOrCancelled,
  dismissed,

  /// انتهت مهلة البحث دون سائق والزبون ضغط «إعادة المحاولة» — يُرسل طلب جديد.
  retry,

  /// انتهت مهلة البحث دون سائق والزبون ضغط «رجوع».
  noDriverFound,
}

/// مهلة البحث ومراحل توسيع النطاق (ثانية ← نصف القطر كم، تطابق الخادم).
abstract final class CustomerSearchTimeline {
  static const int timeoutSeconds = 180;
  static const Map<int, int> stageAtSecond = {60: 1};
  static const Map<int, double> stageRadiusKm = {1: 3};
}

/// يستطلع حالة الطلب ويعرض رادار البحث حتى القبول أو الإلغاء.
class CustomerWaitingDriverRadarHost extends StatefulWidget {
  const CustomerWaitingDriverRadarHost({
    super.key,
    required this.requestId,
    required this.onResult,
    this.radarTitle = 'جاري البحث عن سائق...',
    this.radarSubtitle = 'عم ندور على أقرب سائق لك',
    this.searchWithTimeout = false,
  });

  final int requestId;
  final ValueChanged<CustomerImmediateWaitResult> onResult;
  final String radarTitle;
  final String radarSubtitle;

  /// طلب فوري بث: توسيع النطاق تدريجياً ثم «إعادة المحاولة» عند انتهاء المهلة.
  final bool searchWithTimeout;

  @override
  State<CustomerWaitingDriverRadarHost> createState() =>
      _CustomerWaitingDriverRadarHostState();
}

class _CustomerWaitingDriverRadarHostState
    extends State<CustomerWaitingDriverRadarHost> {
  Timer? _poll;
  Timer? _tick;
  String _error = '';
  bool _finished = false;
  bool _cancelling = false;
  int _timeoutStreak = 0;
  bool _statusInFlight = false;
  int _elapsed = 0;
  /// ساعة حقيقية لا عدّ نبضات — المؤقّت يتوقف عند إطفاء الشاشة ثم يلحق بالوقت.
  final DateTime _startedAt = DateTime.now();
  int _stageSent = 0;
  double? _radiusKm;
  bool _timingOut = false;
  bool _noDriver = false;

  @override
  void initState() {
    super.initState();
    if (kDevMockInstantDriverFound) {
      Future<void>.delayed(const Duration(milliseconds: 1600), () {
        if (!mounted || _finished || _cancelling) return;
        unawaited(AppAlertSound.playTripAccepted());
        _finish(CustomerImmediateWaitResult.accepted);
      });
      return;
    }
    _scheduleStatusPoll(force: true);
    _poll = Timer.periodic(
      CustomerPollIntervals.waitingAccept,
      (_) => _scheduleStatusPoll(),
    );
    if (widget.searchWithTimeout) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  bool get _searchStopped => _finished || _cancelling || _noDriver;

  void _onTick() {
    if (_searchStopped || _timingOut || !mounted) return;
    setState(() {
      _elapsed = DateTime.now().difference(_startedAt).inSeconds;
    });
    var due = 0;
    CustomerSearchTimeline.stageAtSecond.forEach((second, stage) {
      if (_elapsed >= second && stage > due) due = stage;
    });
    if (due > _stageSent) {
      _stageSent = due;
      unawaited(_expandSearch(due));
    }
    if (_elapsed >= CustomerSearchTimeline.timeoutSeconds) {
      unawaited(_onSearchTimeout());
    }
  }

  Future<void> _expandSearch(int stage) async {
    setState(() => _radiusKm = CustomerSearchTimeline.stageRadiusKm[stage]);
    try {
      final res = await http
          .post(
            Uri.parse(ApiEndpoints.expandSearch(widget.requestId)),
            headers: await ApiEndpoints.headers(),
            body: jsonEncode({'stage': stage}),
          )
          .timeout(HttpTimeouts.api);
      if (res.statusCode == 409) _scheduleStatusPoll(force: true);
    } catch (_) {
      // التوسيع التالي أو المهلة يكملان — لا نوقف البحث بسبب فشل مرحلة.
    }
  }

  Future<void> _onSearchTimeout() async {
    if (_searchStopped || _timingOut) return;
    _timingOut = true;
    _tick?.cancel();
    try {
      final res = await http
          .post(
            Uri.parse(ApiEndpoints.searchTimeout(widget.requestId)),
            headers: await ApiEndpoints.headers(),
          )
          .timeout(HttpTimeouts.api);
      final decoded = decodeJsonUtf8(res);
      final data = decoded is Map ? decoded['data'] : null;
      if (!mounted || _finished) return;
      if (res.statusCode == 200 && data is Map) {
        if (data['cancelled'] == true) {
          _enterNoDriver();
          return;
        }
        final st = _normTripStatus(data['status']);
        if (st == 'Reserved' || st == 'DriverArrived' || st == 'Running') {
          unawaited(AppAlertSound.playTripAccepted());
          _finish(CustomerImmediateWaitResult.accepted);
          return;
        }
        _finish(CustomerImmediateWaitResult.declinedOrCancelled);
        return;
      }
      _enqueueTimeoutCancel();
      _enterNoDriver();
    } catch (_) {
      if (!mounted || _finished) return;
      _enqueueTimeoutCancel();
      _enterNoDriver();
    }
  }

  void _enqueueTimeoutCancel() {
    final requestId = widget.requestId;
    ApiQueueWorker.instance.enqueue(
      () async {
        final res = await http
            .post(
              Uri.parse(ApiEndpoints.searchTimeout(requestId)),
              headers: await ApiEndpoints.headers(),
            )
            .timeout(HttpTimeouts.api);
        if (res.statusCode >= 500) {
          throw StateError('search-timeout ${res.statusCode}');
        }
      },
      key: 'search_timeout_$requestId',
      coalesce: true,
      maxAttempts: 4,
    );
  }

  void _enterNoDriver() {
    if (_finished || !mounted) return;
    _poll?.cancel();
    _tick?.cancel();
    if (Get.isRegistered<CustomerActiveTripController>()) {
      Get.find<CustomerActiveTripController>().clearActive();
    }
    setState(() {
      _noDriver = true;
      _error = '';
    });
  }

  void _scheduleStatusPoll({bool force = false}) {
    if (_searchStopped) return;
    ApiQueueWorker.instance.enqueue(
      () async {
        await _fetchStatus();
      },
      key: 'immediate_status_${widget.requestId}',
      coalesce: !force,
      maxAttempts: 1,
    );
  }

  String? _normTripStatus(dynamic v) {
    final raw = v?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase().replaceAll('_', '');
    const canon = {
      'pending': 'Pending',
      'reserved': 'Reserved',
      'removed': 'Removed',
      'finished': 'Finished',
    };
    return canon[lower] ?? raw;
  }

  void _finish(CustomerImmediateWaitResult result) {
    if (_finished) return;
    _finished = true;
    _poll?.cancel();
    widget.onResult(result);
  }

  Future<void> _fetchStatus() async {
    if (_searchStopped || _statusInFlight) return;
    _statusInFlight = true;
    try {
      final res = await http
          .get(
            Uri.parse(ApiEndpoints.immediateStatus(widget.requestId)),
            headers: await ApiEndpoints.headers(),
          )
          .timeout(HttpTimeouts.poll);
      final decoded = decodeJsonUtf8(res);
      final map = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      if (!mounted || _searchStopped) return;
      if (res.statusCode == 200 && map['success'] == true) {
        _timeoutStreak = 0;
        final data = map['data'];
        final req = data is Map ? data['request'] : null;
        final st = _normTripStatus(req is Map ? req['status'] : null);
        if (_error.isNotEmpty) {
          setState(() => _error = '');
        }
        if (st == 'Reserved') {
          unawaited(AppAlertSound.playTripAccepted());
          _finish(CustomerImmediateWaitResult.accepted);
          return;
        }
        if (st == 'Removed' && !_timingOut) {
          _finish(CustomerImmediateWaitResult.declinedOrCancelled);
          return;
        }
      } else if (res.statusCode >= 500) {
        _timeoutStreak++;
        if (_timeoutStreak >= 3 && mounted) {
          setState(() => _error = 'الاتصال بطيء — نتابع البحث…');
        }
      }
    } on TimeoutException {
      _timeoutStreak++;
      if (mounted && !_finished && _timeoutStreak >= 3) {
        setState(() => _error = 'الاتصال بطيء — نتابع البحث…');
      }
    } catch (e) {
      if (mounted && !_finished && !_cancelling) {
        setState(() => _error = '$e');
      }
    } finally {
      _statusInFlight = false;
    }
  }

  /// مثل «إلغاء الطلب»: يغلق الشاشة فوراً ويُلغي على السيرفر عبر طابور الشبكة.
  Future<void> _cancelSearch() async {
    if (_finished || _cancelling) return;
    final ok = await CustomerActionSheets.confirm(
      context,
      title: 'إلغاء البحث',
      message: 'هل تريد إيقاف البحث عن سائق وإلغاء هذا الطلب؟',
      confirmLabel: 'إلغاء البحث',
      cancelLabel: 'متابعة البحث',
      destructive: true,
      icon: Icons.radar_rounded,
    );
    if (ok != true || !mounted || _finished) return;

    setState(() => _cancelling = true);
    _poll?.cancel();

    final requestId = widget.requestId;
    if (Get.isRegistered<CustomerActiveTripController>()) {
      Get.find<CustomerActiveTripController>().clearActive();
    }

    // إغلاق فوري للواجهة — لا ننتظر مهلة السيرفر.
    _finish(CustomerImmediateWaitResult.dismissed);

    ApiQueueWorker.instance.enqueue(
      () async {
        var r = await TripApiService.cancelCustomerRequest(
          requestId,
          reason: 'user_cancelled_search',
        );
        if (!r.ok &&
            (r.statusCode >= 500 ||
                r.statusCode == 408 ||
                r.statusCode == 0 ||
                r.statusCode == -1)) {
          r = await TripApiService.abortActiveTrip(
            requestId,
            reason: 'user_cancelled_search',
          );
        }
        if (!r.ok) {
          throw StateError(r.message ?? 'cancel failed ${r.statusCode}');
        }
      },
      key: 'cancel_request_$requestId',
      coalesce: true,
      maxAttempts: 4,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_noDriver) {
      return CustomerSearchingDriverRadarBody(
        title: 'لم نجد سائقاً متاحاً',
        subtitle:
            'لا يوجد سائق متاح قربك حالياً.\nاضغط «إعادة المحاولة» للبحث من جديد.',
        noDriverFound: true,
        onRetry: () => _finish(CustomerImmediateWaitResult.retry),
        onBack: () => _finish(CustomerImmediateWaitResult.noDriverFound),
      );
    }
    final km = _radiusKm;
    final subtitle = km == null
        ? widget.radarSubtitle
        : 'نوسّع نطاق البحث حتى ${km.toStringAsFixed(0)} كم…';
    return CustomerSearchingDriverRadarBody(
      title: widget.radarTitle,
      subtitle: subtitle,
      error: _friendlyError(_error),
      cancelling: _cancelling,
      onCancelSearch: _cancelSearch,
      progress: widget.searchWithTimeout
          ? (_elapsed / CustomerSearchTimeline.timeoutSeconds).clamp(0.0, 1.0)
          : null,
    );
  }

  String? _friendlyError(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final lower = t.toLowerCase();
    if (lower.contains('timeout') ||
        t.contains('انتهت مهلة') ||
        t.contains('الاتصال بطيء')) {
      return 'الاتصال بطيء — نتابع البحث…';
    }
    if (lower.contains('6379') ||
        lower.contains('redis') ||
        lower.contains('actively refused') ||
        lower.contains('connection could be made')) {
      return 'تعذر الاتصال بخدمة التتبع مؤقتاً — نعيد المحاولة…';
    }
    if (t.length > 120) return 'حدث خطأ أثناء البحث — نعيد المحاولة…';
    return t;
  }
}

/// بعد إرسال الطلب (بث أو سائق محدد): شاشة رادار كاملة أثناء انتظار القبول.
class CustomerWaitingDriverAcceptSheet extends StatelessWidget {
  const CustomerWaitingDriverAcceptSheet({
    super.key,
    required this.requestId,
    this.radarTitle = 'جاري البحث عن سائق...',
    this.radarSubtitle = 'عم ندور على أقرب سائق لك',
    this.searchWithTimeout = false,
  });

  final int requestId;
  final String radarTitle;
  final String radarSubtitle;
  final bool searchWithTimeout;

  static Future<CustomerImmediateWaitResult?> show(
    BuildContext context, {
    required int requestId,
    String radarTitle = 'جاري البحث عن سائق...',
    String radarSubtitle = 'عم ندور على أقرب سائق لك',
    bool searchWithTimeout = false,
  }) async {
    CustomerActiveTripController? tripCtrl;
    if (Get.isRegistered<CustomerActiveTripController>()) {
      tripCtrl = Get.find<CustomerActiveTripController>();
      tripCtrl.holdOrphanPendingCleanup = true;
    }
    try {
      return await Navigator.of(context).push<CustomerImmediateWaitResult>(
        PageRouteBuilder<CustomerImmediateWaitResult>(
          opaque: true,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (ctx, animation, secondaryAnimation) {
            return CustomerWaitingDriverAcceptSheet(
              requestId: requestId,
              radarTitle: radarTitle,
              radarSubtitle: radarSubtitle,
              searchWithTimeout: searchWithTimeout,
            );
          },
          transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } finally {
      if (tripCtrl != null) {
        tripCtrl.holdOrphanPendingCleanup = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: CustomerWaitingDriverRadarHost(
        requestId: requestId,
        radarTitle: radarTitle,
        radarSubtitle: radarSubtitle,
        searchWithTimeout: searchWithTimeout,
        onResult: (result) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop(result);
          }
        },
      ),
    );
  }
}
