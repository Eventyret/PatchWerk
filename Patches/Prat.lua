------------------------------------------------------------------------
-- PatchWerk - Performance patches for Prat-3.0 (Chat Enhancement)
--
-- Prat-3.0 hooks multiple chat frame systems.  On TBC Classic
-- Anniversary several hot paths cause unnecessary per-frame overhead:
--   1. Prat_smfThrottle          - Throttle SMFHax ChatFrame_OnUpdate
--   2. Prat_timestampCache       - Cache timestamp format strings per second
--   3. Prat_bubblesGuard         - Skip bubble scan when none exist
--   4. Prat_playerNamesThrottle  - Throttle UNIT_AURA in PlayerNames
--   5. Prat_guildRosterThrottle  - Rate-limit GuildRoster() calls (network)
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Prat_smfThrottle", group = "Prat", label = "Chat Layout Throttle",
    help = "Reduces chat window updates from 60 to 20 per second. Full speed when you mouse over chat.",
    detail = "With features like Hover Highlighting enabled, Prat recalculates every visible chat line 60 times per second. With 4 chat frames open that's thousands of updates per second. This patch drops it to 20 per second with no visible difference.",
    impact = "FPS", impactLevel = "High", category = "Performance",
    estimate = "~5-10 FPS when chat is visible, huge gain in raids",
    targetVersion = "3.9.87",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Prat_timestampCache", group = "Prat", label = "Timestamp Cache",
    help = "Creates chat timestamps once per second instead of recalculating for every single message.",
    detail = "Prat rebuilds the timestamp text from scratch for every single chat message, even when 10 messages arrive in the same second. During busy raid chat or trade spam, this causes unnecessary frame drops.",
    impact = "Memory", impactLevel = "Low", category = "Performance",
    estimate = "Less memory growth in high-traffic chat channels",
    targetVersion = "3.9.87",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Prat_bubblesGuard", group = "Prat", label = "Bubble Scan Guard",
    help = "Skips chat bubble scanning when no one is talking nearby.",
    detail = "Prat scans for chat bubbles 10 times per second even when you're completely alone or in an instance where no one is talking. The fix skips this entirely when no bubbles exist.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "Reduces baseline overhead while solo or in instances",
    targetVersion = "3.9.87",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Prat_playerNamesThrottle", group = "Prat", label = "Player Info Throttle",
    help = "Throttles player name lookups during buff and debuff changes to 5 times per second.",
    detail = "Prat's player name coloring system reacts to every buff and debuff change in your raid to track player classes. In raids, these changes happen 20-50 times per second but player names never change when someone gains a buff. This patch limits those checks to 5 per second.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "~1-3 FPS in 25-man raids during heavy buff/debuff activity",
    targetVersion = "3.9.87",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Prat_guildRosterThrottle", group = "Prat", label = "Guild Roster Rate Limit",
    help = "Stops Prat from requesting guild roster data in a feedback loop.",
    detail = "Prat requests a full guild roster refresh every time it receives a roster update from the server, creating a feedback loop that generates constant network traffic. In a large active guild with members logging in and out, this produces unnecessary server requests every few seconds. The fix limits roster requests to once per 15 seconds.",
    impact = "Network", impactLevel = "Medium", category = "Performance",
    estimate = "Eliminates guild roster feedback loop network traffic",
    targetVersion = "3.9.87",
}

local GetTime = GetTime
local pairs   = pairs
local floor   = math.floor
local pcall   = pcall
local date    = date

