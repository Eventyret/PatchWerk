-- Wizard.lua: First-time setup wizard for PatchWerk
--
-- Shows a 2-page onboarding flow on first install:
--   1. Welcome + Detected Addons — what PatchWerk does and which addons it found
--   2. Done — summary and quick reference

local _, ns = ...

local ipairs = ipairs
local wipe = wipe
local CreateFrame = CreateFrame
local UIParent = UIParent

local SetSolidColor = ns.SetSolidColor

local WIZARD_WIDTH = 520
local WIZARD_HEIGHT = 420
local NUM_PAGES = 2

local wizardFrame = nil
local currentPage = 1
local pages = {}
local pageDots = {}
local detectedAddons = {}
local completingWizard = false

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
-- Page 1: Welcome + Your Addons (merged)
---------------------------------------------------------------------------
local function BuildWelcomePage(container)
    local page = CreateFrame("Frame", nil, container)
    page:SetAllPoints()
    page:Hide()

    local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cff33ccffPatchWerk|r")

    local sub = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
    sub:SetText("|cffaaaaaaPerformance patches for your addons|r")

    local body = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    body:SetPoint("TOP", sub, "BOTTOM", 0, -10)
    body:SetPoint("LEFT", container, "LEFT", 30, 0)
    body:SetPoint("RIGHT", container, "RIGHT", -30, 0)
    body:SetJustifyH("CENTER")
    body:SetWordWrap(true)
    body:SetText(
        "PatchWerk speeds up your addons and fixes common bugs " ..
        "automatically. All patches are enabled by default.\n\n" ..
        "Type |cffffd100/pw|r anytime to adjust. If an addon ever " ..
        "acts weird, open |cffffd100/pw|r and turn its patches off."
    )

    local summaryFs = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    summaryFs:SetPoint("TOP", body, "BOTTOM", 0, -14)
    summaryFs:SetJustifyH("CENTER")

    -- Scrollable addon list
    local sf = CreateFrame("ScrollFrame", "PatchWerk_WizScroll1", page, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 30, -190)
    sf:SetPoint("BOTTOMRIGHT", -44, 12)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(420, 800)
    sf:SetScrollChild(content)
    sf:SetScript("OnSizeChanged", function(s, w) if w and w > 0 then content:SetWidth(w) end end)

    local built = false
    page.Refresh = function()
        DetectAddons()

        -- Count installed addons (always update, even on re-show)
        local installed = 0
        for _, groupInfo in ipairs(ns.addonGroups) do
            if detectedAddons[groupInfo.id] then
                installed = installed + 1
            end
        end
        if installed == 0 then
            summaryFs:SetText("No supported addons detected yet.")
        else
            summaryFs:SetText("Found patches for |cff33e633" .. installed .. "|r of your addons:")
        end

        if built then return end
        built = true

        local y = 0
        for _, groupInfo in ipairs(ns.addonGroups) do
            if detectedAddons[groupInfo.id] then
                local row = CreateFrame("Frame", nil, content)
                row:SetPoint("TOPLEFT", 0, y)
                row:SetPoint("RIGHT", 0, 0)
                row:SetHeight(22)

                local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                label:SetPoint("LEFT", 8, 0)
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

                y = y - 22
            end
        end
        content:SetHeight(math.max(-y + 8, 100))
    end

    return page
end

