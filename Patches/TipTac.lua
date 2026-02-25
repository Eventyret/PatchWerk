------------------------------------------------------------------------
-- PatchWerk - Performance patches for TipTac (Tooltips)
--
-- TipTac is a popular tooltip enhancement addon that hooks into every
-- GameTooltip frame.  On TBC Classic Anniversary, two hot paths cause
-- unnecessary CPU and network overhead:
--   1. TipTac_unitAppearanceGuard - Skip per-frame OnUpdate work for
--                                   non-unit tooltips
--   2. TipTac_inspectCache        - Extend the 5-second inspect cache
--                                   to reduce server queries
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("TipTac", {
    key = "TipTac_unitAppearanceGuard", label = "Non-Unit Tooltip Guard",
    help = "Stops TipTac from constantly updating when you're hovering items instead of players.",
    detail = "TipTac runs appearance updates constantly for every visible tooltip, including item and spell tooltips where no player or NPC is shown. This wastes resources when you're hovering items in bags or on vendors.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~0.5-1 FPS while hovering items in bags",
})
ns:RegisterPatch("TipTac", {
    key = "TipTac_inspectCache", label = "Extended Inspect Cache",
    help = "Reduces inspect requests from every 5s to every 30s for recently inspected players.",
    detail = "TipTac re-inspects players every 5 seconds when you hover them, sending repeated requests to the server. In crowded cities or raids, this causes inspect delays for everyone. The fix extends the cache to 30 seconds.",
    impact = "Network", impactLevel = "Medium", category = "Performance",
    estimate = "80% fewer inspect requests, less server lag",
})

local pairs    = pairs
local pcall    = pcall
local GetTime  = GetTime
local UnitGUID = UnitGUID

------------------------------------------------------------------------
-- 1. TipTac_unitAppearanceGuard
--
-- TipTac hooks OnUpdate on every GameTooltip and calls
-- tt:UpdateUnitAppearanceToTip(tip) at 60fps for every visible tooltip,
-- including item/spell tooltips where no unit is being shown.  The
-- function checks timestampStartUnitAppearance and returns early if
-- nil, but the function call overhead plus cache lookups still happen
-- every single frame.
--
-- Fix: Wrap UpdateUnitAppearanceToTip with a fast guard that checks
-- whether the tooltip is actually showing a unit via tip:GetUnit()
-- before delegating to the original function.  The "force" parameter
-- bypasses the guard so explicit refreshes still work.
------------------------------------------------------------------------
ns.patches["TipTac_unitAppearanceGuard"] = function()
    if not TipTac then return end

    local tt = TipTac
    if not tt.UpdateUnitAppearanceToTip then return end

    local orig = tt.UpdateUnitAppearanceToTip

    tt.UpdateUnitAppearanceToTip = function(self, tip, force)
        -- Fast exit: only process if the tooltip is actually showing a unit.
        -- When force is true, bypass the guard entirely so explicit refreshes
        -- are never blocked.
        if not force then
            if tip and tip.GetUnit then
                local _, unit = tip:GetUnit()
                if not unit then return end
            end
        end
        return orig(self, tip, force)
    end
end

------------------------------------------------------------------------
-- 2. TipTac_inspectCache
--
-- TipTacTalents uses LibFroznFunctions which has a 5-second inspect
-- cache timeout (LFF_CACHE_TIMEOUT = 5).  Every 5+ seconds after
-- hovering a player, a new NotifyInspect server query is sent.  In
-- crowded areas (cities, raids) this causes constant server queries
-- that contribute to throttling and lag.
--
-- Fix: Hook LibFroznFunctions:InspectUnit to suppress re-inspects
-- within 30 seconds.  When suppressed, the callback is fired directly
-- so TipTac still refreshes the tooltip with existing data.  A
-- hooksecurefunc post-hook on NotifyInspect tracks when inspects
-- actually fire (taint-free, runs after the original).
--
-- NOTE: Previous versions replaced _G.NotifyInspect globally, which
-- caused taint propagation and ADDON_ACTION_FORBIDDEN.  The new
-- approach only hooks addon methods, never Blizzard globals.
------------------------------------------------------------------------
ns.patches["TipTac_inspectCache"] = function()
    if not LibStub then return end
    if not C_Timer or not C_Timer.NewTicker then return end

    -- Only apply when LibFroznFunctions is loaded (TipTacTalents dependency)
    local LFF
    local ok
    ok, LFF = pcall(LibStub.GetLibrary, LibStub, "LibFroznFunctions-1.0")
    if not ok then LFF = nil end
    if not LFF or not LFF.InspectUnit then return end

    local inspectTimes = {}
    local EXTENDED_TIMEOUT = 30 -- seconds (up from library's 5)

    -- Track when NotifyInspect actually fires (post-hook, no taint).
    -- This captures inspects from ALL sources, not just TipTac.
    hooksecurefunc("NotifyInspect", function(unit)
        local guid = unit and UnitGUID(unit)
        if guid then
            inspectTimes[guid] = GetTime()
        end
    end)

    -- Hook InspectUnit to suppress re-inspects within our extended timeout.
    -- When suppressed, we fire the callback directly — WoW keeps the last
    -- inspected player's data in memory, so talent/gear info is still valid.
    local origInspectUnit = LFF.InspectUnit
    LFF.InspectUnit = function(self, unitID, callback, removeCallback, bypassTimeout)
        -- Pass through removal requests and explicit timeout bypasses
        if removeCallback or bypassTimeout then
            return origInspectUnit(self, unitID, callback, removeCallback, bypassTimeout)
        end

        local guid = unitID and UnitGUID(unitID)
        if guid and inspectTimes[guid] then
            local elapsed = GetTime() - inspectTimes[guid]
            if elapsed < EXTENDED_TIMEOUT then
                -- Recent inspect data is still in WoW's memory.
                -- Fire callback so TipTac refreshes tooltip with cached data.
                if callback then
                    pcall(callback)
                end
                return
            end
        end

        return origInspectUnit(self, unitID, callback, removeCallback, bypassTimeout)
    end

    -- Prune old entries periodically to prevent memory leak
    C_Timer.NewTicker(120, function()
        local now = GetTime()
        for guid, t in pairs(inspectTimes) do
            if (now - t) > EXTENDED_TIMEOUT * 2 then
                inspectTimes[guid] = nil
            end
        end
    end)
end
