import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/source_browser_service.dart';
import '../services/theme_service.dart';
import '../utils/font_utils.dart';
import '../widgets/custom_refresh_indicator.dart';
import '../widgets/pulsing_dots_indicator.dart';
import '../widgets/capsule_tab_switcher.dart';
import 'player_screen.dart';

class SourceBrowserScreen extends StatefulWidget {
  const SourceBrowserScreen({super.key});

  @override
  State<SourceBrowserScreen> createState() => _SourceBrowserScreenState();
}

class _SourceBrowserScreenState extends State<SourceBrowserScreen> {
  // 源站列表
  List<SourceSite> _sites = [];
  bool _isLoadingSites = true;
  String? _sitesError;

  // 当前选中的源站
  SourceSite? _selectedSite;

  // 分类列表
  List<SourceCategory> _categories = [];
  bool _isLoadingCategories = false;

  // 当前选中的分类
  SourceCategory? _selectedCategory;

  // 视频列表
  List<SourceVideoItem> _videos = [];
  bool _isLoadingVideos = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _videosError;

  // 搜索
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchMode = false;
  String _searchQuery = '';

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadSites();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadSites() async {
    setState(() {
      _isLoadingSites = true;
      _sitesError = null;
    });

    final sites = await SourceBrowserService.getSites();

    if (mounted) {
      setState(() {
        _sites = sites;
        _isLoadingSites = false;
        if (sites.isEmpty) {
          _sitesError = '没有可用的源站';
        } else {
          // 默认选中第一个源站
          _selectedSite = sites.first;
          _loadCategories();
        }
      });
    }
  }

  Future<void> _loadCategories() async {
    if (_selectedSite == null) return;

    setState(() {
      _isLoadingCategories = true;
      _categories = [];
      _selectedCategory = null;
      _videos = [];
    });

    final categories = await SourceBrowserService.getCategories(_selectedSite!.key);

    if (mounted) {
      setState(() {
        _categories = categories;
        _isLoadingCategories = false;
        if (categories.isNotEmpty) {
          _selectedCategory = categories.first;
          _loadVideos(refresh: true);
        }
      });
    }
  }

  Future<void> _loadVideos({bool refresh = false}) async {
    if (_selectedSite == null || _selectedCategory == null) return;
    if (_isLoadingVideos) return;

    if (refresh) {
      setState(() {
        _videos = [];
        _currentPage = 1;
        _hasMore = true;
        _videosError = null;
      });
    }

    setState(() {
      _isLoadingVideos = true;
    });

    SourceListResponse? response;
    if (_isSearchMode && _searchQuery.isNotEmpty) {
      response = await SourceBrowserService.search(
        sourceKey: _selectedSite!.key,
        query: _searchQuery,
        page: _currentPage,
      );
    } else {
      response = await SourceBrowserService.getList(
        sourceKey: _selectedSite!.key,
        typeId: _selectedCategory!.typeId,
        page: _currentPage,
      );
    }

    if (mounted) {
      setState(() {
        _isLoadingVideos = false;
        if (response != null) {
          _videos.addAll(response.items);
          _hasMore = _currentPage < response.meta.pageCount;
        } else {
          _videosError = '加载失败';
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoadingVideos) return;

    setState(() {
      _isLoadingMore = true;
      _currentPage++;
    });

    SourceListResponse? response;
    if (_isSearchMode && _searchQuery.isNotEmpty) {
      response = await SourceBrowserService.search(
        sourceKey: _selectedSite!.key,
        query: _searchQuery,
        page: _currentPage,
      );
    } else if (_selectedCategory != null) {
      response = await SourceBrowserService.getList(
        sourceKey: _selectedSite!.key,
        typeId: _selectedCategory!.typeId,
        page: _currentPage,
      );
    }

    if (mounted) {
      setState(() {
        _isLoadingMore = false;
        if (response != null) {
          _videos.addAll(response.items);
          _hasMore = _currentPage < response.meta.pageCount;
        }
      });
    }
  }

  void _onSiteChanged(SourceSite site) {
    if (_selectedSite?.key == site.key) return;
    setState(() {
      _selectedSite = site;
      _isSearchMode = false;
      _searchQuery = '';
      _searchController.clear();
    });
    _loadCategories();
  }

  void _onCategoryChanged(SourceCategory category) {
    if (_selectedCategory?.typeId == category.typeId) return;
    setState(() {
      _selectedCategory = category;
      _isSearchMode = false;
      _searchQuery = '';
      _searchController.clear();
    });
    _loadVideos(refresh: true);
  }

  void _onSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearchMode = false;
        _searchQuery = '';
      });
      _loadVideos(refresh: true);
      return;
    }

