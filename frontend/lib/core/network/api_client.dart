import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

class ApiClient {
  late final Dio dio;
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  ApiClient() {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(milliseconds: 1500),
        receiveTimeout: const Duration(milliseconds: 1500),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await storage.read(key: AppConstants.keyAccessToken);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          if (error.response?.statusCode == 401) {
            // Attempt token refresh
            final refreshToken = await storage.read(key: AppConstants.keyRefreshToken);
            if (refreshToken != null) {
              try {
                final refreshRes = await Dio().post(
                  '${AppConstants.apiBaseUrl}/auth/refresh',
                  data: {'refresh_token': refreshToken},
                );

                if (refreshRes.statusCode == 200) {
                  final newAccessToken = refreshRes.data['data']['accessToken'];
                  final newRefreshToken = refreshRes.data['data']['refreshToken'];
                  await storage.write(key: AppConstants.keyAccessToken, value: newAccessToken);
                  await storage.write(key: AppConstants.keyRefreshToken, value: newRefreshToken);

                  // Retry original request
                  error.requestOptions.headers['Authorization'] = 'Bearer $newAccessToken';
                  final clonedReq = await dio.request(
                    error.requestOptions.path,
                    options: Options(
                      method: error.requestOptions.method,
                      headers: error.requestOptions.headers,
                    ),
                    data: error.requestOptions.data,
                    queryParameters: error.requestOptions.queryParameters,
                  );
                  return handler.resolve(clonedReq);
                }
              } catch (_) {
                // Refresh failed; clear stored tokens
                await storage.deleteAll();
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }
}

final apiClient = ApiClient().dio;