------------------------------------------------------------------------
-- 1. Prat_smfThrottle
--
-- When 2-Column Chat or Hover Highlighting is enabled, SMFHax hooks
-- ChatFrame_OnUpdate and calls SplitFontStrings on every visible line
-- of every chat frame at 60+ fps.  This produces 15-20 C API calls
-- per visible chat line per frame — roughly 96,000 calls/second with
-- 4 chat frames showing 20 lines each.
--
-- Fix: Throttle SplitFontStrings to 20Hz (50ms).  During active hover
-- (overPlayer is set), keep full frame rate for smooth fade effect.
------------------------------------------------------------------------
ns.patches["Prat_smfThrottle"] = function()
    if not Prat then return end
    local addon = Prat.Addon
    if not addon or not addon.GetModule then return end

    local ok, smf = pcall(addon.GetModule, addon, "SMFHax", true)
    if not ok or not smf then return end
    if not smf.ChatFrame_OnUpdate then return end

    local orig = smf.ChatFrame_OnUpdate
    local accum = {}

    smf.ChatFrame_OnUpdate = function(self, this, elapsed, ...)
        local id = this and this:GetID() or 0
        accum[id] = (accum[id] or 0) + (elapsed or 0.016)
        local threshold = self.overPlayer and 0.016 or 0.05

        if accum[id] < threshold then
            -- Skip SplitFontStrings but preserve the hook chain
            if self.hooks and self.hooks["ChatFrame_OnUpdate"] then
                self.hooks["ChatFrame_OnUpdate"](this, elapsed, ...)
            end
            return
        end
        accum[id] = 0
        return orig(self, this, elapsed, ...)
    end
end

------------------------------------------------------------------------
-- 2. Prat_timestampCache
--
-- The Timestamps module rebuilds the format string from settings and
-- calls date() + GetServerTime() on every single chat message, even
-- when multiple messages arrive within the same wall-clock second.
-- This produces 2-3 heap allocations per message.
--
-- Fix: Cache the assembled format string and rendered timestamp.
-- Invalidate when settings change or the second advances.
------------------------------------------------------------------------
ns.patches["Prat_timestampCache"] = function()
    if not Prat then return end
    local addon = Prat.Addon
    if not addon or not addon.GetModule then return end

    local ok, tsModule = pcall(addon.GetModule, addon, "Timestamps", true)
    if not ok or not tsModule then return end
    if not tsModule.InsertTimeStamp then return end

    local origInsert = tsModule.InsertTimeStamp
    local cachedFmt = nil
    local cachedTimeStr = nil
    local cachedSec = -1

    -- Invalidate on settings change
    if tsModule.OnValueChanged then
        local origOVC = tsModule.OnValueChanged
        tsModule.OnValueChanged = function(self, ...)
            cachedFmt = nil
            cachedTimeStr = nil
            cachedSec = -1
            return origOVC(self, ...)
        end
    end

    tsModule.InsertTimeStamp = function(self, text, cf)
        if type(text) ~= "string" then return text end
        local db = self.db and self.db.profile
        if not db then return origInsert(self, text, cf) end

        -- Rebuild format string only when settings change
        local code = db.formatcode or ""
        if db.formatdate and db.formatdate ~= "" then
            code = db.formatdate .. " " .. code
        end
        local fmt = (db.formatpre or "") .. code .. (db.formatpost or "")

        if fmt ~= cachedFmt then
            cachedFmt = fmt
            cachedTimeStr = nil
            cachedSec = -1
        end

        -- Recompute timestamp at most once per wall-clock second
        local nowSec
        if db.localtime then
            nowSec = floor(GetTime())
        else
            nowSec = GetServerTime and GetServerTime() or floor(GetTime())
        end

        if nowSec ~= cachedSec then
            cachedSec = nowSec
            if self.GetTime then
                cachedTimeStr = self:GetTime(cachedFmt)
            else
                cachedTimeStr = date(cachedFmt)
            end
        end

        if not cachedTimeStr then return origInsert(self, text, cf) end

        local ts = cachedTimeStr
        if self.IsTimestampPlain and not self:IsTimestampPlain() and Prat.CLR then
            ts = Prat.CLR:Colorize(db.timestampcolor, cachedTimeStr)
        end

        local space = db.space and " " or ""
        if cf and cf.GetJustifyH and cf:GetJustifyH() == "RIGHT" then
            return text .. space .. ts
        end
        return ts .. space .. text
    end
end

