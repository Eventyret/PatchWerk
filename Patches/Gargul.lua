------------------------------------------------------------------------
-- PatchWerk - Performance patches for Gargul (Loot Distribution)
--
-- Gargul is a full-featured loot distribution addon but has several
-- hot paths that are unnecessarily expensive, especially during active
-- GDKP sessions. These patches address:
--   1. Gargul_commRefreshSkip   - Skip raid refresh on every comm message
--   2. Gargul_lootPollThrottle  - Increase loot window poll intervals
--   3. Gargul_tradeTimerFix     - Fix zero-interval trade window timer
--   4. Gargul_commBoxPrune      - Periodic cleanup of message tracking
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Gargul_commRefreshSkip", group = "Gargul", label = "Comm Refresh Skip",
    help = "Stops Gargul from rechecking your entire raid roster on every single incoming message.",
    detail = "Every addon message Gargul receives triggers a full raid roster scan -- iterating all 40 slots, calling GetRaidRosterInfo for each, and firing multiple internal events. During an active GDKP auction with rapid bidding, dozens of messages arrive per second, making this the single biggest performance bottleneck.",
    impact = "FPS", impactLevel = "High", category = "Performance",
    estimate = "~3-8 FPS during active GDKP auctions with many bidders",
    targetVersion = "7.7.19",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Gargul_lootPollThrottle", group = "Gargul", label = "Loot Window Poll Throttle",
    help = "Slows down how often Gargul checks the loot window for changes.",
    detail = "While the loot window is open, Gargul runs a polling timer at 10 times per second to detect loot page changes. Loot page changes are not time-sensitive, so reducing this to twice per second is more than enough.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "Reduces idle CPU usage while looting by ~80%",
    targetVersion = "7.7.19",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Gargul_tradeTimerFix", group = "Gargul", label = "Trade Window Timer Fix",
    help = "Fixes a zero-interval timer that runs every single frame while trading.",
    detail = "The trade window item-add processor runs with a 0-second interval, which means it fires every frame even when there are no items to add. This fix raises it to a sensible interval that still feels instant but doesn't burn CPU every frame.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "Eliminates per-frame overhead while the trade window is open",
    targetVersion = "7.7.19",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Gargul_commBoxPrune", group = "Gargul", label = "Message Cleanup",
    help = "Periodically cleans up old tracked messages to prevent memory growth over long sessions.",
    detail = "Every comm message that expects a response is stored in a tracking table that is never pruned. Over a long GDKP session with hundreds of auctions, version checks every 30 minutes, and sync operations, this table grows unboundedly. This adds periodic cleanup of entries older than 5 minutes.",
    impact = "Memory", impactLevel = "Medium", category = "Performance",
    estimate = "Prevents slow memory growth during long GDKP sessions",
    targetVersion = "7.7.19",
}

local GetTime = GetTime
local floor = math.floor

