import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/theme/theme.dart';
import 'package:spawnalpha/src/ui/recording_widgets.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child, {bool reduceMotion = false}) => tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
              child: Center(child: child),
            ),
          ),
        ),
      );

  double widthAxis(WidgetTester tester, String text) {
    final style = tester.widget<Text>(find.text(text)).style!;
    return style.fontVariations!.firstWhere((v) => v.axis == 'wdth').value;
  }

  testWidgets('a countdown numeral lands wide and settles to normal width', (tester) async {
    await pump(tester, const CountdownNumeral(value: 3));
    expect(widthAxis(tester, '3'), closeTo(150, 1));
    await tester.pump(const Duration(milliseconds: 900));
    expect(widthAxis(tester, '3'), closeTo(100, 2));
    expect(tester.widget<Text>(find.text('3')).style!.fontFamily, SaFonts.display);

    // The next beat lands again.
    await pump(tester, const CountdownNumeral(value: 2));
    await tester.pump();
    expect(widthAxis(tester, '2'), greaterThan(140));
  });

  testWidgets('with reduced motion the numeral swaps without scaling', (tester) async {
    await pump(tester, const CountdownNumeral(value: 3), reduceMotion: true);
    expect(widthAxis(tester, '3'), 100);
    expect(tester.widget<Transform>(find.byType(Transform)).transform.getMaxScaleOnAxis(), 1);
  });

  testWidgets('the record button morphs while recording and reports taps', (tester) async {
    var taps = 0;
    Future<void> button({required bool recording}) =>
        pump(tester, RecordButton(recording: recording, saving: false, enabled: true, onPressed: () => taps++));
    Size disc() => tester.getSize(find.byType(AnimatedContainer));

    await button(recording: false);
    expect(disc(), const Size(56, 56));
    await tester.tap(find.byType(RecordButton));
    expect(taps, 1);

    await button(recording: true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(disc(), const Size(26, 26));
    expect(find.bySemanticsLabel('Stop recording'), findsOneWidget);
  });

  testWidgets('the timecode shows the running time in the signal face', (tester) async {
    await pump(tester, const TimecodePill(elapsed: Duration(seconds: 83), recording: true));
    final text = tester.widget<Text>(find.text('1:23'));
    expect(text.style!.fontFamily, SaFonts.signal);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });
}
