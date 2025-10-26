import 'package:flutter/material.dart';
import 'package:selene/services/live_service.dart';
import '../models/live_channel.dart';
import '../models/live_source.dart';
import '../utils/font_utils.dart';
import '../utils/device_utils.dart';
import '../services/theme_service.dart';
import 'package:provider/provider.dart';
import 'live_player_screen.dart';
import '../widgets/filter_pill_hover.dart';
import '../widgets/filter_options_selector.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen>
    with SingleTickerProviderStateMixin {
  List<LiveChannelGroup> _channelGroups = [];
  List<LiveSource> _liveSources = [];
  LiveSource? _currentSource;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  String _selectedGroup = '全部';
  final ScrollController _scrollController = ScrollController();
  late AnimationController _refreshIconController;

  @override
  void initState() {
    super.initState();
    _refreshIconController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _loadChannels();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _refreshIconController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadChannels({LiveSource? source}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. 获取所有直播源
      final liveSources = await LiveService.getLiveSources();

      if (liveSources.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = '暂无直播源，请在 MoonTV 添加';
            _isLoading = false;
            _liveSources = [];
            _currentSource = null;
          });
        }
        return;
      }

      // 2. 确定要使用的直播源
      final targetSource = source ?? _currentSource ?? liveSources.first;

      // 3. 获取该直播源的频道列表
      final channels = await LiveService.getLiveChannels(targetSource.key);

      if (channels.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = '该直播源暂无频道';
            _isLoading = false;
            _liveSources = liveSources;
            _currentSource = targetSource;
          });
        }
        return;
      }

      // 4. 按 group 进行聚类
      final Map<String, List<LiveChannel>> groupedChannels = {};
      for (var channel in channels) {
        final groupName = channel.group.isEmpty ? '未分组' : channel.group;
        if (!groupedChannels.containsKey(groupName)) {
          groupedChannels[groupName] = [];
        }
        groupedChannels[groupName]!.add(channel);
      }

      // 5. 转换为 LiveChannelGroup 列表
      final groups = groupedChannels.entries
          .map((entry) => LiveChannelGroup(
                name: entry.key,
                channels: entry.value,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _channelGroups = groups;
          _liveSources = liveSources;
          _currentSource = targetSource;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> refreshChannels() async {
    setState(() {
      _isRefreshing = true;
      _errorMessage = null;
    });
    
    // 开始旋转动画
    _refreshIconController.repeat();

    try {
      LiveService.clearAllChannelsAndEpgCache();
      // 1. 重新获取所有直播源
      final liveSources = await LiveService.getLiveSources(forceRefresh: true);

      if (liveSources.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = '暂无直播源，请在 MoonTV 添加';
            _isLoading = false;
            _liveSources = [];
            _currentSource = null;
          });
        }
        return;
      }

      // 2. 检查当前源是否还存在
      LiveSource? targetSource;
      if (_currentSource != null) {
        // 尝试在新的源列表中找到当前源
        try {
          targetSource = liveSources.firstWhere(
            (source) => source.key == _currentSource!.key,
          );
        } catch (e) {
          // 当前源不存在，使用第一个源
          targetSource = liveSources.first;
          if (mounted) {
            _showMessage('当前源已不存在，已切换到 ${targetSource.name}');
          }
        }
      } else {
        // 没有当前源，使用第一个源
        targetSource = liveSources.first;
      }

      // 3. 获取目标源的频道列表
      final channels = await LiveService.getLiveChannels(targetSource.key);

      if (channels.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = '该直播源暂无频道';
            _isLoading = false;
            _liveSources = liveSources;
            _currentSource = targetSource;
          });
        }
        return;
      }

      // 4. 按 group 进行聚类
      final Map<String, List<LiveChannel>> groupedChannels = {};
      for (var channel in channels) {
        final groupName = channel.group.isEmpty ? '未分组' : channel.group;
        if (!groupedChannels.containsKey(groupName)) {
          groupedChannels[groupName] = [];
        }
        groupedChannels[groupName]!.add(channel);
      }

      // 5. 转换为 LiveChannelGroup 列表
      final groups = groupedChannels.entries
          .map((entry) => LiveChannelGroup(
                name: entry.key,
                channels: entry.value,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _channelGroups = groups;
          _liveSources = liveSources;
          _currentSource = targetSource;
          _isLoading = false;
        });
        _showMessage('刷新成功');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '刷新失败: $e';
          _isLoading = false;
        });
        _showMessage('刷新失败: $e');
      }
    } finally {
      // 停止旋转动画
      if (mounted) {
        _refreshIconController.stop();
        _refreshIconController.reset();
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
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
  }



  List<LiveChannel> _getFilteredChannels() {
    if (_selectedGroup == '全部') {
      return _channelGroups.expand((g) => g.channels).toList();
    } else {
      return _channelGroups
          .firstWhere((g) => g.name == _selectedGroup,
              orElse: () => LiveChannelGroup(name: '', channels: []))
          .channels;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return Column(
          children: [
            _buildTopBar(themeService),
            Expanded(
              child: _isLoading
                  ? _buildLoadingView(themeService)
                  : _errorMessage != null
                      ? _buildErrorView(themeService)
                      : _buildChannelList(themeService),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar(ThemeService themeService) {
    final allGroups = ['全部', ..._channelGroups.map((g) => g.name)];
    
    // 构建分组选项
    final groupOptions = allGroups
        .map((g) => SelectorOption(label: g, value: g))
        .toList();
    
    // 构建直播源选项
    final sourceOptions = _liveSources
        .map((s) => SelectorOption(label: s.name, value: s.key))
        .toList();
    
    // 判断是否只有一个直播源
    final showSourceFilter = _liveSources.length > 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: themeService.isDarkMode
            ? const Color(0xFF1e1e1e).withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.8),
      ),
      child: Row(
        children: [
          // 直播源筛选（只有多个源时显示）
          if (showSourceFilter) ...[
            _buildFilterPill(
              '直播源',
              sourceOptions,
              _currentSource?.key ?? '',
              (value) {
                final source = _liveSources.firstWhere((s) => s.key == value);
                _loadChannels(source: source);
                setState(() {
                  _selectedGroup = '全部';
                });
                _scrollToTop();
              },
              themeService,
            ),
            const SizedBox(width: 8),
          ],
          // 分组筛选
          _buildFilterPill(
            '分组',
            groupOptions,
            _selectedGroup,
            (value) {
              setState(() {
                _selectedGroup = value;
              });
              _scrollToTop();
            },
            themeService,
          ),
          const Spacer(),
          // 刷新按钮
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: RotationTransition(
              turns: _refreshIconController,
              child: IconButton(
                icon: Icon(
                  Icons.refresh,
                  size: 20,
                  color: _isRefreshing
                      ? const Color(0xFF27ae60)
                      : (themeService.isDarkMode
                          ? Colors.grey[600]
                          : Colors.grey[500]),
                ),
                tooltip: '刷新直播源',
                onPressed: _isRefreshing ? null : refreshChannels,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(
    String title,
    List<SelectorOption> options,
    String selectedValue,
    ValueChanged<String> onSelected,
    ThemeService themeService,
  ) {
    final selectedOption = options.firstWhere(
      (e) => e.value == selectedValue,
      orElse: () => options.first,
    );
    final isDefault = selectedValue == '全部' || selectedValue.isEmpty;

    return FilterPillHover(
      isPC: DeviceUtils.isPC(),
      isDefault: isDefault,
      title: title,
      selectedOption: selectedOption,
      onTap: () {
        showFilterOptionsSelector(
          context: context,
          title: title,
          options: options,
          selectedValue: selectedValue,
          onSelected: onSelected,
        );
      },
    );
  }

  Widget _buildLoadingView(ThemeService themeService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF27ae60)),
          ),
          const SizedBox(height: 16),
          Text(
            '加载中...',
            style: FontUtils.poppins(
              color: themeService.isDarkMode
                  ? const Color(0xFFb0b0b0)
                  : const Color(0xFF7f8c8d),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(ThemeService themeService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: themeService.isDarkMode
                ? const Color(0xFF666666)
                : const Color(0xFF95a5a6),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? '加载失败',
            style: FontUtils.poppins(
              color: themeService.isDarkMode
                  ? const Color(0xFFb0b0b0)
                  : const Color(0xFF7f8c8d),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: refreshChannels,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27ae60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              '从 MoonTV 获取',
              style: FontUtils.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelList(ThemeService themeService) {
    final channels = _getFilteredChannels();

    if (channels.isEmpty) {
      return Center(
        child: Text(
          '暂无频道',
          style: FontUtils.poppins(
            color: themeService.isDarkMode
                ? const Color(0xFFb0b0b0)
                : const Color(0xFF7f8c8d),
          ),
        ),
      );
    }

    // 非 PC 平台直接使用 2 列，PC 平台根据宽度计算列数
    final int crossAxisCount = DeviceUtils.getLiveChannelColumnCount(context);
    const double childAspectRatio = 1.5;

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        return _buildChannelCard(channels[index], themeService);
      },
    );
  }

  Widget _buildChannelCard(LiveChannel channel, ThemeService themeService) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LivePlayerScreen(
              channel: channel,
              source: _currentSource!,
            ),
          ),
        ).then((_) => _loadChannels());
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 卡片主体 - 2:1 长宽比
          AspectRatio(
            aspectRatio: 2.0,
            child: Container(
              decoration: BoxDecoration(
                color: themeService.isDarkMode
                    ? const Color(0xFF1e1e1e)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildChannelLogo(channel, themeService),
                  ),
                ],
              ),
            ),
          ),
          // 标题 - 放在卡片下方居中
          const SizedBox(height: 8),
          Text(
            channel.name,
            style: FontUtils.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: themeService.isDarkMode
                  ? Colors.white
                  : const Color(0xFF2c3e50),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildChannelLogo(LiveChannel channel, ThemeService themeService) {
    // 如果有台标，显示台标
    if (channel.logo.isNotEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: themeService.isDarkMode
              ? const Color(0xFF2a2a2a)
              : const Color(0xFFc0c0c0),
        ),
        child: Image.network(
          channel.logo,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultPreview(themeService);
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _buildDefaultPreview(themeService);
          },
        ),
      );
    }
    // 没有台标，显示默认图标
    return _buildDefaultPreview(themeService);
  }

  Widget _buildDefaultPreview(ThemeService themeService) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: themeService.isDarkMode
            ? const Color(0xFF2a2a2a)
            : const Color(0xFFc0c0c0),
      ),
      child: Center(
        child: Icon(
          Icons.tv,
          size: 48,
          color: themeService.isDarkMode
              ? const Color(0xFF666666)
              : const Color(0xFF95a5b0),
        ),
      ),
    );
  }
}
