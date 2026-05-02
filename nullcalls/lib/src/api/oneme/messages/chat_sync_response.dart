class ChatSyncResponse {
  final String? token;

  const ChatSyncResponse({this.token});

  factory ChatSyncResponse.fromJson(Map<String, dynamic> json) {
    return ChatSyncResponse(
      token: json['token'] as String?,
    );
  }
}
