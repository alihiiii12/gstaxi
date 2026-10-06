import 'dart:async';
import '../../core/constants/snack_bar.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../../core/network/api_endpoints.dart';
import '../../core/constants/customer_poll_intervals.dart';
import '../../core/utils/app_alert_sound.dart';
import '../../core/utils/driver_card_subtitle.dart';
import '../../core/widgets/driver_customer_preview_row.dart';

/// بعد إرسال طلب فوري: استطلاع السائقين في النطاق ومن قبلوا، ثم اختيار سائق.
class CustomerImmediatePickDriverSheet extends StatefulWidget {
  const CustomerImmediatePickDriverSheet({
    super.key,
    required this.requestId,
    this.estimatedDurationMinutes,
  });

  final int requestId;
  final double? estimatedDurationMinutes;

  @override
  State<CustomerImmediatePickDriverSheet> createState() =>
      _CustomerImmediatePickDriverSheetState();
}

class _CustomerImmediatePickDriverSheetState
    extends State<CustomerImmediatePickDriverSheet> {
  Timer? _poll;
  bool _loading = true;
  String _error = '';
  Map<String, dynamic>? _payload;
  bool _selecting = false;
  int? _selectedDriverId;
  bool _waitingAccept = false;

  @override
  void initState() {
    super.initState();
    _fetch();
    _poll = Timer.periodic(CustomerPollIntervals.waitingAccept, (_) => _fetch());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final res = await http.get(
        Uri.parse(ApiEndpoints.immediateStatus(widget.requestId)),
        headers: await ApiEndpoints.headers(),
      );
      final map = json.decode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (res.statusCode == 200 && map['success'] == true) {
        setState(() {
          _payload = Map<String, dynamic>.from(map['data'] as Map);
          _loading = false;
          _error = '';
        });
        final req = _payload?['request'] as Map<String, dynamic>?;
        final st = req?['status']?.toString();
        if (st == 'Reserved') {
          _poll?.cancel();
          unawaited(AppAlertSound.playTripAccepted());
          if (mounted) Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _loading = false;
          _error = map['message']?.toString() ?? res.body;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _pick(int driverId) async {
    setState(() => _selecting = true);
    try {
      final res = await http.post(
        Uri.parse(ApiEndpoints.selectDriver(widget.requestId)),
        headers: await ApiEndpoints.headers(),
        body: jsonEncode({
          'driverId': driverId,
          if (widget.estimatedDurationMinutes != null &&
              widget.estimatedDurationMinutes! > 0)
            'estimatedDurationMinutes': widget.estimatedDurationMinutes,
        }),
      );
      final map = json.decode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && map['success'] == true) {
        if (mounted) {
          setState(() => _selectedDriverId = driverId);
        }
        AppSnackBar.notify('تم', 'تم إرسال الطلب للسائق — بانتظار قبوله');
        if (mounted) setState(() => _waitingAccept = true);
      } else {
        AppSnackBar.notify('تعذر الاختيار', map['message']?.toString() ?? res.body);
      }
    } catch (e) {
      AppSnackBar.notify('خطأ', '$e');
    }
    if (mounted) setState(() => _selecting = false);
  }

  Widget _driverTile(Map<String, dynamic> row, {required bool offered}) {
    final name = row['name']?.toString() ?? 'سائق';
    final driverId = int.tryParse(row['driverId']?.toString() ?? '') ?? 0;
    final titleName = _selectedDriverId == driverId
        ? '$name (تم الإرسال له)'
        : name;
    final dUrl = row['driver_photo_url']?.toString();
    final cUrl = row['car_photo_url']?.toString();

    final trailing = (_selectedDriverId == driverId && _waitingAccept)
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : (offered
            ? const SizedBox.shrink()
            : Text(
                'لم يقبل بعد',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ));

    return Card(
      color: _selectedDriverId == driverId
          ? Colors.green.shade50
          : (offered ? Colors.green.shade50 : null),
      child: InkWell(
        onTap: (_selectedDriverId == null && !_selecting && driverId > 0)
            ? () => _pick(driverId)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: DriverCustomerPreviewRow(
            dense: true,
            name: titleName,
            driverPhotoUrl: dUrl,
            carPhotoUrl: cUrl,
            subtitle: bookingDriverCardSubtitle(row),
            trailing: trailing,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.72;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'اختيار السائق',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              _selectedDriverId == null
                  ? 'طلب #${widget.requestId} — اختر سائقاً قريباً'
                  : 'طلب #${widget.requestId} — بانتظار قبول السائق',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            if (_selectedDriverId != null) ...[
              const SizedBox(height: 8),
              Material(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    'يرجى الانتظار حتى يقبل السائق الطلب…',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_loading && _payload == null)
              const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error.isNotEmpty && _payload == null)
              SizedBox(
                height: 220,
                child: Center(child: Text(_error, textAlign: TextAlign.center)),
              )
            else
              SizedBox(
                height: maxH - 130,
                child: RefreshIndicator(
                  onRefresh: _fetch,
                  child: ListView(
                    children: [
                      const Text(
                        'سائقون قريبون منك',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      ...(() {
                        final raw =
                            _payload?['eligible_drivers'] as List<dynamic>? ?? [];
                        final list = raw
                            .map((e) => Map<String, dynamic>.from(e as Map))
                            .toList();
                        if (list.isEmpty) {
                          return [
                            Text(
                              'لا يوجد سائقون قريبون الآن. تأكد أن تطبيق السائق يعمل ويحدث الموقع.',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ];
                        }
                        return list
                            .map((d) => _driverTile(d, offered: false))
                            .toList();
                      })(),
                      ...(() {
                        final rawOffers =
                            _payload?['offers'] as List<dynamic>? ?? [];
                        final offers = rawOffers
                            .map((e) => Map<String, dynamic>.from(e as Map))
                            .toList();
                        if (offers.isEmpty) return <Widget>[];
                        return [
                          const SizedBox(height: 16),
                          const Text(
                            'سائقون قبلوا طلبك — يمكنك الاختيار منهم',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          ...offers.map((d) => _driverTile(d, offered: true)),
                        ];
                      })(),
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
}
