import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../services/tmdb_actor_service.dart';
import '../services/theme_service.dart';
import '../services/user_data_service.dart';
import '../utils/font_utils.dart';
import '../screens/player_screen.dart';

/// TMDB 演员搜索结果组件
class TMDBActorResultsWidget extends StatefulWidget {
  final String query;
  final Function(TMDBActorWork)? onWorkTap;

  const TMDBActorResultsWidget({
    super.key,
    required this.query,
    this.onWorkTap,
  });

  @override
  State<TMDBActorResultsWidget> createState() => _TMDBActorResultsWidgetState();
}

class _TMDBActorResultsWidgetState extends State<TMDBActorResultsWidget> {
  TMDBActorSearchResult? _result;
  bool _isLoading = false;
  String? _error;
  String? _serverUrl;

  TMDBContentType _contentType = TMDBContentType.movie;
  TMDBSortBy _sortBy = TMDBSortBy.popularity;
  TMDBSortOrder _sortOrder = TMDBSortOrder.desc;
  bool _onlyRated = false;

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
    _search();
  }
  
  Future<void> _loadServerUrl() async {
    final url = await UserDataService.getServerUrl();
    if (mounted) {
      setState(() {
        _serverUrl = url;
      });
    }
  }
  
  /// 获取代理后的图片URL
  String _getProxiedImageUrl(String originalUrl) {
    if (originalUrl.isEmpty || _serverUrl == null) return originalUrl;
    // 通过后端代理加载图片
    return '$_serverUrl/api/image-proxy?url=${Uri.encodeComponent(originalUrl)}';
  }

  @override
  void didUpdateWidget(TMDBActorResultsWidget oldWidget) {
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

    final result = await TMDBActorService.searchActorWorks(
      actorName: widget.query,
      type: _contentType,
      filterOptions: TMDBFilterOptions(
        sortBy: _sortBy,
        sortOrder: _sortOrder,
        onlyRated: _onlyRated ? true : null,
      ),
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
        Row(
          children: [
            ...TMDBContentType.values.map((type) {
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
                          ? const Color(0xFF8B5CF6) // 紫色主题
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
            }),
            const Spacer(),
            // 只显示有评分的开关
            GestureDetector(
              onTap: () {
                setState(() {
                  _onlyRated = !_onlyRated;
                });
                _search();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _onlyRated
                      ? const Color(0xFF8B5CF6).withOpacity(0.2)
                      : themeService.isDarkMode
                          ? Colors.grey[800]
                          : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _onlyRated
                        ? const Color(0xFF8B5CF6)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _onlyRated ? LucideIcons.check : LucideIcons.circle,
                      size: 14,
                      color: _onlyRated
                          ? const Color(0xFF8B5CF6)
                          : themeService.isDarkMode
                              ? Colors.grey[400]
                              : Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '有评分',
                      style: FontUtils.poppins(
                        fontSize: 12,
                        color: _onlyRated
                            ? const Color(0xFF8B5CF6)
                            : themeService.isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
                  children: [
                    ...[TMDBSortBy.popularity, TMDBSortBy.rating, TMDBSortBy.date, TMDBSortBy.voteCount].map((sortBy) {
                      final isSelected = _sortBy == sortBy;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              if (_sortBy == sortBy) {
                                // 切换排序顺序
                                _sortOrder = _sortOrder == TMDBSortOrder.desc
                                    ? TMDBSortOrder.asc
                                    : TMDBSortOrder.desc;
                              } else {
                                _sortBy = sortBy;
                                _sortOrder = TMDBSortOrder.desc;
                              }
                            });
                            _search();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF8B5CF6)
                                  : themeService.isDarkMode
                                      ? Colors.grey[800]
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF8B5CF6)
                                    : themeService.isDarkMode
                                        ? Colors.grey[700]!
                                        : Colors.grey[300]!,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  sortBy.label,
                                  style: FontUtils.poppins(
                                    fontSize: 11,
                                    color: isSelected
                                        ? Colors.white
                                        : themeService.isDarkMode
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 2),
                                  Icon(
                                    _sortOrder == TMDBSortOrder.desc
                                        ? Icons.arrow_downward
                                        : Icons.arrow_upward,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContent(ThemeService themeService) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
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
                backgroundColor: const Color(0xFF8B5CF6),
              ),
              child: const Text('重试', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_result == null || _result!.list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.user,
              size: 48,
              color: themeService.isDarkMode ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '未找到该演员的相关作品',
              style: FontUtils.poppins(
                fontSize: 14,
                color: themeService.isDarkMode ? Colors.white54 : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    // 调试信息
    final firstWork = _result!.list.isNotEmpty ? _result!.list[0] : null;
    final proxiedPoster = firstWork != null ? _getProxiedImageUrl(firstWork.poster) : '';
    
    return Column(
      children: [
        // 调试信息区域
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.purple.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🔍 调试信息 (共 ${_result!.list.length} 个结果)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              if (firstWork != null) ...[
                Text('id: ${firstWork.id}', style: const TextStyle(fontSize: 11)),
                Text('title: ${firstWork.title}', style: const TextStyle(fontSize: 11)),
                Text('原始poster: ${firstWork.poster}', style: const TextStyle(fontSize: 11)),
                Text('代理poster: $proxiedPoster', style: const TextStyle(fontSize: 11)),
              ],
            ],
          ),
        ),
        // GridView
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.55,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
            ),
            itemCount: _result!.list.length,
            itemBuilder: (context, index) {
              final work = _result!.list[index];
              return _TMDBWorkCard(
                work: work,
                posterUrl: _getProxiedImageUrl(work.poster),
                contentType: _contentType,
                themeService: themeService,
                onTap: () {
                  if (widget.onWorkTap != null) {
                    widget.onWorkTap!(work);
                  } else {
                    _navigateToPlayer(work);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _navigateToPlayer(TMDBActorWork work) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          title: work.title,
          year: work.year,
          stype: _contentType == TMDBContentType.movie ? 'movie' : 'tv',
        ),
      ),
    );
  }
}

/// TMDB 作品卡片
class _TMDBWorkCard extends StatelessWidget {
  final TMDBActorWork work;
  final String posterUrl;
  final TMDBContentType contentType;
  final ThemeService themeService;
  final VoidCallback? onTap;

  const _TMDBWorkCard({
    required this.work,
    required this.posterUrl,
    required this.contentType,
    required this.themeService,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: themeService.isDarkMode
                        ? Colors.grey[800]
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: posterUrl.isNotEmpty
                        ? Image.network(
                            posterUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: themeService.isDarkMode ? Colors.grey[800] : Colors.grey[200],
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: themeService.isDarkMode ? Colors.grey[800] : Colors.grey[200],
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        size: 20,
                                        color: Colors.red[300],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '加载失败',
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: themeService.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          )
                        : _buildPlaceholder(),
                  ),
                ),
                // 评分标签
                if (work.hasRating)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getRatingColor(double.tryParse(work.rate) ?? 0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        work.ratingDisplay,
                        style: FontUtils.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                // 角色名（如果有）
                if (work.character != null && work.character!.isNotEmpty)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.8),
                            Colors.transparent,
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(8),
                        ),
                      ),
                      child: Text(
                        '饰 ${work.character}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FontUtils.poppins(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // 标题
          Text(
            work.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: FontUtils.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: themeService.isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          // 年份
          if (work.year.isNotEmpty)
            Text(
              work.year,
              style: FontUtils.poppins(
                fontSize: 11,
                color: themeService.isDarkMode ? Colors.grey[500] : Colors.grey[600],
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
          LucideIcons.film,
          size: 32,
          color: themeService.isDarkMode ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );
  }

  Color _getRatingColor(double rating) {
    if (rating >= 8.0) return const Color(0xFF22C55E); // 绿色
    if (rating >= 6.0) return const Color(0xFFF97316); // 橙色
    if (rating >= 4.0) return const Color(0xFFEAB308); // 黄色
    return const Color(0xFFEF4444); // 红色
  }
}
