-- PatchWerk - Performance patches for popular addons
-- Core initialization and settings framework

local ADDON_NAME, ns = ...

local pairs = pairs
local pcall = pcall
local tostring = tostring
local CreateFrame = CreateFrame
local DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME

ns.VERSION = "2.0.0"

-- Default settings: all patches enabled by default
-- Keys follow the pattern: "TargetAddon_patchName"
local defaults = {
    -- Details
    Details_hexFix = true,
    Details_fadeHandler = true,
    Details_refreshCap = true,
    Details_npcIdCache = true,
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
    -- LFGBulletinBoard
    LFGBulletinBoard_updateListDirty = true,
    LFGBulletinBoard_sortSkip = true,
    -- Bartender4
    Bartender4_lossOfControlSkip = true,
    Bartender4_usableThrottle = true,
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
    -- GatherMate2
    GatherMate2_minimapThrottle = true,
    GatherMate2_rebuildGuard = true,
    GatherMate2_cleuUnregister = true,
    -- Quartz
    Quartz_castBarThrottle = true,
    Quartz_swingBarThrottle = true,
    Quartz_gcdBarThrottle = true,
    -- Auctionator
    Auctionator_ownerQueryThrottle = true,
    Auctionator_throttleBroadcast = true,
    Auctionator_priceAgeOptimize = true,
    Auctionator_dbKeyCache = true,
    -- VuhDo
    VuhDo_debuffDebounce = true,
    VuhDo_rangeSkipDead = true,
    -- Cell
    Cell_debuffOrderMemo = true,
    Cell_customIndicatorGuard = true,
    Cell_debuffGlowMemo = true,
}

ns.defaults = defaults

-- Patch registry (populated by individual patch files before ADDON_LOADED fires)
ns.patches = {}

-- Track which patches were applied, and target addon info
ns.applied = {}

-- Addon grouping metadata for the GUI
ns.addonGroups = {
    { id = "Details",           label = "Details (Damage Meter)",    deps = { "Details" } },
    { id = "Plater",            label = "Plater (Nameplates)",       deps = { "Plater" } },
    { id = "Pawn",              label = "Pawn (Item Comparison)",    deps = { "Pawn" } },
    { id = "TipTac",            label = "TipTac (Tooltips)",         deps = { "TipTac" } },
    { id = "Questie",           label = "Questie (Quest Helper)",    deps = { "Questie" } },
    { id = "LFGBulletinBoard",  label = "LFG Bulletin Board",       deps = { "LFGBulletinBoard" } },
    { id = "Bartender4",        label = "Bartender4 (Action Bars)",  deps = { "Bartender4" } },
    { id = "TitanPanel",        label = "Titan Panel",               deps = { "Titan" } },
    { id = "OmniCC",            label = "OmniCC (Cooldown Text)",    deps = { "OmniCC" } },
    { id = "Prat",              label = "Prat-3.0 (Chat)",           deps = { "Prat-3.0" } },
    { id = "GatherMate2",       label = "GatherMate2 (Gathering)",   deps = { "GatherMate2" } },
    { id = "Quartz",            label = "Quartz (Cast Bars)",        deps = { "Quartz" } },
    { id = "Auctionator",       label = "Auctionator (Auction House)", deps = { "Auctionator" } },
    { id = "VuhDo",             label = "VuhDo (Raid Frames)",       deps = { "VuhDo" } },
    { id = "Cell",              label = "Cell (Raid Frames)",        deps = { "Cell" } },
}

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
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return loaded and loaded(addonName)
end

-- Print a message to chat
local CHAT_PREFIX = "|cff33ccff[PatchWerk]|r "
function ns:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. msg)
end

-- Initialization on ADDON_LOADED
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, addon)
    if addon ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")

    -- Initialize saved variables (migrate from old name if needed)
    if not PatchWerkDB then
        PatchWerkDB = AddonTweaksDB or {}
        AddonTweaksDB = nil
    end

    -- Copy missing defaults
    for key, value in pairs(defaults) do
        if PatchWerkDB[key] == nil then
            PatchWerkDB[key] = value
        end
    end

    -- Apply patches, counting successes
    local count = 0
    local skipped = 0
    for name, patchFn in pairs(ns.patches) do
        if ns:GetOption(name) then
            local ok, err = pcall(patchFn)
            if ok then
                ns.applied[name] = true
                count = count + 1
            else
                ns:Print("Patch '" .. name .. "' failed: " .. tostring(err))
            end
        else
            skipped = skipped + 1
        end
    end

    if count > 0 then
        ns:Print(count .. " patches applied" .. (skipped > 0 and (" (" .. skipped .. " disabled)") or "") .. ".")
    end
end)
