# Demo Plan

Decided 2026-10-28: there will be a free **demo** of Dungeon Strikers. It's
a cut-down build of the same game, and the full game is what you buy on Steam.
Nothing is built yet. This note records what was agreed and the planned
approach.

## What the demo has

- **Local / offline play only.** No hosting or joining online. Steam Remote
  Play Together still lets friends play a local-only game over the internet,
  so mention that on the store page.
- **Fewer characters.** At least one Human and one Skeleton, so both sides
  can be played.
- **Fewer perks.**
- **Maybe one mode.** Probably the Pitch with the bomb (the core mode), not
  the ball or skull.
- Everything else comes with the paid game.

Which characters, perks and modes go in is still open.

## Where it ships

- **Steam demo.** A Steam demo has its own app ID and its own page, which
  is attached to the main store page. You need a demo to take part in Steam
  Next Fest.
- **Possibly Poki** (poki.com, a browser games site), using the same
  cut-down build. Poki asks for web exclusivity: that covers the open web,
  Discord and YouTube Playables, but **not** Steam, consoles or app stores, so
  both can happen. Deals run about 5 years by default. A Poki build would also
  need:
  - The Compatibility renderer (the web can't run Forward+).
  - Touch controls.
  - A much smaller download (most of it is BGM).
  - The Poki SDK (ad breaks, `gameplayStart` / `gameplayStop`).
  - Online play over WebRTC instead of ENet, or local play only, which suits
    the demo anyway.

  Ask Poki early whether locked content marked "full game on Steam" and a
  wishlist link (through `PokiSDK.openExternalLink`) are allowed.

## Planned approach (code)

- **One codebase, two editions.** Add Demo export presets with a `demo`
  custom feature. The code checks for it with `OS.has_feature("demo")`, the
  same way `Net` checks `dedicated_server`.
- **One place decides what's in the demo.** A small edition helper (a static
  class, or part of `Global`) lists the allowed characters, perks, modes and
  ball picks. `Roster`, the `PerkCatalog` users, `MatchMap` and the main menu
  ask it what's available, rather than having `if demo` checks scattered
  around the code.
- **Show what's locked.** Grey out the classes, perks and modes that aren't
  in the demo and tag them "Full game", with a wishlist button. The Codex is
  a natural place for this too.
- **Leave out what's locked.** Use `exclude_filter` entries in the demo
  presets (like `Steam/*` today) so the cut content isn't in the `.pck` and
  can't be unlocked by digging through the files.
- **No online in the demo.** Hide the Online button, and have `Net` refuse
  to connect when the `demo` feature is set.
