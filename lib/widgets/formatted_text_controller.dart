import 'package:flutter/material.dart';

class FormattedTextController extends TextEditingController {
  final List<Map<String, dynamic>> elements = [];

  FormattedTextController({super.text});

  void refresh() {
    notifyListeners();
  }

  void clearStylesForSelection(TextSelection selection) {
    if (selection.isCollapsed) return;

    final start = selection.start;
    final end = selection.end;

    elements.removeWhere((el) {
      final elFrom = (el['from'] as int?) ?? 0;
      final elLen = (el['length'] as int?) ?? 0;
      final elEnd = elFrom + elLen;

      // Удаляем, если есть пересечение с выделением
      return (elFrom < end && elEnd > start);
    });

    refresh();
  }

  @override
  set value(TextEditingValue newValue) {
    final oldValue = super.value;
    super.value = newValue;
    _handleTextMutation(oldValue.text, newValue.text);
  }

  void _handleTextMutation(String oldText, String newText) {
    if (elements.isEmpty) return;
    if (oldText == newText) return;

    int prefix = 0;
    final minLen = oldText.length < newText.length
        ? oldText.length
        : newText.length;
    while (prefix < minLen &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }

    int oldSuffix = oldText.length;
    int newSuffix = newText.length;
    while (oldSuffix > prefix &&
        newSuffix > prefix &&
        oldText.codeUnitAt(oldSuffix - 1) ==
            newText.codeUnitAt(newSuffix - 1)) {
      oldSuffix--;
      newSuffix--;
    }

    final oldChangedLen = oldSuffix - prefix;
    final newChangedLen = newSuffix - prefix;

    final changeStart = prefix;
    final changeEndOld = prefix + oldChangedLen;

    final delta = newChangedLen - oldChangedLen;

    if (delta == 0 && oldChangedLen == 0) {
      return;
    }

    if (oldChangedLen == 0 && newChangedLen > 0) {
      _applyInsertion(changeStart, newChangedLen);
    } else if (newChangedLen == 0 && oldChangedLen > 0) {
      _applyDeletion(changeStart, changeEndOld);
    } else {
      _applyDeletion(changeStart, changeEndOld);
      if (newChangedLen > 0) {
        _applyInsertion(changeStart, newChangedLen);
      }
    }
  }

  void _applyInsertion(int pos, int insertLen) {
    if (insertLen <= 0) return;

    for (final el in elements) {
      final type = el['type'] as String?;
      final from = (el['from'] as int?) ?? 0;
      final length = (el['length'] as int?) ?? 0;
      if (length <= 0) continue;
      final end = from + length;

      if (type == 'QUOTE') {
        if (pos <= from) {
          el['from'] = from + insertLen;
        } else if (pos < end) {
          el['length'] = length + insertLen;
        }
        continue;
      }

      if (pos < from) {
        el['from'] = from + insertLen;
      } else if (pos < end) {
        el['length'] = length + insertLen;
      }
    }
  }

  void _applyDeletion(int delFrom, int delTo) {
    final delLen = delTo - delFrom;
    if (delLen <= 0) return;

    final toRemove = <Map<String, dynamic>>[];

    for (final el in elements) {
      int from = (el['from'] as int?) ?? 0;
      int length = (el['length'] as int?) ?? 0;
      if (length <= 0) {
        toRemove.add(el);
        continue;
      }
      final end = from + length;

      if (delTo <= from) {
        from -= delLen;
        el['from'] = from < 0 ? 0 : from;
        continue;
      }

      if (delFrom >= end) {
        continue;
      }

      final overlapStart = delFrom > from ? delFrom : from;
      final overlapEnd = delTo < end ? delTo : end;
      final overlapLen = overlapEnd - overlapStart;
      if (overlapLen <= 0) continue;

      if (delFrom <= from && delTo >= end) {
        toRemove.add(el);
        continue;
      }

      if (delFrom <= from) {
        final cut = delTo - from;
        from = delFrom;
        length -= cut;
        if (length <= 0) {
          toRemove.add(el);
        } else {
          el['from'] = from < 0 ? 0 : from;
          el['length'] = length;
        }
        continue;
      }

      if (delTo >= end) {
        length = delFrom - from;
        if (length <= 0) {
          toRemove.add(el);
        } else {
          el['length'] = length;
        }
        continue;
      }

      length -= delLen;
      if (length <= 0) {
        toRemove.add(el);
      } else {
        el['length'] = length;
      }
    }

    if (toRemove.isNotEmpty) {
      elements.removeWhere((e) => toRemove.contains(e));
    }
  }

  TextSpan _buildSpanWithoutQuote(
    BuildContext context,
    String text,
    TextStyle baseStyle,
    List<Map<String, dynamic>> elements,
  ) {
    if (text.isEmpty || elements.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    final bold = List<bool>.filled(text.length, false);
    final italic = List<bool>.filled(text.length, false);
    final underline = List<bool>.filled(text.length, false);
    final strike = List<bool>.filled(text.length, false);
    final quote = List<bool>.filled(text.length, false);
    final mention = List<bool>.filled(text.length, false);

    for (final el in elements) {
      final type = el['type'] as String?;
      final from = (el['from'] as int?) ?? 0;
      final length = (el['length'] as int?) ?? 0;
      if (type == null || length <= 0) continue;
      final start = from.clamp(0, text.length);
      final end = (from + length).clamp(0, text.length);
      for (int i = start; i < end; i++) {
        switch (type) {
          case 'STRONG':
            bold[i] = true;
            break;
          case 'EMPHASIZED':
            italic[i] = true;
            break;
          case 'UNDERLINE':
            underline[i] = true;
            break;
          case 'STRIKETHROUGH':
            strike[i] = true;
            break;
          case 'QUOTE':
            quote[i] = true;
            break;
          case 'USER_MENTION':
            mention[i] = true;
            break;
        }
      }
    }

    final spans = <InlineSpan>[];
    int start = 0;

    TextStyle styleForIndex(int i) {
      var s = baseStyle;
      if (mention[i]) {
        final theme = Theme.of(context);
        return s.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w500);
      }
      if (bold[i]) s = s.copyWith(fontWeight: FontWeight.w600);
      if (italic[i]) s = s.copyWith(fontStyle: FontStyle.italic);
      final decos = <TextDecoration>[];
      if (underline[i]) decos.add(TextDecoration.underline);
      if (strike[i]) decos.add(TextDecoration.lineThrough);
      if (decos.isNotEmpty) {
        s = s.copyWith(decoration: TextDecoration.combine(decos));
      }
      if (quote[i]) {
        final theme = Theme.of(context);
        s = s.copyWith(
          backgroundColor: theme.colorScheme.surfaceVariant.withValues(
            alpha: 0.55,
          ),
        );
      }
      return s;
    }

    while (start < text.length) {
      int end = start + 1;
      final base = styleForIndex(start);
      while (end < text.length && styleForIndex(end) == base) {
        end++;
      }
      spans.add(TextSpan(text: text.substring(start, end), style: base));
      start = end;
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool withComposing = false,
  }) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final text = value.text;

    if (text.isEmpty || elements.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    return _buildSpanWithoutQuote(context, text, baseStyle, elements);
  }
}
