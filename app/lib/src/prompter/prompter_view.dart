import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../model/mark.dart';
import '../model/token.dart';
import '../theme/theme.dart';
import 'kinetic.dart';
import 'marked_text.dart';
import 'prompter_controller.dart';
import 'prompter_layout.dart';

/// The scrolling prompter: the script in large type with its cues, a
/// reading line, and a scroll that follows the [controller].
///
/// In timed mode it scrolls every frame from the delivery timeline and
/// stands still at pauses. In manual mode, or whenever the user drags or
/// wheels it, it follows the user and tells the controller which word is
/// under the reading line.
class PrompterView extends StatefulWidget {
  const PrompterView({
    super.key,
    required this.controller,
    this.fontSize = 44,
    this.mirror = false,
    this.readingLine = SaPrompter.readingLine,
    this.backgroundOpacity = 1,
    this.kinetic = true,
    this.glass = false,
  });

  final PrompterController controller;
  final double fontSize;

  /// Flips the prompter left to right, for beam-splitter teleprompter
  /// glass.
  final bool mirror;

  /// Where the reading line sits, as a fraction of the height from the top.
  final double readingLine;

  /// Below 1 the camera preview shows through.
  final double backgroundOpacity;

  /// Glass instead of black: over a camera preview, the prompter blurs
  /// what is behind it (`stage-glass`), so the speaker still sees their
  /// framing. Overrides [backgroundOpacity].
  final bool glass;

  /// Kinetic text: words wake up as they near the reading line, stressed
  /// words grow and pop, gap cues hit as their hold starts. Off is Still:
  /// only the scroll and the holds move.
  final bool kinetic;

  @override
  State<PrompterView> createState() => PrompterViewState();
}

class PrompterViewState extends State<PrompterView> with SingleTickerProviderStateMixin {
  static final _colors = CueColors.stage;
  static final _stage = SaPalette.dark;

  final _scroll = ScrollController();

  /// Ticks every frame the read-through moves, to repaint the kinetic
  /// effects and the hold ring without rebuilding.
  final _frame = ValueNotifier<int>(0);
  _KineticLayout? _kineticLayout;
  final _textKey = GlobalKey();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  MarkedText? _marked;
  Object? _markedKey;
  PrompterLayout? _layout;
  Object? _layoutKey;
  bool _programmaticScroll = false;
  bool _followingUser = false;

