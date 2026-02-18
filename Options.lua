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
    Fixes       = "|cffff6666",   -- soft red
    Performance = "|cff66b3ff",   -- blue
    Tweaks      = "|cffe6b3ff",   -- lavender
}
local CATEGORY_LABELS = {
    Fixes       = "Fixes",
    Performance = "Performance",
    Tweaks      = "Tweaks",
}
local CATEGORY_DESC = {
    Fixes       = "Prevents crashes or errors on TBC Classic Anniversary",
    Performance = "Improves FPS, memory usage, or network performance",
    Tweaks      = "Improves addon behavior or fixes confusing display issues",
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
    local color = CATEGORY_COLORS[category] or CATEGORY_COLORS.Perf
    local label = CATEGORY_LABELS[category] or category
    return color .. "[" .. label .. "]|r"
end

---------------------------------------------------------------------------
-- GUI Panel (Multi-Page Interface)
---------------------------------------------------------------------------

-- Shared state across all pages
local pendingReload = false
local allCheckboxes = {}
local groupCheckboxes = {}
local groupCountLabels = {}
local statusLabels = {}
local collapsed = {}
local reloadBanners = {}
local relayoutFuncs = {}
local parentCategory = nil
local subCategories = {}
local mainDashboardRefresh = nil

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

local function ComputeTally()
    RebuildLookups()
    local installedGroups, installedCount = {}, 0
    for _, g in ipairs(ns.addonGroups) do
        for _, dep in ipairs(g.deps) do
            if ns:IsAddonLoaded(dep) then
                installedGroups[g.id] = true
                installedCount = installedCount + 1
                break
            end
        end
    end
    local fps, mem, net, high = 0, 0, 0, 0
    local catTotal = { Fixes = 0, Performance = 0, Tweaks = 0 }
    local catActive = { Fixes = 0, Performance = 0, Tweaks = 0 }
    local totalActive = 0
    for _, p in ipairs(PATCH_INFO) do
        if catTotal[p.category] then catTotal[p.category] = catTotal[p.category] + 1 end
        if installedGroups[p.group] and ns:GetOption(p.key) then
            totalActive = totalActive + 1
            if p.impact == "FPS" then fps = fps + 1
            elseif p.impact == "Memory" then mem = mem + 1
            elseif p.impact == "Network" then net = net + 1 end
            if p.impactLevel == "High" then high = high + 1 end
            if catActive[p.category] then catActive[p.category] = catActive[p.category] + 1 end
        end
    end
    return {
        installed = installedCount, totalGroups = #ns.addonGroups,
        totalActive = totalActive, totalPatches = #PATCH_INFO,
        fps = fps, mem = mem, net = net, high = high,
        catTotal = catTotal, catActive = catActive,
    }
end

local function CreateReloadBanner(parent, pageKey)
    local banner = CreateFrame("Frame", nil, parent)
    banner:SetHeight(30)
    banner:Hide()
    local bg = banner:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SetSolidColor(bg, 0.6, 0.4, 0.0, 0.25)
    local text = banner:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 12, 0)
    text:SetText("|cffffcc00Changes pending|r -- click Apply or /reload to take effect")
    local btn = CreateFrame("Button", nil, banner, "UIPanelButtonTemplate")
    btn:SetPoint("RIGHT", -8, 0)
    btn:SetSize(120, 20)
    btn:SetText("Apply (Reload)")
    btn:SetScript("OnClick", ReloadUI)
    reloadBanners[pageKey] = banner
    return banner
end

local function ShowReloadBanner()
    if not pendingReload then
        pendingReload = true
        for _, b in pairs(reloadBanners) do b:Show() end
        for _, fn in pairs(relayoutFuncs) do fn() end
    end
end

