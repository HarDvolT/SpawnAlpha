import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../transcription/word_timing.dart';
import 'format.dart';

/// A bounded page of actual words. Timing, alignment and saving live in services.
class WordReviewPanel extends StatefulWidget {
  const WordReviewPanel({
    super.key,
    required this.transcript,
    required this.busy,
    required this.onCorrect,
  });
  final WordTranscript transcript;
  final bool busy;
  final Future<void> Function(int index, String text) onCorrect;
  @override
  State<WordReviewPanel> createState() => _WordReviewPanelState();
}

class _WordReviewPanelState extends State<WordReviewPanel> {
  static const _pageSize = 20;
  bool _expanded = false;
  int _page = 0;

  Future<void> _edit(int index) async {
    final word = widget.transcript.words[index];
    final value = await showDialog<String>(
      context: context,
      builder: (_) =>
          CorrectWordDialog(word: word, rtl: widget.transcript.language.isRtl),
    );
    if (mounted && value != null && value != word.text) {
      await widget.onCorrect(index, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context), words = widget.transcript.words;
    final pages = (words.length / _pageSize).ceil();
    final page = pages == 0 ? 0 : _page.clamp(0, pages - 1);
    final start = page * _pageSize,
        end = (start + _pageSize).clamp(0, words.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: words.isEmpty
              ? null
              : () => setState(() => _expanded = !_expanded),
          icon: Icon(
            _expanded ? Icons.expand_less_rounded : Icons.edit_note_rounded,
          ),
          label: Text(_expanded ? 'Hide word review' : 'Review wording'),
        ),
        if (_expanded) ...[
          const SizedBox(height: SaSpace.s3),
          Text(
            'Fix one word at a time. Keep what you said. Times and confidence stay as estimated; your original and earlier exports are kept.',
            style: SaType.bodySm.copyWith(color: p.ink2),
          ),
          for (var i = start; i < end; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SaSpace.s2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: widget.transcript.language.isRtl
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Directionality(
                            textDirection: widget.transcript.language.isRtl
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            child: Text(
                              words[i].text,
                              style: SaType.body.copyWith(color: p.ink),
                            ),
                          ),
                        ),
                        Text(
                          '${formatCutTime(words[i].start)} – ${formatCutTime(words[i].end)}'
                          '${words[i].corrected ? ' · Corrected' : ''}'
                          '${words[i].confidence == null || words[i].confidence! < .6 ? ' · Check wording' : ''}',
                          style: SaType.bodySm.copyWith(color: p.ink2),
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: SaSpace.s2,
                    runSpacing: SaSpace.s2,
                    children: [
                      IconButton(
                        onPressed: widget.busy ? null : () => _edit(i),
                        tooltip: 'Edit word ${i + 1}',
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      if (words[i].corrected)
                        IconButton(
                          onPressed: widget.busy
                              ? null
                              : () => widget.onCorrect(
                                  i,
                                  words[i].recognizedText!,
                                ),
                          tooltip: 'Restore word ${i + 1}',
                          icon: const Icon(Icons.undo_rounded),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (pages > 1)
            Wrap(
              spacing: SaSpace.s3,
              runSpacing: SaSpace.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: page == 0
                      ? null
                      : () => setState(() => _page = page - 1),
                  child: const Text('Previous words'),
                ),
                Text(
                  '${page + 1} of $pages',
                  style: SaType.signalLabel.copyWith(color: p.ink2),
                ),
                OutlinedButton(
                  onPressed: page + 1 >= pages
                      ? null
                      : () => setState(() => _page = page + 1),
                  child: const Text('Next words'),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

class CorrectWordDialog extends StatefulWidget {
  const CorrectWordDialog({super.key, required this.word, required this.rtl});
  final SpokenWord word;
  final bool rtl;
  @override
  State<CorrectWordDialog> createState() => _CorrectWordDialogState();
}

class _CorrectWordDialogState extends State<CorrectWordDialog> {
  late final _text = TextEditingController(text: widget.word.text);
  String? _error;
  void _save() {
    try {
      widget.word.withText(_text.text);
      Navigator.pop(context, _text.text);
    } on FormatException {
      setState(
        () => _error = 'Enter one word, with its punctuation if needed.',
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    return AlertDialog(
      title: const Text('Correct this word'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keep the wording you said. This keeps the original word timing.',
            style: SaType.bodySm.copyWith(color: p.ink2),
          ),
          const SizedBox(height: SaSpace.s3),
          Directionality(
            textDirection: widget.rtl ? TextDirection.rtl : TextDirection.ltr,
            child: TextField(
              controller: _text,
              autofocus: true,
              maxLength: 1024,
              style: SaType.body.copyWith(color: p.ink),
              decoration: InputDecoration(
                labelText: 'Word',
                errorText: _error,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _save(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save word')),
      ],
    );
  }
}
