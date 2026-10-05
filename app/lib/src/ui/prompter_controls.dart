import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../prompter/guide.dart';
import '../prompter/prompter_controller.dart';
import '../prompter/prompter_view.dart';
import '../theme/theme.dart';
import 'format.dart';

/// Keyboard control of the prompter, mostly for Windows:
///
/// - Space: play or pause
/// - Up and Down: speed (timed) or line by line (manual)
/// - Left and Right: previous or next sentence
/// - T: switch between timed and manual scroll
/// - V: voice pacing (where a microphone level is available)
/// - Home: back to the start
/// - M: mirror
/// - K: kinetic or still text
/// - G: the next guide (dot, underline, spotlight, off)
/// - Plus and Minus: text size
class PrompterShortcuts extends StatelessWidget {
  const PrompterShortcuts({
    super.key,
    required this.controller,
    required this.view,
    required this.onMirror,
    required this.onFontSize,
    required this.child,
    this.onPlayPause,
    this.onKinetic,
    this.onNextGuide,
    this.voiceAvailable = false,
  });

  final PrompterController controller;
  final GlobalKey<PrompterViewState> view;
  final VoidCallback onMirror;
  final ValueChanged<int> onFontSize;

  /// Replaces the default play and pause, e.g. to start a recording.
  final VoidCallback? onPlayPause;

  /// Switches between kinetic and still text.
  final VoidCallback? onKinetic;

  /// Moves to the next guide.
  final VoidCallback? onNextGuide;

  /// Whether voice pacing can be chosen (a microphone level is available).
  final bool voiceAvailable;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        final manual = c.mode == ScrollMode.manual;
        if (key == LogicalKeyboardKey.space) {
          (onPlayPause ?? c.togglePlay)();
        } else if (key == LogicalKeyboardKey.arrowUp) {
          manual ? view.currentState?.nudge(-1) : c.faster();
        } else if (key == LogicalKeyboardKey.arrowDown) {
          manual ? view.currentState?.nudge(1) : c.slower();
        } else if (key == LogicalKeyboardKey.arrowLeft) {
          c.previousSentence();
        } else if (key == LogicalKeyboardKey.arrowRight) {
          c.nextSentence();
        } else if (key == LogicalKeyboardKey.keyT) {
          c.setMode(manual ? ScrollMode.timed : ScrollMode.manual);
        } else if (key == LogicalKeyboardKey.keyV && voiceAvailable) {
          c.setMode(ScrollMode.voice);
        } else if (key == LogicalKeyboardKey.home) {
          c.restart();
        } else if (key == LogicalKeyboardKey.keyM) {
          onMirror();
        } else if (key == LogicalKeyboardKey.keyK && onKinetic != null) {
          onKinetic!();
        } else if (key == LogicalKeyboardKey.keyG && onNextGuide != null) {
          onNextGuide!();
        } else if (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.numpadAdd) {
          onFontSize(4);
        } else if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
          onFontSize(-4);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}

/// The bar under the prompter: play and speed, then the speaker's
/// choices (pace, guide, motion, kinetic or still), size and mirror.
class PrompterControls extends StatelessWidget {
  const PrompterControls({
    super.key,
    required this.controller,
    required this.mirror,
    required this.onMirror,
    required this.onFontSize,
    this.showPlay = true,
    this.kinetic,
    this.onKinetic,
    this.guide,
    this.onGuide,
    this.motion,
    this.onMotion,
    this.alignment,
    this.onAlignment,
    this.voiceAvailable = false,
  });

  final PrompterController controller;
  final bool mirror;
  final VoidCallback onMirror;
  final ValueChanged<int> onFontSize;

  /// Kinetic or still text; null hides the switch (reduced motion).
  final bool? kinetic;
  final ValueChanged<bool>? onKinetic;

  /// The guide to the word to say; null hides the choice.
  final PrompterGuide? guide;
  final ValueChanged<PrompterGuide>? onGuide;

