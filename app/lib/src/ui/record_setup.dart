import 'dart:io';

import 'package:flutter/material.dart';

import '../recording/mic_monitor.dart';
import '../recording/sound_check.dart';
import '../model/script_document.dart';
import '../theme/theme.dart';
import 'recording_widgets.dart';

/// Pieces of the record set-up on a desktop (docs/design/components/
/// RecordSetup): the live preview on one side, and four decisions in a rail
/// on the other, top to bottom. All on the stage.

/// Where a sound check is.
enum SoundCheckState { idle, listening, heard, quiet, silent }

extension SoundCheckStateOf on SoundVerdict {
  SoundCheckState get state => switch (this) {
    SoundVerdict.heard => SoundCheckState.heard,
    SoundVerdict.quiet => SoundCheckState.quiet,
    SoundVerdict.silent => SoundCheckState.silent,
  };
}

/// One numbered decision in the rail, with its state on the right: in
/// `stage-ok` or `stage-warn`, always with an icon.
class SetupStep extends StatelessWidget {
  const SetupStep({
    super.key,
    required this.number,
    required this.title,
    required this.child,
    this.state,
    this.ok,
  });

  final int number;
  final String title;
  final Widget child;

  /// "ON", "HEARD", "BLOCKED"…, or null for none.
  final String? state;

  /// True: the state is good. False: it needs the user. Null: neutral.
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    final stateColor = ok == null
        ? stage.stageChromeText
        : (ok! ? stage.stageOk : stage.stageWarn);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        SaSpace.s3,
        SaSpace.s3 - 2,
        SaSpace.s3,
        SaSpace.s3,
      ),
      decoration: BoxDecoration(
        color: stage.stageText.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(SaRadius.md),
        border: Border.all(color: stage.stageLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: stage.stageLine,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: SaType.signalLabel.copyWith(
                    color: stage.stageChromeText,
                  ),
                ),
              ),
              const SizedBox(width: SaSpace.s2),
              Expanded(
                child: Text(
                  title,
                  style: SaType.label.copyWith(
                    color: stage.stageText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (state != null) ...[
                if (ok != null)
                  Icon(
                    ok! ? Icons.check_circle_rounded : Icons.warning_rounded,
                    size: 15,
                    color: stateColor,
                  ),
                const SizedBox(width: SaSpace.s1),
                Text(
                  state!,
                  style: SaType.signalLabel.copyWith(color: stateColor),
                ),
              ],
            ],
          ),
          const SizedBox(height: SaSpace.s2),
          child,
        ],
      ),
    );
  }
}

/// Explicit whole-playback choice, kept visible beside microphone setup.
class ComputerSoundChoice extends StatelessWidget {
  const ComputerSoundChoice({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    return Padding(
      padding: const EdgeInsets.all(SaSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Computer sound',
                  style: SaType.label.copyWith(color: stage.stageText),
                ),
              ),
              Semantics(
                label: 'Computer sound',
                child: Switch.adaptive(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: stage.stageText,
                  activeTrackColor: stage.stageOk,
                  inactiveThumbColor: stage.stageChromeText,
                  inactiveTrackColor: stage.stageLine,
                ),
              ),
            ],
          ),
          Text(
            'Records the default Windows playback sound, not only the chosen window. Stays on this PC.',
            style: SaType.caption.copyWith(color: stage.stageChromeText),
          ),
        ],
      ),
    );
  }
}

/// Camera, Screen and Both. The screen modes arrive in build step 2.
class ActivityChoice extends StatelessWidget {
  const ActivityChoice({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    return Padding(
      padding: const EdgeInsets.all(SaSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Activity for automatic edits',
                  style: SaType.label.copyWith(color: stage.stageText),
                ),
              ),
              Semantics(
                label: 'Activity for automatic edits',
                child: Switch.adaptive(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: stage.stageText,
                  activeTrackColor: stage.stageOk,
                  inactiveThumbColor: stage.stageChromeText,
                  inactiveTrackColor: stage.stageLine,
                ),
              ),
            ],
          ),
          Text(
            'Saves mouse positions, clicks and typing timing on this PC. Never saves what you type. Also saves an extra video for mouse effects. Uses more disk space.',
            style: SaType.caption.copyWith(color: stage.stageChromeText),
          ),
        ],
      ),
    );
  }
}

