# PaceRibbon

The review's picture of a take (build step 2): words per minute over time against the coaching style's range, with every marked pause checked.

- **Use** at the top of a take's review, above the per-section scores.
- **Consumer provides** the words-per-minute series (from the word timings of the transcript), the style's range, the take's length and each pause mark with whether it was taken.
- The range is a `tint-slower` band; the pace is a 2.5px `ink` line with a faint area and an emphasised end point; axes in `mono` at `ink-3` on a `line` grid.
- Pause checks sit under the axis: a filled `success` dot for taken, a hollow `warning` ring for missed. The summary chips repeat them with icons (check, error) so colour is never the only signal.
- Tapping a missed pause or a rushed stretch jumps the video and the script to that moment.
- **Don't** show a single overall score without the evidence behind it.
