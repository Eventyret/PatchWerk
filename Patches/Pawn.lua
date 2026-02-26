------------------------------------------------------------------------
-- PatchWerk - Performance patches for Pawn (Item Comparison)
--
-- Pawn hooks 20+ GameTooltip methods to annotate items with upgrade
-- arrows and scale values.  On TBC Classic Anniversary several of its
-- hot paths are unnecessarily expensive because they were written for
-- retail where the cost is hidden by faster hardware.
-- These patches address:
--   1. Pawn_cacheIndex     - O(1) hash lookup instead of O(200) linear scan
--   2. Pawn_tooltipDedup   - Skip redundant tooltip processing for same item
--   3. Pawn_upgradeCache   - Cache upgrade comparison results per item link
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("Pawn", {
    key = "Pawn_cacheIndex", label = "Fast Item Lookup",
    help = "Makes Pawn find item info much faster instead of searching through hundreds of entries.",
    detail = "Pawn searches through up to 200 cached items one by one every time you hover an item. When you're rapidly mousing over loot or vendor items, this causes tooltip lag where there's a visible delay before Pawn's upgrade arrows appear.",
    impact = "FPS", impactLevel = "High", category = "Performance",
    estimate = "Noticeably snappier tooltips when hovering items",
})
ns:RegisterPatch("Pawn", {
    key = "Pawn_tooltipDedup", label = "Duplicate Tooltip Guard",
    help = "Stops Pawn from checking the same item multiple times when you mouse over it.",
    detail = "Multiple tooltip updates fire for the same item, causing Pawn to calculate upgrade scores 2-4 times per hover. This makes tooltips feel sluggish, especially with multiple stat scales enabled.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "Faster tooltip display with multiple stat scales",
})
ns:RegisterPatch("Pawn", {
    key = "Pawn_upgradeCache", label = "Upgrade Result Cache",
    help = "Remembers if an item is an upgrade so Pawn doesn't recheck all your gear on every hover.",
    detail = "Pawn recalculates upgrade comparisons against all your equipped gear for every item you hover, every single time. With 2-3 active stat scales, hovering loot during a dungeon run causes noticeable tooltip delays.",
    impact = "FPS", impactLevel = "High", category = "Performance",
    estimate = "Instant upgrade arrows on items you've seen before",
})

local wipe = wipe

------------------------------------------------------------------------
-- 1. Pawn_cacheIndex
--
-- PawnGetCachedItem(ItemLink, ItemName, NumLines) iterates the entire
-- PawnItemCache array (up to 200 entries) checking ItemLink == CachedItem.Link
-- for every tooltip show.  PawnCacheItem adds items and PawnUncacheItem
-- removes them.
--
-- Fix: Maintain a parallel hash index keyed by ItemLink so the most
-- common lookup path (by link, no NumLines validation) is O(1).
------------------------------------------------------------------------
ns.patches["Pawn_cacheIndex"] = function()
    if not PawnGetCachedItem then return end
    if not PawnCacheItem then return end

    local cacheIndex = {}

    -- Hook PawnCacheItem to maintain index.
    -- Note: PawnItemCache is local to Pawn.lua so we cannot access it to
    -- clean up LRU-evicted entries. The hash index may accumulate stale
    -- entries, but this is acceptable: the O(1) lookup is still a major
    -- improvement over the O(200) linear scan, and stale entries only
    -- return data that was valid at cache time (no corruption risk).
    -- PawnClearCache and PawnUncacheItem hooks handle explicit removals.
    local origCache = PawnCacheItem
    rawset(_G, "PawnCacheItem", function(CachedItem, ...)
        origCache(CachedItem, ...)
        if CachedItem and CachedItem.Link then
            cacheIndex[CachedItem.Link] = CachedItem
        end
    end)

    -- Hook PawnUncacheItem to maintain index
    if PawnUncacheItem then
        local origUncache = PawnUncacheItem
        rawset(_G, "PawnUncacheItem", function(CachedItem, ...)
            if CachedItem and CachedItem.Link then
                cacheIndex[CachedItem.Link] = nil
            end
            return origUncache(CachedItem, ...)
        end)
    end

    -- Hook PawnClearCache if it exists
    if PawnClearCache then
        local origClear = PawnClearCache
        rawset(_G, "PawnClearCache", function(...)
            wipe(cacheIndex)
            return origClear(...)
        end)
    end

    -- Replace PawnGetCachedItem with hash lookup for link-based queries
    local origGet = PawnGetCachedItem
    rawset(_G, "PawnGetCachedItem", function(ItemLink, ItemName, NumLines)
        -- Respect debug mode: Pawn disables caching when PawnCommon.Debug is true
        if PawnCommon and PawnCommon.Debug then
            return origGet(ItemLink, ItemName, NumLines)
        end
        -- Fast path: direct link lookup (most common case)
        if ItemLink and not NumLines then
            local cached = cacheIndex[ItemLink]
            if cached then return cached end
        end
        -- Fallback to original for NumLines validation or name-only lookups
        return origGet(ItemLink, ItemName, NumLines)
    end)
end

