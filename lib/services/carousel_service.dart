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
        final detailsFutures = movies.map((movie) => _getDoubanDetails(context, movie.id));
        final detailsList = await Future.wait(detailsFutures);
        
        for (int i = 0; i < movies.length; i++) {
          final movie = movies[i];
          final details = detailsList[i];
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
    // 方案1：尝试通过后端API获取（包含backdrop和trailerUrl）
    try {
      final serverUrl = await UserDataService.getServerUrl();
      if (serverUrl != null && serverUrl.isNotEmpty) {
        final url = '$serverUrl/api/douban/details?id=$doubanId';
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['code'] == 200 && data['data'] != null) {
            final detailData = data['data'];
            final backdrop = detailData['backdrop'] as String?;
            final plotSummary = detailData['plot_summary'] as String?;
            final trailerUrl = detailData['trailerUrl'] as String?;
            
            // 如果后端返回了有效数据，直接使用
            if (backdrop != null || plotSummary != null || trailerUrl != null) {
              return {
                'backdrop': backdrop,
                'plot_summary': plotSummary,
                'trailerUrl': trailerUrl,
              };
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[CarouselService] 后端API获取详情失败: $doubanId - $e');
    }
    
    // 方案2：使用本地DoubanService作为备用（只能获取summary，没有backdrop和trailerUrl）
    try {
      final result = await DoubanService.getDoubanDetails(context, doubanId: doubanId);
      if (result.success && result.data != null) {
        return {
          'backdrop': null, // 本地方法无法获取backdrop
          'plot_summary': result.data!.summary,
          'trailerUrl': null, // 本地方法无法获取trailerUrl
        };
      }
    } catch (e) {
      debugPrint('[CarouselService] 本地获取详情失败: $doubanId - $e');
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
