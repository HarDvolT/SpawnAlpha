import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../prompter/marked_text.dart';
import '../theme/theme.dart';

/// A director's note pinned to a place in the script.
class PageNote {
  const PageNote({required this.offset, required this.text});

  /// The character offset in the script text the note belongs to: the word
  /// a run or stress starts on, or the word a pause follows.
  final int offset;
  final String text;
}

/// The editor's script page (MarkedScript in the design language): the
/// marked script, amber marker swipes behind stressed words, and the
/// director's notes pencilled in the margin beside their lines.
///
/// One render object lays out the text and the notes and paints the
/// markers, so a marker can draw on (the director's pass) without the text
/// ever re-laying out. On narrow screens the margin folds away; the notes
/// stay readable in the word sheet.
class ScriptPage extends LeafRenderObjectWidget {
  const ScriptPage({
    super.key,
    required this.text,
    required this.textDirection,
    required this.markers,
    required this.notes,
    required this.markerColor,
    required this.noteStyle,
    required this.ruleColor,
    this.reveal = 1,
    this.textScaler = TextScaler.noScaling,
  });

  final InlineSpan text;
  final TextDirection textDirection;

  /// Character ranges to swipe, from [MarkedText.stressRanges].
  final List<(int start, int end, bool accepted)> markers;
  final List<PageNote> notes;

  /// The marker at full strength; proposals get about half.
  final Color markerColor;
  final TextStyle noteStyle;
  final Color ruleColor;

  /// Progress of the director's pass, from 0 (nothing drawn) to 1 (all
  /// marks and notes in place).
  final double reveal;
  final TextScaler textScaler;

  /// Width of the margin, and the gap between it and the text.
  static const marginWidth = 220.0;
  static const marginGap = 40.0;

  /// Below this width the margin folds away.
  static const minWidthForMargin = 640.0;

  @override
  RenderScriptPage createRenderObject(BuildContext context) => RenderScriptPage(
        text: text,
        textDirection: textDirection,
        markers: markers,
        notes: notes,
        markerColor: markerColor,
        noteStyle: noteStyle,
        ruleColor: ruleColor,
        reveal: reveal,
        textScaler: textScaler,
      );

  @override
  void updateRenderObject(BuildContext context, RenderScriptPage renderObject) {
    renderObject
      ..text = text
      ..textDirection = textDirection
      ..markers = markers
      ..notes = notes
      ..markerColor = markerColor
      ..noteStyle = noteStyle
      ..ruleColor = ruleColor
      ..reveal = reveal
      ..textScaler = textScaler;
  }
}

class RenderScriptPage extends RenderBox {
  RenderScriptPage({
    required InlineSpan text,
    required TextDirection textDirection,
    required this._markers,
    required this._notes,
    required this._markerColor,
    required this._noteStyle,
    required this._ruleColor,
    required this._reveal,
    required TextScaler textScaler,
  }) : _painter = TextPainter(text: text, textDirection: textDirection, textScaler: textScaler);

  final TextPainter _painter;
  var _notePainters = <TextPainter>[];
  var _noteTops = <double>[];
  var _shownNotes = <PageNote>[];
  bool _hasMargin = false;
  double _textX = 0;
  double _marginX = 0;

  // ---- properties ---------------------------------------------------------

  set text(InlineSpan value) {
    final old = _painter.text;
    if (old == value) return;
    final change = old?.compareTo(value) ?? RenderComparison.layout;
    _painter.text = value;
    if (change.index >= RenderComparison.layout.index) {
      markNeedsLayout();
      markNeedsSemanticsUpdate();
    } else {
      markNeedsPaint();
    }
  }

  set textDirection(TextDirection value) {
    if (_painter.textDirection == value) return;
    _painter.textDirection = value;
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    if (_painter.textScaler == value) return;
    _painter.textScaler = value;
    markNeedsLayout();
  }

  List<(int, int, bool)> _markers;
  set markers(List<(int, int, bool)> value) {
    if (_listEquals(_markers, value)) return;
    _markers = value;
    markNeedsPaint();
  }

  List<PageNote> _notes;
  set notes(List<PageNote> value) {
    if (_notesEqual(_notes, value)) return;
    _notes = value;
    markNeedsLayout();
  }

  Color _markerColor;
  set markerColor(Color value) {
    if (_markerColor == value) return;
    _markerColor = value;
    markNeedsPaint();
  }