---------------------------------------------------------------------------
-- BuildCategoryPage — reusable group builder for one category
---------------------------------------------------------------------------
local function BuildCategoryPage(content, categoryFilter)
    RebuildLookups()
    local installedData, uninstalledData = {}, {}
    for _, groupInfo in ipairs(ns.addonGroups) do
        local groupId = groupInfo.id
        local patches = {}
        for _, p in ipairs(PATCHES_BY_GROUP[groupId] or {}) do
            if p.category == categoryFilter then table.insert(patches, p) end
        end
        if #patches > 0 then
        local installed = false
        for _, dep in ipairs(groupInfo.deps) do
            if ns:IsAddonLoaded(dep) then installed = true; break end
        end
        local ck = groupId .. "_" .. categoryFilter
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
        local gc = hf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        gc:SetPoint("LEFT", hlabel, "RIGHT", 10, 0)
        groupCountLabels[ck] = gc
        if not installed then
            local note = hf:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            note:SetPoint("LEFT", gc, "RIGHT", 8, 0)
            note:SetText("(not installed)")
        end
        local allOnBtn = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
        allOnBtn:SetPoint("TOPRIGHT", hf, "TOPRIGHT", -80, -8)
        allOnBtn:SetSize(60, 18)
        allOnBtn:SetText("All On")
        allOnBtn:GetFontString():SetFont(allOnBtn:GetFontString():GetFont(), 10)
        local allOffBtn = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
        allOffBtn:SetPoint("LEFT", allOnBtn, "RIGHT", 4, 0)
        allOffBtn:SetSize(60, 18)
        allOffBtn:SetText("All Off")
        allOffBtn:GetFontString():SetFont(allOffBtn:GetFontString():GetFont(), 10)
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
                cbl:SetText(pi.label .. "  " .. FormatBadge(pi.impact, pi.impactLevel))
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
                if mainDashboardRefresh then mainDashboardRefresh() end
                ShowReloadBanner()
            end)
            table.insert(allCheckboxes, cb)
            table.insert(groupCheckboxes[ck], cb)
            by = by - 42
        end
        local bh = -by + 2
        bf:SetHeight(bh)
        local grpCbs = groupCheckboxes[ck]
        allOnBtn:SetScript("OnClick", function()
            for _, cb in ipairs(grpCbs) do ns:SetOption(cb.optionKey, true); cb:SetChecked(true) end
            RefreshStatusLabels(); RefreshGroupCounts()
            if mainDashboardRefresh then mainDashboardRefresh() end
            ShowReloadBanner()
        end)
        allOffBtn:SetScript("OnClick", function()
            for _, cb in ipairs(grpCbs) do ns:SetOption(cb.optionKey, false); cb:SetChecked(false) end
            RefreshStatusLabels(); RefreshGroupCounts()
            if mainDashboardRefresh then mainDashboardRefresh() end
            ShowReloadBanner()
        end)
        if not installed then
            allOnBtn:Disable(); allOffBtn:Disable()
            allOnBtn:SetAlpha(0.4); allOffBtn:SetAlpha(0.4)
        end
        local data = {
            ck = ck, gf = gf, hf = hf, bf = bf, toggle = toggle,
            hh = 38, bh = bh, installed = installed,
        }
        table.insert(installed and installedData or uninstalledData, data)
        end -- #patches > 0
    end
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
    return installedData, uninstalledData, nif
end

