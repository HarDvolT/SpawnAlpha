import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/note_timeline.dart';
import 'package:spawnalpha/src/review/publishing_text.dart';
import 'package:spawnalpha/src/storage/publishing_store.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/publishing_screen.dart';

import '../review/publishing_text_test.dart'
    show publishingScript, publishingWords, publishingPlan, publishingNotes;

class TestPublishingStore extends PublishingStore {
  TestPublishingStore() : super(Directory.systemTemp);
  final requests = <PublishingText>[];
  bool fail = false;
  Completer<Directory>? held;
  @override
  Future<Directory> save(PublishingText draft) async {
    requests.add(draft);
    if (fail) throw const FileSystemException('Generated failure');
    return held != null
        ? await held!.future
        : Directory('generated-local-text');
  }
}

void main() {
  for (final language in ScriptLanguage.values) {
    for (final action in ['copy', 'save', 'fail', 'busy', 'empty']) {
      testWidgets(
        'publishing text $action uses explicit actions and direction $language',
        (tester) async {
          tester.view.physicalSize = const Size(430, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final store = TestPublishingStore();
          if (action == 'fail') store.fail = true;
          if (action == 'busy') {
            store.held = Completer<Directory>();
          }
          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          final draft = publishingFromSpeech(
            source: publishingWords(language),
            plan: publishingPlan(language),
            snapshot: language == ScriptLanguage.fr
                ? publishingNotes(language)
                : publishingScript(language),
            aligned: true,
            noteMoments: language == ScriptLanguage.fr
                ? const [
                    NoteMoment(0, Duration.zero),
                    NoteMoment(1, Duration(seconds: 4)),
                  ]
                : const [],
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(Brightness.light),
              home: PublishingScreen(draft: draft, store: store),
            ),
          );
          await tester.pumpAndSettle();
          expect(store.requests, isEmpty);
          expect(copied, isNull);
          final title = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Title',
          );
          expect(
            Directionality.of(tester.element(title)),
            language.isRtl ? TextDirection.rtl : TextDirection.ltr,
          );
          await tester.enterText(title, '${draft.title} edited');
          await tester.enterText(
            find.byWidgetPredicate(
              (w) => w is TextField && w.decoration?.labelText == 'Description',
            ),
            '${draft.description} edited',
          );
          if (action == 'empty') {
            final chapter = find
                .byWidgetPredicate(
                  (w) =>
                      w is TextField &&
                      w.decoration?.labelText == 'Chapter title',
                )
                .first;
            await tester.ensureVisible(chapter);
            await tester.enterText(chapter, '');
          } else {
            final second = find.widgetWithText(CheckboxListTile, '00:02');
            await tester.ensureVisible(second);
            await tester.tap(second);
          }
          await tester.pumpAndSettle();
          final button = find.text(
            action == 'copy' ? 'Copy text' : 'Save text files',
          );
          await tester.ensureVisible(button);
          await tester.tap(button);
          if (action == 'busy') {
            await tester.pump();
            expect(
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Save text files'),
                  )
                  .onPressed,
              isNull,
            );
            expect(find.byType(LinearProgressIndicator), findsOneWidget);
            store.held!.complete(Directory('generated-local-text'));
          }
          await tester.pumpAndSettle();
          if (action == 'copy') {
            expect(copied, contains('${draft.title} edited'));
            expect(copied, contains('${draft.description} edited'));
            expect(copied, isNot(contains('00:02 ')));
            expect(store.requests, isEmpty);
            expect(
              find.text('Text copied. Nothing was posted.'),
              findsOneWidget,
            );
          } else if (action == 'empty') {
            expect(store.requests, isEmpty);
            expect(
              find.textContaining('Give each kept chapter a title'),
              findsOneWidget,
            );
          } else {
            expect(store.requests, hasLength(1));
            expect(store.requests.single.title, '${draft.title} edited');
            expect(store.requests.single.chapters, hasLength(1));
            expect(
              find.text(
                action == 'fail'
                    ? 'Text could not be saved. Your recording and previous files are safe.'
                    : 'Text files saved on this device.',
              ),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets('long chapter lists page without losing edited titles', (
    tester,
  ) async {
    final draft = PublishingText(
      language: ScriptLanguage.en,
      duration: const Duration(seconds: 20),
      title: 'Generated title',
      description: 'Generated description',
      chapters: [
        for (var i = 0; i < 10; ++i)
          ChapterText(Duration(seconds: i), 'Chapter $i'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: PublishingScreen(draft: draft, store: TestPublishingStore()),
      ),
    );
    await tester.pumpAndSettle();
    final chapter = find
        .byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Chapter title',
        )
        .first;
    await tester.ensureVisible(chapter);
    await tester.enterText(chapter, 'Edited first chapter');
    await tester.scrollUntilVisible(
      find.text('Next chapters'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Next chapters'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Page 2 of 2'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Previous chapters'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Edited first chapter'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Edited first chapter'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
