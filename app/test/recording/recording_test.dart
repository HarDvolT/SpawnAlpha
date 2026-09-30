import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/prompter/voice_activity.dart';
import 'package:spawnalpha/src/recording/audio_input.dart';
import 'package:spawnalpha/src/recording/mp4.dart';

Uint8List box(String type, List<int> body) {
  final size = 8 + body.length;
  return Uint8List.fromList([
    (size >> 24) & 0xff, (size >> 16) & 0xff, (size >> 8) & 0xff, size & 0xff,
    ...type.codeUnits,
    ...body,
  ]);
}

Uint8List track(String handler) => box('trak', box('mdia', box('hdlr', [0, 0, 0, 0, 0, 0, 0, 0, ...handler.codeUnits, 0, 0, 0, 0])));

void main() {
  group('voice activity', () {
    const frame = Duration(milliseconds: 50);
    bool feed(VoiceActivity v, double db, int frames) {
      var speaking = false;
      for (var i = 0; i < frames; i++) {
        speaking = v.update(db, frame);
      }
      return speaking;
    }

    test('hears speech over a quiet room, and ignores the room', () {
      final v = VoiceActivity();
      expect(feed(v, -65, 40), isFalse, reason: 'two seconds of room noise');
      expect(feed(v, -30, 3), isTrue, reason: 'speech well above the floor');
      expect(feed(v, -65, 2), isTrue, reason: 'a short gap between words keeps going');
      expect(feed(v, -65, 10), isFalse, reason: 'a real pause stops it');
    });

    test('adapts to a noisy room', () {
      final v = VoiceActivity();
      expect(feed(v, -40, 200), isFalse, reason: 'ten seconds of steady fan noise becomes the floor');
      expect(v.floorDb, greaterThan(-45));
      expect(feed(v, -22, 3), isTrue, reason: 'a voice above the fan');
    });

    test('long speech does not turn into the floor', () {
      final v = VoiceActivity();
      feed(v, -65, 20);
      // Eight seconds of speech with brief dips between words.
      var speaking = true;
      for (var i = 0; i < 40; i++) {
        speaking = feed(v, -28, 3) && speaking;
        feed(v, -60, 1);
      }
      expect(speaking, isTrue);
    });
  });

  group('mp4 sound check', () {
    test('finds a sound track, or its absence', () {
      expect(moovHasAudioTrack(Uint8List.fromList([...track('vide'), ...track('soun')])), isTrue);
      expect(moovHasAudioTrack(track('vide')), isFalse);
      expect(moovHasAudioTrack(Uint8List(0)), isFalse);
    });

    test('reads a file with the movie box after the media', () async {
      final dir = await Directory.systemTemp.createTemp('mp4');
      addTearDown(() => dir.delete(recursive: true));
      final withSound = File('${dir.path}/a.mp4')
        ..writeAsBytesSync([...box('ftyp', 'isom'.codeUnits), ...box('mdat', List.filled(1000, 7)), ...box('moov', [...track('vide'), ...track('soun')])]);
      final silent = File('${dir.path}/b.mp4')
        ..writeAsBytesSync([...box('ftyp', 'isom'.codeUnits), ...box('moov', track('vide')), ...box('mdat', List.filled(10, 7))]);
      final junk = File('${dir.path}/c.mp4')..writeAsBytesSync([1, 2, 3]);
      expect(await mp4HasAudioTrack(withSound), isTrue);
      expect(await mp4HasAudioTrack(silent), isFalse);
      expect(await mp4HasAudioTrack(junk), isNull);
    });
  });

  test('the meter maps -60 to 0 dBFS onto empty to full', () {
    expect(const MicLevel(peakDb: -100, rmsDb: -100).meter, 0);
    expect(const MicLevel(peakDb: -30, rmsDb: -40).meter, closeTo(0.5, 0.001));
    expect(const MicLevel(peakDb: 3, rmsDb: 0).meter, 1);
  });
}
