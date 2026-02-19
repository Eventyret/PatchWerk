------------------------------------------------------------------------
-- PatchWerk - Compatibility and performance patches for BugSack
--
-- BugSack is a popular error display addon that pairs with !BugGrabber.
-- The latest version targets Retail's Settings API which does not exist
-- in TBC Classic Anniversary, and has a few hot paths that benefit
-- from caching and debouncing.  These patches address:
--   1. BugSack_settingsCompat  - Replace Settings.OpenToCategory calls
--                                with the Classic-compatible
--                                InterfaceOptionsFrame_OpenToCategory
--   2. BugSack_formatCache     - Cache FormatError results on error
--                                objects to avoid 15 gsub calls per
--                                repeated render
--   3. BugSack_searchThrottle  - Debounce the filterSack search so it
--                                only fires after 0.3s of idle typing
--                                instead of on every keystroke
------------------------------------------------------------------------

local _, ns = ...
local C_Timer = C_Timer

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("BugSack", {
    key = "BugSack_settingsCompat", label = "Fix Settings Menu",
    help = "Stops BugSack from throwing errors when you try to open its settings panel.",
    detail = "BugSack's latest version tries to open its settings using a method that only works on Retail WoW. On TBC Classic Anniversary, clicking the settings option from the slash command, right-clicking the sack, or right-clicking the broker icon would cause an error instead of opening settings. This fix makes all three entry points open the settings panel correctly.",
    impact = "FPS", impactLevel = "High", category = "Fixes",
    estimate = "Fixes broken settings menu that would throw errors on Classic",
})
ns:RegisterPatch("BugSack", {
    key = "BugSack_formatCache", label = "Faster Error Viewing",
    help = "Speeds up scrolling through captured errors by remembering previously formatted text.",
    detail = "Every time you view an error in the sack, the addon re-processes and re-colors the entire error text from scratch, even if you already looked at it. When you have many errors captured, scrolling through them can feel sluggish as the addon does this heavy text processing repeatedly. This fix remembers the formatted result so each error is only processed once.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "Faster scrolling through the error list when many errors are captured",
})
ns:RegisterPatch("BugSack", {
    key = "BugSack_searchThrottle", label = "Smoother Search Typing",
    help = "Waits until you pause typing before searching, so the search box does not lag on every keypress.",
    detail = "The search box in BugSack tries to filter through all captured errors after every single keystroke. If you have hundreds of errors saved, this causes noticeable lag and stuttering while you type. This fix waits until you stop typing for a moment before running the search, keeping the input responsive.",
    impact = "FPS", impactLevel = "Low", category = "Performance",
    estimate = "Smoother typing in the error search box without input lag",
})

