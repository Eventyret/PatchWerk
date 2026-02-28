-- !PatchWerk/Fixes.lua
-- Runtime fixes for addon compatibility issues that require event-based timing.
-- These patches target library code that loads AFTER !PatchWerk's Shims.lua
-- but BEFORE PatchWerk's own PLAYER_LOGIN patches can run.
--
-- Flow:  !PatchWerk loads → Shims.lua (file scope) + Fixes.lua (event-based)
--        → ElvUI_Libraries loads → ADDON_LOADED fires → we hook LibElvUIPlugin
--        → later, AceAddon enable phase calls the (now-safe) RegisterPlugin

local pcall = pcall

------------------------------------------------------------------------
-- Fix: LibElvUIPlugin ≥ v15.07 RegisterPlugin crash
--
-- In ElvUI v15.07+, RegisterPlugin (line 146) accesses
-- E.Options.args.plugins before GetPluginOptions() has created it.
-- When ElvUI_Options is already loaded at registration time (possible
-- in certain addon-loading orders), the code hits a nil table:
--
--   E.Options.args.plugins.args.plugins.name = lib:GeneratePluginList()
--
-- The fix: wrap the original call in a safe wrapper.  If the Options
-- access crashes, we still ensure the plugin's setup function fires
-- so addons like ToxiUI can register their settings panel.
------------------------------------------------------------------------

local fixFrame = CreateFrame("Frame")
fixFrame:RegisterEvent("ADDON_LOADED")
fixFrame:SetScript("OnEvent", function(self, event, addon)
    if addon ~= "ElvUI_Libraries" then return end
    self:UnregisterEvent("ADDON_LOADED")

    -- Locate LibElvUIPlugin via LibStub (loaded by ElvUI_Libraries)
    if not LibStub then return end
    local ok, lib = pcall(LibStub, "LibElvUIPlugin-1.0")
    if not ok or not lib or not lib.RegisterPlugin then return end

    local origRegister = lib.RegisterPlugin

    lib.RegisterPlugin = function(self, name, callback, isLib, version)
        local success, err = pcall(origRegister, self, name, callback, isLib, version)
        if not success and callback then
            -- Plugin was stored in lib.plugins (before the crash line) but
            -- its setup function never fired.  Call it now so the plugin
            -- can add its options to ElvUI's config panel.
            local E = _G.ElvUI and _G.ElvUI[1]
            if E and E.CallLoadFunc then
                pcall(E.CallLoadFunc, E, callback)
            end
        end
    end
end)
