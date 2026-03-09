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
    ["Details"]      = "#Details.20260304.14718.170", -- verified 2026-03-09
    ["Plater"]       = "Plater-v635-TBC",             -- verified 2026-03-09
    ["Questie"]      = "11.23.0",                     -- verified 2026-03-09
    ["TitanPanel"]   = "9.1.2",                       -- verified 2026-03-09
    ["BigWigs"]      = "v407.9",                      -- verified 2026-03-09
    ["MoveAny"]      = "1.8.258",                     -- verified 2026-03-09
    ["LeatrixMaps"]  = "2.5.11",                      -- verified 2026-03-09
    ["LeatrixPlus"]  = "2.5.11",                      -- verified 2026-03-09
    ["ElvUI"]        = "v15.08",                      -- verified 2026-03-09
    ["Sonah"]        = "1.9.5",                       -- verified 2026-03-09
    ["Prat"]         = "3.9.93",                      -- verified 2026-03-09
}
