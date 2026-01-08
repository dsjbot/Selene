import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_data_service.dart';

/// M3U8 广告过滤服务
/// 参考后端实现，过滤 HLS 流中的广告片段
class AdFilterService {
  static final Dio _dio = Dio();
  static const String _adFilterEnabledKey = 'ad_filter_enabled';
  
  // 缓存自定义过滤代码
  static String? _customAdFilterCode;
  static int _customAdFilterVersion = 0;
  
  // 广告过滤开关（默认开启）
  static bool _adFilterEnabled = true;
  
  // 临时文件目录
  static Directory? _tempDir;
  
  /// 初始化服务
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _adFilterEnabled = prefs.getBool(_adFilterEnabledKey) ?? true;
    _tempDir = await getTemporaryDirectory();
    
    // 清理旧的临时 M3U8 文件
    _cleanupTempFiles();
    
    // 获取自定义广告过滤代码
    await fetchCustomAdFilterCode();
  }
  
  /// 清理临时文件
  static Future<void> _cleanupTempFiles() async {
    if (_tempDir == null) return;
    
    try {
      final dir = Directory('${_tempDir!.path}/filtered_m3u8');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('[AdFilter] 清理临时文件失败: $e');
    }
  }
  
  /// 获取广告过滤开关状态
  static bool get isEnabled => _adFilterEnabled;
  
  /// 设置广告过滤开关
  static Future<void> setEnabled(bool enabled) async {
    _adFilterEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adFilterEnabledKey, enabled);
  }
  
  /// 从后端获取自定义广告过滤代码
  static Future<void> fetchCustomAdFilterCode() async {
    try {
      final serverUrl = await UserDataService.getServerUrl();
      if (serverUrl == null || serverUrl.isEmpty) return;
      
      final cookies = await UserDataService.getCookies();
      final headers = <String, String>{};
      if (cookies != null && cookies.isNotEmpty) {
        headers['Cookie'] = cookies;
      }
      
      final response = await _dio.get(
        '$serverUrl/api/ad-filter',
        options: Options(headers: headers),
      );
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        _customAdFilterCode = data['code'] as String? ?? '';
        _customAdFilterVersion = data['version'] as int? ?? 1;
        if (_customAdFilterCode != null && _customAdFilterCode!.isNotEmpty) {
          debugPrint('[AdFilter] 获取自定义广告过滤代码成功，版本: $_customAdFilterVersion');
        }
      }
    } catch (e) {
      debugPrint('[AdFilter] 获取自定义广告过滤代码失败: $e');
    }
  }
  
  /// 过滤 M3U8 内容中的广告
  /// [m3u8Content] - 原始 M3U8 内容
  /// [sourceKey] - 播放源标识（用于自定义过滤规则）
  static String filterAdsFromM3U8(String m3u8Content, {String? sourceKey}) {
    if (m3u8Content.isEmpty) {
      return m3u8Content;
    }
    
    try {
      // 默认去广告逻辑（与后端保持一致）
      final lines = m3u8Content.split('\n');
      final filteredLines = <String>[];
      bool inAdBlock = false;
      int adSegmentCount = 0;
      
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        
        // 检测行业标准广告标记（SCTE-35系列）
        if (line.contains('#EXT-X-CUE-OUT') ||
            (line.contains('#EXT-X-DATERANGE') && line.contains('SCTE35')) ||
            line.contains('#EXT-X-SCTE35') ||
            line.contains('#EXT-OATCLS-SCTE35')) {
          inAdBlock = true;
          adSegmentCount++;
          continue; // 跳过广告开始标记
        }
        
        // 检测广告结束标记
        if (line.contains('#EXT-X-CUE-IN')) {
          inAdBlock = false;
          continue; // 跳过广告结束标记
        }
        
        // 如果在广告区块内，跳过所有内容
        if (inAdBlock) {
          continue;
        }
        
        // 过滤 #EXT-X-DISCONTINUITY 标识
        if (!line.contains('#EXT-X-DISCONTINUITY')) {
          filteredLines.add(line);
        }
      }
      
      // 输出统计信息
      if (adSegmentCount > 0) {
        debugPrint('[AdFilter] M3U8广告过滤: 移除 $adSegmentCount 个广告片段');
      }
      
      return filteredLines.join('\n');
    } catch (e) {
      debugPrint('[AdFilter] 过滤广告失败: $e');
      return m3u8Content;
    }
  }
  
  /// 检查是否是主播放列表（包含多个码率/分辨率选项）
  static bool _isMasterPlaylist(String content) {
    return content.contains('#EXT-X-STREAM-INF');
  }
  
  /// 处理 M3U8 URL，返回过滤后的 URL
  /// 如果是 M3U8 文件且启用了广告过滤，会下载、过滤并保存到临时文件
  /// [originalUrl] - 原始视频 URL
  /// [headers] - 请求头
  /// [sourceKey] - 播放源标识
  static Future<String> processM3U8Url(
    String originalUrl, {
    Map<String, String>? headers,
    String? sourceKey,
  }) async {
    // 如果未启用广告过滤，直接返回原始 URL
    if (!_adFilterEnabled) {
      return originalUrl;
    }
    
    // 只处理 m3u8 文件
    final lowerUrl = originalUrl.toLowerCase();
    if (!lowerUrl.contains('.m3u8') && !lowerUrl.contains('m3u8')) {
      return originalUrl;
    }
    
    try {
      // 获取原始 M3U8 内容（设置较短的超时时间）
      final response = await _dio.get(
        originalUrl,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ),
      );
      
      if (response.statusCode == 200 && response.data != null) {
        final originalContent = response.data as String;
        
        // 检查是否是主播放列表（包含其他 m3u8 链接）
        if (_isMasterPlaylist(originalContent)) {
          // 主播放列表需要处理子播放列表的 URL
          // 但为了简化，我们先返回原始 URL，让播放器自己选择码率
          // 广告过滤会在子播放列表级别生效
          debugPrint('[AdFilter] 检测到主播放列表，跳过过滤');
          return originalUrl;
        }
        
        // 过滤广告
        final filteredContent = filterAdsFromM3U8(originalContent, sourceKey: sourceKey);
        
        // 如果内容没有变化，返回原始 URL
        if (filteredContent == originalContent) {
          return originalUrl;
        }
        
        // 处理相对路径的 ts 文件
        final processedContent = _processRelativeUrls(filteredContent, originalUrl);
        
        // 保存到临时文件
        final tempFile = await _saveTempM3U8(processedContent);
        if (tempFile != null) {
          debugPrint('[AdFilter] 已过滤广告，使用临时文件: ${tempFile.path}');
          return tempFile.path;
        }
      }
    } on DioException catch (e) {
      // 网络错误时静默返回原始 URL
      debugPrint('[AdFilter] 网络请求失败: ${e.type} - ${e.message}');
    } catch (e) {
      debugPrint('[AdFilter] 处理 M3U8 失败: $e');
    }
    
    return originalUrl;
  }
  
  /// 处理 M3U8 中的相对路径，转换为绝对路径
  static String _processRelativeUrls(String content, String baseUrl) {
    final lines = content.split('\n');
    final processedLines = <String>[];
    
    // 获取基础 URL（去掉文件名）
    final uri = Uri.parse(baseUrl);
    final basePath = uri.resolve('.').toString();
    
    for (final line in lines) {
      final trimmedLine = line.trim();
      
      // 跳过空行和注释行
      if (trimmedLine.isEmpty || trimmedLine.startsWith('#')) {
        processedLines.add(line);
        continue;
      }
      
      // 如果是相对路径，转换为绝对路径
      if (!trimmedLine.startsWith('http://') && !trimmedLine.startsWith('https://')) {
        final absoluteUrl = uri.resolve(trimmedLine).toString();
        processedLines.add(absoluteUrl);
      } else {
        processedLines.add(line);
      }
    }
    
    return processedLines.join('\n');
  }
  
  /// 保存过滤后的 M3U8 到临时文件
  static Future<File?> _saveTempM3U8(String content) async {
    if (_tempDir == null) {
      _tempDir = await getTemporaryDirectory();
    }
    
    try {
      // 创建临时目录
      final dir = Directory('${_tempDir!.path}/filtered_m3u8');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 生成唯一文件名
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/filtered_$timestamp.m3u8');
      
      // 写入内容
      await file.writeAsString(content);
      
      return file;
    } catch (e) {
      debugPrint('[AdFilter] 保存临时文件失败: $e');
      return null;
    }
  }
}
