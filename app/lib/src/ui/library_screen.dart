import 'package:flutter/material.dart';

import '../app.dart';
import '../model/samples.dart';
import '../model/script_document.dart';
import '../theme/theme.dart';
import 'components.dart';
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
        title: Text('Scripts', style: Theme.of(context).textTheme.headlineMedium),
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
        icon: const Icon(Icons.add_rounded),
        label: const Text('New script'),
      ),
      body: ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final scripts = library.scripts;
          if (scripts.isEmpty) return const _EmptyLibrary();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(SaSpace.s4, SaSpace.s2, SaSpace.s4, 96),
            itemCount: scripts.length,
            separatorBuilder: (_, _) => const SizedBox(height: SaSpace.s2),
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
        leading: IconWell(styleIcon(script.style)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (pending > 0)
            Tooltip(message: '$pending suggested marks to review', child: CueCount(pending)),
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
    final p = SaTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SaSpace.s6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // The brand square and the screen's one display-face line.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: p.cue, borderRadius: BorderRadius.circular(SaRadius.xs)),
            ),
            const SizedBox(height: SaSpace.s5),
            Text('Say it like you mean it.', style: theme.textTheme.displaySmall),
            const SizedBox(height: SaSpace.s3),
            Text(
              'Write a script and the director marks it up: pauses, stress, pace and energy, '
              'shown on the prompter while you record.',
              style: theme.textTheme.bodyLarge!.copyWith(color: p.ink2),
            ),
            const SizedBox(height: SaSpace.s5),
            OutlinedButton.icon(
              onPressed: () async {
                final library = AppScope.of(context).library;
                for (final s in sampleScripts().reversed) {
                  await library.save(s);
                }
              },
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              label: const Text('Add sample scripts (English, French, Arabic)'),
            ),
          ]),
        ),
      ),
    );
  }
}
