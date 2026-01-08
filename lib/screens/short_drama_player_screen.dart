import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import '../models/short_drama.dart';
import '../services/short_drama_service.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/video_player_surface.dart';

class ShortDramaPlayerScreen extends StatefulWidget {
  final int id;
  final String name;
  final String cover;

  const ShortDramaPlayerScreen({
    super.key,
    required this.id,
    required this.name,
    required this.cover,
  });

  @override
  State<ShortDramaPlayerScreen> createState() => _ShortDramaPlayerScreenState();
}

class _ShortDramaPlayerScreenState extends State<ShortDramaPlayerScreen> {
  ShortDramaDetail? _detail;
  ShortDramaParseResult? _parseResult;
  bool _isLoading = true;
  bool _isParsing = false;
  String? _error;
  int _currentEpisode = 0;
  VideoPlayerWidgetController? _playerController;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final response = await ShortDramaService.getDetail(
      id: widget.id,
      name: widget.name,
    );

    if (mounted) {
      if (response.success && response.data != null) {
        setState(() {
          _detail = response.data;
          _isLoading = false;
        });
        // 自动播放第一集
        if (_detail!.episodes.isNotEmpty) {
          _playEpisode(0);
        }
      } else {
        setState(() {
          _error = response.message ?? '加载失败';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _playEpisode(int index) async {
    if (_isParsing) return;
    if (_detail == null) return;
    if (_detail!.episodes.isEmpty) {
      setState(() {
        _error = '没有可播放的剧集';
      });
      return;
    }
    if (index >= _detail!.episodes.length) {
      index = _detail!.episodes.length - 1;
    }

    setState(() {
      _isParsing = true;
      _currentEpisode = index;
      _error = null;
    });

    final response = await ShortDramaService.parse(
      id: widget.id,
      episode: index,
      name: widget.name,
    );

    if (mounted) {
      setState(() {
        _isParsing = false;
        if (response.success && response.data != null) {
          _parseResult = response.data;
          // 如果播放器已存在，更新视频源
          if (_playerController != null && _parseResult!.url.isNotEmpty) {
            _playerController!.updateDataSource(_parseResult!.url);
          }
        } else {
          _error = response.message ?? '解析失败';
        }
      });
    }
  }

  void _onEpisodeEnd() {
    // 自动播放下一集
    if (_detail != null && _currentEpisode < _detail!.episodes.length - 1) {
      _playEpisode(_currentEpisode + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(widget.name),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _detail == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDetail,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // 播放器区域
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _buildPlayer(context),
                    ),
                    // 剧集信息和选集
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 标题和描述
                            Text(
                              _detail?.title.isNotEmpty == true 
                                  ? _detail!.title 
                                  : widget.name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            if (_detail?.desc.isNotEmpty == true) ...[
                              const SizedBox(height: 8),
                              Text(
                                _detail!.desc,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.white60 : Colors.black54,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 16),
                            // 选集标题
                            Row(
                              children: [
                                Text(
                                  '选集',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '共${_detail?.episodes.length ?? 0}集',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // 选集网格
                            _buildEpisodeGrid(context),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildPlayer(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;

    if (_isParsing) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                '正在解析...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null && _parseResult == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _playEpisode(_currentEpisode),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_parseResult == null || _parseResult!.url.isEmpty) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text(
            '等待播放...',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return VideoPlayerWidget(
      surface: isMobile ? VideoPlayerSurface.mobile : VideoPlayerSurface.desktop,
      url: _parseResult!.url,
      videoTitle: '${widget.name} 第${_currentEpisode + 1}集',
      currentEpisodeIndex: _currentEpisode,
      totalEpisodes: _detail?.episodes.length ?? 1,
      sourceName: '短剧',
      isLastEpisode: _detail != null && _currentEpisode >= _detail!.episodes.length - 1,
      onControllerCreated: (controller) {
        _playerController = controller;
      },
      onVideoCompleted: _onEpisodeEnd,
      onNextEpisode: _detail != null && _currentEpisode < _detail!.episodes.length - 1
          ? () => _playEpisode(_currentEpisode + 1)
          : null,
      onBackPressed: () => Navigator.pop(context),
    );
  }

  Widget _buildEpisodeGrid(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final episodes = _detail?.episodes ?? [];

    if (episodes.isEmpty) {
      return Center(
        child: Text(
          '暂无剧集',
          style: TextStyle(
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        childAspectRatio: 1.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        final isSelected = index == _currentEpisode;
        return GestureDetector(
          onTap: () => _playEpisode(index),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).primaryColor
                  : (isDark ? Colors.grey[800] : Colors.grey[200]),
              borderRadius: BorderRadius.circular(6),
              border: isSelected
                  ? Border.all(
                      color: Theme.of(context).primaryColor,
                      width: 2,
                    )
                  : null,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (isDark ? Colors.white70 : Colors.black87),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
