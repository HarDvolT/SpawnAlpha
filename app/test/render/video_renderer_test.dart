import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';
import 'package:spawnalpha/src/transcription/captions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final request = VideoRenderRequest(
    source: r'E:\generated.mp4',
    output: r'E:\new.mp4',
    format: VideoFormat.feed,
    plan: CutPlan(
      takeId: 'generated',
      language: ScriptLanguage.ar,
      sourceDuration: const Duration(seconds: 4),
      ranges: [
        SourceRange(
          start: const Duration(seconds: 3),
          end: const Duration(seconds: 4),
        ),
        SourceRange(
          start: const Duration(seconds: 1),
          end: const Duration(seconds: 2),
        ),
      ],
    ),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WindowsVideoRenderer.channel, null),
  );
  test('sound join option is clock-neutral and only applies to real joins', () {
    VideoRenderRequest build(CutPlan plan, bool soft) => VideoRenderRequest(
      source: request.source,
      output: request.output,
      format: request.format,
      plan: plan,
      softAudioJoins: soft,
    );
    expect(build(request.plan, true).toJson()['audioJoinFadeUs'], 20000);
    expect(build(request.plan, false).toJson()['audioJoinFadeUs'], 0);
    expect(build(request.plan, true).plan.toJson(), request.plan.toJson());
    final continuous = CutPlan(
      takeId: 'generated',
      language: ScriptLanguage.en,
      sourceDuration: const Duration(seconds: 4),
      ranges: [
        SourceRange(start: Duration.zero, end: const Duration(seconds: 2)),
        SourceRange(
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 4),
        ),
      ],
    );
    expect(build(continuous, true).toJson()['audioJoinFadeUs'], 0);
  });
  test('sound join history is additive and rejects malformed choices', () {
    final video = VideoExport(
      id: 'generated',
      format: request.format,
      duration: const Duration(seconds: 2),
      createdAt: DateTime(2026),
      softAudioJoins: true,
    );
    expect(VideoExport.fromJson(video.toJson()).softAudioJoins, isTrue);
    expect(
      VideoExport.fromJson(video.toJson()..remove('softAudioJoins'))
          .softAudioJoins,
      isFalse,
    );
    expect(
      () => VideoExport.fromJson(video.toJson()..['softAudioJoins'] = 20000),
      throwsFormatException,
    );
  });
  for (final language in ScriptLanguage.values) {
    test(
      'caption channel uses complete actual wording and output clock $language',
      () {
        final text = switch (language) {
          ScriptLanguage.en => 'Hello everyone.',
          ScriptLanguage.fr => 'Bonjour à tous.',
          ScriptLanguage.ar => 'مرحبا بكم.',
        };
        final rendered = VideoRenderRequest(
          source: request.source,
          output: request.output,
          format: VideoFormat.portrait,
          plan: CutPlan(
            takeId: 'generated',
            language: language,
            sourceDuration: request.plan.sourceDuration,
            ranges: request.plan.ranges,
          ),
          captions: [
            Caption(
              text,
              const Duration(milliseconds: 100),
              const Duration(milliseconds: 900),
            ),
          ],
        );
        final json = rendered.toJson();
        expect(json['captions'], [
          {'text': text, 'startUs': 100000, 'endUs': 900000},
        ]);
        expect((json['captionLayout']! as Map)['rtl'], language.isRtl);
        expect(
          () => rendered.captions.add(
            Caption(text, Duration.zero, const Duration(seconds: 1)),
          ),
          throwsUnsupportedError,
        );
      },
    );
  }
  test(
    'caption input rejects overlaps, missing words and invalid output clock',
    () {
      VideoRenderRequest build(List<Caption> captions) => VideoRenderRequest(
        source: request.source,
        output: request.output,
        format: request.format,
        plan: request.plan,
        captions: captions,
      );
      for (final invalid in [
        [const Caption('Hello', Duration(seconds: -1), Duration(seconds: 1))],
        [const Caption('', Duration.zero, Duration(seconds: 1))],
        [const Caption('Hello\u0000', Duration.zero, Duration(seconds: 1))],
        [const Caption('Hello', Duration.zero, Duration(seconds: 3))],
        [
          const Caption('Hello', Duration.zero, Duration(seconds: 1)),
          const Caption(
            'World',
            Duration(milliseconds: 500),
            Duration(seconds: 2),
          ),
        ],
      ]) {
        expect(() => build(invalid), throwsFormatException);
      }
      expect(build([]).toJson().containsKey('captionLayout'), isFalse);
      final old = VideoExport(
        id: 'generated',
        format: request.format,
        duration: const Duration(seconds: 2),
        createdAt: DateTime(2026),
      );
      final json = old.toJson()..remove('burnedCaptions');
      expect(VideoExport.fromJson(json).burnedCaptions, isFalse);
      expect(
        () => VideoExport(
          id: 'generated',
          format: request.format,
          duration: const Duration(seconds: 2),
          createdAt: DateTime(2026),
          burnedCaptions: true,
        ),
        throwsArgumentError,
      );
    },
  );
  test('serializes kept order and checks complete progress', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WindowsVideoRenderer.channel, (call) async {
          calls.add(call);
          return call.method == 'start'
              ? 4
              : {'state': 'ready', 'progress': 1.0};
        });
    final progress = <double>[];
    await WindowsVideoRenderer().render(request, progress.add);
    expect(calls.first.arguments['ranges'], [
      {'startUs': 3000000, 'endUs': 4000000},
      {'startUs': 1000000, 'endUs': 2000000},
    ]);
    expect(calls.first.arguments['width'], 1080);
    expect(calls.first.arguments['height'], 1350);
    expect(progress, [1]);
  });
  test('cancel before start reply still reaches the owned job', () async {
    final started = Completer<void>(), reply = Completer<int>();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WindowsVideoRenderer.channel, (call) async {
          calls.add(call);
          if (call.method == 'start') {
            started.complete();
            return reply.future;
          }
          if (call.method == 'status') {
            return {'state': 'cancelled', 'progress': 0.0};
          }
          return null;
        });
    final renderer = WindowsVideoRenderer();
    final pending = renderer.render(request, (_) {});
    final rejected = expectLater(pending, throwsA(isA<RenderCancelled>()));
    await started.future;
    await renderer.cancel();
    reply.complete(4);
    await rejected;
    expect(
      calls.where((c) => c.method == 'cancel').first.arguments['sessionId'],
      4,
    );
  });
  test(
    'invalid native progress cancels instead of claiming a finished video',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WindowsVideoRenderer.channel, (call) async {
            calls.add(call);
            return call.method == 'start'
                ? 4
                : {'state': 'ready', 'progress': double.nan};
          });
      await expectLater(
        WindowsVideoRenderer().render(request, (_) {}),
        throwsFormatException,
      );
      expect(calls.last.method, 'cancel');
    },
  );
}
