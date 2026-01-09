import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'user_data_service.dart';

/// AI 消息
class AIMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final String? timestamp;

  AIMessage({
    required this.role,
    required this.content,
    this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
  };

  factory AIMessage.fromJson(Map<String, dynamic> json) => AIMessage(
    role: json['role'] ?? 'user',
    content: json['content'] ?? '',
    timestamp: json['timestamp'],
  );
}

/// 影片推荐
class MovieRecommendation {
  final String title;
  final String? year;
  final String? genre;
  final String description;
  final String? poster;

  MovieRecommendation({
    required this.title,
    this.year,
    this.genre,
    required this.description,
    this.poster,
  });

  factory MovieRecommendation.fromJson(Map<String, dynamic> json) => MovieRecommendation(
    title: json['title'] ?? '',
    year: json['year'],
    genre: json['genre'],
    description: json['description'] ?? '',
    poster: json['poster'],
  );
}

/// YouTube 视频
class YouTubeVideo {
  final String id;
  final String title;
  final String channelTitle;
  final String? description;
  final String thumbnail;

  YouTubeVideo({
    required this.id,
    required this.title,
    required this.channelTitle,
    this.description,
    required this.thumbnail,
  });

  factory YouTubeVideo.fromJson(Map<String, dynamic> json) => YouTubeVideo(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    channelTitle: json['channelTitle'] ?? '',
    description: json['description'],
    thumbnail: json['thumbnail'] ?? '',
  );
}

/// 视频链接
class VideoLink {
  final String videoId;
  final String originalUrl;
  final String title;
  final String channelName;
  final String thumbnail;
  final bool playable;
  final String? embedUrl;
  final String? error;

  VideoLink({
    required this.videoId,
    required this.originalUrl,
    required this.title,
    required this.channelName,
    required this.thumbnail,
    required this.playable,
    this.embedUrl,
    this.error,
  });

  factory VideoLink.fromJson(Map<String, dynamic> json) => VideoLink(
    videoId: json['videoId'] ?? '',
    originalUrl: json['originalUrl'] ?? '',
    title: json['title'] ?? '',
    channelName: json['channelName'] ?? '',
    thumbnail: json['thumbnail'] ?? '',
    playable: json['playable'] ?? false,
    embedUrl: json['embedUrl'],
    error: json['error'],
  );
}

/// AI 聊天响应
class AIChatResponse {
  final String id;
  final String content;
  final List<MovieRecommendation>? recommendations;
  final List<YouTubeVideo>? youtubeVideos;
  final List<VideoLink>? videoLinks;
  final String? type;
  final String? error;
  final String? errorDetails;

  AIChatResponse({
    required this.id,
    required this.content,
    this.recommendations,
    this.youtubeVideos,
    this.videoLinks,
    this.type,
    this.error,
    this.errorDetails,
  });

  bool get hasError => error != null;

  factory AIChatResponse.fromJson(Map<String, dynamic> json) {
    List<MovieRecommendation>? recommendations;
    if (json['recommendations'] != null) {
      recommendations = (json['recommendations'] as List)
          .map((e) => MovieRecommendation.fromJson(e))
          .toList();
    }

    List<YouTubeVideo>? youtubeVideos;
    if (json['youtubeVideos'] != null) {
      youtubeVideos = (json['youtubeVideos'] as List)
          .map((e) => YouTubeVideo.fromJson(e))
          .toList();
    }

    List<VideoLink>? videoLinks;
    if (json['videoLinks'] != null) {
      videoLinks = (json['videoLinks'] as List)
          .map((e) => VideoLink.fromJson(e))
          .toList();
    }

    String content = '';
    if (json['choices'] != null && (json['choices'] as List).isNotEmpty) {
      content = json['choices'][0]['message']?['content'] ?? '';
    }

    return AIChatResponse(
      id: json['id'] ?? 'chatcmpl-${DateTime.now().millisecondsSinceEpoch}',
      content: content,
      recommendations: recommendations,
      youtubeVideos: youtubeVideos,
      videoLinks: videoLinks,
      type: json['type'],
      error: json['error'],
      errorDetails: json['details'],
    );
  }

