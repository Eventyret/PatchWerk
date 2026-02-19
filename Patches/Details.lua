------------------------------------------------------------------------
-- PatchWerk - Performance patches for Details (Damage Meter)
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

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("Details", {
    key = "Details_hexFix", label = "Color Rendering Fix",
    help = "Fixes slow color calculations in damage meter bars.",
    detail = "Details recalculates bar colors 50+ times per window refresh using a slow method. This causes visible stuttering when you have multiple damage meter windows open during heavy combat, especially on Classic's older engine.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~1-2 FPS in combat with multiple meter windows",
})
ns:RegisterPatch("Details", {
    key = "Details_fadeHandler", label = "Idle Animation Saver",
    help = "Stops the fade system from wasting resources when no bars are animating.",
    detail = "The fade animation system runs constantly even when nothing is fading, wasting resources thousands of times per minute. The fix makes it sleep when idle and only wake up when bars actually need to fade.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "Eliminates idle CPU waste when no bars are fading",
})
ns:RegisterPatch("Details", {
    key = "Details_refreshCap", label = "Refresh Rate Cap",
    help = "Prevents the damage meter from refreshing way too fast, which can tank performance on Classic.",
    detail = "Details tries to refresh at 60fps when streamer mode is enabled, which is way too fast for Classic. This causes severe FPS drops during combat. The fix caps refreshes at 10 per second, which is still plenty responsive.",
    impact = "FPS", impactLevel = "High", category = "Performance",
    estimate = "~3-8 FPS in combat with streamer mode enabled",
})
ns:RegisterPatch("Details", {
    key = "Details_npcIdCache", label = "Enemy Info Cache",
    help = "Remembers enemy info so it doesn't have to figure it out again during every fight.",
    detail = "Details figures out enemy IDs using slow pattern matching, and redoes this dozens of times per refresh for the same enemies. During raid boss fights with many adds, this causes noticeable lag spikes when the meter updates.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~1-3 FPS during large pulls with many adds",
})
ns:RegisterPatch("Details", {
    key = "Details_formatCache", label = "Number Format Cache",
    help = "Caches formatted damage and heal numbers to avoid recalculating the same values.",
    detail = "Details formats the same damage totals repeatedly during each window refresh -- 10-50 times across multiple meter windows. This patch caches the last 200 formatted results so identical numbers are returned instantly instead of rebuilt every time.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~1-2 FPS with multiple meter windows open",
})

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

    -- Handle both calling conventions: Details:hex(num) and Details.hex(num)
    Details.hex = function(selfOrNum, num)
        if num then
            return format("%02x", num)
        else
            return format("%02x", selfOrNum)
        end
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

    if not Details.FadeHandler.frames then return end

    local originalOnUpdate = fadeFrame:GetScript("OnUpdate")
    if not originalOnUpdate then return end

    -- Wrap: skip the real handler when there is nothing to process
    -- Read frames table inside the closure each time in case Details replaces it
    fadeFrame:SetScript("OnUpdate", function(self, deltaTime)
        local frames = Details.FadeHandler.frames
        if not frames or not next(frames) then
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
            -- Sentinel false means the original returned nil
            if cached == false then return nil end
            return cached
        end

        local result = origGetNpcId(self, guid)

        -- Prevent unbounded growth (wipe before insert so new entry survives)
        if cacheCount >= 500 then
            wipe(cache)
            cacheCount = 0
        end

        -- Use false sentinel for nil results so they are cached too
        cache[guid] = (result ~= nil) and result or false
        cacheCount = cacheCount + 1

        return result
    end
end

------------------------------------------------------------------------
-- 5. Details_formatCache
--
-- Details.ToK2() formats damage/heal numbers for display in meter bars.
-- It is called 10-50 times per window refresh for bar labels, and the
-- same total values often repeat across multiple windows or refreshes.
--
-- Fix: Cache the last 200 formatted results.  Wipe when the cache grows
-- beyond 200 entries to prevent unbounded memory use during long
-- sessions with many unique values (boss encounters with varying DoT
-- ticks, etc.).
------------------------------------------------------------------------
ns.patches["Details_formatCache"] = function()
    if not Details then return end
    if not Details.ToK2 then return end

    local origToK2 = Details.ToK2
    local cache = {}
    local cacheCount = 0

    Details.ToK2 = function(self, number)
        if not number then return origToK2(self, number) end

        local cached = cache[number]
        if cached then return cached end

        if cacheCount >= 200 then
            wipe(cache)
            cacheCount = 0
        end

        local result = origToK2(self, number)
        cache[number] = result
        cacheCount = cacheCount + 1

        return result
    end
end
