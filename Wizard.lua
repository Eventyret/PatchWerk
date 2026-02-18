-- Wizard.lua: First-time setup wizard for PatchWerk
--
-- Shows a 4-page onboarding flow on first install:
--   1. Welcome — what PatchWerk does
--   2. Detected Addons — which supported addons are installed
--   3. Configure — checkbox toggles with preset buttons
--   4. Done — summary and reminder

local _, ns = ...

local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local CreateFrame = CreateFrame
local UIParent = UIParent
local GameTooltip = GameTooltip

local WHITE8x8 = "Interface\\Buttons\\WHITE8x8"
local function SetSolidColor(tex, r, g, b, a)
    tex:SetTexture(WHITE8x8)
    tex:SetVertexColor(r, g, b, a or 1)
end

local WIZARD_WIDTH = 520
local WIZARD_HEIGHT = 420
local NUM_PAGES = 4

local CATEGORY_COLORS = {
    Fixes       = { r = 1.0, g = 0.4, b = 0.4 },
    Performance = { r = 0.4, g = 0.7, b = 1.0 },
    Tweaks      = { r = 0.9, g = 0.7, b = 1.0 },
}

local wizardFrame = nil
local currentPage = 1
local pages = {}
local pageDots = {}
local detectedAddons = {}
local wizardCheckboxes = {}

---------------------------------------------------------------------------
-- Detect which supported addons are installed
---------------------------------------------------------------------------
local function DetectAddons()
    wipe(detectedAddons)
    for _, groupInfo in ipairs(ns.addonGroups) do
        local installed = false
        for _, dep in ipairs(groupInfo.deps) do
            if ns:IsAddonLoaded(dep) then installed = true; break end
        end
        detectedAddons[groupInfo.id] = installed
    end
end

---------------------------------------------------------------------------
-- Page 1: Welcome
---------------------------------------------------------------------------
local function BuildWelcomePage(container)
    local page = CreateFrame("Frame", nil, container)
    page:SetAllPoints()
    page:Hide()

    local logo = page:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    logo:SetPoint("TOP", 0, -30)
    logo:SetText("|cff33ccffPatchWerk|r")

    local sub = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sub:SetPoint("TOP", logo, "BOTTOM", 0, -6)
    sub:SetText("|cffaaaaaaPerformance patches for your addons|r")

    local body = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    body:SetPoint("TOP", sub, "BOTTOM", 0, -24)
    body:SetPoint("LEFT", container, "LEFT", 40, 0)
    body:SetPoint("RIGHT", container, "RIGHT", -40, 0)
    body:SetJustifyH("CENTER")
    body:SetWordWrap(true)
    body:SetText(
        "Your addons are great — but some of them are working harder " ..
        "than a Patchwerk tank and leaking more memory than a boss " ..
        "with no mechanics.\n\n" ..
        "PatchWerk patches your addons at load time: throttling " ..
        "excessive updates, caching repeated work, and fixing bugs " ..
        "the developers didn't catch.\n\n" ..
        "No enrage timer. No tank swap. Just pure, uninterrupted " ..
        "performance. Your addons keep working the same — just " ..
        "without the lag.\n\n" ..
        "All patches are safe to toggle. Type |cffffd100/pw|r anytime."
    )

    local hint = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", container, "BOTTOM", 0, 8)
    hint:SetText("Click Next to see what addons PatchWerk can help with.")

    return page
end

