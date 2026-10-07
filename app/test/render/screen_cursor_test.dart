import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/recording/activity_trace.dart';
import 'package:spawnalpha/src/render/screen_cursor.dart';

ActivityEvent cursorEvent(
  int ms, {
  String type = 'cursor',
  String detail = 'arrow',
  bool visible = true,
  int x = 320,
  int y = 180,
  int width = 640,
  int height = 360,
}) => ActivityEvent.fromJson({
  'type': type,
  'timeUs': ms * 1000,
  'width': width,
  'height': height,
  if (type == 'cursor' || type == 'click') ...{
    'x': x,
    'y': y,
    'visible': visible,
    'detail': type == 'click' ? 'left' : detail,
  },
  if (type == 'key') 'count': 1,
  if (type == 'shortcut') 'detail': 'Ctrl+S',
  if (type == 'focus') ...{'x': x, 'y': y, 'rectWidth': 10, 'rectHeight': 10},
});

CutPlan cursorPlan(ScriptLanguage language, [List<(int, int)>? ranges]) =>
    CutPlan(
      takeId: 'generated',
      language: language,
      sourceDuration: const Duration(seconds: 1),
      ranges: (ranges ?? [(0, 1000)])
          .map(
            (r) => SourceRange(
              start: Duration(milliseconds: r.$1),
              end: Duration(milliseconds: r.$2),
            ),
          )
          .toList(),
    );

ScreenCursorPlanner cursorPlanner({bool click = false}) {
  final planner = ScreenCursorPlanner();
  for (var ms = 0; ms < 1000; ms += 50) {
    planner.add(cursorEvent(ms, x: ms ~/ 2));
    if (click && ms == 200) {
      planner.add(cursorEvent(225, type: 'click', x: 200));
    }
  }
  return planner;
}

