import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app.dart';
import '../markup/markup_engine.dart';
import '../markup/providers.dart';
import '../model/coaching_style.dart';
import '../model/mark_editing.dart';
import '../model/script_document.dart';
import '../model/script_language.dart';
import '../prompter/marked_text.dart';
import 'format.dart';
import 'mark_sheet.dart';
import 'prompter_screen.dart';
import 'record_screen.dart';
import 'settings_screen.dart';

/// Write a script, choose its style and language, run the markup, and
/// review the marks and suggestions.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.script});

  final ScriptDocument script;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

enum _PendingChoice { acceptAll, skip }

class _EditorScreenState extends State<EditorScreen> with SingleTickerProviderStateMixin {
  late ScriptDocument _script = widget.script;
  late final _text = TextEditingController(text: _script.text);
  late final _title = TextEditingController(text: _script.title);
  late final _tabs = TabController(length: 2, vsync: this, initialIndex: _script.text.trim().isEmpty ? 0 : 1);
  final _markedKey = GlobalKey();
  Timer? _saveTimer;
  bool _marking = false;
  int _received = 0;

  late AppServices _services;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = AppScope.of(context);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveNow();
    _text.dispose();
    _title.dispose();
    _tabs.dispose();
    super.dispose();
  }

  // ---- state and saving ---------------------------------------------------

  void _update(ScriptDocument next) {
    setState(() => _script = next);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  void _saveNow() {
    _saveTimer?.cancel();
    final library = _services.library;
    // Don't keep a new script until something is written in it.
    final isNew = library.byId(_script.id) == null;
    if (isNew && _script.text.trim().isEmpty && _script.title.trim().isEmpty) return;
    if (!isNew && identical(library.byId(_script.id), _script)) return;
    library.save(_script);
  }

  void _onTextChanged() {
    final text = _text.text;
    if (text == _script.text) return;
    var next = _script.withText(text);
    // Pick the language from the first words written or pasted.
    if (_script.wordCount < 4) {
      final detected = ScriptLanguage.detect(text);
      if (detected != null && detected != next.language) next = next.copyWith(language: detected);
    }
    _update(next);
  }

  // ---- markup -------------------------------------------------------------

  Future<void> _runMarkup({bool forceLocal = false}) async {
    if (_script.wordCount == 0) {
      showMessage(context, 'Write or paste a script first.');
      return;
    }
    final settings = _services.settings;
    final chosen = forceLocal ? MarkupProvider.onDevice : settings.provider;
    // A provider that isn't set up yet falls back to the on-device rules.
    final problem = chosen.isRemote ? settings.setupProblemForProvider : null;
    final engine = settings.engine(
      use: problem == null ? chosen : MarkupProvider.onDevice,
      onProgress: (n) {
        if (mounted) setState(() => _received = n);
      },
    );
    final remote = engine is RemoteMarkupEngine ? engine : null;

    setState(() {
      _marking = true;
      _received = 0;
    });
    final snapshot = _script;
    try {
      final result = await engine.markup(snapshot);
      if (!mounted) return;
      if (_script.text != snapshot.text) {
        showMessage(context, 'The script changed while it was being marked up. Run the markup again.');
        return;
      }
      _update(applyMarkup(_script, result));
      final suggestions = result.suggestions.isEmpty ? '' : ' and ${result.suggestions.length} suggestions';
      var message = '${engine.name} proposed ${result.marks.length} marks$suggestions. Tap a word to review.';
      if (problem != null) message = '${chosen.label} isn\'t set up yet ($problem), so the on-device markup ran. $message';
      showMessage(
        context,
        message,
        action: problem != null ? SnackBarAction(label: 'Settings', onPressed: _openSettings) : null,
      );
    } on MarkupException catch (e) {
      if (!mounted) return;
      showMessage(
        context,
        e.message,
        action: remote == null
            ? null
            : SnackBarAction(label: 'Use on-device', onPressed: () => _runMarkup(forceLocal: true)),
      );
    } finally {
      remote?.close();
      if (mounted) setState(() => _marking = false);
    }
  }

  void _openSettings() =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  // ---- marks --------------------------------------------------------------

  void _onTapMarked(TapUpDetails details, MarkedText marked) {
    final paragraph = _markedKey.currentContext?.findRenderObject();
    if (paragraph is! RenderParagraph) return;
    final offset = paragraph.getPositionForOffset(paragraph.globalToLocal(details.globalPosition)).offset;
    final token = marked.tokenForTap(offset, _script.tokens);
    if (token == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MarkSheet(script: _script, token: token, onChanged: _update),
    );
  }

  // ---- prompter and recording ---------------------------------------------

  Future<void> _open({required bool record}) async {
    if (_script.wordCount == 0) {
      showMessage(context, 'Write or paste a script first.');
      return;
    }
    var script = _script;
    if (script.pendingCount > 0) {
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
      if (choice == null || !mounted) return;
      if (choice == _PendingChoice.acceptAll) {
        script = script.acceptAllMarks();
        _update(script);
      }
    }
    _saveNow();
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => record ? RecordScreen(script: script) : PrompterScreen(script: script),
      fullscreenDialog: true,
    ));
    // The record screen saves takes straight to the library. Pick them up
    // so the next autosave doesn't overwrite them.
    final saved = _services.library.byId(_script.id);
    if (saved != null && mounted && saved.takes.length != _script.takes.length) {
      _update(_script.copyWith(takes: saved.takes));
    }
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pending = _script.pendingCount;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _title,
          decoration: const InputDecoration.collapsed(hintText: 'Untitled script'),
          style: Theme.of(context).textTheme.titleLarge,
          onChanged: (v) => _update(_script.copyWith(title: v)),
        ),
        actions: [
          IconButton(
            tooltip: 'Practice with the prompter',
            icon: const Icon(Icons.slideshow_outlined),
            onPressed: () => _open(record: false),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: () => _open(record: true),
              icon: const Icon(Icons.fiber_manual_record, color: Colors.redAccent),
              label: const Text('Record'),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'Write'),
            Tab(
              child: Badge(
                isLabelVisible: pending > 0,
                label: Text('$pending'),
                offset: const Offset(14, -6),
                child: const Text('Marks'),
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(children: [
            _StyleBar(
              script: _script,
              onStyle: (s) => _update(_script.copyWith(style: s)),
              onLanguage: (l) => _update(_script.copyWith(language: l)),
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(controller: _tabs, children: [_writeTab(), _marksTab()]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _writeTab() => Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _text,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          textDirection: _script.language.isRtl ? TextDirection.rtl : TextDirection.ltr,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(fontSize: 18, height: 1.5),
          decoration: const InputDecoration(
            hintText: 'Write or paste your script. Blank lines separate paragraphs.',
            border: OutlineInputBorder(),
          ),
        ),
      );

  Widget _marksTab() {
    final theme = Theme.of(context);
    final colors = theme.brightness == Brightness.dark ? CueColors.dark : CueColors.light;
    final marked = MarkedText.build(
      tokens: _script.tokens,
      marks: _script.marks,
      style: TextStyle(fontSize: 22, height: 1.7, color: colors.text),
      colors: colors,
    );
    final settings = _services.settings;
    final engineName = settings.provider.isRemote && settings.setupProblemForProvider == null
        ? '${settings.provider.label} (${settings.configOf(settings.provider).model})'
        : 'on-device coach';
    final pending = _script.pendingCount;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              onPressed: _marking ? null : _runMarkup,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_script.marks.isEmpty ? 'Mark up with $engineName' : 'Mark up again'),
            ),
            if (_marking)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text(_received > 0 ? 'Receiving marks… ${(_received / 1000).toStringAsFixed(1)}k' : 'Marking up…'),
              ]),
          ],
        ),
        if (pending > 0) ...[
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(children: [
                Expanded(
                  child: Text('$pending suggested marks are faded until you accept them. Tap a word to edit.'),
                ),
                TextButton(
                  onPressed: () => _update(_script.discardPendingMarks()),
                  child: const Text('Discard'),
                ),
                FilledButton(
                  onPressed: () => _update(_script.acceptAllMarks()),
                  child: const Text('Accept all'),
                ),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_script.tokens.isEmpty)
          Text('Nothing to mark up yet. Write your script in the Write tab.', style: theme.textTheme.bodyLarge)
        else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _onTapMarked(d, marked),
            child: Text.rich(
              key: _markedKey,
              marked.span,
              textDirection: _script.language.isRtl ? TextDirection.rtl : TextDirection.ltr,
            ),
          ),
        if (_script.suggestions.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Suggestions', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final s in _script.suggestions)
            _SuggestionCard(
              suggestion: s,
              isRtl: _script.language.isRtl,
              onApply: () {
                _update(_script.applySuggestion(s));
                // The listener sees matching text and leaves the marks alone.
                _text.value = TextEditingValue(text: _script.text);
              },
              onDismiss: () => _update(_script.dismissSuggestion(s)),
            ),
        ],
        const SizedBox(height: 28),
        CueLegend(colors: colors),
      ],
    );
  }
}

