import 'package:flutter/material.dart';

import '../model/note_deck.dart';
import '../model/script_document.dart';
import '../theme/theme.dart';
import 'notes_stage.dart';

class NotesPracticeScreen extends StatefulWidget {
  const NotesPracticeScreen({super.key, required this.script});
  final ScriptDocument script;
  @override
  State<NotesPracticeScreen> createState() => _NotesPracticeScreenState();
}

class _NotesPracticeScreenState extends State<NotesPracticeScreen> {
  late final _notes = NoteController(widget.script.notes);
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: SaPalette.dark.stage,
    appBar: AppBar(
      backgroundColor: SaPalette.dark.stageChrome,
      foregroundColor: SaPalette.dark.stageText,
      title: Text(widget.script.displayTitle),
    ),
    body: SafeArea(
      child: NotesStage(controller: _notes, language: widget.script.language),
    ),
  );
}
