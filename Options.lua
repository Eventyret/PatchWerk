-- Options: GUI settings panel and slash command interface for PatchWerk
--
-- Provides a scrollable Blizzard Interface Options panel with patch toggles
-- grouped by target addon, impact badges, and user-friendly descriptions.

local _, ns = ...

-- Impact badge colors
local BADGE_COLORS = {
    FPS     = { r = 0.2, g = 0.9, b = 0.2 },   -- green
    Memory  = { r = 0.2, g = 0.8, b = 0.9 },   -- cyan
    Network = { r = 1.0, g = 0.6, b = 0.2 },   -- orange
}

local LEVEL_COLORS = {
    High   = { r = 1.0, g = 1.0, b = 1.0 },
    Medium = { r = 0.8, g = 0.8, b = 0.8 },
    Low    = { r = 0.6, g = 0.6, b = 0.6 },
}

-- Patch metadata with user-friendly labels, help text, and impact info
local PATCH_INFO = {
    -- Details
    { key = "Details_hexFix",        group = "Details",  label = "Hex Encoder Fix",
      help = "Speeds up damage meter bar color rendering.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Details_fadeHandler",   group = "Details",  label = "Fade Handler Idle Guard",
      help = "Saves CPU when damage meter bars aren't animating.",
      impact = "FPS", impactLevel = "Low" },
    { key = "Details_refreshCap",    group = "Details",  label = "Refresh Rate Cap",
      help = "Prevents an extreme 60fps meter refresh that tanks FPS on Classic.",
      impact = "FPS", impactLevel = "High" },
    { key = "Details_npcIdCache",    group = "Details",  label = "NPC ID Cache",
      help = "Remembers NPC IDs to avoid repeated lookups during combat.",
      impact = "FPS", impactLevel = "Medium" },
    -- Plater
    { key = "Plater_fpsCheck",       group = "Plater",   label = "FPS Timer Allocation Fix",
      help = "Stops Plater from creating 60+ throwaway timers per second.",
      impact = "Memory", impactLevel = "High" },
    { key = "Plater_healthText",     group = "Plater",   label = "Health Text Skip",
      help = "Skips nameplate health text updates when nothing changed.",
      impact = "FPS", impactLevel = "Low" },
    { key = "Plater_auraAlign",      group = "Plater",   label = "Aura Alignment Guard",
      help = "Skips redundant buff/debuff icon rearrangement on nameplates.",
      impact = "Memory", impactLevel = "Medium" },
    -- Pawn
    { key = "Pawn_cacheIndex",       group = "Pawn",     label = "Cache Hash Index",
      help = "Makes tooltip item lookups instant instead of scanning 200 entries.",
      impact = "FPS", impactLevel = "High" },
    { key = "Pawn_tooltipDedup",     group = "Pawn",     label = "Tooltip Deduplication",
      help = "Prevents Pawn from processing the same item multiple times per hover.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Pawn_upgradeCache",     group = "Pawn",     label = "Upgrade Comparison Cache",
      help = "Remembers upgrade results so Pawn doesn't recalculate every hover.",
      impact = "FPS", impactLevel = "High" },
    -- TipTac
    { key = "TipTac_unitAppearanceGuard", group = "TipTac", label = "Non-Unit Tooltip Guard",
      help = "Stops per-frame tooltip updates when you're hovering items, not players.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "TipTac_inspectCache",   group = "TipTac",   label = "Extended Inspect Cache",
      help = "Reduces inspect spam from every 5s to every 30s in crowded areas.",
      impact = "Network", impactLevel = "Medium" },
    -- Questie
    { key = "Questie_questLogThrottle", group = "Questie", label = "Quest Log Burst Throttle",
      help = "Limits quest log rescans to twice per second during rapid updates.",
      impact = "FPS", impactLevel = "High" },
    { key = "Questie_availableQuestsDebounce", group = "Questie", label = "Available Quests Debounce",
      help = "Batches rapid quest availability checks into a single update.",
      impact = "FPS", impactLevel = "Medium" },
    -- LFGBulletinBoard
    { key = "LFGBulletinBoard_updateListDirty", group = "LFGBulletinBoard", label = "Dirty Flag UI Rebuild",
      help = "Skips the full group list rebuild when nothing changed.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "LFGBulletinBoard_sortSkip", group = "LFGBulletinBoard", label = "Sort Interval Throttle",
      help = "Limits group list sorting to once every 2 seconds.",
      impact = "FPS", impactLevel = "Low" },
    -- Bartender4
    { key = "Bartender4_lossOfControlSkip", group = "Bartender4", label = "Skip Loss of Control Events",
      help = "Stops 120-button scans for events that do nothing on Classic.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Bartender4_usableThrottle", group = "Bartender4", label = "Usability Update Debounce",
      help = "Batches rapid action bar usability checks into one update.",
      impact = "FPS", impactLevel = "High" },
    -- TitanPanel
    { key = "TitanPanel_reputationsOnUpdate", group = "TitanPanel", label = "Reputations Timer Fix",
      help = "Checks reputation only every 5s instead of every frame.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "TitanPanel_bagDebounce", group = "TitanPanel", label = "Bag Update Debounce",
      help = "Counts bag contents once after looting instead of per slot change.",
      impact = "FPS", impactLevel = "Low" },
    { key = "TitanPanel_performanceThrottle", group = "TitanPanel", label = "Performance Update Throttle",
      help = "Updates FPS/memory display every 3s instead of 1.5s.",
      impact = "FPS", impactLevel = "Low" },
    -- OmniCC
    { key = "OmniCC_gcdSpellCache", group = "OmniCC", label = "GCD Spell Cache",
      help = "Caches GCD status per-frame instead of querying 20+ times.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "OmniCC_ruleMatchCache", group = "OmniCC", label = "Rule Match Cache",
      help = "Remembers which cooldown rules match which frames permanently.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "OmniCC_finishEffectGuard", group = "OmniCC", label = "Finish Effect Guard",
      help = "Skips cooldown finish checks for abilities not close to ready.",
      impact = "FPS", impactLevel = "Low" },
    -- Prat-3.0
    { key = "Prat_smfThrottle", group = "Prat", label = "Chat Layout Throttle",
      help = "Reduces chat line redraws from 60fps to 20fps, saving thousands of API calls.",
      impact = "FPS", impactLevel = "High" },
    { key = "Prat_timestampCache", group = "Prat", label = "Timestamp Cache",
      help = "Renders chat timestamps once per second instead of per message.",
      impact = "Memory", impactLevel = "Low" },
    { key = "Prat_bubblesGuard", group = "Prat", label = "Bubble Scan Guard",
      help = "Skips chat bubble scanning when no one is talking nearby.",
      impact = "FPS", impactLevel = "Low" },
    -- GatherMate2
    { key = "GatherMate2_minimapThrottle", group = "GatherMate2", label = "Minimap Update Throttle",
      help = "Updates minimap pins at 20fps instead of 60fps.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "GatherMate2_rebuildGuard", group = "GatherMate2", label = "Stationary Rebuild Skip",
      help = "Skips minimap node rebuilds when you're standing still.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "GatherMate2_cleuUnregister", group = "GatherMate2", label = "Remove Dead Combat Handler",
      help = "Removes a dead combat log handler that fires hundreds of times in combat.",
      impact = "FPS", impactLevel = "Medium" },
    -- Quartz
    { key = "Quartz_castBarThrottle", group = "Quartz", label = "Cast Bar 30fps Cap",
      help = "Caps cast bar animations to 30fps - looks identical, uses half the CPU.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Quartz_swingBarThrottle", group = "Quartz", label = "Swing Timer 30fps Cap",
      help = "Caps swing timer to 30fps - imperceptible on a 2-3 second swing.",
      impact = "FPS", impactLevel = "Low" },
    { key = "Quartz_gcdBarThrottle", group = "Quartz", label = "GCD Bar 30fps Cap",
      help = "Caps the GCD spark animation to 30fps.",
      impact = "FPS", impactLevel = "Low" },
    -- Auctionator
    { key = "Auctionator_ownerQueryThrottle", group = "Auctionator", label = "Auction Query Throttle",
      help = "Reduces auction queries from 120/sec to 2/sec while AH is open.",
      impact = "Network", impactLevel = "High" },
    { key = "Auctionator_throttleBroadcast", group = "Auctionator", label = "Throttle Timer Broadcast",
      help = "Slows timeout countdown updates from 60/sec to 2/sec.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Auctionator_priceAgeOptimize", group = "Auctionator", label = "Price Age Optimizer",
      help = "Eliminates temporary tables when calculating price freshness.",
      impact = "Memory", impactLevel = "Medium" },
    { key = "Auctionator_dbKeyCache", group = "Auctionator", label = "DB Key Link Cache",
      help = "Caches item-to-database lookups instead of re-parsing on every hover.",
      impact = "FPS", impactLevel = "Medium" },
    -- VuhDo
    { key = "VuhDo_debuffDebounce", group = "VuhDo", label = "Debuff Detection Debounce",
      help = "Batches debuff scans during AoE damage, preventing 100+ rescans/sec.",
      impact = "FPS", impactLevel = "High" },
    { key = "VuhDo_rangeSkipDead", group = "VuhDo", label = "Skip Dead/DC Range Checks",
      help = "Skips range checking on dead or disconnected raid members.",
      impact = "FPS", impactLevel = "Low" },
}

