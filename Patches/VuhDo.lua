------------------------------------------------------------------------
-- PatchWerk - Performance patches for VuhDo (Raid Frames)
--
-- VuhDo is a healing-focused raid frame addon with a deferred task
-- system.  On TBC Classic Anniversary several global hot paths can
-- be optimized without touching the critical healing display:
--   1. VuhDo_debuffDebounce  - Debounce UNIT_AURA debuff detection
--   2. VuhDo_rangeSkipDead   - Skip range checks for dead/DC units
------------------------------------------------------------------------

local _, ns = ...

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
