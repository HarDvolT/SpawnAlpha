import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../review/publishing_text.dart';
import '../storage/publishing_store.dart';
import '../theme/theme.dart';

class PublishingScreen extends StatefulWidget {
  const PublishingScreen({super.key, required this.draft, required this.store});
  final PublishingText draft;
  final PublishingStore store;
  @override
  State<PublishingScreen> createState() => _PublishingScreenState();
}

class _PublishingScreenState extends State<PublishingScreen> {
  late final _title = TextEditingController(text: widget.draft.title),
      _description = TextEditingController(text: widget.draft.description);
  late final _chapters = [
    for (final c in widget.draft.chapters) TextEditingController(text: c.title),
  ];
  late final _selected = List<bool>.filled(_chapters.length, true);
  bool _busy = false;
  int _page = 0;
  static const _pageSize = 8;
  String? _message;
  Directory? _saved;
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    for (final c in _chapters) {
      c.dispose();
    }
    super.dispose();
  }

  PublishingText _draft() => widget.draft.copyWith(
    title: _title.text.trim(),
    description: _description.text.trim(),
    chapters: [
      for (var i = 0; i < _chapters.length; ++i)
        if (_selected[i])
          ChapterText(widget.draft.chapters[i].time, _chapters[i].text.trim()),
    ],
  );
  Future<void> _save({bool copy = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final draft = _draft();
      if (copy) {
        await Clipboard.setData(ClipboardData(text: draft.combined));
      } else {
        final folder = await widget.store.save(draft);
        if (mounted) _saved = folder;
      }
      if (mounted) {
        setState(
          () => _message = copy
              ? 'Text copied. Nothing was posted.'
              : 'Text files saved on this device.',
        );
      }
    } on FormatException {
      if (mounted) {
        setState(
          () => _message = 'Give each kept chapter a title and keep the text within the shown limits.',
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _message = 'Text could not be saved. Your recording and previous files are safe.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context), rtl = widget.draft.language.isRtl;
    final pages = (_chapters.length / _pageSize).ceil();
    Widget reading(Widget child) => Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: child,
    );
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Chapters and description')),
        body: ListView(
          padding: const EdgeInsets.all(SaSpace.s5),
          children: [
            Text(
              'Text for your current cut',
              style: SaType.title.copyWith(color: p.ink),
            ),
            const SizedBox(height: SaSpace.s2),
            Text(
              'This draft stays on this device. Review it before sharing. Earlier saved videos may use a different cut.',
              style: SaType.bodySm.copyWith(color: p.ink2),
            ),
            const SizedBox(height: SaSpace.s4),
            reading(
              TextField(
                controller: _title,
                enabled: !_busy,
                maxLength: 512,
                decoration: const InputDecoration(labelText: 'Title'),
                style: SaType.body,
              ),
            ),
            const SizedBox(height: SaSpace.s4),
            reading(
              TextField(
                controller: _description,
                enabled: !_busy,
                minLines: 3,
                maxLines: 8,
                maxLength: 10000,
                decoration: const InputDecoration(labelText: 'Description'),
                style: SaType.body,
              ),
            ),
            Text(
              'The description starts with an excerpt of your actual speech. No online AI or upload was used.',
              style: SaType.bodySm.copyWith(color: p.ink2),
            ),
            const SizedBox(height: SaSpace.s5),
            Text('Chapters', style: SaType.title.copyWith(color: p.ink)),
            Text(
              'Starts are estimates. Check them before sharing.',
              style: SaType.bodySm.copyWith(color: p.ink2),
            ),
            if (widget.draft.notes)
              Text(
                'Chapter titles come from your private cards. Their bullet reminders stay out.',
                style: SaType.bodySm.copyWith(color: p.ink2),
              ),
            if (widget.draft.notice != null)
              Text(
                widget.draft.notice!,
                style: SaType.bodySm.copyWith(color: p.ink2),
              ),
            if (_chapters.isEmpty)
              Text(
                'No reliable section starts found.',
                style: SaType.bodySm.copyWith(color: p.ink2),
              ),
            for (
              var i = _page * _pageSize;
              i < (_page + 1) * _pageSize && i < _chapters.length;
              ++i
            ) ...[
              const SizedBox(height: SaSpace.s3),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selected[i],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _selected[i] = value ?? false),
                title: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    chapterStamp(widget.draft.chapters[i].time),
                    style: SaType.signalLabel.copyWith(color: p.ink),
                  ),
                ),
              ),
              reading(
                TextField(
                  controller: _chapters[i],
                  enabled: !_busy && _selected[i],
                  maxLength: 512,
                  decoration: const InputDecoration(labelText: 'Chapter title'),
                  style: SaType.body,
                ),
              ),
            ],
            if (pages > 1)
              Wrap(
                spacing: SaSpace.s3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Page ${_page + 1} of $pages',
                    style: SaType.signalLabel.copyWith(color: p.ink2),
                  ),
                  TextButton(
                    onPressed: _busy || _page == 0
                        ? null
                        : () => setState(() => --_page),
                    child: const Text('Previous chapters'),
                  ),
                  TextButton(
                    onPressed: _busy || _page + 1 >= pages
                        ? null
                        : () => setState(() => ++_page),
                    child: const Text('Next chapters'),
                  ),
                ],
              ),
            const SizedBox(height: SaSpace.s5),
            Wrap(
              spacing: SaSpace.s3,
              runSpacing: SaSpace.s2,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _save(copy: true),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy text'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save text files'),
                ),
                if (_saved != null && Platform.isWindows)
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => Process.run('explorer', [_saved!.path]),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Show saved text'),
                  ),
              ],
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null)
              Text(_message!, style: SaType.bodySm.copyWith(color: p.ink2)),
          ],
        ),
      ),
    );
  }
}
