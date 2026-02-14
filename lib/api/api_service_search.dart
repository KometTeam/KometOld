part of 'api_service.dart';

extension ApiServiceSearch on ApiService {
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

    final opcode = useTypeAll ? 60 : 68;

    final response = await sendRequestWithVersion(10, opcode, payload);
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
