/// 跳过片段类型
enum SkipSegmentType { opening, ending }

/// 时间模式
enum SkipTimeMode { absolute, remaining }

/// 单个跳过片段
class SkipSegment {
  final double start; // 开始时间（秒）
  final double end; // 结束时间（秒）
  final SkipSegmentType type;
  final String? title;
  final bool autoSkip;
  final bool autoNextEpisode;
  final SkipTimeMode mode;
  final double? remainingTime;

  SkipSegment({
    required this.start,
    required this.end,
    required this.type,
    this.title,
    this.autoSkip = true,
    this.autoNextEpisode = true,
    this.mode = SkipTimeMode.absolute,
    this.remainingTime,
  });

  factory SkipSegment.fromJson(Map<String, dynamic> json) {
    return SkipSegment(
      start: (json['start'] ?? 0).toDouble(),
      end: (json['end'] ?? 0).toDouble(),
      type: json['type'] == 'ending' ? SkipSegmentType.ending : SkipSegmentType.opening,
      title: json['title'],
      autoSkip: json['autoSkip'] ?? true,
      autoNextEpisode: json['autoNextEpisode'] ?? true,
      mode: json['mode'] == 'remaining' ? SkipTimeMode.remaining : SkipTimeMode.absolute,
      remainingTime: json['remainingTime']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start': start,
      'end': end,
      'type': type == SkipSegmentType.ending ? 'ending' : 'opening',
      if (title != null) 'title': title,
      'autoSkip': autoSkip,
      'autoNextEpisode': autoNextEpisode,
      'mode': mode == SkipTimeMode.remaining ? 'remaining' : 'absolute',
      if (remainingTime != null) 'remainingTime': remainingTime,
    };
  }
}

/// 剧集跳过配置
class EpisodeSkipConfig {
  final String source;
  final String id;
  final String title;
  final List<SkipSegment> segments;
  final int updatedTime;

  EpisodeSkipConfig({
    required this.source,
    required this.id,
    required this.title,
    required this.segments,
    required this.updatedTime,
  });

  factory EpisodeSkipConfig.fromJson(Map<String, dynamic> json) {
    final segmentsList = json['segments'] as List<dynamic>? ?? [];
    return EpisodeSkipConfig(
      source: json['source'] ?? '',
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      segments: segmentsList.map((e) => SkipSegment.fromJson(e)).toList(),
      updatedTime: json['updated_time'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'source': source,
      'id': id,
      'title': title,
      'segments': segments.map((e) => e.toJson()).toList(),
      'updated_time': updatedTime,
    };
  }

  /// 创建默认配置（片头90秒，片尾剩余2分钟）
  factory EpisodeSkipConfig.defaultConfig({
    required String source,
    required String id,
    required String title,
  }) {
    return EpisodeSkipConfig(
      source: source,
      id: id,
      title: title,
      segments: [
        SkipSegment(
          start: 0,
          end: 90,
          type: SkipSegmentType.opening,
          title: '片头',
          autoSkip: true,
        ),
        SkipSegment(
          start: 0,
          end: 120,
          type: SkipSegmentType.ending,
          title: '片尾',
          autoSkip: true,
          autoNextEpisode: true,
          mode: SkipTimeMode.remaining,
          remainingTime: 120,
        ),
      ],
      updatedTime: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
