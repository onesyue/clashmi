// ignore_for_file: empty_catches

import 'dart:convert';
import 'dart:io';

import 'package:clashmi/app/runtime/return_result.dart';
import 'package:clashmi/app/utils/log.dart';

/// XBoard 面板 API 工具类
/// 对接 https://github.com/cedar2025/Xboard
abstract final class XBoardApi {
  /// 从 XBoard 面板获取订阅链接
  /// [baseUrl]  面板地址，如 https://my.yue.to
  /// [authData] WebView localStorage 中读取的 auth_data token
  static Future<ReturnResult<String>> getSubscribeUrl(
    String baseUrl,
    String authData,
  ) async {
    baseUrl = baseUrl.trimRight();
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final url = '$baseUrl/api/v1/user/getSubscribe';
    Log.d('XBoardApi.getSubscribeUrl: $url');
    var client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.parse(url);
      HttpClientRequest request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      // XBoard 使用 Authorization header 传递 token
      request.headers.set('Authorization', authData);
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await response.transform(utf8.decoder).join();
      Log.d('XBoardApi.getSubscribeUrl status=${response.statusCode} body=$body');
      if (response.statusCode != 200) {
        return ReturnResult(
          error: ReturnResultError(
            '获取订阅失败，服务器返回: ${response.statusCode}',
          ),
        );
      }
      final json = jsonDecode(body);
      // XBoard 响应格式: {"data":{"subscribe_url":"..."},"message":"..."}
      final subscribeUrl =
          json?['data']?['subscribe_url'] as String? ??
          json?['data']?['subscribe_url']?.toString();
      if (subscribeUrl == null || subscribeUrl.isEmpty) {
        return ReturnResult(
          error: ReturnResultError('未获取到订阅链接，请确认已购买套餐'),
        );
      }
      return ReturnResult(data: subscribeUrl);
    } catch (e) {
      Log.w('XBoardApi.getSubscribeUrl exception: $e');
      return ReturnResult(error: ReturnResultError('网络请求异常: $e'));
    } finally {
      client.close(force: true);
    }
  }

  /// 获取用户订阅信息（流量、过期时间等）
  /// 返回完整 data 字段 JSON 字符串
  static Future<ReturnResult<Map<String, dynamic>>> getUserInfo(
    String baseUrl,
    String authData,
  ) async {
    baseUrl = baseUrl.trimRight();
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    final url = '$baseUrl/api/v1/user/info';
    var client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.parse(url);
      HttpClientRequest request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('Authorization', authData);
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        return ReturnResult(
          error: ReturnResultError('获取用户信息失败: ${response.statusCode}'),
        );
      }
      final json = jsonDecode(body);
      final data = json?['data'] as Map<String, dynamic>?;
      if (data == null) {
        return ReturnResult(error: ReturnResultError('用户信息为空'));
      }
      return ReturnResult(data: data);
    } catch (e) {
      Log.w('XBoardApi.getUserInfo exception: $e');
      return ReturnResult(error: ReturnResultError('网络请求异常: $e'));
    } finally {
      client.close(force: true);
    }
  }
}
