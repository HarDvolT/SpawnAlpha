import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/screen_source.dart';
import 'package:spawnalpha/src/ui/screen_source_picker.dart';

import '../recording/screen_source_test.dart' show FakeScreenSources, display, window;

void main() {
  for (final name in ['My presentation', 'Présentation française', 'عرض تقديمي']) {
    testWidgets('selects a Unicode window and returns it: $name', (tester) async {
      final backend = FakeScreenSources()..items = [display,
        ScreenSource(id: window.id, name: name, kind: ScreenSourceKind.window, width: 1280, height: 720)];
      ScreenSource? chosen;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () async => chosen = await Navigator.of(context).push<ScreenSource>(MaterialPageRoute(
          builder: (_) => ScreenSourcePicker(sources: backend))), child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Use this source')).onPressed, isNull);
      expect(find.text('DISPLAYS'), findsOneWidget);
      expect(find.text('WINDOWS'), findsOneWidget);
      await tester.tap(find.text(name));
      await tester.pump();
      await tester.tap(find.text('Use this source'));
      await tester.pumpAndSettle();
      expect(chosen!.name, name);
    });
  }

  testWidgets('refresh removes a closed source and explains what to do', (tester) async {
    final backend = FakeScreenSources();
    await tester.pumpWidget(MaterialApp(home: ScreenSourcePicker(sources: backend, selected: window)));
    await tester.pumpAndSettle();
    backend.items = [display];
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no longer available'), findsOneWidget);
    expect(find.text('Open a window, then Refresh.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Use this source')).onPressed, isNull);
  });

  testWidgets('long names fit a narrow window and stay selectable', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final name = List.filled(20, 'Présentation طويلة').join(' ');
    final backend = FakeScreenSources()..items = [ScreenSource(id: window.id, name: name,
      kind: ScreenSourceKind.window, width: 1280, height: 720)];
    await tester.pumpWidget(MaterialApp(home: ScreenSourcePicker(sources: backend)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
