-- VersionOverrides.lua
-- Centralized version compatibility overrides for PatchWerk.
--
-- When a target addon updates but its patches still work fine, add an
-- override here instead of editing every Patches/*.lua file. The version
-- check system consults this table first, falling back to each patch's
-- targetVersion if no override exists.
--
-- Usage:
--   ns.versionOverrides["GroupId"] = "installed_version_string"
--
-- Workflow:
--   1. Run /patch-audit (or /pw outdated) to find mismatches
--   2. Verify the patches still work in-game
--   3. Add/update the override entry below
--   4. Only release when you have actual code changes to ship

local _, ns = ...

ns.versionOverrides = {
    ["Plater"] = "Plater-v632-TBC",   -- verified 2026-02-20
    ["BigDebuffs"] = "v58",            -- verified 2026-02-20
    ["BigWigs"] = "v406.5",            -- verified 2026-02-20
    ["LeatrixMaps"] = "2.5.09",       -- verified 2026-02-20
    ["LeatrixPlus"] = "2.5.09",       -- verified 2026-02-20
}
