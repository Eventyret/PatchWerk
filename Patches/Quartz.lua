------------------------------------------------------------------------
-- PatchWerk - Performance patches for Quartz (Cast Bars)
--
-- Quartz creates cast bar frames with per-frame OnUpdate handlers for
-- smooth animation.  On TBC Classic Anniversary the full 60fps update
-- rate is unnecessary since all internal timing uses absolute GetTime():
--   1. Quartz_castBarThrottle  - Cap main cast bars to 30fps
--   2. Quartz_swingBarThrottle - Cap swing timer bar to 30fps
--   3. Quartz_gcdBarThrottle   - Cap GCD bar to 30fps
------------------------------------------------------------------------

local _, ns = ...

local pcall = pcall

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("Quartz", {
    key = "Quartz_castBarThrottle", label = "Cast Bar 30fps Cap",
    help = "Caps cast bar animations at 30fps -- looks identical, uses half the resources.",
    detail = "Quartz animates cast bars at 60fps, but you can't visually tell the difference between 60fps and 30fps on a 1-3 second cast. The fix caps it at 30fps, cutting the work in half with zero visual difference.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~1-2 FPS with multiple cast bars visible",
})
ns:RegisterPatch("Quartz", {
    key = "Quartz_swingBarThrottle", label = "Swing Timer 30fps Cap",
    help = "Caps the swing timer at 30fps -- no visible difference on a 2-3 second swing.",
    detail = "The swing timer updates 60 times per second during auto-attack, but a 2-3 second swing looks identical at 30fps. This halves the animation work for melee classes and hunters.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "~0.5-1 FPS for melee classes during combat",
})
ns:RegisterPatch("Quartz", {
    key = "Quartz_gcdBarThrottle", label = "GCD Bar 30fps Cap",
    help = "Caps the global cooldown bar at 30fps -- plenty smooth for a 1.5 second bar.",
    detail = "The GCD bar runs at 60fps during every 1.5 second global cooldown. That's complete overkill for such a short bar. The fix caps it at 30fps, which is still perfectly smooth.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "~0.5-1 FPS during ability spam",
})
ns:RegisterPatch("Quartz", {
    key = "Quartz_buffBucket", label = "Buff Bar Update Throttle",
    help = "Limits buff bar updates during rapid target switching to prevent unnecessary repetition.",
    detail = "The Buff module checks up to 72 buffs and debuffs on every target or focus change. During rapid tab-targeting or healer mouse-over targeting, this can fire dozens of times per second. This patch batches those updates so they happen at most 10 times per second with no visible delay.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~1-2 FPS for healers during rapid target switching",
})

------------------------------------------------------------------------
-- Helper: Throttle a named frame's OnUpdate to ~30fps.
-- Quartz uses absolute GetTime() internally (not elapsed), so the
-- accumulated elapsed parameter does not affect timing accuracy.
------------------------------------------------------------------------
local function ThrottleBarOnUpdate(barName)
    local bar = _G[barName]
    if not bar then return false end
    if bar._pwThrottled then return true end
    local origScript = bar:GetScript("OnUpdate")
    if not origScript then return false end

    local accum = 0
    bar:SetScript("OnUpdate", function(self, elapsed)
        accum = accum + elapsed
        if accum < 0.033 then return end
        origScript(self, accum)
        accum = 0
    end)
    bar._pwThrottled = true
    return true
end

------------------------------------------------------------------------
-- Helper: For bars that set OnUpdate via OnShow (Swing, GCD), intercept
-- the OnShow script to re-apply throttling each time the bar appears.
------------------------------------------------------------------------
local function ThrottleBarViaOnShow(barName)
    local bar = _G[barName]
    if not bar then return false end

    local origOnShow = bar:GetScript("OnShow")
    if not origOnShow then return false end

    bar:SetScript("OnShow", function(self)
        origOnShow(self)
        local innerOnUpdate = self:GetScript("OnUpdate")
        if innerOnUpdate then
            local accum = 0
            self:SetScript("OnUpdate", function(self2, elapsed)
                accum = accum + elapsed
                if accum < 0.033 then return end
                accum = 0
                innerOnUpdate(self2, elapsed)
            end)
        end
    end)
    return true
end