  TextStyle _noteStyle;
  set noteStyle(TextStyle value) {
    if (_noteStyle == value) return;
    _noteStyle = value;
    markNeedsLayout();
  }

  Color _ruleColor;
  set ruleColor(Color value) {
    if (_ruleColor == value) return;
    _ruleColor = value;
    markNeedsPaint();
  }

  double _reveal;
  set reveal(double value) {
    if (_reveal == value) return;
    _reveal = value;
    markNeedsPaint();
  }

  bool get _rtl => _painter.textDirection == TextDirection.rtl;

  /// The character offset in the script at [local], or null outside the
  /// text (in the margin).
  int? textOffsetAt(Offset local) {
    final x = local.dx - _textX;
    if (x < 0 || x > _painter.width) return null;
    return _painter.getPositionForOffset(Offset(x, local.dy)).offset;
  }

  /// The script's plain text.
  String get plainText => _painter.plainText;

  /// Where the characters [start] to [end] sit on the page (their first
  /// line), or null.
  Rect? rectOf(int start, int end) {
    final boxes = _painter.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end));
    return boxes.isEmpty ? null : boxes.first.toRect().shift(Offset(_textX, 0));
  }

  /// Where each note in the margin sits on the page, in order; empty while
  /// the margin is folded away. Notes that could not sit near their line
  /// are left out.
  List<Rect> get noteRects => [
        for (final (i, p) in _notePainters.indexed)
          Rect.fromLTWH(_marginX, _noteTops[i], ScriptPage.marginWidth, p.height),
      ];

  // ---- layout -------------------------------------------------------------

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    _hasMargin = _notes.isNotEmpty && width >= ScriptPage.minWidthForMargin;
    final textWidth = _hasMargin ? width - ScriptPage.marginWidth - ScriptPage.marginGap : width;
    _painter.layout(maxWidth: textWidth);
    // The margin is on the trailing side: right in English and French,
    // left in Arabic.
    _textX = _hasMargin && _rtl ? ScriptPage.marginWidth + ScriptPage.marginGap : 0;
    _marginX = _rtl ? 0 : textWidth + ScriptPage.marginGap;

    for (final p in _notePainters) {
      p.dispose();
    }
    _notePainters = [];
    _noteTops = [];
    var bottom = _painter.height;
    _shownNotes = [];
    if (_hasMargin) {
      // Each note sits level with its line, pushed down if it would overlap
      // the one above. A note that would drift more than a line away from
      // its words is left out of the margin (the word sheet still shows
      // it): a note beside the wrong line misleads.
      final maxDrift = _painter.preferredLineHeight * 1.2;
      var last = double.negativeInfinity;
      for (final note in _notes) {
        final anchor = _lineTop(note.offset);
        final painter = TextPainter(
          text: TextSpan(text: note.text, style: _noteStyle),
          textDirection: _painter.textDirection,
          textScaler: _painter.textScaler,
        )..layout(maxWidth: ScriptPage.marginWidth - _arrowWidth);
        final top = math.max(anchor, last + SaSpace.s2);
        if (top - anchor > maxDrift) {
          painter.dispose();
          continue;
        }
        _notePainters.add(painter);
        _noteTops.add(top);
        _shownNotes.add(note);
        last = top + painter.height;
      }
      bottom = math.max(bottom, last);
    }
    size = constraints.constrain(Size(width, bottom));
  }

  static const _arrowWidth = 30.0;

  double _lineTop(int offset) {
    final length = _painter.plainText.length;
    if (length == 0) return 0;
    final start = offset.clamp(0, length - 1);
    final boxes = _painter.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + 1));
    return boxes.isEmpty ? 0 : boxes.first.top;
  }

  // ---- the director's pass -----------------------------------------------

  // Marks land in reading order, about 70ms apart; each note writes on
  // 260ms after its mark. [reveal] runs from 0 to 1 over the whole pass.
  static const _step = 70.0;
  static const _markerMs = 420.0;
  static const _noteDelay = 260.0;
  static const _noteMs = 700.0;

  double get _passMs {
    final count = math.max(_markers.length, _notes.length);
    return count * _step + _noteDelay + _noteMs;
  }

  double _progress(int rank, double delay, double duration) {
    if (_reveal >= 1) return 1;
    final t = _reveal * _passMs - rank * _step - delay;
    return Curves.easeOutCubic.transform((t / duration).clamp(0.0, 1.0));
  }

  int _rankOf(int offset) {
    var rank = 0;
    for (final (start, _, _) in _markers) {
      if (start < offset) rank++;
    }
    return rank;
  }

  // ---- paint --------------------------------------------------------------

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final origin = offset + Offset(_textX, 0);

    for (final (i, (start, end, accepted)) in _markers.indexed) {
      final progress = _progress(i, 0, _markerMs);
      if (progress <= 0) continue;
      final color = accepted ? _markerColor : _markerColor.withValues(alpha: _markerColor.a * 34 / 72);
      final boxes = _painter.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end));
      // A marker across a line break swipes each piece in turn.
      final total = boxes.fold(0.0, (sum, b) => sum + (b.right - b.left));
      var drawn = 0.0;
      for (final box in boxes) {
        final w = box.right - box.left;
        final piece = total == 0 ? 1.0 : ((progress * total - drawn) / w).clamp(0.0, 1.0);
        paintMarkerBand(canvas, box.toRect().shift(origin), color, progress: piece, rtl: _rtl);
        drawn += w;
      }
    }

    _painter.paint(canvas, origin);

    if (!_hasMargin) return;
    // A dashed rule between the text and the margin.
    final ruleX = offset.dx + (_rtl ? ScriptPage.marginWidth + ScriptPage.marginGap / 2 : _marginX - ScriptPage.marginGap / 2);
    final rule = Paint()
      ..color = _ruleColor
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 8) {
      canvas.drawLine(Offset(ruleX, offset.dy + y), Offset(ruleX, offset.dy + math.min(y + 4, size.height)), rule);
    }

    for (final (i, painter) in _notePainters.indexed) {
      final progress = _progress(_rankOf(_shownNotes[i].offset), _noteDelay, _noteMs);
      if (progress <= 0) continue;
      final top = offset.dy + _noteTops[i];
      final left = offset.dx + _marginX;
      final area = Rect.fromLTWH(left, top, ScriptPage.marginWidth, painter.height);
      canvas.save();
      // Pencil writes on in the reading direction.
      final shown = area.width * progress;
      canvas.clipRect(_rtl
          ? Rect.fromLTRB(area.right - shown, area.top - 2, area.right, area.bottom + 2)
          : Rect.fromLTRB(area.left, area.top - 2, area.left + shown, area.bottom + 2));
      _paintArrow(canvas, Offset(_rtl ? area.right - _arrowWidth : area.left, top), _noteStyle.color ?? _ruleColor);
      painter.paint(canvas, Offset(_rtl ? area.right - _arrowWidth - painter.width : area.left + _arrowWidth, top));
      canvas.restore();
    }
  }

  /// A small pencil arrow pointing back at the text.
  void _paintArrow(Canvas canvas, Offset at, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: color.a * 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Drawn for a margin on the right, pointing left; mirrored for Arabic.
    double x(double v) => _rtl ? at.dx + _arrowWidth - v : at.dx + v;
    final y0 = at.dy + 4;
    final path = Path()
      ..moveTo(x(24), y0 + 10)
      ..quadraticBezierTo(x(12), y0 + 10, x(3), y0 + 2)
      ..moveTo(x(3), y0 + 2)
      ..lineTo(x(3.5), y0 + 8)
      ..moveTo(x(3), y0 + 2)
      ..lineTo(x(9), y0 + 3);
    canvas.drawPath(path, paint);
  }

  // ---- input and semantics ------------------------------------------------

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..textDirection = _painter.textDirection
      ..label = _painter.plainText;
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) {
    // Measure with a separate painter, so the laid-out one is untouched.
    final probe = TextPainter(text: _painter.text, textDirection: _painter.textDirection, textScaler: _painter.textScaler)
      ..layout();
    final width = probe.maxIntrinsicWidth;
    probe.dispose();
    return width;
  }

  @override
  void dispose() {
    _painter.dispose();
    for (final p in _notePainters) {
      p.dispose();
    }
    super.dispose();
  }

  static bool _listEquals(List<(int, int, bool)> a, List<(int, int, bool)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _notesEqual(List<PageNote> a, List<PageNote> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].offset != b[i].offset || a[i].text != b[i].text) return false;
    }
    return true;
  }
}
