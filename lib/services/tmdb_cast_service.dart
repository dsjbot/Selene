import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'user_data_service.dart';

/// TMDB 演员信息
class TMDBCastMember {
  final int? id;
  final String name;
  final String? photo;
  final String? character;

  TMDBCastMember({
    this.id,
    required this.name,
    this.photo,
    this.character,
  });

  factory TMDBCastMember.fromJson(Map<String, dynamic> json) {
    return TMDBCastMember(
      id: json['id'] as int?,
      name: json['name']?.toString() ?? '',
      photo: json['photo']?.toString(),
      character: json['character']?.toString(),
    );
  }
}

/// TMDB 演员作品
class TMDBActorWork {
  final String id;
  final String title;
  final String poster;
  final String year;
  final String rate;

  TMDBActorWork({
    required this.id,
    required this.title,
    required this.poster,
    required this.year,
    required this.rate,
  });

  factory TMDBActorWork.fromJson(Map<String, dynamic> json) {
    return TMDBActorWork(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      poster: json['poster']?.toString() ?? '',
      year: json['year']?.toString() ?? '',
      rate: json['rate']?.toString() ?? '',
    );
  }
}

/// TMDB 演员服务
class TMDBCastService {
  static const Duration _timeout = Duration(seconds: 15);

  /// 获取演员照片（批量）
  /// [names] 演员名字列表
  /// 返回带有照片的演员列表
  static Future<List<TMDBCastMember>> getCastPhotos(List<String> names) async {
    if (names.isEmpty) return [];

    try {
      final baseUrl = await UserDataService.getServerUrl();
      final cookies = await UserDataService.getCookies();
      
      if (baseUrl == null || baseUrl.isEmpty) {
        debugPrint('[TMDBCastService] 服务器地址未配置');
        return [];
      }

      // 限制最多20个演员
      final limitedNames = names.take(20).toList();
      final namesParam = limitedNames.join(',');

      final response = await http.get(
        Uri.parse('$baseUrl/api/tmdb/cast-photos?names=${Uri.encodeComponent(namesParam)}'),
        headers: {
          'Accept': 'application/json',
          'Cookie': cookies ?? '',
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // 检查是否启用
        if (data['enabled'] != true) {
          debugPrint('[TMDBCastService] TMDB 演员功能未启用');
          return [];
        }

        final actors = data['actors'] as List<dynamic>? ?? [];
        return actors
            .map((a) => TMDBCastMember.fromJson(a as Map<String, dynamic>))
            .where((a) => a.photo != null && a.photo!.isNotEmpty)
            .toList();
      } else {
        debugPrint('[TMDBCastService] 获取演员照片失败: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('[TMDBCastService] 获取演员照片异常: $e');
      return [];
    }
  }

  /// 获取演员作品
  /// [actorName] 演员名字
  /// [type] 作品类型: 'movie' 或 'tv'
  static Future<List<TMDBActorWork>> getActorWorks(
    String actorName, {
    String type = 'tv',
    String sortBy = 'date',
    String sortOrder = 'desc',
    int limit = 50,
  }) async {
    if (actorName.isEmpty) return [];

    try {
      final baseUrl = await UserDataService.getServerUrl();
      final cookies = await UserDataService.getCookies();
      
      if (baseUrl == null || baseUrl.isEmpty) {
        debugPrint('[TMDBCastService] 服务器地址未配置');
        return [];
      }

      final params = {
        'actor': actorName,
        'type': type,
        'sortBy': sortBy,
        'sortOrder': sortOrder,
        'limit': limit.toString(),
      };

      final uri = Uri.parse('$baseUrl/api/tmdb/actor').replace(queryParameters: params);

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Cookie': cookies ?? '',
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['code'] == 200 && data['list'] != null) {
          final list = data['list'] as List<dynamic>;
          return list
              .map((item) => TMDBActorWork.fromJson(item as Map<String, dynamic>))
              .toList();
        } else {
          debugPrint('[TMDBCastService] 获取演员作品失败: ${data['error'] ?? data['message']}');
          return [];
        }
      } else {
        debugPrint('[TMDBCastService] 获取演员作品失败: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('[TMDBCastService] 获取演员作品异常: $e');
      return [];
    }
  }
}