------------------------------------------------------------------------
-- 3. Prat_bubblesGuard
--
-- The Bubbles module runs FormatBubbles via a 0.1s OnUpdate ticker,
-- calling C_ChatBubbles.GetAllChatBubbles() and iterating all bubbles
-- 10 times per second even when no bubbles exist in the world.
--
-- Fix: Guard with a quick empty-table check before the full iteration.
------------------------------------------------------------------------
ns.patches["Prat_bubblesGuard"] = function()
    if not Prat then return end
    if not C_ChatBubbles or not C_ChatBubbles.GetAllChatBubbles then return end

    local addon = Prat.Addon
    if not addon or not addon.GetModule then return end

    local ok, bubblesModule = pcall(addon.GetModule, addon, "Bubbles", true)
    if not ok or not bubblesModule then return end
    if not bubblesModule.FormatBubbles then return end

    local origFormat = bubblesModule.FormatBubbles
    bubblesModule.FormatBubbles = function(self)
        local all = C_ChatBubbles.GetAllChatBubbles(false)
        if not all then return end
        local hasAny = false
        for _ in pairs(all) do hasAny = true; break end
        if not hasAny then return end
        return origFormat(self)
    end
end

------------------------------------------------------------------------
-- 4. Prat_playerNamesThrottle
--
-- The PlayerNames module registers for UNIT_AURA events to track
-- player class/name info.  In raids, UNIT_AURA fires 20-50 times per
-- second as buffs and debuffs apply across all raid members.  Player
-- name/class info doesn't change on aura updates.
--
-- Fix: Throttle the UNIT_AURA handler to 5Hz (200ms).  Player info
-- updates are purely cosmetic (chat name coloring) and don't need
-- instant responsiveness.
------------------------------------------------------------------------
ns.patches["Prat_playerNamesThrottle"] = function()
    if not Prat then return end
    local addon = Prat.Addon
    if not addon or not addon.GetModule then return end

    local ok, pnModule = pcall(addon.GetModule, addon, "PlayerNames", true)
    if not ok or not pnModule then return end
    if not pnModule.UNIT_AURA then return end

    local origAura = pnModule.UNIT_AURA
    local lastAuraUpdate = 0
    local THROTTLE = 0.2

    pnModule.UNIT_AURA = function(self, event, ...)
        local now = GetTime()
        if now - lastAuraUpdate < THROTTLE then return end
        lastAuraUpdate = now
        return origAura(self, event, ...)
    end
end

------------------------------------------------------------------------
-- 5. Prat_guildRosterThrottle
--
-- The PlayerNames module calls C_GuildInfo.GuildRoster() (or the legacy
-- GuildRoster()) inside its GUILD_ROSTER_UPDATE handler.  This creates
-- a feedback loop: the server responds to GuildRoster() with another
-- GUILD_ROSTER_UPDATE event, which calls GuildRoster() again.  The
-- server has its own ~15s internal throttle, but the client still
-- attempts the call each time, generating outbound network traffic.
-- In a large active guild, GUILD_ROSTER_UPDATE fires frequently from
-- members logging in/out, zone changes, etc.
--
-- Fix: Rate-limit the module's GuildRoster reference to once per 15
-- seconds on the client side, breaking the feedback loop.
------------------------------------------------------------------------
ns.patches["Prat_guildRosterThrottle"] = function()
    if not Prat then return end
    local addon = Prat.Addon
    if not addon or not addon.GetModule then return end

    local ok, pnModule = pcall(addon.GetModule, addon, "PlayerNames", true)
    if not ok or not pnModule then return end
    if type(pnModule.GuildRoster) ~= "function" then return end

    local origGuildRoster = pnModule.GuildRoster
    local lastCallTime = 0
    local COOLDOWN = 15

    pnModule.GuildRoster = function(...)
        local now = GetTime()
        if now - lastCallTime < COOLDOWN then
            return
        end
        lastCallTime = now
        return origGuildRoster(...)
    end
end