---------------------------------------------------------------------------
-- Page 2: Detected Addons
---------------------------------------------------------------------------
local function BuildDetectedPage(container)
    local page = CreateFrame("Frame", nil, container)
    page:SetAllPoints()
    page:Hide()

    local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 24, -14)
    title:SetText("Detected Addons")

    local summary = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    local sf = CreateFrame("ScrollFrame", "PatchWerk_WizScroll2", page, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -48)
    sf:SetPoint("BOTTOMRIGHT", -30, 8)
    local content = CreateFrame("Frame")
    content:SetSize(440, 800)
    sf:SetScrollChild(content)
    sf:SetScript("OnSizeChanged", function(s, w) if w and w > 0 then content:SetWidth(w) end end)

    local built = false
    page.Refresh = function()
        DetectAddons()
        if built then return end
        built = true

        local y = 0
        local installed, total = 0, #ns.addonGroups
        for _, groupInfo in ipairs(ns.addonGroups) do
            if detectedAddons[groupInfo.id] then
                installed = installed + 1

                local row = CreateFrame("Frame", nil, content)
                row:SetPoint("TOPLEFT", 0, y)
                row:SetPoint("RIGHT", 0, 0)
                row:SetHeight(24)

                local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                label:SetPoint("LEFT", 12, 0)
                label:SetText(groupInfo.label)

                local patchCount = 0
                for _, p in ipairs(ns.patchInfo) do
                    if p.group == groupInfo.id then patchCount = patchCount + 1 end
                end
                local info = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                info:SetPoint("RIGHT", -8, 0)
                info:SetText("|cff808080" .. patchCount .. " patches|r")

                if y < 0 then
                    local sep = row:CreateTexture(nil, "BACKGROUND")
                    sep:SetHeight(1)
                    sep:SetPoint("TOPLEFT", 4, 0)
                    sep:SetPoint("TOPRIGHT", -4, 0)
                    SetSolidColor(sep, 0.25, 0.25, 0.25, 0.4)
                end

                y = y - 24
            end
        end
        content:SetHeight(math.max(-y + 8, 100))
        summary:SetText("|cff33e633" .. installed .. "|r of " .. total .. " supported addons detected")
    end

    return page
end

