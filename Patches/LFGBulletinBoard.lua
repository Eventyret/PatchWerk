------------------------------------------------------------------------
-- PatchWerk - Performance patches for LFG Bulletin Board
--
-- LFG Bulletin Board (GroupBulletinBoard/GBB) parses chat messages to
-- build a looking-for-group panel.  On TBC Classic Anniversary its
-- update loop unconditionally rebuilds the UI list every second and
-- re-sorts entries even when nothing has changed.  These patches
-- address:
--   1. LFGBulletinBoard_updateListDirty - Only rebuild UI when data
--                                          has actually changed
--   2. LFGBulletinBoard_sortSkip        - Time-based throttle on
--                                          UpdateRequestList calls
------------------------------------------------------------------------

local _, ns = ...

local pairs   = pairs
local GetTime = GetTime

------------------------------------------------------------------------
-- 1. LFGBulletinBoard_updateListDirty
--
-- GBB.OnUpdate calls GBB.ChatRequests.UpdateRequestList() every 1
-- second unconditionally while the panel is showing the ChatRequests
-- tab.  UpdateRequestList performs: purge expired entries, full
-- table.sort, release and recreate all scroll child frames.
--
-- NOTE: GBB.OnUpdate is stored by reference inside LibGPIToolBox's
-- internal update handler array.  Overwriting GBB.OnUpdate only changes
-- the table field without affecting the already-stored function pointer.
--
-- Fix: Wrap UpdateRequestList with a dirty flag.  A C_Timer.NewTicker
-- monitors the request list for content changes every 0.5s and sets
-- the dirty flag when entries are added or removed.  Uses pairs() to
-- count entries correctly on sparse tables (GBB nil-assigns to remove).
------------------------------------------------------------------------
ns.patches["LFGBulletinBoard_updateListDirty"] = function()
    if not GBB then return end
    if not GBB.ChatRequests or not GBB.ChatRequests.UpdateRequestList then return end

    local dirty = true
    local lastEntryCount = 0

    -- Monitor for list changes via ticker (cannot hook GBB.OnUpdate:
    -- it is stored by reference in LibGPIToolBox._GPIPRIVAT_updates)
    C_Timer.NewTicker(0.5, function()
        if not GBB.RequestList then return end
        -- Count with pairs() to handle sparse tables correctly
        local count = 0
        for _ in pairs(GBB.RequestList) do
            count = count + 1
        end
        if count ~= lastEntryCount then
            dirty = true
            lastEntryCount = count
        end
    end)

    local origURL = GBB.ChatRequests.UpdateRequestList
    GBB.ChatRequests.UpdateRequestList = function(clearNeeded, ...)
        if clearNeeded then
            dirty = false
            return origURL(clearNeeded, ...)
        end
        if not dirty then return end
        dirty = false
        return origURL(clearNeeded, ...)
    end
end

------------------------------------------------------------------------
-- 2. LFGBulletinBoard_sortSkip
--
-- When updateListDirty is disabled, UpdateRequestList still runs every
-- second unconditionally.  This patch provides an independent time-based
-- throttle: UpdateRequestList can run at most once every 2 seconds
-- (unless clearNeeded forces an immediate rebuild).
--
-- When both patches are enabled they chain: the outer wrapper gates on
-- dirty flag, the inner gates on time interval, providing both
-- content-aware and time-based protection.
------------------------------------------------------------------------
ns.patches["LFGBulletinBoard_sortSkip"] = function()
    if not GBB then return end
    if not GBB.ChatRequests or not GBB.ChatRequests.UpdateRequestList then return end

    local lastRun = 0
    local MIN_INTERVAL = 2

    local origURL = GBB.ChatRequests.UpdateRequestList
    GBB.ChatRequests.UpdateRequestList = function(clearNeeded, ...)
        if clearNeeded then
            lastRun = GetTime()
            return origURL(clearNeeded, ...)
        end
        local now = GetTime()
        if (now - lastRun) < MIN_INTERVAL then return end
        lastRun = now
        return origURL(clearNeeded, ...)
    end
end
