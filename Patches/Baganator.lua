------------------------------------------------------------------------
-- PatchWerk - Performance patches for Baganator (Bags)
--
-- Baganator is a popular bag addon with category-based item layouts.
-- On TBC Classic Anniversary, several hot paths fire far more often
-- than necessary:
--   1. Baganator_itemLockFix      - Fast item lock lookups during moves
--   2. Baganator_sortThrottle     - Throttle sort/transfer retry loops
--   3. Baganator_buttonVisThrottle - Throttle modifier key visibility updates
--   4. Baganator_tooltipCache     - Remember tooltip scans across updates
--   5. Baganator_updateDebounce   - Combine rapid bag updates into one
------------------------------------------------------------------------

local _, ns = ...

-- Localize globals used in hot paths
local GetTime = GetTime
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local next = next
local C_Timer = C_Timer
local hooksecurefunc = hooksecurefunc
local GetContainerItemInfo = C_Container and C_Container.GetContainerItemInfo
local SetItemButtonDesaturated = SetItemButtonDesaturated

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("Baganator", {
    key = "Baganator_itemLockFix", label = "Item Lock Speedup",
    help = "Speeds up the item lock check when moving items between bag slots.",
    detail = "When you move an item, Baganator searches through every single button to find the matching bag slot -- twice per move. With 100+ items this adds up fast. The fix builds a quick lookup table so it finds the right button instantly instead of scanning the whole list.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~20-40% faster item moves",
})
ns:RegisterPatch("Baganator", {
    key = "Baganator_sortThrottle", label = "Sort Retry Throttle",
    help = "Reduces lag during bag sorting by spacing out retry attempts.",
    detail = "When sorting or transferring items, Baganator retries the operation on every single frame tick while waiting for items to unlock. Each retry copies all your bag data and re-sorts it. The fix spaces retries to a configurable interval (default 0.2 seconds) so the heavy work only runs 5 times per second instead of 60+.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~30-50% less lag during bag sorting",
})
ns:RegisterPatch("Baganator", {
    key = "Baganator_buttonVisThrottle", label = "Modifier Key Throttle",
    help = "Reduces lag from holding modifier keys with bags open.",
    detail = "Every time you press or release any modifier key (Shift, Ctrl, Alt), Baganator reparents all bag buttons to update their visibility. This fires on every keystroke, not just when bags are open. The fix limits these updates to a configurable interval (default 0.1 seconds) and ensures the final state is always applied.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "~10-30% less lag when holding modifier keys",
})
ns:RegisterPatch("Baganator", {
    key = "Baganator_tooltipCache", label = "Tooltip Scan Cache",
    help = "Remembers tooltip scan results so items don't need to be re-scanned on every bag update.",
    detail = "On Classic/TBC, tooltip scanning is the most expensive per-item operation. Baganator caches the result on each button, but throws it away on every bag update -- even if the item hasn't changed. The fix keeps a shared cache of tooltip results keyed by item link, so the same item is only scanned once.",
    impact = "Memory", impactLevel = "Medium", category = "Performance",
    estimate = "~20-40% faster bag updates",
})
ns:RegisterPatch("Baganator", {
    key = "Baganator_updateDebounce", label = "Bag Update Combiner",
    help = "Combines rapid bag updates into a single refresh instead of processing each one separately.",
    detail = "When you loot multiple items, buy from a vendor, or complete a quest, each bag slot fires its own update event. Baganator processes each one individually, running the full category pipeline every time. The fix waits a short configurable delay (default 0.05 seconds) and combines the burst into a single update.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~30-60% less lag during multi-item looting",
})

ns:RegisterDefault("Baganator_sortThrottleRate", 0.2)
ns:RegisterDefault("Baganator_buttonVisRate", 0.1)
ns:RegisterDefault("Baganator_updateDebounceRate", 0.05)

