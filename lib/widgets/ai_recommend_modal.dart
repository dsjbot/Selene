import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ai_recommend_service.dart';
import '../services/theme_service.dart';
import '../utils/font_utils.dart';
import '../screens/search_screen.dart';
import '../screens/player_screen.dart';

/// AI 推荐模态框
class AIRecommendModal extends StatefulWidget {
  final VideoContext? context;
  final String? welcomeMessage;

  const AIRecommendModal({
    super.key,
    this.context,
    this.welcomeMessage,
  });

  /// 显示 AI 推荐模态框
  static Future<void> show(
    BuildContext context, {
    VideoContext? videoContext,
    String? welcomeMessage,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AIRecommendModal(
        context: videoContext,
        welcomeMessage: welcomeMessage,
      ),
    );
  }

  @override
  State<AIRecommendModal> createState() => _AIRecommendModalState();
}


/// 扩展的 AI 消息（包含推荐数据）
class ExtendedAIMessage extends AIMessage {
  final List<MovieRecommendation>? recommendations;
  final List<YouTubeVideo>? youtubeVideos;
  final List<VideoLink>? videoLinks;
  final String? type;

  ExtendedAIMessage({
    required super.role,
    required super.content,
    super.timestamp,
    this.recommendations,
    this.youtubeVideos,
    this.videoLinks,
    this.type,
  });
}

class _AIRecommendModalState extends State<AIRecommendModal> {
  final List<ExtendedAIMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  bool _isLoading = false;
  String? _error;
  String? _playingVideoId;

