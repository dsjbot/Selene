import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/netdisk_service.dart';
import '../services/theme_service.dart';
import '../utils/font_utils.dart';
import 'netdisk_results_widget.dart';

/// 网盘搜索模态框
class NetDiskModal extends StatefulWidget {
  final String keyword;
  final VoidCallback onClose;

  const NetDiskModal({
    super.key,
    required this.keyword,
    required this.onClose,
  });

  @override
  State<NetDiskModal> createState() => _NetDiskModalState();
}

class _NetDiskModalState extends State<NetDiskModal> {
  NetDiskSearchResult? _result;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    if (widget.keyword.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    final result = await NetDiskService.search(widget.keyword);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.success) {
          _result = result;
        } else {
          _error = result.error;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return GestureDetector(
          onTap: widget.onClose,
          child: Container(
            color: Colors.black.withOpacity(0.5),
            child: GestureDetector(
              onTap: () {}, // 阻止点击穿透
              child: DraggableScrollableSheet(
                initialChildSize: 0.85,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: themeService.isDarkMode
                          ? const Color(0xFF1e1e1e)
                          : Colors.white,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // 拖动指示器
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: themeService.isDarkMode
                                ? Colors.white24
                                : Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // 头部
                        _buildHeader(themeService),
                        // 内容
                        Expanded(
                          child: NetDiskResultsWidget(
                            result: _result,
                            isLoading: _isLoading,
                            error: _error,
                            onRetry: _search,
                            themeService: themeService,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(ThemeService themeService) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: themeService.isDarkMode
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          const Text('📁', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '资源搜索',
                      style: FontUtils.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: themeService.isDarkMode
                            ? Colors.white
                            : const Color(0xFF2c3e50),
                      ),
                    ),
                    if (_isLoading) ...[
                      const SizedBox(width: 12),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF3498DB),
                          ),
                        ),
                      ),
                    ],
                    if (_result != null && _result!.total > 0) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3498DB).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_result!.total} 个资源',
                          style: FontUtils.poppins(
                            fontSize: 12,
                            color: const Color(0xFF3498DB),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '搜索关键词：${widget.keyword}',
                  style: FontUtils.poppins(
                    fontSize: 12,
                    color: themeService.isDarkMode
                        ? Colors.white54
                        : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: widget.onClose,
            icon: Icon(
              Icons.close,
              color: themeService.isDarkMode ? Colors.white54 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

/// 显示网盘搜索模态框
void showNetDiskModal(BuildContext context, String keyword) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => NetDiskModal(
      keyword: keyword,
      onClose: () => Navigator.of(context).pop(),
    ),
  );
}
