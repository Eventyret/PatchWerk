# PatchWerk Changelog

## v1.2.0 — "The One Where Everything Got a Little Shinier"

Think of this as a world buff for your addon folder.

**Shiny new things:**
- In-game changelog popup — shows you what changed after each update so you're never out of the loop
- Baganator patches moved in-house — bag sorting and lock fixes no longer need a separate addon
- Addon registry centralized — one source of truth for all 35 addons instead of metadata scattered across every file
- Setup wizard got a glow-up — "Skip setup" is actually readable now, and it tells you about `/pw` if things go sideways

**Bugs that got /kicked:**
- BugGrabber was hiding ALL your errors, not just the taint ones — real bugs are back on the meter where they belong
- NovaWorldBuffs marker throttle no longer crashes 34 times when layer is nil — that's more wipes than C'Thun prog
- EasyFrames health text finally says "K" and "M" instead of "T" — your target does NOT have 30 trillion HP
- AutoLayer status frame can't teleport to 0,0 anymore — that trick only works for mages
- Details meter respects your speed setting now instead of going full Leeroy on refresh rates
- Auctionator timeout no longer argues with itself about when to give up
- Settings summary counts patches for addons you actually have, not your entire wishlist

**Behind the curtain:**
- Settings panel is alphabetical now — find your addon without a Questie arrow
- Installed addon groups open by default — no more clicking to see your own stuff
- All On / All Off button tells you which way it's going before you press it
- `/pw toggle` now actually tells you how to use it instead of staring blankly
- Update notifications come with a summon portal (download link) now
- Tooltips got a haste buff across the board

---
*97 patches. 35 addons. Zero enrage timers.*

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
