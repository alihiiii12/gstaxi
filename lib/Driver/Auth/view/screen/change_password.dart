import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controller/auth_controller.dart';
import '../../../../core/widgets/app_logo.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  bool _isPasswordVisible = false;
  final Color primaryYellow = const Color(0xFFFFC107);
  final Color darkCharcoal = const Color(0xFF212121);
  final DriverAuthController controller = Get.put(DriverAuthController());

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: primaryYellow,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFD54F), Color(0xFFFFC107), Color(0xFFFFA000)],
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              children: [
                const SizedBox(height: 100),

                // اللوغو
                const AppLogo(
                  heroTag: 'logo',
                  height: 150,
                ),

                const SizedBox(height: 40),

                Text(
                  "تعديل كلمة السر",
                  style: TextStyle(color: darkCharcoal, fontSize: 28, fontWeight: FontWeight.w900),
                ),

                const SizedBox(height: 50),

                // حقل كلمة السر
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: TextField(
                    controller: controller.passwordController,
                    textAlign: TextAlign.right,
                    obscureText: !_isPasswordVisible,
                    style: TextStyle(color: darkCharcoal, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: "كلمة السر الجديدة",
                      contentPadding: const EdgeInsets.all(20),
                      border: InputBorder.none,
                      suffixIcon: const Icon(Icons.lock_rounded, color: Colors.black26),
                      prefixIcon: IconButton(
                        icon: Icon(_isPasswordVisible ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                GestureDetector(
                  onTap: () {
                    controller.submitPassword();
                  },
                  child: Obx(() => Container(
                    width: double.infinity,
                    height: 58,
                    decoration: BoxDecoration(
                      color: darkCharcoal,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, 5))],
                    ),
                    child: Center(
                      child: controller.isLoading.value
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text("تغيير كلمة السر", style: TextStyle(color: Color(0xFFFFC107), fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}