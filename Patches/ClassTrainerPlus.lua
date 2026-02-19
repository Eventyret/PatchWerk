------------------------------------------------------------------------
-- PatchWerk - Performance patch for ClassTrainerPlus
--
-- ClassTrainerPlus (v1.4.1) enhances the default class trainer window
-- with ability filtering, ignore lists, bulk training, and search.
-- Its OnUpdate handler polls IsShiftKeyDown() every single frame to
-- toggle the "Train All" button text and tooltip, generating 60+ calls
-- per second for a key state that changes at most a few times per
-- minute.
--
-- Patches:
--   1. ClassTrainerPlus_shiftKeyThrottle - Throttle shift-key polling
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns.patchInfo[#ns.patchInfo + 1] = {
    key = "ClassTrainerPlus_shiftKeyThrottle",
    group = "ClassTrainerPlus",
    label = "Shift Key Throttle",
    help = "Throttles the shift-key polling from every frame to 8 times per second.",
    detail = "ClassTrainerPlus installs an OnUpdate script on ClassTrainerPlusFrame that calls IsShiftKeyDown() every single frame to detect when the player holds shift (toggling the Train button between 'Train' and 'Train All' and showing a cost tooltip). At 60+ fps this means 60+ redundant calls per second for a key state that changes at most a few times per minute. This patch wraps the OnUpdate handler with a 0.125-second elapsed-time accumulator, reducing polling to 8 times per second. This is still imperceptibly fast for the user but eliminates ~87% of the overhead.",
    impact = "FPS",
    impactLevel = "Low",
    category = "Performance",
    targetVersion = "1.4.1",
    estimate = "~1-2% FPS improvement while trainer window is open",
}

------------------------------------------------------------------------
-- 1. ClassTrainerPlus_shiftKeyThrottle
--
-- In ClassTrainerPlus.lua, ClassTrainerPlusFrame_OnLoad() sets:
--
--   self:SetScript("OnUpdate", function()
--       if (IsShiftKeyDown()) then
--           ClassTrainerPlusTrainButton:SetText(ctp.L.TRAIN_ALL)
--           if (mousedOver) then ShowCostTooltip() end
--       else
--           ClassTrainerPlusTrainButton:SetText(TRAIN)
--           trainAllCostTooltip:Hide()
--       end
--   end)
--
-- This runs every frame with no elapsed-time gate.  The function calls
-- IsShiftKeyDown(), conditionally updates button text, and shows/hides
-- a tooltip.  While individually cheap, at 60+ fps the cumulative cost
-- is non-trivial, especially since the trainer window is often open for
-- extended browsing sessions.
--
-- Fix: After ClassTrainerPlus has loaded and called OnLoad, we capture
-- the existing OnUpdate script from ClassTrainerPlusFrame, then replace
-- it with a throttled wrapper that only fires the original handler at
-- most 8 times per second (every 0.125s).  The wrapper accumulates
-- elapsed time and skips frames until the interval has passed.
--
-- We use 0.125s (8 Hz) rather than 0.25s (4 Hz) because this controls
-- a keyboard modifier check -- a slightly higher rate ensures the
-- button text updates feel responsive when pressing/releasing shift.
------------------------------------------------------------------------
ns.patches["ClassTrainerPlus_shiftKeyThrottle"] = function()
    if not ns:IsAddonLoaded("ClassTrainerPlus") then return end

    -- ClassTrainerPlusFrame is a global frame created by the addon's XML
    local frame = ClassTrainerPlusFrame
    if not frame then return end

    -- Capture the OnUpdate script installed by ClassTrainerPlusFrame_OnLoad
    local originalOnUpdate = frame:GetScript("OnUpdate")
    if not originalOnUpdate then return end

    local THROTTLE_INTERVAL = 0.125  -- 8 updates per second
    local elapsed_acc = 0

    frame:SetScript("OnUpdate", function(self, elapsed)
        elapsed_acc = elapsed_acc + (elapsed or 0)
        if elapsed_acc < THROTTLE_INTERVAL then
            return
        end
        elapsed_acc = 0
        originalOnUpdate(self)
    end)
end
