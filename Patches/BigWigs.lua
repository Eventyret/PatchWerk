------------------------------------------------------------------------
-- PatchWerk - Patches for BigWigs (Boss Mods)
--
-- BigWigs is generally well-optimized with good Classic guards.
-- These patches address minor inefficiencies and TBC Classic compat:
--   1. BigWigs_proxTextThrottle  - Throttle proximity text rendering
--   2. BigWigs_flashRecovery     - Recover Flash plugin (TBC compat)
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

ns:RegisterPatch("BigWigs", {
    key = "BigWigs_flashRecovery", label = "Flash Alert Recovery",
    help = "Recovers boss Flash/Pulse alerts that break on TBC Classic because of missing Retail WoW features.",
    detail = "BigWigs uses a Retail WoW feature for its screen-flash effects that does not exist on TBC Classic. Without this fix, the entire Flash plugin fails to load -- meaning no screen-flash or icon-pulse alerts during boss encounters. This patch detects the broken plugin and rebuilds it using Classic-compatible methods.",
    impact = "FPS", impactLevel = "Low", category = "Fixes",
    estimate = "Restores boss flash and pulse visual alerts",
})

local GetTime = GetTime
local WHITE8x8 = "Interface\\Buttons\\WHITE8x8"

------------------------------------------------------------------------
-- 1. BigWigs_flashRecovery
--
-- BigWigs_Plugins/Flash.lua creates a full-screen flash overlay and a
-- centered pulse icon at file scope.  Line 23 calls SetColorTexture
-- which does not exist on TBC Classic, halting the entire file.  The
-- plugin module (BigWigs:NewPlugin("Flash")) IS created before the
-- error, but OnPluginEnable / BigWigs_Flash / BigWigs_Pulse are never
-- defined.  We detect this and re-create the visual elements and
-- methods using SetTexture + SetVertexColor.
------------------------------------------------------------------------
ns.patches["BigWigs_flashRecovery"] = function()
    local function RecoverFlash()
        if not BigWigs or not BigWigs.GetPlugin then return end

        local ok, flashMod = pcall(BigWigs.GetPlugin, BigWigs, "Flash")
        if not ok or not flashMod then return end

        -- If OnPluginEnable already exists, the plugin loaded fine
        if flashMod.OnPluginEnable then return end

        -- Re-create flash overlay (full-screen blue flash)
        local flashFrame = UIParent:CreateTexture()
        flashFrame:SetAllPoints(UIParent)
        flashFrame:SetAlpha(0)
        flashFrame:SetTexture(WHITE8x8)
        flashFrame:SetVertexColor(0, 0, 1, 0.6)
        flashFrame:Hide()

        local flasher = flashFrame:CreateAnimationGroup()
        flasher:SetScript("OnFinished", function() flashFrame:Hide() end)

        local fade1 = flasher:CreateAnimation("Alpha")
        fade1:SetDuration(0.2); fade1:SetFromAlpha(0); fade1:SetToAlpha(1); fade1:SetOrder(1)
        local fade2 = flasher:CreateAnimation("Alpha")
        fade2:SetDuration(0.2); fade2:SetFromAlpha(1); fade2:SetToAlpha(0); fade2:SetOrder(2)
        local fade3 = flasher:CreateAnimation("Alpha")
        fade3:SetDuration(0.2); fade3:SetFromAlpha(0); fade3:SetToAlpha(1); fade3:SetOrder(3)
        local fade4 = flasher:CreateAnimation("Alpha")
        fade4:SetDuration(0.2); fade4:SetFromAlpha(1); fade4:SetToAlpha(0); fade4:SetOrder(4)

        -- Re-create pulse overlay (centered ability icon)
        local pulseFrame = UIParent:CreateTexture()
        pulseFrame:SetPoint("CENTER", UIParent, "CENTER")
        pulseFrame:SetSize(100, 100)
        pulseFrame:SetAlpha(0.5)
        pulseFrame:SetTexture(132337)  -- Interface\Icons\ability_warrior_charge
        pulseFrame:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        pulseFrame:Hide()

        local pulser = pulseFrame:CreateAnimationGroup()
        pulser:SetScript("OnFinished", function() pulseFrame:Hide() end)

        local pulse1 = pulser:CreateAnimation("Scale")
        pulse1:SetDuration(0.25); pulse1:SetScale(2.5, 2.5); pulse1:SetOrder(1); pulse1:SetEndDelay(0.4)
        local pulse2 = pulser:CreateAnimation("Scale")
        pulse2:SetDuration(0.25); pulse2:SetScale(0.2, 0.2); pulse2:SetOrder(2)

        -- Define the missing plugin methods
        function flashMod:OnPluginEnable()
            if not BigWigsLoader or not BigWigsLoader.isRetail then
                self:RegisterMessage("BigWigs_Flash")
                self:RegisterMessage("BigWigs_Pulse")
            end
        end

        function flashMod:BigWigs_Flash()
            flasher:Stop()
            flashFrame:SetAlpha(0)
            flashFrame:Show()
            flasher:Play()
        end

        function flashMod:BigWigs_Pulse(event, _, _, icon)
            pulser:Stop()
            pulseFrame:SetTexture(icon or 134400)
            pulseFrame:Show()
            pulser:Play()
        end

        -- If the plugin is already enabled, register messages now
        if flashMod.enabled then
            flashMod:OnPluginEnable()
        end
    end

    -- BigWigs_Plugins is LoadOnDemand — check if already loaded
    if ns:IsAddonLoaded("BigWigs_Plugins") then
        RecoverFlash()
        return
    end

    -- Wait for BigWigs_Plugins to load
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function(self, event, addonName)
        if addonName ~= "BigWigs_Plugins" then return end
        self:UnregisterAllEvents()
        RecoverFlash()
    end)
end

------------------------------------------------------------------------
-- 2. BigWigs_proxTextThrottle
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