  factory AIChatResponse.error(String message, {String? details}) => AIChatResponse(
    id: 'error-${DateTime.now().millisecondsSinceEpoch}',
    content: '',
    error: message,
    errorDetails: details,
  );
}

/// 视频上下文（用于 AI 问片）
class VideoContext {
  final String? title;
  final String? year;
  final int? doubanId;
  final int? tmdbId;
  final String? type; // 'movie' | 'tv'
  final int? currentEpisode;

  VideoContext({
    this.title,
    this.year,
    this.doubanId,
    this.tmdbId,
    this.type,
    this.currentEpisode,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (title != null) map['title'] = title;
    if (year != null) map['year'] = year;
    if (doubanId != null) map['douban_id'] = doubanId;
    if (tmdbId != null) map['tmdb_id'] = tmdbId;
    if (type != null) map['type'] = type;
    if (currentEpisode != null) map['currentEpisode'] = currentEpisode;
    return map;
  }
}

/// AI 推荐预设问题
class AIRecommendPreset {
  final String title;
  final String message;

  const AIRecommendPreset({
    required this.title,
    required this.message,
  });
}

/// AI 推荐服务
class AIRecommendService {
  static final Dio _dio = Dio();
  
  static const List<AIRecommendPreset> presets = [
    AIRecommendPreset(
      title: '🎬 推荐热门电影',
      message: '请推荐几部最近的热门电影，包括不同类型的，请直接列出片名',
    ),
    AIRecommendPreset(
      title: '📺 推荐电视剧',
      message: '推荐一些口碑很好的电视剧，最好是最近几年的，请直接列出剧名',
    ),
    AIRecommendPreset(
      title: '😂 推荐喜剧片',
      message: '推荐几部搞笑的喜剧电影，能让人开心的那种，请直接列出片名',
    ),
    AIRecommendPreset(
      title: '🔥 推荐动作片',
      message: '推荐一些精彩的动作电影，场面要刺激的，请直接列出片名',
    ),
    AIRecommendPreset(
      title: '💕 推荐爱情片',
      message: '推荐几部经典的爱情电影，要感人的，请直接列出片名',
    ),
    AIRecommendPreset(
      title: '🔍 推荐悬疑片',
      message: '推荐一些烧脑的悬疑推理电影，请直接列出片名',
    ),
    AIRecommendPreset(
      title: '🌟 推荐经典老片',
      message: '推荐一些经典的老电影，值得收藏的那种，请直接列出片名',
    ),
    AIRecommendPreset(
      title: '🎭 推荐综艺节目',
      message: '推荐一些好看的综艺节目，要有趣的，请直接列出节目名',
    ),
  ];

