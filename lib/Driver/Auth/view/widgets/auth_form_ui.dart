import 'package:flutter/material.dart';

import '../../../../core/constants/app_button_dims.dart';
import '../../../../core/constants/app_sizes.dart';
import 'auth_ui.dart';

/// ألوان بطاقة المصادقة (دخول / إنشاء حساب / استعادة كلمة المرور).
class AuthPalette {
  AuthPalette._();

  static const Color hint = Color(0xFF8A8A8A);
  static const Color fieldFill = Color(0xFFF3F3F5);
  static const Color fieldBorder = Color(0xFFD8D8DC);
  static const Color link = Color(0xFF5D4A00);
}

/// البطاقة البيضاء التي تحتوي حقول المصادقة.
/// ارتفاعها يتناسب مع الشاشة، والمحتوى الزائد يصبح قابلاً للتمرير.
class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.children});

  /// ارتفاع مرجعي على شاشة التصميم.
  static const double heightDesign = 292;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final h = AppSizes.h(heightDesign).clamp(260.0, 340.0);
    return Container(
      width: double.infinity,
      height: h,
      padding: EdgeInsets.fromLTRB(
        AppSizes.w(18),
        AppSizes.h(18),
        AppSizes.w(18),
        AppSizes.h(14),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

class AuthCardTitle extends StatelessWidget {
  const AuthCardTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AuthUi.darkCharcoal,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AuthUi.darkCharcoal.withValues(alpha: 0.7),
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

/// حقل مدوّر الحواف بأيقونة على اليمين (RTL).
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.isPassword = false,
    this.keyboardType,
    this.prefixLabel,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final TextInputType? keyboardType;
  final String? prefixLabel;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppButtonDims.heightMd,
      decoration: BoxDecoration(
        color: AuthPalette.fieldFill,
        borderRadius: BorderRadius.circular(AppButtonDims.radius + 2),
        border: Border.all(color: AuthPalette.fieldBorder, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: TextField(
        controller: widget.controller,
        textAlign: TextAlign.right,
        textDirection: TextDirection.rtl,
        obscureText: widget.isPassword && !_visible,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        style: const TextStyle(
          color: AuthUi.darkCharcoal,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          filled: false,
          hintText: widget.hint,
          hintStyle: const TextStyle(
            color: AuthPalette.hint,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(widget.icon, color: AuthPalette.hint, size: 22),
          prefixText: widget.prefixLabel,
          prefixStyle: const TextStyle(
            color: AuthUi.darkCharcoal,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          suffixIcon: widget.isPassword
              ? IconButton(
                  icon: Icon(
                    _visible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AuthPalette.hint,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _visible = !_visible),
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 14,
          ),
        ),
      ),
    );
  }
}

/// زر أساسي بتدرّج أصفر.
class AuthGradientButton extends StatelessWidget {
  const AuthGradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: double.infinity,
          height: AppButtonDims.heightMd,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppButtonDims.radius + 2),
            gradient: const LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [
                Color(0xFFFFD54F),
                Color(0xFFFFC107),
                Color(0xFFFFA000),
              ],
            ),
          ),
          child: Center(
            child: loading
                ? SizedBox(
                    width: AppSizes.w(22),
                    height: AppSizes.w(22),
                    child: const CircularProgressIndicator(
                      color: AuthUi.darkCharcoal,
                      strokeWidth: 2.4,
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: AuthUi.darkCharcoal,
                      fontSize: AppSizes.sp(16),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class AuthTextLink extends StatelessWidget {
  const AuthTextLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: AuthPalette.link,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class AuthLinkRow extends StatelessWidget {
  const AuthLinkRow({
    super.key,
    required this.prefix,
    required this.action,
    required this.onTap,
  });

  final String prefix;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$prefix ',
          style: TextStyle(
            color: AuthUi.darkCharcoal.withValues(alpha: 0.7),
            fontSize: 13.5,
          ),
        ),
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Text(
              action,
              style: const TextStyle(
                color: AuthPalette.link,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
