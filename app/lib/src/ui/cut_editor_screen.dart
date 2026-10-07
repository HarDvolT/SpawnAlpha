import 'package:flutter/material.dart';

import '../cut/clean_plan.dart';
import '../cut/cut_timeline.dart';
import '../model/cut_plan.dart';
import '../model/script_document.dart';
import '../playback/local_playback.dart';
import '../review/repeated_sections.dart';
import '../theme/theme.dart';
import 'clean_cut_panel.dart';
import 'format.dart';
import 'retake_review_panel.dart';
import 'take_player.dart';

class CutEditorScreen extends StatefulWidget {
  const CutEditorScreen({
    super.key,
    required this.plan,
    required this.take,
    required this.playback,
    this.sections = const [],
    this.title,
  });
  final CleanPlan plan;
  final Take take;
  final LocalPlayback playback;
  final List<RepeatedSection> sections;
  final String? title;
  @override
  State<CutEditorScreen> createState() => _CutEditorScreenState();
}

class _CutEditorScreenState extends State<CutEditorScreen> {
  late CleanPlan _draft = widget.plan;
  SourceRange? _excerpt;
  var _request = 0, _page = 0;
  final _scroll = ScrollController();
  static const _pageSize = 8;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _hear(SourceRange range) {
    setState(() {
      _excerpt = range;
      ++_request;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    final gaps = _draft.changes
        .where((c) => c.kind == CutChangeKind.quiet)
        .toList();
    final pages = (gaps.length / _pageSize).ceil();
    final spans = cutTimeline(_draft);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit your cut')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SaSpace.s4),
          child: Wrap(
            spacing: SaSpace.s3,
            runSpacing: SaSpace.s2,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: identical(_draft, widget.plan)
                    ? null
                    : () => Navigator.pop(context, _draft),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Save changes'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.all(SaSpace.s5),
        children: [
          if (widget.title != null) ...[
            Directionality(
              textDirection: _draft.language.isRtl
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  widget.title!,
                  style: SaType.body.copyWith(color: p.ink),
                ),
              ),
            ),
            const SizedBox(height: SaSpace.s4),
          ],
          Text(
            'Keep the pause you want',
            style: SaType.title.copyWith(color: p.ink),
          ),
          const SizedBox(height: SaSpace.s2),
          Text(
            'Drag the handles inward to keep more of a shortened gap. Your words, marked pauses and original recording stay safe.',
            style: SaType.bodySm.copyWith(color: p.ink2),
          ),
          const SizedBox(height: SaSpace.s4),
          Text(
            '${formatCutTime(_draft.sourceDuration)} → ${formatCutTime(_draft.asCutPlan().duration)}',
            style: SaType.signalLabel.copyWith(color: p.ink),
          ),
          const SizedBox(height: SaSpace.s4),
          TakePlayer(
            backend: widget.playback,
            path: widget.take.path,
            excerpt: _excerpt,
            playRequest: _request,
          ),
          const SizedBox(height: SaSpace.s5),
          Text(
            'Source timeline',
            style: SaType.signalLabel.copyWith(color: p.ink2),
          ),
          Wrap(
            spacing: SaSpace.s3,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.square_rounded,
                    size: SaSpace.s3,
                    color: p.primary,
                  ),
                  const SizedBox(width: SaSpace.s1),
                  Text('Kept', style: SaType.bodySm.copyWith(color: p.ink)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.square_rounded, size: SaSpace.s3, color: p.danger),
                  const SizedBox(width: SaSpace.s1),
                  Text('Removed', style: SaType.bodySm.copyWith(color: p.ink)),
                ],
              ),
            ],
          ),
          const SizedBox(height: SaSpace.s2),
          LayoutBuilder(
            builder: (context, size) => Semantics(
              label: 'Source timeline. Tap a range to hear the original.',
              child: GestureDetector(
                onTapDown: widget.playback.supported
                    ? (tap) {
                        final time =
                            (_draft.sourceDuration.inMicroseconds *
                                    (tap.localPosition.dx / size.maxWidth)
                                        .clamp(0.0, 1.0))
                                .round();
                        _hear(
                          timelineAt(spans, Duration(microseconds: time)).range,
                        );
                      }
                    : null,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(SaRadius.sm),
                  child: CustomPaint(
                    size: Size(size.maxWidth, SaSpace.s7),
                    painter: _TimelinePainter(spans, _draft.sourceDuration, p),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: SaSpace.s2),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0:00', style: SaType.signalLabel.copyWith(color: p.ink2)),
                Text(
                  formatCutTime(_draft.sourceDuration),
                  style: SaType.signalLabel.copyWith(color: p.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(height: SaSpace.s5),
          Text(
            'Adjust shortened gaps',
            style: SaType.title.copyWith(color: p.ink),
          ),
          if (gaps.isEmpty)
            Text(
              'There are no shortened gaps to adjust.',
              style: SaType.bodySm.copyWith(color: p.ink2),
            ),
          for (final gap in gaps.skip(_page * _pageSize).take(_pageSize)) ...[
            const SizedBox(height: SaSpace.s4),
            Text(
              'Gap ${gaps.indexOf(gap) + 1} · ${formatCutTime(gap.bounds.start)}–${formatCutTime(gap.bounds.end)}',
              style: SaType.signalLabel.copyWith(color: p.ink),
            ),
            Text(
              gap.enabled
                  ? 'Removed: ${formatCutTime(gap.range.start)}–${formatCutTime(gap.range.end)}'
                  : 'Original gap kept',
              style: SaType.bodySm.copyWith(color: p.ink2),
            ),
            Directionality(
              textDirection: TextDirection.ltr,
              child: RangeSlider(
                min: 0,
                max: gap.bounds.duration.inMicroseconds.toDouble(),
                values: RangeValues(
                  (gap.range.start - gap.bounds.start).inMicroseconds
                      .toDouble(),
                  (gap.range.end - gap.bounds.start).inMicroseconds.toDouble(),
                ),
                labels: RangeLabels(
                  formatCutTime(gap.range.start),
                  formatCutTime(gap.range.end),
                ),
                semanticFormatterCallback: (value) => formatCutTime(
                  gap.bounds.start + Duration(microseconds: value.round()),
                ),
                onChanged: !gap.enabled
                    ? null
                    : (value) {
                        final start =
                            gap.bounds.start +
                            Duration(microseconds: value.start.round());
                        final end =
                            gap.bounds.start +
                            Duration(microseconds: value.end.round());
                        if (end <= start) return;
                        setState(
                          () => _draft = _draft.withRange(
                            gap.id,
                            SourceRange(start: start, end: end),
                          ),
                        );
                      },
              ),
            ),
            Wrap(
              spacing: SaSpace.s2,
              runSpacing: SaSpace.s2,
              children: [
                TextButton(
                  onPressed: () => setState(
                    () => _draft = _draft.withEnabled(gap.id, !gap.enabled),
                  ),
                  child: Text(
                    gap.enabled ? 'Keep this gap' : 'Shorten this gap',
                  ),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => _draft = _draft.withRange(gap.id, gap.bounds),
                  ),
                  child: const Text('Reset handles'),
                ),
                if (widget.playback.supported)
                  TextButton.icon(
                    onPressed: () => _hear(gap.bounds),
                    icon: const Icon(Icons.hearing_rounded),
                    label: const Text('Hear original gap'),
                  ),
              ],
            ),
          ],
          if (pages > 1)
            Wrap(
              spacing: SaSpace.s3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Page ${_page + 1} of $pages',
                  style: SaType.signalLabel.copyWith(color: p.ink2),
                ),
                TextButton(
                  onPressed: _page == 0 ? null : () => setState(() => --_page),
                  child: const Text('Previous gaps'),
                ),
                TextButton(
                  onPressed: _page + 1 >= pages
                      ? null
                      : () => setState(() => ++_page),
                  child: const Text('Next gaps'),
                ),
              ],
            ),
          const SizedBox(height: SaSpace.s5),
          CleanCutPanel(
            plan: _draft,
            busy: false,
            onChanged: (id, value) =>
                setState(() => _draft = _draft.withEnabled(id, value)),
            onRestore: () => setState(() => _draft = _draft.restoreAll()),
            onListen: widget.playback.supported
                ? (change) => _hear(change.range)
                : null,
          ),
          if (widget.sections.isNotEmpty) ...[
            const SizedBox(height: SaSpace.s5),
            RetakeReviewPanel(
              sections: widget.sections,
              busy: false,
              plan: _draft,
              onListen: widget.playback.supported ? _hear : null,
              onSelect: (id, index) =>
                  setState(() => _draft = _draft.withAttempt(id, index)),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter(this.spans, this.duration, this.palette);
  final List<CutTimelineSpan> spans;
  final Duration duration;
  final SaPalette palette;
  @override
  void paint(Canvas canvas, Size size) {
    for (final span in spans) {
      final start =
          span.range.start.inMicroseconds /
          duration.inMicroseconds *
          size.width;
      final end =
          span.range.end.inMicroseconds / duration.inMicroseconds * size.width;
      canvas.drawRect(
        Rect.fromLTRB(start, 0, end, size.height),
        Paint()..color = span.removed ? palette.danger : palette.primary,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.spans != spans || old.palette != palette || old.duration != duration;
}
