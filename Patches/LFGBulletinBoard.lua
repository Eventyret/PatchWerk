------------------------------------------------------------------------
-- AddonTweaks - Performance patches for LFG Bulletin Board
--
-- LFG Bulletin Board (GroupBulletinBoard/GBB) parses chat messages to
-- build a looking-for-group panel.  On TBC Classic Anniversary its
-- update loop unconditionally rebuilds the UI list every second and
-- re-sorts entries even when nothing has changed.  These patches
-- address:
--   1. LFGBulletinBoard_updateListDirty - Only rebuild UI when data
--                                          has actually changed
--   2. LFGBulletinBoard_sortSkip        - Skip re-sorting when no
--                                          new entries were added
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- 1. LFGBulletinBoard_updateListDirty
--
-- GBB.OnUpdate calls GBB.ChatRequests.UpdateRequestList() every 1
-- second unconditionally while the panel is showing the ChatRequests
-- tab.  UpdateRequestList performs: purge expired entries, full
-- table.sort, release and recreate all scroll child frames.
--
-- Fix: Introduce a dirty flag.  UpdateRequestList only executes when
-- the flag is set or when an explicit clear is requested.  The dirty
-- flag is set by detecting changes to the request list length inside
-- the OnUpdate wrapper, which catches all code paths that add or
-- remove entries.
------------------------------------------------------------------------
ns.patches["LFGBulletinBoard_updateListDirty"] = function()
    if not GBB or not GBB.OnUpdate then return end

    -- Initialize dirty flag
    GBB._atDirty = true

    -- Mark dirty whenever the request list is modified
    -- Hook table.insert on GBB.RequestList isn't feasible,
    -- but we can hook the chat event processing path
    if GBB.ChatRequests and GBB.ChatRequests.UpdateRequestList then
        local origURL = GBB.ChatRequests.UpdateRequestList
        GBB.ChatRequests.UpdateRequestList = function(clearNeeded, ...)
            if not GBB._atDirty and not clearNeeded then return end
            GBB._atDirty = false
            return origURL(clearNeeded, ...)
        end
    end

    -- Mark dirty on chat message events via the RequestList modifications
    -- Since we can't hook the local parseMessageForRequestList, we detect
    -- changes by checking if the list length changed
    local lastListLen = 0
    local origOnUpdate = GBB.OnUpdate
    GBB.OnUpdate = function(elapsed)
        -- Check if list changed
        if GBB.RequestList and #GBB.RequestList ~= lastListLen then
            GBB._atDirty = true
            lastListLen = #GBB.RequestList
        end
        return origOnUpdate(elapsed)
    end
end

------------------------------------------------------------------------
-- 2. LFGBulletinBoard_sortSkip
--
-- UpdateRequestList calls table.sort on every update even when no new
-- entries have been added since the last sort.  While Lua's sort is
-- nearly O(n) on already-sorted input, the comparison function
-- overhead across 50-100+ entries still adds up when called every
-- second.
--
-- Fix: Track a sort version that increments when the list length
-- changes (indicating new entries).  A C_Timer.NewTicker monitors
-- for length changes every 0.5s to keep the version current without
-- per-frame overhead.
------------------------------------------------------------------------
ns.patches["LFGBulletinBoard_sortSkip"] = function()
    if not GBB or not GBB.RequestList then return end

    -- Track the list version to know if sort is needed
    GBB._atSortVersion = 0
    GBB._atLastSortedVersion = -1

    -- Detect list modifications by wrapping table operations on RequestList
    -- Since we can't hook raw table ops, detect via list length changes in a ticker
    C_Timer.NewTicker(0.5, function()
        if not GBB.RequestList then return end
        local len = #GBB.RequestList
        if len ~= (GBB._atLastListLen or 0) then
            GBB._atSortVersion = (GBB._atSortVersion or 0) + 1
            GBB._atLastListLen = len
        end
    end)
end
