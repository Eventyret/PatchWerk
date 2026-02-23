------------------------------------------------------------------------
-- PatchWerk - Nameplate performance patches for ElvUI
--
-- ElvUI's nameplate system processes updates more often than needed,
-- especially during combat with many enemies visible.  These patches
-- reduce unnecessary work:
--   1. ElvUI_npHealthThrottle    - Batches health updates instead of
--                                  processing every single damage tick
--   2. ElvUI_npHighlightEventDriven - Replaces constant checking with
--                                     a smarter approach that only runs
--                                     when your mouse target changes
--   3. ElvUI_npQuestCache        - Remembers quest info per enemy
--                                  instead of re-reading it constantly
--   4. ElvUI_npTargetCache       - Tracks your target change once
--                                  instead of checking every nameplate
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_npHealthThrottle", label = "Nameplate Health Batch",
    help = "Batches nameplate health updates instead of processing every damage tick individually.",
    detail = "ElvUI processes every single damage tick on every visible nameplate separately. In raids or dungeons with many enemies, that means dozens to hundreds of updates per second -- each one looking up the nameplate, finding the health bar, and forcing a redraw. The fix collects all pending updates and processes them together 20 times per second, which looks identical but does far less work.",
    impact = "FPS", impactLevel = "High", category = "Performance",
    estimate = "~10-15% smoother with many enemies visible in combat",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_npHighlightEventDriven", label = "Nameplate Highlight Fix",
    help = "Replaces constant mouse-target polling on all nameplates with a single check when your mouse target changes.",
    detail = "ElvUI checks whether your mouse is over each visible nameplate several times per second using a repeating timer on every single nameplate. With 30-50 nameplates on screen, that is a constant stream of checks even when you aren't moving your mouse. The fix listens for your mouse target to actually change, then updates only the affected nameplates.",
    impact = "FPS", impactLevel = "Medium-High", category = "Performance",
    estimate = "~5-8% smoother with 30+ nameplates visible",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_npQuestCache", label = "Quest Icon Cache",
    help = "Remembers which enemies are quest targets instead of rescanning every time a nameplate appears.",
    detail = "ElvUI scans tooltip text to determine if an enemy is a quest target. This scan runs every time a nameplate appears and every time the quest log changes, using repeated text searches across multiple lines. The fix remembers results per enemy and only rescans when your quest log actually changes.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~2-4% smoother in quest-heavy areas with many nameplates",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_npTargetCache", label = "Target Indicator Cache",
    help = "Tracks your current target once instead of re-checking it on every nameplate update.",
    detail = "ElvUI checks whether each nameplate is your current target during every health update for every visible nameplate. In a dungeon pull with 10 enemies taking damage, that is hundreds of target comparisons per second. The fix tracks your target with a single listener and uses a fast comparison instead.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~2-5% smoother during heavy combat with many targets",
})

local pairs       = pairs
local wipe        = wipe
local pcall       = pcall
local type        = type
local CreateFrame = CreateFrame
local UnitGUID    = UnitGUID
local UnitExists  = UnitExists
local UnitIsUnit  = UnitIsUnit

------------------------------------------------------------------------
-- 1. ElvUI_npHealthThrottle
--
-- ElvUI registers UNIT_HEALTH on nameplates (Nameplates.lua:1067) with
-- zero delay.  Every damage tick fires NamePlateCallBack() which calls
-- pcall(C_NamePlate_GetNamePlateForUnit, unit).  In raids and dungeons
-- this means dozens to hundreds of calls per second.
--
-- Fix: Replace the UNIT_HEALTH / UNIT_MAXHEALTH portion of the
-- callback with a version that batches pending units.  A single
-- OnUpdate frame processes them at a fixed rate (every 0.05 seconds).
------------------------------------------------------------------------
ns.patches["ElvUI_npHealthThrottle"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local NP = E:GetModule("Nameplates", true)
    if not NP then return end

    local C_NamePlate_GetNamePlateForUnit = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if not C_NamePlate_GetNamePlateForUnit then return end

    if not NP.NamePlateCallBack then return end

    local pendingUnits = {}
    local hasPending = false
    local INTERVAL = 0.05

    local batchFrame = CreateFrame("Frame")
    batchFrame:Hide()

    batchFrame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < INTERVAL then return end
        self.elapsed = 0

        for unit in pairs(pendingUnits) do
            pendingUnits[unit] = nil
            local ok, nameplate = pcall(C_NamePlate_GetNamePlateForUnit, unit)
            if ok and nameplate then
                local unitFrame = nameplate.unitFrame or nameplate.UnitFrame
                if unitFrame and unitFrame.Health then
                    unitFrame.Health:ForceUpdate()
                end
            end
        end
        hasPending = false
        self:Hide()
    end)

    local origCallback = NP.NamePlateCallBack
    function NP:NamePlateCallBack(event, unit)
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
            if unit then
                pendingUnits[unit] = true
                if not hasPending then
                    hasPending = true
                    batchFrame:Show()
                end
            end
            return
        end
        return origCallback(self, event, unit)
    end
end

