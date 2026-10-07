import 'package:flutter/material.dart';

import '../model/video_export.dart';
import '../model/caption_style.dart';
import '../render/export_processor.dart';
import '../theme/theme.dart';
import 'format.dart';

class VideoExportPanel extends StatelessWidget {
  const VideoExportPanel({
    super.key,
    required this.format,
    required this.onFormat,
    required this.onExport,
    required this.job,
    required this.busy,
    required this.supported,
    required this.videos,
    required this.onView,
    required this.onShow,
    this.hasCamera = false,
    this.includeCamera = true,
    this.onCamera,
    this.hasCaptions = false,
    this.burnedCaptions = true,
    this.onBurnedCaptions,
    this.captionStyle = CaptionStyle.readable,
    this.onCaptionStyle,
    this.captionMotion = true,
    this.onCaptionMotion,
    this.hasAudioJoins = false,
    this.softAudioJoins = true,
    this.onSoftAudioJoins,
    this.hasScreenActivity = false,
    this.autoZoom = true,
    this.onAutoZoom,
    this.clickHighlights = true,
    this.onClickHighlights,
    this.showShortcuts = true,
    this.onShowShortcuts,
  });
  final VideoFormat format;
  final ValueChanged<VideoFormat> onFormat;
  final VoidCallback onExport;
  final ExportProcessor job;
  final bool busy,
      supported,
      hasCamera,
      includeCamera,
      hasCaptions,
      burnedCaptions;
  final ValueChanged<bool>? onCamera;
  final ValueChanged<bool>? onBurnedCaptions;
  final CaptionStyle captionStyle;
  final ValueChanged<CaptionStyle>? onCaptionStyle;
  final bool captionMotion;
  final ValueChanged<bool>? onCaptionMotion;
  final bool hasAudioJoins, softAudioJoins;
  final ValueChanged<bool>? onSoftAudioJoins;
  final bool hasScreenActivity, autoZoom;
  final ValueChanged<bool>? onAutoZoom;
  final bool clickHighlights;
  final ValueChanged<bool>? onClickHighlights;
  final bool showShortcuts;
  final ValueChanged<bool>? onShowShortcuts;
  final List<VideoExport> videos;
  final ValueChanged<VideoExport> onView, onShow;

