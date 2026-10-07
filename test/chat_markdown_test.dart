import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_app/features/chat/chat_markdown.dart';

List<TextSpan> _leaves(InlineSpan span) => [
      if (span is TextSpan && span.text != null) span,
      if (span is TextSpan)
        for (final c in span.children ?? const <InlineSpan>[]) ..._leaves(c),
    ];

void main() {
  const base = TextStyle(fontSize: 14);

  test('bold is rendered without its markers', () {
    final leaves = _leaves(chatMarkdown('Nhịp **72 bpm** là ổn', base));
    expect(leaves.map((s) => s.text).join(), 'Nhịp 72 bpm là ổn');
    final bold = leaves.firstWhere((s) => s.text == '72 bpm');
    expect(bold.style!.fontWeight, FontWeight.w700);
  });

  test('an unclosed marker mid-stream stays as typed', () {
    final leaves = _leaves(chatMarkdown('Nhịp **72', base));
    expect(leaves.map((s) => s.text).join(), 'Nhịp **72');
  });

  test('bullets, headings and italic', () {
    final text = _leaves(chatMarkdown('## Gợi ý\n- uống *đủ* nước\n1. ngủ sớm', base))
        .map((s) => s.text)
        .join();
    expect(text, 'Gợi ý\n•  uống đủ nước\n1.  ngủ sớm');
  });

  test('snake_case and 2*3*4 are left alone', () {
    final text = _leaves(chatMarkdown('heart_rate_avg = 2*3*4', base))
        .map((s) => s.text)
        .join();
    expect(text, 'heart_rate_avg = 2*3*4');
  });
}
