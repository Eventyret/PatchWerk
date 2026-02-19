-- PatchWerk - Performance patches for popular addons
-- Core initialization and settings framework

local ADDON_NAME, ns = ...

local pairs = pairs
local pcall = pcall
local tostring = tostring
local CreateFrame = CreateFrame
local DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME

local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local IsAddonLoadedFn = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
local rawVersion = GetMeta("PatchWerk", "Version") or "dev"
ns.VERSION = rawVersion:find("@") and "dev" or rawVersion

-- Default settings: all patches enabled by default
-- Keys follow the pattern: "TargetAddon_patchName"
local defaults = {
    -- Details
    Details_hexFix = true,
    Details_fadeHandler = true,
    Details_refreshCap = true,
    Details_npcIdCache = true,
    Details_formatCache = true,
    -- Plater
    Plater_fpsCheck = true,
    Plater_healthText = true,
    Plater_auraAlign = true,
    -- Pawn
    Pawn_cacheIndex = true,
    Pawn_tooltipDedup = true,
    Pawn_upgradeCache = true,
    -- TipTac
    TipTac_unitAppearanceGuard = true,
    TipTac_inspectCache = true,
    -- Questie
    Questie_questLogThrottle = true,
    Questie_availableQuestsDebounce = true,
    Questie_framePoolPrealloc = true,
    -- LFGBulletinBoard
    LFGBulletinBoard_updateListDirty = true,
    LFGBulletinBoard_sortSkip = true,
    -- Bartender4
    Bartender4_lossOfControlSkip = true,
    Bartender4_usableThrottle = true,
    Bartender4_pressAndHoldGuard = true,
    -- TitanPanel
    TitanPanel_reputationsOnUpdate = true,
    TitanPanel_bagDebounce = true,
    TitanPanel_performanceThrottle = true,
    -- OmniCC
    OmniCC_gcdSpellCache = true,
    OmniCC_ruleMatchCache = true,
    OmniCC_finishEffectGuard = true,
    -- Prat-3.0
    Prat_smfThrottle = true,
    Prat_timestampCache = true,
    Prat_bubblesGuard = true,
    Prat_playerNamesThrottle = true,
    Prat_guildRosterThrottle = true,
    -- GatherMate2
    GatherMate2_minimapThrottle = true,
    GatherMate2_rebuildGuard = true,
    GatherMate2_cleuUnregister = true,
    -- Quartz
    Quartz_castBarThrottle = true,
    Quartz_swingBarThrottle = true,
    Quartz_gcdBarThrottle = true,
    Quartz_buffBucket = true,
    -- Auctionator
    Auctionator_ownerQueryThrottle = true,
    Auctionator_throttleBroadcast = true,
    Auctionator_priceAgeOptimize = true,
    Auctionator_dbKeyCache = true,
    -- VuhDo
    VuhDo_debuffDebounce = true,
    VuhDo_rangeSkipDead = true,
    VuhDo_inspectThrottle = true,
    -- Cell
    Cell_debuffOrderMemo = true,
    Cell_customIndicatorGuard = true,
    Cell_debuffGlowMemo = true,
    Cell_inspectQueueThrottle = true,
    -- BigDebuffs
    BigDebuffs_hiddenDebuffsHash = true,
    BigDebuffs_attachFrameGuard = true,
    -- EasyFrames
    EasyFrames_healthTextFix = true,
    -- BugSack
    BugSack_settingsCompat = true,
    BugSack_formatCache = true,
    BugSack_searchThrottle = true,
    -- LoonBestInSlot
    LoonBestInSlot_apiCompat = true,
    LoonBestInSlot_containerCompat = true,
    LoonBestInSlot_settingsCompat = true,
    LoonBestInSlot_phaseUpdate = true,
    LoonBestInSlot_nilGuards = true,
    -- NovaInstanceTracker
    NovaInstanceTracker_weeklyResetGuard = true,
    NovaInstanceTracker_settingsCompat = true,
    -- AutoLayer
    AutoLayer_keyDownThrottle = true,
    AutoLayer_parseCache = true,
    AutoLayer_systemFilterCache = true,
    AutoLayer_pruneCacheFix = true,
    AutoLayer_libSerializeCleanup = true,
    AutoLayer_layerStatusFrame = true,
    AutoLayer_layerChangeToast = true,
    AutoLayer_hopTransitionTracker = true,
    AutoLayer_hopWhisperEnabled = true,
    AutoLayer_hopWhisperMessage = "[PatchWerk] Thanks for the hop!",
    AutoLayer_enhancedTooltip = true,
    -- AtlasLootClassic
    AtlasLootClassic_searchDebounce = true,
    AtlasLootClassic_rosterDebounce = true,
    AtlasLootClassic_searchLowerCache = true,
    -- BigWigs
    BigWigs_proxTextThrottle = true,
    -- Gargul
    Gargul_commRefreshSkip = true,
    Gargul_lootPollThrottle = true,
    Gargul_tradeTimerFix = true,
    Gargul_commBoxPrune = true,
    -- SexyMap
    SexyMap_slashCmdFix = true,
    -- MoveAny
    MoveAny_thinkHelpFrameSkip = true,
    MoveAny_updateMoveFramesDebounce = true,
    -- Attune
    Attune_spairsOptimize = true,
    Attune_bagUpdateDebounce = true,
    Attune_cleuEarlyExit = true,
    -- NovaWorldBuffs
    NovaWorldBuffs_openConfigFix = true,
    NovaWorldBuffs_markerThrottle = true,
    NovaWorldBuffs_cAddOnsShim = true,
    NovaWorldBuffs_cSummonInfoShim = true,
    NovaWorldBuffs_pairsByKeysOptimize = true,
    -- Leatrix Maps
    LeatrixMaps_areaLabelThrottle = true,
    -- Leatrix Plus
    LeatrixPlus_taxiOnUpdateThrottle = true,
    -- NameplateSCT
    NameplateSCT_animationThrottle = true,
    -- QuestXP
    QuestXP_questLogDebounce = true,
    -- RatingBuster
    RatingBuster_debugstackOptimize = true,
    -- ClassTrainerPlus
    ClassTrainerPlus_shiftKeyThrottle = true,
    -- Baganator
    Baganator_itemLockFix = true,
    Baganator_sortThrottle = true,
    Baganator_sortThrottleRate = 0.2,
    Baganator_buttonVisThrottle = true,
    Baganator_buttonVisRate = 0.1,
    Baganator_tooltipCache = true,
    Baganator_updateDebounce = true,
    Baganator_updateDebounceRate = 0.05,
    -- Version checking
    showOutdatedWarnings = true,
    showUpdateNotification = true,
}

