import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/maps/app_map_controller.dart';
import '../../../core/services/photon_search_service.dart';
import '../../../core/theme/app_text_style.dart';
import 'customer_ui_theme.dart';

class _PlaceHit {
  _PlaceHit({required this.displayName, required this.point});
  final String displayName;
  final ll.LatLng point;
}

/// نتيجة اختيار نقطة الانطلاق من الخريطة.
class PickupMapPick {
  const PickupMapPick({required this.point, this.label});

  final ll.LatLng point;
  final String? label;
}

/// اختيار نقطة الانطلاق — دبوس ثابت في الوسط وحرّك الخريطة تحته.
class PickupDestinationMapPicker extends StatefulWidget {
  const PickupDestinationMapPicker({
    super.key,
    required this.initialCenter,
    this.seedPickup,
  });

  final ll.LatLng initialCenter;
  final ll.LatLng? seedPickup;

  @override
  State<PickupDestinationMapPicker> createState() =>
      _PickupDestinationMapPickerState();
}

class _PickupDestinationMapPickerState extends State<PickupDestinationMapPicker> {
  final AppMapController _map = AppMapController();
  final TextEditingController _pickupSearch = TextEditingController();
  Timer? _pickupSearchDebounce;
  List<_PlaceHit> _pickupHits = [];
  bool _pickupSearchLoading = false;
  ll.LatLng? _pick;
  String? _labelFromSearch;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _pick = widget.seedPickup ?? widget.initialCenter;
    _pickupSearch.addListener(() {
      final q = _pickupSearch.text.trim();
      _pickupSearchDebounce?.cancel();
      if (q.length < 2) {
        setState(() => _pickupHits = []);
        return;
      }
      _pickupSearchDebounce = Timer(const Duration(milliseconds: 450), () {
        _fetchPickupPlaces(q);
      });
    });
  }

  @override
  void dispose() {
    _pickupSearchDebounce?.cancel();
    _pickupSearch.dispose();
    _map.detach();
    super.dispose();
  }

  Future<void> _fetchPickupPlaces(String query) async {
    setState(() => _pickupSearchLoading = true);
    try {
      final hits = await PhotonSearchService.search(
        query,
        near: widget.initialCenter,
        limit: 8,
      );
      if (!mounted) return;
      setState(() {
        _pickupHits = hits
            .map(
              (h) => _PlaceHit(
                displayName: h.subtitle.isEmpty
                    ? h.name
                    : '${h.name} — ${h.subtitle}',
                point: h.point,
              ),
            )
            .toList();
        _pickupSearchLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _pickupHits = [];
          _pickupSearchLoading = false;
        });
      }
    }
  }

  /// بدون setState — حتى لا يُعاد بناء الخريطة أثناء السحب فيبطئها.
  void _syncPickFromMapCenter({bool clearSearchLabel = true}) {
    final c = _map.cameraCenter;
    if (!c.latitude.isFinite || !c.longitude.isFinite) return;
    _pick = c;
    if (clearSearchLabel) _labelFromSearch = null;
  }

  Future<void> _useGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      final point = ll.LatLng(pos.latitude, pos.longitude);
      _pick = point;
      _labelFromSearch = null;
      await _map.move(point, 16);
      _syncPickFromMapCenter();
    } catch (_) {}
  }

  void _confirm() {
    _syncPickFromMapCenter(clearSearchLabel: false);
    final p = _pick ?? _map.cameraCenter;
    final raw = (_labelFromSearch ?? _pickupSearch.text).trim();
    final label = raw.isEmpty ? null : raw.split('—').first.trim();
    Navigator.pop(
      context,
      PickupMapPick(point: p, label: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    const title = 'حرّك الخريطة تحت الدبوس لتحديد الانطلاق';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            title,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: CustomerUiTheme.navy,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: TextField(
            controller: _pickupSearch,
            decoration: InputDecoration(
              hintText: 'ابحث عن نقطة الانطلاق',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _pickupSearchLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_pickupHits.isNotEmpty)
          SizedBox(
            height: 120,
            child: ListView.builder(
              itemCount: _pickupHits.length,
              itemBuilder: (_, i) {
                final h = _pickupHits[i];
                return ListTile(
                  dense: true,
                  title: Text(h.displayName, maxLines: 2),
                  onTap: () async {
                    setState(() {
                      _labelFromSearch = h.displayName;
                      _pickupHits = [];
                      _pickupSearch.text = h.displayName;
                    });
                    _pick = h.point;
                    await _map.move(h.point, 16);
                    _syncPickFromMapCenter(clearSearchLabel: false);
                  },
                );
              },
            ),
          ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // خريطة تأخذ كل الإيماءات بسلاسة بكل الاتجاهات.
              AppMapView(
                controller: _map,
                initialCenter: widget.seedPickup ?? widget.initialCenter,
                initialZoom: 15,
                overlay: AppMapOverlay.empty,
                eagerGestureArena: true,
                onMapReady: () async {
                  final c = widget.seedPickup ?? widget.initialCenter;
                  await _map.move(c, 15, animate: false);
                  if (!mounted) return;
                  _pick = c;
                  setState(() => _mapReady = true);
                },
                onCameraIdle: () {
                  if (!_mapReady) return;
                  _syncPickFromMapCenter();
                },
              ),
              // دبوس ثابت فوق الخريطة — لا يلتقط اللمس.
              const IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 36),
                    child: Icon(
                      Icons.location_on_rounded,
                      size: 48,
                      color: CustomerUiTheme.navy,
                      shadows: [
                        Shadow(
                          color: Color(0x59000000),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 16,
                child: FloatingActionButton.small(
                  heroTag: 'pick_gps',
                  backgroundColor: CustomerUiTheme.amber,
                  foregroundColor: CustomerUiTheme.navy,
                  onPressed: _useGps,
                  child: const Icon(Icons.my_location),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: CustomerUiTheme.navy,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _mapReady ? _confirm : null,
              child: const Text('تأكيد نقطة الانطلاق'),
            ),
          ),
        ),
      ],
    );
  }
}
