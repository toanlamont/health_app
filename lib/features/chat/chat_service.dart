import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api_client.dart';

class ChatMessage {
  ChatMessage({required this.role, required this.content});

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    role: json['role'] as String,
    content: json['content'] as String,
  );

  /// `user` or `assistant`.
  final String role;
  String content;
}

class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    title: json['title'] as String,
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  final String id;
  final String title;
  final DateTime updatedAt;
}

/// One thing that happened while a reply streamed in.
sealed class ChatEvent {}

/// First event of every reply: the conversation it was saved to.
class ChatMeta extends ChatEvent {
  ChatMeta(this.conversationId, this.title);
  final String conversationId;
  final String title;
}

/// The model is looking at the user's data with tool [name].
class ChatToolUse extends ChatEvent {
  ChatToolUse(this.name);
  final String name;
}

class ChatDelta extends ChatEvent {
  ChatDelta(this.text);
  final String text;
}

/// Conversations are kept on the server; the app only sends the new message.
///
/// `POST /chat/stream` answers with Server-Sent Events: `event: meta`
/// {conversation_id, title}, any number of `event: tool` {name}, unnamed
/// `data: {"delta": "..."}` frames, then `data: [DONE]` — or `event: error`
/// {detail} if the model fails.
class ChatService {
  final _api = ApiClient();

  Future<List<Conversation>> conversations() async {
    final res = await _api.dio.get<List<dynamic>>('/chat/conversations');
    return res.data!
        .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatMessage>> messages(String conversationId) async {
    final res = await _api.dio.get<List<dynamic>>(
      '/chat/conversations/$conversationId/messages',
    );
    return res.data!
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> delete(String conversationId) =>
      _api.dio.delete<void>('/chat/conversations/$conversationId');

  Stream<ChatEvent> send(
    String message, {
    String? conversationId,
    CancelToken? cancel,
  }) async* {
    final res = await _api.dio.post<ResponseBody>(
      '/chat/stream',
      data: {'message': message, 'conversation_id': ?conversationId},
      cancelToken: cancel,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
        // No overall deadline: a reply can take as long as the model does.
        receiveTimeout: Duration.zero,
        // Let 4xx through so its detail (e.g. the 429 "used up your
        // messages" text) can be read off the stream and shown as is.
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (res.statusCode != 200) {
      final body = await utf8.decodeStream(res.data!.stream.cast<List<int>>());
      throw ChatException(
        _tryDecode(body)?['detail']?.toString() ?? 'Lỗi ${res.statusCode}',
      );
    }

    String? event;
    final data = <String>[];

    await for (final line
        in res.data!.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.isEmpty) {
        // Blank line = end of one event.
        if (data.isNotEmpty) {
          final payload = data.join('\n');
          if (payload == '[DONE]') return;
          final json = _tryDecode(payload);
          switch (event) {
            case 'error':
              throw ChatException(json?['detail']?.toString() ?? payload);
            case 'meta':
              yield ChatMeta(
                json!['conversation_id'] as String,
                json['title'] as String,
              );
            case 'tool':
              yield ChatToolUse(json?['name']?.toString() ?? '');
            default:
              final delta = json?['delta'];
              if (delta is String && delta.isNotEmpty) yield ChatDelta(delta);
          }
        }
        event = null;
        data.clear();
      } else if (line.startsWith(':')) {
        continue; // comment / keep-alive
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        var v = line.substring(5);
        if (v.startsWith(' ')) v = v.substring(1);
        data.add(v);
      }
    }
  }

  Map<String, dynamic>? _tryDecode(String s) {
    try {
      final d = jsonDecode(s);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }
}

class ChatException implements Exception {
  ChatException(this.message);
  final String message;
  @override
  String toString() => message;
}
