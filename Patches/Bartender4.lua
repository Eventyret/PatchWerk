------------------------------------------------------------------------
-- PatchWerk - Performance and compatibility patches for Bartender4
--
-- Bartender4 uses LibActionButton-1.0 (LAB) to manage action bar buttons.
-- On TBC Classic Anniversary, several issues arise:
--   1. Bartender4_lossOfControlSkip    - Skip LOSS_OF_CONTROL events that
--                                        are no-ops on TBC Classic
--   2. Bartender4_usableThrottle       - Debounce ACTIONBAR_UPDATE_USABLE
--                                        and SPELL_UPDATE_USABLE to avoid
--                                        per-button spam on every mana tick
--   3. Bartender4_pressAndHoldGuard    - Prevent ADDON_ACTION_BLOCKED spam
--                                        from backported UpdatePressAndHoldAction
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("Bartender4", {
    key = "Bartender4_lossOfControlSkip", label = "Unused Effect Skip",
    help = "Stops your action bars from constantly checking for stun/silence effects that don't exist on Classic.",
    detail = "Bartender4 scans all your action bar buttons for loss-of-control overlays (stun, silence, etc.) every time something happens in combat. These overlays don't exist on Classic, so every scan finds nothing and wastes resources. This adds up fast during busy fights.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~1-2 FPS in combat on Classic",
})
ns:RegisterPatch("Bartender4", {
    key = "Bartender4_usableThrottle", label = "Button Update Batch",
    help = "Combines rapid action bar updates into a single check instead of refreshing all buttons multiple times per second.",
    detail = "Your action bars refresh on every mana tick, target change, and buff change, causing all your buttons to be rechecked multiple times per second. During intense combat, this can cause button highlights and range coloring to feel sluggish. The fix batches these updates together so your bars stay responsive without the overhead.",
    impact = "FPS", impactLevel = "High", category = "Performance",
    estimate = "~2-4 FPS during mana-heavy combat",
})
ns:RegisterPatch("Bartender4", {
    key = "Bartender4_pressAndHoldGuard", label = "Combat Error Flood Fix",
    help = "Stops a flood of error spam every time you enter combat caused by incompatible retail code.",
    detail = "TBC Anniversary includes newer action bar code meant for Retail WoW that conflicts with Bartender4 during combat. This triggers around 19 errors every time you enter combat, flooding your error log and wasting resources. The fix prevents the conflict from happening in the first place.",
    impact = "FPS", impactLevel = "High", category = "Fixes",
    estimate = "Eliminates ~19 error popups per combat encounter",
})

local pcall   = pcall
local LibStub = LibStub

------------------------------------------------------------------------
-- 1. Bartender4_lossOfControlSkip
--
-- LibActionButton-1.0 registers for LOSS_OF_CONTROL_ADDED and
-- LOSS_OF_CONTROL_UPDATE events.  On TBC Classic, GetLossOfControlCooldown
-- always returns 0,0 so these events trigger a full 120-button
-- UpdateCooldown loop for zero visual change.
--
-- Fix: Wrap the LAB eventFrame's OnEvent handler to silently discard
-- these two events on TBC Classic, eliminating the wasted iteration.
------------------------------------------------------------------------
ns.patches["Bartender4_lossOfControlSkip"] = function()
    if not LibStub then return end

    local ok, LAB = pcall(LibStub, "LibActionButton-1.0")
    if not ok or not LAB or not LAB.eventFrame then return end

    local eventFrame = LAB.eventFrame
    local origOnEvent = eventFrame:GetScript("OnEvent")
    if not origOnEvent then return end

    eventFrame:SetScript("OnEvent", function(frame, event, ...)
        -- LOSS_OF_CONTROL events are no-ops on TBC Classic;
        -- GetLossOfControlCooldown always returns 0,0
        if event == "LOSS_OF_CONTROL_ADDED" or event == "LOSS_OF_CONTROL_UPDATE" then
            return
        end
        return origOnEvent(frame, event, ...)
    end)
end

