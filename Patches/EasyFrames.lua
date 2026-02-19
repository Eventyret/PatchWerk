------------------------------------------------------------------------
-- PatchWerk - Fix for EasyFrames health text number formatting
--
-- EasyFrames uses "T" as the abbreviation for thousands in its
-- ReadableNumber function, which confuses players into thinking
-- health values are in trillions.  Additionally, values in the
-- 1M-9.9M range incorrectly use "T" instead of "M", and the
-- string-truncation approach (%.Ns) produces inaccurate results.
--
-- Fix: Hook each health bar TextString's SetText to intercept the
-- buggy "T" suffix and rewrite it to K/M.  This fires on every
-- SetText call regardless of who triggers it, bypassing all
-- upvalue caching and hook ordering issues.
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

    local format = string.format
    local tonumber = tonumber

    -- Fix EasyFrames' buggy "T" suffix in health text.
    -- EasyFrames' ReadableNumber produces:
    --   10K-99K   → "30T"   (should be "30K")
    --   100K-999K → "500T"  (should be "500K")
    --   1M-9.9M   → "1500T" (should be "1.5M")
    -- Pattern: 4-digit + T = millions, 1-3 digit + T = thousands.
    local function FixHealthFormat(text)
        -- 4-digit + T → millions (e.g. "1500T" → "1.5M")
        text = text:gsub("(%d%d%d%d)T", function(digits)
            return format("%.1fM", tonumber(digits) / 1000)
        end)
        -- 1-3 digit + T → thousands (e.g. "30T" → "30K")
        text = text:gsub("(%d+)T", function(digits)
            return digits .. "K"
        end)
        return text
    end

    -- Hook the TextString's SetText on each health bar.
    -- This intercepts text at the display layer — no matter who calls
    -- SetText (Blizzard, EasyFrames, any other addon), the "T" suffix
    -- gets fixed before it reaches the screen.
    local function HookTextString(bar)
        if not bar then return end
        local ts = bar.TextString
        if not ts then return end

        local origSetText = ts.SetText
        ts.SetText = function(self, text, ...)
            if type(text) == "string" and text:find("%dT") then
                text = FixHealthFormat(text)
            end
            return origSetText(self, text, ...)
        end
    end

    HookTextString(TargetFrameHealthBar)
    HookTextString(FocusFrameHealthBar)
    HookTextString(PetFrameHealthBar)
    HookTextString(PlayerFrameHealthBar
        or (PlayerFrame_GetHealthBar and PlayerFrame_GetHealthBar()))
end
