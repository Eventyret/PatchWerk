# PatchWerk

Runtime performance, compatibility, and QOL patches for popular addons on WoW TBC Classic Anniversary.

PatchWerk hooks into other addons at load time and applies targeted fixes — no addon files are modified. Patches are individually toggleable, wrapped in `pcall` for safety, and automatically disabled if the target addon isn't installed.

## Supported Addons

| Addon | Patches | Category |
|---|---|---|
| Details (Damage Meter) | 5 | Performance |
| Plater (Nameplates) | 3 | Performance |
| Pawn (Item Comparison) | 3 | Performance |
| TipTac (Tooltips) | 2 | Performance |
| Questie (Quest Helper) | 3 | Performance |
| LFG Bulletin Board | 2 | Performance |
| Bartender4 (Action Bars) | 3 | Performance, Fixes |
| Titan Panel | 3 | Performance |
| OmniCC (Cooldown Text) | 3 | Performance |
| Prat-3.0 (Chat) | 5 | Performance |
| GatherMate2 (Gathering) | 3 | Performance |
| Quartz (Cast Bars) | 4 | Performance |
| Auctionator (Auction House) | 4 | Performance |
| VuhDo (Raid Frames) | 3 | Performance |
| Cell (Raid Frames) | 4 | Performance |
| BigDebuffs (Debuff Display) | 2 | Performance |
| EasyFrames (Unit Frames) | 1 | Tweaks |
| BugSack (Error Display) | 3 | Fixes, Performance |
| LoonBestInSlot (Gear Guide) | 5 | Fixes, Tweaks |
| Nova Instance Tracker | 2 | Fixes |
| AutoLayer (Layer Hopping) | 9 | Performance, Fixes, Tweaks |
| AtlasLoot Classic (Loot Browser) | 3 | Performance |
| BigWigs (Boss Mods) | 1 | Performance |
| Gargul (Loot Distribution) | 4 | Performance |
| SexyMap (Minimap) | 1 | Compatibility |
| MoveAny (UI Mover) | 2 | Performance |
| Attune (Attunement Tracker) | 3 | Performance |
| NovaWorldBuffs (World Buff Timers) | 5 | Compatibility, Performance |

**90 patches** across **28 addon groups**.

## How It Works

1. PatchWerk loads via `ADDON_LOADED` after its target addons
2. For each enabled patch, it hooks or replaces specific functions in the target addon
3. Every patch is wrapped in `pcall` — if a patch fails, it logs the error and the rest continue
4. No addon files on disk are ever modified; everything is runtime-only

**Categories:**
- **Performance** — Reduces FPS drops, memory usage, or network traffic
- **Fixes** — Prevents crashes or errors specific to TBC Classic Anniversary
- **Tweaks** — Improves addon behavior or fixes confusing display issues
- **Compatibility** — Shims missing API functions for TBC Classic Anniversary

## Installation

**CurseForge / WowUp:** Search for "PatchWerk" and install.

**Manual:** Download the latest release from [GitHub Releases](https://github.com/Eventyret/PatchWerk/releases), extract into your `Interface/AddOns/` folder, and restart the game.

## Usage

### Slash Commands

| Command | Description |
|---|---|
| `/pw` or `/patchwerk` | Open the settings panel |
| `/pw fixes` | Open the Fixes category page |
| `/pw performance` | Open the Performance category page |
| `/pw tweaks` | Open the Tweaks category page |
| `/pw about` | Open the About page |
| `/pw status` | Print all patch statuses to chat |
| `/pw toggle <name>` | Toggle a specific patch on/off |
| `/pw reset` | Reset all settings to defaults |
| `/pw outdated` | Check for outdated patches |
| `/pw version` | Show version info |
| `/pw wizard` | Show the welcome wizard |
| `/pw help` | Show command help in chat |

### Settings Panel

Open the Blizzard Interface Options or type `/pw` to access the GUI. Patches are grouped by target addon with impact badges (FPS, Memory, Network) and severity levels (High, Medium, Low). Each patch can be toggled individually.

## Version Checking

PatchWerk tracks the version of each target addon it was tested against. When a target addon updates:

- **At login:** PatchWerk compares installed addon versions against its `targetVersion` fields and warns you in chat if any have changed
- **`/pw outdated`** shows which patches may need verification after an addon update
- Outdated patches still work — the warning is informational so you can report any issues

PatchWerk also broadcasts its own version to guild, party, and raid members via invisible addon messages (the same mechanism used by DBM and BigWigs). If a guildmate has a newer version, you'll see a one-time notification.

## Reporting Issues

- [Bug Report](https://github.com/Eventyret/PatchWerk/issues/new?template=bug_report.yml) — Something broke or isn't working right
- [Addon Patch Request](https://github.com/Eventyret/PatchWerk/issues/new?template=addon_request.yml) — Suggest an addon for PatchWerk to patch
- [Outdated Patch Report](https://github.com/Eventyret/PatchWerk/issues/new?template=outdated_patch.yml) — A target addon updated and a patch may need changes

## License

[MIT](LICENSE)
