import 'dart:math';
import 'package:flutter/material.dart';
import '../models/danmaku.dart';

/// 弹幕轨道信息
class _DanmakuTrack {
  double endTime;
  _DanmakuTrack({this.endTime = 0});
}

/// 活跃弹幕信息
class _ActiveDanmaku {
  final DanmakuItem item;
  final int track;
  final double startTime;
  final double duration;
  final double width;
  final Color color;

  _ActiveDanmaku({
    required this.item,
    required this.track,
    required this.startTime,
    required this.duration,
    required this.width,
    required this.color,
  });
}

/// 弹幕层组件 - 使用 CustomPainter 优化性能
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
    this.fontSize = 18.0,
    this.speed = 1.0,
    this.areaHeight = 0.5,
  });

  @override
  State<DanmakuLayer> createState() => _DanmakuLayerState();
}

class _DanmakuLayerState extends State<DanmakuLayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_ActiveDanmaku> _activeDanmakus = [];
  final List<_DanmakuTrack> _tracks = [];
  int _lastProcessedIndex = 0;
  double _lastPosition = 0;
  final Random _random = Random();

  static const double _baseDuration = 8.0;
  static const double _trackHeight = 30.0;
  static const int _maxActiveDanmakus = 30; // 减少同时显示数量

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onTick);
    
    if (widget.isPlaying && widget.enabled) {
      _controller.repeat();
    }
  }

  void _onTick() {
    if (!mounted || !widget.enabled || widget.danmakuList.isEmpty) return;
    _updateDanmakus();
  }

  @override
  void didUpdateWidget(DanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.danmakuList != oldWidget.danmakuList) {
      _reset();
    }

    final currentSeconds = widget.currentPosition.inMilliseconds / 1000.0;
    if ((currentSeconds - _lastPosition).abs() > 2.0) {
      _onSeek(currentSeconds);
    }
    _lastPosition = currentSeconds;

    if (widget.isPlaying && widget.enabled) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    _activeDanmakus.clear();
    _lastProcessedIndex = 0;
    _lastPosition = 0;
    _tracks.clear();
  }

  void _onSeek(double newPosition) {
    _activeDanmakus.clear();
    _lastProcessedIndex = _findDanmakuIndex(newPosition);
  }

  int _findDanmakuIndex(double time) {
    int left = 0;
    int right = widget.danmakuList.length;
    while (left < right) {
      int mid = (left + right) ~/ 2;
      if (widget.danmakuList[mid].time < time) {
        left = mid + 1;
      } else {
        right = mid;
      }
    }
    return left;
  }

  void _updateDanmakus() {
    if (_tracks.isEmpty) return;

    final currentTime = widget.currentPosition.inMilliseconds / 1000.0;
    final duration = _baseDuration / widget.speed;

    // 移除过期弹幕
    _activeDanmakus.removeWhere((d) => currentTime > d.startTime + d.duration);

    // 添加新弹幕
    int addedCount = 0;
    while (_lastProcessedIndex < widget.danmakuList.length &&
        _activeDanmakus.length < _maxActiveDanmakus &&
        addedCount < 3) { // 每帧最多添加3条
      final danmaku = widget.danmakuList[_lastProcessedIndex];

      if (danmaku.time > currentTime + 0.1) break;

      if (danmaku.time < currentTime - duration) {
        _lastProcessedIndex++;
        continue;
      }

      if (_tryAddDanmaku(danmaku, currentTime, duration)) {
        addedCount++;
      }
      _lastProcessedIndex++;
    }
  }

  bool _tryAddDanmaku(DanmakuItem danmaku, double currentTime, double duration) {
    if (_tracks.isEmpty) return false;

    final textWidth = _estimateTextWidth(danmaku.text, widget.fontSize);
    
    int? track = _findAvailableTrack(currentTime);
    if (track == null) return false;

    Color color;
    try {
      final colorStr = danmaku.color.replaceFirst('#', '');
      color = Color(int.parse('FF$colorStr', radix: 16));
    } catch (e) {
      color = Colors.white;
    }

    _activeDanmakus.add(_ActiveDanmaku(
      item: danmaku,
      track: track,
      startTime: danmaku.time,
      duration: duration,
      width: textWidth,
      color: color,
    ));

    _tracks[track].endTime = danmaku.time + duration * 0.35;
    return true;
  }

  int? _findAvailableTrack(double currentTime) {
    if (_tracks.isEmpty) return null;
    final startTrack = _random.nextInt(_tracks.length);

    for (int i = 0; i < _tracks.length; i++) {
      final trackIndex = (startTrack + i) % _tracks.length;
      if (currentTime > _tracks[trackIndex].endTime) {
        return trackIndex;
      }
    }
    return null;
  }

  double _estimateTextWidth(String text, double fontSize) {
    double width = 0;
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      width += code > 127 ? fontSize : fontSize * 0.5;
    }
    return width + 16;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.danmakuList.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight * widget.areaHeight;
        final trackCount = (availableHeight / _trackHeight).floor();

        while (_tracks.length < trackCount) {
          _tracks.add(_DanmakuTrack());
        }
        while (_tracks.length > trackCount) {
          _tracks.removeLast();
        }

        return RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _DanmakuPainter(
                  danmakus: List.from(_activeDanmakus),
                  currentTime: widget.currentPosition.inMilliseconds / 1000.0,
                  screenWidth: constraints.maxWidth,
                  trackHeight: _trackHeight,
                  fontSize: widget.fontSize,
                  opacity: widget.opacity,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// 弹幕绘制器 - 使用 Canvas 直接绘制，性能更好
class _DanmakuPainter extends CustomPainter {
  final List<_ActiveDanmaku> danmakus;
  final double currentTime;
  final double screenWidth;
  final double trackHeight;
  final double fontSize;
  final double opacity;

  _DanmakuPainter({
    required this.danmakus,
    required this.currentTime,
    required this.screenWidth,
    required this.trackHeight,
    required this.fontSize,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final danmaku in danmakus) {
      final elapsed = currentTime - danmaku.startTime;
      final progress = (elapsed / danmaku.duration).clamp(0.0, 1.0);

      double left;
      if (danmaku.item.mode == 1 || danmaku.item.mode == 2) {
        left = (screenWidth - danmaku.width) / 2;
      } else {
        left = screenWidth - (screenWidth + danmaku.width) * progress;
      }

      final top = danmaku.track * trackHeight;

      // 绘制文字阴影
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(opacity * 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

      final textStyle = TextStyle(
        color: danmaku.color.withOpacity(opacity),
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
      );

      final textSpan = TextSpan(text: danmaku.item.text, style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      // 绘制阴影
      canvas.drawRect(
        Rect.fromLTWH(left + 1, top + 1, textPainter.width, textPainter.height),
        shadowPaint,
      );

      // 绘制文字
      textPainter.paint(canvas, Offset(left, top));
    }
  }

  @override
  bool shouldRepaint(_DanmakuPainter oldDelegate) => true;
}
