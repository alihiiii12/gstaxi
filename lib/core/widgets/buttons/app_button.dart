import 'package:flutter/material.dart';

import '../../utils/validation_error.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.text,
    required this.onTap,
    required this.controllers,
    required this.validators,
  }) : assert(
  controllers.length == validators.length,
  'Controllers count must match validators count',
  );

  final String text;
  final VoidCallback onTap;
  final List<TextEditingController> controllers;
  final List<ValidationError? Function(String)> validators;

  bool _isValid() {
    for (int i = 0; i < controllers.length; i++) {
      final error = validators[i](controllers[i].text);
      if (error != null) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(controllers),
      builder: (_, __) {
        final enabled = _isValid();

        return ElevatedButton(
          onPressed: enabled ? onTap : null,
          child: Text(text),
        );
      },
    );
  }
}