------------------------------------------------------------------------
-- 2. Pawn_tooltipDedup
--
-- PawnUpdateTooltip is hooked on 20+ different GameTooltip methods
-- (SetBagItem, SetMerchantItem, SetHyperlink, etc.).  Multiple hooks
-- can fire for the same item, causing the full parse pipeline to run
-- repeatedly for no benefit.
--
-- Fix: Track the last processed item link per tooltip and skip if
-- the same link is seen again.  Clear on Hide / ClearLines.
------------------------------------------------------------------------
ns.patches["Pawn_tooltipDedup"] = function()
    if not PawnUpdateTooltip then return end

    local lastProcessedLink = {}
    local lastProcessedTime = {}
    local DEDUP_WINDOW = 0.1  -- only skip within the same frame (~100ms)

    local origUpdate = PawnUpdateTooltip
    rawset(_G, "PawnUpdateTooltip", function(TooltipName, MethodName, Param1, ...)
        -- Try to determine the item link early
        local itemLink
        if MethodName == "SetHyperlink" and Param1 then
            itemLink = Param1
        else
            local tip = _G[TooltipName]
            if tip and tip.GetItem then
                local _, link = tip:GetItem()
                itemLink = link
            end
        end

        -- Skip if we already processed this exact item on this tooltip
        -- within the same frame. The time window prevents stale dedup:
        -- when the game rebuilds a tooltip via Set* methods (e.g., bag
        -- refresh), Pawn's text is stripped but would never be re-added
        -- if we blocked indefinitely on the same link.
        local now = GetTime()
        if itemLink and lastProcessedLink[TooltipName] == itemLink
            and (now - (lastProcessedTime[TooltipName] or 0)) < DEDUP_WINDOW then
            return
        end
        lastProcessedLink[TooltipName] = itemLink
        lastProcessedTime[TooltipName] = now
        return origUpdate(TooltipName, MethodName, Param1, ...)
    end)

    -- Clear on tooltip hide (GameTooltip + shopping comparison tooltips)
    local function HookTooltipClear(tip, name)
        if not tip then return end
        hooksecurefunc(tip, "Hide", function()
            lastProcessedLink[name] = nil
            lastProcessedTime[name] = nil
        end)
    end

    HookTooltipClear(GameTooltip, "GameTooltip")
    HookTooltipClear(ShoppingTooltip1, "ShoppingTooltip1")
    HookTooltipClear(ShoppingTooltip2, "ShoppingTooltip2")
end

------------------------------------------------------------------------
-- 3. Pawn_upgradeCache
--
-- PawnIsItemAnUpgrade(Item) calls PawnGetItemDataForInventorySlot for
-- every equipped slot, for every enabled scale, on every tooltip show.
-- This is extremely expensive when multiple scales are active.
--
-- Fix: Cache the result per item link and invalidate when the player's
-- equipped items change (UNIT_INVENTORY_CHANGED, PLAYER_EQUIPMENT_CHANGED).
------------------------------------------------------------------------
ns.patches["Pawn_upgradeCache"] = function()
    if not PawnIsItemAnUpgrade then return end

    local upgradeCache = {}

    local origIsUpgrade = PawnIsItemAnUpgrade
    rawset(_G, "PawnIsItemAnUpgrade", function(Item, DoNotRescan)
        if not Item or not Item.Link then
            return origIsUpgrade(Item, DoNotRescan)
        end

        local cached = upgradeCache[Item.Link]
        if cached ~= nil then
            if cached == false then return nil end
            return unpack(cached)
        end

        local result = { origIsUpgrade(Item, DoNotRescan) }

        -- Only cache definitive results. When DoNotRescan is true and result
        -- is nil, Pawn means "best-items data not computed yet" - a temporary
        -- state that should not be permanently cached as "not an upgrade".
        if #result > 0 and result[1] ~= nil then
            upgradeCache[Item.Link] = result
        elseif not DoNotRescan then
            -- nil result with DoNotRescan=false is definitive (no upgrade)
            upgradeCache[Item.Link] = false
        end

        return unpack(result)
    end)

    -- Invalidate cache when equipped items change
    local invalidator = CreateFrame("Frame")
    invalidator:RegisterEvent("UNIT_INVENTORY_CHANGED")
    invalidator:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    invalidator:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_EQUIPMENT_CHANGED" or arg1 == "player" then
            wipe(upgradeCache)
        end
    end)

    -- Invalidate when Pawn recalculates (scale changes, stat edits, etc.)
    -- PawnResetTooltips is called by PawnSetStatValue, PawnSetScaleNormalizationFactor,
    -- PawnSetUpgradeTracking, and other paths that change how upgrades are evaluated.
    if PawnResetTooltips then
        local origReset = PawnResetTooltips
        rawset(_G, "PawnResetTooltips", function(...)
            wipe(upgradeCache)
            return origReset(...)
        end)
    end

    -- Also clear when Pawn does a full cache wipe (e.g. debug toggle)
    if PawnClearCache then
        local origClear = PawnClearCache
        rawset(_G, "PawnClearCache", function(...)
            wipe(upgradeCache)
            return origClear(...)
        end)
    end
end
