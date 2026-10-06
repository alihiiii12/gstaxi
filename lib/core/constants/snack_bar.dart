import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_text_style.dart';

enum AppSnackKind { success, error, warning, info }

/// إشعار داخلي عصري ينزل من أعلى الشاشة.
class AppSnackBar {
  AppSnackBar._();

  static const Color _navy = Color(0xFF11215B);
  static const Color _amber = Color(0xFFFFC107);

  static void success(String message, {String title = 'نجاح'}) =>
      _show(title: title, message: message, kind: AppSnackKind.success);

  static void error(String message, {String title = 'خطأ'}) =>
      _show(title: title, message: message, kind: AppSnackKind.error);

  static void warning(String message, {String title = 'تنبيه'}) =>
      _show(title: title, message: message, kind: AppSnackKind.warning);

  static void info(String message, {String title = 'معلومة'}) =>
      _show(title: title, message: message, kind: AppSnackKind.info);

  /// بديل موحّد لـ `Get.snackbar` بنفس التوقيع الشائع في المشروع.
  static void notify(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackPosition snackPosition = SnackPosition.TOP,
    Color? backgroundColor,
    Color? colorText,
    Widget? mainButton,
    double? borderRadius,
    EdgeInsetsGeometry? margin,
    bool isDismissible = true,
    DismissDirection? dismissDirection,
  }) {
    final kind = _inferKind(title, message, backgroundColor);
    _show(
      title: title,
      message: message,
      kind: kind,
      duration: duration,
      action: mainButton,
    );
  }

  static AppSnackKind _inferKind(
    String title,
    String message,
    Color? backgroundColor,
  ) {
    if (backgroundColor != null) {
      final r = (backgroundColor.r * 255.0).round().clamp(0, 255);
      final g = (backgroundColor.g * 255.0).round().clamp(0, 255);
      final b = (backgroundColor.b * 255.0).round().clamp(0, 255);
      if (r > 180 && g < 120 && b < 120) return AppSnackKind.error;
      if (r > 180 && g > 100 && b < 80) return AppSnackKind.warning;
      if (g > 140 && r < 120) return AppSnackKind.success;
    }
    final t = '$title $message';
    if (t.contains('خطأ') ||
        t.contains('فشل') ||
        t.contains('تعذر') ||
        t.contains('فشل')) {
      return AppSnackKind.error;
    }
    if (t.contains('تنبيه') || t.contains('يُرجى') || t.contains('يرجى')) {
      return AppSnackKind.warning;
    }
    if (t.contains('تم') ||
        t.contains('نجاح') ||
        t.contains('شكرا') ||
        t.contains('حفظ')) {
      return AppSnackKind.success;
    }
    return AppSnackKind.info;
  }

  static void _show({
    required String title,
    required String message,
    required AppSnackKind kind,
    Duration duration = const Duration(seconds: 3),
    Widget? action,
  }) {
    if (Get.isSnackbarOpen == true) {
      Get.closeCurrentSnackbar();
    }

    final style = _styleFor(kind);

    Get.rawSnackbar(
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.transparent,
      snackStyle: SnackStyle.FLOATING,
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: EdgeInsets.zero,
      borderRadius: 20,
      duration: duration,
      animationDuration: const Duration(milliseconds: 420),
      forwardAnimationCurve: Curves.easeOutCubic,
      reverseAnimationCurve: Curves.easeInCubic,
      isDismissible: true,
      dismissDirection: DismissDirection.up,
      overlayBlur: 0,
      messageText: _ModernSnackCard(
        title: title,
        message: message,
        style: style,
        action: action,
        duration: duration,
      ),
    );
  }

  static _SnackVisual _styleFor(AppSnackKind kind) {
    switch (kind) {
      case AppSnackKind.success:
        return const _SnackVisual(
          accent: Color(0xFF16A34A),
          soft: Color(0xFFDCFCE7),
          icon: Icons.check_circle_rounded,
        );
      case AppSnackKind.error:
        return const _SnackVisual(
          accent: Color(0xFFDC2626),
          soft: Color(0xFFFEE2E2),
          icon: Icons.error_rounded,
        );
      case AppSnackKind.warning:
        return const _SnackVisual(
          accent: Color(0xFFD97706),
          soft: Color(0xFFFEF3C7),
          icon: Icons.warning_amber_rounded,
        );
      case AppSnackKind.info:
        return const _SnackVisual(
          accent: _navy,
          soft: Color(0xFFFFF4CC),
          icon: Icons.notifications_active_rounded,
          useAmberIconBg: true,
        );
    }
  }
}

class _SnackVisual {
  const _SnackVisual({
    required this.accent,
    required this.soft,
    required this.icon,
    this.useAmberIconBg = false,
  });

  final Color accent;
  final Color soft;
  final IconData icon;
  final bool useAmberIconBg;
}

class _ModernSnackCard extends StatefulWidget {
  const _ModernSnackCard({
    required this.title,
    required this.message,
    required this.style,
    required this.duration,
    this.action,
  });

  final String title;
  final String message;
  final _SnackVisual style;
  final Duration duration;
  final Widget? action;

  @override
  State<_ModernSnackCard> createState() => _ModernSnackCardState();
}

class _ModernSnackCardState extends State<_ModernSnackCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bar;

  @override
  void initState() {
    super.initState();
    _bar = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.style;
    final iconBg = s.useAmberIconBg
        ? AppSnackBar._amber.withValues(alpha: 0.28)
        : s.soft;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: s.accent.withValues(alpha: 0.18),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppSnackBar._navy.withValues(alpha: 0.14),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: s.accent.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconBg,
                      border: Border.all(
                        color: s.accent.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Icon(s.icon, color: s.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: AppSnackBar._navy,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.message,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                            color: AppSnackBar._navy.withValues(alpha: 0.72),
                          ),
                        ),
                        if (widget.action != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: widget.action!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      if (Get.isSnackbarOpen == true) {
                        Get.closeCurrentSnackbar();
                      }
                    },
                    borderRadius: BorderRadius.circular(99),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppSnackBar._navy.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _bar,
              builder: (context, _) {
                return LinearProgressIndicator(
                  value: 1 - _bar.value,
                  minHeight: 3,
                  backgroundColor: s.soft.withValues(alpha: 0.55),
                  color: s.accent.withValues(alpha: 0.85),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
