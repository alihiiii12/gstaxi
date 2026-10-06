import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../../../Customer/view/widgets/customer_ui_theme.dart';
import '../../../../core/services/account_deletion_service.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../Auth/auth_session.dart';
import '../../../Home/controller/driver_location_controller.dart';
import '../../../Order/view/screen/order_screen.dart';
import '../../../Order_history/view/screen/order_history.dart';
import '../../../Profile/view/screen/profile.dart';
import '../../../Wallet/view/screen/driver_wallet_screen.dart';

/// قائمة جانبية حديثة للفارس — متناسقة مع واجهة الراكب.
class DriverDrawer extends StatelessWidget {
  const DriverDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final box = GetStorage();
    final uid = box.read('user_id')?.toString() ?? '';
    final phone = box.read('user_number')?.toString() ?? '';
    final top = MediaQuery.paddingOf(context).top;

    return Drawer(
      elevation: 0,
      width: MediaQuery.sizeOf(context).width * 0.82,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          bottomLeft: Radius.circular(32),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(32),
          bottomLeft: Radius.circular(32),
        ),
        child: DecoratedBox(
          decoration: CustomerUiTheme.screenGradient,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: top + 12),
              _HeaderCard(userId: uid, phone: phone),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  children: [
                    _NavTile(
                      icon: Icons.person_outline_rounded,
                      label: 'الملف الشخصي',
                      tint: CustomerUiTheme.amber,
                      onTap: () {
                        Navigator.pop(context);
                        Get.to(() => const ProfileScreen());
                      },
                    ),
                    const SizedBox(height: 10),
                    _NavTile(
                      icon: Icons.receipt_long_rounded,
                      label: 'الطلبات',
                      tint: const Color(0xFF60A5FA),
                      onTap: () {
                        Navigator.pop(context);
                        Get.to(() => const OrderScreen());
                      },
                    ),
                    const SizedBox(height: 10),
                    _NavTile(
                      icon: Icons.history_rounded,
                      label: 'سجل الرحلات',
                      tint: CustomerUiTheme.navy,
                      onTap: () {
                        Navigator.pop(context);
                        Get.to(() => const OrderHistoryScreen());
                      },
                    ),
                    const SizedBox(height: 10),
                    _NavTile(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'المحفظة',
                      tint: const Color(0xFF34D399),
                      onTap: () {
                        Navigator.pop(context);
                        Get.to(() => const DriverWalletScreen());
                      },
                    ),
                    const SizedBox(height: 18),
                    _NavTile(
                      icon: Icons.privacy_tip_outlined,
                      label: 'سياسة الخصوصية',
                      tint: CustomerUiTheme.muted,
                      compact: true,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        AccountDeletionService.openPrivacyPolicy();
                      },
                    ),
                    const SizedBox(height: 8),
                    _NavTile(
                      icon: Icons.delete_outline_rounded,
                      label: 'حذف الحساب',
                      tint: const Color(0xFFEF4444),
                      danger: true,
                      compact: true,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        AccountDeletionService.confirmAndDeleteAccount(context);
                      },
                    ),
                    const SizedBox(height: 8),
                    _NavTile(
                      icon: Icons.logout_rounded,
                      label: 'تسجيل الخروج',
                      tint: const Color(0xFFEF4444),
                      danger: true,
                      compact: true,
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                        await AuthSession.signOut();
                        if (Get.isRegistered<DriverController>()) {
                          Get.delete<DriverController>(force: true);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const _DrawerFooter(),
              SizedBox(height: MediaQuery.paddingOf(context).bottom + 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.userId, required this.phone});

  final String userId;
  final String phone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        decoration: CustomerUiTheme.glassCard(radius: 24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: CustomerUiTheme.navy.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const AppLogo(heroTag: 'driver-drawer-logo', height: 64),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: CustomerUiTheme.amber.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'حساب الفارس',
                style: TextStyle(
                  color: CustomerUiTheme.navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (userId.isNotEmpty || phone.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (userId.isNotEmpty)
                    _InfoChip(
                      icon: Icons.badge_outlined,
                      label: 'المعرّف: $userId',
                    ),
                  if (phone.trim().isNotEmpty)
                    _InfoChip(
                      icon: Icons.phone_android_rounded,
                      label: phone,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CustomerUiTheme.navy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: CustomerUiTheme.navy.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: CustomerUiTheme.navy.withValues(alpha: 0.85),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
    this.danger = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;
  final bool danger;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        splashColor: CustomerUiTheme.navy.withValues(alpha: 0.06),
        child: Ink(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 16,
            vertical: compact ? 12 : 14,
          ),
          decoration: BoxDecoration(
            color: danger
                ? const Color(0xFFFEE2E2).withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(compact ? 16 : 20),
            border: Border.all(
              color: danger
                  ? const Color(0xFFEF4444).withValues(alpha: 0.18)
                  : CustomerUiTheme.navy.withValues(alpha: 0.07),
            ),
            boxShadow: compact
                ? null
                : [
                    BoxShadow(
                      color: CustomerUiTheme.navy.withValues(alpha: 0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 38 : 44,
                height: compact ? 38 : 44,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: danger ? 0.14 : 0.16),
                  borderRadius: BorderRadius.circular(compact ? 12 : 14),
                ),
                child: Icon(
                  icon,
                  color: danger ? const Color(0xFFDC2626) : tint,
                  size: compact ? 20 : 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: danger
                        ? const Color(0xFFB91C1C)
                        : CustomerUiTheme.navy,
                    fontSize: compact ? 14 : 15,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_left_rounded,
                color: (danger ? const Color(0xFFDC2626) : CustomerUiTheme.navy)
                    .withValues(alpha: 0.35),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: CustomerUiTheme.navy.withValues(alpha: 0.06),
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'GS TAXI',
                  style: TextStyle(
                    color: CustomerUiTheme.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'بوابتك لعالم التوصيل الذكي',
                  style: TextStyle(
                    color: CustomerUiTheme.muted.withValues(alpha: 0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'إصدار 1.0.0',
                  style: TextStyle(
                    color: CustomerUiTheme.muted.withValues(alpha: 0.55),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
