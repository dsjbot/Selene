import 'package:flutter/material.dart';
import '../models/skip_config.dart';
import '../services/skip_config_service.dart';

/// 跳过设置面板
class SkipSettingsPanel extends StatefulWidget {
  final String? videoSource;
  final String? videoId;
  final String? videoTitle;
  final EpisodeSkipConfig? currentConfig;
  final ValueChanged<EpisodeSkipConfig?> onConfigChanged;

  const SkipSettingsPanel({
    super.key,
    this.videoSource,
    this.videoId,
    this.videoTitle,
    this.currentConfig,
    required this.onConfigChanged,
  });

  @override
  State<SkipSettingsPanel> createState() => _SkipSettingsPanelState();
}

class _SkipSettingsPanelState extends State<SkipSettingsPanel> {
  late TextEditingController _introStartController;
  late TextEditingController _introEndController;
  late TextEditingController _outroTimeController;
  bool _introEnabled = true;
  bool _outroEnabled = true;
  bool _autoSkipIntro = true;
  bool _autoNextEpisode = true;
  bool _outroRemainingMode = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final config = widget.currentConfig;
    
    // 查找片头和片尾配置
    SkipSegment? introSegment;
    SkipSegment? outroSegment;
    
    if (config != null) {
      for (final seg in config.segments) {
        if (seg.type == SkipSegmentType.opening) {
          introSegment = seg;
        } else if (seg.type == SkipSegmentType.ending) {
          outroSegment = seg;
        }
      }
    }

    // 片头默认值：0:00 - 1:30
    _introStartController = TextEditingController(
      text: introSegment != null ? _formatTime(introSegment.start) : '0:00',
    );
    _introEndController = TextEditingController(
      text: introSegment != null ? _formatTime(introSegment.end) : '1:30',
    );
    _introEnabled = introSegment != null;
    _autoSkipIntro = introSegment?.autoSkip ?? true;

