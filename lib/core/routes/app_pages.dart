// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
//
// import '../../feature/auth/view/screens/login_screen.dart';
// import '../../feature/home/view/screens/home_screen.dart';
// import 'app_middlewares.dart';
// import 'app_route.dart';
//
// class AppPages {
//   AppPages._();
//
//   static final pages = <GetPage>[
//     /// =========================
//     /// SPLASH
//     /// =========================
//     GetPage(
//       name: AppRoutes.splash,
//       page: () => const SizedBox(), // لاحقًا SplashScreen
//     ),
//
//     /// =========================
//     /// LOGIN (Guest only)
//     /// =========================
//     GetPage(
//       name: AppRoutes.login,
//       page: () => Login(),
//       middlewares: [GuestMiddleware()],
//     ),
//
//     /// =========================
//     /// HOME (Auth only)
//     /// =========================
//     GetPage(
//       name: AppRoutes.home,
//       page: () => HomeScreen(),
//       middlewares: [AuthMiddleware()],
//     ),
//
//     /// =========================
//     /// PROFILE (Auth only)
//     /// =========================
//     GetPage(
//       name: AppRoutes.profile,
//       page: () => HomeScreen(),
//       middlewares: [AuthMiddleware()],
//     ),
//   ];
// }
