import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/tmdb_cast_service.dart';
import '../services/user_data_service.dart';
import '../utils/font_utils.dart';
import '../models/video_info.dart';
import 'video_card.dart';

/// 演员照片和作品面板
class CastPhotosPanel extends StatefulWidget {
  final List<String> actorNames;
  final String? doubanId;
  final bool isDarkMode;

  const CastPhotosPanel({
    super.key,
    required this.actorNames,
    this.doubanId,
    required this.isDarkMode,
  });

  @override
  State<CastPhotosPanel> createState() => _CastPhotosPanelState();
}

class _CastPhotosPanelState extends State<CastPhotosPanel> {
  List<TMDBCastMember> _actors = [];
  bool _isLoading = true;
  bool _isEnabled = false;
  
  // 选中的演员索引
  int _selectedIndex = 0;
  
  // 演员作品
  List<TMDBActorWork> _actorWorks = [];
  bool _isWorksLoading = false;
  String _worksType = 'tv'; // 'movie' 或 'tv'
  
  // 滚动控制器
  final ScrollController _actorsScrollController = ScrollController();
  final ScrollController _worksScrollController = ScrollController();
  
  // 滚动箭头状态
  bool _showActorsLeftArrow = false;
  bool _showActorsRightArrow = false;
  bool _showWorksLeftArrow = false;
  bool _showWorksRightArrow = false;
  
  // 图片代理相关
  String? _serverUrl;
  String? _cookies;

  @override
  void initState() {
    super.initState();
    _loadServerInfo();
    _loadCastPhotos();
    _actorsScrollController.addListener(_checkActorsScrollPosition);
    _worksScrollController.addListener(_checkWorksScrollPosition);
  }
  
  Future<void> _loadServerInfo() async {
    final url = await UserDataService.getServerUrl();
    final cookies = await UserDataService.getCookies();
    if (mounted) {
      setState(() {
        _serverUrl = url;
        _cookies = cookies;
      });
    }
  }

  @override
  void dispose() {
    _actorsScrollController.removeListener(_checkActorsScrollPosition);
    _worksScrollController.removeListener(_checkWorksScrollPosition);
    _actorsScrollController.dispose();
    _worksScrollController.dispose();
    super.dispose();
  }

  void _checkActorsScrollPosition() {
    if (!_actorsScrollController.hasClients) return;
    final position = _actorsScrollController.position;
    setState(() {
      _showActorsLeftArrow = position.pixels > 0;
      _showActorsRightArrow = position.pixels < position.maxScrollExtent - 1;
    });
  }

  void _checkWorksScrollPosition() {
    if (!_worksScrollController.hasClients) return;
    final position = _worksScrollController.position;
    setState(() {
      _showWorksLeftArrow = position.pixels > 0;
      _showWorksRightArrow = position.pixels < position.maxScrollExtent - 1;
    });
  }

