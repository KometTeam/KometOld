class ChatFolder {
  final String id;
  final String title;
  final String? emoji;
  final List<int>? include;
  final List<dynamic> filters;
  final bool hideEmpty;
  final List<ChatFolderWidget> widgets;
  final List<int>? favorites;
  final Map<String, dynamic>? filterSubjects;
  final List<int>? options;

  ChatFolder({
    required this.id,
    required this.title,
    this.emoji,
    this.include,
    required this.filters,
    required this.hideEmpty,
    required this.widgets,
    this.favorites,  // ← Теперь List<int>?
    this.filterSubjects,
    this.options,
  });

  factory ChatFolder.fromJson(Map<String, dynamic> json) {
    return ChatFolder(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? 'Без названия',
      emoji: json['emoji']?.toString(),

      //  Безопасный парсинг include
      include: (json['include'] as List<dynamic>?)
          ?.map((e) {
            if (e is int) return e;
            if (e is String) return int.tryParse(e) ?? 0;
            return 0;
          })
          .toList(),

      //  Безопасный парсинг filters
      filters: (json['filters'] as List<dynamic>?)
          ?.map((e) {
            if (e is int) return e;
            if (e is String) return int.tryParse(e) ?? 0;
            return 0;
          })
          .toList() ?? [],

      hideEmpty: json['hideEmpty'] ?? false,
      widgets: (json['widgets'] as List<dynamic>?)
          ?.map((widget) => ChatFolderWidget.fromJson(widget))
          .toList() ??
          [],

      //  Безопасный парсинг favorites
      favorites: (json['favorites'] as List<dynamic>?)
          ?.map((e) {
            if (e is int) return e;
            if (e is String) return int.tryParse(e) ?? 0;
            return 0;
          })
          .toList(),

      filterSubjects: json['filterSubjects'],

      // Безопасный парсинг options
      options: (json['options'] as List<dynamic>?)
          ?.map((e) {
            if (e is int) return e;
            if (e is String) return int.tryParse(e) ?? 0;
            return 0;
          })
          .toList(),
    );
  }
}

class ChatFolderWidget {
  final int id;
  final String name;
  final String description;
  final String? iconUrl;
  final String? url;
  final String? startParam;
  final String? background;
  final int? appId;

  ChatFolderWidget({
    required this.id,
    required this.name,
    required this.description,
    this.iconUrl,
    this.url,
    this.startParam,
    this.background,
    this.appId,
  });

  factory ChatFolderWidget.fromJson(Map<String, dynamic> json) {
    return ChatFolderWidget(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      iconUrl: json['iconUrl'],
      url: json['url'],
      startParam: json['startParam'],
      background: json['background'],
      appId: json['appId'],
    );
  }
}
