import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/danmaku.dart';

/// 弹幕渲染数据（预计算）
class _RenderDanmaku {
  final String text;
  final double time;
  final double duration;
  final int track;
  final double width;
  final Color color;
  final int mode;
  ui.Paragraph? _paragraph;

  _RenderDanmaku({
    required this.text,
    required this.time,
    required this.duration,
    required this.track,
    required this.width,
    required this.color,
    required this.mode,
  });

  ui.Paragraph getParagraph(double fontSize) {
    if (_paragraph == null) {
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textDirection: TextDirection.ltr,
      ))
        ..pushStyle(ui.TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          shadows: [
            const ui.Shadow(offset: Offset(1, 1), blurRadius: 1, color: Colors.black),
          ],
        ))
        ..addText(text);
      _paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
    }
    return _paragraph!;
  }
}

/// 弹幕层 - 高性能实现
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

class _DanmakuLayerState extends State<DanmakuLayer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_RenderDanmaku> _visibleDanmakus = [];
  final List<double> _trackEndTimes = [];
  int _nextIndex = 0;
  double _lastTime = -1;
  
  static const double _duration = 8.0;
  static const double _trackHeight = 32.0;
  static const int _maxVisible = 40;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this);
    _startAnimation();
  }

  void _startAnimation() {
    if (widget.isPlaying && widget.enabled && widget.danmakuList.isNotEmpty) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(DanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 弹幕列表变化
    if (widget.danmakuList != oldWidget.danmakuList) {
      _reset();
    }
    
    // 检测 seek
    final time = widget.currentPosition.inMilliseconds / 1000.0;
    if ((_lastTime - time).abs() > 2.0) {
      _onSeek(time);
    }
    
    // 播放状态变化
    if (widget.isPlaying != oldWidget.isPlaying || widget.enabled != oldWidget.enabled) {
      if (widget.isPlaying && widget.enabled) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  void _reset() {
    _visibleDanmakus.clear();
    _trackEndTimes.clear();
    _nextIndex = 0;
    _lastTime = -1;
  }

  void _onSeek(double time) {
    _visibleDanmakus.clear();
    for (int i = 0; i < _trackEndTimes.length; i++) {
      _trackEndTimes[i] = 0;
    }
    // 二分查找
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.danmakuList.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(builder: (context, constraints) {
      // 初始化轨道
      final trackCount = (constraints.maxHeight * widget.areaHeight / _trackHeight).floor();
      while (_trackEndTimes.length < trackCount) _trackEndTimes.add(0);
      while (_trackEndTimes.length > trackCount) _trackEndTimes.removeLast();

      return AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final currentTime = widget.currentPosition.inMilliseconds / 1000.0;
          _lastTime = currentTime;
          final dur = _duration / widget.speed;

          // 移除过期弹幕
          _visibleDanmakus.removeWhere((d) => currentTime > d.time + d.duration);

          // 添加新弹幕
          while (_nextIndex < widget.danmakuList.length && _visibleDanmakus.length < _maxVisible) {
            final item = widget.danmakuList[_nextIndex];
            if (item.time > currentTime + 0.5) break;
            if (item.time >= currentTime - dur) {
              _tryAdd(item, currentTime, dur, constraints.maxWidth);
            }
            _nextIndex++;
          }

          return CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _DanmakuPainter(
              danmakus: _visibleDanmakus,
              currentTime: currentTime,
              screenWidth: constraints.maxWidth,
              trackHeight: _trackHeight,
              fontSize: widget.fontSize,
              opacity: widget.opacity,
            ),
          );
        },
      );
    });
  }

  void _tryAdd(DanmakuItem item, double currentTime, double dur, double screenWidth) {
    if (_trackEndTimes.isEmpty) return;
    
    // 估算宽度
    double w = 0;
    for (int i = 0; i < item.text.length; i++) {
      w += item.text.codeUnitAt(i) > 127 ? widget.fontSize : widget.fontSize * 0.5;
    }
    w += 20;

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
      color = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {}

    _visibleDanmakus.add(_RenderDanmaku(
      text: item.text,
      time: item.time,
      duration: dur,
      track: track,
      width: w,
      color: color,
      mode: item.mode,
    ));

    _trackEndTimes[track] = item.time + dur * 0.3;
  }
}

class _DanmakuPainter extends CustomPainter {
  final List<_RenderDanmaku> danmakus;
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
    for (final d in danmakus) {
      final progress = ((currentTime - d.time) / d.duration).clamp(0.0, 1.0);
      
      double x;
      if (d.mode == 1 || d.mode == 2) {
        x = (screenWidth - d.width) / 2;
      } else {
        x = screenWidth - (screenWidth + d.width) * progress;
      }
      
      final y = d.track * trackHeight;
      final paragraph = d.getParagraph(fontSize);
      
      canvas.save();
      canvas.translate(x, y);
      if (opacity < 1.0) {
        canvas.saveLayer(Rect.fromLTWH(0, 0, d.width, trackHeight), Paint()..color = Colors.white.withOpacity(opacity));
      }
      canvas.drawParagraph(paragraph, Offset.zero);
      if (opacity < 1.0) {
        canvas.restore();
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_DanmakuPainter old) => true;
}
