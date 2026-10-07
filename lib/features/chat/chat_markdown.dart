import 'package:flutter/material.dart';

/// The handful of Markdown the assistant actually writes: bold, italic, inline
/// code, headings and bullet or numbered lists.
///
/// A full Markdown package would be overkill for a chat bubble, and a reply is
/// rendered again on every streamed chunk, so a marker that has not been closed
/// yet has to stay as plain text instead of swallowing the rest of the line.
TextSpan chatMarkdown(String source, TextStyle base) {
  final spans = <InlineSpan>[];
  final lines = source.split('\n');

  for (int i = 0; i < lines.length; i++) {
    var line = lines[i];
    var style = base;

    final heading = RegExp(r'^\s{0,3}(#{1,6})\s+').firstMatch(line);
    final bullet = RegExp(r'^(\s*)[-*+]\s+').firstMatch(line);
    final numbered = RegExp(r'^(\s*)(\d+)[.)]\s+').firstMatch(line);

    if (heading != null) {
      line = line.substring(heading.end);
      style = base.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: (base.fontSize ?? 14) + (heading.group(1)!.length <= 2 ? 2 : 1),
      );
    } else if (bullet != null) {
      final depth = bullet.group(1)!.length ~/ 2;
      spans.add(TextSpan(text: '${'    ' * depth}•  ', style: base));
      line = line.substring(bullet.end);
    } else if (numbered != null) {
      final depth = numbered.group(1)!.length ~/ 2;
      spans.add(
        TextSpan(text: '${'    ' * depth}${numbered.group(2)}.  ', style: base),
      );
      line = line.substring(numbered.end);
    } else if (RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line)) {
      line = '';
    }

    spans.addAll(_inline(line, style));
    if (i < lines.length - 1) spans.add(TextSpan(text: '\n', style: base));
  }

  return TextSpan(style: base, children: spans);
}

/// `**bold**` / `__bold__`, `*italic*` / `_italic_` and `` `code` ``.
final _inlinePattern = RegExp(
  r'`([^`\n]+)`'
  r'|\*\*(.+?)\*\*'
  r'|__(.+?)__'
  r'|(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])'
  r'|(?<![\w_])_(?!\s)(.+?)(?<!\s)_(?![\w_])',
);

List<InlineSpan> _inline(String text, TextStyle style) {
  final spans = <InlineSpan>[];
  int last = 0;

  for (final m in _inlinePattern.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start), style: style));
    }
    if (m.group(1) != null) {
      spans.add(
        TextSpan(
          text: m.group(1),
          style: style.copyWith(
            fontFamily: 'monospace',
            backgroundColor: style.color?.withValues(alpha: 0.08),
          ),
        ),
      );
    } else if (m.group(2) != null || m.group(3) != null) {
      // Bold can hold italic or code, e.g. **nhịp *tim***.
      spans.addAll(
        _inline(
          m.group(2) ?? m.group(3)!,
          style.copyWith(fontWeight: FontWeight.w700),
        ),
      );
    } else {
      spans.addAll(
        _inline(
          m.group(4) ?? m.group(5)!,
          style.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    last = m.end;
  }

  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last), style: style));
  }
  return spans;
}