  PrompterController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _c.addListener(_onController);
    _syncTicker();
  }

  @override
  void didUpdateWidget(PrompterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onController);
    _ticker.dispose();
    _scroll.dispose();
    _frame.dispose();
    _kineticLayout?.dispose();
    super.dispose();
  }

  // ---- driving the scroll -------------------------------------------------

  void _onController() {
    _frame.value++;
    _syncTicker();
    if (!_ticker.isActive && !_followingUser) _scrollToController(animate: true);
    setState(() {});
  }

  void _syncTicker() {
    final run = _c.isPlaying && _c.mode == ScrollMode.timed;
    if (run && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    _c.advance(delta);
    _scrollToController();
    _frame.value++;
  }

  void _scrollToController({bool animate = false}) {
    final layout = _layout;
    if (layout == null || !_scroll.hasClients) return;
    final y = layout.scrollYAt(_c.timeline, _c.position).clamp(0.0, _scroll.position.maxScrollExtent);
    if ((y - _scroll.offset).abs() < 0.5) return;
    _programmaticScroll = true;
    if (animate) {
      _scroll
          .animateTo(y, duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
          .whenComplete(() => _programmaticScroll = false);
    } else {
      _scroll.jumpTo(y);
      _programmaticScroll = false;
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (_programmaticScroll || n.depth != 0) return false;
    if (n is ScrollStartNotification && n.dragDetails != null) _c.pause();
    if (n is ScrollUpdateNotification) _followScroll();
    return false;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) _c.pause();
  }

  void _followScroll() {
    final layout = _layout;
    if (layout == null || !_scroll.hasClients) return;
    _followingUser = true;
    _c.followScroll(layout.tokenAtY(_scroll.offset));
    _followingUser = false;
  }

  /// Moves one line down (positive [direction]) or up, for the arrow keys.
  void nudge(int direction) {
    final layout = _layout;
    if (layout == null || layout.lineOfToken.isEmpty) return;
    final step = direction.sign;
    var target = layout.lineOfToken[_c.currentToken] + step;
    // Skip blank lines, which hold no words.
    while (target > 0 && target < layout.lineCount - 1 && !layout.hasWords(target)) {
      target += step;
    }
    if (target < 0 || target >= layout.lineCount || !layout.hasWords(target)) return;
    _c.seekToToken(layout.firstTokenOn(target));
  }

  // ---- layout -------------------------------------------------------------

  TextStyle get _style {
    final base = _c.script.language.isRtl ? SaType.stageMAr : SaType.stageM;
    return base.copyWith(fontSize: widget.fontSize, color: _stage.stageText);
  }

  MarkedText _markedText() {
    final key = (_c.script, widget.fontSize, widget.kinetic);
    if (_markedKey != key || _marked == null) {
      _markedKey = key;
      _marked = MarkedText.build(
        tokens: _c.tokens,
        marks: _c.marks,
        style: _style,
        colors: _colors,
        // Kinetic: the stressed words are painted by the overlay, so they
        // can grow. Their room on the line is the same either way.
        stressStyle: widget.kinetic ? StressStyle.stageOverlay : StressStyle.stage,
      );
    }
    return _marked!;
  }

  void _measure(Object key) {
    final paragraph = _textKey.currentContext?.findRenderObject();
    final marked = _marked;
    if (paragraph is! RenderParagraph || marked == null || !paragraph.hasSize) return;
    // Full line-height boxes share their top with every word on the line,
    // so a box that starts below the current line's bottom opens a new one.
    final tops = <double>[];
    final bottoms = <double>[];
    final lineOfToken = List<int>.filled(_c.tokens.length, 0);
    for (var i = 0; i < _c.tokens.length; i++) {
      final start = marked.tokenOffsets[i];
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + _c.tokens[i].text.length),
        boxHeightStyle: ui.BoxHeightStyle.max,
      );
      if (boxes.isNotEmpty) {
        final box = boxes.first;
        if (tops.isEmpty || box.top >= bottoms.last - 1) {
          tops.add(box.top);
          bottoms.add(box.bottom);
        } else {
          tops.last = math.min(tops.last, box.top);
          bottoms.last = math.max(bottoms.last, box.bottom);
        }
      }
      lineOfToken[i] = tops.isEmpty ? 0 : tops.length - 1;
    }
    if (tops.isEmpty) return;
    final kinetic = _KineticLayout.measure(
      paragraph: paragraph,
      marked: marked,
      tokens: _c.tokens,
      marks: _c.marks,
      style: _style,
      colors: _colors,
      textScaler: MediaQuery.textScalerOf(context),
    );
    setState(() {
      _layoutKey = key;
      _layout = PrompterLayout(lineOfToken: lineOfToken, lineTops: tops, lineBottoms: bottoms);
      _kineticLayout?.dispose();
      _kineticLayout = kinetic;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToController());
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = _c.script.language.isRtl;
    final direction = isRtl ? TextDirection.rtl : TextDirection.ltr;
    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight;
      final width = constraints.maxWidth;
      final readingY = height * widget.readingLine;
      final gutter = (width * 0.06).clamp(20.0, 64.0);
      final marked = _markedText();

      final layoutKey = (_markedKey, width);
      if (layoutKey != _layoutKey) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _measure(layoutKey);
        });
      }

      final measured = _layoutKey == layoutKey;
      final kineticPainter = _KineticPainter(
        layout: measured ? _layout : null,
        kinetic: measured && widget.kinetic ? _kineticLayout : null,
        controller: _c,
        scroll: _scroll,
        origin: Offset(gutter, readingY),
        colors: _colors,
        repaint: Listenable.merge([_frame, _scroll]),
      );
      final text = CustomPaint(
        painter: _PaceBarPainter(
          layout: measured ? _layout : null,
          marks: _c.marks,
          colors: _colors,
          rtl: isRtl,
          gutter: gutter,
          top: readingY,
        ),
        child: CustomPaint(
          painter: kineticPainter.under,
          foregroundPainter: kineticPainter.over,
          child: Padding(
            padding: EdgeInsets.fromLTRB(gutter, readingY, gutter, height - readingY),
            child: Text.rich(key: _textKey, marked.span, textDirection: direction),
          ),
        ),
      );
      final lineHeight = widget.fontSize * (_style.height ?? 1.45);
      final fadeStrength = widget.glass ? 0.7 : widget.backgroundOpacity;

      final prompter = Stack(children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: SingleChildScrollView(controller: _scroll, child: text),
            ),
          ),
        ),
        // Kinetic: text more than a few lines ahead sits back.
        if (widget.kinetic)
          Positioned(
            left: 0,
            right: 0,
            top: math.min(height, readingY + lineHeight * Kinetic.sitBackLines),
            bottom: 0,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _stage.stage.withValues(alpha: 0),
                      _stage.stage.withValues(alpha: 0.5 * fadeStrength),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Fade what has already been read.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: readingY,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _stage.stage.withValues(alpha: 0.9 * fadeStrength),
                    _stage.stage.withValues(alpha: 0.35 * fadeStrength),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: readingY - 2,
          left: 0,
          right: 0,
          child: IgnorePointer(child: _ReadingLine(gutter: gutter, rtl: isRtl)),
        ),
        Positioned(
          top: readingY - widget.fontSize * 1.6,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(child: _HoldBadge(kind: _c.holding, fontSize: widget.fontSize, controller: _c, frame: _frame)),
          ),
        ),
      ]);

      final surface = ColoredBox(
        color: widget.glass ? _stage.stageGlass : _stage.stage.withValues(alpha: widget.backgroundOpacity),
        child: widget.mirror
            ? Transform(alignment: Alignment.center, transform: Matrix4.diagonal3Values(-1, 1, 1), child: prompter)
            : prompter,
      );
      if (!widget.glass) return surface;
      return ClipRect(child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: surface));
    });
  }
}

