------------------------------------------------------------------------
-- PatchWerk - Miscellaneous tweaks and fixes for ElvUI
--
-- Small quality-of-life improvements and minor performance fixes that
-- don't fit neatly into the other ElvUI patch categories:
--   1. ElvUI_tooltipInspectTTL  - Shows fresher gear information in
--                                 tooltips (30s instead of 2 minutes)
--   2. ElvUI_healPredSizeGuard  - Skips heal prediction bar resizing
--                                 when the health bar size hasn't changed
--   3. ElvUI_auraFilterPool     - Skips redundant buff/debuff filter
--                                 rebuilds when settings are unchanged
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_tooltipInspectTTL", label = "Fresher Tooltip Inspect",
    help = "Shows fresher gear information in tooltips by expiring stored results sooner.",
    detail = "ElvUI's tooltip inspect stores gear results for 2 full minutes. If someone changes a piece of gear, you see stale item level data until the timer expires. The original code also retries without a limit, which can cause a chain of repeated lookups that never stops. This fix shortens the stored duration to 30 seconds for more accurate data and caps retries at 3 to prevent runaway retry chains.",
    impact = "FPS", impactLevel = "Low", category = "Tweaks",
    estimate = "~fresher tooltip data",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_healPredSizeGuard", label = "Heal Prediction Size Guard",
    help = "Skips heal prediction bar resizing when the health bar size hasn't actually changed.",
    detail = "Every time a health bar changes, ElvUI repositions and resizes all 8+ heal prediction overlay bars. In a 40-player raid, this creates hundreds of unnecessary layout updates because most of the time the bar dimensions are the same as they were on the previous pass. This fix compares the current bar dimensions to what was last applied and skips the resize entirely when width and height match.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "~fewer wasted updates in raids",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_auraFilterPool", label = "Aura Filter Rebuild Guard",
    help = "Skips redundant buff/debuff filter rebuilds when settings are unchanged.",
    detail = "Every time ElvUI reconfigures aura icons on unit frames, it writes 17 properties to a filter table per aura button. For 40 raid frames with up to 40 aura slots each, that can mean thousands of property writes during a profile switch or settings change. This fix checks whether the settings reference is the same one that was already applied, and skips the full rebuild when nothing has changed.",
    impact = "Memory", impactLevel = "Low", category = "Performance",
    estimate = "~faster profile switching",
})

local pairs          = pairs
local wipe           = wipe
local CreateFrame    = CreateFrame
local GetTime        = GetTime
local UnitGUID       = UnitGUID
local math           = math
local hooksecurefunc = hooksecurefunc

------------------------------------------------------------------------
-- 1. ElvUI_tooltipInspectTTL
--
-- Tooltip.lua:415 — The tooltip inspect lookup stores results for 120
-- seconds.  That's too long — if someone changes gear, you see stale
-- item level data for 2 minutes.  The retry logic also has no maximum
-- count, which can create a chain of delayed retries that never stops.
--
-- Fix: Reduce the stored duration to 30 seconds for fresher data.  Add
-- a maximum retry limit of 3 to prevent runaway retry chains.
------------------------------------------------------------------------
ns.patches["ElvUI_tooltipInspectTTL"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local TT = E:GetModule("Tooltip", true)
    if not TT then return end

    if not TT.AddInspectInfo then return end

    local origAddInspect = TT.AddInspectInfo

    TT.AddInspectInfo = function(self, tt, unit, numTries, ...)
        -- Cap retries at 3 to prevent runaway retry chains
        numTries = numTries or 0
        if numTries > 3 then return end

        -- Shorten the inspect result lifetime
        -- Original uses 120 second TTL, we reduce to 30
        local unitGUID = unit and UnitGUID(unit)
        if unitGUID then
            local inspectCache = TT.inspectGUIDCache or TT.InspectGUIDCache
            if inspectCache then
                local entry = inspectCache[unitGUID]
                if entry and entry.time then
                    -- Check with shorter TTL (30s instead of 120s)
                    if GetTime() - entry.time > 30 then
                        entry.time = nil
                        entry.itemLevel = nil
                    end
                end
            end
        end

        return origAddInspect(self, tt, unit, numTries, ...)
    end
end

------------------------------------------------------------------------
-- 2. ElvUI_healPredSizeGuard
--
-- HealPrediction.lua:57-88 — SetSize_HealComm calls 8+ SetSize()
-- operations every time the health bar changes.  Even when the bar
-- dimensions haven't changed at all, it repositions and resizes all
-- prediction bars.  In a raid with 40 frames, this creates hundreds
-- of unnecessary layout updates.
--
-- Fix: Compare the current bar dimensions to what was last applied.
-- If width and height are the same, skip the resize entirely.
------------------------------------------------------------------------
ns.patches["ElvUI_healPredSizeGuard"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local UF = E:GetModule("UnitFrames", true)
    if not UF then return end

    if not UF.SetSize_HealComm then return end

    local floor = math.floor
    local origSetSize = UF.SetSize_HealComm

    UF.SetSize_HealComm = function(self, frame)
        if not frame or not frame.Health or not frame.HealthPrediction then
            return origSetSize(self, frame)
        end

        local health = frame.Health
        local pred = frame.HealthPrediction
        local width, height = health:GetSize()

        -- Round to avoid floating point comparison issues
        width = width and floor(width + 0.5) or 0
        height = height and floor(height + 0.5) or 0

        -- Skip if dimensions haven't changed
        if pred._pw_lastWidth == width and pred._pw_lastHeight == height then
            return
        end

        pred._pw_lastWidth = width
        pred._pw_lastHeight = height

        return origSetSize(self, frame)
    end
end

------------------------------------------------------------------------
-- 3. ElvUI_auraFilterPool
--
-- Auras.lua:262-307 — Every time ElvUI reconfigures aura icons
-- (buffs/debuffs on unit frames), it writes 17 properties to a filter
-- table per aura button.  For 40 raid frames with up to 40 aura slots
-- each, that's 27,200 property writes during a profile switch or
-- settings change.
--
-- Fix: Only run the full filter update when the settings reference has
-- actually changed.  If the button already had its filters set from
-- the same configuration object, the rebuild is skipped entirely.
------------------------------------------------------------------------
ns.patches["ElvUI_auraFilterPool"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local UF = E:GetModule("UnitFrames", true)
    if not UF then return end

    if not UF.UpdateFilters then return end

    local origUpdateFilters = UF.UpdateFilters

    UF.UpdateFilters = function(self, button, ...)
        -- Pre-check: if the button already has filters and the db hasn't changed,
        -- we can skip the update
        if button and button.auraFilters and button.db then
            local filters = button.auraFilters
            local db = button.db
            -- Quick fingerprint: if the db reference is the same object, filters
            -- were already set from this config
            if filters._pw_dbRef == db then
                return
            end
        end

        local result = origUpdateFilters(self, button, ...)

        -- Mark that we've updated from this db reference
        if button and button.auraFilters and button.db then
            button.auraFilters._pw_dbRef = button.db
        end

        return result
    end
end
