import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../model/mark.dart';
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
    this.readingLine = 0.3,
    this.backgroundOpacity = 1,
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

  @override
  State<PrompterView> createState() => PrompterViewState();
}

class PrompterViewState extends State<PrompterView> with SingleTickerProviderStateMixin {
  static final _colors = CueColors.stage;

  final _scroll = ScrollController();
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
    super.dispose();
  }

  // ---- driving the scroll -------------------------------------------------

  void _onController() {
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

  MarkedText _markedText() {
    final key = (_c.script, widget.fontSize);
    if (_markedKey != key || _marked == null) {
      _markedKey = key;
      _marked = MarkedText.build(
        tokens: _c.tokens,
        marks: _c.marks,
        style: TextStyle(fontSize: widget.fontSize, height: 1.45, fontWeight: FontWeight.w500),
        colors: _colors,
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
    setState(() {
      _layoutKey = key;
      _layout = PrompterLayout(lineOfToken: lineOfToken, lineTops: tops, lineBottoms: bottoms);
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

      final text = CustomPaint(
        painter: _PaceBarPainter(
          layout: _layoutKey == layoutKey ? _layout : null,
          marks: _c.marks,
          colors: _colors,
          rtl: isRtl,
          gutter: gutter,
          top: readingY,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, readingY, gutter, height - readingY),
          child: Text.rich(key: _textKey, marked.span, textDirection: direction),
        ),
      );

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
                    Colors.black.withValues(alpha: 0.85 * widget.backgroundOpacity),
                    Colors.black.withValues(alpha: 0.35 * widget.backgroundOpacity),
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
          child: IgnorePointer(child: Center(child: _HoldBadge(kind: _c.holding, fontSize: widget.fontSize))),
        ),
      ]);

      return ColoredBox(
        color: Colors.black.withValues(alpha: widget.backgroundOpacity),
        child: widget.mirror
            ? Transform(alignment: Alignment.center, transform: Matrix4.diagonal3Values(-1, 1, 1), child: prompter)
            : prompter,
      );
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
    final arrow = Icon(rtl ? Icons.arrow_left_rounded : Icons.arrow_right_rounded, color: Colors.white70, size: 32);
    return SizedBox(
      height: 4,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: 0.08))),
        Positioned(top: -14, left: rtl ? null : gutter * 0.5 - 20, right: rtl ? gutter * 0.5 - 20 : null, child: arrow),
      ]),
    );
  }
}

/// A badge that shows while the prompter holds at a pause or a breath.
class _HoldBadge extends StatelessWidget {
  const _HoldBadge({required this.kind, required this.fontSize});

  final MarkKind? kind;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final k = kind;
    final (label, icon) = switch (k) {
      MarkKind.pauseLong => ('LONG PAUSE', Icons.pause_circle_filled_rounded),
      MarkKind.breath => ('BREATHE', Icons.air_rounded),
      _ => ('PAUSE', Icons.pause_circle_filled_rounded),
    };
    final color = k == null ? Colors.transparent : CueColors.stage.of(k);
    return AnimatedOpacity(
      opacity: k == null ? 0 : 1,
      duration: const Duration(milliseconds: 120),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: fontSize * 0.4, vertical: fontSize * 0.12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(fontSize),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: fontSize * 0.5),
          SizedBox(width: fontSize * 0.15),
          Text(label,
              style: TextStyle(
                color: color,
                fontSize: fontSize * 0.34,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              )),
        ]),
      ),
    );
  }
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
