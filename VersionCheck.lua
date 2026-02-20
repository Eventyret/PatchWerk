-- PatchWerk - Version checking and update detection
--
-- Scans for outdated patches (target addon was updated since patch was
-- written) and broadcasts PatchWerk's own version via addon messaging
-- for self-update notifications.
--
-- All checks run once at PLAYER_LOGIN.  No polling, no OnUpdate frames.

local ADDON_NAME, ns = ...

-- TBC Classic API compatibility
local SendAddonMsg = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
local RegisterPrefix = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
local GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

local ADDON_MSG_PREFIX = "PatchWerk"
local VERSION_MSG_TAG = "V:"

-- Results populated at PLAYER_LOGIN, consumed by Options.lua
ns.versionResults = {}
ns.outdatedPatches = {}
ns.GITHUB_URL = "https://github.com/Eventyret/PatchWerk/issues"

---------------------------------------------------------------------------
-- Semantic version parsing (for PatchWerk's own version only)
---------------------------------------------------------------------------
local function ParseSemVer(str)
    if not str then return nil end
    local major, minor, patch = str:match("^(%d+)%.(%d+)%.(%d+)$")
    if not major then return nil end
    return tonumber(major) * 1000000 + tonumber(minor) * 1000 + tonumber(patch)
end

---------------------------------------------------------------------------
-- Target addon version scanning
---------------------------------------------------------------------------
local function GetInstalledVersion(addonName)
    if not addonName or not GetMeta then return nil end
    local ok, version = pcall(GetMeta, addonName, "Version")
    if not ok or not version or version == "" then return nil end
    -- Skip unpackaged dev builds (TOC still has the packaging placeholder)
    if version:find("@") then return nil end
    return version
end

function ns:ScanOutdatedPatches()
    wipe(self.versionResults)
    wipe(self.outdatedPatches)

    -- Build lookup: groupId -> loaded addon name
    local groupAddon = {}
    for _, g in ipairs(self.addonGroups) do
        for _, dep in ipairs(g.deps) do
            if self:IsAddonLoaded(dep) then
                groupAddon[g.id] = dep
                break
            end
        end
    end

    -- Validate override keys match known addon groups
    if self.versionOverrides then
        for key in pairs(self.versionOverrides) do
            if not groupAddon[key] then
                local found = false
                for _, g in ipairs(self.addonGroups) do
                    if g.id == key then found = true; break end
                end
                if not found then
                    self:Print("|cffffff00Warning: versionOverrides key '" .. key .. "' has no matching addon group|r")
                end
            end
        end
    end

    -- Check each patch with a targetVersion
    for _, pi in ipairs(self.patchInfo) do
        if pi.targetVersion then
            local dep = groupAddon[pi.group]
            if dep then
                local installed = GetInstalledVersion(dep)
                -- Use centralized override if available, fall back to per-patch targetVersion
                local expectedVersion = (self.versionOverrides and self.versionOverrides[pi.group]) or pi.targetVersion
                if installed and installed ~= expectedVersion then
                    if not self.versionResults[pi.group] then
                        self.versionResults[pi.group] = {
                            addonName = dep,
                            expected = expectedVersion,
                            installed = installed,
                            patches = {},
                        }
                    end
                    local r = self.versionResults[pi.group]
                    r.patches[#r.patches + 1] = pi
                    self.outdatedPatches[#self.outdatedPatches + 1] = pi
                end
            end
        end
    end
end

function ns:ReportOutdatedPatches()
    if #self.outdatedPatches == 0 then
        self:Print("All patches match installed addon versions.")
        return
    end

    self:Print("|cffffff00Version mismatches:|r")
    for groupId, data in pairs(self.versionResults) do
        self:Print("  |cffffffff" .. groupId .. "|r  |cff808080"
            .. data.expected .. "|r -> |cff33ccff" .. data.installed .. "|r"
            .. "  |cffaaaaaa(" .. #data.patches .. " patches)|r")
    end
end

-- Count outdated groups, excluding dismissed ones
function ns:CountUndismissedOutdated()
    local db = self:GetDB()
    local dismissed = db and db.dismissedOutdated or {}
    local count = 0
    for groupId, data in pairs(self.versionResults) do
        local key = groupId .. "_" .. data.installed
        if not dismissed[key] then
            count = count + 1
        end
    end
    return count
end

function ns:DismissOutdatedForGroup(groupId)
    local db = self:GetDB()
    if not db or not db.dismissedOutdated then return end
    local data = self.versionResults[groupId]
    if data then
        db.dismissedOutdated[groupId .. "_" .. data.installed] = true
    end
end

function ns:IsOutdatedDismissed(groupId)
    local db = self:GetDB()
    if not db or not db.dismissedOutdated then return false end
    local data = self.versionResults[groupId]
    if not data then return false end
    return db.dismissedOutdated[groupId .. "_" .. data.installed] or false
end

---------------------------------------------------------------------------
-- PatchWerk self-update via addon messaging
---------------------------------------------------------------------------
local broadcastSent = {}  -- track which channels we have broadcast to

local function BroadcastVersion(channel)
    if not channel or not SendAddonMsg then return end
    if broadcastSent[channel] then return end
    if channel == "GUILD" and not IsInGuild() then return end
    if channel == "PARTY" and not IsInGroup() then return end
    if channel == "RAID" and not IsInRaid() then return end

    local ok = pcall(SendAddonMsg, ADDON_MSG_PREFIX,
        VERSION_MSG_TAG .. ns.VERSION, channel)
    if ok then broadcastSent[channel] = true end
end

local function OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= ADDON_MSG_PREFIX then return end

    local myName = UnitName("player")
    if sender == myName or (sender:find(myName, 1, true) == 1 and sender:sub(#myName + 1, #myName + 1) == "-") then return end

    local remoteVersion = message:match("^V:(.+)$")
    if not remoteVersion then return end

    local db = ns:GetDB()
    if not db then return end

    -- Track highest seen version
    local remoteSV = ParseSemVer(remoteVersion)
    local lastSV = ParseSemVer(db.lastSeenPatchWerkVersion)
    if remoteSV and (not lastSV or remoteSV > lastSV) then
        db.lastSeenPatchWerkVersion = remoteVersion
    end

    -- One-time notification if newer
    if remoteSV and remoteSV > (ParseSemVer(ns.VERSION) or 0) then
        if ns:GetOption("showUpdateNotification")
            and db.updateNotificationShown ~= remoteVersion then
            db.updateNotificationShown = remoteVersion
            ns:Print("|cffffff00A newer version (|cff33e633" .. remoteVersion
                .. "|cffffff00) is available! You have |cffff6666"
                .. ns.VERSION .. "|cffffff00. Get it at: |cff66bbff"
                .. "https://github.com/Eventyret/PatchWerk/releases" .. "|r")
        end
    end
end

---------------------------------------------------------------------------
-- Event handler
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        pcall(RegisterPrefix, ADDON_MSG_PREFIX)
        self:RegisterEvent("CHAT_MSG_ADDON")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")

        ns:ScanOutdatedPatches()

        -- Only show outdated warnings on login for dev builds (running from source).
        -- Released builds have a real version; normal users don't need this noise.
        if ns.VERSION == "dev" and ns:GetOption("showOutdatedWarnings") and #ns.outdatedPatches > 0 then
            C_Timer.After(3, function()
                local count = ns:CountUndismissedOutdated()
                if count > 0 then
                    ns:Print("|cffffff00" .. count .. " addon" .. (count > 1 and "s" or "")
                        .. " updated since patches were written.|r /pw outdated for details.")
                end
            end)
        end

        if ns:GetOption("showUpdateNotification") then
            C_Timer.After(5, function() BroadcastVersion("GUILD") end)
        end

    elseif event == "CHAT_MSG_ADDON" then
        OnAddonMessage(...)

    elseif event == "GROUP_ROSTER_UPDATE" then
        if IsInRaid() then
            C_Timer.After(2, function() BroadcastVersion("RAID") end)
        elseif IsInGroup() then
            C_Timer.After(2, function() BroadcastVersion("PARTY") end)
        end
    end
end)
