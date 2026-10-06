import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../model/note_deck.dart';
import '../model/script_document.dart';
import '../model/script_language.dart';
import '../theme/theme.dart';
import 'editor_screen.dart';
import 'stage_launch.dart';

Widget documentEditor(ScriptDocument document) =>
    document.usesNotes ? NotesEditorScreen(script: document) : EditorScreen(script: document);

Future<void> createDocument(BuildContext context) async {
  final aid = await showDialog<RecordingAid>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('What will help you speak?'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, RecordingAid.script),
          child: const ListTile(
            leading: Icon(Icons.description_outlined),
            title: Text('Script'),
            subtitle: Text('Read a coached script.'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, RecordingAid.notes),
          child: const ListTile(
            leading: Icon(Icons.view_carousel_outlined),
            title: Text('Notes'),
            subtitle: Text('Speak freely from private topic cards.'),
          ),
        ),
      ],
    ),
  );
  if (aid == null || !context.mounted) return;
  final document = ScriptDocument.create(recordingAid: aid, style: AppScope.of(context).settings.defaultStyle);
  await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => documentEditor(document)));
}

class NotesEditorScreen extends StatefulWidget {
  const NotesEditorScreen({super.key, required this.script});
  final ScriptDocument script;
  @override
  State<NotesEditorScreen> createState() => _NotesEditorScreenState();
}

class _NotesEditorScreenState extends State<NotesEditorScreen> {
  late ScriptDocument _document = widget.script.copyWith(
    recordingAid: RecordingAid.notes,
    notes: widget.script.notes.cards.isEmpty ? NoteDeck([NoteCard.create()]) : widget.script.notes,
  );
  late final _title = TextEditingController(text: _document.title);
  int _selected = 0;
  Future<void> _writes = Future<void>.value();
  bool _saving = false;
  String? _problem;

  void _change(ScriptDocument document) {
    setState(() => _document = document);
    _save();
  }

  Future<void> _save() {
    final library = AppScope.of(context).library;
    final snapshot = _document;
    _writes = _writes.then((_) async {
      try {
        // Recording owns its takes; a later text save cannot discard them.
        await library.save(snapshot.copyWith(takes: library.byId(snapshot.id)?.takes ?? snapshot.takes));
        if (mounted && _problem != null) setState(() => _problem = null);
      } on Object {
        if (mounted) {
          setState(() => _problem = 'Notes could not be saved. Try Save again.');
        }
      }
    });
    return _writes;
  }

  Future<void> _open(bool record) async {
    setState(() => _saving = true);
    await _save();
    if (!mounted) return;
    setState(() => _saving = false);
    if (_problem == null) await goOnStage(context, _document, record: record);
  }

