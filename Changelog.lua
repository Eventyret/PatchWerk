-- Changelog.lua: In-game changelog popup for PatchWerk
--
-- Two-panel layout: version list + thanks on the left,
-- scrollable patch notes on the right. Clicking a version
-- switches the right panel. No more scroll doom.
--
-- Shows a "What's New" popup once per version on login.
-- Auto-shows after the wizard is completed, not during first-run.
-- Any dismiss (ESC, X, Got it) marks the version as seen.

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
        version = "1.3.3",
        title = "Hop Polish",
        subtitle = "The One Where We Stopped Guessing",
        flavor = "v1.3.2 rebuilt hop detection from scratch but still had a few tricks up its sleeve. This one finishes the job.",
        sections = {
            {
                header = "Bugs that got /kicked:",
                entries = {
                    "AutoLayer no longer silently stays in the hop group after confirming — it whispered thanks and then just... stood there. Now it actually leaves",
                    "Hop detection no longer breaks after a /reload — PatchWerk picks up the first nearby NPC as a baseline instead of staring at nothing forever",
                    "Stale layer data from before a hop no longer tricks PatchWerk into thinking you're still on the old layer",
                },
            },
            {
                header = "Quality of life:",
                entries = {
                    "Hop detection now works passively — nameplates and mouseover are enough, you don't need to manually target anything. Just stand near NPCs and PatchWerk handles the rest",
                    "Toast messages stay on screen longer (8 seconds, up from 5) so you can actually read 'Layer 5 -> 8' before it vanishes",
                    "Toast duration is now configurable (3-15 seconds) via a slider in AutoLayer settings",
                    "Status frame default position moved up to avoid overlapping debuffs",
                    "Hover the status frame for a clear explanation of what On/Off means",
                    "Hint text during hops updated with clearer guidance",
                },
            },
        },
    },
    {
        version = "1.3.2",
        title = "Layer Detection Rebuilt",
        subtitle = "The One Where We Actually Checked",
        flavor = "PatchWerk was trusting UNIT_PHASE to prove your layer changed. Six hops. Same layer. Awkward whispers. Never again.",
        sections = {
            {
                header = "Bugs that got /kicked:",
                entries = {
                    "AutoLayer hop detection completely rebuilt — PatchWerk now compares creature GUIDs before and after a hop to verify you actually changed layers, instead of trusting events that fire for other group members",
                    "PatchWerk stays in the hop group until it has proof your layer changed. No more leaving after 5 seconds on blind faith",
                    "If the host leaves before PatchWerk can confirm, it enters a 'Verifying' state and keeps checking",
                    "'Thanks for the hop!' whispers only go out when the hop actually worked. No more thanking someone for a layer change that didn't happen",
                    "False-positive hop confirmations from other players cycling through the group no longer trigger early group-leave",
                },
            },
            {
                header = "Quality of life:",
                entries = {
                    "Hop timeout extended from 90s to 120s — some layers take a minute to settle",
                    "New 'Verifying...' state with pulsing animation when the group disbands before confirmation",
                    "Failed hops show an orange warning instead of silently resetting",
                },
            },
        },
    },
    {
        version = "1.3.1",
        title = "Hop Detection Hotfix",
        subtitle = "The One Where We Stopped Believing the Host",
        flavor = "Hotfix incoming. No arena season reset required.",
        sections = {
            {
                header = "Bugs that got /kicked:",
                entries = {
                    "AutoLayer no longer falsely confirms a layer hop just because the host targeted an NPC — your client must actually change layers before PatchWerk believes it worked",
                    "Layer change toasts no longer flash during a hop when the number can't be trusted — the toast only appears once the hop is confirmed",
                    "All hop-related messages now stay on screen for 5 seconds instead of vanishing instantly",
                },
            },
        },
    },
    {
        version = "1.3.0",
        title = "New Addon Support",
        subtitle = "The One Where GudaChat Joined the Party",
        flavor = "Welcome to the raid, GudaChat. Your buffs are ready.",
        sections = {
            {
                header = "Shiny new things:",
                entries = {
                    "GudaChat is now supported — three QOL tweaks ported from Prat for lightweight chat users",
                    "Arrow key message history — just hit Up/Down to cycle sent messages, no Alt needed",
                    "/tt whisper target — type /tt to whisper whoever you're targeting",
                    "/clear and /clearall commands — wipe your chat windows without scrolling back to the Stone Age",
                    "AutoLayer keyword cache now also covers the new prefix filter from v1.7.7",
                },
            },
            {
                header = "Bugs that got /kicked:",
                entries = {
                    "AutoLayer no longer messes with your group inside dungeons or raids — layer requests from guild chat are ignored while you're in an instance, and requesting a hop is blocked too",
                    "Prat's 'Player Info Throttle' removed — it was never actually doing anything, like casting Kings on someone who already has it",
                    "GudaChat arrow keys now survive opening and closing chat — Blizzard was resetting the mode every time you pressed Enter",
                    "Settings panel says 'enabled' instead of 'active' for addons you don't have installed",
                },
            },
            {
                header = "Behind the curtain:",
                entries = {
                    "Version compatibility verified for 8 addon updates (Details, BigWigs, BigDebuffs, NovaInstanceTracker, AutoLayer, LoonBestInSlot, Prat, RatingBuster)",
                },
            },
            {
                header = "Thanks to:",
                entries = {
                    "Shivaz for reporting the AutoLayer dungeon bug — apparently asking for a layer in guild chat is faster than a mage portal for getting into dungeons you weren't invited to",
                },
            },
        },
    },
    {
        version = "1.2.1",
        title = "Bug Fixes",
        subtitle = "The One Where Questie Learned to Count",
        flavor = "Two bug reports walk into Shattrath. Both get fixed before the loading screen.",
        sections = {
            {
                header = "Bugs that got /kicked:",
                entries = {
                    "Questie quest tracking no longer falls behind — looting 8 bones now shows 8/10, not 7/10. The quest log update was eating events instead of batching them",
                    "AutoLayer right-clicking the status frame now always sends a hop request, even when your layer is unknown — no more surprise GUI popping up in Shattrath",
                    "AutoLayer clicking to hop multiple times no longer queues up a conga line of requests — once you're mid-hop, extra clicks are ignored",
                    "AutoLayer actually leaves the group when a hop times out after 90 seconds — no more standing in a party forever like a confused warlock pet (again)",
                    "AutoLayer gives NovaWorldBuffs the full 5 seconds to confirm your new layer after hopping — it was starting the countdown too early and bailing before NWB could check",
                    "AutoLayer 'Searching...' only shows when a hop request actually goes out — no more phantom searches when you click too fast",
                    "AutoLayer picks up hop invites even if your last attempt failed — no more getting stuck because someone invited you right after a timeout",
                },
            },
            {
                header = "Thanks to:",
                entries = {
                    "Finn for reporting both issues while testing live on stream — go check him out at twitch.tv/finnwow31!",
                },
            },
        },
    },
    {
        version = "1.2.0",
        title = "Quality & Polish",
        subtitle = "The One Where Everything Got a Little Shinier",
        flavor = "Think of this as a world buff for your addon folder.",
        sections = {
            {
                header = "Shiny new things:",
                entries = {
                    "In-game changelog popup — you're reading it right now, grats",
                    "Baganator bag sorting and item lock fixes — keeps your bags tidy without an extra addon",
                    "Setup wizard got a glow-up — 'Skip setup' is actually readable now, and it tells you about /pw if things go sideways",
                    "BigWigs Flash Alert Recovery — boss flash and screen-pulse alerts restored on TBC Classic, no more silent wipes",
                },
            },
            {
                header = "Squashed like Razorgore's eggs:",
                entries = {
                    "ESC / Exit Game no longer triggers 'blocked from an action' — our bad, we broke the Quit button. Fixed!",
                    "EasyFrames patch removed — it was breaking the pet action bar and the Exit Game button, so we benched it",
                    "AutoLayer actually leaves the group after hopping now — timing issues meant it just stood there like a confused warlock pet",
                    "AutoLayer status frame can't teleport to 0,0 anymore — that trick only works for mages",
                    "BugGrabber was hiding ALL your errors, not just the harmless ones — real bugs are back on the meter",
                    "NovaWorldBuffs no longer crashes 34 times when layer info is missing — more wipes than C'Thun prog",
                    "Details meter respects your speed setting now instead of going full Leeroy on updates",
                    "Auctionator timeout no longer argues with itself about when to give up",
                    "Settings summary counts patches for addons you actually have, not your entire wishlist",
                    "Enable All / Disable All no longer toggles patches for addons you don't have installed",
                },
            },
            {
                header = "Behind the curtain:",
                entries = {
                    "Settings panel is alphabetical now — find your addon without a Questie arrow",
                    "Installed addon groups open by default — no more clicking to see your own stuff",
                    "All On / All Off button tells you which way it's going before you press it",
                    "/pw toggle now actually tells you how to use it instead of staring blankly",
                    "Update notifications come with a summon portal (download link) now",
                    "Tooltips got a haste buff across the board",
                    "Patch failure messages now tell you to type /pw instead of leaving you guessing",
                    "All patch descriptions rewritten in plain English — no more programmer-speak in your tooltips",
                },
            },
            {
                header = "Thanks to:",
                entries = {
                    "Jerrystclair for reporting the ESC bug — even a mage couldn't portal out of that one",
                },
            },
        },
    },
}

