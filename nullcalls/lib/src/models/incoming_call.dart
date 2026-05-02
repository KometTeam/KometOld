import 'dart:convert';
import 'dart:typed_data';

/// Входящий звонок (opcode 137)
class IncomingCallJson {
  final String vcp;
  final int callerId;
  final String conversationId;

  const IncomingCallJson({
    required this.vcp,
    required this.callerId,
    required this.conversationId,
  });

  factory IncomingCallJson.fromJson(Map<String, dynamic> json) {
    return IncomingCallJson(
      vcp: json['vcp'] as String,
      callerId: json['callerId'] as int,
      conversationId: json['conversationId'] as String,
    );
  }
}

class VcpDecoded {
  final String signalingToken;
  final String signalingServer;
  final String stunServer;
  final String turnServers;
  final String turnUser;
  final String turnPassword;

  const VcpDecoded({
    required this.signalingToken,
    required this.signalingServer,
    required this.stunServer,
    required this.turnServers,
    required this.turnUser,
    required this.turnPassword,
  });

  factory VcpDecoded.fromJson(Map<String, dynamic> json) {
    return VcpDecoded(
      signalingToken: json['tkn'] as String,
      signalingServer: json['wse'] as String,
      stunServer: json['stne'] as String,
      turnServers: json['trne'] as String,
      turnUser: json['trnu'] as String,
      turnPassword: json['trnp'] as String,
    );
  }
}

class TurnServer {
  final List<String> servers;
  final String user;
  final String password;

  const TurnServer({
    required this.servers,
    required this.user,
    required this.password,
  });
}

class SignalingServer {
  final String token;
  final String url;

  const SignalingServer({
    required this.token,
    required this.url,
  });
}

class IncomingCall {
  final TurnServer turn;
  final SignalingServer signaling;
  final String stun;
  final int callerId;
  final String conversationId;

  const IncomingCall({
    required this.turn,
    required this.signaling,
    required this.stun,
    required this.callerId,
    required this.conversationId,
  });

  factory IncomingCall.fromJson(IncomingCallJson raw) {
    final decodedVcp = _decodeVcp(raw.vcp);

    final turn = TurnServer(
      servers: decodedVcp.turnServers.split(','),
      user: decodedVcp.turnUser,
      password: decodedVcp.turnPassword,
    );

    final signaling = SignalingServer(
      token: decodedVcp.signalingToken,
      url: decodedVcp.signalingServer,
    );

    return IncomingCall(
      turn: turn,
      signaling: signaling,
      stun: decodedVcp.stunServer,
      callerId: raw.callerId,
      conversationId: raw.conversationId,
    );
  }

  static int get opcode => 137;
}

VcpDecoded _decodeVcp(String vcp) {
  final parts = vcp.split(':');
  if (parts.length != 2) {
    throw const FormatException('Invalid vcp format');
  }

  final uncompressedSize = int.parse(parts[0]);
  final compressedBase64 = parts[1];

  // Decode base64
  final compressed = base64.decode(compressedBase64);

  // Decompress LZ4
  final decompressed = _lz4Decompress(compressed, uncompressedSize);

  // Parse JSON
  final jsonString = utf8.decode(decompressed);
  final jsonData = json.decode(jsonString) as Map<String, dynamic>;

  return VcpDecoded.fromJson(jsonData);
}

Uint8List _lz4Decompress(List<int> compressed, int uncompressedSize) {
  // Simple LZ4 block decompression implementation
  final src = Uint8List.fromList(compressed);
  final dst = Uint8List(uncompressedSize);
  
  int srcPos = 0;
  int dstPos = 0;
  
  while (srcPos < src.length && dstPos < uncompressedSize) {
    final token = src[srcPos++];
    
    int literalLength = token >> 4;
    if (literalLength == 15) {
      while (srcPos < src.length) {
        final len = src[srcPos++];
        literalLength += len;
        if (len != 255) break;
      }
    }
    
    if (literalLength > 0) {
      dst.setRange(dstPos, dstPos + literalLength, src, srcPos);
      srcPos += literalLength;
      dstPos += literalLength;
    }
    
    if (srcPos >= src.length) break;
    
    final offset = src[srcPos] | (src[srcPos + 1] << 8);
    srcPos += 2;
    
    int matchLength = (token & 0x0F) + 4;
    if (matchLength == 19) {
      while (srcPos < src.length) {
        final len = src[srcPos++];
        matchLength += len;
        if (len != 255) break;
      }
    }
    
    int matchPos = dstPos - offset;
    for (int i = 0; i < matchLength; i++) {
      dst[dstPos++] = dst[matchPos++];
    }
  }
  
  return dst;
}
