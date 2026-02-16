------------------------------------------------------------------------
-- PatchWerk - Performance patches for Cell (Raid Frames)
--
-- Cell is a popular raid frame addon with a custom indicator system.
-- On TBC Classic Anniversary, several functions in the aura processing
-- hot path are called redundantly with identical arguments:
--   1. Cell_debuffOrderMemo      - Memoize GetDebuffOrder last-call result
--   2. Cell_customIndicatorGuard - Skip UpdateCustomIndicators when no
--                                  custom indicators are configured
--   3. Cell_debuffGlowMemo       - Memoize GetDebuffGlow last-call result
------------------------------------------------------------------------

local _, ns = ...

local pairs = pairs

------------------------------------------------------------------------
-- 1. Cell_debuffOrderMemo
--
-- Cell.iFuncs.GetDebuffOrder(spellName, spellId, count) is called for
-- every debuff on every unit frame during aura updates.  The same
-- (spellId, count) pair often hits twice in succession: once from the
-- debuff iteration and once from the raid debuff check.  The function
-- does a table lookup in currentAreaDebuffs and a condition check.
--
-- Fix: Memoize the last call's arguments and result.  If the next call
-- has the same (spellId, count) pair, return the cached result.  This
-- is a last-call cache, not a full cache, so no invalidation needed.
------------------------------------------------------------------------
ns.patches["Cell_debuffOrderMemo"] = function()
    if not Cell or not Cell.iFuncs then return end
    if not Cell.iFuncs.GetDebuffOrder then return end

    local orig = Cell.iFuncs.GetDebuffOrder
    local lastId, lastCount, lastResult

    Cell.iFuncs.GetDebuffOrder = function(spellName, spellId, count)
        if spellId == lastId and count == lastCount then
            return lastResult
        end
        lastId = spellId
        lastCount = count
        lastResult = orig(spellName, spellId, count)
        return lastResult
    end
end

------------------------------------------------------------------------
-- 2. Cell_customIndicatorGuard
--
-- Cell.iFuncs.UpdateCustomIndicators is called for every aura on every
-- unit frame update.  When no custom indicators are configured (the
-- common case for many users), the function iterates an empty table
-- via pairs() on every call.  The overhead is the function call itself
-- plus the pairs() setup and the inner guard checks.
--
-- Fix: On the first actual call (deferred so Cell is fully initialized),
-- check Cell.snippetVars.enabledIndicators for custom indicators.
-- If none exist, replace with a permanent no-op.  If custom indicators
-- are found, restore the original function permanently.  This avoids
-- the timing risk of checking at ADDON_LOADED before Cell populates
-- its indicator tables.
--
-- NOTE: Uses the Classic calling convention (individual args, not
-- auraInfo struct) since this targets TBC Classic Anniversary.
------------------------------------------------------------------------
ns.patches["Cell_customIndicatorGuard"] = function()
    if not Cell or not Cell.iFuncs then return end
    if not Cell.iFuncs.UpdateCustomIndicators then return end

    local orig = Cell.iFuncs.UpdateCustomIndicators

    -- Deferred check: resolve on first call when Cell is fully initialized
    Cell.iFuncs.UpdateCustomIndicators = function(...)
        local hasCustom = false
        if Cell.snippetVars and Cell.snippetVars.enabledIndicators then
            for name in pairs(Cell.snippetVars.enabledIndicators) do
                if type(name) == "string" and name:find("^indicator") then
                    hasCustom = true
                    break
                end
            end
        end
        if hasCustom then
            -- Custom indicators found - restore original permanently
            Cell.iFuncs.UpdateCustomIndicators = orig
            return orig(...)
        end
        -- No custom indicators - install permanent no-op
        Cell.iFuncs.UpdateCustomIndicators = function() end
    end
end

------------------------------------------------------------------------
-- 3. Cell_debuffGlowMemo
--
-- Cell.iFuncs.GetDebuffGlow(spellName, spellId, count) is called
-- immediately after GetDebuffOrder with the same arguments when a raid
-- debuff is found.  It performs the same currentAreaDebuffs lookup plus
-- a glowCondition check.
--
-- Fix: Same last-call memoization pattern as GetDebuffOrder.
------------------------------------------------------------------------
ns.patches["Cell_debuffGlowMemo"] = function()
    if not Cell or not Cell.iFuncs then return end
    if not Cell.iFuncs.GetDebuffGlow then return end

    local orig = Cell.iFuncs.GetDebuffGlow
    local lastId, lastCount, lastGlowType, lastGlowOpts

    Cell.iFuncs.GetDebuffGlow = function(spellName, spellId, count)
        if spellId == lastId and count == lastCount then
            return lastGlowType, lastGlowOpts
        end
        lastId = spellId
        lastCount = count
        lastGlowType, lastGlowOpts = orig(spellName, spellId, count)
        return lastGlowType, lastGlowOpts
    end
end