  Widget _saved(VideoExport video, SaPalette p) => Padding(
    padding: const EdgeInsets.only(top: SaSpace.s2),
    child: Wrap(
      spacing: SaSpace.s2,
      runSpacing: SaSpace.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${video.createdAt.toLocal().toString().substring(0, 16)} · '
          '${video.format.label} · ${formatCutTime(video.duration)}'
          '${video.burnedCaptions ? ' · ${video.captionStyle.label} captions${video.captionMotion ? '' : ' · Still'}' : ''}'
          '${video.softAudioJoins ? ' · Soft sound joins' : ''}'
          '${video.zoomCount > 0 ? ' · ${video.zoomCount} zooms' : ''}'
          '${video.clickCount > 0 ? ' · ${video.clickCount} click highlights' : ''}'
          '${video.shortcutCount > 0 ? ' · ${video.shortcutCount} shortcuts' : ''}',
          style: SaType.signalLabel.copyWith(color: p.ink2),
        ),
        TextButton.icon(
          onPressed: () => onView(video),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Watch saved video'),
        ),
        TextButton.icon(
          onPressed: () => onShow(video),
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Show saved files'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final p = SaTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Save your video', style: SaType.title.copyWith(color: p.ink)),
        const SizedBox(height: SaSpace.s3),
        Wrap(
          spacing: SaSpace.s3,
          runSpacing: SaSpace.s3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<VideoFormat>(
              value: format,
              items: [
                for (final format in VideoFormat.values)
                  DropdownMenuItem(value: format, child: Text(format.label)),
              ],
              onChanged: busy
                  ? null
                  : (value) {
                      if (value != null) onFormat(value);
                    },
            ),
            FilledButton.icon(
              onPressed: busy || !supported ? null : onExport,
              icon: const Icon(Icons.movie_creation_outlined),
              label: const Text('Save video'),
            ),
            if (job.busy && job.phase != ExportPhase.saving)
              OutlinedButton.icon(
                onPressed: job.cancel,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel export'),
              ),
          ],
        ),
        Text(
          hasScreenActivity && autoZoom
              ? 'Saves a new MP4 on this device.'
              : 'Keeps the whole picture and saves a new MP4 on this device.',
          style: SaType.bodySm.copyWith(color: p.ink2),
        ),
        if (hasAudioJoins)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: softAudioJoins,
            onChanged: busy
                ? null
                : (value) => onSoftAudioJoins?.call(value ?? false),
            title: const Text('Soften sound at cuts'),
            subtitle: const Text('Smooth the joins while keeping word timing.'),
          ),
        if (hasScreenActivity)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: clickHighlights,
            onChanged: busy
                ? null
                : (value) => onClickHighlights?.call(value ?? false),
            title: const Text('Highlight clicks'),
            subtitle: const Text('Show a fading ring where you click.'),
          ),
        if (hasScreenActivity)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: autoZoom,
            onChanged: busy
                ? null
                : (value) => onAutoZoom?.call(value ?? false),
            title: const Text('Auto-zoom screen activity'),
            subtitle: const Text('Follow clicks and typing on this device.'),
          ),
        if (hasScreenActivity)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: showShortcuts,
            onChanged: busy
                ? null
                : (value) => onShowShortcuts?.call(value ?? false),
            title: const Text('Show shortcuts'),
            subtitle: const Text(
              'Show Ctrl+C and similar actions. Ordinary typing stays hidden.',
            ),
          ),
        if (hasCaptions)
          Text(
            'SRT and VTT caption files are saved beside the video.',
            style: SaType.bodySm.copyWith(color: p.ink2),
          ),
        if (hasCaptions)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: burnedCaptions,
            onChanged: busy
                ? null
                : (value) => onBurnedCaptions?.call(value ?? false),
            title: const Text('Put captions on video'),
            subtitle: const Text('Your corrected words and cut timing.'),
          ),
        if (hasCaptions && burnedCaptions) ...[
          Text(
            'Caption style',
            style: SaType.signalLabel.copyWith(color: p.ink2),
          ),
          DropdownButton<CaptionStyle>(
            value: captionStyle,
            hint: const Text('Caption style'),
            items: [
              for (final style in CaptionStyle.values)
                DropdownMenuItem(value: style, child: Text(style.label)),
            ],
            onChanged: busy
                ? null
                : (value) {
                    if (value != null) onCaptionStyle?.call(value);
                  },
          ),
          Text(
            captionStyle.description,
            style: SaType.bodySm.copyWith(color: p.ink2),
          ),
          if (captionStyle != CaptionStyle.readable)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: !captionMotion,
              onChanged: busy
                  ? null
                  : (value) => onCaptionMotion?.call(!(value ?? false)),
              title: const Text('Still captions'),
              subtitle: const Text(
                'Keep word timing and emphasis, with less movement.',
              ),
            ),
        ],
        if (hasCamera)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: includeCamera,
            onChanged: busy ? null : (value) => onCamera?.call(value ?? false),
            title: const Text('Include the camera in the corner'),
          ),
        if (!supported)
          Text(
            'Video export is available on Windows first.',
            style: SaType.bodySm.copyWith(color: p.ink2),
          ),
        if (job.busy) ...[
          const SizedBox(height: SaSpace.s3),
          LinearProgressIndicator(
            value: job.phase == ExportPhase.rendering ? job.progress : null,
          ),
          const SizedBox(height: SaSpace.s2),
          Text(
            job.phase == ExportPhase.saving
                ? 'Checking and saving your video…'
                : 'Making your video…',
            style: SaType.signalLabel.copyWith(color: p.ink2),
          ),
        ],
        if (job.problem != null)
          Text(job.problem!, style: SaType.bodySm.copyWith(color: p.danger)),
        if (job.notice != null)
          Text(job.notice!, style: SaType.bodySm.copyWith(color: p.ink2)),
        if (job.phase == ExportPhase.cancelled)
          Text(
            'Export cancelled. Your original and cut are safe.',
            style: SaType.bodySm.copyWith(color: p.ink2),
          ),
        for (final video in videos.take(8)) _saved(video, p),
        if (videos.length > 8)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Earlier saved videos'),
            children: [for (final video in videos.skip(8)) _saved(video, p)],
          ),
      ],
    );
  }
}