  Future<void> _loadCastPhotos() async {
    if (widget.actorNames.isEmpty) {
      setState(() {
        _isLoading = false;
        _isEnabled = false;
      });
      return;
    }

    try {
      final actors = await TMDBCastService.getCastPhotos(widget.actorNames);
      
      if (mounted) {
        setState(() {
          _actors = actors;
          _isLoading = false;
          _isEnabled = actors.isNotEmpty;
        });

        // 如果有演员，自动加载第一个演员的作品
        if (actors.isNotEmpty) {
          _loadActorWorks(actors[0].name);
          // 延迟检查滚动状态
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkActorsScrollPosition();
          });
        }
      }
    } catch (e) {
      debugPrint('[CastPhotosPanel] 加载演员照片失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isEnabled = false;
        });
      }
    }
  }

  Future<void> _loadActorWorks(String actorName) async {
    setState(() {
      _isWorksLoading = true;
      _actorWorks = [];
    });

    try {
      final works = await TMDBCastService.getActorWorks(
        actorName,
        type: _worksType,
        sortBy: 'date',
        sortOrder: 'desc',
        limit: 50,
      );

      if (mounted) {
        setState(() {
          _actorWorks = works;
          _isWorksLoading = false;
        });
        // 延迟检查滚动状态
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkWorksScrollPosition();
        });
      }
    } catch (e) {
      debugPrint('[CastPhotosPanel] 加载演员作品失败: $e');
      if (mounted) {
        setState(() {
          _isWorksLoading = false;
        });
      }
    }
  }

  void _onActorTap(int index) {
    if (index == _selectedIndex) return;
    
    setState(() {
      _selectedIndex = index;
    });
    
    _loadActorWorks(_actors[index].name);
  }

  void _onTypeChange(String type) {
    if (type == _worksType) return;
    
    setState(() {
      _worksType = type;
    });
    
    if (_actors.isNotEmpty) {
      _loadActorWorks(_actors[_selectedIndex].name);
    }
  }

  void _scrollActors(String direction) {
    final offset = direction == 'left' ? -240.0 : 240.0;
    _actorsScrollController.animateTo(
      (_actorsScrollController.offset + offset).clamp(
        0.0,
        _actorsScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _scrollWorks(String direction) {
    final offset = direction == 'left' ? -400.0 : 400.0;
    _worksScrollController.animateTo(
      (_worksScrollController.offset + offset).clamp(
        0.0,
        _worksScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 加载中或未启用时不显示
    if (_isLoading || !_isEnabled || _actors.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedActor = _actors.isNotEmpty ? _actors[_selectedIndex] : null;
    final needsActorsScroll = _showActorsLeftArrow || _showActorsRightArrow;
    final needsWorksScroll = _showWorksLeftArrow || _showWorksRightArrow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        
        // 标题和滚动按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '主演',
                style: FontUtils.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: widget.isDarkMode ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
              if (needsActorsScroll)
                Row(
                  children: [
                    _buildScrollButton(
                      icon: LucideIcons.chevronLeft,
                      enabled: _showActorsLeftArrow,
                      onTap: () => _scrollActors('left'),
                    ),
                    const SizedBox(width: 4),
                    _buildScrollButton(
                      icon: LucideIcons.chevronRight,
                      enabled: _showActorsRightArrow,
                      onTap: () => _scrollActors('right'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        
        // 演员头像列表
        SizedBox(
          height: 110,
          child: ListView.builder(
            controller: _actorsScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _actors.length,
            itemBuilder: (context, index) {
              final actor = _actors[index];
              final isSelected = index == _selectedIndex;
              
              return _buildActorItem(actor, isSelected, index);
            },
          ),
        ),
        
        const SizedBox(height: 16),
        
        // 演员作品区域
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.isDarkMode 
                ? Colors.grey[850]?.withValues(alpha: 0.5) 
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题和类型切换
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '${selectedActor?.name ?? ''} 的作品',
                        style: FontUtils.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: widget.isDarkMode ? Colors.grey[300] : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildTypeSwitch(),
                    ],
                  ),
                  if (needsWorksScroll)
                    Row(
                      children: [
                        _buildScrollButton(
                          icon: LucideIcons.chevronLeft,
                          enabled: _showWorksLeftArrow,
                          onTap: () => _scrollWorks('left'),
                        ),
                        const SizedBox(width: 4),
                        _buildScrollButton(
                          icon: LucideIcons.chevronRight,
                          enabled: _showWorksRightArrow,
                          onTap: () => _scrollWorks('right'),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              
              // 作品列表
              SizedBox(
                height: 200,
                child: _isWorksLoading
                    ? Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              widget.isDarkMode ? Colors.white : Colors.blue,
                            ),
                          ),
                        ),
                      )
                    : _actorWorks.isEmpty
                        ? Center(
                            child: Text(
                              '暂无${_worksType == 'movie' ? '电影' : '电视剧'}作品',
                              style: FontUtils.poppins(
                                fontSize: 14,
                                color: widget.isDarkMode ? Colors.grey[500] : Colors.grey[400],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _worksScrollController,
                            scrollDirection: Axis.horizontal,
                            itemCount: _actorWorks.length,
                            itemBuilder: (context, index) {
                              final work = _actorWorks[index];
                              return _buildWorkItem(work);
                            },
                          ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActorItem(TMDBCastMember actor, bool isSelected, int index) {
    return GestureDetector(
      onTap: () => _onActorTap(index),
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            // 头像
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.blue : Colors.transparent,
                  width: 2,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: ClipOval(
                child: actor.photo != null
                    ? CachedNetworkImage(
                        imageUrl: _getProxiedImageUrl(actor.photo!),
                        fit: BoxFit.cover,
                        httpHeaders: _getImageHeaders(),
                        placeholder: (context, url) => Container(
                          color: widget.isDarkMode ? Colors.grey[800] : Colors.grey[200],
                          child: Icon(
                            LucideIcons.user,
                            size: 24,
                            color: widget.isDarkMode ? Colors.grey[600] : Colors.grey[400],
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: widget.isDarkMode ? Colors.grey[800] : Colors.grey[200],
                          child: Icon(
                            LucideIcons.user,
                            size: 24,
                            color: widget.isDarkMode ? Colors.grey[600] : Colors.grey[400],
                          ),
                        ),
                      )
                    : Container(
                        color: widget.isDarkMode ? Colors.grey[800] : Colors.grey[200],
                        child: Icon(
                          LucideIcons.user,
                          size: 24,
                          color: widget.isDarkMode ? Colors.grey[600] : Colors.grey[400],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            // 名字
            Text(
              actor.name,
              style: FontUtils.poppins(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? Colors.blue
                    : (widget.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            // 角色名（如果有中文角色名）
            if (actor.character != null && 
                actor.character!.isNotEmpty &&
                RegExp(r'[\u4e00-\u9fa5]').hasMatch(actor.character!))
              Text(
                '饰 ${actor.character}',
                style: FontUtils.poppins(
                  fontSize: 10,
                  color: widget.isDarkMode ? Colors.grey[500] : Colors.grey[400],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkItem(TMDBActorWork work) {
    // 获取代理后的封面URL
    final proxiedPoster = _getProxiedImageUrl(work.poster);
    
    // 创建 VideoInfo 对象
    // 使用 'tmdb' 作为 source，避免 VideoCard 添加豆瓣的 headers
    final videoInfo = VideoInfo(
      id: work.id,
      source: 'tmdb',
      title: work.title,
      sourceName: 'TMDB',
      year: work.year,
      cover: proxiedPoster, // 使用代理后的URL
      index: 1,
      totalEpisodes: 1,
      playTime: 0,
      totalTime: 0,
      saveTime: DateTime.now().millisecondsSinceEpoch,
      searchTitle: work.title,
      doubanId: work.id,
      rate: work.rate,
    );

    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 12),
      child: VideoCard(
        videoInfo: videoInfo,
        from: 'douban',
      ),
    );
  }

  Widget _buildTypeSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: widget.isDarkMode ? Colors.grey[700] : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTypeButton('tv', '电视剧'),
          _buildTypeButton('movie', '电影'),
        ],
      ),
    );
  }

  Widget _buildTypeButton(String type, String label) {
    final isSelected = _worksType == type;
    
    return GestureDetector(
      onTap: _isWorksLoading ? null : () => _onTypeChange(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (widget.isDarkMode ? Colors.grey[600] : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: FontUtils.poppins(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
            color: isSelected
                ? (widget.isDarkMode ? Colors.blue[400] : Colors.blue)
                : (widget.isDarkMode ? Colors.grey[400] : Colors.grey[500]),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: enabled
              ? (widget.isDarkMode ? Colors.grey[700] : Colors.grey[200])
              : Colors.transparent,
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled
              ? (widget.isDarkMode ? Colors.grey[300] : Colors.grey[600])
              : (widget.isDarkMode ? Colors.grey[600] : Colors.grey[300]),
        ),
      ),
    );
  }

  /// 获取代理后的图片URL
  String _getProxiedImageUrl(String originalUrl) {
    if (originalUrl.isEmpty || _serverUrl == null) return originalUrl;
    // TMDB 图片需要通过后端代理访问
    if (originalUrl.contains('image.tmdb.org') || originalUrl.contains('tmdb.org')) {
      return '$_serverUrl/api/image-proxy?url=${Uri.encodeComponent(originalUrl)}';
    }
    return originalUrl;
  }

  Map<String, String> _getImageHeaders() {
    final headers = <String, String>{};
    if (_cookies != null && _cookies!.isNotEmpty) {
      headers['Cookie'] = _cookies!;
    }
    return headers;
  }
}
