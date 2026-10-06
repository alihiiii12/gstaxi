// import 'package:courses_qariba/feature/auth/model/user_model.dart';
// import 'package:get/get.dart';
//
// import '../network/api_endpoints.dart';
// import '../network/api_service.dart';
// import 'pagination_controller.dart';
//
// class ProductsController extends GetxController {
//   final pagination = PaginationController<UserModel>();
//
//   @override
//   void onInit() {
//     super.onInit();
//
//     pagination.init(
//       onFetch: (page) {
//         return ApiService.getPaginated<UserModel>(
//           endpoint: ApiEndpoints.login,
//           page: page,
//           fromJson: (json) => UserModel.fromJson(json),
//         );
//       },
//     );
//   }
//
// }
//
//
//
//
//
//
//
//
//
//
//
//
// // final c = Get.find<ProductsController>();
// //
// // Obx(() {
// // if (c.pagination.isLoading.value) {
// // return const Center(child: CircularProgressIndicator());
// // }
// //
// // return ListView.builder(
// // itemCount: c.pagination.items.length +
// // (c.pagination.hasMore.value ? 1 : 0),
// // itemBuilder: (context, index) {
// // if (index == c.pagination.items.length) {
// // c.pagination.fetch();
// // return const Center(
// // child: Padding(
// // padding: EdgeInsets.all(16),
// // child: CircularProgressIndicator(),
// // ),
// // );
// // }
// //
// // final item = c.pagination.items[index];
// // return ProductCard(item: item);
// // },
// // );
// // });