---------------------------------------------------------------------------
-- Page 3: Patch Configuration
---------------------------------------------------------------------------
local function BuildConfigPage(container)
    local page = CreateFrame("Frame", nil, container)
    page:SetAllPoints()
    page:Hide()

    local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 24, -14)
    title:SetText("Configure Patches")

    local desc = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetText("Choose which patches to enable. |cff33e633Recommended: leave everything on.|r")

    -- Preset buttons (row 1)
    local recBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    recBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -6)
    recBtn:SetSize(130, 20)
    recBtn:SetText("All On (Recommended)")
    recBtn:GetFontString():SetFont(recBtn:GetFontString():GetFont(), 10)

    local offBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    offBtn:SetPoint("LEFT", recBtn, "RIGHT", 6, 0)
    offBtn:SetSize(60, 20)
    offBtn:SetText("All Off")
    offBtn:GetFontString():SetFont(offBtn:GetFontString():GetFont(), 10)

    -- Preset buttons (row 2: by category)
    local minBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    minBtn:SetPoint("TOPLEFT", recBtn, "BOTTOMLEFT", 0, -2)
    minBtn:SetSize(80, 20)
    minBtn:SetText("Fixes Only")
    minBtn:GetFontString():SetFont(minBtn:GetFontString():GetFont(), 10)

    local perfBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    perfBtn:SetPoint("LEFT", minBtn, "RIGHT", 6, 0)
    perfBtn:SetSize(110, 20)
    perfBtn:SetText("Performance Only")
    perfBtn:GetFontString():SetFont(perfBtn:GetFontString():GetFont(), 10)

    local tweakBtn = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    tweakBtn:SetPoint("LEFT", perfBtn, "RIGHT", 6, 0)
    tweakBtn:SetSize(90, 20)
    tweakBtn:SetText("Tweaks Only")
    tweakBtn:GetFontString():SetFont(tweakBtn:GetFontString():GetFont(), 10)

    -- Scrollable patch list
    local sf = CreateFrame("ScrollFrame", "PatchWerk_WizScroll3", page, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -94)
    sf:SetPoint("BOTTOMRIGHT", -30, 8)
    local content = CreateFrame("Frame")
    content:SetSize(440, 1400)
    sf:SetScrollChild(content)
    sf:SetScript("OnSizeChanged", function(s, w) if w and w > 0 then content:SetWidth(w) end end)

    local built = false
    page.Refresh = function()
        if built then
            for _, cb in ipairs(wizardCheckboxes) do
                cb:SetChecked(ns:GetOption(cb.optionKey))
            end
            return
        end
        built = true
        wipe(wizardCheckboxes)

        local y = 0
        local cbIndex = 0
        for _, groupInfo in ipairs(ns.addonGroups) do
            if detectedAddons[groupInfo.id] then
                -- Group header separator
                if y < 0 then
                    local sep = content:CreateTexture(nil, "BACKGROUND")
                    sep:SetHeight(1)
                    sep:SetPoint("TOPLEFT", 4, y)
                    sep:SetPoint("RIGHT", content, "RIGHT", -4, 0)
                    SetSolidColor(sep, 0.35, 0.35, 0.35, 0.4)
                end

                local header = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                header:SetPoint("TOPLEFT", 4, y - 4)
                header:SetText("|cffffff00" .. groupInfo.label .. "|r")
                y = y - 22

                -- Patches for this group
                for _, p in ipairs(ns.patchInfo) do
                    if p.group == groupInfo.id then
                        cbIndex = cbIndex + 1
                        local cbName = "PatchWerk_WizCB" .. cbIndex
                        local cb = CreateFrame("CheckButton", cbName, content, "UICheckButtonTemplate")
                        cb:SetPoint("TOPLEFT", 10, y)
                        cb:SetChecked(ns:GetOption(p.key))
                        cb.optionKey = p.key
                        cb.patchCategory = p.category

                        cb:SetScript("OnClick", function(self)
                            ns:SetOption(self.optionKey, self:GetChecked() and true or false)
                        end)

                        local cbText = _G[cbName .. "Text"]
                        if cbText then
                            local cc = CATEGORY_COLORS[p.category]
                            local catTag = ""
                            if cc then
                                catTag = string.format("|cff%02x%02x%02x[%s]|r ",
                                    cc.r * 255, cc.g * 255, cc.b * 255, p.category)
                            end
                            cbText:SetText(catTag .. p.label)
                            -- Help icon
                            local hb = CreateFrame("Frame", nil, content)
                            hb:SetSize(16, 16)
                            hb:SetPoint("LEFT", cbText, "RIGHT", 2, 0)
                            hb:EnableMouse(true)
                            local qm = hb:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                            qm:SetPoint("CENTER", 0, 0)
                            qm:SetText("|cff66bbff(?)|r")
                            hb:SetScript("OnEnter", function(self)
                                qm:SetText("|cffffffff(?)|r")
                                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                                GameTooltip:SetText(p.label, 1, 1, 1)
                                if p.help then GameTooltip:AddLine(p.help, 1, 0.82, 0, true) end
                                if p.detail then
                                    GameTooltip:AddLine(" ")
                                    GameTooltip:AddLine(p.detail, 0.8, 0.8, 0.8, true)
                                end
                                GameTooltip:Show()
                            end)
                            hb:SetScript("OnLeave", function()
                                qm:SetText("|cff66bbff(?)|r")
                                GameTooltip:Hide()
                            end)
                        end

                        cb:SetScript("OnEnter", function(self)
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:SetText(p.label, 1, 1, 1)
                            if p.help then GameTooltip:AddLine(p.help, 1, 0.82, 0, true) end
                            GameTooltip:Show()
                        end)
                        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

                        table.insert(wizardCheckboxes, cb)
                        y = y - 24
                    end
                end
                y = y - 4
            end
        end
        content:SetHeight(math.max(-y + 8, 100))
    end

    -- Preset handlers
    recBtn:SetScript("OnClick", function()
        for _, cb in ipairs(wizardCheckboxes) do
            ns:SetOption(cb.optionKey, true)
            cb:SetChecked(true)
        end
    end)
    minBtn:SetScript("OnClick", function()
        for _, cb in ipairs(wizardCheckboxes) do
            local on = cb.patchCategory == "Fixes"
            ns:SetOption(cb.optionKey, on)
            cb:SetChecked(on)
        end
    end)
    offBtn:SetScript("OnClick", function()
        for _, cb in ipairs(wizardCheckboxes) do
            ns:SetOption(cb.optionKey, false)
            cb:SetChecked(false)
        end
    end)
    perfBtn:SetScript("OnClick", function()
        for _, cb in ipairs(wizardCheckboxes) do
            local on = cb.patchCategory == "Performance"
            ns:SetOption(cb.optionKey, on)
            cb:SetChecked(on)
        end
    end)
    tweakBtn:SetScript("OnClick", function()
        for _, cb in ipairs(wizardCheckboxes) do
            local on = cb.patchCategory == "Tweaks"
            ns:SetOption(cb.optionKey, on)
            cb:SetChecked(on)
        end
    end)

    return page
end

