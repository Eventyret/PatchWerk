-- Options: GUI settings panel and slash command interface for PatchWerk
--
-- Provides a scrollable Blizzard Interface Options panel with patch toggles
-- grouped by target addon, impact badges, and user-friendly descriptions.

local _, ns = ...

local wipe = wipe
local ipairs = ipairs

local WHITE8x8 = "Interface\\Buttons\\WHITE8x8"
-- TBC Classic Anniversary lacks SetColorTexture / numeric SetTexture.
-- Use a white pixel + vertex color instead.
local function SetSolidColor(tex, r, g, b, a)
    tex:SetTexture(WHITE8x8)
    tex:SetVertexColor(r, g, b, a or 1)
end

-- Impact badge colors
local BADGE_COLORS = {
    FPS     = { r = 0.2, g = 0.9, b = 0.2 },   -- green
    Memory  = { r = 0.2, g = 0.8, b = 0.9 },   -- cyan
    Network = { r = 1.0, g = 0.6, b = 0.2 },   -- orange
}

local LEVEL_COLORS = {
    High   = { r = 1.0, g = 0.82, b = 0.0 },  -- gold
    Medium = { r = 0.75, g = 0.75, b = 0.75 }, -- silver
    Low    = { r = 0.6, g = 0.4, b = 0.2 },    -- bronze
}

-- Patch category system
local CATEGORY_COLORS = {
    Fixes         = "|cffff6666",   -- soft red
    Performance   = "|cff66b3ff",   -- blue
    Tweaks        = "|cffe6b3ff",   -- lavender
    Compatibility = "|cff66ff66",   -- green
}
local CATEGORY_LABELS = {
    Fixes         = "Fixes",
    Performance   = "Performance",
    Tweaks        = "Tweaks",
    Compatibility = "Compatibility",
}
local CATEGORY_DESC = {
    Fixes         = "Prevents crashes or errors on TBC Classic Anniversary",
    Performance   = "Improves FPS, memory usage, or network performance",
    Tweaks        = "Improves addon behavior or fixes confusing display issues",
    Compatibility = "Adds missing API support for TBC Classic Anniversary",
}

-- Patch metadata is registered by individual patch files via ns.patchInfo.
-- The PATCH_INFO local alias and derived lookups are built lazily on first use.
local PATCH_INFO = ns.patchInfo

-- Estimated performance improvement per patch (stored as .estimate field in patchInfo)
local PATCH_ESTIMATES = setmetatable({}, { __index = function(_, key)
    for _, p in ipairs(ns.patchInfo) do
        if p.key == key then return p.estimate end
    end
end })

-- Build lookup for patches by group (rebuilt lazily)
local PATCHES_BY_GROUP = {}
local PATCH_NAMES_LOWER = {}
local lookupsDirty = true

local function RebuildLookups()
    if not lookupsDirty then return end
    wipe(PATCHES_BY_GROUP)
    wipe(PATCH_NAMES_LOWER)
    for _, p in ipairs(ns.patchInfo) do
        if not PATCHES_BY_GROUP[p.group] then
            PATCHES_BY_GROUP[p.group] = {}
        end
        table.insert(PATCHES_BY_GROUP[p.group], p)
        PATCH_NAMES_LOWER[p.key:lower()] = p.key
    end
    lookupsDirty = false
end