------------------------------------------------------------------------
-- 1. Baganator_itemLockFix
--
-- BaganatorLiveCategoryLayoutMixin.UpdateLockForItem scans every button
-- linearly to find the matching bagID/slotID pair.  ITEM_LOCK_CHANGED
-- fires twice per item move (pickup + putdown).  With 100+ items the
-- linear scan is wasteful.
--
-- Fix: Build an indexed lookup table keyed by [bagID][slotID].
-- Invalidate the index when buttons are rebuilt via ShowGroup.
------------------------------------------------------------------------
ns.patches["Baganator_itemLockFix"] = function()
    if not ns:IsAddonLoaded("Baganator") then return end
    if not BaganatorLiveCategoryLayoutMixin then return end

    local original = BaganatorLiveCategoryLayoutMixin.UpdateLockForItem

    BaganatorLiveCategoryLayoutMixin.UpdateLockForItem = function(self, bagID, slotID)
        if not self.buttons then return end

        -- Build or rebuild the lookup index when buttons change
        if not self._lockIndex or self._lockIndexCount ~= #self.buttons then
            -- Reuse existing tables instead of allocating new ones
            if self._lockIndex then
                for bID, inner in pairs(self._lockIndex) do
                    wipe(inner)
                end
                wipe(self._lockIndex)
            else
                self._lockIndex = {}
            end
            self._lockIndexCount = #self.buttons
            for _, btn in ipairs(self.buttons) do
                local bID = btn:GetParent():GetID()
                local sID = btn:GetID()
                if not self._lockIndex[bID] then
                    self._lockIndex[bID] = {}
                end
                self._lockIndex[bID][sID] = btn
            end
        end

        -- Direct lookup instead of scanning every button
        local bagLookup = self._lockIndex[bagID]
        if not bagLookup then return end

        local itemButton = bagLookup[slotID]
        if not itemButton then return end

        local info = GetContainerItemInfo(bagID, slotID)
        local locked = info and info.isLocked
        local grey = itemButton.BGR and itemButton.BGR.persistIconGrey
        SetItemButtonDesaturated(itemButton, locked or grey)
    end

    -- Invalidate the lookup when buttons get rebuilt (ShowGroup resets self.buttons)
    if BaganatorLiveCategoryLayoutMixin.ShowGroup then
        local origShowGroup = BaganatorLiveCategoryLayoutMixin.ShowGroup
        BaganatorLiveCategoryLayoutMixin.ShowGroup = function(self, ...)
            self._lockIndex = nil
            self._lockIndexCount = nil
            return origShowGroup(self, ...)
        end
    end
end

------------------------------------------------------------------------
-- 2. Baganator_sortThrottle
--
-- When sorting or transferring items, Baganator waits for item data or
-- lock release by running the retry function on every OnUpdate frame
-- tick.  Each retry does CopyTable on all bags, multiple tFilter passes,
-- and comparison sorting.
--
-- Fix: Wrap the OnUpdate handler with a throttle so retries only fire
-- at a configurable interval instead of every frame.
------------------------------------------------------------------------
local function WrapThrottle(originalApply, throttleRate)
    return function(self, status, ...)
        -- Let the original set up the handlers
        originalApply(self, status, ...)

        -- If an OnUpdate was set (waiting for data/unlock), replace with throttled version
        local currentOnUpdate = self:GetScript("OnUpdate")
        if currentOnUpdate then
            -- Reuse a single throttle handler per manager instance to avoid
            -- creating a new closure on every Apply call
            self._btThrottleTarget = currentOnUpdate
            self._btThrottleElapsed = 0

            if not self._btThrottleHandler then
                self._btThrottleHandler = function(s, dt)
                    s._btThrottleElapsed = s._btThrottleElapsed + dt
                    if s._btThrottleElapsed >= throttleRate then
                        s._btThrottleElapsed = 0
                        s._btThrottleTarget(s, dt)
                    end
                end
            end

            self:SetScript("OnUpdate", self._btThrottleHandler)
        end
    end
end

local function PatchSortFrame(frame, rate)
    if frame.sortManager and frame.sortManager.Apply and not frame.sortManager._btThrottled then
        frame.sortManager.Apply = WrapThrottle(frame.sortManager.Apply, rate)
        frame.sortManager._btThrottled = true
    end
    if frame.transferManager and frame.transferManager.Apply and not frame.transferManager._btThrottled then
        frame.transferManager.Apply = WrapThrottle(frame.transferManager.Apply, rate)
        frame.transferManager._btThrottled = true
    end
end

