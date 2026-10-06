import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;

/// أيقونات الخريطة — تاكسي للسائق، شخص للراكب.
abstract final class MapMarkerIcons {
  static const _taxiAsset = 'assets/images/markers/driver_taxi.png';

  static gmaps.BitmapDescriptor? _driverTaxi;
  static gmaps.BitmapDescriptor? _passengerPerson;
  static gmaps.BitmapDescriptor? _destinationPin;
  static bool _ready = false;

  static bool get isReady => _ready;

  static Future<void> ensureLoaded() async {
    if (_ready) return;

    _driverTaxi = await gmaps.BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(34, 48), devicePixelRatio: 2.5),
      _taxiAsset,
    );
    _passengerPerson = await _buildPersonIcon();
    _destinationPin = await _buildDestinationIcon();
    _ready = true;
  }

  /// موقع السائق (شاشة السائق + تتبع الراكب للسائق).
  static gmaps.BitmapDescriptor get driver => _driverTaxi ?? _fallbackTaxi;

  /// السائق في الطريق — نفس صورة التاكسي.
  static gmaps.BitmapDescriptor get taxi => _driverTaxi ?? _fallbackTaxi;

  /// موقع الراكب / شخص.
  static gmaps.BitmapDescriptor get passenger =>
      _passengerPerson ?? _fallbackPassenger;

  static gmaps.BitmapDescriptor get pickup =>
      gmaps.BitmapDescriptor.defaultMarkerWithHue(
        gmaps.BitmapDescriptor.hueGreen,
      );

  static gmaps.BitmapDescriptor get destination =>
      _destinationPin ??
      gmaps.BitmapDescriptor.defaultMarkerWithHue(
        gmaps.BitmapDescriptor.hueAzure,
      );

  static gmaps.BitmapDescriptor get sos =>
      gmaps.BitmapDescriptor.defaultMarkerWithHue(
        gmaps.BitmapDescriptor.hueYellow,
      );

  static final gmaps.BitmapDescriptor _fallbackTaxi =
      gmaps.BitmapDescriptor.defaultMarkerWithHue(
        gmaps.BitmapDescriptor.hueOrange,
      );

  static final gmaps.BitmapDescriptor _fallbackPassenger =
      gmaps.BitmapDescriptor.defaultMarkerWithHue(
        gmaps.BitmapDescriptor.hueRose,
      );

  static Future<gmaps.BitmapDescriptor> _buildPersonIcon() async {
    const size = 44.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);

    canvas.drawCircle(
      center + const Offset(0, 2),
      size * 0.38,
      Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.drawCircle(
      center,
      size * 0.38,
      Paint()..color = const Color(0xFF11215B),
    );

    canvas.drawCircle(
      center,
      size * 0.34,
      Paint()..color = const Color(0xFFFFC107),
    );

    const icon = Icons.person_rounded;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: 22,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: const Color(0xFF11215B),
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2 - 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return gmaps.BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  static Future<gmaps.BitmapDescriptor> _buildDestinationIcon() async {
    const w = 88.0;
    const h = 118.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const navy = Color(0xFF11215B);
    const gold = Color(0xFFFFC107);
    const tipY = h - 10;
    const head = Offset(w / 2, 40);

    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(w / 2, tipY + 2),
        width: 30,
        height: 11,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.32),
    );

    final pin = Path()
      ..moveTo(head.dx, tipY)
      ..quadraticBezierTo(head.dx - 34, head.dy + 18, head.dx - 30, head.dy)
      ..arcToPoint(
        Offset(head.dx + 30, head.dy),
        radius: const Radius.circular(30),
        clockwise: true,
      )
      ..quadraticBezierTo(head.dx + 34, head.dy + 18, head.dx, tipY)
      ..close();

    canvas.drawPath(pin, Paint()..color = navy);
    canvas.drawPath(
      pin,
      Paint()
        ..color = gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2,
    );
    canvas.drawCircle(head, 18, Paint()..color = gold);
    canvas.drawCircle(head, 14.5, Paint()..color = Colors.white);

    const icon = Icons.place_rounded;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: 22,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: navy,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(head.dx - textPainter.width / 2, head.dy - textPainter.height / 2 - 1),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), h.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return gmaps.BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }
}
