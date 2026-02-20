# PatchWerk Changelog

## v1.2.0 — "The One Where Everything Got a Little Shinier"

Think of this as a world buff for your addon folder.

**Shiny new things:**
- In-game changelog popup — shows you what changed after each update so you're never out of the loop
- Baganator bag sorting and item lock fixes — keeps your bags tidy without needing an extra addon
- Setup wizard got a glow-up — "Skip setup" is actually readable now, and it tells you about `/pw` if things go sideways
- BigWigs Flash Alert Recovery — boss flash and screen-pulse alerts restored on TBC Classic, no more silent wipes because your DBM rival wasn't blinking

**Bugs that got /kicked:**
- ESC / Exit Game no longer triggers "blocked from an action" — our bad, we accidentally broke the Quit button. Fixed!
- EasyFrames patch removed — it was breaking the pet action bar and the Exit Game button, so we benched it like a Fury warrior in a healing comp
- AutoLayer actually leaves the group after hopping now — timing issues meant it sometimes just stood there like a confused warlock pet
- AutoLayer status frame can't teleport to 0,0 anymore — that trick only works for mages
- BugGrabber was hiding ALL your errors, not just the harmless ones — real bugs are back on the meter where they belong
- NovaWorldBuffs no longer crashes 34 times when layer info is missing — that's more wipes than C'Thun prog
- Details meter respects your speed setting now instead of going full Leeroy on updates
- Auctionator timeout no longer argues with itself about when to give up
- Settings summary counts patches for addons you actually have, not your entire wishlist
- Enable All / Disable All no longer toggles patches for addons you don't have installed

**Behind the curtain:**
- Settings panel is alphabetical now — find your addon without a Questie arrow
- Installed addon groups open by default — no more clicking to see your own stuff
- All On / All Off button tells you which way it's going before you press it
- `/pw toggle` now actually tells you how to use it instead of staring blankly
- Update notifications come with a summon portal (download link) now
- Tooltips got a haste buff across the board
- Patch failure messages now tell you to type `/pw` instead of leaving you guessing
- All patch descriptions rewritten in plain English — no more programmer-speak in your tooltips

**Thanks to:**
- **Jerrystclair** for reporting the ESC bug — even a mage couldn't portal out of that one

---
*102 patches. 34 addons. Zero enrage timers.*

## v1.1.0 — "The One Where PatchWerk Got a Makeover"

No realm restart required. We fixed it while you were farming Primal Mana.

**What got buffed:**
- AutoLayer: full hop tracking — detects layer changes, auto-leaves the group, and whispers a thank you to the host. No more awkward silences after a hop
- AutoLayer: customizable whisper message in the settings panel — toggle it off or write your own
- AutoLayer: layer status frame now shows live hop state with pulsing animation during active hops
- AutoLayer: enhanced minimap tooltip with layer info, session stats, and hop state
- Details: number formatting now remembers results — smoother performance during long fights
- Leatrix Maps: area labels update less frantically — smoother zone transitions
- Leatrix Plus: combat checks relaxed — it was working harder than a Prot Paladin in Shattrath
- NameplateSCT: animation frame rate capped so your GPU stops crying during AoE
- QuestXP: quest log no longer freaks out when you turn in quests quickly
- RatingBuster: stat comparisons no longer do unnecessary extra work in the background
- ClassTrainerPlus: trainer window calmed down — it was checking for Shift harder than you check the AH for Primal Fires
- Brand new settings panel — one clean scrollable page, addon-centric layout, no more sub-page maze
- Compact `/pw status` output — see what's patched at a glance, not a 97-line scroll
- Smart `/pw toggle` — toggle all patches for an addon at once (e.g., `/pw toggle details off`)
- Login message now names your patched addons instead of just counting them

**Bugs that got /kicked:**
- Fixed Details TinyThreat crash when formatting numbers
- Fixed RatingBuster crash on load — TBC Classic does things a little differently and RatingBuster wasn't ready
- Fixed harmless PatchWerk warnings cluttering BugSack — false alarms are now filtered out
- Fixed TipTac version mismatch warning after addon update (patches verified, version bumped)
- Fixed unknown `/pw` commands dumping full status instead of showing help

**Behind the curtain:**
- Update checks can now accept addon updates without needing a new PatchWerk release
- Setup wizard simplified to 2 pages — no more 97-checkbox wall
- Outdated patch warnings only shown in dev builds (normal users don't need the noise)

---
*97 patches. 34 addons. Zero enrage timers.*
