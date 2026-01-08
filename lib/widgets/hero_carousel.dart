import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../utils/image_url.dart';
import '../services/user_data_service.dart';

/// 轮播图项目数据
class CarouselItem {
  final String id;
  final String title;
  final String poster;
  final String? backdrop;
  final String? description;
  final String? trailerUrl;
  final String? year;
  final String? rate;
  final String type; // movie, tv, variety, anime

  CarouselItem({
    required this.id,
    required this.title,
    required this.poster,
    this.backdrop,
    this.description,
    this.trailerUrl,
    this.year,
    this.rate,
    required this.type,
  });
}

/// Netflix风格轮播图组件
class HeroCarousel extends StatefulWidget {
  final List<CarouselItem> items;
  final Duration autoPlayInterval;
  final Function(CarouselItem)? onItemTap;
  final bool showIndicators;
  final bool enableVideo; // 是否启用预告片视频

  const HeroCarousel({
    super.key,
    required this.items,
    this.autoPlayInterval = const Duration(seconds: 6),
    this.onItemTap,
    this.showIndicators = true,
    this.enableVideo = true,
  });

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  int _currentIndex = 0;
  Timer? _autoPlayTimer;
  final PageController _pageController = PageController();
  bool _isAutoPlayPaused = false; // 手动滑动后暂停自动播放
  bool _isAutoSwitching = false; // 标记是否是自动切换
  bool _isDisposed = false; // 标记是否已经 dispose
  