ns.defaults = defaults

-- Patch registry (populated by individual patch files before ADDON_LOADED fires)
ns.patches = {}

-- Patch metadata registry (populated by individual patch files)
-- Each entry: { key, group, label, help, detail, impact, impactLevel, category, estimate }
ns.patchInfo = {}

-- Track which patches were applied, and target addon info
ns.applied = {}

-- Addon grouping metadata for the GUI
-- status: "verified" = tested, "shim-fixed" = needs !PatchWerk shims, "untested" = not re-verified
ns.addonGroups = {
    { id = "Details",           label = "Details (Damage Meter)",    deps = { "Details" },             status = "verified" },
    { id = "Plater",            label = "Plater (Nameplates)",       deps = { "Plater" },              status = "verified" },
    { id = "Pawn",              label = "Pawn (Item Comparison)",    deps = { "Pawn" },                status = "verified" },
    { id = "TipTac",            label = "TipTac (Tooltips)",         deps = { "TipTac" },              status = "verified" },
    { id = "Questie",           label = "Questie (Quest Helper)",    deps = { "Questie" },             status = "verified" },
    { id = "LFGBulletinBoard",  label = "LFG Bulletin Board",       deps = { "LFGBulletinBoard" },    status = "verified" },
    { id = "Bartender4",        label = "Bartender4 (Action Bars)",  deps = { "Bartender4" },          status = "verified" },
    { id = "TitanPanel",        label = "Titan Panel",               deps = { "Titan" },               status = "verified" },
    { id = "OmniCC",            label = "OmniCC (Cooldown Text)",    deps = { "OmniCC" },              status = "verified" },
    { id = "Prat",              label = "Prat-3.0 (Chat)",           deps = { "Prat-3.0" },            status = "verified" },
    { id = "GatherMate2",       label = "GatherMate2 (Gathering)",   deps = { "GatherMate2" },         status = "verified" },
    { id = "Quartz",            label = "Quartz (Cast Bars)",        deps = { "Quartz" },              status = "verified" },
    { id = "Auctionator",       label = "Auctionator (Auction House)", deps = { "Auctionator" },       status = "verified" },
    { id = "VuhDo",             label = "VuhDo (Raid Frames)",       deps = { "VuhDo" },               status = "verified" },
    { id = "Cell",              label = "Cell (Raid Frames)",        deps = { "Cell" },                status = "verified" },
    { id = "BigDebuffs",        label = "BigDebuffs (Debuff Display)", deps = { "BigDebuffs" },        status = "verified" },
    { id = "EasyFrames",       label = "EasyFrames (Unit Frames)",    deps = { "EasyFrames" },         status = "verified" },
    { id = "BugSack",          label = "BugSack (Error Display)",    deps = { "BugSack" },             status = "verified" },
    { id = "LoonBestInSlot",   label = "LoonBestInSlot (Gear Guide)", deps = { "LoonBestInSlot" },    status = "shim-fixed" },
    { id = "NovaInstanceTracker", label = "Nova Instance Tracker",  deps = { "NovaInstanceTracker" },  status = "verified" },
    { id = "AutoLayer",          label = "AutoLayer (Layer Hopping)", deps = { "AutoLayer_Vanilla" },  status = "verified" },
    { id = "AtlasLootClassic",   label = "AtlasLoot Classic (Loot Browser)", deps = { "AtlasLootClassic" }, status = "verified" },
    { id = "BigWigs",            label = "BigWigs (Boss Mods)",      deps = { "BigWigs" },              status = "verified" },
    { id = "Gargul",             label = "Gargul (Loot Distribution)", deps = { "Gargul" },            status = "verified" },
    { id = "SexyMap",            label = "SexyMap (Minimap)",         deps = { "SexyMap" },             status = "shim-fixed" },
    { id = "MoveAny",            label = "MoveAny (UI Mover)",       deps = { "MoveAny" },             status = "verified" },
    { id = "Attune",             label = "Attune (Attunement Tracker)", deps = { "Attune" },           status = "verified" },
    { id = "NovaWorldBuffs",     label = "NovaWorldBuffs (World Buff Timers)", deps = { "NovaWorldBuffs" }, status = "shim-fixed" },
    { id = "LeatrixMaps",      label = "Leatrix Maps",              deps = { "Leatrix_Maps" },        status = "verified" },
    { id = "LeatrixPlus",      label = "Leatrix Plus (QOL)",        deps = { "Leatrix_Plus" },        status = "verified" },
    { id = "NameplateSCT",     label = "NameplateSCT (Combat Text)", deps = { "NameplateSCT" },       status = "verified" },
    { id = "QuestXP",          label = "QuestXP (Quest XP Display)", deps = { "QuestXP" },            status = "verified" },
    { id = "RatingBuster",     label = "RatingBuster (Stat Comparison)", deps = { "RatingBuster" },   status = "verified" },
    { id = "ClassTrainerPlus", label = "ClassTrainerPlus (Trainer Enhancement)", deps = { "ClassTrainerPlus" }, status = "verified" },
    { id = "Baganator",        label = "Baganator (Bags)",          deps = { "Baganator" },           status = "verified" },
}

