# PatchWerk Changelog

## v1.1.0 — "The One Where PatchWerk Got a Makeover"

No realm restart required. We fixed it while you were farming Primal Mana.

**What got buffed:**
- AutoLayer: full hop lifecycle tracker — detects layer changes via phase events, auto-leaves the group, and whispers a thank you to the host. No more awkward silences after a hop
- AutoLayer: customizable whisper message in the settings panel — toggle it off or write your own
- AutoLayer: layer status frame now shows live hop state with pulsing animation during active hops
- AutoLayer: enhanced minimap tooltip with layer info, session stats, and hop state
- Details: number formatting cache for `ToK2` — fewer garbage collections during long fights
- Leatrix Maps: area label redraw throttle — smoother zone transitions
- Leatrix Plus: combat polling dialed back from "panicking" to "chill"
- NameplateSCT: animation frame rate capped so your GPU stops crying during AoE
- QuestXP: quest log debounced — stops thrashing on rapid quest turn-ins
- RatingBuster: stat comparisons no longer capture the entire call stack
- ClassTrainerPlus: shift key polling throttled — your trainer window is now respectful
- Brand new settings panel — one clean scrollable page, addon-centric layout, no more sub-page maze
- Compact `/pw status` output — see what's patched at a glance, not a 97-line scroll
- Smart `/pw toggle` — toggle all patches for an addon at once (e.g., `/pw toggle details off`)
- Login message now names your patched addons instead of just counting them

**Bugs that got /kicked:**
- Fixed Details TinyThreat crash (`attempt to compare number with nil`) — the format cache was eating the `self` parameter
- Fixed RatingBuster crash on load — TBC Classic's `debug` is a boolean, not a table
- Fixed taint errors from `!PatchWerk` cluttering BugSack — known cosmetic taint is now silently scrubbed
- Fixed TipTac version mismatch warning after addon update (patches verified, version bumped)
- Fixed unknown `/pw` commands dumping full status instead of showing help

**Behind the curtain:**
- `!PatchWerk` companion addon provides API shims for TBC Classic missing APIs
- Version override system for safe version bumps without releasing new versions
- Setup wizard simplified to 2 pages — no more 97-checkbox wall
- Outdated patch warnings only shown in dev builds (normal users don't need the noise)

---
*97 patches. 34 addons. Zero enrage timers.*
