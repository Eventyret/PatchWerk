-- Changelog.lua: In-game changelog popup for PatchWerk
--
-- Shows a "What's New" popup once per version on login.
-- Auto-shows after the wizard is completed, not during first-run.
-- ESC hides without marking as seen; "Got it" / "X" marks as seen.

local _, ns = ...

local ipairs = ipairs
local CreateFrame = CreateFrame
local UIParent = UIParent

local SetSolidColor = ns.SetSolidColor

---------------------------------------------------------------------------
-- Changelog Data
---------------------------------------------------------------------------
-- Most recent entry first. The /release-notes skill prepends new entries here.
-- Each entry mirrors the CHANGELOG.md sections with punny player-friendly text.

ns.changelog = {
    {
        version = "1.3.0",
        title = "Quality & Polish",
        subtitle = "The One Where Everything Got a Little Shinier",
        flavor = "Think of this as a world buff for your addon folder.",
        sections = {
            {
                header = "Squashed like Razorgore's eggs:",
                entries = {
                    "Misleading 'Reload' label no longer haunts patches for addons you don't have installed",
                    "BigWigs proximity text throttle now tracks SetText and SetFormattedText independently",
                    "BugSack search debounce switched from OnUpdate frame to C_Timer — less work per frame",
                    "Details refresh cap no longer silently overrides your faster_updates setting",
                    "AutoLayer status frame won't teleport to 0,0 if your saved position gets corrupted",
                },
            },
            {
                header = "Behind the curtain:",
                entries = {
                    "Removed dead PATCH_ESTIMATES metatable — tooltips are snappier now",
                    "/pw toggle without arguments now shows usage instead of pretending it doesn't exist",
                    "Version update notification now includes a download link",
                    "Saved-variable cleanup uses a proper lookup table instead of a hand-edited chain",
                },
            },
        },
    },
}

---------------------------------------------------------------------------
-- Frame state
---------------------------------------------------------------------------
local CHANGELOG_WIDTH = 520
local CHANGELOG_HEIGHT = 440

local changelogFrame = nil
local closingChangelog = false

---------------------------------------------------------------------------
-- Build the scrollable content for a changelog entry
---------------------------------------------------------------------------
local function BuildChangelogContent(parent, entry)
    local y = 0

    for i, section in ipairs(entry.sections) do
        -- Section header (gold)
        local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        header:SetPoint("TOPLEFT", 0, y)
        header:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        header:SetJustifyH("LEFT")
        header:SetText("|cffffd100" .. section.header .. "|r")
        y = y - 18

        -- Bullet entries (white)
        for _, text in ipairs(section.entries) do
            local bullet = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            bullet:SetPoint("TOPLEFT", 12, y)
            bullet:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
            bullet:SetJustifyH("LEFT")
            bullet:SetWordWrap(true)
            bullet:SetText("|cffdddddd\194\183|r  " .. text)
            -- Calculate height for wrapped text
            local lineHeight = bullet:GetStringHeight() or 14
            y = y - lineHeight - 4
        end

        -- Spacing between sections
        if i < #entry.sections then
            y = y - 10
        end
    end

    return -y
end

