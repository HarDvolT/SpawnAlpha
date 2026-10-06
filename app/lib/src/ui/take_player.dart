import 'dart:async';

import 'package:flutter/material.dart';

import '../playback/local_playback.dart';
import '../playback/playback_controller.dart';
import '../theme/theme.dart';
import 'format.dart';

class TakePlayer extends StatefulWidget {
  const TakePlayer({
    super.key,
    required this.backend,
    required this.path,
    this.label = 'Original take',
  });
  final LocalPlayback backend;
  final String path, label;
  @override
  State<TakePlayer> createState() => _TakePlayerState();
}

class _TakePlayerState extends State<TakePlayer> with WidgetsBindingObserver {
  late TakePlaybackController _player;
  double? _scrub;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _create();
  }

  void _create() {
    _player = TakePlaybackController(widget.backend);
    if (widget.backend.supported) unawaited(_player.open(widget.path));
  }

  @override
  void didUpdateWidget(TakePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.backend != widget.backend) {
      _player.dispose();
      _scrub = null;
      _create();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_player.pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    return ListenableBuilder(
      listenable: _player,
      builder: (context, _) {
        final status = _player.status;
        final enabled = _player.ready && !_player.commanding;
        final duration = status.duration.inMicroseconds.toDouble();
        final position =
            _scrub ??
            status.position.inMicroseconds.toDouble().clamp(0, duration);
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: SaReview.playerMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: SaType.signalLabel.copyWith(color: p.ink2),
                ),
                const SizedBox(height: SaSpace.s2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: SaReview.playerMaxWidth,
                      maxHeight: SaReview.playerMaxHeight,
                    ),
                    child: AspectRatio(
                      aspectRatio: status.width > 0 && status.height > 0
                          ? status.width / status.height
                          : 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(SaRadius.lg),
                        child: ColoredBox(
                          color: p.stage,
                          child: _player.handle != null && status.frames > 0
                              ? Texture(textureId: _player.handle!.textureId)
                              : Center(
                                  child: _player.loading
                                      ? const CircularProgressIndicator()
                                      : Icon(
                                          Icons.movie_outlined,
                                          color: p.stageText,
                                          size: SaSpace.s8,
                                        ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!widget.backend.supported)
                  Text(
                    'Video playback is available on Windows first.',
                    style: SaType.bodySm.copyWith(color: p.ink2),
                  ),
                if (_player.problem != null) ...[
                  Text(
                    _player.problem!,
                    style: SaType.bodySm.copyWith(color: p.danger),
                  ),
                  TextButton(
                    onPressed: () => _player.open(widget.path),
                    child: const Text('Try playback again'),
                  ),
                ],
                if (widget.backend.supported)
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: status.playing
                              ? 'Pause video'
                              : 'Play video',
                          onPressed: enabled ? _player.toggle : null,
                          icon: Icon(
                            status.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: duration > 0 ? position / duration : 0,
                            semanticFormatterCallback: (value) => formatCutTime(
                              Duration(
                                microseconds: (value * duration).round(),
                              ),
                            ),
                            onChanged: enabled
                                ? (value) =>
                                      setState(() => _scrub = value * duration)
                                : null,
                            onChangeEnd: enabled
                                ? (value) {
                                    _scrub = null;
                                    unawaited(
                                      _player.seek(
                                        Duration(
                                          microseconds: (value * duration)
                                              .round(),
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                          ),
                        ),
                        Text(
                          '${formatDuration(Duration(microseconds: position.round()))} / ${formatDuration(status.duration)}',
                          style: SaType.signalLabel.copyWith(color: p.ink2),
                        ),
                        IconButton(
                          tooltip: _player.muted
                              ? 'Turn video sound on'
                              : 'Mute video',
                          onPressed: enabled ? _player.toggleMute : null,
                          icon: Icon(
                            _player.muted
                                ? Icons.volume_off_outlined
                                : Icons.volume_up_outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
