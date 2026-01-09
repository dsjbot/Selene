import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pip/pip.dart';
import 'mobile_player_controls.dart';
import 'pc_player_controls.dart';
import 'video_player_surface.dart';
import 'danmaku_layer.dart';
import 'danmaku_settings_panel.dart';
import 'skip_prompt_widget.dart';
import '../models/danmaku.dart';
import '../models/skip_config.dart';
import '../services/danmaku_service.dart';
import '../services/skip_config_service.dart';
import '../services/ad_filter_service.dart';
import '../services/player_manager.dart';

class VideoPlayerWidget extends StatefulWidget {
  final VideoPlayerSurface surface;
  final String? url;
  final Map<String, String>? headers;
  final VoidCallback? onBackPressed;
  final Function(VideoPlayerWidgetController)? onControllerCreated;
  final VoidCallback? onReady;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onVideoCompleted;
  final VoidCallback? onPause;
  final bool isLastEpisode;
  final Function(dynamic)? onCastStarted;
  final String? videoTitle;
  final int? currentEpisodeIndex;
  final int? totalEpisodes;
  final String? sourceName;
  final Function(bool isWebFullscreen)? onWebFullscreenChanged;
  final VoidCallback? onExitFullScreen;
  final bool live;
  final Function(bool isPipMode)? onPipModeChanged;
  final String? doubanId; // 豆瓣ID，用于获取弹幕
  final String? videoSource; // 视频源标识，用于跳过配置
  final String? videoId; // 视频ID，用于跳过配置

