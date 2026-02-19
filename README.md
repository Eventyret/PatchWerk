# PatchWerk

<p align="center">
  <img src="Patchwerk.png" alt="PatchWerk" width="200">
</p>

<p align="center">
  <b>No enrage timer. No tank swap. Just pure, uninterrupted performance.</b>
</p>

Ever loaded into Shattrath and watched your FPS drop faster than a tank without a healer? Half the time its not the server. Its your addons doing 60 times more work than they actually need to.

PatchWerk makes them behave. Same addons, same features, no more lag. It stops the stuff you never see: addons refreshing every single frame, recalculating things that havent changed, and eating memory they never give back. Nothing on disk is changed, and every patch is safe to toggle on or off.

> **93 patches** across **28 addons** for WoW TBC Classic Anniversary. Install it, log in, and get back to parsing.

---

## Supported Addons

### Fixes

*These addons showed up to TBC Anniversary and forgot half their kit.*

| Addon | |
|---|---|
| [Bartender4](https://www.curseforge.com/wow/addons/bartender4) | Stops combat error spam |
| [BugSack](https://www.curseforge.com/wow/addons/bugsack) | Settings menu actually opens now |
| [LoonBestInSlot](https://www.curseforge.com/wow/addons/loon-best-in-slot) | Actually loads without crashing |
| [Nova Instance Tracker](https://www.curseforge.com/wow/addons/nova-instance-tracker) | No more login crash |
| [AutoLayer](https://www.curseforge.com/wow/addons/autolayer) | Stops duplicate invites |

### Performance

*Your addons were doing the same work 60 times a second. Somebody had to tell them to chill.*

| Addon | |
|---|---|
| [Details](https://www.curseforge.com/wow/addons/details) | Runs leaner and meaner |
| [Plater](https://www.curseforge.com/wow/addons/plater-nameplates) | Kills a 60/sec timer leak |
| [Pawn](https://www.curseforge.com/wow/addons/pawn) | Faster tooltip comparisons |
| [TipTac](https://www.curseforge.com/wow/addons/tiptac) | Less work per tooltip hover |
| [Questie](https://www.curseforge.com/wow/addons/questie) | Smoother map drawing |
| [LFG Bulletin Board](https://www.curseforge.com/wow/addons/lfg-group-finder-bulletin-board) | Stops needless list rebuilds |
| [Bartender4](https://www.curseforge.com/wow/addons/bartender4) | Fewer button refreshes per tick |
| [Titan Panel](https://www.curseforge.com/wow/addons/titan-panel-classic) | Calms down widget updates |
| [OmniCC](https://www.curseforge.com/wow/addons/omni-cc) | Stops recalculating every frame |
| [Prat-3.0](https://www.curseforge.com/wow/addons/prat-3-0) | Chat runs at 20fps, not 60 |
| [GatherMate2](https://www.curseforge.com/wow/addons/gathermate2) | Minimap pins chill out |
| [Quartz](https://www.curseforge.com/wow/addons/quartz) | Cast bars capped at 30fps |
| [Auctionator](https://www.curseforge.com/wow/addons/auctionator) | Fewer server queries |
| [VuhDo](https://www.curseforge.com/wow/addons/vuhdo) | Calmer during AoE |
| [Cell](https://www.curseforge.com/wow/addons/cell) | Remembers more, recalculates less |
| [BigDebuffs](https://www.curseforge.com/wow/addons/bigdebuffs) | Faster debuff tracking |
| [BugSack](https://www.curseforge.com/wow/addons/bugsack) | Smarter search filtering |
| [AtlasLoot Classic](https://www.curseforge.com/wow/addons/atlaslootclassic) | Smarter search, less chatter |
| [BigWigs](https://www.curseforge.com/wow/addons/big-wigs) | Proximity text updates less often |
| [Gargul](https://www.curseforge.com/wow/addons/gargul) | Lighter during GDKP auctions |
| [MoveAny](https://www.curseforge.com/wow/addons/moveany) | Stops looking for features TBC doesnt have |
| [Attune](https://www.curseforge.com/wow/addons/attune) | Faster sorting and filtering |
| [NovaWorldBuffs](https://www.curseforge.com/wow/addons/nova-world-buffs) | Map markers update less often |
| [AutoLayer](https://www.curseforge.com/wow/addons/autolayer) | Faster message processing |

### Compatibility

*Retail features these addons expected? Not here. PatchWerk covers for them.*

| Addon | |
|---|---|
| [SexyMap](https://www.curseforge.com/wow/addons/sexymap) | Slash command works on TBC now |
| [NovaWorldBuffs](https://www.curseforge.com/wow/addons/nova-world-buffs) | Missing functions filled in |

### Tweaks

*Not broken, just... could be better.*

| Addon | |
|---|---|
| [EasyFrames](https://www.curseforge.com/wow/addons/easy-frames) | 36T health text fixed to K/M/B |
| [AutoLayer](https://www.curseforge.com/wow/addons/autolayer) | Movable status frame with current layer, on/off state, and session stats. Gold toast notification on layer changes. Full hop lifecycle tracking with auto group-leave on confirmation. Enhanced minimap tooltip with layer count and hop progress |

---

## Getting Started

1. Install from [CurseForge](https://www.curseforge.com/wow/addons/patchwerk) or drop the folder into `Interface/AddOns/`
2. Log in. A welcome wizard walks you through which addons were detected and lets you toggle patches
3. Type `/pw` if you want to change anything later

PatchWerk only patches addons you actually have installed. Everything is enabled by default, but the wizard and settings panel let you turn individual patches on or off. If Patchwerk himself had this kind of efficiency, he wouldnt need a hateful strike.

---

## Commands

Type `/pw` to open the settings panel. Type `/pw status` to see which patches are active.

<details>
<summary>Full command list</summary>

| Command | Description |
|---|---|
| `/pw` | Open settings panel |
| `/pw fixes` | Jump to Fixes page |
| `/pw performance` | Jump to Performance page |
| `/pw tweaks` | Jump to Tweaks page |
| `/pw about` | Jump to About page |
| `/pw status` | Print all patch statuses to chat |
| `/pw toggle <name>` | Toggle a specific patch on/off |
| `/pw reset` | Reset all settings to defaults |
| `/pw outdated` | Check for outdated patches |
| `/pw version` | Show version info |
| `/pw wizard` | Show the welcome wizard |
| `/pw help` | Show command help in chat |

</details>

---

## How It Works

- **Hooks in at startup.** PatchWerk loads alongside your other addons and applies targeted fixes before you ever see a loading screen.
- **Each patch is independent.** If one fails, the rest still apply normally. No wipe recovery needed.
- **Your addon files are never touched.** Everything runs in memory. Disable PatchWerk and your addons go back to exactly how they were.

---

## Feedback & Requests

Found a bug? Want PatchWerk to support another addon? Open an issue:

- [Bug Report](https://github.com/Eventyret/PatchWerk/issues/new?template=bug_report.yml) - Something broke or isnt working right
- [Addon Patch Request](https://github.com/Eventyret/PatchWerk/issues/new?template=addon_request.yml) - Suggest an addon for PatchWerk to patch
- [Outdated Patch Report](https://github.com/Eventyret/PatchWerk/issues/new?template=outdated_patch.yml) - An addon updated and a patch may need changes

## Why Does This Exist?

TBC Classic Anniversary is a weird place for addons. Some were written for retail and expect functions that simply arent here. Others were built for Classic Era and never got optimized for TBC. A lot of them run background work every single frame because nobody told them to stop.

PatchWerk was born out of staring at profiler output and wondering why Details is rebuilding colors 60 times a second, or why Plater creates a new timer every frame. These arent bad addons. Theyre great addons that just need a nudge. Rather than waiting for 28 different authors to each ship a fix, PatchWerk patches them all in one place, at load time, without touching a single file on disk.

If you have ever `/reload`d to fix lag and it actually worked, theres a good chance PatchWerk would have fixed it for you permanently.

## Thank You

PatchWerk only exists because 28 addon authors put in the work first. Every addon on the list above is built and maintained by people who do this in their free time so the rest of us can have a better game. PatchWerk doesnt replace what they do. It just helps their stuff run a little smoother on a version of WoW that most of them never specifically built for.

If you use any of these addons, go leave them a thumbs up on CurseForge or star them on GitHub. They earned it.

## License

[MIT](LICENSE)
