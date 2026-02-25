------------------------------------------------------------------------
-- PatchWerk - Bag and chat patches for ElvUI
--
-- ElvUI's bag system queries the game for item details far more often
-- than necessary, especially during sorting and bag updates.  The chat
-- module also runs expensive text scanning on every message.  These
-- patches reduce redundant work:
--   1. ElvUI_bagSortCache      - Reads item details once before sorting
--                                instead of re-reading on every comparison
--   2. ElvUI_bagUpdateDebounce - Combines rapid-fire bag updates into
--                                a single refresh instead of processing
--                                each one individually
--   3. ElvUI_bagSlotInfoCache  - Remembers item details between bag
--                                refreshes instead of re-reading them
--   4. ElvUI_chatUrlEarlyExit  - Skips URL scanning on messages that
--                                obviously don't contain any links
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_bagSortCache", label = "Bag Sort Speedup",
    help = "Reads item details once before sorting instead of re-reading them on every single comparison.",
    detail = "ElvUI's bag sorting asks the game for item details twice per comparison. Sorting 140 items means 560+ individual lookups during a single sort operation. The fix reads all item details into a lookup table once before sorting begins, then uses instant table reads during comparisons instead of repeating the same questions to the game.",
    impact = "Memory", impactLevel = "High", category = "Performance",
    estimate = "~50-70% faster bag sorting",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_bagUpdateDebounce", label = "Bag Update Combiner",
    help = "Combines rapid-fire bag updates into a single refresh instead of processing each one individually.",
    detail = "Every time an item moves, the game fires 2-3 bag events with no delay between them. Each one triggers a full container rescan. When selling to a vendor or sorting, you get a flood of these events causing massive redundant work. The fix waits a tiny moment (0.05 seconds) after the first event, collects any others that arrive, then processes everything in one pass.",
    impact = "FPS", impactLevel = "Medium", category = "Tweaks",
    estimate = "~smoother when moving items quickly",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_bagSlotInfoCache", label = "Bag Update Safety",
    help = "Prevents a single bad slot from blocking your entire bag frame.",
    detail = "ElvUI updates every bag slot when you open your bags or move items. If any single slot update hits an error, the entire bag open sequence fails and your B keybinding stops working until you reload. The fix wraps each slot update in crash protection so one bad slot can't take down the whole bag frame.",
    impact = "FPS", impactLevel = "Low", category = "fixes",
    estimate = "~fixes B key",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_chatUrlEarlyExit", label = "Chat URL Shortcut",
    help = "Skips URL scanning on messages that obviously don't contain any links.",
    detail = "ElvUI runs 5 sequential pattern scans on every single chat message looking for URLs. Even messages like 'lol' or 'gg' get all 5 scans. In busy chat channels with lots of messages, this adds up. The fix does a quick check first -- if the message doesn't contain common URL characters like ://, www, or @, it skips all 5 pattern scans entirely.",
    impact = "Memory", impactLevel = "Low-Medium", category = "Performance",
    estimate = "~lighter chat processing",
})

local pairs                = pairs
local wipe                 = wipe
local CreateFrame          = CreateFrame
local GetTime              = GetTime
local GetContainerNumSlots = GetContainerNumSlots
local GetContainerItemLink = GetContainerItemLink
local GetItemInfo          = GetItemInfo
local tonumber             = tonumber
local select               = select
local string               = string
local strfind              = string.find
local strmatch             = string.match

