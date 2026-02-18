------------------------------------------------------------------------
-- PatchWerk - Performance patches for Cell (Raid Frames)
--
-- Cell is a popular raid frame addon with a custom indicator system.
-- On TBC Classic Anniversary, several functions in the aura processing
-- hot path are called redundantly with identical arguments:
--   1. Cell_debuffOrderMemo        - Memoize GetDebuffOrder last-call result
--   2. Cell_customIndicatorGuard   - Skip UpdateCustomIndicators when no
--                                    custom indicators are configured
--   3. Cell_debuffGlowMemo         - Memoize GetDebuffGlow last-call result
--   4. Cell_inspectQueueThrottle   - Throttle LibGroupInfo inspect queue (network)
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Cell_debuffOrderMemo", group = "Cell", label = "Debuff Priority Cache",
    help = "Remembers the last debuff priority check to skip a duplicate lookup that happens every update.",
    detail = "Cell checks debuff priority twice in a row for the same debuff during updates -- once from the debuff scan and once from the raid debuff check. The fix remembers the last result and skips the duplicate lookup.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~1-2 FPS during debuff-heavy encounters",
    targetVersion = "r274-release",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Cell_customIndicatorGuard", group = "Cell", label = "Custom Indicator Guard",
    help = "Skips custom indicator processing when you don't have any set up.",
    detail = "Cell processes custom indicators for every aura on every raid frame, even if you don't have any custom indicators set up. Most players use default settings, so this is wasted work on every update. The fix detects this and skips the whole system.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~1-2 FPS for users without custom indicators",
    targetVersion = "r274-release",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Cell_debuffGlowMemo", group = "Cell", label = "Debuff Glow Cache",
    help = "Remembers which debuffs should glow on your raid frames to avoid rechecking.",
    detail = "Cell checks which debuffs should glow immediately after checking their priority, using the same information both times. The fix remembers the last result and reuses it, cutting the work in half.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~0.5-1 FPS during raid debuff tracking",
    targetVersion = "r274-release",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Cell_inspectQueueThrottle", group = "Cell", label = "Inspect Queue Throttle",
    help = "Slows down Cell's inspect burst from 4 requests/sec to once per 1.5 seconds.",
    detail = "When you join a group, Cell's group info system fires inspect requests to the server every 0.25 seconds -- that's 4 per second. In a 25-man raid, it sends 24 inspect requests in just 6 seconds, most of which get silently dropped by the server and need retries. The fix spaces them to every 1.5 seconds, which the server handles cleanly.",
    impact = "Network", impactLevel = "Medium", category = "Performance",
    estimate = "83% fewer inspect server requests on group join",
    targetVersion = "r274-release",
}

local pairs = pairs
local GetTime = GetTime

------------------------------------------------------------------------
-- 1. Cell_debuffOrderMemo
--
-- Cell.iFuncs.GetDebuffOrder(spellName, spellId, count) is called for
-- every debuff on every unit frame during aura updates.  The same
-- (spellId, count) pair often hits twice in succession: once from the
-- debuff iteration and once from the raid debuff check.  The function
-- does a table lookup in currentAreaDebuffs and a condition check.
--
-- Fix: Memoize the last call's arguments and result.  If the next call
-- has the same (spellId, count) pair, return the cached result.  This
-- is a last-call cache, not a full cache, so no invalidation needed.
------------------------------------------------------------------------
ns.patches["Cell_debuffOrderMemo"] = function()
    if not Cell or not Cell.iFuncs then return end
    if not Cell.iFuncs.GetDebuffOrder then return end

    local orig = Cell.iFuncs.GetDebuffOrder
    local lastId, lastCount, lastResult

    Cell.iFuncs.GetDebuffOrder = function(spellName, spellId, count)
        if spellId == lastId and count == lastCount then
            return lastResult
        end
        lastId = spellId
        lastCount = count
        lastResult = orig(spellName, spellId, count)
        return lastResult
    end
end

