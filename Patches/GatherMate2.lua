------------------------------------------------------------------------
-- PatchWerk - Performance patches for GatherMate2 (Gathering Nodes)
--
-- GatherMate2 tracks gathering node locations and displays them on
-- the minimap.  On TBC Classic Anniversary its update loops run far
-- more frequently than needed:
--   1. GatherMate2_minimapThrottle - Cap minimap pin updates to 20fps
--   2. GatherMate2_rebuildGuard    - Skip full rebuild when stationary
--   3. GatherMate2_cleuUnregister  - Remove dead combat log handler
------------------------------------------------------------------------

local _, ns = ...

local GetTime = GetTime
local pcall   = pcall

------------------------------------------------------------------------
-- 1. GatherMate2_minimapThrottle
--
-- GatherMate2's Display module runs an OnUpdate handler every frame
-- (60+ fps).  Each frame it calls UpdateIconPositions which makes 4
-- C API calls (GetZoom, GetPlayerWorldPosition, GetPlayerFacing,
-- GetScale) before checking whether the player actually moved.
--
-- Fix: Hook Display.OnEnable to install a 20fps-throttled OnUpdate
-- after the frame is created.  The real accumulated elapsed is
-- forwarded so the internal 2-second rebuild timer works correctly.
-- Note: Display.updateFrame is created inside OnEnable, not at load
-- time, so we must hook OnEnable rather than patching directly.
------------------------------------------------------------------------
ns.patches["GatherMate2_minimapThrottle"] = function()
    if not GatherMate2 then return end

    local ok, Display = pcall(GatherMate2.GetModule, GatherMate2, "Display")
    if not ok or not Display then return end
    if not Display.OnEnable then return end

    local origOnEnable = Display.OnEnable
    Display.OnEnable = function(self, ...)
        origOnEnable(self, ...)
        local frame = self.updateFrame
        if not frame then return end
        local origOnUpdate = frame:GetScript("OnUpdate")
        if not origOnUpdate then return end
        local accum = 0
        frame:SetScript("OnUpdate", function(f, elapsed)
            accum = accum + elapsed
            if accum >= 0.05 then
                origOnUpdate(f, accum)
                accum = 0
            end
        end)
    end
end

------------------------------------------------------------------------
-- 2. GatherMate2_rebuildGuard
--
-- UpdateMiniMap(true) performs a full zone node rebuild every 2 seconds
-- unconditionally.  This iterates all nodes in the current zone doing
-- distance math and pin placement even when the player has not moved.
--
-- Fix: Track player position at last rebuild and skip when stationary.
-- Event-driven rebuilds (new node, config change) still fire because
-- they change positions which break the equality check.
------------------------------------------------------------------------
ns.patches["GatherMate2_rebuildGuard"] = function()
    if not GatherMate2 then return end

    local ok, Display = pcall(GatherMate2.GetModule, GatherMate2, "Display")
    if not ok or not Display then return end
    if not Display.UpdateMiniMap then return end

    local HBD = GatherMate2.HBD
    if not HBD then
        local hasLib, lib = pcall(LibStub, "HereBeDragons-2.0")
        if hasLib then HBD = lib end
    end
    if not HBD or not HBD.GetPlayerWorldPosition then return end

    local origUpdateMiniMap = Display.UpdateMiniMap
    local lastRebuildX, lastRebuildY = -1, -1

    Display.UpdateMiniMap = function(self, force)
        if force then
            local x, y = HBD:GetPlayerWorldPosition()
            if x and y then
                if x == lastRebuildX and y == lastRebuildY then
                    return
                end
                lastRebuildX, lastRebuildY = x, y
            end
        end
        return origUpdateMiniMap(self, force)
    end
end

------------------------------------------------------------------------
-- 3. GatherMate2_cleuUnregister
--
-- The Collector module registers COMBAT_LOG_EVENT_UNFILTERED for Gas
-- Cloud detection (Extract Gas spell).  In TBC Classic Anniversary,
-- Extract Gas is explicitly excluded from the database, yet the CLEU
-- handler still fires on every combat event.  In a raid, that means
-- 200+ wasted function calls per second that just early-return.
--
-- Fix: Unregister the event since gas extraction is unused in TBC.
------------------------------------------------------------------------
ns.patches["GatherMate2_cleuUnregister"] = function()
    if not GatherMate2 then return end

    -- Only apply on TBC Classic Anniversary (Interface 20500-29999)
    local _, _, _, interfaceVersion = GetBuildInfo()
    if not interfaceVersion or interfaceVersion < 20500 or interfaceVersion >= 30000 then
        return
    end

    local ok, Collector = pcall(GatherMate2.GetModule, GatherMate2, "Collector", true)
    if not ok or not Collector then return end
    if not Collector.UnregisterEvent then return end

    pcall(Collector.UnregisterEvent, Collector, "COMBAT_LOG_EVENT_UNFILTERED")
end
