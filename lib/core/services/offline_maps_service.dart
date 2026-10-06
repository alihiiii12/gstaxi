import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../maps/map_style_config.dart';

class OfflineMapPack {
  const OfflineMapPack({
    required this.id,
    required this.nameAr,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    this.minZoom = 8,
    this.maxZoom = 15,
    this.approxMb = 80,
  });

  final String id;
  final String nameAr;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  final double minZoom;
  final double maxZoom;
  final int approxMb;

  LatLngBounds get bounds => LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

  factory OfflineMapPack.fromJson(Map<String, dynamic> j) => OfflineMapPack(
        id: j['id']?.toString() ?? '',
        nameAr: j['name_ar']?.toString() ?? j['name']?.toString() ?? '',
        minLat: (j['min_lat'] as num?)?.toDouble() ?? 0,
        maxLat: (j['max_lat'] as num?)?.toDouble() ?? 0,
        minLng: (j['min_lng'] as num?)?.toDouble() ?? 0,
        maxLng: (j['max_lng'] as num?)?.toDouble() ?? 0,
        minZoom: (j['min_zoom'] as num?)?.toDouble() ?? 8,
        maxZoom: (j['max_zoom'] as num?)?.toDouble() ?? 15,
        approxMb: (j['approx_mb'] as num?)?.toInt() ?? 80,
      );
}

abstract final class DefaultSyriaOfflinePacks {
  static List<OfflineMapPack> get all => const [
        OfflineMapPack(
          id: 'damascus',
          nameAr: 'دمشق وريفها',
          minLat: 33.2,
          maxLat: 33.8,
          minLng: 35.9,
          maxLng: 37.0,
          approxMb: 120,
        ),
        OfflineMapPack(
          id: 'aleppo',
          nameAr: 'حلب',
          minLat: 36.0,
          maxLat: 36.5,
          minLng: 36.9,
          maxLng: 37.4,
          approxMb: 100,
        ),
        OfflineMapPack(
          id: 'homs_hama',
          nameAr: 'حمص وحماة',
          minLat: 34.4,
          maxLat: 35.4,
          minLng: 36.3,
          maxLng: 37.3,
          approxMb: 110,
        ),
        OfflineMapPack(
          id: 'latakia_tartus',
          nameAr: 'اللاذقية وطرطوس',
          minLat: 34.7,
          maxLat: 35.8,
          minLng: 35.7,
          maxLng: 36.3,
          approxMb: 90,
        ),
        OfflineMapPack(
          id: 'south',
          nameAr: 'الجنوب (درعا/سويداء)',
          minLat: 32.3,
          maxLat: 33.2,
          minLng: 35.8,
          maxLng: 37.0,
          approxMb: 85,
        ),
        OfflineMapPack(
          id: 'syria_overview',
          nameAr: 'سوريا (نظرة عامة منخفضة التفصيل)',
          minLat: MapStyleConfig.syriaSouth,
          maxLat: MapStyleConfig.syriaNorth,
          minLng: MapStyleConfig.syriaWest,
          maxLng: MapStyleConfig.syriaEast,
          minZoom: 5,
          maxZoom: 10,
          approxMb: 60,
        ),
      ];
}

class OfflineMapsService extends GetxController {
  static const _kDownloaded = 'offline_map_pack_ids';

  final packs = <OfflineMapPack>[].obs;
  final downloadedIds = <String>{}.obs;
  final downloadingId = RxnString();
  final downloadProgress = 0.0.obs;
  final statusMessage = ''.obs;

  final _box = GetStorage();

  @override
  void onInit() {
    super.onInit();
    final raw = _box.read(_kDownloaded);
    if (raw is List) {
      downloadedIds.addAll(raw.map((e) => e.toString()));
    }
    packs.assignAll(DefaultSyriaOfflinePacks.all);
    loadCatalog();
  }

  Future<void> loadCatalog() async {
    try {
      final res = await http
          .get(Uri.parse(MapStyleConfig.offlineCatalogUrl))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return;
      final decoded = json.decode(res.body);
      if (decoded is! Map) return;
      final list = decoded['packs'];
      if (list is! List || list.isEmpty) return;
      final parsed = <OfflineMapPack>[];
      for (final e in list) {
        if (e is Map) {
          final p = OfflineMapPack.fromJson(Map<String, dynamic>.from(e));
          if (p.id.isNotEmpty) parsed.add(p);
        }
      }
      if (parsed.isNotEmpty) packs.assignAll(parsed);
    } catch (_) {}
  }

  bool isDownloaded(String id) => downloadedIds.contains(id);

  Future<void> downloadPack(OfflineMapPack pack) async {
    if (downloadingId.value != null) return;
    downloadingId.value = pack.id;
    downloadProgress.value = 0;
    statusMessage.value = 'جاري التحميل… يُفضّل Wi‑Fi';
    try {
      await downloadOfflineRegion(
        OfflineRegionDefinition(
          bounds: pack.bounds,
          mapStyleUrl: MapStyleConfig.dayStyleUrl,
          minZoom: pack.minZoom,
          maxZoom: pack.maxZoom,
        ),
        metadata: {
          'name': pack.nameAr,
          'pack_id': pack.id,
        },
        onEvent: (event) {
          if (event is InProgress) {
            downloadProgress.value = (event.progress / 100.0).clamp(0.0, 1.0);
            if (event.requiredResourceCount > 0) {
              downloadProgress.value =
                  event.completedResourceCount / event.requiredResourceCount;
            }
          } else if (event is Success) {
            downloadProgress.value = 1;
          } else {
            statusMessage.value = 'فشل التحميل: $event';
          }
        },
      );
      downloadedIds.add(pack.id);
      await _box.write(_kDownloaded, downloadedIds.toList());
      statusMessage.value = 'تم التحميل: ${pack.nameAr}';
      downloadProgress.value = 1;
    } catch (e) {
      statusMessage.value = 'تعذر التحميل: $e';
      debugPrint('[OfflineMaps] $e');
    } finally {
      downloadingId.value = null;
    }
  }

  Future<void> removePack(OfflineMapPack pack) async {
    downloadedIds.remove(pack.id);
    await _box.write(_kDownloaded, downloadedIds.toList());
    statusMessage.value = 'تمت إزالة ${pack.nameAr}';
    try {
      final regions = await getListOfRegions();
      for (final r in regions) {
        final meta = r.metadata;
        if (meta['pack_id']?.toString() == pack.id) {
          await deleteOfflineRegion(r.id);
        }
      }
    } catch (_) {}
  }
}
