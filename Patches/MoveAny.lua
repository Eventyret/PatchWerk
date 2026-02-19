------------------------------------------------------------------------
-- PatchWerk - Performance patches for MoveAny (UI Mover)
--
-- MoveAny is a comprehensive UI mover but has several perpetual polling
-- loops and hot paths on TBC Classic Anniversary.  These patches address:
--   1. MoveAny_thinkHelpFrameSkip      - Stop useless profile check loop
--   2. MoveAny_updateMoveFramesDebounce - Debounce CreateFrame hook spam
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("MoveAny", {
    key = "MoveAny_thinkHelpFrameSkip",
    label = "Profile Check Skip",
    help = "Stops a perpetual polling loop that checks for EditMode profiles on TBC.",
    detail = "MoveAny runs a ThinkHelpFrame function every 500ms that checks whether EditModeManagerFrame is using a preset profile. On TBC Classic Anniversary, EditModeManagerFrame does not exist, so this check always returns the same result and the loop does nothing useful. This stops the loop entirely.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "Eliminates a 500ms perpetual polling loop",
})
ns:RegisterPatch("MoveAny", {
    key = "MoveAny_updateMoveFramesDebounce",
    label = "Frame Registration Debounce",
    help = "Prevents rapid repeated frame registration scans when many frames are created at once.",
    detail = "MoveAny hooks the global CreateFrame function and triggers a full frame registration scan on every single frame creation. During loading screens and zone transitions, dozens to hundreds of frames are created per second, each triggering a redundant scan. This debounces CreateFrame-triggered scans to at most twice per second.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "Reduces load screen and zone transition overhead",
})

local GetTime = GetTime

------------------------------------------------------------------------
-- 1. MoveAny_thinkHelpFrameSkip
--
-- registerwidgets.lua schedules a 1-second deferred callback that
-- defines MoveAny:ThinkHelpFrame(), which then reschedules itself
-- every 500ms.  On TBC, EditModeManagerFrame is nil, so
-- IsPresetProfileActive() always returns true, making the loop pure
-- overhead with no useful work.
--
-- Fix: After the deferred callback has run and defined ThinkHelpFrame,
-- replace it with a no-op to stop the loop.
------------------------------------------------------------------------
ns.patches["MoveAny_thinkHelpFrameSkip"] = function()
    if not MoveAny then return end

    -- ThinkHelpFrame is defined inside a 1-second C_Timer.After callback.
    -- Wait 2 seconds to ensure it has been created, then replace it.
    C_Timer.After(2, function()
        if MoveAny and MoveAny.ThinkHelpFrame then
            MoveAny.ThinkHelpFrame = function() end
        end
    end)
end

------------------------------------------------------------------------
-- 2. MoveAny_updateMoveFramesDebounce
--
-- moveframes.lua hooks hooksecurefunc("CreateFrame", ...) which calls
-- MoveAny:UpdateMoveFrames("CreateFrame", 0.1) on every frame creation.
-- During loading screens, hundreds of frames are created, flooding
-- UpdateMoveFrames with redundant calls.  The function has a basic
-- "if run then return end" guard but that only prevents concurrency,
-- not rapid successive calls.
--
-- Fix: Wrap MoveAny:UpdateMoveFrames to debounce calls that originate
-- from the CreateFrame hook to at most once per 0.5 seconds.  Other
-- callers (user actions, settings changes) pass through immediately.
------------------------------------------------------------------------
ns.patches["MoveAny_updateMoveFramesDebounce"] = function()
    if not MoveAny then return end
    if not MoveAny.UpdateMoveFrames then return end

    local origUpdateMoveFrames = MoveAny.UpdateMoveFrames
    local lastCreateFrameCall = 0
    local pendingTimer = nil

    MoveAny.UpdateMoveFrames = function(self, from, force, ts)
        -- Only debounce calls triggered by the CreateFrame hook
        if from == "CreateFrame" then
            local now = GetTime()
            if now - lastCreateFrameCall < 0.5 then
                -- Already called recently -- schedule one trailing call
                if not pendingTimer then
                    pendingTimer = C_Timer.After(0.5, function()
                        pendingTimer = nil
                        lastCreateFrameCall = GetTime()
                        origUpdateMoveFrames(self, from, force, ts)
                    end)
                end
                return
            end
            lastCreateFrameCall = now
        end

        return origUpdateMoveFrames(self, from, force, ts)
    end
end
