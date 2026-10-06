import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomButton extends StatefulWidget {
  const CustomButton({
    super.key,
    required this.title,
    this.onTap,
    this.isWrite = true,
  });

  final bool isWrite;
  final String title;
  final void Function()? onTap;

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => isPressed = true),
      onTapUp: (_) => setState(() => isPressed = false),
      onTapCancel: () => setState(() => isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: Get.width,
        height: Get.height/14,
       // margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(

          color: const Color(0xff2563EA),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isPressed
              ? null
              : [

            BoxShadow(
              color: const Color(0xff2563EA).withOpacity(0.4),
              offset: const Offset(0, 8),
              blurRadius: 15,
            ),
          ],
        ),
        child: Center(
          child: Text(
            widget.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
      ),
    );
  }
}