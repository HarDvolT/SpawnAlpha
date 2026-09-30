# ModeSwitcher

The segmented control that picks a recording mode: Camera, Screen or Screen + camera.

- **Use** at the top of the record screen, before a take. It is disabled while recording.
- **Consumer provides** the modes the platform supports (on iOS only Camera for now; on Android, Screen when MediaProjection is available) and the change handler. Remember the last mode per device.
- Icons: `videocam_rounded`, `screen_share_rounded`, `picture_in_picture_alt_rounded`. Labels are always shown beside the icons, except on phones narrower than 360px.
- Switching mode moves the prompter to its place for that mode (see the Recording section). The move animates over `dur-base`.
- **Don't** hide an unavailable mode without saying why: show it disabled, with a tooltip such as "Screen recording on iPhone is coming later".