  // 预告片播放器 - 复用同一个实例
  Player? _trailerPlayer;
  VideoController? _trailerController;
  bool _isVideoLoaded = false;
  bool _isMuted = true;
  String? _currentTrailerUrl;
  String? _serverUrl;
  bool _isLoadingVideo = false; // 防止重复加载

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _loadServerUrl();
    _startAutoPlay();
  }

  /// 初始化播放器（只创建一次）
  void _initPlayer() {
    if (!widget.enableVideo) return;
    _trailerPlayer = Player();
    _trailerController = VideoController(_trailerPlayer!);
    
    // 设置静音和循环
    _trailerPlayer!.setVolume(0);
    _trailerPlayer!.setPlaylistMode(PlaylistMode.loop);
    
    // 监听视频宽高变化（表示视频已加载）
    _trailerPlayer!.stream.width.listen((width) {
      if (mounted && !_isDisposed && width != null && width > 0 && !_isVideoLoaded) {
        setState(() {
          _isVideoLoaded = true;
        });
      }
    });
    
    _trailerPlayer!.stream.error.listen((error) {
      debugPrint('[HeroCarousel] 预告片播放错误: $error');
      if (mounted && !_isDisposed) {
        setState(() {
          _isVideoLoaded = false;
        });
      }
    });
  }

  Future<void> _loadServerUrl() async {
    final url = await UserDataService.getServerUrl();
    if (mounted) {
      setState(() {
        _serverUrl = url;
      });
      // 服务器URL加载完成后，尝试加载当前项目的预告片
      _loadTrailerForCurrentItem();
    }
  }

  @override
  void dispose() {
    debugPrint('[HeroCarousel] dispose called');
    _isDisposed = true;
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    _pageController.dispose();
    
    // 同步停止并释放播放器
    final player = _trailerPlayer;
    _trailerPlayer = null;
    _trailerController = null;
    
    if (player != null) {
      // 同步调用 stop 和 dispose（不等待完成）
      player.stop().then((_) => player.dispose()).catchError((e) {
        debugPrint('[HeroCarousel] dispose player error: $e');
      });
    }
    
    super.dispose();
  }

  /// 加载当前项目的预告片
  Future<void> _loadTrailerForCurrentItem() async {
    if (_isDisposed || !widget.enableVideo || widget.items.isEmpty || _trailerPlayer == null) {
      return;
    }
    
    // 防止重复加载
    if (_isLoadingVideo) return;
    
    final currentItem = widget.items[_currentIndex];
    final trailerUrl = currentItem.trailerUrl;
    
    // 如果没有预告片URL，停止播放
    if (trailerUrl == null || trailerUrl.isEmpty) {
      if (mounted && !_isDisposed) {
        setState(() {
          _isVideoLoaded = false;
          _currentTrailerUrl = null;
        });
      }
      try {
        await _trailerPlayer?.stop();
      } catch (e) {
        debugPrint('[HeroCarousel] stop player error: $e');
      }
      return;
    }
    
    // 如果URL相同，不重新加载
    if (trailerUrl == _currentTrailerUrl) {
      return;
    }
    
    _isLoadingVideo = true;
    if (mounted && !_isDisposed) {
      setState(() {
        _isVideoLoaded = false;
      });
    }
    
    try {
      final proxiedUrl = await _getProxiedVideoUrl(trailerUrl);
      
      // 检查是否已经 dispose
      if (_isDisposed || !mounted || _trailerPlayer == null) return;
      
      _currentTrailerUrl = trailerUrl;
      
      // 获取 cookies 用于视频请求
      final cookies = await UserDataService.getCookies();
      final headers = <String, String>{};
      if (cookies != null && cookies.isNotEmpty) {
        headers['Cookie'] = cookies;
      }
      
      // 再次检查
      if (_isDisposed || !mounted || _trailerPlayer == null) return;
      
      // 切换视频源
      await _trailerPlayer!.open(
        Media(proxiedUrl, httpHeaders: headers),
      );
      
    } catch (e) {
      debugPrint('[HeroCarousel] 加载预告片失败: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _isVideoLoaded = false;
        });
      }
    } finally {
      _isLoadingVideo = false;
    }
  }

  /// 获取代理后的视频URL
  /// 所有预告片视频都通过后端代理，以处理防盗链和跨域问题
  Future<String> _getProxiedVideoUrl(String url) async {
    if (_serverUrl != null && _serverUrl!.isNotEmpty) {
      // 所有预告片视频都走代理，后端会根据域名自动设置正确的 Referer
      return '$_serverUrl/api/video-proxy?url=${Uri.encodeComponent(url)}';
    }
    return url;
  }

  /// 切换静音状态
  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _trailerPlayer?.setVolume(_isMuted ? 0 : 100);
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    if (widget.items.length <= 1) return;
    
    _autoPlayTimer = Timer.periodic(widget.autoPlayInterval, (_) {
      if (!_isAutoPlayPaused && mounted) {
        _goToNext();
      }
    });
  }

  /// 恢复自动播放（供外部调用）
  void resumeAutoPlay() {
    _isAutoPlayPaused = false;
  }

  void _goToNext() {
    if (!mounted || widget.items.isEmpty) return;
    final nextIndex = (_currentIndex + 1) % widget.items.length;
    _isAutoSwitching = true; // 标记为自动切换
    _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _goToPrevious() {
    if (!mounted || widget.items.isEmpty) return;
    final prevIndex = (_currentIndex - 1 + widget.items.length) % widget.items.length;
    _isAutoSwitching = true; // 标记为自动切换（导航按钮也算自动）
    _pageController.animateToPage(
      prevIndex,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    // 如果不是自动切换，说明是用户手动滑动，暂停自动播放
    if (!_isAutoSwitching) {
      _isAutoPlayPaused = true;
    }
    _isAutoSwitching = false; // 重置标记
    
    setState(() {
      _currentIndex = index;
      _isVideoLoaded = false;
    });
    // 加载新页面的预告片
    _loadTrailerForCurrentItem();
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'movie':
        return '电影';
      case 'tv':
        return '剧集';
      case 'variety':
        return '综艺';
      case 'anime':
        return '动漫';
      default:
        return '剧集';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final aspectRatio = isTablet ? 21 / 9 : 16 / 9;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        child: Stack(
          children: [
            // 轮播内容
            PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: widget.items.length,
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return _buildCarouselItem(item, isTablet, index);
              },
            ),

            // 左右导航按钮（仅平板显示）
            if (isTablet && widget.items.length > 1) ...[
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildNavButton(
                    icon: Icons.chevron_left,
                    onTap: _goToPrevious,
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildNavButton(
                    icon: Icons.chevron_right,
                    onTap: _goToNext,
                  ),
                ),
              ),
            ],

            // 指示器
            if (widget.showIndicators && widget.items.length > 1)
              Positioned(
                bottom: isTablet ? 16 : 12,
                left: 0,
                right: 0,
                child: _buildIndicators(),
              ),

            // 页码
            Positioned(
              top: isTablet ? 16 : 8,
              right: isTablet ? 16 : 8,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 10 : 6,
                  vertical: isTablet ? 4 : 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white.withOpacity(0.5)),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.items.length}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isTablet ? 12 : 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarouselItem(CarouselItem item, bool isTablet, int index) {
    // 优先使用 backdrop，如果为空则使用 poster
    final backdrop = item.backdrop;
    final imageUrl = (backdrop != null && backdrop.isNotEmpty) ? backdrop : item.poster;
    final isCurrentItem = index == _currentIndex;
    final hasTrailer = item.trailerUrl != null && item.trailerUrl!.isNotEmpty;
    // 只要是当前项目且有预告片URL，就渲染视频层（通过opacity控制显示）
    final shouldRenderVideo = widget.enableVideo && isCurrentItem && hasTrailer && _trailerController != null;
    
    // 不在整个轮播项上添加点击事件，只在播放按钮上添加
    return FutureBuilder<String>(
      future: getImageUrl(imageUrl, 'douban'),
      builder: (context, snapshot) {
        final String finalImageUrl = snapshot.data ?? imageUrl;
        final headers = getImageRequestHeaders(finalImageUrl, 'douban');
          
          return Stack(
            fit: StackFit.expand,
            children: [
              // 背景图片（始终显示，作为视频的占位符）
              CachedNetworkImage(
                imageUrl: finalImageUrl,
                fit: BoxFit.cover,
                httpHeaders: headers,
                placeholder: (context, url) => Container(
                  color: Colors.grey[900],
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white54,
                      strokeWidth: 2,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) {
                  return Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.broken_image, color: Colors.white54, size: 48),
                  );
                },
              ),

              // 预告片视频层（淡入显示）
              if (shouldRenderVideo)
                AnimatedOpacity(
                  opacity: _isVideoLoaded ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 500),
                  child: Video(
                    controller: _trailerController!,
                    fit: BoxFit.cover,
                    controls: NoVideoControls,
                  ),
                ),

              // 渐变遮罩
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.3),
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),

              // 左侧渐变（增强文字可读性）
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withOpacity(0.5),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5],
                  ),
                ),
              ),

              // 内容
              Positioned(
                left: isTablet ? 32 : 16,
                right: isTablet ? 32 : 16,
                bottom: isTablet ? 48 : 36,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题
                    Text(
                      item.title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isTablet ? 28 : 18,
                        fontWeight: FontWeight.bold,
                        shadows: const [
                          Shadow(
                            offset: Offset(1, 1),
                            blurRadius: 4,
                            color: Colors.black87,
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: isTablet ? 12 : 8),

                    // 元数据
                    Row(
                      children: [
                        if (item.rate != null && item.rate!.isNotEmpty)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isTablet ? 8 : 6,
                              vertical: isTablet ? 4 : 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.star,
                                  color: Colors.white,
                                  size: isTablet ? 14 : 10,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  item.rate!,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isTablet ? 12 : 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (item.year != null && item.year!.isNotEmpty) ...[
                          SizedBox(width: isTablet ? 12 : 8),
                          Text(
                            item.year!,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: isTablet ? 14 : 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        SizedBox(width: isTablet ? 12 : 8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 8 : 6,
                            vertical: isTablet ? 4 : 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white.withOpacity(0.3)),
                          ),
                          child: Text(
                            _getTypeLabel(item.type),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: isTablet ? 12 : 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // 描述（手机上显示1行，平板显示2行）
                    if (item.description != null && item.description!.isNotEmpty) ...[
                      SizedBox(height: isTablet ? 12 : 6),
                      Text(
                        item.description!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: isTablet ? 14 : 11,
                          height: 1.4,
                        ),
                        maxLines: isTablet ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    SizedBox(height: isTablet ? 16 : 12),

                    // 播放按钮
                    Row(
                      children: [
                        _buildActionButton(
                          icon: Icons.play_arrow,
                          label: '播放',
                          isPrimary: true,
                          isTablet: isTablet,
                          onTap: () => widget.onItemTap?.call(item),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 音量控制按钮（仅当预告片视频加载完成时显示）
              if (shouldRenderVideo && _isVideoLoaded)
                Positioned(
                  bottom: isTablet ? 48 : 36,
                  right: isTablet ? 32 : 16,
                  child: GestureDetector(
                    onTap: _toggleMute,
                    child: Container(
                      width: isTablet ? 40 : 32,
                      height: isTablet ? 40 : 32,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.5)),
                      ),
                      child: Icon(
                        _isMuted ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                        size: isTablet ? 20 : 16,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isPrimary,
    required bool isTablet,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 20 : 14,
          vertical: isTablet ? 10 : 6,
        ),
        decoration: BoxDecoration(
          color: isPrimary ? Colors.white : Colors.white.withOpacity(0.3),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isPrimary ? Colors.black : Colors.white,
              size: isTablet ? 22 : 16,
            ),
            SizedBox(width: isTablet ? 6 : 4),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? Colors.black : Colors.white,
                fontSize: isTablet ? 14 : 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }

  Widget _buildIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.items.length, (index) {
        final isActive = index == _currentIndex;
        return GestureDetector(
          onTap: () {
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isActive ? 24 : 8,
            height: 4,
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}
