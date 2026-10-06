import 'package:flutter/material.dart';
import '../../../../core/constants/snack_bar.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:latlong2/latlong.dart';

import '../../../../Customer/view/widgets/customer_request_route_map_dialog.dart';
import '../../../../core/services/nominatim_reverse_geocode.dart';
import '../../../../core/utils/driver_order_display.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/request_category_fare_display.dart';
import '../../../../core/utils/request_route_label.dart';
import '../../../../core/widgets/resolved_place_label_row.dart';
import '../../../Home/controller/driver_location_controller.dart';
import '../../../Home/view/widgets/driver_screen_shell.dart';
import '../../../../Customer/view/widgets/customer_booking_ui.dart';
import '../../../../Customer/view/widgets/customer_ui_theme.dart';
import '../../controller/bookings_controller.dart';
import '../../controller/immediate_bookings_controller.dart';

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, this.initialSegmentIndex = 0});

  /// 0 = فوري، 1 = حجوزات مسبقة
  final int initialSegmentIndex;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  late int _segmentIndex;

  @override
  void initState() {
    super.initState();
    _segmentIndex = widget.initialSegmentIndex.clamp(0, 1);
    // لا تُفسد نفس الـ controllers المشتركة مع شاشة الخريطة الرئيسية.
    if (!Get.isRegistered<BookingsController>()) {
      Get.put(BookingsController());
    }
    if (!Get.isRegistered<ImmediateBookingsController>()) {
      Get.put(ImmediateBookingsController());
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  double? _coordDyn(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  LatLng? _latLngFromLooseMap(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<dynamic, dynamic>.from(raw);
    final lat = _coordDyn(m['lat'] ?? m['latitude']);
    final lng = _coordDyn(m['lng'] ?? m['longitude'] ?? m['lon']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  Future<void> _openDriverOrderRouteMap(Map<String, dynamic> order) async {
    final om = Map<String, dynamic>.from(order);
    final start = om['start_location'] ?? om['startLocation'];
    final dest = om['dest_location'] ?? om['destLocation'];
    final pickup = _latLngFromLooseMap(start);
    final destination = _latLngFromLooseMap(dest);
    var pickupLabel =
        areaLabelFromRequestForPoint(om, start, destination: false);
    var destLabel = areaLabelFromRequestForPoint(om, dest, destination: true);
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
    final id = int.tryParse(order['id']?.toString() ?? '') ?? 0;
    await showCustomerRequestRouteMapDialog(
      context,
      pickup: pickup,
      destination: destination,
      pickupName: pickupLabel,
      destinationName: destLabel,
      requestId: id > 0 ? id : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final BookingsController scheduled = Get.find<BookingsController>();
    final ImmediateBookingsController immediate =
        Get.find<ImmediateBookingsController>();

    return DriverScreenShell(
      title: 'الطلبات',
      actions: [
        DriverHeaderIconButton(
          icon: Icons.refresh_rounded,
          onTap: () {
            scheduled.load();
            immediate.load();
          },
        ),
      ],
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: CustomerBookingSegment(
                scheduled: _segmentIndex == 0,
                onImmediate: () => setState(() => _segmentIndex = 1),
                onScheduled: () => setState(() => _segmentIndex = 0),
                scheduledFirst: true,
                immediateLabel: 'طلبات فورية',
                scheduledLabel: 'حجوزات مسبقة',
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _segmentIndex,
                children: [
                  Obx(() => _buildBookingsList(
                        scheduled.loading.value,
                        scheduled.error.value,
                        scheduled.bookings,
                        scheduled,
                        immediateMode: false,
                      )),
                  Obx(() => _buildBookingsList(
                        immediate.loading.value,
                        immediate.error.value,
                        immediate.bookings,
                        immediate,
                        immediateMode: true,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingsList(
    bool loading,
    String err,
    List<Map<String, dynamic>> list,
    dynamic ctrl, {
    required bool immediateMode,
  }) {
    if (loading && list.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: CustomerUiTheme.navy),
      );
    }
    if (err.isNotEmpty && list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            err,
            textAlign: TextAlign.center,
            style: const TextStyle(color: CustomerUiTheme.navy),
          ),
        ),
      );
    }
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: CustomerUiTheme.glassCard(radius: 24),
            child: Text(
              immediateMode
                  ? 'لا توجد طلبات فورية'
                  : 'لا توجد حجوزات مسبقة',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CustomerUiTheme.navy,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            immediateMode
                ? 'طلبات فورية: ${list.length}'
                : 'حجوزات مسبقة: ${list.length}',
            style: TextStyle(
              color: CustomerUiTheme.muted.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            itemCount: list.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildOrderCard(
                  list[index],
                  ctrl,
                  immediateMode: immediateMode,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(
    Map<String, dynamic> order,
    dynamic ctrl, {
    required bool immediateMode,
  }) {
    final id = order['id'];
    final user = order['user'] as Map<String, dynamic>? ?? {};
    final name =
        '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim().ifEmpty('زبون');
    final om = Map<String, dynamic>.from(order);
    final start = om['start_location'] ?? om['startLocation'];
    final dest = om['dest_location'] ?? om['destLocation'];
    final fromStr = areaLabelFromRequestForPoint(om, start, destination: false);
    final toStr = areaLabelFromRequestForPoint(om, dest, destination: true);
    final fareLine = driverRequestUnifiedPricingLine(om);
    final dateRaw = immediateMode
        ? (order['created_at'] ?? order['createdAt'] ?? '').toString()
        : (order['request_date'] ?? order['requestDate'] ?? '').toString();
    final dateStr = AppFormatters.requestCardDateTimeDisplay(dateRaw);
    final statusLabel = driverOrderListStatusLabel(om);
    final st = normTripStatusForOrder(om);
    final showAccept = driverOrderCanShowAccept(om);

    return Container(
      decoration: CustomerUiTheme.glassCard(radius: 22),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _openDriverOrderRouteMap(order),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                CustomerUiTheme.amber.withValues(alpha: 0.22),
                            child: const Icon(
                              Icons.person,
                              color: CustomerUiTheme.navy,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: CustomerUiTheme.navy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '#$id',
                      style: TextStyle(
                        color: st == 'Pending'
                            ? Colors.green.shade700
                            : CustomerUiTheme.navy.withValues(alpha: 0.75),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 15),
                child: Divider(color: Color(0xFFEEEEEE)),
              ),
              _buildRouteDetail(
                Icons.event_available_outlined,
                immediateMode ? 'تاريخ ووقت الإنشاء' : 'موعد الرحلة',
                dateStr.isEmpty ? '—' : dateStr,
                Colors.blue,
              ),
              const SizedBox(height: 10),
              _buildRouteDetail(
                Icons.flag_circle_outlined,
                'الحالة',
                statusLabel,
                Colors.teal.shade700,
              ),
              const SizedBox(height: 12),
              ResolvedPlaceLabelRow(
                icon: Icons.trip_origin,
                label: 'اسم نقطة الانطلاق',
                initialValue: fromStr,
                point: _latLngFromLooseMap(start),
                iconColor: Colors.blue,
              ),
              const SizedBox(height: 12),
              ResolvedPlaceLabelRow(
                icon: Icons.flag_outlined,
                label: 'اسم الوجهة',
                initialValue: toStr,
                point: _latLngFromLooseMap(dest),
                iconColor: Colors.redAccent,
              ),
              if (fareLine != null) ...[
                const SizedBox(height: 10),
                Text(
                  fareLine,
                  style: TextStyle(
                    color: Colors.green.shade800,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 25),
              if (showAccept)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CustomerUiTheme.navy,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            HapticFeedback.mediumImpact();
                            final msg =
                                await ctrl.accept(int.parse(id.toString()));
                            final ok = msg.isNotEmpty;
                            AppSnackBar.notify(
                              ok ? 'تم' : 'فشل',
                              ok ? msg : 'تعذر القبول',
                              snackPosition: SnackPosition.BOTTOM,
                            );
                            if (ok) {
                              if (immediateMode &&
                                  Get.isRegistered<DriverController>()) {
                                Get.find<DriverController>()
                                    .setAcceptedTripPreview(order);
                              } else if (Get.isRegistered<DriverController>()) {
                                Get.find<DriverController>()
                                    .notifyAssignedTripRefresh();
                              } else {
                                ctrl.load();
                              }
                              Get.back();
                            }
                          },
                          child: Text(
                            'قبول',
                            style: TextStyle(
                              color: CustomerUiTheme.amber,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: immediateMode
                                ? CustomerUiTheme.navy
                                : const Color(0xFFC62828),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            if (immediateMode) {
                              _openDriverOrderRouteMap(order);
                              return;
                            }
                            HapticFeedback.mediumImpact();
                            final confirm = await Get.dialog<bool>(
                              AlertDialog(
                                title: const Text('رفض الحجز'),
                                content: const Text(
                                  'سيتم إبلاغ الزبون لرفضك ويمكنه اختيار سائق آخر لنفس الموعد.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Get.back(result: false),
                                    child: const Text('إلغاء'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Get.back(result: true),
                                    child: const Text('رفض'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm != true) return;
                            if (ctrl is! BookingsController) return;
                            final msg = await ctrl.decline(
                              int.parse(id.toString()),
                            );
                            final ok = msg.isNotEmpty;
                            AppSnackBar.notify(
                              ok ? 'تم' : 'فشل',
                              ok ? msg : 'تعذر الرفض',
                              snackPosition: SnackPosition.BOTTOM,
                            );
                            if (ok) Get.back();
                          },
                          child: Text(
                            immediateMode ? 'الخريطة' : 'رفض',
                            style: TextStyle(
                              color: CustomerUiTheme.amber,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CustomerUiTheme.navy,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => _openDriverOrderRouteMap(order),
                    child: Text(
                      'الخريطة',
                      style: TextStyle(
                        color: CustomerUiTheme.amber,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
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

  Widget _buildRouteDetail(
      IconData icon, String label, String val, Color iconColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
              Text(val,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

extension _EmptyExt on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