    // 片尾默认值：剩余2分钟
    _outroTimeController = TextEditingController(
      text: outroSegment != null 
          ? _formatTime(outroSegment.mode == SkipTimeMode.remaining 
              ? (outroSegment.remainingTime ?? outroSegment.end) 
              : outroSegment.start)
          : '2:00',
    );
    _outroEnabled = outroSegment != null;
    _autoNextEpisode = outroSegment?.autoNextEpisode ?? true;
    _outroRemainingMode = outroSegment?.mode == SkipTimeMode.remaining || outroSegment == null;
  }

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  double _parseTime(String text) {
    text = text.trim();
    if (text.contains(':')) {
      final parts = text.split(':');
      final mins = int.tryParse(parts[0]) ?? 0;
      final secs = int.tryParse(parts[1]) ?? 0;
      return mins * 60.0 + secs;
    }
    return double.tryParse(text) ?? 0;
  }

  Future<void> _saveConfig() async {
    if (widget.videoSource == null || widget.videoId == null) return;

    setState(() => _isSaving = true);

    final segments = <SkipSegment>[];

    // 添加片头配置
    if (_introEnabled) {
      final start = _parseTime(_introStartController.text);
      final end = _parseTime(_introEndController.text);
      if (end > start) {
        segments.add(SkipSegment(
          start: start,
          end: end,
          type: SkipSegmentType.opening,
          title: '片头',
          autoSkip: _autoSkipIntro,
        ));
      }
    }

    // 添加片尾配置
    if (_outroEnabled) {
      final time = _parseTime(_outroTimeController.text);
      if (time > 0) {
        segments.add(SkipSegment(
          start: _outroRemainingMode ? 0 : time,
          end: _outroRemainingMode ? time : time + 120,
          type: SkipSegmentType.ending,
          title: '片尾',
          autoSkip: true,
          autoNextEpisode: _autoNextEpisode,
          mode: _outroRemainingMode ? SkipTimeMode.remaining : SkipTimeMode.absolute,
          remainingTime: _outroRemainingMode ? time : null,
        ));
      }
    }

    final config = EpisodeSkipConfig(
      source: widget.videoSource!,
      id: widget.videoId!,
      title: widget.videoTitle ?? '',
      segments: segments,
      updatedTime: DateTime.now().millisecondsSinceEpoch,
    );

    final success = await SkipConfigService.setSkipConfig(
      source: widget.videoSource!,
      id: widget.videoId!,
      config: config,
    );

    setState(() => _isSaving = false);

    if (success) {
      widget.onConfigChanged(config);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('跳过设置已保存'), duration: Duration(seconds: 2)),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存失败，请重试'), duration: Duration(seconds: 2)),
        );
      }
    }
  }

  Future<void> _deleteConfig() async {
    if (widget.videoSource == null || widget.videoId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除配置'),
        content: const Text('确定要删除跳过配置吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await SkipConfigService.deleteSkipConfig(
      source: widget.videoSource!,
      id: widget.videoId!,
    );

    if (success) {
      widget.onConfigChanged(null);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('跳过配置已删除'), duration: Duration(seconds: 2)),
        );
      }
    }
  }

  @override
  void dispose() {
    _introStartController.dispose();
    _introEndController.dispose();
    _outroTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final screenHeight = MediaQuery.of(context).size.height;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.7),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题（固定在顶部）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('跳过设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                IconButton(
                  icon: Icon(Icons.close, color: subTextColor),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 可滚动内容区域
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 片头设置
                    _buildSectionTitle('片头跳过', _introEnabled, (v) => setState(() => _introEnabled = v), textColor),
                    if (_introEnabled) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _buildTimeField('开始', _introStartController, subTextColor)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildTimeField('结束', _introEndController, subTextColor)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildSwitch('自动跳过', _autoSkipIntro, (v) => setState(() => _autoSkipIntro = v), subTextColor),
                    ],

                    const SizedBox(height: 16),
                    Divider(color: subTextColor.withOpacity(0.3)),
                    const SizedBox(height: 16),

                    // 片尾设置
                    _buildSectionTitle('片尾跳过', _outroEnabled, (v) => setState(() => _outroEnabled = v), textColor),
                    if (_outroEnabled) ...[
                      const SizedBox(height: 8),
                      _buildSwitch(
                        '剩余时间模式',
                        _outroRemainingMode,
                        (v) => setState(() => _outroRemainingMode = v),
                        subTextColor,
                        subtitle: _outroRemainingMode ? '视频结束前触发' : '从指定时间点触发',
                      ),
                      const SizedBox(height: 8),
                      _buildTimeField(
                        _outroRemainingMode ? '剩余时间' : '开始时间',
                        _outroTimeController,
                        subTextColor,
                      ),
                      const SizedBox(height: 8),
                      _buildSwitch('自动下一集', _autoNextEpisode, (v) => setState(() => _autoNextEpisode = v), subTextColor),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 按钮（固定在底部）
            Row(
              children: [
                if (widget.currentConfig != null)
                  TextButton(
                    onPressed: _deleteConfig,
                    child: const Text('删除配置', style: TextStyle(color: Colors.red)),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('取消', style: TextStyle(color: subTextColor)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveConfig,
                  child: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildSectionTitle(String title, bool enabled, ValueChanged<bool> onChanged, Color textColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: textColor)),
        Switch(value: enabled, onChanged: onChanged, activeColor: Colors.blue),
      ],
    );
  }

  Widget _buildTimeField(String label, TextEditingController controller, Color textColor) {
    return TextField(
      controller: controller,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: textColor.withOpacity(0.7)),
        hintText: '分:秒 或 秒数',
        hintStyle: TextStyle(color: textColor.withOpacity(0.5)),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      keyboardType: TextInputType.text,
    );
  }

  Widget _buildSwitch(String label, bool value, ValueChanged<bool> onChanged, Color textColor, {String? subtitle}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: textColor)),
            if (subtitle != null)
              Text(subtitle, style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 12)),
          ],
        ),
        Switch(value: value, onChanged: onChanged, activeColor: Colors.blue),
      ],
    );
  }
}

/// 显示跳过设置对话框
Future<void> showSkipSettingsDialog({
  required BuildContext context,
  String? videoSource,
  String? videoId,
  String? videoTitle,
  EpisodeSkipConfig? currentConfig,
  required ValueChanged<EpisodeSkipConfig?> onConfigChanged,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SkipSettingsPanel(
        videoSource: videoSource,
        videoId: videoId,
        videoTitle: videoTitle,
        currentConfig: currentConfig,
        onConfigChanged: onConfigChanged,
      ),
    ),
  );
}
