------------------------------------------------------------------------
-- PatchWerk - Performance patches for Attune (Attunement Tracker)
--
-- Attune tracks raid attunement progress but has several performance
-- issues in its hot paths:
--   1. Attune_spairsOptimize     - Fix O(n²) sorted pairs iterator
--   2. Attune_bagUpdateDebounce  - Debounce BAG_UPDATE full scans
--   3. Attune_cleuEarlyExit      - Skip irrelevant combat log events
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("Attune", {
    key = "Attune_spairsOptimize",
    label = "Sorted Pairs Optimize",
    help = "Fixes the O(n²) sorted pairs iterator used throughout Attune's UI.",
    detail = "Attune's spairs() function calls Attune_count() on every iteration to get the table length. Attune_count() itself iterates the entire table each call, making key collection O(n²). This replaces it with the O(1) # length operator.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "Significant improvement when viewing attunement UI with many entries",
})
ns:RegisterPatch("Attune", {
    key = "Attune_bagUpdateDebounce",
    label = "Bag Update Debounce",
    help = "Debounces bag update handling to avoid repeated full item scans.",
    detail = "Attune's BAG_UPDATE handler iterates all attunement steps and calls GetItemCount for every item-type step on every single bag slot change. During looting, vendoring, or crafting, this fires dozens of times per second. This debounces the scan to run at most once per 0.5 seconds.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "Reduces lag spikes when looting or interacting with bags",
})
ns:RegisterPatch("Attune", {
    key = "Attune_cleuEarlyExit",
    label = "Combat Log Early Exit",
    help = "Skips combat log events that Attune cannot use.",
    detail = "Attune only processes PARTY_KILL and UNIT_DIED combat log events but extracts all 16 parameters from every single event before checking. This adds an early check on the subevent type and skips the full handler for irrelevant events like SPELL_DAMAGE, SWING_DAMAGE, etc.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "Small improvement during combat with many enemies",
})

local GetTime = GetTime
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local select = select
local pairs = pairs
local tostring = tostring

------------------------------------------------------------------------
-- 1. Attune_spairsOptimize
--
-- Attune_spairs (Attune.lua:4477) collects keys with:
--   keys[Attune_count(keys)+1] = k
-- where Attune_count (Attune.lua:3689) iterates the entire table to
-- count entries each call, making key collection O(n²).
--
-- Called at 9+ locations throughout the UI rendering path (lines 743,
-- 1273, 1451, 2031, 2104, 3262, 3462, 3955, 4852).
--
-- Fix: Replace the global Attune_spairs with an identical version
-- that uses #keys (O(1)) instead of Attune_count(keys).
------------------------------------------------------------------------
ns.patches["Attune_spairsOptimize"] = function()
    if not Attune_spairs then return end

    Attune_spairs = function(t, order)
        local keys = {}
        for k in pairs(t) do keys[#keys+1] = k end

        if order then
            table.sort(keys, function(a, b) return order(t, a, b) end)
        else
            table.sort(keys)
        end

        local i = 0
        return function()
            i = i + 1
            if keys[i] then
                return keys[i], t[keys[i]]
            end
        end
    end
end

------------------------------------------------------------------------
-- 2. Attune_bagUpdateDebounce
--
-- Attune:BAG_UPDATE (Attune.lua:1154) iterates ALL attunement steps
-- and calls GetItemCount for every item-type step on every bag event.
-- BAG_UPDATE fires for each individual slot change during looting,
-- crafting, or vendoring -- often dozens of times per second.
--
-- Fix: Wrap Attune:BAG_UPDATE with a 0.5s debounce timer so rapid
-- successive bag events consolidate into a single scan.
------------------------------------------------------------------------
ns.patches["Attune_bagUpdateDebounce"] = function()
    if not Attune then return end
    if not Attune.BAG_UPDATE then return end

    local origBagUpdate = Attune.BAG_UPDATE
    local pending = nil

    Attune.BAG_UPDATE = function(self, event, ...)
        -- The addon calls BAG_UPDATE(nil) manually at startup (line 612)
        -- to populate item progress.  Let that through immediately.
        if not event then
            return origBagUpdate(self, event)
        end
        if pending then return end
        pending = C_Timer.After(0.5, function()
            pending = nil
            origBagUpdate(self, event)
        end)
    end
end

------------------------------------------------------------------------
-- 3. Attune_cleuEarlyExit
--
-- Attune:COMBAT_LOG_EVENT_UNFILTERED (Attune.lua:860) extracts all
-- 16 parameters from CombatLogGetCurrentEventInfo() on every CLEU
-- event, then checks if param2 is PARTY_KILL or UNIT_DIED.  The vast
-- majority of CLEU events (SPELL_DAMAGE, SWING_DAMAGE, SPELL_AURA_*,
-- etc.) are irrelevant to Attune.
--
-- Fix: Wrap the handler to check the subevent type first and skip
-- the full handler for irrelevant events.
------------------------------------------------------------------------
ns.patches["Attune_cleuEarlyExit"] = function()
    if not Attune then return end
    if not Attune.COMBAT_LOG_EVENT_UNFILTERED then return end

    local origCLEU = Attune.COMBAT_LOG_EVENT_UNFILTERED

    Attune.COMBAT_LOG_EVENT_UNFILTERED = function(self, event, ...)
        local subevent = select(2, CombatLogGetCurrentEventInfo())
        if subevent ~= "PARTY_KILL" and subevent ~= "UNIT_DIED" then return end
        return origCLEU(self, event, ...)
    end
end
