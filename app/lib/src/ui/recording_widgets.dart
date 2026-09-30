import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../recording/mic_monitor.dart';
import '../theme/theme.dart';
import 'format.dart';

/// One countdown beat: the numeral in the display face lands wide and
/// large and settles to normal width on the pop spring, while a ring
/// sweeps once around it over the beat (docs/design/motion.md, "The
/// countdown"). A new [value] starts a new beat.
class CountdownNumeral extends StatefulWidget {
  const CountdownNumeral({super.key, required this.value, this.size = 150});

  final int value;

  /// The dial's diameter.
  final double size;

  @override
  State<CountdownNumeral> createState() => _CountdownNumeralState();
}

class _CountdownNumeralState extends State<CountdownNumeral> with TickerProviderStateMixin {
  late final _land = AnimationController.unbounded(vsync: this);
  late final _sweep = AnimationController(vsync: this, duration: SaDurations.beat);

  @override
  void initState() {
    super.initState();
    _beat();
  }

  @override
  void didUpdateWidget(CountdownNumeral old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _beat();
  }

  void _beat() {
    _land.animateWith(SpringSimulation(SaSprings.pop, 0, 1, 0));
    _sweep.forward(from: 0);
  }

  @override
  void dispose() {
    _land.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final stage = SaPalette.dark;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_land, _sweep]),
        builder: (context, _) {
          // t runs 0 to 1 with the spring's overshoot; reduced motion swaps
          // numerals without scaling and steps the ring in quarters.
          final t = reduce ? 1.0 : _land.value;
          final sweep = reduce ? (_sweep.value * 4).floor() / 4 : _sweep.value;
          final width = (150 - 50 * t).clamp(50.0, 150.0);
          final style = atWidth(SaType.countdown.copyWith(color: stage.stageText, fontSize: widget.size * 0.62), width);
          return CustomPaint(
            painter: _DialPainter(sweep: sweep, color: stage.stageText, fill: stage.stage.withValues(alpha: 0.5)),
            child: Center(
              child: Opacity(
                opacity: (t * 1.6).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 1.35 - 0.35 * t,
                  child: Text('${widget.value}', style: style),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.sweep, required this.color, required this.fill});

  final double sweep;
  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawCircle(rect.center, size.width / 2, Paint()..color = fill);
    final ring = rect.deflate(3);
    canvas.drawArc(
      ring,
      -math.pi / 2,
      2 * math.pi * sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.sweep != sweep || old.color != color || old.fill != fill;
}

/// The record button: a `stage-rec` disc in a ring that morphs to a
/// rounded square while recording, and turns into a spinner while saving.
class RecordButton extends StatefulWidget {
  const RecordButton({super.key, required this.recording, required this.saving, required this.enabled, required this.onPressed});

  final bool recording;
  final bool saving;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton> {
  bool _pressed = false;

  // The overshooting morph of the design (a spring written as a curve).
  static const _morph = Cubic(0.34, 1.56, 0.64, 1);

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    final recording = widget.recording || widget.saving;
    final disc = recording ? 26.0 : 56.0;
    return Semantics(
      button: true,
      label: widget.recording ? 'Stop recording' : 'Record',
      child: Tooltip(
        message: widget.recording ? 'Stop (Space)' : 'Record (Space)',
        child: GestureDetector(
          onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: widget.enabled
              ? (_) {
                  setState(() => _pressed = false);
                  widget.onPressed();
                }
              : null,
          child: AnimatedScale(
            scale: _pressed ? 0.9 : 1,
            duration: SaDurations.instant,
            curve: SaEasing.press,
            child: SizedBox.square(
              dimension: 72,
              child: Stack(alignment: Alignment.center, children: [
                if (widget.saving)
                  SizedBox.square(
                    dimension: 72,
                    child: CircularProgressIndicator(strokeWidth: 4, color: stage.stageRec),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: stage.stageText.withValues(alpha: widget.enabled ? 1 : 0.38), width: 4),
                    ),
                  ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: _morph,
                  width: disc,
                  height: disc,
                  decoration: BoxDecoration(
                    color: stage.stageRec.withValues(alpha: widget.enabled ? (widget.saving ? 0.4 : 1) : 0.38),
                    borderRadius: BorderRadius.circular(recording ? SaRadius.sm : disc / 2),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The glass timecode pill: the tally and the running time in the signal
/// face. The tally is steady while recording and never blinks.
class TimecodePill extends StatelessWidget {
  const TimecodePill({super.key, required this.elapsed, required this.recording});

  final Duration elapsed;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    return GlassSurface(
      borderRadius: SaRadius.full,
      padding: const EdgeInsets.symmetric(horizontal: SaSpace.s3, vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: recording ? stage.stageRec : Colors.transparent,
            border: recording ? null : Border.all(color: stage.stageRec, width: 2),
            boxShadow: recording ? [BoxShadow(color: stage.stageRec.withValues(alpha: 0.7), blurRadius: 10)] : null,
          ),
        ),
        const SizedBox(width: SaSpace.s2),
        Text(formatDuration(elapsed), style: SaType.timecode.copyWith(color: stage.stageText)),
      ]),
    );
  }
}

/// Glass: for surfaces floating over live pixels (the camera preview, a
/// recorded screen). Blurs what is behind it, with a hairline edge.
class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.child, this.borderRadius = SaRadius.md, this.padding});

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    final radius = BorderRadius.circular(borderRadius);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: stage.stageGlass,
            borderRadius: radius,
            border: Border.all(color: stage.stageGlassEdge),
          ),
          child: padding == null ? child : Padding(padding: padding!, child: child),
        ),
      ),
    );
  }
}

