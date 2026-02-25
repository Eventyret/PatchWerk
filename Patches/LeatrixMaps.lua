------------------------------------------------------------------------
-- PatchWerk - Performance patch for Leatrix Maps
--
-- Leatrix Maps enhances the World Map with zone levels, coordinates,
-- and fishing skill info.  Its custom AreaLabelOnUpdate handler runs
-- every single frame (60+ fps) calling C_Map.GetMapInfoAtPosition,
-- string concatenation, and colour calculations each time.
--
--   1. LeatrixMaps_areaLabelThrottle - Throttle area label to 4/sec
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("LeatrixMaps", {
    key = "LeatrixMaps_areaLabelThrottle",
    label = "Area Label Throttle",
    help = "Updates the zone label text 4 times per second instead of every frame.",
    detail = "Leatrix Maps updates the area label on the World Map every single frame -- 60+ times per second -- even though the text only changes when you move your cursor to a different zone. Each update recalculates zone info, level ranges, and colors. This patch limits it to 4 times per second, which still feels instant but eliminates most of the overhead.",
    impact = "FPS",
    impactLevel = "Medium",
    category = "Performance",
    estimate = "Smoother World Map browsing, especially on lower-end systems",
})

------------------------------------------------------------------------
-- 1. LeatrixMaps_areaLabelThrottle
--
-- Leatrix Maps defines a local function AreaLabelOnUpdate(self) and
-- installs it via provider.Label:SetScript("OnUpdate", AreaLabelOnUpdate)
-- for the area label data provider.  This fires every frame with no
-- elapsed-time throttle.  The function calls C_Map.GetMapInfoAtPosition,
-- does table lookups into mapTable, builds coloured level-range strings,
-- and calls self:EvaluateLabels() -- all on every single frame.
--
-- Fix: After Leatrix Maps installs its OnUpdate, we find the Label
-- frame via WorldMapFrame.dataProviders, capture the installed script,
-- and replace it with a throttled wrapper that only calls the original
-- handler at most 4 times per second (every 0.25s).  The wrapper also
-- forwards the self argument so the original handler works unchanged.
------------------------------------------------------------------------
ns.patches["LeatrixMaps_areaLabelThrottle"] = function()
    if not ns:IsAddonLoaded("Leatrix_Maps") then return end

    -- The label provider is set up during Leatrix Maps initialization.
    -- We need to find the data provider that has setAreaLabelCallback,
    -- which is the one Leatrix Maps patches.
    if not WorldMapFrame or not WorldMapFrame.dataProviders then return end

    local THROTTLE_INTERVAL = 0.25  -- 4 updates per second

    for provider in next, WorldMapFrame.dataProviders do
        if provider.setAreaLabelCallback and provider.Label then
            local originalOnUpdate = provider.Label:GetScript("OnUpdate")
            if originalOnUpdate then
                local elapsed_acc = 0

                provider.Label:SetScript("OnUpdate", function(self, elapsed)
                    elapsed_acc = elapsed_acc + (elapsed or 0)
                    if elapsed_acc < THROTTLE_INTERVAL then
                        return
                    end
                    elapsed_acc = 0
                    originalOnUpdate(self)
                end)
            end
            break
        end
    end
end
