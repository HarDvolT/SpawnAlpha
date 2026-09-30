import 'package:flutter/material.dart';

import '../app.dart';
import '../markup/claude_markup_engine.dart';
import '../model/coaching_style.dart';
import '../storage/settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _key = TextEditingController();
  final _model = TextEditingController();
  bool _showKey = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final settings = AppScope.of(context).settings;
    _key.text = settings.apiKey ?? '';
    _model.text = settings.claudeModel;
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Text('Markup', style: theme.textTheme.titleMedium),
              RadioGroup<MarkupSource>(
                groupValue: settings.markupSource,
                onChanged: (v) {
                  if (v != null) settings.update((s) => s.markupSource = v);
                },
                child: Column(children: [
                  for (final source in MarkupSource.values)
                    RadioListTile<MarkupSource>(
                      value: source,
                      title: Text(source.label),
                      subtitle: Text(source.description),
                    ),
                ]),
              ),
              if (settings.markupSource == MarkupSource.claude) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _key,
                  obscureText: !_showKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Claude API key',
                    helperText: 'Kept in the system keychain on this device. Get one at console.anthropic.com.',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _showKey ? 'Hide' : 'Show',
                      icon: Icon(_showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _showKey = !_showKey),
                    ),
                  ),
                  onSubmitted: settings.setApiKey,
                ),
                const SizedBox(height: 8),
                Row(children: [
                  FilledButton(
                    onPressed: () async {
                      await settings.setApiKey(_key.text);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(settings.hasApiKey ? 'Key saved.' : 'Key removed.')));
                      }
                    },
                    child: const Text('Save key'),
                  ),
                  const SizedBox(width: 8),
                  if (settings.hasApiKey)
                    TextButton(
                      onPressed: () {
                        _key.clear();
                        settings.setApiKey(null);
                      },
                      child: const Text('Remove key'),
                    ),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: _model,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    helperText: 'Default: ${ClaudeMarkupEngine.defaultModel}',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => settings.update(
                    (s) => s.claudeModel = v.trim().isEmpty ? ClaudeMarkupEngine.defaultModel : v.trim(),
                  ),
                ),
              ],
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
            ]),
          ),
        ),
      ),
    );
  }
}
