import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app.dart';
import '../model/script_document.dart';
import '../prompter/guide.dart';
import '../prompter/prompter_controller.dart';
import '../prompter/prompter_view.dart';
import '../recording/mic_monitor.dart';
import '../recording/mp4.dart';
import '../recording/sound_check.dart';
import '../recording/screen_source.dart';
import '../recording/floating_prompter.dart';
import '../theme/theme.dart';
import 'format.dart';
import 'prompter_controls.dart';
import 'record_setup.dart';
import 'recording_widgets.dart';
import 'screen_source_picker.dart';
import 'screen_preview_screen.dart';

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

  SoundCheckState _check = SoundCheckState.idle;

  /// The user chose to record although no microphone works.
  bool _allowSilent = false;

  ScreenSource? _screenSource;
  bool _openingScreenPreview = false;

  Future<void> _chooseScreen() async {
    final sources = AppScope.of(context).screens;
    final selected = await Navigator.of(context).push<ScreenSource>(MaterialPageRoute(
      builder: (_) => ScreenSourcePicker(sources: sources, selected: _screenSource),
    ));
    if (mounted && selected != null) setState(() => _screenSource = selected);
  }

  Future<void> _previewScreen() async {
    final source = _screenSource;
    if (source == null || _openingScreenPreview) return;
    final services = AppScope.of(context);
    final previews = services.previews;
    final presentation = FloatingPresentation.fromSettings(_script, services.settings);
    // Release the camera while viewing screen pixels, then reopen on return.
    final camera = _camera;
    setState(() {
      _openingScreenPreview = true;
      _camera = null;
    });
    try {
      await camera?.dispose();
      if (!mounted) return;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => ScreenPreviewScreen(source: source, previews: previews,
          floating: services.floating, presentation: presentation),
      ));
      if (mounted && _cameras.isNotEmpty) await _openCamera(_cameraIndex);
    } finally {
      if (mounted) setState(() => _openingScreenPreview = false);
    }
  }

  /// Wider than this, the set-up is a rail beside the preview.
  static const _wideLayout = 1000.0;

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
      // Meter every microphone while setting up, so the right one is easy to spot.
      await mic.watchEveryMic();
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
    if (mounted) setState(() => _check = SoundCheckState.idle);
    // Reopen the camera so the next take records from this microphone.
    if (!_recording && _countdown == null && _cameras.isNotEmpty && mounted) await _openCamera(_cameraIndex);
  }

  /// Listens while the speaker reads a line, then says what it heard.
  Future<void> _runSoundCheck() async {
    final mic = _mic;
    if (mic == null || !mic.supported || _check == SoundCheckState.listening) return;
    setState(() => _check = SoundCheckState.listening);
    mic.resetLoudest();
    await Future<void>.delayed(SoundCheck.listenFor);
    if (!mounted) return;
    setState(() => _check = SoundCheck.judge(mic.loudestRmsDb).state);
  }

  Future<void> _retryMic() async {
    await _mic?.refresh();
    if (!mounted) return;
    setState(() => _check = SoundCheckState.idle);
    // The camera opened while access was off records silence: reopen it.
    if (!_recording && _cameras.isNotEmpty) await _openCamera(_cameraIndex);
  }

  /// Why a take would have no sound, or null. A take is never silently
  /// soundless: the user fixes it, or chooses to record without sound.
  String? get _noSound {
    final mic = _mic;
    if (mic == null || !mic.supported || _allowSilent) return null;
    if (mic.blocked) return 'Windows is blocking the microphone';
    if (_check == SoundCheckState.silent) return 'No sound from ${mic.input?.name ?? 'the microphone'}';
    return null;
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
      final problem = _noSound;
      if (problem != null) {
        showMessage(
          context,
          '$problem. Fix it in the set-up, or record without sound.',
          action: SnackBarAction(
            label: 'Record without sound',
            onPressed: () {
              setState(() => _allowSilent = true);
              _startCountdown();
            },
          ),
        );
        return;
      }
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
    // Only the chosen microphone is metered during the take.
    await _mic?.stopWatchingAll();
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
      if (mounted) {
        setState(() {});
        await _mic?.watchEveryMic();
      }
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
    void setGuide(PrompterGuide g) => settings.update((s) => s.guide = g);
    final stage = SaPalette.dark;

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
            onNextGuide: () => setGuide(settings.guide.next),
            voiceAvailable: _voiceAvailable,
            child: SafeArea(
              child: LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth >= _wideLayout) {
                  // Desktop: the preview, and the set-up in a rail beside it.
                  return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: _preview(context, constraints.maxHeight, wide: true)),
                    SizedBox(width: 400, child: _rail(context)),
                  ]);
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: _preview(context, constraints.maxHeight, wide: false)),
                  _bottomBar(context),
                ]);
              }),
            ),
          ),
        ),
      ),
    );
  }

  bool get _busy => _recording || _countdown != null || _saving || _openingScreenPreview;

  /// What the camera sees, with the prompter docked under the lens.
  Widget _preview(BuildContext context, double height, {required bool wide}) {
    final settings = AppScope.of(context).settings;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final camera = _camera;
    final stage = SaPalette.dark;
    final panelHeight = height * (wide ? 0.4 : 0.42);
    return Stack(fit: StackFit.expand, children: [
      if (camera != null && camera.value.isInitialized)
        Center(child: CameraPreview(camera))
      else
        // Below the prompter panel, so it stays readable.
        Align(
          alignment: const Alignment(0, 0.5),
          child: Padding(
            padding: const EdgeInsets.all(SaSpace.s5),
            child: _error == null
                ? const CircularProgressIndicator()
                : Text(_error!, textAlign: TextAlign.center, style: SaType.body.copyWith(color: stage.stageText)),
          ),
        ),
      // The prompter: a glass panel right under the lens, top centre. On
      // wide screens it keeps to a narrow column, so the eyes don't sweep
      // across the screen.
      Positioned(
        top: SaSpace.s2,
        left: 0,
        right: 0,
        height: panelHeight,
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
                  guide: settings.guide,
                  motion: settings.motion,
                  alignment: settings.alignment,
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
        top: panelHeight + SaSpace.s4,
        left: 0,
        right: 0,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TimecodePill(elapsed: _recording ? _stopwatch.elapsed : Duration.zero, recording: _recording),
          if (_voiceAvailable && !wide) ...[
            const SizedBox(width: SaSpace.s2),
            MicChip(
              monitor: _mic!,
              onTap: _recording ? () {} : () => showMicPicker(context, _mic!, _chooseMic),
            ),
          ],
        ]),
      ),
      if (_countdown != null) Center(child: CountdownNumeral(value: _countdown!)),
    ]);
  }

  /// Phones: the prompter's controls, then the take number, record and
  /// camera flip within one thumb's reach.
  Widget _bottomBar(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final stage = SaPalette.dark;
    return ColoredBox(
      color: stage.stageChrome,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SaSpace.s2, SaSpace.s2, SaSpace.s2, SaSpace.s3),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          PrompterControls(
            controller: _prompter,
            mirror: settings.mirror,
            onMirror: () => settings.update((s) => s.mirror = !s.mirror),
            onFontSize: (d) => settings.update((s) => s.fontSize = (s.fontSize + d).clamp(24, 96)),
            showPlay: false,
            kinetic: reduceMotion ? null : settings.kinetic,
            onKinetic: (v) => settings.update((s) => s.kinetic = v),
            guide: settings.guide,
            onGuide: (g) => settings.update((s) => s.guide = g),
            motion: settings.motion,
            onMotion: (m) => settings.update((s) => s.motion = m),
            alignment: PrompterAlignment.resolve(settings.alignment,
                rtl: widget.script.language.isRtl, motion: settings.motion),
            onAlignment: (a) => settings.update((s) => s.alignment = a),
            voiceAvailable: _voiceAvailable,
          ),
          const SizedBox(height: SaSpace.s2),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            SizedBox(width: 56, child: _takeNumber()),
            RecordButton(
              recording: _recording || _countdown != null,
              saving: _saving,
              enabled: _camera != null && !_saving,
              onPressed: _toggleRecording,
            ),
            SizedBox(
              width: 56,
              child: _cameras.length > 1
                  ? IconButton(
                      tooltip: 'Switch camera',
                      color: stage.stageText,
                      icon: const Icon(Icons.cameraswitch_rounded),
                      onPressed: _busy ? null : () => _openCamera((_cameraIndex + 1) % _cameras.length),
                    )
                  : null,
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _takeNumber() => Text(
        'T${_script.takes.length + 1}',
        textAlign: TextAlign.center,
        style: atWidth(SaType.title.copyWith(fontFamily: SaFonts.display, fontWeight: FontWeight.w800), 118)
            .copyWith(color: SaPalette.dark.stageText),
        semanticsLabel: 'Take ${_script.takes.length + 1}',
      );

  /// Desktop: the set-up rail (docs/design/components/RecordSetup). What to
  /// record, the camera, the microphone with a sound check, and the
  /// prompter; then the record button, which says what will happen or what
  /// is missing.
  Widget _rail(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final stage = SaPalette.dark;
    final mic = _mic;
    final camera = _camera;
    final busy = _busy;
    // A label above its choices, which get the full width of the rail.
    Widget row(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(top: SaSpace.s2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(label.toUpperCase(), style: SaType.signalLabel.copyWith(color: stage.stageChromeText)),
            const SizedBox(height: SaSpace.s1),
            child,
          ]),
        );

    final steps = <Widget>[
      SetupStep(number: 1, title: 'What to record', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const RecordModeTiles(),
        if (AppScope.of(context).screens.supported) ...[
          const SizedBox(height: SaSpace.s2),
          OutlinedButton.icon(onPressed: busy ? null : _chooseScreen,
            icon: const Icon(Icons.desktop_windows_rounded), label: const Text('Choose screen')),
          if (_screenSource != null) ...[
            Text(_screenSource!.name, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: SaType.caption.copyWith(color: stage.stageChromeText)),
            if (AppScope.of(context).previews.supported)
              OutlinedButton.icon(onPressed: busy ? null : _previewScreen,
                icon: const Icon(Icons.visibility_rounded), label: const Text('Preview screen')),
          ],
        ],
      ])),
      SetupStep(
        number: 2,
        title: 'Camera',
        state: camera != null && camera.value.isInitialized ? 'ON' : (_error != null ? 'CHECK' : null),
        ok: camera != null && camera.value.isInitialized ? true : (_error != null ? false : null),
        child: _cameras.isEmpty
            ? Text(_error ?? 'Looking for cameras…', style: SaType.caption.copyWith(color: stage.stageChromeText))
            : DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  dropdownColor: stage.stageChrome,
                  value: _cameraIndex,
                  style: SaType.label.copyWith(color: stage.stageText),
                  iconEnabledColor: stage.stageChromeText,
                  items: [
                    for (var i = 0; i < _cameras.length; i++)
                      DropdownMenuItem(value: i, child: Text(_cameraName(_cameras[i]), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: busy ? null : (i) => i == null || i == _cameraIndex ? null : _openCamera(i),
                ),
              ),
      ),
      if (mic != null && mic.supported)
        ListenableBuilder(
          listenable: mic,
          builder: (context, _) {
            final blocked = mic.blocked;
            final (state, ok) = blocked
                ? ('BLOCKED', false)
                : switch (_check) {
                    SoundCheckState.heard => ('HEARD', true),
                    SoundCheckState.quiet || SoundCheckState.silent => ('CHECK', false),
                    SoundCheckState.listening => ('LISTENING', null),
                    SoundCheckState.idle => ('NOT CHECKED', null),
                  };
            return SetupStep(
              number: 3,
              title: 'Microphone',
              state: state,
              ok: ok,
              child: blocked
                  ? BlockedPanel(onRetry: _retryMic)
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      MicList(monitor: mic, onChoose: _chooseMic, enabled: !busy),
                      SoundCheckRow(
                        state: _check,
                        micName: mic.input?.name ?? 'the microphone',
                        level: mic.level.meter,
                        onCheck: busy ? null : _runSoundCheck,
                      ),
                    ]),
            );
          },
        ),
      SetupStep(
        number: mic != null && mic.supported ? 4 : 3,
        title: 'Prompter',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          row('Guide', GuideChoice(guide: settings.guide, onChanged: (g) => settings.update((s) => s.guide = g))),
          row('Motion', MotionChoice(motion: settings.motion, onChanged: (m) => settings.update((s) => s.motion = m))),
          row('Align', AlignmentChoice(
            alignment: PrompterAlignment.resolve(settings.alignment,
                rtl: widget.script.language.isRtl, motion: settings.motion),
            onChanged: (a) => settings.update((s) => s.alignment = a),
          )),
          row('Pace', PaceChoice(controller: _prompter, voiceAvailable: _voiceAvailable, manual: false)),
          if (!reduceMotion)
            row('Cues', CuesChoice(kinetic: settings.kinetic, onChanged: (v) => settings.update((s) => s.kinetic = v))),
          row(
            'Size and mirror',
            IconButtonTheme(
              data: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: stage.stageChromeText)),
              child: Row(children: [
                IconButton(
                  tooltip: 'Smaller text (−)',
                  icon: const Icon(Icons.text_decrease_rounded),
                  onPressed: () => settings.update((s) => s.fontSize = (s.fontSize - 4).clamp(24, 96)),
                ),
                IconButton(
                  tooltip: 'Larger text (+)',
                  icon: const Icon(Icons.text_increase_rounded),
                  onPressed: () => settings.update((s) => s.fontSize = (s.fontSize + 4).clamp(24, 96)),
                ),
                IconButton(
                  tooltip: 'Mirror (M)',
                  isSelected: settings.mirror,
                  icon: const Icon(Icons.flip_rounded),
                  onPressed: () => settings.update((s) => s.mirror = !s.mirror),
                ),
              ]),
            ),
          ),
        ]),
      ),
    ];

    final guide = switch (settings.guide) {
      PrompterGuide.dot => 'the dot leads you',
      PrompterGuide.underline => 'the underline leads you',
      PrompterGuide.spotlight => 'the spotlight leads you',
      PrompterGuide.off => 'the prompter follows you',
    };

    // The go button, with one line that says what will happen or what is
    // missing. It follows the microphone: blocked or silent stops the take.
    Widget footer(BuildContext context) {
      final problem = _noSound;
      final Widget line;
      if (_recording) {
        line = Text('Recording ${formatDuration(_stopwatch.elapsed)}. Space or the button stops.',
            style: SaType.caption.copyWith(color: stage.stageChromeText));
      } else if (problem != null) {
        line = Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('$problem. Fix it above, or ', style: SaType.caption.copyWith(color: stage.stageWarn)),
          InkWell(
            onTap: () => setState(() => _allowSilent = true),
            child: Text(
              'record without sound',
              style: SaType.caption.copyWith(
                color: stage.stageText,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: stage.stageText,
              ),
            ),
          ),
        ]);
      } else {
        line = Text(
          '3, 2, 1, then $guide${_prompter.mode == ScrollMode.voice ? ', at the pace of your voice' : ''}.',
          style: SaType.caption.copyWith(color: stage.stageChromeText),
        );
      }
      return Container(
        padding: const EdgeInsets.fromLTRB(SaSpace.s4, SaSpace.s3, SaSpace.s4, SaSpace.s4),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: stage.stageLine))),
        child: Row(children: [
          RecordButton(
            recording: _recording || _countdown != null,
            saving: _saving,
            enabled: camera != null && !_saving && (problem == null || _recording),
            onPressed: _toggleRecording,
          ),
          const SizedBox(width: SaSpace.s3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(
                  _recording ? 'Stop' : 'Record',
                  style: SaType.body.copyWith(color: stage.stageText, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: SaSpace.s2),
                _takeNumber(),
              ]),
              line,
            ]),
          ),
        ]),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: stage.stageChrome,
        border: BorderDirectional(start: BorderSide(color: stage.stageLine)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(SaSpace.s4, SaSpace.s4, SaSpace.s4, SaSpace.s2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SET THE STAGE', style: SaType.signalLabel.copyWith(color: stage.stageChromeText)),
            const SizedBox(height: SaSpace.s1),
            Text(
              _script.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SaType.titleLg.copyWith(color: stage.stageText, fontWeight: FontWeight.w800),
            ),
            Text(
              '\u2068${_script.language.label}\u2069 · ${_script.wordCount} words · ~${formatDuration(estimatedDuration(_script))}',
              style: SaType.meter.copyWith(color: stage.stageChromeText),
            ),
          ]),
        ),
        Expanded(
          // While recording, the set-up steps back.
          child: AnimatedOpacity(
            opacity: busy ? 0.35 : 1,
            duration: SaDurations.base,
            child: IgnorePointer(
              ignoring: busy,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: SaSpace.s3),
                itemCount: steps.length,
                separatorBuilder: (_, _) => const SizedBox(height: SaSpace.s2),
                itemBuilder: (_, i) => steps[i],
              ),
            ),
          ),
        ),
        if (mic == null) footer(context) else ListenableBuilder(listenable: mic, builder: (context, _) => footer(context)),
      ]),
    );
  }

  /// A camera's name without the device path Windows appends to it.
  static String _cameraName(CameraDescription c) {
    final name = c.name.split(' <').first.trim();
    return name.isEmpty ? 'Camera' : name;
  }
}
