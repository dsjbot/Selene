import 'dart:async';
import 'package:flutter/material.dart';
import '../models/skip_config.dart';

/// 片头跳过提示组件
class SkipIntroPrompt extends StatelessWidget {
  final VoidCallback onSkip;
  final VoidCallback onDismiss;

  const SkipIntroPrompt({
    super.key,
    required this.onSkip,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '检测到片头',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onSkip,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '跳过',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(
              Icons.close,
              color: Colors.white54,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

/// 片尾倒计时组件
class SkipEndingCountdown extends StatefulWidget {
  final int countdownSeconds;
  final VoidCallback onNextEpisode;
  final VoidCallback onCancel;
  final bool isLastEpisode;

  const SkipEndingCountdown({
    super.key,
    required this.countdownSeconds,
    required this.onNextEpisode,
    required this.onCancel,
    this.isLastEpisode = false,
  });

  @override
  State<SkipEndingCountdown> createState() => _SkipEndingCountdownState();
}

class _SkipEndingCountdownState extends State<SkipEndingCountdown> {
  late int _remainingSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.countdownSeconds;
    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        widget.onNextEpisode();
      } else {
        setState(() {
          _remainingSeconds--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.isLastEpisode
        ? '${_remainingSeconds}秒后结束播放'
        : '${_remainingSeconds}秒后自动播放下一集';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.timer,
            color: Colors.white70,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: widget.onCancel,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white54),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '取消',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 跳过控制器 - 管理跳过逻辑
class SkipController {
  final EpisodeSkipConfig? config;
  final Duration videoDuration;
  final bool isLastEpisode;

  // 状态
  bool _introSkipped = false;
  bool _endingTriggered = false;
  bool _introDismissed = false;
  bool _endingCancelled = false;

  SkipController({
    this.config,
    required this.videoDuration,
    this.isLastEpisode = false,
  });

  /// 重置状态（切换视频时调用）
  void reset() {
    _introSkipped = false;
    _endingTriggered = false;
    _introDismissed = false;
    _endingCancelled = false;
  }

  /// 标记片头已跳过
  void markIntroSkipped() {
    _introSkipped = true;
  }

  /// 标记片头提示已关闭
  void markIntroDismissed() {
    _introDismissed = true;
  }

  /// 标记片尾已触发
  void markEndingTriggered() {
    _endingTriggered = true;
  }

  /// 标记片尾已取消
  void markEndingCancelled() {
    _endingCancelled = true;
  }

  /// 检查当前位置是否在片头区间
  SkipSegment? checkIntro(Duration position) {
    if (config == null || _introSkipped || _introDismissed) return null;

    final posSeconds = position.inMilliseconds / 1000.0;

    for (final segment in config!.segments) {
      if (segment.type == SkipSegmentType.opening) {
        if (posSeconds >= segment.start && posSeconds < segment.end) {
          return segment;
        }
      }
    }
    return null;
  }

  /// 检查当前位置是否在片尾区间
  SkipSegment? checkEnding(Duration position) {
    if (config == null || _endingTriggered || _endingCancelled) return null;
    if (videoDuration == Duration.zero) return null;

    final posSeconds = position.inMilliseconds / 1000.0;
    final totalSeconds = videoDuration.inMilliseconds / 1000.0;

    for (final segment in config!.segments) {
      if (segment.type == SkipSegmentType.ending) {
        double startTime;
        double endTime;

        if (segment.mode == SkipTimeMode.remaining) {
          // 剩余时间模式
          final remaining = segment.remainingTime ?? segment.end;
          startTime = totalSeconds - remaining;
          endTime = totalSeconds;
        } else {
          // 绝对时间模式
          startTime = segment.start;
          endTime = segment.end;
        }

        if (posSeconds >= startTime && posSeconds < endTime) {
          return segment;
        }
      }
    }
    return null;
  }

  /// 获取片头跳过目标位置
  Duration? getIntroSkipTarget(SkipSegment segment) {
    return Duration(milliseconds: (segment.end * 1000).round());
  }

  /// 是否应该自动跳过片头
  bool shouldAutoSkipIntro(SkipSegment segment) {
    return segment.autoSkip;
  }

  /// 是否应该自动播放下一集
  bool shouldAutoNextEpisode(SkipSegment segment) {
    return segment.autoNextEpisode && !isLastEpisode;
  }
}