---------------------------------------------------------------------------
-- Create the changelog frame (lazy, called once)
---------------------------------------------------------------------------
local function CreateChangelogFrame()
    if changelogFrame then return changelogFrame end

    local entry = ns.changelog[1]
    if not entry then return nil end

    -- Full-screen dimmed overlay
    local overlay = CreateFrame("Frame", "PatchWerk_ChangelogOverlay", UIParent)
    overlay:SetFrameStrata("DIALOG")
    overlay:SetAllPoints(UIParent)
    overlay:EnableMouse(true)
    local obg = overlay:CreateTexture(nil, "BACKGROUND")
    obg:SetAllPoints()
    SetSolidColor(obg, 0, 0, 0, 0.6)
    overlay:Hide()

    -- Main frame
    local f = CreateFrame("Frame", "PatchWerk_Changelog", overlay)
    f:SetSize(CHANGELOG_WIDTH, CHANGELOG_HEIGHT)
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

    -- Close "X" link (top-right)
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(24, 18)
    closeBtn:SetPoint("TOPRIGHT", -8, -6)
    local closeTxt = closeBtn:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    closeTxt:SetAllPoints()
    closeTxt:SetText("|cff666666X|r")
    closeBtn:SetScript("OnEnter", function() closeTxt:SetText("|cffaaaaaaX|r") end)
    closeBtn:SetScript("OnLeave", function() closeTxt:SetText("|cff666666X|r") end)
    closeBtn:SetScript("OnClick", function() ns:CloseChangelog() end)

    -- Title: "PatchWerk"
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 30, -16)
    title:SetText("|cff33ccffPatchWerk|r")

    -- "What's New in vX.Y.Z"
    local versionLine = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    versionLine:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    versionLine:SetText("What's New in v" .. entry.version)

    -- Subtitle (punny)
    local subtitle = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", versionLine, "BOTTOMLEFT", 0, -4)
    subtitle:SetPoint("RIGHT", f, "RIGHT", -30, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetWordWrap(true)
    subtitle:SetText("|cffbbbbbb\"" .. entry.subtitle .. "\"|r")

    -- Flavor text (grey)
    local flavor = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    flavor:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
    flavor:SetPoint("RIGHT", f, "RIGHT", -30, 0)
    flavor:SetJustifyH("LEFT")
    flavor:SetWordWrap(true)
    flavor:SetText("|cff888888" .. entry.flavor .. "|r")

    -- Separator below flavor
    local headerSep = f:CreateTexture(nil, "ARTWORK")
    headerSep:SetHeight(1)
    headerSep:SetPoint("TOPLEFT", flavor, "BOTTOMLEFT", -14, -10)
    headerSep:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    SetSolidColor(headerSep, 0.25, 0.25, 0.25, 0.6)

    -- Scroll frame for section content
    local sf = CreateFrame("ScrollFrame", "PatchWerk_ChangelogScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", headerSep, "BOTTOMLEFT", 4, -8)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -44, 50)

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(sf:GetWidth() > 0 and sf:GetWidth() or 420)
    content:SetHeight(800)
    sf:SetScrollChild(content)
    sf:SetScript("OnSizeChanged", function(s, w)
        if w and w > 0 then content:SetWidth(w) end
    end)

    local contentHeight = BuildChangelogContent(content, entry)
    content:SetHeight(math.max(contentHeight + 8, 100))

    -- Nav separator (above button bar)
    local navSep = f:CreateTexture(nil, "ARTWORK")
    navSep:SetHeight(1)
    navSep:SetPoint("BOTTOMLEFT", 0, 44)
    navSep:SetPoint("BOTTOMRIGHT", 0, 44)
    SetSolidColor(navSep, 0.25, 0.25, 0.25, 0.6)

    -- "Got it" button (bottom-right)
    local gotItBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    gotItBtn:SetPoint("BOTTOMRIGHT", -12, 6)
    gotItBtn:SetSize(80, 24)
    gotItBtn:SetText("Got it")
    gotItBtn:SetScript("OnClick", function() ns:CloseChangelog() end)

    -- ESC to close (hides without marking as seen)
    tinsert(UISpecialFrames, "PatchWerk_Changelog")
    f:SetScript("OnHide", function()
        overlay:Hide()
        if closingChangelog then
            closingChangelog = false
            local db = ns:GetDB()
            if db then db.lastSeenChangelogVersion = ns.VERSION end
        end
    end)

    f.overlay = overlay
    changelogFrame = f
    return f
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function ns:ShowChangelog()
    local f = CreateChangelogFrame()
    if not f then return end
    f.overlay:Show()
    f:Show()
end

function ns:CloseChangelog()
    closingChangelog = true
    if changelogFrame then
        changelogFrame:Hide()
    end
end

---------------------------------------------------------------------------
-- Auto-show changelog on login (2s delay, after Wizard's 1s)
---------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(2, function()
        local db = ns:GetDB()
        if not db then return end

        -- Don't show if wizard hasn't been completed yet
        if not db.wizardCompleted then return end

        -- Don't show in dev builds
        if ns.VERSION == "dev" then return end

        -- Don't show if already seen this version
        if db.lastSeenChangelogVersion == ns.VERSION then return end

        -- Don't show if no changelog data
        if not ns.changelog or not ns.changelog[1] then return end

        if not InCombatLockdown() then
            ns:ShowChangelog()
        else
            -- Defer until combat ends
            local cf = CreateFrame("Frame")
            cf:RegisterEvent("PLAYER_REGEN_ENABLED")
            cf:SetScript("OnEvent", function(s)
                s:UnregisterAllEvents()
                ns:ShowChangelog()
            end)
        end
    end)
end)
