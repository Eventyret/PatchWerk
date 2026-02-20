------------------------------------------------------------------------
-- PatchWerk - Performance patches for AtlasLootClassic (Loot Browser)
--
-- AtlasLootClassic is a comprehensive loot browser but has several
-- performance hot paths on TBC Classic Anniversary. These patches
-- address:
--   1. AtlasLootClassic_searchDebounce     - Debounce search box filtering
--   2. AtlasLootClassic_rosterDebounce     - Debounce version messages
--   3. AtlasLootClassic_searchLowerCache   - Cache lowercased item names
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("AtlasLootClassic", {
    key = "AtlasLootClassic_searchDebounce",
    label = "Search Box Debounce",
    help = "Adds a short delay before filtering items while you type in the search box.",
    detail = "Every single keypress triggers a full 30-button filter pass with string matching. Typing quickly causes dozens of unnecessary filter cycles. This adds a 150ms debounce so the filter only runs once you pause typing.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "Eliminates lag spikes when typing in the search box",
})
ns:RegisterPatch("AtlasLootClassic", {
    key = "AtlasLootClassic_rosterDebounce",
    label = "Version Message Throttle",
    help = "Prevents repeated version check messages when your raid roster changes quickly.",
    detail = "AtlasLootClassic sends an addon version message to the raid on every single RAID_ROSTER_UPDATE event. During raid formation or when multiple people join or leave, this can fire dozens of times in seconds. This adds a 5-second cooldown per channel.",
    impact = "Network", impactLevel = "Medium", category = "Performance",
    estimate = "Reduces message spam during raid formation",
})
ns:RegisterPatch("AtlasLootClassic", {
    key = "AtlasLootClassic_searchLowerCache",
    label = "Search Name Cache",
    help = "Caches lowercased item names so the search filter doesn't recalculate them every keypress.",
    detail = "The search filter converts every button name to lowercase each time you type a character. With 30 buttons, that is 30 repeated conversions per keypress that always produce the same result. The fix remembers the converted names so they are only done once per page.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "Smoother search with less memory churn",
})

local GetTime = GetTime

------------------------------------------------------------------------
-- 1. AtlasLootClassic_searchDebounce
--
-- ItemFrame.OnSearchTextChanged is called on every keypress in the
-- search box.  Each call triggers UpdateFilter() which iterates all
-- 30 buttons with string matching.
--
-- Fix: Replace with a 150ms debounced version using C_Timer.After.
------------------------------------------------------------------------
ns.patches["AtlasLootClassic_searchDebounce"] = function()
    if not AtlasLoot then return end
    local ItemFrame = AtlasLoot.GUI and AtlasLoot.GUI.ItemFrame
    if not ItemFrame then return end
    if not ItemFrame.OnSearchTextChanged then return end

    local pendingTimer = nil

    local origOnSearchTextChanged = ItemFrame.OnSearchTextChanged
    ItemFrame.OnSearchTextChanged = function(msg)
        if pendingTimer then
            pendingTimer:Cancel()
            pendingTimer = nil
        end
        pendingTimer = C_Timer.NewTimer(0.15, function()
            pendingTimer = nil
            origOnSearchTextChanged(msg)
        end)
    end
end

------------------------------------------------------------------------
-- 2. AtlasLootClassic_rosterDebounce
--
-- AtlasLoot.SendAddonVersion is called from RAID_ROSTER_UPDATE with
-- channel "RAID", and from GROUP_JOINED with "RAID" and "PARTY".
-- During raid formation, RAID_ROSTER_UPDATE fires rapidly -- every
-- join, leave, role change, etc.
--
-- Fix: Add a per-channel cooldown of 5 seconds so only the first
-- call in each burst window actually sends.
------------------------------------------------------------------------
ns.patches["AtlasLootClassic_rosterDebounce"] = function()
    if not AtlasLoot then return end
    if not AtlasLoot.SendAddonVersion then return end

    local origSend = AtlasLoot.SendAddonVersion
    local lastSent = {}

    AtlasLoot.SendAddonVersion = function(channel, target)
        if not channel then return origSend(channel, target) end

        local key = channel .. (target or "")
        local now = GetTime()
        if lastSent[key] and (now - lastSent[key]) < 5 then
            return
        end
        lastSent[key] = now
        return origSend(channel, target)
    end
end

------------------------------------------------------------------------
-- 3. AtlasLootClassic_searchLowerCache
--
-- UpdateFilterItem calls string.lower on button.RawName or
-- button.name:GetText() for every button on every filter pass.
-- With 30 buttons and rapid typing, that is many allocations.
--
-- Fix: Hook ItemFrame.Refresh to pre-cache lowered names on each
-- button as button._pwLowerName, then wrap UpdateFilterItem to
-- use the cached value.
------------------------------------------------------------------------
ns.patches["AtlasLootClassic_searchLowerCache"] = function()
    if not AtlasLoot then return end
    local ItemFrame = AtlasLoot.GUI and AtlasLoot.GUI.ItemFrame
    if not ItemFrame then return end
    if not ItemFrame.Refresh then return end
    if not ItemFrame.UpdateFilterItem then return end

    local slower = string.lower

    -- Hook Refresh to cache lowered names after buttons are populated
    local origRefresh = ItemFrame.Refresh
    ItemFrame.Refresh = function(self, ...)
        origRefresh(self, ...)
        -- Cache lowered names for each button
        if self.frame and self.frame.ItemButtons then
            for i = 1, 30 do
                local button = self.frame.ItemButtons[i]
                if button then
                    local text = button.RawName
                    if not text and button.name then
                        text = button.name:GetText()
                    end
                    button._pwLowerName = text and slower(text) or nil
                end
            end
        end
    end

    -- Wrap UpdateFilterItem to use cached lowered names
    local sfind = string.find
    local origUpdateFilterItem = ItemFrame.UpdateFilterItem
    ItemFrame.UpdateFilterItem = function(buttonID, reset)
        -- Only optimize if there is an active search string
        if not ItemFrame.SearchString then
            return origUpdateFilterItem(buttonID, reset)
        end

        local button = ItemFrame.frame and (ItemFrame.frame.ItemButtons[buttonID] or buttonID)
        if not button then return origUpdateFilterItem(buttonID, reset) end

        -- Use cached lower name if available
        if button._pwLowerName then
            -- Run the original for class filter portion
            local origSearch = ItemFrame.SearchString
            ItemFrame.SearchString = nil
            reset = origUpdateFilterItem(buttonID, reset)
            ItemFrame.SearchString = origSearch

            -- Apply search filter using cached name
            if not sfind(button._pwLowerName, ItemFrame.SearchString, 1, true) then
                button:SetAlpha(0.33)
            elseif reset then
                button:SetAlpha(1.0)
            end
            return false
        end

        return origUpdateFilterItem(buttonID, reset)
    end
end
