import 'package:flutter/material.dart';

import 'chat_panel.dart';
import 'mascot.dart';

/// A Messenger-style chat head floating over [child].
///
/// The mascot bubble starts in the bottom-right corner, can be dragged
/// anywhere and snaps to the nearest side when let go. Tapping it opens the
/// chat as a floating window; the bubble parks in the top-right corner while
/// the window is open and goes back to where it was when it closes.
class ChatHead extends StatefulWidget {
  const ChatHead({super.key, required this.child});

  final Widget child;

  @override
  State<ChatHead> createState() => _ChatHeadState();
}

class _ChatHeadState extends State<ChatHead> {
  static const _size = 60.0;
  static const _margin = 12.0;
  static const _anim = Duration(milliseconds: 260);

  /// Top-left of the bubble when the window is closed; null until the first
  /// layout, when the default corner is known.
  Offset? _pos;
  bool _dragging = false;
  bool _open = false;

  Offset _clamp(Offset p, Size area) => Offset(
    p.dx.clamp(_margin, area.width - _size - _margin),
    p.dy.clamp(_margin, area.height - _size - _margin),
  );

  void _snapToSide(Size area) {
    final p = _clamp(_pos!, area);
    final left = p.dx + _size / 2 < area.width / 2;
    setState(() {
      _dragging = false;
      _pos = Offset(left ? _margin : area.width - _size - _margin, p.dy);
    });
  }

  void _setOpen(bool open) {
    if (!open) FocusScope.of(context).unfocus();
    setState(() => _open = open);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final area = box.biggest;
        _pos ??= Offset(
          area.width - _size - _margin - 4,
          area.height - _size - _margin - 8,
        );
        // Clamped only for display: the keyboard shrinks the area, and the
        // bubble should return to its spot once it closes.
        final bubbleAt = _open
            ? Offset(area.width - _size - _margin, _margin)
            : _clamp(_pos!, area);

        return Stack(
          children: [
            widget.child,

            // Dim the screen behind the window; tapping it closes the chat.
            IgnorePointer(
              ignoring: !_open,
              child: AnimatedOpacity(
                opacity: _open ? 1 : 0,
                duration: _anim,
                child: GestureDetector(
                  onTap: () => _setOpen(false),
                  child: Container(color: Colors.black38),
                ),
              ),
            ),

            // The window. Kept mounted while closed so the conversation lives on.
            Positioned(
              left: _margin,
              right: _margin,
              top: _margin + _size + 8,
              bottom: _margin,
              child: IgnorePointer(
                ignoring: !_open,
                child: AnimatedOpacity(
                  opacity: _open ? 1 : 0,
                  duration: _anim,
                  child: AnimatedScale(
                    scale: _open ? 1 : 0.6,
                    alignment: Alignment.topRight,
                    duration: _anim,
                    curve: Curves.easeOutBack,
                    child: Material(
                      elevation: 12,
                      clipBehavior: Clip.antiAlias,
                      borderRadius: BorderRadius.circular(24),
                      color: Theme.of(context).colorScheme.surface,
                      child: ChatPanel(onClose: () => _setOpen(false)),
                    ),
                  ),
                ),
              ),
            ),

            AnimatedPositioned(
              duration: _dragging ? Duration.zero : _anim,
              curve: Curves.easeOutCubic,
              left: bubbleAt.dx,
              top: bubbleAt.dy,
              child: GestureDetector(
                onTap: () => _setOpen(!_open),
                onPanStart: _open
                    ? null
                    : (_) => setState(() => _dragging = true),
                onPanUpdate: _open
                    ? null
                    : (d) =>
                          setState(() => _pos = _clamp(_pos! + d.delta, area)),
                onPanEnd: _open ? null : (_) => _snapToSide(area),
                child: AnimatedScale(
                  scale: _dragging ? 1.1 : 1,
                  duration: const Duration(milliseconds: 120),
                  child: Container(
                    width: _size,
                    height: _size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.surface,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Semantics(
                      button: true,
                      label: _open ? 'Thu nhỏ chat' : 'Chat với Tim',
                      child: const Mascot(size: 44),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
