import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/douban_movie.dart';
import '../widgets/hero_carousel.dart';
import 'douban_service.dart';
import 'user_data_service.dart';

/// 轮播图数据服务
class CarouselService {
  /// 获取轮播图数据
  /// 从热门电影、剧集、综艺、动漫中获取数据，并获取详情（背景图、简介、预告片）
  static Future<List<CarouselItem>> getCarouselItems(BuildContext context) async {
    final List<CarouselItem> items = [];

    try {
      // 并行获取热门电影、剧集、综艺、动漫数据（与后端保持一致的分类参数）
      final results = await Future.wait([
        DoubanService.getCategoryData(context, kind: 'movie', category: '热门', type: '全部', pageLimit: 5),
        DoubanService.getCategoryData(context, kind: 'tv', category: 'tv', type: 'tv', pageLimit: 5),
        DoubanService.getCategoryData(context, kind: 'tv', category: 'show', type: 'show', pageLimit: 3),
        DoubanService.getCategoryData(context, kind: 'tv', category: 'tv', type: 'tv_animation', pageLimit: 3),
      ]);

      final moviesResult = results[0];
      final tvShowsResult = results[1];
      final showsResult = results[2];
      final animeResult = results[3];

      // 处理电影数据（取前3个）- 立即获取详情
      if (moviesResult.success && moviesResult.data != null) {
        final movies = moviesResult.data!.take(3).toList();
        debugPrint('[CarouselService] 电影数据: ${movies.map((m) => "${m.title}(${m.id})").join(", ")}');
        final detailsFutures = movies.map((movie) => _getDoubanDetails(context, movie.id));
        final detailsList = await Future.wait(detailsFutures);
        
        for (int i = 0; i < movies.length; i++) {
          final movie = movies[i];
          final details = detailsList[i];
          debugPrint('[CarouselService] 添加电影: ${movie.title}, trailerUrl: ${details?['trailerUrl']}');
          items.add(CarouselItem(
            id: movie.id,
            title: movie.title,
            poster: movie.poster,
            backdrop: details?['backdrop'] ?? _getHDPoster(movie.poster),
            description: details?['plot_summary'],
            trailerUrl: details?['trailerUrl'],
            year: movie.year,
            rate: movie.rate,
            type: 'movie',
          ));
        }
      }

      // 处理剧集数据（取前3个）
      if (tvShowsResult.success && tvShowsResult.data != null) {
        final tvShows = tvShowsResult.data!.take(3).toList();
        final detailsFutures = tvShows.map((show) => _getDoubanDetails(context, show.id));
        final detailsList = await Future.wait(detailsFutures);
        
        for (int i = 0; i < tvShows.length; i++) {
          final show = tvShows[i];
          final details = detailsList[i];
          items.add(CarouselItem(
            id: show.id,
            title: show.title,
            poster: show.poster,
            backdrop: details?['backdrop'] ?? _getHDPoster(show.poster),
            description: details?['plot_summary'],
            trailerUrl: details?['trailerUrl'],
            year: show.year,
            rate: show.rate,
            type: 'tv',
          ));
        }
      }

      // 处理综艺数据（取前2个）
      if (showsResult.success && showsResult.data != null) {
        final shows = showsResult.data!.take(2).toList();
        final detailsFutures = shows.map((show) => _getDoubanDetails(context, show.id));
        final detailsList = await Future.wait(detailsFutures);
        
        for (int i = 0; i < shows.length; i++) {
          final show = shows[i];
          final details = detailsList[i];
          items.add(CarouselItem(
            id: show.id,
            title: show.title,
            poster: show.poster,
            backdrop: details?['backdrop'] ?? _getHDPoster(show.poster),
            description: details?['plot_summary'],
            trailerUrl: details?['trailerUrl'],
            year: show.year,
            rate: show.rate,
            type: 'variety',
          ));
        }
      }

      // 处理动漫数据（取前2个）
      if (animeResult.success && animeResult.data != null) {
        final animes = animeResult.data!.take(2).toList();
        final detailsFutures = animes.map((anime) => _getDoubanDetails(context, anime.id));
        final detailsList = await Future.wait(detailsFutures);
        
        for (int i = 0; i < animes.length; i++) {
          final anime = animes[i];
          final details = detailsList[i];
          items.add(CarouselItem(
            id: anime.id,
            title: anime.title,
            poster: anime.poster,
            backdrop: details?['backdrop'] ?? _getHDPoster(anime.poster),
            description: details?['plot_summary'],
            trailerUrl: details?['trailerUrl'],
            year: anime.year,
            rate: anime.rate,
            type: 'anime',
          ));
        }
      }
    } catch (e) {
      debugPrint('[CarouselService] 获取轮播图数据失败: $e');
    }

    return items;
  }

