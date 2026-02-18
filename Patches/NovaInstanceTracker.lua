------------------------------------------------------------------------
-- PatchWerk - Compatibility patches for NovaInstanceTracker
--
-- NovaInstanceTracker is a dungeon/raid lockout tracker that was
-- written primarily for retail and Wrath Classic.  It uses several
-- APIs that do not exist in TBC Classic Anniversary, causing hard
-- crashes on login.  These patches add guards for missing APIs:
--
--   1. NovaInstanceTracker_weeklyResetGuard
--        Guard C_DateAndTime.GetSecondsUntilWeeklyReset() which does
--        not exist in TBC Classic.  Without this patch the addon
--        errors immediately during OnInitialize.
--
--   2. NovaInstanceTracker_settingsCompat
--        Guard Settings.OpenToCategory() which was added in 10.x
--        retail.  Falls back to the Classic-era
--        InterfaceOptionsFrame_OpenToCategory() API.
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns.patchInfo[#ns.patchInfo+1] = {
    key = "NovaInstanceTracker_weeklyResetGuard", group = "NovaInstanceTracker", label = "Fix Login Crash",
    help = "Prevents the addon from crashing every time you log in on TBC Classic Anniversary.",
    detail = "NovaInstanceTracker tries to calculate your weekly reset timer during login using a method that does not exist in TBC Classic Anniversary. This causes the addon to throw an error on every login, potentially breaking its tracking features. This fix safely handles the missing timer so the addon loads without errors.",
    impact = "FPS", impactLevel = "High", category = "Fixes",
    estimate = "Fixes addon crash that happened every time you logged in",
    targetVersion = "2.17",
}
ns.patchInfo[#ns.patchInfo+1] = {
    key = "NovaInstanceTracker_settingsCompat", group = "NovaInstanceTracker", label = "Fix Settings Menu",
    help = "Fixes the /nit config command so it opens the settings panel instead of throwing an error.",
    detail = "Typing '/nit config' to open the addon's settings tries to use a method that only exists in Retail WoW. On TBC Classic Anniversary, this causes a crash instead of showing the options panel. This fix makes the command open settings correctly on Classic.",
    impact = "FPS", impactLevel = "High", category = "Fixes",
    estimate = "Fixes settings menu that would crash on Classic",
    targetVersion = "2.17",
}

------------------------------------------------------------------------
-- 1. NovaInstanceTracker_weeklyResetGuard  (Bug fix - Critical)
--
-- NIT:updateWeeklyResetTime() is called during OnInitialize and
-- unconditionally calls C_DateAndTime.GetSecondsUntilWeeklyReset().
-- This API does not exist in TBC Classic Anniversary, resulting in a
-- "attempt to index global 'C_DateAndTime'" or "attempt to call nil"
-- error that prevents the addon from loading at all.
--
-- Fix: Replace the function with a guarded version that checks for
-- C_DateAndTime and GetSecondsUntilWeeklyReset before calling them.
-- If the API is unavailable the function silently returns, leaving
-- the weeklyResetTime at whatever value the saved variables hold.
------------------------------------------------------------------------
ns.patches["NovaInstanceTracker_weeklyResetGuard"] = function()
    if not NIT then return end

    NIT.updateWeeklyResetTime = function(self)
        if not C_DateAndTime or not C_DateAndTime.GetSecondsUntilWeeklyReset then return end
        self.db.global[self.realm].weeklyResetTime = GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()
    end
end

------------------------------------------------------------------------
-- 2. NovaInstanceTracker_settingsCompat  (Bug fix - Critical)
--
-- NIT:openConfig() calls Settings.OpenToCategory(self.NITOptions.name)
-- which was introduced in retail 10.0 (Dragonflight).  In TBC Classic
-- the Settings global does not exist and the call produces a hard
-- error when the user tries to open the addon's configuration.
--
-- Fix: Replace with a version that checks for the modern API first
-- and falls back to InterfaceOptionsFrame_OpenToCategory().  The
-- double call to InterfaceOptionsFrame_OpenToCategory is a well-known
-- Classic workaround: the first call opens the Interface Options panel
-- and the second call actually navigates to the correct sub-category.
--
-- self.NITOptions is the frame returned by AceConfigDialog's
-- AddToBlizOptions("NovaInstanceTracker", "NovaInstanceTracker").
------------------------------------------------------------------------
ns.patches["NovaInstanceTracker_settingsCompat"] = function()
    if not NIT then return end

    NIT.openConfig = function(self)
        if Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(self.NITOptions.name)
        else
            InterfaceOptionsFrame_OpenToCategory(self.NITOptions)
            InterfaceOptionsFrame_OpenToCategory(self.NITOptions)
        end
    end
end
