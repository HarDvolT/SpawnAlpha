import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/note_deck.dart';
import 'package:spawnalpha/src/model/script_document.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/review/publishing_text.dart';
import 'package:spawnalpha/src/review/publishing_loader.dart';
import 'package:spawnalpha/src/storage/publishing_store.dart';
import 'package:spawnalpha/src/transcription/speech_processor.dart';
import 'package:spawnalpha/src/transcription/word_timing.dart';

import '../cut/retake_review_test.dart'
    show retakeWords, retakeScript, retakePlan;
import '../cut/filler_review_test.dart'
    show fillerFixture, fillerScript, fillerPlan;

ScriptDocument publishingScript(ScriptLanguage language) =>
    ScriptDocument.create(
      language: language,
      title: switch (language) {
        ScriptLanguage.en => 'Launch plans',
        ScriptLanguage.fr => 'Préparer le lancement',
        ScriptLanguage.ar => 'خطط البداية',
      },
      text: switch (language) {
        ScriptLanguage.en => 'We launch today.\n\nOur plans work.',
        ScriptLanguage.fr => 'Nous lançons demain.\n\nNos idées fonctionnent.',
        ScriptLanguage.ar => 'نحن نبدأ الآن.\n\nهذه خطط واضحة.',
      },
    );
WordTranscript publishingWords(
  ScriptLanguage language, {
  double? confidence = .9,
}) {
  final snapshot = publishingScript(language);
  return WordTranscript(
    language: language,
    duration: const Duration(seconds: 8),
    words: [
      for (var i = 0; i < snapshot.tokens.length; ++i)
        SpokenWord(
          text: snapshot.tokens[i].text,
          start: Duration(
            milliseconds: i < 3 ? 300 + i * 500 : 5000 + (i - 3) * 500,
          ),
          end: Duration(
            milliseconds: i < 3 ? 600 + i * 500 : 5300 + (i - 3) * 500,
          ),
          confidence: confidence,
        ),
    ],
  );
}

CutPlan publishingPlan(ScriptLanguage language) => CutPlan(
  takeId: 'generated',
  language: language,
  sourceDuration: const Duration(seconds: 8),
  ranges: [
    SourceRange(start: Duration.zero, end: const Duration(milliseconds: 2200)),
    SourceRange(
      start: const Duration(milliseconds: 4500),
      end: const Duration(seconds: 8),
    ),
  ],
);
ScriptDocument publishingNotes(ScriptLanguage language) =>
    publishingScript(language).copyWith(
      recordingAid: RecordingAid.notes,
      notes: NoteDeck([
        NoteCard(
          id: 'one',
          title: switch (language) {
            ScriptLanguage.en => 'Opening',
            ScriptLanguage.fr => 'Introduction',
            ScriptLanguage.ar => 'المقدمة',
          },
          body: 'Unspoken private reminders',
        ),
        NoteCard(
          id: 'two',
          title: switch (language) {
            ScriptLanguage.en => 'Next steps',
            ScriptLanguage.fr => 'Les étapes suivantes',
            ScriptLanguage.ar => 'الخطوات التالية',
          },
          body: 'Different unspoken bullet text',
        ),
      ]),
    );

