import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'user_data_service.dart';

/// 源站信息
class SourceSite {
  final String key;
  final String name;

  SourceSite({required this.key, required this.name});

  factory SourceSite.fromJson(Map<String, dynamic> json) {
    return SourceSite(
      key: json['key'] ?? '',
      name: json['name'] ?? '',
    );
  }
}

/// 分类信息
class SourceCategory {
  final String typeId;
  final String typeName;

  SourceCategory({required this.typeId, required this.typeName});

  factory SourceCategory.fromJson(Map<String, dynamic> json) {
    return SourceCategory(
      typeId: (json['type_id'] ?? '').toString(),
      typeName: json['type_name'] ?? '',
    );
  }
}

/// 视频项目
class SourceVideoItem {
  final String id;
  final String title;
  final String poster;
  final String year;
  final String typeName;
  final String remarks;

  SourceVideoItem({
    required this.id,
    required this.title,
    required this.poster,
    required this.year,
    required this.typeName,
    required this.remarks,
  });

  factory SourceVideoItem.fromJson(Map<String, dynamic> json) {
    return SourceVideoItem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      poster: json['poster'] ?? '',
      year: json['year'] ?? '',
      typeName: json['type_name'] ?? '',
      remarks: json['remarks'] ?? '',
    );
  }
}

/// 分页元数据
class PageMeta {
  final int page;
  final int pageCount;
  final int total;
  final int limit;

  PageMeta({
    required this.page,
    required this.pageCount,
    required this.total,
    required this.limit,
  });

  factory PageMeta.fromJson(Map<String, dynamic> json) {
    return PageMeta(
      page: json['page'] ?? 1,
      pageCount: json['pagecount'] ?? 1,
      total: json['total'] ?? 0,
      limit: json['limit'] ?? 20,
    );
  }
}

/// 列表响应
class SourceListResponse {
  final List<SourceVideoItem> items;
  final PageMeta meta;
  final SourceSite source;

  SourceListResponse({
    required this.items,
    required this.meta,
    required this.source,
  });
}

/// 源浏览器服务
class SourceBrowserService {
  static const Duration _timeout = Duration(seconds: 15);

  /// 获取可用源站列表
  static Future<List<SourceSite>> getSites() async {
    try {
      final baseUrl = await UserDataService.getServerUrl();
      if (baseUrl == null) {
        debugPrint('[源浏览器] 服务器地址未配置');
        return [];
      }

      final cookies = await UserDataService.getCookies();
      final uri = Uri.parse('$baseUrl/api/source-browser/sites');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final sources = data['sources'] as List<dynamic>? ?? [];
        return sources.map((e) => SourceSite.fromJson(e)).toList();
      } else {
        debugPrint('[源浏览器] 获取源站列表失败: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('[源浏览器] 获取源站列表异常: $e');
      return [];
    }
  }

  /// 获取源站分类列表
  static Future<List<SourceCategory>> getCategories(String sourceKey) async {
    try {
      final baseUrl = await UserDataService.getServerUrl();
      if (baseUrl == null) return [];

      final cookies = await UserDataService.getCookies();
      final uri = Uri.parse('$baseUrl/api/source-browser/categories?source=$sourceKey');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final categories = data['categories'] as List<dynamic>? ?? [];
        return categories.map((e) => SourceCategory.fromJson(e)).toList();
      } else {
        debugPrint('[源浏览器] 获取分类失败: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('[源浏览器] 获取分类异常: $e');
      return [];
    }
  }

  /// 获取分类下的视频列表
  static Future<SourceListResponse?> getList({
    required String sourceKey,
    required String typeId,
    int page = 1,
  }) async {
    try {
      final baseUrl = await UserDataService.getServerUrl();
      if (baseUrl == null) return null;

      final cookies = await UserDataService.getCookies();
      final uri = Uri.parse(
        '$baseUrl/api/source-browser/list?source=$sourceKey&type_id=$typeId&page=$page',
      );

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = (data['items'] as List<dynamic>? ?? [])
            .map((e) => SourceVideoItem.fromJson(e))
            .toList();
        final meta = PageMeta.fromJson(data['meta'] ?? {});
        final source = SourceSite.fromJson(data['source'] ?? {});
        return SourceListResponse(items: items, meta: meta, source: source);
      } else {
        debugPrint('[源浏览器] 获取列表失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[源浏览器] 获取列表异常: $e');
      return null;
    }
  }

  /// 搜索视频
  static Future<SourceListResponse?> search({
    required String sourceKey,
    required String query,
    int page = 1,
  }) async {
    try {
      final baseUrl = await UserDataService.getServerUrl();
      if (baseUrl == null) return null;

      final cookies = await UserDataService.getCookies();
      final uri = Uri.parse(
        '$baseUrl/api/source-browser/search?source=$sourceKey&q=${Uri.encodeComponent(query)}&page=$page',
      );

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = (data['items'] as List<dynamic>? ?? [])
            .map((e) => SourceVideoItem.fromJson(e))
            .toList();
        final meta = PageMeta.fromJson(data['meta'] ?? {});
        final source = SourceSite.fromJson(data['source'] ?? {});
        return SourceListResponse(items: items, meta: meta, source: source);
      } else {
        debugPrint('[源浏览器] 搜索失败: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[源浏览器] 搜索异常: $e');
      return null;
    }
  }
}