-- Reverse lookup: lowercase group id -> canonical group id
ns.addonGroupsByIdLower = {}
for _, g in ipairs(ns.addonGroups) do
    ns.addonGroupsByIdLower[g.id:lower()] = g.id
end

function ns:GetDB()
    return PatchWerkDB
end

function ns:GetOption(key)
    local db = self:GetDB()
    if db and db[key] ~= nil then
        return db[key]
    end
    return defaults[key]
end

function ns:SetOption(key, value)
    local db = self:GetDB()
    if db then
        db[key] = value
    end
end

-- Check if a target addon is loaded
function ns:IsAddonLoaded(addonName)
    return IsAddonLoadedFn and IsAddonLoadedFn(addonName)
end

-- Print a message to chat
local CHAT_PREFIX = "|cff33ccff[PatchWerk]|r "
function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. msg)
end

local WHITE8x8 = "Interface\\Buttons\\WHITE8x8"
function ns.SetSolidColor(tex, r, g, b, a)
    tex:SetTexture(WHITE8x8)
    tex:SetVertexColor(r, g, b, a or 1)
end

-- Phase 1: Initialize saved variables on our own ADDON_LOADED
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addon)
    if addon ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")

    -- Initialize saved variables (migrate from old name if needed)
    local isNewInstall = not PatchWerkDB and not AddonTweaksDB
    if not PatchWerkDB then
        PatchWerkDB = AddonTweaksDB or {}
    end
    AddonTweaksDB = nil

    -- Copy missing defaults
    for key, value in pairs(defaults) do
        if PatchWerkDB[key] == nil then
            PatchWerkDB[key] = value
        end
    end

    -- Prune stale keys from old patch versions
    for key in pairs(PatchWerkDB) do
        if defaults[key] == nil and key ~= "dismissedOutdated" and key ~= "wizardCompleted"
            and key ~= "lastSeenPatchWerkVersion" and key ~= "updateNotificationShown" then
            PatchWerkDB[key] = nil
        end
    end

    -- Per-addon outdated dismissal storage
    if not PatchWerkDB.dismissedOutdated then
        PatchWerkDB.dismissedOutdated = {}
    end

    -- Wizard: new installs see the wizard, existing users skip it
    if isNewInstall then
        PatchWerkDB.wizardCompleted = false
    elseif PatchWerkDB.wizardCompleted == nil then
        PatchWerkDB.wizardCompleted = true
    end
