import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../services/release_calendar_service.dart';
import '../services/theme_service.dart';
import '../utils/font_utils.dart';
import '../utils/device_utils.dart';
import '../models/video_info.dart';
import '../screens/release_calendar_screen.dart';
import 'video_menu_bottom_sheet.dart';

/// 即将上映组件
class UpcomingSection extends StatefulWidget {
  final Function(VideoInfo)? onItemTap;
  final VoidCallback? onMoreTap;
  final Function(VideoInfo, VideoMenuAction)? onGlobalMenuAction;

  const UpcomingSection({
    super.key,
    this.onItemTap,
    this.onMoreTap,
    this.onGlobalMenuAction,
  });

  // 静态刷新方法
  static final _refreshController = StreamController<void>.broadcast();
  static Stream<void> get refreshStream => _refreshController.stream;
  
  static Future<void> refreshUpcoming() async {
    _refreshController.add(null);
  }

  @override
  State<UpcomingSection> createState() => _UpcomingSectionState();
}

class _UpcomingSectionState extends State<UpcomingSection> {
  List<ReleaseCalendarItem> _items = [];
  bool _isLoading = true;
  String? _error;
  String _selectedFilter = 'all'; // 'all' | 'movie' | 'tv'
  StreamSubscription<void>? _refreshSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshSubscription = UpcomingSection.refreshStream.listen((_) {
      _loadData(forceRefresh: true);
    });
  }

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await ReleaseCalendarService.getUpcomingForHome(
        maxItems: 10,
        forceRefresh: forceRefresh,
      );

      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<ReleaseCalendarItem> get _filteredItems {
    if (_selectedFilter == 'all') return _items;
    return _items.where((item) => item.type == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有数据且不在加载中，不显示组件
    if (!_isLoading && _items.isEmpty && _error == null) {
      return const SizedBox.shrink();
    }

    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        size: 20,
                        color: const Color(0xFFF97316), // orange-500
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '即将上映',
                        style: FontUtils.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: themeService.isDarkMode
                              ? Colors.white
                              : const Color(0xFF2c3e50),
                        ),
                      ),
                    ],
                  ),
                  if (widget.onMoreTap != null)
                    GestureDetector(
                      onTap: widget.onMoreTap,
                      child: Row(
                        children: [
                          Text(
                            '查看更多',
                            style: FontUtils.poppins(
                              fontSize: 13,
                              color: themeService.isDarkMode
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                          Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: themeService.isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ],
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ReleaseCalendarScreen(),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          Text(
                            '查看更多',
                            style: FontUtils.poppins(
                              fontSize: 13,
                              color: themeService.isDarkMode
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                          Icon(
                            LucideIcons.chevronRight,
                            size: 16,
                            color: themeService.isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // 筛选标签
            if (!_isLoading && _items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    _buildFilterChip('全部', 'all', _items.length, themeService),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      '电影',
                      'movie',
                      _items.where((i) => i.type == 'movie').length,
                      themeService,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      '电视剧',
                      'tv',
                      _items.where((i) => i.type == 'tv').length,
                      themeService,
                    ),
                  ],
                ),
              ),
            // 内容区域
            SizedBox(
              height: DeviceUtils.isTablet(context) ? 260 : 200,
              child: _buildContent(themeService),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(
    String label,
    String value,
    int count,
    ThemeService themeService,
  ) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF97316)
              : themeService.isDarkMode
                  ? Colors.grey[800]
                  : Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
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
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '($count)',
                style: FontUtils.poppins(
                  fontSize: 11,
                  color: isSelected
                      ? Colors.white.withOpacity(0.8)
                      : themeService.isDarkMode
                          ? Colors.grey[500]
                          : Colors.grey[500],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeService themeService) {
    if (_isLoading) {
      return _buildLoadingState(themeService);
    }

    if (_error != null) {
      return _buildErrorState(themeService);
    }

    if (_filteredItems.isEmpty) {
      return _buildEmptyState(themeService);
    }

    return _buildItemsList(themeService);
  }

  Widget _buildLoadingState(ThemeService themeService) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          width: DeviceUtils.isTablet(context) ? 160 : 120,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: themeService.isDarkMode
                ? Colors.grey[800]
                : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
        );
      },
    );
  }

  Widget _buildErrorState(ThemeService themeService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 32,
            color: Colors.red[300],
          ),
          const SizedBox(height: 8),
          Text(
            '加载失败',
            style: FontUtils.poppins(
              fontSize: 14,
              color: themeService.isDarkMode ? Colors.white54 : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _loadData(forceRefresh: true),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeService themeService) {
    return Center(
      child: Text(
        '暂无即将上映内容',
        style: FontUtils.poppins(
          fontSize: 14,
          color: themeService.isDarkMode ? Colors.white54 : Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildItemsList(ThemeService themeService) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        return _buildItemCard(item, themeService);
      },
    );
  }

  Widget _buildItemCard(ReleaseCalendarItem item, ThemeService themeService) {
    final cardWidth = DeviceUtils.isTablet(context) ? 160.0 : 120.0;
    final imageHeight = DeviceUtils.isTablet(context) ? 200.0 : 150.0;

    return GestureDetector(
      onTap: () {
        if (widget.onItemTap != null) {
          final videoInfo = VideoInfo(
            id: item.id,
            source: 'upcoming_release',
            title: item.title,
            sourceName: '即将上映',
            year: item.releaseDate.split('-').first,
            cover: item.cover ?? '',
            index: 1,
            totalEpisodes: item.episodes ?? 1,
            playTime: 0,
            totalTime: 0,
            saveTime: 0,
            searchTitle: item.title,
          );
          widget.onItemTap!(videoInfo);
        }
      },
      onLongPress: () {
        if (widget.onGlobalMenuAction != null) {
          final videoInfo = VideoInfo(
            id: item.id,
            source: 'upcoming_release',
            title: item.title,
            sourceName: '即将上映',
            year: item.releaseDate.split('-').first,
            cover: item.cover ?? '',
            index: 1,
            totalEpisodes: item.episodes ?? 1,
            playTime: 0,
            totalTime: 0,
            saveTime: 0,
            searchTitle: item.title,
          );
          VideoMenuBottomSheet.show(
            context,
            videoInfo: videoInfo,
            onAction: (action) {
              widget.onGlobalMenuAction!(videoInfo, action);
            },
            from: 'upcoming',
          );
        }
      },
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图
            Stack(
              children: [
                Container(
                  height: imageHeight,
                  decoration: BoxDecoration(
                    color: themeService.isDarkMode
                        ? Colors.grey[800]
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: item.cover != null && item.cover!.isNotEmpty
                        ? Image.network(
                            item.cover!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildPlaceholder(themeService);
                            },
                          )
                        : _buildPlaceholder(themeService),
                  ),
                ),
                // 类型标签（左上角）
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.type == 'movie'
                          ? const Color(0xFFEF4444) // red-500
                          : const Color(0xFF3B82F6), // blue-500
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.type == 'movie' ? '电影' : '剧集',
                      style: FontUtils.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // 上映状态标签（右上角）
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getStatusColor(item),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.remarksText,
                      style: FontUtils.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 标题
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: FontUtils.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: themeService.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeService themeService) {
    return Container(
      color: themeService.isDarkMode ? Colors.grey[800] : Colors.grey[200],
      child: Center(
        child: Icon(
          LucideIcons.film,
          size: 32,
          color: themeService.isDarkMode ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );
  }

  Color _getStatusColor(ReleaseCalendarItem item) {
    if (item.isReleased) {
      return const Color(0xFF22C55E); // green-500
    } else if (item.isReleasingToday) {
      return const Color(0xFFF97316); // orange-500
    } else {
      return const Color(0xFF6366F1); // indigo-500
    }
  }
}
