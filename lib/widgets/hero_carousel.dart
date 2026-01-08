import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/image_url.dart';

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

  const HeroCarousel({
    super.key,
    required this.items,
    this.autoPlayInterval = const Duration(seconds: 6),
    this.onItemTap,
    this.showIndicators = true,
  });

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  int _currentIndex = 0;
  Timer? _autoPlayTimer;
  final PageController _pageController = PageController();
  bool _isUserInteracting = false;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
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
    });
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
                  return _buildCarouselItem(item, isTablet);
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
          ],
        ),
      ),
    );
  }

  Widget _buildCarouselItem(CarouselItem item, bool isTablet) {
    // 优先使用 backdrop，如果为空则使用 poster
    final backdrop = item.backdrop;
    final imageUrl = (backdrop != null && backdrop.isNotEmpty) ? backdrop : item.poster;
    
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
              // 背景图片
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
                  debugPrint('[HeroCarousel] 图片加载失败: $url, 错误: $error');
                  return Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.broken_image, color: Colors.white54, size: 48),
                  );
                },
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
