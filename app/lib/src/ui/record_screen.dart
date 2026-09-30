import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app.dart';
import '../model/script_document.dart';
import '../prompter/prompter_controller.dart';
import '../prompter/prompter_view.dart';
import '../recording/mic_monitor.dart';
import '../recording/mp4.dart';
import '../theme/theme.dart';
import 'format.dart';
import 'prompter_controls.dart';
import 'recording_widgets.dart';

/// Records the camera with the coached prompter over the preview. The
/// prompter starts when the recording starts, after a countdown. Each
/// take is saved under the app's recordings folder and added to the
/// script; the screen returns the updated script when it closes.
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key, required this.script});

  final ScriptDocument script;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> with WidgetsBindingObserver {
  late ScriptDocument _script = widget.script;
  late final _prompter = PrompterController(widget.script);
  final _view = GlobalKey<PrompterViewState>();

  List<CameraDescription> _cameras = [];
  CameraController? _camera;
  int _cameraIndex = 0;
  String? _error;

  int? _countdown;
  Timer? _countdownTimer;
  final _stopwatch = Stopwatch();
  Timer? _clock;
  bool _saving = false;

  /// The chosen microphone: meter, voice pacing and the silent-take check.
  MicMonitor? _mic;

  bool get _recording => _camera?.value.isRecordingVideo ?? false;

  bool get _voiceAvailable => _mic?.supported ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _prompter.addListener(_onPrompter);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mic != null) return;
    _mic = MicMonitor(AppScope.of(context).audio)..addListener(_onMic);
    _setUp();
  }

  /// Chooses the microphone before the camera opens, because the camera
  /// records from the microphone chosen when it is created.
  Future<void> _setUp() async {
    final mic = _mic!;
    try {
      await mic.start(AppScope.of(context).settings.audioInputId);
      // Where the microphone can be heard, the prompter follows the voice.
      if (mic.supported) _prompter.setMode(ScrollMode.voice);
    } on Object catch (e) {
      debugPrint('Microphone monitor unavailable: $e');
    }
    if (mounted) await _setUpCameras();
  }

  void _onMic() => _prompter.speaking = _mic!.speaking;

  Future<void> _chooseMic(String? id) async {
    final mic = _mic;
    if (mic == null) return;
    await AppScope.of(context).settings.update((s) => s.audioInputId = id);
    await mic.choose(id);
    // Reopen the camera so the next take records from this microphone.
    if (!_recording && _countdown == null && _cameras.isNotEmpty && mounted) await _openCamera(_cameraIndex);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _countdownTimer?.cancel();
    _clock?.cancel();
    _prompter.removeListener(_onPrompter);
    _prompter.dispose();
    _camera?.dispose();
    _mic?.removeListener(_onMic);
    _mic?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Mobile systems take the camera away from apps in the background. On
    // Windows "inactive" only means the window lost focus, so keep going.
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      if (_recording) _stop();
      _camera = null;
      camera.dispose();
      setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _openCamera(_cameraIndex);
    }
  }

  // ---- camera -------------------------------------------------------------

  Future<void> _setUpCameras() async {
    try {
      _cameras = await availableCameras();
    } on CameraException catch (e) {
      setState(() => _error = _describe(e));
      return;
    }
    if (_cameras.isEmpty) {
      setState(() => _error = 'No camera found.');
      return;
    }
    // Face the speaker when there is a choice.
    final front = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    await _openCamera(front >= 0 ? front : 0);
  }

  Future<void> _openCamera(int index) async {
    final old = _camera;
    _camera = null;
    await old?.dispose();
    final camera = CameraController(_cameras[index], ResolutionPreset.high, enableAudio: true);
    try {
      await camera.initialize();
      await camera.prepareForVideoRecording();
    } on CameraException catch (e) {
      await camera.dispose();
      if (mounted) setState(() => _error = _describe(e));
      return;
    }
    if (!mounted) {
      await camera.dispose();
      return;
    }
    setState(() {
      _camera = camera;
      _cameraIndex = index;
      _error = null;
    });
  }

  static String _describe(CameraException e) => switch (e.code) {
        'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' || 'CameraAccessRestricted' =>
          'Camera access is off. Allow it for this app in your system settings.',
        'AudioAccessDenied' || 'AudioAccessDeniedWithoutPrompt' || 'AudioAccessRestricted' =>
          'Microphone access is off. Allow it for this app in your system settings.',
        _ => 'The camera could not start: ${e.description ?? e.code}',
      };

  // ---- recording ----------------------------------------------------------

  void _onPrompter() {
    // The last word has scrolled past: wrap up the take.
    if (_prompter.state == PlaybackState.finished && _recording) _stop();
  }

  void _toggleRecording() {
    if (_saving) return;
    if (_countdown != null) {
      _countdownTimer?.cancel();
      setState(() => _countdown = null);
    } else if (_recording) {
      _stop();
    } else {
      _startCountdown();
    }
  }

  void _startCountdown() {
    if (_camera == null) return;
    setState(() => _countdown = 3);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = (_countdown ?? 1) - 1;
      if (next > 0) {
        setState(() => _countdown = next);
        return;
      }
      timer.cancel();
      setState(() => _countdown = null);
      _start();
    });
  }

  Future<void> _start() async {
    final camera = _camera;
    if (camera == null) return;
    try {
      await camera.startVideoRecording();
    } on CameraException catch (e) {
      if (mounted) showMessage(context, _describe(e));
      return;
    }
    _mic?.resetLoudest();
    _stopwatch
      ..reset()
      ..start();
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(() {}));
    if (_prompter.state == PlaybackState.finished) _prompter.restart();
    if (_prompter.mode != ScrollMode.manual) _prompter.play();
    setState(() {});
  }

  Future<void> _stop() async {
    final camera = _camera;
    if (camera == null || !camera.value.isRecordingVideo || _saving) return;
    _saving = true;
    _prompter.pause();
    _clock?.cancel();
    _stopwatch.stop();
    final services = AppScope.of(context);
    final loudest = _mic?.loudestRmsDb;
    try {
      final file = await camera.stopVideoRecording();
      final take = await _keep(file, _stopwatch.elapsed, services.recordingsDir);
      _script = _script.copyWith(takes: [..._script.takes, take]);
      await services.library.save(_script);
      if (mounted) _showSaved(take, await _soundProblem(take, loudest));
    } on Object catch (e) {
      if (mounted) showMessage(context, 'The take could not be saved: $e');
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  /// Moves the recording into the recordings folder with a readable name.
  Future<Take> _keep(XFile file, Duration duration, Directory dir) async {
    await dir.create(recursive: true);
    final now = DateTime.now();
    final stamp = now.toIso8601String().split('.').first.replaceAll(':', '-');
    final slug = _script.displayTitle
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final extension = file.path.contains('.') ? file.path.split('.').last : 'mp4';
    final name = '${slug.isEmpty ? 'take' : slug.substring(0, slug.length.clamp(0, 40))}-$stamp.$extension';
    final target = '${dir.path}${Platform.pathSeparator}$name';
    try {
      await File(file.path).rename(target);
    } on FileSystemException {
      // Across drives a rename fails; copy instead.
      await file.saveTo(target);
      try {
        await File(file.path).delete();
      } on FileSystemException {
        // The copy is safe; a leftover temp file is harmless.
      }
    }
    return Take(path: target, recordedAt: now, duration: duration);
  }

  /// Why this take may have no usable sound, or null when it sounds fine.
  Future<String?> _soundProblem(Take take, double? loudestRmsDb) async {
    final hasTrack = await mp4HasAudioTrack(File(take.path));
    if (hasTrack == false) {
      return 'This take has no sound track. Check the microphone, then record again.';
    }
    final mic = _mic;
    if (mic != null && mic.supported && loudestRmsDb != null && loudestRmsDb < -55) {
      final name = mic.input?.name ?? 'the microphone';
      return '$name heard almost nothing during this take. If you spoke, choose another microphone '
          'and record again.';
    }
    return null;
  }

  void _showSaved(Take take, String? soundProblem) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(soundProblem == null ? 'Take saved' : 'Take saved, but check the sound'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (soundProblem != null) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.mic_off_rounded, color: SaTheme.of(context).danger, size: 20),
              const SizedBox(width: SaSpace.s2),
              Expanded(child: Text(soundProblem)),
            ]),
            const SizedBox(height: SaSpace.s3),
          ],
          Text('${formatDuration(take.duration)} recorded.\n\n${take.path}'),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _prompter.restart();
            },
            child: const Text('Record another'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(this.context, _script);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    void changeFont(int delta) => settings.update((s) => s.fontSize = (s.fontSize + delta).clamp(24, 96));
    void toggleMirror() => settings.update((s) => s.mirror = !s.mirror);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    void setKinetic(bool v) => settings.update((s) => s.kinetic = v);
    final camera = _camera;
    final stage = SaPalette.dark;
    final size = MediaQuery.sizeOf(context);

    return PopScope(
      canPop: !_recording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) showMessage(context, 'Stop the recording first.');
      },
      child: Scaffold(
        backgroundColor: stage.stage,
        body: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => PrompterShortcuts(
            controller: _prompter,
            view: _view,
            onMirror: toggleMirror,
            onFontSize: changeFont,
            onPlayPause: _toggleRecording,
            onKinetic: reduceMotion ? null : () => setKinetic(!settings.kinetic),
            voiceAvailable: _voiceAvailable,
            child: SafeArea(
              child: Column(children: [
                Expanded(
                  child: Stack(fit: StackFit.expand, children: [
                    if (camera != null && camera.value.isInitialized)
                      Center(child: CameraPreview(camera))
                    else
                      // Below the prompter panel, so it stays readable.
                      Align(
                        alignment: const Alignment(0, 0.5),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: _error == null
                              ? const CircularProgressIndicator()
                              : Text(_error!, textAlign: TextAlign.center, style: SaType.body.copyWith(color: stage.stageText)),
                        ),
                      ),
                    // The prompter: a glass panel right under the lens, top centre.
                    // On wide screens it keeps to a narrow column, so the eyes
                    // don't sweep across the screen.
                    Positioned(
                      top: SaSpace.s2,
                      left: 0,
                      right: 0,
                      height: size.height * 0.42,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: SaSpace.s2),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(SaRadius.lg),
                              child: PrompterView(
                                key: _view,
                                controller: _prompter,
                                fontSize: settings.fontSize * 0.8,
                                mirror: settings.mirror,
                                readingLine: 0.3,
                                glass: true,
                                kinetic: settings.kinetic && !reduceMotion,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: SaSpace.s2,
                      left: SaSpace.s2,
                      child: IconButton(
                        tooltip: 'Close',
                        color: stage.stageChromeText,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _recording ? null : () => Navigator.pop(context, _script),
                      ),
                    ),
                    // The timecode sits under the prompter, on glass.
                    Positioned(
                      top: size.height * 0.42 + SaSpace.s4,
                      left: 0,
                      right: 0,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        TimecodePill(elapsed: _recording ? _stopwatch.elapsed : Duration.zero, recording: _recording),
                        if (_voiceAvailable) ...[
                          const SizedBox(width: SaSpace.s2),
                          MicChip(
                            monitor: _mic!,
                            onTap: _recording ? () {} : () => showMicPicker(context, _mic!, _chooseMic),
                          ),
                        ],
                      ]),
                    ),
                    if (_countdown != null) Center(child: CountdownNumeral(value: _countdown!)),
                  ]),
                ),
                ColoredBox(
                  color: stage.stageChrome,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(SaSpace.s2, SaSpace.s2, SaSpace.s2, SaSpace.s3),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      PrompterControls(
                        controller: _prompter,
                        mirror: settings.mirror,
                        onMirror: toggleMirror,
                        onFontSize: changeFont,
                        showPlay: false,
                        kinetic: reduceMotion ? null : settings.kinetic,
                        onKinetic: setKinetic,
                        voiceAvailable: _voiceAvailable,
                      ),
                      const SizedBox(height: SaSpace.s2),
                      // Take number, record, camera flip: one thumb's reach.
                      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                            'T${_script.takes.length + 1}',
                            textAlign: TextAlign.center,
                            style: atWidth(SaType.title.copyWith(fontFamily: SaFonts.display, fontWeight: FontWeight.w800), 118)
                                .copyWith(color: stage.stageText),
                            semanticsLabel: 'Take ${_script.takes.length + 1}',
                          ),
                        ),
                        RecordButton(
                          recording: _recording || _countdown != null,
                          saving: _saving,
                          enabled: camera != null && !_saving,
                          onPressed: _toggleRecording,
                        ),
                        SizedBox(
                          width: 56,
                          child: _cameras.length > 1
                              ? IconButton(
                                  tooltip: 'Switch camera',
                                  color: stage.stageText,
                                  icon: const Icon(Icons.cameraswitch_rounded),
                                  onPressed: _recording || _countdown != null
                                      ? null
                                      : () => _openCamera((_cameraIndex + 1) % _cameras.length),
                                )
                              : null,
                        ),
                      ]),
                    ]),
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
