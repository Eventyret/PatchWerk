------------------------------------------------------------------------
-- PatchWerk - Performance and compatibility patches for NovaWorldBuffs
--
-- NovaWorldBuffs is a comprehensive world buff timer but has several
-- performance issues and compatibility problems on TBC Anniversary:
--   1. NovaWorldBuffs_openConfigFix     - Fix Settings.OpenToCategory
--   2. NovaWorldBuffs_markerThrottle    - Throttle map marker updates
--   3. NovaWorldBuffs_cAddOnsShim       - Polyfill C_AddOns namespace
--   4. NovaWorldBuffs_cSummonInfoShim   - Polyfill C_SummonInfo namespace
--   5. NovaWorldBuffs_pairsByKeysOptimize - Reduce table allocations
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
ns:RegisterPatch("NovaWorldBuffs", {
    key = "NovaWorldBuffs_openConfigFix",
    label = "Config Panel Fix",
    help = "Fixes the /nwb config command so it opens the settings panel on TBC.",
    detail = "NovaWorldBuffs uses Settings.OpenToCategory to open its config panel, but this API does not exist on TBC Classic Anniversary. This wraps the openConfig function with a fallback to InterfaceOptionsFrame_OpenToCategory.",
    impact = "Compatibility", impactLevel = "High", category = "Compatibility",
    estimate = "Makes /nwb config work reliably on TBC Classic Anniversary",
})
ns:RegisterPatch("NovaWorldBuffs", {
    key = "NovaWorldBuffs_markerThrottle",
    label = "Map Marker Throttle",
    help = "Throttles unthrottled world map marker updates from every frame to once per second.",
    detail = "World buff markers, DMF markers, and Felwood markers all update their timer text on every rendered frame (60+ fps) with no throttle. Songflower markers are already properly throttled to once per second. This applies the same 1-second throttle to the unthrottled markers, covering worldmap, minimap, and DMF displays.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "FPS improvement when viewing the world map or Felwood minimap",
})
ns:RegisterPatch("NovaWorldBuffs", {
    key = "NovaWorldBuffs_cAddOnsShim",
    label = "C_AddOns Polyfill",
    help = "Provides the C_AddOns namespace for TBC Classic where it does not exist.",
    detail = "NovaWorldBuffs calls C_AddOns.IsAddOnLoaded directly at two runtime locations (CHAT_MSG_SYSTEM handler and world map marker scaling) without the nil guard used elsewhere. On TBC Classic Anniversary, C_AddOns is nil, causing Lua errors on every system message and world map open. This creates a polyfill mapping to the classic global APIs.",
    impact = "Compatibility", impactLevel = "High", category = "Compatibility",
    estimate = "Eliminates Lua errors on system messages and world map opens",
})
ns:RegisterPatch("NovaWorldBuffs", {
    key = "NovaWorldBuffs_cSummonInfoShim",
    label = "C_SummonInfo Polyfill",
    help = "Provides the C_SummonInfo namespace for TBC Classic where it does not exist.",
    detail = "NovaWorldBuffs uses C_SummonInfo.ConfirmSummon and C_SummonInfo.GetSummonConfirmTimeLeft for auto-accepting summons after Darkmoon Faire buffs. These APIs do not exist in TBC Classic Anniversary. This polyfill maps ConfirmSummon to the classic global and provides a visibility-based fallback for GetSummonConfirmTimeLeft.",
    impact = "Compatibility", impactLevel = "Medium", category = "Compatibility",
    estimate = "Restores auto-summon feature for Vanish/Feign Death users at DMF",
})
ns:RegisterPatch("NovaWorldBuffs", {
    key = "NovaWorldBuffs_pairsByKeysOptimize",
    label = "Sorted Pairs Optimize",
    help = "Reduces table allocations in the sorted pairs iterator used throughout NWB.",
    detail = "NWB:pairsByKeys allocates a new table and closure on every call. It is called from the 1-second ticker, layer frame recalculation, Felwood marker updates, and guild data status checks. This replaces it with a version that reuses a single sort buffer, eliminating repeated allocations.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "Reduces GC pressure from 3-6 table allocations per second on layered servers",
})

