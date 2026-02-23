------------------------------------------------------------------------
-- PatchWerk - GCD detection fix for HazeCooldowns (Cooldown Text)
--
-- HazeCooldowns uses spell ID 61304 for GCD detection, but that
-- spell does not exist in TBC Classic Anniversary.  This means
-- GetSpellCooldown(61304) always returns nil, gcdDuration stays 0,
-- and IsGCD() always returns false.
--
-- The addon's secondary safety net (duration < 2s filter) catches
-- most GCD-only cooldowns, but it also suppresses legitimate short
-- cooldowns (e.g. Arcane Explosion).  With a working IsGCD(), only
-- actual GCD swipes are hidden while real short cooldowns are kept.
--
-- Fix: replace the spell ID with a per-class rank-1 spell that every
-- character knows and that triggers the GCD.
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch: Fix GCD Spell ID
------------------------------------------------------------------------
ns:RegisterPatch("HazeCooldowns", {
    key = "HazeCooldowns_gcdSpellFix",
    label = "Fix GCD Detection",
    help = "Replace invalid GCD spell ID with a class-appropriate spell",
    detail = "HazeCooldowns uses spell 61304 for GCD detection, which doesn't exist in TBC Classic. GetSpellCooldown() returns nil and IsGCD() always fails. This patch sets a per-class rank-1 spell so GCD detection works correctly, preventing false cooldown text on GCD-only abilities.",
    impact = "FPS",
    impactLevel = "Low",
    category = "fixes",
})

ns.patches["HazeCooldowns_gcdSpellFix"] = function()
    if not ns:IsAddonLoaded("HazeCooldowns") then return end

    local addon = _G.HazeCooldowns
    if not addon then return end

    -- Per-class rank-1 spells: no cooldown of their own, trigger the GCD,
    -- and every character of that class knows them by max level.
    local CLASS_GCD_SPELLS = {
        WARRIOR = 6673,  -- Battle Shout
        PALADIN = 635,   -- Holy Light
        HUNTER  = 1978,  -- Serpent Sting
        ROGUE   = 1752,  -- Sinister Strike
        PRIEST  = 585,   -- Smite
        SHAMAN  = 403,   -- Lightning Bolt
        MAGE    = 133,   -- Fireball
        WARLOCK = 686,   -- Shadow Bolt
        DRUID   = 5176,  -- Wrath
    }

    local _, class = UnitClass("player")
    local gcdSpell = class and CLASS_GCD_SPELLS[class]

    if gcdSpell then
        addon.GCD_SPELL_ID = gcdSpell
    end
end