-- Build lookup for patches by group
local PATCHES_BY_GROUP = {}
for _, p in ipairs(PATCH_INFO) do
    if not PATCHES_BY_GROUP[p.group] then
        PATCHES_BY_GROUP[p.group] = {}
    end
    table.insert(PATCHES_BY_GROUP[p.group], p)
end

-- Case-insensitive patch name resolver for slash commands
local PATCH_NAMES_LOWER = {}
for _, p in ipairs(PATCH_INFO) do
    PATCH_NAMES_LOWER[p.key:lower()] = p.key
end

-- Format an impact badge string with color codes
local function FormatBadge(impact, level)
    if not impact then return "" end
    local bc = BADGE_COLORS[impact] or BADGE_COLORS.FPS
    local lc = LEVEL_COLORS[level] or LEVEL_COLORS.Medium
    return string.format("|cff%02x%02x%02x[%s]|r |cff%02x%02x%02x%s|r",
        bc.r * 255, bc.g * 255, bc.b * 255, impact,
        lc.r * 255, lc.g * 255, lc.b * 255, level or "")
end

---------------------------------------------------------------------------
-- GUI Panel
---------------------------------------------------------------------------

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "PatchWerk"

    local checkboxes = {}
    local groupCheckboxes = {} -- [groupId] = { cb1, cb2, ... }
    local groupCountLabels = {} -- [groupId] = fontString
    local statusLabels = {}
    local contentBuilt = false

    local function RefreshStatusLabels()
        for _, info in ipairs(statusLabels) do
            local enabled = ns:GetOption(info.key)
            local applied = ns.applied[info.key]
            if applied then
                info.fontString:SetText("|cff33e633Active|r")
            elseif enabled and not applied then
                info.fontString:SetText("|cffffff00Reload|r")
            elseif not enabled then
                info.fontString:SetText("|cff808080Off|r")
            else
                info.fontString:SetText("")
            end
        end
    end

    local function RefreshGroupCounts()
        for groupId, cbs in pairs(groupCheckboxes) do
            local active = 0
            local total = #cbs
            for _, cb in ipairs(cbs) do
                if ns:GetOption(cb.optionKey) then
                    active = active + 1
                end
            end
            local label = groupCountLabels[groupId]
            if label then
                if active == total then
                    label:SetText("|cff33e633" .. active .. "/" .. total .. " active|r")
                elseif active > 0 then
                    label:SetText("|cffffff00" .. active .. "/" .. total .. " active|r")
                else
                    label:SetText("|cff808080" .. active .. "/" .. total .. " active|r")
                end
            end
        end
    end

    local function BuildContent()
        if contentBuilt then return end
        contentBuilt = true

        local scrollFrame = CreateFrame("ScrollFrame", "PatchWerk_OptionsScroll", panel, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 0, -10)
        scrollFrame:SetPoint("BOTTOMRIGHT", -26, 10)

        local content = CreateFrame("Frame")
        content:SetSize(580, 2000)
        scrollFrame:SetScrollChild(content)

        scrollFrame:SetScript("OnSizeChanged", function(self, w)
            if w and w > 0 then content:SetWidth(w) end
        end)

        -- Helpers
        local function AddSeparator(y, alpha)
            local line = content:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", 12, y)
            line:SetPoint("TOPRIGHT", -12, y)
            line:SetColorTexture(0.6, 0.6, 0.6, alpha or 0.25)
            return y - 8
        end

        -- Title
        local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("PatchWerk")

        local version = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        version:SetPoint("LEFT", title, "RIGHT", 6, 0)
        version:SetText("v" .. ns.VERSION)

        local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        subtitle:SetText("Performance patches for popular addons. Toggle patches below, then /reload.")
        subtitle:SetJustifyH("LEFT")

        -- Active count
        local activeCount = 0
        for _ in pairs(ns.applied) do activeCount = activeCount + 1 end
        local totalCount = #PATCH_INFO

        local countText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        countText:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -2)
        countText:SetText("|cff33e633" .. activeCount .. "/" .. totalCount .. " patches active|r")
        countText:SetJustifyH("LEFT")

        local yOffset = -74

        -- Build addon group sections
        for _, groupInfo in ipairs(ns.addonGroups) do
            local groupId = groupInfo.id
            local groupPatches = PATCHES_BY_GROUP[groupId]
            if not groupPatches then groupPatches = {} end

            -- Check if any dep for this group is loaded
            local installed = false
            for _, dep in ipairs(groupInfo.deps) do
                if ns:IsAddonLoaded(dep) then
                    installed = true
                    break
                end
            end

            -- Group separator
            yOffset = yOffset - 6
            yOffset = AddSeparator(yOffset, installed and 0.35 or 0.15)

            -- Group header (larger font)
            local header = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            header:SetPoint("TOPLEFT", 16, yOffset)
            if installed then
                header:SetText(groupInfo.label)
            else
                header:SetText("|cff666666" .. groupInfo.label .. "|r")
            end

            -- Active count per group (right-aligned next to header)
            local groupCount = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            groupCount:SetPoint("LEFT", header, "RIGHT", 10, 0)
            groupCountLabels[groupId] = groupCount

            -- Not installed label
            if not installed then
                local note = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                note:SetPoint("LEFT", groupCount, "RIGHT", 8, 0)
                note:SetText("(not installed)")
            end

            -- Enable All / Disable All buttons (right side of header)
            local enableAllBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            enableAllBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", -80, yOffset + 2)
            enableAllBtn:SetSize(60, 18)
            enableAllBtn:SetText("All On")
            enableAllBtn:GetFontString():SetFont(enableAllBtn:GetFontString():GetFont(), 10)

            local disableAllBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            disableAllBtn:SetPoint("LEFT", enableAllBtn, "RIGHT", 4, 0)
            disableAllBtn:SetSize(60, 18)
            disableAllBtn:SetText("All Off")
            disableAllBtn:GetFontString():SetFont(disableAllBtn:GetFontString():GetFont(), 10)

            yOffset = yOffset - 24

            -- Init group checkbox tracking
            groupCheckboxes[groupId] = {}

            for _, patchInfo in ipairs(groupPatches) do
                local cb = CreateFrame("CheckButton", "PatchWerk_CB_" .. patchInfo.key, content, "UICheckButtonTemplate")
                cb:SetPoint("TOPLEFT", 20, yOffset)
                cb.optionKey = patchInfo.key

                -- Disable checkbox interaction for uninstalled addons
                if not installed then
                    cb:Disable()
                    cb:SetAlpha(0.4)
                end

                local cbName = cb:GetName()
                local cbLabel = _G[cbName .. "Text"]
                if cbLabel then
                    -- Label with impact badge inline
                    local badge = FormatBadge(patchInfo.impact, patchInfo.impactLevel)
                    cbLabel:SetText(patchInfo.label .. "  " .. badge)
                    cbLabel:SetFontObject(installed and "GameFontHighlight" or "GameFontDisable")
                end

                -- Status badge (right side)
                local statusBadge = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                statusBadge:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, yOffset - 5)
                table.insert(statusLabels, { key = patchInfo.key, fontString = statusBadge })

                -- Help text
                local helpText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                helpText:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 26, 2)
                helpText:SetPoint("RIGHT", content, "RIGHT", -70, 0)
                helpText:SetText(installed and patchInfo.help or ("|cff555555" .. patchInfo.help .. "|r"))
                helpText:SetJustifyH("LEFT")
                helpText:SetWordWrap(true)

                -- Tooltip
                cb:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(patchInfo.label, 1, 1, 1)
                    GameTooltip:AddLine(patchInfo.help, 1, 0.82, 0, true)
                    if patchInfo.impact then
                        GameTooltip:AddLine(" ")
                        local bc = BADGE_COLORS[patchInfo.impact] or BADGE_COLORS.FPS
                        GameTooltip:AddLine("Impact: " .. patchInfo.impact .. " (" .. (patchInfo.impactLevel or "Medium") .. ")",
                            bc.r, bc.g, bc.b)
                    end
                    GameTooltip:AddLine(" ")
                    if not installed then
                        GameTooltip:AddLine("Target addon not installed", 0.5, 0.5, 0.5)
                    elseif ns.applied[patchInfo.key] then
                        GameTooltip:AddLine("Status: Active", 0, 1, 0)
                    else
                        GameTooltip:AddLine("Requires /reload to take effect", 1, 1, 0)
                    end
                    GameTooltip:Show()
                end)
                cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

                cb:SetScript("OnClick", function(self)
                    ns:SetOption(self.optionKey, self:GetChecked() and true or false)
                    RefreshStatusLabels()
                    RefreshGroupCounts()
                end)

                table.insert(checkboxes, cb)
                table.insert(groupCheckboxes[groupId], cb)
                yOffset = yOffset - 42
            end

            -- Wire up Enable/Disable All buttons
            local grpCbs = groupCheckboxes[groupId]
            enableAllBtn:SetScript("OnClick", function()
                for _, cb in ipairs(grpCbs) do
                    ns:SetOption(cb.optionKey, true)
                    cb:SetChecked(true)
                end
                RefreshStatusLabels()
                RefreshGroupCounts()
            end)
            disableAllBtn:SetScript("OnClick", function()
                for _, cb in ipairs(grpCbs) do
                    ns:SetOption(cb.optionKey, false)
                    cb:SetChecked(false)
                end
                RefreshStatusLabels()
                RefreshGroupCounts()
            end)

            if not installed then
                enableAllBtn:Disable()
                disableAllBtn:Disable()
                enableAllBtn:SetAlpha(0.4)
                disableAllBtn:SetAlpha(0.4)
            end

            yOffset = yOffset - 2
        end

        -- Bottom buttons
        yOffset = yOffset - 6
        yOffset = AddSeparator(yOffset, 0.35)

        local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        resetBtn:SetPoint("TOPLEFT", 16, yOffset)
        resetBtn:SetSize(130, 26)
        resetBtn:SetText("Reset Defaults")
        resetBtn:SetScript("OnClick", function()
            if PatchWerkDB then
                wipe(PatchWerkDB)
                for key, value in pairs(ns.defaults) do
                    PatchWerkDB[key] = value
                end
            end
            for _, cb in ipairs(checkboxes) do
                cb:SetChecked(ns:GetOption(cb.optionKey))
            end
            RefreshStatusLabels()
            RefreshGroupCounts()
            ns:Print("Settings reset to defaults. Reload to apply.")
        end)

        local reloadBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        reloadBtn:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
        reloadBtn:SetSize(110, 26)
        reloadBtn:SetText("Reload UI")
        reloadBtn:SetScript("OnClick", ReloadUI)

        yOffset = yOffset - 40
        content:SetHeight(-yOffset + 20)
    end

    panel:SetScript("OnShow", function()
        BuildContent()
        local sf = PatchWerk_OptionsScroll
        if sf then
            local w = sf:GetWidth()
            if w and w > 0 then sf:GetScrollChild():SetWidth(w) end
        end
        for _, cb in ipairs(checkboxes) do
            cb:SetChecked(ns:GetOption(cb.optionKey))
        end
        RefreshStatusLabels()
        RefreshGroupCounts()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "PatchWerk")
        category.ID = "PatchWerk"
        Settings.RegisterAddOnCategory(category)
        ns.settingsCategoryID = "PatchWerk"
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    ns.optionsPanel = panel
    return panel
