import 'package:flutter/material.dart';
import '../models/short_drama.dart';
import '../services/short_drama_service.dart';
import '../widgets/short_drama_card.dart';
import 'short_drama_player_screen.dart';

class ShortDramaScreen extends StatefulWidget {
  const ShortDramaScreen({super.key});

  @override
  State<ShortDramaScreen> createState() => _ShortDramaScreenState();
}

class _ShortDramaScreenState extends State<ShortDramaScreen> {
  List<ShortDramaCategory> _categories = [];
  List<ShortDramaItem> _items = [];
  bool _isLoadingCategories = true;
  bool _isLoadingList = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int? _selectedCategoryId;
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadCategories() async {
    final response = await ShortDramaService.getCategories();
    if (mounted) {
      setState(() {
        _isLoadingCategories = false;
        if (response.success && response.data != null) {
          _categories = response.data!;
          if (_categories.isNotEmpty) {
            _selectedCategoryId = _categories.first.typeId;
            _loadList();
          }
        }
      });
    }
  }

  Future<void> _loadList({bool refresh = false}) async {
    if (_isLoadingList) return;
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
    }
    if (!_hasMore && !refresh) return;

    setState(() => _isLoadingList = true);

    final response = _isSearching
        ? await ShortDramaService.search(
            query: _searchQuery,
            page: _currentPage,
          )
        : await ShortDramaService.getList(
            categoryId: _selectedCategoryId!,
            page: _currentPage,
          );

    if (mounted) {
      setState(() {
        _isLoadingList = false;
        if (response.success && response.data != null) {
          if (refresh || _currentPage == 1) {
            _items = response.data!.list;
          } else {
            _items.addAll(response.data!.list);
          }
          _hasMore = response.data!.hasMore;
          _currentPage++;
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_isLoadingList && _hasMore) {
      await _loadList();
    }
  }

  Future<void> _refresh() async {
    await _loadList(refresh: true);
  }

  void _onCategorySelected(int categoryId) {
    if (_selectedCategoryId == categoryId) return;
    setState(() {
      _selectedCategoryId = categoryId;
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
      _items = [];
      _currentPage = 1;
      _hasMore = true;
    });
    _loadList();
  }

  void _onSearch(String query) {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchQuery = '';
        _items = [];
        _currentPage = 1;
        _hasMore = true;
      });
      _loadList();
      return;
    }

    setState(() {
      _isSearching = true;
      _searchQuery = query;
      _items = [];
      _currentPage = 1;
      _hasMore = true;
    });
    _loadList();
  }

  void _openDetail(ShortDramaItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShortDramaPlayerScreen(
          id: item.id,
          name: item.name,
          cover: item.cover,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('短剧'),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索短剧...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onSubmitted: _onSearch,
              textInputAction: TextInputAction.search,
            ),
          ),
        ),
      ),
      body: _isLoadingCategories
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 分类标签
                if (!_isSearching && _categories.isNotEmpty)
                  Container(
                    height: 48,
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _categories.length,
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        final isSelected =
                            category.typeId == _selectedCategoryId;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: ChoiceChip(
                            label: Text(category.typeName),
                            selected: isSelected,
                            onSelected: (_) =>
                                _onCategorySelected(category.typeId),
                            selectedColor: Theme.of(context).primaryColor,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                              fontSize: 13,
                            ),
                            backgroundColor:
                                isDark ? Colors.grey[800] : Colors.grey[200],
                          ),
                        );
                      },
                    ),
                  ),
                // 内容列表
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: _items.isEmpty && _isLoadingList
                        ? const Center(child: CircularProgressIndicator())
                        : _items.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.movie_filter_outlined,
                                      size: 64,
                                      color: isDark
                                          ? Colors.grey[600]
                                          : Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _isSearching ? '没有找到相关短剧' : '暂无内容',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : GridView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(12),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  childAspectRatio: 0.6,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                itemCount: _items.length + (_hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= _items.length) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    );
                                  }
                                  final item = _items[index];
                                  return ShortDramaCard(
                                    item: item,
                                    onTap: () => _openDetail(item),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
    );
  }
}