---------------------------------------------------------------------------
-- Category Sub-Page Builder
---------------------------------------------------------------------------
local function CreateCategorySubPanel(name, catFilter, desc)
    local sub = CreateFrame("Frame")
    sub.name = name
    sub.parent = "PatchWerk"
    sub:Hide()
    local built = false
    sub:SetScript("OnShow", function(self)
        if built then
            for _, cb in ipairs(allCheckboxes) do cb:SetChecked(ns:GetOption(cb.optionKey)) end
            RefreshStatusLabels(); RefreshGroupCounts()
            local b = reloadBanners[catFilter]
            if b then if pendingReload then b:Show() else b:Hide() end end
            if relayoutFuncs[catFilter] then relayoutFuncs[catFilter]() end
            return
        end
        built = true
        local bg = self:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        SetSolidColor(bg, 0.08, 0.08, 0.08, 1)
        local sf = CreateFrame("ScrollFrame", "PatchWerk_Scroll_" .. catFilter, self, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 0, -10)
        sf:SetPoint("BOTTOMRIGHT", -26, 10)
        local content = CreateFrame("Frame")
        content:SetSize(580, 2000)
        sf:SetScrollChild(content)
        sf:SetScript("OnSizeChanged", function(s, w) if w and w > 0 then content:SetWidth(w) end end)
        local contentBg = content:CreateTexture(nil, "BACKGROUND")
        contentBg:SetAllPoints()
        SetSolidColor(contentBg, 0.08, 0.08, 0.08, 1)
        local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText(name)
        local descFs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        descFs:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        descFs:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        descFs:SetText(desc)
        descFs:SetJustifyH("LEFT")
        local banner = CreateReloadBanner(content, catFilter)
        local headerBot = -50
        local iData, uData, nif = BuildCategoryPage(content, catFilter)
        local function Relayout()
            local y = headerBot
            if pendingReload then
                banner:ClearAllPoints()
                banner:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
                banner:SetPoint("RIGHT", content, "RIGHT", -12, 0)
                banner:Show(); y = y - 34
            else banner:Hide() end
            for _, dd in ipairs(iData) do
                dd.gf:ClearAllPoints()
                dd.gf:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                dd.gf:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                if collapsed[dd.ck] then
                    dd.bf:Hide(); dd.gf:SetHeight(dd.hh); y = y - dd.hh
                else
                    dd.bf:Show(); local h = dd.hh + dd.bh; dd.gf:SetHeight(h); y = y - h
                end
            end
            if #uData > 0 then
                nif:ClearAllPoints()
                nif:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                nif:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                nif:Show(); y = y - 32
            else nif:Hide() end
            for _, dd in ipairs(uData) do
                dd.gf:ClearAllPoints()
                dd.gf:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                dd.gf:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                if collapsed[dd.ck] then
                    dd.bf:Hide(); dd.gf:SetHeight(dd.hh); y = y - dd.hh
                else
                    dd.bf:Show(); local h = dd.hh + dd.bh; dd.gf:SetHeight(h); y = y - h
                end
            end
            content:SetHeight(-y + 20)
        end
        relayoutFuncs[catFilter] = Relayout
        for _, dd in ipairs(iData) do
            dd.hf:SetScript("OnMouseDown", function()
                collapsed[dd.ck] = not collapsed[dd.ck]
                dd.toggle:SetText(collapsed[dd.ck] and "|cffcccccc[+]|r" or "|cffcccccc[-]|r")
                Relayout()
            end)
        end
        for _, dd in ipairs(uData) do
            dd.hf:SetScript("OnMouseDown", function()
                collapsed[dd.ck] = not collapsed[dd.ck]
                dd.toggle:SetText(collapsed[dd.ck] and "|cffcccccc[+]|r" or "|cffcccccc[-]|r")
                Relayout()
            end)
        end
        Relayout()
        -- Initialize checkbox states on first build (same as the re-show branch)
        for _, cb in ipairs(allCheckboxes) do cb:SetChecked(ns:GetOption(cb.optionKey)) end
        RefreshStatusLabels()
        RefreshGroupCounts()
    end)
    return sub
end

