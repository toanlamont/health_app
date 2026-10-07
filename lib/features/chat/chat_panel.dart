import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'chat_service.dart';
import 'mascot.dart';

/// What the mascot says it is doing while a tool runs.
const _toolLabels = {
  'get_profile': 'Đang xem hồ sơ…',
  'get_heart_rate': 'Đang xem nhịp tim…',
  'get_weight': 'Đang xem cân nặng…',
  'get_meals': 'Đang xem bữa ăn…',
  'get_goals': 'Đang xem mục tiêu…',
  'get_reminders': 'Đang xem lời nhắc…',
};

/// The conversation itself, shown inside the floating window of [ChatHead].
///
/// Conversations live on the server, so "new chat" only starts another one;
/// earlier ones are under the history button. The panel stays mounted while
/// the window is closed, so a reply still streaming in carries on.
class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _service = ChatService();
  final _input = TextEditingController();
  final _scroll = ScrollController();

  String? _conversationId;
  String? _title;
  List<ChatMessage> _messages = [];
  bool _loadingMessages = false;

  StreamSubscription<ChatEvent>? _sub;
  CancelToken? _cancel;
  bool _streaming = false;
  String? _toolStatus;

  /// Showing the list of conversations instead of the current one.
  bool _showHistory = false;
  List<Conversation>? _conversations;
  bool _historyFailed = false;

  @override
  void dispose() {
    _cancel?.cancel();
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _stop() {
    _cancel?.cancel();
    _sub?.cancel();
    _sub = null;
    if (_streaming) {
      setState(() {
        _streaming = false;
        _toolStatus = null;
        // Nothing arrived before stop: drop the empty placeholder bubble.
        if (_messages.isNotEmpty && _messages.last.content.isEmpty) {
          _messages.removeLast();
        }
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _newChat() {
    _stop();
    setState(() {
      _conversationId = null;
      _title = null;
      _messages = [];
      _showHistory = false;
    });
  }

  Future<void> _openHistory() async {
    setState(() {
      _showHistory = true;
      _historyFailed = false;
    });
    try {
      final list = await _service.conversations();
      if (mounted) setState(() => _conversations = list);
    } catch (_) {
      if (mounted) setState(() => _historyFailed = true);
    }
  }

  Future<void> _openConversation(Conversation c) async {
    _stop();
    setState(() {
      _showHistory = false;
      _conversationId = c.id;
      _title = c.title;
      _messages = [];
      _loadingMessages = true;
    });
    try {
      final messages = await _service.messages(c.id);
      // Another conversation may have been opened while this one loaded.
      if (!mounted || _conversationId != c.id) return;
      setState(() {
        _messages = messages;
        _loadingMessages = false;
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted || _conversationId != c.id) return;
      setState(() => _loadingMessages = false);
      _showError('Không tải được cuộc trò chuyện');
    }
  }

  Future<void> _deleteConversation(Conversation c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá cuộc trò chuyện?'),
        content: Text('"${c.title}" sẽ bị xoá vĩnh viễn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.delete(c.id);
      if (!mounted) return;
      setState(() => _conversations?.removeWhere((x) => x.id == c.id));
      if (_conversationId == c.id) _newChat();
    } catch (_) {
      if (mounted) _showError('Không xoá được, thử lại sau');
    }
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty || _streaming || _loadingMessages) return;
    _input.clear();

    final reply = ChatMessage(role: 'assistant', content: '');
    setState(() {
      _messages
        ..add(ChatMessage(role: 'user', content: text))
        ..add(reply);
      _streaming = true;
      _toolStatus = null;
    });
    _scrollToEnd();

    _cancel = CancelToken();
    _sub = _service
        .send(text, conversationId: _conversationId, cancel: _cancel)
        .listen(
          (event) {
            setState(() {
              switch (event) {
                case ChatMeta(:final conversationId, :final title):
                  _conversationId = conversationId;
                  _title = title;
                case ChatToolUse(:final name):
                  _toolStatus = _toolLabels[name] ?? 'Đang tra cứu…';
                case ChatDelta(:final text):
                  _toolStatus = null;
                  reply.content += text;
              }
            });
            _scrollToEnd();
          },
          onError: (Object e) {
            if (e is DioException && CancelToken.isCancel(e)) return;
            if (!mounted) return;
            setState(() {
              _streaming = false;
              _toolStatus = null;
              if (reply.content.isEmpty) _messages.remove(reply);
            });
            _showError(
              e is ChatException
                  ? e.message
                  : 'Không nhận được phản hồi: ${_describe(e)}',
            );
          },
          onDone: () {
            if (mounted) {
              setState(() {
                _streaming = false;
                _toolStatus = null;
              });
            }
          },
          cancelOnError: true,
        );
  }

  String _describe(Object e) {
    if (e is ChatException) return e.message;
    if (e is DioException) return e.message ?? 'lỗi kết nối';
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(context),
        const Divider(height: 1),
        Expanded(child: _showHistory ? _history(context) : _chat(context)),
      ],
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
      child: Row(
        children: [
          if (_showHistory)
            IconButton(
              tooltip: 'Quay lại',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _showHistory = false),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Mascot(size: 36),
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _showHistory ? 'Lịch sử trò chuyện' : (_title ?? 'Tim'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (!_showHistory)
                  Text(
                    _streaming
                        ? (_toolStatus ?? 'Đang trả lời…')
                        : 'Trợ lý sức khoẻ AI',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (!_showHistory)
            IconButton(
              tooltip: 'Lịch sử trò chuyện',
              icon: const Icon(Icons.history),
              onPressed: _openHistory,
            ),
          IconButton(
            tooltip: 'Cuộc trò chuyện mới',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newChat,
          ),
          IconButton(
            tooltip: 'Thu nhỏ',
            icon: const Icon(Icons.close),
            onPressed: () {
              FocusScope.of(context).unfocus();
              widget.onClose();
            },
          ),
        ],
      ),
    );
  }

  Widget _history(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = _conversations;
    if (_historyFailed) {
      return Center(
        child: TextButton.icon(
          onPressed: _openHistory,
          icon: const Icon(Icons.refresh),
          label: const Text('Không tải được, thử lại'),
        ),
      );
    }
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) {
      return Center(
        child: Text(
          'Chưa có cuộc trò chuyện nào',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final fmt = DateFormat('dd/MM HH:mm');
    return RefreshIndicator(
      onRefresh: _openHistory,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: list.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
        itemBuilder: (_, i) {
          final c = list[i];
          final current = c.id == _conversationId;
          return ListTile(
            selected: current,
            leading: const Icon(Icons.chat_bubble_outline),
            title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(fmt.format(c.updatedAt)),
            trailing: IconButton(
              tooltip: 'Xoá',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteConversation(c),
            ),
            onTap: () => _openConversation(c),
          );
        },
      ),
    );
  }

  Widget _chat(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: _loadingMessages
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Mascot(size: 72),
                        const SizedBox(height: 12),
                        Text(
                          'Chào bạn, mình là Tim! Hỏi mình về nhịp tim, '
                          'cân nặng, bữa ăn hay mục tiêu của bạn nhé — '
                          'mình xem được số liệu bạn đã ghi trong app.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final pending =
                        _streaming &&
                        i == _messages.length - 1 &&
                        _messages[i].content.isEmpty;
                    return _Bubble(
                      message: _messages[i],
                      typing: pending,
                      status: pending ? _toolStatus : null,
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Nhắn cho Tim…',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: _streaming ? 'Dừng' : 'Gửi',
                icon: Icon(_streaming ? Icons.stop : Icons.send),
                onPressed: _streaming ? _stop : _send,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.typing, this.status});

  final ChatMessage message;
  final bool typing;

  /// What the assistant is doing before its first word, e.g. reading data.
  final String? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.role == 'user';
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.68,
      ),
      decoration: BoxDecoration(
        color: mine ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
      ),
      child: typing
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                if (status != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    status!,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            )
          : SelectableText(
              message.content,
              style: TextStyle(
                color: mine ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
    );
    if (mine) return Align(alignment: Alignment.centerRight, child: bubble);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Mascot(size: 26),
        const SizedBox(width: 6),
        Flexible(child: bubble),
      ],
    );
  }
}
