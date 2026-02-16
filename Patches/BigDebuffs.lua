------------------------------------------------------------------------
-- PatchWerk - Performance patches for BigDebuffs (Debuff Display)
--
-- BigDebuffs is an AceAddon that shows priority debuffs on unit frames
-- and nameplates.  On TBC Classic Anniversary, two hot paths in the
-- UNIT_AURA handler cause unnecessary overhead:
--   1. BigDebuffs_hiddenDebuffsHash - O(1) hidden debuff check instead
--                                     of linear tContains scan
--   2. BigDebuffs_attachFrameGuard  - Skip AttachUnitFrame when already
--                                     attached for the current unit
------------------------------------------------------------------------

local _, ns = ...

local pairs = pairs
local wipe  = wipe

------------------------------------------------------------------------
-- 1. BigDebuffs_hiddenDebuffsHash
--
-- Inside the 40-slot aura loop in UNIT_AURA, BigDebuffs calls
-- tContains(self.HiddenDebuffs, id) on every debuff slot that matches
-- a known spell.  tContains is a linear array scan (iterates with
-- pairs() checking value == searchValue).  With 40 aura slots checked
-- per event across multiple units, this adds up.
--
-- Fix: Replace the HiddenDebuffs array with a proxy table where each
-- hidden ID appears as both key and value.  tContains iterates
-- pairs(table) checking if v == searchValue, so having id = id entries
-- makes the existing tContains call find the match on the first
-- iteration for any hidden ID.
--
-- NOTE: On TBC Classic Anniversary, HiddenDebuffs is typically empty
-- (populated from BigDebuffs_Mainline.lua on retail).  The patch
-- gracefully skips when the table is empty.
------------------------------------------------------------------------
ns.patches["BigDebuffs_hiddenDebuffsHash"] = function()
    if not BigDebuffs then return end
    if not BigDebuffs.HiddenDebuffs then return end
    if not next(BigDebuffs.HiddenDebuffs) then return end

    local proxy = {}
    for _, id in pairs(BigDebuffs.HiddenDebuffs) do
        proxy[id] = id
    end
    BigDebuffs.HiddenDebuffs = proxy
end

------------------------------------------------------------------------
-- 2. BigDebuffs_attachFrameGuard
--
-- BigDebuffs:AttachUnitFrame(unit) is called at the top of every
-- UNIT_AURA event.  It iterates the full anchors table (9 frame
-- systems: Blizzard, ElvUI, NDui, Cell, etc.) to find and attach
-- the correct frame for the unit.  Each resolver function runs
-- multiple unit:match() calls.  Once attached, the frame reference
-- doesn't change until a full layout reset.
--
-- Fix: Track which units have been attached and skip the re-attach
-- call when the frame is already known.  Invalidate on
-- PLAYER_ENTERING_WORLD (full layout resets), and hook Refresh/Test
-- (profile changes and test mode toggling) to clear the cache.
------------------------------------------------------------------------
ns.patches["BigDebuffs_attachFrameGuard"] = function()
    if not BigDebuffs then return end
    if not BigDebuffs.AttachUnitFrame then return end
    if not BigDebuffs.UnitFrames then return end

    local orig = BigDebuffs.AttachUnitFrame
    local attached = {}

    BigDebuffs.AttachUnitFrame = function(self, unit)
        if attached[unit] and self.UnitFrames[unit] then
            return
        end
        orig(self, unit)
        if self.UnitFrames[unit] then
            attached[unit] = true
        end
    end

    -- Invalidate on zone transitions (full layout resets)
    local invalidator = CreateFrame("Frame")
    invalidator:RegisterEvent("PLAYER_ENTERING_WORLD")
    invalidator:SetScript("OnEvent", function()
        wipe(attached)
    end)

    -- Invalidate on profile changes and test mode toggling
    if BigDebuffs.Refresh then
        hooksecurefunc(BigDebuffs, "Refresh", function()
            wipe(attached)
        end)
    end
    if BigDebuffs.Test then
        hooksecurefunc(BigDebuffs, "Test", function()
            wipe(attached)
        end)
    end
end