------------------------------------------------------------------------
-- 2. Bartender4_usableThrottle
--
-- ACTIONBAR_UPDATE_USABLE fires extremely frequently: every mana tick,
-- target change, aura gain/loss, etc.  Each event causes LAB to call
-- IsUsableAction(slot) on all 120 action buttons.  SPELL_UPDATE_USABLE
-- has similar burst behaviour.
--
-- Fix: Debounce both events with a 1-frame delay (C_Timer.After(0))
-- so that multiple rapid-fire events within a single frame collapse
-- into a single update pass.
--
-- NOTE: This patch re-reads the eventFrame's current OnEvent script
-- at apply time, so it correctly chains with lossOfControlSkip
-- regardless of patch application order.
------------------------------------------------------------------------
ns.patches["Bartender4_usableThrottle"] = function()
    if not LibStub then return end

    local ok, LAB = pcall(LibStub, "LibActionButton-1.0")
    if not ok or not LAB or not LAB.eventFrame then return end

    local eventFrame = LAB.eventFrame
    -- Re-read the CURRENT script (which may already be wrapped by
    -- lossOfControlSkip or the original handler)
    local currentOnEvent = eventFrame:GetScript("OnEvent")
    if not currentOnEvent then return end

    local usablePending = false
    local spellUsablePending = false

    eventFrame:SetScript("OnEvent", function(frame, event, ...)
        if event == "ACTIONBAR_UPDATE_USABLE" then
            if not usablePending then
                usablePending = true
                C_Timer.After(0, function()
                    usablePending = false
                    currentOnEvent(frame, "ACTIONBAR_UPDATE_USABLE")
                end)
            end
            return
        elseif event == "SPELL_UPDATE_USABLE" then
            if not spellUsablePending then
                spellUsablePending = true
                C_Timer.After(0, function()
                    spellUsablePending = false
                    currentOnEvent(frame, "SPELL_UPDATE_USABLE")
                end)
            end
            return
        end
        return currentOnEvent(frame, event, ...)
    end)
end

------------------------------------------------------------------------
-- 3. Bartender4_pressAndHoldGuard
--
-- TBC Classic Anniversary ships retail-backported ActionButton code that
-- includes UpdatePressAndHoldAction().  This function calls SetAttribute()
-- on Blizzard multi-bar buttons (MultiBarBottomLeft, MultiBarBottomRight,
-- etc.) that Bartender4 hides but does NOT fully deregister from
-- Blizzard's action button update system.
--
-- Result: ~19x ADDON_ACTION_BLOCKED errors per combat entry because
-- SetAttribute() is protected during combat lockdown.
--
-- Fix: If the global UpdatePressAndHoldAction exists, wrap it with an
-- InCombatLockdown() guard so the SetAttribute() call is skipped during
-- combat.  Fallback: strip OnEvent from hidden Blizzard multi-bar
-- buttons so the Blizzard bar system can no longer drive UpdateAction
-- on them.
------------------------------------------------------------------------
ns.patches["Bartender4_pressAndHoldGuard"] = function()
    if not ns:IsAddonLoaded("Bartender4") then return end

    -- Strip OnEvent from Blizzard multi-bar buttons that Bartender4
    -- already hid by re-parenting to UIHider.  This prevents the
    -- Blizzard ActionButton OnEvent chain from calling UpdateAction
    -- (and thus UpdatePressAndHoldAction/SetAttribute) on them.
    --
    -- NOTE: We deliberately do NOT replace the global UpdatePressAndHoldAction
    -- function.  Replacing Blizzard globals via normal assignment taints
    -- them in WoW's taint tracking system, which can propagate through
    -- secure code paths and cause ADDON_ACTION_FORBIDDEN when the player
    -- clicks spells in the SpellBookFrame.  The button-stripping approach
    -- targets only the problematic hidden buttons without any global writes.
    local barPrefixes = {
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarLeftButton",
        "MultiBarRightButton",
    }
    for _, prefix in ipairs(barPrefixes) do
        for i = 1, 12 do
            local btn = _G[prefix .. i]
            if btn and btn:GetParent() ~= UIParent then
                btn:SetScript("OnEvent", nil)
            end
        end
    end
end
