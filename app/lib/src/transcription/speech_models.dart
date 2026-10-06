import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'speech_backend.dart';

enum SpeechModelPhase { missing, checking, downloading, ready, failed }

/// Only the public model is downloaded. Scripts and audio never enter a request.
class SpeechModels extends ChangeNotifier {
  SpeechModels(this.directory, this.backend, {http.Client Function()? client})
    : _client = client ?? http.Client.new;
  final Directory directory;
  final SpeechBackend backend;
  final http.Client Function() _client;
  static const expectedBytes = 147951465;
  static final uri = Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.bin',
  );
  File get file =>
      File('${directory.path}${Platform.pathSeparator}ggml-base.bin');
  SpeechModelPhase phase = SpeechModelPhase.missing;
  double progress = 0;
  String? problem;
  bool _cancelled = false;
  http.Client? _download;
  Future<void>? _work;
  bool get busy =>
      phase == SpeechModelPhase.checking ||
      phase == SpeechModelPhase.downloading;
  bool get ready => phase == SpeechModelPhase.ready;
  void _phase(SpeechModelPhase next) {
    phase = next;
    notifyListeners();
  }

  Future<void> _begin({required bool download}) {
    final running = _work;
    if (running != null) return running;
    _cancelled = false;
    final work = Future<void>(() => _prepare(download: download))
        .whenComplete(() => _work = null);
    _work = work;
    return work;
  }

  /// Automatic-on-stop checks the installed file without any network request.
  Future<bool> checkInstalled() async {
    if (!ready) await _begin(download: false);
    return ready;
  }

  /// Explicit first-use action may download; wait for any installed-file check.
  Future<void> prepare() async {
    final checking = _work;
    if (checking != null) {
      await checking;
      if (_cancelled) return;
    }
    if (!ready) await _begin(download: true);
  }

  Future<void> _prepare({required bool download}) async {
    if (ready) return;
    if (!backend.supported) {
      problem = 'Offline speech is available on Windows first.';
      _phase(SpeechModelPhase.failed);
      return;
    }
    problem = null;
    progress = 0;
    final partial = File('${file.path}.partial');
    try {
      _phase(SpeechModelPhase.checking);
      if (_cancelled) throw const SpeechCancelled();
      if (await file.exists() && await backend.verify(file.path)) {
        if (_cancelled) throw const SpeechCancelled();
        _phase(SpeechModelPhase.ready);
        return;
      }
      if (_cancelled) throw const SpeechCancelled();
      if (!download) {
        _phase(SpeechModelPhase.missing);
        return;
      }
      await directory.create(recursive: true);
      _phase(SpeechModelPhase.downloading);
      final client = _download = _client();
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 ||
          (response.contentLength != null &&
              response.contentLength != expectedBytes)) {
        throw const FormatException('Offline model download unavailable');
      }
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final bytes in response.stream.timeout(
          const Duration(seconds: 30),
        )) {
          if (_cancelled) throw const SpeechCancelled();
          received += bytes.length;
          if (received > expectedBytes) {
            throw const FormatException('Invalid model download');
          }
          sink.add(bytes);
          // Awaiting flush bounds the writer queue, including slow local disks.
          await sink.flush();
          progress = received / expectedBytes;
          notifyListeners();
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received != expectedBytes || _cancelled) {
        throw const FormatException('Incomplete model download');
      }
      _phase(SpeechModelPhase.checking);
      if (!await backend.verify(partial.path)) {
        throw const FormatException('Model checksum did not match');
      }
      if (_cancelled) throw const SpeechCancelled();
      await partial.rename(file.path);
      _phase(SpeechModelPhase.ready);
    } on Object {
      problem = _cancelled ? 'Setup cancelled. Try again when ready.' : 'Speech setup could not finish. Check your connection and free space, then try again.';
      _phase(SpeechModelPhase.failed);
    } finally {
      _download?.close();
      _download = null;
      if (await partial.exists()) {
        try {
          await partial.delete();
        } on FileSystemException {
          /* Retry can replace our partial. */
        }
      }
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    _download?.close();
    try {
      await backend.cancel();
    } on Object {
      /* Keep cancellation requested. */
    }
  }
}
