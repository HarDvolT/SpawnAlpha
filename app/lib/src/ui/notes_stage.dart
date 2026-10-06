import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../model/note_deck.dart';
import '../model/script_language.dart';
import '../theme/theme.dart';

/// A single private card, with manual navigation independent of recording.
class NotesStage extends StatefulWidget {
  const NotesStage({super.key, required this.controller, required this.language, this.onChanged});
  final NoteController controller;
  final ScriptLanguage language;
  final ValueChanged<int>? onChanged;
  @override
  State<NotesStage> createState() => _NotesStageState();
}

class _NotesStageState extends State<NotesStage> with SingleTickerProviderStateMixin {
  late final _fade = AnimationController.unbounded(vsync: this, value: 1);
  final _scroll = ScrollController();
  late int _index = widget.controller.index;
  void _navigate(bool next) {
    if (next ? widget.controller.next() : widget.controller.previous()) {
      _transition();
      setState(() {});
      widget.onChanged?.call(widget.controller.index);
    }
  }

  void _transition() {
    _index = widget.controller.index;
    if (MediaQuery.disableAnimationsOf(context)) {
      _fade.value = 1;
    } else {
      _fade.animateWith(SpringSimulation(SaSprings.smooth, 0, 1, 0));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  void didUpdateWidget(NotesStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index != widget.controller.index || oldWidget.controller != widget.controller) _transition();
  }

  @override
  void dispose() {
    _fade.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, stage = SaPalette.dark;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true, shift: true): () => _navigate(true),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true, shift: true): () => _navigate(false),
      },
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: stage.stageGlass,
          child: Column(
            children: [
              Expanded(
                child: AnimatedBuilder(
                  animation: _fade,
                  builder: (context, child) => Opacity(opacity: _fade.value.clamp(0, 1), child: child),
                  child: Directionality(
                    textDirection: widget.language.isRtl ? TextDirection.rtl : TextDirection.ltr,
                    child: Scrollbar(
                      controller: _scroll,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.all(SaSpace.s5),
                        child: Align(
                          alignment: AlignmentDirectional.topStart,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (c.card == null || c.card!.isEmpty)
                                Text(
                                  'Add talking points in the Notes editor.',
                                  style: SaType.body.copyWith(color: stage.stageChromeText),
                                )
                              else ...[
                                if (c.card!.title.trim().isNotEmpty) ...[
                                  Text(c.card!.title, style: SaType.stageS.copyWith(color: stage.stageText)),
                                  const SizedBox(height: SaSpace.s4),
                                ],
                                for (final point in c.card!.points)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: SaSpace.s3),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('•', style: SaType.body.copyWith(color: stage.stageOk)),
                                        const SizedBox(width: SaSpace.s3),
                                        Expanded(
                                          child: Text(
                                            point.trim(),
                                            style: SaType.body.copyWith(color: stage.stageText),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SaSpace.s3, vertical: SaSpace.s2),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous card · Ctrl+Shift+Left',
                      color: stage.stageText,
                      disabledColor: stage.stageLine,
                      onPressed: c.canPrevious ? () => _navigate(false) : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          'Card ${c.card == null ? 0 : c.index + 1} of ${c.deck.cards.length}',
                          textAlign: TextAlign.center,
                          style: SaType.signalLabel.copyWith(color: stage.stageChromeText),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next card · Ctrl+Shift+Right',
                      color: stage.stageText,
                      disabledColor: stage.stageLine,
                      onPressed: c.canNext ? () => _navigate(true) : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