class _StyleBar extends StatelessWidget {
  const _StyleBar({required this.script, required this.onStyle, required this.onLanguage});

  final ScriptDocument script;
  final ValueChanged<CoachingStyle> onStyle;
  final ValueChanged<ScriptLanguage> onLanguage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // On a phone the style names don't fit; show icons and name the style
    // in the line below.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<CoachingStyle>(
            segments: [
              for (final s in CoachingStyle.values)
                ButtonSegment(
                  value: s,
                  label: narrow ? null : Text(s.label),
                  icon: Icon(styleIcon(s)),
                  tooltip: narrow ? '${s.label}: ${s.goal}' : s.goal,
                ),
            ],
            selected: {script.style},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onStyle(s.single),
          ),
          DropdownButton<ScriptLanguage>(
            value: script.language,
            underline: const SizedBox.shrink(),
            items: [
              for (final l in ScriptLanguage.values) DropdownMenuItem(value: l, child: Text(l.label)),
            ],
            onChanged: (l) {
              if (l != null) onLanguage(l);
            },
          ),
          Text(
            '${narrow ? '${script.style.label} · ' : ''}'
            '${script.wordCount} words · ~${formatDuration(estimatedDuration(script))} · '
            '${script.style.minWpm}–${script.style.maxWpm} wpm',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.isRtl,
    required this.onApply,
    required this.onDismiss,
  });

  final Suggestion suggestion;
  final bool isRtl;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final direction = isRtl ? TextDirection.rtl : TextDirection.ltr;
    final replacement = suggestion.replacement;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(suggestion.kind.label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Text(
            suggestion.original,
            textDirection: direction,
            style: TextStyle(
              decoration: replacement == null ? null : TextDecoration.lineThrough,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (replacement != null) ...[
            const SizedBox(height: 4),
            Text(replacement, textDirection: direction, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          if (suggestion.note != null) ...[
            const SizedBox(height: 6),
            Text(suggestion.note!, style: theme.textTheme.bodySmall),
          ],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(spacing: 4, children: [
              TextButton(onPressed: onDismiss, child: Text(replacement == null ? 'Got it' : 'Dismiss')),
              if (replacement != null) FilledButton.tonal(onPressed: onApply, child: const Text('Apply')),
            ]),
          ),
        ]),
      ),
    );
  }
}
