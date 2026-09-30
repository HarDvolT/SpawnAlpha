import 'package:flutter/material.dart';

import '../model/mark.dart';
import '../model/token.dart';

/// Colours for the delivery cues, in a dark (prompter) and a light
/// (editor) variant.
class CueColors {
  const CueColors({
    required this.text,
    required this.stress,
    required this.energy,
    required this.slower,
    required this.faster,
    required this.pause,
    required this.breath,
    required this.selection,
  });

  static const dark = CueColors(
    text: Color(0xFFF4F4F2),
    stress: Color(0xFFFFC940),
    energy: Color(0xFFFF8A65),
    slower: Color(0xFF40C4FF),
    faster: Color(0xFFFF9100),
    pause: Color(0xFFB388FF),
    breath: Color(0xFF69F0AE),
    selection: Color(0x33FFFFFF),
  );

  static const light = CueColors(
    text: Color(0xFF1C1B1F),
    stress: Color(0xFFD84315),
    energy: Color(0xFFC2185B),
    slower: Color(0xFF0288D1),
    faster: Color(0xFFEF6C00),
    pause: Color(0xFF5E35B1),
    breath: Color(0xFF2E7D32),
    selection: Color(0x331565C0),
  );

  final Color text;
  final Color stress;
  final Color energy;
  final Color slower;
  final Color faster;
  final Color pause;
  final Color breath;
  final Color selection;

  Color of(MarkKind kind) => switch (kind) {
        MarkKind.stress => stress,
        MarkKind.energy => energy,
        MarkKind.slower => slower,
        MarkKind.faster => faster,
        MarkKind.pauseShort || MarkKind.pauseLong => pause,
        MarkKind.breath => breath,
      };
}

/// Separates a cue icon from its word without letting a line break
/// between them (narrow no-break space).
const _thinSpace = '\u202F';

/// The icon for each kind of cue.
IconData cueIcon(MarkKind kind) => switch (kind) {
      MarkKind.stress => Icons.format_bold_rounded,
      MarkKind.pauseShort => Icons.pause_rounded,
      MarkKind.pauseLong => Icons.pause_circle_rounded,
      MarkKind.breath => Icons.air_rounded,
      MarkKind.slower => Icons.keyboard_double_arrow_down_rounded,
      MarkKind.faster => Icons.keyboard_double_arrow_up_rounded,
      MarkKind.energy => Icons.bolt_rounded,
    };

/// The spans that draw a cue inside the text.
///
/// Cue icons are drawn as glyphs of the icon font rather than as widget
/// spans: Flutter swaps widget spans between slots in right-to-left text,
/// which put Arabic cues on the wrong side of their words. Icon glyphs are
/// private-use characters, which the bidi algorithm treats as strong
/// left-to-right, so each glyph is its own run and stays where it is
/// written.
List<TextSpan> cueSpans(MarkKind kind, CueColors colors, double fontSize, {bool accepted = true}) {
  final color = colors.of(kind).withValues(alpha: accepted ? 1 : 0.5);
  final icon = cueIcon(kind);
  final glyph = TextSpan(
    text: String.fromCharCode(icon.codePoint),
    style: TextStyle(
      inherit: false,
      fontFamily: icon.fontFamily,
      package: icon.fontPackage,
      color: color,
      fontSize: fontSize * (kind == MarkKind.pauseLong ? 0.85 : 0.7),
      fontWeight: FontWeight.normal,
    ),
  );
  final label = switch (kind) {
    MarkKind.slower => 'slow',
    MarkKind.faster => 'fast',
    _ => null,
  };
  return [
    glyph,
    if (label != null)
      TextSpan(
        text: label,
        style: TextStyle(color: color, fontSize: fontSize * 0.38, fontWeight: FontWeight.w700),
      ),
  ];
}

/// A script rendered with its cues, plus where each token starts in the
/// rendered text, so callers can measure and hit-test words.
class MarkedText {
  const MarkedText(this.span, this.tokenOffsets, this.cueRanges);

  final InlineSpan span;

  /// For each token, its character offset in [span]'s plain text.
  final List<int> tokenOffsets;

  /// The character ranges of the cue icons, with the token each belongs
  /// to: the word a pace or energy run opens on, or the word a pause
  /// follows.
  final List<(int start, int end, int token)> cueRanges;

  /// The token at character [offset] of the rendered text, or null.
  int? tokenAtOffset(int offset, List<Token> tokens) {
    var low = 0;
    var high = tokenOffsets.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final start = tokenOffsets[mid];
      if (offset < start) {
        high = mid - 1;
      } else if (offset >= start + tokens[mid].text.length) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    return null;
  }

  /// The token a tap at character [offset] refers to: the word itself, the
  /// word a cue icon belongs to, or else the word before.
  int? tokenForTap(int offset, List<Token> tokens) {
    final word = tokenAtOffset(offset, tokens);
    if (word != null) return word;
    for (final (start, end, token) in cueRanges) {
      if (offset >= start && offset < end) return token;
    }
    int? before;
    for (var i = 0; i < tokenOffsets.length && tokenOffsets[i] <= offset; i++) {
      before = i;
    }
    return before;
  }