    setState(() {
      _isSearchMode = true;
      _searchQuery = query.trim();
      _videos = [];
      _currentPage = 1;
      _hasMore = true;
    });
    _loadVideos(refresh: true);
  }

  void _onVideoTap(SourceVideoItem video) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          source: _selectedSite?.key,
          id: video.id,
          title: video.title,
          year: video.year,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);

    if (_isLoadingSites) {
      return const Center(child: PulsingDotsIndicator());
    }

    if (_sitesError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(_sitesError!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSites,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return StyledRefreshIndicator(
      onRefresh: () async {
        if (_isSearchMode) {
          _onSearch(_searchQuery);
        } else {
          await _loadVideos(refresh: true);
        }
      },
      refreshText: '刷新中...',
      primaryColor: const Color(0xFF27AE60),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // 头部
          SliverToBoxAdapter(child: _buildHeader()),
          // 源站选择器
          SliverToBoxAdapter(child: _buildSiteSelector(themeService)),
          // 搜索框
          SliverToBoxAdapter(child: _buildSearchBar(themeService)),
          // 分类选择器
          if (!_isSearchMode && _categories.isNotEmpty)
            SliverToBoxAdapter(child: _buildCategorySelector(themeService)),
          // 视频网格
          if (_isLoadingVideos && _videos.isEmpty)
            const SliverFillRemaining(
              child: Center(child: PulsingDotsIndicator()),
            )
          else if (_videosError != null && _videos.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(_videosError!, style: TextStyle(color: Colors.grey[600])),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: _buildVideoGrid(themeService),
            ),
          // 加载更多指示器
          if (_isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: PulsingDotsIndicator(),
              ),
            ),
          // 底部间距
          const SliverToBoxAdapter(child: SizedBox(height: 50)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '源浏览器',
            style: FontUtils.poppins(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '浏览和搜索视频源内容',
            style: FontUtils.poppins(
              fontSize: 14,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSiteSelector(ThemeService themeService) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '选择源站',
            style: FontUtils.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: CapsuleTabSwitcher(
              tabs: _sites.map((s) => s.name).toList(),
              selectedTab: _selectedSite?.name ?? '',
              onTabChanged: (name) {
                final site = _sites.firstWhere((s) => s.name == name);
                _onSiteChanged(site);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ThemeService themeService) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '在 ${_selectedSite?.name ?? '当前源'} 中搜索...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    _onSearch('');
                  },
                )
              : null,
          filled: true,
          fillColor: themeService.isDarkMode
              ? Colors.white.withOpacity(0.1)
              : Colors.grey.withOpacity(0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onSubmitted: _onSearch,
        onChanged: (value) {
          setState(() {}); // 更新清除按钮状态
        },
      ),
    );
  }

  Widget _buildCategorySelector(ThemeService themeService) {
    if (_isLoadingCategories) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: PulsingDotsIndicator()),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '分类',
            style: FontUtils.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: CapsuleTabSwitcher(
              tabs: _categories.map((c) => c.typeName).toList(),
              selectedTab: _selectedCategory?.typeName ?? '',
              onTabChanged: (name) {
                final category = _categories.firstWhere((c) => c.typeName == name);
                _onCategoryChanged(category);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoGrid(ThemeService themeService) {
    if (_videos.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.movie_outlined, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  _isSearchMode ? '没有找到相关内容' : '暂无内容',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 根据屏幕宽度计算列数
    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 1200
        ? 6
        : screenWidth > 900
            ? 5
            : screenWidth > 600
                ? 4
                : 3;

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.65,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildVideoCard(_videos[index], themeService),
        childCount: _videos.length,
      ),
    );
  }

  Widget _buildVideoCard(SourceVideoItem video, ThemeService themeService) {
    return GestureDetector(
      onTap: () => _onVideoTap(video),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 封面图片
                  video.poster.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: video.poster,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[800],
                            child: const Center(
                              child: Icon(Icons.movie, color: Colors.white54),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[800],
                            child: const Center(
                              child: Icon(Icons.broken_image, color: Colors.white54),
                            ),
                          ),
                        )
                      : Container(
                          color: Colors.grey[800],
                          child: const Center(
                            child: Icon(Icons.movie, color: Colors.white54, size: 32),
                          ),
                        ),
                  // 备注标签（如：更新至xx集）
                  if (video.remarks.isNotEmpty)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          video.remarks,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 标题
          Text(
            video.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FontUtils.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: themeService.isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          // 年份和类型
          if (video.year.isNotEmpty || video.typeName.isNotEmpty)
            Text(
              [video.year, video.typeName].where((s) => s.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FontUtils.poppins(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
        ],
      ),
    );
  }
}
