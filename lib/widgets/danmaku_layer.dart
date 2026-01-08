import 'package:flutter/material.dart';
import '../models/danmaku.dart';

/// 单条弹幕数据
class _DanmakuData {
  final String text;
  final double startTime;
  final double duration;
  final int track;
  final Color color;
  final int mode;

  _DanmakuData({
    required this.text,
    required this.startTime,
    required this.duration,
    required this.track,
    required this.color,
    required this.mode,
  });
}

/// 弹幕层组件
class DanmakuLayer extends StatefulWidget {
  final List<DanmakuItem> danmakuList;
  final Duration currentPosition;
  final bool isPlaying;
  final bool enabled;
  final double opacity;
  final double fontSize;
  final double speed;
  final double areaHeight;

  const DanmakuLayer({
    super.key,
    required this.danmakuList,
    required this.currentPosition,
    required this.isPlaying,
    this.enabled = true,
    this.opacity = 1.0,
    this.fontSize = 20.0,
    this.speed = 1.0,
    this.areaHeight = 0.5,
  });

  @override
  State<DanmakuLayer> createState() => _DanmakuLayerState();
}

class _DanmakuLayerState extends State<DanmakuLayer> {
  final List<_DanmakuData> _activeDanmakus = [];
  final List<double> _trackEndTimes = [];
  int _nextIndex = 0;
  double _lastSeekTime = -999;

  static const double _baseDuration = 10.0;
  static const double _trackHeight = 28.0;

  @override
  void didUpdateWidget(DanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.danmakuList != oldWidget.danmakuList) {
      _reset();
      return;
    }

    if (!widget.enabled || widget.danmakuList.isEmpty) return;

    final currentTime = widget.currentPosition.inMilliseconds / 1000.0;

    // 检测 seek（跳跃超过3秒）
    if ((currentTime - _lastSeekTime).abs() > 3.0) {
      _onSeek(currentTime);
    }
    _lastSeekTime = currentTime;

    if (widget.isPlaying) {
      _updateDanmakus(currentTime);
    }
  }

  void _reset() {
    _activeDanmakus.clear();
    _trackEndTimes.clear();
    _nextIndex = 0;
    _lastSeekTime = -999;
  }

  void _onSeek(double time) {
    _activeDanmakus.clear();
    for (int i = 0; i < _trackEndTimes.length; i++) {
      _trackEndTimes[i] = 0;
    }
    // 二分查找新位置
    int left = 0, right = widget.danmakuList.length;
    while (left < right) {
      int mid = (left + right) ~/ 2;
      if (widget.danmakuList[mid].time < time) {
        left = mid + 1;
      } else {
        right = mid;
      }
    }
    _nextIndex = left;
  }

  void _updateDanmakus(double currentTime) {
    final duration = _baseDuration / widget.speed;

    // 移除过期弹幕
    _activeDanmakus.removeWhere((d) => currentTime > d.startTime + d.duration);

    // 添加新弹幕（每次最多添加5条）
    int added = 0;
    while (_nextIndex < widget.danmakuList.length && added < 5) {
      final item = widget.danmakuList[_nextIndex];

      if (item.time > currentTime + 0.2) break;

      if (item.time >= currentTime - duration) {
        _tryAddDanmaku(item, currentTime, duration);
        added++;
      }
      _nextIndex++;
    }
  }

  void _tryAddDanmaku(DanmakuItem item, double currentTime, double duration) {
    if (_trackEndTimes.isEmpty) return;

    // 找可用轨道
    int? track;
    for (int i = 0; i < _trackEndTimes.length; i++) {
      if (currentTime >= _trackEndTimes[i]) {
        track = i;
        break;
      }
    }
    if (track == null) return;

    // 解析颜色
    Color color = Colors.white;
    try {
      final hex = item.color.replaceFirst('#', '');
      if (hex.length == 6) {
        color = Color(int.parse('FF$hex', radix: 16));
      }
    } catch (_) {}

    _activeDanmakus.add(_DanmakuData(
      text: item.text,
      startTime: item.time,
      duration: duration,
      track: track,
      color: color,
      mode: item.mode,
    ));

    // 更新轨道占用时间
    _trackEndTimes[track] = item.time + duration * 0.35;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.danmakuList.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 初始化轨道
        final trackCount = (constraints.maxHeight * widget.areaHeight / _trackHeight).floor();
        while (_trackEndTimes.length < trackCount) {
          _trackEndTimes.add(0);
        }

        final currentTime = widget.currentPosition.inMilliseconds / 1000.0;
        final screenWidth = constraints.maxWidth;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: _activeDanmakus.map((d) {
            final progress = ((currentTime - d.startTime) / d.duration).clamp(0.0, 1.0);

            double left;
            if (d.mode == 1 || d.mode == 2) {
              // 顶部/底部固定弹幕
              left = screenWidth / 2;
            } else {
              // 滚动弹幕
              left = screenWidth * (1 - progress) - 100 * progress;
            }

            return Positioned(
              left: left,
              top: d.track * _trackHeight,
              child: Text(
                d.text,
                style: TextStyle(
                  color: d.color.withOpacity(widget.opacity),
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w500,
                  shadows: const [
                    Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black87),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
