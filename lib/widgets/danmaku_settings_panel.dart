import 'package:flutter/material.dart';

/// 弹幕设置数据
class DanmakuSettings {
  bool enabled;
  double opacity;
  double fontSize;
  double speed;
  double areaHeight;

  DanmakuSettings({
    this.enabled = true,
    this.opacity = 0.8,
    this.fontSize = 18.0,
    this.speed = 1.0,
    this.areaHeight = 0.5,
  });

  DanmakuSettings copyWith({
    bool? enabled,
    double? opacity,
    double? fontSize,
    double? speed,
    double? areaHeight,
  }) {
    return DanmakuSettings(
      enabled: enabled ?? this.enabled,
      opacity: opacity ?? this.opacity,
      fontSize: fontSize ?? this.fontSize,
      speed: speed ?? this.speed,
      areaHeight: areaHeight ?? this.areaHeight,
    );
  }
}

/// 弹幕设置面板
class DanmakuSettingsPanel extends StatelessWidget {
  final DanmakuSettings settings;
  final ValueChanged<DanmakuSettings> onSettingsChanged;
  final bool isFullscreen;

  const DanmakuSettingsPanel({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    this.isFullscreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final panelWidth = isFullscreen ? 280.0 : 240.0;
    final itemPadding = isFullscreen ? 16.0 : 12.0;
    final titleSize = isFullscreen ? 14.0 : 12.0;
    final labelSize = isFullscreen ? 13.0 : 11.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: panelWidth,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Padding(
              padding: EdgeInsets.all(itemPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '弹幕设置',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // 弹幕开关
                  _buildSwitch(
                    value: settings.enabled,
                    onChanged: (value) {
                      onSettingsChanged(settings.copyWith(enabled: value));
                    },
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: Colors.white.withValues(alpha: 0.1),
            ),
            // 透明度
            _buildSliderItem(
              label: '透明度',
              value: settings.opacity,
              min: 0.1,
              max: 1.0,
              displayValue: '${(settings.opacity * 100).round()}%',
              onChanged: settings.enabled
                  ? (value) {
                      onSettingsChanged(settings.copyWith(opacity: value));
                    }
                  : null,
              padding: itemPadding,
              labelSize: labelSize,
            ),
            // 字体大小
            _buildSliderItem(
              label: '字体大小',
              value: settings.fontSize,
              min: 12.0,
              max: 32.0,
              displayValue: '${settings.fontSize.round()}',
              onChanged: settings.enabled
                  ? (value) {
                      onSettingsChanged(settings.copyWith(fontSize: value));
                    }
                  : null,
              padding: itemPadding,
              labelSize: labelSize,
            ),
            // 弹幕速度
            _buildSliderItem(
              label: '弹幕速度',
              value: settings.speed,
              min: 0.5,
              max: 2.0,
              displayValue: '${settings.speed.toStringAsFixed(1)}x',
              onChanged: settings.enabled
                  ? (value) {
                      onSettingsChanged(settings.copyWith(speed: value));
                    }
                  : null,
              padding: itemPadding,
              labelSize: labelSize,
            ),
            // 显示区域
            _buildSliderItem(
              label: '显示区域',
              value: settings.areaHeight,
              min: 0.25,
              max: 1.0,
              displayValue: '${(settings.areaHeight * 100).round()}%',
              onChanged: settings.enabled
                  ? (value) {
                      onSettingsChanged(settings.copyWith(areaHeight: value));
                    }
                  : null,
              padding: itemPadding,
              labelSize: labelSize,
            ),
            SizedBox(height: itemPadding / 2),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitch({
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return GestureDetector(
      onTap: onChanged != null ? () => onChanged(!value) : null,
      child: Container(
        width: 44,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: value
              ? Colors.blue.withValues(alpha: 0.8)
              : Colors.grey.withValues(alpha: 0.4),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderItem({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double>? onChanged,
    required double padding,
    required double labelSize,
  }) {
    final isEnabled = onChanged != null;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding / 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isEnabled
                      ? Colors.white.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.4),
                  fontSize: labelSize,
                ),
              ),
              Text(
                displayValue,
                style: TextStyle(
                  color: isEnabled
                      ? Colors.white.withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.3),
                  fontSize: labelSize,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor:
                  isEnabled ? Colors.blue : Colors.grey.withValues(alpha: 0.3),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
              thumbColor: isEnabled ? Colors.white : Colors.grey,
              overlayColor: Colors.blue.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
