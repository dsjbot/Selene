import 'package:flutter/material.dart';
import '../models/danmaku.dart';

/// 单条弹幕Widget - 使用独立动画
class _DanmakuItem extends StatefulWidget {
  final String text;
  final Color color;
  final double fontSize;
  final double opacity;
  final double duration;
  final double top;
  final int mode;
  final double screenWidth;
  final double textWidth;

  const _DanmakuItem({
    super.key,
    required this.text,
    required this.color,
    required this.fontSize,
    required this.opacity,
    required this.duration,
    required this.top,
    required this.mode,
    required this.screenWidth,
    required this.textWidth,
  });

  @override
  State<_DanmakuItem> createState() => _DanmakuItemState();
}

class _DanmakuItemState extends State<_DanmakuItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (widget.duration * 1000).toInt()),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      widget.text,
      style: TextStyle(
        color: widget.color.withOpacity(widget.opacity),
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w500,
        shadows: const [
          Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black87),
        ],
      ),
    );

    // 固定弹幕（顶部/底部）- 居中显示
    if (widget.mode != 0) {
      return Positioned(
        top: widget.top,
        left: 0,
        right: 0,
        child: Center(child: textWidget),
      );
    }

    // 滚动弹幕 - 从右到左
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        // 从屏幕右边缘开始，移动到完全离开左边缘
        // 总移动距离 = 屏幕宽度 + 弹幕宽度
        final totalDistance = widget.screenWidth + widget.textWidth;
        final left = widget.screenWidth - totalDistance * progress;
        return Positioned(
          top: widget.top,
          left: left,
          child: child!,
        );
      },
      child: textWidget,
    );
  }
}

/// 轨道信息 - 记录每条轨道上弹幕的占用情况
class _TrackInfo {
  // 上一条弹幕尾部离开屏幕右边缘的时间（新弹幕可以开始进入的时间）
  double availableTime;
  
  _TrackInfo() : availableTime = 0;
  
  void reset() {
    availableTime = 0;
  }
}

/// 弹幕管理数据
class _PendingDanmaku {
  final DanmakuItem item;
  final int track;
  final double duration;
  final Color color;
  final Key key;
  final double startTime;
  final double textWidth;

  _PendingDanmaku({
    required this.item,
    required this.track,
    required this.duration,
    required this.color,
    required this.key,
    required this.startTime,
    required this.textWidth,
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
  final List<_PendingDanmaku> _visibleDanmakus = [];
  final List<_TrackInfo> _tracks = [];
  int _nextIndex = 0;
  double _lastTime = -999;
  int _keyCounter = 0;
  double _screenWidth = 0;

  static const double _baseDuration = 10.0; // 弹幕滚动时间
  static const double _trackHeight = 32.0;

  @override
  void didUpdateWidget(DanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.danmakuList != oldWidget.danmakuList) {
      _reset();
      return;
    }

    if (!widget.enabled || widget.danmakuList.isEmpty || !widget.isPlaying) {
      return;
    }

    final currentTime = widget.currentPosition.inMilliseconds / 1000.0;

    // 检测 seek（跳转超过2秒）
    if ((currentTime - _lastTime).abs() > 2.0) {
      _onSeek(currentTime);
    }
    _lastTime = currentTime;

    _processNewDanmakus(currentTime);
    _removeExpiredDanmakus(currentTime);
  }

  void _reset() {
    setState(() {
      _visibleDanmakus.clear();
      for (var track in _tracks) {
        track.reset();
      }
      _nextIndex = 0;
      _lastTime = -999;
    });
  }

  void _onSeek(double time) {
    _visibleDanmakus.clear();
    for (var track in _tracks) {
      track.reset();
    }
    // 二分查找定位到目标时间
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

  void _processNewDanmakus(double currentTime) {
    final duration = _baseDuration / widget.speed;
    bool changed = false;

    while (_nextIndex < widget.danmakuList.length) {
      final item = widget.danmakuList[_nextIndex];

      // 还没到显示时间
      if (item.time > currentTime + 0.1) break;

      // 已经过期的弹幕跳过
      if (item.time < currentTime - 0.5) {
        _nextIndex++;
        continue;
      }

      // 尝试添加弹幕
      if (_tryAddDanmaku(item, currentTime, duration)) {
        changed = true;
      }
      _nextIndex++;
    }

    if (changed) {
      setState(() {});
    }
  }

  void _removeExpiredDanmakus(double currentTime) {
    final duration = _baseDuration / widget.speed;
    final before = _visibleDanmakus.length;
    _visibleDanmakus.removeWhere((d) => currentTime > d.startTime + duration + 0.5);
    if (_visibleDanmakus.length != before) {
      setState(() {});
    }
  }

  double _estimateTextWidth(String text) {
    // 估算文字宽度：中文字符约等于字体大小，英文约0.6倍
    double width = 0;
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code > 127) {
        width += widget.fontSize; // 中文等宽字符
      } else {
        width += widget.fontSize * 0.5; // ASCII字符
      }
    }
    return width + 10; // 加一点边距
  }

  bool _tryAddDanmaku(DanmakuItem item, double currentTime, double duration) {
    if (_tracks.isEmpty || _screenWidth <= 0) return false;

    // 估算弹幕宽度
    final textWidth = _estimateTextWidth(item.text);
    
    // 弹幕速度 = 总移动距离 / 时间
    final totalDistance = _screenWidth + textWidth;
    final speed = totalDistance / duration;
    
    // 弹幕尾部完全进入屏幕所需时间（即尾部离开右边缘）
    final tailEnterTime = textWidth / speed;

    int? track;
    for (int i = 0; i < _tracks.length; i++) {
      // 检查轨道是否可用：上一条弹幕的尾部已经完全进入屏幕
      if (currentTime >= _tracks[i].availableTime) {
        track = i;
        break;
      }
    }

    if (track == null) return false; // 所有轨道都被占用

    Color color = Colors.white;
    try {
      final hex = item.color.replaceFirst('#', '');
      if (hex.length == 6) {
        color = Color(int.parse('FF$hex', radix: 16));
      }
    } catch (_) {}

    _visibleDanmakus.add(_PendingDanmaku(
      item: item,
      track: track,
      duration: duration,
      color: color,
      key: ValueKey(_keyCounter++),
      startTime: currentTime,
      textWidth: textWidth,
    ));

    // 更新轨道可用时间：当前时间 + 尾部进入时间 + 小间隔
    _tracks[track].availableTime = currentTime + tailEnterTime + 0.3;

    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.danmakuList.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _screenWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight * widget.areaHeight;
        final trackCount = (availableHeight / _trackHeight).floor();
        
        // 调整轨道数量
        while (_tracks.length < trackCount) {
          _tracks.add(_TrackInfo());
        }
        while (_tracks.length > trackCount) {
          _tracks.removeLast();
        }

        return ClipRect(
          child: SizedBox(
            width: constraints.maxWidth,
            height: availableHeight,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: _visibleDanmakus.map<Widget>((d) {
                return _DanmakuItem(
                  key: d.key,
                  text: d.item.text,
                  color: d.color,
                  fontSize: widget.fontSize,
                  opacity: widget.opacity,
                  duration: d.duration,
                  top: d.track * _trackHeight,
                  mode: d.item.mode,
                  screenWidth: constraints.maxWidth,
                  textWidth: d.textWidth,
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}
