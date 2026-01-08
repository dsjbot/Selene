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
  /// 从热门电影、剧集、综艺中获取数据，并尝试获取高清背景图
  static Future<List<CarouselItem>> getCarouselItems(BuildContext context) async {
    final List<CarouselItem> items = [];

    try {
      // 并行获取热门电影、剧集、综艺数据
      final results = await Future.wait([
        DoubanService.getHotMovies(context, pageLimit: 5),
        DoubanService.getHotTvShows(context, pageLimit: 5),
        DoubanService.getHotShows(context, pageLimit: 3),
      ]);

      final moviesResult = results[0];
      final tvShowsResult = results[1];
      final showsResult = results[2];

      // 处理电影数据（取前3个）
      if (moviesResult.success && moviesResult.data != null) {
        final movies = moviesResult.data!.take(3).toList();
        for (final movie in movies) {
          final backdrop = await _getBackdropImage(movie.title, movie.year, 'movie');
          items.add(CarouselItem(
            id: movie.id,
            title: movie.title,
            poster: movie.poster,
            backdrop: backdrop ?? _getHDPoster(movie.poster),
            year: movie.year,
            rate: movie.rate,
            type: 'movie',
          ));
        }
      }

      // 处理剧集数据（取前3个）
      if (tvShowsResult.success && tvShowsResult.data != null) {
        final tvShows = tvShowsResult.data!.take(3).toList();
        for (final show in tvShows) {
          final backdrop = await _getBackdropImage(show.title, show.year, 'tv');
          items.add(CarouselItem(
            id: show.id,
            title: show.title,
            poster: show.poster,
            backdrop: backdrop ?? _getHDPoster(show.poster),
            year: show.year,
            rate: show.rate,
            type: 'tv',
          ));
        }
      }

      // 处理综艺数据（取前2个）
      if (showsResult.success && showsResult.data != null) {
        final shows = showsResult.data!.take(2).toList();
        for (final show in shows) {
          final backdrop = await _getBackdropImage(show.title, show.year, 'tv');
          items.add(CarouselItem(
            id: show.id,
            title: show.title,
            poster: show.poster,
            backdrop: backdrop ?? _getHDPoster(show.poster),
            year: show.year,
            rate: show.rate,
            type: 'variety',
          ));
        }
      }
    } catch (e) {
      debugPrint('[CarouselService] 获取轮播图数据失败: $e');
    }

    return items;
  }

  /// 获取TMDB背景图
  static Future<String?> _getBackdropImage(String title, String year, String type) async {
    try {
      final serverUrl = await UserDataService.getServerUrl();
      if (serverUrl == null || serverUrl.isEmpty) return null;
      
      final url = '$serverUrl/api/tmdb/backdrop?title=${Uri.encodeComponent(title)}&year=$year&type=$type';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final backdrop = data['backdrop'] as String?;
        if (backdrop != null && backdrop.isNotEmpty) {
          return backdrop;
        }
      }
    } catch (e) {
      debugPrint('[CarouselService] 获取TMDB背景图失败: $title - $e');
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
