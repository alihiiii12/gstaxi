//
// import '../network/api_exceptions.dart';
// import '../network/api_response.dart';
//
// abstract class BaseRepository {
//   ApiResult<T> handleRequest<T>(Future<T> Function() request) async {
//     try {
//       final result = await request();
//       return ApiResult.success(result);
//     } on ApiException catch (e) {
//       return ApiResult.failure(e.message);
//     } catch (_) {
//       return ApiResult.failure('Unexpected error');
//     }
//   }
// }
