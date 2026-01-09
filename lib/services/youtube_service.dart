import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'user_data_service.dart';

/// YouTube 视频数据模型
class YouTubeVideo {
  final String videoId;
  final String title;
  final String description;
  final String thumbnailUrl;
  final String channelTitle;
  final String channelId;
  final String publishedAt;

  YouTubeVideo({
    required this.videoId,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.channelTitle,
    required this.channelId,
    required this.publishedAt,
  });

  factory YouTubeVideo.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final snippet = json['snippet'] ?? {};
    final thumbnails = snippet['thumbnails'] ?? {};
    // 优先使用 high > medium > default
    final thumbnail = thumbnails['high'] ?? thumbnails['medium'] ?? thumbnails['default'] ?? {};
    
    // 解析 videoId
    final videoId = id is Map ? (id['videoId'] ?? '') : (json['videoId'] ?? id?.toString() ?? '');
    
    // 获取缩略图 URL，如果为空则根据 videoId 构建
    String thumbnailUrl = thumbnail['url'] ?? '';
    if (thumbnailUrl.isEmpty && videoId.isNotEmpty) {
      // YouTube 缩略图 URL 格式
      thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    }

    return YouTubeVideo(
      videoId: videoId,
      title: snippet['title'] ?? '',
      description: snippet['description'] ?? '',
      thumbnailUrl: thumbnailUrl,
      channelTitle: snippet['channelTitle'] ?? '',
      channelId: snippet['channelId'] ?? '',
      publishedAt: snippet['publishedAt'] ?? '',
    );
  }

  /// 获取格式化的发布日期
  String get formattedDate {
    try {
      final date = DateTime.parse(publishedAt);
      return '${date.year}年${date.month}月${date.day}日';
    } catch (e) {
      return publishedAt;
    }
  }

  /// 获取 YouTube 视频链接
  String get videoUrl => 'https://www.youtube.com/watch?v=$videoId';

  /// 获取嵌入播放链接（无 cookie 版本）
  String get embedUrl => 'https://www.youtube-nocookie.com/embed/$videoId?autoplay=1&rel=0';
}

/// YouTube 搜索结果
class YouTubeSearchResult {
  final bool success;
  final List<YouTubeVideo> videos;
  final int total;
  final String query;
  final String source; // 'youtube' | 'demo' | 'fallback'
  final String? warning;
  final String? error;
  final bool fromCache;

  YouTubeSearchResult({
    required this.success,
    required this.videos,
    required this.total,
    required this.query,
    required this.source,
    this.warning,
    this.error,
    this.fromCache = false,
  });

  factory YouTubeSearchResult.error(String message) {
    return YouTubeSearchResult(
      success: false,
      videos: [],
      total: 0,
      query: '',
      source: 'error',
      error: message,
    );
  }
}

/// YouTube 内容类型
enum YouTubeContentType {
  all,
  music,
  movie,
  educational,
  gaming,
  sports,
  news,
}

extension YouTubeContentTypeExtension on YouTubeContentType {
  String get value {
    switch (this) {
      case YouTubeContentType.all:
        return 'all';
      case YouTubeContentType.music:
        return 'music';
      case YouTubeContentType.movie:
        return 'movie';
      case YouTubeContentType.educational:
        return 'educational';
      case YouTubeContentType.gaming:
        return 'gaming';
      case YouTubeContentType.sports:
        return 'sports';
      case YouTubeContentType.news:
        return 'news';
    }
  }

  String get label {
    switch (this) {
      case YouTubeContentType.all:
        return '全部';
      case YouTubeContentType.music:
        return '音乐';
      case YouTubeContentType.movie:
        return '电影';
      case YouTubeContentType.educational:
        return '教育';
      case YouTubeContentType.gaming:
        return '游戏';
      case YouTubeContentType.sports:
        return '体育';
      case YouTubeContentType.news:
        return '新闻';
    }
  }
}

/// YouTube 排序方式
enum YouTubeSortOrder {
  relevance,
  date,
  viewCount,
  rating,
  title,
}

extension YouTubeSortOrderExtension on YouTubeSortOrder {
  String get value {
    switch (this) {
      case YouTubeSortOrder.relevance:
        return 'relevance';
      case YouTubeSortOrder.date:
        return 'date';
      case YouTubeSortOrder.viewCount:
        return 'viewCount';
      case YouTubeSortOrder.rating:
        return 'rating';
      case YouTubeSortOrder.title:
        return 'title';
    }
  }

