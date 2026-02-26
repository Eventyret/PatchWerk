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
local tinsert = tinsert
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
        version = "1.5.3",
        title = "Smarter Hop Detection",
        subtitle = "The One Where AutoLayer Learned to Listen",
        flavor = "Consider this the Emergency Maintenance your AddOns folder never got.",
        sections = {
            {
                header = "What got buffed:",
                entries = {
                    "AutoLayer now reads the host's whisper to know exactly which layer you're heading to \226\128\148 the status frame shows \"Hopping to Layer 3...\" instead of just \"Hopping...\"",
                    "If you get invited to a layer you're already on, it instantly leaves and retries instead of waiting 10+ seconds",
                    "Countdown timers in the status frame show how long you've been waiting \226\128\148 no more guessing",
                    "Layer confirmation shows exact numbers: \"Layer 2 -> 3\" or \"Hopped to Layer 3!\"",
                    "Scans nearby enemies to detect your new layer faster \226\128\148 no need to manually target NPCs",
                    "After 5 seconds, reminds you to stay near NPCs for faster detection",
                },
            },
            {
                header = "Squashed like Razorgore's eggs:",
                entries = {
                    "Pawn: Upgrade arrows and stat values on item tooltips no longer vanish after 15\226\128\14830 minutes \226\128\148 the duplicate tooltip guard was too aggressive and blocked Pawn from refreshing its text. (Thanks TarybleTexan!)",
                    "Pawn: Changing your stat scales or weights now immediately updates upgrade results on tooltips \226\128\148 no more stale values until /reload",
                    "AutoLayer: Hops that actually succeeded could be reported as failed \226\128\148 or hang forever \226\128\148 because layer detection was still reading stale data from before the hop. Now clears old info when you join the group so targeting any NPC detects your new layer.",
                    "Cross-continent detection is more reliable \226\128\148 the old check sometimes falsely flagged hops as cross-continent",
                    "Removed the old \"Verifying...\" state that could leave you in limbo \226\128\148 hops now confirm or fail cleanly",
                    "Status frame spells out \"Layer 3\" instead of cryptic \"L3\"",
                },
            },
        },
    },
    {
        version = "1.5.2",
        title = "Bag Fix + Invite Decline",
        subtitle = "The One Where the Bags Opened Again",
        flavor = "No realm restart required. We fixed it while you were farming Primal Mana.",
        sections = {
            {
                header = "Squashed like Razorgore's eggs:",
                entries = {
                    "ElvUI: Pressing B to open your bags stopped working when the bag speedup patch was enabled \226\128\148 the speedup was broken from the start and could crash the bag frame on first open. Replaced with crash protection so one bad slot can never block your bags. (Thanks Yitra_Beloff!)",
                    "AutoLayer: Cross-continent and recently-hopped hosts are now declined at the door instead of accepted and then immediately kicked \226\128\148 no more \"Dungeon Difficulty\" spam from stale re-invites",
                },
            },
        },
    },
    {
        version = "1.5.1",
        title = "Hop Host Hotfix",
        subtitle = "The One Where the Bouncer Remembered Faces",
        flavor = "Hotfix incoming. No arena season reset required.",
        sections = {
            {
                header = "Bugs that got /kicked:",
                entries = {
                    "Fixed false \"hop confirmed\" when the layer never actually changed \226\128\148 the verification now checks your actual layer number before celebrating",
                    "After a real successful hop, the same host can no longer re-invite you and trigger a duplicate hop cycle \226\128\148 recent hosts are remembered for 60 seconds",
                },
            },
        },
    },
    {
        version = "1.5.0",
        title = "ElvUI + Spellbook Fix",
        subtitle = "The One Where ElvUI Walked In and the Spellbook Chilled Out",
        flavor = "Two big things in one release: ElvUI support with 24 patches and the spellbook security warning fixed for good.",
        sections = {
            {
                header = "ElvUI \226\128\148 TBC Classic compatibility:",
                entries = {
                    "ElvUI's addon manager skin no longer errors out when it tries to use Retail-only game functions",
                    "ElvUI's bag skin can now find the container functions it needs on TBC Classic",
                    "Loot history window no longer throws errors \226\128\148 TBC Classic doesn't have a loot history system",
                    "Gem socket window skin no longer errors when opening the socketing UI",
                    "Communities and Guild Finder skin checks whether those windows exist before trying to style them",
                },
            },
            {
                header = "ElvUI \226\128\148 Your dungeon pulls just got smoother:",
                entries = {
                    "Nameplate health updates are batched instead of processing every single damage tick individually",
                    "Mouse highlight checking only runs when your mouse target actually changes",
                    "Quest objective icons remember which enemies are quest targets instead of rescanning constantly",
                    "Target indicator tracks your target once instead of re-checking every nameplate on every health update",
                },
            },
            {
                header = "ElvUI \226\128\148 Your raid frames thank you:",
                entries = {
                    "Idle unit frames skip expensive processing when the player shown hasn't changed",
                    "Mouseover, target, and focus glow effects consolidated from 120 separate watchers into one pass",
                    "Raid frame text is no longer rewritten when the displayed value hasn't actually changed",
                    "Health bar color settings read once per update instead of 5+ repeated lookups",
                },
            },
            {
                header = "ElvUI \226\128\148 Action bars, bags, and QOL:",
                entries = {
                    "Bar visibility recalculated 10 times per second instead of 20+ during casting",
                    "Keybind text formatting skips buttons with no keybind assigned",
                    "Bag sorting pre-reads all item details once \226\128\148 up to 70% faster",
                    "Rapid-fire bag events combined into a single refresh",
                    "Chat URL detection does a quick check first \226\128\148 messages without links skip all pattern scans",
                    "Tooltip inspect data expires after 30s instead of 2 minutes",
                },
            },
            {
                header = "Spellbook security warning \226\128\148 fixed for good:",
                entries = {
                    "Fixed the \"AddOn tried to call a protected function\" error when clicking spells in the spellbook",
                    "OmniCC cooldown cache now works inside OmniCC's own code instead of replacing a game function \226\128\148 this was the culprit",
                    "TipTac inspect cache now reduces inspect spam through TipTac's own library instead of replacing a game function",
                    "Bartender4 action bar fix uses a targeted approach that doesn't touch game functions",
                    "Added /pw taintcheck diagnostic \226\128\148 if you ever see the warning again, this shows exactly what's causing it",
                },
            },
            {
                header = "Quality of life:",
                entries = {
                    "Login chat no longer gets flooded with \"Total time played\" messages \226\128\148 PatchWerk blocks them for 10 seconds after login, then /played works normally",
                    "AutoLayer hop confirmation no longer shows the same message twice \226\128\148 one clean gold toast instead of a double blue flash",
                },
            },
            {
                header = "Housekeeping:",
                entries = {
                    "Removed BigWigs Flash Recovery \226\128\148 the companion addon now handles this on its own",
                    "Removed NovaWorldBuffs Addon Check Fix \226\128\148 same reason, companion addon covers it",
                    "Fixed BigWigs Proximity Text Throttle \226\128\148 turns out it was never actually doing anything. Rewritten so it works now",
                    "Fixed Leatrix Maps and Leatrix Plus patches \226\128\148 both were silently never running due to a startup check that always failed",
                    "Updated version compatibility for Details, BigWigs, Leatrix Maps, and Leatrix Plus",
                },
            },
        },
    },
    {
        version = "1.4.2",
        title = "Spellbook Fix",
        subtitle = "The One Where the Spellbook Fought Back",
        flavor = "Hotfix incoming. No arena season reset required.",
        sections = {
            {
                header = "Bugs that got /kicked:",
                entries = {
                    "Fixed a Blizzard security warning that blocked spell casting from the spellbook \226\128\148 clicking a spell would fail with \"AddOn tried to call a protected function\"",
                    "Hardened all compatibility layer entries against similar issues \226\128\148 the companion addon now writes all of its entries using a technique that avoids interfering with Blizzard's security checks entirely",
                },
            },
        },
    },
    {
        version = "1.4.1",
        title = "Cross-Continent Hops",
        subtitle = "The One Where Layers Learned Geography",
        flavor = "Another patch cycle. No realm restarts, no 6-hour downtime. You're welcome.",
        sections = {
            {
                header = "What got buffed:",
                entries = {
                    "AutoLayer now detects when a hop host is on a different continent and leaves within seconds \226\128\148 Azeroth and Outland have separate layer pools, so a host in Orgrimmar can't change your layer in Nagrand",
                    "Cross-continent mismatches auto-retry up to 3 times to find someone on your continent",
                    "Hosts that were already skipped are remembered for 5 minutes \226\128\148 repeat invites are rejected instantly",
                    "Shift+Left-click the status frame to cancel an active hop at any time",
                    "Thank-you whisper got a personality upgrade: \"Hopped! Smoother than a Paladin bubble-hearth. Cheers!\"",
                },
            },
            {
                header = "Bugs that got /kicked:",
                entries = {
                    "AutoLayer no longer gets stuck in the group after a successful hop \226\128\148 the root cause of \"hop complete but still in party\" reports has been fixed",
                    "Hop confirmation no longer falsely reports \"failed\" in NPC-sparse areas \226\128\148 PatchWerk now waits longer before giving up",
                    "Stale invites from other hosts no longer pull you into a new group after a confirmed hop",
                    "Hop verification no longer times out on fresh login",
                },
            },
        },
    },
    {
        version = "1.4.0",
        title = "Loot & Cooldowns",
        subtitle = "3 Addons Patched, 0 Loot Frames Seen",
        flavor = "No realm restart required. We fixed it while you were farming Primal Mana.",
        sections = {
            {
                header = "Newly attuned:",
                entries = {
                    "HazeLoot: fast auto-loot \226\128\148 when auto-loot is on, items are grabbed instantly without the loot frame flashing. Shift-click still shows the interactive frame. Master loot always shows the frame so you can distribute properly",
                    "HazeCooldowns: cooldown text no longer shows countdown timers on the global cooldown. The GCD detection was completely broken on TBC Classic \226\128\148 every ability briefly flashed '1.5' after you pressed it. Now only real cooldowns get timers",
                    "Plumber: loot window, spell flyouts, and settings panel no longer crash on TBC Classic. The companion addon now fills in the missing game functions Plumber expects",
                },
            },
            {
                header = "Behind the curtain:",
                entries = {
                    "Companion addon learned four new tricks: toy collection lookups, mount journal queries, spell data readiness, and item data readiness",
                },
            },
        },
    },
    {
        version = "1.3.3",
        title = "Hop Polish",
        subtitle = "The One Where We Stopped Guessing",
        flavor = "v1.3.2 rebuilt hop detection from scratch — and accidentally broke a few things along the way. This patch fixes those and makes the whole experience smoother.",
        sections = {
            {
                header = "Bugs that got /kicked:",
                entries = {
                    "AutoLayer now actually leaves the group after confirming a hop — v1.3.2 introduced a bug where PatchWerk whispered thanks and then just... stood there in the group forever",
                    "Hop detection no longer breaks after a /reload — another v1.3.2 regression where PatchWerk lost track of your layer and couldn't confirm anything",
                    "Layer info from before a hop no longer lingers and confuses the next detection",
                    "Clicking quests in the quest log no longer flickers — both the Questie and QuestXP performance patches were delaying updates while you were browsing the log. Now updates fire instantly when the quest log is open",
                },
            },
            {
                header = "Quality of life:",
                entries = {
                    "You no longer need to manually target an NPC to confirm hops — just stand near any creatures in a city and PatchWerk picks it up automatically",
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
-- Frame layout
---------------------------------------------------------------------------
local FRAME_WIDTH = 680
local FRAME_HEIGHT = 520
local SIDEBAR_WIDTH = 130

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
--
-- Layout: content on the LEFT (wide), version picker on the RIGHT (slim).
-- "Thanks to:" sections live inside each version's patch notes data.
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

    local border = f:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    SetSolidColor(border, 0.3, 0.3, 0.3, 1)

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

    ---------------------------------------------------------------------------
    -- Left panel: title + header + scrollable content (wide)
    ---------------------------------------------------------------------------
    local contentTop = -12
    local contentLeft = 16
    local sidebarLeft = FRAME_WIDTH - SIDEBAR_WIDTH

    -- Title
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", contentLeft, contentTop)
    title:SetText("|cff33ccffPatchWerk|r")

    local tagline = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    tagline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    tagline:SetText("|cff666666Patch Notes|r")

    local headerTop = -52

    -- Version title + subtitle + flavor (updated when selecting a version)
    local contentTitle = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    contentTitle:SetPoint("TOPLEFT", contentLeft, headerTop - 2)
    contentTitle:SetPoint("RIGHT", f, "RIGHT", -(SIDEBAR_WIDTH + 20), 0)
    contentTitle:SetJustifyH("LEFT")

    local contentSubtitle = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    contentSubtitle:SetPoint("TOPLEFT", contentTitle, "BOTTOMLEFT", 0, -4)
    contentSubtitle:SetPoint("RIGHT", f, "RIGHT", -(SIDEBAR_WIDTH + 20), 0)
    contentSubtitle:SetJustifyH("LEFT")
    contentSubtitle:SetWordWrap(true)

    local contentFlavor = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    contentFlavor:SetPoint("TOPLEFT", contentSubtitle, "BOTTOMLEFT", 0, -6)
    contentFlavor:SetPoint("RIGHT", f, "RIGHT", -(SIDEBAR_WIDTH + 20), 0)
    contentFlavor:SetJustifyH("LEFT")
    contentFlavor:SetWordWrap(true)

    local headerSep = f:CreateTexture(nil, "ARTWORK")
    headerSep:SetHeight(1)
    headerSep:SetPoint("TOPLEFT", contentFlavor, "BOTTOMLEFT", -4, -8)
    headerSep:SetPoint("RIGHT", f, "RIGHT", -(SIDEBAR_WIDTH + 16), 0)
    SetSolidColor(headerSep, 0.25, 0.25, 0.25, 0.6)

    -- Pre-build a scroll frame per version
    local versionScrollFrames = {}
    for i, entry in ipairs(ns.changelog) do
        local sf = CreateFrame("ScrollFrame", "PatchWerk_ChangelogScroll" .. i, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", headerSep, "BOTTOMLEFT", 4, -8)
        sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(SIDEBAR_WIDTH + 32), 50)
        sf:Hide()

        local content = CreateFrame("Frame", nil, sf)
        local contentWidth = FRAME_WIDTH - SIDEBAR_WIDTH - 80
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
    -- Right sidebar: version picker
    ---------------------------------------------------------------------------

    -- Vertical separator
    local vSep = f:CreateTexture(nil, "ARTWORK")
    vSep:SetWidth(1)
    vSep:SetPoint("TOP", f, "TOPRIGHT", -SIDEBAR_WIDTH, headerTop)
    vSep:SetPoint("BOTTOM", f, "BOTTOMRIGHT", -SIDEBAR_WIDTH, 44)
    SetSolidColor(vSep, 0.25, 0.25, 0.25, 0.6)

    -- "Versions" header
    local sidebarHeader = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sidebarHeader:SetPoint("TOPLEFT", vSep, "TOPRIGHT", 10, -6)
    sidebarHeader:SetText("|cff888888Versions|r")

    -- Version buttons
    local versionButtons = {}
    local selectedIndex = 1

    local function SelectVersion(index)
        selectedIndex = index
        local entry = ns.changelog[index]

        for i, btn in ipairs(versionButtons) do
            if i == index then
                btn.bg:SetVertexColor(0.15, 0.4, 0.6, 0.8)
                btn.label:SetTextColor(1, 1, 1)
            else
                btn.bg:SetVertexColor(0.1, 0.1, 0.1, 0)
                btn.label:SetTextColor(0.6, 0.6, 0.6)
            end
        end

        contentTitle:SetText("v" .. entry.version .. "  \226\128\148  " .. entry.title)
        contentSubtitle:SetText("|cffbbbbbb\"" .. entry.subtitle .. "\"|r")
        contentFlavor:SetText("|cff888888" .. entry.flavor .. "|r")

        for i, sf in ipairs(versionScrollFrames) do
            if i == index then sf:Show() else sf:Hide() end
        end
    end

    local by = -24
    for i, entry in ipairs(ns.changelog) do
        local btn = CreateFrame("Button", nil, f)
        btn:SetPoint("TOPLEFT", vSep, "TOPRIGHT", 4, by)
        btn:SetSize(SIDEBAR_WIDTH - 10, 22)

        local btnBg = btn:CreateTexture(nil, "BACKGROUND")
        btnBg:SetAllPoints()
        SetSolidColor(btnBg, 0.1, 0.1, 0.1, 0)
        btn.bg = btnBg

        local label = btn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("LEFT", 6, 0)
        label:SetText("v" .. entry.version)
        label:SetTextColor(0.6, 0.6, 0.6)
        btn.label = label

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

    ---------------------------------------------------------------------------
    -- Bottom bar
    ---------------------------------------------------------------------------
    local navSep = f:CreateTexture(nil, "ARTWORK")
    navSep:SetHeight(1)
    navSep:SetPoint("BOTTOMLEFT", 0, 44)
    navSep:SetPoint("BOTTOMRIGHT", 0, 44)
    SetSolidColor(navSep, 0.25, 0.25, 0.25, 0.6)

    local gotItBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    gotItBtn:SetPoint("BOTTOMRIGHT", -12, 6)
    gotItBtn:SetSize(80, 24)
    gotItBtn:SetText("Got it")
    gotItBtn:SetScript("OnClick", function() ns:CloseChangelog() end)

    -- Prev / Next buttons (bottom-left)
    local prevBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    prevBtn:SetPoint("BOTTOMLEFT", 12, 6)
    prevBtn:SetSize(24, 24)
    prevBtn:SetText("<")
    prevBtn:SetScript("OnClick", function()
        if selectedIndex > 1 then
            SelectVersion(selectedIndex - 1)
        end
    end)

    local nextBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
    nextBtn:SetSize(24, 24)
    nextBtn:SetText(">")
    nextBtn:SetScript("OnClick", function()
        if selectedIndex < #ns.changelog then
            SelectVersion(selectedIndex + 1)
        end
    end)

    local navLabel = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    navLabel:SetPoint("LEFT", nextBtn, "RIGHT", 8, 0)

    -- Wrap SelectVersion to update nav state
    local origSelect = SelectVersion
    SelectVersion = function(index)
        origSelect(index)
        prevBtn:SetEnabled(index > 1)
        nextBtn:SetEnabled(index < #ns.changelog)
        navLabel:SetText("|cff888888" .. index .. " / " .. #ns.changelog .. "|r")
    end

    -- ESC dismissal via UISpecialFrames (named frame required)
    tinsert(UISpecialFrames, "PatchWerk_Changelog")
    f:SetScript("OnHide", function()
        overlay:Hide()
        local db = ns:GetDB()
        if db then db.lastSeenChangelogVersion = ns.VERSION end
    end)

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
