# Animated launch, icon, and interface

Status: PROPOSED. Design brief, nothing built.

## Why this is not cosmetic

There is a functional argument hiding inside the aesthetic one.

A menu-bar utility that gives no feedback while it works is indistinguishable
from one that has crashed. Drop five files on the icon, watch nothing happen
for four seconds while `xz -9` runs, and the honest user conclusion is "it
crashed" — not "it is working". A visible working state is the difference
between a tool that feels dead and a tool that feels alive, and it costs
nothing at runtime.

So: animation here is not decoration. It is the app telling the truth about
what it is doing.

## 1. Icon

Current state: an emoji (💥) as the status item title. That is a placeholder
and it shows — emoji do not respect menu-bar tinting, do not go monochrome in
the way the menu bar expects, and render inconsistently across macOS versions
and appearance modes.

Replace with a **template image** (`isTemplate = true`) so macOS handles
light/dark, tint, and the menu-bar-highlighted state for free.

Form: the mark should read at 16pt and 1pt stroke weight. Something that
survives being tiny — a compression gesture, two forms converging into one
dense form. Resist literal illustration; resist a cartoon. At menu-bar size
the only things that survive are silhouette and negative space.

States, all as variations of one mark so it never reads as a different app:

| State | Treatment |
|---|---|
| Idle | Template mark, static |
| Working | Mark animates: compression cycle, ~1.2s loop, subtle |
| Success | Brief settle to a denser form, ~600ms, then idle |
| Error | Mark holds a broken/offset variant until acknowledged |

The error state must **persist**, not flash. A failure that disappears before
you look up is a failure you will never diagnose.

App icon (for `~/Applications/Smash.app`, Finder, Dock during share sheet):
full-colour, follows the macOS rounded-rect convention. `logo.svg` exists in
the repo and is the natural starting point.

## 2. Launch animation

Restraint is the whole design here. A menu-bar app launches at login and lives
for weeks. Anything theatrical on every launch becomes an irritant by day two.

- **First run ever**: a real moment. The popover opens by itself, the drop
  zone draws in, one line of text explains the deal. This is the only time the
  app should ask for attention.
- **Every subsequent launch**: the icon fades in over ~200ms. Nothing else.
  No bounce, no sound, no popover.
- **Never**: a splash screen. Menu-bar utilities do not get splash screens.

## 3. Interface

The popover is currently a drop zone plus a menu. It can carry more without
becoming an application.

```
┌──────────────────────────────────┐
│  ⊹ Smash                    ⚙︎    │   title + settings
├──────────────────────────────────┤
│                                  │
│      ┌────────────────────┐      │
│      │   drop files here  │      │   drop zone; grows on
│      │   or click         │      │   drag-enter, does not
│      └────────────────────┘      │   jump the layout
│                                  │
├──────────────────────────────────┤
│  claude-md-omnibus.txt           │   recent artifacts,
│  495KB → 97KB · 19.6% · ✓        │   newest first, 5 max
│  ⧉ copy path   ⤴ reveal          │
├──────────────────────────────────┤
│  sample.txt                      │
│  2.1KB → 1.4KB · 66% · ✓         │
└──────────────────────────────────┘
```

Principles:

- **The ratio is the reward.** `495KB → 97KB · 19.6%` is the single most
  satisfying fact the app produces. Show it prominently and animate the count
  up as it resolves.
- **Progress must be real.** Bytes processed, not a fake indeterminate spinner
  that runs at constant speed regardless of what is happening. If the app
  cannot know the progress, it shows elapsed time — which is at least true.
  Fake progress is the same lie as fake latency.
- **The drop zone must not move under the cursor.** Grow it in place on
  drag-enter; never reflow the panel while a drag is in flight.
- **Every result is actionable in one click**: copy path, reveal in Finder.
  A result you have to go hunting for is half a result.
- **Errors stay in the panel** with the actual message, not a modal that
  steals focus and is dismissed before it is read.

## 4. Non-negotiable constraints

- **Reduced motion**: honour
  `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`. Every animation
  above degrades to an instant state change. No exceptions, and it must be
  tested with the setting on, not assumed.
- **No third-party dependencies.** AppKit and Core Animation only. The project
  ships a single bash script and a signed Swift binary; that is a feature.
- **Nothing on the main thread that can block.** The compression already must
  not; the animation absolutely must not.
- **Accessibility labels on every control**, including the drop zone, which
  already has one — keep it accurate as the UI grows.
- **Animation must never gate the work.** If a 600ms success animation delays
  the artifact being usable by 600ms, the animation is wrong. Visual feedback
  trails the work; it never leads it.

## 5. Suggested order

1. Template-image icon with idle + working states. Highest value: it fixes the
   "did it crash?" ambiguity, which is a live complaint, not a hypothetical.
2. Real progress and the ratio readout in the popover.
3. Recent-artifacts list with copy/reveal.
4. First-run moment.
5. Success/error icon states and the launch fade.

Ship 1 alone and the app is meaningfully better.
