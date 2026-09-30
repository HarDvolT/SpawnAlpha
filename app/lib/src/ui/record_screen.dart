import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app.dart';
import '../model/script_document.dart';
import '../prompter/prompter_controller.dart';
import '../prompter/prompter_view.dart';
import 'format.dart';
import 'prompter_controls.dart';

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

  bool get _recording => _camera?.value.isRecordingVideo ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _prompter.addListener(_onPrompter);
    _setUpCameras();
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
    _stopwatch
      ..reset()
      ..start();
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(() {}));
    if (_prompter.state == PlaybackState.finished) _prompter.restart();
    if (_prompter.mode == ScrollMode.timed) _prompter.play();
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
    try {
      final file = await camera.stopVideoRecording();
      final take = await _keep(file, _stopwatch.elapsed, services.recordingsDir);
      _script = _script.copyWith(takes: [..._script.takes, take]);
      await services.library.save(_script);
      if (mounted) _showSaved(take);
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

  void _showSaved(Take take) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Take saved'),
        content: Text('${formatDuration(take.duration)} recorded.\n\n${take.path}'),
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
    final camera = _camera;

    return PopScope(
      canPop: !_recording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) showMessage(context, 'Stop the recording first.');
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ListenableBuilder(
          listenable: settings,
          builder: (context, _) => PrompterShortcuts(
            controller: _prompter,
            view: _view,
            onMirror: toggleMirror,
            onFontSize: changeFont,
            onPlayPause: _toggleRecording,
            child: SafeArea(
              child: Column(children: [
                Expanded(
                  child: Stack(fit: StackFit.expand, children: [
                    if (camera != null && camera.value.isInitialized)
                      Center(child: CameraPreview(camera))
                    else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: _error == null
                              ? const CircularProgressIndicator()
                              : Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    // The prompter sits at the top, close to the lens.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: MediaQuery.sizeOf(context).height * 0.45,
                      child: PrompterView(
                        key: _view,
                        controller: _prompter,
                        fontSize: settings.fontSize * 0.8,
                        mirror: settings.mirror,
                        readingLine: 0.35,
                        backgroundOpacity: 0.6,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      left: 4,
                      child: IconButton(
                        tooltip: 'Close',
                        color: Colors.white70,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _recording ? null : () => Navigator.pop(context, _script),
                      ),
                    ),
                    if (_recording)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _RecordingBadge(elapsed: _stopwatch.elapsed),
                      ),
                    if (_countdown != null)
                      Center(
                        child: Text(
                          '$_countdown',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 120,
                            fontWeight: FontWeight.w800,
                            shadows: [Shadow(blurRadius: 24)],
                          ),
                        ),
                      ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      if (_cameras.length > 1)
                        IconButton(
                          tooltip: 'Switch camera',
                          color: Colors.white,
                          icon: const Icon(Icons.cameraswitch_outlined),
                          onPressed: _recording || _countdown != null
                              ? null
                              : () => _openCamera((_cameraIndex + 1) % _cameras.length),
                        ),
                      _RecordButton(
                        recording: _recording || _countdown != null,
                        enabled: camera != null && !_saving,
                        onPressed: _toggleRecording,
                      ),
                      PrompterControls(
                        controller: _prompter,
                        mirror: settings.mirror,
                        onMirror: toggleMirror,
                        onFontSize: changeFont,
                        showPlay: false,
                      ),
                    ],
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

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.recording, required this.enabled, required this.onPressed});

  final bool recording;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: recording ? 'Stop (Space)' : 'Record (Space)',
      child: InkResponse(
        onTap: enabled ? onPressed : null,
        radius: 40,
        child: Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: recording ? 26 : 52,
            height: recording ? 26 : 52,
            decoration: BoxDecoration(
              color: enabled ? Colors.redAccent : Colors.grey,
              borderRadius: BorderRadius.circular(recording ? 6 : 26),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingBadge extends StatelessWidget {
  const _RecordingBadge({required this.elapsed});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.fiber_manual_record, color: Colors.white, size: 14),
        const SizedBox(width: 4),
        Text(formatDuration(elapsed), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
