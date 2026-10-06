import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_images.dart';
import '../../../../core/routes/splash_login_transition.dart';
import '../../../../core/services/auth_restore_service.dart';
import '../../../../core/services/startup_gates.dart';
import '../../../../core/widgets/app_logo.dart';
import '../widgets/auth_scene_background.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  bool _navigated = false;
  bool _gatesPassed = false;
  bool _exitReady = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack),
      ),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.28, curve: Curves.easeOut),
      ),
    );

    _controller.addStatusListener(_onAnimationStatus);
    _controller.forward();
    _runStartupChecks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage(AppImages.splashBg), context);
    precacheImage(const AssetImage(AppImages.logo), context);
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _exitReady = true;
      _goNext();
    }
  }

  Future<void> _runStartupChecks() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted || _navigated) return;

    final blocked = await StartupGates.blockIfNeeded(context);
    if (!mounted || blocked) return;

    _gatesPassed = true;
    _goNext();
  }

  void _goNext() {
    if (_navigated || !mounted || !_gatesPassed || !_exitReady) return;
    _navigated = true;

    if (!AuthRestoreService.hasSession) {
      SplashLoginTransition.open(context);
      return;
    }

    AuthRestoreService.restoreAndNavigate();
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logoWidth = SplashLoginTransition.splashLogoWidth(context);

    return Scaffold(
      backgroundColor: AuthSceneBackground.fillColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuthSceneBackground(),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: child,
                  ),
                );
              },
              child: AppLogo(
                heroTag: SplashLoginTransition.heroTag,
                width: logoWidth,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
