import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../cut/clean_plan.dart';
import '../model/mark.dart';
import '../model/script_document.dart';
import '../model/video_export.dart';
import '../model/caption_style.dart';
import '../model/cut_plan.dart';
import '../render/export_processor.dart';
import '../review/repeated_sections.dart';
import '../theme/theme.dart';
import '../transcription/captions.dart';
import '../transcription/speech_processor.dart';
import '../transcription/speech_models.dart';
import '../transcription/take_processing.dart';
import 'format.dart';
import 'home_screen.dart';
import 'clean_cut_panel.dart';
import 'take_player.dart';
import 'video_export_panel.dart';
import 'word_review_panel.dart';
import 'retake_review_panel.dart';

class TakeReviewScreen extends StatefulWidget {
  const TakeReviewScreen({
    super.key,
    required this.script,
    required this.take,
    this.processAfterStop = false,
    this.fromRecording = false,
    this.recordingNotice,
  });
  final ScriptDocument script;
  final Take take;
  final bool processAfterStop, fromRecording;
  final String? recordingNotice;
  @override
  State<TakeReviewScreen> createState() => _TakeReviewScreenState();
}

class _TakeReviewScreenState extends State<TakeReviewScreen> {
  SavedTranscript? _spoken;
  bool _loaded = false, _exporting = false;
  String? _exportMessage;
  File? _exportFile;
  CleanPlan? _clean;
  bool _planning = false;
  String? _cutProblem;
  VideoFormat _format = VideoFormat.landscape;
  bool _cameraInExport = true, _reviewReady = false;
  bool _burnedCaptions = true;
  CaptionStyle _captionStyle = CaptionStyle.cue;
  bool _captionStyleChosen = false;
  bool? _captionMotion;
  bool _softAudioJoins = true;
  bool _autoZoom = true;
  List<VideoExport> _videos = [];
  VideoExport? _viewing;
  final _reviewScroll = ScrollController();
  final _playerViewKey = GlobalKey();
  SourceRange? _listenRange;
  int _listenRequest = 0;
  List<RepeatedSection> _sections = const [];
  bool _comparing = false;
  String? _comparisonProblem;
  int _comparisonGeneration = 0;
  void _setSpoken(SavedTranscript? spoken) {
    _spoken = spoken;
    _sections = const [];
    _comparisonProblem = null;
    _comparing = false;
    final generation = ++_comparisonGeneration;
    if (spoken?.alignment == null ||
        spoken?.snapshot == null ||
        spoken!.snapshot!.usesNotes) {
      return;
    }
    _comparing = true;
    compute(repeatedSectionsFromJson, {
      'script': spoken.snapshot!.toJson(),
      'words': spoken.transcript.toJson(),
    }).then(
      (sections) {
        if (!mounted || generation != _comparisonGeneration) return;
        setState(() {
          _sections = sections;
          _comparing = false;
        });
      },
      onError: (Object _) {
        if (!mounted || generation != _comparisonGeneration) return;
        setState(() {
          _comparing = false;
          _comparisonProblem = 'Repeated sections could not be compared. Your words and original are safe.';
        });
      },
    );
  }

