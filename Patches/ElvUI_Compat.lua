------------------------------------------------------------------------
-- PatchWerk - TBC Classic Anniversary compatibility patches for ElvUI
--
-- ElvUI references several Blizzard APIs that don't exist in TBC
-- Classic Anniversary.  These patches provide safe fallbacks:
--   1. ElvUI_addonManagerCompat  - Addon manager skin protection
--   2. ElvUI_containerCompat     - Bag/container API fallbacks
--   3. ElvUI_lootHistoryCompat   - Loot history API stub
--   4. ElvUI_socketInfoCompat    - Socket info API stub
--   5. ElvUI_communitiesGuard    - Communities frame nil guard
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_addonManagerCompat", label = "Addon Manager Fix",
    help = "Prevents the addon manager skin from breaking when ElvUI tries to use functions that don't exist on TBC Classic.",
    detail = "ElvUI's addon manager skin was written for Retail WoW and references functions that may not be available in certain load-order edge cases on TBC Classic Anniversary. If the skin fails, it throws errors every time you open the addon list. This fix wraps the skin in a safety net so any failure is silently caught -- the addon list still works fine, just without the ElvUI visual styling.",
    impact = "FPS", impactLevel = "High", category = "Compatibility",
    estimate = "Prevents addon manager errors",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_containerCompat", label = "Bag Skin Fix",
    help = "Ensures ElvUI's bag skin can find the container and item functions it needs on TBC Classic.",
    detail = "ElvUI's bag skin references several container and item functions that only exist in Retail WoW. On TBC Classic Anniversary, these functions live under different names. This fix bridges the gap so ElvUI's bag skin can find what it needs, preventing errors when you open your bags.",
    impact = "FPS", impactLevel = "High", category = "Compatibility",
    estimate = "Prevents bag-related errors",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_lootHistoryCompat", label = "Loot History Fix",
    help = "Provides a safe stand-in for the loot history system that doesn't exist in TBC Classic.",
    detail = "ElvUI's loot skin tries to read from a loot history system that only exists in Retail WoW. On TBC Classic Anniversary, this system is completely absent, causing errors whenever ElvUI tries to skin the loot window. This fix provides a harmless stand-in that returns empty results, so ElvUI's loot skin loads without errors.",
    impact = "FPS", impactLevel = "Medium", category = "Compatibility",
    estimate = "Prevents loot window errors",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_socketInfoCompat", label = "Socket Info Fix",
    help = "Provides a safe stand-in for the gem socket system that doesn't exist in TBC Classic.",
    detail = "ElvUI's socket window skin tries to read socket type information from a system that only exists in Retail WoW. On TBC Classic Anniversary, this causes errors when ElvUI tries to skin the gem socketing window. This fix provides a harmless stand-in that returns empty results.",
    impact = "FPS", impactLevel = "Low", category = "Compatibility",
    estimate = "Prevents socket window errors",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_communitiesGuard", label = "Communities Skin Guard",
    help = "Prevents errors from ElvUI trying to skin a Communities window that doesn't exist in TBC Classic.",
    detail = "ElvUI tries to apply visual styling to the Communities and Guild Finder windows, but these windows don't exist in TBC Classic Anniversary. Without this fix, ElvUI throws errors when it tries to style something that isn't there. This fix checks whether the windows exist before attempting to style them.",
    impact = "FPS", impactLevel = "Low", category = "Compatibility",
    estimate = "Prevents communities skin errors",
})

local pcall = pcall
local type = type
local select = select
local unpack = unpack
local GetItemInfo = GetItemInfo

