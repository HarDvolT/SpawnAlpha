import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../markup/markup_engine.dart';
import '../markup/providers.dart';
import '../model/coaching_style.dart';
import '../storage/settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  final _model = TextEditingController();
  MarkupProvider? _loadedFor;
  bool _showKey = false;
  bool _checking = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  /// Fills the fields for [provider] when it changes.
  void _load(Settings settings) {
    final p = settings.provider;
    if (_loadedFor == p) return;
    _loadedFor = p;
    final config = settings.configOf(p);
    _url.text = config.baseUrl;
    _model.text = config.model;
    _key.text = settings.apiKeyOf(p) ?? '';
    _status = null;
  }

  Future<List<String>?> _fetchModels(Settings settings) async {
    final engine = settings.remoteEngine(settings.provider);
    if (engine == null) return null;
    setState(() {
      _checking = true;
      _status = null;
    });
    try {
      final models = await engine.listModels();
      if (!mounted) return null;
      final model = _model.text.trim();
      final missing = model.isNotEmpty && models.isNotEmpty && !models.contains(model);
      setState(() {
        _statusIsError = missing || models.isEmpty;
        _status = models.isEmpty
            ? 'Connected, but the server lists no models. '
                '${settings.provider.isLocal ? 'Download or load a model first.' : ''}'
            : 'Connected. ${models.length} model${models.length == 1 ? '' : 's'} available.'
                '${missing ? ' "$model" is not one of them.' : ''}';
      });
      return models;
    } on MarkupException catch (e) {
      if (mounted) {
        setState(() {
          _statusIsError = true;
          _status = e.message;
        });
      }
      return null;
    } finally {
      engine.close();
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _pickModel(Settings settings) async {
    final models = await _fetchModels(settings);
    if (models == null || models.isEmpty || !mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            for (final m in models)
              ListTile(
                title: Text(m),
                trailing: m == _model.text.trim() ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, m),
              ),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    _model.text = picked;
    await settings.setConfig(settings.provider, settings.configOf(settings.provider).copyWith(model: picked));
    setState(() {
      _status = null;
      _statusIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          _load(settings);
          final provider = settings.provider;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text('Markup', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Which AI marks up your scripts. You can use a cloud model with your own key, '
                  'a model on your own computer, or the free on-device coach.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MarkupProvider>(
                  initialValue: provider,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Markup engine', border: OutlineInputBorder()),
                  items: [
                    for (final p in MarkupProvider.values)
                      DropdownMenuItem(
                        value: p,
                        child: Text(p.isLocal ? '${p.label} (on your computer)' : p.label),
                      ),
                  ],
                  onChanged: (p) {
                    if (p != null) settings.update((s) => s.provider = p);
                  },
                ),
                const SizedBox(height: 8),
                Text(provider.description, style: theme.textTheme.bodySmall),
                if (provider.isRemote) ..._providerFields(settings, provider, theme),
                const Divider(height: 40),
                Text('New scripts', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                DropdownButtonFormField<CoachingStyle>(
                  initialValue: settings.defaultStyle,
                  decoration: const InputDecoration(labelText: 'Default coaching style', border: OutlineInputBorder()),
                  items: [for (final s in CoachingStyle.values) DropdownMenuItem(value: s, child: Text(s.label))],
                  onChanged: (v) {
                    if (v != null) settings.update((s) => s.defaultStyle = v);
                  },
                ),
                const Divider(height: 40),
                Text('Prompter', style: theme.textTheme.titleMedium),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Text size'),
                  subtitle: Slider(
                    value: settings.fontSize,
                    min: 24,
                    max: 96,
                    divisions: 18,
                    label: settings.fontSize.round().toString(),
                    onChanged: (v) => settings.update((s) => s.fontSize = v),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mirror text'),
                  subtitle: const Text('For teleprompter glass that reflects the screen'),
                  value: settings.mirror,
                  onChanged: (v) => settings.update((s) => s.mirror = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Make a cut after recording'),
                  subtitle: const Text('Once offline speech is set up, find words and make a reversible cut after Stop. Your original is kept.'),
                  value: settings.processAfterStop,
                  onChanged: (v) => settings.update((s) => s.processAfterStop = v),
                ),
                const Divider(height: 40),
                Text('Privacy and licences', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Scripts and recordings stay on this device, and API keys are stored securely here and sent only '
                  'to their own provider. A script leaves the device only when you mark it up with an online '
                  'provider: its text goes to that provider, under your agreement with them. The on-device coach '
                  'keeps it here, and a local model (Ollama, LM Studio) keeps it on your own network.',
                  style: theme.textTheme.bodySmall,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Licences'),
                  subtitle: const Text('Fonts, icons and open-source software in this app'),
                  onTap: () => showLicensePage(context: context, applicationName: 'SpawnAlpha'),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _providerFields(Settings settings, MarkupProvider provider, ThemeData theme) {
    final host = Uri.tryParse(_url.text.trim())?.host ?? '';
    final onPhone = Platform.isAndroid || Platform.isIOS;
    final phoneLocalhost = onPhone && (host == 'localhost' || host == '127.0.0.1');
    final urlHelp = switch (provider) {
      MarkupProvider.ollama || MarkupProvider.lmStudio =>
        'Ollama listens on port 11434 and LM Studio on 1234. From a phone, use your computer\'s '
            'address on the same Wi-Fi, such as http://192.168.1.20:11434/v1.',
      MarkupProvider.custom => 'The API root, usually ending in /v1.',
      _ => 'Change this only to go through a proxy.',
    };
    final problem = settings.setupProblemForProvider;

    return [
      const SizedBox(height: 16),
      TextField(
        controller: _url,
        autocorrect: false,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: 'Server address',
          helperText: urlHelp,
          helperMaxLines: 3,
          errorText: phoneLocalhost
              ? 'On a phone, localhost is the phone itself. Use your computer\'s network address.'
              : null,
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
          suffixIcon: _url.text.trim() == provider.defaultBaseUrl || provider.defaultBaseUrl.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Reset to ${provider.defaultBaseUrl}',
                  icon: const Icon(Icons.restart_alt),
                  onPressed: () {
                    _url.text = provider.defaultBaseUrl;
                    settings.setConfig(provider, settings.configOf(provider).copyWith(baseUrl: _url.text));
                  },
                ),
        ),
        onChanged: (v) => settings.setConfig(provider, settings.configOf(provider).copyWith(baseUrl: v.trim())),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _key,
        obscureText: !_showKey,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: provider.needsKey ? '${provider.label} API key' : 'API key (optional)',
          helperText: [
            if (provider.keyUrl != null) 'Get one at ${provider.keyUrl}.',
            if (!provider.needsKey && provider.isLocal) 'Local servers usually need none.',
            'Kept in the system keychain on this device.',
          ].join(' '),
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: _showKey ? 'Hide' : 'Show',
            icon: Icon(_showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _showKey = !_showKey),
          ),
        ),
        onChanged: (v) => settings.setApiKey(provider, v),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _model,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: 'Model',
          helperText: provider.defaultModel.isEmpty
              ? 'Type a model name, or pick one from the server\'s list.'
              : 'Default: ${provider.defaultModel}',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: 'Choose from the server\'s models',
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: _checking ? null : () => _pickModel(settings),
          ),
        ),
        onChanged: (v) => settings.setConfig(provider, settings.configOf(provider).copyWith(model: v.trim())),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton.icon(
          onPressed: _checking ? null : () => _fetchModels(settings),
          icon: _checking
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.wifi_tethering),
          label: const Text('Test connection'),
        ),
        if (problem != null) Text(problem, style: TextStyle(color: theme.colorScheme.error)),
      ]),
      if (_status != null) ...[
        const SizedBox(height: 8),
        Text(
          _status!,
          style: TextStyle(color: _statusIsError ? theme.colorScheme.error : theme.colorScheme.primary),
        ),
      ],
    ];
  }
}
