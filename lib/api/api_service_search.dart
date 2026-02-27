part of 'api_service.dart';

extension ApiServiceSearch on ApiService {
  /// Глобальный поиск по чатам, контактам и сообщениям
  /// opcode 68 - поиск с маркером для пагинации (PUBLIC_CHATS и т.д.)
  /// opcode 60 - поиск типа ALL для получения всех результатов сразу
  Future<Map<String, dynamic>> globalSearch(
    String query, {
    int count = 30,
    String? marker,
    bool useTypeAll = false,
  }) async {
    await waitUntilOnline();

    final payload = <String, dynamic>{
      'query': query,
      'count': count,
      if (marker != null) 'marker': marker,
      if (useTypeAll) 'type': 'ALL',
    };

    // opcode 60 для поиска с type: ALL
    // opcode 68 для поиска с пагинацией
    final opcode = useTypeAll ? 60 : 68;

    final response = await sendRequest(opcode, payload);
    final responsePayload = response['payload'];

    if (responsePayload is Map<String, dynamic>) {
      return responsePayload;
    }

    if (responsePayload is Map) {
      return responsePayload.cast<String, dynamic>();
    }

    return <String, dynamic>{};
  }
}
