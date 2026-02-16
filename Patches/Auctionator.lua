------------------------------------------------------------------------
-- AddonTweaks - Performance patches for Auctionator (Auction House)
--
-- Auctionator hooks into the Legacy AH system for TBC Classic.  Several
-- hot paths cause unnecessary server queries and memory allocations:
--   1. Auctionator_ownerQueryThrottle - Throttle GetOwnerAuctionItems
--   2. Auctionator_throttleBroadcast - Reduce EventBus timeout spam
--   3. Auctionator_priceAgeOptimize  - Zero-allocation price age lookup
--   4. Auctionator_dbKeyCache        - Cache item link to DB key mapping
------------------------------------------------------------------------

local _, ns = ...

local GetTime  = GetTime
local pairs    = pairs
local floor    = math.floor
local tonumber = tonumber

------------------------------------------------------------------------
-- 1. Auctionator_ownerQueryThrottle
--
-- Both the Cancelling and Selling tab mixins call
-- GetOwnerAuctionItems(0) every single frame in their OnUpdate
-- handlers — 60+ server queries per second, per tab.  Auction data
-- only changes on post/cancel actions, not at frame rate.
--
-- Fix: Throttle to once per second.  A shared timestamp prevents
-- both tabs from querying simultaneously.
------------------------------------------------------------------------
ns.patches["Auctionator_ownerQueryThrottle"] = function()
    if not AuctionatorCancellingFrameMixin then return end

    local lastQuery = 0

    -- Throttle Cancelling tab
    local origCancelUpdate = AuctionatorCancellingFrameMixin.OnUpdate
    if origCancelUpdate then
        AuctionatorCancellingFrameMixin.OnUpdate = function(self, ...)
            local now = GetTime()
            if (now - lastQuery) >= 1.0 then
                lastQuery = now
                return origCancelUpdate(self, ...)
            end
        end
    end

    -- Throttle Selling tab
    if AuctionatorSaleItemMixin and AuctionatorSaleItemMixin.OnUpdate then
        local origSaleUpdate = AuctionatorSaleItemMixin.OnUpdate
        AuctionatorSaleItemMixin.OnUpdate = function(self, ...)
            local now = GetTime()
            if (now - lastQuery) >= 1.0 then
                lastQuery = now
                return origSaleUpdate(self, ...)
            end
            -- Let the non-server-query parts still run (item checks, price update)
            if self.itemInfo and self.UpdatePrices then
                self:UpdatePrices()
            end
        end
    end
end

------------------------------------------------------------------------
-- 2. Auctionator_throttleBroadcast
--
-- The AH throttling frame fires EventBus:Fire for
-- CurrentThrottleTimeout 60 times per second during any AH
-- transaction.  This is a display-only countdown value.
--
-- Fix: Throttle the timeout broadcast to 2Hz while keeping the
-- Ready/ThrottleUpdate state-change detection at full frame rate.
------------------------------------------------------------------------
ns.patches["Auctionator_throttleBroadcast"] = function()
    if not AuctionatorAHThrottlingFrameMixin then return end
    if not Auctionator or not Auctionator.EventBus then return end
    if not AuctionatorAHThrottlingFrameMixin.OnUpdate then return end

    local origOnUpdate = AuctionatorAHThrottlingFrameMixin.OnUpdate
    local TIMEOUT = 10
    local lastTimeoutFire = 0

    AuctionatorAHThrottlingFrameMixin.OnUpdate = function(self, elapsed)
        -- Timeout accumulation (cheap, every frame)
        if self.AnyWaiting and self:AnyWaiting() then
            self.timeout = self.timeout - elapsed
            if self.timeout <= 0 then
                if self.ResetWaiting then self:ResetWaiting() end
                if self.ResetTimeout then self:ResetTimeout() end
            end
        else
            self.timeout = TIMEOUT
        end

        -- Throttle display-only broadcast to 2Hz
        if self.timeout ~= TIMEOUT then
            local now = GetTime()
            if (now - lastTimeoutFire) >= 0.5 then
                lastTimeoutFire = now
                if Auctionator.AH and Auctionator.AH.Events then
                    Auctionator.EventBus:Fire(self,
                        Auctionator.AH.Events.CurrentThrottleTimeout, self.timeout)
                end
            end
        end

        -- State-change detection stays at full frame rate
        local ready = self.IsReady and self:IsReady() or false
        if ready and not self.oldReady then
            if Auctionator.AH and Auctionator.AH.Events then
                Auctionator.EventBus:Fire(self, Auctionator.AH.Events.Ready)
                Auctionator.EventBus:Fire(self, Auctionator.AH.Events.ThrottleUpdate, true)
            end
        elseif self.oldReady ~= ready then
            if Auctionator.AH and Auctionator.AH.Events then
                Auctionator.EventBus:Fire(self, Auctionator.AH.Events.ThrottleUpdate, false)
            end
        end
        self.oldReady = ready
    end
end

------------------------------------------------------------------------
-- 3. Auctionator_priceAgeOptimize
--
-- GetPriceAge allocates a new table, fills it with all history keys,
-- converts them all to numbers, sorts the array, then only reads the
-- maximum.  This runs on every tooltip hover over any item.
--
-- Fix: Replace with a zero-allocation O(n) linear max scan.
------------------------------------------------------------------------
ns.patches["Auctionator_priceAgeOptimize"] = function()
    if not Auctionator then return end
    if not Auctionator.DatabaseMixin then return end

    Auctionator.DatabaseMixin.GetPriceAge = function(self, dbKey)
        local itemData = self.db and self.db[dbKey]
        if not itemData or not itemData.h then return nil end

        local maxDay = nil
        for dayStr in pairs(itemData.h) do
            local day = tonumber(dayStr)
            if day and (not maxDay or day > maxDay) then
                maxDay = day
            end
        end

        if not maxDay then return nil end

        local scanDay0 = Auctionator.Constants and Auctionator.Constants.SCAN_DAY_0 or 0
        local today = floor((time() - scanDay0) / 86400)
        return today - maxDay
    end

    -- Patch live instance since the mixin was already applied at load
    if Auctionator.Database then
        Auctionator.Database.GetPriceAge = Auctionator.DatabaseMixin.GetPriceAge
    end
end

------------------------------------------------------------------------
-- 4. Auctionator_dbKeyCache
--
-- DBKeyFromLink runs a regex match and GetItemInfoInstant on every
-- tooltip display to convert an item link to a database key.  In TBC
-- Classic, item links are deterministic per session, so results can
-- be cached aggressively.
--
-- Fix: Cache DBKeyFromLink results by item link string.
------------------------------------------------------------------------
ns.patches["Auctionator_dbKeyCache"] = function()
    if not Auctionator then return end
    if not Auctionator.Utilities or not Auctionator.Utilities.DBKeyFromLink then return end

    local cache = {}
    local origDBKeyFromLink = Auctionator.Utilities.DBKeyFromLink

    Auctionator.Utilities.DBKeyFromLink = function(itemLink, callback)
        if not itemLink then
            if callback then callback({}) end
            return
        end

        local cached = cache[itemLink]
        if cached then
            if callback then callback(cached) end
            return
        end

        origDBKeyFromLink(itemLink, function(dbKeys)
            cache[itemLink] = dbKeys
            if callback then callback(dbKeys) end
        end)
    end
end
