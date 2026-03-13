import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ChannelSettingsScreen extends StatefulWidget {
  final int chatId;
  final Map<String, dynamic> channelData;
  final int myId;

  const ChannelSettingsScreen({
    super.key,
    required this.chatId,
    required this.channelData,
    required this.myId,
  });

  @override
  State<ChannelSettingsScreen> createState() {
    return _ChannelSettingsScreenState();
  }
}

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen> {
  bool _showDetails = false;
  bool _showParticipants = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    try {
      // Безопасное получение данных
      final title = widget.channelData['title'] as String? ?? 'Канал';
      final options =
          widget.channelData['options'] as Map<String, dynamic>? ?? {};
      final isOfficial = options['OFFICIAL'] == true;
      final access = widget.channelData['access'] as String? ?? 'PRIVATE';
      final link = widget.channelData['link'] as String?;
      final created = widget.channelData['created'] as int?;
      final joinTime = widget.channelData['joinTime'] as int?;
      final participantsCount =
          widget.channelData['participantsCount'] as int? ?? 0;
      final participants =
          widget.channelData['participants'] as Map<String, dynamic>? ?? {};
      final adminParticipants =
          widget.channelData['adminParticipants'] as Map<String, dynamic>? ??
          {};
      final owner = widget.channelData['owner'] as int?;

      return Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title),
              if (isOfficial) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified, color: Colors.blue, size: 20),
              ],
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Статус канала
            _buildInfoCard(
              title: 'Статус канала',
              children: [
                _buildInfoRow(
                  'Тип',
                  access == 'PRIVATE' ? 'Приватный' : 'Публичный',
                  icon: access == 'PRIVATE' ? Icons.lock : Icons.public,
                ),
                if (isOfficial)
                  _buildInfoRow(
                    'Официальный',
                    'Да',
                    icon: Icons.verified,
                    valueColor: Colors.blue,
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Ссылка-приглашение
            if (link != null)
              _buildInfoCard(
                title: 'Пригласительная ссылка',
                children: [
                  InkWell(
                    onTap: () => _copyToClipboard(link),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.link, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              link,
                              style: const TextStyle(
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.copy, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 16),

            // Настройки канала
            _buildInfoCard(
              title: 'Настройки канала',
              children: [
                _buildSettingRow(
                  'Подпись администратора',
                  options['SIGN_ADMIN'] == true,
                ),
                _buildSettingRow(
                  'Все могут закреплять сообщения',
                  options['ALL_CAN_PIN_MESSAGE'] == true,
                ),
                _buildSettingRow(
                  'Только админы могут звонить',
                  options['ONLY_ADMIN_CAN_CALL'] == true,
                ),
                _buildSettingRow(
                  'Только админы могут добавлять участников',
                  options['ONLY_ADMIN_CAN_ADD_MEMBER'] == true,
                ),
                _buildSettingRow(
                  'Только владелец может менять иконку/название',
                  options['ONLY_OWNER_CAN_CHANGE_ICON_TITLE'] == true,
                ),
                _buildSettingRow(
                  'Запрет копирования сообщений',
                  options['MESSAGE_COPY_NOT_ALLOWED'] == true,
                ),
                _buildSettingRow(
                  'Запрос на вступление',
                  options['JOIN_REQUEST'] == true,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Участники
            _buildInfoCard(
              title: 'Участники ($participantsCount)',
              children: [
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Показать участников'),
                    trailing: Icon(
                      _showParticipants
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _showParticipants = expanded;
                      });
                    },
                    children: [
                      if (_showParticipants)
                        SizedBox(
                          height: 320,
                          child: _ParticipantsList(
                            owner: owner,
                            adminParticipants: adminParticipants,
                            participants: participants,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Подробная информация
            _buildInfoCard(
              title: 'Подробная информация',
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _showDetails = !_showDetails;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 20),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('Показать детали')),
                        Icon(
                          _showDetails
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showDetails) ...[
                  const Divider(),
                  if (created != null)
                    _buildInfoRow(
                      'Дата создания',
                      _formatDate(created),
                      icon: Icons.calendar_today,
                    ),
                  if (joinTime != null)
                    _buildInfoRow(
                      'Дата присоединения',
                      _formatDate(joinTime),
                      icon: Icons.login,
                    ),
                  _buildInfoRow(
                    'ID канала',
                    widget.chatId.toString(),
                    icon: Icons.tag,
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    } catch (e) {
      return Scaffold(
        appBar: AppBar(title: const Text('Канал')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Ошибка отображения настроек канала: $e'),
        ),
      );
    }
  }

  Widget _buildInfoCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    IconData? icon,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w500, color: valueColor),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow(String label, bool enabled) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: enabled
                  ? Colors.green.withOpacity(0.2)
                  : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              enabled ? 'Можно' : 'Нельзя',
              style: TextStyle(
                color: enabled ? Colors.green : Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('dd.MM.yyyy HH:mm').format(date);
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }
}

class _ParticipantsList extends StatelessWidget {
  final int? owner;
  final Map<String, dynamic> adminParticipants;
  final Map<String, dynamic> participants;

  const _ParticipantsList({
    required this.owner,
    required this.adminParticipants,
    required this.participants,
  });

  @override
  Widget build(BuildContext context) {
    final entries = <_ParticipantEntry>[];

    if (owner != null) {
      entries.add(
        _ParticipantEntry(userId: owner!, isOwner: true, isAdmin: false),
      );
    }

    for (final key in adminParticipants.keys) {
      final userId = int.tryParse(key) ?? 0;
      if (owner != null && userId == owner) continue;
      entries.add(
        _ParticipantEntry(userId: userId, isOwner: false, isAdmin: true),
      );
    }

    for (final key in participants.keys) {
      if (adminParticipants.containsKey(key)) continue;
      final userId = int.tryParse(key) ?? 0;
      if (owner != null && userId == owner) continue;
      entries.add(
        _ParticipantEntry(userId: userId, isOwner: false, isAdmin: false),
      );
    }

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final e = entries[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.person, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text('ID: ${e.userId}')),
              if (e.isOwner)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Владелец',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else if (e.isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Админ',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ParticipantEntry {
  final int userId;
  final bool isOwner;
  final bool isAdmin;

  _ParticipantEntry({
    required this.userId,
    required this.isOwner,
    required this.isAdmin,
  });
}
