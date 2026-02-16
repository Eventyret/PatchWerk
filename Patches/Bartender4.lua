------------------------------------------------------------------------
-- AddonTweaks - Performance patches for Bartender4 (Action Bars)
--
-- Bartender4 uses LibActionButton-1.0 (LAB) to manage action bar buttons.
-- On TBC Classic Anniversary, two event-handling hot paths generate
-- significant CPU overhead with zero visual benefit:
--   1. Bartender4_lossOfControlSkip  - Skip LOSS_OF_CONTROL events that
--                                      are no-ops on TBC Classic
--   2. Bartender4_usableThrottle     - Debounce ACTIONBAR_UPDATE_USABLE
--                                      and SPELL_UPDATE_USABLE to avoid
--                                      per-button spam on every mana tick
------------------------------------------------------------------------

local _, ns = ...

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
