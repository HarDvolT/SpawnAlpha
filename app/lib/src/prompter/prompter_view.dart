import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../model/mark.dart';
import '../model/token.dart';
import '../theme/theme.dart';
import 'guide.dart';
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
    this.guide = PrompterGuide.dot,
    this.motion = PrompterMotion.lineStep,
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

  /// How the word to say now is shown: a bouncing dot, an underline, a
  /// spotlight, or nothing but the reading line.
  final PrompterGuide guide;

  /// Line step (the line being read stays still) or a smooth scroll.
  final PrompterMotion motion;

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

  /// Wall-clock seconds while the ticker runs, for motion that goes on
  /// while the read-through waits (the dot bobbing for the voice).
  double _clock = 0;

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
    final run = _c.isPlaying && _c.mode != ScrollMode.manual;
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
    _clock += delta.inMicroseconds / 1e6;
    _c.advance(delta);
    _scrollToController(glide: delta);
    _frame.value++;
  }

  /// Glide time constant: the view settles on a new line in about 300 ms,
  /// without overshoot (like `spring-smooth`).
  static const _glideTau = 0.09;

  void _scrollToController({bool animate = false, Duration? glide}) {
    final layout = _layout;
    if (layout == null || !_scroll.hasClients) return;
    final y = layout
        .scrollYAt(_c.timeline, _c.position, motion: widget.motion)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    if ((y - _scroll.offset).abs() < 0.5) return;
    _programmaticScroll = true;
    if (glide != null) {
      // Ease toward the line being read, a little further each frame.
      final k = 1 - math.exp(-(glide.inMicroseconds / 1e6) / _glideTau);
      final next = _scroll.offset + (y - _scroll.offset) * k;
      _scroll.jumpTo((y - next).abs() < 0.5 ? y : next);
      _programmaticScroll = false;
    } else if (animate) {
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
      rtl: _c.script.language.isRtl,
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
        kinetic: measured ? _kineticLayout : null,
        effects: widget.kinetic,
        guide: widget.guide,
        calm: MediaQuery.disableAnimationsOf(context),
        rtl: isRtl,
        clock: () => _clock,
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
              // Its own layer, so the guide can fade words out (dstOut)
              // without cutting through the glass behind them. The mask
              // itself changes nothing: any opaque colour keeps every pixel.
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => LinearGradient(colors: [_stage.stage, _stage.stage]).createShader(bounds),
                child: SingleChildScrollView(controller: _scroll, child: text),
              ),
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
          child: IgnorePointer(
            child: _ReadingLine(
              gutter: gutter,
              rtl: isRtl,
              listening: _c.mode == ScrollMode.voice && _c.isPlaying ? _c.speaking : null,
              lineHeight: lineHeight,
            ),
          ),
        ),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: kineticPainter.dot))),
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
  const _ReadingLine({required this.gutter, required this.rtl, required this.lineHeight, this.listening});

  final double gutter;
  final bool rtl;

  /// The caret points at the middle of the line being read, just below.
  final double lineHeight;

  /// In voice mode: whether the speaker is heard (the caret lights up in
  /// amber), or null in other modes.
  final bool? listening;

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    final heard = listening ?? false;
    final arrow = AnimatedScale(
      scale: heard ? 1.25 : 1,
      duration: SaDurations.quick,
      child: Icon(
        rtl ? Icons.arrow_left_rounded : Icons.arrow_right_rounded,
        color: heard ? stage.stageStress : stage.stageChromeText,
        size: 32,
      ),
    );
    return SizedBox(
      height: 4,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: ColoredBox(color: stage.stageLine)),
        Positioned(
          top: lineHeight / 2 - 16,
          left: rtl ? null : gutter * 0.5 - 20,
          right: rtl ? gutter * 0.5 - 20 : null,
          child: arrow,
        ),
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

/// A word the kinetic prompter paints itself (stressed, or in an energy or
/// pace run): where it sits in the paragraph, and a painter that draws it
/// at that spot, so it can punch, hop, lean or float.
class _OverlayWord {
  _OverlayWord(this.token, this.box, this.painter, this.paintAt, {required this.stressed, required this.run});

  final int token;
  final Rect box;
  final TextPainter painter;

  /// Where to paint [painter] so its glyphs land exactly on [box].
  final Offset paintAt;
  final bool stressed;
  final MarkKind? run;
}

