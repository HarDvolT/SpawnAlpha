import 'dart:async';

import 'package:flutter/material.dart';

import '../recording/screen_preview.dart';
import '../recording/screen_preview_controller.dart';
import '../recording/screen_source.dart';
import '../theme/theme.dart';

class ScreenPreviewScreen extends StatefulWidget {
  const ScreenPreviewScreen({super.key, required this.source, required this.previews});
  final ScreenSource source;
  final ScreenPreviews previews;
  @override
  State<ScreenPreviewScreen> createState() => _ScreenPreviewScreenState();
}

class _ScreenPreviewScreenState extends State<ScreenPreviewScreen> {
  late final _preview = ScreenPreviewController(widget.previews);
  @override
  void initState() {
    super.initState();
    unawaited(_preview.show(widget.source));
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = SaPalette.dark;
    return Theme(
      data: buildTheme(Brightness.dark),
      child: ListenableBuilder(
        listenable: _preview,
        builder: (context, _) => Scaffold(
          backgroundColor: stage.stage,
          appBar: AppBar(
            backgroundColor: stage.stageChrome,
            foregroundColor: stage.stageText,
            title: const Text('Preview screen'),
          ),
          body: Padding(
            padding: const EdgeInsets.all(SaSpace.s4),
            child: Column(
              children: [
                Text(
                  widget.source.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SaType.body.copyWith(color: stage.stageText),
                ),
                const SizedBox(height: SaSpace.s2),
                Text('Live preview only · nothing saved', style: SaType.caption.copyWith(color: stage.stageChromeText)),
                const SizedBox(height: SaSpace.s4),
                Expanded(
                  child: Center(
                    child: switch (_preview.phase) {
                      PreviewPhase.starting => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: SaSpace.s3),
                          Text('Opening preview…', style: SaType.bodySm.copyWith(color: stage.stageChromeText)),
                        ],
                      ),
                      PreviewPhase.live => AspectRatio(
                        aspectRatio: _preview.aspectRatio,
                        child: Texture(textureId: _preview.handle!.textureId),
                      ),
                      PreviewPhase.unavailable => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_rounded, color: stage.stageWarn),
                          const SizedBox(height: SaSpace.s3),
                          Text(
                            _preview.problem!,
                            textAlign: TextAlign.center,
                            style: SaType.bodySm.copyWith(color: stage.stageWarn),
                          ),
                          const SizedBox(height: SaSpace.s3),
                          FilledButton.icon(
                            onPressed: () => _preview.show(widget.source),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
