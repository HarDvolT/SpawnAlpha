import 'claude_markup_engine.dart';
import 'local_markup_engine.dart';
import 'markup_engine.dart';
import 'openai_compatible_engine.dart';

/// The protocol a provider speaks.
enum ProviderApi {
  /// The on-device rules; no network.
  none,

  /// Anthropic's Messages API.
  anthropic,

  /// OpenAI's Chat Completions API, which most other providers and local
  /// servers also speak.
  openAiCompatible,
}

/// The engines the user can pick in Settings. Each preset fills in the
/// server address; the user adds a key where one is needed and picks a
/// model.
enum MarkupProvider {
  onDevice(
    label: 'On-device',
    description: 'Free and works offline. Rule-based, so simpler than an AI model.',
    api: ProviderApi.none,
  ),
  claude(
    label: 'Claude',
    description: 'Anthropic. Your script is sent to Anthropic.',
    api: ProviderApi.anthropic,
    defaultBaseUrl: ClaudeMarkupEngine.defaultBaseUrl,
    defaultModel: ClaudeMarkupEngine.defaultModel,
    keyUrl: 'console.anthropic.com',
  ),
  openAi(
    label: 'OpenAI',
    description: 'Your script is sent to OpenAI.',
    api: ProviderApi.openAiCompatible,
    defaultBaseUrl: 'https://api.openai.com/v1',
    keyUrl: 'platform.openai.com',
  ),
  gemini(
    label: 'Google Gemini',
    description: 'Your script is sent to Google.',
    api: ProviderApi.openAiCompatible,
    defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    keyUrl: 'aistudio.google.com',
  ),
  mistral(
    label: 'Mistral',
    description: 'Your script is sent to Mistral AI.',
    api: ProviderApi.openAiCompatible,
    defaultBaseUrl: 'https://api.mistral.ai/v1',
    keyUrl: 'console.mistral.ai',
  ),
  ollama(
    label: 'Ollama',
    description: 'A model running on your own computer. Nothing leaves your network.',
    api: ProviderApi.openAiCompatible,
    defaultBaseUrl: 'http://localhost:11434/v1',
    needsKey: false,
    isLocal: true,
  ),
  lmStudio(
    label: 'LM Studio',
    description: 'A model running on your own computer. Nothing leaves your network.',
    api: ProviderApi.openAiCompatible,
    defaultBaseUrl: 'http://localhost:1234/v1',
    needsKey: false,
    isLocal: true,
  ),
  custom(
    label: 'Other (OpenAI-compatible)',
    description: 'Any server that speaks the OpenAI API: OpenRouter, Groq, DeepSeek, llama.cpp, vLLM…',
    api: ProviderApi.openAiCompatible,
    needsKey: false,
  );

  const MarkupProvider({
    required this.label,
    required this.description,
    required this.api,
    this.defaultBaseUrl = '',
    this.defaultModel = '',
    this.needsKey = true,
    this.isLocal = false,
    this.keyUrl,
  });

  final String label;
  final String description;
  final ProviderApi api;
  final String defaultBaseUrl;
  final String defaultModel;

  /// Whether the provider refuses requests without an API key. For local
  /// and custom servers a key is optional.
  final bool needsKey;

  /// Runs on the user's own machine or network.
  final bool isLocal;

  /// Where to get a key, shown in Settings.
  final String? keyUrl;

  bool get isRemote => api != ProviderApi.none;

  static MarkupProvider fromName(String? name) => switch (name) {
        // Settings written before providers existed.
        'local' => MarkupProvider.onDevice,
        _ => MarkupProvider.values.firstWhere((p) => p.name == name, orElse: () => MarkupProvider.onDevice),
      };
}

/// The user's choices for one provider.
class ProviderConfig {
  const ProviderConfig({required this.baseUrl, required this.model});

  factory ProviderConfig.defaults(MarkupProvider provider) =>
      ProviderConfig(baseUrl: provider.defaultBaseUrl, model: provider.defaultModel);

  final String baseUrl;
  final String model;

  ProviderConfig copyWith({String? baseUrl, String? model}) =>
      ProviderConfig(baseUrl: baseUrl ?? this.baseUrl, model: model ?? this.model);

  Map<String, Object?> toJson() => {'baseUrl': baseUrl, 'model': model};

  static ProviderConfig fromJson(MarkupProvider provider, Object? json) {
    final defaults = ProviderConfig.defaults(provider);
    if (json is! Map) return defaults;
    final baseUrl = json['baseUrl'];
    final model = json['model'];
    return ProviderConfig(
      baseUrl: baseUrl is String && baseUrl.trim().isNotEmpty ? baseUrl.trim() : defaults.baseUrl,
      model: model is String ? model.trim() : defaults.model,
    );
  }
}

/// Why [provider] can't run yet with [config] and [apiKey], or null when
/// it can.
String? setupProblem(MarkupProvider provider, ProviderConfig config, String? apiKey) {
  if (!provider.isRemote) return null;
  final url = Uri.tryParse(config.baseUrl.trim());
  if (config.baseUrl.trim().isEmpty || url == null || !url.hasScheme || url.host.isEmpty) {
    return 'Enter the server address for ${provider.label}.';
  }
  if (provider.needsKey && (apiKey ?? '').trim().isEmpty) return 'Add your ${provider.label} API key.';
  if (config.model.trim().isEmpty) return 'Choose a model for ${provider.label}.';
  return null;
}

/// The engine for [provider]. Remote engines must be closed after use.
MarkupEngine buildEngine(
  MarkupProvider provider,
  ProviderConfig config,
  String? apiKey, {
  void Function(int received)? onProgress,
}) =>
    switch (provider.api) {
      ProviderApi.none => const LocalMarkupEngine(),
      ProviderApi.anthropic => ClaudeMarkupEngine(
          apiKey: apiKey ?? '',
          model: config.model.trim(),
          baseUrl: config.baseUrl.trim(),
          onProgress: onProgress,
        ),
      ProviderApi.openAiCompatible => OpenAiCompatibleEngine(
          // A custom server is best named by its address.
          name: provider == MarkupProvider.custom
              ? (Uri.tryParse(config.baseUrl.trim())?.host ?? 'The server')
              : provider.label,
          baseUrl: config.baseUrl.trim(),
          model: config.model.trim(),
          apiKey: apiKey?.trim(),
          isLocal: provider.isLocal || _isLocalAddress(config.baseUrl),
          onProgress: onProgress,
        ),
    };

/// Addresses on this machine or the local network, which may be slow to
/// answer while a model loads.
bool _isLocalAddress(String baseUrl) {
  final host = Uri.tryParse(baseUrl.trim())?.host ?? '';
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '10.0.2.2' ||
      host.endsWith('.local') ||
      RegExp(r'^(10|192\.168|172\.(1[6-9]|2\d|3[01]))\.').hasMatch(host);
}
