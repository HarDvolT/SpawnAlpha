import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../recording/recording_hud.dart';
import '../theme/theme.dart';
import 'format.dart';
import 'recording_widgets.dart';

const recordingHudViewChannel = MethodChannel('spawnalpha/recording_hud_view');
Future<void> runRecordingHud() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = HudState.fromJson(
    await recordingHudViewChannel.invokeMapMethod<Object?, Object?>('ready') ??
        const {},
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: RecordingHudScreen(initial: state),
    ),
  );
}

class RecordingHudScreen extends StatefulWidget {
  const RecordingHudScreen({super.key, required this.initial});
  final HudState initial;
  @override
  State<RecordingHudScreen> createState() => _RecordingHudScreenState();
}

class _RecordingHudScreenState extends State<RecordingHudScreen> {
  late HudState _state = widget.initial;
  final _grip = GlobalKey();
  final _pause = GlobalKey(),
      _stop = GlobalKey(),
      _prompter = GlobalKey(),
      _lock = GlobalKey(),
      _companion = GlobalKey(),
      _choice = GlobalKey(),
      _question = GlobalKey();
  bool _reporting = false;

  void _reportHitRegions() {
    if (_reporting) return;
    _reporting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reporting = false;
      if (!mounted) return;
      final regions = <List<double>>[];
      for (final key in [
        _grip,
        _pause,
        _stop,
        _prompter,
        _lock,
        _companion,
        _choice,
        _question,
      ]) {
        final box = key.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize) continue;
        final origin = box.localToGlobal(Offset.zero);
        regions.add([
          origin.dx,
          origin.dy,
          origin.dx + box.size.width,
          origin.dy + box.size.height,
        ]);
      }
      unawaited(
        recordingHudViewChannel
            .invokeMethod<void>('hitRegions', regions)
            .catchError((Object error) {}),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    recordingHudViewChannel.setMethodCallHandler((call) async {
      if (call.method == 'update' && call.arguments is Map && mounted) {
        setState(
          () => _state = HudState.fromJson(
            (call.arguments as Map).cast<Object?, Object?>(),
          ),
        );
      }
    });
  }