void main() {
  for (final language in ScriptLanguage.values) {
    test(
      'script paragraph chapters and description use actual kept speech $language',
      () {
        final script = publishingScript(language),
            words = publishingWords(language),
            plan = publishingPlan(language);
        final draft = publishingFromSpeech(
          source: words,
          plan: plan,
          snapshot: script,
          aligned: true,
        );
        expect(draft.title, script.title);
        expect(draft.description, words.words.map((w) => w.text).join(' '));
        expect(draft.chapters.map((c) => c.time), [
          Duration.zero,
          const Duration(milliseconds: 2700),
        ]);
        expect(draft.chapterText, startsWith('00:00 '));
        expect(draft.chapterText, contains('\n00:02 '));
        expect(draft.notice, isNull);
        expect(draft.duration, plan.duration);
        expect(draft.notes, isFalse);
        final lateOnly = CutPlan(
          takeId: 'generated',
          language: language,
          sourceDuration: words.duration,
          ranges: [plan.ranges.last],
        );
        final late = publishingFromSpeech(
          source: WordTranscript(
            language: language,
            duration: words.duration,
            words: words.words.skip(3).toList(),
          ),
          plan: lateOnly,
          snapshot: script,
          aligned: true,
        );
        expect(late.chapters, hasLength(1));
        expect(late.chapters.single.time, Duration.zero);
        expect(late.chapters.single.title, draft.chapters.last.title);
        expect(
          late.description,
          words.words.skip(3).map((w) => w.text).join(' '),
        );
        final reordered = CutPlan(
          takeId: 'generated',
          language: language,
          sourceDuration: words.duration,
          ranges: plan.ranges.reversed.toList(),
        );
        expect(
          () => publishingFromSpeech(
            source: words,
            plan: reordered,
            snapshot: script,
            aligned: true,
          ),
          throwsFormatException,
        );
        expect(() => draft.chapters.clear(), throwsUnsupportedError);
      },
    );
    test(
      'chosen retakes supply description and frozen chapter times $language',
      () {
        final words = retakeWords(language), script = retakeScript(language);
        final base = retakePlan(words),
            clean = base.withAttempt(base.retakes.single.id, 1);
        final draft = publishingFromSpeech(
          source: words,
          plan: clean.asCutPlan(),
          clean: clean,
          snapshot: script,
          aligned: true,
        );
        expect(draft.description, script.text);
        expect(draft.chapters, hasLength(1));
        expect(draft.chapters.single.time, Duration.zero);
        expect(draft.duration, clean.asCutPlan().duration);
        expect(
          () => publishingFromSpeech(
            source: words,
            plan: clean.asCutPlan(),
            snapshot: script,
            aligned: true,
          ),
          throwsFormatException,
        );
      },
    );
    test(
      'explicit filler choice leaves only retained actual words in description $language',
      () {
        final words = fillerFixture(language),
            script = fillerScript(fillerFixture(language));
        final base = fillerPlan(words),
            clean = base.withEnabled(
              base.changes.firstWhere((c) => c.kind.name == 'filler').id,
              true,
            );
        final draft = publishingFromSpeech(
          source: words,
          plan: clean.asCutPlan(),
          clean: clean,
          snapshot: script,
          aligned: true,
        );
        expect(draft.description, script.text);
        expect(draft.duration, clean.asCutPlan().duration);
        expect(draft.chapters, hasLength(1));
      },
    );
    test(
      'Notes anchors titles without borrowing private bullets or script adherence $language',
      () {
        final notes = publishingNotes(language),
            words = publishingWords(language),
            plan = publishingPlan(language);
        final moments = chapterNoteMoments(
          [
            {'cardIndex': 0, 'timeUs': 0},
            {'cardIndex': 1, 'timeUs': 4000000},
          ],
          notes,
          words.duration,
        );
        final draft = publishingFromSpeech(
          source: words,
          plan: plan,
          snapshot: notes,
          aligned: true,
          noteMoments: moments,
        );
        expect(draft.notes, isTrue);
        expect(
          draft.chapters.map((c) => c.title),
          notes.notes.cards.map((c) => c.title),
        );
        expect(draft.chapters.last.time, const Duration(milliseconds: 2700));
        expect(draft.description, words.words.map((w) => w.text).join(' '));
        expect(jsonEncode(draft.toJson()), isNot(contains('reminders')));
        expect(jsonEncode(draft.toJson()), isNot(contains('bullet')));
        final noClock = publishingFromSpeech(
          source: words,
          plan: plan,
          snapshot: notes,
        );
        expect(noClock.chapters, isEmpty);
        expect(noClock.notice, contains('unavailable'));
        expect(noClock.description, draft.description);
      },
    );
    test(
      'uncertain/no alignment keeps actual text without guessed chapter timing $language',
      () {
        final words = publishingWords(language, confidence: null),
            plan = publishingPlan(language),
            script = publishingScript(language);
        final unknown = publishingFromSpeech(
          source: words,
          plan: plan,
          snapshot: script,
          aligned: true,
        );
        expect(unknown.chapters, isEmpty);
        expect(unknown.description, words.words.map((w) => w.text).join(' '));
        final unaligned = publishingFromSpeech(
          source: words,
          plan: plan,
          snapshot: script,
        );
        expect(unaligned.chapters, isEmpty);
        expect(unaligned.notice, contains('unavailable'));
        final corrected = WordTranscript(
          language: language,
          duration: words.duration,
          words: [
            for (final word in words.words)
              SpokenWord(
                text: word.text,
                start: word.start,
                end: word.end,
                confidence: 0,
                recognizedText: 'generated-misheard',
              ),
          ],
        );
        expect(
          publishingFromSpeech(
            source: corrected,
            plan: plan,
            snapshot: script,
            aligned: true,
          ).chapters,
          hasLength(2),
        );
      },
    );
    test(
      'local save creates new complete text folders and preserves earlier files $language',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'spawnalpha-publishing-',
        );
        addTearDown(() => root.delete(recursive: true));
        final store = PublishingStore(root);
        final draft = publishingFromSpeech(
          source: publishingWords(language),
          plan: publishingPlan(language),
          snapshot: publishingScript(language),
          aligned: true,
        );
        final first = await store.save(draft);
        final bytes = <String, List<int>>{};
        for (final name in [
          'title.txt',
          'description.txt',
          'chapters.txt',
          'publishing.txt',
          'publishing.json',
        ]) {
          bytes[name] = await File('${first.path}/$name').readAsBytes();
        }
        final changed = draft.copyWith(
          title: '${draft.title} edited',
          chapters: [draft.chapters.last],
        );
        final second = await store.save(changed);
        expect(second.path, isNot(first.path));
        expect(
          await File('${second.path}/title.txt').readAsString(),
          changed.title,
        );
        expect(
          await File('${second.path}/chapters.txt').readAsString(),
          changed.chapterText,
        );
        expect(
          await File('${second.path}/publishing.txt').readAsString(),
          changed.combined,
        );
        expect(
          jsonDecode(
            await File('${second.path}/publishing.json').readAsString(),
          ),
          changed.toJson(),
        );
        for (final entry in bytes.entries) {
          expect(
            await File('${first.path}/${entry.key}').readAsBytes(),
            entry.value,
          );
        }
        expect(
          await root.list().where((e) => e.path.endsWith('.tmp')).length,
          0,
        );
        final blocked = File('${root.path}/blocked');
        await blocked.writeAsString('generated previous file');
        await expectLater(
          PublishingStore(Directory(blocked.path)).save(draft),
          throwsA(isA<FileSystemException>()),
        );
        expect(await blocked.readAsString(), 'generated previous file');
      },
    );
    for (final mode in TakeMode.values) {
      test(
        'guarded frozen card metadata supports $mode and rejects substitution $language',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'spawnalpha-publishing-cards-',
          );
          addTearDown(() => root.delete(recursive: true));
          final snapshot = publishingNotes(language),
              source = File('${root.path}/generated.mp4');
          await source.writeAsString('generated source');
          final take = Take(
            path: source.path,
            recordedAt: DateTime(2026),
            duration: const Duration(seconds: 8),
            mode: mode,
            metadataPath: '${root.path}/manifest.json',
          );
          final spoken = SavedTranscript(
            sourcePath: source.path,
            transcript: publishingWords(language),
            snapshot: snapshot,
          );
          Map<String, Object?> metadata(ScriptDocument script) => {
            'version': 1,
            'mode': mode.name,
            'script': script.toJson(),
            if (mode == TakeMode.camera)
              'take': take.toJson()
            else
              'video': 'generated.mp4',
            'noteChanges': [
              {'cardIndex': 0, 'timeUs': 0},
              {'cardIndex': 1, 'timeUs': 4000000},
            ],
          };
          await File(take.metadataPath!)
              .writeAsString(jsonEncode(metadata(snapshot)));
          final draft = await loadPublishingText(
            PublishingJob(spoken, publishingPlan(language), take),
          );
          expect(draft.chapters, hasLength(2));
          final changed = snapshot.copyWith(
            notes: snapshot.notes.replace(
              0,
              snapshot.notes.cards.first.copyWith(title: 'Changed later'),
            ),
          );
          await File(take.metadataPath!)
              .writeAsString(jsonEncode(metadata(changed)));
          final rejected = await loadPublishingText(
            PublishingJob(spoken, publishingPlan(language), take),
          );
          expect(rejected.chapters, isEmpty);
          expect(rejected.description, draft.description);
          await File(take.metadataPath!).writeAsString('{invalid');
          expect(
            (await loadPublishingText(
              PublishingJob(spoken, publishingPlan(language), take),
            )).chapters,
            isEmpty,
          );
        },
      );
    }
  }
  test('nearby sections merge within a whole second and stamps keep hours', () {
    final script = publishingScript(ScriptLanguage.en);
    final source = WordTranscript(
      language: script.language,
      duration: const Duration(seconds: 2),
      words: [
        for (final (i, token) in script.tokens.indexed)
          SpokenWord(
            text: token.text,
            start: Duration(milliseconds: i * 100),
            end: Duration(milliseconds: i * 100 + 80),
            confidence: .9,
          ),
      ],
    );
    final plan = CutPlan(
      takeId: 'generated',
      language: script.language,
      sourceDuration: source.duration,
      ranges: [SourceRange(start: Duration.zero, end: source.duration)],
    );
    final draft = publishingFromSpeech(
      source: source,
      plan: plan,
      snapshot: script,
      aligned: true,
    );
    expect(draft.chapters, hasLength(1));
    expect(draft.chapters.single.title, contains(' / '));
    expect(
      chapterStamp(const Duration(hours: 2, minutes: 3, seconds: 9)),
      '2:03:09',
    );
    expect(
      () => chapterStamp(const Duration(seconds: -1)),
      throwsArgumentError,
    );
  });
  test('metadata from another folder, a link or oversized input never supplies card titles', () async {
    final root = await Directory.systemTemp.createTemp(
      'spawnalpha-text-guard-',
    );
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}/generated.mp4');
    await source.writeAsString('generated source');
    final snapshot = publishingNotes(ScriptLanguage.en);
    final spoken = SavedTranscript(
      sourcePath: source.path,
      transcript: publishingWords(ScriptLanguage.en),
      snapshot: snapshot,
    );
    Future<void> rejected(String metadata) async {
      final take = Take(
        path: source.path,
        recordedAt: DateTime(2026),
        duration: spoken.transcript.duration,
        metadataPath: metadata,
      );
      final draft = await loadPublishingText(
        PublishingJob(spoken, publishingPlan(ScriptLanguage.en), take),
      );
      expect(draft.chapters, isEmpty);
      expect(draft.notice, contains('unavailable'));
    }

    final folder = await Directory('${root.path}/other').create();
    final outside = File('${folder.path}/manifest.json');
    await outside.writeAsString(
      jsonEncode({
        'version': 1,
        'mode': 'camera',
        'script': snapshot.toJson(),
        'take': {'path': source.path},
        'noteChanges': [
          {'cardIndex': 0, 'timeUs': 0},
        ],
      }),
    );
    await rejected(outside.path);
    final link = Link('${root.path}/linked.json');
    await link.create(outside.path);
    await rejected(link.path);
    final large = File('${root.path}/large.json');
    await large.writeAsString(' ' * (16 * 1024 * 1024 + 1));
    await rejected(large.path);
  });
  test('invalid card clocks, clocks and chapter payloads are rejected', () {
    final notes = publishingNotes(ScriptLanguage.en);
    for (final json in [
      null,
      [],
      [
        {'cardIndex': 2, 'timeUs': 0},
      ],
      [
        {'cardIndex': 0, 'timeUs': 1},
      ],
      [
        {'cardIndex': 0, 'timeUs': 0, 'extra': true},
      ],
      [
        {'cardIndex': 0, 'timeUs': 0},
        {'cardIndex': 1, 'timeUs': 0},
      ],
      [
        {'cardIndex': 0, 'timeUs': 0},
        {'cardIndex': 1, 'timeUs': 8000000},
      ],
    ]) {
      expect(
        () => chapterNoteMoments(json, notes, const Duration(seconds: 8)),
        throwsFormatException,
      );
    }
    final good = publishingFromSpeech(
      source: publishingWords(ScriptLanguage.en),
      plan: publishingPlan(ScriptLanguage.en),
      snapshot: publishingScript(ScriptLanguage.en),
      aligned: true,
    );
    expect(
      () => good.copyWith(chapters: [const ChapterText(Duration.zero, '')]),
      throwsFormatException,
    );
    expect(
      () => good.copyWith(
        chapters: [
          const ChapterText(Duration.zero, 'a'),
          const ChapterText(Duration.zero, 'b'),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => good.copyWith(chapters: [ChapterText(good.duration, 'end')]),
      throwsFormatException,
    );
    expect(() => good.copyWith(title: 'a\u0000b'), throwsFormatException);
    expect(
      () => good.copyWith(description: 'a' * 10001),
      throwsFormatException,
    );
    expect(
      () => publishingFromSpeech(
        source: publishingWords(ScriptLanguage.fr),
        plan: publishingPlan(ScriptLanguage.en),
      ),
      throwsFormatException,
    );
  });
}
