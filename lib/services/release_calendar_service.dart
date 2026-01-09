import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'user_data_service.dart';

/// 发布日历项
class ReleaseCalendarItem {
  final String id;
  final String title;
  final String type; // 'movie' | 'tv'
  final String director;
  final String actors;
  final String region;
  final String genre;
  final String releaseDate; // YYYY-MM-DD
  final String? cover;
  final String? description;
  final int? episodes;
  final String source;
  final int createdAt;
  final int updatedAt;

  ReleaseCalendarItem({
    required this.id,
    required this.title,
    required this.type,
    required this.director,
    required this.actors,
    required this.region,
    required this.genre,
    required this.releaseDate,
    this.cover,
    this.description,
    this.episodes,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReleaseCalendarItem.fromJson(Map<String, dynamic> json) {
    return ReleaseCalendarItem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      type: json['type'] ?? 'movie',
      director: json['director'] ?? '',
      actors: json['actors'] ?? '',
      region: json['region'] ?? '',
      genre: json['genre'] ?? '',
      releaseDate: json['releaseDate'] ?? '',
      cover: json['cover'],
      description: json['description'],
      episodes: json['episodes'],
      source: json['source'] ?? 'manmankan',
      createdAt: json['createdAt'] ?? 0,
      updatedAt: json['updatedAt'] ?? 0,
    );
  }

  /// 计算距离上映还有几天
  int get daysUntilRelease {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final release = DateTime.parse(releaseDate);
      final releaseDay = DateTime(release.year, release.month, release.day);
      return releaseDay.difference(today).inDays;
    } catch (e) {
      return 0;
    }
  }

  /// 获取上映状态文字
  String get remarksText {
    final days = daysUntilRelease;
    if (days < 0) {
      return '已上映${-days}天';
    } else if (days == 0) {
      return '今日上映';
    } else {
      return '${days}天后上映';
    }
  }

  /// 是否已上映
  bool get isReleased => daysUntilRelease < 0;

  /// 是否今日上映
  bool get isReleasingToday => daysUntilRelease == 0;

  /// 是否即将上映（未来）
  bool get isUpcoming => daysUntilRelease > 0;
}

/// 发布日历过滤器选项
class FilterOption {
  final String value;
  final String label;
  final int count;

  FilterOption({
    required this.value,
    required this.label,
    required this.count,
  });

  factory FilterOption.fromJson(Map<String, dynamic> json) {
    return FilterOption(
      value: json['value']?.toString() ?? '',
      label: json['label'] ?? '',
      count: json['count'] ?? 0,
    );
  }
}

/// 发布日历过滤器
class ReleaseCalendarFilters {
  final List<FilterOption> types;
  final List<FilterOption> regions;
  final List<FilterOption> genres;

  ReleaseCalendarFilters({
    required this.types,
    required this.regions,
    required this.genres,
  });