  @override
  void initState() {
    super.initState();
    _initWelcomeMessage();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _initWelcomeMessage() {
    final defaultWelcome = widget.context?.title != null
        ? '想了解《${widget.context!.title}》的更多信息吗？我可以帮你查询剧情、演员、评价等。'
        : '''你好！我是 **AI 智能助手**，支持以下功能：

- 🎬 **影视剧推荐** - 推荐电影、电视剧、动漫等
- 🔗 **视频链接解析** - 解析 YouTube 链接并播放
- 📺 **视频内容搜索** - 搜索相关视频内容

💡 **提示**：直接告诉我你想看什么类型的内容！''';

    _messages.add(ExtendedAIMessage(
      role: 'assistant',
      content: widget.welcomeMessage ?? defaultWelcome,
      timestamp: DateTime.now().toIso8601String(),
    ));
  }


  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage(String content) async {
    if (content.trim().isEmpty || _isLoading) return;

    final userMessage = ExtendedAIMessage(
      role: 'user',
      content: content.trim(),
      timestamp: DateTime.now().toIso8601String(),
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
      _error = null;
      _inputController.clear();
    });

    _scrollToBottom();

    // 添加思考中消息
    final thinkingIndex = _messages.length;
    setState(() {
      _messages.add(ExtendedAIMessage(
        role: 'assistant',
        content: '思考中...',
        timestamp: DateTime.now().toIso8601String(),
      ));
    });

    try {
      // 只发送最近 8 条消息
      final conversationHistory = _messages
          .where((m) => m.content != '思考中...')
          .toList()
          .reversed
          .take(8)
          .toList()
          .reversed
          .map((m) => AIMessage(role: m.role, content: m.content))
          .toList();

      String streamingContent = '';

      final response = await AIRecommendService.sendMessage(
        messages: conversationHistory,
        context: widget.context,
        onStream: (chunk) {
          streamingContent += chunk;
          if (mounted) {
            setState(() {
              if (thinkingIndex < _messages.length) {
                _messages[thinkingIndex] = ExtendedAIMessage(
                  role: 'assistant',
                  content: streamingContent,
                  timestamp: DateTime.now().toIso8601String(),
                );
              }
            });
            _scrollToBottom();
          }
        },
      );


      if (response.hasError) {
        setState(() {
          _messages[thinkingIndex] = ExtendedAIMessage(
            role: 'assistant',
            content: '❌ ${response.error}${response.errorDetails != null ? '\n\n${response.errorDetails}' : ''}',
            timestamp: DateTime.now().toIso8601String(),
          );
          _isLoading = false;
        });
        return;
      }

      // 从回复中提取推荐
      final recommendations = _extractRecommendations(response.content);

      setState(() {
        _messages[thinkingIndex] = ExtendedAIMessage(
          role: 'assistant',
          content: response.content,
          timestamp: DateTime.now().toIso8601String(),
          recommendations: recommendations.isNotEmpty ? recommendations : null,
          youtubeVideos: response.youtubeVideos,
          videoLinks: response.videoLinks,
          type: response.type,
        );
        _isLoading = false;
      });

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages[thinkingIndex] = ExtendedAIMessage(
          role: 'assistant',
          content: '❌ 发送失败: $e',
          timestamp: DateTime.now().toIso8601String(),
        );
        _isLoading = false;
      });
    }
  }

  List<MovieRecommendation> _extractRecommendations(String content) {
    final recommendations = <MovieRecommendation>[];
    final lines = content.split('\n');

    // 匹配《片名》格式
    final titlePattern = RegExp(r'《([^》]+)》');

    for (final line in lines) {
      if (recommendations.length >= 4) break;

      final match = titlePattern.firstMatch(line);
      if (match != null) {
        final title = match.group(1)?.trim() ?? '';
        String? year;
        String? genre;

        // 尝试提取年份
        final yearMatch = RegExp(r'[（(](\d{4})[）)]').firstMatch(line);
        if (yearMatch != null) {
          year = yearMatch.group(1);
        }

        // 尝试提取类型
        final genreMatch = RegExp(r'\[([^\]]+)\]').firstMatch(line);
        if (genreMatch != null) {
          genre = genreMatch.group(1);
        }

        recommendations.add(MovieRecommendation(
          title: title,
          year: year,
          genre: genre,
          description: 'AI推荐内容',
        ));
      }
    }

    return recommendations;
  }


  void _handleTitleClick(String title) {
    final cleanTitle = AIRecommendService.cleanMovieTitle(title);
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchScreen(initialQuery: cleanTitle),
      ),
    );
  }

  void _handleMovieSelect(MovieRecommendation movie) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          title: movie.title,
          year: movie.year,
        ),
      ),
    );
  }

  void _handleYouTubeVideoSelect(YouTubeVideo video) {
    setState(() {
      _playingVideoId = _playingVideoId == video.id ? null : video.id;
    });
  }

  void _handleVideoLinkPlay(VideoLink video) {
    if (video.playable && video.embedUrl != null) {
      setState(() {
        _playingVideoId = _playingVideoId == video.videoId ? null : video.videoId;
      });
    }
  }

  void _openYouTubeExternal(String videoId) async {
    final url = Uri.parse('https://www.youtube.com/watch?v=$videoId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        final isDark = themeService.isDarkMode;
        final screenHeight = MediaQuery.of(context).size.height;

        return Container(
          height: screenHeight * 0.85,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F2937) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _buildHeader(isDark),
              Expanded(child: _buildMessageList(isDark)),
              _buildPresets(isDark),
              _buildInputArea(isDark),
            ],
          ),
        );
      },
    );
  }


  void _clearChat() {
    setState(() {
      _messages.clear();
      _playingVideoId = null;
      _error = null;
    });
    _initWelcomeMessage();
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              LucideIcons.sparkles,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 智能推荐',
                  style: FontUtils.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  '影视推荐 · 视频解析',
                  style: FontUtils.poppins(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          // 清空按钮
          if (_messages.length > 1)
            IconButton(
              onPressed: _isLoading ? null : _clearChat,
              tooltip: '清空对话',
              icon: Icon(
                LucideIcons.trash2,
                color: _isLoading 
                    ? Colors.grey 
                    : (isDark ? Colors.grey[400] : Colors.grey[600]),
                size: 20,
              ),
            ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              LucideIcons.x,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(bool isDark) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageItem(message, isDark);
      },
    );
  }


  Widget _buildMessageItem(ExtendedAIMessage message, bool isDark) {
    final isUser = message.role == 'user';
    final isThinking = message.content == '思考中...';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // 消息气泡
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser
                  ? const Color(0xFF3B82F6)
                  : (isDark ? const Color(0xFF374151) : Colors.grey[100]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: isThinking
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDark ? Colors.white70 : Colors.grey[600]!,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '思考中...',
                        style: FontUtils.poppins(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                    ],
                  )
                : isUser
                    ? Text(
                        message.content,
                        style: FontUtils.poppins(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      )
                    : _buildMarkdownContent(message.content, isDark),
          ),

          // 推荐影片卡片
          if (!isUser && message.recommendations != null && message.recommendations!.isNotEmpty)
            _buildRecommendationCards(message.recommendations!, isDark),

          // YouTube 视频卡片
          if (!isUser && message.youtubeVideos != null && message.youtubeVideos!.isNotEmpty)
            _buildYouTubeCards(message.youtubeVideos!, isDark),

          // 视频链接卡片
          if (!isUser && message.videoLinks != null && message.videoLinks!.isNotEmpty)
            _buildVideoLinkCards(message.videoLinks!, isDark),
        ],
      ),
    );
  }


  Widget _buildMarkdownContent(String content, bool isDark) {
    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: FontUtils.poppins(
          fontSize: 14,
          color: isDark ? Colors.white : Colors.black87,
        ),
        h1: FontUtils.poppins(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : Colors.black87,
        ),
        h2: FontUtils.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
        h3: FontUtils.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
        strong: FontUtils.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
        listBullet: FontUtils.poppins(
          fontSize: 14,
          color: isDark ? Colors.white70 : Colors.black54,
        ),
        code: TextStyle(
          fontSize: 13,
          color: const Color(0xFF8B5CF6),
          backgroundColor: isDark ? const Color(0xFF1F2937) : const Color(0xFFF3E8FF),
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onTapLink: (text, href, title) {
        // 检查是否是影片标题
        final titleMatch = RegExp(r'《([^》]+)》').firstMatch(text);
        if (titleMatch != null) {
          _handleTitleClick(titleMatch.group(1)!);
        } else if (href != null) {
          launchUrl(Uri.parse(href));
        }
      },
    );
  }

  Widget _buildRecommendationCards(List<MovieRecommendation> recommendations, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '🎬 点击搜索',
                  style: FontUtils.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF3B82F6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '推荐影片',
                style: FontUtils.poppins(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...recommendations.take(4).map((movie) => _buildMovieCard(movie, isDark)),
        ],
      ),
    );
  }


  Widget _buildMovieCard(MovieRecommendation movie, bool isDark) {
    return GestureDetector(
      onTap: () => _handleMovieSelect(movie),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF374151) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          movie.title,
                          style: FontUtils.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      if (movie.year != null)
                        Text(
                          '(${movie.year})',
                          style: FontUtils.poppins(
                            fontSize: 12,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                  if (movie.genre != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        movie.genre!,
                        style: FontUtils.poppins(
                          fontSize: 12,
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.search,
              size: 16,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYouTubeCards(List<YouTubeVideo> videos, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '📺 点击播放',
                  style: FontUtils.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'YouTube视频推荐',
                style: FontUtils.poppins(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...videos.map((video) => _buildYouTubeCard(video, isDark)),
        ],
      ),
    );
  }


  Widget _buildYouTubeCard(YouTubeVideo video, bool isDark) {
    final isPlaying = _playingVideoId == video.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF374151) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _handleYouTubeVideoSelect(video),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          video.thumbnail,
                          width: 80,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 80,
                            height: 60,
                            color: Colors.grey[300],
                            child: const Icon(LucideIcons.play, color: Colors.grey),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Icon(
                              LucideIcons.play,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FontUtils.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          video.channelTitle,
                          style: FontUtils.poppins(
                            fontSize: 11,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isPlaying)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _openYouTubeExternal(video.id),
                      icon: const Icon(LucideIcons.externalLink, size: 16),
                      label: const Text('在YouTube打开'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildVideoLinkCards(List<VideoLink> videos, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '🔗 链接解析',
                  style: FontUtils.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '视频链接解析结果',
                style: FontUtils.poppins(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...videos.map((video) => _buildVideoLinkCard(video, isDark)),
        ],
      ),
    );
  }

  Widget _buildVideoLinkCard(VideoLink video, bool isDark) {
    if (!video.playable) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF374151) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '解析失败',
              style: FontUtils.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
            if (video.error != null)
              Text(
                video.error!,
                style: FontUtils.poppins(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            Text(
              '原链接: ${video.originalUrl}',
              style: FontUtils.poppins(
                fontSize: 11,
                color: isDark ? Colors.grey[500] : Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF374151) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        video.thumbnail,
                        width: 80,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 80,
                          height: 60,
                          color: Colors.grey[300],
                          child: const Icon(LucideIcons.play, color: Colors.grey),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => _handleVideoLinkPlay(video),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Icon(
                              LucideIcons.play,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FontUtils.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        video.channelName,
                        style: FontUtils.poppins(
                          fontSize: 11,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openYouTubeExternal(video.videoId),
                    icon: const Icon(LucideIcons.externalLink, size: 16),
                    label: const Text('原始链接'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildPresets(bool isDark) {
    // 只在消息少于 2 条时显示预设
    if (_messages.length > 2) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: AIRecommendService.presets.take(4).map((preset) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _sendMessage(preset.message),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF374151) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  ),
                  child: Text(
                    preset.title,
                    style: FontUtils.poppins(
                      fontSize: 12,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildInputArea(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _focusNode,
              enabled: !_isLoading,
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: _sendMessage,
              style: FontUtils.poppins(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: '输入你想看的内容...',
                hintStyle: FontUtils.poppins(
                  fontSize: 14,
                  color: isDark ? Colors.grey[500] : Colors.grey[400],
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF374151) : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isLoading ? null : () => _sendMessage(_inputController.text),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: _isLoading
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                      ),
                color: _isLoading ? Colors.grey : null,
                borderRadius: BorderRadius.circular(22),
              ),
              child: _isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    )
                  : const Icon(
                      LucideIcons.send,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
