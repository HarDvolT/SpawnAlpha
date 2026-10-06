import 'package:flutter/material.dart';

import '../model/cut_plan.dart';
import '../review/repeated_sections.dart';
import '../cut/clean_plan.dart';
import '../theme/theme.dart';
import 'format.dart';

class RetakeReviewPanel extends StatefulWidget {
  const RetakeReviewPanel({
    super.key,
    required this.sections,
    required this.busy,
    this.onListen,
    this.plan,
    this.onSelect,
  });
  final List<RepeatedSection> sections;
  final bool busy;
  final ValueChanged<SourceRange>? onListen;
  final CleanPlan? plan;
  final void Function(String, int?)? onSelect;
  @override
  State<RetakeReviewPanel> createState() => _RetakeReviewPanelState();
}

class _RetakeReviewPanelState extends State<RetakeReviewPanel> {
  var _section = 0, _attemptPage = 0;
  static const _pageSize = 3;
  @override
  void didUpdateWidget(RetakeReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.sections, oldWidget.sections)) {
      _section = _attemptPage = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) return const SizedBox.shrink();
    final p = SaTheme.of(context), section = widget.sections[_section];
    final pageCount = (section.attempts.length / _pageSize).ceil();
    final first = _attemptPage * _pageSize;
    final choice = widget.plan?.retakes
        .where((r) => r.id == section.id)
        .firstOrNull;
    Widget reading(String text) => Directionality(
      textDirection: section.language.isRtl
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Align(
        alignment: section.language.isRtl
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Text(text, style: SaType.body.copyWith(color: p.ink)),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Compare attempts', style: SaType.title.copyWith(color: p.ink)),
        const SizedBox(height: SaSpace.s2),
        Text(
          widget.onSelect == null
              ? 'Hear each attempt. Everything is kept while you compare.'
              : 'Hear the original, then choose what stays in your cut.',
          style: SaType.bodySm.copyWith(color: p.ink2),
        ),
        const SizedBox(height: SaSpace.s3),
        Text(
          'Repeated section ${_section + 1} of ${widget.sections.length}',
          style: SaType.signalLabel.copyWith(color: p.ink2),
        ),
        Text('In your script', style: SaType.bodySm.copyWith(color: p.ink2)),
        reading(section.scriptText),
        if (choice != null)
          TextButton.icon(
            onPressed: widget.busy || choice.selected == null
                ? null
                : () => widget.onSelect?.call(choice.id, null),
            icon: const Icon(Icons.restore_rounded),
            label: Text(
              choice.selected == null
                  ? 'All attempts kept'
                  : 'Keep all attempts',
            ),
          ),
        for (final (offset, attempt)
            in section.attempts.skip(first).take(_pageSize).indexed) ...[
          const SizedBox(height: SaSpace.s3),
          Text(
            'Attempt ${first + offset + 1} of ${section.attempts.length}',
            style: SaType.signalLabel.copyWith(color: p.ink),
          ),
          reading(attempt.text),
          if (choice != null)
            Text(
              choice.selected == null || choice.selected == first + offset
                  ? 'Kept in cut'
                  : 'Removed from cut',
              style: SaType.bodySm.copyWith(color: p.ink2),
            ),
          Text(
            '${formatCutTime(attempt.range.start)}–${formatCutTime(attempt.range.end)} · ${attempt.matched} of ${section.scriptWords} script words matched${attempt.covered < section.scriptWords ? ' · Partial section' : ''}',
            style: SaType.bodySm.copyWith(color: p.ink2),
          ),
          if (attempt.changed > 0 || attempt.added > 0)
            Text(
              '${attempt.changed} changed · ${attempt.added} added within this section',
              style: SaType.bodySm.copyWith(color: p.ink2),
            ),
          if (attempt.uncertain > 0)
            Text(
              '${attempt.uncertain} words need a wording check',
              style: SaType.bodySm.copyWith(color: p.ink2),
            ),
          if (widget.onListen != null)
            TextButton.icon(
              onPressed: widget.busy
                  ? null
                  : () => widget.onListen!(attempt.range),
              icon: const Icon(Icons.hearing_rounded),
              label: Text('Hear attempt ${first + offset + 1}'),
            ),
          if (choice != null && widget.onSelect != null) ...[
            OutlinedButton(
              onPressed:
                  widget.busy ||
                      choice.selected == first + offset ||
                      !choice.canSelect(first + offset)
                  ? null
                  : () => widget.onSelect!(choice.id, first + offset),
              child: Text('Keep attempt ${first + offset + 1}'),
            ),
            if (!choice.canSelect(first + offset))
              Text(
                attempt.covered < section.scriptWords
                    ? 'This attempt is only part of the section.'
                    : 'A safe cut was not found. Keep the attempts together.',
                style: SaType.bodySm.copyWith(color: p.ink2),
              ),
          ],
        ],
        if (pageCount > 1)
          Wrap(
            spacing: SaSpace.s2,
            children: [
              TextButton(
                onPressed: _attemptPage == 0
                    ? null
                    : () => setState(() => --_attemptPage),
                child: const Text('Previous attempts'),
              ),
              TextButton(
                onPressed: _attemptPage + 1 >= pageCount
                    ? null
                    : () => setState(() => ++_attemptPage),
                child: const Text('More attempts'),
              ),
            ],
          ),
        if (widget.sections.length > 1)
          Wrap(
            spacing: SaSpace.s2,
            children: [
              TextButton(
                onPressed: _section == 0
                    ? null
                    : () => setState(() {
                        --_section;
                        _attemptPage = 0;
                      }),
                child: const Text('Previous section'),
              ),
              TextButton(
                onPressed: _section + 1 >= widget.sections.length
                    ? null
                    : () => setState(() {
                        ++_section;
                        _attemptPage = 0;
                      }),
                child: const Text('Next section'),
              ),
            ],
          ),
      ],
    );
  }
}
