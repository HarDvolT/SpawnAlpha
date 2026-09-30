import 'package:flutter/material.dart';

import '../model/mark.dart';
import '../model/mark_editing.dart';
import '../model/script_document.dart';
import '../prompter/marked_text.dart';
import '../theme/theme.dart';

/// The sheet that opens when a word is tapped in the editor: the marks on
/// that word, to accept, change or remove, and buttons to add new ones.
class MarkSheet extends StatefulWidget {
  const MarkSheet({super.key, required this.script, required this.token, required this.onChanged});

  final ScriptDocument script;
  final int token;
  final ValueChanged<ScriptDocument> onChanged;

  @override
  State<MarkSheet> createState() => _MarkSheetState();
}

class _MarkSheetState extends State<MarkSheet> {
  late ScriptDocument _script = widget.script;

  void _apply(ScriptDocument next) {
    setState(() => _script = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = CueColors.forStudio(context);
    final token = widget.token;
    final marks = _script.marksAt(token);
    final direction = _script.language.isRtl ? TextDirection.rtl : TextDirection.ltr;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_script.tokens[token].text, textDirection: direction, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (marks.isEmpty)
            Text('No marks on this word.', style: theme.textTheme.bodyMedium)
          else
            for (final m in marks) _MarkRow(
                mark: m,
                rtl: _script.language.isRtl,
                covered: m.kind.isGap ? null : _script.textOf(m.start, m.end),
                colors: colors,
                direction: direction,
                onAccept: () => _apply(_script.acceptMark(m.id)),
                onRemove: () => _apply(_script.removeMark(m.id)),
                onKind: (k) => _apply(_script.changeMarkKind(m.id, k)),
              ),
          const SizedBox(height: 16),
          Text('Add', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final kind in MarkKind.values)
              ActionChip(
                avatar: Icon(cueIcon(kind), color: colors.of(kind), size: 18),
                label: Text(_addLabel(kind)),
                onPressed: _script.canAddMark(kind, token) ? () => _apply(_script.addMark(kind, token)) : null,
              ),
          ]),
        ]),
      ),
    );
  }

  static String _addLabel(MarkKind kind) => switch (kind) {
        MarkKind.stress => 'Stress this word',
        MarkKind.pauseShort => 'Pause after',
        MarkKind.pauseLong => 'Long pause after',
        MarkKind.breath => 'Breathe after',
        MarkKind.slower => 'Slow down (sentence)',
        MarkKind.faster => 'Speed up (sentence)',
        MarkKind.energy => 'Lift energy (sentence)',
      };
}

class _MarkRow extends StatelessWidget {
  const _MarkRow({
    required this.mark,
    required this.rtl,
    required this.covered,
    required this.colors,
    required this.direction,
    required this.onAccept,
    required this.onRemove,
    required this.onKind,
  });

  final Mark mark;
  final bool rtl;
  final String? covered;
  final CueColors colors;
  final TextDirection direction;
  final VoidCallback onAccept;
  final VoidCallback onRemove;
  final ValueChanged<MarkKind> onKind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = switch (mark.origin) {
      MarkOrigin.rules => 'on-device coach',
      MarkOrigin.ai => 'AI model',
      MarkOrigin.user => 'you',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(cueIcon(mark.kind), color: colors.of(mark.kind)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButton<MarkKind>(
                value: mark.kind,
                underline: const SizedBox.shrink(),
                items: [
                  for (final k in mark.kind.alternatives) DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (k) {
                  if (k != null && k != mark.kind) onKind(k);
                },
              ),
              if (covered != null) Text('“$covered”', textDirection: direction, style: theme.textTheme.bodyMedium),
              // The director's reason, in pencil, as in the script's margin.
              if (mark.note != null)
                Padding(
                  padding: const EdgeInsets.only(top: SaSpace.s1),
                  child: Text(
                    mark.note!,
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    style: (rtl ? SaType.noteAr : SaType.note).copyWith(color: SaTheme.of(context).ink2),
                  ),
                ),
              Text(
                ['from $source', if (!mark.accepted) 'not reviewed'].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ]),
          ),
          if (!mark.accepted)
            IconButton(tooltip: 'Accept', icon: const Icon(Icons.check_rounded), onPressed: onAccept),
          IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline_rounded), onPressed: onRemove),
        ]),
      ),
    );
  }
}
