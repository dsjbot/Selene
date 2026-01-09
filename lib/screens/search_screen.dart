import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/page_cache_service.dart';
import '../services/theme_service.dart';
import '../services/sse_search_service.dart';
import '../services/netdisk_service.dart';
import '../models/search_result.dart';
import '../models/video_info.dart';
import '../widgets/video_menu_bottom_sheet.dart';
import '../widgets/custom_switch.dart';
import '../widgets/favorites_grid.dart';
import '../widgets/search_result_agg_grid.dart';
import '../widgets/search_results_grid.dart';
import '../widgets/filter_options_selector.dart';
import '../widgets/filter_pill_hover.dart';
import '../widgets/main_layout.dart';
import '../utils/font_utils.dart';
import '../utils/device_utils.dart';
import 'player_screen.dart';

enum SortOrder { none, asc, desc }
enum SearchType { video, netdisk }

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  List<String> _searchHistory = [];
  List<SearchResult> _searchResults = [];
  bool _hasSearched = false;
  bool _hasReceivedStart = false; // 是否已收到start消息
  String? _searchError;
  SearchProgress? _searchProgress;
  Timer? _updateTimer; // 用于防抖的定时器
  bool _useAggregatedView = true; // 是否使用聚合视图，默认开启

  // 筛选和排序状态
  String _selectedSource = 'all';
  String _selectedYear = 'all';
  String _selectedTitle = 'all';
  SortOrder _yearSortOrder = SortOrder.none;

  // 长按删除相关状态
  String? _deletingHistoryItem;
  AnimationController? _deleteAnimationController;
  Animation<double>? _deleteAnimation;

  // hover 状态
  String? _hoveredHistoryItem;
  String? _hoveredDeleteButton;
  String? _hoveredFilterPill;
  bool _isYearSortHovered = false;
  bool _isClearHistoryButtonHovered = false;

  // 搜索类型
  SearchType _searchType = SearchType.video;
  
  // 网盘搜索相关状态
  NetDiskSearchResult? _netdiskResult;
  bool _isNetdiskLoading = false;
  String? _netdiskError;
  String? _selectedCloudType;
  final Map<String, bool> _visiblePasswords = {};

  late SSESearchService _searchService;
  StreamSubscription<List<SearchResult>>? _incrementalResultsSubscription;
  StreamSubscription<SearchProgress>? _progressSubscription;
  StreamSubscription<String>? _errorSubscription;

  List<SearchResult> get _filteredSearchResults {
    List<SearchResult> results = List.from(_searchResults);

    // Source filter
    if (_selectedSource != 'all') {
      results = results.where((r) => r.sourceName == _selectedSource).toList();
    }

    // Year filter
    if (_selectedYear != 'all') {
      results = results.where((r) => r.year == _selectedYear).toList();
    }

    // Title filter
    if (_selectedTitle != 'all') {
      results = results.where((r) => r.title == _selectedTitle).toList();
    }

    // Year sort
    if (_yearSortOrder != SortOrder.none) {
      results.sort((a, b) {
        final yearAIsNum = int.tryParse(a.year) != null;
        final yearBIsNum = int.tryParse(b.year) != null;

        if (yearAIsNum && !yearBIsNum) {
          return -1; // a (数字) 在 b (非数字) 前面
        }
        if (!yearAIsNum && yearBIsNum) {
          return 1; // b (数字) 在 a (非数字) 前面
        }
        if (!yearAIsNum && !yearBIsNum) {
          return 0; // 都是非数字，保持顺序
        }

        final yearA = int.parse(a.year);
        final yearB = int.parse(b.year);

        if (_yearSortOrder == SortOrder.desc) {
          return yearB.compareTo(yearA);
        } else {
          // SortOrder.asc
          return yearA.compareTo(yearB);
        }
      });
    }

    return results;
  }

  @override
  void initState() {
    super.initState();

    _searchService = SSESearchService();
    _setupSearchListeners();
    _loadSearchHistory();

    // 初始化删除动画控制器
    _deleteAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500), // 1.5秒变红动画
      vsync: this,
    );
    _deleteAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _deleteAnimationController!,
      curve: Curves.easeInOut,
    ));

    // 进入搜索页面时自动聚焦搜索框
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _incrementalResultsSubscription?.cancel();
    _progressSubscription?.cancel();
    _errorSubscription?.cancel();
    _updateTimer?.cancel();
    _searchService.dispose();
    _deleteAnimationController?.dispose();
    super.dispose();
  }

  /// 设置搜索监听器
  void _setupSearchListeners() {
    // 取消之前的监听器
    _incrementalResultsSubscription?.cancel();
    _progressSubscription?.cancel();
    _errorSubscription?.cancel();

    // 监听增量搜索结果
    _incrementalResultsSubscription =
        _searchService.incrementalResultsStream.listen((incrementalResults) {
      if (mounted && incrementalResults.isNotEmpty) {
        // 将增量结果添加到现有结果列表中
        _searchResults.addAll(incrementalResults);

        // 使用防抖机制，避免过于频繁的UI更新，同时确保用户交互不受影响
        _updateTimer?.cancel();
        _updateTimer = Timer(const Duration(milliseconds: 50), () {
          if (mounted) {
            // 使用 scheduleMicrotask 确保UI更新在下一个微任务中执行，不阻塞用户交互
            scheduleMicrotask(() {
              if (mounted) {
                setState(() {
                  // 触发UI更新
                });
              }
            });
          }
        });
      }
    });

    // 监听搜索进度
    _progressSubscription = _searchService.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _searchProgress = progress;
          _hasReceivedStart = true;
        });
      }
    });

    // 监听搜索错误
    _errorSubscription = _searchService.errorStream.listen((error) {
      if (mounted) {
        // 检查是否是连接关闭错误，如果是则忽略
        final errorString = error.toLowerCase();
        if (errorString.contains('connection closed') ||
            errorString.contains('clientexception') ||
            errorString.contains('connection terminated')) {
          // 连接被关闭，这是正常情况，不显示错误
          return;
        }

        setState(() {
          _searchError = error;
        });
      }
    });
  }

  Future<void> _loadSearchHistory() async {
    // 首先尝试从缓存加载数据
    try {
      final result = await PageCacheService().getSearchHistory(context);
      if (mounted) {
        setState(() {
          _searchHistory = result.success ? (result.data ?? []) : [];
        });
      }
    } catch (e) {
      // 缓存加载失败，设置为空
      if (mounted) {
        setState(() {
          _searchHistory = [];
        });
      }
    }
  }

  Future<void> _refreshSearchHistory() async {
    try {
      // 刷新缓存数据
      await PageCacheService().refreshSearchHistory(context);

      // 重新获取搜索历史数据
      final result = await PageCacheService().getSearchHistory(context);
      if (mounted) {
        setState(() {
          _searchHistory = result.success ? (result.data ?? []) : [];
        });
      }
    } catch (e) {
      // 错误处理，保持当前显示的内容
    }
  }

  /// 异步刷新收藏夹数据
  Future<void> _refreshFavorites() async {
    try {
      // 刷新收藏夹缓存数据
      await PageCacheService().refreshFavorites(context);
    } catch (e) {
      // 错误处理，静默处理
    }
  }

  /// 添加搜索历史（本地状态、缓存、服务器）
  void addSearchHistory(String query) {
    if (query.trim().isEmpty) return;

    final trimmedQuery = query.trim();

    // 立即添加到缓存
    PageCacheService().addSearchHistory(trimmedQuery, context);

    // 立即更新本地状态和UI
    if (mounted) {
      setState(() {
        // 检查是否已存在相同的搜索词（区分大小写）
        final existingIndex =
            _searchHistory.indexWhere((item) => item == trimmedQuery);

        if (existingIndex == -1) {
          // 不存在，添加到列表开头
          _searchHistory.insert(0, trimmedQuery);
        } else {
          // 已存在，移动到开头（保持原始大小写）
          final existingItem = _searchHistory[existingIndex];
          _searchHistory.removeAt(existingIndex);
          _searchHistory.insert(0, existingItem);
        }
      });
    }
  }

  /// 显示清空确认弹窗
  void _showClearConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Consumer<ThemeService>(
          builder: (context, themeService, child) {
            return AlertDialog(
              backgroundColor: themeService.isDarkMode
                  ? const Color(0xFF1e1e1e)
                  : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.all(24),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 图标
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFe74c3c).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFFe74c3c),
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 标题
                  Text(
                    '清空搜索历史',
                    style: FontUtils.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: themeService.isDarkMode
                          ? const Color(0xFFffffff)
                          : const Color(0xFF2c3e50),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 描述
                  Text(
                    '确定要清空所有搜索历史吗？此操作无法撤销。',
                    style: FontUtils.poppins(
                      fontSize: 14,
                      color: themeService.isDarkMode
                          ? const Color(0xFFb0b0b0)
                          : const Color(0xFF7f8c8d),
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  // 按钮
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            '取消',
                            style: FontUtils.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: themeService.isDarkMode
                                  ? const Color(0xFFb0b0b0)
                                  : const Color(0xFF7f8c8d),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _clearSearchHistory();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFe74c3c),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            '清空',
                            style: FontUtils.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 清空搜索历史
  Future<void> _clearSearchHistory() async {
    try {
      final result = await PageCacheService().clearSearchHistory(context);

      if (result.success) {
        // 立即清空本地状态
        if (mounted) {
          setState(() {
            _searchHistory.clear();
          });
        }
      } else {
        // 异常时异步刷新搜索历史以恢复数据
        _refreshSearchHistory();
      }
    } catch (e) {
      // 异常时异步刷新搜索历史以恢复数据
      _refreshSearchHistory();
    }
  }

  /// 开始删除动画
  void _startDeleteAnimation(String historyItem) {
    setState(() {
      _deletingHistoryItem = historyItem;
    });
    _deleteAnimationController?.forward().then((_) {
      // 动画完成后执行删除
      _deleteSearchHistory(historyItem);
    });
  }

  /// 取消删除动画
  void _cancelDeleteAnimation() {
    _deleteAnimationController?.reset();
    setState(() {
      _deletingHistoryItem = null;
    });
  }

  /// 删除单个搜索历史
  Future<void> _deleteSearchHistory(String historyItem) async {
    try {
      final result =
          await PageCacheService().deleteSearchHistory(historyItem, context);

      if (result.success) {
        // 立即从UI中移除
        if (mounted) {
          setState(() {
            _searchHistory.remove(historyItem);
            _deletingHistoryItem = null;
          });
        }
      } else {
        // API调用失败，异步刷新搜索历史以恢复数据
        _refreshSearchHistory();
      }
    } catch (e) {
      // 异常时异步刷新搜索历史以恢复数据
      _refreshSearchHistory();
    }
  }

  void _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _searchQuery = query.trim();
      _hasSearched = true;
      _hasReceivedStart = false; // 重置start状态
      _searchError = null;
      _searchResults.clear();
      _searchProgress = null; // 清空进度信息
      _useAggregatedView = true; // 默认开启聚合
      // 重置筛选和排序
      _selectedSource = 'all';
      _selectedYear = 'all';
      _selectedTitle = 'all';
      _yearSortOrder = SortOrder.none;
      // 重置网盘搜索状态
      _netdiskResult = null;
      _netdiskError = null;
      _selectedCloudType = null;
      _visiblePasswords.clear();
    });

    // 添加到搜索历史
    addSearchHistory(_searchQuery);

    // 搜索框失焦
    _searchFocusNode.unfocus();

    // 根据搜索类型执行不同的搜索
    if (_searchType == SearchType.netdisk) {
      await _performNetdiskSearch(_searchQuery);
    } else {
      await _performVideoSearch(_searchQuery);
    }
  }

  /// 执行视频搜索
  Future<void> _performVideoSearch(String query) async {
    try {
      // 开始 SSE 搜索
      await _searchService.startSearch(query);

      // 重新设置监听器，确保流控制器已初始化
      _setupSearchListeners();
    } catch (e) {
      if (mounted) {
        // 检查是否是连接关闭错误，如果是则忽略
        final errorString = e.toString().toLowerCase();
        if (errorString.contains('connection closed') ||
            errorString.contains('clientexception') ||
            errorString.contains('connection terminated')) {
          // 连接被关闭，这是正常情况，不显示错误
          return;
        }

        setState(() {
          _searchError = e.toString();
        });
      }
    }
  }

  /// 执行网盘搜索
  Future<void> _performNetdiskSearch(String query) async {
    setState(() {
      _isNetdiskLoading = true;
      _netdiskError = null;
      _netdiskResult = null;
      _selectedCloudType = null;
    });

    final result = await NetDiskService.search(query);

    if (mounted) {
      setState(() {
        _isNetdiskLoading = false;
        if (result.success) {
          _netdiskResult = result;
          _netdiskError = null;
        } else {
          _netdiskResult = null;
          _netdiskError = result.error;
        }
      });
    }
  }

  /// 复制链接到剪贴板
  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('链接已复制', style: FontUtils.poppins(color: Colors.white)),
        backgroundColor: const Color(0xFF27AE60),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 打开链接
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('无法打开链接', style: FontUtils.poppins(color: Colors.white)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        final ml = MainLayout(
          content: Container(
            color: themeService.isDarkMode
                ? const Color(0xFF121212)
                : const Color(0xFFf5f5f5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 搜索类型切换按钮（始终显示）
                _buildSearchTypeSelector(themeService),
                if (!_hasSearched) ...[
                  // 搜索错误提示
                  if (_searchError != null)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildSearchError(themeService),
                    ),
                  // 搜索历史（只有在从未搜索过时显示）
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildSearchHistory(themeService),
                    ),
                  ),
                ],
                if (_hasSearched) ...[
                  // 搜索结果区域，不添加额外padding
                  Expanded(
                    child: _searchType == SearchType.netdisk
                        ? _buildNetdiskResults(themeService)
                        : _buildSearchResults(themeService),
                  ),
                ],
              ],
            ),
          ),
          currentBottomNavIndex: -1, // 不选中任何底部导航项
          onBottomNavChanged: (index) {
            // 点击底部导航时关闭搜索页面
            Navigator.pop(context);
          },
          selectedTopTab: '',
          onTopTabChanged: (tab) {},
          showBottomNav: false, // 不显示底部导航栏
          isSearchMode: true,
          searchController: _searchController,
          searchFocusNode: _searchFocusNode,
          searchQuery: _searchQuery,
          onSearchQueryChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
          onSearchSubmitted: (value) {
            _performSearch(value);
          },
          onClearSearch: () {
            setState(() {
              _searchQuery = '';
              _searchController.clear();
              _hasSearched = false;
              _hasReceivedStart = false;
              _searchResults.clear();
              _searchError = null;
              _searchProgress = null;
              _searchService.stopSearch();
              // 重置网盘搜索状态
              _netdiskResult = null;
              _netdiskError = null;
              _isNetdiskLoading = false;
              _selectedCloudType = null;
              _visiblePasswords.clear();
            });
          },
          onHomeTap: () {
            Navigator.pop(context);
          },
        );
        if (Platform.isIOS) {
          return PopScope(
            canPop: true, // 允许返回
            child: ml,
          );
        } else {
          return ml;
        }
      },
    );
  }

  Widget _buildSearchHistory(ThemeService themeService) {
    // 如果没有搜索历史，显示空状态
    if (_searchHistory.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 120.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.history,
                size: 80,
                color: themeService.isDarkMode
                    ? const Color(0xFF444444)
                    : const Color(0xFFbdc3c7),
              ),
              const SizedBox(height: 24),
              Text(
                '暂无搜索历史',
                style: FontUtils.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: themeService.isDarkMode
                      ? const Color(0xFF666666)
                      : const Color(0xFF7f8c8d),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '开始搜索你喜欢的内容吧',
                style: FontUtils.poppins(
                  fontSize: 14,
                  color: themeService.isDarkMode
                      ? const Color(0xFF555555)
                      : const Color(0xFF95a5a6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 22.0, right: 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline, // 基线对齐
            textBaseline: TextBaseline.alphabetic, // 使用字母基线
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '搜索历史',
                style: FontUtils.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: themeService.isDarkMode
                      ? const Color(0xFFffffff)
                      : const Color(0xFF2c3e50),
                ),
              ),
              MouseRegion(
                cursor: DeviceUtils.isPC()
                    ? SystemMouseCursors.click
                    : MouseCursor.defer,
                onEnter: DeviceUtils.isPC()
                    ? (_) {
                        setState(() {
                          _isClearHistoryButtonHovered = true;
                        });
                      }
                    : null,
                onExit: DeviceUtils.isPC()
                    ? (_) {
                        setState(() {
                          _isClearHistoryButtonHovered = false;
                        });
                      }
                    : null,
                child: TextButton(
                  onPressed: _showClearConfirmation,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    overlayColor: Colors.transparent,
                  ),
                  child: Text(
                    '清空',
                    style: FontUtils.poppins(
                      fontSize: 14,
                      color: DeviceUtils.isPC() && _isClearHistoryButtonHovered
                          ? const Color(0xFFe74c3c) // hover 时红色
                          : themeService.isDarkMode
                              ? const Color(0xFFb0b0b0)
                              : const Color(0xFF7f8c8d),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _searchHistory.map((history) {
              final isDeleting = _deletingHistoryItem == history;
              final isHovered = _hoveredHistoryItem == history;

              return MouseRegion(
                cursor: DeviceUtils.isPC()
                    ? SystemMouseCursors.click
                    : MouseCursor.defer,
                onEnter: DeviceUtils.isPC()
                    ? (_) {
                        setState(() {
                          _hoveredHistoryItem = history;
                        });
                      }
                    : null,
                onExit: DeviceUtils.isPC()
                    ? (_) {
                        // 只有当前 hover 的是这个历史项时才清除
                        if (_hoveredHistoryItem == history) {
                          setState(() {
                            _hoveredHistoryItem = null;
                          });
                        }
                      }
                    : null,
                child: GestureDetector(
                  onTap: () {
                    if (!isDeleting) {
                      _searchController.text = history;
                      setState(() {
                        _searchQuery = history;
                      });
                      _performSearch(history);
                    }
                  },
                  onLongPressStart: (_) {
                    if (!isDeleting) {
                      _startDeleteAnimation(history);
                    }
                  },
                  onLongPressEnd: (_) {
                    if (isDeleting) {
                      _cancelDeleteAnimation();
                    }
                  },
                  child: AnimatedBuilder(
                    animation:
                        _deleteAnimation ?? const AlwaysStoppedAnimation(0.0),
                    builder: (context, child) {
                      // 计算颜色插值
                      Color backgroundColor;
                      Color textColor;
                      Color borderColor;

                      if (isDeleting) {
                        final animationValue = _deleteAnimation?.value ?? 0.0;

                        // 背景色从正常色渐变到红色
                        backgroundColor = Color.lerp(
                          themeService.isDarkMode
                              ? const Color(0xFF1e1e1e)
                              : Colors.white,
                          const Color(0xFFe74c3c).withOpacity(0.2),
                          animationValue,
                        )!;

                        // 文字色从正常色渐变到红色
                        textColor = Color.lerp(
                          themeService.isDarkMode
                              ? const Color(0xFFffffff)
                              : const Color(0xFF2c3e50),
                          const Color(0xFFe74c3c),
                          animationValue,
                        )!;

                        // 边框色从正常色渐变到红色
                        borderColor = Color.lerp(
                          themeService.isDarkMode
                              ? const Color(0xFF333333)
                              : const Color(0xFFe9ecef),
                          const Color(0xFFe74c3c),
                          animationValue,
                        )!;
                      } else if (DeviceUtils.isPC() && isHovered) {
                        // PC 端 hover 效果 - 浅绿色
                        backgroundColor = themeService.isDarkMode
                            ? const Color(0xFF1e3a28) // 深色模式下的深绿背景
                            : const Color(0xFFe8f5e9); // 浅色模式下的浅绿背景
                        textColor = const Color(0xFF27ae60); // 绿色文字
                        borderColor = const Color(0xFF52c77a); // 浅绿边框
                      } else {
                        backgroundColor = themeService.isDarkMode
                            ? const Color(0xFF1e1e1e)
                            : Colors.white;
                        textColor = themeService.isDarkMode
                            ? const Color(0xFFffffff)
                            : const Color(0xFF2c3e50);
                        borderColor = themeService.isDarkMode
                            ? const Color(0xFF333333)
                            : const Color(0xFFe9ecef);
                      }

                      return Stack(
                        clipBehavior: Clip.none, // 允许子组件超出边界
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: backgroundColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: borderColor,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  history,
                                  style: FontUtils.poppins(
                                    fontSize: 14,
                                    color: textColor,
                                  ),
                                ),
                                if (isDeleting) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: textColor,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // PC 端 hover 时显示的删除按钮
                          if (DeviceUtils.isPC() && isHovered && !isDeleting)
                            Positioned(
                              top: -6,
                              right: -6,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                onEnter: (_) {
                                  setState(() {
                                    _hoveredDeleteButton = history;
                                  });
                                },
                                onExit: (_) {
                                  setState(() {
                                    _hoveredDeleteButton = null;
                                  });
                                },
                                child: GestureDetector(
                                  onTap: () {
                                    _deleteSearchHistory(history);
                                  },
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: _hoveredDeleteButton == history
                                          ? const Color(0xFFe74c3c) // hover 时红色
                                          : const Color(0xFF95a5a6), // 默认灰色
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 2,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// 构建搜索错误显示
  Widget _buildSearchError(ThemeService themeService) {
    final error = _searchError;
    if (error == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFe74c3c).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFe74c3c).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: Color(0xFFe74c3c),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: FontUtils.poppins(
                fontSize: 14,
                color: const Color(0xFFe74c3c),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _searchError = null;
              });
            },
            child: Text(
              '重试',
              style: FontUtils.poppins(
                fontSize: 12,
                color: const Color(0xFFe74c3c),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ThemeService themeService) {
    // 如果已搜索过，总是显示搜索结果区域
    if (_hasSearched) {
      return _buildSearchResultsList(themeService);
    }

    // 默认返回空容器
    return const SizedBox.shrink();
  }

  Widget _buildSearchResultsList(ThemeService themeService) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        // 标题行 - 有padding
        Padding(
          padding: const EdgeInsets.only(left: 22.0, right: 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline, // 基线对齐
            textBaseline: TextBaseline.alphabetic, // 使用字母基线
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '搜索结果',
                    style: FontUtils.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: themeService.isDarkMode
                          ? const Color(0xFFffffff)
                          : const Color(0xFF2c3e50),
                    ),
                  ),
                  if (_hasSearched) ...[
                    const SizedBox(width: 8),
                    if (_hasReceivedStart)
                      Text(
                        _getProgressText(),
                        style: FontUtils.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: themeService.isDarkMode
                              ? const Color(0xFFb0b0b0)
                              : const Color(0xFF7f8c8d),
                        ),
                      )
                  ],
                ],
              ),
              // 聚合开关
              if (_hasSearched && _searchResults.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '聚合',
                      style: FontUtils.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: themeService.isDarkMode
                            ? const Color(0xFFffffff)
                            : const Color(0xFF2c3e50),
                      ),
                    ),
                    const SizedBox(width: 6),
                    MouseRegion(
                      cursor: DeviceUtils.isPC()
                          ? SystemMouseCursors.click
                          : MouseCursor.defer,
                      child: Transform.translate(
                        offset: const Offset(0, 1.0),
                        child: CustomSwitch(
                          value: _useAggregatedView,
                          onChanged: (value) {
                            setState(() {
                              _useAggregatedView = value;
                            });
                          },
                          activeColor: const Color(0xFF27ae60),
                          inactiveColor: themeService.isDarkMode
                              ? const Color(0xFF444444)
                              : const Color(0xFFcccccc),
                          width: 32,
                          height: 16,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        // 根据搜索状态显示不同内容
        if (_hasSearched && _searchResults.isEmpty)
          Expanded(
            child: Center(
              child: _buildEmptyStateContent(),
            ),
          )
        else
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // 靠左对齐
              children: [
                // 筛选器行
                if (_hasSearched && _searchResults.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 22.0, right: 16.0),
                    child: _buildFilterSection(themeService),
                  ),
                ],
                const SizedBox(height: 8),
                // Grid区域 - 无padding，占满宽度
                Expanded(
                  child: _useAggregatedView
                      ? SearchResultAggGrid(
                          key: const ValueKey('agg_grid'),
                          results: _filteredSearchResults,
                          themeService: themeService,
                          onVideoTap: _onVideoTap,
                          onGlobalMenuAction: _onGlobalMenuAction,
                          onSourceSelected: (SearchResult result) {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => PlayerScreen(
                                          source: result.source,
                                          id: result.id,
                                          year: result.year,
                                          title: result.title,
                                          stitle: _searchQuery,
                                          stype: result.episodes.length > 1
                                              ? 'tv'
                                              : 'movie',
                                        )));
                          },
                          hasReceivedStart: _hasReceivedStart,
                        )
                      : SearchResultsGrid(
                          key: const ValueKey('list_grid'),
                          results: _filteredSearchResults,
                          themeService: themeService,
                          onVideoTap: _onVideoTap,
                          onGlobalMenuAction: _onGlobalMenuAction,
                          hasReceivedStart: _hasReceivedStart,
                        ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _onVideoTap(VideoInfo videoInfo) {
    _onGlobalMenuAction(videoInfo, VideoMenuAction.play);
  }

  String _getProgressText() {
    if (_searchProgress != null) {
      return '${_searchProgress!.completedSources}/${_searchProgress!.totalSources}';
    }
    return '0/0';
  }

  Widget _buildEmptyStateContent() {
    final bool isSearchFinished = _hasReceivedStart &&
        _searchProgress != null &&
        _searchProgress!.completedSources >= _searchProgress!.totalSources;

    if (isSearchFinished) {
      // 未找到结果
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            LucideIcons.folderSearch,
            size: 80,
            color: Color(0xFFbdc3c7),
          ),
          const SizedBox(height: 24),
          Text(
            '未找到结果',
            style: FontUtils.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF7f8c8d),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '请尝试更换关键词',
            style: FontUtils.poppins(
              fontSize: 14,
              color: const Color(0xFF95a5a6),
            ),
          ),
        ],
      );
    } else {
      // 搜索中...
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            LucideIcons.search,
            size: 80,
            color: Color(0xFFbdc3c7),
          ),
          const SizedBox(height: 24),
          Text(
            '搜索中...',
            style: FontUtils.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF7f8c8d),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '聚合搜索中，请稍候',
            style: FontUtils.poppins(
              fontSize: 14,
              color: const Color(0xFF95a5a6),
            ),
          ),
        ],
      );
    }
  }

  /// 处理视频菜单操作
  void _onGlobalMenuAction(VideoInfo videoInfo, VideoMenuAction action) {
    final stitle = _searchQuery;
    switch (action) {
      case VideoMenuAction.play:
        if (_useAggregatedView) {
          // 聚合卡片，只传递title和stitle，并从id中解析stype
          final parts = videoInfo.id.split('_');
          final type = parts.length > 2 ? parts.last : null;
          final year = parts.length > 1 ? parts[1] : null;

          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => PlayerScreen(
                        title: videoInfo.title,
                        stitle: stitle,
                        stype: type,
                        year: year,
                      )));
        } else {
          // 非聚合卡片，传递完整信息
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => PlayerScreen(
                        source: videoInfo.source,
                        id: videoInfo.id,
                        year: videoInfo.year,
                        title: videoInfo.title,
                        stype: videoInfo.totalEpisodes > 1 ? 'tv' : 'movie',
                        stitle: stitle,
                      )));
        }
        break;
      case VideoMenuAction.favorite:
        // 收藏
        _handleFavorite(videoInfo);
        break;
      case VideoMenuAction.unfavorite:
        // 取消收藏
        _handleUnfavorite(videoInfo);
        break;
      case VideoMenuAction.deleteRecord:
        // 搜索场景不支持删除记录
        break;
      case VideoMenuAction.doubanDetail:
        // 豆瓣详情 - 已在组件内部处理URL跳转
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '正在打开豆瓣详情: ${videoInfo.title}',
              style: FontUtils.poppins(color: Colors.white),
            ),
            backgroundColor: const Color(0xFF3498DB),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
        break;
      case VideoMenuAction.bangumiDetail:
        // Bangumi详情 - 已在组件内部处理URL跳转
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '正在打开 Bangumi 详情: ${videoInfo.title}',
              style: FontUtils.poppins(color: Colors.white),
            ),
            backgroundColor: const Color(0xFF3498DB),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
        break;
    }
  }

  /// 处理收藏
  Future<void> _handleFavorite(VideoInfo videoInfo) async {
    try {
      // 构建收藏数据
      final favoriteData = {
        'cover': videoInfo.cover,
        'save_time': DateTime.now().millisecondsSinceEpoch,
        'source_name': videoInfo.sourceName,
        'title': videoInfo.title,
        'total_episodes': videoInfo.totalEpisodes,
        'year': videoInfo.year,
      };

      // 使用统一的收藏方法（包含缓存操作和API调用）
      final result = await PageCacheService()
          .addFavorite(videoInfo.source, videoInfo.id, favoriteData, context);

      if (result.success) {
        // 通知UI刷新收藏状态
        if (mounted) {
          setState(() {});
        }
      } else {
        // 显示错误提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.errorMessage ?? '收藏失败',
                style: FontUtils.poppins(color: Colors.white),
              ),
              backgroundColor: const Color(0xFFe74c3c),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
        _refreshFavorites();
      }
    } catch (e) {
      // 显示错误提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '收藏失败: ${e.toString()}',
              style: FontUtils.poppins(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFe74c3c),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      _refreshFavorites();
    }
  }

  /// 处理取消收藏
  Future<void> _handleUnfavorite(VideoInfo videoInfo) async {
    try {
      // 先立即从UI中移除该项目
      FavoritesGrid.removeFavoriteFromUI(videoInfo.source, videoInfo.id);

      // 通知继续观看组件刷新收藏状态
      if (mounted) {
        setState(() {});
      }

      // 使用统一的取消收藏方法（包含缓存操作和API调用）
      final result = await PageCacheService()
          .removeFavorite(videoInfo.source, videoInfo.id, context);

      if (!result.success) {
        // 显示错误提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.errorMessage ?? '取消收藏失败',
                style: FontUtils.poppins(color: Colors.white),
              ),
              backgroundColor: const Color(0xFFe74c3c),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
        // API失败时重新刷新缓存以恢复数据
        _refreshFavorites();
      }
    } catch (e) {
      // 显示错误提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '取消收藏失败: ${e.toString()}',
              style: FontUtils.poppins(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFe74c3c),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      // 异常时重新刷新缓存以恢复数据
      _refreshFavorites();
    }
  }

  // 筛选器相关方法

  List<SelectorOption> get _sourceOptions {
    final sources = _searchResults.map((r) => r.sourceName).toSet().toList();
    sources.sort();
    final options =
        sources.map((s) => SelectorOption(label: s, value: s)).toList();
    return [
      const SelectorOption(label: '全部来源', value: 'all'),
      ...options,
    ];
  }

  List<SelectorOption> get _yearOptions {
    final years = _searchResults
        .map((r) => r.year)
        .where((y) => y.isNotEmpty)
        .toSet()
        .toList();
    years.sort((a, b) => b.compareTo(a)); // Sort descending
    final options =
        years.map((y) => SelectorOption(label: y, value: y)).toList();
    return [
      const SelectorOption(label: '全部年份', value: 'all'),
      ...options,
    ];
  }

  List<SelectorOption> get _titleOptions {
    final titles = _searchResults.map((r) => r.title).toSet().toList();
    titles.sort();
    final options =
        titles.map((t) => SelectorOption(label: t, value: t)).toList();
    return [
      const SelectorOption(label: '全部标题', value: 'all'),
      ...options,
    ];
  }

  Widget _buildFilterSection(ThemeService themeService) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start, // 靠左对齐
        children: [
          _buildFilterPill('来源', _sourceOptions, _selectedSource, (newValue) {
            setState(() {
              _selectedSource = newValue;
            });
          }, isFirst: true),
          _buildFilterPill('标题', _titleOptions, _selectedTitle, (newValue) {
            setState(() {
              _selectedTitle = newValue;
            });
          }),
          _buildFilterPill('年份', _yearOptions, _selectedYear, (newValue) {
            setState(() {
              _selectedYear = newValue;
            });
          }),
          _buildYearSortButton(),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String title, List<SelectorOption> options,
      String selectedValue, ValueChanged<String> onSelected,
      {bool isFirst = false}) {
    bool isDefault = selectedValue == 'all';
    bool isHovered = _hoveredFilterPill == title;

    return MouseRegion(
      cursor: DeviceUtils.isPC() ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: DeviceUtils.isPC()
          ? (_) {
              setState(() {
                _hoveredFilterPill = title;
              });
            }
          : null,
      onExit: DeviceUtils.isPC()
          ? (_) {
              setState(() {
                _hoveredFilterPill = null;
              });
            }
          : null,
      child: GestureDetector(
        onTap: () {
          _showFilterOptions(
              context, title, options, selectedValue, onSelected);
        },
        child: Container(
          padding: EdgeInsets.fromLTRB(isFirst ? 0 : 8, 6, 8, 6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Text(
                title, // 始终显示原始标题，不显示选中内容
                style: FontUtils.poppins(
                  fontSize: 13,
                  color: (DeviceUtils.isPC() && isHovered) || !isDefault
                      ? const Color(0xFF27AE60)
                      : Theme.of(context).textTheme.bodySmall?.color,
                  fontWeight: (DeviceUtils.isPC() && isHovered) || !isDefault
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: (DeviceUtils.isPC() && isHovered) || !isDefault
                    ? const Color(0xFF27AE60)
                    : Theme.of(context).textTheme.bodySmall?.color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilterOptions(
      BuildContext context,
      String title,
      List<SelectorOption> options,
      String selectedValue,
      ValueChanged<String> onSelected) {
    if (DeviceUtils.isPC()) {
      // PC端使用 filter_options_selector.dart 中的 PC 组件
      showFilterOptionsSelector(
        context: context,
        title: title,
        options: options,
        selectedValue: selectedValue,
        onSelected: onSelected,
        useCompactLayout: title == '标题', // 只有标题筛选使用紧凑布局
      );
    } else {
      // 移动端显示底部弹出
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          final screenWidth = MediaQuery.of(context).size.width;
          final modalWidth =
              DeviceUtils.isTablet(context) ? screenWidth * 0.5 : screenWidth;
          const horizontalPadding = 16.0;
          const spacing = 10.0;
          final itemWidth =
              (modalWidth - horizontalPadding * 2 - spacing * 2) / 3;

          return Container(
            width: DeviceUtils.isTablet(context)
                ? modalWidth
                : double.infinity, // 设置宽度为100%
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, // 左对齐
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                    minHeight: 200.0,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: horizontalPadding, vertical: 8),
                      child: Wrap(
                        alignment: WrapAlignment.start, // 左对齐
                        spacing: spacing,
                        runSpacing: spacing,
                        children: options.map((option) {
                          final isSelected = option.value == selectedValue;
                          return SizedBox(
                            width: itemWidth,
                            child: InkWell(
                              onTap: () {
                                onSelected(option.value);
                                Navigator.pop(context);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                alignment: Alignment.centerLeft, // 内容左对齐
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF27AE60)
                                      : Theme.of(context)
                                          .chipTheme
                                          .backgroundColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  option.label,
                                  textAlign: TextAlign.left, // 文字左对齐
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      );
    }
  }

  Widget _buildYearSortButton() {
    IconData icon;
    String text;
    switch (_yearSortOrder) {
      case SortOrder.desc:
        icon = LucideIcons.arrowDown10;
        text = '年份';
        break;
      case SortOrder.asc:
        icon = LucideIcons.arrowUp10;
        text = '年份';
        break;
      case SortOrder.none:
        icon = LucideIcons.arrowDownUp;
        text = '年份';
        break;
    }

    bool isDefault = _yearSortOrder == SortOrder.none;

    return MouseRegion(
      cursor: DeviceUtils.isPC() ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: DeviceUtils.isPC()
          ? (_) {
              setState(() {
                _isYearSortHovered = true;
              });
            }
          : null,
      onExit: DeviceUtils.isPC()
          ? (_) {
              setState(() {
                _isYearSortHovered = false;
              });
            }
          : null,
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (_yearSortOrder == SortOrder.none) {
              _yearSortOrder = SortOrder.desc;
            } else if (_yearSortOrder == SortOrder.desc) {
              _yearSortOrder = SortOrder.asc;
            } else {
              _yearSortOrder = SortOrder.none;
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Text(
                text,
                style: FontUtils.poppins(
                  fontSize: 13,
                  color:
                      (DeviceUtils.isPC() && _isYearSortHovered) || !isDefault
                          ? const Color(0xFF27AE60)
                          : Theme.of(context).textTheme.bodySmall?.color,
                  fontWeight:
                      (DeviceUtils.isPC() && _isYearSortHovered) || !isDefault
                          ? FontWeight.w500
                          : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                icon,
                size: 16,
                color: (DeviceUtils.isPC() && _isYearSortHovered) || !isDefault
                    ? const Color(0xFF27AE60)
                    : Theme.of(context).textTheme.bodySmall?.color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建搜索类型选择器
  Widget _buildSearchTypeSelector(ThemeService themeService) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildSearchTypeButton(
            label: '影视资源',
            icon: LucideIcons.film,
            isSelected: _searchType == SearchType.video,
            onTap: () {
              if (_searchType != SearchType.video) {
                setState(() {
                  _searchType = SearchType.video;
                });
                // 如果已有搜索词，重新搜索
                if (_searchQuery.isNotEmpty && _hasSearched) {
                  _performSearch(_searchQuery);
                }
              }
            },
            themeService: themeService,
          ),
          const SizedBox(width: 12),
          _buildSearchTypeButton(
            label: '网盘资源',
            icon: LucideIcons.hardDrive,
            isSelected: _searchType == SearchType.netdisk,
            onTap: () {
              if (_searchType != SearchType.netdisk) {
                setState(() {
                  _searchType = SearchType.netdisk;
                });
                // 如果已有搜索词，重新搜索
                if (_searchQuery.isNotEmpty && _hasSearched) {
                  _performSearch(_searchQuery);
                }
              }
            },
            themeService: themeService,
          ),
        ],
      ),
    );
  }

  /// 构建搜索类型按钮
  Widget _buildSearchTypeButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeService themeService,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF27AE60)
              : themeService.isDarkMode
                  ? Colors.white.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(
                  color: themeService.isDarkMode
                      ? Colors.white.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.3),
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? Colors.white
                  : themeService.isDarkMode
                      ? Colors.white.withOpacity(0.8)
                      : Colors.black87,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: FontUtils.poppins(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? Colors.white
                    : themeService.isDarkMode
                        ? Colors.white.withOpacity(0.8)
                        : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建网盘搜索结果
  Widget _buildNetdiskResults(ThemeService themeService) {
    if (_isNetdiskLoading) {
      return _buildNetdiskLoading(themeService);
    }

    if (_netdiskError != null) {
      return _buildNetdiskError(themeService);
    }

    if (_netdiskResult == null || _netdiskResult!.mergedByType.isEmpty) {
      return _buildNetdiskEmpty(themeService);
    }

    return _buildNetdiskResultsList(themeService);
  }

  /// 构建网盘搜索加载状态
  Widget _buildNetdiskLoading(ThemeService themeService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3498DB)),
          ),
          const SizedBox(height: 16),
          Text(
            '正在搜索网盘资源...',
            style: FontUtils.poppins(
              fontSize: 14,
              color: themeService.isDarkMode
                  ? const Color(0xFFb0b0b0)
                  : const Color(0xFF7f8c8d),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建网盘搜索错误状态
  Widget _buildNetdiskError(ThemeService themeService) {
    final isFunctionDisabled = _netdiskError?.contains('未启用') == true ||
        _netdiskError?.contains('未配置') == true;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isFunctionDisabled
                ? Colors.blue.withOpacity(0.1)
                : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFunctionDisabled
                  ? Colors.blue.withOpacity(0.3)
                  : Colors.red.withOpacity(0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFunctionDisabled ? Icons.info_outline : Icons.error_outline,
                size: 48,
                color: isFunctionDisabled ? Colors.blue : Colors.red[300],
              ),
              const SizedBox(height: 16),
              Text(
                isFunctionDisabled ? '网盘搜索功能未启用' : '搜索失败',
                style: FontUtils.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isFunctionDisabled ? Colors.blue : Colors.red[400],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _netdiskError ?? '未知错误',
                style: FontUtils.poppins(
                  fontSize: 14,
                  color: themeService.isDarkMode
                      ? Colors.white70
                      : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isFunctionDisabled
                      ? Colors.blue.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isFunctionDisabled
                      ? '💡 联系管理员启用网盘搜索功能\n暂时可以使用影视搜索功能查找内容'
                      : '💡 检查网络连接是否正常\n稍后重试或使用不同关键词搜索',
                  style: FontUtils.poppins(
                    fontSize: 12,
                    color: themeService.isDarkMode
                        ? Colors.white60
                        : Colors.black45,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (!isFunctionDisabled) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _performNetdiskSearch(_searchQuery),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3498DB),
                  ),
                  child: const Text('重试', style: TextStyle(color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 构建网盘搜索空状态
  Widget _buildNetdiskEmpty(ThemeService themeService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_queue,
            size: 64,
            color: themeService.isDarkMode ? Colors.white24 : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            '未找到相关资源',
            style: FontUtils.poppins(
              fontSize: 16,
              color: themeService.isDarkMode ? Colors.white54 : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '尝试使用其他关键词搜索',
            style: FontUtils.poppins(
              fontSize: 13,
              color: themeService.isDarkMode ? Colors.white38 : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建网盘搜索结果列表
  Widget _buildNetdiskResultsList(ThemeService themeService) {
    final result = _netdiskResult!;
    final types = result.mergedByType.keys.toList();
    final typesToShow = _selectedCloudType != null ? [_selectedCloudType!] : types;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        // 标题行
        Padding(
          padding: const EdgeInsets.only(left: 22.0, right: 16.0),
          child: Row(
            children: [
              Text(
                '搜索结果',
                style: FontUtils.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: themeService.isDarkMode
                      ? const Color(0xFFffffff)
                      : const Color(0xFF2c3e50),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF3498DB).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${result.total} 个资源',
                  style: FontUtils.poppins(
                    fontSize: 12,
                    color: const Color(0xFF3498DB),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 云盘类型筛选
        _buildCloudTypeFilter(types, themeService),
        const SizedBox(height: 8),
        // 结果列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: typesToShow.length,
            itemBuilder: (context, index) {
              final type = typesToShow[index];
              final items = result.mergedByType[type] ?? [];
              if (items.isEmpty) return const SizedBox.shrink();
              return _buildNetdiskTypeSection(type, items, themeService);
            },
          ),
        ),
      ],
    );
  }

  /// 构建云盘类型筛选器
  Widget _buildCloudTypeFilter(List<String> types, ThemeService themeService) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildCloudTypeChip(
              label: '全部 (${_netdiskResult!.total})',
              isSelected: _selectedCloudType == null,
              onTap: () => setState(() => _selectedCloudType = null),
              themeService: themeService,
            ),
            const SizedBox(width: 8),
            ...types.map((type) {
              final count = _netdiskResult!.mergedByType[type]?.length ?? 0;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildCloudTypeChip(
                  label: '${NetDiskService.getCloudTypeName(type)} ($count)',
                  isSelected: _selectedCloudType == type,
                  onTap: () => setState(() => _selectedCloudType = type),
                  color: Color(NetDiskService.getCloudTypeColor(type)),
                  themeService: themeService,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// 构建云盘类型筛选芯片
  Widget _buildCloudTypeChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeService themeService,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (color ?? const Color(0xFF3498DB))
              : themeService.isDarkMode
                  ? Colors.white.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(
                  color: themeService.isDarkMode
                      ? Colors.white.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.3),
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
                    ? Colors.white.withOpacity(0.8)
                    : Colors.black87,
          ),
        ),
      ),
    );
  }

  /// 构建网盘类型分组
  Widget _buildNetdiskTypeSection(String type, List<NetDiskItem> items, ThemeService themeService) {
    final color = Color(NetDiskService.getCloudTypeColor(type));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 类型标题
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                NetDiskService.getCloudTypeIcon(type),
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 8),
              Text(
                NetDiskService.getCloudTypeName(type),
                style: FontUtils.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${items.length} 个链接',
                  style: FontUtils.poppins(
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 资源列表
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return _buildNetdiskItem(item, type, index, color, themeService);
        }),
        const SizedBox(height: 8),
      ],
    );
  }

  /// 构建网盘资源项
  Widget _buildNetdiskItem(NetDiskItem item, String type, int index, Color typeColor, ThemeService themeService) {
    final linkKey = '$type-$index';
    final isPasswordVisible = _visiblePasswords[linkKey] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: themeService.isDarkMode
            ? Colors.white.withOpacity(0.05)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: themeService.isDarkMode
              ? Colors.white.withOpacity(0.1)
              : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openUrl(item.url),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Text(
                  item.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FontUtils.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: themeService.isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                // 链接
                Row(
                  children: [
                    const Icon(Icons.link, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: themeService.isDarkMode
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.url.length > 50 ? '${item.url.substring(0, 50)}...' : item.url,
                          style: FontUtils.poppins(
                            fontSize: 11,
                            color: themeService.isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _copyToClipboard(item.url),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.copy, size: 16, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
                // 密码（如果有）
                if (item.password.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: themeService.isDarkMode
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isPasswordVisible ? item.password : '****',
                          style: FontUtils.poppins(
                            fontSize: 11,
                            color: themeService.isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _visiblePasswords[linkKey] = !isPasswordVisible;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                            size: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: item.password));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('密码已复制', style: FontUtils.poppins(color: Colors.white)),
                              backgroundColor: const Color(0xFF27AE60),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.copy, size: 16, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ],
                // 元信息
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (item.source.isNotEmpty) ...[
                      Text(
                        '来源: ${item.source}',
                        style: FontUtils.poppins(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (item.datetime.isNotEmpty)
                      Text(
                        '时间: ${_formatDateTime(item.datetime)}',
                        style: FontUtils.poppins(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
                // 操作按钮
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openUrl(item.url),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('访问链接'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: typeColor,
                        side: BorderSide(color: typeColor.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: FontUtils.poppins(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 格式化日期时间
  String _formatDateTime(String datetime) {
    try {
      final dt = DateTime.parse(datetime);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return datetime;
    }
  }
}
