# PatchWerk Changelog

| Version | Highlights |
|---------|-----------|
| [v1.5.0-beta1](#v150-beta1--the-one-where-elvui-walked-into-the-repair-bot) | ElvUI support — 24 patches across nameplates, unit frames, action bars, bags, and TBC compatibility |
| [v1.4.0](#v140--3-addons-patched-0-loot-frames-seen) | HazeLoot fast auto-loot, HazeCooldowns GCD fix, Plumber TBC compatibility |
| [v1.3.3](#v133--the-one-where-we-stopped-guessing) | Passive hop detection, configurable toasts, status frame polish |
| [v1.3.2](#v132--the-one-where-we-actually-checked) | GUID-based hop verification, no more false confirmations |
| [v1.3.1](#v131--the-one-where-we-stopped-believing-the-host) | Hop detection hotfix |
| [v1.3.0](#v130--the-one-where-gudachat-joined-the-party) | GudaChat support, instance guard, keyword cache |
| [v1.2.1](#v121--the-one-where-questie-learned-to-count) | Questie tracking fix, AutoLayer hop reliability |
| [v1.2.0](#v120--the-one-where-everything-got-a-little-shinier) | In-game changelog, settings overhaul, BigWigs flash recovery |
| [v1.1.0](#v110--the-one-where-patchwerk-got-a-makeover) | Settings panel, hop tracking, enhanced tooltips |

### Special Thanks

Bug reports, testing, and feedback from these legends made PatchWerk better for everyone:

- **[Finn](https://www.twitch.tv/finnwow31)** — live stream testing and bug reports ([v1.2.1](#v121--the-one-where-questie-learned-to-count))
- **Jerrystclair** — reported the ESC/Exit Game bug ([v1.2.0](#v120--the-one-where-everything-got-a-little-shinier))
- **Shivaz** — reported the AutoLayer dungeon invite bug ([v1.3.0](#v130--the-one-where-gudachat-joined-the-party))

---

## v1.5.0-beta1 — "The One Where ElvUI Walked Into the Repair Bot"

Consider this the Emergency Maintenance your ElvUI never got. PatchWerk now supports ElvUI with 24 targeted patches — the biggest single-addon integration yet. This is a **beta release** so we can collect feedback before going stable. If something feels off, please report it!

> **This is a beta.** All 24 patches are enabled by default. If any patch causes issues, you can toggle it off individually with `/pw` and let us know which one. Bug reports, feedback, and "it's smoother now" messages are all welcome — leave a comment on CurseForge, Wago, or open a GitHub issue.

**TBC Classic compatibility fixes:**
- ElvUI's addon manager skin no longer errors out when it tries to use Retail-only game functions — the skin is now wrapped in crash protection so your addon list always works
- ElvUI's bag skin can now find the container functions it needs on TBC Classic — missing game functions are bridged to their classic equivalents
- Loot history window no longer throws errors — TBC Classic doesn't have a loot history system, so ElvUI now gets safe empty results instead of a crash
- Gem socket window skin no longer errors when opening the socketing UI — the missing socket type lookup is handled gracefully
- Communities and Guild Finder skin no longer fires into the void — these windows don't exist in TBC Classic, so the skin checks first and skips quietly

**Nameplate performance — your dungeon pulls just got smoother:**
- Health updates are now batched instead of processing every single damage tick individually — in a big pull with 10+ enemies, this cuts nameplate update work dramatically
- Mouse highlight checking replaced with a smarter approach that only runs when your mouse target actually changes, instead of constantly polling every visible nameplate
- Quest objective icons now remember which enemies are quest targets instead of rescanning tooltip text every time a nameplate appears
- Target indicator now tracks your target once when it changes, instead of re-checking every nameplate on every health update

**Unit frame performance — your raid frames thank you:**
- Idle unit frames now skip expensive processing when the player shown hasn't changed — in a 40-player raid, this eliminates thousands of redundant checks per second
- Mouseover, target, and focus glow effects consolidated from 120 separate watchers into a single combined pass
- Text on raid frame tags (name, health, power) is no longer rewritten when the displayed value hasn't actually changed — skips unnecessary layout recalculations
- Health bar color settings are now read once per update instead of being looked up 5+ times through nested tables

**Action bar performance:**
- Bar visibility during casting is now recalculated 10 times per second instead of 20+ — still feels instant, cuts the work in half
- Keybind text formatting skips buttons that have no keybind assigned, avoiding thousands of pointless text operations during bar reloads
- Button greying (desaturation) only recalculates when a cooldown actually starts or finishes, not on every update tick
- Data bar visual rebuilds are skipped entirely when your settings haven't changed — only the actual XP/rep values update

**Bag and chat improvements:**
- Bag sorting pre-reads all item details once before sorting begins, instead of re-reading them on every single comparison — up to 70% faster sorting
- Rapid-fire bag events (from vendoring, sorting, moving items) are combined into a single refresh instead of processing each one individually
- Bag slot item details are remembered between refreshes — opening your bags no longer queries the game for every single slot from scratch
- Chat URL detection does a quick check first — messages that obviously don't contain links skip all 5 pattern scans entirely

**Quality of life:**
- Tooltip inspect data now expires after 30 seconds instead of 2 minutes — you'll see gear changes faster when mousing over players
- Heal prediction bars skip resizing when the health bar dimensions haven't actually changed — fewer wasted layout updates in raids
- Buff/debuff filter rebuilds are skipped when settings haven't changed — faster profile switching

---
*131 patches. 38 addons. Zero enrage timers. This is a beta — [report issues here](https://github.com/Eventyret/PatchWerk/issues).*

## v1.4.0 — "3 Addons Patched, 0 Loot Frames Seen"

No realm restart required. We fixed it while you were farming Primal Mana.

**Newly attuned:**
- HazeLoot: fast auto-loot — when auto-loot is on, items are grabbed instantly without the loot frame flashing on screen. Shift-click still shows the full interactive frame. Master loot always shows the frame so you can distribute properly
- HazeCooldowns: cooldown text no longer shows countdown timers on the global cooldown. The GCD detection was completely broken on TBC Classic — every ability briefly flashed "1.5" after you pressed it. Now only real cooldowns get timers
- Plumber: loot window, spell flyouts, and settings panel no longer crash on TBC Classic. The companion addon now fills in the missing game functions Plumber expects (toy collection, mount journal, spell readiness checks)

**Behind the curtain:**
- Companion addon learned four new tricks: toy collection lookups, mount journal queries, spell data readiness, and item data readiness — all returning safe defaults since those systems don't exist in TBC

---
*107 patches. 37 addons. Zero enrage timers.*

## v1.3.3 — "The One Where We Stopped Guessing"

v1.3.2 rebuilt hop detection from scratch — and accidentally broke a few things along the way. This patch fixes those regressions and makes the whole experience smoother.

**Bugs that got /kicked:**
- AutoLayer now actually leaves the group after confirming a hop — v1.3.2 introduced a bug where PatchWerk whispered "thanks for the hop!" and then just... stood there in the group forever
- Hop detection no longer breaks after a `/reload` — another v1.3.2 regression where PatchWerk lost track of your layer and couldn't confirm anything until you restarted the game
- Layer info from before a hop no longer lingers and confuses the next detection — v1.3.2 wasn't clearing old data properly
- Clicking quests in the quest log no longer flickers — both the Questie and QuestXP performance patches were delaying updates even while you were browsing the log. Now updates fire instantly when the quest log is open, and only batch in the background during combat

**Quality of life:**
- You no longer need to manually target an NPC to confirm hops — just stand near any creatures in a city and PatchWerk picks up the layer automatically from nearby nameplates and mouseover
- Toast messages stay on screen longer (8 seconds, up from 5) so you can actually read "Layer 5 -> 8" before it vanishes
- Toast duration is now configurable (3–15 seconds) via a slider in AutoLayer settings
- Status frame default position moved up to avoid overlapping debuffs
- Hover the status frame for a clear explanation of what On/Off means
- Hint text during hops updated: "Stay near NPCs to confirm layer" and "Hover over any NPC to confirm"

---
*105 patches. 35 addons. Zero enrage timers.*

## v1.3.2 — "The One Where We Actually Checked"

PatchWerk was trusting UNIT_PHASE to prove your layer changed. Turns out UNIT_PHASE fires for *everyone else* in the group — other hoppers joining and leaving were constantly triggering it, so PatchWerk said "thanks for the hop!" while you sat on the same layer the whole time. Six hops. Same layer. Awkward whispers. Never again.

**Bugs that got /kicked:**
- AutoLayer hop detection completely rebuilt — PatchWerk now reads the zoneID from creature GUIDs before and after a hop to verify you actually changed layers, instead of trusting UNIT_PHASE events that fire for other group members
- PatchWerk stays in the hop group until it has proof your layer changed (GUID zoneID differs or NWB reports a new layer number). No more leaving after 5 seconds on blind faith
- If the host leaves before PatchWerk can confirm, it enters a "Verifying" state and keeps checking — mouseover or walk near any NPC to let it know where you ended up
- "Thanks for the hop!" whispers only go out when the hop actually worked. No more thanking someone for a layer change that didn't happen
- False-positive hop confirmations from other players cycling through the group no longer trigger early group-leave

**Quality of life:**
- Hop timeout extended from 90s to 120s — some layers take a minute to settle
- New "Verifying..." state with pulsing animation when the group disbands before confirmation
- Failed hops show an orange warning ("Layer unchanged" or "Hop timed out") instead of silently resetting

---
*105 patches. 35 addons. Zero enrage timers.*

## v1.3.1 — "The One Where We Stopped Believing the Host"

Hotfix incoming. No arena season reset required.

**Bugs that got /kicked:**
- AutoLayer no longer falsely confirms a layer hop just because the host targeted an NPC — your client must actually change layers before PatchWerk believes it worked. Previously, joining a hop group and seeing the host's layer number was enough to trigger "thanks for the hop!" while you were still sitting on your original layer
- Layer change toasts ("Layer 1 -> 4") no longer flash during a hop when the number can't be trusted — the toast now only appears once the hop is actually confirmed
- All hop-related messages (layer confirmed, layer changed, left group) now stay on screen for 5 seconds instead of vanishing instantly

---
*105 patches. 35 addons. Zero enrage timers.*

## v1.3.0 — "The One Where GudaChat Joined the Party"

Welcome to the raid, GudaChat. Your buffs are ready.

**Shiny new things:**
- GudaChat is now a supported addon with three QOL tweaks ported from Prat for lightweight chat users:
  - Arrow key message history — just hit Up/Down to cycle through sent messages, no Alt needed
  - /tt whisper target — type /tt to whisper whoever you're targeting
  - /clear and /clearall commands — wipe your chat windows without scrolling back to the Stone Age
- AutoLayer keyword cache now also covers the new prefix filter from v1.7.7 — fewer throwaway tables in busy channels
- Older addons that use classic API functions now find them even when only the modern versions exist — covers more edge cases

**Bugs that got /kicked:**
- AutoLayer no longer messes with your group inside dungeons or raids — if you're the party leader in a dungeon and someone asks for a layer in guild chat, AutoLayer now ignores it instead of inviting them into your run. Requesting a layer hop while inside an instance is also blocked
- Prat's "Player Info Throttle" patch has been removed — it was never actually doing anything, like a ret paladin casting Blessing of Kings on someone who already has it
- GudaChat arrow keys now survive opening and closing chat — Blizzard was resetting the mode every time you pressed Enter
- Settings panel says "enabled" instead of "active" for addons you don't have installed — because "2/2 active" when nothing is running was confusing everyone

**Behind the curtain:**
- Version compatibility verified for 8 addon updates (Details, BigWigs, BigDebuffs, NovaInstanceTracker, AutoLayer, LoonBestInSlot, Prat, RatingBuster)

**Thanks to:**
- **Shivaz** for reporting the AutoLayer dungeon bug — apparently asking for a layer in guild chat is faster than a mage portal for getting into dungeons you weren't invited to

---
*105 patches. 35 addons. Zero enrage timers.*

## v1.2.1 — "The One Where Questie Learned to Count"

Two bug reports walk into Shattrath. Both get fixed before the loading screen.

**Bugs that got /kicked:**
- Questie quest tracking no longer falls behind — looting 8 bones now shows 8/10, not 7/10. The quest log update was eating events instead of batching them
- AutoLayer right-clicking the status frame now always sends a hop request, even when your layer is unknown — no more surprise GUI popping up in Shattrath
- AutoLayer clicking to hop multiple times no longer queues up a conga line of requests — once you're mid-hop, extra clicks are ignored
- AutoLayer actually leaves the group when a hop times out after 90 seconds — no more standing in a party forever like a confused warlock pet (again)
- AutoLayer gives NovaWorldBuffs the full 5 seconds to confirm your new layer after hopping — it was starting the countdown too early and bailing before NWB could check
- AutoLayer "Searching..." only shows when a hop request actually goes out — no more phantom searches when you click too fast
- AutoLayer picks up hop invites even if your last attempt failed — no more getting stuck because someone invited you right after a timeout

**Thanks to:**
- **[Finn](https://www.twitch.tv/finnwow31)** for reporting both issues while testing live on stream — go check him out!

---
*102 patches. 35 addons. Zero enrage timers.*

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
