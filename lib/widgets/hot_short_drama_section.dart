import 'package:flutter/material.dart';
import '../models/short_drama.dart';
import '../services/short_drama_service.dart';
import '../widgets/short_drama_card.dart';
import '../utils/font_utils.dart';

class HotShortDramaSection extends StatefulWidget {
  final Function(ShortDramaItem)? onDramaTap;
  final VoidCallback? onMoreTap;

  const HotShortDramaSection({
    super.key,
    this.onDramaTap,
    this.onMoreTap,
  });

  // 静态方法用于刷新数据
  static Future<void> refreshHotShortDramas() async {
    _HotShortDramaSectionState._refreshNotifier.value =
        !_HotShortDramaSectionState._refreshNotifier.value;
  }

  @override
  State<HotShortDramaSection> createState() => _HotShortDramaSectionState();
}

class _HotShortDramaSectionState extends State<HotShortDramaSection> {
  static final ValueNotifier<bool> _refreshNotifier = ValueNotifier(false);

  List<ShortDramaItem> _items = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshNotifier.addListener(_onRefresh);
  }

  @override
  void dispose() {
    _refreshNotifier.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final response = await ShortDramaService.getRecommend(size: 12);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (response.success && response.data != null) {
          _items = response.data!;
        } else {
          _error = response.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 如果加载失败或没有数据，不显示此区块
    if (_error != null || (!_isLoading && _items.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '热门短剧',
                style: FontUtils.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF2c3e50),
                ),
              ),
              if (widget.onMoreTap != null)
                GestureDetector(
                  onTap: widget.onMoreTap,
                  child: Row(
                    children: [
                      Text(
                        '更多',
                        style: FontUtils.poppins(
                          fontSize: 14,
                          color: const Color(0xFF27ae60),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 12,
                        color: Color(0xFF27ae60),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // 内容区域
        SizedBox(
          height: 200,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Container(
                      width: 120,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      child: ShortDramaCard(
                        item: item,
                        onTap: () => widget.onDramaTap?.call(item),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
