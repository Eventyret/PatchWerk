------------------------------------------------------------------------
-- PatchWerk - Fix for EasyFrames health text number formatting
--
-- EasyFrames uses "T" as the abbreviation for thousands in its
-- ReadableNumber function, which confuses players into thinking
-- health values are in trillions.  Additionally, values in the
-- 1M-9.9M range incorrectly use "T" instead of "M", and the
-- string-truncation approach (%.Ns) produces inaccurate results.
--
-- Fix: Hook each health bar's UpdateTextString so we run AFTER
-- EasyFrames sets the buggy text, then re-set it with correct
-- K/M/B suffixes.  This bypasses the local-upvalue caching issue
-- entirely — we don't need to replace any EasyFrames functions.
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("EasyFrames", {
    key = "EasyFrames_healthTextFix", label = "Health Text Fix",
    help = "Fixes confusing 'T' suffix on health numbers -- changes to standard K/M/B abbreviations.",
    detail = "EasyFrames uses 'T' for thousands (e.g. '30T' for 30,000 HP) which looks like trillions. It also mislabels values in the 1-9.9 million range as 'T'. The fix replaces the number formatting with standard K (thousands), M (millions), B (billions).",
    impact = "FPS", impactLevel = "Low", category = "Tweaks",
    estimate = "Correct K/M/B abbreviations on health text",
})

ns.patches["EasyFrames_healthTextFix"] = function()
    if not EasyFrames then return end

    local UnitHealth = UnitHealth
    local UnitHealthMax = UnitHealthMax
    local format = string.format

    -- Corrected number abbreviation: K, M, B
    local function ReadableNumber(num)
        if not num then
            return 0
        elseif num >= 1000000000 then
            return format("%.1fB", num / 1000000000)
        elseif num >= 1000000 then
            return format("%.1fM", num / 1000000)
        elseif num >= 1000 then
            return format("%.0fK", num / 1000)
        else
            return num
        end
    end

    -- Re-set health text with corrected suffixes.
    -- Called as a post-hook on each health bar's UpdateTextString,
    -- so it runs AFTER EasyFrames has set its buggy "T" text.
    local function FixHealthText(bar, dbKey)
        local profile = EasyFrames.db and EasyFrames.db.profile
        if not profile or not profile[dbKey] then return end

        local hf = profile[dbKey].healthFormat
        -- Only fix the formats that use ReadableNumber (2, 3, 4)
        if hf ~= "2" and hf ~= "3" and hf ~= "4" then return end

        local unit = bar.unit
        if not unit then return end

        local health = UnitHealth(unit)
        if not health or health <= 0 then return end
        local healthMax = UnitHealthMax(unit)
        if not healthMax or healthMax <= 0 then return end

        local textString = bar.TextString
        if not textString then return end

        if hf == "2" then
            textString:SetText(ReadableNumber(health) .. " / " .. ReadableNumber(healthMax))
        elseif hf == "3" then
            local pct = (health / healthMax) * 100
            textString:SetText(ReadableNumber(health) .. " / " .. ReadableNumber(healthMax) .. " (" .. format("%.0f", pct) .. "%)")
        elseif hf == "4" then
            local pct = (health / healthMax) * 100
            textString:SetText(ReadableNumber(health) .. " (" .. format("%.0f", pct) .. "%)")
        end
    end

    -- Hook each health bar's UpdateTextString directly.
    -- Our hook fires AFTER both the default handler and EasyFrames' hook,
    -- so we simply overwrite the buggy text with the corrected version.
    local bars = {
        { global = "TargetFrameHealthBar", dbKey = "target" },
        { global = "FocusFrameHealthBar",  dbKey = "focus" },
        { global = "PetFrameHealthBar",    dbKey = "pet" },
    }

    for _, info in ipairs(bars) do
        local bar = _G[info.global]
        if bar then
            hooksecurefunc(bar, "UpdateTextString", function(self)
                FixHealthText(self, info.dbKey)
            end)
        end
    end

    -- Player health bar uses a getter function in some versions
    local playerBar = PlayerFrameHealthBar
        or (PlayerFrame_GetHealthBar and PlayerFrame_GetHealthBar())
    if playerBar then
        hooksecurefunc(playerBar, "UpdateTextString", function(self)
            FixHealthText(self, "player")
        end)
    end
end