------------------------------------------------------------------------
-- 1. BugSack_settingsCompat  (Bug fix)
--
-- BugSack calls Settings.OpenToCategory(addon.settingsCategory:GetID())
-- in three places:
--   core.lua  - SlashCmdList.BugSack handler (when msg ~= "show")
--   sack.lua  - sessionLabel OnClick (right-click to open options)
--   ldb.lua   - plugin.OnClick (right-click the LDB data object)
--
-- The Settings API does not exist in TBC Classic Anniversary (20505).
-- Fix: After BugSack loads, replace SlashCmdList.BugSack with a
-- version that uses InterfaceOptionsFrame_OpenToCategory, hook the
-- sack's sessionLabel OnClick, and hook the LDB plugin.OnClick.
------------------------------------------------------------------------
ns.patches["BugSack_settingsCompat"] = function()
    if not BugSack then return end
    -- Only patch if the modern Settings API is missing
    if Settings and Settings.OpenToCategory then return end
    if not InterfaceOptionsFrame_OpenToCategory then return end

    local addon = BugSack

    -- Helper: open BugSack's options panel via the Classic API.
    -- InterfaceOptionsFrame_OpenToCategory often needs to be called
    -- twice on Classic to actually navigate to the right panel.
    local function openOptions()
        InterfaceOptionsFrame_OpenToCategory("BugSack")
        InterfaceOptionsFrame_OpenToCategory("BugSack")
    end

    -- (a) Patch SlashCmdList.BugSack
    -- The original: if msg == "show" then addon:OpenSack() else Settings.OpenToCategory(...) end
    SlashCmdList.BugSack = function(msg)
        msg = msg:lower()
        if msg == "show" then
            addon:OpenSack()
        else
            openOptions()
        end
    end

    -- (b) Patch sack.lua sessionLabel OnClick
    -- The sessionLabel is created inside createBugSack() which fires
    -- lazily on first OpenSack.  We hook addon.OpenSack so that after
    -- the sack frame is created we can re-wire the OnClick handler.
    local sackHooked = false
    hooksecurefunc(addon, "OpenSack", function()
        if sackHooked then return end
        local frame = _G["BugSackFrame"]
        if not frame then return end

        -- sessionLabel is the title-bar button that supports right-click.
        -- It's the first child Button of BugSackFrame that has an OnClick
        -- handler referencing Settings.  We iterate children to find it.
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            if child:IsObjectType("Button") and child:GetScript("OnClick") then
                local script = child:GetScript("OnClick")
                -- Replace the OnClick that contains the Settings call
                -- We identify it by checking if it's a button anchored to
                -- the title region (has NormalFontObject set to Left).
                local font = child:GetNormalFontObject()
                if font and font == GameFontNormalLeft then
                    child:SetScript("OnClick", function(self, button)
                        if button ~= "RightButton" then
                            return
                        end
                        frame:Hide()
                        openOptions()
                    end)
                    break
                end
            end
        end
        sackHooked = true
    end)

    -- (c) Patch ldb.lua plugin.OnClick
    -- The LDB data object is registered as "BugSack" via LibDataBroker.
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    if ldb then
        local dataObj = ldb:GetDataObjectByName("BugSack")
        if dataObj and dataObj.OnClick then
            local origOnClick = dataObj.OnClick
            dataObj.OnClick = function(self, button)
                if button == "RightButton" then
                    openOptions()
                else
                    -- Delegate everything else to the original handler.
                    -- We need to avoid calling origOnClick because it
                    -- would also hit Settings.OpenToCategory on right-click.
                    -- For non-right-click, replicate the original logic.
                    if IsShiftKeyDown() then
                        ReloadUI()
                    elseif IsAltKeyDown() and (addon.db.altwipe == true) then
                        addon:Reset()
                    elseif BugSackFrame and BugSackFrame:IsShown() then
                        addon:CloseSack()
                    else
                        addon:OpenSack()
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- 2. BugSack_formatCache  (Performance)
--
-- addon:FormatError(err) runs colorStack (8 gsub calls) and
-- colorLocals (7+ gsub calls) every time it formats an error, even
-- if the same error object was already formatted and nothing changed.
-- The formatted output only depends on the error's message, stack,
-- locals, and counter fields.
--
-- Fix: Cache the formatted result on the error object using a private
-- key.  Also store the counter value at formatting time so the cache
-- is invalidated when the error recurs (counter increments).
------------------------------------------------------------------------
ns.patches["BugSack_formatCache"] = function()
    if not BugSack then return end

    local addon = BugSack
    if not addon.FormatError then return end

    local origFormatError = addon.FormatError

    addon.FormatError = function(self, err)
        if type(err) ~= "table" then
            return origFormatError(self, err)
        end

        -- Invalidate the cache if the counter changed (error recurred)
        if err._pwFormatted and err._pwFormatCounter == err.counter then
            return err._pwFormatted
        end

        local result = origFormatError(self, err)
        err._pwFormatted = result
        err._pwFormatCounter = err.counter
        return result
    end
end

------------------------------------------------------------------------
-- 3. BugSack_searchThrottle  (Performance)
--
-- In sack.lua, the search editbox's OnTextChanged handler calls
-- filterSack(editbox) on every keystroke.  filterSack does a linear
-- scan of all errors, checking message/stack/locals with string.find.
-- With hundreds of captured errors, this causes noticeable input lag
-- while typing a search query.
--
-- Fix: Replace the OnTextChanged handler on the searchBox with a
-- debounced version that waits 0.3 seconds of idle time before
-- actually running the filter.  Uses C_Timer.NewTimer to schedule
-- the search callback after the debounce delay.
------------------------------------------------------------------------
ns.patches["BugSack_searchThrottle"] = function()
    if not BugSack then return end

    local addon = BugSack
    if not addon.OpenSack then return end

    local DEBOUNCE_DELAY = 0.3
    local throttleHooked = false

    hooksecurefunc(addon, "OpenSack", function()
        if throttleHooked then return end
        local frame = _G["BugSackFrame"]
        if not frame then return end

        -- Find the searchBox: it's the EditBox child of BugSackFrame.
        local searchBox = nil
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            if child:IsObjectType("EditBox") then
                searchBox = child
                break
            end
        end

        if not searchBox then return end

        -- Grab the original filterSack handler that was set as OnTextChanged.
        local origOnTextChanged = searchBox:GetScript("OnTextChanged")
        if not origOnTextChanged then return end

        local searchTimer = nil

        -- Replace the OnTextChanged with our debounced version.
        searchBox:SetScript("OnTextChanged", function(editbox)
            if searchTimer then
                searchTimer:Cancel()
            end
            searchTimer = C_Timer.NewTimer(DEBOUNCE_DELAY, function()
                searchTimer = nil
                origOnTextChanged(editbox)
            end)
        end)

        throttleHooked = true
    end)
end
