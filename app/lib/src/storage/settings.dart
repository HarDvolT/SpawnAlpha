import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../markup/claude_markup_engine.dart';
import '../model/coaching_style.dart';

/// Which engine marks up scripts.
enum MarkupSource {
  /// Rule-based, on the device. Free and offline.
  local('On-device', 'Free and works offline'),

  /// Claude, with the user's own API key, until the subscription exists.
  claude('Claude (cloud)', 'Better markup and rewrite suggestions; needs an API key');

  const MarkupSource(this.label, this.description);

  final String label;
  final String description;

  static MarkupSource fromName(String? name) =>
      MarkupSource.values.firstWhere((s) => s.name == name, orElse: () => MarkupSource.local);
}

/// Somewhere to keep the API key out of plain files: the Keychain on iOS,
/// the Keystore on Android and the Credential Manager on Windows.
abstract interface class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String? value);
}

class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String? value) =>
      value == null ? _storage.delete(key: key) : _storage.write(key: key, value: value);
}

class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;
}

/// The user's preferences. Plain settings go in a JSON file; the API key
/// goes in the [SecretStore].
class Settings extends ChangeNotifier {
  Settings({this._file, this._secrets = const PlatformSecretStore()});

  static const _apiKeyName = 'anthropic_api_key';

  final File? _file;
  final SecretStore _secrets;

  MarkupSource markupSource = MarkupSource.local;
  String claudeModel = ClaudeMarkupEngine.defaultModel;
  CoachingStyle defaultStyle = CoachingStyle.presentation;
  double fontSize = 44;
  bool mirror = false;
  String? _apiKey;

  String? get apiKey => _apiKey;
  bool get hasApiKey => (_apiKey ?? '').isNotEmpty;

  /// True when the cloud engine is chosen and can run.
  bool get useClaude => markupSource == MarkupSource.claude && hasApiKey;

  Future<void> load() async {
    final file = _file;
    if (file != null && await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString());
        if (json is Map<String, Object?>) {
          markupSource = MarkupSource.fromName(json['markupSource'] as String?);
          claudeModel = json['claudeModel'] as String? ?? claudeModel;
          defaultStyle = CoachingStyle.fromName(json['defaultStyle'] as String?);
          fontSize = (json['fontSize'] as num?)?.toDouble() ?? fontSize;
          mirror = json['mirror'] as bool? ?? mirror;
        }
      } on FormatException catch (e) {
        debugPrint('Ignoring unreadable settings: $e');
      }
    }
    try {
      _apiKey = await _secrets.read(_apiKeyName);
    } on Exception catch (e) {
      debugPrint('Could not read the API key: $e');
    }
    notifyListeners();
  }

  Future<void> update(void Function(Settings s) change) async {
    change(this);
    notifyListeners();
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({
      'markupSource': markupSource.name,
      'claudeModel': claudeModel,
      'defaultStyle': defaultStyle.name,
      'fontSize': fontSize,
      'mirror': mirror,
    }));
  }

  Future<void> setApiKey(String? key) async {
    final trimmed = key?.trim();
    _apiKey = (trimmed?.isEmpty ?? true) ? null : trimmed;
    notifyListeners();
    await _secrets.write(_apiKeyName, _apiKey);
  }
}
