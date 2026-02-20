-- PatchWerk - Centralized addon registry
-- Loaded between Core.lua and Patches/*.lua
-- Provides: ns.registry, ns.addonGroups, ns.addonGroupsByIdLower,
--           ns:RegisterPatch(), ns:RegisterDefault()

local _, ns = ...

------------------------------------------------------------------------
-- Registry: one entry per supported addon
-- Fields: id, label, deps, status, targetVersion (optional)
-- Note: deps[1] is always the addon folder name (used by tools)
------------------------------------------------------------------------
ns.registry = {
    { id = "Details",            label = "Details (Damage Meter)",                  deps = { "Details" },             status = "verified",    targetVersion = "#Details.20260217.14604.169" },
    { id = "Plater",             label = "Plater (Nameplates)",                     deps = { "Plater" },              status = "verified",    targetVersion = "Plater-v632-TBC" },
    { id = "Pawn",               label = "Pawn (Item Comparison)",                  deps = { "Pawn" },                status = "verified",    targetVersion = "2.13.0" },
    { id = "TipTac",             label = "TipTac (Tooltips)",                       deps = { "TipTac" },              status = "verified",    targetVersion = "26.02.18" },
    { id = "Questie",            label = "Questie (Quest Helper)",                  deps = { "Questie" },             status = "verified",    targetVersion = "11.21.6" },
    { id = "LFGBulletinBoard",   label = "LFG Bulletin Board",                     deps = { "LFGBulletinBoard" },    status = "verified",    targetVersion = "3.50" },
    { id = "Bartender4",         label = "Bartender4 (Action Bars)",                deps = { "Bartender4" },          status = "verified",    targetVersion = "4.17.3" },
    { id = "TitanPanel",         label = "Titan Panel",                             deps = { "Titan" },               status = "verified",    targetVersion = "9.1.1" },
    { id = "OmniCC",             label = "OmniCC (Cooldown Text)",                  deps = { "OmniCC" },              status = "verified",    targetVersion = "11.2.8" },
    { id = "Prat",               label = "Prat-3.0 (Chat)",                        deps = { "Prat-3.0" },            status = "verified",    targetVersion = "3.9.87" },
    { id = "GatherMate2",        label = "GatherMate2 (Gathering)",                 deps = { "GatherMate2" },         status = "verified",    targetVersion = "1.47.9-classic" },
    { id = "Quartz",             label = "Quartz (Cast Bars)",                      deps = { "Quartz" },              status = "verified",    targetVersion = "3.7.17" },
    { id = "Auctionator",        label = "Auctionator (Auction House)",             deps = { "Auctionator" },         status = "verified",    targetVersion = "308" },
    { id = "VuhDo",              label = "VuhDo (Raid Frames)",                     deps = { "VuhDo" },               status = "verified",    targetVersion = "3.197-tbcc" },
    { id = "Cell",               label = "Cell (Raid Frames)",                      deps = { "Cell" },                status = "verified",    targetVersion = "r274-release" },
    { id = "BigDebuffs",         label = "BigDebuffs (Debuff Display)",             deps = { "BigDebuffs" },          status = "verified",    targetVersion = "v58" },
    { id = "BugSack",            label = "BugSack (Error Display)",                 deps = { "BugSack" },             status = "verified",    targetVersion = "v11.2.9" },
    { id = "LoonBestInSlot",     label = "LoonBestInSlot (Gear Guide)",             deps = { "LoonBestInSlot" },      status = "shim-fixed", targetVersion = "6.0.0" },
    { id = "NovaInstanceTracker", label = "Nova Instance Tracker",                  deps = { "NovaInstanceTracker" }, status = "verified",    targetVersion = "2.17" },
    { id = "AutoLayer",          label = "AutoLayer (Layer Hopping)",               deps = { "AutoLayer_Vanilla" },   status = "verified",    targetVersion = "1.7.6" },
    { id = "AtlasLootClassic",   label = "AtlasLoot Classic (Loot Browser)",        deps = { "AtlasLootClassic" },    status = "verified",    targetVersion = "BCC 2.5.4" },
    { id = "BigWigs",            label = "BigWigs (Boss Mods)",                     deps = { "BigWigs" },             status = "verified",    targetVersion = "v406.5" },
    { id = "Gargul",             label = "Gargul (Loot Distribution)",              deps = { "Gargul" },              status = "verified",    targetVersion = "7.7.19" },
    { id = "SexyMap",            label = "SexyMap (Minimap)",                       deps = { "SexyMap" },             status = "shim-fixed", targetVersion = "v12.0.2" },
    { id = "MoveAny",            label = "MoveAny (UI Mover)",                     deps = { "MoveAny" },             status = "verified",    targetVersion = "1.8.250" },
    { id = "Attune",             label = "Attune (Attunement Tracker)",             deps = { "Attune" },              status = "verified",    targetVersion = "266" },
    { id = "NovaWorldBuffs",     label = "NovaWorldBuffs (World Buff Timers)",      deps = { "NovaWorldBuffs" },      status = "shim-fixed", targetVersion = "3.30" },
    { id = "LeatrixMaps",        label = "Leatrix Maps",                            deps = { "Leatrix_Maps" },        status = "verified",    targetVersion = "2.5.09" },
    { id = "LeatrixPlus",        label = "Leatrix Plus (QOL)",                      deps = { "Leatrix_Plus" },        status = "verified",    targetVersion = "2.5.09" },
    { id = "NameplateSCT",       label = "NameplateSCT (Combat Text)",              deps = { "NameplateSCT" },        status = "verified",    targetVersion = "1.52" },
    { id = "QuestXP",            label = "QuestXP (Quest XP Display)",              deps = { "QuestXP" },             status = "verified",    targetVersion = "0.6.2" },
    { id = "RatingBuster",       label = "RatingBuster (Stat Comparison)",          deps = { "RatingBuster" },        status = "verified",    targetVersion = "2.1.4" },
    { id = "ClassTrainerPlus",   label = "ClassTrainerPlus (Trainer Enhancement)",  deps = { "ClassTrainerPlus" },    status = "verified",    targetVersion = "1.4.1" },
    { id = "Baganator",          label = "Baganator (Bags)",                        deps = { "Baganator" },           status = "verified",    targetVersion = "787" },
}

------------------------------------------------------------------------
-- Build ns.addonGroups and lookup tables from registry
------------------------------------------------------------------------
ns.addonGroups = {}
ns.addonGroupsByIdLower = {}

local registryById = {}

for _, entry in ipairs(ns.registry) do
    ns.addonGroups[#ns.addonGroups + 1] = {
        id = entry.id,
        label = entry.label,
        deps = entry.deps,
        status = entry.status,
    }
    ns.addonGroupsByIdLower[entry.id:lower()] = entry.id
    registryById[entry.id] = entry
end

-- Sort addon groups alphabetically by label for consistent display
table.sort(ns.addonGroups, function(a, b)
    return a.label:lower() < b.label:lower()
end)

------------------------------------------------------------------------
-- ns:RegisterPatch(groupId, info)
--
-- Called by Patches/*.lua to register a patch. Sets group, targetVersion
-- (from registry if not provided), appends to patchInfo, and auto-adds
-- the key to defaults as true.
------------------------------------------------------------------------
function ns:RegisterPatch(groupId, info)
    local reg = registryById[groupId]
    if not reg then
        error("PatchWerk: Unknown group '" .. tostring(groupId) .. "' in RegisterPatch", 2)
    end

    info.group = groupId

    if info.targetVersion == nil then
        info.targetVersion = reg.targetVersion
    end

    ns.patchInfo[#ns.patchInfo + 1] = info
    ns.defaults[info.key] = true
end

------------------------------------------------------------------------
-- ns:RegisterDefault(key, value)
--
-- For non-boolean defaults or settings without a corresponding patch
-- (e.g., Baganator_sortThrottleRate, AutoLayer_hopWhisperMessage).
------------------------------------------------------------------------
function ns:RegisterDefault(key, value)
    ns.defaults[key] = value
end