  factory ReleaseCalendarFilters.fromJson(Map<String, dynamic> json) {
    return ReleaseCalendarFilters(
      types: (json['types'] as List<dynamic>?)
              ?.map((e) => FilterOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      regions: (json['regions'] as List<dynamic>?)
              ?.map((e) => FilterOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => FilterOption.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// 发布日历搜索结果
class ReleaseCalendarResult {
  final bool success;
  final List<ReleaseCalendarItem> items;
  final int total;
  final bool hasMore;
  final ReleaseCalendarFilters? filters;
  final String? error;

  ReleaseCalendarResult({
    required this.success,
    required this.items,
    required this.total,
    required this.hasMore,
    this.filters,
    this.error,
  });

  factory ReleaseCalendarResult.error(String message) {
    return ReleaseCalendarResult(
      success: false,
      items: [],
      total: 0,
      hasMore: false,
      error: message,
    );
  }
}

/// 发布日历服务
class ReleaseCalendarService {
  static const Duration _timeout = Duration(seconds: 30);

  // 内存缓存
  static ReleaseCalendarResult? _cachedResult;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(hours: 1);

  /// 获取发布日历数据
  static Future<ReleaseCalendarResult> getCalendar({
    String? type,
    String? region,
    String? genre,
    String? dateFrom,
    String? dateTo,
    int? limit,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    // 检查缓存（仅对无过滤条件的请求使用缓存）
    if (!forceRefresh &&
        type == null &&
        region == null &&
        genre == null &&
        dateFrom == null &&
        dateTo == null &&
        offset == 0 &&
        _cachedResult != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      debugPrint('[发布日历] 使用缓存数据');
      return _cachedResult!;
    }

    try {
      final baseUrl = await UserDataService.getServerUrl();
      if (baseUrl == null) {
        return ReleaseCalendarResult.error('服务器地址未配置');
      }

      final cookies = await UserDataService.getCookies();
      
      // 构建查询参数
      final queryParams = <String, String>{};
      if (type != null && type.isNotEmpty) queryParams['type'] = type;
      if (region != null && region.isNotEmpty) queryParams['region'] = region;
      if (genre != null && genre.isNotEmpty) queryParams['genre'] = genre;
      if (dateFrom != null && dateFrom.isNotEmpty) queryParams['dateFrom'] = dateFrom;
      if (dateTo != null && dateTo.isNotEmpty) queryParams['dateTo'] = dateTo;
      if (limit != null) queryParams['limit'] = limit.toString();
      if (offset > 0) queryParams['offset'] = offset.toString();
      if (forceRefresh) queryParams['refresh'] = 'true';

      final uri = Uri.parse('$baseUrl/api/release-calendar').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      debugPrint('[发布日历] 请求: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      debugPrint('[发布日历] 响应状态: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final items = (data['items'] as List<dynamic>?)
                ?.map((e) => ReleaseCalendarItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        
        final result = ReleaseCalendarResult(
          success: true,
          items: items,
          total: data['total'] ?? items.length,
          hasMore: data['hasMore'] ?? false,
          filters: data['filters'] != null
              ? ReleaseCalendarFilters.fromJson(data['filters'] as Map<String, dynamic>)
              : null,
        );

        // 缓存无过滤条件的结果
        if (type == null &&
            region == null &&
            genre == null &&
            dateFrom == null &&
            dateTo == null &&
            offset == 0) {
          _cachedResult = result;
          _cacheTime = DateTime.now();
        }

        debugPrint('[发布日历] 成功: ${items.length} 个结果');
        return result;
      } else if (response.statusCode == 401) {
        return ReleaseCalendarResult.error('请先登录');
      } else {
        final data = json.decode(response.body);
        return ReleaseCalendarResult.error(data['error'] ?? '获取发布日历失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[发布日历] 异常: $e');
      if (e.toString().contains('TimeoutException')) {
        return ReleaseCalendarResult.error('请求超时，请稍后重试');
      }
      return ReleaseCalendarResult.error('网络错误: $e');
    }
  }

  /// 获取首页即将上映数据（智能筛选和分配）
  static Future<List<ReleaseCalendarItem>> getUpcomingForHome({
    int maxItems = 10,
    bool forceRefresh = false,
  }) async {
    final result = await getCalendar(limit: 100, forceRefresh: forceRefresh);
    
    if (!result.success || result.items.isEmpty) {
      return [];
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = today.subtract(const Duration(days: 7));
    final ninetyDaysLater = today.add(const Duration(days: 90));

    // 过滤出即将上映和刚上映的作品（过去7天到未来90天）
    final upcoming = result.items.where((item) {
      try {
        final releaseDate = DateTime.parse(item.releaseDate);
        final releaseDateOnly = DateTime(releaseDate.year, releaseDate.month, releaseDate.day);
        return releaseDateOnly.isAfter(sevenDaysAgo.subtract(const Duration(days: 1))) &&
               releaseDateOnly.isBefore(ninetyDaysLater.add(const Duration(days: 1)));
      } catch (e) {
        return false;
      }
    }).toList();

    // 智能去重：基于标题去重
    final uniqueUpcoming = <ReleaseCalendarItem>[];
    final seenTitles = <String>{};
    
    for (final item in upcoming) {
      final normalizedTitle = _normalizeTitle(item.title);
      if (!seenTitles.contains(normalizedTitle)) {
        seenTitles.add(normalizedTitle);
        uniqueUpcoming.add(item);
      }
    }

    // 智能分配：按时间段分类
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final sevenDaysLater = today.add(const Duration(days: 7));
    final sevenDaysLaterStr = '${sevenDaysLater.year}-${sevenDaysLater.month.toString().padLeft(2, '0')}-${sevenDaysLater.day.toString().padLeft(2, '0')}';
    final thirtyDaysLater = today.add(const Duration(days: 30));
    final thirtyDaysLaterStr = '${thirtyDaysLater.year}-${thirtyDaysLater.month.toString().padLeft(2, '0')}-${thirtyDaysLater.day.toString().padLeft(2, '0')}';

    final recentlyReleased = uniqueUpcoming.where((i) => i.releaseDate.compareTo(todayStr) < 0).toList();
    final releasingToday = uniqueUpcoming.where((i) => i.releaseDate == todayStr).toList();
    final nextSevenDays = uniqueUpcoming.where((i) => i.releaseDate.compareTo(todayStr) > 0 && i.releaseDate.compareTo(sevenDaysLaterStr) <= 0).toList();
    final nextThirtyDays = uniqueUpcoming.where((i) => i.releaseDate.compareTo(sevenDaysLaterStr) > 0 && i.releaseDate.compareTo(thirtyDaysLaterStr) <= 0).toList();
    final laterReleasing = uniqueUpcoming.where((i) => i.releaseDate.compareTo(thirtyDaysLaterStr) > 0).toList();

    // 配额分配策略
    final selectedItems = <ReleaseCalendarItem>[];
    
    // 2已上映 + 1今日 + 4近期(7天) + 2中期(30天) + 1远期
    selectedItems.addAll(recentlyReleased.take(2));
    selectedItems.addAll(releasingToday.take(1));
    selectedItems.addAll(nextSevenDays.take(4));
    selectedItems.addAll(nextThirtyDays.take(2));
    selectedItems.addAll(laterReleasing.take(1));

    // 如果没填满，按优先级补充
    if (selectedItems.length < maxItems) {
      final remaining = maxItems - selectedItems.length;
      final additionalSeven = nextSevenDays.skip(4).take(remaining).toList();
      selectedItems.addAll(additionalSeven);
    }

    if (selectedItems.length < maxItems) {
      final remaining = maxItems - selectedItems.length;
      final additionalThirty = nextThirtyDays.skip(2).take(remaining).toList();
      selectedItems.addAll(additionalThirty);
    }

    if (selectedItems.length < maxItems) {
      final remaining = maxItems - selectedItems.length;
      final additionalLater = laterReleasing.skip(1).take(remaining).toList();
      selectedItems.addAll(additionalLater);
    }

    if (selectedItems.length < maxItems) {
      final remaining = maxItems - selectedItems.length;
      final additionalRecent = recentlyReleased.skip(2).take(remaining).toList();
      selectedItems.addAll(additionalRecent);
    }

    debugPrint('[发布日历] 首页即将上映: ${selectedItems.length} 个');
    return selectedItems.take(maxItems).toList();
  }

  /// 标题归一化（用于去重）
  static String _normalizeTitle(String title) {
    var normalized = title.replaceAll('：', ':').trim();
    
    // 处理副标题
    if (normalized.contains(':')) {
      final parts = normalized.split(':').map((p) => p.trim()).toList();
      normalized = parts.last;
    }
    
    // 移除季数、集数等后缀
    normalized = normalized
        .replaceAll(RegExp(r'第[一二三四五六七八九十\d]+季'), '')
        .replaceAll(RegExp(r'Season\s*\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'S\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+\d+$'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
    
    return normalized;
  }

  /// 清除缓存
  static void clearCache() {
    _cachedResult = null;
    _cacheTime = null;
  }
}