------------------------------------------------------------------------
-- 1. ElvUI_addonManagerCompat
--
-- ElvUI/Game/TBC/Skins/AddonManager.lua line 8 captures a local
-- reference to C_AddOns.GetAddOnInfo at file parse time.  While
-- !PatchWerk's Shims.lua provides C_AddOns (and loads first via the
-- "!" prefix), certain load-order edge cases or delayed skin
-- initialisation can still cause the addon manager skin to fail.
--
-- Fix: Ensure C_AddOns is fully populated as a safety net, then wrap
-- the ElvUI skin function in a protected call.  If the skin errors,
-- the addon list still works -- just without ElvUI's visual styling.
------------------------------------------------------------------------
ns.patches["ElvUI_addonManagerCompat"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    if not E or not E.private then return end

    local S = E:GetModule("Skins", true)
    if not S then return end

    -- Ensure C_AddOns has all the functions ElvUI expects
    if not C_AddOns then
        C_AddOns = {
            GetAddOnInfo    = GetAddOnInfo,
            GetNumAddOns    = GetNumAddOns,
            EnableAddOn     = EnableAddOn,
            DisableAddOn    = DisableAddOn,
            IsAddOnLoaded   = IsAddOnLoaded,
        }
    end

    -- Wrap the addon manager skin with crash protection
    local original = S.AddonManager or S.Skin_AddonManager
    if not original then return end

    local methodName = S.AddonManager and "AddonManager" or "Skin_AddonManager"

    S[methodName] = function(self, ...)
        local ok, err = pcall(original, self, ...)
        if not ok then
            -- Skin failure is cosmetic only; the addon list still works
        end
    end
end

------------------------------------------------------------------------
-- 2. ElvUI_containerCompat
--
-- ElvUI/Game/TBC/Skins/Bags.lua lines 9-12 capture local references
-- to C_Container.ContainerIDToInventoryID, C_Container.GetContainerNumFreeSlots,
-- C_Container.GetContainerItemLink, and C_Item.GetItemQualityByID at
-- file parse time.  While !PatchWerk's Shims.lua provides these, this
-- patch acts as a safety net to ensure every function ElvUI expects
-- is present with a working fallback.
--
-- Fix: Fill in any gaps in C_Container and C_Item with the classic
-- global equivalents.  This runs at PLAYER_LOGIN time, which is after
-- all files have been parsed but before ElvUI's skin functions execute.
------------------------------------------------------------------------
ns.patches["ElvUI_containerCompat"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    if not E then return end

    local S = E:GetModule("Skins", true)
    if not S then return end

    -- Ensure C_Container exists with all functions ElvUI's bag skin needs
    if not C_Container then
        C_Container = {}
    end
    if not C_Container.ContainerIDToInventoryID and ContainerIDToInventoryID then
        C_Container.ContainerIDToInventoryID = ContainerIDToInventoryID
    end
    if not C_Container.GetContainerNumFreeSlots and GetContainerNumFreeSlots then
        C_Container.GetContainerNumFreeSlots = GetContainerNumFreeSlots
    end
    if not C_Container.GetContainerItemLink and GetContainerItemLink then
        C_Container.GetContainerItemLink = GetContainerItemLink
    end

    -- Ensure C_Item exists with the quality lookup ElvUI uses
    if not C_Item then
        C_Item = {}
    end
    if not C_Item.GetItemQualityByID then
        C_Item.GetItemQualityByID = function(itemID)
            if not itemID then return nil end
            local _, _, quality = GetItemInfo(itemID)
            return quality
        end
    end
end

------------------------------------------------------------------------
-- 3. ElvUI_lootHistoryCompat
--
-- ElvUI/Game/TBC/Skins/Loot.lua lines 17-18 reference
-- C_LootHistory.GetNumItems and C_LootHistory.GetItem.  The loot
-- history system does not exist in TBC Classic Anniversary at all.
--
-- Fix: Provide a stub C_LootHistory with no-op functions that return
-- safe empty values.  ElvUI's loot skin will see zero history items
-- and skip the history-related skinning gracefully.
------------------------------------------------------------------------
ns.patches["ElvUI_lootHistoryCompat"] = function()
    if not ElvUI then return end

    if not C_LootHistory then
        C_LootHistory = {
            GetNumItems = function() return 0 end,
            GetItem     = function() return nil end,
        }
    end
end

------------------------------------------------------------------------
-- 4. ElvUI_socketInfoCompat
--
-- ElvUI/Game/TBC/Skins/Socket.lua line 8 references
-- C_ItemSocketInfo.GetSocketTypes which does not exist in TBC Classic
-- Anniversary.
--
-- Fix: Provide a stub C_ItemSocketInfo with a GetSocketTypes function
-- that returns an empty table.  ElvUI's socket skin will see no
-- socket type data and skip socket-type-specific styling gracefully.
------------------------------------------------------------------------
ns.patches["ElvUI_socketInfoCompat"] = function()
    if not ElvUI then return end

    if not C_ItemSocketInfo then
        C_ItemSocketInfo = {
            GetSocketTypes = function()
                return {}
            end,
        }
    end
end

------------------------------------------------------------------------
-- 5. ElvUI_communitiesGuard
--
-- ElvUI/Game/TBC/Skins/Communities.lua skins CommunitiesFrame and
-- ClubFinderGuildFinderFrame, neither of which exist in TBC Classic
-- Anniversary.  When ElvUI's skin function runs, it attempts to
-- access fields on these nil frames and throws errors.
--
-- Fix: Wrap the Communities skin function to check whether
-- CommunitiesFrame exists before running.  If the frame is absent,
-- the skin is silently skipped.  If the frame somehow exists but the
-- skin errors for another reason, the error is caught safely.
------------------------------------------------------------------------
ns.patches["ElvUI_communitiesGuard"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    if not E then return end

    local S = E:GetModule("Skins", true)
    if not S then return end

    if not S.Communities then return end

    local original = S.Communities

    S.Communities = function(self, ...)
        -- The Communities window doesn't exist in TBC Classic Anniversary
        if not _G.CommunitiesFrame then return end

        local ok, err = pcall(original, self, ...)
        if not ok then
            -- Skin failure is cosmetic only
        end
    end
end