  void command(String value) =>
      unawaited(recordingHudViewChannel.invokeMethod<void>('command', value));
  @override
  void dispose() {
    recordingHudViewChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _reportHitRegions();
    final p = SaPalette.dark, s = _state;
    if (s.phase == HudPhase.preparing || s.phase == HudPhase.countdown) {
      return Scaffold(
        backgroundColor: p.stageScrim,
        body: LayoutBuilder(
          builder: (context, constraints) {
            // Native docking can resize one frame before the new state arrives.
            // Keep the old countdown usable at the HUD height during that handoff.
            if (constraints.maxHeight < SaPrompter.countdownWindowSize) {
              return Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.phase == HudPhase.countdown
                          ? '${s.countdown}'
                          : 'Getting ready…',
                      style: SaType.timecode.copyWith(color: p.stageText),
                    ),
                    IconButton(
                      key: _stop,
                      tooltip: 'Cancel',
                      onPressed: () => command('stop'),
                      icon: Icon(Icons.close_rounded, color: p.stageText),
                    ),
                  ],
                ),
              );
            }
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (s.phase == HudPhase.countdown)
                    CountdownNumeral(
                      value: s.countdown,
                      size: SaPrompter.countdownWindowSize / 2,
                    )
                  else
                    Text(
                      'Getting ready…',
                      style: SaType.titleLg.copyWith(color: p.stageText),
                    ),
                  const SizedBox(height: SaSpace.s4),
                  Text(
                    'Hidden from recording',
                    style: SaType.signalLabel.copyWith(color: p.stageOk),
                  ),
                  const SizedBox(height: SaSpace.s3),
                  TextButton(
                    key: _stop,
                    style: TextButton.styleFrom(foregroundColor: p.stageText),
                    onPressed: () => command('stop'),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }
    final busy = s.phase == HudPhase.saving;
    final paused = s.phase == HudPhase.paused;
    final level = ((s.peakDb + 60) / 60).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: p.stageChrome,
      body: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SaSpace.s3,
          vertical: SaSpace.s2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              key: _grip,
              onPanStart: (_) =>
                  unawaited(recordingHudViewChannel.invokeMethod<void>('drag')),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Hidden from recording',
                      style: SaType.signalLabel.copyWith(
                        color: p.stageChromeText,
                      ),
                    ),
                  ),
                  if (s.recordSystemAudio)
                    Tooltip(
                      message: 'Computer sound on',
                      child: Icon(
                        Icons.volume_up_rounded,
                        size: SaSpace.s4,
                        color: p.stageChromeText,
                      ),
                    ),
                  if (s.camera)
                    InkWell(
                      key: _choice,
                      onTap: busy ? null : () => command('companionAsk'),
                      child: Tooltip(
                        message: 'Camera companion choice',
                        child: Icon(
                          Icons.center_focus_strong_rounded,
                          size: SaSpace.s4,
                          color: busy ? p.stageLine : p.stageChromeText,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (s.companionQuestion && !busy)
              LayoutBuilder(
                builder: (context, constraints) =>
                    // The native window can expand one frame after its state.
                    MediaQuery.sizeOf(context).height <
                        SaPrompter.hudQuestionHeight
                    ? const SizedBox.shrink()
                    : Padding(
                        key: _question,
                        padding: const EdgeInsets.symmetric(
                          vertical: SaSpace.s3,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Keep your eyes near the camera',
                              style: SaType.title.copyWith(color: p.stageText),
                            ),
                            Text(
                              'Following the mouse pulls your eyes away from the camera.',
                              style: SaType.bodySm.copyWith(
                                color: p.stageChromeText,
                              ),
                            ),
                            const SizedBox(height: SaSpace.s2),
                            Row(
                              children: [
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: p.stageText,
                                    foregroundColor: p.stageChrome,
                                  ),
                                  onPressed: () => command('companionDocked'),
                                  child: const Text('Keep docked'),
                                ),
                                const SizedBox(width: SaSpace.s2),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: p.stageText,
                                  ),
                                  onPressed: () => command('companionFollow'),
                                  child: const Text('Follow anyway'),
                                ),
                                const Spacer(),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: p.stageChromeText,
                                  ),
                                  onPressed: () => command('companionCancel'),
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
            Row(
              children: [
                Icon(
                  busy
                      ? Icons.hourglass_empty_rounded
                      : paused
                      ? Icons.pause_circle_outline_rounded
                      : Icons.fiber_manual_record_rounded,
                  color: busy || paused ? p.stageChromeText : p.rec,
                ),
                const SizedBox(width: SaSpace.s2),
                Text(
                  busy ? 'Saving…' : formatDuration(s.duration),
                  style: SaType.timecode.copyWith(color: p.stageText),
                ),
                const SizedBox(width: SaSpace.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        s.recordAudio
                            ? s.microphone
                            : s.recordSystemAudio
                            ? 'Computer sound only'
                            : 'Without sound',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SaType.caption.copyWith(
                          color: p.stageChromeText,
                        ),
                      ),
                      LinearProgressIndicator(
                        value: s.recordAudio ? level : 0,
                        minHeight: SaPrompter.micMeterHeight,
                        color: s.peakDb >= -3 ? p.stageWarn : p.stageChromeText,
                        backgroundColor: p.stageLine,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SaSpace.s3),
                IconButton(
                  key: _pause,
                  tooltip: paused ? 'Resume recording' : 'Pause recording',
                  onPressed: busy ? null : () => command('pause'),
                  icon: Icon(
                    paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: busy ? p.stageLine : p.stageChromeText,
                  ),
                ),
                IconButton(
                  key: _stop,
                  tooltip: 'Stop recording',
                  onPressed: busy ? null : () => command('stop'),
                  icon: Icon(
                    Icons.stop_rounded,
                    color: busy ? p.stageLine : p.rec,
                  ),
                ),
                IconButton(
                  key: _prompter,
                  tooltip: s.prompterOpen ? 'Hide prompter' : 'Show prompter',
                  onPressed: busy ? null : () => command('prompter'),
                  icon: Icon(
                    s.prompterOpen
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    color: busy ? p.stageLine : p.stageChromeText,
                  ),
                ),
                IconButton(
                  key: _companion,
                  tooltip: s.companion ? 'Turn Companion off' : 'Companion',
                  onPressed: busy ? null : () => command('companion'),
                  icon: Icon(
                    Icons.near_me_rounded,
                    color: busy
                        ? p.stageLine
                        : s.companion
                        ? p.stageOk
                        : p.stageChromeText,
                  ),
                ),
                IconButton(
                  key: _lock,
                  tooltip: s.companion
                      ? 'Following Companion is click-through'
                      : 'Lock prompter · Ctrl+Shift+L unlocks',
                  onPressed: busy || !s.prompterOpen || s.companion
                      ? null
                      : () => command('lock'),
                  icon: Icon(
                    Icons.lock_open_rounded,
                    color: busy || !s.prompterOpen || s.companion
                        ? p.stageLine
                        : p.stageChromeText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