---------------------------------------------------------------------------
-- Page 2: Done
---------------------------------------------------------------------------
local function BuildDonePage(container)
    local page = CreateFrame("Frame", nil, container)
    page:SetAllPoints()
    page:Hide()

    local check = page:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    check:SetPoint("TOP", 0, -50)
    check:SetText("|cff33e633Patched Up!|r")

    local summaryFs = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    summaryFs:SetPoint("TOP", check, "BOTTOM", 0, -14)
    summaryFs:SetJustifyH("CENTER")

    local body = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    body:SetPoint("TOP", summaryFs, "BOTTOM", 0, -24)
    body:SetPoint("LEFT", container, "LEFT", 40, 0)
    body:SetPoint("RIGHT", container, "RIGHT", -40, 0)
    body:SetJustifyH("CENTER")
    body:SetWordWrap(true)
    body:SetText(
        "|cffffd100/pw|r  Open settings\n" ..
        "|cffffd100/pw status|r  Show what's active\n\n" ..
        "All patches are enabled and working.\n" ..
        "You can toggle individual patches anytime in settings.\n\n" ..
        "|cff888888Made by|r |cffffd100Eventyret|r  |cff888888(|r|cff8788EEHexusPlexus|r |cff888888- Thunderstrike EU)|r"
    )

    page.Refresh = function()
        local enabled, addons = 0, 0
        for _, p in ipairs(ns.patchInfo) do
            if ns:GetOption(p.key) then enabled = enabled + 1 end
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
    if wizardFrame then
        if pageNum > 1 then wizardFrame.backBtn:Show() else wizardFrame.backBtn:Hide() end
        wizardFrame.nextBtn:SetText(pageNum == NUM_PAGES and "Finish" or "Next")
        wizardFrame.nextBtn:SetWidth(80)
    end
    if pages[pageNum] and pages[pageNum].Refresh then
        pages[pageNum].Refresh()
    end
end

---------------------------------------------------------------------------
-- Create the wizard frame (lazy, called once)
---------------------------------------------------------------------------
local function CreateWizardFrame()
    if wizardFrame then return wizardFrame end

    DetectAddons()

    -- Full-screen dimmed overlay
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
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(overlay:GetFrameLevel() + 10)

    -- Border
    local border = f:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    SetSolidColor(border, 0.3, 0.3, 0.3, 1)

    -- Dark background
    local bg = f:CreateTexture(nil, "BORDER")
    bg:SetAllPoints()
    SetSolidColor(bg, 0.05, 0.05, 0.05, 0.97)

    -- Skip link
    local skipBtn = CreateFrame("Button", nil, f)
    skipBtn:SetSize(64, 18)
    skipBtn:SetPoint("TOPRIGHT", -8, -6)
    local skipTxt = skipBtn:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    skipTxt:SetAllPoints()
    skipTxt:SetText("|cff999999Skip setup|r")
    skipBtn:SetScript("OnEnter", function() skipTxt:SetText("|cffccccccSkip setup|r") end)
    skipBtn:SetScript("OnLeave", function() skipTxt:SetText("|cff999999Skip setup|r") end)
    skipBtn:SetScript("OnClick", function() ns:CompleteWizard() end)

    -- Page container
    local pc = CreateFrame("Frame", nil, f)
    pc:SetPoint("TOPLEFT", 0, 0)
    pc:SetPoint("BOTTOMRIGHT", 0, 44)

    -- Build pages
    pages[1] = BuildWelcomePage(pc)
    pages[2] = BuildDonePage(pc)

    -- Nav bar separator
    local navSep = f:CreateTexture(nil, "ARTWORK")
    navSep:SetHeight(1)
    navSep:SetPoint("BOTTOMLEFT", 0, 44)
    navSep:SetPoint("BOTTOMRIGHT", 0, 44)
    SetSolidColor(navSep, 0.25, 0.25, 0.25, 0.6)

    -- Page indicator dots
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

    -- Back button
    local backBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    backBtn:SetPoint("BOTTOMLEFT", 12, 6)
    backBtn:SetSize(80, 24)
    backBtn:SetText("Back")
    backBtn:SetScript("OnClick", function()
        if currentPage > 1 then ShowPage(currentPage - 1) end
    end)
    f.backBtn = backBtn

    -- Next / Finish button
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

    -- ESC to close (only marks complete if Finish/Skip was clicked)
    -- Avoid tinsert(UISpecialFrames) — writing to that table taints the
    -- ESC key processing path, causing ADDON_ACTION_BLOCKED on Quit/Logout.
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    f:SetScript("OnHide", function()
        overlay:Hide()
        if completingWizard then
            completingWizard = false
            local db = ns:GetDB()
            if db then db.wizardCompleted = true end
        end
    end)

    f.overlay = overlay
    wizardFrame = f
    return f
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function ns:ShowWizard()
    local f = CreateWizardFrame()
    f.overlay:Show()
    f:Show()
    ShowPage(1)
end

function ns:CompleteWizard()
    completingWizard = true
    if wizardFrame then
        wizardFrame:Hide()
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
