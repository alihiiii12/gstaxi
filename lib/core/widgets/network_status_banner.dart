import 'package:flutter/material.dart';

import '../network/network_status_service.dart';

/// شريط أعلى الشاشة يظهر فوق كل صفحات التطبيق عند ضعف الإنترنت أو انقطاعه.
class NetworkStatusBanner extends StatelessWidget {
  const NetworkStatusBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final service = NetworkStatusService.instance;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        ValueListenableBuilder<NetworkQuality>(
          valueListenable: service.quality,
          builder: (context, q, _) {
            final show = q != NetworkQuality.good;
            final offline = q == NetworkQuality.offline;
            final top = MediaQuery.paddingOf(context).top;
            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !show,
                child: AnimatedSlide(
                  offset: show ? Offset.zero : const Offset(0, -1.2),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: AnimatedOpacity(
                    opacity: show ? 1 : 0,
                    duration: const Duration(milliseconds: 260),
                    child: Material(
                      color: offline
                          ? const Color(0xFFC62828)
                          : const Color(0xFFEF8F00),
                      elevation: 6,
                      child: InkWell(
                        onTap: service.recheck,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(14, top + 8, 14, 9),
                          child: Directionality(
                            textDirection: TextDirection.rtl,
                            child: Row(
                              children: [
                                Icon(
                                  offline
                                      ? Icons.wifi_off_rounded
                                      : Icons.network_check_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    offline
                                        ? 'الاتصال بالإنترنت مقطوع — تحقق من الاتصال'
                                        : 'الاتصال بالإنترنت ضعيف — تحقق من الاتصال',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
