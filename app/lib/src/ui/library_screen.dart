import 'package:flutter/material.dart';

import '../app.dart';
import '../model/samples.dart';
import '../model/script_document.dart';
import 'editor_screen.dart';
import 'format.dart';
import 'settings_screen.dart';

/// The list of scripts.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final library = services.library;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scripts'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(
          context,
          ScriptDocument.create(style: services.settings.defaultStyle),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New script'),
      ),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final scripts = library.scripts;
          if (scripts.isEmpty) return const _EmptyLibrary();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: scripts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (context, i) => _ScriptTile(script: scripts[i]),
          );
        },
      ),
    );
  }

  static void _open(BuildContext context, ScriptDocument script) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EditorScreen(script: script)));
  }
}

class _ScriptTile extends StatelessWidget {
  const _ScriptTile({required this.script});

  final ScriptDocument script;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = script.pendingCount;
    final details = [
      script.style.label,
      // Isolate the language name so Arabic doesn't reorder its neighbours.
      '\u2068${script.language.label}\u2069',
      '${script.wordCount} words',
      '~${formatDuration(estimatedDuration(script))}',
      if (script.takes.isNotEmpty) '${script.takes.length} take${script.takes.length == 1 ? '' : 's'}',
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: Text(
          script.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: script.language.isRtl && script.title.isEmpty ? TextDirection.rtl : null,
        ),
        subtitle: Text(details),
        leading: CircleAvatar(child: Icon(styleIcon(script.style))),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (pending > 0)
            Tooltip(
              message: '$pending suggested marks to review',
              child: Badge(label: Text('$pending'), backgroundColor: theme.colorScheme.tertiary),
            ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value != 'delete') return;
              final confirmed = await confirm(
                context,
                title: 'Delete this script?',
                message: '"${script.displayTitle}" and its marks will be deleted. Recordings stay on disk.',
                action: 'Delete',
              );
              if (confirmed && context.mounted) await AppScope.of(context).library.delete(script.id);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete'))],
          ),
        ]),
        onTap: () => LibraryScreen._open(context, script),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.record_voice_over_outlined, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Write a script and let the coach mark it up', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Pauses, stress, pace and energy cues show on the prompter while you record.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () async {
              final library = AppScope.of(context).library;
              for (final s in sampleScripts().reversed) {
                await library.save(s);
              }
            },
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Add sample scripts (English, French, Arabic)'),
          ),
        ]),
      ),
    );
  }
}
