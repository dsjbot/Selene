import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/danmaku.dart';
import 'user_data_service.dart';

/// 弹幕服务
class DanmakuService {
  static const Duration _timeout = Duration(seconds: 30);

  /// 获取弹幕数据
  /// [title] 视频标题
  /// [episode] 集数（可选）
  /// [doubanId] 豆瓣ID（可选，用于精确匹配）
  static Future<DanmakuResponse> getDanmaku({
    required String title,
    String? episode,
    String? doubanId,
  }) async {
    try {
      final baseUrl = await UserDataService.getServerUrl();
      if (baseUrl == null) {
        return DanmakuResponse.error('服务器地址未配置');
      }

      final cookies = await UserDataService.getCookies();

      // 构建查询参数
      final queryParams = <String, String>{
        'title': title,
      };
      if (episode != null && episode.isNotEmpty) {
        queryParams['episode'] = episode;
      }
      if (doubanId != null && doubanId.isNotEmpty) {
        queryParams['doubanId'] = doubanId;
      }

      final uri = Uri.parse('$baseUrl/api/danmu-external')
          .replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseDanmakuResponse(data);
      } else {
        return DanmakuResponse.error('获取弹幕失败: ${response.statusCode}');
      }
    } catch (e) {
      return DanmakuResponse.error('获取弹幕异常: $e');
    }
  }

  /// 解析弹幕响应
  static DanmakuResponse _parseDanmakuResponse(Map<String, dynamic> data) {
    try {
      // 后端返回格式: { danmu: [...], platforms: [...], total: number }
      // 或者: { code: 0, name: string, danum: number, danmuku: [...] }
      
      List<DanmakuItem> danmakuList = [];
      int count = 0;
      bool success = false;

      if (data.containsKey('danmu')) {
        // 新格式 - 后端实际返回格式
        final list = data['danmu'] as List<dynamic>? ?? [];
        count = data['total'] ?? list.length;
        danmakuList = list.map((e) => DanmakuItem.fromJson(e as Map<String, dynamic>)).toList();
        success = danmakuList.isNotEmpty;
      } else if (data.containsKey('danmakuList')) {
        // 备用格式
        success = data['success'] ?? false;
        count = data['count'] ?? 0;
        final list = data['danmakuList'] as List<dynamic>? ?? [];
        danmakuList = list.map((e) => DanmakuItem.fromJson(e as Map<String, dynamic>)).toList();
      } else if (data.containsKey('danmuku')) {
        // 弹弹play格式
        success = (data['code'] ?? -1) == 0;
        count = data['danum'] ?? 0;
        final list = data['danmuku'] as List<dynamic>? ?? [];
        danmakuList = list.map((e) => _parseDanmukuItem(e)).toList();
      }

      // 按时间排序
      danmakuList.sort((a, b) => a.time.compareTo(b.time));

      return DanmakuResponse(
        success: success || danmakuList.isNotEmpty,
        count: danmakuList.length,
        danmakuList: danmakuList,
      );
    } catch (e) {
      return DanmakuResponse.error('解析弹幕数据失败: $e');
    }
  }

  /// 解析单条弹幕（弹弹play格式）
  static DanmakuItem _parseDanmukuItem(dynamic item) {
    if (item is Map<String, dynamic>) {
      return DanmakuItem.fromJson(item);
    } else if (item is List && item.length >= 2) {
      // 数组格式: [time, mode, color, userId, text]
      return DanmakuItem(
        time: (item[0] ?? 0).toDouble(),
        mode: item.length > 1 ? (item[1] ?? 0) : 0,
        color: item.length > 2 ? _parseColor(item[2]) : '#FFFFFF',
        text: item.length > 4 ? item[4].toString() : '',
      );
    }
    return DanmakuItem(text: '', time: 0);
  }

  /// 解析颜色值
  static String _parseColor(dynamic color) {
    if (color is String) {
      if (color.startsWith('#')) return color;
      // 尝试解析为数字
      final num = int.tryParse(color);
      if (num != null) {
        return '#${num.toRadixString(16).padLeft(6, '0').toUpperCase()}';
      }
      return color;
    } else if (color is int) {
      return '#${color.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    }
    return '#FFFFFF';
  }
}
