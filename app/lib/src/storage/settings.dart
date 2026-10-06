import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../markup/markup_engine.dart';
import '../markup/providers.dart';
import '../model/coaching_style.dart';
import '../model/script_document.dart';
import '../prompter/guide.dart';

/// Somewhere to keep API keys out of plain files: the Keychain on iOS, the
/// Keystore on Android and the Credential Manager on Windows.
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
  Future<void> write(String key, String? value) => value == null
      ? _storage.delete(key: key)
      : _storage.write(key: key, value: value);
}

class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null ? values.remove(key) : values[key] = value;
}

/// The user's preferences. Plain settings go in a JSON file; API keys go
/// in the [SecretStore], one per provider.
class Settings extends ChangeNotifier {
  Settings({this._file, this._secrets = const PlatformSecretStore()});

  final File? _file;
  final SecretStore _secrets;

  /// The engine that marks up scripts.
  MarkupProvider provider = MarkupProvider.onDevice;
  final Map<MarkupProvider, ProviderConfig> _configs = {};
  final Map<MarkupProvider, String> _keys = {};

  CoachingStyle defaultStyle = CoachingStyle.presentation;
  double fontSize = 44;
  bool mirror = false;
  TakeMode recordMode = TakeMode.camera;
  bool processAfterStop = true;

  /// Null until the first camera companion choice; no cursor data is stored.
  bool? companionCameraFollow;

  /// Kinetic text on the prompter (words wake up near the reading line);
  /// off is Still. Reduced motion forces Still whatever this says.
  bool kinetic = true;

  /// How the prompter shows the word to say: a bouncing dot, an underline,
  /// a spotlight, or nothing but the reading line.
  PrompterGuide guide = PrompterGuide.dot;

  /// How the prompter moves between holds. The owner chose One phrase.
  PrompterMotion motion = PrompterMotion.phrase;

  /// Center is the starting choice. Null retains automatic language alignment.
  PrompterAlignment? alignment = PrompterAlignment.center;

  /// The microphone takes record from (Windows endpoint ID); null for the
  /// system default.
  String? audioInputId;

  static String _keyName(MarkupProvider p) => 'api_key_${p.name}';

  ProviderConfig configOf(MarkupProvider p) =>
      _configs[p] ?? ProviderConfig.defaults(p);

  String? apiKeyOf(MarkupProvider p) => _keys[p];

  bool hasApiKey(MarkupProvider p) => (_keys[p] ?? '').isNotEmpty;

  /// Why the chosen provider can't run yet, or null when it can.
  String? get setupProblemForProvider =>
      setupProblem(provider, configOf(provider), apiKeyOf(provider));

  /// The engine to mark up with: the chosen provider when it is set up,
  /// else the on-device rules. Remote engines must be closed after use.
  MarkupEngine engine({
    MarkupProvider? use,
    void Function(int received)? onProgress,
  }) {
    final p = use ?? provider;
    if (setupProblem(p, configOf(p), apiKeyOf(p)) != null) {
      return buildEngine(MarkupProvider.onDevice, configOf(p), null);
    }
    return buildEngine(p, configOf(p), apiKeyOf(p), onProgress: onProgress);
  }

  /// The engine for [p] as configured, for listing models in Settings even
  /// before a model is chosen. Null for the on-device engine.
  RemoteMarkupEngine? remoteEngine(MarkupProvider p) {
    if (!p.isRemote) return null;
    final config = configOf(p);
    // A placeholder model lets the engine be built; listing ignores it.
    final engine = buildEngine(
      p,
      config.model.isEmpty ? config.copyWith(model: '-') : config,
      apiKeyOf(p),
    );
    return engine is RemoteMarkupEngine ? engine : null;
  }

  Future<void> load() async {
    final file = _file;
    if (file != null && await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString());
        if (json is Map<String, Object?>) _read(json);
      } on FormatException {
        // Preserve unreadable settings without logging private stored text.
      }
    }
    for (final p in MarkupProvider.values.where((p) => p.isRemote)) {
      try {
        var key = await _secrets.read(_keyName(p));
        // Before providers existed, the Claude key had its own name.
        if ((key ?? '').isEmpty && p == MarkupProvider.claude) {
          key = await _secrets.read('anthropic_api_key');
        }
        if (key != null && key.isNotEmpty) _keys[p] = key;
      } on Object {
        // Secure-storage errors may contain private diagnostics.
      }
    }
    notifyListeners();
  }

  void _read(Map<String, Object?> json) {
    processAfterStop = json['processAfterStop'] is bool
        ? json['processAfterStop']! as bool
        : true;
    companionCameraFollow = json['companionCameraFollow'] is bool
        ? json['companionCameraFollow'] as bool
        : null;
    provider = MarkupProvider.fromName(
      (json['markupProvider'] ?? json['markupSource']) as String?,
    );
    final providers = json['providers'];
    if (providers is Map) {
      for (final p in MarkupProvider.values.where((p) => p.isRemote)) {
        if (providers.containsKey(p.name)) {
          _configs[p] = ProviderConfig.fromJson(p, providers[p.name]);
        }
      }
    }
    // Settings written before providers existed kept only a Claude model.
    final claudeModel = json['claudeModel'];
    if (claudeModel is String && !_configs.containsKey(MarkupProvider.claude)) {
      _configs[MarkupProvider.claude] = configOf(MarkupProvider.claude)
          .copyWith(model: claudeModel);
    }
    defaultStyle = CoachingStyle.fromName(json['defaultStyle'] as String?);
    fontSize = (json['fontSize'] as num?)?.toDouble() ?? fontSize;
    mirror = json['mirror'] as bool? ?? mirror;
    kinetic = json['kinetic'] as bool? ?? kinetic;
    guide = PrompterGuide.fromName(json['guide'] as String?);
    if (json.containsKey('motion')) {
      motion = PrompterMotion.fromName(json['motion'] as String?);
    }
    if (json.containsKey('alignment')) {
      alignment = PrompterAlignment.fromName(json['alignment'] as String?);
    }
    audioInputId = json['audioInputId'] as String?;
    recordMode =
        TakeMode.values
            .where((v) => v.name == json['recordMode'])
            .firstOrNull ??
        TakeMode.camera;
  }

  Map<String, Object?> toJson() => {
    'markupProvider': provider.name,
    'providers': {
      for (final e in _configs.entries) e.key.name: e.value.toJson(),
    },
    'defaultStyle': defaultStyle.name,
    'fontSize': fontSize,
    'mirror': mirror,
    'recordMode': recordMode.name,
    'processAfterStop': processAfterStop,
    if (companionCameraFollow != null)
      'companionCameraFollow': companionCameraFollow,
    'kinetic': kinetic,
    'guide': guide.name,
    'motion': motion.name,
    if (alignment != null) 'alignment': alignment!.name,
    if (audioInputId != null) 'audioInputId': audioInputId,
  };

  Future<void> update(void Function(Settings s) change) async {
    change(this);
    notifyListeners();
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(toJson()));
  }

  Future<void> setConfig(MarkupProvider p, ProviderConfig config) =>
      update((s) => s._configs[p] = config);

  Future<void> setApiKey(MarkupProvider p, String? key) async {
    final trimmed = key?.trim() ?? '';
    if (trimmed.isEmpty) {
      _keys.remove(p);
    } else {
      _keys[p] = trimmed;
    }
    notifyListeners();
    await _secrets.write(_keyName(p), trimmed.isEmpty ? null : trimmed);
  }
}