local GetTime = GetTime
local tostring = tostring
local pcall = pcall
local pairs = pairs

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
-- World buff markers (6847,6947), DMF markers (8023,8067), Felwood
-- worldmap markers (6353,6463), and Felwood minimap markers (6409)
-- all use OnUpdate handlers that call their respective update functions
-- every rendered frame with no throttle.
--
-- Songflower markers (6185,6269) are already properly throttled.
--
-- Fix: Wrap the four update functions with a 1-second throttle,
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
            if not times[markerType] then times[markerType] = {} end
            local lastTime = times[markerType][layer] or 0
            local now = GetTime()
            if now - lastTime < 1 then
                if not results[markerType] then results[markerType] = {} end
                return results[markerType][layer]
            end
            times[markerType][layer] = now
            local result = orig(self, markerType, layer, ...)
            if not results[markerType] then results[markerType] = {} end
            results[markerType][layer] = result
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

    -- Throttle updateFelwoodWorldmapMarker (called with type arg)
    -- 10 tuber + 4 dragon markers = 14 unthrottled OnUpdate handlers
    if NWB.updateFelwoodWorldmapMarker then
        local orig = NWB.updateFelwoodWorldmapMarker
        local times = {}

        NWB.updateFelwoodWorldmapMarker = function(self, markerType, ...)
            local key = tostring(markerType)
            local now = GetTime()
            if times[key] and now - times[key] < 1 then return end
            times[key] = now
            return orig(self, markerType, ...)
        end
    end
end

------------------------------------------------------------------------
-- 3. NovaWorldBuffs_cAddOnsShim
--
-- NovaWorldBuffs calls C_AddOns.IsAddOnLoaded directly at:
--   line 5047 (CHAT_MSG_SYSTEM handler - fires on every system message)
--   line 7001 (updateWorldbuffMarkersScale - fires on world map open)
-- without the nil guard used elsewhere (line 37).
--
-- On TBC Classic Anniversary, C_AddOns is nil.  The classic globals
-- IsAddOnLoaded and GetAddOnMetadata serve the same purpose.
--
-- Fix: Create the C_AddOns namespace if it does not exist, mapping
-- its functions to the classic global equivalents.
------------------------------------------------------------------------
ns.patches["NovaWorldBuffs_cAddOnsShim"] = function()
    if C_AddOns then return end  -- already exists, nothing to do

    C_AddOns = {
        IsAddOnLoaded = IsAddOnLoaded,
        GetAddOnMetadata = GetAddOnMetadata,
    }
end

------------------------------------------------------------------------
-- 4. NovaWorldBuffs_cSummonInfoShim
--
-- NovaWorldBuffs uses C_SummonInfo at 5 locations for the auto-summon
-- feature that accepts pending summons after getting Darkmoon Faire
-- buffs (via Vanish, Feign Death, or leaving combat):
--   lines 1719, 1739 (GetSummonConfirmTimeLeft)
--   lines 1747, 1760, 1794 (ConfirmSummon)
--
-- C_SummonInfo does not exist in TBC Classic Anniversary.
-- ConfirmSummon() exists as a classic global.
-- GetSummonConfirmTimeLeft has no direct TBC equivalent.
--
-- Fix: Create the C_SummonInfo namespace, mapping ConfirmSummon to the
-- classic global and providing a visibility-based fallback for
-- GetSummonConfirmTimeLeft.
------------------------------------------------------------------------
ns.patches["NovaWorldBuffs_cSummonInfoShim"] = function()
    if C_SummonInfo then return end  -- already exists, nothing to do

    C_SummonInfo = {
        ConfirmSummon = function()
            if ConfirmSummon then ConfirmSummon() end
        end,
        GetSummonConfirmTimeLeft = function()
            -- No direct TBC equivalent.  Check if the summon confirm
            -- dialog is visible as a proxy for having a pending summon.
            if StaticPopup_Visible and StaticPopup_Visible("CONFIRM_SUMMON") then
                return 120  -- return a positive value to indicate active summon
            end
            return 0
        end,
    }
end

------------------------------------------------------------------------
-- 5. NovaWorldBuffs_pairsByKeysOptimize
--
-- NWB:pairsByKeys (NovaWorldBuffs.lua:3865) allocates a new table and
-- closure on every call.  It is called from:
--   - The 1-second ticker (for each buff type × layer combination)
--   - recalclayerFrame, recalcMinimapLayerFrame
--   - updateFelwoodWorldmapMarker (for each visible marker)
--   - getGuildDataStatus, setCurrentLayerText, GetLayerNum
--
-- On a layered server this creates 3-6+ table/closure pairs per second
-- from the ticker alone, plus more when UI frames are open.
--
-- Fix: Replace with a version that reuses a single sort buffer.
-- Safe because Lua's table.sort is synchronous and the iterator is
-- consumed before the next call in all usage patterns (no nesting).
------------------------------------------------------------------------
ns.patches["NovaWorldBuffs_pairsByKeysOptimize"] = function()
    local NWB = GetNWB()
    if not NWB then return end
    if not NWB.pairsByKeys then return end

    local sortBuf = {}

    NWB.pairsByKeys = function(self, t, f)
        local n = 0
        for k in pairs(t) do
            n = n + 1
            sortBuf[n] = k
        end
        -- Trim stale entries from previous calls
        for i = n + 1, #sortBuf do
            sortBuf[i] = nil
        end
        table.sort(sortBuf, f)

        local i = 0
        return function()
            i = i + 1
            if sortBuf[i] == nil then return nil end
            return sortBuf[i], t[sortBuf[i]]
        end
    end
end