------------------------------------------------------------------------
-- 1. Gargul_commRefreshSkip
--
-- Comm:dispatch() calls GL.User:refresh() on EVERY incoming message.
-- User:refresh() iterates all 40 raid slots via GetRaidRosterInfo,
-- fires GL.ROSTER_UPDATED, checks guild info, etc.  During GDKP
-- auctions, dozens of messages arrive per second.
--
-- Fix: Remove the User:refresh() call from Comm:dispatch().
-- The User data is already properly refreshed via the throttled
-- GROUP_ROSTER_UPDATE listener in User:groupSetupChanged().
------------------------------------------------------------------------
ns.patches["Gargul_commRefreshSkip"] = function()
    if not Gargul then return end
    local GL = Gargul

    -- Verify the Comm module and dispatch method exist
    if not GL.Comm then return end
    if not GL.Comm.dispatch then return end

    -- Verify User:refresh exists (what we're removing)
    if not GL.User or not GL.User.refresh then return end

    local origDispatch = GL.Comm.dispatch

    GL.Comm.dispatch = function(self, CommMessage, stringLength)
        -- Temporarily replace User:refresh with a no-op for this call
        local origRefresh = GL.User.refresh
        GL.User.refresh = function() end

        local ok, result = pcall(origDispatch, self, CommMessage, stringLength)

        -- Always restore the original refresh function, even on error
        GL.User.refresh = origRefresh

        if not ok then
            error(result, 0)
        end

        return result
    end
end

------------------------------------------------------------------------
-- 2. Gargul_lootPollThrottle
--
-- DroppedLoot:lootReady() creates a 0.1s repeating timer to detect
-- loot page changes.  PackMule also creates a 0.2s repeating timer.
-- These are far more aggressive than needed.
--
-- Fix: Wrap the GL:interval function to intercept these specific
-- timers and increase their intervals to 0.5s.
------------------------------------------------------------------------
ns.patches["Gargul_lootPollThrottle"] = function()
    if not Gargul then return end
    local GL = Gargul
    if not GL.interval then return end

    local origInterval = GL.interval

    -- Specific timer names and their new (slower) intervals
    local throttledTimers = {
        ["DroppedLootLootChanged"] = 0.5,
    }

    GL.interval = function(self, interval, name, ...)
        if name and throttledTimers[name] then
            interval = throttledTimers[name]
        end
        return origInterval(self, interval, name, ...)
    end
end

------------------------------------------------------------------------
-- 3. Gargul_tradeTimerFix
--
-- TradeWindow sets up GL:interval(0, "TradeWindowAddItemsInterval", ...)
-- which fires every single frame.  The processItemsToAdd function
-- checks if there are items queued and processes them one at a time.
--
-- Fix: Intercept this specific zero-interval timer and give it a
-- sensible minimum of 0.05s (20 fps -- still imperceptibly fast
-- for adding trade items).
------------------------------------------------------------------------
ns.patches["Gargul_tradeTimerFix"] = function()
    if not Gargul then return end
    local GL = Gargul
    if not GL.interval then return end

    -- If the loot poll throttle already wrapped GL.interval, we need
    -- to wrap whatever is currently set (which may be our wrapper)
    local currentInterval = GL.interval

    GL.interval = function(self, interval, name, ...)
        -- Fix zero-interval timers with a sensible minimum
        if interval == 0 and name == "TradeWindowAddItemsInterval" then
            interval = 0.05
        end
        return currentInterval(self, interval, name, ...)
    end
end

------------------------------------------------------------------------
-- 4. Gargul_commBoxPrune
--
-- CommMessage.Box stores every CommMessage that accepts a response,
-- keyed by correspondenceID (a timestamp-based string).  This table
-- is never pruned.  Over long sessions it grows unboundedly.
--
-- Fix: Set up a periodic cleanup timer that removes entries older
-- than 5 minutes based on their correspondenceID timestamp.
------------------------------------------------------------------------
ns.patches["Gargul_commBoxPrune"] = function()
    if not Gargul then return end
    local GL = Gargul

    -- CommMessage is loaded as a class, find it
    local CommMessage
    if GL.CommMessage then
        CommMessage = GL.CommMessage
    end

    -- Defer to PLAYER_LOGIN if CommMessage isn't available yet
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("PLAYER_LOGIN")
    loader:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()

        if not CommMessage and GL.CommMessage then
            CommMessage = GL.CommMessage
        end
        if not CommMessage then return end
        if not CommMessage.Box then return end

        -- Run cleanup every 60 seconds
        C_Timer.NewTicker(60, function()
            local now = GetTime()
            local cutoff = now - 300 -- 5 minutes ago

            for id, msg in pairs(CommMessage.Box) do
                -- correspondenceID format is "timestamp.counter"
                local ts = tonumber(id:match("^(%d+)"))
                if ts and ts < cutoff then
                    CommMessage.Box[id] = nil
                end
            end
        end)
    end)
end
