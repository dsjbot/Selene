import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/search_result.dart';
import 'api_service.dart';
import 'downstream_service.dart';
import '../services/user_data_service.dart';
import '../services/local_mode_storage_service.dart';

/// 搜索服务
class SearchService {
  /// 同步搜索（本地搜索）
  /// 并发调用所有资源的搜索，返回所有结果
  static Future<List<SearchResult>> searchSync(String query) async {
    try {
      // 检查是否是本地模式
      final isLocalMode = await UserDataService.getIsLocalMode();

      // 获取搜索资源列表
      final allResources = isLocalMode
          ? await LocalModeStorageService.getSubscriptionContent()
          : await ApiService.getSearchResources();

      // 过滤掉被禁用的资源
      final resources =
          allResources.where((resource) => !resource.disabled).toList();

      if (resources.isEmpty) {
        return [];
      }

      // 并发调用所有资源的搜索，每个调用增加 20 秒超时
      final searchFutures = resources.map((resource) {
        return DownstreamService.searchFromApi(resource, query)
            .timeout(const Duration(seconds: 20))
            .catchError((error) {
          // 捕获错误，返回空列表
          return <SearchResult>[];
        });
      }).toList();

      // 等待所有搜索完成
      final allResults = await Future.wait(searchFutures);

      // 按照 resources 的顺序合并结果（allResults 的顺序与 resources 一致）
      final results = <SearchResult>[];
      for (int i = 0; i < allResults.length; i++) {
        if (allResults[i].isNotEmpty) {
          results.addAll(allResults[i]);
        }
      }

      return results;
    } catch (e) {
      return [];
    }
  }

