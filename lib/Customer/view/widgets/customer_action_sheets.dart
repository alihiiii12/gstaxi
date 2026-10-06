import 'package:flutter/material.dart';

import '../../../core/theme/app_text_style.dart';
import 'customer_ui_theme.dart';

/// نتيجة نافذة الإلغاء (مع سبب اختياري).
class CustomerCancelPromptResult {
  const CustomerCancelPromptResult({required this.confirmed, this.reason = ''});

  final bool confirmed;
  final String reason;
}

/// نوافذ تأكيد/إلغاء بتصميم زجاجي كهرماني-كحلي (بدل AlertDialog الافتراضي).
abstract final class CustomerActionSheets {
  CustomerActionSheets._();

  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'تأكيد',
    String cancelLabel = 'رجوع',
    bool destructive = false,
    IconData icon = Icons.help_outline_rounded,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CustomerUiTheme.navy.withValues(alpha: 0.55),
      builder: (ctx) {
        final bottom = MediaQuery.viewPaddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(14, 0, 14, 12 + bottom),
          child: _SheetCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 6),
                _IconBadge(
                  icon: icon,
                  destructive: destructive,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: CustomerUiTheme.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    height: 1.5,
                    color: CustomerUiTheme.navy.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _GhostButton(
                        label: cancelLabel,
                        onTap: () => Navigator.pop(ctx, false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PrimaryButton(
                        label: confirmLabel,
                        destructive: destructive,
                        onTap: () => Navigator.pop(ctx, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// إلغاء مع سبب اختياري — تصميم بطاقة سفلية.
  static Future<CustomerCancelPromptResult?> cancelWithReason(
    BuildContext context, {
    String title = 'إلغاء الطلب',
    String message = 'اذكر سبب الإلغاء إن رغبت (اختياري).',
    String confirmLabel = 'إلغاء الطلب',
    String cancelLabel = 'رجوع',
    bool reasonRequired = false,
  }) {
    return showModalBottomSheet<CustomerCancelPromptResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: CustomerUiTheme.navy.withValues(alpha: 0.55),
      builder: (ctx) {
        final reasonC = TextEditingController();
        final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
        final bottomPad = MediaQuery.viewPaddingOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            0,
            14,
            12 + bottomPad + bottomInset,
          ),
          child: _SheetCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 6),
                const _IconBadge(
                  icon: Icons.cancel_outlined,
                  destructive: true,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: CustomerUiTheme.navy,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    height: 1.5,
                    color: CustomerUiTheme.navy.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonC,
                  maxLines: 3,
                  minLines: 2,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontWeight: FontWeight.w600,
                    color: CustomerUiTheme.navy,
                  ),
                  decoration: InputDecoration(
                    hintText: 'مثال: تغيّر الموعد، انتظرت طويلاً…',
                    hintStyle: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: CustomerUiTheme.muted.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w400,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF3F5FA),
                    contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: CustomerUiTheme.navy.withValues(alpha: 0.08),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: CustomerUiTheme.navy.withValues(alpha: 0.08),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: CustomerUiTheme.amber,
                        width: 1.6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _GhostButton(
                        label: cancelLabel,
                        onTap: () => Navigator.pop(ctx),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PrimaryButton(
                        label: confirmLabel,
                        destructive: true,
                        onTap: () {
                          final reason = reasonC.text.trim();
                          if (reasonRequired && reason.isEmpty) return;
                          Navigator.pop(
                            ctx,
                            CustomerCancelPromptResult(
                              confirmed: true,
                              reason: reason,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> showBusy(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: CustomerUiTheme.navy.withValues(alpha: 0.45),
      builder: (_) => Center(
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: CustomerUiTheme.navy.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Center(
            child: SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: CustomerUiTheme.navy,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetCard extends StatelessWidget {
  const _SheetCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: CustomerUiTheme.amber.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: CustomerUiTheme.navy.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 4,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: CustomerUiTheme.navy.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, this.destructive = false});

  final IconData icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final bg = destructive
        ? const Color(0xFFFFEBEE)
        : CustomerUiTheme.amber.withValues(alpha: 0.22);
    final fg = destructive ? const Color(0xFFC62828) : CustomerUiTheme.navy;
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(
          color: destructive
              ? const Color(0xFFE57373).withValues(alpha: 0.45)
              : CustomerUiTheme.amber.withValues(alpha: 0.55),
        ),
      ),
      child: Icon(icon, color: fg, size: 28),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: destructive
                  ? const [Color(0xFFE53935), Color(0xFFC62828)]
                  : const [
                      Color(0xFFFFD54F),
                      CustomerUiTheme.amber,
                      Color(0xFFFFA000),
                    ],
            ),
            boxShadow: [
              BoxShadow(
                color: (destructive
                        ? const Color(0xFFE53935)
                        : CustomerUiTheme.amber)
                    .withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: destructive ? Colors.white : CustomerUiTheme.navy,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFFF3F5FA),
            border: Border.all(
              color: CustomerUiTheme.navy.withValues(alpha: 0.08),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: CustomerUiTheme.navy,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
