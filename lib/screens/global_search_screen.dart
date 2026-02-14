import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gwid/api/api_service.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  String? _errorMessage;

  String _query = '';
  String? _marker;
  bool _hasMore = false;

  final Map<String, List<Map<String, dynamic>>> _sections = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore) return;
    if (_isLoading) return;
    if (_query.isEmpty) return;

    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _performSearch({bool reset = true}) async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;

    if (reset) {
      setState(() {
        _query = q;
        _marker = null;
        _hasMore = false;
        _errorMessage = null;
        _sections.clear();
      });
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final payload = await ApiService.instance.globalSearch(
        q,
        marker: _marker,
        count: 30,
        useTypeAll: false,
      );

      final result = payload['result'];
      if (result is List) {
        for (final item in result) {
          if (item is! Map) continue;
          final map = item.cast<String, dynamic>();
          final section = map['section']?.toString() ?? 'RESULT';
          (_sections[section] ??= []).add(map);
        }
      }

      final marker = payload['marker']?.toString();
      final total = payload['total'];
      final bool canPage = marker != null && marker.isNotEmpty;

      setState(() {
        _marker = marker;
        _hasMore = canPage;
        if (total is num && total == 0 && _sections.isEmpty) {
          _hasMore = false;
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_marker == null || _marker!.isEmpty) return;
    await _performSearch(reset: false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final sectionKeys = _sections.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Глобальный поиск'),
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _performSearch(),
                    decoration: InputDecoration(
                      labelText: 'Запрос',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _isLoading ? null : _performSearch,
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Найти'),
                ),
              ],
            ),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: colors.error),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _query.isEmpty
                ? Center(
                    child: Text(
                      'Введите запрос',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  )
                : (sectionKeys.isEmpty && !_isLoading)
                    ? Center(
                        child: Text(
                          'Ничего не найдено',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: sectionKeys.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_hasMore && index == sectionKeys.length) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: _isLoading
                                    ? const CircularProgressIndicator()
                                    : TextButton(
                                        onPressed: _loadMore,
                                        child: const Text('Загрузить еще'),
                                      ),
                              ),
                            );
                          }

                          final section = sectionKeys[index];
                          final items = _sections[section] ?? const [];

                          return _SectionWidget(
                            title: section,
                            items: items,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SectionWidget extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;

  const _SectionWidget({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: colors.surfaceContainerHighest,
          child: Text(
            '$title (${items.length})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ...items.map((item) {
          final chat = item['chat'];
          final highlights = item['highlights'];

          String primary = '';
          String secondary = '';

          if (chat is Map) {
            final chatMap = chat.cast<String, dynamic>();
            primary =
                chatMap['title']?.toString() ?? chatMap['link']?.toString() ?? '';
            secondary = chatMap['description']?.toString() ?? '';

            final participantsCount = chatMap['participantsCount'];
            if (participantsCount is num) {
              secondary = secondary.isEmpty
                  ? 'Участников: ${participantsCount.toInt()}'
                  : '$secondary\nУчастников: ${participantsCount.toInt()}';
            }
          }

          if (primary.isEmpty) {
            primary = item['chatId']?.toString() ?? 'Результат';
          }

          if (highlights is List && highlights.isNotEmpty) {
            final h = highlights.map((e) => e.toString()).join(', ');
            secondary = secondary.isEmpty ? h : '$secondary\n$h';
          }

          return ListTile(
            title: Text(primary, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: secondary.isEmpty
                ? null
                : Text(secondary, maxLines: 3, overflow: TextOverflow.ellipsis),
          );
        }),
      ],
    );
  }
}
