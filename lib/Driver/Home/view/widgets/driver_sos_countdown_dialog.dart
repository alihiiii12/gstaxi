import 'package:flutter/material.dart';

import '../../../../core/widgets/sos_countdown_dialog.dart';

/// عدّ تنازلي 15 ثانية ثم إرسال SOS (واجهة السائق — نفس المنطق المشترك).
class DriverSosCountdownDialog extends StatelessWidget {
  const DriverSosCountdownDialog({super.key, required this.onSend});

  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return SosCountdownDialog(onSend: onSend);
  }
}
