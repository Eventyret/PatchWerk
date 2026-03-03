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
-- Fix: LibElvUIPlugin RegisterPlugin crash on TBC Classic Anniversary
--
-- LibElvUIPlugin's RegisterPlugin (line 146) accesses
-- E.Options.args.plugins before GetPluginOptions() has created it.
-- On TBC Classic Anniversary, a timing issue can cause this access
-- to hit a nil table and crash:
--
--   E.Options.args.plugins.args.plugins.name = lib:GeneratePluginList()
--
-- The fix wraps the original call in pcall.  If it crashes, we still
-- fire the plugin's setup callback so addons like ToxiUI can register
-- their settings panel.
------------------------------------------------------------------------

local hooked = false

local fixFrame = CreateFrame("Frame")
fixFrame:RegisterEvent("ADDON_LOADED")
fixFrame:RegisterEvent("PLAYER_LOGIN")
fixFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterAllEvents()
        return
    end

    -- Try to hook on every ADDON_LOADED until we find LibElvUIPlugin
    if hooked then
        self:UnregisterAllEvents()
        return
    end

    if not LibStub then return end
    local ok, lib = pcall(LibStub, "LibElvUIPlugin-1.0")
    if not ok or not lib or not lib.RegisterPlugin then return end

    -- Found it — hook and stop listening
    hooked = true
    self:UnregisterAllEvents()

    local origRegister = lib.RegisterPlugin

    lib.RegisterPlugin = function(self, name, callback, isLib, version)
        local success, err = pcall(origRegister, self, name, callback, isLib, version)
        if not success and callback then
            -- Plugin was stored in lib.plugins before the crash line
            -- but its setup function never fired.  Call it now so the
            -- plugin can add its options to ElvUI's config panel.
            local E = _G.ElvUI and _G.ElvUI[1]
            if E and E.CallLoadFunc then
                pcall(E.CallLoadFunc, E, callback)
            end
        end
    end
end)
