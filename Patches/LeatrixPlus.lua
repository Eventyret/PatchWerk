------------------------------------------------------------------------
-- PatchWerk - Performance patch for Leatrix Plus
--
-- Leatrix Plus creates configuration panels (TaxiPanel for the flight
-- map and SideMinimap for minimap settings) that install OnUpdate
-- handlers to poll UnitAffectingCombat("player") every single frame.
-- Their sole purpose is to hide the panel when the player enters
-- combat.  While WoW only fires OnUpdate for visible frames, the
-- panels stay open for as long as the user is configuring settings,
-- and every frame during that time runs a combat API call for no
-- benefit -- combat status only changes once (on the transition).
--
-- This patch replaces both per-frame polling handlers with a single
-- PLAYER_REGEN_DISABLED event listener that hides any open Leatrix
-- Plus configuration panel the instant combat begins.  This is both
-- more efficient (zero per-frame cost) and more responsive (fires on
-- the exact frame combat starts rather than on the next OnUpdate tick).
--
--   1. LeatrixPlus_taxiOnUpdateThrottle - Replace combat-check
--      OnUpdate polling with event-driven hide
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("LeatrixPlus", {
    key = "LeatrixPlus_taxiOnUpdateThrottle",
    label = "Smarter Combat-Hide",
    help = "Closes config panels when combat starts without checking every single frame.",
    detail = "Leatrix Plus checks whether you are in combat every single frame while its Flight Map or Minimap settings panels are open, just to hide them when a fight starts. This patch replaces that constant checking with a single listener that fires the instant combat begins -- same result, no wasted work.",
    impact = "FPS",
    impactLevel = "Low",
    category = "Performance",
    estimate = "Small FPS boost while Leatrix Plus config panels are open",
})

------------------------------------------------------------------------
-- 1. LeatrixPlus_taxiOnUpdateThrottle
--
-- Leatrix Plus creates configuration panels via LeaPlusLC:CreatePanel()
-- which stores them in the global LeaConfigList table.  Two of these
-- panels -- TaxiPanel (for "Enhance flight map") and SideMinimap (for
-- "Enhance minimap") -- set an OnUpdate handler that polls
-- UnitAffectingCombat("player") every frame to hide the panel when
-- combat starts:
--
--   TaxiPanel:SetScript("OnUpdate", function()
--       if UnitAffectingCombat("player") then
--           TaxiPanel:Hide()
--       end
--   end)
--
-- and identically for SideMinimap.
--
-- Fix: After Leatrix Plus initializes (deferred one frame via
-- C_Timer.After(0) to avoid a PLAYER_LOGIN race), we find these
-- panels via their global references, remove the OnUpdate scripts,
-- and register a single event frame for PLAYER_REGEN_DISABLED that
-- iterates the LeaConfigList table and hides any visible panel.
-- This gives the same behavior with zero per-frame overhead.
--
-- Timing: Both PatchWerk and Leatrix Plus initialize at PLAYER_LOGIN.
-- Leatrix Plus creates panels inside LeaPlusLC:Player() which is
-- called from its own PLAYER_LOGIN handler.  Since handler order
-- between different frames is non-deterministic, we defer our patch
-- by one frame with C_Timer.After(0) to guarantee all PLAYER_LOGIN
-- handlers have completed and the panels exist.
------------------------------------------------------------------------
ns.patches["LeatrixPlus_taxiOnUpdateThrottle"] = function()
    if not ns:IsAddonLoaded("Leatrix_Plus") then return end

    -- Defer by one frame so Leatrix Plus has finished its PLAYER_LOGIN
    -- initialization and all panels have been created.
    C_Timer.After(0, function()
        -- Panel global names set by LeaPlusLC:CreatePanel(title, globref):
        --   _G["LeaPlusGlobalPanel_TaxiPanel"]     -- "Enhance flight map"
        --   _G["LeaPlusGlobalPanel_SideMinimap"]    -- "Enhance minimap"
        -- These only exist if the corresponding feature is enabled.
        local panelNames = {
            "LeaPlusGlobalPanel_TaxiPanel",
            "LeaPlusGlobalPanel_SideMinimap",
        }

        -- Track which panels we successfully stripped the OnUpdate from.
        -- We only install the event listener if we actually found panels.
        local patchedPanels = {}

        for _, globalName in ipairs(panelNames) do
            local panel = _G[globalName]
            if panel then
                -- Verify it currently has an OnUpdate before removing it.
                -- This avoids clobbering a script that another addon or a
                -- future Leatrix Plus version may have changed.
                local existingScript = panel:GetScript("OnUpdate")
                if existingScript then
                    panel:SetScript("OnUpdate", nil)
                    patchedPanels[#patchedPanels + 1] = panel
                end
            end
        end

        -- Nothing to patch -- panels not found (features might be disabled)
        if #patchedPanels == 0 then return end

        -- Grab the full config panel list if available.  LeaConfigList is
        -- a global table populated by CreatePanel() -- if we have it, we
        -- can hide ALL open config panels on combat start, not just the
        -- two we specifically targeted.  This matches the original intent.
        local configList = rawget(_G, "LeaConfigList")

        -- Create a lightweight event frame to replace the per-frame polling.
        -- PLAYER_REGEN_DISABLED fires once at the exact moment combat starts.
        local combatHider = CreateFrame("Frame")
        combatHider:RegisterEvent("PLAYER_REGEN_DISABLED")
        combatHider:SetScript("OnEvent", function()
            -- Hide all Leatrix Plus config panels when combat starts
            if configList then
                for i = 1, #configList do
                    local panel = configList[i]
                    if panel and panel:IsShown() then
                        panel:Hide()
                    end
                end
            else
                -- Fallback: just hide the panels we specifically patched
                for i = 1, #patchedPanels do
                    if patchedPanels[i]:IsShown() then
                        patchedPanels[i]:Hide()
                    end
                end
            end
        end)
    end)
end
