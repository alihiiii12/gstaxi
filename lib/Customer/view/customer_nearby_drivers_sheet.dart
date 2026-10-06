import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/network/api_endpoints.dart';
import '../../core/utils/driver_card_subtitle.dart';
import '../../core/widgets/driver_customer_preview_row.dart';

/// عرض السائقين القريبين مع تبويب لكل فئة تسعيرية (مريحة، اقتصادي…).
class CustomerNearbyDriversSheet extends StatefulWidget {
  const CustomerNearbyDriversSheet({
    super.key,
    required this.pickupLat,
    required this.pickupLng,
    required this.destLat,
    required this.destLng,
    required this.carTypes,
    this.initialCarTypeId,
    this.estimatedDurationMinutes,
    this.estimatedTripKm,
    this.dialogTitle,
    this.selectionHint,
    required this.onSendToDriver,
  });

  final double pickupLat;
  final double pickupLng;
  final double destLat;
  final double destLng;
  final List<Map<String, dynamic>> carTypes;
  final int? initialCarTypeId;
  final double? estimatedDurationMinutes;
  /// مسافة الرحلة الكاملة عبر كل المحطات.
  final double? estimatedTripKm;
  final String? dialogTitle;
  final String? selectionHint;

  /// يُرجع رقم الطلب عند النجاح.
  final Future<int?> Function(int driverId, int carTypeId) onSendToDriver;

  @override
  State<CustomerNearbyDriversSheet> createState() =>
      _CustomerNearbyDriversSheetState();
}

class _CustomerNearbyDriversSheetState extends State<CustomerNearbyDriversSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<int> _typeIds = [];
  final List<String> _typeNames = [];

  final Map<int, List<Map<String, dynamic>>> _rowsByType = {};
  final Map<int, bool> _loadingByType = {};
  final Map<int, String> _errorByType = {};
  int? _sendingId;
  Timer? _refreshTimer;

  int get _currentTypeId {
    if (_typeIds.isEmpty) return 0;
    final i = _tabController.index.clamp(0, _typeIds.length - 1);
    return _typeIds[i];
  }

  @override
  void initState() {
    super.initState();
    for (final e in widget.carTypes) {
      final id = int.tryParse(e['id']?.toString() ?? '') ?? 0;
      if (id <= 0) continue;
      _typeIds.add(id);
      _typeNames.add(e['name']?.toString().trim().isNotEmpty == true
          ? e['name'].toString().trim()
          : 'فئة #$id');
    }
    var initialIndex = 0;
    if (widget.initialCarTypeId != null) {
      final ix = _typeIds.indexOf(widget.initialCarTypeId!);
      if (ix >= 0) initialIndex = ix;
    }
    _tabController = TabController(
      length: _typeIds.isEmpty ? 1 : _typeIds.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController.addListener(_onTabChanged);
    if (_typeIds.isNotEmpty) {
      for (final id in _typeIds) {
        unawaited(_loadForType(id, silent: true));
      }
    }
    _refreshTimer = Timer.periodic(const Duration(seconds: 14), (_) {
      if (_typeIds.isEmpty) return;
      unawaited(_loadForType(_currentTypeId, silent: true));
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (_typeIds.isEmpty) return;
    unawaited(_loadForType(_currentTypeId));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadForType(int carTypeId, {bool silent = false}) async {
    if (carTypeId <= 0) return;
    if (!silent) {
      setState(() {
        _loadingByType[carTypeId] = true;
        _errorByType[carTypeId] = '';
      });
    }
    try {
      final uri = Uri.parse(ApiEndpoints.nearbyDriversBooking(
        pickupLat: widget.pickupLat,
        pickupLng: widget.pickupLng,
        carTypeId: carTypeId,
        destLat: widget.destLat,
        destLng: widget.destLng,
        estimatedDurationMinutes: widget.estimatedDurationMinutes,
        estimatedTripKm: widget.estimatedTripKm,
      ));
      final res = await http.get(uri, headers: await ApiEndpoints.headers());
      final map = json.decode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (res.statusCode == 200 && map['success'] == true) {
        final raw = map['data'] as List<dynamic>? ?? [];
        setState(() {
          _rowsByType[carTypeId] =
              raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _loadingByType[carTypeId] = false;
        });
      } else {
        setState(() {
          _loadingByType[carTypeId] = false;
          _errorByType[carTypeId] =
              map['message']?.toString() ?? res.body;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingByType[carTypeId] = false;
          _errorByType[carTypeId] = '$e';
        });
      }
    }
  }

  Future<void> _send(int driverId, int carTypeId) async {
    setState(() => _sendingId = driverId);
    try {
      final rid = await widget.onSendToDriver(driverId, carTypeId);
      if (!mounted) return;
      if (rid != null) Navigator.of(context).pop(rid);
    } finally {
      if (mounted) setState(() => _sendingId = null);
    }
  }

  Widget _buildDriverList(int carTypeId) {
    final loading = _loadingByType[carTypeId] == true;
    final err = _errorByType[carTypeId] ?? '';
    final rows = _rowsByType[carTypeId] ?? [];

    if (loading && rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (err.isNotEmpty && rows.isEmpty) {
      return Center(child: Text(err, textAlign: TextAlign.center));
    }
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'لا يوجد سائقون متصلون في هذه الفئة قريباً منك.\nجرّب تبويباً آخر أو «تحديث».',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    }

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (ctx, i) {
        final row = rows[i];
        final name = row['name']?.toString() ?? 'سائق';
        final did =
            int.tryParse(row['driverId']?.toString() ?? '') ?? 0;
        final busy = _sendingId != null;
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: DriverCustomerPreviewRow(
              name: name,
              driverPhotoUrl: row['driver_photo_url']?.toString(),
              carPhotoUrl: row['car_photo_url']?.toString(),
              subtitle: bookingDriverCardSubtitle(row),
              trailing: _sendingId == did
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ElevatedButton(
                      onPressed: (!busy && did > 0)
                          ? () => _send(did, carTypeId)
                          : null,
                      child: const Text('إرسال الطلب'),
                    ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.dialogTitle ?? 'اختر السائق حسب الفئة',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Text(
            widget.selectionHint ??
                'اختر الفئة من الأعلى ثم السائق. يظهر عدد المتصلين في كل فئة.',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          if (_typeIds.isEmpty)
            const Expanded(
              child: Center(child: Text('لا توجد فئات مركبات محمّلة.')),
            )
          else ...[
            TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: const Color(0xFF11215B),
              indicatorColor: const Color(0xFFFFC107),
              tabs: List.generate(_typeIds.length, (i) {
                final id = _typeIds[i];
                final cnt = (_rowsByType[id] ?? []).length;
                final loading = _loadingByType[id] == true;
                final badge = loading && cnt == 0 ? '…' : '$cnt';
                return Tab(text: '${_typeNames[i]} ($badge)');
              }),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _typeIds
                    .map((id) => _buildDriverList(id))
                    .toList(),
              ),
            ),
          ],
          TextButton.icon(
            onPressed: _typeIds.isEmpty
                ? null
                : () => _loadForType(_currentTypeId),
            icon: const Icon(Icons.refresh),
            label: const Text('تحديث القائمة'),
          ),
        ],
      ),
    );
  }
}
