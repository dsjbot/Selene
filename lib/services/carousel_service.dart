import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/douban_movie.dart';
import '../widgets/hero_carousel.dart';
import 'douban_service.dart';
import 'user_data_service.dart';

/// 轮播图数据服务
class CarouselService {
  static const String _cacheKey = 'carousel_items_cache';
  static const String _cacheTimeKey = 'carousel_items_cache_time';
  static const Duration _cacheDuration = Duration(hours: 1); // 缓存1小时
  
  // 内存缓存
  static List<CarouselItem>? _memoryCache;
  static DateTime? _memoryCacheTime;
  
  /// 获取轮播图数据（带缓存）
  /// 从热门电影、剧集、综艺、动漫中获取数据，并获取详情（背景图、简介、预告片）
  static Future<List<CarouselItem>> getCarouselItems(BuildContext context, {bool forceRefresh = false}) async {
    // 1. 如果不强制刷新，先尝试从内存缓存获取
    if (!forceRefresh && _memoryCache != null && _memoryCacheTime != null) {
      if (DateTime.now().difference(_memoryCacheTime!) < _cacheDuration) {
        debugPrint('[CarouselService] 使用内存缓存，共 ${_memoryCache!.length} 项');
        return _memoryCache!;
      }
    }
    
    // 2. 如果不强制刷新，尝试从本地存储获取缓存
    if (!forceRefresh) {
      final cachedItems = await _loadFromCache();
      if (cachedItems != null && cachedItems.isNotEmpty) {
        debugPrint('[CarouselService] 使用本地缓存，共 ${cachedItems.length} 项');
        _memoryCache = cachedItems;
        _memoryCacheTime = DateTime.now();
        return cachedItems;
      }
    }
    
    // 3. 从网络获取数据
    final items = await _fetchFromNetwork(context);
    
    // 4. 保存到缓存
    if (items.isNotEmpty) {
      _memoryCache = items;
      _memoryCacheTime = DateTime.now();
      await _saveToCache(items);
    }
    
    return items;
  }
  
  /// 清除缓存
  static Future<void> clearCache() async {
    _memoryCache = null;
    _memoryCacheTime = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTimeKey);
    debugPrint('[CarouselService] 缓存已清除');
  }
  
  /// 从本地存储加载缓存
  static Future<List<CarouselItem>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheTimeStr = prefs.getString(_cacheTimeKey);
      
      if (cacheTimeStr == null) return null;
      
      final cacheTime = DateTime.tryParse(cacheTimeStr);
      if (cacheTime == null) return null;
      
      // 检查缓存是否过期
      if (DateTime.now().difference(cacheTime) > _cacheDuration) {
        debugPrint('[CarouselService] 本地缓存已过期');
        return null;
      }
      
      final cacheJson = prefs.getString(_cacheKey);
      if (cacheJson == null) return null;
      
      final List<dynamic> jsonList = json.decode(cacheJson);
      return jsonList.map((item) => CarouselItem(
        id: item['id'] as String,
        title: item['title'] as String,
        poster: item['poster'] as String,
        backdrop: item['backdrop'] as String?,
        description: item['description'] as String?,
        trailerUrl: item['trailerUrl'] as String?,
        year: item['year'] as String?,
        rate: item['rate'] as String?,
        type: item['type'] as String,
      )).toList();
    } catch (e) {
      debugPrint('[CarouselService] 加载缓存失败: $e');
      return null;
    }
  }
  
  /// 保存到本地存储
  static Future<void> _saveToCache(List<CarouselItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final jsonList = items.map((item) => {
        'id': item.id,
        'title': item.title,
        'poster': item.poster,
        'backdrop': item.backdrop,
        'description': item.description,
        'trailerUrl': item.trailerUrl,
        'year': item.year,
        'rate': item.rate,
        'type': item.type,
      }).toList();
      
      await prefs.setString(_cacheKey, json.encode(jsonList));
      await prefs.setString(_cacheTimeKey, DateTime.now().toIso8601String());
      debugPrint('[CarouselService] 缓存已保存，共 ${items.length} 项');
    } catch (e) {
      debugPrint('[CarouselService] 保存缓存失败: $e');
    }
  }
  
  /// 从网络获取数据
  static Future<List<CarouselItem>> _fetchFromNetwork(BuildContext context) async {
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
    String? backdrop;
    String? plotSummary;
    String? trailerUrl;
    
    // 方案1：尝试通过后端API获取（包含backdrop和trailerUrl）
    try {
      final serverUrl = await UserDataService.getServerUrl();
      final cookies = await UserDataService.getCookies();
      
      if (serverUrl != null && serverUrl.isNotEmpty) {
        final url = '$serverUrl/api/douban/details?id=$doubanId';
        
        // 构建请求头，包含认证 cookies
        final headers = <String, String>{
          'Accept': 'application/json',
        };
        if (cookies != null && cookies.isNotEmpty) {
          headers['Cookie'] = cookies;
        }
        
        final response = await http.get(
          Uri.parse(url),
          headers: headers,
        ).timeout(const Duration(seconds: 15));
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          
          if (data['code'] == 200 && data['data'] != null) {
            final detailData = data['data'];
            backdrop = detailData['backdrop'] as String?;
            plotSummary = detailData['plot_summary'] as String?;
            trailerUrl = detailData['trailerUrl'] as String?;
            
            // 过滤空字符串
            if (backdrop != null && backdrop.isEmpty) backdrop = null;
            if (plotSummary != null && plotSummary.isEmpty) plotSummary = null;
            if (trailerUrl != null && trailerUrl.isEmpty) trailerUrl = null;
          }
        }
      }
    } catch (e) {
      debugPrint('[CarouselService] 后端API获取详情失败: $doubanId - $e');
    }
    
    // 方案2：如果后端没有返回summary，使用本地DoubanService作为备用
    if (plotSummary == null) {
      try {
        final result = await DoubanService.getDoubanDetails(context, doubanId: doubanId);
        if (result.success && result.data != null) {
          final localSummary = result.data!.summary;
          if (localSummary != null && localSummary.isNotEmpty) {
            plotSummary = localSummary;
          }
        }
      } catch (e) {
        debugPrint('[CarouselService] 本地获取详情失败: $doubanId - $e');
      }
    }
    
    // 返回结果
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
