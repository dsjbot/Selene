/// 短剧分类
class ShortDramaCategory {
  final int typeId;
  final String typeName;

  ShortDramaCategory({
    required this.typeId,
    required this.typeName,
  });

  factory ShortDramaCategory.fromJson(Map<String, dynamic> json) {
    return ShortDramaCategory(
      typeId: json['type_id'] ?? json['typeId'] ?? json['id'] ?? 0,
      typeName: json['type_name'] ?? json['typeName'] ?? json['name'] ?? '',
    );
  }
}

/// 短剧列表项
class ShortDramaItem {
  final int id;
  final String name;
  final String cover;
  final String updateTime;
  final double score;
  final int episodeCount;
  final String description;

  ShortDramaItem({
    required this.id,
    required this.name,
    required this.cover,
    required this.updateTime,
    required this.score,
    required this.episodeCount,
    required this.description,
  });

  factory ShortDramaItem.fromJson(Map<String, dynamic> json) {
    return ShortDramaItem(
      id: json['id'] ?? 0,
      name: json['name'] ?? json['title'] ?? '',
      cover: json['cover'] ?? json['poster'] ?? json['image'] ?? '',
      updateTime: json['update_time'] ?? json['updateTime'] ?? json['time'] ?? '',
      score: _parseDouble(json['score'] ?? json['rating']),
      episodeCount: json['episode_count'] ?? json['episodeCount'] ?? json['episodes'] ?? 1,
      description: json['description'] ?? json['desc'] ?? json['intro'] ?? '',
    );
  }

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}

/// 短剧列表响应
class ShortDramaListResponse {
  final List<ShortDramaItem> list;
  final bool hasMore;

  ShortDramaListResponse({
    required this.list,
    required this.hasMore,
  });

  factory ShortDramaListResponse.fromJson(Map<String, dynamic> json) {
    // 尝试多种可能的字段名
    final listData = json['list'] ?? json['data'] ?? json['items'] ?? json['results'] ?? [];
    final list = (listData as List<dynamic>?)
            ?.map((e) => ShortDramaItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return ShortDramaListResponse(
      list: list,
      hasMore: json['hasMore'] ?? json['has_more'] ?? json['hasNext'] ?? false,
    );
  }
}

/// 短剧详情
class ShortDramaDetail {
  final String id;
  final String title;
  final String poster;
  final List<String> episodes;
  final List<String> episodesTitles;
  final String source;
  final String sourceName;
  final String year;
  final String desc;
  final String typeName;
  final String dramaName;

  ShortDramaDetail({
    required this.id,
    required this.title,
    required this.poster,
    required this.episodes,
    required this.episodesTitles,
    required this.source,
    required this.sourceName,
    required this.year,
    required this.desc,
    required this.typeName,
    required this.dramaName,
  });

  factory ShortDramaDetail.fromJson(Map<String, dynamic> json) {
    // 处理 episodes 字段，可能是数组或数字
    List<String> episodes = [];
    List<String> episodesTitles = [];
    
    final episodesData = json['episodes'] ?? json['episode_list'];
    if (episodesData is List) {
      episodes = episodesData.map((e) => e.toString()).toList();
    } else if (episodesData is int) {
      // 如果是数字，生成集数列表
      episodes = List.generate(episodesData, (i) => (i + 1).toString());
    } else if (json['episode_count'] != null) {
      final count = json['episode_count'] is int 
          ? json['episode_count'] 
          : int.tryParse(json['episode_count'].toString()) ?? 1;
      episodes = List.generate(count, (i) => (i + 1).toString());
    }
    
    final titlesData = json['episodes_titles'] ?? json['episode_titles'];
    if (titlesData is List) {
      episodesTitles = titlesData.map((e) => e.toString()).toList();
    }
    
    // 如果没有标题，使用默认标题
    if (episodesTitles.isEmpty && episodes.isNotEmpty) {
      episodesTitles = episodes.map((e) => '第$e集').toList();
    }

    return ShortDramaDetail(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? json['name'] ?? '',
      poster: json['poster'] ?? json['cover'] ?? json['image'] ?? '',
      episodes: episodes,
      episodesTitles: episodesTitles,
      source: json['source'] ?? 'shortdrama',
      sourceName: json['source_name'] ?? json['sourceName'] ?? '短剧',
      year: json['year'] ?? '',
      desc: json['desc'] ?? json['description'] ?? json['intro'] ?? '',
      typeName: json['type_name'] ?? json['typeName'] ?? '短剧',
      dramaName: json['drama_name'] ?? json['dramaName'] ?? json['name'] ?? '',
    );
  }
}

/// 短剧解析结果
class ShortDramaParseResult {
  final String url;
  final String originalUrl;
  final String proxyUrl;
  final String title;
  final int episode;
  final int totalEpisodes;

  ShortDramaParseResult({
    required this.url,
    required this.originalUrl,
    required this.proxyUrl,
    required this.title,
    required this.episode,
    required this.totalEpisodes,
  });

  factory ShortDramaParseResult.fromJson(Map<String, dynamic> json) {
    return ShortDramaParseResult(
      url: json['url'] ?? json['playUrl'] ?? json['play_url'] ?? '',
      originalUrl: json['originalUrl'] ?? json['original_url'] ?? json['url'] ?? '',
      proxyUrl: json['proxyUrl'] ?? json['proxy_url'] ?? '',
      title: json['title'] ?? json['name'] ?? '',
      episode: json['episode'] ?? 1,
      totalEpisodes: json['totalEpisodes'] ?? json['total_episodes'] ?? json['total'] ?? 1,
    );
  }
}
