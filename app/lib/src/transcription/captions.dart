import 'word_timing.dart';

class Caption {
  const Caption(this.text, this.start, this.end);
  final String text;
  final Duration start, end;
}

/// Subtitles always follow actual speech, including free-speech Notes takes.
/// Whole words stay together; long pauses and sentence ends start a new phrase.
List<Caption> captionsFromSpeech(WordTranscript transcript) {
  final result = <Caption>[];
  final words = <SpokenWord>[];
  void finish() {
    if (words.isEmpty) return;
    result.add(
      Caption(
        words.map((w) => w.text).join(' '),
        words.first.start,
        words.last.end,
      ),
    );
    words.clear();
  }

  for (final word in transcript.words) {
    if (words.isNotEmpty &&
        (words.length >= 7 ||
            words.fold<int>(0, (n, w) => n + w.text.runes.length + 1) +
                    word.text.runes.length >
                42 ||
            word.start - words.last.end > const Duration(milliseconds: 700))) {
      finish();
    }
    words.add(word);
    if (RegExp(r'[.!?\u061f]$').hasMatch(word.text)) finish();
  }
  finish();
  return List.unmodifiable(result);
}

String _stamp(Duration time, {required bool vtt, bool roundUp = false}) {
  final total = roundUp
      ? (time.inMicroseconds + 999) ~/ 1000
      : time.inMilliseconds;
  String pad(int n, int width) => n.toString().padLeft(width, '0');
  return '${pad(total ~/ 3600000, 2)}:${pad(total ~/ 60000 % 60, 2)}:${pad(total ~/ 1000 % 60, 2)}${vtt ? '.' : ','}${pad(total % 1000, 3)}';
}

String subtitleText(List<Caption> captions, {bool vtt = false}) {
  final out = StringBuffer(vtt ? 'WEBVTT\n\n' : '');
  for (var i = 0; i < captions.length; i++) {
    final c = captions[i];
    if (!vtt) out.writeln(i + 1);
    out.writeln(
      '${_stamp(c.start, vtt: vtt)} --> ${_stamp(c.end, vtt: vtt, roundUp: true)}',
    );
    // VTT treats angle brackets and ampersands as markup; speech stays literal.
    out.writeln(
      vtt
          ? c.text
                .replaceAll('&', '&amp;')
                .replaceAll('<', '&lt;')
                .replaceAll('>', '&gt;')
          : c.text,
    );
    out.writeln();
  }
  return out.toString();
}
