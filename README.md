# Page Turn Animation

A KOReader plugin that adds a smooth **wipe animation** when you turn a
page, instead of the instant flash. Fully configurable: pick the effect,
the direction, the angle, the speed, and even set a different effect per
tap zone on the screen.

> Originally based on a patch by @Euphoriyy, rewritten and extended with
> AI assistance: configurable speed/steps, more effects, per-zone effect
> grid, automatic angle, night mode tuning, and multi-language menus.

---

## 🛠️ Where to find it

**Tools ➔ More tools ➔ Software page turn animation**

Every setting below lives in this one submenu.

---

## 🌐 Language

The plugin's own menus and help text ship in **English, Spanish and
Brazilian Portuguese**. It's the first item in the submenu:

**Language / Idioma**

Leave it on **Auto** to follow KOReader's own UI language (falls back to
English for any language the plugin doesn't ship), or pick one manually.
Changing it applies immediately to the submenu; the plugin's name and
description in the Plugin Manager list only refresh on the next KOReader
start.

---

## 🔌 Turning it on

- **Plugin active** — master switch. Turns the whole plugin on/off
  (installs or removes its hook into KOReader's page-turning code).
- **Enable animation** — turns the animation itself on/off without
  disabling the plugin, so all your settings stay saved for when you
  turn it back on.

---

## 🎬 Effects

Two independent pickers, one for each direction:

- **Next page effect**
- **Previous page effect**

Each can be set to any of these:

| Effect | What it does |
|---|---|
| **Horizontal** | Plain left↔right band wipe. Fixed, ignores the angle setting. |
| **Vertical** | Plain top↔bottom band wipe. Fixed, ignores the angle setting. |
| **Top left / Top right / Bottom left / Bottom right** | Diagonal wipe pivoting from that screen corner. Angle controlled by **Diagonal angle** below (or overridden per-cell — see the effect grid). |
| **Diagonal from right (auto)** | Diagonal wipe from the right side. Automatically picks the **top-right** or **bottom-right** corner depending on whether your tap lands in the top or bottom half of the screen, and always uses the **automatic angle** (see below) — no need to turn that toggle on separately. |
| **Diagonal from left (auto)** | Same as above, mirrored to the left side (top-left / bottom-left). |

Next-page and previous-page effects are fully independent — you can, for
example, have the next page wipe in from the right and the previous page
wipe in from the left.

---

## 📐 Diagonal angle

Sets the angle (in degrees, measured from the screen's horizontal edge)
of the diagonal wipe's front line, for the 4 fixed corner effects.

- **45°** (default) — classic symmetric diagonal.
- **Lower** values flatten it towards a top-to-bottom band sweep.
- **Higher** values (up to **89°**, as close to vertical as the math
  safely allows) steepen it towards a left-to-right sweep.

This is one shared value for both directions — not one angle for "next"
and another for "previous" — unless you override a specific cell in the
effect grid (see below).

### 🎯 Automatic angle (by tap position)

Instead of a fixed angle, calculate it every turn from **where on the
screen you tapped**:

- Tapping near the **vertical middle** of the screen gives the steepest
  angle (**89°**, closest to a left/right sweep).
- Tapping near the **top or bottom edge** flattens it back down to
  **45°**.
- Everything in between is a smooth gradient.

Only applies to the 4 fixed corner effects (not Horizontal/Vertical), and
only to turns triggered by an actual on-screen tap — swipes, buttons and
physical keys have no tap position to go on, so they keep using the
fixed **Diagonal angle** instead. A cell's own angle override (see the
effect grid) always takes priority over this.

> The **"Diagonal from right/left (auto)"** effects above always use this
> automatic angle, regardless of whether this toggle is on.

#### Central zone (%)

Fine-tunes the automatic angle: sets how much of the half-screen
(measured from the exact vertical middle out to the top/bottom edge)
stays **flat at 89°** before the gradient down to 45° kicks in.

- **0%** (default) — no flat zone, the gradient starts right at the
  center.
- **e.g. 20%** — tapping anywhere within 20% of the center still gives
  89°; only past that does the angle start dropping, still reaching
  exactly 45° right at the edge.

Affects both the automatic-angle toggle above and the "Diagonal from
right/left" effects, since they share this same calculation.

---

## 🔲 Effect grid — a different effect per screen zone

Instead of (or on top of) the global next/previous effect pickers, you
can split the screen into a grid and assign a **different effect to each
zone**.

- **Grid enabled** — turns the per-zone grid on/off. When off, the plugin
  just uses the global Next/Previous effect pickers above for every tap,
  same as if there were no grid at all.
- **Grid size** — set the number of columns and rows.
- **Edit grid** — opens the visual editor:
  - **Tap** a cell to cycle through: global effect (uses whichever of
    Next/Previous applies) → Horizontal → Vertical → the 4 corners →
    Diagonal from right (auto) → Diagonal from left (auto) → back to
    global.
  - **Long-press (hold)** a cell currently set to one of the 4 fixed
    corners to give **that cell its own diagonal angle**, instead of the
    global "Diagonal angle" setting — handy for a shallow wipe in one
    zone and a steep one in another. A cell with its own angle shows it
    next to its icon (e.g. "↖ 30°"). Long-pressing any other kind of
    cell (global, horizontal, vertical, or one of the two auto-side
    effects) shows a reminder that only the 4 fixed corners can have
    their own angle.
- **Show grid** — displays an overlay of the current grid and each
  zone's assigned effect, without opening the editor.

---

## ⏱️ Speed

- **Speed** — four ready-made presets (step count + delay bundled
  together):

  | Preset | Steps | Delay |
  |---|---|---|
  | Slow | 16 | 40 ms |
  | Medium | 8 | 20 ms |
  | Fast | 4 | 10 ms |
  | Instant | 2 | 5 ms |

- **Steps** — number of intermediate frames per page turn (2–24). More
  steps = smoother but slower.
- **Delay** — pause between steps, in milliseconds (5–100 ms).

Picking a preset just sets Steps and Delay to matching values — you can
still fine-tune either one afterwards; they're independent settings, not
locked to the preset.

---

## 🌙 Dark mode (night mode tuning)

Configures how the animation behaves specifically while KOReader's night
mode is on. **Light mode is never affected by any of this.**

- **Refresh mode**:
  - **Automatic** (default) — intermediate steps use the fast `ui`
    refresh, same as light mode (fluid); only the last step of each turn
    is upgraded to `partial`, to clean up any leftover ghosting.
  - **Quality on every step** — every step uses `partial`, paced with a
    real e-ink vsync wait instead of a fixed delay, so it doesn't look
    choppy. Pair this with a lower "Steps in quality mode" below, since
    each step is heavier than in light mode.
  - **Same as light mode** — disables all of this, restoring the
    original unconditional `ui` behavior (may show ghosting at night).
- **Steps in quality mode** — step count used only in "Quality" mode,
  independent from the normal step count above.
- **Quality refresh frequency** — only 1 out of every N steps pays the
  full `partial` + vsync-wait cost; the rest use the fast `ui` refresh.
  Defaults to 1 (every step is `partial`), since the fast refresh doesn't
  invert blacks cleanly on many panels (Kindles included) — raising this
  only helps if your panel handles it well; otherwise expect flicker
  instead of fluidity.
- **Extra pause between steps** — optional extra delay (ms), on top of
  the vsync wait, for a slower feel in Quality mode.
- **Full refresh at the end** — upgrades the last step to a full
  flashing refresh instead of `partial`, for the rare case where
  `partial` alone still leaves something behind.

### Why this exists

The fast `ui` refresh doesn't reliably commit solid blacks, which showed
up as leftover gray ("ghosting") on inverted/dark backgrounds — most
noticeable on devices without hardware inversion (e.g. Kindles), where
night mode is emulated by inverting pixels in software. `partial` (the
same mode normal page turns already use) fixes that but settles slower on
the panel, so pacing it with a real vsync wait — instead of the same
short fixed delay used for `ui` — is what keeps "Quality on every step"
smooth instead of stuttering.
