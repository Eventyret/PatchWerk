-- !PatchWerk/Fixes.lua
-- Runtime fixes for addon compatibility issues that require event-based timing.
-- These patches target library code that loads AFTER !PatchWerk's Shims.lua
-- but BEFORE PatchWerk's own PLAYER_LOGIN patches can run.
--
-- Flow:  !PatchWerk loads → Shims.lua (file scope) + Fixes.lua (event-based)
--        → ElvUI_Libraries loads → ADDON_LOADED fires → we hook LibElvUIPlugin
--        → later, AceAddon enable phase calls the (now-safe) RegisterPlugin

local pcall = pcall
local type = type

------------------------------------------------------------------------
-- Fix: LibElvUIPlugin RegisterPlugin crash on TBC Classic Anniversary
--
-- LibElvUIPlugin's RegisterPlugin (line 146) accesses
-- E.Options.args.plugins before GetPluginOptions() has created it.
-- When ElvUI_Options reports as loaded during plugin registration
-- (a timing issue specific to TBC Classic Anniversary), the code
-- tries to index a nil table:
--
--   E.Options.args.plugins.args.plugins.name = lib:GeneratePluginList()
--
-- The fix has two layers:
--   1. Pre-create a minimal table chain so line 146 doesn't crash.
--   2. After the original call succeeds, call GetPluginOptions() to
--      build the real AceConfig widget structure (the placeholder
--      would never be replaced otherwise, because the ADDON_LOADED
--      listener that normally triggers GetPluginOptions is skipped
--      when IsAddOnLoaded("ElvUI_Options") is already true).
--   3. A pcall wrapper acts as a final safety net.
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
        -- Pre-create the Options table chain that line 146 expects.
        -- GetPluginOptions() will overwrite this with the real
        -- AceConfig structure below (or when ElvUI_Options loads).
        local E = _G.ElvUI and _G.ElvUI[1]
        local didPreCreate = false
        if E and E.Options and type(E.Options.args) == "table" then
            if not E.Options.args.plugins then
                E.Options.args.plugins = { args = { plugins = {} } }
                didPreCreate = true
            elseif type(E.Options.args.plugins.args) ~= "table" then
                E.Options.args.plugins.args = { plugins = {} }
                didPreCreate = true
            elseif not E.Options.args.plugins.args.plugins then
                E.Options.args.plugins.args.plugins = {}
                didPreCreate = true
            end
        end

        local success, err = pcall(origRegister, self, name, callback, isLib, version)

        -- If we used a placeholder, build the real AceConfig structure.
        -- In the crash scenario, IsAddOnLoaded("ElvUI_Options") is true
        -- so the normal ADDON_LOADED → GetPluginOptions path is skipped.
        if didPreCreate and lib.GetPluginOptions then
            pcall(lib.GetPluginOptions, lib)
        end

        if not success and callback then
            -- Plugin was stored in lib.plugins before the crash line
            -- but its setup function never fired.  Call it now so the
            -- plugin can add its options to ElvUI's config panel.
            if E and E.CallLoadFunc then
                pcall(E.CallLoadFunc, E, callback)
            end
        end
    end
end)