---------------------------------------------------------------------------
-- Page 4: Done
---------------------------------------------------------------------------
local function BuildDonePage(container)
    local page = CreateFrame("Frame", nil, container)
    page:SetAllPoints()
    page:Hide()

    local check = page:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    check:SetPoint("TOP", 0, -40)
    check:SetText("|cff33e633Patched Up!|r")

    local summaryFs = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    summaryFs:SetPoint("TOP", check, "BOTTOM", 0, -12)
    summaryFs:SetJustifyH("CENTER")

    local body = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    body:SetPoint("TOP", summaryFs, "BOTTOM", 0, -20)
    body:SetPoint("LEFT", container, "LEFT", 40, 0)
    body:SetPoint("RIGHT", container, "RIGHT", -40, 0)
    body:SetJustifyH("CENTER")
    body:SetWordWrap(true)
    body:SetText(
        "Made by |cffffd100Eventyret|r  (|cff8788EEHexusPlexus|r - Thunderstrike EU)\n\n" ..
        "If PatchWerk made your UI smoother, tell your guild!\n" ..
        "Every raider deserves more frames and fewer hateful strikes.\n\n" ..
        "Changes take effect after |cffffd100/reload|r.\n\n" ..
        "|cffffd100/pw|r — Open settings panel\n" ..
        "|cffffd100/pw status|r — Check patch status\n" ..
        "|cffffd100/pw reset|r — Reset to defaults"
    )

    page.Refresh = function()
        local enabled, addons = 0, 0
        for _, cb in ipairs(wizardCheckboxes) do
            if ns:GetOption(cb.optionKey) then enabled = enabled + 1 end
        end
        for _, g in ipairs(ns.addonGroups) do
            if detectedAddons[g.id] then addons = addons + 1 end
        end
        summaryFs:SetText("|cff33e633" .. enabled .. " patches|r enabled for |cff33ccff" .. addons .. " addons|r")
    end

    return page
end

---------------------------------------------------------------------------
-- Navigation: show a specific page
---------------------------------------------------------------------------
local function ShowPage(pageNum)
    currentPage = pageNum
    for i = 1, NUM_PAGES do
        if pages[i] then
            if i == pageNum then pages[i]:Show() else pages[i]:Hide() end
        end
        if pageDots[i] then
            if i == pageNum then
                pageDots[i]:SetVertexColor(0.2, 0.8, 1.0, 1)
            else
                pageDots[i]:SetVertexColor(0.3, 0.3, 0.3, 1)
            end
        end
    end
    -- Refresh dynamic content for the visible page
    if pages[pageNum] and pages[pageNum].Refresh then
        pages[pageNum].Refresh()
    end
    -- Update nav buttons
    if wizardFrame then
        if pageNum > 1 then wizardFrame.backBtn:Show() else wizardFrame.backBtn:Hide() end
        wizardFrame.nextBtn:SetText(pageNum == NUM_PAGES and "Finish" or "Next")
    end
end

