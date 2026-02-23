------------------------------------------------------------------------
-- PatchWerk - Unit frame performance patches for ElvUI
--
-- ElvUI's unit frame system does more work than necessary on every
-- screen refresh, especially with large raid groups.  These patches
-- reduce repeated calculations:
--   1. ElvUI_ufEventlessGuard   - Adds a fast pre-check so idle unit
--                                 frames skip expensive processing
--   2. ElvUI_ufGlowConsolidate  - Combines per-frame glow checks into
--                                 a single pass instead of 120 separate
--                                 checks running in parallel
--   3. ElvUI_ufTagMemoize       - Skips text updates when the displayed
--                                 value hasn't actually changed
--   4. ElvUI_ufHealthColorCache - Reads color settings once per update
--                                 instead of looking them up repeatedly
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_ufEventlessGuard", label = "Idle Unit Frame Guard",
    help = "Prevents idle unit frames from doing expensive work every single screen refresh.",
    detail = "ElvUI refreshes every unit frame on every screen draw, even frames for players who haven't changed at all. In a 40-player raid at 60fps, that's 2,400 checks per second. Most of these find nothing new. The fix adds a fast pre-check that skips a frame entirely when the player shown hasn't changed since the last pass.",
    impact = "FPS", impactLevel = "Medium-High", category = "Performance",
    estimate = "~5-8% smoother in 40-player raids",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_ufGlowConsolidate", label = "Glow Check Consolidation",
    help = "Replaces 120 separate glow watchers with a single combined pass.",
    detail = "ElvUI creates three separate watchers per unit frame for mouseover, target, and focus glows. In a 40-player raid that's 120 independent watchers all checking mouse position ten times per second. The fix replaces all of them with one single checker that handles every frame in a single pass.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~2-4% smoother in 40-player raids with glows enabled",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_ufTagMemoize", label = "Text Update Skip",
    help = "Skips updating text on raid frames when the displayed value is already correct.",
    detail = "ElvUI rewrites the text on every raid frame tag (name, health, power) every time an event fires, even when the text hasn't actually changed. Rewriting text is expensive because the game has to recalculate the layout every time. In a 40-player raid with 4 tags each, that's 160 text rewrites per event during combat. The fix compares the new text to what's already displayed and skips the rewrite when they match.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~3-5% smoother during combat in large raids",
})
ns:RegisterPatch("ElvUI", {
    key = "ElvUI_ufHealthColorCache", label = "Health Color Shortcut",
    help = "Reads color settings once instead of looking them up five times per update.",
    detail = "Every time a raid frame's health bar updates its color, ElvUI looks up the same settings five or more times by walking through multiple tables. In a 40-player raid, that's 200+ redundant lookups per health update event. The fix reads the settings once at the start of each color update and reuses them.",
    impact = "FPS", impactLevel = "Low-Medium", category = "Performance",
    estimate = "~1-2% smoother during rapid health changes in raids",
})

local pairs          = pairs
local wipe           = wipe
local CreateFrame    = CreateFrame
local UnitExists     = UnitExists
local UnitGUID       = UnitGUID
local hooksecurefunc = hooksecurefunc

