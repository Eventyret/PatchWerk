------------------------------------------------------------------------
-- AddonTweaks - Performance patches for Details (Damage Meter)
--
-- Details is one of the most popular damage meters but ships with several
-- hot paths that are unnecessarily expensive on TBC Classic Anniversary.
-- These patches address:
--   1. Details_hexFix        - Replace slow character-loop hex encoder
--   2. Details_fadeHandler   - Stop OnUpdate ticking when no fades active
--   3. Details_refreshCap    - Prevent 60fps meter refresh from faster_updates
--   4. Details_npcIdCache    - Cache NPC ID extraction from GUIDs
------------------------------------------------------------------------

local _, ns = ...

local pairs   = pairs
local next    = next
local wipe    = wipe
local format  = string.format

------------------------------------------------------------------------
-- 1. Details_hexFix
--
-- Details.hex() builds hex strings one character at a time using string
-- concatenation inside a while loop.  It is called 50+ times per window
-- refresh (twice per bar in DPS mode for colour generation).
--
-- Fix: Replace with a single string.format call.
------------------------------------------------------------------------
ns.patches["Details_hexFix"] = function()
    if not Details then return end
    if not Details.hex then return end

    Details.hex = function(self, num)
        return format("%02x", num)
    end
end

------------------------------------------------------------------------
-- 2. Details_fadeHandler
--
-- The frame "DetailsFadeFrameOnUpdate" runs an OnUpdate handler every
-- single frame, iterating Details.FadeHandler.frames even when the
-- table is completely empty.
--
-- Fix: Wrap the original OnUpdate with an idle guard that hides the
-- frame when there is nothing to fade, and hook the Fader entry point
-- to re-show it when new fades are queued.  This preserves the original
-- fade logic byte-for-byte while eliminating idle-frame overhead.
------------------------------------------------------------------------
ns.patches["Details_fadeHandler"] = function()
    local fadeFrame = _G["DetailsFadeFrameOnUpdate"]
    if not fadeFrame then return end
    if not Details then return end
    if not Details.FadeHandler then return end

    local frames = Details.FadeHandler.frames
    if not frames then return end

    local originalOnUpdate = fadeFrame:GetScript("OnUpdate")
    if not originalOnUpdate then return end

    -- Wrap: skip the real handler when there is nothing to process
    fadeFrame:SetScript("OnUpdate", function(self, deltaTime)
        if not next(frames) then
            self:Hide()
            return
        end
        originalOnUpdate(self, deltaTime)
    end)

    -- Start hidden - nothing should be fading at patch-apply time
    fadeFrame:Hide()

    -- Re-show the frame whenever a new fade is queued
    if Details.FadeHandler.Fader then
        hooksecurefunc(Details.FadeHandler, "Fader", function()
            if not fadeFrame:IsShown() then
                fadeFrame:Show()
            end
        end)
    end
end

------------------------------------------------------------------------
-- 3. Details_refreshCap
--
-- Details.RefreshUpdater creates a C_Timer.NewTicker at a given interval.
-- When streamer_config.faster_updates is true the interval is forced to
-- 0.016s (60 fps), which is catastrophically expensive on Classic where
-- the meter has far less optimised rendering code.
--
-- Fix: Hook RefreshUpdater to force-disable faster_updates on Classic
-- and enforce a sane minimum interval of 0.1s (10 Hz).
------------------------------------------------------------------------
ns.patches["Details_refreshCap"] = function()
    if not Details then return end
    if not Details.RefreshUpdater then return end

    local origRefreshUpdater = Details.RefreshUpdater

    Details.RefreshUpdater = function(self, intervalAmount)
        -- Force disable faster_updates on Classic - 60fps refresh is too expensive
        if Details.streamer_config and Details.streamer_config.faster_updates then
            Details.streamer_config.faster_updates = false
        end

        -- Enforce minimum 0.1s interval
        if intervalAmount and intervalAmount < 0.1 then
            intervalAmount = 0.1
        end

        return origRefreshUpdater(self, intervalAmount)
    end
end

------------------------------------------------------------------------
-- 4. Details_npcIdCache
--
-- Details.GetNpcIdFromGuid runs a Lua pattern match on every call but
-- never caches the result.  It is invoked from sort comparators and
-- IsEnemy checks, so the same GUID can be resolved dozens of times per
-- refresh cycle.
--
-- Fix: Add a lightweight cache in front of the original function.
-- The cache is wiped when it exceeds 500 entries to prevent unbounded
-- growth during long sessions with many unique NPCs.
------------------------------------------------------------------------
ns.patches["Details_npcIdCache"] = function()
    if not Details then return end
    if not Details.GetNpcIdFromGuid then return end

    local origGetNpcId = Details.GetNpcIdFromGuid
    local cache = {}
    local cacheCount = 0

    Details.GetNpcIdFromGuid = function(self, guid)
        if not guid or guid == "" then
            return 0
        end

        local cached = cache[guid]
        if cached ~= nil then
            return cached
        end

        local result = origGetNpcId(self, guid)
        cache[guid] = result
        cacheCount = cacheCount + 1

        -- Prevent unbounded growth
        if cacheCount > 500 then
            wipe(cache)
            cacheCount = 0
        end

        return result
    end
end
