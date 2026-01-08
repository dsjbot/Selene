import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/danmaku.dart';

/// 弹幕轨道信息
class _DanmakuTrack {
  double endTime; // 该轨道上弹幕结束的时间
  double endX; // 该轨道上弹幕的结束位置

  _DanmakuTrack({this.endTime = 0, this.endX = 0});
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

/// 弹幕层组件
class DanmakuLayer extends StatefulWidget {
  final List<DanmakuItem> danmakuList;
  final Duration currentPosition;
  final bool isPlaying;
  final bool enabled;
  final double opacity;
  final double fontSize;
  final double speed; // 弹幕速度倍率
  final double areaHeight; // 弹幕显示区域高度比例 (0.0 - 1.0)

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
  final List<_ActiveDanmaku> _activeDanmakus = [];
  final List<_DanmakuTrack> _tracks = [];
  int _lastProcessedIndex = 0;
  double _lastPosition = 0;
  Timer? _updateTimer;
  final Random _random = Random();
  bool _isInitialized = false; // 标记是否已初始化轨道

  // 弹幕配置
  static const double _baseDuration = 8.0; // 基础持续时间（秒）
  static const double _trackHeight = 28.0; // 轨道高度
  static const int _maxActiveDanmakus = 50; // 最大同时显示弹幕数

  @override
  void initState() {
    super.initState();
    _initTracks();
    _startUpdateTimer();
  }

