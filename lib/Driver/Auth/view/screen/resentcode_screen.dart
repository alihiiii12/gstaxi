import 'package:flutter/material.dart';
import '../../../../core/constants/snack_bar.dart';
import 'package:get/get.dart';

class ResentCodeScreen extends StatefulWidget {
  const ResentCodeScreen({super.key});

  @override
  State<ResentCodeScreen> createState() => _ResentCodeScreenState();
}

class _ResentCodeScreenState extends State<ResentCodeScreen> {
  @override

  final Color primaryYellow = const Color(0xFFFFC107); // الأصفر الأساسي
  final Color darkCharcoal = const Color(0xFF212121); // الأسود الفحمي (بديل الكحلي)
  final Color lightAmber = const Color(0xFFFFF8E1);  // أصفر فاتح جداً للحقول

  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFD54F),
              Color(0xFFFFC107),
              Color(0xFFFFA000),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // زر العودة
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF11215B)),
                    onPressed: () => Get.back(),
                  ),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // أيقونة الرسالة المستلمة
                      Container(
                        padding: const EdgeInsets.all(25),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                        ),
                        child: const Icon(
                          Icons.mark_email_read_rounded,
                          size: 80,
                          color: Color(0xFF11215B),
                        ),
                      ),

                      const SizedBox(height: 40),

                      const Text(
                        "تحقق من الكود",
                        style: TextStyle(
                          color: Color(0xFF11215B),
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      const Text(
                        "أدخل الرمز المكون من 4 أرقام المرسل إلى\n 09xxxxxxxx",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF11215B),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                        ),
                      ),

                      const SizedBox(height: 50),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        textDirection: TextDirection.ltr,
                        children: [
                          _otpBox(first: true, last: false),
                          _otpBox(first: false, last: false),
                          _otpBox(first: false, last: false),
                          _otpBox(first: false, last: true),
                        ],
                      ),

                      const SizedBox(height: 40),

                      GestureDetector(
                        onTap: () {
                          AppSnackBar.notify("نجاح", "تم التحقق من الكود بنجاح",
                              backgroundColor: Colors.green, colorText: Colors.white);
                        },
                        child: Container(
                          width: double.infinity,
                          height: 60,
                          decoration: BoxDecoration(
                            color: darkCharcoal,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF11215B).withOpacity(0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              "تأكيد الرمز",
                              style: TextStyle(
                                color: primaryYellow,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 30),

                      // إعادة إرسال الكود
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () {},
                            child: const Text(
                              "إعادة الإرسال",
                              style: TextStyle(
                                color: Color(0xFF11215B),
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          const Text("لم يصلك الكود؟",
                              style: TextStyle(color: Color(0xFF11215B))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _otpBox({required bool first, last}) {
    return Container(
      height: 70,
      width: 60,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        autofocus: true,
        onChanged: (value) {
          if (value.length == 1 && last == false) {
            FocusScope.of(context).nextFocus();
          }
          if (value.isEmpty && first == false) {
            FocusScope.of(context).previousFocus();
          }
        },
        showCursor: false,
        readOnly: false,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF11215B)),
        keyboardType: TextInputType.number,
        maxLength: 1,
        decoration: const InputDecoration(
          counterText: "",
          border: InputBorder.none,
        ),
      ),
    );
  }
}