/// Camera, Screen and Both. The screen modes arrive in build step 2.
class RecordModeTiles extends StatelessWidget {
  const RecordModeTiles({
    super.key,
    this.mode = TakeMode.camera,
    this.onChanged,
    this.screenReady = false,
    this.bothReady = false,
  });
  final TakeMode mode;
  final ValueChanged<TakeMode>? onChanged;
  final bool screenReady, bothReady;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (icon, label, value, ready) in [
          (Icons.videocam_rounded, 'Camera', TakeMode.camera, true),
          (Icons.screen_share_rounded, 'Screen', TakeMode.screen, screenReady),
          (
            Icons.picture_in_picture_alt_rounded,
            'Both',
            TakeMode.both,
            bothReady,
          ),
        ]) ...[
          Expanded(
            child: _ModeTile(
              icon: icon,
              label: label,
              ready: ready,
              selected: mode == value,
              onTap: ready && onChanged != null
                  ? () => onChanged!(value)
                  : null,
            ),
          ),
          if (label != 'Both') const SizedBox(width: SaSpace.s2),
        ],
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.label,
    required this.ready,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool ready;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    final fg = selected ? stage.stage : stage.stageChromeText;
    return Semantics(
      selected: selected,
      button: true,
      enabled: ready,
      child: Tooltip(
        message: ready
            ? 'Record ${label.toLowerCase()}'
            : 'Arrives in the next build',
        child: Material(
          color: selected ? stage.stageText : stage.stageChrome,
          borderRadius: BorderRadius.circular(SaRadius.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(SaRadius.md),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: SaSpace.s2 + 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(SaRadius.md),
                border: Border.all(color: stage.stageGlassEdge),
              ),
              child: Column(
                children: [
                  Icon(icon, color: fg),
                  const SizedBox(height: SaSpace.s1),
                  Text(
                    label,
                    style: SaType.label.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!ready)
                    Text(
                      'NEXT BUILD',
                      style: SaType.signalLabel.copyWith(color: fg),
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

/// Every microphone, each with its own live meter, the Windows default
/// first and labelled. The one that moves when you talk is the right one.
class MicList extends StatelessWidget {
  const MicList({
    super.key,
    required this.monitor,
    required this.onChoose,
    this.enabled = true,
  });

  final MicMonitor monitor;
  final ValueChanged<String?> onChoose;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        if (monitor.available.isEmpty) {
          return Text(
            'No microphone found. Plug one in, then check again.',
            style: SaType.caption.copyWith(color: stage.stageChromeText),
          );
        }
        return Column(
          children: [
            for (final input in monitor.available)
              Builder(
                builder: (context) {
                  final chosen = input == monitor.input;
                  final level = chosen
                      ? monitor.level
                      : monitor.levels[input.id];
                  return Material(
                    color: chosen
                        ? stage.stageText.withValues(alpha: 0.08)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SaRadius.sm),
                      side: chosen
                          ? BorderSide(color: stage.stageGlassEdge)
                          : BorderSide.none,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(SaRadius.sm),
                      onTap: enabled && !chosen
                          ? () => onChoose(input.isDefault ? null : input.id)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SaSpace.s2,
                          vertical: SaSpace.s2 - 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              chosen
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 18,
                              color: chosen
                                  ? stage.stageText
                                  : stage.stageChromeText,
                            ),
                            const SizedBox(width: SaSpace.s2),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    input.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: SaType.label.copyWith(
                                      color: chosen
                                          ? stage.stageText
                                          : stage.stageChromeText,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (input.isDefault)
                                    Text(
                                      'Windows default',
                                      style: SaType.caption.copyWith(
                                        color: stage.stageChromeText,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            LevelMeter(
                              level: level?.meter ?? 0,
                              speaking: chosen && monitor.speaking,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

/// "Check your sound": read a line, and hear whether the microphone heard it.
class SoundCheckRow extends StatelessWidget {
  const SoundCheckRow({
    super.key,
    required this.state,
    required this.micName,
    required this.onCheck,
    this.level = 0,
  });

  final SoundCheckState state;
  final String micName;
  final VoidCallback? onCheck;

  /// The chosen microphone's level, for the big meter while listening.
  final double level;

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    final (icon, color, title, detail) = switch (state) {
      SoundCheckState.idle => (
        Icons.graphic_eq_rounded,
        stage.stageChromeText,
        'Check your sound.',
        'Read one line; nothing is saved.',
      ),
      SoundCheckState.listening => (
        Icons.mic_rounded,
        stage.stageText,
        'Say a line from your script…',
        null,
      ),
      SoundCheckState.heard => (
        Icons.check_circle_rounded,
        stage.stageOk,
        'We hear you.',
        'Good level from $micName.',
      ),
      SoundCheckState.quiet => (
        Icons.volume_down_rounded,
        stage.stageWarn,
        'Very quiet.',
        'Move closer, or raise the level of $micName.',
      ),
      SoundCheckState.silent => (
        Icons.warning_rounded,
        stage.stageWarn,
        'Nothing heard',
        'from $micName. Choose another microphone above.',
      ),
    };
    return Container(
      margin: const EdgeInsets.only(top: SaSpace.s2),
      padding: const EdgeInsets.fromLTRB(
        SaSpace.s3,
        SaSpace.s2,
        SaSpace.s2,
        SaSpace.s2,
      ),
      decoration: BoxDecoration(
        color: stage.stage.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(SaRadius.sm),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: SaSpace.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (detail != null) TextSpan(text: ' $detail'),
                    ],
                  ),
                  style: SaType.caption.copyWith(color: stage.stageText),
                ),
                if (state == SoundCheckState.listening) ...[
                  const SizedBox(height: SaSpace.s1),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(SaRadius.xs),
                    child: LinearProgressIndicator(
                      value: level,
                      minHeight: 6,
                      color: stage.stageText,
                      backgroundColor: stage.stageLine,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (state != SoundCheckState.listening) ...[
            const SizedBox(width: SaSpace.s2),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: stage.stageText,
                side: BorderSide(color: stage.stageGlassEdge),
                textStyle: SaType.label,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onCheck,
              icon: Icon(
                state == SoundCheckState.idle
                    ? Icons.mic_rounded
                    : Icons.replay_rounded,
                size: 16,
              ),
              label: Text(state == SoundCheckState.idle ? 'Check' : 'Again'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Windows is blocking the microphones: say so plainly, name the two
/// switches, and go straight to them.
class BlockedPanel extends StatelessWidget {
  const BlockedPanel({super.key, required this.onRetry});

  final VoidCallback onRetry;

  /// Opens Windows Settings at Privacy & security › Microphone.
  static Future<void> openPrivacySettings() async {
    if (!Platform.isWindows) return;
    await Process.start('explorer.exe', ['ms-settings:privacy-microphone']);
  }

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    return Container(
      padding: const EdgeInsets.all(SaSpace.s3),
      decoration: BoxDecoration(
        color: stage.stageWarn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SaRadius.sm),
        border: Border.all(color: stage.stageWarn.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mic_off_rounded, size: 18, color: stage.stageWarn),
              const SizedBox(width: SaSpace.s2),
              Expanded(
                child: Text(
                  'Windows is blocking the microphone',
                  style: SaType.label.copyWith(
                    color: stage.stageText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SaSpace.s1),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'SpawnAlpha can\'t hear any microphone. In Windows Settings, turn on ',
                ),
                TextSpan(
                  text: 'Microphone access',
                  style: TextStyle(
                    color: stage.stageText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: ' and '),
                TextSpan(
                  text: 'Let desktop apps access your microphone',
                  style: TextStyle(
                    color: stage.stageText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            style: SaType.caption.copyWith(color: stage.stageChromeText),
          ),
          const SizedBox(height: SaSpace.s2),
          Wrap(
            spacing: SaSpace.s2,
            runSpacing: SaSpace.s2,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: stage.stageText,
                  foregroundColor: stage.stage,
                  textStyle: SaType.label,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: openPrivacySettings,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Open privacy settings'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: stage.stageText,
                  side: BorderSide(color: stage.stageGlassEdge),
                  textStyle: SaType.label,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Check again'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
