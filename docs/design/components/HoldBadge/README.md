# HoldBadge

The pill that names a pause while the prompter holds: PAUSE, LONG PAUSE or BREATHE, with a ring that empties over the hold.

- **Use** only on the stage, just above the reading line, and only while the scroll is holding on a marked gap. Natural beats at punctuation get no badge.
- **Consumer provides** the kind (pause, long pause, breath) and the hold's length and progress, both from the delivery timeline.
- Colours: `stage-pause` for Pause and Long pause, `stage-breath` for Breathe, on a translucent black pill with a 2px border in the same colour. Label in capitals with 0.12em tracking; this is the only place cue names are capitalised.
- Motion: arrives over `dur-quick` (fade and a 4px rise), the ring empties linearly over the hold, leaves over `dur-quick` as the next word starts. Breathe also swells to 1.06 and back, like an inhale; reduced motion drops the swell but keeps the ring.
- **Don't** show it in the Studio or for anything but a hold.
