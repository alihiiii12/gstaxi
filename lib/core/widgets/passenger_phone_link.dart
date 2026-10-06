import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/phone_call_launcher.dart';

/// رقم هاتف قابل للضغط — يفتح تطبيق الاتصال فوراً.
class PassengerPhoneLink extends StatelessWidget {
  const PassengerPhoneLink({
    super.key,
    required this.phone,
    this.style,
    this.showIcon = true,
    this.iconSize = 17,
    this.padding = EdgeInsets.zero,
  });

  final String phone;
  final TextStyle? style;
  final bool showIcon;
  final double iconSize;
  final EdgeInsetsGeometry padding;

  void _onTap() {
    HapticFeedback.lightImpact();
    unawaited(launchPhoneCall(phone));
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ??
        const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF11215B),
          letterSpacing: 0.3,
          fontSize: 14,
        );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showIcon) ...[
                Icon(
                  Icons.phone_in_talk_outlined,
                  size: iconSize,
                  color: baseStyle.color ?? const Color(0xFF11215B),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: baseStyle.copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: (baseStyle.color ?? const Color(0xFF11215B))
                        .withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
