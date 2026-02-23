------------------------------------------------------------------------
-- PatchWerk - Fast auto-loot for HazeLoot (Loot Frame)
--
-- HazeLoot always shows its custom loot frame, even when WoW's
-- auto-loot is active.  This causes the frame to flash briefly
-- while items are being taken.
--
-- This patch hooks HazeLootFrame:Update() to detect auto-loot state.
-- When auto-loot is active, items are looted instantly without showing
-- the frame.  Manual loot (shift-click) still shows HazeLoot normally.
--
-- Master loot is always passed through untouched -- the loot frame is
-- shown regardless of auto-loot state so the master looter can
-- distribute items.
------------------------------------------------------------------------

local _, ns = ...

-- Cache globals
local GetCVar = GetCVar
local GetNumLootItems = GetNumLootItems
local GetLootMethod = GetLootMethod
local IsModifiedClick = IsModifiedClick
local LootSlot = LootSlot
local C_Timer = C_Timer

------------------------------------------------------------------------
-- Patch: Fast Auto-Loot
------------------------------------------------------------------------
ns:RegisterPatch("HazeLoot", {
    key = "HazeLoot_fastAutoLoot",
    label = "Fast Auto-Loot",
    help = "Skip the loot frame when WoW auto-loot is active",
    detail = "When auto-loot is active (via CVar or modifier key), items are looted instantly without showing HazeLoot's frame. If some items fail to loot (full bags, BoP confirmation), the frame appears for the leftovers. Master loot windows always show the frame.",
    impact = "QOL",
    impactLevel = "Low",
    category = "tweaks",
})

ns.patches["HazeLoot_fastAutoLoot"] = function()
    if not ns:IsAddonLoaded("HazeLoot") then return end

    local frame = _G.HazeLootFrame
    if not frame then return end

    local origUpdate = frame.Update
    if not origUpdate then return end

    -- Detect whether WoW's auto-loot is currently active.
    -- Mirrors Plumber's logic:
    --   autoLootDefault=1 AND modifier NOT held  -> auto-loot
    --   autoLootDefault=0 AND modifier held       -> auto-loot
    local function IsAutoLootActive()
        local autoLootDefault = GetCVar("autoLootDefault") == "1"
        local modifierHeld = IsModifiedClick("AUTOLOOTTOGGLE")
        -- XOR: auto-loot is active when exactly one of these is true
        if autoLootDefault then
            return not modifierHeld
        else
            return modifierHeld
        end
    end

    frame.Update = function(self, noSnap, isRefresh)
        -- Always pass through refresh calls (HazeLoot's own retry logic)
        if isRefresh then
            return origUpdate(self, noSnap, isRefresh)
        end

        -- Never fast-loot during master loot -- always show the frame
        if GetLootMethod and GetLootMethod() == "master" then
            return origUpdate(self, noSnap, isRefresh)
        end

        -- Manual loot: show HazeLoot's frame as normal
        if not IsAutoLootActive() then
            return origUpdate(self, noSnap, isRefresh)
        end

        -- Auto-loot active: grab everything silently
        local numLoot = GetNumLootItems()
        if numLoot == 0 then return end

        for slot = numLoot, 1, -1 do
            LootSlot(slot)
        end

        -- Safety net: if items remain after a short delay (full bags,
        -- BoP confirmation, etc.), fall back to showing HazeLoot's frame
        C_Timer.After(0.3, function()
            if GetNumLootItems() > 0 then
                origUpdate(self, true, false)
            end
        end)
    end
end