  /// 检查 AI 推荐功能是否可用
  static Future<bool> checkAvailable() async {
    try {
      final serverUrl = await UserDataService.getServerUrl();
      final cookies = await UserDataService.getCookies();

      if (serverUrl == null || serverUrl.isEmpty) {
        return false;
      }

      final response = await _dio.post(
        '$serverUrl/api/ai-recommend',
        data: {
          'messages': [{'role': 'user', 'content': '测试'}],
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            if (cookies != null && cookies.isNotEmpty) 'Cookie': cookies,
          },
          validateStatus: (status) => true, // 接受所有状态码
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      // 403 表示功能未启用或无权限
      if (response.statusCode == 403) {
        return false;
      }

      // 401 表示需要登录但功能可用
      if (response.statusCode == 401) {
        return true;
      }

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[AIRecommendService] 检查可用性失败: $e');
      return false;
    }
  }

  /// 发送 AI 推荐消息（支持流式响应）
  static Future<AIChatResponse> sendMessage({
    required List<AIMessage> messages,
    VideoContext? context,
    Function(String chunk)? onStream,
  }) async {
    try {
      final serverUrl = await UserDataService.getServerUrl();
      final cookies = await UserDataService.getCookies();

      if (serverUrl == null || serverUrl.isEmpty) {
        return AIChatResponse.error('服务器地址未配置');
      }

      final requestBody = {
        'messages': messages.map((m) => m.toJson()).toList(),
        if (context != null) 'context': context.toJson(),
        'stream': onStream != null,
      };

      // 流式响应处理 - 使用原生 HttpClient 以支持真正的流式传输
      if (onStream != null) {
        String fullContent = '';
        List<YouTubeVideo> youtubeVideos = [];
        List<VideoLink> videoLinks = [];
        String buffer = '';

        debugPrint('[AIRecommendService] 开始流式请求...');

        final httpClient = HttpClient();
        httpClient.connectionTimeout = const Duration(seconds: 30);
        httpClient.autoUncompress = false; // 禁用自动解压，避免缓冲
        
        try {
          final uri = Uri.parse('$serverUrl/api/ai-recommend');
          final request = await httpClient.postUrl(uri);
          
          // 设置请求头
          request.headers.set('Content-Type', 'application/json');
          request.headers.set('Accept', 'text/event-stream');
          request.headers.set('Cache-Control', 'no-cache');
          if (cookies != null && cookies.isNotEmpty) {
            request.headers.set('Cookie', cookies);
          }
          
          // 写入请求体
          request.write(jsonEncode(requestBody));
          
          // 发送请求并获取响应
          final response = await request.close();
          
          debugPrint('[AIRecommendService] 响应状态码: ${response.statusCode}');
          debugPrint('[AIRecommendService] 响应头: ${response.headers}');

          if (response.statusCode == 401) {
            httpClient.close();
            return AIChatResponse.error('请先登录');
          }

          if (response.statusCode == 403) {
            final body = await response.transform(utf8.decoder).join();
            httpClient.close();
            try {
              final json = jsonDecode(body);
              return AIChatResponse.error(
                json['error'] ?? 'AI推荐功能未启用或无权限',
                details: json['details'],
              );
            } catch (_) {
              return AIChatResponse.error('AI推荐功能未启用或无权限');
            }
          }

          if (response.statusCode != 200) {
            final body = await response.transform(utf8.decoder).join();
            httpClient.close();
            try {
              final json = jsonDecode(body);
              return AIChatResponse.error(
                json['error'] ?? '请求失败',
                details: json['details'],
              );
            } catch (_) {
              return AIChatResponse.error('请求失败: ${response.statusCode}');
            }
          }

          // 处理 SSE 流
          await for (final chunk in response.transform(utf8.decoder)) {
            buffer += chunk;
            
            // 按换行符分割，处理完整的行
            while (buffer.contains('\n')) {
              final newlineIndex = buffer.indexOf('\n');
              final line = buffer.substring(0, newlineIndex).trim();
              buffer = buffer.substring(newlineIndex + 1);
              
              if (line.isEmpty) continue;
              
              if (line.startsWith('data: ')) {
                final data = line.substring(6);

                if (data == '[DONE]') {
                  debugPrint('[AIRecommendService] 流式响应完成');
                  continue;
                }

                try {
                  final json = jsonDecode(data);

                  // 处理文本流
                  if (json['text'] != null) {
                    final text = json['text'] as String;
                    fullContent += text;
                    onStream(text);
                  }

                  // 处理 YouTube 视频数据
                  if (json['type'] == 'youtube_data' && json['youtubeVideos'] != null) {
                    youtubeVideos = (json['youtubeVideos'] as List)
                        .map((e) => YouTubeVideo.fromJson(e))
                        .toList();
                    debugPrint('[AIRecommendService] 收到YouTube视频: ${youtubeVideos.length}');
                  }

                  // 处理视频链接数据
                  if (json['type'] == 'video_links' && json['videoLinks'] != null) {
                    videoLinks = (json['videoLinks'] as List)
                        .map((e) => VideoLink.fromJson(e))
                        .toList();
                    debugPrint('[AIRecommendService] 收到视频链接: ${videoLinks.length}');
                  }
                } catch (e) {
                  debugPrint('[AIRecommendService] 解析 SSE 数据失败: $e');
                }
              }
            }
          }

          httpClient.close();
          debugPrint('[AIRecommendService] 流式响应处理完成，总内容长度: ${fullContent.length}');

          return AIChatResponse(
            id: 'stream-${DateTime.now().millisecondsSinceEpoch}',
            content: fullContent,
            youtubeVideos: youtubeVideos.isNotEmpty ? youtubeVideos : null,
            videoLinks: videoLinks.isNotEmpty ? videoLinks : null,
          );
        } catch (e) {
          httpClient.close();
          debugPrint('[AIRecommendService] 流式请求失败: $e');
          return AIChatResponse.error('网络错误: $e');
        }
      }

      // 非流式响应
      final response = await _dio.post(
        '$serverUrl/api/ai-recommend',
        data: requestBody,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            if (cookies != null && cookies.isNotEmpty) 'Cookie': cookies,
          },
          validateStatus: (status) => true,
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 401) {
        return AIChatResponse.error('请先登录');
      }

      if (response.statusCode == 403) {
        return AIChatResponse.error(
          response.data['error'] ?? 'AI推荐功能未启用或无权限',
          details: response.data['details'],
        );
      }

      if (response.statusCode != 200) {
        return AIChatResponse.error(
          response.data['error'] ?? '请求失败',
          details: response.data['details'],
        );
      }

      return AIChatResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('[AIRecommendService] Dio异常: $e');
      if (e.type == DioExceptionType.receiveTimeout || 
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.connectionTimeout) {
        return AIChatResponse.error('请求超时，请稍后重试');
      }
      return AIChatResponse.error('网络错误: ${e.message}');
    } catch (e) {
      debugPrint('[AIRecommendService] 发送消息失败: $e');
      return AIChatResponse.error('网络错误: $e');
    }
  }

