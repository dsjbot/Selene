/// 弹幕数据模型
class DanmakuItem {
  final String text;
  final double time; // 秒
  final String color;
  final int mode; // 0: 滚动, 1: 顶部, 2: 底部

  DanmakuItem({
    required this.text,
    required this.time,
    this.color = '#FFFFFF',
    this.mode = 0,
  });

  factory DanmakuItem.fromJson(Map<String, dynamic> json) {
    return DanmakuItem(
      text: json['text'] ?? '',
      time: (json['time'] ?? 0).toDouble(),
      color: json['color'] ?? '#FFFFFF',
      mode: json['mode'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'time': time,
      'color': color,
      'mode': mode,
    };
  }
}

/// 弹幕响应数据
class DanmakuResponse {
  final bool success;
  final int count;
  final List<DanmakuItem> danmakuList;
  final String? error;

  DanmakuResponse({
    required this.success,
    required this.count,
    required this.danmakuList,
    this.error,
  });

  factory DanmakuResponse.fromJson(Map<String, dynamic> json) {
    final List<dynamic> list = json['danmakuList'] ?? [];
    return DanmakuResponse(
      success: json['success'] ?? false,
      count: json['count'] ?? 0,
      danmakuList: list.map((e) => DanmakuItem.fromJson(e)).toList(),
      error: json['error'],
    );
  }

  factory DanmakuResponse.error(String message) {
    return DanmakuResponse(
      success: false,
      count: 0,
      danmakuList: [],
      error: message,
    );
  }
}
