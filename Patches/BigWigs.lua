------------------------------------------------------------------------
-- PatchWerk - Performance patches for BigWigs (Boss Mods)
--
-- BigWigs is generally well-optimized with good Classic guards.
-- These patches address minor inefficiencies:
--   1. BigWigs_proxTextThrottle  - Throttle proximity text rendering
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
-- Fix: Wait for BigWigs_Core to load (it is LoadOnDemand), then
-- hook the proximity plugin's Open method.  On first open, wrap the
-- anchor's text FontString methods with an 80ms throttle (~12 updates
-- per second).  This preserves the full-speed detection logic while
-- reducing rendering overhead.
------------------------------------------------------------------------
ns.patches["BigWigs_proxTextThrottle"] = function()
    -- BigWigs_Core is LoadOnDemand -- it won't exist at ADDON_LOADED time.
    -- Listen for it to load, then install the hook.
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function(self, event, addonName)
        -- Wait for BigWigs_Core or BigWigs_Plugins to load
        if addonName ~= "BigWigs_Core" and addonName ~= "BigWigs_Plugins" then return end
        if not BigWigs then return end
        if not BigWigs.GetPlugin then return end

        -- GetPlugin throws if the plugin isn't registered yet (BigWigs_Plugins
        -- may not have loaded). Wrap in pcall and keep listening if it fails.
        local ok, proxy = pcall(BigWigs.GetPlugin, BigWigs, "Proximity")
        if not ok or not proxy then return end
        if not proxy.Open then return end

        -- Success -- stop listening and install the hook
        self:UnregisterAllEvents()

        local patched = false
        hooksecurefunc(proxy, "Open", function()
            if patched then return end
            local anchor = _G["BigWigsProximityAnchor"]
            if not anchor then return end

            patched = true

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
        end)
    end)
end
