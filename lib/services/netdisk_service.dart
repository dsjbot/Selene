import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'user_data_service.dart';

/// 网盘资源项
class NetDiskItem {
  final String url;
  final String password;
  final String note;
  final String datetime;
  final String source;
  final List<String>? images;

  NetDiskItem({
    required this.url,
    required this.password,
    required this.note,
    required this.datetime,
    required this.source,
    this.images,
  });

  factory NetDiskItem.fromJson(Map<String, dynamic> json) {
    return NetDiskItem(
      url: json['url'] ?? '',
      password: json['password'] ?? '',
      note: json['note'] ?? '',
      datetime: json['datetime'] ?? '',
      source: json['source'] ?? '',
      images: json['images'] != null 
          ? List<String>.from(json['images']) 
          : null,
    );
  }
  
  /// 获取显示标题（优先使用note，否则使用url）
  String get displayTitle => note.isNotEmpty ? note : '未命名资源';
}

/// 网盘搜索结果（按类型分组）
class NetDiskSearchResult {
  final bool success;
  final int total;
  final Map<String, List<NetDiskItem>> mergedByType;
  final String? error;
  final bool fromCache;

  NetDiskSearchResult({
    required this.success,
    required this.total,
    required this.mergedByType,
    this.error,
    this.fromCache = false,
  });

  factory NetDiskSearchResult.error(String message) {
    return NetDiskSearchResult(
      success: false,
      total: 0,
      mergedByType: {},
      error: message,
    );
  }
}

/// 云盘类型配置
class CloudTypeConfig {
  final String name;
  final int color;
  final String icon;

  const CloudTypeConfig({
    required this.name,
    required this.color,
    required this.icon,
  });
}

/// 网盘搜索服务
class NetDiskService {
  static const Duration _timeout = Duration(seconds: 30);

  /// 云盘类型配置表
  static const Map<String, CloudTypeConfig> cloudTypes = {
    'baidu': CloudTypeConfig(name: '百度网盘', color: 0xFF2196F3, icon: '📁'),
    'aliyun': CloudTypeConfig(name: '阿里云盘', color: 0xFFFF9800, icon: '☁️'),
    'aliyundrive': CloudTypeConfig(name: '阿里云盘', color: 0xFFFF9800, icon: '☁️'),
    'quark': CloudTypeConfig(name: '夸克网盘', color: 0xFF9C27B0, icon: '⚡'),
    'tianyi': CloudTypeConfig(name: '天翼云盘', color: 0xFF4CAF50, icon: '📱'),
    '189': CloudTypeConfig(name: '天翼云盘', color: 0xFF4CAF50, icon: '📱'),
    'uc': CloudTypeConfig(name: 'UC网盘', color: 0xFFE91E63, icon: '🌐'),
    'xunlei': CloudTypeConfig(name: '迅雷云盘', color: 0xFF00BCD4, icon: '⚡'),
    '115': CloudTypeConfig(name: '115网盘', color: 0xFF795548, icon: '💾'),
    'mobile': CloudTypeConfig(name: '移动云盘', color: 0xFF3F51B5, icon: '📲'),
    'pikpak': CloudTypeConfig(name: 'PikPak', color: 0xFFFF5722, icon: '📦'),
    '123': CloudTypeConfig(name: '123云盘', color: 0xFF009688, icon: '🔢'),
    'magnet': CloudTypeConfig(name: '磁力链接', color: 0xFF607D8B, icon: '🧲'),
    'ed2k': CloudTypeConfig(name: '电驴链接', color: 0xFF8BC34A, icon: '🐴'),
    'others': CloudTypeConfig(name: '其他', color: 0xFF9E9E9E, icon: '📄'),
  };

  /// 获取云盘类型显示名称
  static String getCloudTypeName(String type) {
    return cloudTypes[type.toLowerCase()]?.name ?? type;
  }

  /// 获取云盘类型图标颜色
  static int getCloudTypeColor(String type) {
    return cloudTypes[type.toLowerCase()]?.color ?? 0xFF9E9E9E;
  }
  
  /// 获取云盘类型图标
  static String getCloudTypeIcon(String type) {
    return cloudTypes[type.toLowerCase()]?.icon ?? '📄';
  }

  /// 搜索网盘资源
  static Future<NetDiskSearchResult> search(String query) async {
    if (query.trim().isEmpty) {
      return NetDiskSearchResult.error('搜索关键词不能为空');
    }

    try {
      final baseUrl = await UserDataService.getServerUrl();
      if (baseUrl == null) {
        return NetDiskSearchResult.error('服务器地址未配置');
      }

      final cookies = await UserDataService.getCookies();
      final uri = Uri.parse('$baseUrl/api/netdisk/search?q=${Uri.encodeComponent(query)}');

      debugPrint('[网盘搜索] 请求: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      debugPrint('[网盘搜索] 响应状态: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true && data['data'] != null) {
          final resultData = data['data'];
          final total = resultData['total'] ?? 0;
          final mergedByType = <String, List<NetDiskItem>>{};
          
          // 解析按类型分组的结果
          final rawMerged = resultData['merged_by_type'] as Map<String, dynamic>? ?? {};
          for (final entry in rawMerged.entries) {
            final items = (entry.value as List<dynamic>?)
                ?.map((e) => NetDiskItem.fromJson(e as Map<String, dynamic>))
                .toList() ?? [];
            if (items.isNotEmpty) {
              mergedByType[entry.key] = items;
            }
          }

          debugPrint('[网盘搜索] 成功: $total 个结果, ${mergedByType.length} 个类型');
          
          return NetDiskSearchResult(
            success: true,
            total: total,
            mergedByType: mergedByType,
            fromCache: data['fromCache'] == true,
          );
        } else {
          return NetDiskSearchResult.error(data['error'] ?? '搜索失败');
        }
      } else if (response.statusCode == 400) {
        final data = json.decode(response.body);
        return NetDiskSearchResult.error(data['error'] ?? '请求参数错误');
      } else if (response.statusCode == 401) {
        return NetDiskSearchResult.error('请先登录');
      } else {
        return NetDiskSearchResult.error('搜索失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[网盘搜索] 异常: $e');
      if (e.toString().contains('TimeoutException')) {
        return NetDiskSearchResult.error('搜索超时，请稍后重试');
      }
      return NetDiskSearchResult.error('网络错误: $e');
    }
  }
}
