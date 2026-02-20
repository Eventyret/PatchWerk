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
