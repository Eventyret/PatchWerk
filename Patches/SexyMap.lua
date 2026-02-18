------------------------------------------------------------------------
-- PatchWerk - Compatibility patches for SexyMap (Minimap)
--
-- SexyMap uses mostly local closures that are not externally hookable.
-- This patch addresses the one reachable compatibility issue:
--   1. SexyMap_slashCmdFix  - Fix /sexymap and /minimap slash commands
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns.patchInfo[#ns.patchInfo+1] = {
    key = "SexyMap_slashCmdFix", group = "SexyMap", label = "Slash Command Fix",
    help = "Fixes the /sexymap and /minimap commands so they open the settings panel.",
    detail = "SexyMap uses Settings.OpenToCategory to open its config panel, but this API may not work correctly on TBC Classic Anniversary. This wraps the slash command with a fallback to the classic InterfaceOptionsFrame_OpenToCategory method.",
    impact = "Compatibility", impactLevel = "High", category = "Compatibility",
    estimate = "Makes /sexymap and right-click config work reliably",
}

------------------------------------------------------------------------
-- 1. SexyMap_slashCmdFix
--
-- SexyMap_Classic.lua sets up SlashCmdList.SexyMap in PLAYER_LOGIN to
-- call Settings.OpenToCategory(categoryID).  This API does not exist
-- or does not work correctly on TBC Classic Anniversary.
--
-- Fix: After SexyMap's PLAYER_LOGIN handler has run, wrap the slash
-- command to try the original first, then fall back to the classic
-- InterfaceOptionsFrame_OpenToCategory("SexyMap") if it errors.
-- This also fixes right-click-to-config since that calls the same
-- slash handler.
------------------------------------------------------------------------
ns.patches["SexyMap_slashCmdFix"] = function()
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("PLAYER_LOGIN")
    loader:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()

        -- Defer one frame to ensure SexyMap's PLAYER_LOGIN has run
        C_Timer.After(0, function()
            if not SlashCmdList.SexyMap then return end

            local original = SlashCmdList.SexyMap
            SlashCmdList.SexyMap = function()
                local ok = pcall(original)
                if not ok then
                    -- Fallback for TBC Classic where Settings.OpenToCategory
                    -- may not exist or may not work with AceConfigDialog IDs
                    if InterfaceOptionsFrame_OpenToCategory then
                        InterfaceOptionsFrame_OpenToCategory("SexyMap")
                        InterfaceOptionsFrame_OpenToCategory("SexyMap")
                    end
                end
            end
        end)
    end)
end
