------------------------------------------------------------------------
-- PatchWerk - Fix for EasyFrames health text number formatting
--
-- EasyFrames uses "T" as the abbreviation for thousands in its
-- ReadableNumber function, which confuses players into thinking
-- health values are in trillions.  Additionally, values in the
-- 1M-9.9M range incorrectly use "T" instead of "M", and the
-- string-truncation approach (%.Ns) produces inaccurate results.
--
-- Fix: Replace UpdateHealthValues with a version that uses a
-- corrected ReadableNumber using proper division and standard
-- suffixes: K for thousands, M for millions, B for billions.
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("EasyFrames", {
    key = "EasyFrames_healthTextFix", label = "Health Text Fix",
    help = "Fixes confusing 'T' suffix on health numbers -- changes to standard K/M/B abbreviations.",
    detail = "EasyFrames uses 'T' for thousands (e.g. '36T' for 36,000 HP) which looks like trillions. It also mislabels values in the 1-9.9 million range as 'T'. The fix replaces the number formatting with standard K (thousands), M (millions), B (billions).",
    impact = "FPS", impactLevel = "Low", category = "Tweaks",
    estimate = "Correct K/M/B abbreviations on health text",
})

ns.patches["EasyFrames_healthTextFix"] = function()
    if not EasyFrames then return end
    if not EasyFrames.Utils then return end
    if not EasyFrames.Utils.UpdateHealthValues then return end

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

    local origUpdate = EasyFrames.Utils.UpdateHealthValues

    EasyFrames.Utils.UpdateHealthValues = function(frame, healthFormat, customHealthFormat, customHealthFormatFormulas, useHealthFormatFullValues, useChineseNumeralsHealthFormat)
        -- Only intercept the formats that use ReadableNumber (2, 3, 4)
        -- Custom and percent-only formats are unaffected
        if healthFormat ~= "2" and healthFormat ~= "3" and healthFormat ~= "4" then
            return origUpdate(frame, healthFormat, customHealthFormat, customHealthFormatFormulas, useHealthFormatFullValues, useChineseNumeralsHealthFormat)
        end

        local unit = frame.unit
        local healthbar = frame:GetParent().healthbar

        if UnitHealth(unit) <= 0 then return end

        local Health = UnitHealth(unit)
        local HealthMax = UnitHealthMax(unit)

        if healthFormat == "2" then
            healthbar.TextString:SetText(ReadableNumber(Health) .. " / " .. ReadableNumber(HealthMax))
        elseif healthFormat == "3" then
            local HealthPercent = (Health / HealthMax) * 100
            healthbar.TextString:SetText(ReadableNumber(Health) .. " / " .. ReadableNumber(HealthMax) .. " (" .. format("%.0f", HealthPercent) .. "%)")
        elseif healthFormat == "4" then
            local HealthPercent = (Health / HealthMax) * 100
            healthbar.TextString:SetText(ReadableNumber(Health) .. " (" .. format("%.0f", HealthPercent) .. "%)")
        end
    end
end
