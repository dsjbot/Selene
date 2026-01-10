// 通用图片地址处理工具
import '../services/user_data_service.dart';

// 缓存的 cookies
String? _cachedCookies;
bool _cookiesLoaded = false;

/// 初始化/刷新 cookies 缓存
Future<void> _ensureCookiesLoaded() async {
  if (!_cookiesLoaded) {
    _cachedCookies = await UserDataService.getCookies();
    _cookiesLoaded = true;
  }
}

/// 根据来源处理图片 URL（例如豆瓣域名替换）。
/// - [originalUrl]: 原始图片地址
/// - [source]: 数据来源（如 'douban'、'bangumi' 等）
/// 返回可直接用于加载的图片地址。
Future<String> getImageUrl(String originalUrl, String? source) async {
  // 确保 cookies 已加载
  await _ensureCookiesLoaded();
  
  if (source == 'douban' && originalUrl.isNotEmpty) {
    final imageSourceKey = await UserDataService.getDoubanImageSourceKey();
    
    switch (imageSourceKey) {
      case 'official_cdn':
        return originalUrl.replaceAll(
          RegExp(r'img\d+\.doubanio\.com'),
          'img3.doubanio.com',
        );
      case 'cdn_tencent':
        return originalUrl.replaceAll(
          RegExp(r'img\d+\.doubanio\.com'),
          'img.doubanio.cmliussss.net',
        );
      case 'cdn_aliyun':
        return originalUrl.replaceAll(
          RegExp(r'img\d+\.doubanio\.com'),
          'img.doubanio.cmliussss.com',
        );
      case 'direct':
      default:
        return originalUrl;
    }
  }
  return originalUrl;
}

/// 返回加载网络图片所需的 HTTP 头（主要用于绕过特定站点的反盗链）。
/// 注意：只有当 [source] 为 'douban' 或 URL 指向 douban 域名时才添加 Referer/UA。其他来源返回空头。
Map<String, String>? getImageRequestHeaders(String imageUrl, String? source) {
  final bool isDoubanSource = (source == 'douban') ||
      RegExp(r'https?://([^/]+\.)?douban(io|)\.com', caseSensitive: false)
          .hasMatch(imageUrl);

  if (isDoubanSource) {
    // 常见可用的 Referer 和 UA，避免 403 或 Android 解码失败
    return <String, String>{
      'Referer': 'https://movie.douban.com/',
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    };
  }
  
  // 即将上映来源（manmankan.com）需要特殊 headers
  final bool isUpcomingSource = (source == 'upcoming_release') ||
      imageUrl.contains('manmankan.com');
  if (isUpcomingSource) {
    return <String, String>{
      'Referer': 'https://g.manmankan.com/',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    };
  }
  
  // 检查是否是通过后端代理的图片（需要 Cookie 认证）
  final bool isProxiedImage = imageUrl.contains('/api/image-proxy');
  if (isProxiedImage && _cachedCookies != null && _cachedCookies!.isNotEmpty) {
    return <String, String>{
      'Cookie': _cachedCookies!,
    };
  }
  
  return null;
}


