------------------------------------------------------------------------
-- PatchWerk - Performance patches for VuhDo (Raid Frames)
--
-- VuhDo is a healing-focused raid frame addon with a deferred task
-- system.  On TBC Classic Anniversary several global hot paths can
-- be optimized without touching the critical healing display:
--   1. VuhDo_debuffDebounce   - Debounce UNIT_AURA debuff detection
--   2. VuhDo_rangeSkipDead    - Skip range checks for dead/DC units
--   3. VuhDo_inspectThrottle  - Throttle NotifyInspect polling (network)
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("VuhDo", {
    key = "VuhDo_debuffDebounce", label = "Debuff Scan Batch",
    help = "During heavy AoE damage, combines debuff checks instead of running 100+ per second.",
    detail = "During heavy AoE damage in raids, VuhDo's debuff checker fires 100+ times per second as aura updates flood in. This creates raid frame stuttering during encounters like Lurker or Vashj. The fix combines checks within 33ms windows.",
    impact = "FPS", impactLevel = "High", category = "Performance",
    estimate = "~2-5 FPS in 25-man raids during AoE encounters",
})
ns:RegisterPatch("VuhDo", {
    key = "VuhDo_rangeSkipDead", label = "Skip Dead Range Checks",
    help = "Skips range checking on dead or disconnected raid members.",
    detail = "VuhDo checks range on every raid member continuously, making multiple checks per person per update. Dead and disconnected players obviously can't change range, but VuhDo checks them anyway. In a 25-man with deaths, that's a lot of wasted work.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "~1-3 FPS during wipe recovery and rez phases",
})
ns:RegisterPatch("VuhDo", {
    key = "VuhDo_inspectThrottle", label = "Inspect Request Throttle",
    help = "Reduces server inspect requests from every 2 seconds to every 5 seconds.",
    detail = "VuhDo sends inspect requests to the server every 2.1 seconds to determine raid members' specs and roles. In a 25-man raid, this means continuous inspect traffic for the entire session as members join, leave, or go out of range. The fix spaces requests to every 5 seconds, cutting server traffic by 60%.",
    impact = "Network", impactLevel = "Medium", category = "Performance",
    estimate = "60% fewer inspect server requests in raids",
})

local GetTime = GetTime

------------------------------------------------------------------------
-- 1. VuhDo_debuffDebounce
--
-- VUHDO_determineDebuff is called on every UNIT_AURA event for every
-- tracked unit.  During AoE encounters this fires 20-100+ times per
-- second, scanning debuff data structures each time.  The global is
-- resolved at call-time in VUHDO_OnEvent.
--
-- Fix: Debounce per unit with a 33ms window.  Cached results are
-- returned for rapid-fire events on the same unit within the window.
------------------------------------------------------------------------
ns.patches["VuhDo_debuffDebounce"] = function()
    if not VUHDO_determineDebuff then return end

    local origDetermineDebuff = VUHDO_determineDebuff
    local lastCallTime = {}
    local cacheResult = {}
    local cacheName = {}

    rawset(_G, "VUHDO_determineDebuff", function(aUnit, anArg2)
        local now = GetTime()
        local last = lastCallTime[aUnit]
        if last and (now - last) < 0.033 then
            return cacheResult[aUnit], cacheName[aUnit]
        end
        lastCallTime[aUnit] = now
        local result, name = origDetermineDebuff(aUnit, anArg2)
        cacheResult[aUnit] = result
        cacheName[aUnit] = name
        return result, name
    end)
end

------------------------------------------------------------------------
-- 2. VuhDo_rangeSkipDead
--
-- VUHDO_updateUnitRange polls 4-5 C API functions per unit to check
-- range status (UnitIsCharmed, UnitCanAttack, UnitInRange,
-- UnitIsVisible).  Dead and disconnected units cannot meaningfully
-- change range.  This affects the non-deferred call path where the
-- global is resolved at call-time.
--
-- Fix: Early exit when the unit is dead or disconnected.
------------------------------------------------------------------------
ns.patches["VuhDo_rangeSkipDead"] = function()
    if not VUHDO_updateUnitRange then return end
    if not VUHDO_RAID then return end

    local origUpdateRange = VUHDO_updateUnitRange
    rawset(_G, "VUHDO_updateUnitRange", function(aUnit, aMode)
        local info = VUHDO_RAID[aUnit]
        if info then
            if info["dead"] or not info["connected"] then
                return
            end
        end
        return origUpdateRange(aUnit, aMode)
    end)
end

------------------------------------------------------------------------
-- 3. VuhDo_inspectThrottle
--
-- VUHDO_tryInspectNext() is called every ~2.1 seconds via a timer in
-- VUHDO_handleSegment2L.  It iterates all raid members and sends
-- NotifyInspect() for the first uninspected unit.  Each NotifyInspect
-- is a server round-trip.  In a 25-man raid with members joining/leaving
-- or going out of range, this sends one inspect request every 2.1 seconds
-- continuously.
--
-- Fix: Throttle to once every 5 seconds.  Role detection still works,
-- just completes the initial scan more slowly (~125s vs ~52s for 25
-- players).  Since most roles are determined via other means, the
-- practical impact is minimal.
------------------------------------------------------------------------
ns.patches["VuhDo_inspectThrottle"] = function()
    if type(VUHDO_tryInspectNext) ~= "function" then return end

    local origTryInspect = VUHDO_tryInspectNext
    local lastInspectTime = 0
    local INSPECT_INTERVAL = 5

    rawset(_G, "VUHDO_tryInspectNext", function(...)
        local now = GetTime()
        if now - lastInspectTime < INSPECT_INTERVAL then
            return
        end
        lastInspectTime = now
        return origTryInspect(...)
    end)
end
