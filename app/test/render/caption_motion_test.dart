import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/caption_style.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';
import 'package:spawnalpha/src/transcription/captions.dart';
import 'package:spawnalpha/src/transcription/caption_cues.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

WordTranscript motionWords(ScriptLanguage language) {
  final texts = switch (language) {
    ScriptLanguage.en => ['Hello', 'again', 'today.'],
    ScriptLanguage.fr => ['Bonjour', 'à', 'tous.'],
    ScriptLanguage.ar => ['مَرْحَبًا', 'بِكُمْ', 'اليوم.'],
  };
  return WordTranscript(
    language: language,
    duration: const Duration(seconds: 2),
    words: [
      for (final (i, text) in texts.indexed)
        SpokenWord(
          text: text,
          start: Duration(microseconds: 123456 + i * 400000),
          end: Duration(microseconds: 345678 + i * 400000),
        ),
    ],
  );
}

VideoRenderRequest motionRequest(
  ScriptLanguage language,
  List<Caption> captions, {
  CaptionStyle style = CaptionStyle.karaoke,
}) => VideoRenderRequest(
  source: r'E:\generated.mp4',
  output: r'E:\new.mp4',
  format: VideoFormat.portrait,
  plan: CutPlan(
    takeId: 'generated',
    language: language,
    sourceDuration: const Duration(seconds: 2),
    ranges: [
      SourceRange(start: Duration.zero, end: const Duration(seconds: 2)),
    ],
  ),
  captions: captions,
  captionStyle: style,
);