---------------------------------------------------------------------------
-- Special Thanks (shown on the left panel, always visible)
---------------------------------------------------------------------------
ns.changelogThanks = {
    { name = "Finn", link = "twitch.tv/finnwow31", note = "Live testing & bug reports" },
    { name = "Jerrystclair", note = "Reported the ESC bug" },
    { name = "Shivaz", note = "Reported the dungeon invite bug" },
}

---------------------------------------------------------------------------
-- Frame layout
---------------------------------------------------------------------------
local FRAME_WIDTH = 680
local FRAME_HEIGHT = 520
local LEFT_WIDTH = 160

local changelogFrame = nil

---------------------------------------------------------------------------
-- Build scrollable section content for one changelog entry
---------------------------------------------------------------------------
local function BuildChangelogContent(parent, entry)
    local y = 0
    local ROW_PAD = 4

    for i, section in ipairs(entry.sections) do
        local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        header:SetPoint("TOPLEFT", 0, y)
        header:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        header:SetJustifyH("LEFT")
        header:SetText("|cffffd100" .. section.header .. "|r")
        y = y - 20

        for _, text in ipairs(section.entries) do
            local bullet = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            bullet:SetPoint("TOPLEFT", 12, y)
            bullet:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
            bullet:SetJustifyH("LEFT")
            bullet:SetWordWrap(true)
            bullet:SetText("|cffdddddd\194\183|r  " .. text)

            local h = bullet:GetStringHeight()
            if not h or h < 10 then h = 18 end
            y = y - h - ROW_PAD
        end

        if i < #entry.sections then
            y = y - 12
        end
    end

    return -y
