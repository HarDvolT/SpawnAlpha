import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The amber cue button: only for the action that brings the director's
/// proposals to life (Accept all) or ships the result (Export).
ButtonStyle cueButtonStyle(BuildContext context) {
  final p = SaTheme.of(context);
  return FilledButton.styleFrom(
    backgroundColor: p.cue,
    foregroundColor: p.onCue,
    textStyle: SaType.label,
    minimumSize: const Size(40, 40),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SaRadius.md)),
  );
}

/// A plain button: low emphasis, next to a stronger one.
ButtonStyle plainButtonStyle(BuildContext context) =>
    TextButton.styleFrom(foregroundColor: SaTheme.of(context).ink2, textStyle: SaType.label);

/// A count in a `cue` disc, as on the pending banner and library tiles.
class CueCount extends StatelessWidget {
  const CueCount(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.cue, borderRadius: BorderRadius.circular(SaRadius.full)),
      child: Text('$count', style: SaType.label.copyWith(color: p.onCue, fontWeight: FontWeight.w700)),
    );
  }
}

/// The banner above the script while proposed cues wait for review.
class PendingBanner extends StatelessWidget {
  const PendingBanner({super.key, required this.count, required this.onDiscard, required this.onAcceptAll});

  final int count;
  final VoidCallback onDiscard;
  final VoidCallback onAcceptAll;

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(SaSpace.s4, SaSpace.s3, SaSpace.s3, SaSpace.s3),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border.all(color: p.lineStrong),
          borderRadius: BorderRadius.circular(SaRadius.md),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final message = Row(children: [
            CueCount(count),
            const SizedBox(width: SaSpace.s3),
            Expanded(
              child: Text(
                'Proposed cues are faded until you accept them. Tap a word to change one.',
                style: SaType.bodySm.copyWith(color: p.ink),
              ),
            ),
          ]);
          final actions = [
            TextButton(style: plainButtonStyle(context), onPressed: onDiscard, child: const Text('Discard')),
            const SizedBox(width: SaSpace.s2),
            FilledButton.icon(
              style: cueButtonStyle(context),
              onPressed: onAcceptAll,
              icon: const Icon(Icons.done_all_rounded, size: 20),
              label: const Text('Accept all'),
            ),
          ];
          if (constraints.maxWidth >= 560) return Row(children: [Expanded(child: message), ...actions]);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            message,
            const SizedBox(height: SaSpace.s2),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ]);
        }),
      ),
    );
  }
}

/// A small rounded icon well, as used for list leading icons.
class IconWell extends StatelessWidget {
  const IconWell(this.icon, {super.key, this.size = 36});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: p.surfaceSunk, borderRadius: BorderRadius.circular(SaRadius.sm + 2)),
      child: Icon(icon, size: size * 0.55, color: p.ink),
    );
  }
}
