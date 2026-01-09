import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/youtube_service.dart';
import '../services/theme_service.dart';
import '../utils/font_utils.dart';

/// YouTube 搜索结果组件
class YouTubeResultsWidget extends StatefulWidget {
  final String query;
  final Function(YouTubeVideo)? onVideoTap;

  const YouTubeResultsWidget({
    super.key,
    required this.query,
    this.onVideoTap,
  });

  @override
  State<YouTubeResultsWidget> createState() => _YouTubeResultsWidgetState();
}

class _YouTubeResultsWidgetState extends State<YouTubeResultsWidget> {
  YouTubeSearchResult? _result;
  bool _isLoading = false;
  String? _error;

  YouTubeContentType _contentType = YouTubeContentType.all;
  YouTubeSortOrder _sortOrder = YouTubeSortOrder.relevance;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(YouTubeResultsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _search();
    }
  }

  Future<void> _search() async {
    if (widget.query.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await YouTubeService.search(
      query: widget.query,
      contentType: _contentType,
      sortOrder: _sortOrder,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.success) {
          _result = result;
          _error = null;
        } else {
          _error = result.error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 筛选器
            _buildFilters(themeService),
            const SizedBox(height: 12),
            // 警告信息
            if (_result?.warning != null)
              _buildWarning(themeService),
            // 内容
            Expanded(
              child: _buildContent(themeService),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilters(ThemeService themeService) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 内容类型筛选
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: YouTubeContentType.values.map((type) {
              final isSelected = _contentType == type;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _contentType = type;
                    });
                    _search();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFF0000) // YouTube 红
                          : themeService.isDarkMode
                              ? Colors.grey[800]
                              : Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      type.label,
                      style: FontUtils.poppins(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected
                            ? Colors.white
                            : themeService.isDarkMode
                                ? Colors.grey[300]
                                : Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // 排序筛选
        Row(
          children: [
            Text(
              '排序：',
              style: FontUtils.poppins(
                fontSize: 12,
                color: themeService.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: YouTubeSortOrder.values.map((order) {
                    final isSelected = _sortOrder == order;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _sortOrder = order;
                          });
                          _search();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF3B82F6)
                                : themeService.isDarkMode
                                    ? Colors.grey[800]
                                    : Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF3B82F6)
                                  : themeService.isDarkMode
                                      ? Colors.grey[700]!
                                      : Colors.grey[300]!,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (order.icon.isNotEmpty) ...[
                                Text(order.icon, style: const TextStyle(fontSize: 10)),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                order.label,
                                style: FontUtils.poppins(
                                  fontSize: 11,
                                  color: isSelected
                                      ? Colors.white
                                      : themeService.isDarkMode
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWarning(ThemeService themeService) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _result!.warning!,
              style: FontUtils.poppins(
                fontSize: 12,
                color: const Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeService themeService) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF0000)),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: FontUtils.poppins(
                fontSize: 14,
                color: themeService.isDarkMode ? Colors.white70 : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _search,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF0000),
              ),
              child: const Text('重试', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_result == null || _result!.videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.youtube,
              size: 48,
              color: themeService.isDarkMode ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '未找到相关 YouTube 视频',
              style: FontUtils.poppins(
                fontSize: 14,
                color: themeService.isDarkMode ? Colors.white54 : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _result!.videos.length + 1, // +1 for debug info
      itemBuilder: (context, index) {
        // 第一个item显示调试信息
        if (index == 0) {
          final firstVideo = _result!.videos.isNotEmpty ? _result!.videos[0] : null;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔍 调试信息 (共 ${_result!.videos.length} 个结果)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 4),
                if (firstVideo != null) ...[
                  Text('videoId: ${firstVideo.videoId}', style: const TextStyle(fontSize: 11)),
                  Text('thumbnailUrl: ${firstVideo.thumbnailUrl}', style: const TextStyle(fontSize: 11)),
                  Text('title: ${firstVideo.title}', style: const TextStyle(fontSize: 11)),
                ],
              ],
            ),
          );
        }
        
        final video = _result!.videos[index - 1];
        return _YouTubeVideoCard(
          video: video,
          themeService: themeService,
          onTap: () => widget.onVideoTap?.call(video),
        );
      },
    );
  }
}

/// YouTube 视频卡片
class _YouTubeVideoCard extends StatefulWidget {
  final YouTubeVideo video;
  final ThemeService themeService;
  final VoidCallback? onTap;

  const _YouTubeVideoCard({
    required this.video,
    required this.themeService,
    this.onTap,
  });

  @override
  State<_YouTubeVideoCard> createState() => _YouTubeVideoCardState();
}

class _YouTubeVideoCardState extends State<_YouTubeVideoCard> {
  YouTubeVideo get video => widget.video;
  ThemeService get themeService => widget.themeService;

  @override
  Widget build(BuildContext context) {
    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: themeService.isDarkMode
              ? Colors.white.withOpacity(0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: themeService.isDarkMode
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 缩略图 - 点击播放
            GestureDetector(
              onTap: _openInBrowser,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: video.thumbnailUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: video.thumbnailUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: themeService.isDarkMode ? Colors.grey[800] : Colors.grey[200],
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF0000)),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => _buildPlaceholder(),
                            )
                          : _buildPlaceholder(),
                    ),
                  ),
                  // YouTube 标识
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF0000),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.youtube, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'YouTube',
                            style: FontUtils.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 播放按钮
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF0000).withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 信息
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FontUtils.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: themeService.isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 频道和日期
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          video.channelTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FontUtils.poppins(
                            fontSize: 12,
                            color: themeService.isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ),
                      ),
                      Text(
                        video.formattedDate,
                        style: FontUtils.poppins(
                          fontSize: 11,
                          color: themeService.isDarkMode
                              ? Colors.grey[500]
                              : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: themeService.isDarkMode ? Colors.grey[800] : Colors.grey[200],
      child: Center(
        child: Icon(
          LucideIcons.youtube,
          size: 48,
          color: themeService.isDarkMode ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(video.videoUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