/// A marker at the reading line, on the side the text starts from.
class _ReadingLine extends StatelessWidget {
  const _ReadingLine({required this.gutter, required this.rtl});

  final double gutter;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    final arrow = Icon(rtl ? Icons.arrow_left_rounded : Icons.arrow_right_rounded, color: stage.stageChromeText, size: 32);
    return SizedBox(
      height: 4,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: ColoredBox(color: stage.stageLine)),
        Positioned(top: -14, left: rtl ? null : gutter * 0.5 - 20, right: rtl ? gutter * 0.5 - 20 : null, child: arrow),
      ]),
    );
  }
}

/// The badge that shows while the prompter holds at a pause or a breath:
/// glass, the cue's colour, its name in the signal face, and a ring that
/// empties linearly over exactly the hold's length.
class _HoldBadge extends StatelessWidget {
  const _HoldBadge({required this.kind, required this.fontSize, required this.controller, required this.frame});

  final MarkKind? kind;
  final double fontSize;
  final PrompterController controller;
  final Listenable frame;

  @override
  Widget build(BuildContext context) {
    final k = kind;
    final label = switch (k) {
      MarkKind.pauseLong => 'LONG PAUSE',
      MarkKind.breath => 'BREATHE',
      _ => 'PAUSE',
    };
    final stage = SaPalette.dark;
    final color = k == null ? stage.stageChromeText : CueColors.stage.of(k);
    final scale = (fontSize / 44).clamp(0.75, 1.6) * (k == MarkKind.pauseLong ? 1.15 : 1);
    return AnimatedOpacity(
      opacity: k == null ? 0 : 1,
      duration: SaDurations.quick,
      child: AnimatedSlide(
        offset: k == null ? const Offset(0, 0.15) : Offset.zero,
        duration: SaDurations.base,
        curve: SaEasing.standard,
        child: Container(
          height: 32 * scale,
          padding: EdgeInsets.fromLTRB(6 * scale, 0, 14 * scale, 0),
          decoration: BoxDecoration(
            color: stage.stageGlass,
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(SaRadius.full),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox.square(
              dimension: 22 * scale,
              child: CustomPaint(painter: _HoldRingPainter(controller: controller, color: color, repaint: frame)),
            ),
            SizedBox(width: 8 * scale),
            Text(label, style: SaType.signalLabel.copyWith(color: color, fontSize: 11 * scale)),
          ]),
        ),
      ),
    );
  }
}

