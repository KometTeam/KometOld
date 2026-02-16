import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gwid/utils/theme_provider.dart';

class BypassScreen extends StatefulWidget {
  final bool isModal;

  const BypassScreen({super.key, this.isModal = false});

  @override
  State<BypassScreen> createState() => _BypassScreenState();
}

class _BypassScreenState extends State<BypassScreen> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    if (widget.isModal) {
      final colors = Theme.of(context).colorScheme;
      return _buildModalSettings(context, colors, themeProvider);
    }
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("Специальные возможности и фишки")),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          // Обход блокировки
          Text(
            "ОБХОД БЛОКИРОВКИ",
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return SwitchListTile(
                title: const Text(
                  "Обход блокировки",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  "Разрешить отправку сообщений заблокированным пользователям",
                ),
                value: themeProvider.blockBypass,
                onChanged: (value) {
                  themeProvider.setBlockBypass(value);
                },
                secondary: Icon(
                  themeProvider.blockBypass
                      ? Icons.psychology
                      : Icons.psychology_outlined,
                  color: themeProvider.blockBypass
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Фишки (цветные никнеймы, скоро)
          Text(
            "ФИШКИ (KOMET.COLOR)",
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text(
              'Авто-дополнение уникальных сообщений',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Показывать панель выбора цвета при вводе komet.color#',
            ),
            value: themeProvider.kometAutoCompleteEnabled,
            onChanged: (value) {
              themeProvider.setKometAutoCompleteEnabled(value);
            },
            secondary: Icon(
              themeProvider.kometAutoCompleteEnabled
                  ? Icons.auto_awesome
                  : Icons.auto_awesome_outlined,
              color: themeProvider.kometAutoCompleteEnabled
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),
          ),
          SwitchListTile(
            title: const Text(
              'Включить список особых сообщений',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Показывать кнопку для быстрой вставки шаблонов особых сообщений',
            ),
            value: themeProvider.specialMessagesEnabled,
            onChanged: (value) {
              themeProvider.setSpecialMessagesEnabled(value);
            },
            secondary: Icon(
              themeProvider.specialMessagesEnabled
                  ? Icons.auto_fix_high
                  : Icons.auto_fix_high_outlined,
              color: themeProvider.specialMessagesEnabled
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalSettings(
    BuildContext context,
    ColorScheme colors,
    ThemeProvider themeProvider,
  ) {
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text("Специальные возможности и фишки"),
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          Text(
            "ОБХОД БЛОКИРОВКИ",
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text(
              "Обход блокировки",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              "Разрешить отправку сообщений заблокированным пользователям",
            ),
            value: themeProvider.blockBypass,
            onChanged: (value) {
              themeProvider.setBlockBypass(value);
            },
            secondary: Icon(
              themeProvider.blockBypass
                  ? Icons.psychology
                  : Icons.psychology_outlined,
              color: themeProvider.blockBypass
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          Text(
            "ФИШКИ (KOMET.COLOR)",
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text(
              'Авто-дополнение уникальных сообщений',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Показывать панель выбора цвета при вводе komet.color#',
            ),
            value: themeProvider.kometAutoCompleteEnabled,
            onChanged: (value) {
              themeProvider.setKometAutoCompleteEnabled(value);
            },
            secondary: Icon(
              themeProvider.kometAutoCompleteEnabled
                  ? Icons.auto_awesome
                  : Icons.auto_awesome_outlined,
              color: themeProvider.kometAutoCompleteEnabled
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),
          ),
          SwitchListTile(
            title: const Text(
              'Включить список особых сообщений',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Показывать кнопку для быстрой вставки шаблонов особых сообщений',
            ),
            value: themeProvider.specialMessagesEnabled,
            onChanged: (value) {
              themeProvider.setSpecialMessagesEnabled(value);
            },
            secondary: Icon(
              themeProvider.specialMessagesEnabled
                  ? Icons.auto_fix_high
                  : Icons.auto_fix_high_outlined,
              color: themeProvider.specialMessagesEnabled
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
