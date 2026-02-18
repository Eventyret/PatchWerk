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
ns.patchInfo[#ns.patchInfo+1] = {
    key = "OmniCC_gcdSpellCache", group = "OmniCC", label = "Cooldown Status Cache",
    help = "Checks the Global Cooldown once per update instead of 20+ times.",
    detail = "Every time you press an ability and trigger the global cooldown, OmniCC checks it 20+ times across all your action bars. This creates micro-stuttering during ability spam, especially noticeable in PvP and fast raid rotations.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~1-2 FPS during ability rotation",
    targetVersion = "11.2.8",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "OmniCC_ruleMatchCache", group = "OmniCC", label = "Display Rule Cache",
    help = "Remembers which cooldown display settings apply to each ability. Resets on profile change.",
    detail = "OmniCC figures out which display settings apply to each cooldown by checking every one against a list of rules. Since these never change during gameplay, it's doing hundreds of identical lookups for no reason.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "Reduced microstutter when multiple cooldowns trigger",
    targetVersion = "11.2.8",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "OmniCC_finishEffectGuard", group = "OmniCC", label = "Finish Effect Guard",
    help = "Skips cooldown finish animations for abilities that aren't close to coming off cooldown.",
    detail = "OmniCC tries to play cooldown-finished animations even for abilities that are nowhere near ready. The fix skips this wasted work unless an ability is actually within 2 seconds of being usable again.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "~0.5-1 FPS during active combat with many abilities",
    targetVersion = "11.2.8",
}

local GetTime = GetTime

------------------------------------------------------------------------
-- 1. OmniCC_gcdSpellCache
--
-- OmniCC calls GetSpellCooldown(61304) twice per SetTimer invocation:
-- once in IsGCD() and once in GetGCDTimeRemaining().  When the GCD
-- fires, SetCooldown triggers on 12+ action buttons simultaneously,
-- producing 24+ redundant C API crossings per GCD cycle.  The result
-- is identical within a single frame.
--
-- Fix: Wrap GetSpellCooldown with a per-frame cache for spell ID 61304.
-- All other spell IDs pass through unmodified.
------------------------------------------------------------------------
ns.patches["OmniCC_gcdSpellCache"] = function()
    if not OmniCC then return end

    local GCD_SPELL_ID = 61304
    local cacheFrame = -1
    local cacheA, cacheB, cacheC, cacheD
    local origGetSpellCooldown = GetSpellCooldown

    GetSpellCooldown = function(spellID)
        if spellID == GCD_SPELL_ID then
            local now = GetTime()
            if now ~= cacheFrame then
                cacheFrame = now
                cacheA, cacheB, cacheC, cacheD = origGetSpellCooldown(GCD_SPELL_ID)
            end
            return cacheA, cacheB, cacheC, cacheD
        end
        return origGetSpellCooldown(spellID)
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
