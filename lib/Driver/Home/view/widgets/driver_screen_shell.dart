import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../Customer/view/widgets/customer_ui_theme.dart';

/// غلاف شاشات الفارس — خلفية وترويسة متناسقة مع التصميم الجديد.
class DriverScreenShell extends StatelessWidget {
  const DriverScreenShell({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bottom,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: CustomerUiTheme.screenGradient,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(14, top > 0 ? 4 : 8, 14, 0),
                child: Row(
                  children: [
                    _HeaderIconButton(
                      icon: Icons.arrow_forward_ios_rounded,
                      onTap: () => Get.back(),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: CustomerUiTheme.navy,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (actions != null && actions!.isNotEmpty)
                      Row(mainAxisSize: MainAxisSize.min, children: actions!)
                    else
                      const SizedBox(width: 46),
                  ],
                ),
              ),
              if (bottom != null) bottom!,
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class DriverHeaderIconButton extends StatelessWidget {
  const DriverHeaderIconButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CustomerUiTheme.navy.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: CustomerUiTheme.navy.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: CustomerUiTheme.navy, size: 20),
      ),
    );
  }
}

class _HeaderIconButton extends DriverHeaderIconButton {
  const _HeaderIconButton({required super.icon, required super.onTap});
}
