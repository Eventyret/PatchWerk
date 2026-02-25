------------------------------------------------------------------------
-- PatchWerk - Patches for BigWigs (Boss Mods)
--
-- BigWigs is generally well-optimized with good Classic guards.
--   1. BigWigs_proxTextThrottle  - Throttle proximity text rendering
--
-- NOTE: BigWigs_flashRecovery was removed in v1.5.0. The !PatchWerk
-- companion addon provides SetColorTexture on the Texture metatable,
-- which allows Flash.lua to load correctly on its own.
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("BigWigs", {
    key = "BigWigs_proxTextThrottle", label = "Proximity Text Throttle",
    help = "Reduces how often the proximity display redraws its player list text.",
    detail = "The proximity display updates its text 20 times per second. Most monitors and human reaction times cannot benefit from updates faster than 10-12 per second. This throttles text rendering to ~12fps while keeping the proximity detection running at full speed.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "Small FPS improvement when proximity display is open during encounters",
})

local GetTime = GetTime

------------------------------------------------------------------------
-- 1. BigWigs_proxTextThrottle
--
-- The proximity display updates player names and title text 20 times
-- per second via CTimerAfter(0.05, ...) chains.  The text rendering
-- (SetText, SetFormattedText) is the visually expensive part.
--
-- Fix: Wait for BigWigs_Plugins to load (it is LoadOnDemand), then
-- watch for the BigWigsProximityAnchor frame to be created.  Once it
-- exists, wrap its text FontString methods with an 80ms throttle
-- (~12 updates per second).  This preserves the full-speed detection
-- logic while reducing rendering overhead.
--
-- NOTE: We hook the global frame directly because BigWigs:GetPlugin()
-- returns a shallow copy containing only { db = ... }, not the real
-- plugin module.  The anchor frame is always created as a global.
------------------------------------------------------------------------
ns.patches["BigWigs_proxTextThrottle"] = function()
    local function InstallThrottle()
        local anchor = _G["BigWigsProximityAnchor"]
        if not anchor then return false end

        -- Throttle the main text body (player list)
        local textObj = anchor.text
        if textObj then
            local lastSetTextTime = 0
            local origSetText = textObj.SetText
            textObj.SetText = function(self, text, ...)
                local now = GetTime()
                if now - lastSetTextTime < 0.08 then return end
                lastSetTextTime = now
                return origSetText(self, text, ...)
            end

            local lastSetFormattedTextTime = 0
            local origSetFmtText = textObj.SetFormattedText
            if origSetFmtText then
                textObj.SetFormattedText = function(self, fmt, ...)
                    local now = GetTime()
                    if now - lastSetFormattedTextTime < 0.08 then return end
                    lastSetFormattedTextTime = now
                    return origSetFmtText(self, fmt, ...)
                end
            end
        end

        -- Throttle the title bar (range/count display)
        local titleObj = anchor.title
        if titleObj then
            local lastTitleTime = 0
            local origTitleFmt = titleObj.SetFormattedText
            if origTitleFmt then
                titleObj.SetFormattedText = function(self, fmt, ...)
                    local now = GetTime()
                    if now - lastTitleTime < 0.08 then return end
                    lastTitleTime = now
                    return origTitleFmt(self, fmt, ...)
                end
            end
        end

        return true
    end

    -- BigWigs_Plugins is LoadOnDemand — wait for it to load, then
    -- watch for the anchor frame (created lazily on first Open).
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function(self, event, addonName)
        if addonName ~= "BigWigs_Plugins" then return end
        self:UnregisterAllEvents()

        -- The anchor is created on first Open(), so poll until it exists.
        -- Check immediately, then retry every 2 seconds for 5 minutes.
        if InstallThrottle() then return end

        local attempts = 0
        C_Timer.NewTicker(2, function(ticker)
            attempts = attempts + 1
            if InstallThrottle() or attempts >= 150 then
                ticker:Cancel()
            end
        end)
    end)
end
