-- Options: GUI settings panel and slash command interface for AddonTweaks
--
-- Provides a scrollable Blizzard Interface Options panel with patch toggles
-- grouped by target addon, status badges, and inline descriptions.

local _, ns = ...

-- Patch metadata with user-friendly labels and help text
local PATCH_INFO = {
    -- Details
    { key = "Details_hexFix",        group = "Details",  label = "Hex Encoder Fix",
      help = "Replaces slow character-by-character hex builder with a single format() call." },
    { key = "Details_fadeHandler",   group = "Details",  label = "Fade Handler Idle Guard",
      help = "Stops the fade OnUpdate from running when no bars are actively fading." },
    { key = "Details_refreshCap",    group = "Details",  label = "Refresh Rate Cap",
      help = "Prevents the streamer 60fps refresh mode which is too expensive for Classic." },
    { key = "Details_npcIdCache",    group = "Details",  label = "NPC ID Cache",
      help = "Caches GUID-to-NPC-ID extraction to avoid redundant pattern matching." },
    -- Plater
    { key = "Plater_fpsCheck",       group = "Plater",   label = "FPS Timer Allocation Fix",
      help = "Replaces per-frame C_Timer.After(0) with a persistent OnUpdate frame." },
    { key = "Plater_healthText",     group = "Plater",   label = "Health Text Skip",
      help = "Skips health text formatting when values haven't changed." },
    { key = "Plater_auraAlign",      group = "Plater",   label = "Aura Alignment Guard",
      help = "Skips redundant aura icon layout when visible count is unchanged." },
    -- Pawn
    { key = "Pawn_cacheIndex",       group = "Pawn",     label = "Cache Hash Index",
      help = "Replaces O(200) linear cache scan with O(1) hash lookup per tooltip show." },
    { key = "Pawn_tooltipDedup",     group = "Pawn",     label = "Tooltip Deduplication",
      help = "Skips redundant processing when multiple tooltip hooks fire for the same item." },
    { key = "Pawn_upgradeCache",     group = "Pawn",     label = "Upgrade Comparison Cache",
      help = "Caches upgrade results per item link, invalidated on gear changes." },
    -- TipTac
    { key = "TipTac_unitAppearanceGuard", group = "TipTac", label = "Non-Unit Tooltip Guard",
      help = "Skips per-frame appearance updates for item and spell tooltips." },
    { key = "TipTac_inspectCache",   group = "TipTac",   label = "Extended Inspect Cache",
      help = "Extends talent inspect cache from 5 to 30 seconds to reduce server queries." },
    -- Questie
    { key = "Questie_questLogThrottle", group = "Questie", label = "Quest Log Burst Throttle",
      help = "Limits quest log scans to once per 0.5 seconds during rapid event bursts." },
    { key = "Questie_availableQuestsDebounce", group = "Questie", label = "Available Quests Debounce",
      help = "Collapses rapid recalculation calls into a single 100ms-delayed update." },
    -- LFGBulletinBoard
    { key = "LFGBulletinBoard_updateListDirty", group = "LFGBulletinBoard", label = "Dirty Flag UI Rebuild",
      help = "Skips the 1-second full UI rebuild when no new messages arrived." },
    { key = "LFGBulletinBoard_sortSkip", group = "LFGBulletinBoard", label = "Sort Interval Throttle",
      help = "Limits list rebuilds to once every 2 seconds even when the dirty flag is disabled." },
    -- Bartender4
    { key = "Bartender4_lossOfControlSkip", group = "Bartender4", label = "Skip Loss of Control Events",
      help = "Eliminates 120-button update loops for no-op events on TBC Classic." },
    { key = "Bartender4_usableThrottle", group = "Bartender4", label = "Usability Update Debounce",
      help = "Batches rapid IsUsableAction checks into a single next-frame update." },
    -- TitanPanel
    { key = "TitanPanel_reputationsOnUpdate", group = "TitanPanel", label = "Reputations Timer Fix",
      help = "Replaces per-frame OnUpdate with a 5-second timer matching the internal throttle." },
    { key = "TitanPanel_bagDebounce", group = "TitanPanel", label = "Bag Update Debounce",
      help = "Debounces rapid BAG_UPDATE events into a single 0.2s delayed scan." },
    { key = "TitanPanel_performanceThrottle", group = "TitanPanel", label = "Performance Update Throttle",
      help = "Increases minimum update interval from 1.5 to 3 seconds." },
    -- OmniCC
    { key = "OmniCC_gcdSpellCache", group = "OmniCC", label = "GCD Spell Cache",
      help = "Caches GetSpellCooldown result per frame during GCD bursts. Eliminates 20+ redundant API calls per GCD cycle." },
    { key = "OmniCC_ruleMatchCache", group = "OmniCC", label = "Rule Match Cache",
      help = "Caches frame name pattern matching results. Frame names never change, so one match per name is enough." },
    { key = "OmniCC_finishEffectGuard", group = "OmniCC", label = "Finish Effect Guard",
      help = "Skips finish-effect checks for cooldowns that are clearly not expiring, reducing per-update overhead." },
    -- Prat-3.0
    { key = "Prat_smfThrottle", group = "Prat", label = "Chat Layout Throttle",
      help = "Throttles per-frame chat line relayout from 60fps to 20fps. Saves ~96,000 API calls/sec with 4 chat windows." },
    { key = "Prat_timestampCache", group = "Prat", label = "Timestamp Cache",
      help = "Caches timestamp format string and rendered time per second instead of rebuilding on every message." },
    { key = "Prat_bubblesGuard", group = "Prat", label = "Bubble Scan Guard",
      help = "Skips the 10/sec chat bubble scan when no bubbles exist in the world." },
    -- GatherMate2
    { key = "GatherMate2_minimapThrottle", group = "GatherMate2", label = "Minimap Update Throttle",
      help = "Caps minimap pin position updates from 60fps to 20fps. Eliminates wasteful API calls while standing still." },
    { key = "GatherMate2_rebuildGuard", group = "GatherMate2", label = "Stationary Rebuild Skip",
      help = "Skips the full 2-second minimap node rebuild when the player hasn't moved since the last rebuild." },
    { key = "GatherMate2_cleuUnregister", group = "GatherMate2", label = "Remove Dead Combat Handler",
      help = "Unregisters the Extract Gas combat log handler that is disabled in TBC Classic but still fires on every combat event." },
    -- Quartz
    { key = "Quartz_castBarThrottle", group = "Quartz", label = "Cast Bar 30fps Cap",
      help = "Throttles Player/Target/Focus/Pet cast bar updates from 60fps to 30fps. Timing uses absolute GetTime, so accuracy is unaffected." },
    { key = "Quartz_swingBarThrottle", group = "Quartz", label = "Swing Timer 30fps Cap",
      help = "Throttles the auto-attack swing bar to 30fps. Visually identical for a 2-3 second swing timer." },
    { key = "Quartz_gcdBarThrottle", group = "Quartz", label = "GCD Bar 30fps Cap",
      help = "Throttles the GCD spark animation to 30fps during every spell cast." },
    -- Auctionator
    { key = "Auctionator_ownerQueryThrottle", group = "Auctionator", label = "Auction Query Throttle",
      help = "Throttles GetOwnerAuctionItems from 120/sec (both tabs) to 2/sec. Eliminates constant server spam while AH is open." },
    { key = "Auctionator_throttleBroadcast", group = "Auctionator", label = "Throttle Timer Broadcast",
      help = "Reduces timeout countdown broadcasts from 60/sec to 2/sec. The countdown display updates every 0.5s instead of every frame." },
    { key = "Auctionator_priceAgeOptimize", group = "Auctionator", label = "Price Age Optimizer",
      help = "Replaces table-alloc + sort with a zero-allocation max scan for tooltip price age calculation." },
    { key = "Auctionator_dbKeyCache", group = "Auctionator", label = "DB Key Link Cache",
      help = "Caches item link to database key mapping. Eliminates repeated regex parsing on every tooltip hover." },
    -- VuhDo
    { key = "VuhDo_debuffDebounce", group = "VuhDo", label = "Debuff Detection Debounce",
      help = "Debounces per-unit debuff scanning with a 33ms window during AoE debuff storms." },
    { key = "VuhDo_rangeSkipDead", group = "VuhDo", label = "Skip Dead/DC Range Checks",
      help = "Skips range polling (4-5 API calls) for dead and disconnected raid members." },
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

---------------------------------------------------------------------------
-- GUI Panel
---------------------------------------------------------------------------

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "AddonTweaks"

    local checkboxes = {}
    local statusLabels = {}
    local contentBuilt = false

    local function RefreshStatusLabels()
        for _, info in ipairs(statusLabels) do
            local enabled = ns:GetOption(info.key)
            local applied = ns.applied[info.key]
            if applied then
                info.fontString:SetText("Active")
                info.fontString:SetTextColor(0.2, 0.9, 0.2)
            elseif enabled and not applied then
                info.fontString:SetText("Reload needed")
                info.fontString:SetTextColor(1, 0.82, 0)
            elseif not enabled then
                info.fontString:SetText("Disabled")
                info.fontString:SetTextColor(0.5, 0.5, 0.5)
            else
                info.fontString:SetText("Not loaded")
                info.fontString:SetTextColor(0.4, 0.4, 0.4)
            end
        end
    end

    local function BuildContent()
        if contentBuilt then return end
        contentBuilt = true

        local scrollFrame = CreateFrame("ScrollFrame", "AddonTweaks_OptionsScroll", panel, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 0, -10)
        scrollFrame:SetPoint("BOTTOMRIGHT", -26, 10)

        local content = CreateFrame("Frame")
        content:SetSize(580, 1200)
        scrollFrame:SetScrollChild(content)

        scrollFrame:SetScript("OnSizeChanged", function(self, w)
            if w and w > 0 then content:SetWidth(w) end
        end)

        -- Helpers
        local function AddSeparator(y)
            local line = content:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", 12, y)
            line:SetPoint("TOPRIGHT", -12, y)
            line:SetColorTexture(0.6, 0.6, 0.6, 0.25)
            return y - 10
        end

        local function AddGroupHeader(text, installed, y)
            y = AddSeparator(y)
            local header = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            header:SetPoint("TOPLEFT", 16, y)
            header:SetText(text)

            if not installed then
                local note = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                note:SetPoint("LEFT", header, "RIGHT", 8, 0)
                note:SetText("(not installed)")
            end
            return y - 22
        end

        -- Title
        local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("AddonTweaks")

        local version = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        version:SetPoint("LEFT", title, "RIGHT", 6, 0)
        version:SetText("v" .. ns.VERSION)

        local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        subtitle:SetText("Performance patches for popular addons. Toggle patches below, then /reload.")
        subtitle:SetJustifyH("LEFT")

        -- Active count
        local activeCount = 0
        for _ in pairs(ns.applied) do activeCount = activeCount + 1 end
        local totalCount = #PATCH_INFO

        local countText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        countText:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -2)
        countText:SetText("|cff00ff00" .. activeCount .. "/" .. totalCount .. " patches active|r. Changes require /reload.")
        countText:SetJustifyH("LEFT")

        local yOffset = -78

        -- Build addon group sections
        for _, groupInfo in ipairs(ns.addonGroups) do
            local groupId = groupInfo.id
            local groupPatches = PATCHES_BY_GROUP[groupId]
            if not groupPatches then groupPatches = {} end -- skip empty groups

            -- Check if any dep for this group is loaded
            local installed = false
            for _, dep in ipairs(groupInfo.deps) do
                if ns:IsAddonLoaded(dep) then
                    installed = true
                    break
                end
            end

            yOffset = AddGroupHeader(groupInfo.label, installed, yOffset)

            for _, patchInfo in ipairs(groupPatches) do
                local cb = CreateFrame("CheckButton", "AddonTweaks_CB_" .. patchInfo.key, content, "UICheckButtonTemplate")
                cb:SetPoint("TOPLEFT", 16, yOffset)
                cb.optionKey = patchInfo.key

                local cbName = cb:GetName()
                local cbLabel = _G[cbName .. "Text"]
                if cbLabel then
                    cbLabel:SetText(patchInfo.label)
                    cbLabel:SetFontObject("GameFontHighlight")
                    if not installed then
                        cbLabel:SetFontObject("GameFontDisable")
                    end
                end

                -- Status badge
                local badge = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                badge:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, yOffset - 5)
                table.insert(statusLabels, { key = patchInfo.key, fontString = badge })

                -- Help text
                local helpText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                helpText:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 26, 2)
                helpText:SetPoint("RIGHT", content, "RIGHT", -90, 0)
                helpText:SetText(patchInfo.help)
                helpText:SetJustifyH("LEFT")
                helpText:SetWordWrap(true)

                -- Tooltip
                cb:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(patchInfo.label, 1, 1, 1)
                    GameTooltip:AddLine(patchInfo.help, 1, 0.82, 0, true)
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
                end)

                table.insert(checkboxes, cb)
                yOffset = yOffset - 42
            end

            yOffset = yOffset - 4
        end

        -- Slash Command Reference
        yOffset = yOffset - 2
        yOffset = AddSeparator(yOffset)

        local cmdHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        cmdHeader:SetPoint("TOPLEFT", 16, yOffset)
        cmdHeader:SetText("Slash Commands")
        yOffset = yOffset - 22

        local commands = {
            { cmd = "/atweaks",                 info = "Open this settings panel" },
            { cmd = "/atweaks status",          info = "Show all patch status in chat" },
            { cmd = "/atweaks toggle <patch>",  info = "Toggle a patch on or off" },
            { cmd = "/atweaks reset",           info = "Reset all settings to defaults" },
        }

        for _, cmdInfo in ipairs(commands) do
            local line = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            line:SetPoint("TOPLEFT", 22, yOffset)
            line:SetText("|cffffcc00" .. cmdInfo.cmd .. "|r")
            line:SetJustifyH("LEFT")

            local desc = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            desc:SetPoint("TOPLEFT", 220, yOffset)
            desc:SetText(cmdInfo.info)
            desc:SetJustifyH("LEFT")

            yOffset = yOffset - 16
        end

        -- Buttons
        yOffset = yOffset - 14
        yOffset = AddSeparator(yOffset)

        local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        resetBtn:SetPoint("TOPLEFT", 16, yOffset)
        resetBtn:SetSize(130, 26)
        resetBtn:SetText("Reset Defaults")
        resetBtn:SetScript("OnClick", function()
            if AddonTweaksDB then
                wipe(AddonTweaksDB)
                for key, value in pairs(ns.defaults) do
                    AddonTweaksDB[key] = value
                end
            end
            for _, cb in ipairs(checkboxes) do
                cb:SetChecked(ns:GetOption(cb.optionKey))
            end
            RefreshStatusLabels()
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
        local sf = AddonTweaks_OptionsScroll
        if sf then
            local w = sf:GetWidth()
            if w and w > 0 then sf:GetScrollChild():SetWidth(w) end
        end
        for _, cb in ipairs(checkboxes) do
            cb:SetChecked(ns:GetOption(cb.optionKey))
        end
        RefreshStatusLabels()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "AddonTweaks")
        category.ID = "AddonTweaks"
        Settings.RegisterAddOnCategory(category)
        ns.settingsCategoryID = "AddonTweaks"
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
        ns:Print("Use /atweaks status to see available patches.")
        return
    end

    local current = ns:GetOption(patchKey)
    ns:SetOption(patchKey, not current)
    local newState = not current and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    ns:Print(patchKey .. " is now " .. newState .. ". Reload UI to apply.")
end

local function HandleReset()
    if AddonTweaksDB then
        wipe(AddonTweaksDB)
        for key, value in pairs(ns.defaults) do
            AddonTweaksDB[key] = value
        end
    end
    ns:Print("All settings reset to defaults. Reload UI to apply.")
end

SLASH_ADDONTWEAKS1 = "/atweaks"
SLASH_ADDONTWEAKS2 = "/addontweaks"

SlashCmdList["ADDONTWEAKS"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end

    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "" then
        if ns.settingsCategoryID and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(ns.settingsCategoryID)
        elseif InterfaceOptionsFrame_OpenToCategory and ns.optionsPanel then
            -- Double-call is a well-known workaround for a Blizzard bug where
            -- the first call opens Interface Options but doesn't select the panel
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
        ns:Print("  /atweaks              Open settings panel")
        ns:Print("  /atweaks status       Show all patch status")
        ns:Print("  /atweaks toggle X     Toggle a patch on/off")
        ns:Print("  /atweaks reset        Reset to defaults")
        ns:Print("  /atweaks help         Show this help")
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
