------------------------------------------------------------------------
-- PatchWerk - Performance and compatibility patches for NovaWorldBuffs
--
-- NovaWorldBuffs is a comprehensive world buff timer but has several
-- performance issues and a compatibility problem on TBC Anniversary:
--   1. NovaWorldBuffs_openConfigFix  - Fix Settings.OpenToCategory
--   2. NovaWorldBuffs_markerThrottle - Throttle map marker updates
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Helper: retrieve the NWB addon object via AceAddon.
-- NWB is declared local in every NovaWorldBuffs file (local NWB = addon.a)
-- and is NOT exposed as a global, so we fetch it from the Ace registry.
------------------------------------------------------------------------
local function GetNWB()
    if not LibStub then return nil end
    local AceAddon = LibStub("AceAddon-3.0", true)
    if not AceAddon then return nil end
    return AceAddon:GetAddon("NovaWorldBuffs", true)
end

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns.patchInfo[#ns.patchInfo+1] = {
    key = "NovaWorldBuffs_openConfigFix", group = "NovaWorldBuffs",
    label = "Config Panel Fix",
    help = "Fixes the /nwb config command so it opens the settings panel on TBC.",
    detail = "NovaWorldBuffs uses Settings.OpenToCategory to open its config panel, but this API does not exist on TBC Classic Anniversary. This wraps the openConfig function with a fallback to InterfaceOptionsFrame_OpenToCategory.",
    impact = "Compatibility", impactLevel = "High", category = "Compatibility",
    estimate = "Makes /nwb config work reliably on TBC Classic Anniversary",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "NovaWorldBuffs_markerThrottle", group = "NovaWorldBuffs",
    label = "Map Marker Throttle",
    help = "Throttles unthrottled world map marker updates from every frame to once per second.",
    detail = "World buff markers, DMF markers, and Felwood minimap markers all update their timer text on every rendered frame (60+ fps) with no throttle. Songflower markers are already properly throttled to once per second. This applies the same 1-second throttle to the unthrottled markers.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "FPS improvement when viewing the world map or Felwood minimap",
}

local GetTime = GetTime
local tostring = tostring
local pcall = pcall

------------------------------------------------------------------------
-- 1. NovaWorldBuffs_openConfigFix
--
-- NWB:openConfig (NovaWorldBuffs.lua:4166) calls
-- Settings.OpenToCategory() which does not exist on TBC Classic
-- Anniversary.
--
-- Fix: Wrap NWB:openConfig with a pcall and fall back to the classic
-- InterfaceOptionsFrame_OpenToCategory API on failure.
------------------------------------------------------------------------
ns.patches["NovaWorldBuffs_openConfigFix"] = function()
    local NWB = GetNWB()
    if not NWB then return end
    if not NWB.openConfig then return end

    local origOpenConfig = NWB.openConfig
    NWB.openConfig = function(self)
        local ok = pcall(origOpenConfig, self)
        if not ok then
            if InterfaceOptionsFrame_OpenToCategory then
                InterfaceOptionsFrame_OpenToCategory(self.NWBOptions or "NovaWorldBuffs")
                InterfaceOptionsFrame_OpenToCategory(self.NWBOptions or "NovaWorldBuffs")
            end
        end
    end
end

------------------------------------------------------------------------
-- 2. NovaWorldBuffs_markerThrottle
--
-- World buff markers (NovaWorldBuffs.lua:6847,6947), DMF markers
-- (8023,8067), and Felwood minimap markers (6409,6463,6519) all use
-- OnUpdate handlers that call their respective update functions every
-- rendered frame with no throttle.
--
-- Songflower markers (6185,6269) are already properly throttled with
-- a 1-second GetServerTime() guard.
--
-- Fix: Wrap the three update functions with a 1-second throttle,
-- caching return values so OnUpdate SetText calls still get valid text.
------------------------------------------------------------------------
ns.patches["NovaWorldBuffs_markerThrottle"] = function()
    local NWB = GetNWB()
    if not NWB then return end

    -- Throttle updateWorldbuffMarkers (called with type, layer args)
    if NWB.updateWorldbuffMarkers then
        local orig = NWB.updateWorldbuffMarkers
        local times = {}
        local results = {}

        NWB.updateWorldbuffMarkers = function(self, markerType, layer, ...)
            local key = tostring(markerType) .. ":" .. tostring(layer)
            local now = GetTime()
            if times[key] and now - times[key] < 1 then
                return results[key]
            end
            times[key] = now
            local result = orig(self, markerType, layer, ...)
            results[key] = result
            return result
        end
    end

    -- Throttle updateDmfMarkers (type arg is unused/shadowed internally)
    if NWB.updateDmfMarkers then
        local orig = NWB.updateDmfMarkers
        local lastTime = 0
        local lastResult = nil

        NWB.updateDmfMarkers = function(self, ...)
            local now = GetTime()
            if now - lastTime < 1 then return lastResult end
            lastTime = now
            lastResult = orig(self, ...)
            return lastResult
        end
    end

    -- Throttle updateFelwoodMinimapMarker (called with type arg)
    if NWB.updateFelwoodMinimapMarker then
        local orig = NWB.updateFelwoodMinimapMarker
        local times = {}

        NWB.updateFelwoodMinimapMarker = function(self, markerType, ...)
            local key = tostring(markerType)
            local now = GetTime()
            if times[key] and now - times[key] < 1 then return end
            times[key] = now
            return orig(self, markerType, ...)
        end
    end
end