  void _hearChange(CutChange change) => _hearRange(change.range);
  void _hearRange(SourceRange range) {
    final start = range.start - SaDurations.reviewContext;
    final end = range.end + SaDurations.reviewContext;
    setState(() {
      _viewing = null;
      _listenRange = SourceRange(
        start: start < Duration.zero ? Duration.zero : start,
        end: end > widget.take.duration ? widget.take.duration : end,
      );
      ++_listenRequest;
    });
    // The player can be outside the list's cache after reviewing many changes.
    if (_reviewScroll.hasClients) _reviewScroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final playerContext = _playerViewKey.currentContext;
      if (mounted && playerContext != null) {
        Scrollable.ensureVisible(playerContext);
      }
    });
  }

  @override
  void dispose() {
    _reviewScroll.dispose();
    super.dispose();
  }

  Take _latestTake(AppServices app) =>
      app.library
          .byId(widget.script.id)
          ?.takes
          .where((t) => t.path == widget.take.path)
          .firstOrNull ??
      widget.take;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final app = AppScope.of(context), processor = app.speech;
    if (widget.processAfterStop) {
      Future<void>(() async {
        if (mounted) await _process(automatic: true);
      });
    }
    final loadingTake = _latestTake(app);
    Future.wait([
      app.cuts.load(loadingTake),
      app.videoExports.load(loadingTake),
    ]).then((values) {
      if (mounted) {
        setState(() {
          final latest = _latestTake(app);
          // A slow disk read must not replace a newly processed or edited cut.
          if (latest.wordsPath == loadingTake.wordsPath &&
              latest.cutPath == loadingTake.cutPath) {
            _clean = values[0] as CleanPlan?;
          }
          if (latest.exportsPath == loadingTake.exportsPath) {
            _videos = values[1]! as List<VideoExport>;
          }
          _reviewReady = true;
        });
      }
    });
    if (processor.result?.sourcePath == widget.take.path) {
      _setSpoken(processor.result);
      return;
    }
    processor.load(loadingTake).then((value) {
      if (mounted && _latestTake(app).wordsPath == loadingTake.wordsPath) {
        setState(() => _setSpoken(value));
      }
    });
  }

  Future<void> _saveVideo() async {
    final app = AppScope.of(context);
    final video = await app.exports.export(
      widget.script,
      _latestTake(app),
      _format,
      clean: _clean,
      camera: _cameraInExport,
      burnedCaptions: _burnedCaptions,
      captionStyle: _captionStyle,
      captionMotion: _captionMotion ?? !MediaQuery.disableAnimationsOf(context),
      softAudioJoins: _softAudioJoins,
      autoZoom: _autoZoom,
    );
    final saved = await app.videoExports.load(_latestTake(app));
    if (mounted) {
      setState(() {
        _videos = saved;
        if (video != null) _viewing = video;
      });
    }
  }

  Future<void> _process({bool automatic = false}) async {
    final app = AppScope.of(context);
    await app.processing.run(
      widget.script,
      _latestTake(app),
      automatic: automatic,
    );
    final take = _latestTake(app);
    final spoken = await app.speech.load(take),
        clean = await app.cuts.load(take);
    if (mounted) {
      setState(() {
        _setSpoken(spoken);
        _clean = clean;
      });
    }
  }

  Future<void> _makeCut({bool reviewFillers = false}) async {
    if (_planning || _spoken == null) return;
    final app = AppScope.of(context);
    setState(() {
      _planning = true;
      _cutProblem = null;
    });
    try {
      final plan = await app.cuts.create(
        widget.script,
        _latestTake(app),
        _spoken!,
        base: reviewFillers ? _clean : null,
      );
      if (mounted) setState(() => _clean = plan);
    } on Object {
      if (mounted) {
        setState(
          () => _cutProblem = 'The cut could not be saved. Your original and words are safe. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Future<void> _correctWord(int index, String text) async {
    final app = AppScope.of(context);
    final corrected = await app.speech.correctWord(
      widget.script.id,
      _latestTake(app),
      index,
      text,
    );
    if (!mounted || corrected == null) return;
    setState(() {
      _setSpoken(corrected);
      _clean = null;
    });
    await _makeCut();
  }

  Future<void> _saveCut(CleanPlan plan) async {
    if (_planning) return;
    final app = AppScope.of(context);
    setState(() {
      _planning = true;
      _cutProblem = null;
    });
    try {
      await app.cuts.save(widget.script.id, _latestTake(app), plan);
      if (mounted) {
        setState(() {
          _clean = plan;
          _exportFile = null;
          _exportMessage = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _cutProblem = 'This change could not be saved. The previous cut and original are safe.',
        );
      }
    } finally {
      if (mounted) setState(() => _planning = false);
    }
  }

  Future<void> _export() async {
    final spoken = _spoken;
    if (spoken == null || _exporting) return;
    final directory = Directory(
      '${AppScope.of(context).recordingsDir.parent.path}${Platform.pathSeparator}exports',
    );
    setState(() => _exporting = true);
    try {
      await directory.create(recursive: true);
      final id = newId(),
          captions = captionsFromSpeech(
            _clean == null
                ? spoken.transcript
                : speechOnCleanCut(spoken.transcript, _clean!),
          );
      final srt = File(
        '${directory.path}${Platform.pathSeparator}$id-captions.srt',
      );
      final vtt = File(
        '${directory.path}${Platform.pathSeparator}$id-captions.vtt',
      );
      await srt.writeAsString(subtitleText(captions), flush: true);
      await vtt.writeAsString(subtitleText(captions, vtt: true), flush: true);
      if (mounted) {
        setState(() {
          _exportMessage = 'SRT and VTT captions saved on this device.';
          _exportFile = srt;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _exportMessage =
              'Captions could not be saved. Check free space, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), p = SaTheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        app.speech,
        app.speechModels,
        app.exports,
        app.processing,
      ]),
      builder: (context, _) {
        final job = app.speech,
            model = app.speechModels,
            busy =
                job.busy ||
                model.busy ||
                _planning ||
                app.exports.busy ||
                app.processing.busy;
        final spoken = _spoken;
        final processingBusy = job.busy || model.busy || app.processing.busy;
        final needsSetup =
            app.processing.source == widget.take.path &&
            app.processing.phase == TakeProcessPhase.needsSetup;
        final words = spoken?.transcript.words ?? const [];
        final alignment = spoken?.alignment;
        final changed = alignment?['words'] is List
            ? (alignment!['words']! as List)
                  .where((w) => w is Map && w['match'] != 'exact')
                  .length
            : 0;
        return PopScope(
          canPop: !busy,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              showMessage(
                context,
                app.exports.busy
                    ? app.exports.phase == ExportPhase.saving
                          ? 'Please wait while your video is saved.'
                          : 'Cancel export first. Your recording is safe.'
                    : _planning
                    ? 'Please wait while your cut is saved.'
                    : 'Cancel processing first. Your recording is safe.',
              );
            }
          },
          child: Scaffold(
            appBar: AppBar(title: const Text('Your take')),
            body: ListView(
              controller: _reviewScroll,
              padding: const EdgeInsets.all(SaSpace.s5),
              children: [
                Directionality(
                  textDirection: widget.script.language.isRtl
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: Text(
                    widget.script.displayTitle,
                    style: SaType.body.copyWith(
                      color: p.ink,
                      fontSize: SaType.titleLg.fontSize,
                      fontWeight: SaType.titleLg.fontWeight,
                    ),
                  ),
                ),
                const SizedBox(height: SaSpace.s2),
                Text(
                  '${formatDuration(widget.take.duration)} · original kept on this device',
                  style: SaType.bodySm.copyWith(color: p.ink2),
                ),
                const SizedBox(height: SaSpace.s4),
                if (widget.recordingNotice != null) ...[
                  Text(
                    widget.recordingNotice!,
                    style: SaType.body.copyWith(color: p.danger),
                  ),
                  const SizedBox(height: SaSpace.s4),
                ],
                if (widget.fromRecording)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.videocam_outlined),
                      label: const Text('Record another'),
                    ),
                  ),
                if (needsSetup) ...[
                  Text(
                    'Set up offline speech to make your cut. First use downloads a 148 MB model from Hugging Face. No recording is uploaded.',
                    style: SaType.bodySm.copyWith(color: p.ink2),
                  ),
                  const SizedBox(height: SaSpace.s3),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: busy ? null : _process,
                      icon: const Icon(Icons.subtitles_outlined),
                      label: const Text('Find spoken words'),
                    ),
                  ),
                  const SizedBox(height: SaSpace.s4),
                ],
                if (processingBusy) ...[
                  const SizedBox(height: SaSpace.s3),
                  LinearProgressIndicator(
                    value: model.phase == SpeechModelPhase.downloading
                        ? model.progress
                        : job.phase == SpeechPhase.running
                        ? job.progress
                        : null,
                  ),
                  const SizedBox(height: SaSpace.s2),
                  Wrap(
                    spacing: SaSpace.s3,
                    runSpacing: SaSpace.s2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        job.phase == SpeechPhase.editing
                            ? 'Saving corrected words…'
                            : app.processing.phase == TakeProcessPhase.cut
                            ? 'Making your cut…'
                            : model.phase == SpeechModelPhase.downloading
                            ? 'Downloading offline speech…'
                            : model.phase == SpeechModelPhase.checking ||
                                  app.processing.phase ==
                                      TakeProcessPhase.checking
                            ? 'Checking offline speech…'
                            : job.phase == SpeechPhase.saving
                            ? 'Saving spoken words…'
                            : 'Finding spoken words…',
                        style: SaType.signalLabel.copyWith(color: p.ink2),
                      ),
                      if (job.phase != SpeechPhase.editing)
                        OutlinedButton.icon(
                          onPressed: app.processing.busy
                              ? app.processing.cancel
                              : job.cancel,
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Cancel processing'),
                        ),
                    ],
                  ),
                  const SizedBox(height: SaSpace.s4),
                ],
                if (_viewing != null)
                  TextButton.icon(
                    onPressed: () => setState(() => _viewing = null),
                    icon: const Icon(Icons.undo_rounded),
                    label: const Text('Watch original take'),
                  ),
                TakePlayer(
                  key: _playerViewKey,
                  backend: app.playback,
                  excerpt: _listenRange,
                  playRequest: _listenRequest,
                  path: _viewing == null
                      ? widget.take.path
                      : app.videoExports.file(_viewing!).path,
                  label: _viewing == null
                      ? 'Original take'
                      : 'Saved video · ${_viewing!.format.label}',
                ),
                const SizedBox(height: SaSpace.s4),
                Wrap(
                  spacing: SaSpace.s3,
                  runSpacing: SaSpace.s2,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => showTakeFile(context, widget.take),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Show original file'),
                    ),
                    if (!needsSetup)
                      FilledButton.icon(
                        onPressed: busy || !app.speechBackend.supported
                            ? null
                            : _process,
                        icon: const Icon(Icons.subtitles_outlined),
                        label: Text(
                          spoken == null
                              ? 'Find spoken words'
                              : 'Try speech again',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: SaSpace.s3),
                Text(
                  'Speech runs offline. Your voice and notes stay here. Word times are estimates; check captions before sharing.',
                  style: SaType.bodySm.copyWith(color: p.ink2),
                ),
                if (!app.speechBackend.supported)
                  Text(
                    'Offline speech is available on Windows first.',
                    style: SaType.bodySm.copyWith(color: p.ink2),
                  ),
                Text(
                  'Speech processing supports takes up to 24 hours. Your original is always kept.',
                  style: SaType.bodySm.copyWith(color: p.ink2),
                ),
                if (!model.ready && !needsSetup) ...[
                  const SizedBox(height: SaSpace.s3),
                  Text(
                    'First use downloads a 148 MB speech model from Hugging Face. No recording is uploaded.',
                    style: SaType.bodySm.copyWith(color: p.ink2),
                  ),
                ],
                if (job.problem != null)
                  Text(
                    job.problem!,
                    style: SaType.bodySm.copyWith(color: p.danger),
                  ),
                if (model.problem != null)
                  Text(
                    model.problem!,
                    style: SaType.bodySm.copyWith(color: p.danger),
                  ),
                if (app.processing.source == widget.take.path &&
                    app.processing.problem != null)
                  Text(
                    app.processing.problem!,
                    style: SaType.bodySm.copyWith(color: p.danger),
                  ),
                if (job.phase == SpeechPhase.cancelled)
                  Text(
                    'Processing cancelled. Your original is safe.',
                    style: SaType.bodySm.copyWith(color: p.ink2),
                  ),
                const SizedBox(height: SaSpace.s5),
                VideoExportPanel(
                  format: _format,
                  onFormat: (value) => setState(() {
                    _format = value;
                    if (!_captionStyleChosen) {
                      _captionStyle = value == VideoFormat.portrait
                          ? CaptionStyle.punch
                          : CaptionStyle.cue;
                    }
                  }),
                  onExport: _saveVideo,
                  job: app.exports,
                  busy: busy || !_reviewReady || _exporting,
                  supported: app.renderer.supported,
                  hasCamera: widget.take.cameraPath != null,
                  includeCamera: _cameraInExport,
                  onCamera: (value) => setState(() => _cameraInExport = value),
                  hasCaptions: words.isNotEmpty,
                  hasScreenActivity:
                      widget.take.mode != TakeMode.camera &&
                      widget.take.activityPath != null,
                  autoZoom: _autoZoom,
                  onAutoZoom: (value) => setState(() => _autoZoom = value),
                  hasAudioJoins: _clean?.asCutPlan().hasJoins ?? false,
                  softAudioJoins: _softAudioJoins,
                  onSoftAudioJoins: (value) =>
                      setState(() => _softAudioJoins = value),
                  burnedCaptions: _burnedCaptions,
                  captionStyle: _captionStyle,
                  captionMotion:
                      _captionMotion ??
                      !MediaQuery.disableAnimationsOf(context),
                  onCaptionMotion: (value) =>
                      setState(() => _captionMotion = value),
                  onCaptionStyle: (value) => setState(() {
                    _captionStyle = value;
                    _captionStyleChosen = true;
                  }),
                  onBurnedCaptions: (value) =>
                      setState(() => _burnedCaptions = value),
                  videos: _videos,
                  onView: (video) => setState(() => _viewing = video),
                  onShow: (video) {
                    if (Platform.isWindows) {
                      Process.run('explorer', [
                        '/select,',
                        app.videoExports.file(video).path,
                      ]);
                    }
                  },
                ),
                if (spoken != null) ...[
                  const SizedBox(height: SaSpace.s5),
                  if (_clean != null)
                    CleanCutPanel(
                      plan: _clean!,
                      busy: busy,
                      onChanged: (id, value) =>
                          _saveCut(_clean!.withEnabled(id, value)),
                      onRestore: () => _saveCut(_clean!.restoreAll()),
                      onListen: app.playback.supported ? _hearChange : null,
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: busy ? null : _makeCut,
                      icon: const Icon(Icons.auto_fix_high_outlined),
                      label: const Text('Make a cut'),
                    ),
                  if (_clean != null && !_clean!.fillersReviewed)
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => _makeCut(reviewFillers: true),
                      icon: const Icon(Icons.manage_search_rounded),
                      label: const Text('Review fillers'),
                    ),
                  if (_clean != null &&
                      !_clean!.retakesReviewed &&
                      _sections.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => _makeCut(reviewFillers: true),
                      icon: const Icon(Icons.compare_rounded),
                      label: const Text('Review retakes'),
                    ),
                  if (_planning) const LinearProgressIndicator(),
                  if (_cutProblem != null)
                    Text(
                      _cutProblem!,
                      style: SaType.bodySm.copyWith(color: p.danger),
                    ),
                  const SizedBox(height: SaSpace.s5),
                  if (_comparing)
                    Text(
                      'Comparing repeated sections…',
                      style: SaType.bodySm.copyWith(color: p.ink2),
                    ),
                  if (_comparisonProblem != null)
                    Text(
                      _comparisonProblem!,
                      style: SaType.bodySm.copyWith(color: p.ink2),
                    ),
                  if (_sections.isNotEmpty) ...[
                    RetakeReviewPanel(
                      sections: _sections,
                      busy: busy,
                      onListen: app.playback.supported ? _hearRange : null,
                      plan: _clean,
                      onSelect: (id, index) =>
                          _saveCut(_clean!.withAttempt(id, index)),
                    ),
                    const SizedBox(height: SaSpace.s5),
                  ],
                  Text(
                    'Spoken words',
                    style: SaType.title.copyWith(color: p.ink),
                  ),
                  const SizedBox(height: SaSpace.s2),
                  Text(
                    '${words.length} words${spoken.snapshot?.usesNotes == true ? ' · free speech from Notes' : ''}',
                    style: SaType.signalLabel.copyWith(color: p.ink2),
                  ),
                  if (spoken.notice != null)
                    Text(
                      spoken.notice!,
                      style: SaType.bodySm.copyWith(color: p.ink2),
                    ),
                  if (changed > 0)
                    Text(
                      '$changed spoken words differ from the script. Captions keep what you said.',
                      style: SaType.bodySm.copyWith(color: p.ink2),
                    ),
                  if (alignment?['missedTokens'] is List &&
                      (alignment!['missedTokens']! as List).isNotEmpty)
                    Text(
                      '${(alignment['missedTokens']! as List).length} script words were not found. No words were invented.',
                      style: SaType.bodySm.copyWith(color: p.ink2),
                    ),
                  const SizedBox(height: SaSpace.s4),
                  Directionality(
                    textDirection: spoken.transcript.language.isRtl
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: SelectableText(
                      words.map((w) => w.text).join(' '),
                      style: SaType.body.copyWith(color: p.ink),
                    ),
                  ),
                  const SizedBox(height: SaSpace.s4),
                  WordReviewPanel(
                    transcript: spoken.transcript,
                    busy: busy,
                    onCorrect: _correctWord,
                  ),
                  const SizedBox(height: SaSpace.s4),
                  Wrap(
                    spacing: SaSpace.s3,
                    runSpacing: SaSpace.s2,
                    children: [
                      OutlinedButton.icon(
                        onPressed: words.isEmpty
                            ? null
                            : () => Clipboard.setData(
                                ClipboardData(
                                  text: words.map((w) => w.text).join(' '),
                                ),
                              ),
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Copy transcript'),
                      ),
                      FilledButton.icon(
                        onPressed: words.isEmpty || _exporting || busy
                            ? null
                            : _export,
                        icon: const Icon(Icons.download_outlined),
                        label: Text(
                          _clean == null
                              ? 'Save SRT + VTT captions'
                              : 'Save cut captions (SRT + VTT)',
                        ),
                      ),
                    ],
                  ),
                  if (_exportMessage != null)
                    Text(
                      _exportMessage!,
                      style: SaType.bodySm.copyWith(color: p.ink2),
                    ),
                  if (_exportFile != null && Platform.isWindows)
                    TextButton(
                      onPressed: () => Process.run('explorer', [
                        '/select,',
                        _exportFile!.path,
                      ]),
                      child: const Text('Show caption files'),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