end

---------------------------------------------------------------------------
-- Create the two-panel changelog frame (lazy, called once)
---------------------------------------------------------------------------
local function CreateChangelogFrame()
    if changelogFrame then return changelogFrame end
    if not ns.changelog or not ns.changelog[1] then return nil end

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
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
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

    -- Close "X" (top-right)
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(24, 18)
    closeBtn:SetPoint("TOPRIGHT", -8, -6)
    local closeTxt = closeBtn:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    closeTxt:SetAllPoints()
    closeTxt:SetText("|cff666666X|r")
    closeBtn:SetScript("OnEnter", function() closeTxt:SetText("|cffaaaaaaX|r") end)
    closeBtn:SetScript("OnLeave", function() closeTxt:SetText("|cff666666X|r") end)
    closeBtn:SetScript("OnClick", function() ns:CloseChangelog() end)

    -- Title: "PatchWerk" (top-left)
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", 16, -12)
    title:SetText("|cff33ccffPatchWerk|r")

    local tagline = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    tagline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    tagline:SetText("|cff666666Patch Notes|r")

    ---------------------------------------------------------------------------
    -- Left panel: vertical separator + version buttons + thanks
    ---------------------------------------------------------------------------
    local leftTop = -52

    -- Vertical separator between panels
    local vSep = f:CreateTexture(nil, "ARTWORK")
    vSep:SetWidth(1)
    vSep:SetPoint("TOPLEFT", LEFT_WIDTH, leftTop)
    vSep:SetPoint("BOTTOMLEFT", LEFT_WIDTH, 44)
    SetSolidColor(vSep, 0.25, 0.25, 0.25, 0.6)

    -- Version buttons
    local versionButtons = {}
    local selectedIndex = 1

    -- Right panel elements (declared here so SelectVersion can access them)
    local rightTitle, rightSubtitle, rightFlavor
    local versionScrollFrames = {}

    local function SelectVersion(index)
        selectedIndex = index
        local entry = ns.changelog[index]

        -- Update button highlights
        for i, btn in ipairs(versionButtons) do
            if i == index then
                btn.bg:SetVertexColor(0.15, 0.4, 0.6, 0.8)
                btn.label:SetTextColor(1, 1, 1)
            else
                btn.bg:SetVertexColor(0.1, 0.1, 0.1, 0)
                btn.label:SetTextColor(0.6, 0.6, 0.6)
            end
        end

        -- Update right panel header
        rightTitle:SetText("v" .. entry.version .. "  —  " .. entry.title)
        rightSubtitle:SetText("|cffbbbbbb\"" .. entry.subtitle .. "\"|r")
        rightFlavor:SetText("|cff888888" .. entry.flavor .. "|r")

        -- Show/hide content scroll frames
        for i, sf in ipairs(versionScrollFrames) do
            if i == index then sf:Show() else sf:Hide() end
        end
    end

    local by = leftTop - 6
    for i, entry in ipairs(ns.changelog) do
        local btn = CreateFrame("Button", nil, f)
        btn:SetPoint("TOPLEFT", 4, by)
        btn:SetSize(LEFT_WIDTH - 10, 22)

        local btnBg = btn:CreateTexture(nil, "BACKGROUND")
        btnBg:SetAllPoints()
        SetSolidColor(btnBg, 0.1, 0.1, 0.1, 0)
        btn.bg = btnBg

        local label = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("LEFT", 8, 0)
        label:SetText("v" .. entry.version)
        label:SetTextColor(0.6, 0.6, 0.6)
        btn.label = label

        -- "NEW" badge on the latest version
        if i == 1 then
            local badge = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            badge:SetPoint("LEFT", label, "RIGHT", 4, 0)
            badge:SetText("|cff33ff33NEW|r")
        end

        btn:SetScript("OnClick", function() SelectVersion(i) end)
        btn:SetScript("OnEnter", function()
            if i ~= selectedIndex then
                btnBg:SetVertexColor(0.15, 0.15, 0.15, 0.5)
            end
        end)
        btn:SetScript("OnLeave", function()
            if i ~= selectedIndex then
                btnBg:SetVertexColor(0.1, 0.1, 0.1, 0)
            end
        end)

        versionButtons[i] = btn
        by = by - 24
    end

    -- Thanks section (bottom of left panel)
    if ns.changelogThanks and #ns.changelogThanks > 0 then
        local thanksSep = f:CreateTexture(nil, "ARTWORK")
        thanksSep:SetHeight(1)
        thanksSep:SetPoint("BOTTOMLEFT", 8, 100)
        thanksSep:SetPoint("RIGHT", vSep, "LEFT", -8, 0)
        SetSolidColor(thanksSep, 0.25, 0.25, 0.25, 0.4)

        local thanksHeader = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        thanksHeader:SetPoint("TOPLEFT", thanksSep, "BOTTOMLEFT", 0, -6)
        thanksHeader:SetText("|cffffd100Special Thanks|r")

        local ty = -22
        for _, person in ipairs(ns.changelogThanks) do
            local line = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            line:SetPoint("TOPLEFT", thanksSep, "BOTTOMLEFT", 0, ty)
            line:SetPoint("RIGHT", vSep, "LEFT", -8, 0)
            line:SetJustifyH("LEFT")
            line:SetWordWrap(true)

            local text = "|cff33ccff" .. person.name .. "|r"
            if person.note then
                text = text .. "\n|cff888888" .. person.note .. "|r"
            end
            line:SetText(text)

            local h = line:GetStringHeight()
            if not h or h < 12 then h = 24 end
            ty = ty - h - 4
        end
    end

    ---------------------------------------------------------------------------
    -- Right panel: header + scrollable content per version
    ---------------------------------------------------------------------------
    local rightLeft = LEFT_WIDTH + 14
    local rightRight = -16

    rightTitle = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    rightTitle:SetPoint("TOPLEFT", rightLeft, leftTop - 2)
    rightTitle:SetPoint("RIGHT", f, "RIGHT", rightRight, 0)
    rightTitle:SetJustifyH("LEFT")

    rightSubtitle = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    rightSubtitle:SetPoint("TOPLEFT", rightTitle, "BOTTOMLEFT", 0, -4)
    rightSubtitle:SetPoint("RIGHT", f, "RIGHT", rightRight, 0)
    rightSubtitle:SetJustifyH("LEFT")
    rightSubtitle:SetWordWrap(true)

    rightFlavor = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    rightFlavor:SetPoint("TOPLEFT", rightSubtitle, "BOTTOMLEFT", 0, -6)
    rightFlavor:SetPoint("RIGHT", f, "RIGHT", rightRight, 0)
    rightFlavor:SetJustifyH("LEFT")
    rightFlavor:SetWordWrap(true)

    -- Separator below flavor
    local headerSep = f:CreateTexture(nil, "ARTWORK")
    headerSep:SetHeight(1)
    headerSep:SetPoint("TOPLEFT", rightFlavor, "BOTTOMLEFT", -4, -8)
    headerSep:SetPoint("RIGHT", f, "RIGHT", rightRight, 0)
    SetSolidColor(headerSep, 0.25, 0.25, 0.25, 0.6)

    -- Pre-build a scroll frame + content for each version
    for i, entry in ipairs(ns.changelog) do
        local sf = CreateFrame("ScrollFrame", "PatchWerk_ChangelogScroll" .. i, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", headerSep, "BOTTOMLEFT", 4, -8)
        sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 50)
        sf:Hide()

        local content = CreateFrame("Frame", nil, sf)
        local contentWidth = FRAME_WIDTH - LEFT_WIDTH - 70
        content:SetWidth(contentWidth)
        content:SetHeight(800)
        sf:SetScrollChild(content)
        sf:SetScript("OnSizeChanged", function(s, w)
            if w and w > 0 then content:SetWidth(w) end
        end)

        local h = BuildChangelogContent(content, entry)
        content:SetHeight(math.max(h + 20, 100))

        versionScrollFrames[i] = sf
    end

    ---------------------------------------------------------------------------
    -- Bottom bar
    ---------------------------------------------------------------------------
    local navSep = f:CreateTexture(nil, "ARTWORK")
    navSep:SetHeight(1)
    navSep:SetPoint("BOTTOMLEFT", 0, 44)
    navSep:SetPoint("BOTTOMRIGHT", 0, 44)
    SetSolidColor(navSep, 0.25, 0.25, 0.25, 0.6)

    -- "Got it" button
    local gotItBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    gotItBtn:SetPoint("BOTTOMRIGHT", -12, 6)
    gotItBtn:SetSize(80, 24)
    gotItBtn:SetText("Got it")
    gotItBtn:SetScript("OnClick", function() ns:CloseChangelog() end)

    -- Prev / Next buttons
    local prevBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    prevBtn:SetPoint("BOTTOMLEFT", LEFT_WIDTH + 8, 6)
    prevBtn:SetSize(24, 24)
    prevBtn:SetText("<")
    prevBtn:SetScript("OnClick", function()
        if selectedIndex < #ns.changelog then
            SelectVersion(selectedIndex + 1)
        end
    end)

    local nextBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
    nextBtn:SetSize(24, 24)
    nextBtn:SetText(">")
    nextBtn:SetScript("OnClick", function()
        if selectedIndex > 1 then
            SelectVersion(selectedIndex - 1)
        end
    end)

    local navLabel = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    navLabel:SetPoint("LEFT", nextBtn, "RIGHT", 8, 0)
    f.navLabel = navLabel

    -- Wrap SelectVersion to update nav buttons
    local origSelect = SelectVersion
    SelectVersion = function(index)
        origSelect(index)
        prevBtn:SetEnabled(index < #ns.changelog)
        nextBtn:SetEnabled(index > 1)
        navLabel:SetText("|cff888888" .. index .. " / " .. #ns.changelog .. "|r")
    end

    -- ESC dismissal (avoid tinsert into UISpecialFrames — causes taint)
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
        local db = ns:GetDB()
        if db then db.lastSeenChangelogVersion = ns.VERSION end
    end)

    -- Select the latest version by default
    SelectVersion(1)

    f.overlay = overlay
    f.SelectVersion = SelectVersion
    changelogFrame = f
    return f
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function ns:ShowChangelog()
    local f = CreateChangelogFrame()
    if not f then return end
    f.SelectVersion(1)
    f.overlay:Show()
    f:Show()
end

function ns:CloseChangelog()
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
