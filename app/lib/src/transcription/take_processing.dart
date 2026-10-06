import 'package:flutter/foundation.dart';

import '../cut/clean_plan.dart';
import '../model/script_document.dart';
import '../storage/clean_cut_store.dart';
import 'speech_processor.dart';

enum TakeProcessPhase {
  idle,
  checking,
  needsSetup,
  speech,
  cut,
  ready,
  cancelled,
  failed,
}

/// Coordinates the post-stop workflow; widgets only forward actions and render.
/// Automatic first use never downloads a model or overwrites a saved revision.
class TakeProcessing extends ChangeNotifier {
  TakeProcessing(this.speech, this.cuts);
  final SpeechProcessor speech;
  final CleanCutStore cuts;
  TakeProcessPhase phase = TakeProcessPhase.idle;
  String? source, problem;
  CleanPlan? result;
  bool _cancelled = false;
  bool get busy =>
      phase == TakeProcessPhase.checking ||
      phase == TakeProcessPhase.speech ||
      phase == TakeProcessPhase.cut;
  void _phase(TakeProcessPhase value) {
    phase = value;
    notifyListeners();
  }

  Future<CleanPlan?> run(
    ScriptDocument document,
    Take take, {
    bool automatic = false,
  }) async {
    if (busy || speech.busy || !speech.backend.supported) return null;
    _cancelled = false;
    source = take.path;
    problem = null;
    result = null;
    _phase(TakeProcessPhase.checking);
    try {
      if (automatic &&
          take.wordsPath == null &&
          !await speech.models.checkInstalled()) {
        _phase(
          _cancelled ? TakeProcessPhase.cancelled : TakeProcessPhase.needsSetup,
        );
        return null;
      }
      if (_cancelled) {
        _phase(TakeProcessPhase.cancelled);
        return null;
      }
      SavedTranscript? spoken;
      if (automatic && take.wordsPath != null) {
        spoken = await speech.load(take);
        if (spoken == null) {
          throw const FormatException('Saved words unavailable');
        }
      } else {
        _phase(TakeProcessPhase.speech);
        await speech.process(document, take);
        if (_cancelled || speech.phase == SpeechPhase.cancelled) {
          _phase(TakeProcessPhase.cancelled);
          return null;
        }
        if (speech.phase != SpeechPhase.ready ||
            speech.result?.sourcePath != take.path) {
          problem = speech.problem;
          _phase(TakeProcessPhase.failed);
          return null;
        }
        spoken = speech.result;
      }
      if (_cancelled) {
        _phase(TakeProcessPhase.cancelled);
        return null;
      }
      final latest = speech.library
          .byId(document.id)
          ?.takes
          .where((t) => t.path == take.path)
          .firstOrNull;
      if (latest == null) throw const FormatException('Take unavailable');
      _phase(TakeProcessPhase.cut);
      result = automatic && latest.cutPath != null
          ? await cuts.load(latest)
          : null;
      // A missing/stale saved cut is never silently replaced on reopen.
      if (automatic && latest.cutPath != null && result == null) {
        throw const FormatException('Cut unavailable');
      }
      result ??= await cuts.create(document, latest, spoken!);
      _phase(_cancelled ? TakeProcessPhase.cancelled : TakeProcessPhase.ready);
      return result;
    } on Object {
      problem = _cancelled ? null : 'Your cut could not finish. Your original and any saved words are safe. Try again.';
      _phase(_cancelled ? TakeProcessPhase.cancelled : TakeProcessPhase.failed);
      return null;
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    try {
      if (phase == TakeProcessPhase.checking) {
        await speech.models.cancel();
      } else if (phase == TakeProcessPhase.speech) {
        await speech.cancel();
      }
    } on Object {
      /* Retain cancellation; never show private platform errors. */
    }
  }
}
