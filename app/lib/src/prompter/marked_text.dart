import 'package:flutter/material.dart';

import '../model/mark.dart';
import '../model/token.dart';
import '../theme/theme.dart';
import 'kinetic.dart';

/// Colours for the delivery cues: the stage set (always dark, whatever
/// the device theme) and a Studio set per theme. All come from the design
/// tokens (`cue-*`, `stage-*`, `tint-*`).
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
    required this.tintSlower,
    required this.tintFaster,
    required this.marker,
  });

  /// The stage: the prompter, the countdown, the recording HUD.
  static final stage = CueColors(
    text: SaPalette.dark.stageText,
    stress: SaPalette.dark.stageStress,
    energy: SaPalette.dark.stageEnergy,
    slower: SaPalette.dark.stageSlower,
    faster: SaPalette.dark.stageFaster,
    pause: SaPalette.dark.stagePause,
    breath: SaPalette.dark.stageBreath,
    selection: SaPalette.dark.tintSelect,
    tintSlower: SaPalette.dark.stageTintSlower,
    tintFaster: SaPalette.dark.stageTintFaster,
    marker: SaPalette.dark.cue.withValues(alpha: 0.72),
  );

  /// The Studio (editor, sheets, legend) in one theme.
  factory CueColors.studio(SaPalette p) => CueColors(
        text: p.ink,
        stress: p.cueStress,
        energy: p.cueEnergy,
        slower: p.cueSlower,
        faster: p.cueFaster,
        pause: p.cuePause,
        breath: p.cueBreath,
        selection: p.tintSelect,
        tintSlower: p.tintSlower,
        tintFaster: p.tintFaster,
        marker: p.cue.withValues(alpha: 0.72),
      );

  static final studioLight = CueColors.studio(SaPalette.light);
  static final studioDark = CueColors.studio(SaPalette.dark);

  /// The Studio colours for the theme at [context].
  static CueColors forStudio(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? studioDark : studioLight;

  final Color text;
  final Color stress;
  final Color energy;
  final Color slower;
  final Color faster;
  final Color pause;
  final Color breath;
  final Color selection;
  final Color tintSlower;
  final Color tintFaster;

  /// The marker swipe behind a stressed word in the Studio.
  final Color marker;

  Color of(MarkKind kind) => switch (kind) {
        MarkKind.stress => stress,
        MarkKind.energy => energy,
        MarkKind.slower => slower,
        MarkKind.faster => faster,
        MarkKind.pauseShort || MarkKind.pauseLong => pause,
        MarkKind.breath => breath,
      };

  /// The tint behind the words of a pace run.
  Color tintOf(MarkKind kind) => kind == MarkKind.faster ? tintFaster : tintSlower;
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

/// How stressed words are drawn.
enum StressStyle {
  /// On the stage: `stage-stress` amber, heavier and 1.15× larger.
  stage,

  /// The stage's layout, with the stressed words left transparent: the
  /// kinetic prompter paints them itself, so they can grow and pop.
  stageOverlay,

  /// In the Studio: ink at weight 700, with an amber marker swipe painted
  /// behind it by the page (see [MarkedText.stressRanges]). The text itself
  /// carries no colour, so the marker can animate without re-laying out.
  marker,
}

/// A script rendered with its cues, plus where each token starts in the
/// rendered text, so callers can measure and hit-test words.
class MarkedText {
  const MarkedText(this.span, this.tokenOffsets, this.cueRanges, [this.stressRanges = const []]);

  final InlineSpan span;

  /// For each token, its character offset in [span]'s plain text.
  final List<int> tokenOffsets;

  /// The character ranges of the cue icons, with the token each belongs
  /// to: the word a pace or energy run opens on, or the word a pause
  /// follows.
  final List<(int start, int end, int token)> cueRanges;

  /// The character range of each stress mark, in reading order, with
  /// whether it is accepted: where the Studio paints its marker swipes.
  final List<(int start, int end, bool accepted)> stressRanges;

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
    StressStyle stressStyle = StressStyle.stage,
  }) {
    final marker = stressStyle == StressStyle.marker;
    final overlay = stressStyle == StressStyle.stageOverlay;
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
      final paceTint = paceMark == null ? null : TextStyle(backgroundColor: _tint(colors.tintOf(paceMark.kind), paceMark));
      if (i > 0) {
        final separator = t.lineBreaksBefore > 0 ? '\n' * t.lineBreaksBefore.clamp(1, 2) : ' ';
        // Keep a pace tint unbroken across the spaces inside a run.
        final inRun = t.lineBreaksBefore == 0 && paceMark != null && identical(paceMark, pace[i - 1]);
        // On the stage, the spaces beside a stressed word are widened so it
        // has room to grow (the same in Kinetic and Still, so switching
        // never reflows).
        final room = !marker && (stress[i] != null || stress[i - 1] != null)
            ? TextStyle(letterSpacing: fontSize * Kinetic.stressRoom)
            : null;
        final spaceStyle = inRun ? paceTint!.merge(room) : room;
        add(TextSpan(text: separator, style: spaceStyle));
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
      if (stressMark != null && overlay) {
        color = const Color(0x00000000);
      } else if (stressMark != null && !marker) {
        color = _fade(colors.stress, stressMark);
      } else if (energyMark != null) {
        color = _fade(colors.energy, energyMark);
      }
      add(TextSpan(
        text: t.text,
        style: TextStyle(
          color: color,
          fontWeight: stressMark == null ? null : FontWeight.w700,
          fontSize: stressMark != null && !marker ? fontSize * 1.15 : null,
          backgroundColor: selected.contains(i) ? colors.selection : paceTint?.backgroundColor,
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

    final stressRanges = [
      for (final m in marks.where((m) => m.kind == MarkKind.stress && m.end < n).toList()
        ..sort((a, b) => a.start.compareTo(b.start)))
        (offsets[m.start], offsets[m.end] + tokens[m.end].text.length, m.accepted),
    ];
    return MarkedText(
      TextSpan(style: style.copyWith(color: style.color ?? colors.text), children: children),
      offsets,
      cueRanges,
      stressRanges,
    );
  }

  static Color _fade(Color color, Mark mark) => mark.accepted ? color : color.withValues(alpha: 0.6);

  /// Pending runs get half the tint.
  static Color _tint(Color tint, Mark mark) => mark.accepted ? tint : tint.withValues(alpha: tint.a / 2);
}

/// Paints the marker swipe behind a stressed word: a band over the lower
/// part of the glyph [box] (from 50% to 92% of its height), drawn
/// [progress] of the way across in the reading direction.
void paintMarkerBand(Canvas canvas, Rect box, Color color, {double progress = 1, bool rtl = false}) {
  if (progress <= 0) return;
  final pad = box.height * 0.06;
  final full = Rect.fromLTRB(box.left - pad, box.top + box.height * 0.5, box.right + pad, box.top + box.height * 0.92);
  final width = full.width * progress.clamp(0.0, 1.0);
  final band = rtl
      ? Rect.fromLTRB(full.right - width, full.top, full.right, full.bottom)
      : Rect.fromLTRB(full.left, full.top, full.left + width, full.bottom);
  canvas.drawRRect(RRect.fromRectAndRadius(band, Radius.circular(box.height * 0.08)), Paint()..color = color);
}

/// A short text with the Studio's marker swipe behind it, for legends and
/// sheets (the script page paints its own).
class MarkerText extends StatelessWidget {
  const MarkerText(this.text, {super.key, required this.color, required this.style});

  final String text;
  final Color color;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _MarkerPainter(color, Directionality.of(context) == TextDirection.rtl),
        child: Text(text, style: style.copyWith(fontWeight: FontWeight.w700)),
      );
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.color, this.rtl);

  final Color color;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) => paintMarkerBand(canvas, Offset.zero & size, color, rtl: rtl);

  @override
  bool shouldRepaint(_MarkerPainter old) => old.color != color || old.rtl != rtl;
}

