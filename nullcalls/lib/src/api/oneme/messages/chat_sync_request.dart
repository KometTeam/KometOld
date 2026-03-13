class ChatSyncRequest {
  final String token;
  final bool interactive;
  final int chatsCount;
  final int chatsSync;
  final int contactsSync;
  final int presenceSync;
  final int draftsSync;

  const ChatSyncRequest({
    required this.token,
    required this.interactive,
    required this.chatsCount,
    required this.chatsSync,
    required this.contactsSync,
    required this.presenceSync,
    required this.draftsSync,
  });

  factory ChatSyncRequest.create(String token) {
    return ChatSyncRequest(
      token: token,
      interactive: false,
      chatsCount: 40,
      chatsSync: 0,
      contactsSync: 0,
      presenceSync: 0,
      draftsSync: 0,
    );
  }

  static int get opcode => 19;

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'interactive': interactive,
      'chatsCount': chatsCount,
      'chatsSync': chatsSync,
      'contactsSync': contactsSync,
      'presenceSync': presenceSync,
      'draftsSync': draftsSync,
    };
  }
}
