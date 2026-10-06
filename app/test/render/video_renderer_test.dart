import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/cut_plan.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/model/video_export.dart';
import 'package:spawnalpha/src/render/video_renderer.dart';

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