void main() {
  for (final language in ScriptLanguage.values) {
    test(
      'cursor clock survives cuts, reorder and repeated ranges $language',
      () {
        final plan = cursorPlan(language, [(200, 400), (700, 900), (200, 400)]);
        final track = cursorPlanner(click: true).finish(plan);
        expect(track.duration, const Duration(milliseconds: 600));
        expect(
          track.steps.where((s) => s.reset).map((s) => s.start.inMilliseconds),
          [0, 200, 400],
        );
        expect(
          track.steps.where((s) => s.snap).map((s) => s.start.inMilliseconds),
          [25, 425],
        );
        expect(track.steps[5].x, 350 / 640);
        expect(track.steps.last.end, track.duration);
        track.validateClock(plan);
        expect(
          jsonEncode(ScreenCursor.fromJson(track.toJson()).toJson()),
          jsonEncode(track.toJson()),
        );
        expect(jsonEncode(track.toJson()), isNot(contains('sourcePath')));
        expect(() => track.steps.clear(), throwsUnsupportedError);
      },
    );
    test('continuous splits keep identical cursor observations $language', () {
      final whole = cursorPlanner(click: true).finish(cursorPlan(language));
      final split = cursorPlanner(click: true)
          .finish(cursorPlan(language, [(0, 500), (500, 1000)]));
      expect(jsonEncode(split.toJson()), jsonEncode(whole.toJson()));
    });
    test(
      'removed observations cannot seed a cut or supply a click shape $language',
      () {
        final track = cursorPlanner(click: true)
            .finish(cursorPlan(language, [(225, 375)]));
        expect(track.steps.first.start.inMilliseconds, 25);
        expect(track.steps.first.x, 125 / 640);
        expect(track.steps.any((s) => s.snap), isFalse);
        expect(track.steps.last.end.inMilliseconds, 150);
        expect(
          track.steps.last.end - track.steps.last.start,
          const Duration(milliseconds: 25),
        );
      },
    );
    test(
      'hidden positions, shape changes and resizing retain only safe data $language',
      () {
        final planner = ScreenCursorPlanner();
        for (var ms = 0; ms < 1000; ms += 50) {
          planner.add(
            cursorEvent(
              ms,
              detail: ms < 300
                  ? 'arrow'
                  : ms < 500
                  ? 'hand'
                  : ms < 700
                  ? 'text'
                  : 'other',
              visible: ms < 700,
              x: 111,
              y: 123,
              width: ms < 500 ? 640 : 800,
              height: ms < 500 ? 360 : 600,
            ),
          );
          planner.add(cursorEvent(ms, type: 'key'));
          planner.add(cursorEvent(ms, type: 'shortcut'));
        }
        final track = planner.finish(cursorPlan(language));
        expect(
          track.steps.map((s) => s.shape).toSet(),
          CursorShape.values.toSet(),
        );
        expect(track.steps[10].width, 800);
        expect(track.steps[10].x, 111 / 800);
        expect(
          track.steps
              .where((s) => s.shape == CursorShape.hidden)
              .every((s) => s.x == 0 && s.y == 0 && !s.snap),
          isTrue,
        );
        final json = jsonEncode(track.toJson());
        expect(json, isNot(contains('Ctrl+S')));
        expect(json, isNot(contains('count')));
      },
    );
  }
  test('equal-time cursor sample keeps the exact click anchor', () {
    final planner = ScreenCursorPlanner();
    planner.add(cursorEvent(0));
    planner.add(cursorEvent(100, type: 'click', x: 222));
    planner.add(cursorEvent(100, x: 223, detail: 'hand'));
    for (var ms = 150; ms < 1000; ms += 50) {
      planner.add(cursorEvent(ms));
    }
    final step = planner.finish(cursorPlan(ScriptLanguage.en)).steps[1];
    expect(step.x, 222 / 640);
    expect(step.shape, CursorShape.hand);
    expect(step.snap, isTrue);
  });
  test('equal-time hidden observation clears a click anchor', () {
    final planner = ScreenCursorPlanner();
    planner.add(cursorEvent(0));
    planner.add(cursorEvent(100, type: 'click'));
    planner.add(cursorEvent(100, visible: false, detail: 'other'));
    for (var ms = 150; ms < 1000; ms += 50) {
      planner.add(cursorEvent(ms));
    }
    final step = planner.finish(cursorPlan(ScriptLanguage.en)).steps[1];
    expect(step.shape, CursorShape.hidden);
    expect(step.snap, isFalse);
    expect(step.x, 0);
  });
  for (final condition in [
    'shape',
    'gap',
    'head',
    'tail',
    'order',
    'click',
    'resize-click',
    'empty-cut',
    'reuse',
  ]) {
    test('unsafe cursor evidence is rejected: $condition', () {
      final planner = ScreenCursorPlanner();
      void run() {
        if (condition == 'click') {
          planner.add(cursorEvent(0, type: 'click'));
          planner.finish(cursorPlan(ScriptLanguage.en));
        } else {
          planner.add(cursorEvent(condition == 'head' ? 251 : 0));
          if (condition == 'shape') {
            planner.add(cursorEvent(1, detail: 'other'));
          }
          if (condition == 'gap') planner.add(cursorEvent(251));
          if (condition == 'order') planner.add(cursorEvent(1));
          if (condition == 'order') planner.add(cursorEvent(0));
          if (condition == 'resize-click') {
            planner.add(cursorEvent(1, type: 'click', width: 800));
            planner.finish(cursorPlan(ScriptLanguage.en, [(1, 10)]));
          }
          if (condition == 'head') planner.add(cursorEvent(300));
          for (
            var ms = condition == 'head' ? 350 : 50;
            ms < (condition == 'tail' ? 750 : 1000);
            ms += 50
          ) {
            planner.add(cursorEvent(ms));
          }
          planner.finish(
            cursorPlan(
              ScriptLanguage.en,
              condition == 'empty-cut' ? [(1, 10)] : null,
            ),
          );
          if (condition == 'reuse') planner.add(cursorEvent(1000));
        }
      }

      expect(run, throwsFormatException);
    });
  }
  test('observation bounds stop growing input and retained reuse', () {
    final planner = ScreenCursorPlanner();
    for (var i = 0; i < maxCursorSteps; ++i) {
      planner.add(cursorEvent(i, x: i % 640));
    }
    expect(
      () => planner.add(cursorEvent(maxCursorSteps)),
      throwsFormatException,
    );
    final plan = CutPlan(
      takeId: 'generated',
      language: ScriptLanguage.en,
      sourceDuration: const Duration(milliseconds: maxCursorSteps),
      ranges: List.generate(
        2,
        (_) => SourceRange(
          start: Duration.zero,
          end: const Duration(milliseconds: maxCursorSteps),
        ),
      ),
    );
    expect(() => planner.finish(plan), throwsFormatException);
  });
  test(
    'frozen cursor schema rejects gaps, private fields and cut-crossing data',
    () {
      final plan = cursorPlan(ScriptLanguage.en, [(0, 400), (700, 900)]);
      final json = cursorPlanner().finish(plan).toJson();
      void bad(Map<String, Object?> value) => expect(
        () => ScreenCursor.fromJson(value).validateClock(plan),
        throwsFormatException,
      );
      bad({...json, 'sourcePath': 'private'});
      bad({...json, 'version': 2});
      bad({...json, 'steps': []});
      bad({...json, 'durationUs': 999999});
      final steps = json['steps']! as List;
      for (final patch in <Map<String, Object?>>[
        {'x': double.nan},
        {'x': 1},
        {'y': -1},
        {'shape': 'private'},
        {'shape': 'hidden', 'x': .3},
        {'endUs': 300000},
        {'startUs': -1},
        {'width': 0},
        {'reset': false},
        {'snap': 'yes'},
        {'text': 'private'},
      ]) {
        bad({
          ...json,
          'steps': [
            {...steps.first as Map, ...patch},
            ...steps.skip(1),
          ],
        });
      }
      bad({
        ...json,
        'steps': [steps.first, steps.first],
      });
      final cutIndex = steps.indexWhere((s) => (s as Map)['startUs'] == 400000);
      bad({
        ...json,
        'steps': [
          ...steps.take(cutIndex),
          {...steps[cutIndex] as Map, 'reset': false},
          ...steps.skip(cutIndex + 1),
        ],
      });
      bad({
        ...json,
        'steps': [
          ...steps.take(cutIndex - 1),
          {...steps[cutIndex - 1] as Map, 'endUs': 410000},
          ...steps.skip(cutIndex),
        ],
      });
    },
  );
}
