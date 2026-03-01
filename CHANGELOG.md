# PatchWerk Changelog

| Version | Highlights |
|---------|-----------|
| [v1.5.6](#v156--the-one-where-the-plugins-actually-stayed) | ElvUI plugin registration crash finally squashed for real this time |
| [v1.5.5](#v155--the-one-where-elvui-remembered-its-plugins) | ElvUI plugins and profiles work again — missing compatibility function restored |
| [v1.5.4](#v154--the-one-where-the-host-stopped-calling-back) | AutoLayer stops re-invites for good, popup resets after hop, Bagnon crash fix |
| [v1.5.3](#v153--the-one-where-autolayer-learned-to-listen) | AutoLayer whisper-aware hops, cross-continent raid detection, popup fix + Pawn tooltip fix |
| [v1.5.2](#v152--the-one-where-the-bags-opened-again) | ElvUI bags fixed (B key works again) + AutoLayer declines known-bad hosts at the door |
| [v1.5.1](#v151--the-one-where-the-bouncer-remembered-faces) | AutoLayer no longer falls for the same host re-inviting after a successful hop |
| [v1.5.0](#v150--the-one-where-elvui-walked-in-and-the-spellbook-chilled-out) | ElvUI support (24 patches) + spellbook security warning finally fixed for good |
| [v1.4.2](#v142--the-one-where-the-spellbook-fought-back) | Fixed spellbook Blizzard security warning blocking spell casting |
| [v1.4.1](#v141--the-one-where-layers-learned-geography) | AutoLayer cross-continent hop detection, auto-retry, and cancel button |
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
- **Shivaz** — reported the AutoLayer dungeon invite bug ([v1.3.0](#v130--the-one-where-gudachat-joined-the-party)), suggested the Bagnon crash fix ([v1.5.4](#v154--the-one-where-the-host-stopped-calling-back))
- **Don_Perry** — reported the spellbook security warning ([v1.4.2](#v142--the-one-where-the-spellbook-fought-back), [v1.5.0](#v150--the-one-where-elvui-walked-in-and-the-spellbook-chilled-out))
- **Yitra_Beloff** — reported the ElvUI bag keybinding bug ([v1.5.2](#v152--the-one-where-the-bags-opened-again))
- **TarybleTexan** — reported the Pawn tooltip disappearing bug ([v1.5.3](#v153--the-one-where-autolayer-learned-to-listen))
- **Der2werg** — reported ElvUI plugins and profiles being broken ([v1.5.5](#v155--the-one-where-elvui-remembered-its-plugins), [v1.5.6](#v156--the-one-where-the-plugins-actually-stayed))
- **geggiot94470** — confirmed the ElvUI plugin registration crash ([v1.5.6](#v156--the-one-where-the-plugins-actually-stayed))

---

## v1.5.6 — "The One Where the Plugins Actually Stayed"

Consider this the Emergency Maintenance your AddOns folder never got.

**Squashed like Razorgore's eggs:**
- ElvUI: Plugin registration (ToxiUI and others) was still crashing on startup because the options panel wasn't fully built yet when plugins tried to register. The previous fix caught the crash but didn't prevent it — this one builds the missing structure ahead of time so the registration goes through cleanly
- ElvUI: Verified patches against ElvUI v15.07 (up from v15.05)

---

## v1.5.5 — "The One Where ElvUI Remembered Its Plugins"

Hotfix incoming. No arena season reset required.

**Bugs that got /kicked:**
- ElvUI: All plugins (including ToxiUI) were invisible in ElvUI's options panel because a missing compatibility function prevented them from registering during startup. Restored the missing piece so plugins show up and work correctly again
- ElvUI: Profile selection was broken for the same reason — ElvUI's startup sequence would hit a wall before it finished setting up the options panel. Profiles, imports, and copying all work again
- ElvUI: In ElvUI v15.07+, plugin registration could crash if the options panel loaded in an unexpected order. PatchWerk now catches this and ensures plugins still finish setting up correctly
- ElvUI: Added a safety net for the addon manager panel in case the enable-state check was missing from the game's built-in functions

---

## v1.5.4 — "The One Where the Host Stopped Calling Back"

No realm restart required. We fixed it while you were farming Primal Mana.

**Squashed like Razorgore's eggs:**
- AutoLayer: After a successful hop, the host would immediately re-invite you — turns out PatchWerk's thank-you whisper contained the word "layer", which the host's addon read as a brand new hop request. The whisper has been reworded so hosts stop calling back
- AutoLayer: The status popup would stay stuck on "Hopped!" for 8 seconds after a successful hop, forcing you to manually cancel it. Now shows the success message for 3 seconds then quietly returns to your current layer display
- AutoLayer: After confirming a hop, the addon could get permanently stuck in the group — the background checker stopped running after confirmation, so it never retried leaving. Now keeps checking until you're actually out
- AutoLayer: Re-invites from the same host were sometimes accepted then immediately left, instead of being silently declined at the door. Name matching now works correctly regardless of realm suffixes
- AutoLayer: The On/Off indicator in the status frame always showed "On" after a hop, even when AutoLayer was disabled
- Bagnon/BagBrother: Fixed a crash on login caused by BagBrother trying to modify a bag function that doesn't exist in TBC Classic (Thanks Shivaz!)

---

## v1.5.3 — "The One Where AutoLayer Learned to Listen"

Consider this the Emergency Maintenance your AddOns folder never got.

**What got buffed:**
- AutoLayer now reads the host's whisper to know exactly which layer you're heading to — the status frame shows "Hopping to Layer 3..." instead of a vague "Hopping..." so you always know what's happening
- If you get invited to a layer you're already on, AutoLayer instantly leaves and retries instead of sitting in the group for 10+ seconds figuring it out
- Countdown timers in the status frame show how long you've been waiting — no more guessing whether things are still working
- Layer confirmation is clearer: you'll see "Layer 2 -> 3" with exact numbers, or "Hopped to Layer 3!" when the target is known
- PatchWerk now scans nearby enemies to help detect your new layer faster — stand near any creatures and detection kicks in without needing to manually target or mouseover
- After 5 seconds, the status frame reminds you to stay near NPCs for faster detection — helpful if you're hopping in an empty field
- Cross-continent hosts now get a whisper explaining why you declined: "I'm in Outland — layers don't cross the Dark Portal!" — so they know it's not personal
- Updated the hop thank-you whisper to "Fresh layer, fresh mobs. Thanks for the lift!" — less cringe, more gratitude

**Squashed like Razorgore's eggs:**
- Pawn: Upgrade arrows and stat values on item tooltips no longer vanish after 15-30 minutes. The "Duplicate Tooltip Guard" patch was too aggressive — once it saw an item, it blocked Pawn from re-adding its text even when the tooltip was rebuilt by the game. Now it only skips genuine duplicates within the same instant. (Thanks **TarybleTexan** for the report!)
- Pawn: Changing your stat scales or weights now immediately updates upgrade results on tooltips. Previously, the "Upgrade Result Cache" would keep showing old values until you reloaded your UI.
- AutoLayer: Hops that actually succeeded could be reported as failed — or hang forever in "Hopping..." — because the layer detection was still reading stale data from before the hop. Now the old layer info is cleared the moment you join the hop group, so targeting or walking near any NPC immediately detects your new layer
- AutoLayer: Cross-continent detection now works when the host converts the group to a raid (common with AutoLayer hosts in cities). Previously, hosts in Orgrimmar's Hall of Legends or similar indoor locations weren't detected because raid members use "raid1" instead of "party1"
- AutoLayer: Cross-continent hosts that keep re-inviting no longer leave a stuck popup with broken buttons. The decline now goes through the popup's own button handler instead of calling DeclineGroup() from addon code, which was tainting the popup system
- AutoLayer: After confirming a hop, re-invites from the same or different hosts during the confirmation window are now silently declined — no more brief join/leave cycles or the status frame getting "stuck"
- Cross-continent detection is more reliable — the old two-step check sometimes raced with group data and falsely flagged hops as cross-continent. Now it waits for complete data before deciding
- AutoLayer can now leave groups that were converted to raids in the open world — previously IsInRaid() blocked LeaveParty() even though the raid was just AutoLayer's way of handling multiple hoppers
- Removed the old "Verifying..." intermediate state that could leave you in limbo after the host left the group — hops now either confirm or fail cleanly
- Status frame no longer shows cryptic "L3" — it spells out "Layer 3" like a normal person

---
*100+ patches. 35 addons. Zero enrage timers.*

---

## v1.5.2 — "The One Where the Bags Opened Again"

No realm restart required. We fixed it while you were farming Primal Mana.

**Squashed like Razorgore's eggs:**
- ElvUI: Pressing B to open your bags stopped working when the "Bag Slot Info Speedup" patch was enabled. The speedup was broken from the start — it looked up item details but never actually used them, and could crash the bag frame on first open. Replaced with crash protection so one bad slot can never block your bags from opening. (Thanks **Yitra_Beloff** for the report!)
- AutoLayer: Cross-continent and recently-hopped hosts are now declined at the door instead of accepted and then immediately kicked. No more "Dungeon Difficulty set to Normal" spam from stale re-invites.

---
*100+ patches. 35 addons. Zero enrage timers.*

---

## v1.5.1 — "The One Where the Bouncer Remembered Faces"

Hotfix incoming. No arena season reset required.

**Bugs that got /kicked:**
- AutoLayer: Fixed false "hop confirmed" when the layer never actually changed. If you were on layer 9 and a host on layer 2 invited you, it would say "thanks for the hop!" and pat itself on the back — while you were still standing on layer 9. The verification now checks the actual layer number before celebrating.
- AutoLayer: After a real successful hop, the same host could re-invite you through their stale LFG queue and trigger a whole new hop cycle. Now it remembers who just hosted you for 60 seconds and instantly leaves if they try again. One hop per host, no encore performances.

---
*100+ patches. 35 addons. Still zero enrage timers.*

---

## v1.5.0 — "The One Where ElvUI Walked In and the Spellbook Chilled Out"

Two big things in one release: ElvUI support with 24 targeted patches — the biggest single-addon integration yet — and the complete fix for the spellbook security warning that's been haunting us since v1.4.2.

**ElvUI — TBC Classic compatibility fixes:**
- ElvUI's addon manager skin no longer errors out when it tries to use Retail-only game functions — the skin is now wrapped in crash protection so your addon list always works
- ElvUI's bag skin can now find the container functions it needs on TBC Classic — missing game functions are bridged to their classic equivalents
- Loot history window no longer throws errors — TBC Classic doesn't have a loot history system, so ElvUI now gets safe empty results instead of a crash
- Gem socket window skin no longer errors when opening the socketing UI — the missing socket type lookup is handled gracefully
- Communities and Guild Finder skin no longer fires into the void — these windows don't exist in TBC Classic, so the skin checks first and skips quietly

**ElvUI — Nameplate performance — your dungeon pulls just got smoother:**
- Health updates are now batched instead of processing every single damage tick individually — in a big pull with 10+ enemies, this cuts nameplate update work dramatically
- Mouse highlight checking replaced with a smarter approach that only runs when your mouse target actually changes, instead of constantly polling every visible nameplate
- Quest objective icons now remember which enemies are quest targets instead of rescanning tooltip text every time a nameplate appears
- Target indicator now tracks your target once when it changes, instead of re-checking every nameplate on every health update

**ElvUI — Unit frame performance — your raid frames thank you:**
- Idle unit frames now skip expensive processing when the player shown hasn't changed — in a 40-player raid, this eliminates thousands of redundant checks per second
- Mouseover, target, and focus glow effects consolidated from 120 separate watchers into a single combined pass
- Text on raid frame tags (name, health, power) is no longer rewritten when the displayed value hasn't actually changed — skips unnecessary layout recalculations
- Health bar color settings are now read once per update instead of being looked up 5+ times through nested tables

**ElvUI — Action bars and bags:**
- Bar visibility during casting is now recalculated 10 times per second instead of 20+ — still feels instant, cuts the work in half
- Keybind text formatting skips buttons that have no keybind assigned, avoiding thousands of pointless text operations during bar reloads
- Button greying (desaturation) only recalculates when a cooldown actually starts or finishes, not on every update tick
- Data bar visual rebuilds are skipped entirely when your settings haven't changed — only the actual XP/rep values update
- Bag sorting pre-reads all item details once before sorting begins, instead of re-reading them on every single comparison — up to 70% faster sorting
- Rapid-fire bag events (from vendoring, sorting, moving items) are combined into a single refresh instead of processing each one individually
- Bag slot item details are remembered between refreshes — opening your bags no longer queries the game for every single slot from scratch
- Chat URL detection does a quick check first — messages that obviously don't contain links skip all 5 pattern scans entirely

**ElvUI — Quality of life:**
- Tooltip inspect data now expires after 30 seconds instead of 2 minutes — you'll see gear changes faster when mousing over players
- Heal prediction bars skip resizing when the health bar dimensions haven't actually changed — fewer wasted layout updates in raids
- Buff/debuff filter rebuilds are skipped when settings haven't changed — faster profile switching

**Spellbook security warning — finally fixed for good:**
- Fixed the "AddOn tried to call a protected function" error that popped up when clicking spells in the spellbook. v1.4.2 fixed one cause, but another was hiding in PatchWerk's main addon. The root cause: some performance patches were replacing built-in game functions with faster versions, which Blizzard's security system treats as suspicious — even though they were harmless. When the spellbook tried to use one of those replaced functions, Blizzard blocked the spell cast entirely. All affected patches have been rewritten to work *alongside* the game instead of replacing anything:
  - **OmniCC cooldown cache** (the culprit): Now speeds up cooldown checks inside OmniCC's own code instead of replacing a game function — same performance improvement, no security warning
  - **TipTac inspect cache**: Now reduces inspect spam through TipTac's own library instead of replacing a game function
  - **Bartender4 action bar fix**: Uses a targeted approach that doesn't touch game functions
  - **AutoLayer**: Cleaned up unnecessary work that ran for every user at login, even without AutoLayer installed
- Added `/pw taintcheck` diagnostic — if you ever see the security warning again, this shows exactly what's causing it

**Quality of life:**
- Login chat no longer gets flooded with "Total time played" messages — multiple addons all ask the server for your /played time at startup, each printing two lines. PatchWerk now quietly blocks those messages for 10 seconds after login. Typing /played yourself still works after the window
- AutoLayer hop confirmation no longer shows the same message twice — a timing issue caused the "Hop confirmed" notification to appear in duplicate. Now you get one clean gold toast

**Housekeeping:**
- Removed BigWigs Flash Recovery patch — the companion addon now handles what this patch was doing, so BigWigs flash alerts work on their own
- Removed NovaWorldBuffs Addon Check Fix — same reason, the companion addon already provides what NovaWorldBuffs needs
- Fixed BigWigs Proximity Text Throttle — turns out this patch was never actually doing anything due to how BigWigs loads its plugins. Rewritten so it actually works now
- Fixed Leatrix Maps and Leatrix Plus patches — both patches were silently never running due to a startup check that always failed. Now they actually apply their optimizations
- Updated version compatibility for Details, BigWigs, Leatrix Maps, and Leatrix Plus

---

## v1.4.2 — "The One Where the Spellbook Fought Back"

Hotfix incoming. No arena season reset required.

**Bugs that got /kicked:**
- Fixed a Blizzard security warning that blocked spell casting from the spellbook — clicking a spell in the spellbook would fail with "AddOn tried to call a protected function." The companion addon's compatibility layer was accidentally interfering with the spellbook's secure click path
- Hardened all compatibility layer entries against similar issues — the companion addon now writes all of its entries using a technique that avoids interfering with Blizzard's security checks entirely. This prevents the same class of error from appearing in any other protected action (not just spell casting)

---

## v1.4.1 — "The One Where Layers Learned Geography"

Another patch cycle. No realm restarts, no 6-hour downtime. You're welcome.

**What got buffed:**
- AutoLayer now detects when a hop host is on a different continent and leaves within seconds — no more sitting in a group for 2 minutes waiting for a hop that can never happen. Azeroth and Outland have completely separate layer pools, so a host in Orgrimmar can't change your layer in Nagrand
- When a cross-continent mismatch is detected, PatchWerk whispers the host why you left ("I'm in Outland — layers don't cross the Dark Portal!") and automatically retries up to 3 times to find someone on your continent
- Hosts that were already skipped are remembered for 5 minutes — if the same person keeps inviting, PatchWerk leaves instantly without re-checking or re-whispering
- Shift+Left-click the AutoLayer status frame to cancel an active hop at any time — leaves the group and resets everything
- Thank-you whisper after a successful hop got a personality upgrade: "Hopped! Smoother than a Paladin bubble-hearth. Cheers!"

**Bugs that got /kicked:**
- AutoLayer no longer gets permanently stuck in the group after a successful hop — a long-standing issue where the leave command silently crashed has been fixed. This was the root cause of "hop complete but still in party" reports
- Hop confirmation no longer falsely reports "failed" when layer data isn't available yet — if you're in an NPC-sparse area (open fields, far from towns), PatchWerk now waits longer before giving up instead of declaring failure
- Stale invites from other hosts no longer pull you into a new group right after a confirmed hop — PatchWerk now rejects group joins when you've already landed on your new layer
- Hop verification no longer times out on fresh login when layer data wasn't ready yet

---
*131 patches. 38 addons. Zero enrage timers.*

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
