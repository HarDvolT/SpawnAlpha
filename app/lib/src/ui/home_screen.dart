import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../markup/providers.dart';
import '../model/mark.dart';
import '../model/samples.dart';
import '../model/script_document.dart';
import '../model/token.dart';
import '../prompter/guide.dart';
import '../prompter/marked_text.dart';
import '../theme/theme.dart';
import 'notes_editor_screen.dart';
import 'format.dart';
import 'library_screen.dart';
import 'record_setup.dart';
import 'recording_widgets.dart';
import 'script_page.dart';
import 'settings_screen.dart';
import 'stage_launch.dart';
import 'takes_screen.dart';
import 'take_review_screen.dart';

/// The first screen: a director's desk (docs/design/components/Home). One
/// hero, "Record next", on the stage; the scripts as marked pages; the
/// recent takes. A sidebar on wide windows, a tab bar on phones.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// Wider than this, the sidebar shows.
  static const sidebarBreakpoint = 900.0;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// The script the hero offers to record, when the user picked one; else
  /// the most recently edited.
  String? _nextId;

  ScriptDocument? _next(List<ScriptDocument> scripts) {
    if (scripts.isEmpty) return null;
    for (final s in scripts) {
      if (s.id == _nextId) return s;
    }
    return scripts.first;
  }

  void _openScript(ScriptDocument script) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => documentEditor(script)));

  void _newScript() => createDocument(context);

  void _openScripts() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LibraryScreen()));

  void _openTakes() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TakesScreen()));

  void _openSettings() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.library, services.settings]),
      builder: (context, _) {
        final scripts = services.library.scripts;
        final next = _next(scripts);
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= HomeScreen.sidebarBreakpoint;
            final body = _HomeBody(
              scripts: scripts,
              next: next,
              wide: wide,
              onOpen: _openScript,
              onNew: _newScript,
              onChooseNext: (s) => setState(() => _nextId = s.id),
              onSeeAll: _openScripts,
              onAllTakes: _openTakes,
            );
            if (wide) {
              return Scaffold(
                body: Row(
                  children: [
                    _Sidebar(
                      scripts: scripts.length,
                      takes: scripts.fold(0, (n, s) => n + s.takes.length),
                      provider: services.settings.provider,
                      onScripts: _openScripts,
                      onTakes: _openTakes,
                      onSettings: _openSettings,
                    ),
                    Expanded(child: body),
                  ],
                ),
              );
            }
            final stage = SaPalette.dark;
            return Scaffold(
              body: SafeArea(bottom: false, child: body),
              floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
              floatingActionButton: next == null
                  ? null
                  : FloatingActionButton(
                      tooltip: 'Record ${next.displayTitle}',
                      backgroundColor: stage.stage,
                      shape: const CircleBorder(),
                      onPressed: () => goOnStage(context, next, record: true),
                      child: Container(
                        width: SaSpace.s5,
                        height: SaSpace.s5,
                        decoration: BoxDecoration(color: stage.stageRec, shape: BoxShape.circle),
                      ),
                    ),
              bottomNavigationBar: BottomAppBar(
                shape: const CircularNotchedRectangle(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _TabButton(icon: Icons.home_rounded, label: 'Home', selected: true, onTap: () {}),
                    _TabButton(icon: Icons.description_outlined, label: 'Scripts', onTap: _openScripts),
                    const SizedBox(width: SaSpace.s6),
                    _TabButton(icon: Icons.video_library_outlined, label: 'Takes', onTap: _openTakes),
                    _TabButton(icon: Icons.settings_outlined, label: 'Settings', onTap: _openSettings),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.icon, required this.label, required this.onTap, this.selected = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    final color = selected ? p.ink : p.ink3;
    return InkResponse(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SaSpace.s2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            Text(
              label,
              style: SaType.caption.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Sidebar (wide windows) -------------------------------------------------

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.scripts,
    required this.takes,
    required this.provider,
    required this.onScripts,
    required this.onTakes,
    required this.onSettings,
  });

  static const width = 216.0;

  final int scripts;
  final int takes;
  final MarkupProvider provider;
  final VoidCallback onScripts;
  final VoidCallback onTakes;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: p.surfaceSunk,
        border: BorderDirectional(end: BorderSide(color: p.line)),
      ),
      padding: const EdgeInsets.fromLTRB(SaSpace.s3, SaSpace.s5, SaSpace.s3, SaSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: SaSpace.s2, bottom: SaSpace.s5),
            child: Row(
              children: [
                Container(
                  width: SaSpace.s4 + 2,
                  height: SaSpace.s4 + 2,
                  decoration: BoxDecoration(color: p.cue, borderRadius: BorderRadius.circular(SaRadius.xs)),
                ),
                const SizedBox(width: SaSpace.s3 - 2),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'SpawnAlpha',
                      style: atWidth(
                        SaType.title.copyWith(fontFamily: SaFonts.display, fontWeight: FontWeight.w800),
                        112,
                      ).copyWith(color: p.ink),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _NavItem(icon: Icons.home_rounded, label: 'Home', selected: true, onTap: () {}),
          _NavItem(icon: Icons.description_outlined, label: 'Scripts', count: scripts, onTap: onScripts),
          _NavItem(icon: Icons.video_library_outlined, label: 'Takes', count: takes, onTap: onTakes),
          _NavItem(icon: Icons.settings_outlined, label: 'Settings', onTap: onSettings),
          const Spacer(),
          // Who marks up the scripts, and what that means for privacy.
          Container(
            padding: const EdgeInsets.all(SaSpace.s3),
            decoration: BoxDecoration(
              color: p.surface,
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(SaRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DIRECTOR', style: SaType.signalLabel.copyWith(color: p.ink3)),
                const SizedBox(height: SaSpace.s1),
                Text(
                  provider.isRemote ? provider.label : 'On-device coach',
                  style: SaType.label.copyWith(color: p.ink, fontWeight: FontWeight.w700),
                ),
                Text(
                  provider.isRemote ? 'Scripts go to ${provider.label} when you mark up' : 'Free · works offline',
                  style: SaType.caption.copyWith(color: p.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.onTap, this.count, this.selected = false});

  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SaSpace.s1),
      child: Material(
        color: selected ? p.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SaRadius.md),
          side: selected ? BorderSide(color: p.line) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(SaRadius.md),
          onTap: onTap,
          child: SizedBox(
            height: 38,
            child: Row(
              children: [
                const SizedBox(width: SaSpace.s3),
                Icon(icon, size: 20, color: selected ? p.ink : p.ink2),
                const SizedBox(width: SaSpace.s3),
                Expanded(
                  child: Text(
                    label,
                    style: SaType.label.copyWith(color: selected ? p.ink : p.ink2, fontWeight: FontWeight.w600),
                  ),
                ),
                if (count != null) Text('$count', style: SaType.meter.copyWith(color: p.ink3)),
                const SizedBox(width: SaSpace.s3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---- The desk ----------------------------------------------------------------

class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.scripts,
    required this.next,
    required this.wide,
    required this.onOpen,
    required this.onNew,
    required this.onChooseNext,
    required this.onSeeAll,
    required this.onAllTakes,
  });

  final List<ScriptDocument> scripts;
  final ScriptDocument? next;
  final bool wide;
  final ValueChanged<ScriptDocument> onOpen;
  final VoidCallback onNew;
  final ValueChanged<ScriptDocument> onChooseNext;
  final VoidCallback onSeeAll;
  final VoidCallback onAllTakes;

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    final takes = [
      for (final s in scripts)
        for (var i = 0; i < s.takes.length; i++) (script: s, take: s.takes[i], number: i + 1),
    ]..sort((a, b) => b.take.recordedAt.compareTo(a.take.recordedAt));
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final thisWeek = takes.where((t) => t.take.recordedAt.isAfter(weekAgo)).length;
    final pad = wide ? SaSpace.s6 : SaSpace.s4;
    final next = this.next;
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, wide ? SaSpace.s5 : SaSpace.s4, pad, SaSpace.s8),
      children: [
        _Rise(
          order: 0,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: SaSpace.s4,
            runSpacing: SaSpace.s1,
            children: [
              Text(
                scripts.isEmpty ? 'Say it like you mean it.' : 'Ready when you are.',
                style: SaType.titleLg.copyWith(color: p.ink, fontWeight: FontWeight.w800),
              ),
              if (scripts.isNotEmpty)
                Text(
                  '${scripts.length} script${scripts.length == 1 ? '' : 's'} · $thisWeek take${thisWeek == 1 ? '' : 's'} this week',
                  style: SaType.signalLabel.copyWith(color: p.ink3),
                ),
            ],
          ),
        ),
        const SizedBox(height: SaSpace.s5),
        _Rise(
          order: 1,
          child: next == null
              ? const _Welcome()
              : _RecordNext(
                  script: next,
                  scripts: scripts,
                  wide: wide,
                  onOpen: () => onOpen(next),
                  onChoose: onChooseNext,
                ),
        ),
        if (scripts.isNotEmpty) ...[
          const SizedBox(height: SaSpace.s6),
          _Rise(
            order: 2,
            child: _SectionHead(title: 'Scripts', action: 'See all', onAction: onSeeAll),
          ),
          const SizedBox(height: SaSpace.s3),
          _Rise(
            order: 2,
            child: Wrap(
              spacing: SaSpace.s3,
              runSpacing: SaSpace.s3,
              children: [
                for (final s in scripts.take(wide ? 7 : 5))
                  _PageCard(key: ValueKey('page-${s.id}'), script: s, onTap: () => onOpen(s)),
                _NewPageCard(onTap: onNew),
              ],
            ),
          ),
        ],
        if (takes.isNotEmpty) ...[
          const SizedBox(height: SaSpace.s6),
          _Rise(
            order: 3,
            child: _SectionHead(title: 'Recent takes', action: 'All takes', onAction: onAllTakes),
          ),
          const SizedBox(height: SaSpace.s3),
          _Rise(
            order: 3,
            child: Wrap(
              spacing: SaSpace.s3,
              runSpacing: SaSpace.s3,
              children: [
                for (final t in takes.take(wide ? 6 : 4)) TakeThumb(script: t.script, take: t.take, number: t.number),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Sections rise into place one after another as the desk sets itself.
class _Rise extends StatelessWidget {
  const _Rise({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: SaDurations.slow + SaDurations.stagger * (order * 4),
      curve: SaEasing.standard,
      builder: (context, t, child) {
        // Each section waits its turn, then rises.
        final start = order * 0.12;
        final k = ((t - start) / (1 - start)).clamp(0.0, 1.0);
        return Opacity(
          opacity: k,
          child: Transform.translate(offset: Offset(0, SaSpace.s3 * (1 - k)), child: child),
        );
      },
      child: child,
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.action, required this.onAction});

  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    return Row(
      children: [
        Text(
          title,
          style: SaType.title.copyWith(color: p.ink, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: p.ink2, textStyle: SaType.label),
          onPressed: onAction,
          child: Text(action),
        ),
      ],
    );
  }
}

// ---- The hero: Record next, on the stage --------------------------------------

class _RecordNext extends StatelessWidget {
  const _RecordNext({
    required this.script,
    required this.scripts,
    required this.wide,
    required this.onOpen,
    required this.onChoose,
  });

  final ScriptDocument script;
  final List<ScriptDocument> scripts;
  final bool wide;
  final VoidCallback onOpen;
  final ValueChanged<ScriptDocument> onChoose;

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    final settings = AppScope.of(context).settings;
    final accepted = script.marks.where((m) => m.accepted).length;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RECORD NEXT', style: SaType.signalLabel.copyWith(color: stage.stageChromeText)),
        const SizedBox(height: SaSpace.s2),
        Row(
          children: [
            Flexible(
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(SaRadius.xs),
                child: Text(
                  script.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SaType.titleLg.copyWith(color: stage.stageText, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            if (scripts.length > 1)
              PopupMenuButton<ScriptDocument>(
                tooltip: 'Record another script',
                icon: Icon(Icons.swap_horiz_rounded, color: stage.stageChromeText),
                onSelected: onChoose,
                itemBuilder: (_) => [
                  for (final s in scripts)
                    PopupMenuItem(
                      value: s,
                      child: Text(s.displayTitle, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: SaSpace.s3),
        _StagePreview(script: script),
        const SizedBox(height: SaSpace.s3),
        DefaultTextStyle.merge(
          style: SaType.meter.copyWith(color: stage.stageChromeText),
          child: Wrap(
            spacing: SaSpace.s4,
            runSpacing: SaSpace.s1,
            children: [
              _Meta(icon: styleIcon(script.style), text: script.style.label),
              Text(script.contentSummary),
              if (!script.usesNotes) Text('~${formatDuration(estimatedDuration(script))}'),
              Text('$accepted cue${accepted == 1 ? '' : 's'}'),
              if (script.pendingCount > 0) Text('${script.pendingCount} to review'),
            ],
          ),
        ),
      ],
    );
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        RecordModeTiles(
          mode: settings.recordMode,
          screenReady: AppScope.of(context).recorder.supported,
          bothReady: AppScope.of(context).recorder.supported && AppScope.of(context).bubbles.supported,
          onChanged: (mode) => settings.update((s) => s.recordMode = mode),
        ),
        const SizedBox(height: SaSpace.s3),
        Wrap(
          spacing: SaSpace.s2,
          runSpacing: SaSpace.s2,
          children: [
            _Check(
              icon: settings.recordMode == TakeMode.screen ? Icons.screen_share_rounded : Icons.videocam_outlined,
              text: switch (settings.recordMode) {
                TakeMode.screen => 'Screen',
                TakeMode.both => 'Screen + camera',
                TakeMode.camera => 'Camera',
              },
            ),
            _Check(
              icon: Icons.mic_none_rounded,
              text: settings.audioInputId == null ? 'System microphone' : 'Your microphone',
            ),
            _Check(icon: Icons.record_voice_over_outlined, text: 'Guide: ${settings.guide.label}'),
          ],
        ),
        const SizedBox(height: SaSpace.s4),
        Row(
          children: [
            RecordButton(
              recording: false,
              saving: false,
              enabled: true,
              onPressed: () => goOnStage(context, script, record: true),
            ),
            const SizedBox(width: SaSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Record',
                    style: SaType.body.copyWith(color: stage.stageText, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    script.usesNotes
                        ? '3, 2, 1, then speak freely from your notes'
                        : '3, 2, 1, then ${switch (settings.guide) {
                            PrompterGuide.dot => 'the dot leads you',
                            PrompterGuide.underline => 'the underline leads you',
                            PrompterGuide.spotlight => 'the spotlight leads you',
                            PrompterGuide.off => 'the prompter follows you',
                          }}',
                    style: SaType.caption.copyWith(color: stage.stageChromeText),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: stage.stageText,
                side: BorderSide(color: stage.stageGlassEdge),
                textStyle: SaType.label,
              ),
              onPressed: () => goOnStage(context, script, record: false),
              icon: const Icon(Icons.slideshow_rounded, size: 18),
              label: const Text('Practice'),
            ),
          ],
        ),
      ],
    );
    return Container(
      padding: EdgeInsets.all(wide ? SaSpace.s5 : SaSpace.s4),
      decoration: BoxDecoration(
        color: stage.stage,
        gradient: RadialGradient(center: const Alignment(1, -1), radius: 1.2, colors: [stage.stageChrome, stage.stage]),
        borderRadius: BorderRadius.circular(SaRadius.lg),
        boxShadow: SaTheme.of(context).shadowFloat,
      ),
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: left),
                const SizedBox(width: SaSpace.s5),
                Expanded(flex: 3, child: right),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                left,
                const SizedBox(height: SaSpace.s4),
                right,
              ],
            ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: SaPalette.dark.stageChromeText),
      const SizedBox(width: SaSpace.s1),
      Text(text),
    ],
  );
}

/// The script's first lines as the prompter will show them: stage type,
/// the cues in their stage colours.
class _StagePreview extends StatelessWidget {
  const _StagePreview({required this.script});

  final ScriptDocument script;

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    if (script.usesNotes) {
      return Directionality(
        textDirection: script.language.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Text(
          [
            script.notes.cards.firstOrNull?.title ?? '',
            ...?script.notes.cards.firstOrNull?.points,
          ].where((s) => s.trim().isNotEmpty).join('\n'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: SaType.title.copyWith(color: stage.stageText),
        ),
      );
    }
    final (tokens, marks) = _opening(script, 40);
    final marked = MarkedText.build(
      tokens: tokens,
      marks: marks.where((m) => m.accepted).toList(),
      style: SaType.title.copyWith(color: stage.stageText, fontWeight: FontWeight.w500),
      colors: CueColors.stage,
    );
    return Directionality(
      textDirection: script.language.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Text.rich(marked.span, maxLines: 3, overflow: TextOverflow.ellipsis),
    );
  }
}

/// The first [count] tokens of [script] and the marks that fit in them.
(List<Token>, List<Mark>) _opening(ScriptDocument script, int count) {
  final tokens = script.tokens.take(count).toList();
  final marks = [
    for (final m in script.marks)
      if (m.end < tokens.length) m,
  ];
  return (tokens, marks);
}

class _Check extends StatelessWidget {
  const _Check({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SaSpace.s3, vertical: SaSpace.s1 + 2),
      decoration: BoxDecoration(color: stage.stageChrome, borderRadius: BorderRadius.circular(SaRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: stage.stageOk),
          const SizedBox(width: SaSpace.s1 + 2),
          Text(text, style: SaType.caption.copyWith(color: stage.stageChromeText)),
        ],
      ),
    );
  }
}

/// No scripts yet: the samples, already marked up, are one tap away.
class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    return Container(
      padding: const EdgeInsets.all(SaSpace.s5),
      decoration: BoxDecoration(
        color: stage.stage,
        borderRadius: BorderRadius.circular(SaRadius.lg),
        boxShadow: SaTheme.of(context).shadowFloat,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR FIRST TAKE', style: SaType.signalLabel.copyWith(color: stage.stageChromeText)),
          const SizedBox(height: SaSpace.s2),
          Text(
            'Write a script and the director marks it up: pauses, stress, pace and energy, '
            'shown on the prompter while you record.',
            style: SaType.body.copyWith(color: stage.stageText),
          ),
          const SizedBox(height: SaSpace.s4),
          Wrap(
            spacing: SaSpace.s2,
            runSpacing: SaSpace.s2,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: stage.stageText,
                  foregroundColor: stage.stage,
                  textStyle: SaType.label,
                ),
                onPressed: () async {
                  final library = AppScope.of(context).library;
                  for (final s in sampleScripts().reversed) {
                    await library.save(s);
                  }
                },
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Add sample scripts (English, French, Arabic)'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: stage.stageText,
                  side: BorderSide(color: stage.stageGlassEdge),
                  textStyle: SaType.label,
                ),
                onPressed: () => createDocument(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New script'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- Scripts as marked pages ----------------------------------------------------

class _PageCard extends StatefulWidget {
  const _PageCard({super.key, required this.script, required this.onTap});

  static const width = 220.0;
  static const height = 196.0;

  final ScriptDocument script;
  final VoidCallback onTap;

  @override
  State<_PageCard> createState() => _PageCardState();
}

class _PageCardState extends State<_PageCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    final script = widget.script;
    final rtl = script.language.isRtl;
    final colors = CueColors.forStudio(context);
    final (tokens, marks) = _opening(script, 36);
    final marked = MarkedText.build(
      tokens: tokens,
      marks: marks,
      style: (rtl ? SaType.scriptEditAr : SaType.scriptEdit).copyWith(fontSize: SaType.bodySm.fontSize, color: p.ink2),
      colors: colors,
      stressStyle: StressStyle.marker,
    );
    String? note;
    for (final m in script.marks) {
      if (m.note != null) {
        note = pencilCase(m.note!);
        break;
      }
    }
    final reduce = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedSlide(
        offset: _hover && !reduce ? const Offset(0, -0.015) : Offset.zero,
        duration: SaDurations.base,
        curve: SaEasing.standard,
        child: Material(
          color: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SaRadius.md),
            side: BorderSide(color: _hover ? p.lineStrong : p.line),
          ),
          elevation: _hover ? 3 : 0,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: SizedBox(
              width: _PageCard.width,
              height: _PageCard.height,
              child: Padding(
                padding: const EdgeInsets.all(SaSpace.s3 + 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      script.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: rtl && script.title.isEmpty ? TextDirection.rtl : null,
                      style: SaType.body.copyWith(
                        fontFamily: SaFonts.display,
                        fontFamilyFallback: SaFonts.displayFallback,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                    // The director's first note, in pencil, tucked under the title.
                    if (note != null)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Transform.rotate(
                          angle: -0.05,
                          child: Text(
                            note,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (rtl ? SaType.noteAr : SaType.note).copyWith(color: p.ink3),
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: SaSpace.s2),
                    Expanded(
                      child: ClipRect(
                        child: OverflowBox(
                          alignment: AlignmentDirectional.topStart,
                          maxHeight: double.infinity,
                          child: TweenAnimationBuilder<double>(
                            // The director's pass: the marks draw in as the desk arrives.
                            tween: Tween(begin: reduce ? 1 : 0, end: 1),
                            duration: SaDurations.beat,
                            curve: SaEasing.standard,
                            builder: (context, reveal, _) => ScriptPage(
                              text: script.usesNotes ? TextSpan(text: [script.notes.cards.firstOrNull?.title ?? '', ...?script.notes.cards.firstOrNull?.points].join('\n'), style: (rtl ? SaType.scriptEditAr : SaType.scriptEdit).copyWith(color: p.ink)) : marked.span,
                              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                              markers: script.usesNotes ? const [] : marked.stressRanges,
                              notes: const [],
                              markerColor: colors.marker,
                              noteStyle: SaType.note,
                              ruleColor: Colors.transparent,
                              reveal: reveal,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: SaSpace.s2),
                    Row(
                      children: [
                        Icon(styleIcon(script.style), size: 15, color: p.ink3),
                        const SizedBox(width: SaSpace.s1),
                        Expanded(
                          child: Text(
                            '${script.usesNotes ? 'Notes' : script.style.label} · \u2068${script.language.label}\u2069',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SaType.caption.copyWith(color: p.ink3),
                          ),
                        ),
                        if (script.pendingCount > 0)
                          Tooltip(
                            message: '${script.pendingCount} suggested marks to review',
                            child: Container(
                              width: SaSpace.s2,
                              height: SaSpace.s2,
                              decoration: BoxDecoration(color: p.cue, shape: BoxShape.circle),
                            ),
                          ),
                        for (var i = 0; i < script.takes.length.clamp(0, 5); i++)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 3),
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(color: p.ink3, shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewPageCard extends StatelessWidget {
  const _NewPageCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SaRadius.md),
        side: BorderSide(color: p.lineStrong, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(SaRadius.md),
        onTap: onTap,
        child: SizedBox(
          width: _PageCard.width,
          height: _PageCard.height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: p.primary, borderRadius: BorderRadius.circular(SaRadius.md)),
                child: Icon(Icons.add_rounded, color: p.onPrimary),
              ),
              const SizedBox(height: SaSpace.s2),
              Text(
                'New script',
                style: SaType.body.copyWith(color: p.ink, fontWeight: FontWeight.w700),
              ),
              Text('Write or paste', style: SaType.caption.copyWith(color: p.ink2)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Takes ------------------------------------------------------------------------

/// A take as a 16:9 stage thumbnail with its duration, script and date.
/// Opening it shows the file in Explorer on Windows (in-app playback is
/// still to come).
class TakeThumb extends StatelessWidget {
  const TakeThumb({super.key, required this.script, required this.take, required this.number});

  static const width = 200.0;

  final ScriptDocument script;
  final Take take;
  final int number;

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    final stage = SaPalette.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(SaRadius.sm),
        onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => TakeReviewScreen(script: script, take: take))),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(SaRadius.sm),
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 0.9,
                    colors: [stage.stageChrome, stage.stage],
                  ),
                ),
                child: Stack(
                  children: [
                    Center(child: Icon(Icons.play_arrow_rounded, color: stage.stageChromeText, size: 32)),
                    PositionedDirectional(
                      end: SaSpace.s2,
                      bottom: SaSpace.s2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: SaSpace.s1 + 1, vertical: 1),
                        decoration: BoxDecoration(
                          color: stage.stageScrim,
                          borderRadius: BorderRadius.circular(SaRadius.xs),
                        ),
                        child: Text(
                          formatDuration(take.duration),
                          style: SaType.meter.copyWith(color: stage.stageText),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: SaSpace.s1 + 2),
            Text(
              '${script.displayTitle} · T$number',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SaType.label.copyWith(color: p.ink, fontWeight: FontWeight.w600),
            ),
            Text(_when(take.recordedAt), style: SaType.caption.copyWith(color: p.ink3)),
            if (take.mode != TakeMode.camera || take.recovered)
              Text(
                '${take.mode == TakeMode.both
                    ? 'Screen + camera'
                    : take.mode == TakeMode.screen
                    ? 'Screen'
                    : 'Camera'}${take.recovered ? ' · Recovered' : ''}',
                style: SaType.caption.copyWith(color: p.ink2),
              ),
          ],
        ),
      ),
    );
  }

  static String _when(DateTime at) {
    final now = DateTime.now();
    final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    if (at.year == now.year && at.month == now.month && at.day == now.day) {
      return 'Today, $time';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (at.year == yesterday.year && at.month == yesterday.month && at.day == yesterday.day) {
      return 'Yesterday, $time';
    }
    return '${at.day}/${at.month}/${at.year}';
  }
}

/// Shows where a take's file is: selected in Explorer on Windows,
/// otherwise its path.
Future<void> showTakeFile(BuildContext context, Take take) async {
  if (!File(take.path).existsSync()) {
    showMessage(context, 'This take\'s file is no longer on disk.');
    return;
  }
  if (Platform.isWindows) {
    await Process.run('explorer', ['/select,', take.path]);
    return;
  }
  if (context.mounted) showMessage(context, take.path);
}
