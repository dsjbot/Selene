import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 播放器实例包装类
class ManagedPlayer {
  final String id;
  final Player player;
  final VideoController controller;
  
  ManagedPlayer({
    required this.id,
    required this.player,
    required this.controller,
  });
}

/// 全局播放器管理器 - 单例模式
/// 
/// 核心策略：不 dispose 播放器，只复用
/// 这样可以完全避免 media_kit 的 FFI 回调崩溃问题
class PlayerManager {
  static final PlayerManager _instance = PlayerManager._internal();
  factory PlayerManager() => _instance;
  PlayerManager._internal();
  
  // 播放器池（永不释放，只复用）
  final Map<String, ManagedPlayer> _players = {};
  
  // 主播放器 ID（用于视频播放页面）
  static const String mainPlayerId = 'main_player';
  
  // 轮播图播放器 ID
  static const String carouselPlayerId = 'carousel_player';
  
  /// 获取或创建播放器
  Future<ManagedPlayer> getPlayer(String id) async {
    // 如果已存在，直接返回
    if (_players.containsKey(id)) {
      debugPrint('[PlayerManager] 复用播放器: $id');
      return _players[id]!;
    }
    
    // 创建新播放器
    debugPrint('[PlayerManager] 创建播放器: $id');
    final player = Player();
    final controller = VideoController(player);
    
    final managed = ManagedPlayer(
      id: id,
      player: player,
      controller: controller,
    );
    
    _players[id] = managed;
    return managed;
  }
  
  /// 获取已存在的播放器（不创建新的）
  ManagedPlayer? getExistingPlayer(String id) {
    return _players[id];
  }
  
  /// 停止播放器（不释放，只停止）
  Future<void> stopPlayer(String id) async {
    final managed = _players[id];
    if (managed == null) return;
    
    debugPrint('[PlayerManager] 停止播放器: $id');
    try {
      await managed.player.stop();
    } catch (e) {
      debugPrint('[PlayerManager] 停止播放器出错: $e');
    }
  }
  
  /// 暂停所有播放器
  Future<void> pauseAll() async {
    for (final managed in _players.values) {
      try {
        await managed.player.pause();
      } catch (e) {
        debugPrint('[PlayerManager] 暂停播放器失败: ${managed.id}, $e');
      }
    }
  }
  
  /// 停止所有播放器
  Future<void> stopAll() async {
    for (final managed in _players.values) {
      try {
        await managed.player.stop();
      } catch (e) {
        debugPrint('[PlayerManager] 停止播放器失败: ${managed.id}, $e');
      }
    }
  }
  
  /// 获取播放器数量
  int get count => _players.length;
}
