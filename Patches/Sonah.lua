------------------------------------------------------------------------
-- PatchWerk - Visibility control patch for Sonah (Rotation Helper)
--
-- Sonah (v1.9.4) is a rotation helper for TBC Classic Anniversary.
-- It always shows its UI whenever the player is in combat (or out of
-- combat if configured). There is no built-in option to restrict
-- visibility to specific zone types like dungeons or raids.
--
-- Patches:
--   1. Sonah_visibilityMode - Zone-based visibility control
------------------------------------------------------------------------

local _, ns = ...

local IsInInstance = IsInInstance
local UnitAffectingCombat = UnitAffectingCombat
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc

------------------------------------------------------------------------
-- Patch metadata
------------------------------------------------------------------------

ns:RegisterPatch("Sonah", {
    key = "Sonah_visibilityMode",
    label = "Zone Visibility Control",
    help = "Choose where Sonah appears: everywhere, only in dungeons, only in raids, or only in instances.",
    detail = "By default Sonah shows its rotation helper everywhere you go. This patch lets you restrict it to specific zone types -- for example, only in dungeons and raids so it stays out of your way while questing or doing world content.",
    impact = "FPS", impactLevel = "Low", category = "tweaks",
    estimate = "Hides UI outside chosen zones",
})

ns:RegisterDefault("Sonah_visibilityMode", "everywhere")

------------------------------------------------------------------------
-- Visibility mode definitions
------------------------------------------------------------------------

local VISIBILITY_MODES = {
    { value = "everywhere",      label = "Everywhere (default)" },
    { value = "dungeons_raids",  label = "Dungeons & Raids" },
    { value = "raids",           label = "Raids Only" },
    { value = "dungeons",        label = "Dungeons Only" },
    { value = "instances",       label = "All Instances (incl. BGs & Arena)" },
}

local function ShouldShowInZone(mode)
    local inInstance, instanceType = IsInInstance()
    if mode == "everywhere" then
        return true
    elseif mode == "dungeons_raids" then
        return inInstance and (instanceType == "party" or instanceType == "raid")
    elseif mode == "raids" then
        return inInstance and instanceType == "raid"
    elseif mode == "dungeons" then
        return inInstance and instanceType == "party"
    elseif mode == "instances" then
        return inInstance
    end
    return true
end

------------------------------------------------------------------------
-- 1. Zone Visibility Control
------------------------------------------------------------------------
ns.patches["Sonah_visibilityMode"] = function()
    if not ns:IsAddonLoaded("Sonah") then return end

    local Sonah = _G.Sonah
    if not Sonah or not Sonah.UI then return end

    local UI = Sonah.UI
    local mainFrame = _G.SonahMainFrame

    -- Helper to get the current mode from PatchWerk settings
    local function GetMode()
        return ns:GetOption("Sonah_visibilityMode") or "everywhere"
    end

    -- Helper to check zone + apply visibility to the main frame
    local function UpdateZoneVisibility()
        local frame = mainFrame or _G.SonahMainFrame
        if not frame then return end
        if not SonahDB or SonahDB.enabled == false then return end

        local mode = GetMode()
        if mode == "everywhere" then return end

        if not ShouldShowInZone(mode) then
            frame:Hide()
        end
    end

    -- Hook UpdateCombatVisibility to enforce zone restriction after Sonah
    -- decides to show the frame
    if UI.UpdateCombatVisibility then
        hooksecurefunc(UI, "UpdateCombatVisibility", function()
            UpdateZoneVisibility()
        end)
    end

    -- Hook the combat frame events: when Sonah shows the frame on
    -- PLAYER_REGEN_DISABLED, re-hide it if we're in the wrong zone
    local zoneFrame = CreateFrame("Frame")
    zoneFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    zoneFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    zoneFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    zoneFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    zoneFrame:SetScript("OnEvent", function(self, event)
        -- Small delay to let Sonah process the event first
        C_Timer.After(0.1, function()
            local frame = mainFrame or _G.SonahMainFrame
            if not frame then return end
            if not SonahDB or SonahDB.enabled == false then return end

            local mode = GetMode()
            if mode == "everywhere" then return end

            if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
                -- Zoning: show or hide based on new zone
                if ShouldShowInZone(mode) then
                    -- Let Sonah's own combat visibility logic decide
                    if UI.UpdateCombatVisibility then
                        UI:UpdateCombatVisibility()
                    end
                else
                    frame:Hide()
                end
            else
                -- Combat events: just enforce the zone restriction
                UpdateZoneVisibility()
            end
        end)
    end)

    -- Also hook UpdateDisplay to prevent updates when hidden by zone filter
    if UI.UpdateDisplay then
        local origUpdateDisplay = UI.UpdateDisplay
        UI.UpdateDisplay = function(selfUI, ...)
            local mode = GetMode()
            if mode ~= "everywhere" and not ShouldShowInZone(mode) then
                return
            end
            return origUpdateDisplay(selfUI, ...)
        end
    end
end