---------------------------------------------------------------------------
-- Create the wizard frame (lazy, called once)
---------------------------------------------------------------------------
local function CreateWizardFrame()
    if wizardFrame then return wizardFrame end

    DetectAddons()

    -- Full-screen dimmed overlay (captures clicks behind wizard)
    local overlay = CreateFrame("Frame", "PatchWerk_WizardOverlay", UIParent)
    overlay:SetFrameStrata("DIALOG")
    overlay:SetAllPoints(UIParent)
    overlay:EnableMouse(true)
    local obg = overlay:CreateTexture(nil, "BACKGROUND")
    obg:SetAllPoints()
    SetSolidColor(obg, 0, 0, 0, 0.6)
    overlay:Hide()

    -- Main wizard frame
    local f = CreateFrame("Frame", "PatchWerk_Wizard", overlay)
    f:SetSize(WIZARD_WIDTH, WIZARD_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(overlay:GetFrameLevel() + 10)

    -- Border (1px around frame)
    local border = f:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    SetSolidColor(border, 0.3, 0.3, 0.3, 1)

    -- Dark background
    local bg = f:CreateTexture(nil, "BORDER")
    bg:SetAllPoints()
    SetSolidColor(bg, 0.05, 0.05, 0.05, 0.97)

    -- Skip link (top-right corner)
    local skipBtn = CreateFrame("Button", nil, f)
    skipBtn:SetSize(40, 18)
    skipBtn:SetPoint("TOPRIGHT", -8, -6)
    local skipTxt = skipBtn:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    skipTxt:SetAllPoints()
    skipTxt:SetText("|cff666666Skip|r")
    skipBtn:SetScript("OnEnter", function() skipTxt:SetText("|cffaaaaaaSkip|r") end)
    skipBtn:SetScript("OnLeave", function() skipTxt:SetText("|cff666666Skip|r") end)
    skipBtn:SetScript("OnClick", function() ns:CompleteWizard() end)

    -- Page container (everything above the nav bar)
    local pc = CreateFrame("Frame", nil, f)
    pc:SetPoint("TOPLEFT", 0, 0)
    pc:SetPoint("BOTTOMRIGHT", 0, 44)

    -- Build all pages
    pages[1] = BuildWelcomePage(pc)
    pages[2] = BuildDetectedPage(pc)
    pages[3] = BuildConfigPage(pc)
    pages[4] = BuildDonePage(pc)

    -- Nav bar separator
    local navSep = f:CreateTexture(nil, "ARTWORK")
    navSep:SetHeight(1)
    navSep:SetPoint("BOTTOMLEFT", 0, 44)
    navSep:SetPoint("BOTTOMRIGHT", 0, 44)
    SetSolidColor(navSep, 0.25, 0.25, 0.25, 0.6)

    -- Page indicator dots (centered, bottom of frame above nav buttons)
    local dotW = NUM_PAGES * 16
    local dotAnchor = CreateFrame("Frame", nil, f)
    dotAnchor:SetSize(dotW, 10)
    dotAnchor:SetPoint("BOTTOM", 0, 30)
    for i = 1, NUM_PAGES do
        local dot = dotAnchor:CreateTexture(nil, "ARTWORK")
        dot:SetSize(8, 8)
        dot:SetPoint("LEFT", (i - 1) * 16 + 4, 0)
        SetSolidColor(dot, 0.3, 0.3, 0.3, 1)
        pageDots[i] = dot
    end

    -- Back button (bottom-left)
    local backBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    backBtn:SetPoint("BOTTOMLEFT", 12, 6)
    backBtn:SetSize(80, 24)
    backBtn:SetText("Back")
    backBtn:SetScript("OnClick", function()
        if currentPage > 1 then ShowPage(currentPage - 1) end
    end)
    f.backBtn = backBtn

    -- Next / Finish button (bottom-right)
    local nextBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextBtn:SetPoint("BOTTOMRIGHT", -12, 6)
    nextBtn:SetSize(80, 24)
    nextBtn:SetText("Next")
    nextBtn:SetScript("OnClick", function()
        if currentPage < NUM_PAGES then
            ShowPage(currentPage + 1)
        else
            ns:CompleteWizard()
        end
    end)
    f.nextBtn = nextBtn

    -- ESC to close (via UISpecialFrames)
    tinsert(UISpecialFrames, "PatchWerk_Wizard")
    f:SetScript("OnHide", function()
        overlay:Hide()
        local db = ns:GetDB()
        if db then db.wizardCompleted = true end
    end)

    f.overlay = overlay
    wizardFrame = f
    return f
end

---------------------------------------------------------------------------
-- Public API (called by Options.lua and Core.lua)
---------------------------------------------------------------------------

function ns:ShowWizard()
    local f = CreateWizardFrame()
    f.overlay:Show()
    f:Show()
    ShowPage(1)
end

function ns:CompleteWizard()
    local db = self:GetDB()
    if db then db.wizardCompleted = true end
    if wizardFrame then
        wizardFrame:Hide()      -- triggers OnHide -> overlay:Hide()
    end
end

function ns:ResetWizard()
    local db = self:GetDB()
    if db then db.wizardCompleted = false end
end

---------------------------------------------------------------------------
-- Auto-show wizard on first login
---------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(1, function()
        local db = ns:GetDB()
        if db and db.wizardCompleted == false then
            if not InCombatLockdown() then
                ns:ShowWizard()
            else
                -- Defer until combat ends
                local cf = CreateFrame("Frame")
                cf:RegisterEvent("PLAYER_REGEN_ENABLED")
                cf:SetScript("OnEvent", function(s)
                    s:UnregisterAllEvents()
                    ns:ShowWizard()
                end)
            end
        end
    end)
end)
