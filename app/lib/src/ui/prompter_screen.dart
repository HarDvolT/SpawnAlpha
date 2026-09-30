import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app.dart';
import '../model/script_document.dart';
import '../prompter/prompter_controller.dart';
import '../prompter/prompter_view.dart';
import '../recording/mic_monitor.dart';
import '../theme/theme.dart';
import 'prompter_controls.dart';
import 'recording_widgets.dart';

/// The prompter on its own, for practice or for use with separate camera
/// gear.
class PrompterScreen extends StatefulWidget {
  const PrompterScreen({super.key, required this.script});

  final ScriptDocument script;

  @override
  State<PrompterScreen> createState() => _PrompterScreenState();
}

class _PrompterScreenState extends State<PrompterScreen> {
  late final _controller = PrompterController(widget.script);
  final _view = GlobalKey<PrompterViewState>();

  /// The microphone, for voice pacing.
  MicMonitor? _mic;

  bool get _voiceAvailable => _mic?.supported ?? false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mic != null) return;
    final services = AppScope.of(context);
    final mic = _mic = MicMonitor(services.audio)..addListener(_onMic);
    mic.start(services.settings.audioInputId).then((_) {
      if (mounted && mic.supported) _controller.setMode(ScrollMode.voice);
      if (mounted) setState(() {});
    }, onError: (Object e) => debugPrint('Microphone monitor unavailable: $e'));
  }

  void _onMic() => _controller.speaking = _mic!.speaking;

  Future<void> _chooseMic(String? id) async {
    await AppScope.of(context).settings.update((s) => s.audioInputId = id);
    await _mic?.choose(id);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _controller.dispose();
    _mic?.removeListener(_onMic);
    _mic?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    void changeFont(int delta) => settings.update((s) => s.fontSize = (s.fontSize + delta).clamp(24, 96));
    void toggleMirror() => settings.update((s) => s.mirror = !s.mirror);
    // Reduced motion forces Still, and hides the switch.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    void setKinetic(bool v) => settings.update((s) => s.kinetic = v);

    return Scaffold(
      backgroundColor: SaPalette.dark.stage,
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => PrompterShortcuts(
          controller: _controller,
          view: _view,
          onMirror: toggleMirror,
          onFontSize: changeFont,
          onKinetic: reduceMotion ? null : () => setKinetic(!settings.kinetic),
          voiceAvailable: _voiceAvailable,
          child: SafeArea(
            child: Column(children: [
              Expanded(
                child: Stack(children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () {
                        if (_controller.mode != ScrollMode.manual) _controller.togglePlay();
                      },
                      child: PrompterView(
                        key: _view,
                        controller: _controller,
                        fontSize: settings.fontSize,
                        mirror: settings.mirror,
                        kinetic: settings.kinetic && !reduceMotion,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: IconButton(
                      tooltip: 'Close',
                      color: SaPalette.dark.stageChromeText,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  if (_voiceAvailable)
                    Positioned(
                      top: SaSpace.s2,
                      right: SaSpace.s2,
                      child: MicChip(monitor: _mic!, onTap: () => showMicPicker(context, _mic!, _chooseMic)),
                    ),
                ]),
              ),
              ColoredBox(
                color: SaPalette.dark.stageChrome,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: SaSpace.s2, horizontal: SaSpace.s2),
                  child: PrompterControls(
                    controller: _controller,
                    mirror: settings.mirror,
                    onMirror: toggleMirror,
                    onFontSize: changeFont,
                    kinetic: reduceMotion ? null : settings.kinetic,
                    onKinetic: setKinetic,
                    voiceAvailable: _voiceAvailable,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