/// The hold badge's ring: full as the hold starts, empty as it ends.
class _HoldRingPainter extends CustomPainter {
  _HoldRingPainter({required this.controller, required this.color, required Listenable repaint}) : super(repaint: repaint);

  final PrompterController controller;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final hold = controller.timeline.holdAt(controller.position);
    final left = hold == null
        ? 0.0
        : 1 - ((controller.position - hold.$1).inMicroseconds / (hold.$2 - hold.$1).inMicroseconds).clamp(0.0, 1.0);
    final rect = Offset.zero & size;
    final stroke = size.width * 0.14;
    final ring = rect.deflate(stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(ring.center, ring.width / 2, paint..color = color.withValues(alpha: 0.25));
    if (left > 0) canvas.drawArc(ring, -math.pi / 2, 2 * math.pi * left, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_HoldRingPainter old) => old.color != color || old.controller != controller;
}

/// Paints a pace bar in the gutter beside each slower or faster run.
class _PaceBarPainter extends CustomPainter {
  _PaceBarPainter({
    required this.layout,
    required this.marks,
    required this.colors,
    required this.rtl,
    required this.gutter,
    required this.top,
  });

  final PrompterLayout? layout;
  final List<Mark> marks;
  final CueColors colors;
  final bool rtl;
  final double gutter;
  final double top;

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout;
    if (l == null) return;
    final x = rtl ? size.width - gutter * 0.5 : gutter * 0.5;
    for (final m in marks) {
      if (!m.kind.isPace || m.end >= l.lineOfToken.length) continue;
      final y1 = top + l.lineTops[l.lineOfToken[m.start]] + 4;
      final y2 = top + l.lineBottoms[l.lineOfToken[m.end]] - 4;
      final paint = Paint()
        ..color = colors.of(m.kind)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(_PaceBarPainter old) =>
      old.layout != layout || old.marks != marks || old.rtl != rtl || old.gutter != gutter || old.top != top;
}

/// A stressed word the kinetic prompter paints itself: where it sits in
/// the paragraph, and a painter that draws it at that spot.
class _StressWord {
  _StressWord(this.token, this.box, this.painter, this.paintAt);

  final int token;
  final Rect box;
  final TextPainter painter;

  /// Where to paint [painter] so its glyphs land exactly on [box].
  final Offset paintAt;
}

/// What the kinetic effects need to know about the laid-out script, in the
/// paragraph's coordinates. Measured once per layout, not per frame.
class _KineticLayout {
  _KineticLayout({
    required this.stressWords,
    required this.energy,
    required this.faster,
    required this.slower,
    required this.gapGlyphs,
    required this.lineHeight,
  });

  factory _KineticLayout.measure({
    required RenderParagraph paragraph,
    required MarkedText marked,
    required List<Token> tokens,
    required List<Mark> marks,
    required TextStyle style,
    required CueColors colors,
    required TextScaler textScaler,
  }) {
    List<Rect> boxes(int start, int end) => [
          for (final b in paragraph.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end))) b.toRect(),
        ];
    int startOf(int token) => marked.tokenOffsets[token];
    int endOf(int token) => marked.tokenOffsets[token] + tokens[token].text.length;