/// The microphone in use, with a live level meter. Tapping it opens the
/// picker.
class MicChip extends StatelessWidget {
  const MicChip({super.key, required this.monitor, required this.onTap});

  final MicMonitor monitor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        final failed = monitor.level.failed;
        final name = failed ? 'Microphone blocked' : (monitor.input?.name ?? 'Microphone');
        return Semantics(
          button: true,
          label: 'Microphone: $name. Choose another.',
          child: GestureDetector(
            onTap: onTap,
            child: GlassSurface(
              borderRadius: SaRadius.full,
              padding: const EdgeInsets.fromLTRB(SaSpace.s2, 6, SaSpace.s3, 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(failed ? Icons.mic_off_rounded : Icons.mic_rounded,
                    size: 16, color: failed ? stage.stageRec : stage.stageText),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SaType.caption.copyWith(color: stage.stageText, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: SaSpace.s2),
                LevelMeter(level: monitor.level.meter, speaking: monitor.speaking),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Five bars that light with the microphone level. Amber while the speaker
/// is heard, so voice pacing is easy to trust.
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.level, this.speaking = false, this.height = 14});

  /// 0 to 1.
  final double level;
  final bool speaking;
  final double height;

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    final on = speaking ? stage.stageStress : stage.stageText;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < 5; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          margin: const EdgeInsets.only(left: 2),
          width: 3,
          height: height * (0.4 + 0.15 * i),
          decoration: BoxDecoration(
            color: level > i / 5 ? on : stage.stageText.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
    ]);
  }
}

/// Picks the microphone takes record from, with a live meter and help when
/// Windows blocks access.
Future<void> showMicPicker(BuildContext context, MicMonitor monitor, ValueChanged<String?> onChoose) {
  final stage = SaPalette.dark;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: stage.stageChrome,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        final text = SaType.body.copyWith(color: stage.stageText);
        final meta = SaType.caption.copyWith(color: stage.stageChromeText);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(SaSpace.s5, 0, SaSpace.s5, SaSpace.s5),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Microphone', style: SaType.title.copyWith(color: stage.stageText)),
              const SizedBox(height: SaSpace.s1),
              Text('Speak: the bars should move. If they stay flat, choose another microphone.', style: meta),
              const SizedBox(height: SaSpace.s3),
              if (monitor.available.isEmpty) Text('No microphone found.', style: text),
              for (final input in monitor.available)
                InkWell(
                  borderRadius: BorderRadius.circular(SaRadius.md),
                  onTap: () => onChoose(input.isDefault ? null : input.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: SaSpace.s2, horizontal: SaSpace.s1),
                    child: Row(children: [
                      Icon(
                        input == monitor.input ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                        color: input == monitor.input ? stage.stageStress : stage.stageChromeText,
                        size: 20,
                      ),
                      const SizedBox(width: SaSpace.s3),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(input.name, style: text, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (input.isDefault) Text('Windows default', style: meta),
                        ]),
                      ),
                      if (input == monitor.input) LevelMeter(level: monitor.level.meter, speaking: monitor.speaking, height: 18),
                    ]),
                  ),
                ),
              if (monitor.level.failed) ...[
                const SizedBox(height: SaSpace.s3),
                Text(
                  'Windows is blocking the microphone. Open Settings › Privacy & security › Microphone, '
                  'and turn on "Let desktop apps access your microphone".',
                  style: meta.copyWith(color: stage.stageRec),
                ),
              ],
            ]),
          ),
        );
      },
    ),
  );
}