  void _move(int delta) {
    final to = _selected + delta;
    if (to < 0 || to >= _document.notes.cards.length) return;
    _change(_document.copyWith(notes: _document.notes.move(_selected, to)));
    setState(() => _selected = to);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context), deck = _document.notes;
    final card = deck.cards[_selected];
    final direction = _document.language.isRtl ? TextDirection.rtl : TextDirection.ltr;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _title,
          textDirection: direction,
          decoration: const InputDecoration(hintText: 'Untitled notes', border: InputBorder.none),
          onChanged: (value) => _change(_document.copyWith(title: value)),
        ),
        actions: [
          IconButton(tooltip: 'Save notes', onPressed: _save, icon: const Icon(Icons.save_outlined)),
          IconButton(
            tooltip: 'Practice notes',
            onPressed: _saving ? null : () => _open(false),
            icon: const Icon(Icons.slideshow_outlined),
          ),
          IconButton(
            tooltip: 'Record',
            onPressed: _saving ? null : () => _open(true),
            icon: Icon(Icons.fiber_manual_record_rounded, color: p.rec),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(SaSpace.s5),
        children: [
          Text('Speak freely from topic cards.', style: SaType.titleLg.copyWith(color: p.ink)),
          const SizedBox(height: SaSpace.s2),
          Text('Only you see these notes. They stay on this device.', style: SaType.bodySm.copyWith(color: p.ink2)),
          const SizedBox(height: SaSpace.s4),
          Wrap(
            spacing: SaSpace.s3,
            runSpacing: SaSpace.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<ScriptLanguage>(
                value: _document.language,
                onChanged: (value) {
                  if (value != null) {
                    _change(_document.copyWith(language: value));
                  }
                },
                items: [for (final l in ScriptLanguage.values) DropdownMenuItem(value: l, child: Text(l.label))],
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final document = _document.copyWith(recordingAid: RecordingAid.script);
                  _change(document);
                  await _writes;
                  if (!context.mounted || _problem != null) return;
                  await Navigator.of(context)
                      .pushReplacement<void, void>(MaterialPageRoute(builder: (_) => EditorScreen(script: document)));
                },
                icon: const Icon(Icons.description_outlined),
                label: const Text('Use Script'),
              ),
            ],
          ),
          if (_problem != null) Text(_problem!, style: SaType.bodySm.copyWith(color: p.danger)),
          const SizedBox(height: SaSpace.s4),
          Wrap(
            spacing: SaSpace.s2,
            runSpacing: SaSpace.s2,
            children: [
              for (var i = 0; i < deck.cards.length; i++)
                ChoiceChip(
                  label: Text('Card ${i + 1}'),
                  selected: i == _selected,
                  onSelected: (_) => setState(() => _selected = i),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded),
                label: const Text('Add card'),
                onPressed: deck.cards.length >= NoteDeck.maxCards
                    ? null
                    : () {
                        _change(_document.copyWith(notes: deck.add(NoteCard.create())));
                        setState(() => _selected = _document.notes.cards.length - 1);
                      },
              ),
            ],
          ),
          const SizedBox(height: SaSpace.s4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Card ${_selected + 1} of ${deck.cards.length}',
                  style: SaType.signalLabel.copyWith(color: p.ink2),
                ),
              ),
              IconButton(
                tooltip: 'Move card earlier',
                onPressed: _selected > 0 ? () => _move(-1) : null,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              IconButton(
                tooltip: 'Move card later',
                onPressed: _selected + 1 < deck.cards.length ? () => _move(1) : null,
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              IconButton(
                tooltip: 'Remove card',
                onPressed: () {
                  var next = deck.remove(_selected);
                  if (next.cards.isEmpty) next = NoteDeck([NoteCard.create()]);
                  _change(_document.copyWith(notes: next));
                  setState(() => _selected = _selected.clamp(0, next.cards.length - 1));
                },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: SaSpace.s3),
          TextFormField(
            key: ValueKey('${card.id}-title'),
            initialValue: card.title,
            textDirection: direction,
            maxLength: NoteDeck.maxCardLength - card.body.length,
            decoration: const InputDecoration(labelText: 'Topic title', hintText: 'What is this card about?', counterText: ''),
            onChanged: (value) => _change(
              _document.copyWith(
                notes: _document.notes.replace(_selected, _document.notes.cards[_selected].copyWith(title: value)),
              ),
            ),
          ),
          const SizedBox(height: SaSpace.s3),
          TextFormField(
            key: ValueKey('${card.id}-body'),
            initialValue: card.body,
            textDirection: direction,
            minLines: 6,
            maxLines: null,
            maxLength: NoteDeck.maxCardLength - card.title.length,
            decoration: const InputDecoration(
              counterText: '',
              labelText: 'Talking points',
              hintText: 'One reminder per line. Use your own words when you speak.',
            ),
            onChanged: (value) => _change(
              _document.copyWith(
                notes: _document.notes.replace(_selected, _document.notes.cards[_selected].copyWith(body: value)),
              ),
            ),
          ),
          const SizedBox(height: SaSpace.s4),
          Text(
            'Next / Previous move between cards. The last card stays until you stop recording.',
            style: SaType.bodySm.copyWith(color: p.ink2),
          ),
        ],
      ),
    );
  }
}
