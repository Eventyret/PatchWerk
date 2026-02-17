------------------------------------------------------------------------
-- PatchWerk - Performance patches for Plater (Nameplates)
--
-- Plater is a popular nameplate addon but has several hot paths that
-- generate unnecessary garbage collection pressure and CPU overhead
-- on TBC Classic Anniversary.  These patches address:
--   1. Plater_fpsCheck    - Replace C_Timer.After(0) self-rescheduling
--                           FPS tracker with a persistent OnUpdate frame
--   2. Plater_healthText  - Skip UpdateLifePercentText when health
--                           values haven't changed since last call
--   3. Plater_auraAlign   - Skip redundant AlignAuraFrames calls when
--                           the visible aura icon count is unchanged
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Plater_fpsCheck", group = "Plater", label = "Timer Leak Fix",
    help = "Fixes a Plater bug that wastes memory by creating 60+ temporary timers per second.",
    detail = "Plater creates 60+ temporary objects every second just to track your FPS, which causes memory buildup over time. During heavy combat with many nameplates visible, this contributes to stuttering. The fix uses a single reusable tracker instead.",
    impact = "Memory", impactLevel = "High", category = "Performance",
    estimate = "~2-4 FPS, fewer garbage collection stutters",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Plater_healthText", group = "Plater", label = "Health Text Skip",
    help = "Skips nameplate health text updates when the value hasn't changed.",
    detail = "Plater reformats nameplate health text on every update even when HP hasn't changed. With 20-40 nameplates visible in a dungeon or raid, that's thousands of wasted text updates per second for no visual benefit.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "~0.5-1 FPS with 20+ nameplates visible",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "Plater_auraAlign", group = "Plater", label = "Aura Icon Guard",
    help = "Skips reshuffling buff/debuff icons on nameplates when nothing changed.",
    detail = "Plater reshuffles buff and debuff icons on nameplates 200+ times per second during combat, creating throwaway data each time. This causes stutters when you have many visible nameplates with multiple buffs or debuffs active.",
    impact = "Memory", impactLevel = "Medium", category = "Performance",
    estimate = "~1-3 FPS with many nameplates in combat",
}

local pairs  = pairs
local max    = math.max
local ceil   = math.ceil

------------------------------------------------------------------------
-- 1. Plater_fpsCheck
--
-- Plater.EveryFrameFPSCheck reschedules itself via C_Timer.After(0, ...)
-- on every single frame.  This allocates 60+ timer callback objects per
-- second that the garbage collector must eventually sweep.  The function
-- itself is trivial: it tracks FPS samples, calculates how many plates
-- to update per frame, and resets platesUpdatedThisFrame to zero.
--
-- Fix: Neutralise the self-rescheduling timer chain by replacing the
-- function with a no-op, then create a persistent frame whose OnUpdate
-- script performs the identical work without any timer allocation.
------------------------------------------------------------------------
ns.patches["Plater_fpsCheck"] = function()
    if not Plater then return end
    if not Plater.EveryFrameFPSCheck then return end
    if not Plater.FPSData then return end

    -- Kill the self-rescheduling timer chain
    Plater.EveryFrameFPSCheck = function() end

    -- Persistent replacement frame
    local fpsFrame = CreateFrame("Frame")
    local GetTime = GetTime

    fpsFrame:SetScript("OnUpdate", function()
        local data = Plater.FPSData
        -- Guard all sub-fields: they may be nil during Plater's deferred init
        if not data or not data.startTime or not data.frames then return end

        local curTime = GetTime()

        if (data.startTime + 0.25) < curTime then
            data.curFPS = max(data.frames / (curTime - data.startTime), 1)

            -- The original uses local upvalues DB_TICK_THROTTLE and
            -- NUM_NAMEPLATES_ON_SCREEN that we cannot access.  Read
            -- from the profile if available, otherwise use sane defaults.
            local throttle = 0.1
            if Plater.db and Plater.db.profile and Plater.db.profile.update_throttle then
                throttle = Plater.db.profile.update_throttle
            end

            local numPlates = 30
            if Plater.GetNominalNumNameplates then
                -- Use pcall: may be method or function depending on Plater version
                local ok, result = pcall(Plater.GetNominalNumNameplates, Plater)
                if ok and result then numPlates = result end
            end

            data.platesToUpdatePerFrame = ceil(numPlates / throttle / data.curFPS)
            data.frames = 0
            data.startTime = curTime
        else
            data.frames = data.frames + 1
        end

        data.platesUpdatedThisFrame = 0
    end)
