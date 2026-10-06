import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../constants/app_sizes.dart';

import '../constants/error_model.dart';
import 'helpers.dart';

/// =========================
/// 🔢 NUM EXTENSIONS
/// =========================

extension NumSizeX on num {
  /// Height (responsive)
  double get h => AppSizes.h(toDouble());

  /// Width (responsive)
  double get w => AppSizes.w(toDouble());

  /// Font size (responsive)
  double get sp => AppSizes.sp(toDouble());

  /// Vertical Spacer
  SizedBox get vSpace => SizedBox(height: h);

  /// Horizontal Spacer
  SizedBox get hSpace => SizedBox(width: w);

  /// Padding all
  EdgeInsets get pa => EdgeInsets.all(w);

  /// Padding horizontal
  EdgeInsets get ph => EdgeInsets.symmetric(horizontal: w);

  /// Padding vertical
  EdgeInsets get pv => EdgeInsets.symmetric(vertical: h);
}

/// =========================
/// 📐 EDGE INSETS EXTENSIONS
/// =========================

extension PaddingX on Widget {
  /// Padding all
  Widget pAll(double value) =>
      Padding(padding: value.pa, child: this);

  /// Padding horizontal
  Widget pH(double value) =>
      Padding(padding: value.ph, child: this);

  /// Padding vertical
  Widget pV(double value) =>
      Padding(padding: value.pv, child: this);

  /// Custom padding
  Widget pOnly({
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) =>
      Padding(
        padding: EdgeInsets.only(
          top: top?.h ?? 0,
          bottom: bottom?.h ?? 0,
          left: left?.w ?? 0,
          right: right?.w ?? 0,
        ),
        child: this,
      );
}

/// =========================
/// 🧾 STRING EXTENSIONS
/// =========================

extension StringLocalizationX on String {
  /// Localization shortcut
  String get l => tr;

  /// Capitalize first letter
  String get capitalize =>
      isEmpty ? this : this[0].toUpperCase() + substring(1);

  /// Check email
  bool get isEmail =>
      RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
          .hasMatch(this);

  /// Check phone
  bool get isPhone =>
      RegExp(r'^\+?[0-9]{7,15}$').hasMatch(this);
}

/// =========================
/// 📦 CONTEXT EXTENSIONS
/// =========================

extension ContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => theme.textTheme;
  ColorScheme get colors => theme.colorScheme;

  double get width => MediaQuery.of(this).size.width;
  double get height => MediaQuery.of(this).size.height;

  bool get isDark =>
      theme.brightness == Brightness.dark;
}

/// =========================
/// 🔔 SNACKBAR EXTENSIONS
/// =========================

extension SnackbarX on String {
  void successSnack() =>
      AppHelpers.successSnack(this);

  void errorSnack() =>
      AppHelpers.errorSnack(this);
}

/// =========================
/// 📋 LIST EXTENSIONS
/// =========================

extension ListX<T> on List<T> {
  /// Safe first
  T? get firstOrNull =>
      isNotEmpty ? first : null;

  /// Safe last
  T? get lastOrNull =>
      isNotEmpty ? last : null;
}

/// =========================
/// 🧠 RX EXTENSIONS
/// =========================

extension RxX<T> on Rx<T> {
  /// Update value easily
  void updateValue(T value) => this.value = value;
}


extension EitherHandler<T> on Either<ErrorModel, T> {
  void handle({
    required void Function(T data) onSuccess,
    String? successMessage,
    void Function(ErrorModel error)? onError,
  }) {
    fold(
          (error) {
        if (onError != null) {
          onError(error);
        } else {
          AppHelpers.errorSnack(error.message);
        }
      },
          (data) {
        if (successMessage != null) {
          AppHelpers.successSnack(successMessage);
        }
        onSuccess(data);
      },
    );
  }
}