    final fontSize = style.fontSize ?? 44;
    // The same look the stage gives stressed words (see MarkedText.build).
    final stressStyle = style.merge(TextStyle(color: colors.stress, fontWeight: FontWeight.w700, fontSize: fontSize * 1.15));
    final direction = paragraph.textDirection;
    final stressWords = <_StressWord>[];
    final energy = <(int, Rect)>[];
    final faster = <(int, List<Rect>)>[];
    final slower = <(int, List<Rect>)>[];
    final gapGlyphs = <(int, MarkKind, Rect)>[];
    for (final m in marks) {
      if (m.end >= tokens.length) continue;
      switch (m.kind) {
        case MarkKind.stress:
          for (var i = m.start; i <= m.end; i++) {
            final found = boxes(startOf(i), endOf(i));
            if (found.isEmpty) continue;
            final painter = TextPainter(
              text: TextSpan(text: tokens[i].text, style: stressStyle),
              textDirection: direction,
              textScaler: textScaler,
            )..layout();
            final own = painter.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: tokens[i].text.length));
            final ownTopLeft = own.isEmpty ? Offset.zero : Offset(own.first.left, own.first.top);
            stressWords.add(_StressWord(i, found.first, painter, found.first.topLeft - ownTopLeft));
          }
        case MarkKind.energy:
          for (var i = m.start; i <= m.end; i++) {
            for (final b in boxes(startOf(i), endOf(i))) {
              energy.add((i, b));
            }
          }
        case MarkKind.faster:
          faster.add((m.start, boxes(startOf(m.start), endOf(m.end))));
        case MarkKind.slower:
          slower.add((m.start, boxes(startOf(m.start), endOf(m.end))));
        case MarkKind.pauseShort || MarkKind.pauseLong || MarkKind.breath:
          // The glyph after the word: its cue range starts at or after the word's end.
          for (final (start, end, token) in marked.cueRanges) {
            if (token == m.end && start >= endOf(m.end)) {
              final found = boxes(start + 1, end);
              if (found.isNotEmpty) gapGlyphs.add((m.end, m.kind, found.first));
            }
          }
      }
    }
    final lineHeight = fontSize * (style.height ?? 1.45);
    return _KineticLayout(
      stressWords: stressWords,
      energy: energy,
      faster: faster,
      slower: slower,
      gapGlyphs: gapGlyphs,
      lineHeight: lineHeight,
    );
  }

  final List<_StressWord> stressWords;
  final List<(int token, Rect box)> energy;
  final List<(int firstToken, List<Rect> boxes)> faster;
  final List<(int firstToken, List<Rect> boxes)> slower;
  final List<(int token, MarkKind kind, Rect glyph)> gapGlyphs;
  final double lineHeight;

  void dispose() {
    for (final w in stressWords) {
      w.painter.dispose();
    }
  }
}

/// Paints the kinetic prompter's effects around the fixed paragraph:
/// [under] draws glows, speed lines and breathing tints behind the text;
/// [over] draws the stressed words (grown and popping) and the gap cues'
/// hits. Only paint changes each frame; the paragraph never re-lays out.
///
/// With [kinetic] null (Still, or not measured yet) only the stressed words
/// are drawn, at rest, if the paragraph left them to the overlay.
class _KineticPainter {
  _KineticPainter({
    required this.layout,
    required this.kinetic,
    required this.controller,
    required this.scroll,
    required this.origin,
    required this.colors,
    required this.repaint,
  });

  final PrompterLayout? layout;
  final _KineticLayout? kinetic;
  final PrompterController controller;
  final ScrollController scroll;

  /// Where the paragraph starts inside the painted area.
  final Offset origin;
  final CueColors colors;
  final Listenable repaint;

  late final under = _KineticLayer(this, over: false);
  late final over = _KineticLayer(this, over: true);

  /// Lines between the reading line and [box] (negative once read).
  double linesAhead(Rect box, double lineHeight) {
    final reading = scroll.hasClients ? scroll.offset : 0.0;
    return (box.top - reading) / lineHeight;
  }

  double livenessOf(Rect box, double lineHeight) => Kinetic.liveness(linesAhead(box, lineHeight));