------------------------------------------------------------------------
-- 1. Quartz_castBarThrottle
--
-- The main cast bars (Player, Target, Focus, Pet) run OnUpdate at full
-- framerate.  Each frame calls SetValue, ClearAllPoints + SetPoint for
-- the spark, and SetFormattedText for the timer text — 4-6 render API
-- calls per frame per active bar.
--
-- Fix: Throttle to 30fps.  Also hook ApplySettings to re-apply after
-- config changes which re-set the OnUpdate script.
------------------------------------------------------------------------
ns.patches["Quartz_castBarThrottle"] = function()
    if not Quartz3 then return end

    local barNames = {
        "Quartz3CastBarPlayer", "Quartz3CastBarTarget",
        "Quartz3CastBarFocus",  "Quartz3CastBarPet",
    }

    local applied = false
    for _, name in ipairs(barNames) do
        if ThrottleBarOnUpdate(name) then applied = true end
    end
    if not applied then return end

    -- Re-apply throttle after settings changes restore the original script
    if Quartz3.CastBarTemplate and Quartz3.CastBarTemplate.template
       and Quartz3.CastBarTemplate.template.ApplySettings then
        local origApply = Quartz3.CastBarTemplate.template.ApplySettings
        Quartz3.CastBarTemplate.template.ApplySettings = function(self, ...)
            origApply(self, ...)
            local name = self and self.GetName and self:GetName()
            if name then ThrottleBarOnUpdate(name) end
        end
    end
end

------------------------------------------------------------------------
-- 2. Quartz_swingBarThrottle
--
-- The swing timer bar runs OnUpdate continuously during all auto-attack
-- combat.  Each frame formats remaining time text and updates bar fill.
-- The OnUpdate is set via an OnShow script each time the bar appears.
--
-- Fix: Intercept OnShow to capture and throttle the local OnUpdate
-- closure to 30fps.  Bar fill at 30fps is visually identical for a
-- 2-3 second swing timer.
------------------------------------------------------------------------
ns.patches["Quartz_swingBarThrottle"] = function()
    if not Quartz3 then return end
    ThrottleBarViaOnShow("Quartz3SwingBar")
end

------------------------------------------------------------------------
-- 3. Quartz_gcdBarThrottle
--
-- The GCD bar runs OnUpdate during every 1.5s GCD cycle, positioning
-- a spark via ClearAllPoints + SetPoint every frame.  The OnUpdate is
-- set via OnShow each time the GCD fires.
--
-- Fix: Same OnShow intercept pattern to throttle to 30fps.
------------------------------------------------------------------------
ns.patches["Quartz_gcdBarThrottle"] = function()
    if not Quartz3 then return end
    ThrottleBarViaOnShow("Quartz3GCDBar")
end

------------------------------------------------------------------------
-- 4. Quartz_buffBucket
--
-- The Buff module updates target/focus buff bars on every
-- PLAYER_TARGET_CHANGED and PLAYER_FOCUS_CHANGED event.  During
-- rapid target switching (tab-targeting, healer mouse-over) these
-- fire in quick succession, each iterating up to 72 auras
-- (32 buffs + 40 debuffs) via UnitAura.
--
-- Fix: Throttle UpdateTargetBars and UpdateFocusBars to at most once
-- per 100ms.  The module already uses AceBucket to batch UNIT_AURA at
-- 0.5s, so target/focus changes are the remaining hot path.
------------------------------------------------------------------------
ns.patches["Quartz_buffBucket"] = function()
    if not Quartz3 then return end

    local ok, Buff = pcall(Quartz3.GetModule, Quartz3, "Buff", true)
    if not ok or not Buff then return end
    if not Buff.UpdateTargetBars or not Buff.UpdateFocusBars then return end

    local GetTime = GetTime
    local lastTargetUpdate, lastFocusUpdate = 0, 0
    local THROTTLE = 0.1

    local origUpdateTarget = Buff.UpdateTargetBars
    Buff.UpdateTargetBars = function(self)
        local now = GetTime()
        if now - lastTargetUpdate < THROTTLE then return end
        lastTargetUpdate = now
        return origUpdateTarget(self)
    end

    local origUpdateFocus = Buff.UpdateFocusBars
    Buff.UpdateFocusBars = function(self)
        local now = GetTime()
        if now - lastFocusUpdate < THROTTLE then return end
        lastFocusUpdate = now
        return origUpdateFocus(self)
    end
end
