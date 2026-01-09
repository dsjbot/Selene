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

    // 滚动弹幕 - 从右到左，统一速度
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        // 从屏幕右边缘开始，移动到完全离开左边缘
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

/// 轨道信息 - 记录每条轨道上弹幕的占用情况（防重叠核心）
class _TrackInfo {
  // 上一条弹幕的信息，用于计算是否会追尾
  double lastDanmakuStartTime; // 上一条弹幕开始时间
  double lastDanmakuWidth;     // 上一条弹幕宽度
  double lastDanmakuSpeed;     // 上一条弹幕速度（像素/秒）
  
  _TrackInfo() 
      : lastDanmakuStartTime = -999,
        lastDanmakuWidth = 0,
        lastDanmakuSpeed = 0;
  
  void reset() {
    lastDanmakuStartTime = -999;
    lastDanmakuWidth = 0;
    lastDanmakuSpeed = 0;
  }
  
  /// 检查新弹幕是否可以安全进入此轨道（不会追尾）
  /// [currentTime] 当前时间
  /// [screenWidth] 屏幕宽度
  /// [newDanmakuWidth] 新弹幕宽度
  /// [newDanmakuSpeed] 新弹幕速度（像素/秒）
  /// 
  /// 由于弹幕速度根据文字长度不同而变化（短弹幕慢，长弹幕快），
  /// 需要精确计算是否会发生追尾碰撞
  bool canAccept(double currentTime, double screenWidth, double newDanmakuWidth, double newDanmakuSpeed) {
    // 如果轨道从未使用过，直接可用
    if (lastDanmakuStartTime < 0) return true;
    
    // 计算上一条弹幕当前位置（头部位置，从屏幕右边缘开始）
    final elapsed = currentTime - lastDanmakuStartTime;
    final lastDanmakuHeadPos = screenWidth - elapsed * lastDanmakuSpeed;
    final lastDanmakuTailPos = lastDanmakuHeadPos + lastDanmakuWidth;
    
    // 条件1：上一条弹幕的尾部必须已经完全进入屏幕（留出间隙）
    // 间隙 = 弹幕宽度的20%或最小30像素
    final minGap = (lastDanmakuWidth * 0.2).clamp(30.0, 100.0);
    if (lastDanmakuTailPos > screenWidth - minGap) {
      return false;
    }
    
    // 条件2：新弹幕不会追上上一条弹幕（防追尾）
    // 由于弹幕速度不同（短弹幕慢，长弹幕快），需要检查是否会追尾
    // 
    // 计算：新弹幕到达上一条弹幕当前尾部位置的时间
    // 如果新弹幕速度更快，可能会追上上一条弹幕
    if (newDanmakuSpeed > lastDanmakuSpeed) {
      // 新弹幕更快，需要检查是否会追尾
      // 相对速度 = 新弹幕速度 - 上一条弹幕速度
      final relativeSpeed = newDanmakuSpeed - lastDanmakuSpeed;
      // 当前距离 = 上一条弹幕尾部到屏幕右边缘的距离
      final currentGap = screenWidth - lastDanmakuTailPos;
      // 追上所需时间 = 距离 / 相对速度
      final catchUpTime = currentGap / relativeSpeed;
      // 上一条弹幕完全离开屏幕所需时间
      final lastDanmakuExitTime = (lastDanmakuTailPos + lastDanmakuWidth) / lastDanmakuSpeed;
      
      // 如果追上时间 < 上一条弹幕离开时间，说明会追尾
      if (catchUpTime < lastDanmakuExitTime) {
        return false;
      }
    }
    
    return true;
  }
  
  /// 更新轨道信息
  void update(double startTime, double width, double speed) {
    lastDanmakuStartTime = startTime;
    lastDanmakuWidth = width;
    lastDanmakuSpeed = speed;
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

  // 基础穿越时间（秒）- 弹幕从右边进入到左边完全消失的基准时间
  // 参考后端 artplayer-plugin-danmuku 的 speed 参数（默认5秒）
  static const double _baseDuration = 8.0;
  static const double _trackHeight = 32.0;
  
  /// 根据弹幕文字宽度计算穿越时间
  /// 短弹幕慢一些，长弹幕快一些，模拟后端的自然效果
  double _calculateDuration(double textWidth) {
    // 基准宽度（约10个中文字符）
    const double baseWidth = 200.0;
    
    // 根据文字宽度调整时间
    // 短弹幕（<100px）：时间 * 1.2（慢20%）
    // 中等弹幕（100-300px）：正常时间
    // 长弹幕（>300px）：时间 * 0.85（快15%）
    double durationMultiplier;
    if (textWidth < 100) {
      // 短弹幕慢一些，让用户有时间阅读
      durationMultiplier = 1.2;
    } else if (textWidth > 300) {
      // 长弹幕快一些，避免占用轨道太久
      durationMultiplier = 0.85;
    } else {
      // 中等长度弹幕，根据宽度线性插值
      // 100px -> 1.1, 200px -> 1.0, 300px -> 0.9
      durationMultiplier = 1.1 - (textWidth - 100) / 200 * 0.2;
    }
    
    // 最终时间 = 基础时间 * 宽度系数 / 用户速度设置
    // 用户速度设置越大，时间越短（弹幕越快）
    return _baseDuration * durationMultiplier / widget.speed;
  }

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
      if (_tryAddDanmaku(item, currentTime)) {
        changed = true;
      }
      _nextIndex++;
    }

    if (changed) {
      setState(() {});
    }
  }

  void _removeExpiredDanmakus(double currentTime) {
    final before = _visibleDanmakus.length;
    _visibleDanmakus.removeWhere((d) => currentTime > d.startTime + d.duration + 0.5);
    if (_visibleDanmakus.length != before) {
      setState(() {});
    }
  }

  double _estimateTextWidth(String text) {
    // 估算文字宽度：中文字符约等于字体大小，英文约0.5倍
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

  bool _tryAddDanmaku(DanmakuItem item, double currentTime) {
    if (_tracks.isEmpty || _screenWidth <= 0) return false;

    // 估算弹幕宽度
    final textWidth = _estimateTextWidth(item.text);
    
    // 根据文字宽度计算穿越时间（短弹幕慢，长弹幕快）
    final duration = _calculateDuration(textWidth);
    
    // 计算实际速度（像素/秒）= 总移动距离 / 时间
    final totalDistance = _screenWidth + textWidth;
    final actualSpeed = totalDistance / duration;

    int? track;
    for (int i = 0; i < _tracks.length; i++) {
      // 使用防重叠算法检查轨道是否可用
      if (_tracks[i].canAccept(currentTime, _screenWidth, textWidth, actualSpeed)) {
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

    // 更新轨道信息（记录弹幕的宽度和速度，用于防追尾计算）
    _tracks[track].update(currentTime, textWidth, actualSpeed);

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
