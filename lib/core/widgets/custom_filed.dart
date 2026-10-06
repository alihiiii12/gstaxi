import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../constants/app_colors.dart';


class CustomFiled extends StatelessWidget {
  CustomFiled({
    super.key, required this.hint, required this.title,  this.isPass =false, this.onChanged
    ,this.controller });
  TextEditingController? controller;
  final String hint;
  final String title;
  final bool isPass ;
  final ValueChanged<String>? onChanged; // مهم
  @override
  Widget build(BuildContext context) {
    return Container(

      width: Get.width,
      margin: EdgeInsets.all(5),
      padding: EdgeInsets.symmetric(horizontal: 10,vertical: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,style: TextStyle(color: AppColors.Accent,fontSize: 15,fontWeight: FontWeight.w500),),
          SizedBox(height: 10,),
          Container(

            // margin: EdgeInsets.all(5),
            // padding: EdgeInsets.symmetric(horizontal: 25,vertical: 5),
            // height: Get.height *.06,
            decoration: BoxDecoration(
              color: AppColors.AccentLight,
// color: AppColor.primaryColor,
              borderRadius: BorderRadius.circular(15),
            ),
            child: TextField(
              controller: controller,
              cursorColor:AppColors.primaryColor,
              onChanged: onChanged,
              obscureText: isPass,
              decoration: InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 25),

                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(
                      color: AppColors.primaryColor,
                      width: 2,
                    ),
                  ),
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: TextStyle(color: AppColors.TextSecondray,fontSize: 14)
              ),
            ),
          ),
        ],
      ),
    );
  }
}
