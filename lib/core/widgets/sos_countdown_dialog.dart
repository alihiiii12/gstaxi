import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/app_alert_sound.dart';

/// عدّ تنازلي 15 ثانية ثم إرسال SOS (سائق أو راكب).
class SosCountdownDialog extends StatefulWidget {
  const SosCountdownDialog({super.key, required this.onSend});

  final Future<void> Function() onSend;

  @override
  State<SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends State<SosCountdownDialog> {
  static const int _startSec = 15;

  int _remaining = _startSec;
  Timer? _timer;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _fired) return;
      if (_remaining <= 1) {
        _timer?.cancel();
        unawaited(_commitSend());
        return;
      }
      setState(() => _remaining--);
    });
  }

  Future<void> _commitSend() async {
    if (_fired || !mounted) return;
    _fired = true;
    _timer?.cancel();
    try {
      await AppAlertSound.playSosDangerHorn();
      await widget.onSend();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _cancel() {
    if (_fired) return;
    _fired = true;
    _timer?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تنبيه طوارئ SOS'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'عند انتهاء العد التنازلي يُرسل تنبيه إلى لوحة التحكم مع موقعك الحالي. '
            'اضغط «إلغاء» إن كان الأمر خطأً.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            '$_remaining',
            style: const TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w800,
              color: Colors.red,
            ),
          ),
          const Text('ثانية', style: TextStyle(color: Colors.black54)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _cancel,
          child: const Text('إلغاء'),
        ),
      ],
    );
  }
}