  const VideoPlayerWidget({
    super.key,
    this.surface = VideoPlayerSurface.mobile,
    this.url,
    this.headers,
    this.onBackPressed,
    this.onControllerCreated,
    this.onReady,
    this.onNextEpisode,
    this.onVideoCompleted,
    this.onPause,
    this.isLastEpisode = false,
    this.onCastStarted,
    this.videoTitle,
    this.currentEpisodeIndex,
    this.totalEpisodes,
    this.sourceName,
    this.onWebFullscreenChanged,
    this.onExitFullScreen,
    this.live = false,
    this.onPipModeChanged,
    this.videoSource,
    this.videoId,
    this.doubanId,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class VideoPlayerWidgetController {
  VideoPlayerWidgetController._(this._state);
  final _VideoPlayerWidgetState _state;

  Future<void> updateDataSource(
    String url, {
    Duration? startAt,
    Map<String, String>? headers,
  }) async {
    await _state._updateDataSource(
      url,
      startAt: startAt,
      headers: headers,
    );
  }

  Future<void> seekTo(Duration position) async {
    await _state._player?.seek(position);
  }

  Duration? get currentPosition => _state._player?.state.position;

  Duration? get duration => _state._player?.state.duration;

  bool get isPlaying => _state._player?.state.playing ?? false;

  Future<void> pause() async {
    await _state._player?.pause();
  }

  Future<void> play() async {
    await _state._player?.play();
  }

  void addProgressListener(VoidCallback listener) {
    _state._addProgressListener(listener);
  }

  void removeProgressListener(VoidCallback listener) {
    _state._removeProgressListener(listener);
  }

  Future<void> setSpeed(double speed) async {
    await _state._setPlaybackSpeed(speed);
  }

  double get playbackSpeed => _state._playbackSpeed.value;

  Future<void> setVolume(double volume) async {
    await _state._player?.setVolume(volume);
  }

  double? get volume => _state._player?.state.volume;

  void exitWebFullscreen() {
    _state._exitWebFullscreen();
  }

  Future<void> dispose() async {
    await _state._externalDispose();
  }

  bool get isPipMode => _state._isPipMode;
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
  ManagedPlayer? _managedPlayer; // 使用 PlayerManager 管理的播放器
  bool _isInitialized = false;
  bool _hasCompleted = false;
  bool _isLoadingVideo = false;
  String? _currentUrl;
  Map<String, String>? _currentHeaders;
  final List<VoidCallback> _progressListeners = [];
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  final ValueNotifier<double> _playbackSpeed = ValueNotifier<double>(1.0);
  bool _playerDisposed = false;
  VoidCallback? _exitWebFullscreenCallback;
  final Pip _pip = Pip();
  bool _isPipMode = false;

  // 弹幕相关状态
  List<DanmakuItem> _danmakuList = [];
  DanmakuSettings _danmakuSettings = DanmakuSettings();
  bool _isLoadingDanmaku = false;

  // 跳过片头片尾相关状态
  EpisodeSkipConfig? _skipConfig;
  SkipController? _skipController;
  bool _showIntroPrompt = false;
  bool _showEndingCountdown = false;
  SkipSegment? _currentIntroSegment;
  SkipSegment? _currentEndingSegment;
  Duration _currentPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    debugPrint('[VideoPlayerWidget] initState - videoTitle: ${widget.videoTitle}, live: ${widget.live}');
    WidgetsBinding.instance.addObserver(this);
    _currentUrl = widget.url;
    _currentHeaders = widget.headers;
    _initializePlayer();
    _setupPip();
    _registerPipObserver();
    widget.onControllerCreated?.call(VideoPlayerWidgetController._(this));
    // 加载弹幕和跳过配置
    if (!widget.live) {
      _loadDanmaku();
      _loadSkipConfig();
    }
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    debugPrint('[VideoPlayerWidget] didUpdateWidget - old videoTitle: ${oldWidget.videoTitle}, new videoTitle: ${widget.videoTitle}');
    if (widget.headers != oldWidget.headers && widget.headers != null) {
      _currentHeaders = widget.headers;
    }
    if (widget.url != oldWidget.url && widget.url != null) {
      unawaited(_updateDataSource(widget.url!));
    }
    // 视频标题或集数变化时重新加载弹幕
    if (!widget.live &&
        (widget.videoTitle != oldWidget.videoTitle ||
            widget.currentEpisodeIndex != oldWidget.currentEpisodeIndex ||
            widget.doubanId != oldWidget.doubanId)) {
      debugPrint('[VideoPlayerWidget] 触发弹幕重新加载');
      _loadDanmaku();
    }
    // 视频源或ID变化时重新加载跳过配置
    if (!widget.live &&
        (widget.videoSource != oldWidget.videoSource ||
            widget.videoId != oldWidget.videoId)) {
      debugPrint('[VideoPlayerWidget] 触发跳过配置重新加载');
      _loadSkipConfig();
    }
  }

  Future<void> _initializePlayer() async {
    if (_playerDisposed) {
      return;
    }
    
    setState(() {
      _isLoadingVideo = true;
    });
    
    // 使用 PlayerManager 获取播放器（复用单例）
    final managed = await PlayerManager().getPlayer(PlayerManager.mainPlayerId);
    
    if (_playerDisposed || !mounted) {
      return;
    }
    
    _managedPlayer = managed;
    _player = managed.player;
    _videoController = managed.controller;
    
    // 不等待 stop 完成，直接设置监听器并加载新视频
    // stop 和 open 会自动处理状态切换
    _setupPlayerListeners();
    
    setState(() {
      _isInitialized = true;
    });
    
    if (_currentUrl != null) {
      await _openCurrentMedia();
    }
  }

  Future<void> _openCurrentMedia({Duration? startAt}) async {
    if (_playerDisposed || _player == null || _currentUrl == null) {
      return;
    }
    
    // 保存当前 URL 用于后续比较
    final urlToOpen = _currentUrl!;
    
    setState(() {
      _isLoadingVideo = true;
    });
    try {
      // 处理广告过滤
      String processedUrl = urlToOpen;
      if (AdFilterService.isEnabled) {
        // 检查是否已经被 dispose
        if (_playerDisposed || !mounted) return;
        
        try {
          processedUrl = await AdFilterService.processM3U8Url(
            urlToOpen,
            headers: _currentHeaders,
            sourceKey: widget.videoSource,
          );
        } catch (e) {
          debugPrint('VideoPlayerWidget: ad filter error $e');
          // 广告过滤失败时使用原始 URL
          processedUrl = urlToOpen;
        }
        
        // 再次检查是否已经被 dispose 或 URL 已经改变
        if (_playerDisposed || !mounted || _player == null || _currentUrl != urlToOpen) return;
      }
      
      await _player!.open(
        Media(
          processedUrl,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
        play: true,
      );
      
      if (_playerDisposed || !mounted) return;
      
      await _player!.setRate(_playbackSpeed.value);
      if (mounted && !_playerDisposed) {
        setState(() {
          _hasCompleted = false;
        });
      }
    } catch (error) {
      debugPrint('VideoPlayerWidget: failed to open media $error');
      if (mounted && !_playerDisposed) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    }
  }

  void _setupPlayerListeners() {
    if (_player == null) {
      return;
    }
    
    // 先取消之前的订阅
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _durationSubscription?.cancel();

    _positionSubscription = _player!.stream.position.listen((position) {
      // 更新弹幕位置
      if (mounted && !_playerDisposed) {
        setState(() {
          _currentPosition = position;
        });
        // 检测片头片尾跳过
        _checkSkipSegments(position);
      }
      for (final listener in List<VoidCallback>.from(_progressListeners)) {
        try {
          listener();
        } catch (error) {
          debugPrint('VideoPlayerWidget: progress listener error $error');
        }
      }
    });

    _playingSubscription = _player!.stream.playing.listen((playing) {
      if (!mounted || _playerDisposed) return;
      if (!playing) {
        setState(() {
          _hasCompleted = false;
        });
        _pip.setup(const PipOptions(
          autoEnterEnabled: false,
          aspectRatioX: 16,
          aspectRatioY: 9,
          preferredContentWidth: 480,
          preferredContentHeight: 270,
          controlStyle: 2,
        ));
      } else {
        _pip.setup(const PipOptions(
          autoEnterEnabled: true,
          aspectRatioX: 16,
          aspectRatioY: 9,
          preferredContentWidth: 480,
          preferredContentHeight: 270,
          controlStyle: 2,
        ));
      }
    });

    if (!widget.live) {
      _completedSubscription = _player!.stream.completed.listen((completed) {
        if (!mounted || _playerDisposed) return;
        if (completed && !_hasCompleted) {
          _hasCompleted = true;
          widget.onVideoCompleted?.call();
        }
      });
    }

    _durationSubscription = _player!.stream.duration.listen((duration) {
      if (!mounted || _playerDisposed) return;
      if (duration != Duration.zero) {
        if (_isLoadingVideo) {
          setState(() {
            _isLoadingVideo = false;
          });
        }
        widget.onReady?.call();
      }
    });
  }

  Future<void> _updateDataSource(
    String url, {
    Duration? startAt,
    Map<String, String>? headers,
  }) async {
    if (_playerDisposed) {
      return;
    }
    _currentUrl = url;
    if (headers != null) {
      _currentHeaders = headers;
    }

    if (_player == null) {
      await _initializePlayer();
      return;
    }

    // 保存当前 URL 用于后续比较
    final urlToUpdate = url;

    setState(() {
      _isLoadingVideo = true;
    });

    try {
      // 处理广告过滤
      String processedUrl = urlToUpdate;
      if (AdFilterService.isEnabled) {
        // 检查是否已经被 dispose
        if (_playerDisposed || !mounted) return;
        
        try {
          processedUrl = await AdFilterService.processM3U8Url(
            urlToUpdate,
            headers: _currentHeaders,
            sourceKey: widget.videoSource,
          );
        } catch (e) {
          debugPrint('VideoPlayerWidget: ad filter error $e');
          // 广告过滤失败时使用原始 URL
          processedUrl = urlToUpdate;
        }
        
        // 再次检查是否已经被 dispose 或 URL 已经改变
        if (_playerDisposed || !mounted || _player == null || _currentUrl != urlToUpdate) return;
      }
      
      final currentSpeed = _player!.state.rate;
      await _player!.open(
        Media(
          processedUrl,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
        play: true,
      );
      
      if (_playerDisposed || !mounted) return;
      
      _playbackSpeed.value = currentSpeed;
      await _player!.setRate(currentSpeed);
      if (mounted && !_playerDisposed) {
        setState(() {
          _hasCompleted = false;
        });
      }
    } catch (error) {
      debugPrint('VideoPlayerWidget: error while changing source $error');
      if (mounted && !_playerDisposed) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    }
  }

  void _addProgressListener(VoidCallback listener) {
    if (!_progressListeners.contains(listener)) {
      _progressListeners.add(listener);
    }
  }

  void _removeProgressListener(VoidCallback listener) {
    _progressListeners.remove(listener);
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    _playbackSpeed.value = speed;
    await _player?.setRate(speed);
  }

  void _exitWebFullscreen() {
    _exitWebFullscreenCallback?.call();
  }

  /// 加载弹幕数据
  Future<void> _loadDanmaku() async {
    debugPrint('[弹幕] _loadDanmaku 被调用');
    debugPrint('[弹幕] videoTitle: ${widget.videoTitle}');
    debugPrint('[弹幕] currentEpisodeIndex: ${widget.currentEpisodeIndex}');
    debugPrint('[弹幕] doubanId: ${widget.doubanId}');
    
    if (widget.videoTitle == null || widget.videoTitle!.isEmpty) {
      debugPrint('[弹幕] 视频标题为空，跳过加载');
      return;
    }

    debugPrint('[弹幕] 开始加载弹幕...');

    setState(() {
      _isLoadingDanmaku = true;
      _danmakuList = [];
    });

    try {
      final episode = widget.currentEpisodeIndex != null
          ? (widget.currentEpisodeIndex! + 1).toString()
          : null;

      debugPrint('[弹幕] 调用 DanmakuService.getDanmaku');
      final response = await DanmakuService.getDanmaku(
        title: widget.videoTitle!,
        episode: episode,
        doubanId: widget.doubanId,
      );

      debugPrint('[弹幕] 收到响应: success=${response.success}, count=${response.count}, error=${response.error}');

      if (mounted) {
        setState(() {
          _isLoadingDanmaku = false;
          if (response.success) {
            _danmakuList = response.danmakuList;
            debugPrint('[弹幕] 加载成功: ${_danmakuList.length} 条');
          } else {
            debugPrint('[弹幕] 加载失败: ${response.error}');
          }
        });
      }
    } catch (e) {
      debugPrint('[弹幕] 加载异常: $e');
      if (mounted) {
        setState(() {
          _isLoadingDanmaku = false;
        });
      }
    }
  }

  /// 更新弹幕设置
  void _updateDanmakuSettings(DanmakuSettings settings) {
    setState(() {
      _danmakuSettings = settings;
    });
  }

  /// 加载跳过配置
  Future<void> _loadSkipConfig() async {
    if (widget.videoSource == null || widget.videoId == null) {
      debugPrint('[跳过配置] 视频源或ID为空，跳过加载');
      return;
    }

    debugPrint('[跳过配置] 开始加载: source=${widget.videoSource}, id=${widget.videoId}');

    try {
      final config = await SkipConfigService.getSkipConfig(
        source: widget.videoSource!,
        id: widget.videoId!,
      );

      if (mounted) {
        setState(() {
          _skipConfig = config;
          _skipController = SkipController(
            config: config,
            videoDuration: _player?.state.duration ?? Duration.zero,
            isLastEpisode: widget.isLastEpisode,
          );
          // 重置跳过状态
          _showIntroPrompt = false;
          _showEndingCountdown = false;
          _currentIntroSegment = null;
          _currentEndingSegment = null;
        });
        debugPrint('[跳过配置] 加载完成: ${config?.segments.length ?? 0} 个片段');
      }
    } catch (e) {
      debugPrint('[跳过配置] 加载异常: $e');
    }
  }

  /// 检测跳过片段
  void _checkSkipSegments(Duration position) {
    if (_skipController == null || widget.live || _isPipMode) return;

    // 更新视频时长
    final duration = _player?.state.duration ?? Duration.zero;
    if (duration != Duration.zero && _skipController!.videoDuration != duration) {
      _skipController = SkipController(
        config: _skipConfig,
        videoDuration: duration,
        isLastEpisode: widget.isLastEpisode,
      );
    }

    // 检测片头
    final introSegment = _skipController!.checkIntro(position);
    if (introSegment != null && _currentIntroSegment == null) {
      _currentIntroSegment = introSegment;
      if (_skipController!.shouldAutoSkipIntro(introSegment)) {
        // 自动跳过
        _skipIntro();
      } else {
        // 显示手动跳过提示
        setState(() {
          _showIntroPrompt = true;
        });
      }
    } else if (introSegment == null && _showIntroPrompt) {
      // 离开片头区间，隐藏提示
      setState(() {
        _showIntroPrompt = false;
        _currentIntroSegment = null;
      });
    }

    // 检测片尾
    final endingSegment = _skipController!.checkEnding(position);
    if (endingSegment != null && _currentEndingSegment == null) {
      _currentEndingSegment = endingSegment;
      if (_skipController!.shouldAutoNextEpisode(endingSegment)) {
        // 显示倒计时
        setState(() {
          _showEndingCountdown = true;
        });
      }
    }
  }

  /// 跳过片头
  void _skipIntro() {
    if (_currentIntroSegment == null || _player == null) return;

    final target = _skipController?.getIntroSkipTarget(_currentIntroSegment!);
    if (target != null) {
      debugPrint('[跳过配置] 跳过片头到: ${target.inSeconds}s');
      _player!.seek(target);
    }

    _skipController?.markIntroSkipped();
    setState(() {
      _showIntroPrompt = false;
      _currentIntroSegment = null;
    });
  }

  /// 关闭片头提示
  void _dismissIntroPrompt() {
    _skipController?.markIntroDismissed();
    setState(() {
      _showIntroPrompt = false;
    });
  }

  /// 触发下一集
  void _triggerNextEpisode() {
    debugPrint('[跳过配置] 自动播放下一集');
    _skipController?.markEndingTriggered();
    setState(() {
      _showEndingCountdown = false;
      _currentEndingSegment = null;
    });
    widget.onNextEpisode?.call();
  }

  /// 取消片尾倒计时
  void _cancelEndingCountdown() {
    _skipController?.markEndingCancelled();
    setState(() {
      _showEndingCountdown = false;
    });
  }

  /// 更新跳过配置（从设置面板保存后调用）
  void _updateSkipConfig(EpisodeSkipConfig? config) {
    setState(() {
      _skipConfig = config;
      _skipController = SkipController(
        config: config,
        videoDuration: _player?.state.duration ?? Duration.zero,
        isLastEpisode: widget.isLastEpisode,
      );
      // 重置跳过状态
      _showIntroPrompt = false;
      _showEndingCountdown = false;
      _currentIntroSegment = null;
      _currentEndingSegment = null;
    });
    debugPrint('[跳过配置] 配置已更新: ${config?.segments.length ?? 0} 个片段');
  }

  void _setupPip() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    _pip.setup(const PipOptions(
      autoEnterEnabled: true,
      aspectRatioX: 16,
      aspectRatioY: 9,
      preferredContentWidth: 480,
      preferredContentHeight: 270,
      controlStyle: 2,
    ));
  }

  void _registerPipObserver() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    _pip.registerStateChangedObserver(PipStateChangedObserver(
      onPipStateChanged: (state, error) {
        if (!mounted) return;
        switch (state) {
          case PipState.pipStateStarted:
            debugPrint('PiP started successfully');
            if (mounted) {
              setState(() => _isPipMode = true);
              widget.onPipModeChanged?.call(true);
            }
            break;
          case PipState.pipStateStopped:
            debugPrint('PiP stopped');
            if (mounted) {
              setState(() {
                _isPipMode = false;
              });
              widget.onPipModeChanged?.call(false);
            }
            break;
          case PipState.pipStateFailed:
            debugPrint('PiP failed: $error');
            if (mounted) {
              setState(() => _isPipMode = false);
              widget.onPipModeChanged?.call(false);
            }
            break;
        }
      },
    ));
  }

  Future<void> _enterPipMode() async {
    debugPrint('_enterPipMode');
    try {
      var support = await _pip.isSupported();
      if (!support) {
        debugPrint('Device does not support PiP!');
        return;
      }
      await _player?.play();
      await _pip.start();
    } catch (e) {
      debugPrint('Failed to enter PiP mode: $e');
      _setupPip();
    }
  }

  Future<void> _externalDispose() async {
    if (!mounted || _playerDisposed) {
      return;
    }
    await _disposePlayer();
  }

  Future<void> _disposePlayer() async {
    if (_playerDisposed) {
      return;
    }
    _playerDisposed = true;
    
    // 取消所有订阅
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _playingSubscription?.cancel();
    _playingSubscription = null;
    _completedSubscription?.cancel();
    _completedSubscription = null;
    _durationSubscription?.cancel();
    _durationSubscription = null;
    _progressListeners.clear();
    
    // 停止播放器（不释放）
    await PlayerManager().stopPlayer(PlayerManager.mainPlayerId);
    
    _player = null;
    _videoController = null;
    _managedPlayer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_player == null || _playerDisposed) {
      return;
    }
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
      case AppLifecycleState.resumed:
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    debugPrint('[VideoPlayerWidget] dispose called');
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid || Platform.isIOS) {
      _pip.unregisterStateChangedObserver();
      _pip.dispose();
    }
    // 同步设置标记，防止其他异步操作继续
    _playerDisposed = true;
    
    // 取消所有订阅（重要：避免回调到已销毁的 Widget）
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _playingSubscription?.cancel();
    _playingSubscription = null;
    _completedSubscription?.cancel();
    _completedSubscription = null;
    _durationSubscription?.cancel();
    _durationSubscription = null;
    _progressListeners.clear();
    
    // 停止播放器（不释放，只停止）
    // 播放器由 PlayerManager 管理，永不 dispose
    PlayerManager().stopPlayer(PlayerManager.mainPlayerId);
    
    _player = null;
    _videoController = null;
    _managedPlayer = null;
    
    _playbackSpeed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: _isInitialized && _videoController != null
          ? Stack(
              children: [
                Video(
                  controller: _videoController!,
                  controls: (state) {
                    // 弹幕层需要放在controls里面，这样全屏时也能显示
                    return Stack(
                      children: [
                        // 弹幕层（放在控制层下面）
                        if (!widget.live && !_isPipMode)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DanmakuLayer(
                                danmakuList: _danmakuList,
                                currentPosition: _currentPosition,
                                isPlaying: _player?.state.playing ?? false,
                                enabled: _danmakuSettings.enabled,
                                opacity: _danmakuSettings.opacity,
                                fontSize: _danmakuSettings.fontSize,
                                speed: _danmakuSettings.speed,
                                areaHeight: _danmakuSettings.areaHeight,
                              ),
                            ),
                          ),
                        // 控制层
                        widget.surface == VideoPlayerSurface.desktop
                            ? PCPlayerControls(
                                state: state,
                                player: _player!,
                                onBackPressed: widget.onBackPressed,
                                onNextEpisode: widget.onNextEpisode,
                                onPause: widget.onPause,
                                videoUrl: _currentUrl ?? '',
                                isLastEpisode: widget.isLastEpisode,
                                isLoadingVideo: _isLoadingVideo,
                                onCastStarted: widget.onCastStarted,
                                videoTitle: widget.videoTitle,
                                currentEpisodeIndex: widget.currentEpisodeIndex,
                                totalEpisodes: widget.totalEpisodes,
                                sourceName: widget.sourceName,
                                onWebFullscreenChanged: widget.onWebFullscreenChanged,
                                onExitWebFullscreenCallbackReady: (callback) {
                                  _exitWebFullscreenCallback = callback;
                                },
                                onExitFullScreen: widget.onExitFullScreen,
                                live: widget.live,
                                playbackSpeedListenable: _playbackSpeed,
                                onSetSpeed: _setPlaybackSpeed,
                                danmakuCount: _danmakuList.length,
                                danmakuSettings: _danmakuSettings,
                                onDanmakuSettingsChanged: _updateDanmakuSettings,
                                videoSource: widget.videoSource,
                                videoId: widget.videoId,
                                skipConfig: _skipConfig,
                                onSkipConfigChanged: _updateSkipConfig,
                              )
                            : MobilePlayerControls(
                                player: _player!,
                                state: state,
                                onControlsVisibilityChanged: (_) {},
                                onBackPressed: widget.onBackPressed,
                                onFullscreenChange: (_) {},
                                onNextEpisode: widget.onNextEpisode,
                                onPause: widget.onPause,
                                videoUrl: _currentUrl ?? '',
                                isLastEpisode: widget.isLastEpisode,
                                isLoadingVideo: _isLoadingVideo,
                                onCastStarted: widget.onCastStarted,
                                videoTitle: widget.videoTitle,
                                currentEpisodeIndex: widget.currentEpisodeIndex,
                                totalEpisodes: widget.totalEpisodes,
                                sourceName: widget.sourceName,
                                onExitFullScreen: widget.onExitFullScreen,
                                live: widget.live,
                                playbackSpeedListenable: _playbackSpeed,
                                onSetSpeed: _setPlaybackSpeed,
                                onEnterPipMode: _enterPipMode,
                                isPipMode: _isPipMode,
                                danmakuCount: _danmakuList.length,
                                danmakuSettings: _danmakuSettings,
                                onDanmakuSettingsChanged: _updateDanmakuSettings,
                                videoSource: widget.videoSource,
                                videoId: widget.videoId,
                                skipConfig: _skipConfig,
                                onSkipConfigChanged: _updateSkipConfig,
                              ),
                        // 片头跳过提示
                        if (_showIntroPrompt && !_isPipMode)
                          Positioned(
                            left: 16,
                            top: 60,
                            child: SkipIntroPrompt(
                              onSkip: _skipIntro,
                              onDismiss: _dismissIntroPrompt,
                            ),
                          ),
                        // 片尾倒计时
                        if (_showEndingCountdown && !_isPipMode)
                          Positioned(
                            top: 16,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: SkipEndingCountdown(
                                countdownSeconds: 5,
                                onNextEpisode: _triggerNextEpisode,
                                onCancel: _cancelEndingCountdown,
                                isLastEpisode: widget.isLastEpisode,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                // 视频加载中的指示器（覆盖在视频上方）
                if (_isLoadingVideo)
                  const Positioned.fill(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
    );
  }
}
