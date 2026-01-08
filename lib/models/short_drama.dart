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
      typeId: json['type_id'] ?? 0,
      typeName: json['type_name'] ?? '',
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
      name: json['name'] ?? '',
      cover: json['cover'] ?? '',
      updateTime: json['update_time'] ?? '',
      score: (json['score'] ?? 0).toDouble(),
      episodeCount: json['episode_count'] ?? 1,
      description: json['description'] ?? '',
    );
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
    final list = (json['list'] as List<dynamic>?)
            ?.map((e) => ShortDramaItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return ShortDramaListResponse(
      list: list,
      hasMore: json['hasMore'] ?? false,
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
    return ShortDramaDetail(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      poster: json['poster'] ?? '',
      episodes: (json['episodes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      episodesTitles: (json['episodes_titles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      source: json['source'] ?? 'shortdrama',
      sourceName: json['source_name'] ?? '短剧',
      year: json['year'] ?? '',
      desc: json['desc'] ?? '',
      typeName: json['type_name'] ?? '短剧',
      dramaName: json['drama_name'] ?? '',
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
      url: json['url'] ?? '',
      originalUrl: json['originalUrl'] ?? '',
      proxyUrl: json['proxyUrl'] ?? '',
      title: json['title'] ?? '',
      episode: json['episode'] ?? 1,
      totalEpisodes: json['totalEpisodes'] ?? 1,
    );
  }
}
