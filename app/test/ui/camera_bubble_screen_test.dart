import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/camera_bubble.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/camera_bubble_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(cameraBubbleViewChannel, null),
  );
  for (final (name, direction) in [
    ('Chosen camera', TextDirection.ltr),
    ('Caméra choisie', TextDirection.ltr),
    ('الكاميرا المختارة', TextDirection.rtl),
  ]) {
    testWidgets('live camera bubble fits and only hides its preview: $name', (
      tester,
    ) async {
      tester.view.physicalSize = Size.square(SaPrompter.cameraBubbleSize);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final methods = <String>[];
      messenger.setMockMethodCallHandler(cameraBubbleViewChannel, (call) async {
        methods.add(call.method);
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: CameraBubbleScreen(
            initial: CameraBubbleState(
              name: name,
              live: true,
              textureId: 9,
              width: 1280,
              height: 720,
            ),
            preview: ColoredBox(color: SaPalette.dark.stageTintSlower),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ClipOval), findsOneWidget);
      expect(tester.widget<Text>(find.text(name)).textDirection, direction);
      expect(find.text('Hidden from recording'), findsOneWidget);
      final fitted = tester.widget<FittedBox>(find.byType(FittedBox));
      expect(fitted.fit, BoxFit.cover);
      await tester.tap(find.byTooltip('Hide camera preview'));
      expect(methods, ['hide']);
      await tester.drag(find.text(name), const Offset(20, 0));
      expect(methods, ['hide', 'drag']);
    });
  }
  testWidgets('before go shows waiting without an old or empty texture', (
    tester,
  ) async {
    tester.view.physicalSize = Size.square(SaPrompter.cameraBubbleSize);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const CameraBubbleScreen(initial: CameraBubbleState()),
      ),
    );
    expect(find.text('Camera starts at go'), findsOneWidget);
    expect(find.byType(Texture), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
