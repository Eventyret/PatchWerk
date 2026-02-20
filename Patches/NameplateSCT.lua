------------------------------------------------------------------------
-- PatchWerk - Performance patches for NameplateSCT (Scrolling Combat Text)
--
-- NameplateSCT displays floating combat numbers anchored to nameplates.
-- Its animation loop runs every frame with no throttle, performing
-- repeated DB lookups for every active text animation.
--
-- Patches:
--   1. NameplateSCT_animationThrottle - Cap animation OnUpdate to ~30fps
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("NameplateSCT", {
    key = "NameplateSCT_animationThrottle",
    label = "Animation Throttle",
    help = "Caps the floating combat text animation to 30fps instead of running every frame.",
    detail = "NameplateSCT updates every floating combat number on every single frame -- 60+ times per second. With 10-20 numbers on screen during AoE pulls, that is a lot of position and size recalculations each frame. Capping the animation to 30fps halves this work while keeping the text movement visually smooth.",
    impact = "FPS",
    impactLevel = "Medium",
    category = "Performance",
    estimate = "~1-3 FPS during heavy AoE combat",
})

------------------------------------------------------------------------
-- 1. NameplateSCT_animationThrottle
--
-- The AnimationOnUpdate() function is a local that gets set as the
-- OnUpdate handler on NameplateSCT.frame. It iterates all entries in
-- the `animating` table every frame, performing:
--   - GetTime() calls
--   - UnitIsUnit() checks
--   - Multiple NameplateSCT.db.global.* lookups (strata, alpha,
--     formatting, offsets, iconScale, font, etc.)
--   - LibEasing calculations
--   - SetPoint/SetAlpha/SetTextHeight on every fontString
--
-- At 60fps with 10-20 active animations during AoE, this is a
-- significant per-frame cost. Capping at 30fps (0.033s interval)
-- halves the overhead while maintaining smooth visual animation.
--
-- Strategy: Hook NameplateSCT.frame's SetScript so that whenever the
-- addon installs its AnimationOnUpdate handler, we wrap it with an
-- elapsed-time accumulator that only fires the real handler at ~30fps.
------------------------------------------------------------------------
local THROTTLE_INTERVAL = 0.033  -- ~30 fps

ns.patches["NameplateSCT_animationThrottle"] = function()
    local addon = NameplateSCT
    if not addon then return end

    local frame = addon.frame
    if not frame then return end

    -- The addon sets/clears OnUpdate dynamically:
    --   SetScript("OnUpdate", AnimationOnUpdate)  when animations start
    --   SetScript("OnUpdate", nil)                when animations end
    --
    -- We hook SetScript to intercept the OnUpdate handler installation
    -- and wrap it with our throttle. This is robust against load order
    -- since the handler is set lazily when the first animation starts.
    local origSetScript = frame.SetScript
    local elapsed = 0

    frame.SetScript = function(self, scriptType, handler)
        if scriptType == "OnUpdate" and handler ~= nil then
            -- Wrap the real AnimationOnUpdate with a throttle
            elapsed = 0
            origSetScript(self, "OnUpdate", function(f, dt)
                elapsed = elapsed + dt
                if elapsed < THROTTLE_INTERVAL then return end
                elapsed = 0
                handler()
            end)
        else
            -- Pass through nil (clearing the script) or other script types
            origSetScript(self, scriptType, handler)
        end
    end

    -- If the OnUpdate is already running (animations in flight at patch
    -- time), wrap the current handler immediately
    local currentHandler = frame:GetScript("OnUpdate")
    if currentHandler then
        elapsed = 0
        origSetScript(frame, "OnUpdate", function(f, dt)
            elapsed = elapsed + dt
            if elapsed < THROTTLE_INTERVAL then return end
            elapsed = 0
            currentHandler()
        end)
    end
end
