import 'package:flutter_test/flutter_test.dart';
import 'package:spawnalpha/src/recording/camera_identity.dart';

void main() {
  for (final name in ['Chosen camera', 'Caméra choisie', 'الكاميرا المختارة']) {
    test('keeps friendly $name separate from the exact chosen link', () {
      final identity = WindowsCameraIdentity.parse(
        '$name <opaque-device-link>',
      );
      expect(identity.name, name);
      expect(identity.deviceId, 'opaque-device-link');
      expect(
        WindowsCameraIdentity.parse('$name <label> <chosen>').name,
        '$name <label>',
      );
      expect(
        WindowsCameraIdentity.parse('$name <label> <chosen>').deviceId,
        'chosen',
      );
    });
  }
  test('plain and malformed names cannot fall back to a default camera', () {
    for (final value in [
      '',
      'Camera',
      'Camera <>',
      'Camera <link',
      'Camera <bad\u0000link>',
    ]) {
      expect(WindowsCameraIdentity.parse(value).deviceId, isNull);
    }
  });
}