---------------------------------------------------------------------------
-- About Sub-Page
---------------------------------------------------------------------------
local function CreateAboutPanel()
    local ap = CreateFrame("Frame")
    ap.name = "About"
    ap.parent = "PatchWerk"
    ap:Hide()
    local built = false
    ap:SetScript("OnShow", function(self)
        if built then return end
        built = true
        local bg = self:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        SetSolidColor(bg, 0.08, 0.08, 0.08, 1)
        local sf = CreateFrame("ScrollFrame", "PatchWerk_Scroll_About", self, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 0, -10)
        sf:SetPoint("BOTTOMRIGHT", -26, 10)
        local content = CreateFrame("Frame")
        content:SetSize(580, 800)
        sf:SetScrollChild(content)
        sf:SetScript("OnSizeChanged", function(s, w) if w and w > 0 then content:SetWidth(w) end end)
        local contentBg = content:CreateTexture(nil, "BACKGROUND")
        contentBg:SetAllPoints()
        SetSolidColor(contentBg, 0.08, 0.08, 0.08, 1)
        local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("|cff33ccffPatchWerk|r")
        local ver = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        ver:SetPoint("LEFT", title, "RIGHT", 6, 0)
        ver:SetText("v" .. ns.VERSION)
        local author = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        author:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        author:SetText("by |cffffd100Eventyret|r  (|cff8788EEHexusPlexus|r - Thunderstrike EU)")
        local flavor = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        flavor:SetPoint("TOPLEFT", author, "BOTTOMLEFT", 0, -12)
        flavor:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        flavor:SetJustifyH("LEFT"); flavor:SetWordWrap(true)
        flavor:SetText(
            "No enrage timer. No tank swap. Just pure, uninterrupted performance.\n\n" ..
            "PatchWerk fixes performance problems hiding inside your other addons -- " ..
            "things like addons refreshing way too fast, doing the same work twice, " ..
            "or leaking memory like a boss with no mechanics. Your addons keep " ..
            "working exactly the same, just without the lag.\n\n" ..
            "All patches are enabled by default and everything is safe to toggle. " ..
            "Most players can just leave it all on and enjoy the extra frames. " ..
            "If Patchwerk himself had this kind of efficiency, he wouldn't need " ..
            "a hateful strike.")
        local legendSep = content:CreateTexture(nil, "BACKGROUND")
        legendSep:SetHeight(1)
        legendSep:SetPoint("TOPLEFT", flavor, "BOTTOMLEFT", -4, -16)
        legendSep:SetPoint("RIGHT", content, "RIGHT", -16, 0)
        SetSolidColor(legendSep, 0.6, 0.6, 0.6, 0.35)
        local legendTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        legendTitle:SetPoint("TOPLEFT", legendSep, "BOTTOMLEFT", 4, -8)
        legendTitle:SetText("Badge Legend")
        local legendText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        legendText:SetPoint("TOPLEFT", legendTitle, "BOTTOMLEFT", 0, -6)
        legendText:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        legendText:SetJustifyH("LEFT"); legendText:SetWordWrap(true)
        legendText:SetText(
            "|cffff9999Categories:|r\n" ..
            "  |cffff6666[Fixes]|r  Crash or error fix for TBC Classic Anniversary\n" ..
            "  |cff66b3ff[Performance]|r  FPS, memory, or network optimization\n" ..
            "  |cffe6b3ff[Tweaks]|r  Behavior or display improvement\n\n" ..
            "|cff99ccffImpact Type:|r\n" ..
            "  |cff33e633[FPS]|r  Smoother gameplay\n" ..
            "  |cff33cce6[Memory]|r  Less memory usage and fewer slowdowns\n" ..
            "  |cffff9933[Network]|r  Less server traffic\n\n" ..
            "|cffffffccImpact Level:|r\n" ..
            "  |cffffd100High|r  Very noticeable improvement\n" ..
            "  |cffbfbfbfMedium|r  Helps in busy situations\n" ..
            "  |cff996633Low|r  Small improvement")
        local cmdSep = content:CreateTexture(nil, "BACKGROUND")
        cmdSep:SetHeight(1)
        cmdSep:SetPoint("TOPLEFT", legendText, "BOTTOMLEFT", -4, -16)
        cmdSep:SetPoint("RIGHT", content, "RIGHT", -16, 0)
        SetSolidColor(cmdSep, 0.6, 0.6, 0.6, 0.35)
        local cmdTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        cmdTitle:SetPoint("TOPLEFT", cmdSep, "BOTTOMLEFT", 4, -8)
        cmdTitle:SetText("Slash Commands")
        local cmdText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        cmdText:SetPoint("TOPLEFT", cmdTitle, "BOTTOMLEFT", 0, -6)
        cmdText:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        cmdText:SetJustifyH("LEFT"); cmdText:SetWordWrap(true)
        cmdText:SetText(
            "|cffffd100/pw|r or |cffffd100/patchwerk|r  Open main settings panel\n" ..
            "|cffffd100/pw fixes|r  Open Fixes page\n" ..
            "|cffffd100/pw performance|r  Open Performance page\n" ..
            "|cffffd100/pw tweaks|r  Open Tweaks page\n" ..
            "|cffffd100/pw about|r  Open this page\n" ..
            "|cffffd100/pw status|r  Print patch status to chat\n" ..
            "|cffffd100/pw toggle <name>|r  Toggle a specific patch\n" ..
            "|cffffd100/pw reset|r  Reset all settings to defaults\n" ..
            "|cffffd100/pw wizard|r  Show the welcome wizard\n" ..
            "|cffffd100/pw help|r  Show command help in chat")
        content:SetHeight(800)
    end)
    return ap
