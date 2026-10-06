import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import '../../localization/l.dart';
import '../../utils/validation_error.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.validate,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.enabled = true,
    this.prefixIcon,
    this.suffixIcon,
    this.inputFormatters,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValidationError? Function(String value) validate;
  final bool obscure;
  final TextInputType keyboardType;
  final bool enabled;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (_, value, __) {
        final ValidationError? error = validate(value.text);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
           Container(
             width: Get.width,
             height: Get.height/14,
             padding: EdgeInsets.fromLTRB(10, 3, 10, 3),

             decoration: BoxDecoration(
               borderRadius: BorderRadius.circular(20),
               color: Colors.white
             ),
             child: TextField(
               controller: controller,
               obscureText: obscure,
               keyboardType: keyboardType,
               enabled: enabled,
               inputFormatters: inputFormatters,
               onChanged: onChanged,
               style:  TextStyle(color: Color(0xFF1E293B)),
               decoration: InputDecoration(
                 hintText: hint,
                 hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                 prefixIcon: prefixIcon,
                 suffixIcon: suffixIcon,
                 contentPadding:  EdgeInsets.symmetric(horizontal: 25, vertical: 18),

                 border: InputBorder.none,
                 enabledBorder: InputBorder.none,
                 focusedBorder: InputBorder.none,
                 errorBorder: InputBorder.none,
               ),
             ),
           ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 20),
                child: Text(
                  L.validation(error),
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}