end)

-- Phase 2: Apply patches at PLAYER_LOGIN (all addons are loaded by then)
local patcher = CreateFrame("Frame")
patcher:RegisterEvent("PLAYER_LOGIN")
patcher:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    local count = 0
    local patchedGroups = {}
    for _, pi in ipairs(ns.patchInfo) do
        local name = pi.key
        local patchFn = ns.patches[name]
        if not patchFn then -- skip metadata-only entries
        elseif ns:GetOption(name) then
            local ok, err = pcall(patchFn)
            if ok then
                ns.applied[name] = true
                count = count + 1
                -- Track which addon group this patch belongs to
                local group = pi.group
                if group and not patchedGroups[group] then
                    patchedGroups[group] = true
                end
            else
                ns:Print("Patch '" .. name .. "' failed: " .. tostring(err))
            end
        end
    end

    if count > 0 then
        -- Build addon name list: show up to 3, then "+N more"
        local names = {}
        for _, g in ipairs(ns.addonGroups) do
            if patchedGroups[g.id] then
                -- Use short name (strip parenthetical)
                local short = g.label:match("^(.-)%s*%(") or g.label
                names[#names + 1] = short
            end
        end
        local display
        if #names <= 3 then
            display = table.concat(names, ", ")
        else
            display = names[1] .. ", " .. names[2] .. ", " .. names[3] .. ", +" .. (#names - 3) .. " more"
        end
        ns:Print("Patched " .. display .. ".")
    end

    -- Suppress known !PatchWerk taint errors from BugGrabber/BugSack.
    -- The SetColorTexture metatable shim in !PatchWerk/Shims.lua taints the
    -- shared Texture __index, which causes harmless ADDON_ACTION_BLOCKED.
    -- These fire DURING addon loading (before PLAYER_LOGIN) and badAddons
    -- dedup means they only fire ONCE — so callbacks can't catch them.
    -- Scrub the error DB directly instead.
    if BugGrabberDB and BugGrabberDB.errors then
        local errs = BugGrabberDB.errors
        for i = #errs, 1, -1 do
            local msg = errs[i] and errs[i].message
            if msg and (msg:find("!PatchWerk", 1, true) or msg:find("PatchWerk", 1, true)) then
                table.remove(errs, i)
            end
        end
    end

    -- Also register a callback for defense-in-depth (handles edge cases
    -- where future taint errors bypass the badAddons one-shot gate).
    if BugGrabber then
        if BugGrabber.setupCallbacks then
            pcall(BugGrabber.setupCallbacks, BugGrabber)
        end
        if BugGrabber.RegisterCallback then
            local filter = {}
            BugGrabber.RegisterCallback(filter, "BugGrabber_BugGrabbed", function(_, err)
                if not err or not err.message then return end
                if not err.message:find("!PatchWerk", 1, true)
                    and not err.message:find("PatchWerk", 1, true) then return end
                local errs2 = BugGrabberDB and BugGrabberDB.errors
                if errs2 then
                    for i = #errs2, 1, -1 do
                        if errs2[i] == err then
                            table.remove(errs2, i)
                            break
                        end
                    end
                end
            end)
        end
    end
end)