/// What the kinetic effects need to know about the laid-out script, in the
/// paragraph's coordinates. Measured once per layout, not per frame.
class _KineticLayout {
  _KineticLayout({
    required this.words,
    required this.energy,
    required this.faster,
    required this.slower,
    required this.gapGlyphs,
    required this.lineHeight,
    required this.tokenBoxes,
    required this.bounce,
    required this.textWidth,
  });

  factory _KineticLayout.measure({
    required RenderParagraph paragraph,
    required MarkedText marked,
    required List<Token> tokens,
    required List<Mark> marks,
    required TextStyle style,
    required CueColors colors,
    required TextScaler textScaler,
    required bool rtl,
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
    final words = <_OverlayWord>[];
    final energy = <(int, Rect)>[];
    final faster = <(int, List<Rect>)>[];
    final slower = <(int, List<Rect>)>[];
    final gapGlyphs = <(int, MarkKind, Rect)>[];
    // Per word, for the bouncing dot.
    final stressed = List<bool>.filled(tokens.length, false);
    final run = List<MarkKind?>.filled(tokens.length, null);
    final opensRun = List<bool>.filled(tokens.length, false);
    final gap = List<MarkKind?>.filled(tokens.length, null);
    final glyphOf = List<Rect?>.filled(tokens.length, null);
    for (final m in marks) {
      if (m.end >= tokens.length) continue;
      if (m.kind == MarkKind.stress) {
        for (var i = m.start; i <= m.end; i++) {
          stressed[i] = true;
        }
      } else if (m.kind == MarkKind.energy || m.kind.isPace) {
        for (var i = m.start; i <= m.end; i++) {
          run[i] = m.kind;
        }
        opensRun[m.start] = true;
      }
    }
    for (final m in marks) {
      if (m.end >= tokens.length) continue;
      switch (m.kind) {
        case MarkKind.stress:
          break;
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
              if (found.isNotEmpty) {
                gapGlyphs.add((m.end, m.kind, found.first));
                gap[m.end] = m.kind;
                glyphOf[m.end] = found.first;
              }
            }
          }
      }
    }
    // The words the overlay paints: the same looks the stage gives them
    // (see MarkedText.build).
    for (var i = 0; i < tokens.length; i++) {
      if (!stressed[i] && run[i] == null) continue;
      final found = boxes(startOf(i), endOf(i));
      if (found.isEmpty) continue;
      final look = stressed[i]
          ? stressStyle
          : run[i] == MarkKind.energy
              ? style.copyWith(color: colors.energy)
              : style;
      final painter = TextPainter(
        text: TextSpan(text: tokens[i].text, style: look),
        textDirection: direction,
        textScaler: textScaler,
      )..layout();
      final own = painter.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: tokens[i].text.length));
      final ownTopLeft = own.isEmpty ? Offset.zero : Offset(own.first.left, own.first.top);
      words.add(_OverlayWord(i, found.first, painter, found.first.topLeft - ownTopLeft, stressed: stressed[i], run: run[i]));
    }
    final lineHeight = fontSize * (style.height ?? 1.45);
    // Every word's box, for the current-word guide.
    final tokenBoxes = [
      for (var i = 0; i < tokens.length; i++)
        () {
          final found = boxes(startOf(i), endOf(i));
          return found.isEmpty ? null : found.first;
        }(),
    ];
    final bounce = BouncePath(
      words: [
        for (var i = 0; i < tokens.length; i++)
          DotWord(
            box: tokenBoxes[i],
            stressed: stressed[i],
            run: run[i],
            opensRun: opensRun[i],
            gap: gap[i],
            gapGlyph: glyphOf[i],
          ),
      ],
      fontSize: fontSize,
      rtl: rtl,
    );
    return _KineticLayout(
      tokenBoxes: tokenBoxes,
      bounce: bounce,
      textWidth: paragraph.size.width,
      words: words,
      energy: energy,
      faster: faster,
      slower: slower,
      gapGlyphs: gapGlyphs,
      lineHeight: lineHeight,
    );
  }

  final List<_OverlayWord> words;
  final List<(int token, Rect box)> energy;
  final List<(int firstToken, List<Rect> boxes)> faster;
  final List<(int firstToken, List<Rect> boxes)> slower;
  final List<(int token, MarkKind kind, Rect glyph)> gapGlyphs;
  final double lineHeight;

  /// The first box of every token, or null for tokens with no box.
  final List<Rect?> tokenBoxes;

  /// The bouncing dot's path through the words.
  final BouncePath bounce;

  /// The paragraph's width, for fading whole lines.
  final double textWidth;

  void dispose() {
    for (final w in words) {
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
    required this.effects,
    required this.guide,
    required this.calm,
    required this.rtl,
    required this.clock,
  });

  final PrompterLayout? layout;
  final _KineticLayout? kinetic;

  /// Kinetic effects on. Off (Still), only the current-word guide is drawn.
  final bool effects;

  /// How the word to say now is shown.
  final PrompterGuide guide;

  /// Reduced motion: the dot jumps from word to word without arcs.
  final bool calm;

  /// Wall-clock seconds, for the dot bobbing while it waits for the voice.
  final double Function() clock;

  /// The script runs right to left: the guide fills from the right.
  final bool rtl;
  final PrompterController controller;
  final ScrollController scroll;

  /// Where the paragraph starts inside the painted area.
  final Offset origin;
  final CueColors colors;
  final Listenable repaint;

  late final under = _KineticLayer(this, over: false);
  late final over = _KineticLayer(this, over: true);
  late final dot = _DotLayer(this);

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
      if (p.effects) {
        _paintWords(canvas, k);
        _paintWait(canvas, k);
      }
      _paintGuide(canvas, k);
      if (p.effects) _paintHits(canvas, k);
    } else if (p.effects) {
      _paintGlows(canvas, k);
    }
    canvas.restore();
  }

  /// The guide to the word to say now (docs/design/prompter.md, "The
  /// guide"). Fading uses [BlendMode.dstOut] on the text's own layer, so
  /// words fade without darkening the glass behind them.
  void _paintGuide(Canvas canvas, _KineticLayout k) {
    final c = p.controller;
    final timeline = c.timeline;
    final layout = p.layout;
    if (p.guide == PrompterGuide.off || timeline.isEmpty || layout == null) return;
    if (timeline.length != k.tokenBoxes.length) return;
    final current = c.currentToken.clamp(0, k.tokenBoxes.length - 1);
    final box = k.tokenBoxes[current];
    if (box == null) return;
    final started = c.state != PlaybackState.ready;
    switch (p.guide) {
      case PrompterGuide.dot:
        // The dot itself is painted above everything (see _DotLayer).
        if (started) _fadeSaid(canvas, k, layout, current, box);
      case PrompterGuide.underline:
        if (started) _fadeSaid(canvas, k, layout, current, box);
        _paintUnderline(canvas, box, current, started);
      case PrompterGuide.spotlight:
        _paintSpotlight(canvas, k, current, box);
      case PrompterGuide.off:
        break;
    }
  }

  /// Fades out [alpha] of what is under [rect] on the text's layer.
  static Paint _fade(double alpha) => Paint()
    ..blendMode = BlendMode.dstOut
    ..color = SaPalette.dark.stage.withValues(alpha: alpha);

  /// Words already said on the line being read fade back.
  void _fadeSaid(Canvas canvas, _KineticLayout k, PrompterLayout layout, int current, Rect box) {
    final line = layout.lineOfToken[current];
    final top = layout.lineTops[line];
    final bottom = layout.lineBottoms[line];
    final rect = p.rtl
        ? Rect.fromLTRB(box.right + 1, top, k.textWidth + 8, bottom)
        : Rect.fromLTRB(-8, top, box.left - 1, bottom);
    if (rect.width > 0) canvas.drawRect(rect, _fade(0.55));
  }

  /// A bar fills across the word as it is said, in the reading direction.
  void _paintUnderline(Canvas canvas, Rect box, int current, bool started) {
    final c = p.controller;
    final timeline = c.timeline;
    final start = timeline.startOf(current);
    final length = timeline.endOf(current) - start;
    final said = !started
        ? 0.0
        : length.inMicroseconds <= 0
            ? 1.0
            : ((c.position - start).inMicroseconds / length.inMicroseconds).clamp(0.0, 1.0);
    final y = box.bottom + 3;
    final text = SaPalette.dark.stageText;
    final paint = Paint()
      ..color = text.withValues(alpha: 0.25)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(box.left, y), Offset(box.right, y), paint);
    final w = box.width * said;
    if (w > 0) {
      canvas.drawLine(
        Offset(p.rtl ? box.right - w : box.left, y),
        Offset(p.rtl ? box.right : box.left + w, y),
        paint..color = text,
      );
    }
  }

  /// Everything fades back except the word to say (full) and the next one.
  void _paintSpotlight(Canvas canvas, _KineticLayout k, int current, Rect box) {
    final next = current + 1 < k.tokenBoxes.length ? k.tokenBoxes[current + 1] : null;
    final all = Rect.fromLTRB(-p.origin.dx, -p.origin.dy, k.textWidth + p.origin.dx, k.lineHeight * 4 + (p.layout?.lineBottoms.last ?? 0));
    final lit = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(all)
      ..addRect(box.inflate(3));
    if (next != null) lit.addRect(next.inflate(3));
    canvas.drawPath(lit, _fade(0.68));
    if (next != null) canvas.drawRect(next.inflate(3), _fade(0.3));
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

  /// The words the overlay owns, each acting out its cue (docs/design/
  /// prompter.md, "Kinetic text"): stressed words grow toward the line and
  /// punch as they are spoken, with a glow (and a strike, unless the dot
  /// strikes them); energy words hop; faster words lean forward; slower
  /// words float. Only transforms: the paragraph never moves.
  void _paintWords(Canvas canvas, _KineticLayout k) {
    final c = p.controller;
    final timeline = c.timeline;
    final lh = k.lineHeight;
    final fontSize = k.bounce.fontSize;
    final clock = p.clock();
    // Only what can be on screen.
    final top = (p.scroll.hasClients ? p.scroll.offset : 0.0) - p.origin.dy - lh;
    final bottom = top + (p.scroll.hasClients ? p.scroll.position.viewportDimension : 2000) + 2 * lh;
    final lean = math.tan(Kinetic.leanDegrees * math.pi / 180) * (p.rtl ? 1 : -1);
    for (final w in k.words) {
      if (w.box.bottom < top || w.box.top > bottom) continue;
      final l = p.livenessOf(w.box, lh);
      final since = w.token < timeline.length ? c.position - timeline.startOf(w.token) : const Duration(days: 1);
      final center = w.box.center;
      canvas.save();
      if (l > 0) {
        switch (w.run) {
          case MarkKind.energy:
            final hop = Kinetic.hop(since);
            canvas.translate(0, -Kinetic.hopHeight * fontSize * hop);
            if (hop > 0) _scaleAbout(canvas, center, 1 + 0.06 * hop);
          case MarkKind.slower:
            canvas.translate(0, Kinetic.floatDepth * fontSize * l * Kinetic.float(clock, w.token));
          case MarkKind.faster:
            // Lean forward from the baseline, in the reading direction.
            canvas
              ..translate(center.dx, w.box.bottom)
              ..skew(lean * l, 0)
              ..translate(-center.dx, -w.box.bottom);
          default:
            break;
        }
      }
      if (w.stressed) {
        final popping = !since.isNegative && since < Kinetic.popWindow;
        final pop = popping ? Kinetic.pop(since) : 0.0;
        if (pop > 0) {
          // A glow while it punches.
          canvas.drawRRect(
            RRect.fromRectAndRadius(w.box.inflate(fontSize * 0.1), Radius.circular(fontSize * 0.2)),
            Paint()
              ..color = p.colors.stress.withValues(alpha: 0.5 * pop / Kinetic.popAmplitude)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, fontSize * 0.35),
          );
        }
        _scaleAbout(canvas, center, Kinetic.stressScale(l, popping ? since : null));
        w.painter.paint(canvas, w.paintAt);
        canvas.restore();
        if (p.guide != PrompterGuide.dot && !since.isNegative && since < BouncePath.slamLength) {
          _paintStrike(canvas, w.box, since.inMicroseconds / BouncePath.slamLength.inMicroseconds, fontSize);
        }
        continue;
      }
      w.painter.paint(canvas, w.paintAt);
      canvas.restore();
    }
  }

  static void _scaleAbout(Canvas canvas, Offset center, double scale) => canvas
    ..translate(center.dx, center.dy)
    ..scale(scale)
    ..translate(-center.dx, -center.dy);

  /// The amber strike across a stressed word as it is spoken: drawn fast,
  /// then faded. The dot draws its own when it is the guide.
  void _paintStrike(Canvas canvas, Rect box, double t, double fontSize) {
    final drawn = Curves.easeOutCubic.transform((t / 0.3).clamp(0.0, 1.0));
    final alpha = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
    final y = box.bottom + fontSize * 0.08;
    final w = box.width * drawn;
    canvas.drawLine(
      Offset(p.rtl ? box.right - w : box.left, y),
      Offset(p.rtl ? box.right : box.left + w, y),
      Paint()
        ..color = p.colors.stress.withValues(alpha: alpha)
        ..strokeWidth = math.max(3, fontSize * 0.11)
        ..strokeCap = StrokeCap.round,
    );
  }

  /// During a pause, the next few words wait: they fade back until the
  /// hold ends, so the eye doesn't run ahead.
  void _paintWait(Canvas canvas, _KineticLayout k) {
    final c = p.controller;
    final holding = c.holding;
    if (holding != MarkKind.pauseShort && holding != MarkKind.pauseLong) return;
    final from = c.currentToken + 1;
    final fade = _fade(1 - Kinetic.waitOpacity);
    for (var i = from; i < math.min(from + Kinetic.waitWords, k.tokenBoxes.length); i++) {
      final b = k.tokenBoxes[i];
      if (b != null) canvas.drawRect(b.inflate(4), fade);
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
      old.p.kinetic != p.kinetic ||
      old.p.effects != p.effects ||
      old.p.guide != p.guide ||
      old.p.calm != p.calm ||
      old.p.origin != p.origin ||
      old.p.layout != p.layout ||
      old.p.colors != p.colors;
}

/// The bouncing dot, painted over the whole prompter so the fades over
/// the read zone never dim it. It follows the text as it scrolls.
class _DotLayer extends CustomPainter {
  _DotLayer(this.p) : super(repaint: p.repaint);

  final _KineticPainter p;

  @override
  void paint(Canvas canvas, Size size) {
    final k = p.kinetic;
    if (k == null || p.guide != PrompterGuide.dot || p.layout == null) return;
    final c = p.controller;
    if (c.timeline.isEmpty || c.timeline.length != k.tokenBoxes.length) return;
    final reading = p.scroll.hasClients ? p.scroll.offset : 0.0;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(p.origin.dx, p.origin.dy - reading);
    _paintDot(canvas, k);
    canvas.restore();
  }

  /// The bouncing dot, acting out each cue: its size, colour and sign, the
  /// timer ring at a pause, and (with Kinetic on) what it throws: the
  /// shockwave and strike on a stressed word, echoes, streaks or sparks.
  void _paintDot(Canvas canvas, _KineticLayout k) {
    final p = this.p;
    final c = p.controller;
    final bounce = k.bounce;
    final frame = bounce.at(c.timeline, c.position, waiting: c.waitingForVoice, clock: p.clock(), calm: p.calm);
    if (frame == null) return;
    final base = bounce.radius;
    final r = base * frame.size;
    final color = _colorOf(frame.tint);

    if (p.effects && !p.calm) {
      _paintTrail(canvas, bounce, frame, base, color);
      final slam = frame.slam;
      final box = frame.slamBox;
      if (slam != null && box != null) {
        // The strike: drawn across the word fast, then faded.
        final drawn = Curves.easeOutCubic.transform((slam / 0.3).clamp(0.0, 1.0));
        final alpha = slam < 0.6 ? 1.0 : 1 - (slam - 0.6) / 0.4;
        final y = box.bottom + base * 0.4;
        final w = box.width * drawn;
        canvas.drawLine(
          Offset(p.rtl ? box.right - w : box.left, y),
          Offset(p.rtl ? box.right : box.left + w, y),
          Paint()
            ..color = p.colors.stress.withValues(alpha: alpha)
            ..strokeWidth = math.max(3, base * 0.55)
            ..strokeCap = StrokeCap.round,
        );
      }
      final burst = frame.burst;
      if (burst != null) {
        final eased = Curves.easeOutCubic.transform(burst);
        canvas.drawCircle(
          frame.center,
          r * (1.1 + 2.6 * eased),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = base * 0.45 * (1 - burst) + 1
            ..color = p.colors.stress.withValues(alpha: 1 - burst),
        );
      }
    }

    final timer = frame.timer;
    if (timer != null) {
      // A timer ring around the pause sign, draining over the hold.
      final ring = Rect.fromCircle(center: frame.center, radius: r + base * 0.55);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.5, base * 0.3)
        ..strokeCap = StrokeCap.round;
      canvas.drawOval(ring, stroke..color = color.withValues(alpha: 0.25));
      if (timer > 0) canvas.drawArc(ring, -math.pi / 2, 2 * math.pi * timer, false, stroke..color = color);
    }

    canvas.save();
    canvas.translate(frame.center.dx, frame.center.dy);
    canvas.scale(frame.scaleX, frame.scaleY);
    canvas.drawCircle(
      Offset.zero,
      r * 1.4,
      Paint()
        ..color = color.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.8),
    );
    canvas.drawCircle(Offset.zero, r, Paint()..color = color);
    canvas.restore();

    final sign = frame.sign;
    if (sign != null && frame.signAlpha > 0) _paintSign(canvas, sign, frame.center, r, frame.signAlpha);
  }

  Color _colorOf(DotTint tint) => switch (tint) {
        DotTint.plain => p.colors.text,
        DotTint.stress => p.colors.stress,
        DotTint.energy => p.colors.energy,
        DotTint.slower => p.colors.slower,
        DotTint.faster => p.colors.faster,
        DotTint.pause => p.colors.pause,
        DotTint.breath => p.colors.breath,
      };

  /// Echoes behind it in a slower run (slow motion), streaks in a faster
  /// run, sparks in an energy run: where it was a moment ago.
  void _paintTrail(Canvas canvas, BouncePath bounce, DotFrame frame, double base, Color color) {
    final c = p.controller;
    DotFrame? back(int ms) {
      final t = c.position - Duration(milliseconds: ms);
      return bounce.at(c.timeline, t.isNegative ? Duration.zero : t);
    }

    switch (frame.trail) {
      case DotTrail.none:
        return;
      case DotTrail.echoes:
        for (var n = 3; n >= 1; n--) {
          final echo = back(110 * n);
          if (echo == null) continue;
          canvas.drawCircle(echo.center, base * echo.size * (1 - 0.12 * n), Paint()..color = color.withValues(alpha: 0.42 - 0.11 * n));
        }
      case DotTrail.streaks:
        final paint = Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = base * 0.5;
        var from = frame.center;
        for (var n = 1; n <= 3; n++) {
          final was = back(35 * n);
          if (was == null) continue;
          canvas.drawLine(from, was.center, paint..color = color.withValues(alpha: 0.55 - 0.15 * n));
          from = was.center;
        }
      case DotTrail.sparks:
        for (var n = 1; n <= 4; n++) {
          final was = back(40 * n);
          if (was == null) continue;
          // Sparks scatter a little off the path, the same way every time.
          final angle = n * 2.4;
          final off = Offset(math.cos(angle), math.sin(angle)) * (base * 0.5 * n);
          canvas.drawCircle(was.center + off, base * (0.42 - 0.08 * n), Paint()..color = color.withValues(alpha: 0.8 - 0.17 * n));
        }
    }
  }

  static final _signPainters = <DotSign, TextPainter>{};
  static const _signFontSize = 64.0;

  /// The cue's glyph inside the grown dot, in stage black.
  void _paintSign(Canvas canvas, DotSign sign, Offset center, double r, double alpha) {
    final painter = _signPainters.putIfAbsent(sign, () {
      final icon = switch (sign) {
        DotSign.pause => cueIcon(MarkKind.pauseShort),
        DotSign.pauseLong => cueIcon(MarkKind.pauseShort),
        DotSign.breath => cueIcon(MarkKind.breath),
        DotSign.slower => cueIcon(MarkKind.slower),
        DotSign.faster => cueIcon(MarkKind.faster),
        DotSign.energy => cueIcon(MarkKind.energy),
        DotSign.listen => Icons.mic_rounded,
      };
      return TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: _signFontSize,
            color: SaPalette.dark.stage,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
    final scale = r * 1.35 / _signFontSize;
    final rect = Rect.fromCircle(center: center, radius: r);
    canvas.saveLayer(rect, Paint()..color = SaPalette.dark.stage.withValues(alpha: alpha));
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DotLayer old) =>
      old.p.kinetic != p.kinetic ||
      old.p.guide != p.guide ||
      old.p.calm != p.calm ||
      old.p.effects != p.effects ||
      old.p.origin != p.origin ||
      old.p.layout != p.layout;
}