/// A cue's symbol at icon size, for sheets and chips: its glyph, or for
/// stress (which has no glyph; the word is the cue) a marked "Aa".
class CueBadge extends StatelessWidget {
  const CueBadge(this.kind, {super.key, required this.colors, this.size = 20});

  final MarkKind kind;
  final CueColors colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (kind == MarkKind.stress) {
      return MarkerText('Aa', color: colors.marker, style: TextStyle(color: colors.text, fontSize: size * 0.8, height: 1.2));
    }
    return Icon(cueIcon(kind), color: colors.of(kind), size: size);
  }
}

/// A key to the cue symbols.
class CueLegend extends StatelessWidget {
  const CueLegend({super.key, required this.colors, this.fontSize = 14, this.stressStyle = StressStyle.stage});

  final CueColors colors;
  final double fontSize;

  /// Draw the stress sample as the stage does, or as the Studio's marker.
  final StressStyle stressStyle;

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
        if (stressStyle == StressStyle.marker)
          Row(mainAxisSize: MainAxisSize.min, children: [
            MarkerText('Word', color: colors.marker, style: TextStyle(color: colors.text, fontSize: fontSize)),
            Text(' stress', style: TextStyle(color: colors.text, fontSize: fontSize * 0.85)),
          ])
        else
          item([
            TextSpan(text: 'Word', style: TextStyle(color: colors.stress, fontWeight: FontWeight.w700, fontSize: fontSize)),
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