  /// 获取视频详情（本地直接调用下游API）
  static Future<List<SearchResult>> getDetailSync(
      String source, String id) async {
    try {
      // 检查是否是本地模式
      final isLocalMode = await UserDataService.getIsLocalMode();

      // 获取搜索资源列表
      final allResources = isLocalMode
          ? await LocalModeStorageService.getSubscriptionContent()
          : await ApiService.getSearchResources();

      // 找到对应 source 的资源
      final apiSite = allResources.firstWhere(
        (resource) => resource.key == source,
        orElse: () => throw Exception('未找到对应的源: $source'),
      );

      // 如果 detail 不为空，使用特殊源处理
      if (apiSite.detail.isNotEmpty) {
        final result = await _handleSpecialSourceDetail(id, apiSite);
        return [result];
      }

      // 构建详情请求 URL
      final detailUrl = '${apiSite.api}?ac=videolist&ids=$id';

      // 发起请求，设置 10 秒超时
      final response = await http.get(
        Uri.parse(detailUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('详情请求失败: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      if (data == null ||
          data['list'] == null ||
          data['list'] is! List ||
          (data['list'] as List).isEmpty) {
        throw Exception('获取到的详情内容无效');
      }

      final videoDetail = data['list'][0];
      List<String> episodes = [];
      List<String> titles = [];

      // 处理播放源拆分
      if (videoDetail['vod_play_url'] != null) {
        // 先用 $$$ 分割
        final vodPlayUrlArray =
            (videoDetail['vod_play_url'] as String).split('\$\$\$');

        // 分集之间 # 分割，标题和播放链接 $ 分割
        for (final url in vodPlayUrlArray) {
          List<String> matchEpisodes = [];
          List<String> matchTitles = [];

          final titleUrlArray = url.split('#');

          for (final titleUrl in titleUrlArray) {
            final episodeTitleUrl = titleUrl.split('\$');
            if (episodeTitleUrl.length == 2 &&
                episodeTitleUrl[1].endsWith('.m3u8')) {
              matchTitles.add(episodeTitleUrl[0]);
              matchEpisodes.add(episodeTitleUrl[1]);
            }
          }

          if (matchEpisodes.length > episodes.length) {
            episodes = matchEpisodes;
            titles = matchTitles;
          }
        }
      }

      // 如果播放源为空，则尝试从内容中解析 m3u8
      if (episodes.isEmpty && videoDetail['vod_content'] != null) {
        final m3u8Pattern = RegExp(r'https?://[^\s<>"]+\.m3u8');
        final matches =
            m3u8Pattern.allMatches(videoDetail['vod_content'] as String);
        episodes = matches.map((match) => match.group(0)!).toList();
      }

      // 解析年份
      String year = 'unknown';
      if (videoDetail['vod_year'] != null && videoDetail['vod_year'] != '') {
        final yearMatch =
            RegExp(r'\d{4}').firstMatch(videoDetail['vod_year'] as String);
        if (yearMatch != null) {
          year = yearMatch.group(0)!;
        }
      }

      final result = SearchResult(
        id: id,
        title: videoDetail['vod_name'] ?? '',
        poster: videoDetail['vod_pic'] ?? '',
        episodes: episodes,
        episodesTitles: titles,
        source: apiSite.key,
        sourceName: apiSite.name,
        class_: videoDetail['vod_class'],
        year: year,
        desc: _cleanHtmlTags(videoDetail['vod_content'] ?? ''),
        typeName: videoDetail['type_name'],
        doubanId: videoDetail['vod_douban_id'],
      );

      return [result];
    } catch (e) {
      return [];
    }
  }

  /// 处理特殊源的详情（通过 HTML 页面解析）
  static Future<SearchResult> _handleSpecialSourceDetail(
      String id, dynamic apiSite) async {
    final detailUrl = '${apiSite.detail}/index.php/vod/detail/id/$id.html';

    // 发起请求，设置 10 秒超时
    final response = await http.get(
      Uri.parse(detailUrl),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        'Accept': 'text/html',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('详情页请求失败: ${response.statusCode}');
    }

    final html = response.body;
    List<String> matches = [];

    // 如果是 ffzy 源，使用特殊的正则表达式
    if (apiSite.key == 'ffzy') {
      final ffzyPattern =
          RegExp(r'\$(https?://[^"\x27\s]+?/\d{8}/\d+_[a-f0-9]+/index\.m3u8)');
      matches =
          ffzyPattern.allMatches(html).map((match) => match.group(0)!).toList();
    }

    // 如果没有匹配到，使用通用的正则表达式
    if (matches.isEmpty) {
      final generalPattern = RegExp(r'\$(https?://[^"\x27\s]+?\.m3u8)');
      matches = generalPattern
          .allMatches(html)
          .map((match) => match.group(0)!)
          .toList();
    }

    // 去重并清理链接前缀
    final uniqueMatches = matches.toSet().toList();
    final episodes = uniqueMatches.map((link) {
      // 去掉开头的 $
      link = link.substring(1);
      // 去掉可能的括号后缀
      final parenIndex = link.indexOf('(');
      return parenIndex > 0 ? link.substring(0, parenIndex) : link;
    }).toList();

    // 根据 episodes 数量生成剧集标题
    final episodesTitles =
        List.generate(episodes.length, (i) => (i + 1).toString());

    // 提取标题
    final titleMatch = RegExp(r'<h1[^>]*>([^<]+)</h1>').firstMatch(html);
    final titleText = titleMatch != null ? titleMatch.group(1)!.trim() : '';

    // 提取描述
    final descMatch =
        RegExp(r'<div[^>]*class=["\x27]sketch["\x27][^>]*>([\s\S]*?)</div>')
            .firstMatch(html);
    final descText =
        descMatch != null ? _cleanHtmlTags(descMatch.group(1)!) : '';

    // 提取封面
    final coverMatches =
        RegExp(r'(https?://[^"\x27\s]+?\.jpg)').allMatches(html);
    final coverUrl =
        coverMatches.isNotEmpty ? coverMatches.first.group(0)!.trim() : '';

    // 提取年份
    final yearMatch = RegExp(r'>(\d{4})<').firstMatch(html);
    final yearText = yearMatch != null ? yearMatch.group(1)! : 'unknown';

    return SearchResult(
      id: id,
      title: titleText,
      poster: coverUrl,
      episodes: episodes,
      episodesTitles: episodesTitles,
      source: apiSite.key,
      sourceName: apiSite.name,
      class_: '',
      year: yearText,
      desc: descText,
      typeName: '',
      doubanId: 0,
    );
  }

  /// 清理 HTML 标签
  static String _cleanHtmlTags(String text) {
    if (text.isEmpty) return '';

    String cleanedText = text
        .replaceAll(RegExp(r'<[^>]+>'), '\n')
        .replaceAll(RegExp(r'\n+'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'^\n+|\n+$'), '')
        .trim();

    return _decodeHtmlEntities(cleanedText);
  }

  /// 解码 HTML 实体
  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }
}
