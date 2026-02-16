------------------------------------------------------------------------
-- AddonTweaks - Performance patches for VuhDo (Raid Frames)
--
-- VuhDo is a healing-focused raid frame addon with a deferred task
-- system.  On TBC Classic Anniversary several global hot paths can
-- be optimized without touching the critical healing display:
--   1. VuhDo_emptyQueueGuard - Skip task processing when queue empty
--   2. VuhDo_debuffDebounce  - Debounce UNIT_AURA debuff detection
--   3. VuhDo_rangeSkipDead   - Skip range checks for dead/DC units
------------------------------------------------------------------------

local _, ns = ...

local GetTime = GetTime

------------------------------------------------------------------------
-- 1. VuhDo_emptyQueueGuard
--
-- VUHDO_processDeferredTaskQueue is called from VUHDO_OnUpdate Segment
-- 1B every single frame.  When no tasks are queued, it still runs
-- semaphore timeout checks and other overhead for no benefit.  The
-- global is resolved at call-time from the segment callback, so
-- replacing it takes effect immediately.
--
-- Fix: Add an early exit when the priority queue is empty.
------------------------------------------------------------------------
ns.patches["VuhDo_emptyQueueGuard"] = function()
    if not VUHDO_processDeferredTaskQueue then return end
    if not VUHDO_TASK_PRIORITY_QUEUE then return end

    local origProcess = VUHDO_processDeferredTaskQueue
    VUHDO_processDeferredTaskQueue = function()
        if #VUHDO_TASK_PRIORITY_QUEUE == 0 then return end
        return origProcess()
    end
end

------------------------------------------------------------------------
-- 2. VuhDo_debuffDebounce
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

    VUHDO_determineDebuff = function(aUnit, anArg2)
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
    end
end

------------------------------------------------------------------------
-- 3. VuhDo_rangeSkipDead
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
    VUHDO_updateUnitRange = function(aUnit, aMode)
        local info = VUHDO_RAID[aUnit]
        if info then
            if info["dead"] or not info["connected"] then
                return
            end
        end
        return origUpdateRange(aUnit, aMode)
    end
end
