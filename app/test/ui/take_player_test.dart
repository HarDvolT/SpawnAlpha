import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/model/script_language.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/take_player.dart';

import '../playback/playback_controller_test.dart' show FakePlayback;

void main() {
  for (final language in ScriptLanguage.values) {
    testWidgets('player controls and closure $language', (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = FakePlayback();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Directionality(
              textDirection: language.isRtl
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: TakePlayer(backend: fake, path: 'generated'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fake.commands, isEmpty);
      await tester.tap(find.byTooltip('Play video'));
      await tester.pump();
      expect(fake.commands, ['play']);
      await tester.tap(find.byTooltip('Mute video'));
      await tester.pump();
      expect(fake.commands.last, 'mute:true');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(fake.closed.length, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
