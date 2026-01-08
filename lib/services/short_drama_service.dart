import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/short_drama.dart';
import 'api_service.dart';
import 'user_data_service.dart';

/// 短剧服务
class ShortDramaService {
  static const Duration _timeout = Duration(seconds: 30);

  /// 获取基础URL
  static Future<String?> _getBaseUrl() async {
    return await UserDataService.getServerUrl();
  }

  /// 获取认证cookies
  static Future<String?> _getCookies() async {
    return await UserDataService.getCookies();
  }

  /// 获取短剧分类列表
  static Future<ApiResponse<List<ShortDramaCategory>>> getCategories() async {
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null) {
        return ApiResponse.error('服务器地址未配置');
      }

      final cookies = await _getCookies();
      final response = await http.get(
        Uri.parse('$baseUrl/api/shortdrama/categories'),
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final categories = data
            .map((e) => ShortDramaCategory.fromJson(e as Map<String, dynamic>))
            .toList();
        return ApiResponse.success(categories);
      } else {
        return ApiResponse.error('获取分类失败: ${response.statusCode}');
      }
    } catch (e) {
      return ApiResponse.error('获取分类异常: $e');
    }
  }

  /// 获取短剧列表
  static Future<ApiResponse<ShortDramaListResponse>> getList({
    required int categoryId,
    int page = 1,
    int size = 20,
  }) async {
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null) {
        return ApiResponse.error('服务器地址未配置');
      }

      final cookies = await _getCookies();
      final response = await http.get(
        Uri.parse(
            '$baseUrl/api/shortdrama/list?categoryId=$categoryId&page=$page&size=$size'),
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(ShortDramaListResponse.fromJson(data));
      } else {
        return ApiResponse.error('获取列表失败: ${response.statusCode}');
      }
    } catch (e) {
      return ApiResponse.error('获取列表异常: $e');
    }
  }

  /// 搜索短剧
  static Future<ApiResponse<ShortDramaListResponse>> search({
    required String query,
    int page = 1,
    int size = 20,
  }) async {
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null) {
        return ApiResponse.error('服务器地址未配置');
      }

      final cookies = await _getCookies();
      final encodedQuery = Uri.encodeComponent(query);
      final response = await http.get(
        Uri.parse(
            '$baseUrl/api/shortdrama/search?keyword=$encodedQuery&page=$page&size=$size'),
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(ShortDramaListResponse.fromJson(data));
      } else {
        return ApiResponse.error('搜索失败: ${response.statusCode}');
      }
    } catch (e) {
      return ApiResponse.error('搜索异常: $e');
    }
  }

  /// 获取推荐短剧
  static Future<ApiResponse<List<ShortDramaItem>>> getRecommend({
    int? category,
    int size = 10,
  }) async {
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null) {
        return ApiResponse.error('服务器地址未配置');
      }

      final cookies = await _getCookies();
      String url = '$baseUrl/api/shortdrama/recommend?size=$size';
      if (category != null) {
        url += '&category=$category';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final dynamic responseData = json.decode(response.body);
        List<ShortDramaItem> items = [];
        
        // 处理不同的响应格式
        if (responseData is List) {
          items = responseData
              .map((e) => ShortDramaItem.fromJson(e as Map<String, dynamic>))
              .toList();
        } else if (responseData is Map<String, dynamic>) {
          // 可能是 { list: [...], hasMore: bool } 格式
          final list = responseData['list'] ?? responseData['data'] ?? responseData['items'];
          if (list is List) {
            items = list
                .map((e) => ShortDramaItem.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        }
        
        return ApiResponse.success(items);
      } else {
        return ApiResponse.error('获取推荐失败: ${response.statusCode}');
      }
    } catch (e) {
      return ApiResponse.error('获取推荐异常: $e');
    }
  }

  /// 获取短剧详情
  static Future<ApiResponse<ShortDramaDetail>> getDetail({
    required int id,
    String? name,
  }) async {
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null) {
        return ApiResponse.error('服务器地址未配置');
      }

      final cookies = await _getCookies();
      // 使用 name 参数作为主要查询条件，与后端 API 保持一致
      String url = '$baseUrl/api/shortdrama/detail?id=$id';
      if (name != null && name.isNotEmpty) {
        url += '&name=${Uri.encodeComponent(name)}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(ShortDramaDetail.fromJson(data));
      } else {
        // 尝试解析错误信息
        String errorMsg = '获取详情失败: ${response.statusCode}';
        try {
          final errorData = json.decode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMsg = errorData['message'];
          } else if (errorData is Map && errorData['error'] != null) {
            errorMsg = errorData['error'];
          }
        } catch (_) {}
        return ApiResponse.error(errorMsg);
      }
    } catch (e) {
      return ApiResponse.error('获取详情异常: $e');
    }
  }

  /// 解析短剧播放地址
  static Future<ApiResponse<ShortDramaParseResult>> parse({
    required int id,
    required int episode,
    String? name,
  }) async {
    try {
      final baseUrl = await _getBaseUrl();
      if (baseUrl == null) {
        return ApiResponse.error('服务器地址未配置');
      }

      final cookies = await _getCookies();
      // episode 从 0 开始，API 可能需要从 1 开始
      String url = '$baseUrl/api/shortdrama/parse?id=$id&episode=${episode + 1}';
      if (name != null && name.isNotEmpty) {
        url += '&name=${Uri.encodeComponent(name)}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(ShortDramaParseResult.fromJson(data));
      } else {
        String errorMsg = '解析失败: ${response.statusCode}';
        try {
          final errorData = json.decode(response.body);
          if (errorData is Map && errorData['message'] != null) {
            errorMsg = errorData['message'];
          } else if (errorData is Map && errorData['error'] != null) {
            errorMsg = errorData['error'];
          }
        } catch (_) {}
        return ApiResponse.error(errorMsg);
      }
    } catch (e) {
      return ApiResponse.error('解析异常: $e');
    }
  }
}
