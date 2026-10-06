import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../maps/map_style_config.dart';
import '../utils/utf8_text.dart';
import 'google_places_service.dart';

class PlaceHit {
  const PlaceHit({
    required this.name,
    required this.point,
    this.subtitle = '',
  });

  final String name;
  final LatLng point;
  final String subtitle;
}

/// بحث أماكن: Photon وNominatim بالتوازي لتقليل انتظار البحث.
class PhotonSearchService {
  PhotonSearchService._();

  static const _photonTimeout = Duration(milliseconds: 2800);

  static Future<List<PlaceHit>> search(
    String query, {
    LatLng? near,
    int limit = 8,
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];

    // ابدأ الاحتياطي فوراً بينما Photon يعمل — لا ننتظر 8ث×2 ثم نبدأ.
    final backupFuture = GooglePlacesService.autocomplete(
      query: q,
      biasNear: near,
      limit: limit,
    );

    final photon = await _photon(q, near: near, limit: limit, useBbox: true);
    if (photon.isNotEmpty) return photon;

    final photonWide = await _photon(q, near: near, limit: limit, useBbox: false);
    if (photonWide.isNotEmpty) return photonWide;

    final fallback = await backupFuture;
    return fallback
        .map(
          (h) => PlaceHit(
            name: h.label,
            point: h.point,
          ),
        )
        .toList();
  }

  static Future<List<PlaceHit>> _photon(
    String q, {
    LatLng? near,
    int limit = 8,
    bool useBbox = true,
  }) async {
    try {
      final params = <String, String>{
        'q': q,
        'lang': 'ar',
        'limit': '$limit',
      };
      if (near != null) {
        params['lat'] = near.latitude.toString();
        params['lon'] = near.longitude.toString();
      }
      if (useBbox) {
        params['bbox'] =
            '${MapStyleConfig.syriaWest},${MapStyleConfig.syriaSouth},${MapStyleConfig.syriaEast},${MapStyleConfig.syriaNorth}';
      }

      final uri = Uri.parse(MapStyleConfig.photonBaseUrl)
          .replace(queryParameters: params);
      final res = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'SyriaTaxiApp/1.0',
              'Accept': 'application/json',
            },
          )
          .timeout(_photonTimeout);
      if (res.statusCode != 200) return [];
      final map = decodeJsonUtf8(res);
      if (map is! Map) return [];
      final features = map['features'];
      if (features is! List) return [];
      final out = <PlaceHit>[];
      for (final f in features) {
        if (f is! Map) continue;
        final geom = f['geometry'];
        final props = f['properties'];
        if (geom is! Map || props is! Map) continue;
        final coords = geom['coordinates'];
        if (coords is! List || coords.length < 2) continue;
        if (coords[0] is! num || coords[1] is! num) continue;
        final name = repairUtf8Mojibake(
          props['name']?.toString() ??
              props['street']?.toString() ??
              props['city']?.toString() ??
              'موقع',
        );
        final city = repairUtf8Mojibake(props['city']?.toString() ?? '');
        final state = repairUtf8Mojibake(props['state']?.toString() ?? '');
        final subtitle = [city, state].where((e) => e.isNotEmpty).join('، ');
        out.add(
          PlaceHit(
            name: name,
            point: LatLng(
              (coords[1] as num).toDouble(),
              (coords[0] as num).toDouble(),
            ),
            subtitle: subtitle,
          ),
        );
      }
      return out;
    } catch (_) {
      return [];
    }
  }
}