end

---------------------------------------------------------------------------
-- Slash Commands
---------------------------------------------------------------------------

local function ShowStatus()
    ns:Print("Patch Status (v" .. ns.VERSION .. "):")
    ns:Print("-----------------------------")
    for _, groupInfo in ipairs(ns.addonGroups) do
        local installed = false
        for _, dep in ipairs(groupInfo.deps) do
            if ns:IsAddonLoaded(dep) then installed = true; break end
        end

        local groupPatches = PATCHES_BY_GROUP[groupInfo.id]
        if groupPatches and #groupPatches > 0 then
            if installed then
                ns:Print("|cffffffff" .. groupInfo.label .. "|r")
            else
                ns:Print("|cff666666" .. groupInfo.label .. " (not installed)|r")
            end

            for _, p in ipairs(groupPatches) do
                local enabled = ns:GetOption(p.key)
                local applied = ns.applied[p.key]
                local status
                if applied then
                    status = "|cff00ff00active|r"
                elseif enabled and installed then
                    status = "|cffffff00enabled (reload needed)|r"
                elseif not installed then
                    status = "|cff666666not installed|r"
                else
                    status = "|cffff0000disabled|r"
                end
                ns:Print("  " .. p.label .. ": " .. status)
            end
        end
    end
end

local function HandleToggle(input)
    local patchKey = PATCH_NAMES_LOWER[input:lower()]
    if not patchKey then
        ns:Print("Unknown patch: " .. tostring(input))
        ns:Print("Use /patchwerk status to see available patches.")
        return
    end

    local current = ns:GetOption(patchKey)
    ns:SetOption(patchKey, not current)
    local newState = not current and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    ns:Print(patchKey .. " is now " .. newState .. ". Reload UI to apply.")