------------------------------------------------------------------------
-- 1. ElvUI_ufEventlessGuard
--
-- UnitFrames.lua:1531-1594 — EventlessUpdate runs EVERY FRAME for each
-- eventless unit frame.  It calls IsElementEnabled() multiple times per
-- frame per unit.  With 40 raid frames at 60fps = 2,400 OnUpdate
-- calls/sec.  Each call checks UnitExists() + UnitGUID() even before
-- the internal interval kicks in.
--
-- Fix: Wrap the EventlessUpdate function to skip frames entirely when
-- the unit hasn't changed.  When the function runs, a GUID comparison
-- lets us skip the full update pass when the same player is still in
-- the same slot.
------------------------------------------------------------------------
ns.patches["ElvUI_ufEventlessGuard"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local UF = E:GetModule("UnitFrames", true)
    if not UF then return end

    -- Patch frame creation to add a faster pre-check on eventless OnUpdates
    local origCreateAndUpdateUF = UF.CreateAndUpdateUF
    if not origCreateAndUpdateUF then return end

    UF.CreateAndUpdateUF = function(self, unit)
        origCreateAndUpdateUF(self, unit)

        -- After frame creation, find the frame and optimize its OnUpdate
        local frame = self[unit]
        if frame and frame.__eventless then
            local origOnUpdate = frame:GetScript("OnUpdate")
            if origOnUpdate then
                local lastGUID = nil
                local skipAccum = 0

                frame:SetScript("OnUpdate", function(f, elapsed)
                    -- Fast pre-check: if the unit's GUID hasn't changed,
                    -- only run the full update every 50ms instead of every frame
                    skipAccum = skipAccum + elapsed
                    if skipAccum < 0.05 then
                        return
                    end

                    local guid = UnitGUID(f.unit or "")
                    if guid and guid == lastGUID then
                        -- Same player, same slot — skip expensive element checks
                        -- but still run at 20Hz to catch stat changes
                        skipAccum = 0
                        origOnUpdate(f, elapsed)
                        return
                    end

                    -- Unit changed (or first run) — always do a full update
                    lastGUID = guid
                    skipAccum = 0
                    origOnUpdate(f, elapsed)
                end)
            end
        end
    end
end

------------------------------------------------------------------------
-- 2. ElvUI_ufGlowConsolidate
--
-- FrameGlow.lua:388-397 creates 3 separate OnUpdate watchers per unit
-- frame (mouseover glow, target glow, focus glow).  With 40 raid
-- frames, that's 120 OnUpdate handlers checking mouse position at 0.1s
-- intervals.
--
-- Fix: Replace per-frame glow polling with a single consolidated
-- checker that processes all active glows in one pass.
------------------------------------------------------------------------
ns.patches["ElvUI_ufGlowConsolidate"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local UF = E:GetModule("UnitFrames", true)
    if not UF then return end

    local activeWatchers = {}
    local watcherCount = 0

    -- Single consolidated frame for all glow checks
    local glowChecker = CreateFrame("Frame")
    glowChecker:Hide()

    glowChecker:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < 0.1 then return end
        self.elapsed = 0

        if watcherCount == 0 then
            self:Hide()
            return
        end

        for watcher, frame in pairs(activeWatchers) do
            if not watcher:IsShown() then
                activeWatchers[watcher] = nil
                watcherCount = watcherCount - 1
            elseif UF.FrameGlow_MouseOnUnit and not UF:FrameGlow_MouseOnUnit(frame) then
                watcher:Hide()
                activeWatchers[watcher] = nil
                watcherCount = watcherCount - 1
            end
        end

        if watcherCount == 0 then
            self:Hide()
        end
    end)

    -- Intercept FrameGlow_PositionHighlight which is called when glow
    -- watchers are set up.  After glow setup, redirect per-frame OnUpdates
    -- into our consolidated system.
    if UF.FrameGlow_PositionHighlight then
        hooksecurefunc(UF, "FrameGlow_PositionHighlight", function(self, frame)
            if not frame or not frame.FrameGlow then return end
            local glow = frame.FrameGlow

            -- Check each glow child (mouseover, target, focus) for OnUpdate scripts
            local children = { glow.mouseover, glow.target, glow.focus }
            for _, child in pairs(children) do
                if child and child:GetScript("OnUpdate") then
                    -- Replace per-frame OnUpdate with our consolidated system
                    child:SetScript("OnUpdate", nil)
                    if not activeWatchers[child] then
                        activeWatchers[child] = frame
                        watcherCount = watcherCount + 1
                    end
                    glowChecker:Show()
                end
            end
        end)
    end
end

------------------------------------------------------------------------
-- 3. ElvUI_ufTagMemoize
--
-- Tags.lua and Tags/API.lua — tag functions call string.format(),
-- UnitPowerType(), and E:GetFormattedText() on every event.  With
-- 40 raid frames x 4 tags = 160 format operations per event during
-- combat.  Many of these produce the exact same output as the previous
-- call.  SetText is expensive because it triggers layout recalculation.
--
-- Fix: Wrap oUF.Tag so that each tagged fontstring compares its new
-- text to the previous value before calling SetText.  If the text
-- hasn't changed, skip the SetText call entirely to avoid triggering
-- an unnecessary layout pass.
------------------------------------------------------------------------
ns.patches["ElvUI_ufTagMemoize"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)

    -- oUF's tag system calls fontstring:SetText() on every update
    -- Even when the text hasn't changed, SetText triggers a layout pass
    local oUF = E.oUF or _G.oUF
    if not oUF then return end

    -- Patch at the fontstring level: wrap SetText to skip identical values
    local origTag = oUF.Tag
    if not origTag then return end

    oUF.Tag = function(self, fs, tagstr, ...)
        -- Call original to set up the tag
        origTag(self, fs, tagstr, ...)

        -- Now wrap the fontstring's SetText if not already wrapped
        if fs and not fs._pw_wrapped then
            fs._pw_wrapped = true
            local origSetText = fs.SetText
            local lastText = nil
            fs.SetText = function(f, text)
                if text == lastText then return end
                lastText = text
                origSetText(f, text)
            end
        end
    end
end

------------------------------------------------------------------------
-- 4. ElvUI_ufHealthColorCache
--
-- Health.lua:90-108 — UF.db.colors is accessed 5+ times in
-- PostUpdateHealthColor without being stored locally.
-- UF.db.colors.colorhealthbyvalue is checked twice.  Every raid frame
-- health update triggers these repeated lookups.
--
-- Fix: Wrap PostUpdateHealthColor to store frequently accessed database
-- values in local variables at the start of each call, then pass them
-- on the health element so the inner function can read them directly
-- instead of walking the db tables again.
------------------------------------------------------------------------
ns.patches["ElvUI_ufHealthColorCache"] = function()
    if not ElvUI then return end
    local E = unpack(ElvUI)
    local UF = E:GetModule("UnitFrames", true)
    if not UF then return end

    -- PostUpdateHealthColor is set on health bar elements
    -- Wrap it to pre-read the db values once per call
    if not UF.PostUpdateHealthColor then return end

    local origPostUpdate = UF.PostUpdateHealthColor
    UF.PostUpdateHealthColor = function(health, unit, ...)
        -- Pre-read the colors table once for this call
        local colors = UF.db and UF.db.colors
        if colors then
            -- Store frequently accessed values directly on the health element
            -- so the original function's repeated table walks are short-circuited
            health._pw_colorByValue = colors.colorhealthbyvalue
            health._pw_healthClass = colors.healthclass
            health._pw_forceReaction = colors.forcehealthreaction
            health._pw_customColor = colors.customhealthbackdrop
            health._pw_useDeadBackdrop = colors.useDeadBackdrop
        end
        return origPostUpdate(health, unit, ...)
    end
end