  @override
  void didUpdateWidget(DanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 弹幕列表变化时重置
    if (widget.danmakuList != oldWidget.danmakuList) {
      _reset();
    }

    // 检测 seek 操作（位置跳跃超过2秒）
    final currentSeconds = widget.currentPosition.inMilliseconds / 1000.0;
    if ((currentSeconds - _lastPosition).abs() > 2.0) {
      _onSeek(currentSeconds);
    }
    _lastPosition = currentSeconds;

    // 播放状态变化
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _startUpdateTimer();
      } else {
        _stopUpdateTimer();
      }
    }
  }

  @override
  void dispose() {
    _stopUpdateTimer();
    super.dispose();
  }

  void _initTracks() {
    _tracks.clear();
    // 初始化轨道数量会在 build 时根据实际高度动态调整
  }

  void _reset() {
    _activeDanmakus.clear();
    _lastProcessedIndex = 0;
    _lastPosition = 0;
    _isInitialized = false;
    _initTracks();
  }

  void _onSeek(double newPosition) {
    _activeDanmakus.clear();
    // 不清空轨道，只重置弹幕索引
    // _initTracks();

    // 找到新位置对应的弹幕索引
    _lastProcessedIndex = _findDanmakuIndex(newPosition);
  }

  int _findDanmakuIndex(double time) {
    // 二分查找
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

  void _startUpdateTimer() {
    _stopUpdateTimer();
    // 60fps 更新
    _updateTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (mounted && widget.isPlaying && widget.enabled) {
        _updateDanmakus();
      }
    });
  }

  void _stopUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  void _updateDanmakus() {
    if (!mounted || widget.danmakuList.isEmpty || _tracks.isEmpty || !_isInitialized) return;

    final currentTime = widget.currentPosition.inMilliseconds / 1000.0;
    final duration = _baseDuration / widget.speed;

    // 移除过期弹幕
    _activeDanmakus.removeWhere((d) {
      return currentTime > d.startTime + d.duration;
    });

    // 添加新弹幕
    while (_lastProcessedIndex < widget.danmakuList.length &&
        _activeDanmakus.length < _maxActiveDanmakus) {
      final danmaku = widget.danmakuList[_lastProcessedIndex];

      // 弹幕时间还没到
      if (danmaku.time > currentTime + 0.1) break;

      // 弹幕时间已过
      if (danmaku.time < currentTime - duration) {
        _lastProcessedIndex++;
        continue;
      }

      // 尝试添加弹幕
      _tryAddDanmaku(danmaku, currentTime, duration);
      _lastProcessedIndex++;
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _tryAddDanmaku(
      DanmakuItem danmaku, double currentTime, double duration) {
    if (_tracks.isEmpty) return;

    // 计算弹幕宽度（估算）
    final textWidth = _estimateTextWidth(danmaku.text, widget.fontSize);

    // 根据弹幕模式选择轨道
    int? track;
    if (danmaku.mode == 1) {
      // 顶部弹幕
      track = _findAvailableTrack(currentTime, textWidth, true);
    } else if (danmaku.mode == 2) {
      // 底部弹幕
      track = _findAvailableTrack(currentTime, textWidth, false);
    } else {
      // 滚动弹幕
      track = _findAvailableScrollTrack(currentTime, textWidth, duration);
    }

    if (track == null) return; // 没有可用轨道，丢弃

    // 解析颜色
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

    // 更新轨道状态
    if (track < _tracks.length) {
      _tracks[track].endTime = danmaku.time + duration * 0.3;
      _tracks[track].endX = textWidth;
    }
  }

  int? _findAvailableScrollTrack(
      double currentTime, double textWidth, double duration) {
    // 随机起始轨道，避免弹幕集中在顶部
    final startTrack = _random.nextInt(max(1, _tracks.length));

    for (int i = 0; i < _tracks.length; i++) {
      final trackIndex = (startTrack + i) % _tracks.length;
      final track = _tracks[trackIndex];

      // 检查轨道是否可用
      if (currentTime > track.endTime) {
        return trackIndex;
      }
    }
    return null;
  }

  int? _findAvailableTrack(
      double currentTime, double textWidth, bool fromTop) {
    if (fromTop) {
      for (int i = 0; i < _tracks.length ~/ 3; i++) {
        if (currentTime > _tracks[i].endTime) {
          return i;
        }
      }
    } else {
      for (int i = _tracks.length - 1; i >= _tracks.length * 2 ~/ 3; i--) {
        if (currentTime > _tracks[i].endTime) {
          return i;
        }
      }
    }
    return null;
  }

  double _estimateTextWidth(String text, double fontSize) {
    // 简单估算：中文字符宽度约等于字体大小，英文约为一半
    double width = 0;
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code > 127) {
        width += fontSize;
      } else {
        width += fontSize * 0.5;
      }
    }
    return width + 16; // 加上 padding
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

        // 动态调整轨道数量
        while (_tracks.length < trackCount) {
          _tracks.add(_DanmakuTrack());
        }
        while (_tracks.length > trackCount) {
          _tracks.removeLast();
        }

        // 标记已初始化
        if (!_isInitialized && _tracks.isNotEmpty) {
          _isInitialized = true;
        }

        final currentTime = widget.currentPosition.inMilliseconds / 1000.0;

        return ClipRect(
          child: Stack(
            children: _activeDanmakus.map((danmaku) {
              return _buildDanmakuWidget(
                danmaku,
                currentTime,
                constraints.maxWidth,
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildDanmakuWidget(
    _ActiveDanmaku danmaku,
    double currentTime,
    double screenWidth,
  ) {
    final elapsed = currentTime - danmaku.startTime;
    final progress = (elapsed / danmaku.duration).clamp(0.0, 1.0);

    double left;
    double top = danmaku.track * _trackHeight;

    if (danmaku.item.mode == 1 || danmaku.item.mode == 2) {
      // 顶部/底部弹幕：居中显示
      left = (screenWidth - danmaku.width) / 2;
    } else {
      // 滚动弹幕：从右到左
      left = screenWidth - (screenWidth + danmaku.width) * progress;
    }

    return Positioned(
      left: left,
      top: top,
      child: Opacity(
        opacity: widget.opacity,
        child: Text(
          danmaku.item.text,
          style: TextStyle(
            color: danmaku.color,
            fontSize: widget.fontSize,
            fontWeight: FontWeight.w500,
            shadows: const [
              Shadow(
                offset: Offset(1, 1),
                blurRadius: 2,
                color: Colors.black,
              ),
              Shadow(
                offset: Offset(-1, -1),
                blurRadius: 2,
                color: Colors.black,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
