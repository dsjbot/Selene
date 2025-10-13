import 'dart:io';

import 'package:flutter/material.dart';

/// 设备类型工具类
class DeviceUtils {
  // 平板的最小宽度阈值（dp）
  static const double tabletMinWidth = 600.0;

  /// 判断当前设备是否是平板
  ///
  /// 通过屏幕宽度判断，宽度 >= 600dp 视为平板
  static bool isTablet(BuildContext context) {
    if (isPC()) {
      return true;
    }
    final double width = MediaQuery.of(context).size.width;
    return width >= tabletMinWidth;
  }

  /// 判断当前设备是否是平板竖屏
  ///
  /// 逻辑：isTablet 且宽高比小于等于 1.2
  static bool isPortraitTablet(BuildContext context) {
    if (!isTablet(context)) {
      return false;
    }
    if (isPC()) {
      return false;
    }

    final Size size = MediaQuery.of(context).size;
    final double aspectRatio = size.width / size.height;
    return aspectRatio <= 1.2;
  }

  /// 判断当前平台是否是 Windows
  static bool isWindows() {
    return Platform.isWindows;
  }

  /// 判断当前平台是否是 macOS
  static bool isMacOS() {
    return Platform.isMacOS;
  }

  /// 判断当前平台是否是 PC（Windows 或 macOS）
  static bool isPC() {
    return isWindows() || isMacOS();
  }
}
