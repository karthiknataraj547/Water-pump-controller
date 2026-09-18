import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

class ApiClient {
  late final Dio dio;
  final FlutterSecureStorage storage = const FlutterSecureStorage();

  ApiClient() {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.activeApiBaseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Strictly enforce production cloud API base URL (No local host overrides)
          AppConstants.activeApiBaseUrl = AppConstants.cloudApiBaseUrl;
          await storage.delete(key: AppConstants.keyCustomApiBaseUrl);
          options.baseUrl = AppConstants.cloudApiBaseUrl;
          if (options.path.startsWith('/') && options.baseUrl.endsWith('/api/v1')) {
            options.path = '/api/v1${options.path}';
            options.baseUrl = options.baseUrl.substring(0, options.baseUrl.length - 7);
          }

          final token = await storage.read(key: AppConstants.keyAccessToken);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          // Handle 401 Unauthorized token refresh
          if (error.response?.statusCode == 401) {
            final refreshToken = await storage.read(key: AppConstants.keyRefreshToken);
            if (refreshToken != null && refreshToken.isNotEmpty) {
              try {
                final refreshRes = await Dio().post(
                  '${AppConstants.activeApiBaseUrl}/auth/refresh',
                  data: {'refresh_token': refreshToken},
                  options: Options(headers: {'Content-Type': 'application/json'}),
                );

                if (refreshRes.statusCode == 200 && refreshRes.data != null) {
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
                // If refresh token is explicitly rejected by the server, clear only auth tokens
                // Keep device ID and preferences intact
                await storage.delete(key: AppConstants.keyAccessToken);
                await storage.delete(key: AppConstants.keyRefreshToken);
              }
            }
          }

          // Handle 429 Rate Limit response
          if (error.response?.statusCode == 429) {
            final retryAfter = error.response?.headers.value('retry-after') ?? '30';
            error = error.copyWith(
              message: 'Rate limit exceeded. Please wait $retryAfter seconds before retrying.',
            );
          }

          return handler.next(error);
        },
      ),
    );
  }
}

final apiClient = ApiClient().dio;