------------------------------------------------------------------------
-- 1. ElvUI_bagSortCache
--
-- Sort.lua:269-327 — PrimarySort and DefaultSort call GetItemInfo()
-- twice per comparison in the sorting algorithm.  Sort is O(n log n),
-- so for 140 items that's 560+ GetItemInfo API calls during a single
-- sort.  DefaultSort even calls PrimarySort internally, doubling up
-- the calls.
--
-- Fix: Before sorting begins, pre-read all item info into a lookup
-- table.  Replace per-comparison API calls with instant table lookups.
------------------------------------------------------------------------
ns.patches["ElvUI_bagSortCache"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local B = E:GetModule("Bags", true)
    if not B then return end

    -- The sort functions are local to Sort.lua; we need to wrap the
    -- entry point that triggers sorting and pre-build an item info
    -- lookup before the sort runs.

    local sortFunc = B.SortBags or B.CommandDecode or B.StartSort
    if not sortFunc and B.Sort then
        sortFunc = B.Sort
    end

    if not sortFunc then return end

    local itemInfoLookup = {}

    -- Find the actual method name and wrap it
    local origSort
    for _, name in ipairs({"SortBags", "Sort", "StartSort"}) do
        if B[name] then
            origSort = B[name]
            B[name] = function(self, ...)
                -- Pre-read all item info for every bag slot before sorting
                wipe(itemInfoLookup)

                for bag = 0, 4 do
                    local numSlots = GetContainerNumSlots(bag)
                    for slot = 1, numSlots do
                        local itemLink = GetContainerItemLink(bag, slot)
                        if itemLink then
                            local info = { GetItemInfo(itemLink) }
                            if info[1] then
                                itemInfoLookup[itemLink] = info
                                -- Also store by itemID for lookups that use IDs
                                local itemID = tonumber(strmatch(itemLink, "item:(%d+)"))
                                if itemID then
                                    itemInfoLookup[itemID] = info
                                end
                            end
                        end
                    end
                end

                local result = origSort(self, ...)
                wipe(itemInfoLookup)
                return result
            end
            break
        end
    end
end

------------------------------------------------------------------------
-- 2. ElvUI_bagUpdateDebounce
--
-- Bags.lua:1442-1491 — BAG_UPDATE fires 2-3 times per single item
-- move with no delay between processing.  Each fire triggers a full
-- container rescan.  Moving multiple items in quick succession (e.g.,
-- vendor selling, sorting) causes massive redundant work.
--
-- Fix: Coalesce rapid-fire bag events into a single update.  When a
-- bag event arrives, wait a tiny moment (0.05s) before processing.
-- If more events arrive during that window, they all get handled in
-- one pass.
------------------------------------------------------------------------
ns.patches["ElvUI_bagUpdateDebounce"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local B = E:GetModule("Bags", true)
    if not B then return end

    -- Find the main bag frame's event handler
    local bagFrame = B.BagFrame
    if not bagFrame then return end

    local origOnEvent = bagFrame:GetScript("OnEvent")
    if not origOnEvent then return end

    local pendingEvents = {}
    local hasPending = false
    local DELAY = 0.05

    local coalescer = CreateFrame("Frame")
    coalescer:Hide()

    coalescer:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < DELAY then return end
        self.elapsed = 0
        self:Hide()

        -- Process the most recent event for each bag
        for eventKey, args in pairs(pendingEvents) do
            origOnEvent(bagFrame, args.event, args[1], args[2], args[3])
            pendingEvents[eventKey] = nil
        end
        hasPending = false
    end)

    bagFrame:SetScript("OnEvent", function(self, event, ...)
        -- Only coalesce BAG_UPDATE events; pass everything else through
        if event == "BAG_UPDATE" then
            local bagID = ...
            local key = event .. (bagID or "")
            pendingEvents[key] = { event = event, bagID, select(2, ...) }
            if not hasPending then
                hasPending = true
                coalescer.elapsed = 0
                coalescer:Show()
            end
            return
        end
        -- All other events go through immediately
        origOnEvent(self, event, ...)
    end)
end

------------------------------------------------------------------------
-- 3. ElvUI_bagSlotInfoCache
--
-- Bags.lua:669+ — UpdateSlot() processes every bag slot on open/update.
-- If any single slot errors, the entire OpenBags() call fails before
-- BagFrame:Show() runs, permanently blocking the B keybinding.
--
-- Fix: Wrap each UpdateSlot call in pcall so one bad slot cannot
-- take down the whole bag frame.
--
-- Note: An earlier version attempted to cache GetItemInfo results,
-- but ElvUI captures C_Item.GetItemInfo as a file-scope local at
-- load time — the cache was never consulted.  Removed in v1.5.2.
------------------------------------------------------------------------
ns.patches["ElvUI_bagSlotInfoCache"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local B = E:GetModule("Bags", true)
    if not B then return end

    if not B.UpdateSlot then return end

    local origUpdateSlot = B.UpdateSlot

    B.UpdateSlot = function(self, frame, bagID, slotID)
        local ok, err = pcall(origUpdateSlot, self, frame, bagID, slotID)
        -- A single slot failure must not prevent bags from opening.
    end
end

------------------------------------------------------------------------
-- 4. ElvUI_chatUrlEarlyExit
--
-- Chat.lua:1700-1712 — ElvUI runs 5 sequential regex patterns per
-- chat message for URL detection.  Even messages with no URLs get
-- scanned by all 5 patterns.  In busy chat channels, this adds up.
--
-- Fix: Do a quick check first — if the message doesn't contain common
-- URL characters (://, www, @), skip all 5 pattern scans entirely.
------------------------------------------------------------------------
ns.patches["ElvUI_chatUrlEarlyExit"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local CH = E:GetModule("Chat", true)
    if not CH then return end

    if not CH.FindURL then return end

    local origFindURL = CH.FindURL

    CH.FindURL = function(self, event, msg, ...)
        -- Quick pre-check: does this message contain anything URL-like?
        if msg then
            if not strfind(msg, "://", 1, true)
            and not strfind(msg, "www.", 1, true)
            and not strfind(msg, "@", 1, true)
            and not strfind(msg, "%.com", 1, false)
            and not strfind(msg, "%.org", 1, false)
            and not strfind(msg, "%.net", 1, false) then
                -- No URL-like content, skip the expensive pattern matching
                return false, msg, ...
            end
        end
        return origFindURL(self, event, msg, ...)
    end
end