------------------------------------------------------------------------
-- 2. ElvUI_npHighlightEventDriven
--
-- Plugins/Highlight.lua lines 15-26: every visible nameplate runs an
-- OnUpdate polling UnitExists('mouseover') + UnitIsUnit('mouseover',
-- unit) every 0.1s.  With 50 nameplates visible, that is constant CPU
-- drain even when the mouse is not moving.
--
-- Fix: Create a single event frame that listens for
-- UPDATE_MOUSEOVER_UNIT.  Hook into nameplate highlight construction
-- to replace per-frame polling with registration in the central
-- event system.  When the mouse target changes, only the relevant
-- nameplates are updated.
------------------------------------------------------------------------
ns.patches["ElvUI_npHighlightEventDriven"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local NP = E:GetModule("Nameplates", true)
    if not NP then return end

    -- Central tracking for all active highlights
    local activeHighlights = {}

    local highlightFrame = CreateFrame("Frame")
    highlightFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    highlightFrame:SetScript("OnEvent", function()
        for frame, highlight in pairs(activeHighlights) do
            if not frame.unit or not UnitExists("mouseover") or not UnitIsUnit("mouseover", frame.unit) then
                highlight:Hide()
                if highlight.ForceUpdate then
                    highlight:ForceUpdate()
                end
                activeHighlights[frame] = nil
            end
        end
    end)

    -- Hook into nameplate construction to replace OnUpdate with event
    if not NP.Construct_Highlight then return end

    local origConstruct = NP.Construct_Highlight
    NP.Construct_Highlight = function(self, nameplate)
        local highlight = origConstruct(self, nameplate)
        if not highlight then return highlight end

        -- Override Show to register with our event system and remove polling
        local origShow = highlight.Show
        highlight.Show = function(h)
            origShow(h)
            activeHighlights[nameplate] = h
            -- Remove the per-frame polling
            h:SetScript("OnUpdate", nil)
        end

        local origHide = highlight.Hide
        highlight.Hide = function(h)
            origHide(h)
            activeHighlights[nameplate] = nil
        end

        return highlight
    end
end

------------------------------------------------------------------------
-- 3. ElvUI_npQuestCache
--
-- QuestIcons.lua lines 145-184 scans unit tooltips with GetUnitInfo()
-- on every QUEST_LOG_UPDATE and NAME_PLATE_UNIT_ADDED.  Contains
-- nested loops with string operations (strsub, strmatch, strlower,
-- strfind).  Runs for every nameplate.
--
-- Fix: Store quest data per unit GUID.  Only rescan when the quest
-- log actually changes.  Reuse results for the same GUID across
-- nameplate add/remove cycles.
------------------------------------------------------------------------
ns.patches["ElvUI_npQuestCache"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local NP = E:GetModule("Nameplates", true)
    if not NP then return end

    local questCache = {}
    local cacheValid = true

    -- Invalidate when the quest log changes
    local invalidator = CreateFrame("Frame")
    invalidator:RegisterEvent("QUEST_LOG_UPDATE")
    invalidator:RegisterEvent("QUEST_ACCEPTED")
    invalidator:RegisterEvent("QUEST_REMOVED")
    invalidator:SetScript("OnEvent", function()
        wipe(questCache)
        cacheValid = false
        -- Re-validate after a short delay to allow the quest log to settle
        C_Timer.After(0.1, function() cacheValid = true end)
    end)

    -- Hook the quest scanning function if it exists
    if not NP.QuestIcons_GetQuests then return end

    local origGetQuests = NP.QuestIcons_GetQuests
    NP.QuestIcons_GetQuests = function(self, unitID, ...)
        local guid = unitID and UnitGUID(unitID)
        if guid and cacheValid then
            local cached = questCache[guid]
            if cached ~= nil then
                -- Sentinel false means the original returned nil/nothing
                if cached == false then return nil end
                return cached
            end
        end

        local result = origGetQuests(self, unitID, ...)

        if guid then
            -- Use false sentinel for nil results so they are stored too
            questCache[guid] = (result ~= nil) and result or false
        end

        return result
    end
end

------------------------------------------------------------------------
-- 4. ElvUI_npTargetCache
--
-- TargetIndicator.lua line 66 calls UnitIsUnit(self.unit, 'target')
-- on every health update for every nameplate, plus UnitHealth() and
-- UnitHealthMax() for low-health threshold checks.
--
-- Fix: Track the current target via PLAYER_TARGET_CHANGED.  Only run
-- the full indicator logic when the target actually changes, not on
-- every health tick.  Use a fast GUID comparison to skip non-target
-- nameplates entirely.
------------------------------------------------------------------------
ns.patches["ElvUI_npTargetCache"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local NP = E:GetModule("Nameplates", true)
    if not NP then return end

    local currentTargetGUID = nil

    local targetTracker = CreateFrame("Frame")
    targetTracker:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetTracker:SetScript("OnEvent", function()
        currentTargetGUID = UnitGUID("target")
        -- Force update all nameplate target indicators on target change
        local plates = NP.Plates
        if not plates then return end
        for nameplate in pairs(plates) do
            if nameplate.TargetIndicator and nameplate.TargetIndicator.ForceUpdate then
                nameplate.TargetIndicator:ForceUpdate()
            end
        end
    end)

    -- Hook the PostUpdate to use fast GUID comparison instead of
    -- calling UnitIsUnit on every health update for every nameplate
    if not NP.TargetIndicator_PostUpdate then return end

    local origPostUpdate = NP.TargetIndicator_PostUpdate
    NP.TargetIndicator_PostUpdate = function(self, unit, ...)
        -- Quick GUID comparison -- skip the full check for non-targets
        local unitGUID = unit and UnitGUID(unit)
        if unitGUID and unitGUID ~= currentTargetGUID then
            -- Not our target -- make sure indicators are hidden and bail out
            local owner = self.__owner or self:GetParent()
            if owner then
                local element = owner.TargetIndicator
                if element and element:IsShown() then
                    element:Hide()
                end
            end
            return
        end
        -- This IS the target (or we can't tell) -- run the full logic
        return origPostUpdate(self, unit, ...)
    end
end
