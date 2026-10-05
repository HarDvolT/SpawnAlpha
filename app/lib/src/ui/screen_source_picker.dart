import 'dart:async';

import 'package:flutter/material.dart';

import '../recording/screen_source.dart';
import '../recording/source_selection.dart';
import '../theme/theme.dart';

/// Stage source selection. This first recorder slice reads metadata only.
class ScreenSourcePicker extends StatefulWidget {
  const ScreenSourcePicker({super.key, required this.sources, this.selected});
  final ScreenSources sources;
  final ScreenSource? selected;

  @override
  State<ScreenSourcePicker> createState() => _ScreenSourcePickerState();
}

class _ScreenSourcePickerState extends State<ScreenSourcePicker> {
  late final _selection = SourceSelection(widget.sources, selected: widget.selected);

  @override
  void initState() {
    super.initState();
    unawaited(_selection.refresh());
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final selected = await _selection.confirm();
    if (mounted && selected != null) Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    return Theme(
      data: buildTheme(Brightness.dark),
      child: ListenableBuilder(
        listenable: _selection,
        builder: (context, _) => Scaffold(
          backgroundColor: stage.stage,
          appBar: AppBar(
            backgroundColor: stage.stageChrome,
            foregroundColor: stage.stageText,
            title: const Text('Choose screen or window'),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _selection.loading ? null : _selection.refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: SaPrompter.columnMax * SaType.body.fontSize!),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(SaSpace.s4),
                    child: Text(
                      'Choose an entire display or just one window. Nothing is recorded here.',
                      style: SaType.bodySm.copyWith(color: stage.stageChromeText),
                    ),
                  ),
                  if (_selection.loading) const LinearProgressIndicator(),
                  if (_selection.problem != null)
                    Padding(
                      padding: const EdgeInsets.all(SaSpace.s4),
                      child: Row(
                        children: [
                          Icon(Icons.warning_rounded, color: stage.stageWarn),
                          const SizedBox(width: SaSpace.s2),
                          Expanded(
                            child: Text(_selection.problem!, style: SaType.bodySm.copyWith(color: stage.stageWarn)),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: SaSpace.s4),
                      children: [
                        for (final kind in ScreenSourceKind.values) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: SaSpace.s3),
                            child: Text(
                              kind == ScreenSourceKind.display ? 'DISPLAYS' : 'WINDOWS',
                              style: SaType.signalLabel.copyWith(color: stage.stageChromeText),
                            ),
                          ),
                          for (final source in _selection.sources.where((s) => s.kind == kind))
                            Padding(
                              padding: const EdgeInsets.only(bottom: SaSpace.s2),
                              child: Material(
                                color: stage.stageChrome,
                                borderRadius: BorderRadius.circular(SaRadius.md),
                                child: ListTile(
                                  enabled: !_selection.loading,
                                  selected: _selection.selected?.id == source.id,
                                  onTap: () => _selection.choose(source.id),
                                  leading: Icon(
                                    kind == ScreenSourceKind.display
                                        ? Icons.desktop_windows_rounded
                                        : Icons.web_asset_rounded,
                                    color: stage.stageChromeText,
                                  ),
                                  title: Text(
                                    source.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: SaType.bodySm.copyWith(color: stage.stageText),
                                  ),
                                  subtitle: Text(
                                    '${source.width} × ${source.height}${source.primary ? ' · Main display' : ''}',
                                    style: SaType.caption.copyWith(color: stage.stageChromeText),
                                  ),
                                  trailing: _selection.selected?.id == source.id
                                      ? Icon(Icons.check_circle_rounded, color: stage.stageOk)
                                      : null,
                                ),
                              ),
                            ),
                          if (!_selection.loading && !_selection.sources.any((s) => s.kind == kind))
                            Text(
                              kind == ScreenSourceKind.display ? 'No displays found.' : 'Open a window, then Refresh.',
                              style: SaType.bodySm.copyWith(color: stage.stageChromeText),
                            ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(SaSpace.s4),
                    child: FilledButton.icon(
                      onPressed: _selection.loading || _selection.selected == null ? null : _confirm,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Use this source'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
