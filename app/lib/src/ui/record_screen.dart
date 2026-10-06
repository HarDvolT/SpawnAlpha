import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app.dart';
import '../model/script_document.dart';
import '../model/note_deck.dart';
import '../prompter/guide.dart';
import '../prompter/prompter_controller.dart';
import '../prompter/prompter_view.dart';
import '../recording/mic_monitor.dart';
import '../recording/mp4.dart';
import '../recording/sound_check.dart';
import '../recording/screen_source.dart';
import '../recording/floating_prompter.dart';
import '../recording/screen_preview_controller.dart';
import '../recording/screen_take_controller.dart';
import '../recording/camera_identity.dart';
import '../theme/theme.dart';
import 'format.dart';
import 'prompter_controls.dart';
import 'record_setup.dart';
import 'recording_widgets.dart';
import 'screen_source_picker.dart';
import 'screen_preview_screen.dart';
import 'notes_stage.dart';
import 'notes_editor_screen.dart';
import '../storage/camera_take_store.dart';

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
  late NoteController _notes = NoteController(widget.script.notes);
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
  bool _startingCamera = false;
  CameraTakeSnapshot? _cameraSnapshot;

  Future<void> _noteChanged(int index) async {
    if (!_recording || _screenMode) return;
    try {
      await _cameraSnapshot?.select(index, _elapsed);
    } on Object {
      if (mounted) showMessage(context, 'The video keeps recording. Card timing could not be saved.');
    }
  }

  /// The chosen microphone: meter, voice pacing and the silent-take check.
  MicMonitor? _mic;

  SoundCheckState _check = SoundCheckState.idle;

  /// The user chose to record although no microphone works.
  bool _allowSilent = false;
  bool _recordSystemAudio = false;
  bool _recordActivity = false;

  ScreenSource? _screenSource;
  bool _openingScreenPreview = false;
  TakeMode _mode = TakeMode.camera;
  ScreenTakeController? _screenTake;
  ScreenPreviewController? _screenPreview;
  bool _changingMode = false;
  bool get _screenMode => _mode != TakeMode.camera;
  String get _withoutMicrophone =>
      _screenMode && _recordSystemAudio ? 'record without microphone' : 'record without sound';
  bool get _needsCamera => _mode != TakeMode.screen;
  int _cameraGeneration = 0;

  void _onScreenTake() {
    if (mounted) setState(() {});
  }

  Duration get _elapsed =>
      _mode == TakeMode.camera ? _stopwatch.elapsed : _screenTake?.status?.duration ?? Duration.zero;
  bool get _savingTake => _saving || _screenTake?.phase == ScreenTakePhase.saving;
  bool get _canRecord =>
      (_screenTake?.busy ?? false) ||
      (_script.stageReady &&
          switch (_mode) {
            TakeMode.camera => _camera != null,
            TakeMode.screen => _screenSource != null,
            TakeMode.both =>
              _screenSource != null &&
                  _camera != null &&
                  WindowsCameraIdentity.parse(_cameras[_cameraIndex].name).deviceId != null,
          });

  Future<void> _setAid(RecordingAid aid) async {
    if (_busy) return;
    final document = _script.copyWith(recordingAid: aid);
    await AppScope.of(context).library.save(document);
    if (mounted) setState(() => _script = document);
  }

  Future<void> _editNotes() async {
    if (_busy) return;
    final library = AppScope.of(context).library;
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => NotesEditorScreen(script: _script)));
    if (!mounted) return;
    final saved = library.byId(_script.id);
    if (saved != null) {
      setState(() {
        _script = saved;
        _notes = NoteController(saved.notes);
        _prompter.updateScript(saved);
      });
    }
  }

  Future<void> _setMode(TakeMode mode) async {
    if (_busy || mode == _mode) return;
    final services = AppScope.of(context);
    if (mode == TakeMode.both && (!services.recorder.supported || !services.bubbles.supported)) {
      return;
    }
    setState(() {
      _mode = mode;
      _changingMode = true;
    });
    try {
      await AppScope.of(context).settings.update((s) => s.recordMode = mode);
      if (mode == TakeMode.screen) {
        ++_cameraGeneration;
        final camera = _camera;
        _camera = null;
        await camera?.dispose();
        if (_screenSource case final source?) {
          await _screenPreview?.show(source);
        }
      } else {
        await _screenPreview?.stop();
        if (_cameras.isEmpty) {
          await _setUpCameras();
        } else {
          await _openCamera(_cameraIndex);
        }
        if (_screenMode && _screenSource != null) {
          await _screenPreview?.show(_screenSource!);
        }
      }
    } finally {
      if (mounted) setState(() => _changingMode = false);
    }
  }

  Future<void> _chooseScreen() async {
    final sources = AppScope.of(context).screens;
    final selected = await Navigator.of(context).push<ScreenSource>(
      MaterialPageRoute(
        builder: (_) => ScreenSourcePicker(sources: sources, selected: _screenSource),
      ),
    );
    if (mounted && selected != null) {
      setState(() => _screenSource = selected);
      if (_screenMode) await _screenPreview?.show(selected);
    }
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
      if (_screenMode) await _screenPreview?.stop();
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ScreenPreviewScreen(
            source: source,
            previews: previews,
            floating: services.floating,
            presentation: presentation,
          ),
        ),
      );
      if (mounted && _needsCamera && _cameras.isNotEmpty) {
        await _openCamera(_cameraIndex);
      }
      if (mounted && _screenMode) await _screenPreview?.show(source);
    } finally {
      if (mounted) setState(() => _openingScreenPreview = false);
    }
  }

  /// Wider than this, the set-up is a rail beside the preview.
  static const _wideLayout = 1000.0;

  bool get _recording => (_camera?.value.isRecordingVideo ?? false) || (_screenTake?.recording ?? false);

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
    final services = AppScope.of(context);
    _mode = switch (services.settings.recordMode) {
      TakeMode.screen when services.recorder.supported => TakeMode.screen,
      TakeMode.both when services.recorder.supported && services.bubbles.supported => TakeMode.both,
      _ => TakeMode.camera,
    };
    _screenTake = ScreenTakeController(
      recorder: services.recorder,
      huds: services.huds,
      floating: services.floating,
      store: services.screenTakes,
      bubbles: services.bubbles,
      cameraFollow: services.settings.companionCameraFollow,
      rememberCameraFollow: (value) => services.settings.update((s) => s.companionCameraFollow = value),
    )..addListener(_onScreenTake);
    _screenPreview = ScreenPreviewController(services.previews);
    _mic = MicMonitor(services.audio)..addListener(_onMic);
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
    } on Object {
      debugPrint('Microphone monitor unavailable.');
    }
    if (mounted && _needsCamera) await _setUpCameras();
  }

  void _onMic() => _prompter.speaking = _mic!.speaking;

  Future<void> _chooseMic(String? id) async {
    final mic = _mic;
    if (mic == null) return;
    await AppScope.of(context).settings.update((s) => s.audioInputId = id);
    await mic.choose(id);
    if (mounted) setState(() => _check = SoundCheckState.idle);
    // Reopen the camera so the next take records from this microphone.
    _allowSilent = false;
    if (_mode == TakeMode.camera &&
        !_script.usesNotes &&
        !_recording &&
        _countdown == null &&
        _cameras.isNotEmpty &&
        mounted) {
      await _openCamera(_cameraIndex);
    }
  }

  /// Listens while the speaker reads a line, then says what it heard.
  Future<void> _runSoundCheck() async {
    final mic = _mic;
    if (mic == null || !mic.supported || _check == SoundCheckState.listening) {
      return;
    }
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
    _allowSilent = false;
    if (_mode == TakeMode.camera && !_recording && _cameras.isNotEmpty) {
      await _openCamera(_cameraIndex);
    }
  }

  /// Why a take would have no sound, or null. A take is never silently
  /// soundless: the user fixes it, or chooses to record without sound.
  String? get _noSound {
    final mic = _mic;
    if (_allowSilent) return null;
    if (_screenMode && (mic == null || !mic.supported || mic.available.isEmpty)) {
      return 'No microphone found';
    }
    if (mic == null || !mic.supported) return null;
    if (mic.blocked) return 'Windows is blocking the microphone';
    if (_check == SoundCheckState.silent) {
      return 'No sound from ${mic.input?.name ?? 'the microphone'}';
    }
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
    ++_cameraGeneration;
    _mic?.removeListener(_onMic);
    _mic?.dispose();
    _screenTake?.removeListener(_onScreenTake);
    _screenTake?.dispose();
    _screenPreview?.dispose();
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
      if (mounted) setState(() => _error = _describe(e));
      return;
    }
    if (!mounted || !_needsCamera) return;
    if (_cameras.isEmpty) {
      setState(() => _error = 'No camera found.');
      return;
    }
    // Face the speaker when there is a choice.
    final front = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    await _openCamera(front >= 0 ? front : 0);
  }

  Future<void> _openCamera(int index) async {
    final generation = ++_cameraGeneration;
    final old = _camera;
    _camera = null;
    await old?.dispose();
    if (!mounted || !_needsCamera || generation != _cameraGeneration) return;
    final camera = CameraController(_cameras[index], ResolutionPreset.high, enableAudio: _mode == TakeMode.camera);
    try {
      await camera.initialize();
      if (_mode == TakeMode.camera) await camera.prepareForVideoRecording();
    } on CameraException catch (e) {
      await camera.dispose();
      if (mounted && generation == _cameraGeneration) {
        setState(() => _error = _describe(e));
      }
      return;
    }
    if (!mounted || !_needsCamera || generation != _cameraGeneration) {
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
    'CameraAccessDenied' ||
    'CameraAccessDeniedWithoutPrompt' ||
    'CameraAccessRestricted' => 'Camera access is off. Allow it for this app in your system settings.',
    'AudioAccessDenied' ||
    'AudioAccessDeniedWithoutPrompt' ||
    'AudioAccessRestricted' => 'Microphone access is off. Allow it for this app in your system settings.',
    _ => 'The camera could not start: ${e.description ?? e.code}',
  };

  // ---- recording ----------------------------------------------------------

  void _onPrompter() {
    // The last word has scrolled past: wrap up the take.
    if (_mode == TakeMode.camera && _prompter.state == PlaybackState.finished && _recording) {
      _stop();
    }
  }

  void _toggleRecording() {
    if (_savingTake || _changingMode || _startingCamera) return;
    if (!_canRecord && _countdown == null && !_recording) {
      showMessage(context, _script.stageReady ? 'Choose a working recording source first.' : 'Add your script or talking points before recording.');
      return;
    }
    if (_screenMode && (_screenTake?.busy ?? false)) {
      _screenTake!.stop();
      return;
    }
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
          '$problem. Fix it in the set-up, or $_withoutMicrophone.',
          action: SnackBarAction(
            label: _screenMode && _recordSystemAudio ? 'Record without microphone' : 'Record without sound',
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
    if (_screenMode) {
      unawaited(_startScreen());
      return;
    }
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

  Future<void> _startScreen() async {
    final source = _screenSource, owner = _screenTake;
    if (source == null || owner == null || owner.busy || !_canRecord) return;
    final services = AppScope.of(context);
    final cameraChoice = _mode == TakeMode.both ? WindowsCameraIdentity.parse(_cameras[_cameraIndex].name) : null;
    if (cameraChoice != null && cameraChoice.deviceId == null) return;
    final presentation = FloatingPresentation.fromSettings(
      _script,
      services.settings,
      pace: _allowSilent && _prompter.mode == ScrollMode.voice ? ScrollMode.timed : _prompter.mode,
    );
    await owner.start(
      presentation: presentation,
      source: source,
      recordAudio: !_allowSilent,
      recordSystemAudio: _recordSystemAudio,
      recordActivity: _recordActivity,
      microphoneId: _mic?.input?.id,
      microphoneName: _mic?.input?.name ?? 'Microphone',
      cameraId: cameraChoice?.deviceId,
      cameraName: cameraChoice?.name,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      prepare: () async {
        ++_cameraGeneration;
        final camera = _camera;
        _camera = null;
        await camera?.dispose();
        await _screenPreview?.stop();
        await _mic?.stopWatchingAll();
      },
    );
    if (!mounted) return;
    _script = services.library.byId(_script.id) ?? _script;
    final take = owner.take;
    if (take != null) {
      _showSaved(take, owner.problem);
    } else if (owner.problem != null) {
      showMessage(context, owner.problem!);
    }
    if (mounted && !owner.busy) {
      await _mic?.watchEveryMic();
      if (_needsCamera && _cameras.isNotEmpty) await _openCamera(_cameraIndex);
      if (mounted) await _screenPreview?.show(source);
    }
  }

  Future<void> _start() async {
    final camera = _camera;
    if (camera == null || _startingCamera || camera.value.isRecordingVideo) return;
    setState(() => _startingCamera = true);
    final recordingsDir = AppScope.of(context).recordingsDir;
    try {
      // Only the chosen microphone is metered during the take.
      await _mic?.stopWatchingAll();
      _cameraSnapshot = await CameraTakeSnapshot.reserve(recordingsDir, _script);
      await camera.startVideoRecording();
    } on CameraException catch (e) {
      if (mounted) showMessage(context, _describe(e));
      try { await _cameraSnapshot?.cancel(); } on Object { /* Preserve the snapshot. */ }
      await _mic?.watchEveryMic();
      return;
    } on Object {
      if (mounted) showMessage(context, 'The take could not start. Check local storage and try again.');
      await _mic?.watchEveryMic();
      return;
    } finally {
      if (mounted) setState(() => _startingCamera = false);
    }
    _mic?.resetLoudest();
    _stopwatch
      ..reset()
      ..start();
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(() {}));
    _notes.restart();
    if (!_script.usesNotes) {
      if (_prompter.state == PlaybackState.finished) _prompter.restart();
      if (_prompter.mode != ScrollMode.manual) _prompter.play();
    }
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
      await _cameraSnapshot?.finish(take);
      if (mounted) _showSaved(take, await _soundProblem(take, loudest));
    } on Object {
      if (mounted) {
        showMessage(context, 'The take could not be saved. Its data stays on this device.');
      }
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
    return Take(path: target, recordedAt: now, duration: duration, metadataPath: _cameraSnapshot?.file.path);
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
        title: Text(
          soundProblem == null
              ? 'Take saved'
              : take.mode == TakeMode.camera
              ? 'Take saved, but check the sound'
              : 'Take saved, with a warning',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (soundProblem != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    take.mode == TakeMode.camera ? Icons.mic_off_rounded : Icons.warning_amber_rounded,
                    color: SaTheme.of(context).danger,
                    size: 20,
                  ),
                  const SizedBox(width: SaSpace.s2),
                  Expanded(child: Text(soundProblem)),
                ],
              ),
              const SizedBox(height: SaSpace.s3),
            ],
            Text('${formatDuration(take.duration)} recorded.\n\n${take.path}'),
          ],
        ),
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
    final stage = SaPalette.dark;

    return Theme(
      data: Theme.of(context).copyWith(
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: stage.stageText,
            disabledForegroundColor: stage.stageLine,
            side: BorderSide(color: stage.stageGlassEdge),
          ),
        ),
        textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: stage.stageChromeText)),
        iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: stage.stageChromeText)),
      ),
      child: PopScope(
        canPop: !_busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) showMessage(context, 'Stop the recording first.');
        },
        child: Scaffold(
          backgroundColor: stage.stage,
          body: ListenableBuilder(
            listenable: settings,
            builder: (context, _) => _readerShortcuts(
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= _wideLayout) {
                      // Desktop: the preview, and the set-up in a rail beside it.
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _preview(context, constraints.maxHeight, wide: true)),
                          SizedBox(width: 400, child: _rail(context)),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _preview(context, constraints.maxHeight, wide: false)),
                        _bottomBar(context),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _readerShortcuts(Widget child) {
    if (_script.usesNotes) { return CallbackShortcuts(bindings: {
      const SingleActivator(LogicalKeyboardKey.space): _toggleRecording,
    }, child: child); }
    final settings = AppScope.of(context).settings;
    return PrompterShortcuts(
      controller: _prompter,
      view: _view,
      onMirror: () => settings.update((s) => s.mirror = !s.mirror),
      onFontSize: (d) => settings.update((s) => s.fontSize = (s.fontSize + d).clamp(24, 96)),
      onPlayPause: _toggleRecording,
      onKinetic: MediaQuery.disableAnimationsOf(context) ? null : () => settings.update((s) => s.kinetic = !s.kinetic),
      onNextGuide: () => settings.update((s) => s.guide = s.guide.next),
      voiceAvailable: _voiceAvailable,
      child: child,
    );
  }

  bool get _busy =>
      _startingCamera ||
      _recording ||
      _countdown != null ||
      _saving ||
      _openingScreenPreview ||
      _changingMode ||
      (_screenTake?.busy ?? false);

  /// What the camera sees, with the prompter docked under the lens.
  Widget _preview(BuildContext context, double height, {required bool wide}) {
    final settings = AppScope.of(context).settings;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final camera = _camera;
    final stage = SaPalette.dark;
    final panelHeight = height * (wide ? 0.4 : 0.42);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_screenMode)
          _screenPixels()
        else if (camera != null && camera.value.isInitialized)
          Center(child: CameraPreview(camera))
        else
          // Below the prompter panel, so it stays readable.
          Align(
            alignment: const Alignment(0, 0.5),
            child: Padding(
              padding: const EdgeInsets.all(SaSpace.s5),
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: SaType.body.copyWith(color: stage.stageText),
                    ),
            ),
          ),
        if (_mode == TakeMode.both && camera != null && camera.value.isInitialized)
          Positioned(
            bottom: SaSpace.s6,
            left: SaSpace.s6,
            width: SaPrompter.cameraBubbleSize,
            height: SaPrompter.cameraBubbleSize,
            child: ClipOval(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: SaPrompter.cameraBubbleSize * camera.value.aspectRatio,
                  height: SaPrompter.cameraBubbleSize,
                  child: CameraPreview(camera),
                ),
              ),
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
                  child: _script.usesNotes
                      ? NotesStage(controller: _notes, language: _script.language, onChanged: _noteChanged)
                      : PrompterView(
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
            onPressed: _busy ? null : () => Navigator.pop(context, _script),
          ),
        ),
        // The timecode sits under the prompter, on glass.
        Positioned(
          top: panelHeight + SaSpace.s4,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TimecodePill(elapsed: _recording ? _elapsed : Duration.zero, recording: _recording),
              if (_voiceAvailable && !wide) ...[
                const SizedBox(width: SaSpace.s2),
                MicChip(monitor: _mic!, onTap: _recording ? () {} : () => showMicPicker(context, _mic!, _chooseMic)),
              ],
            ],
          ),
        ),
        if (_countdown != null) Center(child: CountdownNumeral(value: _countdown!)),
      ],
    );
  }

  Widget _screenPixels() {
    final preview = _screenPreview!;
    final owner = _screenTake!;
    final stage = SaPalette.dark;
    return ListenableBuilder(
      listenable: preview,
      builder: (context, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(SaSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (owner.busy) ...[
                Text(
                  switch (owner.phase) {
                    ScreenTakePhase.countdown => 'Countdown · ${owner.countdown}',
                    ScreenTakePhase.preparing || ScreenTakePhase.starting => 'Preparing hidden controls…',
                    ScreenTakePhase.paused => 'Paused · picture and sound are held',
                    ScreenTakePhase.saving => 'Saving take…',
                    _ => 'Recording · the floating reader and controls are hidden from the video',
                  },
                  textAlign: TextAlign.center,
                  style: SaType.body.copyWith(color: stage.stageText),
                ),
                const SizedBox(height: SaSpace.s3),
                if (owner.recording)
                  OutlinedButton.icon(
                    onPressed: owner.togglePause,
                    icon: Icon(owner.phase == ScreenTakePhase.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                    label: Text(owner.phase == ScreenTakePhase.paused ? 'Resume' : 'Pause'),
                  ),
              ] else if (_screenSource == null) ...[
                Icon(Icons.screen_share_rounded, color: stage.stageChromeText),
                const SizedBox(height: SaSpace.s3),
                Text(
                  'Choose the display or window to record.',
                  textAlign: TextAlign.center,
                  style: SaType.body.copyWith(color: stage.stageText),
                ),
                const SizedBox(height: SaSpace.s3),
                OutlinedButton.icon(
                  onPressed: _chooseScreen,
                  icon: const Icon(Icons.desktop_windows_rounded),
                  label: const Text('Choose screen'),
                ),
              ] else ...[
                Text(
                  _screenSource!.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SaType.body.copyWith(color: stage.stageText),
                ),
                const SizedBox(height: SaSpace.s2),
                Text(
                  'Live preview · recordings stay on this PC',
                  style: SaType.caption.copyWith(color: stage.stageChromeText),
                ),
                const SizedBox(height: SaSpace.s3),
                if (preview.phase == PreviewPhase.live)
                  Flexible(
                    child: AspectRatio(
                      aspectRatio: preview.aspectRatio,
                      child: Texture(textureId: preview.handle!.textureId),
                    ),
                  )
                else if (preview.phase == PreviewPhase.starting)
                  const CircularProgressIndicator()
                else ...[
                  Text(preview.problem ?? 'Preview stopped.', style: SaType.caption.copyWith(color: stage.stageWarn)),
                  TextButton(onPressed: () => preview.show(_screenSource!), child: const Text('Try again')),
                ],
              ],
            ],
          ),
        ),
      ),
    );
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_screenMode)
              ComputerSoundChoice(
                value: _recordSystemAudio,
                onChanged: _busy ? null : (value) => setState(() => _recordSystemAudio = value),
              ),
            if (_screenMode)
              ActivityChoice(
                value: _recordActivity,
                onChanged: _busy ? null : (value) => setState(() => _recordActivity = value),
              ),
            if (!_script.usesNotes)
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
                alignment: PrompterAlignment.resolve(
                  settings.alignment,
                  rtl: widget.script.language.isRtl,
                  motion: settings.motion,
                ),
                onAlignment: (a) => settings.update((s) => s.alignment = a),
                voiceAvailable: _voiceAvailable,
              ),
            const SizedBox(height: SaSpace.s2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                SizedBox(width: 56, child: _takeNumber()),
                RecordButton(
                  recording: _recording || _countdown != null || (_screenTake?.busy ?? false),
                  saving: _savingTake,
                  enabled: _canRecord && !_savingTake,
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _takeNumber() => Text(
    'T${_script.takes.length + 1}',
    textAlign: TextAlign.center,
    style: atWidth(
      SaType.title.copyWith(fontFamily: SaFonts.display, fontWeight: FontWeight.w800),
      118,
    ).copyWith(color: SaPalette.dark.stageText),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label.toUpperCase(), style: SaType.signalLabel.copyWith(color: stage.stageChromeText)),
          const SizedBox(height: SaSpace.s1),
          child,
        ],
      ),
    );

    final steps = <Widget>[
      SetupStep(
        number: 1,
        title: 'What to record',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<RecordingAid>(
              segments: const [
                ButtonSegment(
                  value: RecordingAid.script,
                  label: Text('Script'),
                  icon: Icon(Icons.description_outlined),
                ),
                ButtonSegment(
                  value: RecordingAid.notes,
                  label: Text('Notes'),
                  icon: Icon(Icons.view_carousel_outlined),
                ),
              ],
              selected: {_script.recordingAid},
              onSelectionChanged: busy ? null : (value) => _setAid(value.single),
            ),
            if (_script.usesNotes) ...[
              const SizedBox(height: SaSpace.s2),
              OutlinedButton.icon(
                onPressed: busy ? null : _editNotes,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit notes'),
              ),
              Text(
                _script.notes.ready
                    ? 'Your notes are private. Advance cards yourself.'
                    : 'Add talking points to each card before recording.',
                style: SaType.caption.copyWith(color: stage.stageChromeText),
              ),
            ],
            const SizedBox(height: SaSpace.s3),
            RecordModeTiles(
              mode: _mode,
              screenReady: AppScope.of(context).recorder.supported,
              bothReady: AppScope.of(context).recorder.supported && AppScope.of(context).bubbles.supported,
              onChanged: busy ? null : _setMode,
            ),
            if (_screenMode && AppScope.of(context).screens.supported) ...[
              const SizedBox(height: SaSpace.s2),
              OutlinedButton.icon(
                onPressed: busy ? null : _chooseScreen,
                icon: const Icon(Icons.desktop_windows_rounded),
                label: const Text('Choose screen'),
              ),
              if (_screenSource != null) ...[
                Text(
                  _screenSource!.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SaType.caption.copyWith(color: stage.stageChromeText),
                ),
                if (AppScope.of(context).previews.supported)
                  OutlinedButton.icon(
                    onPressed: busy ? null : _previewScreen,
                    icon: const Icon(Icons.visibility_rounded),
                    label: const Text('Preview screen'),
                  ),
              ],
            ],
          ],
        ),
      ),
      if (_needsCamera)
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
                        DropdownMenuItem(
                          value: i,
                          child: Text(_cameraName(_cameras[i]), overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: busy ? null : (i) => i == null || i == _cameraIndex ? null : _openCamera(i),
                  ),
                ),
        ),
      if (_mode == TakeMode.both)
        Text(
          'The camera is saved separately. Sound stays with the screen video.',
          style: SaType.caption.copyWith(color: stage.stageChromeText),
        ),
      if (_mode == TakeMode.screen)
        SetupStep(
          number: 2,
          title: 'Screen',
          state: _screenSource == null ? 'CHOOSE' : 'READY',
          ok: _screenSource != null,
          child: Text(
            _screenSource == null
                ? 'Choose a display or window above.'
                : 'The floating reader and controls are hidden from the recording.',
            style: SaType.caption.copyWith(color: stage.stageChromeText),
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
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MicList(monitor: mic, onChoose: _chooseMic, enabled: !busy),
                        SoundCheckRow(
                          state: _check,
                          micName: mic.input?.name ?? 'the microphone',
                          level: mic.level.meter,
                          onCheck: busy ? null : _runSoundCheck,
                        ),
                      ],
                    ),
            );
          },
        ),
      if (_screenMode)
        ComputerSoundChoice(
          value: _recordSystemAudio,
          onChanged: busy ? null : (value) => setState(() => _recordSystemAudio = value),
        ),
      if (_screenMode)
        ActivityChoice(
          value: _recordActivity,
          onChanged: busy ? null : (value) => setState(() => _recordActivity = value),
        ),
      if (!_script.usesNotes)
        SetupStep(
          number: mic != null && mic.supported ? 4 : 3,
          title: 'Prompter',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              row('Guide', GuideChoice(guide: settings.guide, onChanged: (g) => settings.update((s) => s.guide = g))),
              row(
                'Motion',
                MotionChoice(motion: settings.motion, onChanged: (m) => settings.update((s) => s.motion = m)),
              ),
              row(
                'Align',
                AlignmentChoice(
                  alignment: PrompterAlignment.resolve(
                    settings.alignment,
                    rtl: widget.script.language.isRtl,
                    motion: settings.motion,
                  ),
                  onChanged: (a) => settings.update((s) => s.alignment = a),
                ),
              ),
              row('Pace', PaceChoice(controller: _prompter, voiceAvailable: _voiceAvailable, manual: false)),
              if (!reduceMotion)
                row(
                  'Cues',
                  CuesChoice(kinetic: settings.kinetic, onChanged: (v) => settings.update((s) => s.kinetic = v)),
                ),
              row(
                'Size and mirror',
                IconButtonTheme(
                  data: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: stage.stageChromeText)),
                  child: Row(
                    children: [
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
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ];

    final guide = _script.usesNotes ? 'speak freely from your notes' : switch (settings.guide) {
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
      if (_screenTake?.busy == true && _screenMode) {
        line = Text(
          _screenTake!.phase == ScreenTakePhase.saving
              ? 'Saving take…'
              : 'Use the hidden controls. Space or this button stops.',
          style: SaType.caption.copyWith(color: stage.stageChromeText),
        );
      } else if (_recording) {
        line = Text(
          'Recording ${formatDuration(_elapsed)}. Space or the button stops.',
          style: SaType.caption.copyWith(color: stage.stageChromeText),
        );
      } else if (!_script.stageReady) {
        line = Text(_script.usesNotes ? 'Add talking points to each card above.' : 'Write a script before recording.',
          style: SaType.caption.copyWith(color: stage.stageWarn));
      } else if (!_canRecord && _screenMode) {
        line = Text(
          _screenSource == null
              ? 'Choose a display or window above to record.'
              : 'Choose a working camera above to record Both.',
          style: SaType.caption.copyWith(color: stage.stageWarn),
        );
      } else if (problem != null) {
        line = Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('$problem. Fix it above, or ', style: SaType.caption.copyWith(color: stage.stageWarn)),
            InkWell(
              onTap: () => setState(() => _allowSilent = true),
              child: Text(
                _withoutMicrophone,
                style: SaType.caption.copyWith(
                  color: stage.stageText,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: stage.stageText,
                ),
              ),
            ),
          ],
        );
      } else {
        line = Text(
          '${_allowSilent
              ? _screenMode && _recordSystemAudio
                    ? 'Computer sound only · Timed pace. '
                    : 'Without sound · Timed pace. '
              : ''}3, 2, 1, then $guide${!_allowSilent && _prompter.mode == ScrollMode.voice ? ', at the pace of your voice' : ''}.',
          style: SaType.caption.copyWith(color: stage.stageChromeText),
        );
      }
      return Container(
        padding: const EdgeInsets.fromLTRB(SaSpace.s4, SaSpace.s3, SaSpace.s4, SaSpace.s4),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: stage.stageLine)),
        ),
        child: Row(
          children: [
            RecordButton(
              recording: _recording || _countdown != null || (_screenTake?.busy ?? false),
              saving: _savingTake,
              enabled: _canRecord && !_savingTake && (problem == null || _recording),
              onPressed: _toggleRecording,
            ),
            const SizedBox(width: SaSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _recording ? 'Stop' : 'Record',
                        style: SaType.body.copyWith(color: stage.stageText, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: SaSpace.s2),
                      _takeNumber(),
                    ],
                  ),
                  line,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: stage.stageChrome,
        border: BorderDirectional(start: BorderSide(color: stage.stageLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SaSpace.s4, SaSpace.s4, SaSpace.s4, SaSpace.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SET THE STAGE', style: SaType.signalLabel.copyWith(color: stage.stageChromeText)),
                const SizedBox(height: SaSpace.s3),
                Directionality(
                  textDirection: _script.language.isRtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Text(
                    _script.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                    style: SaType.titleLg.copyWith(color: stage.stageText, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: SaSpace.s2),
                Text(
                  '\u2068${_script.language.label}\u2069 · ${_script.contentSummary}${_script.usesNotes ? '' : ' · ~${formatDuration(estimatedDuration(_script))}'}',
                  style: SaType.caption.copyWith(color: stage.stageChromeText),
                ),
              ],
            ),
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
          if (mic == null)
            footer(context)
          else
            ListenableBuilder(listenable: mic, builder: (context, _) => footer(context)),
        ],
      ),
    );
  }

  /// A camera's name without the device path Windows appends to it.
  static String _cameraName(CameraDescription c) {
    return WindowsCameraIdentity.parse(c.name).name;
  }
}
