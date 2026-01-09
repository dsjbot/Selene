import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../services/release_calendar_service.dart';
import '../services/theme_service.dart';
import '../utils/font_utils.dart';
import '../utils/device_utils.dart';
import '../widgets/main_layout.dart';
import '../widgets/custom_refresh_indicator.dart';
import 'player_screen.dart';

/// 发布日历页面
class ReleaseCalendarScreen extends StatefulWidget {
  const ReleaseCalendarScreen({super.key});

  @override
  State<ReleaseCalendarScreen> createState() => _ReleaseCalendarScreenState();
}

class _ReleaseCalendarScreenState extends State<ReleaseCalendarScreen> {
  List<ReleaseCalendarItem> _items = [];
  ReleaseCalendarFilters? _filters;
  bool _isLoading = true;
  String? _error;

  // 筛选状态
  String _selectedType = ''; // '' | 'movie' | 'tv'
  String _selectedRegion = '';
  String _selectedGenre = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await ReleaseCalendarService.getCalendar(
        forceRefresh: forceRefresh,
      );

      if (mounted) {
        setState(() {
          if (result.success) {
            _items = result.items;
            _filters = result.filters;
          } else {
            _error = result.error;
          }
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
    var items = _items;

    if (_selectedType.isNotEmpty) {
      items = items.where((i) => i.type == _selectedType).toList();
    }

    if (_selectedRegion.isNotEmpty && _selectedRegion != '全部') {
      items = items.where((i) => i.region.contains(_selectedRegion)).toList();
    }

    if (_selectedGenre.isNotEmpty && _selectedGenre != '全部') {
      items = items.where((i) => i.genre.contains(_selectedGenre)).toList();
    }

    // 按发布日期排序
    items.sort((a, b) => a.releaseDate.compareTo(b.releaseDate));

    return items;
  }

  // 按日期分组
  Map<String, List<ReleaseCalendarItem>> get _groupedItems {
    final grouped = <String, List<ReleaseCalendarItem>>{};
    for (final item in _filteredItems) {
      final date = item.releaseDate;
      if (!grouped.containsKey(date)) {
        grouped[date] = [];
      }
      grouped[date]!.add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return MainLayout(
          content: Container(
            color: themeService.isDarkMode
                ? const Color(0xFF121212)
                : const Color(0xFFf5f5f5),
            child: Column(
              children: [
                // 标题栏
                _buildHeader(themeService),
                // 筛选器
                _buildFilters(themeService),
                // 内容
                Expanded(
                  child: _buildContent(themeService),
                ),
              ],
            ),
          ),
          currentBottomNavIndex: -1,
          onBottomNavChanged: (index) {
            Navigator.pop(context);
          },
          selectedTopTab: '',
          onTopTabChanged: (tab) {},
          showBottomNav: false,
          onHomeTap: () {
            Navigator.pop(context);
          },
        );
      },
    );
  }

  Widget _buildHeader(ThemeService themeService) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(
              LucideIcons.arrowLeft,
              size: 24,
              color: themeService.isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(width: 16),
          Icon(
            LucideIcons.calendar,
            size: 24,
            color: const Color(0xFFF97316),
          ),
          const SizedBox(width: 8),
          Text(
            '发布日历',
            style: FontUtils.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: themeService.isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const Spacer(),
          if (!_isLoading)
            Text(
              '共 ${_filteredItems.length} 部',
              style: FontUtils.poppins(
                fontSize: 13,
                color: themeService.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilters(ThemeService themeService) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：类型筛选
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  label: '全部类型',
                  value: '',
                  selectedValue: _selectedType,
                  onTap: () => setState(() => _selectedType = ''),
                  themeService: themeService,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: '电影',
                  value: 'movie',
                  selectedValue: _selectedType,
                  onTap: () => setState(() => _selectedType = 'movie'),
                  themeService: themeService,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: '电视剧',
                  value: 'tv',
                  selectedValue: _selectedType,
                  onTap: () => setState(() => _selectedType = 'tv'),
                  themeService: themeService,
                ),
              ],
            ),
          ),
          // 第二行：地区和类型筛选
          if (_filters != null && (_filters!.regions.isNotEmpty || _filters!.genres.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (_filters!.regions.isNotEmpty)
                      _buildDropdownFilter(
                        label: _selectedRegion.isEmpty ? '地区' : _selectedRegion,
                        options: ['全部', ..._filters!.regions.map((r) => r.value)],
                        selectedValue: _selectedRegion,
                        onChanged: (value) => setState(() => _selectedRegion = value == '全部' ? '' : value),
                        themeService: themeService,
                      ),
                    if (_filters!.regions.isNotEmpty && _filters!.genres.isNotEmpty)
                      const SizedBox(width: 8),
                    if (_filters!.genres.isNotEmpty)
                      _buildDropdownFilter(
                        label: _selectedGenre.isEmpty ? '类型' : _selectedGenre,
                        options: ['全部', ..._filters!.genres.map((g) => g.value)],
                        selectedValue: _selectedGenre,
                        onChanged: (value) => setState(() => _selectedGenre = value == '全部' ? '' : value),
                        themeService: themeService,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required String value,
    required String selectedValue,
    required VoidCallback onTap,
    required ThemeService themeService,
  }) {
    final isSelected = value == selectedValue;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF97316)
              : themeService.isDarkMode
                  ? Colors.grey[800]
                  : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(
                  color: themeService.isDarkMode
                      ? Colors.grey[700]!
                      : Colors.grey[300]!,
                ),
        ),
        child: Text(
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
      ),
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required List<String> options,
    required String selectedValue,
    required Function(String) onChanged,
    required ThemeService themeService,
  }) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: themeService.isDarkMode ? const Color(0xFF2d2d2d) : Colors.white,
      itemBuilder: (context) => options.map((option) {
        return PopupMenuItem<String>(
          value: option,
          child: Text(
            option,
            style: FontUtils.poppins(
              fontSize: 13,
              color: themeService.isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: themeService.isDarkMode ? Colors.grey[800] : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: themeService.isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: FontUtils.poppins(
                fontSize: 13,
                color: themeService.isDarkMode ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: themeService.isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeService themeService) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF97316)),
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
              '加载失败',
              style: FontUtils.poppins(
                fontSize: 16,
                color: themeService.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: FontUtils.poppins(
                fontSize: 13,
                color: themeService.isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadData(forceRefresh: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF97316),
              ),
              child: const Text('重试', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_filteredItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.calendar,
              size: 48,
              color: themeService.isDarkMode ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '暂无数据',
              style: FontUtils.poppins(
                fontSize: 16,
                color: themeService.isDarkMode ? Colors.white54 : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return StyledRefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      refreshText: '刷新中...',
      primaryColor: const Color(0xFFF97316),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _groupedItems.length,
        itemBuilder: (context, index) {
          final date = _groupedItems.keys.elementAt(index);
          final items = _groupedItems[date]!;
          return _buildDateSection(date, items, themeService);
        },
      ),
    );
  }

  Widget _buildDateSection(
    String date,
    List<ReleaseCalendarItem> items,
    ThemeService themeService,
  ) {
    final dateInfo = _getDateInfo(date);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 日期标题
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: dateInfo.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: dateInfo.color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                dateInfo.icon,
                size: 16,
                color: dateInfo.color,
              ),
              const SizedBox(width: 8),
              Text(
                _formatDate(date),
                style: FontUtils.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: dateInfo.color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                dateInfo.label,
                style: FontUtils.poppins(
                  fontSize: 12,
                  color: dateInfo.color.withOpacity(0.8),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: dateInfo.color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${items.length}部',
                  style: FontUtils.poppins(
                    fontSize: 11,
                    color: dateInfo.color,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 项目列表
        ...items.map((item) => _buildItemCard(item, themeService)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildItemCard(ReleaseCalendarItem item, ThemeService themeService) {
    // 只有已上映的才能点击播放
    final canPlay = item.isReleased || item.isReleasingToday;

    return GestureDetector(
      onTap: canPlay ? () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlayerScreen(
              title: item.title,
              year: item.releaseDate.split('-').first,
            ),
          ),
        );
      } : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 80,
                    height: 110,
                    color: themeService.isDarkMode ? Colors.grey[800] : Colors.grey[200],
                    child: _buildCoverImage(item, themeService),
                  ),
                ),
                // 未上映遮罩
                if (!canPlay)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Icon(
                          LucideIcons.clock,
                          size: 24,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题和类型
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FontUtils.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: canPlay
                                ? (themeService.isDarkMode ? Colors.white : Colors.black87)
                                : (themeService.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: item.type == 'movie'
                              ? const Color(0xFFEF4444).withOpacity(0.1)
                              : const Color(0xFF3B82F6).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.type == 'movie' ? '电影' : '剧集',
                          style: FontUtils.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: item.type == 'movie'
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF3B82F6),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 导演
                  if (item.director.isNotEmpty)
                    Text(
                      '导演: ${item.director}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FontUtils.poppins(
                        fontSize: 12,
                        color: themeService.isDarkMode
                            ? Colors.grey[400]
                            : Colors.grey[600],
                      ),
                    ),
                  // 主演
                  if (item.actors.isNotEmpty)
                    Text(
                      '主演: ${item.actors}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FontUtils.poppins(
                        fontSize: 12,
                        color: themeService.isDarkMode
                            ? Colors.grey[400]
                            : Colors.grey[600],
                      ),
                    ),
                  const SizedBox(height: 4),
                  // 标签
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (item.region.isNotEmpty)
                        _buildTag(item.region, LucideIcons.mapPin, themeService),
                      if (item.genre.isNotEmpty)
                        _buildTag(item.genre, LucideIcons.tag, themeService),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 上映状态
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(item).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.remarksText,
                      style: FontUtils.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _getStatusColor(item),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建封面图片
  Widget _buildCoverImage(ReleaseCalendarItem item, ThemeService themeService) {
    if (item.cover == null || item.cover!.isEmpty) {
      return Center(
        child: Icon(
          LucideIcons.film,
          size: 24,
          color: themeService.isDarkMode
              ? Colors.grey[600]
              : Colors.grey[400],
        ),
      );
    }

    return Image.network(
      item.cover!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      headers: const {
        'Referer': 'https://g.manmankan.com/',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
      errorBuilder: (context, error, stackTrace) {
        return Center(
          child: Icon(
            LucideIcons.film,
            size: 24,
            color: themeService.isDarkMode
                ? Colors.grey[600]
                : Colors.grey[400],
          ),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF97316)),
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTag(String text, IconData icon, ThemeService themeService) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: themeService.isDarkMode
            ? Colors.white.withOpacity(0.1)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 10,
            color: themeService.isDarkMode ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: FontUtils.poppins(
              fontSize: 10,
              color: themeService.isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final weekdays = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
      return '${date.year}年${date.month}月${date.day}日 ${weekdays[date.weekday % 7]}';
    } catch (e) {
      return dateStr;
    }
  }

  _DateInfo _getDateInfo(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final releaseDay = DateTime(date.year, date.month, date.day);
      final diff = releaseDay.difference(today).inDays;

      if (diff < 0) {
        return _DateInfo(
          label: '已上映',
          color: const Color(0xFF22C55E),
          icon: LucideIcons.check,
        );
      } else if (diff == 0) {
        return _DateInfo(
          label: '今日上映',
          color: const Color(0xFFF97316),
          icon: LucideIcons.star,
        );
      } else if (diff <= 7) {
        return _DateInfo(
          label: '即将上映',
          color: const Color(0xFF3B82F6),
          icon: LucideIcons.clock,
        );
      } else {
        return _DateInfo(
          label: '敬请期待',
          color: const Color(0xFF6366F1),
          icon: LucideIcons.calendar,
        );
      }
    } catch (e) {
      return _DateInfo(
        label: '',
        color: Colors.grey,
        icon: LucideIcons.calendar,
      );
    }
  }

  Color _getStatusColor(ReleaseCalendarItem item) {
    if (item.isReleased) {
      return const Color(0xFF22C55E);
    } else if (item.isReleasingToday) {
      return const Color(0xFFF97316);
    } else {
      return const Color(0xFF6366F1);
    }
  }
}

class _DateInfo {
  final String label;
  final Color color;
  final IconData icon;

  _DateInfo({
    required this.label,
    required this.color,
    required this.icon,
  });
}
