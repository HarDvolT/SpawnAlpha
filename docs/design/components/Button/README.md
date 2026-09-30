# Button

Studio buttons: one primary action per screen, outlined secondaries, the amber cue button, plain, danger and icon-only.

- **Primary** (`primary` fill, `on-primary` text): the one main action on a screen, such as Mark up, Save key or Record (in the Studio).
- **Secondary** (outlined in `line-strong`, `surface` fill): every other action.
- **Cue** (`cue` fill, `on-cue` text): only Accept all, the action that brings the director's proposals to life.
- **Plain**: low-emphasis actions next to a stronger one (Discard next to Accept all).
- **Danger** (`danger` text): destructive actions, always confirmed in a dialog that repeats the verb ("Delete script").
- **Icon**: 40px square, `radius-md`, with an accessible label and a tooltip.
- Height 40px, `radius-md`, `label` text in sentence case, optional 20px leading icon. Press scales to 0.97 over `dur-instant`. Focus: 2px `focus` ring with a 2px gap. Disabled: 38% opacity.
- **Consumer provides** the label, an optional icon and the handler. On the stage, use icon buttons on `stage-chrome` instead.