void main() {
  for (final language in ScriptLanguage.values) {
    test('Karaoke has exact words, UTF-16 ranges and gaps $language', () {
      final spoken = motionWords(language),
          captions = captionsFromSpeech(motionWords(language));
      final phrase = captions.single;
      expect(phrase.words.length, spoken.words.length);
      var offset = 0;
      for (final (i, word) in spoken.words.indexed) {
        final timed = phrase.words[i];
        expect([timed.offset, timed.length], [offset, word.text.length]);
        expect([timed.start, timed.end], [word.start, word.end]);
        expect(
          phrase.text.substring(timed.offset, timed.offset + timed.length),
          word.text,
        );
        offset += word.text.length + 1;
      }
      final json = motionRequest(language, captions).toJson();
      expect((json['captionLayout'] as Map)['style'], 'karaoke');
      expect((json['captionLayout'] as Map)['rtl'], language.isRtl);
      expect(
        ((json['captions'] as List).single as Map)['words'],
        phrase.words.map((w) => w.toJson()).toList(),
      );
      expect(subtitleText(captions), contains('00:00:00,123 --> 00:00:01,146'));
      expect(
        () => phrase.words.add(phrase.words.first),
        throwsUnsupportedError,
      );
    });
    test('saved styles and old exports remain compatible $language', () {
      final video = VideoExport(
        id: 'generated',
        format: VideoFormat.portrait,
        duration: const Duration(seconds: 2),
        createdAt: DateTime(2026),
        captions: true,
        burnedCaptions: true,
        captionStyle: CaptionStyle.karaoke,
      );
      expect(
        VideoExport.fromJson(video.toJson()).captionStyle,
        CaptionStyle.karaoke,
      );
      final old = video.toJson()
        ..remove('captionStyle')
        ..remove('captionMotion');
      expect(VideoExport.fromJson(old).captionStyle, CaptionStyle.readable);
      expect(VideoExport.fromJson(old).captionMotion, isTrue);
      expect(
        VideoExport.fromJson(video.toJson()..['captionMotion'] = false)
            .captionMotion,
        isFalse,
      );
      expect(
        () => VideoExport.fromJson(video.toJson()..['captionMotion'] = 3),
        throwsFormatException,
      );
      old['captionStyle'] = 'unknown';
      expect(() => VideoExport.fromJson(old), throwsFormatException);
      old['captionStyle'] = 4;
      expect(() => VideoExport.fromJson(old), throwsFormatException);
    });
    test('request owns its word list after validation $language', () {
      final original = captionsFromSpeech(motionWords(language)).single;
      final words = original.words.toList();
      final request = motionRequest(language, [
        Caption(original.text, original.start, original.end, words: words),
      ]);
      words.clear();
      expect(request.captions.single.words, hasLength(3));
      expect(
        () => request.captions.single.words.clear(),
        throwsUnsupportedError,
      );
    });
  }
  test('Arabic display elongation leaves actual captions intact and updates UTF-16 ranges', () {
    final words = motionWords(ScriptLanguage.ar);
    final phrase = captionsFromSpeech(
      words,
      cues: const [CaptionCue(stress: true), CaptionCue(), CaptionCue()],
    ).single;
    final request = motionRequest(ScriptLanguage.ar, [
      phrase,
    ], style: CaptionStyle.cue);
    final shown = (request.toJson()['captions'] as List).single as Map;
    expect(shown['text'], contains('\u0640\u0640\u0640'));
    expect(request.captions.single.text, isNot(contains('\u0640')));
    final timed = shown['words'] as List;
    expect(timed[1]['offset'], phrase.words[1].offset + 3);
    expect(timed[0]['startUs'], phrase.words.first.start.inMicroseconds);
    expect(
      (request.toJson()['captionLayout'] as Map)['popStiffness'],
      greaterThan(0),
    );
  });
  test('Punch rejects multiword stressed chunks and all kinetic styles require real timing', () {
    final words = motionWords(ScriptLanguage.en),
        phrase = captionsFromSpeech(motionWords(ScriptLanguage.en)).single;
    final stressed = Caption(
      phrase.text,
      phrase.start,
      phrase.end,
      words: [
        CaptionWord(
          phrase.words.first.offset,
          phrase.words.first.length,
          phrase.words.first.start,
          phrase.words.first.end,
          cue: const CaptionCue(stress: true),
        ),
        ...phrase.words.skip(1),
      ],
    );
    expect(
      () =>
          motionRequest(words.language, [stressed], style: CaptionStyle.punch),
      throwsFormatException,
    );
    for (final style in CaptionStyle.values.where(
      (s) => s != CaptionStyle.readable,
    )) {
      expect(
        () => motionRequest(words.language, [
          Caption(phrase.text, phrase.start, phrase.end),
        ], style: style),
        throwsFormatException,
      );
    }
  });
  test('timed caption rejects missing, split, overlapping and incomplete words', () {
    const start = Duration(milliseconds: 100),
        end = Duration(milliseconds: 900);
    const valid = [
      CaptionWord(0, 5, start, Duration(milliseconds: 400)),
      CaptionWord(6, 5, Duration(milliseconds: 600), end),
    ];
    for (final words in <List<CaptionWord>>[
      [],
      [valid.first],
      [const CaptionWord(1, 4, start, Duration(milliseconds: 400)), valid.last],
      [valid.first, const CaptionWord(6, 5, Duration(milliseconds: 300), end)],
      [const CaptionWord(0, 6, start, Duration(milliseconds: 400)), valid.last],
      [
        const CaptionWord(
          0,
          5,
          Duration(milliseconds: 200),
          Duration(milliseconds: 400),
        ),
        valid.last,
      ],
      [
        valid.first,
        const CaptionWord(
          6,
          5,
          Duration(milliseconds: 600),
          Duration(seconds: 1),
        ),
      ],
      [const CaptionWord(0, 0, start, end)],
      [const CaptionWord(0, 20, start, end)],
    ]) {
      expect(
        () => motionRequest(ScriptLanguage.en, [
          Caption('Hello world', start, end, words: words),
        ]),
        throwsFormatException,
      );
    }
    // Readable keeps its legacy complete phrase API without manufactured times.
    expect(
      motionRequest(ScriptLanguage.en, [
        const Caption('Hello world', start, end),
      ], style: CaptionStyle.readable).captions.single.words,
      isEmpty,
    );
  });
  test(
    'emoji, Arabic diacritics and Latin switching preserve UTF-16 words',
    () {
      final transcript = WordTranscript(
        language: ScriptLanguage.ar,
        duration: const Duration(seconds: 1),
        words: [
          SpokenWord(
            text: 'مَرْحَبًا',
            start: Duration.zero,
            end: const Duration(milliseconds: 200),
          ),
          SpokenWord(
            text: '🛰️Hi',
            start: const Duration(milliseconds: 300),
            end: const Duration(milliseconds: 400),
          ),
          SpokenWord(
            text: 'Bonjour.',
            start: const Duration(milliseconds: 500),
            end: const Duration(milliseconds: 700),
          ),
        ],
      );
      final phrase = captionsFromSpeech(transcript).single;
      expect(
        motionRequest(ScriptLanguage.ar, [phrase]).captions.single.text,
        'مَرْحَبًا 🛰️Hi Bonjour.',
      );
      final broken = [
        phrase.words.first,
        CaptionWord(
          phrase.words[1].offset,
          1,
          phrase.words[1].start,
          phrase.words[1].end,
        ),
        phrase.words.last,
      ];
      expect(
        () => motionRequest(ScriptLanguage.ar, [
          Caption(phrase.text, phrase.start, phrase.end, words: broken),
        ]),
        throwsFormatException,
      );
    },
  );
}
