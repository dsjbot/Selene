import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'user_data_service.dart';

/// TMDB 演员作品数据模型
class TMDBActorWork {
  final String id;
  final String title;
  final String poster;
  final String rate;
  final String year;
  final double? popularity;
  final int? voteCount;
  final List<int>? genreIds;
  final String? character;
  final int? episodeCount;
  final String? originalLanguage;

  TMDBActorWork({
    required this.id,
    required this.title,
    required this.poster,
    required this.rate,
    required this.year,
    this.popularity,
    this.voteCount,
    this.genreIds,
    this.character,
    this.episodeCount,
    this.originalLanguage,
  });

  factory TMDBActorWork.fromJson(Map<String, dynamic> json) {
    return TMDBActorWork(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      poster: json['poster'] ?? '',
      rate: json['rate']?.toString() ?? '0',
      year: json['year']?.toString() ?? '',
      popularity: (json['popularity'] as num?)?.toDouble(),
      voteCount: json['vote_count'] as int?,
      genreIds: (json['genre_ids'] as List<dynamic>?)?.map((e) => e as int).toList(),
      character: json['character'] as String?,
      episodeCount: json['episode_count'] as int?,
      originalLanguage: json['original_language'] as String?,
    );
  }

  /// 获取评分显示
  String get ratingDisplay {
    final rating = double.tryParse(rate) ?? 0;
    if (rating == 0) return '暂无评分';
    return rating.toStringAsFixed(1);
  }

  /// 是否有评分
  bool get hasRating => (double.tryParse(rate) ?? 0) > 0;
}

/// TMDB 演员搜索结果
class TMDBActorSearchResult {
  final bool success;
  final List<TMDBActorWork> list;
  final int? total;
  final String? error;

  TMDBActorSearchResult({
    required this.success,
    required this.list,
    this.total,
    this.error,
  });

  factory TMDBActorSearchResult.error(String message) {
    return TMDBActorSearchResult(
      success: false,
      list: [],
      error: message,
    );
  }
}

/// TMDB 内容类型
enum TMDBContentType {
  movie,
  tv,
}

extension TMDBContentTypeExtension on TMDBContentType {
  String get value {
    switch (this) {
      case TMDBContentType.movie:
        return 'movie';
      case TMDBContentType.tv:
        return 'tv';
    }
  }

  String get label {
    switch (this) {
      case TMDBContentType.movie:
        return '电影';
      case TMDBContentType.tv:
        return '电视剧';
    }
  }
}

/// TMDB 排序方式
enum TMDBSortBy {
  rating,
  date,
  popularity,
  voteCount,
  title,
  episodeCount,
}

extension TMDBSortByExtension on TMDBSortBy {
  String get value {
    switch (this) {
      case TMDBSortBy.rating:
        return 'rating';
      case TMDBSortBy.date:
        return 'date';
      case TMDBSortBy.popularity:
        return 'popularity';
      case TMDBSortBy.voteCount:
        return 'vote_count';
      case TMDBSortBy.title:
        return 'title';
      case TMDBSortBy.episodeCount:
        return 'episode_count';
    }
  }

  String get label {
    switch (this) {
      case TMDBSortBy.rating:
        return '评分';
      case TMDBSortBy.date:
        return '日期';
      case TMDBSortBy.popularity:
        return '人气';
      case TMDBSortBy.voteCount:
        return '投票数';
      case TMDBSortBy.title:
        return '标题';
      case TMDBSortBy.episodeCount:
        return '集数';
    }
  }
}

/// TMDB 排序顺序
enum TMDBSortOrder {
  asc,
  desc,
}

extension TMDBSortOrderExtension on TMDBSortOrder {
  String get value {
    switch (this) {
      case TMDBSortOrder.asc:
        return 'asc';
      case TMDBSortOrder.desc:
        return 'desc';
    }
  }

  String get label {
    switch (this) {
      case TMDBSortOrder.asc:
        return '升序';
      case TMDBSortOrder.desc:
        return '降序';
    }
  }
}

/// TMDB 筛选选项
class TMDBFilterOptions {
  final int? startYear;
  final int? endYear;
  final double? minRating;
  final double? maxRating;
  final double? minPopularity;
  final double? maxPopularity;
  final int? minVoteCount;
  final int? minEpisodeCount;
  final List<int>? genreIds;
  final List<String>? languages;
  final bool? onlyRated;
  final TMDBSortBy? sortBy;
  final TMDBSortOrder? sortOrder;
  final int? limit;

  TMDBFilterOptions({
    this.startYear,
    this.endYear,
    this.minRating,
    this.maxRating,
    this.minPopularity,
    this.maxPopularity,
    this.minVoteCount,
    this.minEpisodeCount,
    this.genreIds,
    this.languages,
    this.onlyRated,
    this.sortBy,
    this.sortOrder,
    this.limit,
  });