  /// Line step or smooth; null hides the choice.
  final PrompterMotion? motion;
  final ValueChanged<PrompterMotion>? onMotion;

  final PrompterAlignment? alignment;
  final ValueChanged<PrompterAlignment>? onAlignment;

  /// Whether to offer voice pacing.
  final bool voiceAvailable;

  /// False when a record button drives playback instead.
  final bool showPlay;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        // Timed and voice both run on the planned pace; manual is by hand.
        final timed = c.mode != ScrollMode.manual;
        final stage = SaPalette.dark;
        return IconButtonTheme(
          data: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: stage.stageChromeText)),
          child: DefaultTextStyle.merge(
            style: SaType.meter.copyWith(color: stage.stageChromeText),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: SaSpace.s2,
              children: [
                if (showPlay) ...[
                  IconButton(
                    tooltip: 'Back to start (Home)',
                    icon: const Icon(Icons.replay_rounded),
                    onPressed: c.restart,
                  ),
                  IconButton.filled(
                    tooltip: c.isPlaying ? 'Pause (Space)' : 'Play (Space)',
                    iconSize: 32,
                    style: IconButton.styleFrom(
                      backgroundColor: stage.stageText,
                      foregroundColor: stage.stage,
                      disabledBackgroundColor: stage.stageText.withValues(alpha: 0.38),
                    ),
                    icon: Icon(c.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    onPressed: timed ? c.togglePlay : null,
                  ),
                ],
                if (timed) ...[
                  IconButton(
                    tooltip: 'Slower (Down)',
                    icon: const Icon(Icons.remove_rounded),
                    onPressed: c.slower,
                  ),
                  SizedBox(
                    width: 132,
                    child: Text(
                      '${c.speed.toStringAsFixed(1)}× · ${c.effectiveWpm} WPM',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Faster (Up)',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: c.faster,
                  ),
                  Text(formatDuration(c.remaining), style: SaType.timecode.copyWith(color: stage.stageText)),
                ],
                const SizedBox(width: 8),
                _Group(label: 'Pace', child: PaceChoice(controller: c, voiceAvailable: voiceAvailable)),
                if (guide != null) _Group(label: 'Guide', child: GuideChoice(guide: guide!, onChanged: onGuide)),
                if (motion != null) _Group(label: 'Motion', child: MotionChoice(motion: motion!, onChanged: onMotion)),
                if (alignment != null) _Group(label: 'Align', child: AlignmentChoice(alignment: alignment!, onChanged: onAlignment)),
                if (kinetic != null) CuesChoice(kinetic: kinetic!, onChanged: onKinetic),
                IconButton(
                  tooltip: 'Smaller text (−)',
                  icon: const Icon(Icons.text_decrease_rounded),
                  onPressed: () => onFontSize(-4),
                ),
                IconButton(
                  tooltip: 'Larger text (+)',
                  icon: const Icon(Icons.text_increase_rounded),
                  onPressed: () => onFontSize(4),
                ),
                IconButton(
                  tooltip: 'Mirror (M)',
                  isSelected: mirror,
                  icon: const Icon(Icons.flip_rounded),
                  onPressed: onMirror,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A group of choices with a small stage label before it, in the signal
/// face. The label and its choices always wrap together.
class _Group extends StatelessWidget {
  const _Group({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: SaSpace.s2),
        // On a narrow screen the label goes above its choices.
        child: Wrap(
          spacing: SaSpace.s2,
          runSpacing: SaSpace.s1,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(label.toUpperCase(), style: SaType.signalLabel.copyWith(color: SaPalette.dark.stageChromeText)),
            child,
          ],
        ),
      );
}

/// The stage look for a row of choices: dark, with the choice lit.
ButtonStyle stageSegmentStyle() {
  final stage = SaPalette.dark;
  return SegmentedButton.styleFrom(
    foregroundColor: stage.stageChromeText,
    selectedForegroundColor: stage.stage,
    selectedBackgroundColor: stage.stageText,
    backgroundColor: stage.stage.withValues(alpha: 0.4),
    side: BorderSide(color: stage.stageGlassEdge),
    visualDensity: VisualDensity.compact,
    textStyle: SaType.label,
    padding: const EdgeInsets.symmetric(horizontal: SaSpace.s2),
  );
}

/// Timed, Voice (where a microphone level is available) or Manual.
class PaceChoice extends StatelessWidget {
  const PaceChoice({super.key, required this.controller, required this.voiceAvailable, this.manual = true});

  final PrompterController controller;
  final bool voiceAvailable;

  /// Offer Manual too (not while recording, where the voice or the plan
  /// drives the prompter).
  final bool manual;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SegmentedButton<ScrollMode>(
          style: stageSegmentStyle(),
          showSelectedIcon: false,
          segments: [
            if (voiceAvailable)
              const ButtonSegment(
                value: ScrollMode.voice,
                label: Text('Voice'),
                tooltip: 'Moves while you talk, waits when you stop (V)',
              ),
            const ButtonSegment(value: ScrollMode.timed, label: Text('Timed'), tooltip: 'Scrolls at the planned pace (T)'),
            if (manual) const ButtonSegment(value: ScrollMode.manual, label: Text('Manual'), tooltip: 'You scroll (T)'),
          ],
          selected: {controller.mode},
          onSelectionChanged: (s) => controller.setMode(s.single),
        ),
      );
}

/// Dot, Underline, Spotlight or Off.
class GuideChoice extends StatelessWidget {
  const GuideChoice({super.key, required this.guide, required this.onChanged});

  final PrompterGuide guide;
  final ValueChanged<PrompterGuide>? onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<PrompterGuide>(
        key: const ValueKey('guide'),
        style: stageSegmentStyle(),
        showSelectedIcon: false,
        segments: [
          for (final g in PrompterGuide.values) ButtonSegment(value: g, label: Text(g.label), tooltip: '${g.hint} (G)'),
        ],
        selected: {guide},
        onSelectionChanged: (s) => onChanged?.call(s.single),
      );
}

/// Line step, Smooth or One phrase.
class MotionChoice extends StatelessWidget {
  const MotionChoice({super.key, required this.motion, required this.onChanged});

  final PrompterMotion motion;
  final ValueChanged<PrompterMotion>? onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<PrompterMotion>(
        key: const ValueKey('motion'),
        style: stageSegmentStyle(),
        showSelectedIcon: false,
        segments: [
          for (final m in PrompterMotion.values) ButtonSegment(value: m, label: Text(m.label), tooltip: m.hint),
        ],
        selected: {motion},
        onSelectionChanged: (s) => onChanged?.call(s.single),
      );
}

/// Left, Center or Right, without changing the reading direction.
class AlignmentChoice extends StatelessWidget {
  const AlignmentChoice({super.key, required this.alignment, required this.onChanged});

  final PrompterAlignment alignment;
  final ValueChanged<PrompterAlignment>? onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<PrompterAlignment>(
        key: const ValueKey('alignment'),
        style: stageSegmentStyle(),
        showSelectedIcon: false,
        segments: [
          for (final a in PrompterAlignment.values)
            ButtonSegment(value: a, label: Text(a.label), tooltip: 'Align text ${a.label.toLowerCase()}'),
        ],
        selected: {alignment},
        onSelectionChanged: (s) => onChanged?.call(s.single),
      );
}

/// Kinetic or Still.
class CuesChoice extends StatelessWidget {
  const CuesChoice({super.key, required this.kinetic, required this.onChanged});

  final bool kinetic;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
        style: stageSegmentStyle(),
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: true, label: Text('Kinetic'), tooltip: 'Cues act themselves out near the reading line (K)'),
          ButtonSegment(value: false, label: Text('Still'), tooltip: 'Only the motion, the guide and the holds (K)'),
        ],
        selected: {kinetic},
        onSelectionChanged: (s) => onChanged?.call(s.single),
      );
}
