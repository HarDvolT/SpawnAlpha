import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../cut/clean_plan.dart';
import '../model/mark.dart';
import '../model/script_document.dart';
import '../theme/theme.dart';
import '../transcription/captions.dart';
import '../transcription/speech_processor.dart';
import '../transcription/speech_models.dart';
import 'format.dart';
import 'home_screen.dart';
import 'clean_cut_panel.dart';

class TakeReviewScreen extends StatefulWidget {
  const TakeReviewScreen({super.key, required this.script, required this.take});
  final ScriptDocument script;
  final Take take;
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
    app.cuts.load(_latestTake(app)).then((value) {
      if (mounted) setState(() => _clean = value);
    });
    if (processor.result?.sourcePath == widget.take.path) {
      _spoken = processor.result;
      return;
    }
    processor.load(widget.take).then((value) {
      if (mounted) setState(() => _spoken = value);
    });
  }

  Future<void> _process() async {
    final app = AppScope.of(context);
    await app.speech.process(widget.script, widget.take);
    if (mounted && app.speech.result?.sourcePath == widget.take.path) {
      setState(() {
        _spoken = app.speech.result;
        _clean = null;
      });
      await _makeCut();
    }
  }

  Future<void> _makeCut() async {
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
                : speechOnCut(spoken.transcript, _clean!.asCutPlan()),
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
      listenable: Listenable.merge([app.speech, app.speechModels]),
      builder: (context, _) {
        final job = app.speech,
            model = app.speechModels,
            busy = job.busy || model.busy || _planning;
        final spoken = _spoken;
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
                'Cancel processing first. Your recording is safe.',
              );
            }
          },
          child: Scaffold(
            appBar: AppBar(title: const Text('Your take')),
            body: ListView(
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
                Wrap(
                  spacing: SaSpace.s3,
                  runSpacing: SaSpace.s2,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => showTakeFile(context, widget.take),
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Show original file'),
                    ),
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
                    if (busy)
                      OutlinedButton.icon(
                        onPressed: job.cancel,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Cancel processing'),
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
                if (!model.ready) ...[
                  const SizedBox(height: SaSpace.s3),
                  Text(
                    'First use downloads a 148 MB speech model from Hugging Face. No recording is uploaded.',
                    style: SaType.bodySm.copyWith(color: p.ink2),
                  ),
                ],
                if (busy) ...[
                  const SizedBox(height: SaSpace.s4),
                  LinearProgressIndicator(
                    value: model.phase == SpeechModelPhase.downloading
                        ? model.progress
                        : job.phase == SpeechPhase.running
                        ? job.progress
                        : null,
                  ),
                  const SizedBox(height: SaSpace.s2),
                  Text(
                    model.phase == SpeechModelPhase.downloading
                        ? 'Downloading offline speech…'
                        : model.phase == SpeechModelPhase.checking
                        ? 'Checking the model…'
                        : job.phase == SpeechPhase.saving
                        ? 'Saving spoken words…'
                        : 'Finding spoken words…',
                    style: SaType.signalLabel.copyWith(color: p.ink2),
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
                if (job.phase == SpeechPhase.cancelled)
                  Text(
                    'Processing cancelled. Your original is safe.',
                    style: SaType.bodySm.copyWith(color: p.ink2),
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
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: busy ? null : _makeCut,
                      icon: const Icon(Icons.auto_fix_high_outlined),
                      label: const Text('Make a cut'),
                    ),
                  if (_planning) const LinearProgressIndicator(),
                  if (_cutProblem != null)
                    Text(
                      _cutProblem!,
                      style: SaType.bodySm.copyWith(color: p.danger),
                    ),
                  const SizedBox(height: SaSpace.s5),
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
