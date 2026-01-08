import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/skip_config.dart';
import 'user_data_service.dart';

/// 片头片尾跳过配置服务
class SkipConfigService {
  static const Duration _timeout = Duration(seconds: 15);

  /// 获取跳过配置
  /// [source] 视频源
  /// [id] 视频ID
  static Future<EpisodeSkipConfig?> getSkipConfig({
    required String source,
    required String id,
  }) async {
    try {
      final baseUrl = await UserDataService.getServerUrl();
      if (baseUrl == null) {
        debugPrint('[跳过配置] 服务器地址未配置');
        return null;
      }

      final cookies = await UserDataService.getCookies();
      final key = '$source+$id';

      final uri = Uri.parse('$baseUrl/api/skipconfigs');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
        body: json.encode({
          'action': 'get',
          'key': key,
        }),
      ).timeout(_timeout);

      debugPrint('[跳过配置] GET响应: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['config'] != null) {
          return EpisodeSkipConfig.fromJson(data['config']);
        }
      }
      return null;
    } catch (e) {
      debugPrint('[跳过配置] 获取异常: $e');
      return null;
    }
  }

  /// 保存跳过配置
  static Future<bool> setSkipConfig({
    required String source,
    required String id,
    required EpisodeSkipConfig config,
  }) async {
    try {
      final baseUrl = await UserDataService.getServerUrl();
      if (baseUrl == null) return false;

      final cookies = await UserDataService.getCookies();
      final key = '$source+$id';

      final uri = Uri.parse('$baseUrl/api/skipconfigs');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
        body: json.encode({
          'action': 'set',
          'key': key,
          'config': config.toJson(),
        }),
      ).timeout(_timeout);

      debugPrint('[跳过配置] SET响应: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[跳过配置] 保存异常: $e');
      return false;
    }
  }

  /// 删除跳过配置
  static Future<bool> deleteSkipConfig({
    required String source,
    required String id,
  }) async {
    try {
      final baseUrl = await UserDataService.getServerUrl();
      if (baseUrl == null) return false;

      final cookies = await UserDataService.getCookies();
      final key = '$source+$id';

      final uri = Uri.parse('$baseUrl/api/skipconfigs');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
        body: json.encode({
          'action': 'delete',
          'key': key,
        }),
      ).timeout(_timeout);

      debugPrint('[跳过配置] DELETE响应: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[跳过配置] 删除异常: $e');
      return false;
    }
  }

  /// 获取所有跳过配置
  static Future<List<EpisodeSkipConfig>> getAllSkipConfigs() async {
    try {
      final baseUrl = await UserDataService.getServerUrl();
      if (baseUrl == null) return [];

      final cookies = await UserDataService.getCookies();

      final uri = Uri.parse('$baseUrl/api/skipconfigs');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
        body: json.encode({
          'action': 'getAll',
        }),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final configs = data['configs'] as List<dynamic>? ?? [];
        return configs.map((e) => EpisodeSkipConfig.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[跳过配置] 获取全部异常: $e');
      return [];
    }
  }
}
