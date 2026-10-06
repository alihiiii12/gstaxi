import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:get/get_navigation/src/root/get_material_app.dart';
import 'package:get_storage/get_storage.dart';
import 'package:syriataxi/Driver/Auth/view/screen/splash_screen.dart';
import 'package:syriataxi/Driver/Home/service/driver_keepalive_service.dart';

import 'core/constants/app_sizes.dart';
import 'core/maps/map_marker_icons.dart';
import 'core/network/network_status_service.dart';
import 'core/widgets/network_status_banner.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/secure_auth_token.dart';
import 'core/services/storage_service.dart';
import 'core/utils/app_alert_sound.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();

  await StorageService.init();
  await SecureAuthToken.init();
  await DriverKeepaliveService.init();

  if (DefaultFirebaseOptions.isConfigured) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  await PushNotificationService.instance.init();
  await AppAlertSound.ensureInitialized();
  await MapMarkerIcons.ensureLoaded();
  NetworkStatusService.instance.start();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) {
        AppSizes.init(context);
        final mq = MediaQuery.of(context);
        // يمنع تضخّم/تصغير الواجهة بسبب إعدادات خط النظام على أجهزة مختلفة.
        final scaler = mq.textScaler.clamp(
          minScaleFactor: 0.90,
          maxScaleFactor: 1.15,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: scaler),
          child: NetworkStatusBanner(child: child ?? const SizedBox.shrink()),
        );
      },
      home: SplashScreen(),
    );
  }
}