-- LEGACY PATCH_INFO removed — metadata now lives in each Patches/*.lua file
-- (see Patches/Details.lua etc. for the registration pattern)

-- Human-readable impact descriptions for tooltips
local IMPACT_DESC = {
    FPS = "Smoother gameplay",
    Memory = "Less memory usage",
    Network = "Less server traffic",
}
local LEVEL_DESC = {
    High = "very noticeable improvement",
    Medium = "helps in busy situations",
    Low = "small improvement",
}

-- Format an impact badge string with color codes
local function FormatBadge(impact, level)
    if not impact then return "" end
    local bc = BADGE_COLORS[impact] or BADGE_COLORS.FPS
    local lc = LEVEL_COLORS[level] or LEVEL_COLORS.Medium
    return string.format("|cff%02x%02x%02x[%s]|r |cff%02x%02x%02x%s|r",
        bc.r * 255, bc.g * 255, bc.b * 255, impact,
        lc.r * 255, lc.g * 255, lc.b * 255, level or "")
end

-- Format a category badge string with color code
local function FormatCategoryBadge(category)
    if not category then return "" end
    local color = CATEGORY_COLORS[category] or CATEGORY_COLORS.Performance
    local label = CATEGORY_LABELS[category] or category
    return color .. "[" .. label .. "]|r"
end

---------------------------------------------------------------------------
-- GUI Panel (Single Addon-Centric Panel)
---------------------------------------------------------------------------

local pendingReload = false
local allCheckboxes = {}
local groupCheckboxes = {}
local groupCountLabels = {}
local statusLabels = {}
local collapsed = {}
local reloadBanner = nil
local relayoutFunc = nil
local summaryLabel = nil

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
    for gcKey, cbs in pairs(groupCheckboxes) do
        local active, total = 0, #cbs
        for _, cb in ipairs(cbs) do
            if ns:GetOption(cb.optionKey) then active = active + 1 end
        end
        local label = groupCountLabels[gcKey]
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

local function RefreshSummary()
    if not summaryLabel then return end
    RebuildLookups()
    local installedCount, totalActive, totalPatches = 0, 0, 0
    for _, g in ipairs(ns.addonGroups) do
        for _, dep in ipairs(g.deps) do
            if ns:IsAddonLoaded(dep) then
                installedCount = installedCount + 1
                break
            end
        end
    end
    for _, p in ipairs(PATCH_INFO) do
        totalPatches = totalPatches + 1
        if ns:GetOption(p.key) then totalActive = totalActive + 1 end
    end
    if totalActive == totalPatches then
        summaryLabel:SetText("|cff33e633All good|r -- " .. totalActive .. " patches active for " .. installedCount .. " addons")
    elseif totalActive > 0 then
        summaryLabel:SetText(totalActive .. "/" .. totalPatches .. " patches active for " .. installedCount .. " addons")
    else
        summaryLabel:SetText("|cff808080No patches active|r")
    end
end

local function ShowReloadBanner()
    if not pendingReload then
        pendingReload = true
        if reloadBanner then reloadBanner:Show() end
        if relayoutFunc then relayoutFunc() end
    end
end

---------------------------------------------------------------------------
-- BuildAddonGroup — build all patches for one addon group (no category filter)
---------------------------------------------------------------------------
local function BuildAddonGroup(content, groupInfo, installed)
    RebuildLookups()
    local groupId = groupInfo.id
    local patches = PATCHES_BY_GROUP[groupId] or {}
    if #patches == 0 then return nil end

    local ck = groupId
    if collapsed[ck] == nil then collapsed[ck] = true end

    local gf = CreateFrame("Frame", nil, content)
    local hf = CreateFrame("Frame", nil, gf)
    hf:SetPoint("TOPLEFT", 0, 0)
    hf:SetPoint("TOPRIGHT", 0, 0)
    hf:SetHeight(38)
    hf:EnableMouse(true)

    local sep = hf:CreateTexture(nil, "BACKGROUND")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 12, -2)
    sep:SetPoint("TOPRIGHT", -12, -2)
    SetSolidColor(sep, 0.6, 0.6, 0.6, installed and 0.35 or 0.15)

    local toggle = hf:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    toggle:SetPoint("TOPLEFT", 8, -12)
    toggle:SetText("|cffcccccc[+]|r")

    local hlabel = hf:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    hlabel:SetPoint("LEFT", toggle, "RIGHT", 4, 0)
    hlabel:SetText(installed and groupInfo.label or ("|cff666666" .. groupInfo.label .. "|r"))

    -- Outdated indicator (dev builds only — normal users don't need version mismatch noise)
    local outdatedIcon
    if ns.VERSION == "dev" and installed and ns.versionResults and ns.versionResults[groupId]
        and not ns:IsOutdatedDismissed(groupId) then
        outdatedIcon = CreateFrame("Frame", nil, hf)
        outdatedIcon:SetSize(20, 20)
        outdatedIcon:SetPoint("LEFT", hlabel, "RIGHT", 4, 0)
        outdatedIcon:EnableMouse(true)
        local warn = outdatedIcon:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        warn:SetPoint("CENTER", 0, 0)
        warn:SetText("|cffffff00(!)|r")
        local vr = ns.versionResults[groupId]
        outdatedIcon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Addon Updated", 1, 0.82, 0)
            GameTooltip:AddLine("Written for v" .. vr.expected .. ", installed v" .. vr.installed, 1, 1, 1, true)
            GameTooltip:AddLine("Patches still work but may need verification.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Click to dismiss", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        outdatedIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        outdatedIcon:SetScript("OnMouseDown", function()
            ns:DismissOutdatedForGroup(groupId)
            outdatedIcon:Hide()
            GameTooltip:Hide()
        end)
    end

    local gc = hf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    gc:SetPoint("LEFT", outdatedIcon or hlabel, "RIGHT", outdatedIcon and 4 or 10, 0)
    groupCountLabels[ck] = gc

    if not installed then
        local note = hf:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        note:SetPoint("LEFT", gc, "RIGHT", 8, 0)
        note:SetText("(not installed)")
    end

    local allBtn = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
    allBtn:SetPoint("TOPRIGHT", hf, "TOPRIGHT", -12, -8)
    allBtn:SetSize(40, 18)
    allBtn:SetText("All")
    allBtn:GetFontString():SetFont(allBtn:GetFontString():GetFont(), 10)

    local hoverBg = hf:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    SetSolidColor(hoverBg, 1, 1, 1, 0)
    hf:SetScript("OnEnter", function() hoverBg:SetVertexColor(1, 1, 1, 0.03) end)
    hf:SetScript("OnLeave", function() hoverBg:SetVertexColor(1, 1, 1, 0) end)

    local bf = CreateFrame("Frame", nil, gf)
    bf:SetPoint("TOPLEFT", hf, "BOTTOMLEFT", 0, 0)
    bf:SetPoint("TOPRIGHT", hf, "BOTTOMRIGHT", 0, 0)
    if not groupCheckboxes[ck] then groupCheckboxes[ck] = {} end

    local by = 0
    for _, pi in ipairs(patches) do
        local cb = CreateFrame("CheckButton", "PatchWerk_CB_" .. pi.key, bf, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 20, by)
        cb.optionKey = pi.key
        if not installed then cb:Disable(); cb:SetAlpha(0.4) end
        local cbn = cb:GetName()
        local cbl = _G[cbn .. "Text"]
        if cbl then
            local catBadge = FormatCategoryBadge(pi.category)
            cbl:SetText(pi.label .. "  " .. catBadge .. " " .. FormatBadge(pi.impact, pi.impactLevel))
            cbl:SetFontObject(installed and "GameFontHighlight" or "GameFontDisable")
        end
        if pi.detail and cbl then
            local hb = CreateFrame("Frame", nil, bf)
            hb:SetSize(16, 16)
            hb:SetPoint("LEFT", cbl, "RIGHT", 4, 0)
            hb:EnableMouse(true)
            local qm = hb:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            qm:SetPoint("CENTER", 0, 0)
            qm:SetText("|cff66bbff(?)|r")
            if not installed then hb:SetAlpha(0.4) end
            hb:SetScript("OnEnter", function(self)
                qm:SetText("|cffffffff(?)|r")
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("What does this fix?", 0.4, 0.8, 1.0)
                GameTooltip:AddLine(pi.detail, 1, 0.82, 0, true)
                local est = PATCH_ESTIMATES[pi.key]
                if est then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Estimated gain: " .. est, 0.2, 0.9, 0.2, true)
                end
                GameTooltip:Show()
            end)
            hb:SetScript("OnLeave", function()
                qm:SetText("|cff66bbff(?)|r")
                GameTooltip:Hide()
            end)
        end
        local sb = bf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        sb:SetPoint("TOPRIGHT", bf, "TOPRIGHT", -20, by - 5)
        table.insert(statusLabels, { key = pi.key, fontString = sb })
        local ht = bf:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        ht:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 26, 2)
        ht:SetPoint("RIGHT", bf, "RIGHT", -70, 0)
        ht:SetText(installed and pi.help or ("|cff555555" .. pi.help .. "|r"))
        ht:SetJustifyH("LEFT")
        ht:SetWordWrap(true)
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(pi.label, 1, 1, 1)
            GameTooltip:AddLine(pi.help, 1, 0.82, 0, true)
            if pi.impact then
                GameTooltip:AddLine(" ")
                local bc = BADGE_COLORS[pi.impact] or BADGE_COLORS.FPS
                local lc = LEVEL_COLORS[pi.impactLevel] or LEVEL_COLORS.Medium
                GameTooltip:AddLine(IMPACT_DESC[pi.impact] or pi.impact, bc.r, bc.g, bc.b)
                local how = LEVEL_DESC[pi.impactLevel] or ""
                if how ~= "" then GameTooltip:AddLine(how, lc.r, lc.g, lc.b) end
            end
            GameTooltip:AddLine(" ")
            if not installed then
                GameTooltip:AddLine("Target addon not installed", 0.5, 0.5, 0.5)
            elseif ns.applied[pi.key] then
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
            RefreshSummary()
            ShowReloadBanner()
        end)
        table.insert(allCheckboxes, cb)
        table.insert(groupCheckboxes[ck], cb)
        by = by - 42
    end

    -- AutoLayer-specific settings: hop whisper toggle + custom message
    if groupId == "AutoLayer" and installed then
        by = by - 10
        local whisperSep = bf:CreateTexture(nil, "BACKGROUND")
        whisperSep:SetHeight(1)
        whisperSep:SetPoint("TOPLEFT", 24, by)
        whisperSep:SetPoint("RIGHT", bf, "RIGHT", -20, 0)
        SetSolidColor(whisperSep, 0.4, 0.4, 0.4, 0.3)
        by = by - 10

        local whisperCb = CreateFrame("CheckButton", "PatchWerk_CB_hopWhisper", bf, "UICheckButtonTemplate")
        whisperCb:SetPoint("TOPLEFT", 20, by)
        whisperCb.optionKey = "AutoLayer_hopWhisperEnabled"
        local wcbn = whisperCb:GetName()
        local wcbl = _G[wcbn .. "Text"]
        if wcbl then
            wcbl:SetText("Whisper thank you after auto-leave")
            wcbl:SetFontObject("GameFontHighlight")
        end
        whisperCb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Hop Whisper", 1, 1, 1)
            GameTooltip:AddLine("Send a thank-you whisper to the group host when auto-leaving after a layer hop.", 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        whisperCb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        whisperCb:SetScript("OnClick", function(self)
            ns:SetOption(self.optionKey, self:GetChecked() and true or false)
        end)
        table.insert(allCheckboxes, whisperCb)
        by = by - 28

        local msgLabel = bf:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        msgLabel:SetPoint("TOPLEFT", 48, by)
        msgLabel:SetText("Message:")

        local msgBox = CreateFrame("EditBox", "PatchWerk_HopWhisperMsg", bf, "InputBoxTemplate")
        msgBox:SetPoint("LEFT", msgLabel, "RIGHT", 8, 0)
        msgBox:SetPoint("RIGHT", bf, "RIGHT", -24, 0)
        msgBox:SetHeight(20)
        msgBox:SetAutoFocus(false)
        msgBox:SetMaxLetters(100)
        msgBox:SetText(ns:GetOption("AutoLayer_hopWhisperMessage") or "[PatchWerk] Thanks for the hop!")
        msgBox:SetScript("OnEnterPressed", function(self)
            local text = self:GetText()
            if text == "" then text = "[PatchWerk] Thanks for the hop!" end
            ns:SetOption("AutoLayer_hopWhisperMessage", text)
            self:ClearFocus()
        end)
        msgBox:SetScript("OnEscapePressed", function(self)
            self:SetText(ns:GetOption("AutoLayer_hopWhisperMessage") or "[PatchWerk] Thanks for the hop!")
            self:ClearFocus()
        end)

        local msgHint = bf:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        msgHint:SetPoint("TOPLEFT", 48, by - 22)
        msgHint:SetText("|cff555555Sent to the group host when auto-leaving after a hop.|r")
        by = by - 44
    end

    local bh = -by + 2
    bf:SetHeight(bh)

    local grpCbs = groupCheckboxes[ck]
    allBtn:SetScript("OnClick", function()
        -- Toggle: if any are on, turn all off; otherwise turn all on
        local anyOn = false
        for _, cb in ipairs(grpCbs) do
            if ns:GetOption(cb.optionKey) then anyOn = true; break end
        end
        local newVal = not anyOn
        for _, cb in ipairs(grpCbs) do
            ns:SetOption(cb.optionKey, newVal)
            cb:SetChecked(newVal)
        end
        RefreshStatusLabels(); RefreshGroupCounts(); RefreshSummary()
        ShowReloadBanner()
    end)
    if not installed then
        allBtn:Disable()
        allBtn:SetAlpha(0.4)
    end

    return {
        ck = ck, gf = gf, hf = hf, bf = bf, toggle = toggle,
        hh = 38, bh = bh, installed = installed,
    }
end

---------------------------------------------------------------------------
-- Single Options Panel
---------------------------------------------------------------------------
local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "PatchWerk"
    panel:Hide()
    local built = false

    panel:SetScript("OnShow", function(self)
        if built then
            for _, cb in ipairs(allCheckboxes) do cb:SetChecked(ns:GetOption(cb.optionKey)) end
            RefreshStatusLabels(); RefreshGroupCounts(); RefreshSummary()
            if reloadBanner then
                if pendingReload then reloadBanner:Show() else reloadBanner:Hide() end
            end
            if relayoutFunc then relayoutFunc() end
            return
        end
        built = true

        local bg = self:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        SetSolidColor(bg, 0.08, 0.08, 0.08, 1)

        local sf = CreateFrame("ScrollFrame", "PatchWerk_Scroll_Main", self, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 0, -10)
        sf:SetPoint("BOTTOMRIGHT", -26, 10)
        local content = CreateFrame("Frame")
        content:SetSize(580, 2000)
        sf:SetScrollChild(content)
        sf:SetScript("OnSizeChanged", function(s, w) if w and w > 0 then content:SetWidth(w) end end)
        local contentBg = content:CreateTexture(nil, "BACKGROUND")
        contentBg:SetAllPoints()
        SetSolidColor(contentBg, 0.08, 0.08, 0.08, 1)

        -- Header
        local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("|cff33ccffPatchWerk|r")
        local ver = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        ver:SetPoint("LEFT", title, "RIGHT", 6, 0)
        ver:SetText("v" .. ns.VERSION)

        -- Flavor intro
        local introText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        introText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        introText:SetPoint("RIGHT", content, "RIGHT", -16, 0)
        introText:SetJustifyH("LEFT")
        introText:SetWordWrap(true)
        introText:SetText("|cff888888No enrage timer. No tank swap. Just pure, uninterrupted performance."
            .. " Same addons, same features, no more lag.|r")

        summaryLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        summaryLabel:SetPoint("TOPLEFT", introText, "BOTTOMLEFT", 0, -6)
        summaryLabel:SetJustifyH("LEFT")

        -- Enable All / Disable All buttons
        local enableAllBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        enableAllBtn:SetPoint("TOPLEFT", summaryLabel, "BOTTOMLEFT", 0, -8)
        enableAllBtn:SetSize(80, 22)
        enableAllBtn:SetText("Enable All")
        enableAllBtn:GetFontString():SetFont(enableAllBtn:GetFontString():GetFont(), 10)
        enableAllBtn:SetScript("OnClick", function()
            for _, cb in ipairs(allCheckboxes) do
                ns:SetOption(cb.optionKey, true)
                cb:SetChecked(true)
            end
            RefreshStatusLabels(); RefreshGroupCounts(); RefreshSummary()
            ShowReloadBanner()
        end)

        local disableAllBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        disableAllBtn:SetPoint("LEFT", enableAllBtn, "RIGHT", 6, 0)
        disableAllBtn:SetSize(80, 22)
        disableAllBtn:SetText("Disable All")
        disableAllBtn:GetFontString():SetFont(disableAllBtn:GetFontString():GetFont(), 10)
        disableAllBtn:SetScript("OnClick", function()
            for _, cb in ipairs(allCheckboxes) do
                ns:SetOption(cb.optionKey, false)
                cb:SetChecked(false)
            end
            RefreshStatusLabels(); RefreshGroupCounts(); RefreshSummary()
            ShowReloadBanner()
        end)

        -- Reload banner
        local banner = CreateFrame("Frame", nil, content)
        banner:SetHeight(30)
        banner:Hide()
        local bannerBg = banner:CreateTexture(nil, "BACKGROUND")
        bannerBg:SetAllPoints()
        SetSolidColor(bannerBg, 0.6, 0.4, 0.0, 0.25)
        local bannerText = banner:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        bannerText:SetPoint("LEFT", 12, 0)
        bannerText:SetText("|cffffcc00Changes pending|r -- click Apply or /reload to take effect")
        local bannerBtn = CreateFrame("Button", nil, banner, "UIPanelButtonTemplate")
        bannerBtn:SetPoint("RIGHT", -8, 0)
        bannerBtn:SetSize(120, 20)
        bannerBtn:SetText("Apply (Reload)")
        bannerBtn:SetScript("OnClick", ReloadUI)
        reloadBanner = banner

        local headerBot = -100

        -- Build addon groups
        RebuildLookups()
        local installedData, uninstalledData = {}, {}
        for _, groupInfo in ipairs(ns.addonGroups) do
            local installed = false
            for _, dep in ipairs(groupInfo.deps) do
                if ns:IsAddonLoaded(dep) then installed = true; break end
            end
            local data = BuildAddonGroup(content, groupInfo, installed)
            if data then
                table.insert(installed and installedData or uninstalledData, data)
            end
        end

        -- "Not Installed" separator
        local nif = CreateFrame("Frame", nil, content)
        nif:SetHeight(32)
        local niSep = nif:CreateTexture(nil, "BACKGROUND")
        niSep:SetHeight(1)
        niSep:SetPoint("TOPLEFT", 12, -4)
        niSep:SetPoint("TOPRIGHT", -12, -4)
        SetSolidColor(niSep, 0.5, 0.5, 0.5, 0.4)
        local niLabel = nif:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        niLabel:SetPoint("TOPLEFT", 16, -12)
        niLabel:SetText("|cff666666Not Installed|r")
        if #uninstalledData == 0 then nif:Hide() end

        -- Footer / About section
        local footer = CreateFrame("Frame", nil, content)
        footer:SetHeight(60)
        local footerSep = footer:CreateTexture(nil, "BACKGROUND")
        footerSep:SetHeight(1)
        footerSep:SetPoint("TOPLEFT", 12, -2)
        footerSep:SetPoint("TOPRIGHT", -12, -2)
        SetSolidColor(footerSep, 0.5, 0.5, 0.5, 0.3)

        -- Author line with class colors
        local authorText = footer:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        authorText:SetPoint("TOPLEFT", 16, -12)
        -- Warlock: #9482C9, Mage: #69CCF0, Yellow: #FFD100
        authorText:SetText("|cffccccccEventyret|r  |cff555555(|r"
            .. "|cff9482C9HexusPlexus|r |cff555555/|r |cff69CCF0HokusFokus|r"
            .. " |cff555555-|r |cffFFD100Thunderstrike EU|r|cff555555)|r")

        local cmdHint = footer:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        cmdHint:SetPoint("TOPLEFT", authorText, "BOTTOMLEFT", 0, -4)
        cmdHint:SetText("|cff555555Type /pw help for commands|r")

        -- Reset Defaults button
        local resetBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
        resetBtn:SetPoint("TOPRIGHT", footer, "TOPRIGHT", -16, -10)
        resetBtn:SetSize(100, 18)
        resetBtn:SetText("Reset Defaults")
        resetBtn:GetFontString():SetFont(resetBtn:GetFontString():GetFont(), 10)
        resetBtn:SetScript("OnClick", function()
            if PatchWerkDB then
                local wizardState = PatchWerkDB.wizardCompleted
                local dismissed = PatchWerkDB.dismissedOutdated
                wipe(PatchWerkDB)
                for key, value in pairs(ns.defaults) do PatchWerkDB[key] = value end
                PatchWerkDB.wizardCompleted = wizardState
                PatchWerkDB.dismissedOutdated = dismissed or {}
            end
            for _, cb in ipairs(allCheckboxes) do cb:SetChecked(ns:GetOption(cb.optionKey)) end
            RefreshStatusLabels(); RefreshGroupCounts(); RefreshSummary()
            ShowReloadBanner()
            ns:Print("Settings reset to defaults. Reload to apply.")
        end)

        -- Layout function
        local function Relayout()
            local y = headerBot
            if pendingReload then
                banner:ClearAllPoints()
                banner:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
                banner:SetPoint("RIGHT", content, "RIGHT", -12, 0)
                banner:Show(); y = y - 34
            else
                banner:Hide()
            end
            for _, dd in ipairs(installedData) do
                dd.gf:ClearAllPoints()
                dd.gf:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                dd.gf:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                if collapsed[dd.ck] then
                    dd.bf:Hide(); dd.gf:SetHeight(dd.hh); y = y - dd.hh
                else
                    dd.bf:Show(); local h = dd.hh + dd.bh; dd.gf:SetHeight(h); y = y - h
                end
            end
            if #uninstalledData > 0 then
                nif:ClearAllPoints()
                nif:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                nif:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                nif:Show(); y = y - 32
            else
                nif:Hide()
            end
            for _, dd in ipairs(uninstalledData) do
                dd.gf:ClearAllPoints()
                dd.gf:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                dd.gf:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                if collapsed[dd.ck] then
                    dd.bf:Hide(); dd.gf:SetHeight(dd.hh); y = y - dd.hh
                else
                    dd.bf:Show(); local h = dd.hh + dd.bh; dd.gf:SetHeight(h); y = y - h
                end
            end
            footer:ClearAllPoints()
            footer:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y - 8)
            footer:SetPoint("RIGHT", content, "RIGHT", 0, 0)
            y = y - 8 - 60
            content:SetHeight(-y + 20)
        end
        relayoutFunc = Relayout

        -- Wire collapse toggles
        for _, dd in ipairs(installedData) do
            dd.hf:SetScript("OnMouseDown", function()
                collapsed[dd.ck] = not collapsed[dd.ck]
                dd.toggle:SetText(collapsed[dd.ck] and "|cffcccccc[+]|r" or "|cffcccccc[-]|r")
                Relayout()
            end)
        end
        for _, dd in ipairs(uninstalledData) do
            dd.hf:SetScript("OnMouseDown", function()
                collapsed[dd.ck] = not collapsed[dd.ck]
                dd.toggle:SetText(collapsed[dd.ck] and "|cffcccccc[+]|r" or "|cffcccccc[-]|r")
                Relayout()
            end)
        end

        -- Initialize
        for _, cb in ipairs(allCheckboxes) do cb:SetChecked(ns:GetOption(cb.optionKey)) end
        RefreshStatusLabels()
        RefreshGroupCounts()
        RefreshSummary()
        Relayout()
    end)
    return panel
end

---------------------------------------------------------------------------
-- Register Panel
---------------------------------------------------------------------------
local function RegisterPanel()
    local panel = CreateOptionsPanel()
    ns.optionsPanel = panel
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "PatchWerk")
        category.ID = "PatchWerk"
        Settings.RegisterAddOnCategory(category)
        ns.settingsCategoryID = "PatchWerk"
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

---------------------------------------------------------------------------
-- Slash Commands
---------------------------------------------------------------------------

local function ShowStatus(verbose)
    RebuildLookups()
    ns:Print("Status (v" .. ns.VERSION .. "):")
    for _, groupInfo in ipairs(ns.addonGroups) do
        local installed = false
        for _, dep in ipairs(groupInfo.deps) do
            if ns:IsAddonLoaded(dep) then installed = true; break end
        end

        local groupPatches = PATCHES_BY_GROUP[groupInfo.id]
        if groupPatches and #groupPatches > 0 and installed then
            local active, total, disabled = 0, #groupPatches, 0
            for _, p in ipairs(groupPatches) do
                if ns.applied[p.key] then
                    active = active + 1
                elseif not ns:GetOption(p.key) then
                    disabled = disabled + 1
                end
            end
            local short = groupInfo.label:match("^(.-)%s*%(") or groupInfo.label
            local color = active == total and "|cff33e633" or (active > 0 and "|cffffff00" or "|cff808080")
            local suffix = disabled > 0 and (" (" .. disabled .. " disabled)") or ""
            ns:Print("  " .. short .. ": " .. color .. active .. "/" .. total .. " active|r" .. suffix)

            if verbose then
                for _, p in ipairs(groupPatches) do
                    local status
                    if ns.applied[p.key] then
                        status = "|cff00ff00active|r"
                    elseif ns:GetOption(p.key) then
                        status = "|cffffff00enabled (reload needed)|r"
                    else
                        status = "|cffff0000disabled|r"
                    end
                    local catBadge = FormatCategoryBadge(p.category)
                    ns:Print("    " .. catBadge .. " " .. p.label .. ": " .. status)
                end
            end
        end
    end
end

local function HandleToggle(args)
    RebuildLookups()
    local target = args[2] and args[2]:lower() or ""
    local forceState = args[3] and args[3]:lower() or nil

    -- Try addon-level toggle first
    local canonicalId = ns.addonGroupsByIdLower[target]
    if canonicalId then
        local groupPatches = PATCHES_BY_GROUP[canonicalId]
        if groupPatches and #groupPatches > 0 then
            local newVal
            if forceState == "on" then
                newVal = true
            elseif forceState == "off" then
                newVal = false
            else
                -- Toggle: if any are on, turn all off; otherwise turn all on
                local anyOn = false
                for _, p in ipairs(groupPatches) do
                    if ns:GetOption(p.key) then anyOn = true; break end
                end
                newVal = not anyOn
            end
            for _, p in ipairs(groupPatches) do
                ns:SetOption(p.key, newVal)
            end
            local short = target
            for _, g in ipairs(ns.addonGroups) do
                if g.id == canonicalId then
                    short = g.label:match("^(.-)%s*%(") or g.label
                    break
                end
            end
            local stateStr = newVal and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
            ns:Print("All " .. short .. " patches " .. stateStr .. ". Reload UI to apply.")
            return
        end
    end

    -- Fall back to single patch toggle
    local patchKey = PATCH_NAMES_LOWER[target]
    if not patchKey then
        ns:Print("Unknown addon or patch: " .. tostring(args[2]))
        ns:Print("Use /pw status to see available patches.")
        return
    end

    local newVal
    if forceState == "on" then
        newVal = true
    elseif forceState == "off" then
        newVal = false
    else
        newVal = not ns:GetOption(patchKey)
    end
    ns:SetOption(patchKey, newVal)
    local newState = newVal and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    ns:Print(patchKey .. " is now " .. newState .. ". Reload UI to apply.")
end

local function HandleReset()
    if PatchWerkDB then
        local wizardState = PatchWerkDB.wizardCompleted
        local dismissed = PatchWerkDB.dismissedOutdated
        wipe(PatchWerkDB)
        for key, value in pairs(ns.defaults) do
            PatchWerkDB[key] = value
        end
        PatchWerkDB.wizardCompleted = wizardState
        PatchWerkDB.dismissedOutdated = dismissed or {}
    end
    ns:Print("All settings reset to defaults. Reload UI to apply.")
end

local function OpenOptionsPanel()
    if ns.settingsCategoryID and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(ns.settingsCategoryID)
    elseif InterfaceOptionsFrame_OpenToCategory and ns.optionsPanel then
        InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
    end
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
        OpenOptionsPanel()
    elseif cmd == "status" then
        local verbose = args[2] and args[2]:lower() == "verbose"
        ShowStatus(verbose)
    elseif cmd == "toggle" and args[2] then
        HandleToggle(args)
    elseif cmd == "reset" then
        HandleReset()
    elseif cmd == "outdated" then
        ns:ScanOutdatedPatches()
        ns:ReportOutdatedPatches()
    elseif cmd == "wizard" or cmd == "setup" then
        if ns.ResetWizard then ns:ResetWizard() end
        if ns.ShowWizard then ns:ShowWizard() end
    elseif cmd == "help" then
        ns:Print("Usage:")
        ns:Print("  /pw              Open settings panel")
        ns:Print("  /pw status       Show patched addons summary")
        ns:Print("  /pw toggle X     Toggle addon or patch (e.g. details, details off)")
        ns:Print("  /pw reset        Reset all settings to defaults")
        ns:Print("  /pw outdated     Check for addon version changes")
        ns:Print("  /pw wizard       Re-run the setup wizard")
    else
        ns:Print("Unknown command: " .. tostring(args[1]) .. ". Type /pw help for usage.")
    end
end

---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    RegisterPanel()
end)
