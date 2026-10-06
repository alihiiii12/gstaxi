import 'dart:math';

import 'package:get_storage/get_storage.dart';

/// معرّف ثابت لهذا الهاتف — يُستخدم لمنع الدخول من جهازين مختلفين بنفس الحساب.
class DeviceSessionId {
  DeviceSessionId._();

  static const _key = 'device_session_id';

  static String get() {
    final box = GetStorage();
    final cached = box.read<String>(_key);
    if (cached != null && cached.trim().isNotEmpty) {
      return cached.trim();
    }

    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    box.write(_key, id);
    return id;
  }
}
