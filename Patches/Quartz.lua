------------------------------------------------------------------------
-- AddonTweaks - Performance patches for Quartz (Cast Bars)
--
-- Quartz creates cast bar frames with per-frame OnUpdate handlers for
-- smooth animation.  On TBC Classic Anniversary the full 60fps update
-- rate is unnecessary since all internal timing uses absolute GetTime():
--   1. Quartz_castBarThrottle  - Cap main cast bars to 30fps
--   2. Quartz_swingBarThrottle - Cap swing timer bar to 30fps
--   3. Quartz_gcdBarThrottle   - Cap GCD bar to 30fps
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Helper: Throttle a named frame's OnUpdate to ~30fps.
-- Quartz uses absolute GetTime() internally (not elapsed), so the
-- accumulated elapsed parameter does not affect timing accuracy.
------------------------------------------------------------------------
local function ThrottleBarOnUpdate(barName)
    local bar = _G[barName]
    if not bar then return false end
    if bar._addonTweaksThrottled then return true end
    local origScript = bar:GetScript("OnUpdate")
    if not origScript then return false end

    local accum = 0
    bar:SetScript("OnUpdate", function(self, elapsed)
        accum = accum + elapsed
        if accum < 0.033 then return end
        origScript(self, accum)
        accum = 0
    end)
    bar._addonTweaksThrottled = true
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
