import 'package:flutter/material.dart';

/// صورة السائق + صورة السيارة (أو أيقونة) + الاسم.
class DriverCustomerPreviewRow extends StatelessWidget {
  const DriverCustomerPreviewRow({
    super.key,
    required this.name,
    this.driverPhotoUrl,
    this.carPhotoUrl,
    this.subtitle,
    this.trailing,
    this.dense = false,
  });

  final String name;
  final String? driverPhotoUrl;
  final String? carPhotoUrl;
  final String? subtitle;
  final Widget? trailing;
  final bool dense;

  static bool _hasUrl(String? u) {
    if (u == null) return false;
    final t = u.trim();
    if (t.isEmpty) return false;
    final lower = t.toLowerCase();
    return lower != 'null' && lower != 'undefined';
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF11215B);
    const amber = Color(0xFFFFC107);
    final r = dense ? 22.0 : 28.0;
    final carW = dense ? 64.0 : 76.0;
    final carH = dense ? 48.0 : 56.0;

    Widget face() {
      final u = driverPhotoUrl?.trim();
      if (_hasUrl(u)) {
        return CircleAvatar(
          radius: r,
          backgroundColor: navy.withValues(alpha: 0.08),
          backgroundImage: NetworkImage(u!),
          onBackgroundImageError: (_, __) {},
        );
      }
      return CircleAvatar(
        radius: r,
        backgroundColor: navy.withValues(alpha: 0.10),
        child: Icon(
          Icons.person_rounded,
          size: dense ? 24 : 28,
          color: navy.withValues(alpha: 0.75),
        ),
      );
    }

    Widget carPlaceholder() {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              amber.withValues(alpha: 0.35),
              navy.withValues(alpha: 0.10),
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.local_taxi_rounded,
            color: navy,
            size: dense ? 26 : 30,
          ),
        ),
      );
    }

    Widget carBox() {
      final u = carPhotoUrl?.trim();
      return Container(
        width: carW,
        height: carH,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: navy.withValues(alpha: 0.14), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: navy.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: _hasUrl(u)
            ? Image.network(
                u!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => carPlaceholder(),
              )
            : carPlaceholder(),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        face(),
        SizedBox(width: dense ? 8 : 10),
        carBox(),
        SizedBox(width: dense ? 10 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: dense ? 14 : 15.5,
                  color: navy,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: dense ? 11.5 : 12.5,
                      color: navy.withValues(alpha: 0.65),
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
