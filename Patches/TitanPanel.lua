------------------------------------------------------------------------
-- AddonTweaks - Performance patches for Titan Panel
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
    local btn = _G["TitanPanelReputationsButton"]
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

    TitanPanelButton_UpdateButton = function(id, ...)
        if id == "Bag" then
            if bagTimer then
                bagTimer:Cancel()
            end
            bagTimer = C_Timer.NewTimer(0.2, function()
                bagTimer = nil
                origUpdate("Bag")
            end)
            return
        end
        return origUpdate(id, ...)
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
