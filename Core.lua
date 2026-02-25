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

-- Default settings (populated by Registry.lua and Patches/*.lua)
-- Patch defaults are auto-registered via ns:RegisterPatch().
-- Non-patch settings live here.
local defaults = {
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

-- Addon groups, lookup tables, RegisterPatch, and RegisterDefault
-- are provided by Registry.lua (loaded before Patches/*.lua)

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

    -- Migrate stale defaults that changed between versions
    local MIGRATIONS = {
        { key = "AutoLayer_hopWhisperMessage",
          old = "[PatchWerk] Thanks for the hop!",
          new = "[PatchWerk] Hopped! Smoother than a Paladin bubble-hearth. Cheers!" },
    }
    for _, m in ipairs(MIGRATIONS) do
        if PatchWerkDB[m.key] == m.old then
            PatchWerkDB[m.key] = m.new
        end
    end

    -- Prune stale keys from old patch versions
    local RESERVED_DB_KEYS = {
        dismissedOutdated = true,
        wizardCompleted = true,
        lastSeenPatchWerkVersion = true,
        lastSeenChangelogVersion = true,
        updateNotificationShown = true,
    }
    for key in pairs(PatchWerkDB) do
        if defaults[key] == nil and not RESERVED_DB_KEYS[key] then
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
                ns:Print("|cffff6666" .. (pi.label or name) .. " could not be applied.|r Type /pw to disable it.")
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

end)

------------------------------------------------------------------------
-- Taint Diagnostic: identifies EXACTLY which globals PatchWerk tainted.
-- Runs automatically on ADDON_ACTION_FORBIDDEN and via /pw taintcheck.
------------------------------------------------------------------------
function ns:RunTaintCheck()
    self:Print("|cffffcc00--- Taint Diagnostic ---")
    local taintCount = 0
    local pwCount = 0

    local function Check(label, tbl, key)
        if tbl[key] == nil then return end
        local ok, secure, taintedBy = pcall(issecurevariable, tbl, key)
        if not ok then return end
        if secure then return end
        taintCount = taintCount + 1
        local isPW = (taintedBy == "PatchWerk" or taintedBy == "!PatchWerk")
        if isPW then pwCount = pwCount + 1 end
        local tag = isPW and "|cffff3333" or "|cffffcc00"
        self:Print(tag .. "TAINT:|r " .. label .. "." .. key .. " -> |cff33ccff" .. (taintedBy or "?") .. "|r")
    end

    -- SpellBook-critical globals
    local spellbook = {
        "CastSpell", "SpellBook_GetSpellBookSlot", "SpellButton_UpdateButton",
        "SpellBookFrame_Update", "SpellBookFrame_UpdateSpells",
        "GetSpellBookItemInfo", "GetSpellBookItemName", "GetSpellInfo",
        "GetSpellTexture", "GetSpellCooldown", "IsPassiveSpell",
        "IsCurrentSpell", "IsSelectedSpell", "GetSpellAutocast",
        "BOOKTYPE_SPELL", "BOOKTYPE_PET", "MAX_SPELLS", "SpellBookFrame",
    }
    for _, key in ipairs(spellbook) do Check("_G", _G, key) end

    -- Action bar related (taint can chain to spellbook)
    local actionbar = {
        "UpdatePressAndHoldAction", "ActionButton_UpdateAction",
        "ActionButton_OnEvent", "MultiActionBar_ShowAllGrids",
        "MultiActionBar_HideAllGrids",
    }
    for _, key in ipairs(actionbar) do Check("_G", _G, key) end

    -- Globals PatchWerk patches may have written
    local patched = {
        "NotifyInspect", "TitanPanelButton_UpdateButton",
        "PawnCacheItem", "PawnUncacheItem", "PawnClearCache",
        "PawnGetCachedItem", "PawnUpdateTooltip", "PawnIsItemAnUpgrade",
        "VUHDO_determineDebuff", "VUHDO_updateUnitRange", "VUHDO_tryInspectNext",
        "C_SummonInfo", "NWB_CurrentLayer", "ProccessQueue",
        "SLASH_PATCHWERK1", "SLASH_PATCHWERK2",
    }
    for _, key in ipairs(patched) do Check("_G", _G, key) end

    -- Enum table entries
    if type(Enum) == "table" then
        for key in pairs(Enum) do
            Check("Enum", Enum, tostring(key))
        end
    end

    -- SpellBookFrame properties
    if SpellBookFrame then
        for _, key in ipairs({"bookType", "selectedSkillLine", "currentPage", "maxPages"}) do
            Check("SpellBookFrame", SpellBookFrame, key)
        end
    end

    -- SlashCmdList entry
    if SlashCmdList then
        Check("SlashCmdList", SlashCmdList, "PATCHWERK")
    end

    if taintCount == 0 then
        self:Print("|cff33ff33No taint found in checked globals.|r")
        self:Print("May be execution-path taint (not value-based).")
    else
        self:Print(taintCount .. " tainted (" .. pwCount .. " by PatchWerk).")
    end
    self:Print("|cffffcc00--- End Diagnostic ---")
end

-- Auto-run diagnostic once when PatchWerk is blamed for a blocked action
do
    local diagRan = false
    local diagFrame = CreateFrame("Frame")
    diagFrame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    diagFrame:SetScript("OnEvent", function(_, _, addon)
        if addon ~= "PatchWerk" and addon ~= "!PatchWerk" then return end
        if diagRan then return end
        diagRan = true
        C_Timer.After(0.5, function()
            ns:Print("|cffff6666ADDON_ACTION_FORBIDDEN detected.|r Running taint diagnostic...")
            ns:RunTaintCheck()
        end)
    end)
end
