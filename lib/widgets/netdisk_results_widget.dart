import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/netdisk_service.dart';
import '../services/theme_service.dart';
import '../utils/font_utils.dart';

/// 网盘搜索结果组件
class NetDiskResultsWidget extends StatefulWidget {
  final NetDiskSearchResult? result;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;
  final ThemeService themeService;

  const NetDiskResultsWidget({
    super.key,
    this.result,
    this.isLoading = false,
    this.error,
    this.onRetry,
    required this.themeService,
  });

  @override
  State<NetDiskResultsWidget> createState() => _NetDiskResultsWidgetState();
}

class _NetDiskResultsWidgetState extends State<NetDiskResultsWidget> {
  String? _selectedCloudType;
  final Map<String, bool> _visiblePasswords = {};

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return _buildLoading();
    }

    if (widget.error != null) {
      return _buildError();
    }

    if (widget.result == null || widget.result!.mergedByType.isEmpty) {
      return _buildEmpty();
    }

    return _buildResults();
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3498DB)),
          ),
          const SizedBox(height: 16),
          Text(
            '正在搜索网盘资源...',
            style: FontUtils.poppins(
              fontSize: 14,
              color: widget.themeService.isDarkMode
                  ? const Color(0xFFb0b0b0)
                  : const Color(0xFF7f8c8d),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    final isFunctionDisabled = widget.error?.contains('未启用') == true ||
        widget.error?.contains('未配置') == true;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isFunctionDisabled
                ? Colors.blue.withOpacity(0.1)
                : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFunctionDisabled
                  ? Colors.blue.withOpacity(0.3)
                  : Colors.red.withOpacity(0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFunctionDisabled ? Icons.info_outline : Icons.error_outline,
                size: 48,
                color: isFunctionDisabled ? Colors.blue : Colors.red[300],
              ),
              const SizedBox(height: 16),
              Text(
                isFunctionDisabled ? '网盘搜索功能未启用' : '搜索失败',
                style: FontUtils.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isFunctionDisabled ? Colors.blue : Colors.red[400],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.error ?? '未知错误',
                style: FontUtils.poppins(
                  fontSize: 14,
                  color: widget.themeService.isDarkMode
                      ? Colors.white70
                      : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isFunctionDisabled
                      ? Colors.blue.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isFunctionDisabled
                      ? '💡 联系管理员启用网盘搜索功能\n暂时可以使用影视搜索功能查找内容'
                      : '💡 检查网络连接是否正常\n稍后重试或使用不同关键词搜索',
                  style: FontUtils.poppins(
                    fontSize: 12,
                    color: widget.themeService.isDarkMode
                        ? Colors.white60
                        : Colors.black45,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (!isFunctionDisabled && widget.onRetry != null) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: widget.onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3498DB),
                  ),
                  child: const Text('重试', style: TextStyle(color: Colors.white)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_queue,
            size: 64,
            color: widget.themeService.isDarkMode ? Colors.white24 : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            '未找到相关资源',
            style: FontUtils.poppins(
              fontSize: 16,
              color: widget.themeService.isDarkMode ? Colors.white54 : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '尝试使用其他关键词搜索',
            style: FontUtils.poppins(
              fontSize: 13,
              color: widget.themeService.isDarkMode ? Colors.white38 : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final result = widget.result!;
    final types = result.mergedByType.keys.toList();
    final typesToShow = _selectedCloudType != null ? [_selectedCloudType!] : types;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 云盘类型筛选
        _buildCloudTypeFilter(types),
        const SizedBox(height: 8),
        // 结果列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: typesToShow.length,
            itemBuilder: (context, index) {
              final type = typesToShow[index];
              final items = result.mergedByType[type] ?? [];
              if (items.isEmpty) return const SizedBox.shrink();
              return _buildTypeSection(type, items);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCloudTypeFilter(List<String> types) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildCloudTypeChip(
              label: '全部 (${widget.result!.total})',
              isSelected: _selectedCloudType == null,
              onTap: () => setState(() => _selectedCloudType = null),
            ),
            const SizedBox(width: 8),
            ...types.map((type) {
              final count = widget.result!.mergedByType[type]?.length ?? 0;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildCloudTypeChip(
                  label: '${NetDiskService.getCloudTypeName(type)} ($count)',
                  isSelected: _selectedCloudType == type,
                  onTap: () => setState(() => _selectedCloudType = type),
                  color: Color(NetDiskService.getCloudTypeColor(type)),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCloudTypeChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (color ?? const Color(0xFF3498DB))
              : widget.themeService.isDarkMode
                  ? Colors.white.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(
                  color: widget.themeService.isDarkMode
                      ? Colors.white.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.3),
                ),
        ),
        child: Text(
          label,
          style: FontUtils.poppins(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected
                ? Colors.white
                : widget.themeService.isDarkMode
                    ? Colors.white.withOpacity(0.8)
                    : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSection(String type, List<NetDiskItem> items) {
    final color = Color(NetDiskService.getCloudTypeColor(type));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 类型标题
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                NetDiskService.getCloudTypeIcon(type),
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 8),
              Text(
                NetDiskService.getCloudTypeName(type),
                style: FontUtils.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${items.length} 个链接',
                  style: FontUtils.poppins(
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 资源列表
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          return _buildResourceItem(item, type, index, color);
        }),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildResourceItem(NetDiskItem item, String type, int index, Color typeColor) {
    final linkKey = '$type-$index';
    final isPasswordVisible = _visiblePasswords[linkKey] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: widget.themeService.isDarkMode
            ? Colors.white.withOpacity(0.05)
            : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: widget.themeService.isDarkMode
              ? Colors.white.withOpacity(0.1)
              : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openUrl(item.url),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Text(
                  item.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: FontUtils.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: widget.themeService.isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                // 链接
                Row(
                  children: [
                    const Icon(Icons.link, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.themeService.isDarkMode
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.url.length > 50 ? '${item.url.substring(0, 50)}...' : item.url,
                          style: FontUtils.poppins(
                            fontSize: 11,
                            color: widget.themeService.isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _copyToClipboard(item.url, '链接已复制'),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.copy, size: 16, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
                // 密码（如果有）
                if (item.password.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.themeService.isDarkMode
                              ? Colors.white.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isPasswordVisible ? item.password : '****',
                          style: FontUtils.poppins(
                            fontSize: 11,
                            color: widget.themeService.isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _visiblePasswords[linkKey] = !isPasswordVisible;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                            size: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _copyToClipboard(item.password, '密码已复制'),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.copy, size: 16, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ],
                // 元信息
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (item.source.isNotEmpty) ...[
                      Text(
                        '来源: ${item.source}',
                        style: FontUtils.poppins(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (item.datetime.isNotEmpty)
                      Text(
                        '时间: ${_formatDateTime(item.datetime)}',
                        style: FontUtils.poppins(fontSize: 11, color: Colors.grey),
                      ),
                  ],
                ),
                // 操作按钮
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openUrl(item.url),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('访问链接'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: typeColor,
                        side: BorderSide(color: typeColor.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: FontUtils.poppins(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: FontUtils.poppins(color: Colors.white)),
        backgroundColor: const Color(0xFF27AE60),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('无法打开链接', style: FontUtils.poppins(color: Colors.white)),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatDateTime(String datetime) {
    try {
      final dt = DateTime.parse(datetime);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return datetime;
    }
  }
}