ns.patches["Baganator_sortThrottle"] = function()
    if not ns:IsAddonLoaded("Baganator") then return end

    local rate = ns:GetOption("Baganator_sortThrottleRate") or 0.2

    -- Only hook the leaf-level view mixins. The parent mixin
    -- (BaganatorItemViewCommonBackpackViewMixin) creates the managers
    -- in its OnLoad, but that is always called from within a child's
    -- OnLoad, so hooking the children is sufficient.
    local mixins = {
        BaganatorCategoryViewBackpackViewMixin,
        BaganatorSingleViewBackpackViewMixin,
    }

    for _, mixin in ipairs(mixins) do
        if mixin and mixin.OnLoad then
            local origOnLoad = mixin.OnLoad
            mixin.OnLoad = function(self, ...)
                origOnLoad(self, ...)
                PatchSortFrame(self, rate)
            end
        end
    end
end

------------------------------------------------------------------------
-- 3. Baganator_buttonVisThrottle
--
-- MODIFIER_STATE_CHANGED fires on every key press and release.
-- BaganatorItemViewButtonVisibilityMixin:Update iterates all bag
-- buttons and reparents them on each event.
--
-- Fix: Throttle the update to a configurable interval, with a trailing
-- timer to guarantee the final state is always applied.
------------------------------------------------------------------------
ns.patches["Baganator_buttonVisThrottle"] = function()
    if not ns:IsAddonLoaded("Baganator") then return end
    if not BaganatorItemViewButtonVisibilityMixin then return end

    local original = BaganatorItemViewButtonVisibilityMixin.Update

    -- Cache the rate once at patch time; only changes on /reload
    local rate = ns:GetOption("Baganator_buttonVisRate") or 0.1

    BaganatorItemViewButtonVisibilityMixin.Update = function(self)
        local now = GetTime()

        -- Per-instance state stored on the frame itself
        local lastUpdate = self._btVisLastUpdate or 0

        if now - lastUpdate >= rate then
            self._btVisLastUpdate = now
            original(self)
        elseif not self._btVisPendingTimer then
            -- Build a reusable callback once per instance to avoid
            -- allocating a new closure on every deferred schedule
            if not self._btVisTimerCallback then
                self._btVisTimerCallback = function()
                    self._btVisPendingTimer = nil
                    self._btVisLastUpdate = GetTime()
                    original(self)
                end
            end

            self._btVisPendingTimer = C_Timer.NewTimer(
                rate - (now - lastUpdate),
                self._btVisTimerCallback
            )
        end
    end

    -- Cancel any pending timer when the frame hides to avoid
    -- firing an update on a hidden frame (wasted work)
    hooksecurefunc(BaganatorItemViewButtonVisibilityMixin, "OnHide", function(self)
        if self._btVisPendingTimer then
            self._btVisPendingTimer:Cancel()
            self._btVisPendingTimer = nil
        end
    end)
end

------------------------------------------------------------------------
-- 4. Baganator_tooltipCache
--
-- On Classic/TBC, tooltip scanning (DumpClassicTooltip) is the most
-- expensive per-item operation.  Baganator caches it in BGR.tooltipInfo
-- but resets BGR on every SetItemDetails call.  This patch preserves
-- the cached tooltip when the underlying item hasn't changed.
--
-- Fix: Maintain a global cache keyed by itemLink and restore cached
-- tooltip data after SetItemDetails resets it.
------------------------------------------------------------------------
do
    -- Global tooltip cache shared across all buttons (scoped to this block)
    local tooltipCache = {}
    local cacheCount = 0
    local CACHE_MAX_SIZE = 500

    local function PruneTooltipCache()
        if cacheCount > CACHE_MAX_SIZE then
            wipe(tooltipCache)
            cacheCount = 0
        end
    end

    local function CacheStore(itemLink, tooltipInfo)
        if not tooltipCache[itemLink] then
            cacheCount = cacheCount + 1
        end
        tooltipCache[itemLink] = tooltipInfo
    end

    local function PatchItemButtonMixin(mixin)
        if not mixin or not mixin.SetItemDetails then return false end

        local original = mixin.SetItemDetails

        mixin.SetItemDetails = function(self, cacheData, ...)
            -- Save the current tooltip info and item link before the update
            local prevBGR = self.BGR
            local prevLink = prevBGR and prevBGR.itemLink
            local prevTooltip = prevBGR and prevBGR.tooltipInfo

            -- Store in global cache if we had valid data
            if prevLink and prevTooltip then
                CacheStore(prevLink, prevTooltip)
            end

            -- Run the original SetItemDetails (this resets BGR)
            original(self, cacheData, ...)

            -- Restore cached tooltip if the item is the same
            local newBGR = self.BGR
            if newBGR and newBGR.tooltipGetter then
                local currentLink = newBGR.itemLink or (cacheData and cacheData.itemLink)
                if currentLink then
                    local cached = tooltipCache[currentLink]
                    if cached then
                        newBGR.tooltipInfo = cached
                    end
                end
            end
        end

        return true
    end

    ns.patches["Baganator_tooltipCache"] = function()
        if not ns:IsAddonLoaded("Baganator") then return end

        local patched = false

        -- TBC Classic uses the Classic mixin
        local classicMixin = BaganatorClassicLiveContainerItemButtonMixin
        if classicMixin then
            patched = PatchItemButtonMixin(classicMixin) or patched
        end

        -- Retail uses the Retail mixin (not relevant for TBC, but safe to include)
        local retailMixin = BaganatorRetailLiveContainerItemButtonMixin
        if retailMixin then
            patched = PatchItemButtonMixin(retailMixin) or patched
        end

        if not patched then return end

        -- Prune the cache periodically
        C_Timer.NewTicker(60, PruneTooltipCache)
    end