end

---------------------------------------------------------------------------
-- Main "At a Glance" Dashboard Page
---------------------------------------------------------------------------
local function CreateMainPanel()
    local panel = CreateFrame("Frame")
    panel.name = "PatchWerk"
    panel:Hide()
    local built = false
    local mainCountLabel, mainCatLabel, mainTallyLabel
    local cardCounts = {}
    local function RefreshDashboard()
        if not mainCountLabel then return end
        local t = ComputeTally()
        mainCountLabel:SetText(t.installed .. " of " .. t.totalGroups .. " supported addons installed — " ..
            "|cff33e633" .. t.totalActive .. "/" .. t.totalPatches .. " patches active|r")
        local parts = {}
        if t.catActive.Performance > 0 then table.insert(parts, "|cff66b3ff" .. t.catActive.Performance .. " Performance|r") end
        if t.catActive.Fixes > 0 then table.insert(parts, "|cffff6666" .. t.catActive.Fixes .. " Fixes|r") end
        if t.catActive.Tweaks > 0 then table.insert(parts, "|cffe6b3ff" .. t.catActive.Tweaks .. " Tweaks|r") end
        mainCatLabel:SetText(#parts > 0 and table.concat(parts, "  |cff666666|||r  ") or "|cff808080No active patches|r")
        local iparts = {}
        if t.fps > 0 then table.insert(iparts, "|cff33e633" .. t.fps .. " FPS|r") end
        if t.mem > 0 then table.insert(iparts, "|cff33cce6" .. t.mem .. " Memory|r") end
        if t.net > 0 then table.insert(iparts, "|cffff9933" .. t.net .. " Network|r") end
        if #iparts > 0 then
            local txt = table.concat(iparts, "  |cff666666|||r  ")
            if t.high > 0 then txt = txt .. "  —  |cffffd100" .. t.high .. " high-impact|r" end
            mainTallyLabel:SetText(txt)
        else
            mainTallyLabel:SetText("|cff808080No active patches for installed addons|r")
        end
        for cat, fs in pairs(cardCounts) do
            if t.catTotal[cat] then fs:SetText(t.catTotal[cat] .. " patches") end
        end
    end
    mainDashboardRefresh = RefreshDashboard
    panel:SetScript("OnShow", function(self)
        if built then
            RefreshDashboard()
            local b = reloadBanners["main"]
            if b then if pendingReload then b:Show() else b:Hide() end end
            if relayoutFuncs["main"] then relayoutFuncs["main"]() end
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
        content:SetSize(580, 800)
        sf:SetScrollChild(content)
        sf:SetScript("OnSizeChanged", function(s, w) if w and w > 0 then content:SetWidth(w) end end)
        local contentBg = content:CreateTexture(nil, "BACKGROUND")
        contentBg:SetAllPoints()
        SetSolidColor(contentBg, 0.08, 0.08, 0.08, 1)
        local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("PatchWerk")
        local ver = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        ver:SetPoint("LEFT", title, "RIGHT", 6, 0)
        ver:SetText("v" .. ns.VERSION)
        local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        subtitle:SetText("Performance patches for popular addons")
        subtitle:SetJustifyH("LEFT")
        mainCountLabel = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        mainCountLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -6)
        mainCountLabel:SetJustifyH("LEFT")
        mainCatLabel = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        mainCatLabel:SetPoint("TOPLEFT", mainCountLabel, "BOTTOMLEFT", 0, -2)
        mainCatLabel:SetJustifyH("LEFT")
        mainTallyLabel = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        mainTallyLabel:SetPoint("TOPLEFT", mainCatLabel, "BOTTOMLEFT", 0, -2)
        mainTallyLabel:SetJustifyH("LEFT")
        local banner = CreateReloadBanner(content, "main")
        local cardsTop = -110
        local cardDefs = {
            { name = "Fixes", color = {1,0.4,0.4}, catID = "PatchWerk_Fixes", desc = "Prevents crashes and errors" },
            { name = "Performance", color = {0.4,0.7,1}, catID = "PatchWerk_Performance", desc = "FPS, memory, and network optimizations" },
            { name = "Tweaks", color = {0.9,0.7,1}, catID = "PatchWerk_Tweaks", desc = "Behavior improvements" },
            { name = "About", color = {0.6,0.6,0.6}, catID = "PatchWerk_About", desc = "Info, commands, and credits" },
        }
        local cardFrames = {}
        local function Relayout()
            local y = cardsTop
            if pendingReload then
                banner:ClearAllPoints()
                banner:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
                banner:SetPoint("RIGHT", content, "RIGHT", -12, 0)
                banner:Show(); y = y - 34
            else banner:Hide() end
            for _, card in ipairs(cardFrames) do
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
                card:SetPoint("RIGHT", content, "RIGHT", -16, 0)
                y = y - 52
            end
            if panel.resetBtn then
                panel.resetBtn:ClearAllPoints()
                panel.resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y - 10)
            end
            content:SetHeight(-(y - 10) + 60)
        end
        relayoutFuncs["main"] = Relayout
        for _, def in ipairs(cardDefs) do
            local card = CreateFrame("Frame", nil, content)
            card:SetHeight(44)
            card:EnableMouse(true)
            local bg = card:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            SetSolidColor(bg, 0.12, 0.12, 0.12, 0.8)
            local bar = card:CreateTexture(nil, "ARTWORK")
            bar:SetPoint("TOPLEFT", 0, 0); bar:SetPoint("BOTTOMLEFT", 0, 0)
            bar:SetWidth(4)
            SetSolidColor(bar, def.color[1], def.color[2], def.color[3], 1)
            local ct = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            ct:SetPoint("TOPLEFT", 14, -6)
            ct:SetText(def.name)
            if def.name ~= "About" then
                local countFs = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                countFs:SetPoint("LEFT", ct, "RIGHT", 8, 0)
                cardCounts[def.name] = countFs
            end
            local cd = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            cd:SetPoint("TOPLEFT", ct, "BOTTOMLEFT", 0, -2)
            cd:SetText("|cff999999" .. def.desc .. "|r")
            local arrow = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            arrow:SetPoint("RIGHT", -12, 0)
            arrow:SetText("|cffaaaaaa>|r")
            card:SetScript("OnEnter", function()
                bg:SetVertexColor(0.18, 0.18, 0.18, 0.9)
                arrow:SetText("|cffcccccc>|r")
            end)
            card:SetScript("OnLeave", function()
                bg:SetVertexColor(0.12, 0.12, 0.12, 0.8)
                arrow:SetText("|cffaaaaaa>|r")
            end)
            local targetID = def.catID
            card:SetScript("OnMouseDown", function()
                if Settings and Settings.OpenToCategory then
                    Settings.OpenToCategory(targetID)
                elseif InterfaceOptionsFrame_OpenToCategory and subCategories[def.name] then
                    InterfaceOptionsFrame_OpenToCategory(subCategories[def.name])
                    InterfaceOptionsFrame_OpenToCategory(subCategories[def.name])
                end
            end)
            table.insert(cardFrames, card)
        end
        local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        resetBtn:SetSize(160, 26)
        resetBtn:SetText("Reset to Defaults (All On)")
        resetBtn:SetScript("OnClick", function()
            if PatchWerkDB then
                wipe(PatchWerkDB)
                for key, value in pairs(ns.defaults) do PatchWerkDB[key] = value end
            end
            for _, cb in ipairs(allCheckboxes) do cb:SetChecked(ns:GetOption(cb.optionKey)) end
            RefreshStatusLabels(); RefreshGroupCounts(); RefreshDashboard()
            ShowReloadBanner()
            ns:Print("Settings reset to defaults. Reload to apply.")
        end)
        panel.resetBtn = resetBtn
        local reloadBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        reloadBtn:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
        reloadBtn:SetSize(140, 26)
        reloadBtn:SetText("Apply Changes (Reload)")
        reloadBtn:SetScript("OnClick", ReloadUI)
        local wizardBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        wizardBtn:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -6)
        wizardBtn:SetSize(160, 26)
        wizardBtn:SetText("Show Welcome Wizard")
        wizardBtn:SetScript("OnClick", function()
            if ns.ResetWizard then ns:ResetWizard() end
            if ns.ShowWizard then ns:ShowWizard() end
        end)
        RefreshDashboard()
        Relayout()
    end)
    return panel
