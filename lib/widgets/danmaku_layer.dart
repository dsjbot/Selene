import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

  const _DanmakuItem({
    required this.text,
    required this.color,
    required this.fontSize,
    required this.opacity,
    required this.duration,
    required this.top,
    required this.mode,
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          top: widget.top,
          right: widget.mode == 0
              ? null
              : null, // 固定弹幕居中处理
          left: widget.mode == 0
              ? _calculateLeft(context)
              : null,
          child: widget.mode == 0
              ? child!
              : Center(child: child),
        );
      },
      child: Text(
        widget.text,
        style: TextStyle(
          color: widget.color.withOpacity(widget.opacity),
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w500,
          shadows: const [
            Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black87),
          ],
        ),
      ),
    );
  }

  double _calculateLeft(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // 从右边进入，到左边消失
    final progress = _controller.value;
    return screenWidth - (screenWidth + 300) * progress;
  }
}

/// 弹幕管理数据
class _PendingDanmaku {
  final DanmakuItem item;
  final int track;
  final double duration;
  final Color color;
  final Key key;

  _PendingDanmaku({
    required this.item,
    required this.track,
    required this.duration,
    required this.color,
    required this.key,
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
  final List<double> _trackEndTimes = [];
  int _nextIndex = 0;
  double _lastTime = -999;
  int _keyCounter = 0;

  static const double _baseDuration = 8.0;
  static const double _trackHeight = 30.0;
  static const int _maxVisible = 30;

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

    // 检测 seek
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
      _trackEndTimes.clear();
      _nextIndex = 0;
      _lastTime = -999;
    });
  }

  void _onSeek(double time) {
    _visibleDanmakus.clear();
    for (int i = 0; i < _trackEndTimes.length; i++) {
      _trackEndTimes[i] = 0;
    }
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

    while (_nextIndex < widget.danmakuList.length &&
        _visibleDanmakus.length < _maxVisible) {
      final item = widget.danmakuList[_nextIndex];

      if (item.time > currentTime + 0.1) break;

      if (item.time >= currentTime - 0.5) {
        if (_tryAddDanmaku(item, currentTime, duration)) {
          changed = true;
        }
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
    _visibleDanmakus.removeWhere((d) => currentTime > d.item.time + duration + 0.5);
    if (_visibleDanmakus.length != before) {
      setState(() {});
    }
  }

  bool _tryAddDanmaku(DanmakuItem item, double currentTime, double duration) {
    if (_trackEndTimes.isEmpty) return false;

    int? track;
    for (int i = 0; i < _trackEndTimes.length; i++) {
      if (currentTime >= _trackEndTimes[i]) {
        track = i;
        break;
      }
    }
    if (track == null) return false;

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
    ));

    _trackEndTimes[track] = currentTime + duration * 0.4;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.danmakuList.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackCount =
            (constraints.maxHeight * widget.areaHeight / _trackHeight).floor();
        while (_trackEndTimes.length < trackCount) {
          _trackEndTimes.add(0);
        }

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: _visibleDanmakus.map((d) {
            return _DanmakuItem(
              key: d.key,
              text: d.item.text,
              color: d.color,
              fontSize: widget.fontSize,
              opacity: widget.opacity,
              duration: d.duration,
              top: d.track * _trackHeight,
              mode: d.item.mode,
            );
          }).toList(),
        );
      },
    );
  }
}