end

------------------------------------------------------------------------
-- 5. Baganator_updateDebounce
--
-- When multiple bags update in quick succession (looting, vendor buys,
-- quest rewards), each bag fires a separate update event.  Each one
-- triggers UpdateForCharacter which runs the full category pipeline.
--
-- Fix: Debounce those calls so only the last one in a burst actually
-- triggers the pipeline.  Only debounces the leaf-level view mixins,
-- never the parent mixin which is called synchronously.
------------------------------------------------------------------------
local function WrapDebounce(mixin, methodName, rate)
    local original = mixin[methodName]
    if not original then return end

    mixin[methodName] = function(self, character, isLive)
        -- Skip debounce on first update or character change to avoid
        -- a visible empty bag frame on first open
        if not self._btDebounceReady or self.lastCharacter ~= character then
            self._btDebounceReady = true
            original(self, character, isLive)
            return
        end

        -- Store pending args directly on the frame - no table allocation
        self._btDebounceChar = character
        self._btDebounceIsLive = isLive

        if self._btDebounceTimer then
            self._btDebounceTimer:Cancel()
        end

        -- Create the callback once per frame instance and reuse it
        if not self._btDebounceCallback then
            self._btDebounceCallback = function()
                self._btDebounceTimer = nil
                local char = self._btDebounceChar
                if char then
                    local live = self._btDebounceIsLive
                    self._btDebounceChar = nil
                    self._btDebounceIsLive = nil
                    original(self, char, live)
                end
            end
        end

        self._btDebounceTimer = C_Timer.NewTimer(rate, self._btDebounceCallback)
    end

    -- Hook OnHide to cancel pending timers and reset state so the
    -- next open gets an immediate (non-debounced) first update
    if not mixin._btDebounceOnHideHooked then
        mixin._btDebounceOnHideHooked = true
        hooksecurefunc(mixin, "OnHide", function(self)
            if self._btDebounceTimer then
                self._btDebounceTimer:Cancel()
                self._btDebounceTimer = nil
            end
            self._btDebounceChar = nil
            self._btDebounceIsLive = nil
            self._btDebounceReady = nil
        end)
    end
end

ns.patches["Baganator_updateDebounce"] = function()
    if not ns:IsAddonLoaded("Baganator") then return end

    -- Cache rate at apply time; settings changes require /reload
    local rate = ns:GetOption("Baganator_updateDebounceRate") or 0.05

    -- Only debounce the leaf-level view mixins, not the parent
    if BaganatorCategoryViewBackpackViewMixin then
        WrapDebounce(BaganatorCategoryViewBackpackViewMixin, "UpdateForCharacter", rate)
    end

    if BaganatorSingleViewBackpackViewMixin then
        WrapDebounce(BaganatorSingleViewBackpackViewMixin, "UpdateForCharacter", rate)
    end
end