end

---------------------------------------------------------------------------
-- Register All Panels
---------------------------------------------------------------------------
local function RegisterAllPanels()
    local mainPanel = CreateMainPanel()
    ns.optionsPanel = mainPanel
    if Settings and Settings.RegisterCanvasLayoutCategory then
        parentCategory = Settings.RegisterCanvasLayoutCategory(mainPanel, "PatchWerk")
        parentCategory.ID = "PatchWerk"
        Settings.RegisterAddOnCategory(parentCategory)
        ns.settingsCategoryID = "PatchWerk"
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(mainPanel)
    end
    local subDefs = {
        { name = "Fixes", filter = "Fixes", desc = "Patches that prevent crashes or errors on TBC Classic Anniversary" },
        { name = "Performance", filter = "Performance", desc = "Optimizations for FPS, memory usage, and network traffic" },
        { name = "Tweaks", filter = "Tweaks", desc = "Behavior and display improvements" },
    }
    for _, def in ipairs(subDefs) do
        local subPanel = CreateCategorySubPanel(def.name, def.filter, def.desc)
        subCategories[def.name] = subPanel
        if Settings and parentCategory then
            local sc = Settings.RegisterCanvasLayoutSubcategory(parentCategory, subPanel, def.name)
            sc.ID = "PatchWerk_" .. def.filter
            Settings.RegisterAddOnCategory(sc)
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(subPanel)
        end
    end
    local aboutPanel = CreateAboutPanel()
    subCategories["About"] = aboutPanel
    if Settings and parentCategory then
        local sc = Settings.RegisterCanvasLayoutSubcategory(parentCategory, aboutPanel, "About")
        sc.ID = "PatchWerk_About"
        Settings.RegisterAddOnCategory(sc)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(aboutPanel)
    end