end

local function HandleReset()
    if PatchWerkDB then
        wipe(PatchWerkDB)
        for key, value in pairs(ns.defaults) do
            PatchWerkDB[key] = value
        end
    end
    ns:Print("All settings reset to defaults. Reload UI to apply.")
end

SLASH_PATCHWERK1 = "/patchwerk"
SLASH_PATCHWERK2 = "/pw"

SlashCmdList["PATCHWERK"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end

    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "" then
        if ns.settingsCategoryID and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(ns.settingsCategoryID)
        elseif InterfaceOptionsFrame_OpenToCategory and ns.optionsPanel then
            InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
            InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
        else
            ShowStatus()
        end
    elseif cmd == "status" then
        ShowStatus()
    elseif cmd == "toggle" and args[2] then
        HandleToggle(args[2])
    elseif cmd == "reset" then
        HandleReset()
    elseif cmd == "config" or cmd == "options" then
        if ns.settingsCategoryID and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(ns.settingsCategoryID)
        elseif InterfaceOptionsFrame_OpenToCategory and ns.optionsPanel then
            InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
            InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
        else
            ShowStatus()
        end
    elseif cmd == "help" then
        ns:Print("Usage:")
        ns:Print("  /patchwerk              Open settings panel")
        ns:Print("  /patchwerk status       Show all patch status")
        ns:Print("  /patchwerk toggle X     Toggle a patch on/off")
        ns:Print("  /patchwerk reset        Reset to defaults")
        ns:Print("  /patchwerk help         Show this help")
    else
        ShowStatus()
    end
end

---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    CreateOptionsPanel()
end)