------------------------------------------------------------------------
-- 2. Cell_customIndicatorGuard
--
-- Cell.iFuncs.UpdateCustomIndicators is called for every aura on every
-- unit frame update.  When no custom indicators are configured (the
-- common case for many users), the function iterates an empty table
-- via pairs() on every call.  The overhead is the function call itself
-- plus the pairs() setup and the inner guard checks.
--
-- Fix: On the first actual call (deferred so Cell is fully initialized),
-- check Cell.snippetVars.enabledIndicators for custom indicators.
-- If none exist, replace with a permanent no-op.  If custom indicators
-- are found, restore the original function permanently.  This avoids
-- the timing risk of checking at ADDON_LOADED before Cell populates
-- its indicator tables.
--
-- NOTE: Uses the Classic calling convention (individual args, not
-- auraInfo struct) since this targets TBC Classic Anniversary.
------------------------------------------------------------------------
ns.patches["Cell_customIndicatorGuard"] = function()
    if not Cell or not Cell.iFuncs then return end
    if not Cell.iFuncs.UpdateCustomIndicators then return end

    local orig = Cell.iFuncs.UpdateCustomIndicators

    -- Deferred check: resolve on first call when Cell is fully initialized
    Cell.iFuncs.UpdateCustomIndicators = function(...)
        local hasCustom = false
        if Cell.snippetVars and Cell.snippetVars.enabledIndicators then
            for name in pairs(Cell.snippetVars.enabledIndicators) do
                if type(name) == "string" and name:find("^indicator") then
                    hasCustom = true
                    break
                end
            end
        end
        if hasCustom then
            -- Custom indicators found - restore original permanently
            Cell.iFuncs.UpdateCustomIndicators = orig
            return orig(...)
        end
        -- No custom indicators - install permanent no-op
        Cell.iFuncs.UpdateCustomIndicators = function() end
    end
end

------------------------------------------------------------------------
-- 3. Cell_debuffGlowMemo
--
-- Cell.iFuncs.GetDebuffGlow(spellName, spellId, count) is called
-- immediately after GetDebuffOrder with the same arguments when a raid
-- debuff is found.  It performs the same currentAreaDebuffs lookup plus
-- a glowCondition check.
--
-- Fix: Same last-call memoization pattern as GetDebuffOrder.
------------------------------------------------------------------------
ns.patches["Cell_debuffGlowMemo"] = function()
    if not Cell or not Cell.iFuncs then return end
    if not Cell.iFuncs.GetDebuffGlow then return end

    local orig = Cell.iFuncs.GetDebuffGlow
    local lastId, lastCount, lastGlowType, lastGlowOpts

    Cell.iFuncs.GetDebuffGlow = function(spellName, spellId, count)
        if spellId == lastId and count == lastCount then
            return lastGlowType, lastGlowOpts
        end
        lastId = spellId
        lastCount = count
        lastGlowType, lastGlowOpts = orig(spellName, spellId, count)
        return lastGlowType, lastGlowOpts
    end
end

------------------------------------------------------------------------
-- 4. Cell_inspectQueueThrottle
--
-- Cell bundles LibGroupInfo which polls an inspect queue via an OnUpdate
-- handler every 0.25 seconds.  Each tick sends a NotifyInspect() server
-- request for the next uninspected group member.  In a 25-man raid this
-- means 4 inspect requests per second for the first ~6 seconds after
-- joining, and the server silently drops most of them, causing retries.
--
-- Fix: Wrap the OnUpdate to only fire every 1.5 seconds (matching the
-- library's own RETRY_INTERVAL).  This reduces burst inspect traffic
-- by ~83% and avoids server-side throttle drops.
------------------------------------------------------------------------
ns.patches["Cell_inspectQueueThrottle"] = function()
    local frame = _G["LibGroupInfoFrame"]
    if not frame then return end

    local origOnUpdate = frame:GetScript("OnUpdate")
    if not origOnUpdate then return end

    local accumulator = 0
    local INTERVAL = 1.5

    frame:SetScript("OnUpdate", function(self, elapsed)
        accumulator = accumulator + elapsed
        if accumulator < INTERVAL then return end
        origOnUpdate(self, accumulator)
        accumulator = 0
    end)
end
