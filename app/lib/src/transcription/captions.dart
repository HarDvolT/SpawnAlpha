import 'word_timing.dart';
import 'caption_cues.dart';

class Caption {
  const Caption(this.text, this.start, this.end, {this.words = const []});
  final String text;
  final Duration start, end;
  final List<CaptionWord> words;
}

/// UTF-16 ranges refer to the complete shaped phrase, never guessed glyphs.
class CaptionWord {
  const CaptionWord(
    this.offset,
    this.length,
    this.start,
    this.end, {
    this.cue = const CaptionCue(),
  });
  final int offset, length;
  final Duration start, end;
  final CaptionCue cue;
  Map<String, Object?> toJson() => {
    'offset': offset,
    'length': length,
    'startUs': start.inMicroseconds,
    'endUs': end.inMicroseconds,
    'stress': cue.stress,
    'energy': cue.energy,
    'pace': cue.pace.name,
  };
}

/// Subtitles always follow actual speech, including free-speech Notes takes.
/// Whole words stay together; long pauses and sentence ends start a new phrase.
List<Caption> captionsFromSpeech(
  WordTranscript transcript, {
  List<CaptionCue>? cues,
  bool punch = false,
}) {
  if (cues != null && cues.length != transcript.words.length) {
    throw const FormatException('Caption cues mismatch');
  }
  final result = <Caption>[];
  final words = <(SpokenWord, CaptionCue)>[];
  void finish() {
    if (words.isEmpty) return;
    var offset = 0;
    final timed = <CaptionWord>[];
    for (final (word, cue) in words) {
      timed.add(
        CaptionWord(offset, word.text.length, word.start, word.end, cue: cue),
      );
      offset += word.text.length + 1;
    }
    result.add(
      Caption(
        words.map((w) => w.$1.text).join(' '),
        words.first.$1.start,
        words.last.$1.end,
        words: List.unmodifiable(timed),
      ),
    );
    words.clear();
  }

  for (final (i, word) in transcript.words.indexed) {
    final cue = cues?[i] ?? const CaptionCue();
    if (words.isNotEmpty &&
        ((punch && cue.stress) ||
            words.length >= (punch ? 3 : 7) ||
            words.fold<int>(0, (n, w) => n + w.$1.text.runes.length + 1) +
                    word.text.runes.length >
                42 ||
            word.start - words.last.$1.end >
                const Duration(milliseconds: 700))) {
      finish();
    }
    words.add((word, cue));
    if (cue.breakAfter ||
        (punch && cue.stress) ||
        RegExp(r'[.!?\u061f]$').hasMatch(word.text)) {
      finish();
    }
  }
  finish();
  return List.unmodifiable(result);
}

/// Display elongation is separate from actual words and subtitle spelling.
Caption captionDisplay(Caption original, {required bool rtl}) {
  if (!rtl || original.words.every((w) => !w.cue.stress)) return original;
  final text = StringBuffer(), words = <CaptionWord>[];
  for (final word in original.words) {
    if (words.isNotEmpty) text.write(' ');
    final actual = original.text.substring(
      word.offset,
      word.offset + word.length,
    );
    final shown = word.cue.stress ? captionKashida(actual) : actual;
    words.add(
      CaptionWord(
        text.length,
        shown.length,
        word.start,
        word.end,
        cue: word.cue,
      ),
    );
    text.write(shown);
  }
  return Caption(
    text.toString(),
    original.start,
    original.end,
    words: List.unmodifiable(words),
  );
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
