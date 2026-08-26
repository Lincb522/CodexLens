---
name: Token Pulse
description: A reference-led real-time Codex context console in the macOS menu bar.
palette: "Desaturated blue context field with quiet adaptive glass below"
background: "AppKit-owned native NSMenu glass"
typography:
  ui: "SF Pro, system default"
  data: "SF Mono, system monospaced"
  minimum: "12pt"
layout:
  fixedWidth: "340pt"
  overview: "Context hero plus one switchable updates surface"
motion:
  feedback: "100-150ms ease-out"
  state: "320-380ms damped spring"
  progress: "460ms damped spring"
---

# Design System: Token Pulse 2.1

## Direction

**Context Daily** translates the supplied mobile health reference into a macOS
menu-bar utility without copying its phone chrome. The information hierarchy is
the reference:

1. a calm identity header;
2. a compact multi-task selector;
3. one edge-to-edge atmospheric field with a single oversized live value;
4. three equal supporting metrics;
5. one lower “Updates” area with a three-way segmented switch;
6. an independent Tibo cycle row and detail destination;
7. a compact icon navigation bar.

The interface no longer presents every metric at the same visual weight. Context
input is the hero. Task, quota and account details share one switchable lower
surface, so data remains available without becoming a wall of text.

## Overview hierarchy

### Identity header

The header contains only product identity, monitored account and refresh. Account
plan and login-mode badges were removed from the header to preserve the supplied
reference's simple top rhythm; they remain available in the account menu and
control center.

### Multi-task selector

When multiple tasks are active, the top ribbon exposes up to four real tasks at
once, with an explicit Task number and each task's live context input. Overflow
tasks remain reachable from a named menu without adding a scrolling list.

### Context hero

The blue-to-cyan field spans the entire upper overview rather than appearing as
a card. Its blurred vertical gradient continues behind the beginning of the
Updates region and gradually reaches zero opacity, so there is no rounded edge,
circle-shaped glow or horizontal seam against the lower light/dark material. It
contains:

- the real task title with a pause-aware marquee;
- a live/stale state and details disclosure;
- a Context / Task Total segmented switch;
- one 52pt numeric hero value;
- published context capacity and used percentage;
- input, cached input and output tiles;
- published capacity and real request composition.

Expanded evidence stays inside the same hero and separates conversation context,
current turn and task cumulative usage. Each exact counter occupies its own
label/value row, followed by accounting evidence and the applicable pricing tier.

### Updates

The lower surface exposes Task, Quota and Account as a segmented switch instead
of stacking three permanent sections.

- Task: current turn, task total, API estimate, project and model.
- Quota: primary remaining percentage, reset evidence, forecast, and up to two
  additional real quota windows.
- Account: official daily/lifetime Token and real credits.

Tibo remains a separate public reset-cycle row below Updates and also stays
available in More. It never changes or masquerades as an account quota reset.

### Bottom navigation

Overview, local ledger and control center are persistent raster-icon
destinations with full hover and accessibility labels. More contains Tibo,
developer information, exports and quit. No unexplained one-letter controls are
used.

## Surface rules

- AppKit owns the real menu glass through
  `NSStatusItem -> NSMenu -> NSMenuItem.view -> NSHostingView`.
- The SwiftUI root remains clear, non-opaque and vibrancy-enabled.
- Only the upper overview carries a large colour field. It fades continuously
  into the adaptive translucent lower material; lower cards remain neutral and
  readable in light and dark appearances.
- Blue is the navigation/selection accent and also anchors the atmospheric
  context field. Green is reserved for verified healthy/remaining states;
  amber and coral remain semantic warning and failure colours.
- Product and internal icons remain raster Image Assets. No SVG or SF Symbols are
  used as product icons.
- Corner radii follow one scale: 12pt tiles and 16-18pt secondary surfaces. The
  gradient itself has no card outline or bottom radius.
- Every visible explicit font is at least 12pt.

## Motion

- Live Token values use numeric content transitions.
- Context/Task and Updates switches use interruptible damped springs.
- The current progress width retargets with a damped spring.
- Buttons respond immediately with a small press compression.
- Long titles and times use a pause-aware reversible marquee instead of ellipsis,
  wrapping or scale-to-fit.
- Page transitions preserve direction.
- Reduce Motion disables repeated motion and substitutes immediate/opacity state
  changes.

## Constraints

- Fixed popover width: **340pt**.
- No `ScrollView`, scroll indicator or hidden scroll gesture.
- Text never uses `minimumScaleFactor` and visible labels never wrap.
- Task history uses pagination.
- Missing data stays unavailable; the redesign introduces no demo or inferred
  values.
- Structured Tibo predictions and confirmed resets retain their existing
  evidence-backed state machine.
- Light and dark mode use the same hierarchy and interaction model.