  /// Builds the span for [tokens] with [marks]:
  /// - stressed words are larger, heavier and coloured;
  /// - energy runs are coloured and open with a bolt;
  /// - slower and faster runs are tinted and open with a labelled arrow;
  /// - pauses and breaths are icons in the gap after their word.
  ///
  /// Marks that are not accepted are drawn faded, for review in the
  /// editor. [selected] tokens get a highlight.
  static MarkedText build({
    required List<Token> tokens,
    required List<Mark> marks,
    required TextStyle style,
    required CueColors colors,
    Set<int> selected = const {},
  }) {
    final n = tokens.length;
    final stress = List<Mark?>.filled(n, null);
    final energy = List<Mark?>.filled(n, null);
    final pace = List<Mark?>.filled(n, null);
    final gapAfter = List<Mark?>.filled(n, null);
    final opening = List<List<Mark>>.generate(n, (_) => []);
    for (final m in marks) {
      if (m.end >= n) continue;
      switch (m.kind) {
        case MarkKind.pauseShort || MarkKind.pauseLong || MarkKind.breath:
          gapAfter[m.end] = m;
        case MarkKind.stress:
          for (var i = m.start; i <= m.end; i++) {
            stress[i] = m;
          }
        case MarkKind.energy:
          for (var i = m.start; i <= m.end; i++) {
            energy[i] = m;
          }
          opening[m.start].add(m);
        case MarkKind.slower || MarkKind.faster:
          for (var i = m.start; i <= m.end; i++) {
            pace[i] = m;
          }
          opening[m.start].add(m);
      }
    }

    final fontSize = style.fontSize ?? 16;
    final children = <InlineSpan>[];
    final offsets = List<int>.filled(n, 0);
    final cueRanges = <(int, int, int)>[];
    var offset = 0;
    void add(TextSpan span) {
      children.add(span);
      offset += span.toPlainText(includeSemanticsLabels: false).length;
    }

    for (var i = 0; i < n; i++) {
      final t = tokens[i];
      final paceMark = pace[i];
      final paceTint = paceMark == null ? null : TextStyle(backgroundColor: _tint(colors.of(paceMark.kind), paceMark));
      if (i > 0) {
        final separator = t.lineBreaksBefore > 0 ? '\n' * t.lineBreaksBefore.clamp(1, 2) : ' ';
        // Keep a pace tint unbroken across the spaces inside a run.
        final inRun = t.lineBreaksBefore == 0 && paceMark != null && identical(paceMark, pace[i - 1]);
        add(TextSpan(text: separator, style: inRun ? paceTint : null));
      }

      for (final m in opening[i]) {
        final start = offset;
        for (final span in cueSpans(m.kind, colors, fontSize, accepted: m.accepted)) {
          add(span);
        }
        add(TextSpan(text: _thinSpace, style: paceTint));
        cueRanges.add((start, offset, i));
      }

      offsets[i] = offset;
      final stressMark = stress[i];
      final energyMark = energy[i];
      Color? color;
      if (stressMark != null) {
        color = _fade(colors.stress, stressMark);
      } else if (energyMark != null) {
        color = _fade(colors.energy, energyMark);
      }
      add(TextSpan(
        text: t.text,
        style: TextStyle(
          color: color,
          fontWeight: stressMark != null ? FontWeight.w800 : null,
          fontSize: stressMark != null ? fontSize * 1.15 : null,
          backgroundColor: selected.contains(i) ? colors.selection : paceTint?.backgroundColor,
          decoration: stressMark != null && !stressMark.accepted ? TextDecoration.underline : null,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: colors.stress,
        ),
      ));

      final gap = gapAfter[i];
      if (gap != null) {
        final start = offset;
        add(const TextSpan(text: _thinSpace));
        for (final span in cueSpans(gap.kind, colors, fontSize, accepted: gap.accepted)) {
          add(span);
        }
        cueRanges.add((start, offset, i));
      }
    }

    return MarkedText(
      TextSpan(style: style.copyWith(color: style.color ?? colors.text), children: children),
      offsets,
      cueRanges,
    );
  }

  static Color _fade(Color color, Mark mark) => mark.accepted ? color : color.withValues(alpha: 0.6);

  static Color _tint(Color color, Mark mark) => color.withValues(alpha: mark.accepted ? 0.2 : 0.1);
}

/// A key to the cue symbols.
class CueLegend extends StatelessWidget {
  const CueLegend({super.key, required this.colors, this.fontSize = 14});

  final CueColors colors;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    Widget item(List<InlineSpan> cue, String label) => Text.rich(TextSpan(children: [
          ...cue,
          TextSpan(text: ' $label', style: TextStyle(color: colors.text, fontSize: fontSize * 0.85)),
        ]));
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        item([
          TextSpan(text: 'Word', style: TextStyle(color: colors.stress, fontWeight: FontWeight.w800, fontSize: fontSize)),
        ], 'stress'),
        for (final (kind, label) in [
          (MarkKind.pauseShort, 'pause'),
          (MarkKind.pauseLong, 'long pause'),
          (MarkKind.breath, 'breathe'),
          (MarkKind.slower, 'slow down'),
          (MarkKind.faster, 'speed up'),
          (MarkKind.energy, 'lift energy'),
        ])
          item(cueSpans(kind, colors, fontSize * 1.3), label),
      ],
    );
  }
}
