import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../services/favorite_places_service.dart';

/// قائمة المفضلة + إضافة الموقع الحالي.
class FavoritePlacesSheet extends StatelessWidget {
  const FavoritePlacesSheet({
    super.key,
    required this.onPick,
    this.currentPoint,
  });

  final void Function(LatLng point, String title) onPick;
  final LatLng? currentPoint;

  static Future<void> show(
    BuildContext context, {
    required void Function(LatLng point, String title) onPick,
    LatLng? currentPoint,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FavoritePlacesSheet(
        onPick: onPick,
        currentPoint: currentPoint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fav = Get.isRegistered<FavoritePlacesService>()
        ? Get.find<FavoritePlacesService>()
        : Get.put(FavoritePlacesService());

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Obx(() {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'المواقع المفضلة',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (currentPoint != null)
                OutlinedButton.icon(
                  onPressed: () async {
                    final title = await _askTitle(context);
                    if (title == null || title.trim().isEmpty) return;
                    await fav.add(title.trim(), currentPoint!);
                  },
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('حفظ الموقع الحالي'),
                ),
              const SizedBox(height: 8),
              if (fav.places.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('لا توجد مواقع محفوظة بعد'),
                )
              else
                ...fav.places.map(
                  (p) => ListTile(
                    leading: const Icon(Icons.place, color: Color(0xFF11215B)),
                    title: Text(p.title),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => fav.remove(p.id),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      onPick(p.point, p.title);
                    },
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  Future<String?> _askTitle(BuildContext context) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم الموقع'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: 'مثل: المنزل / الموقف'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