  /// 获取豆瓣详情（背景图、简介、预告片）
  /// 优先通过后端API获取，失败则使用本地DoubanService作为备用
  static Future<Map<String, String?>?> _getDoubanDetails(BuildContext context, String doubanId) async {
    String? backdrop;
    String? plotSummary;
    String? trailerUrl;
    
    // 方案1：尝试通过后端API获取（包含backdrop和trailerUrl）
    try {
      final serverUrl = await UserDataService.getServerUrl();
      debugPrint('[CarouselService] 服务器URL: $serverUrl, doubanId: $doubanId');
      
      if (serverUrl != null && serverUrl.isNotEmpty) {
        final url = '$serverUrl/api/douban/details?id=$doubanId';
        debugPrint('[CarouselService] 请求后端API: $url');
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
        
        debugPrint('[CarouselService] 后端API响应状态: ${response.statusCode}');
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          debugPrint('[CarouselService] 后端API响应code: ${data['code']}');
          
          if (data['code'] == 200 && data['data'] != null) {
            final detailData = data['data'];
            backdrop = detailData['backdrop'] as String?;
            plotSummary = detailData['plot_summary'] as String?;
            trailerUrl = detailData['trailerUrl'] as String?;
            
            // 过滤空字符串
            if (backdrop != null && backdrop.isEmpty) backdrop = null;
            if (plotSummary != null && plotSummary.isEmpty) plotSummary = null;
            if (trailerUrl != null && trailerUrl.isEmpty) trailerUrl = null;
            
            debugPrint('[CarouselService] 后端返回 $doubanId:');
            debugPrint('  - backdrop: ${backdrop != null ? "有" : "无"}');
            debugPrint('  - summary: ${plotSummary != null ? "有(${plotSummary.length}字)" : "无"}');
            debugPrint('  - trailerUrl: ${trailerUrl ?? "无"}');
          } else {
            debugPrint('[CarouselService] 后端返回code不是200或data为null');
          }
        } else {
          debugPrint('[CarouselService] 后端API响应非200: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
        }
      } else {
        debugPrint('[CarouselService] 服务器URL为空，跳过后端API');
      }
    } catch (e) {
      debugPrint('[CarouselService] 后端API获取详情失败: $doubanId - $e');
    }
    
    // 方案2：如果后端没有返回summary，使用本地DoubanService作为备用
    if (plotSummary == null) {
      try {
        debugPrint('[CarouselService] 尝试本地DoubanService获取详情: $doubanId');
        final result = await DoubanService.getDoubanDetails(context, doubanId: doubanId);
        if (result.success && result.data != null) {
          final localSummary = result.data!.summary;
          if (localSummary != null && localSummary.isNotEmpty) {
            plotSummary = localSummary;
            debugPrint('[CarouselService] 本地获取成功: $doubanId - summary长度: ${plotSummary.length}');
          }
        }
      } catch (e) {
        debugPrint('[CarouselService] 本地获取详情失败: $doubanId - $e');
      }
    }
    
    // 返回结果
    debugPrint('[CarouselService] 最终返回 $doubanId - backdrop: ${backdrop != null}, summary: ${plotSummary != null}, trailer: ${trailerUrl != null}');
    
    if (backdrop != null || plotSummary != null || trailerUrl != null) {
      return {
        'backdrop': backdrop,
        'plot_summary': plotSummary,
        'trailerUrl': trailerUrl,
      };
    }
    
    return null;
  }

  /// 将豆瓣海报URL转换为高清版本
  static String _getHDPoster(String url) {
    return url
        .replaceAll('/view/photo/s/', '/view/photo/l/')
        .replaceAll('/view/photo/m/', '/view/photo/l/')
        .replaceAll('/view/photo/sqxs/', '/view/photo/l/')
        .replaceAll('/s_ratio_poster/', '/l_ratio_poster/')
        .replaceAll('/m_ratio_poster/', '/l_ratio_poster/');
  }
}
