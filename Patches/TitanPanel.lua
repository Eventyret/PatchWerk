------------------------------------------------------------------------
-- PatchWerk - Performance patches for Titan Panel
--
-- Titan Panel is a popular information bar addon that displays system
-- stats, bag space, reputation, and more.  On TBC Classic Anniversary,
-- several plugins run expensive updates far more frequently than needed:
--   1. TitanPanel_reputationsOnUpdate  - Replace per-frame OnUpdate with
--                                        a 5-second C_Timer ticker
--   2. TitanPanel_bagDebounce          - Debounce BAG_UPDATE to avoid
--                                        rapid full bag scans during looting
--   3. TitanPanel_performanceThrottle  - Increase minimum Performance
--                                        plugin update interval to 3s
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns.patchInfo[#ns.patchInfo+1] = {
    key = "TitanPanel_reputationsOnUpdate", group = "TitanPanel", label = "Reputation Timer Fix",
    help = "Checks your reputation every 5 seconds instead of constantly.",
    detail = "The reputation plugin checks for updates every single frame even though it only needs to update every few seconds. This wastes 300+ checks per second just to see if it's time to refresh yet.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~0.5-1 FPS from eliminating 300+ idle checks/sec",
    targetVersion = "9.1.1",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "TitanPanel_bagDebounce", group = "TitanPanel", label = "Bag Update Batch",
    help = "Counts bag contents once after looting instead of on every individual slot change.",
    detail = "Titan Panel scans all your bags on every individual bag change. When you loot multiple items quickly, this triggers 4-10 full bag scans in under a second, causing brief stutters. The fix waits for looting to finish before scanning once.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "Eliminates brief stutter when looting multiple items",
    targetVersion = "9.1.1",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "TitanPanel_performanceThrottle", group = "TitanPanel", label = "Performance Display Throttle",
    help = "Updates the FPS/memory display every 3s instead of every 1.5s.",
    detail = "The FPS and memory display updates every 1.5 seconds, checking memory usage across all loaded addons. Ironically, these frequent checks themselves contribute to the performance overhead being displayed.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "~0.5-1 FPS, less ironic performance overhead",
    targetVersion = "9.1.1",
}

local GetTime          = GetTime
local C_Timer          = C_Timer
local hooksecurefunc   = hooksecurefunc

------------------------------------------------------------------------
-- 1. TitanPanel_reputationsOnUpdate
--
-- TitanPanelReputationsButton sets an OnUpdate script that fires every
-- single frame (60+ fps).  The handler contains an internal 5-second
-- throttle, but the Lua function call overhead and elapsed-time check
-- still execute every frame for no benefit between updates.
--
-- Fix: Hook SetScript on the button to intercept when the OnUpdate
-- handler is installed (happens on PLAYER_ENTERING_WORLD).  Replace it
-- with a C_Timer.NewTicker at 5-second intervals, matching the addon's
-- intended update rate while eliminating per-frame overhead.
------------------------------------------------------------------------
ns.patches["TitanPanel_reputationsOnUpdate"] = function()
    -- Elib constructs frame name as "TitanPanel" .. id .. "Button"
    -- TitanReputations uses id = "TITAN_REPUTATION_XP"
    local btn = _G["TitanPanelTITAN_REPUTATION_XPButton"] or _G["TitanPanelReputationsButton"]
    if not btn then return end

    local checked = false

    hooksecurefunc(btn, "SetScript", function(self, scriptType, handler)
        if scriptType == "OnUpdate" and handler and not checked then
            checked = true
            -- Remove the per-frame OnUpdate handler
            self:SetScript("OnUpdate", nil)
            -- Replace with a 5-second ticker (matches the internal throttle)
            C_Timer.NewTicker(5, function()
                if self:IsVisible() and handler then
                    handler(self, 5) -- pass 5 as elapsed to satisfy the throttle check
                end
            end)
        end
    end)
end

------------------------------------------------------------------------
-- 2. TitanPanel_bagDebounce
--
-- TitanBag calls GetBagData() (a full scan of all 5 bag containers) on
-- every BAG_UPDATE event.  During looting, BAG_UPDATE fires once per
-- slot changed, causing 4-10 redundant full bag scans in rapid
-- succession for a single loot action.
--
-- Fix: Wrap TitanPanelButton_UpdateButton so that calls with id="Bag"
-- are debounced with a 0.2-second delay.  Multiple rapid calls cancel
-- the previous timer, so only the final call in a burst actually
-- executes the bag scan.  All other plugin IDs pass through immediately.
------------------------------------------------------------------------
ns.patches["TitanPanel_bagDebounce"] = function()
    if not TitanPanelButton_UpdateButton then return end
    if not _G["TitanPanelBagButton"] then return end

    local origUpdate = TitanPanelButton_UpdateButton
    local bagTimer = nil

    TitanPanelButton_UpdateButton = function(id, setButtonWidth, ...)
        if id == "Bag" then
            if bagTimer then
                bagTimer:Cancel()
            end
            -- Preserve setButtonWidth argument for the deferred call
            local capturedWidth = setButtonWidth
            bagTimer = C_Timer.NewTimer(0.2, function()
                bagTimer = nil
                origUpdate("Bag", capturedWidth)
            end)
            return
        end
        return origUpdate(id, setButtonWidth, ...)
    end
end

------------------------------------------------------------------------
-- 3. TitanPanel_performanceThrottle
--
-- TitanPerformance runs every 1.5 seconds, calling GetFramerate(),
-- GetNetStats(), gcinfo(), and potentially looping all loaded addons
-- for memory usage reporting.  On TBC Classic Anniversary this is
-- unnecessarily frequent for information that changes slowly.
--
-- Fix: Wrap TitanPanelButton_UpdateButton so that calls with
-- id="Performance" are rate-limited to once every 3 seconds.  Calls
-- within the cooldown window are silently discarded.
--
-- NOTE: This patch re-reads TitanPanelButton_UpdateButton at apply
-- time, so it correctly chains with bagDebounce regardless of patch
-- application order (pairs() iteration is not deterministic).
------------------------------------------------------------------------
ns.patches["TitanPanel_performanceThrottle"] = function()
    if not TitanPanelButton_UpdateButton then return end
    if not _G["TitanPanelPerformanceButton"] then return end

    -- Capture the CURRENT function (may already be wrapped by bagDebounce)
    local currentUpdate = TitanPanelButton_UpdateButton
    local perfLast = 0

    TitanPanelButton_UpdateButton = function(id, ...)
        if id == "Performance" then
            local now = GetTime()
            if (now - perfLast) < 3 then return end
            perfLast = now
        end
        return currentUpdate(id, ...)
    end
end
