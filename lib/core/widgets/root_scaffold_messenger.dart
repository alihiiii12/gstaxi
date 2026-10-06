import 'package:flutter/material.dart';

/// مفتاح عالمي لعرض SnackBar بأمان من أي مكان (بما فيها GetX بدون context).
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
