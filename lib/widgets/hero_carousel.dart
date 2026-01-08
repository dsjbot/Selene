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
  final String? debugError; // 调试用：记录获取详情时的错误

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
    this.debugError,
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
  bool _isUserInteracting = false;
  
  // 预告片播放器
  Player? _trailerPlayer;
  VideoController? _trailerController;
  bool _isVideoLoaded = false;
  bool _isMuted = true;
  String? _currentTrailerUrl;
  String? _serverUrl;
  
  // 调试信息
  String _debugInfo = '初始化中...';

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
    _startAutoPlay();
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
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    _disposeTrailerPlayer();
    super.dispose();
  }

  void _disposeTrailerPlayer() {
    final player = _trailerPlayer;
    _trailerPlayer = null;
    _trailerController = null;
    _isVideoLoaded = false;
    _currentTrailerUrl = null;
    
    // 异步释放播放器，避免阻塞 UI
    if (player != null) {
      Future.microtask(() async {
        try {
          await player.stop();
          await player.dispose();
        } catch (e) {
          debugPrint('[HeroCarousel] 释放播放器时出错: $e');
        }
      });
    }
  }

  /// 加载当前项目的预告片
  Future<void> _loadTrailerForCurrentItem() async {
    if (!widget.enableVideo || widget.items.isEmpty) {
      setState(() => _debugInfo = '跳过: enableVideo=${widget.enableVideo}, items=${widget.items.length}');
      return;
    }
    
    final currentItem = widget.items[_currentIndex];
    final trailerUrl = currentItem.trailerUrl;
    final errorInfo = currentItem.debugError ?? "无";
    
    // 始终显示完整调试信息
    setState(() => _debugInfo = '${currentItem.title}\nerror: $errorInfo');
    
    // 如果没有预告片URL，释放播放器
    if (trailerUrl == null || trailerUrl.isEmpty) {
      _disposeTrailerPlayer();
      return;
    }
    
    // 如果URL相同且播放器存在，不重新加载
    if (trailerUrl == _currentTrailerUrl && _trailerPlayer != null) {
      return;
    }
    
    // 先释放旧的播放器
    _disposeTrailerPlayer();
    
    // 等待一帧，确保旧播放器已释放
    await Future.delayed(const Duration(milliseconds: 100));
    
    if (!mounted) return;
    
    // 创建新的播放器
    try {
      final proxiedUrl = await _getProxiedVideoUrl(trailerUrl);
      setState(() => _debugInfo = '${currentItem.title}\n加载视频中...');
      
      final newPlayer = Player();
      final newController = VideoController(newPlayer);
      
      _trailerPlayer = newPlayer;
      _trailerController = newController;
      _currentTrailerUrl = trailerUrl;
      
      // 设置静音和循环
      await newPlayer.setVolume(_isMuted ? 0 : 100);
      await newPlayer.setPlaylistMode(PlaylistMode.loop);
      
      // 监听视频宽高变化（表示视频已加载）
      newPlayer.stream.width.listen((width) {
        if (mounted && width != null && width > 0 && !_isVideoLoaded && _trailerPlayer == newPlayer) {
          setState(() {
            _isVideoLoaded = true;
            _debugInfo = '${currentItem.title}\n视频已加载 宽度:$width';
          });
        }
      });
      
      // 监听播放状态
      newPlayer.stream.playing.listen((playing) {
        if (mounted && playing && _trailerPlayer == newPlayer) {
          setState(() => _debugInfo = '${currentItem.title}\n播放中...');
        }
      });
      
      newPlayer.stream.error.listen((error) {
        if (mounted && _trailerPlayer == newPlayer) {
          setState(() {
            _isVideoLoaded = false;
            _debugInfo = '${currentItem.title}\n播放错误: $error';
          });
        }
      });
      
      // 获取 cookies 用于视频请求
      final cookies = await UserDataService.getCookies();
      final headers = <String, String>{};
      if (cookies != null && cookies.isNotEmpty) {
        headers['Cookie'] = cookies;
      }
      
      // 开始播放，带上认证 headers
      await newPlayer.open(
        Media(proxiedUrl, httpHeaders: headers),
      );
      
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _debugInfo = '${currentItem.title}\n加载失败: $e');
      }
      _disposeTrailerPlayer();
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
      if (!_isUserInteracting && mounted) {
        _goToNext();
      }
    });
  }

  void _goToNext() {
    if (!mounted || widget.items.isEmpty) return;
    final nextIndex = (_currentIndex + 1) % widget.items.length;
    _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _goToPrevious() {
    if (!mounted || widget.items.isEmpty) return;
    final prevIndex = (_currentIndex - 1 + widget.items.length) % widget.items.length;
    _pageController.animateToPage(
      prevIndex,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _isVideoLoaded = false;
    });
    // 加载新页面的预告片
    _loadTrailerForCurrentItem();
  }

  void _onUserInteractionStart() {
    _isUserInteracting = true;
    _autoPlayTimer?.cancel();
  }

  void _onUserInteractionEnd() {
    _isUserInteracting = false;
    _startAutoPlay();
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
            GestureDetector(
              onHorizontalDragStart: (_) => _onUserInteractionStart(),
              onHorizontalDragEnd: (_) => _onUserInteractionEnd(),
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: widget.items.length,
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return _buildCarouselItem(item, isTablet, index);
                },
              ),
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
            
            // 调试信息（临时）
            Positioned(
              top: isTablet ? 50 : 30,
              left: isTablet ? 16 : 8,
              right: isTablet ? 16 : 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '调试: $_debugInfo\nvideoLoaded: $_isVideoLoaded\ncontroller: ${_trailerController != null}',
                  style: const TextStyle(
                    color: Colors.yellow,
                    fontSize: 10,
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
    
    return GestureDetector(
      onTap: () => widget.onItemTap?.call(item),
      child: FutureBuilder<String>(
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
      ),
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
