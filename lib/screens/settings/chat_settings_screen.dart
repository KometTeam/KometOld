import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:gwid/utils/theme_provider.dart';

class ChatSettingsScreen extends StatefulWidget {
  final bool isModal;

  const ChatSettingsScreen({super.key, this.isModal = false});

  @override
  State<ChatSettingsScreen> createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  bool _sendByEnter = false;
  bool _autoDownloadImages = true;
  bool _autoDownloadVideos = false;
  bool _autoDownloadFiles = false;
  bool _showLinkPreviews = true;
  bool _compactMode = false;
  double _fontSize = 16.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sendByEnter = prefs.getBool('chat_send_by_enter') ?? false;
      _autoDownloadImages = prefs.getBool('chat_auto_download_images') ?? true;
      _autoDownloadVideos = prefs.getBool('chat_auto_download_videos') ?? false;
      _autoDownloadFiles = prefs.getBool('chat_auto_download_files') ?? false;
      _showLinkPreviews = prefs.getBool('chat_show_link_previews') ?? true;
      _compactMode = prefs.getBool('chat_compact_mode') ?? false;
      _fontSize = prefs.getDouble('chat_font_size') ?? 16.0;
      _isLoading = false;
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = context.watch<ThemeProvider>();

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: !widget.isModal
          ? AppBar(
              title: const Text('Настройки чатов'),
              backgroundColor: colors.surface,
              foregroundColor: colors.onSurface,
              elevation: 0,
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (widget.isModal)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border(
                    bottom: BorderSide(color: colors.outline.withValues(alpha: 0.2)),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const Expanded(
                      child: Text(
                        'Настройки чатов',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSection('Отправка сообщений', colors),
                  _buildSwitchTile(
                    'Отправка по Enter',
                    'Отправлять сообщение при нажатии Enter',
                    Icons.keyboard_return,
                    _sendByEnter,
                    (value) {
                      setState(() => _sendByEnter = value);
                      _saveSetting('chat_send_by_enter', value);
                    },
                  ),
                  const SizedBox(height: 24),

                  _buildSection('Автозагрузка медиа', colors),
                  _buildSwitchTile(
                    'Изображения',
                    'Автоматически загружать изображения',
                    Icons.image,
                    _autoDownloadImages,
                    (value) {
                      setState(() => _autoDownloadImages = value);
                      _saveSetting('chat_auto_download_images', value);
                    },
                  ),
                  _buildSwitchTile(
                    'Видео',
                    'Автоматически загружать видео',
                    Icons.videocam,
                    _autoDownloadVideos,
                    (value) {
                      setState(() => _autoDownloadVideos = value);
                      _saveSetting('chat_auto_download_videos', value);
                    },
                  ),
                  _buildSwitchTile(
                    'Файлы',
                    'Автоматически загружать документы',
                    Icons.insert_drive_file,
                    _autoDownloadFiles,
                    (value) {
                      setState(() => _autoDownloadFiles = value);
                      _saveSetting('chat_auto_download_files', value);
                    },
                  ),
                  const SizedBox(height: 24),

                  _buildSection('Отображение', colors),
                  _buildSwitchTile(
                    'Превью ссылок',
                    'Показывать предпросмотр веб-ссылок',
                    Icons.link,
                    _showLinkPreviews,
                    (value) {
                      setState(() => _showLinkPreviews = value);
                      _saveSetting('chat_show_link_previews', value);
                    },
                  ),
                  _buildSwitchTile(
                    'Компактный режим',
                    'Уменьшить отступы между сообщениями',
                    Icons.view_compact,
                    _compactMode,
                    (value) {
                      setState(() => _compactMode = value);
                      _saveSetting('chat_compact_mode', value);
                      theme.setChatCompactMode(value);
                    },
                  ),
                  const SizedBox(height: 16),

                  _buildFontSizeSlider(colors),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors.primary,
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: colors.primary),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: colors.onSurfaceVariant,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildFontSizeSlider(ColorScheme colors) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.format_size, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Размер шрифта',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '${_fontSize.toInt()} pt',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Slider(
              value: _fontSize,
              min: 12,
              max: 22,
              divisions: 10,
              label: _fontSize.toInt().toString(),
              onChanged: (value) {
                setState(() => _fontSize = value);
              },
              onChangeEnd: (value) {
                _saveSetting('chat_font_size', value);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('A', style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                Text('A', style: TextStyle(fontSize: 16, color: colors.onSurfaceVariant)),
                Text('A', style: TextStyle(fontSize: 22, color: colors.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
