import 'package:flutter/material.dart';

import '../model/video_export.dart';
import '../model/caption_style.dart';
import '../render/export_processor.dart';
import '../render/export_batch.dart';
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
    this.hasRoomTone = false,
    this.roomToneJoins = false,
    this.onRoomToneJoins,
    this.hasScreenActivity = false,
    this.autoZoom = true,
    this.onAutoZoom,
    this.clickHighlights = true,
    this.onClickHighlights,
    this.showShortcuts = true,
    this.onShowShortcuts,
    this.hasScreen = false,
    this.screenFrame = true,
    this.onScreenFrame,
    this.hasCameraEmphasis = false,
    this.cameraPunch = true,
    this.onCameraPunch,
    this.cameraClear = true,
    this.onCameraClear,
    this.hasMotionBlur = false,
    this.motionBlur = true,
    this.onMotionBlur,
    this.balanceSound = true,
    this.onBalanceSound,
    this.softenSharpSound = false,
    this.onSoftenSharpSound,
    this.reduceNoise = false,
    this.onReduceNoise,
    this.batch,
    this.moreFormats = false,
    this.onMoreFormats,
    this.extraFormats = const {},
    this.onExtraFormat,
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
  final bool hasRoomTone, roomToneJoins;
  final ValueChanged<bool>? onRoomToneJoins;
  final bool hasScreenActivity, autoZoom;
  final ValueChanged<bool>? onAutoZoom;
  final bool clickHighlights;
  final ValueChanged<bool>? onClickHighlights;
  final bool showShortcuts;
  final ValueChanged<bool>? onShowShortcuts;
  final bool hasScreen, screenFrame;
  final ValueChanged<bool>? onScreenFrame;
  final bool hasCameraEmphasis, cameraPunch;
  final ValueChanged<bool>? onCameraPunch;
  final bool cameraClear;
  final ValueChanged<bool>? onCameraClear;
  final bool hasMotionBlur, motionBlur;
  final ValueChanged<bool>? onMotionBlur;
  final bool balanceSound;
  final ValueChanged<bool>? onBalanceSound;
  final bool softenSharpSound;
  final ValueChanged<bool>? onSoftenSharpSound;
  final bool reduceNoise;
  final ValueChanged<bool>? onReduceNoise;
  final ExportBatch? batch;
  final bool moreFormats;
  final ValueChanged<bool>? onMoreFormats;
  final Set<VideoFormat> extraFormats;
  final void Function(VideoFormat, bool)? onExtraFormat;
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
          '${video.roomTone != null ? ' · Room tone at cuts' : ''}'
          '${video.zoomCount > 0 ? ' · ${video.zoomCount} zooms' : ''}'
          '${video.clickCount > 0 ? ' · ${video.clickCount} click highlights' : ''}'
          '${video.shortcutCount > 0 ? ' · ${video.shortcutCount} shortcuts' : ''}'
          '${video.screenFrame ? ' · Framed screen' : ''}'
          '${video.cameraPunchCount > 0 ? ' · ${video.cameraPunchCount} camera accents' : ''}'
          '${video.cameraClear ? ' · Camera stays clear' : ''}'
          '${video.motionBlur ? ' · Soft zoom motion' : ''}'
          '${video.balanceSound ? ' · Balanced volume' : ''}'
          '${video.softenSharpSound ? ' · Softer S sounds' : ''}'
          '${video.reduceNoise ? ' · Reduced noise' : ''}',
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
    final queue = batch;
    final count =
        1 + (moreFormats ? extraFormats.where((f) => f != format).length : 0);
    final exporting = (queue?.busy ?? false) || job.busy;
    final attaching = job.phase == ExportPhase.saving;
    final canStop =
        exporting &&
        (!attaching ||
            (queue != null &&
                queue.busy &&
                queue.saved + 1 < queue.total &&
                !queue.cancelled));
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
              label: Text(count > 1 ? 'Save $count videos' : 'Save video'),
            ),
            if (canStop)
              OutlinedButton.icon(
                onPressed: queue?.cancelled == true
                    ? null
                    : queue?.cancel ?? job.cancel,
                icon: const Icon(Icons.close_rounded),
                label: Text(
                  attaching ? 'Stop after this video' : 'Cancel export',
                ),
              ),
          ],
        ),
        if (onMoreFormats != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: moreFormats,
            onChanged: busy ? null : (value) => onMoreFormats!(value ?? false),
            title: const Text('Also save other formats'),
            subtitle: const Text(
              'Use the same cut, captions and effects for every version.',
            ),
          ),
        if (moreFormats)
          Wrap(
            spacing: SaSpace.s2,
            runSpacing: SaSpace.s2,
            children: [
              for (final extra in VideoFormat.values)
                if (extra != format)
                  FilterChip(
                    label: Text(extra.label),
                    labelStyle: SaType.label.copyWith(
                      color: extraFormats.contains(extra) ? p.onPrimary : p.ink,
                    ),
                    selected: extraFormats.contains(extra),
                    onSelected: busy || onExtraFormat == null
                        ? null
                        : (value) => onExtraFormat!(extra, value),
                  ),
            ],
          ),
        Text(
          hasScreenActivity && autoZoom
              ? 'Saves a new MP4 on this device.'
              : 'Keeps the whole picture and saves a new MP4 on this device.',
          style: SaType.bodySm.copyWith(color: p.ink2),
        ),
        const SizedBox(height: SaSpace.s1),
        Text(
          'Add or remove effects after recording. Each save makes a new version and keeps your original and earlier videos.',
          style: SaType.bodySm.copyWith(color: p.ink2),
        ),
        if (hasCameraEmphasis)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: cameraPunch,
            onChanged: busy
                ? null
                : (value) => onCameraPunch?.call(value ?? false),
            title: const Text('Emphasize the camera'),
            subtitle: const Text(
              'Gently zoom in on marked emphasis in takes of 20 seconds or more.',
            ),
          ),
        if (hasCamera && includeCamera && hasScreenActivity)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: cameraClear,
            onChanged: busy
                ? null
                : (value) => onCameraClear?.call(value ?? false),
            title: const Text('Keep the camera clear'),
            subtitle: const Text(
              'Move the camera aside when it covers the pointer or a zoom target.',
            ),
          ),
        if (hasScreen)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: screenFrame,
            onChanged: busy
                ? null
                : (value) => onScreenFrame?.call(value ?? false),
            title: const Text('Frame the screen'),
            subtitle: const Text('Add rounded corners and a soft background.'),
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
        if (hasAudioJoins && softAudioJoins && hasRoomTone)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: roomToneJoins,
            onChanged: busy
                ? null
                : (value) => onRoomToneJoins?.call(value ?? false),
            title: const Text('Use room tone at cuts'),
            subtitle: const Text(
              'Uses quiet sound from the parts you keep. Words and timing stay the same.',
            ),
          ),
        if (onReduceNoise != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: reduceNoise,
            onChanged: busy
                ? null
                : (value) => onReduceNoise?.call(value ?? false),
            title: const Text('Reduce background noise'),
            subtitle: const Text(
              'Best for steady hiss or fan noise. This also affects any computer sound.',
            ),
          ),
        if (onSoftenSharpSound != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: softenSharpSound,
            onChanged: busy
                ? null
                : (value) => onSoftenSharpSound?.call(value ?? false),
            title: const Text('Soften harsh S sounds'),
            subtitle: const Text(
              'Gently lower sharp sounds. This also affects any computer sound.',
            ),
          ),
        if (onBalanceSound != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: balanceSound,
            onChanged: busy
                ? null
                : (value) => onBalanceSound?.call(value ?? false),
            title: const Text('Balance sound volume'),
            subtitle: const Text(
              'Make quiet sound easier to hear. Silent or very short sound keeps its volume.',
            ),
          ),
        if (hasMotionBlur && autoZoom)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: motionBlur,
            onChanged: busy
                ? null
                : (value) => onMotionBlur?.call(value ?? false),
            title: const Text('Soften zoom motion'),
            subtitle: const Text(
              'Add gentle blur while the screen zooms or pans.',
            ),
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
        if (exporting) ...[
          const SizedBox(height: SaSpace.s3),
          LinearProgressIndicator(
            value: queue?.busy == true
                ? queue!.progress
                : job.phase == ExportPhase.rendering
                ? job.progress
                : null,
          ),
          const SizedBox(height: SaSpace.s2),
          Text(
            queue?.busy == true && queue!.total > 1
                ? '${attaching ? 'Saving' : 'Making'} video ${queue.saved + 1} of ${queue.total} · ${queue.current?.label ?? ''}'
                : attaching
                ? 'Checking and saving your video…'
                : 'Making your video…',
            style: SaType.signalLabel.copyWith(color: p.ink2),
          ),
        ],
        if (queue != null && !queue.busy && queue.total > 1)
          Text(
            '${queue.saved} of ${queue.total} videos saved.${queue.cancelled ? ' The remaining videos were cancelled.' : ''}',
            style: SaType.bodySm.copyWith(color: p.ink2),
          ),
        if (queue?.problem != null && queue!.problem != job.problem)
          Text(queue.problem!, style: SaType.bodySm.copyWith(color: p.danger)),
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
