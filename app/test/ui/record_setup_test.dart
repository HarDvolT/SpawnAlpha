import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/mic_monitor.dart';
import 'package:spawnalpha/src/ui/record_setup.dart';

import '../recording/mic_monitor_test.dart';

Widget _host(Widget child) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
      ),
    );

void main() {
  testWidgets('lists every microphone, the default labelled, and switches on tap', (tester) async {
    final mic = MicMonitor(FakeAudioInputs([-30]));
    await mic.start(null);
    String? chosen = 'nothing';
    await tester.pumpWidget(_host(MicList(monitor: mic, onChoose: (id) => chosen = id)));
    expect(find.text('Headset'), findsOneWidget);
    expect(find.text('USB microphone'), findsOneWidget);
    expect(find.text('Windows default'), findsOneWidget);
    await tester.tap(find.text('USB microphone'));
    expect(chosen, 'usb');
    await mic.stop();
    mic.dispose();
  });

  testWidgets('the sound check says what it heard, and names the microphone', (tester) async {
    for (final (state, text) in [
      (SoundCheckState.idle, 'Check your sound.'),
      (SoundCheckState.heard, 'We hear you.'),
      (SoundCheckState.silent, 'Nothing heard'),
    ]) {
      await tester.pumpWidget(_host(SoundCheckRow(state: state, micName: 'Headset', onCheck: () {})));
      expect(find.textContaining(text, findRichText: true), findsOneWidget, reason: '$state');
    }
    expect(find.textContaining('Headset', findRichText: true), findsOneWidget);
  });

  testWidgets('when Windows blocks the microphone, it names the switches and offers the way there', (tester) async {
    var retried = false;
    await tester.pumpWidget(_host(BlockedPanel(onRetry: () => retried = true)));
    expect(find.text('Windows is blocking the microphone'), findsOneWidget);
    expect(find.textContaining('Let desktop apps access your microphone', findRichText: true), findsOneWidget);
    expect(find.text('Open privacy settings'), findsOneWidget);
    await tester.tap(find.text('Check again'));
    expect(retried, isTrue);
  });
}
