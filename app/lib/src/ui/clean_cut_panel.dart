import 'package:flutter/material.dart';

import '../cut/clean_plan.dart';
import '../theme/theme.dart';
import 'format.dart';

class CleanCutPanel extends StatefulWidget {
  const CleanCutPanel({
    super.key,
    required this.plan,
    required this.busy,
    required this.onChanged,
    required this.onRestore,
    this.onListen,
  });
  final CleanPlan plan;
  final bool busy;
  final void Function(String, bool) onChanged;
  final VoidCallback onRestore;
  final ValueChanged<CutChange>? onListen;
  @override
  State<CleanCutPanel> createState() => _CleanCutPanelState();
}

class _CleanCutPanelState extends State<CleanCutPanel> {
  var _shown = 8;
  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context), plan = widget.plan, cut = plan.asCutPlan();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your cut', style: SaType.title.copyWith(color: p.ink)),
        const SizedBox(height: SaSpace.s2),
        Text(
          '${formatCutTime(plan.sourceDuration)} → ${formatCutTime(cut.duration)}',
          style: SaType.signalLabel.copyWith(color: p.ink),
        ),
        const SizedBox(height: SaSpace.s2),
        Text(
          'Words, marked pauses and breaths stay unless you choose a filler or another retake. Turn off a change to restore that part of the original.',
          style: SaType.bodySm.copyWith(color: p.ink2),
        ),
        if (plan.notice != null)
          Text(plan.notice!, style: SaType.bodySm.copyWith(color: p.ink2)),
        if (plan.changes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SaSpace.s3),
            child: Text(
              'No safe gaps or filler removals found.',
              style: SaType.body.copyWith(color: p.ink),
            ),
          ),
        for (final change in plan.changes.take(_shown))
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: change.enabled,
            onChanged:
                widget.busy ||
                    plan.discardedRetakes.any(
                      (r) =>
                          change.spokenIndices.isNotEmpty &&
                          change.spokenIndices.first >= r.firstWord &&
                          change.spokenIndices.last <= r.lastWord,
                    )
                ? null
                : (value) => widget.onChanged(change.id, value),
            title: Text(
              change.kind == CutChangeKind.filler
                  ? 'Possible filler'
                  : 'Shorten a silent gap',
              style: SaType.body.copyWith(color: p.ink),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (change.text != null)
                  Directionality(
                    textDirection: plan.language.isRtl
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: Align(
                      alignment: plan.language.isRtl
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Text(
                        change.text!,
                        style: SaType.body.copyWith(color: p.ink),
                      ),
                    ),
                  ),
                Text(
                  '${formatCutTime(change.range.start)}–${formatCutTime(change.range.end)} · ${plan.discardedRetakes.any((r) => change.spokenIndices.isNotEmpty && change.spokenIndices.first >= r.firstWord && change.spokenIndices.last <= r.lastWord)
                      ? 'Removed with another attempt'
                      : change.enabled
                      ? 'Removed'
                      : change.kind == CutChangeKind.filler
                      ? 'Kept · check meaning'
                      : 'Original restored'}',
                  style: SaType.bodySm.copyWith(color: p.ink2),
                ),
                if (change.kind == CutChangeKind.filler &&
                    widget.onListen != null)
                  TextButton.icon(
                    onPressed: widget.busy
                        ? null
                        : () => widget.onListen!(change),
                    icon: const Icon(Icons.hearing_rounded),
                    label: const Text('Hear this phrase'),
                  ),
              ],
            ),
          ),
        if (plan.changes.length > _shown)
          TextButton(
            onPressed: () => setState(() => _shown += 8),
            child: const Text('Show more changes'),
          ),
        if (plan.changes.any((c) => c.enabled) || plan.hasRetakeSelection)
          OutlinedButton.icon(
            onPressed: widget.busy ? null : widget.onRestore,
            icon: const Icon(Icons.restore_rounded),
            label: Text(
              plan.changes.any((c) => c.kind == CutChangeKind.filler) ||
                      plan.retakes.isNotEmpty
                  ? 'Restore all changes'
                  : 'Restore all gaps',
            ),
          ),
      ],
    );
  }
}