  String get label {
    switch (this) {
      case YouTubeSortOrder.relevance:
        return '相关性';
      case YouTubeSortOrder.date:
        return '最新发布';
      case YouTubeSortOrder.viewCount:
        return '观看次数';
      case YouTubeSortOrder.rating:
        return '评分';
      case YouTubeSortOrder.title:
        return '标题';
    }
  }

  String get icon {
    switch (this) {
      case YouTubeSortOrder.relevance:
        return '';
      case YouTubeSortOrder.date:
        return '🕒';
      case YouTubeSortOrder.viewCount:
        return '👀';
      case YouTubeSortOrder.rating:
        return '⭐';
      case YouTubeSortOrder.title:
        return '🔤';
    }
  }
}

/// YouTube 服务
class YouTubeService {
  static const Duration _timeout = Duration(seconds: 30);

  // 内存缓存
  static final Map<String, YouTubeSearchResult> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 30);
  static final Map<String, DateTime> _cacheTime = {};

  /// 搜索 YouTube 视频
  static Future<YouTubeSearchResult> search({
    required String query,
    YouTubeContentType contentType = YouTubeContentType.all,
    YouTubeSortOrder sortOrder = YouTubeSortOrder.relevance,
    int maxResults = 25,
  }) async {
    if (query.trim().isEmpty) {
      return YouTubeSearchResult.error('搜索关键词不能为空');
    }

    // 构建缓存 key
    final cacheKey = 'youtube_${query}_${contentType.value}_${sortOrder.value}_$maxResults';

    // 检查缓存
    if (_cache.containsKey(cacheKey) && _cacheTime.containsKey(cacheKey)) {
      final cacheAge = DateTime.now().difference(_cacheTime[cacheKey]!);
      if (cacheAge < _cacheDuration) {
        debugPrint('[YouTube] 使用缓存: $query');
        return _cache[cacheKey]!;
      }
    }

    try {
      final baseUrl = await UserDataService.getServerUrl();
      if (baseUrl == null) {
        return YouTubeSearchResult.error('服务器地址未配置');
      }

      final cookies = await UserDataService.getCookies();

      // 构建查询参数
      final queryParams = <String, String>{
        'q': query.trim(),
        'maxResults': maxResults.toString(),
      };

      if (contentType != YouTubeContentType.all) {
        queryParams['contentType'] = contentType.value;
      }

      if (sortOrder != YouTubeSortOrder.relevance) {
        queryParams['order'] = sortOrder.value;
      }

      final uri = Uri.parse('$baseUrl/api/youtube/search')
          .replace(queryParameters: queryParams);

      debugPrint('[YouTube] 请求: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      debugPrint('[YouTube] 响应状态: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          final videos = (data['videos'] as List<dynamic>?)
                  ?.map((v) => YouTubeVideo.fromJson(v as Map<String, dynamic>))
                  .toList() ??
              [];

          final result = YouTubeSearchResult(
            success: true,
            videos: videos,
            total: data['total'] ?? videos.length,
            query: data['query'] ?? query,
            source: data['source'] ?? 'youtube',
            warning: data['warning'],
            fromCache: data['fromCache'] ?? false,
          );

          // 缓存结果
          _cache[cacheKey] = result;
          _cacheTime[cacheKey] = DateTime.now();

          debugPrint('[YouTube] 成功: ${videos.length} 个结果');
          return result;
        } else {
          return YouTubeSearchResult.error(data['error'] ?? 'YouTube 搜索失败');
        }
      } else if (response.statusCode == 401) {
        return YouTubeSearchResult.error('请先登录');
      } else if (response.statusCode == 403) {
        final data = json.decode(response.body);
        return YouTubeSearchResult.error(data['error'] ?? '您无权使用 YouTube 搜索功能');
      } else if (response.statusCode == 400) {
        final data = json.decode(response.body);
        return YouTubeSearchResult.error(data['error'] ?? 'YouTube 搜索功能未启用');
      } else {
        return YouTubeSearchResult.error('YouTube 搜索失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[YouTube] 异常: $e');
      if (e.toString().contains('TimeoutException')) {
        return YouTubeSearchResult.error('请求超时，请稍后重试');
      }
      return YouTubeSearchResult.error('网络错误: $e');
    }
  }

  /// 清除缓存
  static void clearCache() {
    _cache.clear();
    _cacheTime.clear();
  }
}