end

---------------------------------------------------------------------------
-- Navigate to Sub-Page
---------------------------------------------------------------------------
local function OpenSubPage(pageKey)
    local catID = "PatchWerk_" .. pageKey
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(catID)
    elseif InterfaceOptionsFrame_OpenToCategory and subCategories[pageKey] then
        InterfaceOptionsFrame_OpenToCategory(subCategories[pageKey])
        InterfaceOptionsFrame_OpenToCategory(subCategories[pageKey])
    end
end

---------------------------------------------------------------------------
-- Slash Commands
---------------------------------------------------------------------------

local function ShowStatus()
    RebuildLookups()
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
                local catBadge = FormatCategoryBadge(p.category)
                ns:Print("  " .. catBadge .. " " .. p.label .. ": " .. status)
            end
        end
    end
end

local function HandleToggle(input)
    RebuildLookups()
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
    elseif cmd == "fixes" then
        OpenSubPage("Fixes")
    elseif cmd == "performance" or cmd == "perf" then
        OpenSubPage("Performance")
    elseif cmd == "tweaks" then
        OpenSubPage("Tweaks")
    elseif cmd == "about" then
        OpenSubPage("About")
    elseif cmd == "config" or cmd == "options" then
        if ns.settingsCategoryID and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(ns.settingsCategoryID)
        elseif InterfaceOptionsFrame_OpenToCategory and ns.optionsPanel then
            InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
            InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
        else
            ShowStatus()
        end
    elseif cmd == "wizard" or cmd == "setup" then
        if ns.ResetWizard then ns:ResetWizard() end
        if ns.ShowWizard then ns:ShowWizard() end
    elseif cmd == "help" then
        ns:Print("Usage:")
        ns:Print("  /pw                Open settings panel")
        ns:Print("  /pw fixes          Open Fixes page")
        ns:Print("  /pw performance    Open Performance page")
        ns:Print("  /pw tweaks         Open Tweaks page")
        ns:Print("  /pw about          Open About page")
        ns:Print("  /pw status         Show all patch status")
        ns:Print("  /pw toggle X       Toggle a patch on/off")
        ns:Print("  /pw reset          Reset to defaults")
        ns:Print("  /pw wizard         Show the setup wizard")
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
    RegisterAllPanels()
end)