  /// Seconds into the read-through, for the moving speed lines and the
  /// breathing tint.
  double get seconds => controller.position.inMicroseconds / 1e6;
}

class _KineticLayer extends CustomPainter {
  _KineticLayer(this.p, {required this.over}) : super(repaint: p.repaint);

  final _KineticPainter p;
  final bool over;

  @override
  void paint(Canvas canvas, Size size) {
    final k = p.kinetic;
    if (k == null) return;
    canvas.save();
    canvas.translate(p.origin.dx, p.origin.dy);
    if (over) {
      _paintStress(canvas, k);
      _paintHits(canvas, k);
    } else {
      _paintGlows(canvas, k);
    }
    canvas.restore();
  }

  void _paintGlows(Canvas canvas, _KineticLayout k) {
    final lh = k.lineHeight;
    // Lift energy: a soft glow builds behind the words.
    for (final (_, box) in k.energy) {
      final l = p.livenessOf(box, lh);
      if (l <= 0) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(box.inflate(4), const Radius.circular(8)),
        Paint()
          ..color = p.colors.energy.withValues(alpha: 0.22 * l)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
    // Speed up: thin speed lines drift through the tint.
    for (final (_, boxes) in k.faster) {
      for (final box in boxes) {
        final l = p.livenessOf(box, lh);
        if (l <= 0) continue;
        canvas.save();
        canvas.clipRRect(RRect.fromRectAndRadius(box, const Radius.circular(SaRadius.xs)));
        final paint = Paint()
          ..color = p.colors.faster.withValues(alpha: 0.28 * l)
          ..strokeWidth = 3;
        const spacing = 16.0;
        final shift = (p.seconds * 60) % spacing;
        for (var x = box.left - box.height + shift; x < box.right + spacing; x += spacing) {
          canvas.drawLine(Offset(x, box.bottom), Offset(x + box.height * 0.45, box.top), paint);
        }
        canvas.restore();
      }
    }
    // Slow down: the tint breathes, once every 2.4 seconds.
    final breath = 0.5 + 0.5 * math.sin(2 * math.pi * p.seconds / 2.4);
    for (final (_, boxes) in k.slower) {
      for (final box in boxes) {
        final l = p.livenessOf(box, lh);
        if (l <= 0) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(SaRadius.xs)),
          Paint()..color = p.colors.slower.withValues(alpha: 0.12 * l * breath),
        );
      }
    }
  }

  void _paintStress(Canvas canvas, _KineticLayout k) {
    final c = p.controller;
    final timeline = c.timeline;
    for (final w in k.stressWords) {
      final l = p.livenessOf(w.box, k.lineHeight);
      Duration? since;
      if (w.token < timeline.length) {
        final s = c.position - timeline.startOf(w.token);
        if (!s.isNegative && s < Kinetic.popWindow) since = s;
      }
      final scale = Kinetic.stressScale(l, since);
      canvas.save();
      final center = w.box.center;
      canvas
        ..translate(center.dx, center.dy)
        ..scale(scale)
        ..translate(-center.dx, -center.dy);
      w.painter.paint(canvas, w.paintAt);
      canvas.restore();
    }
  }

  void _paintHits(Canvas canvas, _KineticLayout k) {
    final c = p.controller;
    final timeline = c.timeline;
    for (final (token, kind, glyph) in k.gapGlyphs) {
      if (token >= timeline.length) continue;
      final hit = Kinetic.hit(c.position - timeline.endOf(token));
      if (hit == null) continue;
      // A ring bursts off the glyph as its hold starts.
      final eased = Curves.easeOutCubic.transform(hit);
      canvas.drawCircle(
        glyph.center,
        glyph.height * (0.45 + 0.6 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = p.colors.of(kind).withValues(alpha: 1 - hit),
      );
    }
  }

  @override
  bool shouldRepaint(_KineticLayer old) =>
      old.p.kinetic != p.kinetic || old.p.origin != p.origin || old.p.layout != p.layout || old.p.colors != p.colors;
}