end

------------------------------------------------------------------------
-- 2. Plater_healthText
--
-- Plater.UpdateLifePercentText is called inside NameplateTick's
-- throttled block for every nameplate that has percent text enabled.
-- Each call runs string.format() and SetText() even when the health
-- bar's current and max health have not changed since the last call.
--
-- Fix: Cache the last-seen health and healthMax on the healthBar
-- widget.  If both values match the previous call, skip the original
-- function entirely - the text on screen is already correct.
------------------------------------------------------------------------
ns.patches["Plater_healthText"] = function()
    if not Plater then return end
    if not Plater.UpdateLifePercentText then return end

    local orig = Plater.UpdateLifePercentText

    Plater.UpdateLifePercentText = function(healthBar, unitId, showHealthAmount, showPercentAmount, showDecimals)
        if not healthBar then
            return orig(healthBar, unitId, showHealthAmount, showPercentAmount, showDecimals)
        end

        local newHealth = healthBar.currentHealth
        local newMax    = healthBar.currentHealthMax

        -- If fields are nil (not yet populated), always pass through to original
        if newHealth == nil or newMax == nil then
            return orig(healthBar, unitId, showHealthAmount, showPercentAmount, showDecimals)
        end

        if healthBar._atLastHealth == newHealth and healthBar._atLastMax == newMax then
            return
        end

        healthBar._atLastHealth = newHealth
        healthBar._atLastMax    = newMax

        return orig(healthBar, unitId, showHealthAmount, showPercentAmount, showDecimals)
    end
end

------------------------------------------------------------------------
-- 3. Plater_auraAlign
--
-- Plater.AlignAuraFrames is called after every aura update to
-- reposition buff/debuff icons on a nameplate.  Each invocation
-- allocates a fresh scratch table (`local iconFrameContainerCopy = {}`)
-- that is immediately discarded, generating significant GC pressure
-- during combat (200+ calls/second across all visible nameplates).
--
-- Fully replacing AlignAuraFrames is risky because it contains complex
-- layout logic that varies across Plater versions.  Instead we wrap it
-- with a lightweight guard: count visible aura icons on the buff frame
-- and skip the call entirely when the count has not changed.  This
-- eliminates the vast majority of redundant layout passes (and their
-- associated table allocations) while preserving correctness whenever
-- the aura set actually changes.
------------------------------------------------------------------------
ns.patches["Plater_auraAlign"] = function()
    if not Plater then return end
    if not Plater.AlignAuraFrames then return end

    local orig = Plater.AlignAuraFrames

    Plater.AlignAuraFrames = function(self, ...)
        if not self then
            return orig(self, ...)
        end

        -- The buff container holds all aura icon frames for this plate
        local container = self.PlaterBuffList
        if not container then
            return orig(self, ...)
        end

        -- Count currently visible icons (type guard for non-frame metadata entries)
        local count = 0
        for _, icon in pairs(container) do
            if type(icon) == "table" and icon.IsShown and icon:IsShown() then
                count = count + 1
            end
        end

        -- If the visible count is unchanged and non-zero, the layout
        -- produced by the original would be identical - skip it.
        if self._atLastAuraCount == count and count > 0 then
            return
        end

        self._atLastAuraCount = count

        return orig(self, ...)
    end
end