  /// 从 AI 回复中提取影片标题
  static List<String> extractMovieTitles(String content) {
    final titles = <String>{};

    // 匹配《片名》格式
    final pattern1 = RegExp(r'《([^》]+)》');
    for (final match in pattern1.allMatches(content)) {
      final title = match.group(1)?.trim();
      if (title != null && title.length > 1 && title.length < 50) {
        titles.add(title);
      }
    }

    // 匹配【片名】格式
    final pattern2 = RegExp(r'【([^】]+)】');
    for (final match in pattern2.allMatches(content)) {
      final title = match.group(1)?.trim();
      if (title != null && title.length > 1 && title.length < 50) {
        titles.add(title);
      }
    }

    return titles.toList();
  }

  /// 清理片名中的特殊字符
  static String cleanMovieTitle(String title) {
    return title
        .replaceAll(RegExp(r'（.*?）'), '') // 移除中文括号内容
        .replaceAll(RegExp(r'\(.*?\)'), '') // 移除英文括号内容
        .replaceAll(RegExp(r'\d{4}年?'), '') // 移除年份
        .replaceAll(RegExp(r'第\d+季'), '') // 移除季数
        .replaceAll(RegExp(r'\s+'), ' ') // 多个空格合并为一个
        .trim();
  }

  /// 生成对话摘要
  static String generateChatSummary(List<AIMessage> messages) {
    final userMessages = messages.where((m) => m.role == 'user').toList();
    if (userMessages.isEmpty) return '新对话';

    final firstUserMessage = userMessages.first.content;
    if (firstUserMessage.length <= 20) {
      return firstUserMessage;
    }

    return '${firstUserMessage.substring(0, 17)}...';
  }
}
