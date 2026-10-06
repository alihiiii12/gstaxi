import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/storage_service.dart';
import 'app_route.dart';

/// =========================
/// 🔐 Auth Middleware
/// =========================
class AuthMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    if (!StorageService.isLoggedIn) {
      return const RouteSettings(name: AppRoutes.login);
    }
    return null;
  }
}

/// =========================
/// 👤 Guest Middleware
/// =========================
class GuestMiddleware extends GetMiddleware {
  @override
  RouteSettings? redirect(String? route) {
    if (StorageService.isLoggedIn) {
      return const RouteSettings(name: AppRoutes.home);
    }
    return null;
  }
}
