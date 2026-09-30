import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../prompter/prompter_controller.dart';
import '../prompter/prompter_view.dart';
import 'format.dart';

/// Keyboard control of the prompter, mostly for Windows:
///
/// - Space: play or pause
/// - Up and Down: speed (timed) or line by line (manual)
/// - Left and Right: previous or next sentence
/// - T: switch between timed and manual scroll
/// - Home: back to the start
/// - M: mirror
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
  });

  final PrompterController controller;
  final GlobalKey<PrompterViewState> view;
  final VoidCallback onMirror;
  final ValueChanged<int> onFontSize;

  /// Replaces the default play and pause, e.g. to start a recording.
  final VoidCallback? onPlayPause;
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
        } else if (key == LogicalKeyboardKey.home) {
          c.restart();
        } else if (key == LogicalKeyboardKey.keyM) {
          onMirror();
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

/// The bar under the prompter: play, speed, scroll mode, mirror and size.
class PrompterControls extends StatelessWidget {
  const PrompterControls({
    super.key,
    required this.controller,
    required this.mirror,
    required this.onMirror,
    required this.onFontSize,
    this.showPlay = true,
  });

  final PrompterController controller;
  final bool mirror;
  final VoidCallback onMirror;
  final ValueChanged<int> onFontSize;

  /// False when a record button drives playback instead.
  final bool showPlay;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final timed = c.mode == ScrollMode.timed;
        return IconButtonTheme(
          data: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: Colors.white)),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
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
                    width: 116,
                    child: Text(
                      '${c.speed.toStringAsFixed(1)}×  ${c.effectiveWpm} wpm',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Faster (Up)',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: c.faster,
                  ),
                  Text(formatDuration(c.remaining)),
                ],
                const SizedBox(width: 8),
                SegmentedButton<ScrollMode>(
                  style: SegmentedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    selectedForegroundColor: Colors.black,
                    selectedBackgroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    visualDensity: VisualDensity.compact,
                  ),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ScrollMode.timed, label: Text('Timed'), tooltip: 'Scrolls at the planned pace (T)'),
                    ButtonSegment(value: ScrollMode.manual, label: Text('Manual'), tooltip: 'You scroll (T)'),
                  ],
                  selected: {c.mode},
                  onSelectionChanged: (s) => c.setMode(s.single),
                ),
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
