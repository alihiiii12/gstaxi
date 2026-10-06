import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/services/offline_maps_service.dart';

/// تحميل حزم خرائط أوفلاين لسوريا (أسلوب MAPS.ME).
class OfflineMapsScreen extends StatelessWidget {
  const OfflineMapsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = Get.isRegistered<OfflineMapsService>()
        ? Get.find<OfflineMapsService>()
        : Get.put(OfflineMapsService());

    return Scaffold(
      appBar: AppBar(
        title: const Text('خرائط أوفلاين'),
        backgroundColor: const Color(0xFF11215B),
        foregroundColor: Colors.white,
      ),
      body: Obx(() {
        final msg = svc.statusMessage.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (msg.isNotEmpty)
              Material(
                color: const Color(0xFFE8EEF9),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(msg, style: const TextStyle(fontSize: 13)),
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'حمّل مناطق سوريا لاستخدام الخريطة بدون إنترنت. يُفضّل التحميل عبر Wi‑Fi.',
                style: TextStyle(color: Colors.black54),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: svc.packs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final pack = svc.packs[i];
                  final downloaded = svc.isDownloaded(pack.id);
                  final downloading = svc.downloadingId.value == pack.id;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pack.nameAr,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  downloading
                                      ? 'التقدّم ${(svc.downloadProgress.value * 100).toStringAsFixed(0)}%'
                                      : 'حجم تقريبي ~${pack.approxMb} MB',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 13,
                                  ),
                                ),
                                if (downloading) ...[
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: svc.downloadProgress.value > 0
                                          ? svc.downloadProgress.value
                                          : null,
                                      minHeight: 4,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (downloading)
                            const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          else if (downloaded)
                            IconButton(
                              tooltip: 'إزالة',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => svc.removePack(pack),
                            )
                          else
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFF9A825),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),
                              ),
                              onPressed: svc.downloadingId.value != null
                                  ? null
                                  : () => svc.downloadPack(pack),
                              child: const Text('تحميل'),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }),
    );
  }
}
