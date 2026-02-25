------------------------------------------------------------------------
-- PatchWerk - Performance patches for OmniCC (Cooldown Text)
--
-- OmniCC hooks every cooldown frame to display countdown text.  On TBC
-- Classic Anniversary several hot paths cause redundant API calls:
--   1. OmniCC_gcdSpellCache     - Cache GetSpellCooldown(61304) per frame
--   2. OmniCC_ruleMatchCache    - Cache GetMatchingRule results by name
--   3. OmniCC_finishEffectGuard - Skip finish effect for non-expiring CDs
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("OmniCC", {
    key = "OmniCC_gcdSpellCache", label = "Cooldown Status Cache",
    help = "Checks the Global Cooldown once per update instead of 20+ times.",
    detail = "Every time you press an ability and trigger the global cooldown, OmniCC checks it 20+ times across all your action bars. This creates micro-stuttering during ability spam, especially noticeable in PvP and fast raid rotations.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~1-2 FPS during ability rotation",
})
ns:RegisterPatch("OmniCC", {
    key = "OmniCC_ruleMatchCache", label = "Display Rule Cache",
    help = "Remembers which cooldown display settings apply to each ability. Resets on profile change.",
    detail = "OmniCC figures out which display settings apply to each cooldown by checking every one against a list of rules. Since these never change during gameplay, it's doing hundreds of identical lookups for no reason.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "Reduced microstutter when multiple cooldowns trigger",
})
ns:RegisterPatch("OmniCC", {
    key = "OmniCC_finishEffectGuard", label = "Finish Effect Guard",
    help = "Skips cooldown finish animations for abilities that aren't close to coming off cooldown.",
    detail = "OmniCC tries to play cooldown-finished animations even for abilities that are nowhere near ready. The fix skips this wasted work unless an ability is actually within 2 seconds of being usable again.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "~0.5-1 FPS during active combat with many abilities",
})

local GetTime = GetTime
local GetSpellCooldown = GetSpellCooldown

------------------------------------------------------------------------
-- 1. OmniCC_gcdSpellCache
--
-- OmniCC calls GetSpellCooldown(61304) via its local IsGCD() function
-- inside Cooldown:SetTimer().  When the GCD fires, SetCooldown triggers
-- on 12+ action buttons simultaneously, each calling IsGCD() and
-- producing 12+ redundant C API crossings per GCD cycle.
--
-- Fix: Replace OmniCC.Cooldown.SetTimer with an optimized version that
-- inlines the GCD detection with a per-frame cache.  This avoids
-- replacing _G.GetSpellCooldown, which caused taint propagation to
-- SpellBookFrame and ADDON_ACTION_FORBIDDEN on CastSpell().
------------------------------------------------------------------------
ns.patches["OmniCC_gcdSpellCache"] = function()
    if not OmniCC then return end
    if not OmniCC.Cooldown then return end

    local GCD_SPELL_ID = 61304
    local Cooldown = OmniCC.Cooldown

    -- Verify required methods exist (guards against OmniCC version changes)
    if not Cooldown.SetTimer or not Cooldown.TryShowFinishEffect
       or not Cooldown.GetKind or not Cooldown.GetPriority
       or not Cooldown.CanShowText or not Cooldown.RequestUpdate then
        return
    end

    -- Per-frame GCD value cache
    local cacheTime = -1
    local gcdStart, gcdDuration, gcdEnabled, gcdModRate

    -- Replace SetTimer with version that caches GCD lookups per-frame.
    -- Faithfully reimplements OmniCC's Cooldown:SetTimer (cooldown.lua)
    -- but replaces the local IsGCD() call with an inlined per-frame cache.
    Cooldown.SetTimer = function(self, start, duration, modRate)
        if modRate == nil then
            modRate = 1
        end

        -- Exact match early-exit (original line 458)
        if self._occ_start == start and self._occ_duration == duration and self._occ_modRate == modRate then
            return
        end

        -- Show finish effect for previous cooldown state (original line 464)
        Cooldown.TryShowFinishEffect(self)

        self._occ_start = start
        self._occ_duration = duration
        self._occ_modRate = modRate

        -- Inline GCD detection with per-frame cache (replaces IsGCD call)
        if start > 0 and duration > 0 and modRate > 0 then
            local now = GetTime()
            if now ~= cacheTime then
                cacheTime = now
                gcdStart, gcdDuration, gcdEnabled, gcdModRate = GetSpellCooldown(GCD_SPELL_ID)
            end
            self._occ_gcd = (gcdEnabled and true or false)
                and start == gcdStart
                and duration == gcdDuration
                and modRate == gcdModRate
        else
            self._occ_gcd = false
        end

        self._occ_kind = Cooldown.GetKind(self)
        self._occ_priority = Cooldown.GetPriority(self)
        self._occ_show = Cooldown.CanShowText(self)

        Cooldown.RequestUpdate(self)
    end
end

------------------------------------------------------------------------
-- 2. OmniCC_ruleMatchCache
--
-- OmniCC:GetMatchingRule(name) iterates all active rules, running Lua
-- pattern matching per rule per cooldown frame name.  Frame names never
-- change at runtime, so results can be cached and only invalidated on
-- profile changes.
--
-- Fix: Cache results by frame name.  Invalidate on profile switch.
------------------------------------------------------------------------
ns.patches["OmniCC_ruleMatchCache"] = function()
    if not OmniCC then return end
    if not OmniCC.GetMatchingRule then return end

    local cache = {}
    local wipe = wipe

    local origGetMatchingRule = OmniCC.GetMatchingRule
    OmniCC.GetMatchingRule = function(self, name)
        if not name then return origGetMatchingRule(self, name) end
        local cached = cache[name]
        if cached ~= nil then
            if cached == false then return false end
            return cached
        end
        local result = origGetMatchingRule(self, name)
        cache[name] = (result ~= nil and result ~= false) and result or false
        return result
    end

    if OmniCC.OnProfileChanged then
        local origChanged = OmniCC.OnProfileChanged
        OmniCC.OnProfileChanged = function(self, ...)
            wipe(cache)
            return origChanged(self, ...)
        end
    end

    if OmniCC.OnProfileReset then
        local origReset = OmniCC.OnProfileReset
        OmniCC.OnProfileReset = function(self, ...)
            wipe(cache)
            return origReset(self, ...)
        end
    end
end

------------------------------------------------------------------------
-- 3. OmniCC_finishEffectGuard
--
-- TryShowFinishEffect is called unconditionally inside SetTimer on
-- every cooldown update.  It invokes GetGCDTimeRemaining (another
-- GetSpellCooldown call).  For cooldowns that clearly cannot be
-- finishing (no previous active state or far from expiry), the chain
-- is wasted work.
--
-- Fix: Fast pre-check on previous cooldown state.  Only call the
-- original when a cooldown was active and is near expiry (<2s).
------------------------------------------------------------------------
ns.patches["OmniCC_finishEffectGuard"] = function()
    if not OmniCC then return end
    if not OmniCC.Cooldown or not OmniCC.Cooldown.TryShowFinishEffect then return end

    local origTry = OmniCC.Cooldown.TryShowFinishEffect
    OmniCC.Cooldown.TryShowFinishEffect = function(self)
        local prevStart = self._occ_start
        local prevDuration = self._occ_duration
        if not prevStart or prevStart <= 0 or not prevDuration or prevDuration <= 0 then
            return
        end
        local remain = (prevStart + prevDuration) - GetTime()
        if remain > 2 or remain < -0.5 then
            return
        end
        return origTry(self)
    end
end
