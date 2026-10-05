import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../prompter/prompter_controller.dart';
import '../prompter/prompter_view.dart';
import '../recording/floating_prompter.dart';
import '../theme/theme.dart';

const floatingViewChannel = MethodChannel('spawnalpha/floating_view');

Future<void> runFloatingPrompter() async {
  WidgetsFlutterBinding.ensureInitialized();
  final wire = await floatingViewChannel.invokeMapMethod<String, Object?>(
    'ready',
  );
  final presentation = FloatingPresentation.decode(
    wire!['presentation']! as String,
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: FloatingPrompterScreen(presentation: presentation),
    ),
  );
}

class FloatingPrompterScreen extends StatefulWidget {
  const FloatingPrompterScreen({super.key, required this.presentation});
  final FloatingPresentation presentation;
  @override
  State<FloatingPrompterScreen> createState() => _FloatingPrompterScreenState();
}

class _FloatingPrompterScreenState extends State<FloatingPrompterScreen> {
  late final _controller = PrompterController(
    widget.presentation.script,
    mode: widget.presentation.pace,
  );
  bool _locked = false;
  double _opacity = 1;
  String? _problem;
  bool _changingLock = false;
  bool _recordingActive = false,
      _recordingPaused = false,
      _resumeReading = false;

  @override
  void initState() {
    super.initState();
    floatingViewChannel.setMethodCallHandler((call) async {
      if (call.method == 'hidden' && !_recordingActive) _controller.pause();
      if (call.method == 'recordingState' && call.arguments is Map) {
        final state = call.arguments as Map;
        final active = state['active'] == true,
            paused = state['paused'] == true;
        _controller.speaking = state['speaking'] == true;
        if (active && !_recordingActive) {
          _controller.restart();
          if (_controller.mode != ScrollMode.manual) _controller.play();
        }
        if (active && paused && !_recordingPaused) {
          _resumeReading = _controller.isPlaying;
          _controller.pause();
        } else if (active && !paused && _recordingPaused && _resumeReading) {
          _controller.play();
        }
        if (!active) _controller.pause();
        _recordingActive = active;
        _recordingPaused = paused;
        if (mounted) setState(() {});
      }
      if (call.method == 'command') {
        switch (call.arguments) {
          case 'play':
            if (!_recordingPaused) _controller.togglePlay();
          case 'faster':
            _controller.faster();
          case 'slower':
            _controller.slower();
          case 'previous':
            _controller.previousSentence();
          case 'next':
            _controller.nextSentence();
          case 'lock':
            await _toggleLock();
        }
      }
    });
  }

  Future<void> _toggleLock() async {
    if (_changingLock) return;
    _changingLock = true;
    try {
      final locked = await floatingViewChannel.invokeMethod<bool>(
        'lock',
        !_locked,
      );
      if (mounted) {
        setState(() {
          _locked = locked == true;
          _problem = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _problem = 'A shortcut is in use. Lock stays off.');
      }
    } finally {
      _changingLock = false;
    }
  }

  Future<void> _close() async {
    if (!_recordingActive) _controller.pause();
    await floatingViewChannel.invokeMethod<void>('close');
  }

  @override
  void dispose() {
    floatingViewChannel.setMethodCallHandler(null);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.presentation;
    final stage = SaPalette.dark;
    return Scaffold(
      backgroundColor: stage.stageChrome,
      body: IconButtonTheme(data: IconButtonThemeData(style: IconButton.styleFrom(
        foregroundColor: stage.stageChromeText, disabledForegroundColor: stage.stageLine)), child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onPanStart: (_) =>
                      unawaited(floatingViewChannel.invokeMethod<void>('drag')),
                  child: Padding(
                    padding: const EdgeInsets.all(SaSpace.s3),
                    child: Row(
                      children: [
                        Icon(
                          Icons.visibility_off_rounded,
                          color: stage.stageOk,
                        ),
                        const SizedBox(width: SaSpace.s2),
                        Text(
                          'Hidden from recording',
                          style: SaType.signalLabel.copyWith(
                            color: stage.stageChromeText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Dock under the lens',
                onPressed: () => floatingViewChannel.invokeMethod<void>('dock'),
                icon: const Icon(Icons.vertical_align_top_rounded),
              ),
              IconButton(
                tooltip: 'Lock · Ctrl+Shift+L unlocks',
                onPressed: _toggleLock,
                icon: Icon(
                  _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                ),
              ),
              IconButton(
                tooltip: 'Close prompter',
                onPressed: _close,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          if (_locked)
            Text(
              'Ctrl+Shift+L to unlock',
              style: SaType.caption.copyWith(color: stage.stageOk),
            ),
          if (_problem != null)
            Text(
              _problem!,
              style: SaType.caption.copyWith(color: stage.stageWarn),
            ),
          Expanded(
            child: Directionality(
              textDirection: p.script.language.isRtl
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: PrompterView(
                controller: _controller,
                fontSize: SaType.stageS.fontSize!,
                guide: p.guide,
                motion: p.motion,
                alignment: p.alignment,
                mirror: p.mirror,
                kinetic: p.kinetic && !MediaQuery.disableAnimationsOf(context),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => Row(
              children: [
                IconButton(
                  tooltip: _controller.isPlaying ? 'Pause' : 'Play',
                  onPressed: _recordingPaused ? null : _controller.togglePlay,
                  icon: Icon(
                    _controller.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Restart',
                  onPressed: _recordingPaused ? null : _controller.restart,
                  icon: const Icon(Icons.replay_rounded),
                ),
                IconButton(
                  tooltip: 'Slower',
                  onPressed: _controller.slower,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Text(
                  '${_controller.speed.toStringAsFixed(1)}× · ${_controller.mode == ScrollMode.voice ? 'Voice' : 'Timed'}',
                  style: SaType.timecode.copyWith(color: stage.stageChromeText),
                ),
                IconButton(
                  tooltip: 'Faster',
                  onPressed: _controller.faster,
                  icon: const Icon(Icons.add_rounded),
                ),
                Text(
                  'Opacity',
                  style: SaType.caption.copyWith(color: stage.stageChromeText),
                ),
                Expanded(
                  child: Slider(
                    value: _opacity,
                    min: SaPrompter.floatingMinOpacity,
                    onChanged: (value) {
                      setState(() => _opacity = value);
                      unawaited(
                        floatingViewChannel.invokeMethod<void>(
                          'opacity',
                          value,
                        ),
                      );
                    },
                  ),
                ),
                GestureDetector(
                  onPanStart: (_) => unawaited(
                    floatingViewChannel.invokeMethod<void>('resize'),
                  ),
                  child: Tooltip(
                    message: 'Resize prompter',
                    child: Padding(
                      padding: const EdgeInsets.all(SaSpace.s2),
                      child: Icon(
                        Icons.open_in_full_rounded,
                        color: stage.stageChromeText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      )),
    );
  }
}
