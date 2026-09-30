import 'package:flutter/material.dart';

import '../app.dart';
import '../model/mark_editing.dart';
import '../model/script_document.dart';
import 'format.dart';
import 'prompter_screen.dart';
import 'record_screen.dart';

enum _PendingChoice { acceptAll, skip }

/// Before going on stage: the prompter shows only accepted marks, so ask
/// once about marks nobody has reviewed. Returns the script to use (with
/// every mark accepted if the user chose that), or null if they cancelled.
Future<ScriptDocument?> reviewBeforeStage(BuildContext context, ScriptDocument script) async {
  if (script.pendingCount == 0) return script;
  final choice = await showDialog<_PendingChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Review the suggested marks?'),
      content: Text(
        '${script.pendingCount} suggested marks have not been reviewed. '
        'The prompter only shows marks you accept.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, _PendingChoice.skip),
          child: const Text('Leave them out'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _PendingChoice.acceptAll),
          child: const Text('Accept all'),
        ),
      ],
    ),
  );
  if (choice == null) return null;
  return choice == _PendingChoice.acceptAll ? script.acceptAllMarks() : script;
}

/// Goes on stage from outside the editor (the Home screen): reviews the
/// marks, saves any it accepted, then opens the record or practice screen.
Future<void> goOnStage(BuildContext context, ScriptDocument script, {required bool record}) async {
  if (script.wordCount == 0) {
    showMessage(context, 'Write or paste a script first.');
    return;
  }
  final library = AppScope.of(context).library;
  final reviewed = await reviewBeforeStage(context, script);
  if (reviewed == null || !context.mounted) return;
  if (!identical(reviewed, script)) await library.save(reviewed);
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (_) => record ? RecordScreen(script: reviewed) : PrompterScreen(script: reviewed),
    fullscreenDialog: true,
  ));
}