  /// 转换为查询参数
  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    if (startYear != null) params['startYear'] = startYear.toString();
    if (endYear != null) params['endYear'] = endYear.toString();
    if (minRating != null) params['minRating'] = minRating.toString();
    if (maxRating != null) params['maxRating'] = maxRating.toString();
    if (minPopularity != null) params['minPopularity'] = minPopularity.toString();
    if (maxPopularity != null) params['maxPopularity'] = maxPopularity.toString();
    if (minVoteCount != null) params['minVoteCount'] = minVoteCount.toString();
    if (minEpisodeCount != null) params['minEpisodeCount'] = minEpisodeCount.toString();
    if (genreIds != null && genreIds!.isNotEmpty) {
      params['genreIds'] = genreIds!.join(',');
    }
    if (languages != null && languages!.isNotEmpty) {
      params['languages'] = languages!.join(',');
    }
    if (onlyRated == true) params['onlyRated'] = 'true';
    if (sortBy != null) params['sortBy'] = sortBy!.value;
    if (sortOrder != null) params['sortOrder'] = sortOrder!.value;
    if (limit != null) params['limit'] = limit.toString();
    return params;
  }

  /// 复制并修改
  TMDBFilterOptions copyWith({
    int? startYear,
    int? endYear,
    double? minRating,
    double? maxRating,
    double? minPopularity,
    double? maxPopularity,
    int? minVoteCount,
    int? minEpisodeCount,
    List<int>? genreIds,
    List<String>? languages,
    bool? onlyRated,
    TMDBSortBy? sortBy,
    TMDBSortOrder? sortOrder,
    int? limit,
  }) {
    return TMDBFilterOptions(
      startYear: startYear ?? this.startYear,
      endYear: endYear ?? this.endYear,
      minRating: minRating ?? this.minRating,
      maxRating: maxRating ?? this.maxRating,
      minPopularity: minPopularity ?? this.minPopularity,
      maxPopularity: maxPopularity ?? this.maxPopularity,
      minVoteCount: minVoteCount ?? this.minVoteCount,
      minEpisodeCount: minEpisodeCount ?? this.minEpisodeCount,
      genreIds: genreIds ?? this.genreIds,
      languages: languages ?? this.languages,
      onlyRated: onlyRated ?? this.onlyRated,
      sortBy: sortBy ?? this.sortBy,
      sortOrder: sortOrder ?? this.sortOrder,
      limit: limit ?? this.limit,
    );
  }
}

/// TMDB 演员搜索服务
class TMDBActorService {
  static const Duration _timeout = Duration(seconds: 30);

  // 内存缓存
  static final Map<String, TMDBActorSearchResult> _cache = {};
  static const Duration _cacheDuration = Duration(hours: 1);
  static final Map<String, DateTime> _cacheTime = {};

  /// 搜索演员作品
  static Future<TMDBActorSearchResult> searchActorWorks({
    required String actorName,
    TMDBContentType type = TMDBContentType.movie,
    TMDBFilterOptions? filterOptions,
  }) async {
    if (actorName.trim().isEmpty) {
      return TMDBActorSearchResult.error('演员名字不能为空');
    }

    // 构建缓存 key
    final filterParams = filterOptions?.toQueryParams() ?? {};
    final cacheKey = 'tmdb_actor_${actorName}_${type.value}_${filterParams.toString()}';

    // 检查缓存
    if (_cache.containsKey(cacheKey) && _cacheTime.containsKey(cacheKey)) {
      final cacheAge = DateTime.now().difference(_cacheTime[cacheKey]!);
      if (cacheAge < _cacheDuration) {
        debugPrint('[TMDB演员] 使用缓存: $actorName');
        return _cache[cacheKey]!;
      }
    }

    try {
      final baseUrl = await UserDataService.getServerUrl();
      if (baseUrl == null) {
        return TMDBActorSearchResult.error('服务器地址未配置');
      }

      final cookies = await UserDataService.getCookies();

      // 构建查询参数
      final queryParams = <String, String>{
        'actor': actorName.trim(),
        'type': type.value,
        ...filterParams,
      };

      final uri = Uri.parse('$baseUrl/api/tmdb/actor')
          .replace(queryParameters: queryParams);

      debugPrint('[TMDB演员] 请求: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (cookies != null) 'Cookie': cookies,
        },
      ).timeout(_timeout);

      debugPrint('[TMDB演员] 响应状态: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['code'] == 200) {
          final list = (data['list'] as List<dynamic>?)
                  ?.map((v) => TMDBActorWork.fromJson(v as Map<String, dynamic>))
                  .toList() ??
              [];

          final result = TMDBActorSearchResult(
            success: true,
            list: list,
            total: data['total'] as int?,
          );

          // 缓存结果
          _cache[cacheKey] = result;
          _cacheTime[cacheKey] = DateTime.now();

          debugPrint('[TMDB演员] 成功: ${list.length} 个结果');
          return result;
        } else {
          return TMDBActorSearchResult.error(data['message'] ?? data['error'] ?? 'TMDB 演员搜索失败');
        }
      } else if (response.statusCode == 503) {
        final data = json.decode(response.body);
        return TMDBActorSearchResult.error(data['error'] ?? 'TMDB 演员搜索功能未启用');
      } else if (response.statusCode == 400) {
        final data = json.decode(response.body);
        return TMDBActorSearchResult.error(data['error'] ?? '参数错误');
      } else {
        return TMDBActorSearchResult.error('TMDB 演员搜索失败: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[TMDB演员] 异常: $e');
      if (e.toString().contains('TimeoutException')) {
        return TMDBActorSearchResult.error('请求超时，请稍后重试');
      }
      return TMDBActorSearchResult.error('网络错误: $e');
    }
  }

  /// 清除缓存
  static void clearCache() {
    _cache.clear();
    _cacheTime.clear();
  }
}
