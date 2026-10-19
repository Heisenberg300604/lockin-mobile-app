/// Authenticated HTTP access to the deployed LockIn API.
library;

import 'dart:async';

import 'package:dio/dio.dart';

/// A backend failure in a form that is safe to display in the UI.
class ApiException implements Exception {
  const ApiException({required this.statusCode, required this.message});

  final int? statusCode;
  final String message;

  @override
  String toString() => message;
}

/// Fetches a fresh Clerk token for every request and retries transient API
/// failures once. Tokens are never persisted here.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this._tokenProvider,
    this._onUnauthorized,
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: baseUrl.replaceFirst(RegExp(r'/+$'), ''),
           connectTimeout: const Duration(seconds: 65),
           receiveTimeout: const Duration(seconds: 65),
           sendTimeout: const Duration(seconds: 65),
           headers: const {'Accept': 'application/json'},
         ),
       );

  final Dio _dio;
  final Future<String?> Function() _tokenProvider;
  final Future<void> Function()? _onUnauthorized;

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) =>
      _request('GET', path, queryParameters: queryParameters);

  Future<dynamic> post(String path, {Object? data}) =>
      _request('POST', path, data: data);

  Future<dynamic> patch(String path, {Object? data}) =>
      _request('PATCH', path, data: data);

  Future<void> delete(String path) async {
    await _request('DELETE', path);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final token = await _tokenProvider();
        if (token == null || token.isEmpty) {
          throw const ApiException(
            statusCode: 401,
            message: 'Please sign in again to continue.',
          );
        }
        final response = await _dio.request<dynamic>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: Options(
            method: method,
            contentType: data == null ? null : Headers.jsonContentType,
            headers: {'Authorization': 'Bearer $token'},
          ),
        );
        return response.data;
      } on ApiException {
        rethrow;
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        final retryable =
            status == 401 ||
            (status != null && status >= 500) ||
            _isTimeout(error);
        if (attempt == 0 && retryable) continue;
        if (status == 401) {
          await _onUnauthorized?.call();
        }
        throw _asApiException(error);
      } on TimeoutException {
        if (attempt == 0) continue;
        throw const ApiException(
          statusCode: null,
          message: 'The server took too long to respond. Please try again.',
        );
      } catch (_) {
        throw const ApiException(
          statusCode: null,
          message: 'Could not reach LockIn. Check your connection and retry.',
        );
      }
    }
    throw const ApiException(
      statusCode: null,
      message: 'Could not reach LockIn. Please retry.',
    );
  }

  bool _isTimeout(DioException error) => switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => true,
    _ => false,
  };

  ApiException _asApiException(DioException error) {
    final body = error.response?.data;
    final rawMessage = body is Map ? body['message'] : null;
    final message = rawMessage is List
        ? rawMessage.map((item) => item.toString()).join('\n')
        : rawMessage is String && rawMessage.isNotEmpty
        ? rawMessage
        : error.response?.statusCode == 401
        ? 'Your session has expired. Please sign in again.'
        : 'Could not complete that request. Please retry.';
    return ApiException(
      statusCode: error.response?.statusCode,
      message: message,
    );
  }
}
