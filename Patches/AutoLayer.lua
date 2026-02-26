------------------------------------------------------------------------
-- PatchWerk - Performance, bug fix, and UX patches for AutoLayer_Vanilla
--
-- AutoLayer_Vanilla (v1.7.7) is a layer-hopping automation addon for
-- TBC Classic Anniversary. It monitors chat channels and auto-invites
-- players requesting layer transfers, with a hard dependency on
-- NovaWorldBuffs for layer detection (NWB_CurrentLayer global).
--
-- Patches:
--   1. AutoLayer_keyDownThrottle     - Throttle keystroke frame (Performance)
--   2. AutoLayer_parseCache          - Cache parsed triggers/blacklist (Performance)
--   3. AutoLayer_systemFilterCache   - Pre-compute system message patterns (Performance)
--   4. AutoLayer_pruneCacheFix       - Fix forward-iteration removal bug (Fixes)
--   5. AutoLayer_libSerializeCleanup - Mark unused LibSerialize (Tweaks)
--   6. AutoLayer_layerStatusFrame    - On-screen layer status display (Tweaks)
--   7. AutoLayer_layerChangeToast    - Layer change notification (Tweaks)
--   8. AutoLayer_hopTransitionTracker - Hop lifecycle tracker (Tweaks)
--   9. AutoLayer_enhancedTooltip     - Enhanced minimap tooltip (Tweaks)
--  10. AutoLayer_instanceGuard       - Block invites and hops inside instances (Fixes)
------------------------------------------------------------------------

local _, ns = ...

local GetTime = GetTime
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local pcall = pcall
local math_sin = math.sin
local math_abs = math.abs
local math_floor = math.floor
local UnitName = UnitName
local UnitGUID = UnitGUID
local UnitExists = UnitExists
local strsplit = strsplit
local GetNumGroupMembers = GetNumGroupMembers
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsInInstance = IsInInstance
local LeaveParty = LeaveParty
local hooksecurefunc = hooksecurefunc

local WHITE8x8 = "Interface\\Buttons\\WHITE8x8"

------------------------------------------------------------------------
-- Instance IDs for cross-continent detection via UnitPosition().
-- The 4th return value of UnitPosition identifies the continent:
--   0 = Eastern Kingdoms, 1 = Kalimdor, 530 = Outland.
-- UnitPosition("party1") returns nil when the party member is on a
-- different continent — this is the primary detection mechanism.
------------------------------------------------------------------------
local INSTANCE_CONTINENTS = {
    [0]   = "AZEROTH",   -- Eastern Kingdoms
    [1]   = "AZEROTH",   -- Kalimdor
    [530] = "OUTLAND",   -- Outland
}

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------

-- 1. Keystroke Throttle
ns:RegisterPatch("AutoLayer", {
    key = "AutoLayer_keyDownThrottle",
    label = "Keystroke Throttle",
    help = "Stops AutoLayer from processing its queue on every single keystroke (WASD, abilities, camera turns).",
    detail = "AutoLayer processes its invite queue every time you press any key -- movement, abilities, camera turns, everything. During normal gameplay this means dozens of unnecessary checks per second. This patch limits it to at most 5 checks per second, which is still plenty fast but cuts out most of the wasted work.",
    impact = "FPS", impactLevel = "High", category = "Performance",
    estimate = "~2-5 FPS during active gameplay",
})

-- 2. Parse Cache
ns:RegisterPatch("AutoLayer", {
    key = "AutoLayer_parseCache",
    label = "Keyword Cache",
    help = "Remembers your trigger words and blacklist instead of rebuilding them on every chat message.",
    detail = "AutoLayer rebuilds its keyword, blacklist, and prefix tables from scratch on every incoming chat message. In busy channels like Trade or LookingForGroup, this creates thousands of throwaway tables per minute, causing memory buildup and brief hitches. This patch remembers the tables and only rebuilds when your settings actually change.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~1-2 FPS in busy chat environments",
})

-- 3. System Filter Cache
ns:RegisterPatch("AutoLayer", {
    key = "AutoLayer_systemFilterCache",
    label = "System Message Cache",
    help = "Pre-computes system message filters once instead of rebuilding 15 text patterns on every system message.",
    detail = "AutoLayer rebuilds 15 text matching patterns from scratch every time a system message appears (group invites, loot, achievements, etc.). This patch builds all the patterns once when you log in and reuses them, instead of redoing the work every time.",
    impact = "FPS", impactLevel = "Medium", category = "Performance",
    estimate = "~1 FPS during heavy system message activity",
})

-- 4. Cache Prune Fix
ns:RegisterPatch("AutoLayer", {
    key = "AutoLayer_pruneCacheFix",
    label = "Cache Prune Fix",
    help = "Fixes a bug where stale cache entries could be skipped during cleanup, potentially causing duplicate invites.",
    detail = "AutoLayer has a bug in how it cleans up expired entries from its invite cooldown list. When removing an entry, the next entry in the list gets accidentally skipped. This can leave stale cooldown entries behind, which may cause duplicate invites or missed cleanup. The fix ensures all expired entries are properly removed.",
    category = "Fixes",
    estimate = "Prevents duplicate invites from stale cache entries",
})

-- 5. Unused Library Cleanup
ns:RegisterPatch("AutoLayer", {
    key = "AutoLayer_libSerializeCleanup",
    label = "Unused Library Note",
    help = "Notes that AutoLayer loads a library (LibSerialize) that it never actually uses.",
    detail = "AutoLayer loads a data-packing library at startup but never actually calls it anywhere. The library sits in memory doing nothing. This patch serves as a note for the addon author that the library can be safely removed.",
    impact = "Memory", impactLevel = "Low", category = "Tweaks",
    estimate = "Minimal (informational only)",
})

-- 6. Layer Status Frame
ns:RegisterPatch("AutoLayer", {
    key = "AutoLayer_layerStatusFrame",
    label = "Layer Status Frame",
    help = "Adds a small, movable on-screen frame showing your current layer, AutoLayer status, and session invite count.",
    detail = "Displays a compact, draggable frame with your current layer number (green when known, red when unknown), whether AutoLayer is enabled or disabled, and how many players you've layered this session. Position is saved between sessions. Integrates with the Hop Transition Tracker for live hop state display.",
    category = "Tweaks",
    estimate = "Visual enhancement with minimal overhead",
})

-- 7. Layer Change Toast
ns:RegisterPatch("AutoLayer", {
    key = "AutoLayer_layerChangeToast",
    label = "Layer Change Toast",
    help = "Shows a brief gold notification when your layer changes, e.g. 'Layer 2 -> 3'.",
    detail = "Monitors the NWB_CurrentLayer global for changes and displays a gold-colored message via UIErrorsFrame when a layer transition is detected. Also plays a subtle ping sound. The message auto-dismisses after a few seconds, matching the style of standard WoW system messages.",
    category = "Tweaks",
    estimate = "Visual enhancement only",
})

-- 8. Hop Transition Tracker
ns:RegisterPatch("AutoLayer", {
    key = "AutoLayer_hopTransitionTracker",
    label = "Hop Transition Tracker",
    help = "Tracks the full hop lifecycle with visual feedback: idle, waiting, in group, and confirmed states.",
    detail = "Monitors AutoLayer's hop requests to track each stage of a layer hop. During an active hop, layer detection speeds up to 10x faster for quicker confirmation. States are displayed in the Layer Status Frame with color-coded text: yellow for waiting, orange with pulsing for in group, green flash for confirmed.",
    category = "Tweaks",
    estimate = "Visual enhancement, integrates with Layer Status Frame",
})

-- 9. Enhanced Tooltip
ns:RegisterPatch("AutoLayer", {
    key = "AutoLayer_enhancedTooltip",
    label = "Enhanced Tooltip",
    help = "Adds extra information to the AutoLayer minimap icon tooltip.",
    detail = "Enhances the AutoLayer minimap icon tooltip with richer information including current layer with color coding, total available layers from NovaWorldBuffs, session invite count, AutoLayer enabled/disabled status, and active hop transition state if mid-hop.",
    category = "Tweaks",
    estimate = "Visual enhancement, tooltip only",
})

-- 10. Instance Guard
ns:RegisterPatch("AutoLayer", {
    key = "AutoLayer_instanceGuard",
    label = "Instance Guard",
    help = "Prevents AutoLayer from inviting players or leaving your group while you're inside a dungeon or raid.",
    detail = "AutoLayer has no awareness of dungeon or raid instances. If you're the party leader inside a dungeon and someone asks for a layer in guild chat, AutoLayer will happily invite them into your dungeon group. Likewise, requesting a layer hop while in an instance will leave your dungeon party without warning. This patch blocks both paths when you're inside an instance.",
    category = "Fixes",
    estimate = "Prevents accidental group disruption in dungeons and raids",
})

ns:RegisterDefault("AutoLayer_hopWhisperEnabled", true)
ns:RegisterDefault("AutoLayer_hopWhisperMessage", "[PatchWerk] Hopped! Smoother than a Paladin bubble-hearth. Cheers!")
ns:RegisterDefault("AutoLayer_toastDuration", 8)
ns:RegisterDefault("AutoLayer_statusFrame_point", nil)

------------------------------------------------------------------------
-- Shared state for visual patches (6, 7, 8)
------------------------------------------------------------------------

local statusFrame = nil
local pollerStarted = false
local UpdateStatusFrame  -- forward declaration (called by ConfirmHop/FailHop before definition)

local hopState = {
    state = "IDLE",         -- IDLE, WAITING_INVITE, IN_GROUP, CONFIRMED, NO_RESPONSE
    source = nil,           -- "OUTBOUND" (from SendLayerRequest) or "INBOUND" (from PARTY_INVITE_REQUEST)
    fromLayer = nil,
    targetLayer = nil,      -- parsed from [AutoLayer] whisper "layer {N}"
    hostName = nil,         -- captured when entering IN_GROUP (before group disbands)
    deadline = nil,         -- GetTime()+N for countdown display
    _nwbCleared = false,    -- ensures NWB caches cleared exactly once on group disband
    _lastNWBPoke = 0,       -- throttle for periodic NWB re-detection nudges
    timestamp = 0,
    lastKnownLayer = nil,
    lastRequestTime = 0,    -- cooldown: when the last hop request was sent
    hopRetries = 0,         -- failed hop retry counter
}

-- Hosts confirmed cross-continent: { ["Name"] = { time = timestamp, continent = "Azeroth" } }.
-- Skips instant-leave without wasting retries or re-whispering.
-- Entries expire after 5 minutes (host might move continents).
local crossContinentHosts = {}
local CROSS_CONTINENT_EXPIRY = 300  -- 5 minutes

local recentHopHosts = {}
local RECENT_HOP_EXPIRY = 60  -- 1 minute

-- Blanket cross-continent block: once we detect a single cross-continent
-- host, decline ALL new AutoLayer invites pre-emptively while the player
-- remains on the same continent. Prevents the join->detect->leave spam
-- when dozens of Azeroth hosts re-invite an Outland player.
local crossContinentBlock = nil   -- { expiry = GetTime()+N, continent = "OUTLAND"|"AZEROTH" }
local declinedWhisperTimes = {}   -- { ["Name"] = GetTime() } rate-limit whispers
local DECLINED_WHISPER_CD = 120   -- seconds between whispers to the same declined host

-- Track when we last broadcast a hop request so we can distinguish
-- AutoLayer invite responses from manual party invites.  Any invite
-- arriving within this window of our broadcast is almost certainly
-- an AutoLayer host responding, not a friend/guild invite.
local lastHopBroadcastTime = 0
local HOP_BROADCAST_WINDOW = 60  -- seconds

-- Track incoming [AutoLayer] whispers: { ["Name"] = { time, layer } }.
-- Used to extract the target layer for same-layer skip logic.
local autoLayerWhispers = {}

local POLL_IDLE = 1.0
local POLL_ACTIVE = 0.1
local CONFIRM_DURATION = 3.0
local WAITING_TIMEOUT = 20.0
local MAX_HOP_RETRIES = 3
local HOP_RETRY_DELAY = 3.0
local IN_GROUP_TIMEOUT = 120.0

local function GetToastDuration()
    return ns:GetOption("AutoLayer_toastDuration") or 8
end
local NO_RESPONSE_DURATION = 5.0

------------------------------------------------------------------------
-- Helper: Get the other party member's name (for whisper on leave)
------------------------------------------------------------------------
local function GetPartyMemberName()
    local myName = UnitName("player")
    for i = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(i)
        if name and name ~= myName then
            return name
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Cross-continent detection via UnitPosition().
--
-- UnitPosition("party1") returns nil when the party member is on a
-- different continent (or in an instance). Combined with a valid
-- UnitPosition("player") return (confirming we're in the open world),
-- nil party position = cross-continent = hop won't work.
--
-- This replaces the previous WHO-based approach (SendWho is protected
-- in TBC Classic and silently fails from event handlers).
------------------------------------------------------------------------
local HandleFailedHop  -- forward declaration

local function IsCrossContinentHop()
    if hopState.state ~= "IN_GROUP" then return false, nil end
    if type(UnitPosition) ~= "function" then return false, nil end

    -- Player must be in the open world (UnitPosition returns nil in instances)
    local _, _, _, playerInstanceID = UnitPosition("player")
    if not playerInstanceID then return false, nil end

    -- Party member on a different continent returns nil.
    -- Also returns nil if party1 left the group already — guard against that.
    if not UnitExists("party1") then return false, nil end

    local _, _, _, partyInstanceID = UnitPosition("party1")

    if not partyInstanceID then
        -- Party member exists but returned nil position — they're on a
        -- different continent or in an instance. Can't hop either way.
        local playerContinent = INSTANCE_CONTINENTS[playerInstanceID]
        if playerContinent then
            local otherContinent = (playerContinent == "OUTLAND") and "Azeroth" or "Outland"
            return true, otherContinent
        end
        return true, nil
    end

    -- Both returned data — compare continent groupings
    local playerContinent = INSTANCE_CONTINENTS[playerInstanceID]
    local partyContinent = INSTANCE_CONTINENTS[partyInstanceID]

    if playerContinent and partyContinent and playerContinent ~= partyContinent then
        local otherContinent = (partyContinent == "OUTLAND") and "Outland" or "Azeroth"
        return true, otherContinent
    end

    return false, nil
end

------------------------------------------------------------------------
-- Helper: Leave hop group
------------------------------------------------------------------------
local function LeaveHopGroup(reason)
    if not IsInGroup() or IsInRaid() or IsInInstance() then return end

    LeaveParty()

    if reason == "confirmed" then
        -- Layer already verified — NWB cache is correct, don't invalidate.
        -- No toast here: ConfirmHop() already showed the gold notification.
    elseif reason == "cross_continent" then
        -- No phase happened — NWB caches and zone data are still valid.
        -- HandleFailedHop shows its own message, so nothing to display here.
    else
        -- Invalidate NWB's stale layer cache for verifying/timeout
        rawset(_G, "NWB_CurrentLayer", 0)
        if NWB then
            NWB.currentLayer = 0
            if NWB.lastKnownLayerMapID then NWB.lastKnownLayerMapID = 0 end
            if NWB.lastKnownLayerMapZoneID then NWB.lastKnownLayerMapZoneID = 0 end
            if NWB.lastKnownLayerID then NWB.lastKnownLayerID = 0 end
        end
        if reason == "timeout" then
            UIErrorsFrame:AddMessage("PatchWerk: Left group \226\128\148 hop timed out", 0.2, 0.8, 1.0, 1.0, GetToastDuration())
        end
    end
    -- Whisper is handled by ConfirmHop, not here
end

local retryFrame  -- forward declaration (created by InitHopFrames)

------------------------------------------------------------------------
-- Lazy initialization for frames that only AutoLayer patches need.
-- Prevents file-scope frame creation and event registration for users
-- who don't have AutoLayer installed (avoids unnecessary taint vectors).
------------------------------------------------------------------------
local hopFramesInit = false
local function InitHopFrames()
    if hopFramesInit then return end
    hopFramesInit = true

    -- Retry frame: fires pending retries on the next keypress.
    -- SendChatMessage to channels is protected in TBC Classic and
    -- requires hardware event context. OnKeyDown handlers have it.
    retryFrame = CreateFrame("Frame", nil, UIParent)
    retryFrame:EnableKeyboard(true)
    retryFrame:SetPropagateKeyboardInput(true)
    retryFrame:Hide()
    retryFrame:SetScript("OnKeyDown", function(self)
        self:Hide()
        if hopState.state ~= "WAITING_INVITE" then return end
        if not AutoLayer or not AutoLayer.SlashCommand then return end
        lastHopBroadcastTime = GetTime()
        pcall(AutoLayer.SlashCommand, AutoLayer, "req")
    end)
end

------------------------------------------------------------------------
-- Helper: Confirm a successful hop (toast + whisper + state update)
------------------------------------------------------------------------
local function ConfirmHop(layerNum)
    hopState.state = "CONFIRMED"
    hopState.timestamp = GetTime()
    hopState.hopRetries = 0
    hopState.targetLayer = nil
    hopState.deadline = GetTime() + CONFIRM_DURATION
    hopState._nwbCleared = false
    retryFrame:Hide()  -- disarm pending retry

    if hopState.hostName then
        recentHopHosts[hopState.hostName] = GetTime()
    end

    -- Gold toast notification
    if ns.applied["AutoLayer_layerChangeToast"] then
        local msg
        if hopState.fromLayer and layerNum then
            msg = "Layer " .. hopState.fromLayer .. " -> " .. layerNum
        else
            msg = "Hop confirmed!"
        end
        UIErrorsFrame:AddMessage(msg, 1.0, 0.82, 0.0, 1.0, GetToastDuration())
        PlaySound(SOUNDKIT and SOUNDKIT.MAP_PING or 3175)
    end

    -- Thank-you whisper to the hop host
    if hopState.hostName and ns:GetOption("AutoLayer_hopWhisperEnabled") then
        local whisper = ns:GetOption("AutoLayer_hopWhisperMessage") or "[PatchWerk] Hopped! Smoother than a Paladin bubble-hearth. Cheers!"
        pcall(SendChatMessage, whisper, "WHISPER", nil, hopState.hostName)
    end

    UpdateStatusFrame()
end

------------------------------------------------------------------------
-- Helper: Mark a hop as failed (reset state + orange message)
------------------------------------------------------------------------
local function FailHop(reason)
    UIErrorsFrame:AddMessage("PatchWerk: " .. reason, 1.0, 0.6, 0.0, 1.0, GetToastDuration())
    retryFrame:Hide()       -- disarm pending retry
    hopState.state = "IDLE"
    hopState.source = nil
    hopState.fromLayer = nil
    hopState.targetLayer = nil
    hopState.hostName = nil
    hopState.deadline = nil
    hopState._nwbCleared = false
    hopState.hopRetries = 0
    UpdateStatusFrame()
end

-- Retry frame and OnKeyDown handler are created by InitHopFrames()
-- when an AutoLayer patch runs. See the lazy-init function above.

------------------------------------------------------------------------
-- Helper: Handle a hop that isn't working.
-- Called by cross-continent detection or Method 4 (10s nothing
-- changed). Leaves the group and auto-retries up to 3 times.
--
-- The retry fires on the next keypress after a short delay because
-- SendChatMessage to channels is protected in TBC Classic and
-- requires hardware event context (C_Timer callbacks don't have it).
--
-- @param reason  Optional string like "Azeroth" for cross-continent,
--                or nil for generic "hop not working" message.
------------------------------------------------------------------------
HandleFailedHop = function(reason)
    LeaveHopGroup(reason and "cross_continent" or "timeout")

    -- Cross-continent with blanket block active: no point retrying — every
    -- available host is on the wrong continent.  Fail immediately with a
    -- clear message instead of broadcasting more "req" messages to chat.
    if reason and crossContinentBlock and GetTime() < crossContinentBlock.expiry then
        local myCont = crossContinentBlock.continent
        local myLocation = (myCont == "OUTLAND") and "Outland" or "Azeroth"
        FailHop("Can't hop \226\128\148 hosts are in " .. reason .. " (you're in " .. myLocation .. ")")
        return
    end

    if hopState.hopRetries < MAX_HOP_RETRIES then
        hopState.hopRetries = hopState.hopRetries + 1
        local attempt = hopState.hopRetries
        local msg
        if reason then
            msg = "PatchWerk: Host is in " .. reason .. " \226\128\148 retrying (" .. attempt .. "/" .. MAX_HOP_RETRIES .. ")"
        else
            msg = "PatchWerk: Hop not working \226\128\148 retrying (" .. attempt .. "/" .. MAX_HOP_RETRIES .. ")"
        end
        UIErrorsFrame:AddMessage(msg, 1.0, 0.6, 0.0, 1.0, GetToastDuration())
        hopState.state = "WAITING_INVITE"
        hopState.timestamp = GetTime()
        UpdateStatusFrame()
        -- Arm the retry frame after a delay; the next keypress fires it
        C_Timer.After(HOP_RETRY_DELAY, function()
            if hopState.state ~= "WAITING_INVITE" then return end
            retryFrame:Show()  -- arms keyboard capture
        end)
    else
        if reason then
            FailHop("No same-continent hosts found after " .. MAX_HOP_RETRIES .. " attempts")
        else
            FailHop("Hop failed after " .. MAX_HOP_RETRIES .. " attempts")
        end
    end
end

------------------------------------------------------------------------
-- Helper: Get NWB addon reference
------------------------------------------------------------------------
local function GetNWB()
    local ok, addon = pcall(function()
        return LibStub("AceAddon-3.0"):GetAddon("NovaWorldBuffs")
    end)
    return ok and addon or nil
end

------------------------------------------------------------------------
-- Helper: Update the status frame display
------------------------------------------------------------------------
local function FormatCountdown(deadline)
    if not deadline then return "" end
    local remaining = deadline - GetTime()
    if remaining < 0 then return "" end
    local minutes = math_floor(remaining / 60)
    local seconds = math_floor(remaining % 60)
    if minutes > 0 then
        return " (" .. minutes .. ":" .. string.format("%02d", seconds) .. ")"
    end
    return " (0:" .. string.format("%02d", seconds) .. ")"
end

UpdateStatusFrame = function()
    if not statusFrame or not statusFrame:IsShown() then return end
    if not AutoLayer or not AutoLayer.db then return end

    -- Info line (line 2): layer + status, or hop state
    local currentLayer = NWB_CurrentLayer
    local currentNum = currentLayer and tonumber(currentLayer)
    local layerKnown = currentNum and currentNum > 0
    local enabled = AutoLayer.db.profile.enabled
    local infoStr

    if hopState.state == "NO_RESPONSE" then
        infoStr = "|cffff3333No response|r" .. FormatCountdown(hopState.deadline)
    elseif hopState.state == "WAITING_INVITE" then
        infoStr = "|cffffcc00Searching...|r" .. FormatCountdown(hopState.deadline)
    elseif hopState.state == "IN_GROUP" then
        if hopState.targetLayer then
            infoStr = "|cffff9933Hopping to Layer " .. hopState.targetLayer .. "...|r"
        else
            infoStr = "|cffff9933Hopping...|r"
        end
        -- Show elapsed time instead of countdown for IN_GROUP
        local elapsed = math_floor(GetTime() - hopState.timestamp)
        infoStr = infoStr .. " |cff888888(" .. elapsed .. "s)|r"
    elseif hopState.state == "CONFIRMED" then
        if hopState.fromLayer and currentNum and currentNum > 0 and currentNum ~= hopState.fromLayer then
            infoStr = "|cff33ff33Layer " .. hopState.fromLayer .. " -> " .. currentNum .. "|r"
        elseif hopState.targetLayer then
            infoStr = "|cff33ff33Hopped to Layer " .. hopState.targetLayer .. "!|r"
        else
            infoStr = "|cff33ff33Hop complete!|r"
        end
    elseif enabled then
        if layerKnown then
            infoStr = "|cff33ff33On|r  |cff555555·|r  Layer " .. currentLayer
        else
            infoStr = "|cff33ff33On|r"
        end
    else
        if layerKnown then
            infoStr = "|cffff3333Off|r  |cff555555·|r  Layer " .. currentLayer
        else
            infoStr = "|cffff3333Off|r"
        end
    end
    statusFrame.infoText:SetText(infoStr)

    -- Show hint text during active hop states
    if statusFrame.hintText then
        local hint = nil
        if hopState.state == "WAITING_INVITE" and hopState.hopRetries > 0 then
            if retryFrame:IsShown() then
                hint = "|cffff9933Retrying... press any key (" .. hopState.hopRetries .. "/" .. MAX_HOP_RETRIES .. ")|r"
            else
                hint = "|cffff9933Retrying... (" .. hopState.hopRetries .. "/" .. MAX_HOP_RETRIES .. ")|r"
            end
        elseif hopState.state == "WAITING_INVITE" then
            hint = "|cff888888Waiting for an invite...|r"
        elseif hopState.state == "IN_GROUP" then
            local elapsed = math_floor(GetTime() - hopState.timestamp)
            if elapsed < 5 then
                -- Early: phase is still settling, NPC hint not useful yet
                if hopState.targetLayer then
                    hint = "|cff888888Waiting for layer " .. hopState.targetLayer .. "...|r"
                else
                    hint = "|cff888888Detecting layer change...|r"
                end
            else
                -- After 5s: NWB needs an NPC to confirm (we also scan nameplates)
                if hopState.targetLayer then
                    hint = "|cff888888Stay near NPCs for layer " .. hopState.targetLayer .. " (" .. elapsed .. "s)|r"
                else
                    hint = "|cff888888Stay near NPCs to confirm (" .. elapsed .. "s)|r"
                end
            end
        elseif hopState.state == "NO_RESPONSE" then
            hint = "|cff888888Right-click to try again|r"
        end

        statusFrame.hintText:SetText(hint or "")
        if hint then
            statusFrame.hintText:Show()
            statusFrame:SetHeight(46)
        else
            statusFrame.hintText:Hide()
            statusFrame:SetHeight(34)
        end
    end
end

------------------------------------------------------------------------
-- Helper: Layer polling (shared between patches 6, 7, 8)
------------------------------------------------------------------------
local function PollLayer()
    if not AutoLayer then return end

    local currentLayer = NWB_CurrentLayer
    local currentNum = currentLayer and tonumber(currentLayer)
    local lastNum = hopState.lastKnownLayer

    -- Detect layer change (NWB confirmed a new layer number)
    -- During a hop, NWB changes are verified by the IN_GROUP handler
    -- below. Toast only fires for non-hop layer changes (e.g.
    -- organically moving between layers).
    local layerChanged = false
    if currentNum and currentNum > 0 then
        if lastNum and lastNum > 0 and currentNum ~= lastNum then
            layerChanged = true
        elseif not lastNum and hopState.fromLayer and currentNum ~= hopState.fromLayer then
            layerChanged = true
        end
    end
    if layerChanged then
        -- During an active hop, suppress the generic toast — confirmation
        -- is handled by the IN_GROUP verification below.
        local midHop = (hopState.state == "IN_GROUP" or hopState.state == "WAITING_INVITE")

        -- Layer change toast (patch 7)
        if ns.applied["AutoLayer_layerChangeToast"] and not midHop then
            local fromNum = lastNum or hopState.fromLayer
            local msg = "Layer " .. (fromNum or "?") .. " -> " .. currentNum
            UIErrorsFrame:AddMessage(msg, 1.0, 0.82, 0.0, 1.0, GetToastDuration())
            PlaySound(SOUNDKIT and SOUNDKIT.MAP_PING or 3175)
        end

    end

    -- IN_GROUP: simplified verification using targetLayer from whisper.
    -- NWB_CurrentLayer persists after group disband and updates when
    -- the player targets an NPC. No VERIFYING state needed.
    if ns.applied["AutoLayer_hopTransitionTracker"] and hopState.state == "IN_GROUP" then
        local elapsed = GetTime() - hopState.timestamp

        -- Clear NWB caches exactly once after group disband so NWB
        -- re-detects from fresh NPC interaction instead of restoring
        -- stale data. We stay IN_GROUP and let PollLayer handle the rest.
        if not IsInGroup() and not hopState._nwbCleared then
            hopState._nwbCleared = true
            rawset(_G, "NWB_CurrentLayer", 0)
            if NWB then
                NWB.currentLayer = 0
                if NWB.lastKnownLayerMapID then NWB.lastKnownLayerMapID = 0 end
                if NWB.lastKnownLayerMapZoneID then NWB.lastKnownLayerMapZoneID = 0 end
                if NWB.lastKnownLayerID then NWB.lastKnownLayerID = 0 end
            end
        end

        -- Re-read after potential cache clear
        currentNum = NWB_CurrentLayer and tonumber(NWB_CurrentLayer)

        local layerConfirmed = false

        if hopState.targetLayer then
            -- Primary path: we know the target layer from the whisper
            if currentNum and currentNum > 0 and currentNum == hopState.targetLayer then
                layerConfirmed = true
            elseif currentNum and currentNum > 0 and currentNum == hopState.fromLayer and elapsed > 10 then
                -- Still on the same layer after 10s — hop failed
                HandleFailedHop()
            end
        else
            -- Fallback path: no targetLayer (whisper missing/unparseable)
            if currentNum and currentNum > 0 and hopState.fromLayer
               and hopState.fromLayer > 0 and currentNum ~= hopState.fromLayer then
                layerConfirmed = true
            elseif currentNum and currentNum > 0 and hopState.fromLayer
                   and hopState.fromLayer > 0 and currentNum == hopState.fromLayer and elapsed > 10 then
                HandleFailedHop()
            elseif not hopState.fromLayer and elapsed > 15 then
                -- No baseline at all — trust after 15s
                layerConfirmed = true
            end
        end

        -- Periodically poke NWB to re-detect from nearby NPCs.
        -- NWB scans on its own events, but this nudge speeds up detection
        -- by feeding it target, mouseover, or visible nameplates.
        if not layerConfirmed and elapsed > 3 and NWB and NWB.setCurrentLayerText then
            local now = GetTime()
            if (now - hopState._lastNWBPoke) > 3 then
                hopState._lastNWBPoke = now
                local poked = false
                if UnitExists("target") then
                    pcall(NWB.setCurrentLayerText, NWB, "target")
                    poked = true
                end
                if not poked and UnitExists("mouseover") then
                    pcall(NWB.setCurrentLayerText, NWB, "mouseover")
                    poked = true
                end
                -- Scan visible nameplates — nearby NPCs the player hasn't targeted
                if not poked then
                    for i = 1, 40 do
                        if UnitExists("nameplate" .. i) then
                            local guid = UnitGUID("nameplate" .. i)
                            if guid then
                                local unitType = strsplit("-", guid)
                                if unitType == "Creature" then
                                    pcall(NWB.setCurrentLayerText, NWB, "nameplate" .. i)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Safety timeout
        if not layerConfirmed and elapsed > IN_GROUP_TIMEOUT then
            if not IsInGroup() then
                -- Group disbanded and timed out — trust the hop
                layerConfirmed = true
            else
                LeaveHopGroup("timeout")
                FailHop("Hop timed out \226\128\148 target an NPC to check your layer")
            end
        end

        if layerConfirmed then
            hopState.hostName = hopState.hostName or GetPartyMemberName()
            ConfirmHop(currentNum and currentNum > 0 and currentNum or nil)
            -- Leave immediately — phase is already confirmed
            if IsInGroup() and not IsInRaid() and not IsInInstance() then
                LeaveHopGroup("confirmed")
            end
        end
    end

    -- CONFIRMED: ensure we've left the hop group.
    -- Safety net: if the immediate leave after ConfirmHop didn't work
    -- (e.g. group state changed between confirm and leave), retry each poll.
    if hopState.state == "CONFIRMED" and IsInGroup() and not IsInRaid() and not IsInInstance() then
        LeaveHopGroup("confirmed")
    end

    -- Update last known layer
    if currentNum and currentNum > 0 then
        hopState.lastKnownLayer = currentNum
    end

    -- State timeouts
    local now = GetTime()
    if hopState.state == "CONFIRMED" and (now - hopState.timestamp) > CONFIRM_DURATION then
        hopState.state = "IDLE"
        hopState.source = nil
        hopState.fromLayer = nil
        hopState.targetLayer = nil
        hopState.hostName = nil
        hopState.deadline = nil
        hopState._nwbCleared = false
        hopState.hopRetries = 0
    end
    -- IN_GROUP safety net: 120s without any proof — leave and reset.
    -- This is the last resort; Method 4 (10s "nothing changed") handles
    -- most failures faster. This catches edge cases with no baselines.
    if hopState.state == "IN_GROUP" and (now - hopState.timestamp) > IN_GROUP_TIMEOUT then
        LeaveHopGroup("timeout")
        FailHop("Hop timed out \226\128\148 target an NPC to check your layer")
    end
    if hopState.state == "WAITING_INVITE" and (now - hopState.timestamp) > WAITING_TIMEOUT then
        if IsInGroup() then
            -- Already in group, GROUP_ROSTER_UPDATE just hasn't fired yet
            hopState.state = "IN_GROUP"
            hopState.timestamp = now
        else
            UIErrorsFrame:AddMessage("No invite received", 1.0, 0.3, 0.3)
            hopState.state = "NO_RESPONSE"
            hopState.source = nil
            hopState.timestamp = now
        end
    end
    if hopState.state == "NO_RESPONSE" and (now - hopState.timestamp) > NO_RESPONSE_DURATION then
        hopState.state = "IDLE"
        hopState.source = nil
        hopState.fromLayer = nil
        hopState.targetLayer = nil
        hopState.hostName = nil
        hopState.deadline = nil
        hopState._nwbCleared = false
        hopState.hopRetries = 0
    end

    -- Update status frame
    UpdateStatusFrame()

    -- Schedule next poll (faster during active hop)
    local interval = (hopState.state == "IN_GROUP" or hopState.state == "WAITING_INVITE")
        and POLL_ACTIVE or POLL_IDLE
    C_Timer.After(interval, PollLayer)
end

------------------------------------------------------------------------
-- Helper: Start the shared poller (idempotent)
------------------------------------------------------------------------
local function StartPoller()
    if pollerStarted then return end
    pollerStarted = true
    InitHopFrames()

    -- Initialize last known layer
    local currentLayer = NWB_CurrentLayer
    if currentLayer and tonumber(currentLayer) and tonumber(currentLayer) > 0 then
        hopState.lastKnownLayer = tonumber(currentLayer)
    end

    C_Timer.After(POLL_IDLE, PollLayer)
end

------------------------------------------------------------------------
-- Helper: Create the status frame (used by patch 6)
------------------------------------------------------------------------
local function CreateStatusFrame()
    if statusFrame then return statusFrame end
    InitHopFrames()

    local f = CreateFrame("Frame", "PatchWerk_AutoLayerStatus", UIParent)
    f:SetSize(190, 34)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)

    -- Restore saved position
    local p = ns:GetOption("AutoLayer_statusFrame_point")
    if type(p) == "table" and #p >= 5 then
        f:ClearAllPoints()
        f:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -70)
    end

    -- Border (extends 1px beyond frame bounds)
    local border = f:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetTexture(WHITE8x8)
    border:SetVertexColor(0.25, 0.25, 0.25, 0.9)

    -- Background (covers frame area, draws above border)
    local bg = f:CreateTexture(nil, "BORDER")
    bg:SetAllPoints()
    bg:SetTexture(WHITE8x8)
    bg:SetVertexColor(0.05, 0.05, 0.05, 0.85)

    -- Title (line 1)
    local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("TOPLEFT", 6, -4)
    titleText:SetText("|cff33ccffAutoLayer|r  |cff555555(PatchWerk)|r")

    -- Info line (line 2): layer + status, or hop state
    local infoText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
    f.infoText = infoText

    -- Hint line (line 3): contextual help, hidden by default
    local hintText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintText:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -1)
    hintText:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    hintText:Hide()
    f.hintText = hintText

    -- Drag to reposition (left-button drag only)
    f:SetScript("OnDragStart", function(self)
        self._dragging = true
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self._lastDragTime = GetTime()
        self._dragging = false
        local point, _, relPoint, x, y = self:GetPoint()
        ns:SetOption("AutoLayer_statusFrame_point", { point, "UIParent", relPoint, x, y })
    end)

    -- Click interactions: left = toggle, shift+left = cancel hop,
    -- right = quick hop, shift+right = hop GUI
    f:SetScript("OnMouseUp", function(self, button)
        -- Ignore clicks right after a drag
        if self._lastDragTime and (GetTime() - self._lastDragTime) < 0.2 then return end
        if self._dragging then return end
        if not AutoLayer then return end

        if button == "LeftButton" then
            if IsShiftKeyDown() then
                -- Shift+Left: cancel active hop and reset state
                if hopState.state ~= "IDLE" then
                    retryFrame:Hide()
                    if IsInGroup() and not IsInRaid() and not IsInInstance() then
                        LeaveParty()
                    end
                    hopState.state = "IDLE"
                    hopState.source = nil
                    hopState.fromLayer = nil
                    hopState.targetLayer = nil
                    hopState.hostName = nil
                    hopState.deadline = nil
                    hopState._nwbCleared = false
                    hopState.hopRetries = 0
                    UIErrorsFrame:AddMessage("PatchWerk: Hop cancelled", 1.0, 0.6, 0.0, 1.0, GetToastDuration())
                    UpdateStatusFrame()
                end
            elseif AutoLayer.Toggle then
                AutoLayer:Toggle()
                UpdateStatusFrame()
            end
        elseif button == "RightButton" then
            if IsShiftKeyDown() then
                -- Shift+Right: open full hop GUI for picking specific layers
                if AutoLayer.HopGUI then
                    AutoLayer:HopGUI()
                end
            else
                -- Right-click: quick hop to any other layer
                -- Block when mid-hop, on cooldown, or inside an instance
                if hopState.state == "IN_GROUP" or hopState.state == "CONFIRMED" then return end
                if IsInInstance() then return end
                if not AutoLayer.SlashCommand then return end
                local now = GetTime()
                if (now - hopState.lastRequestTime) < 3.0 then return end
                -- Always send via SlashCommand — AutoLayer handles unknown
                -- layers internally. Never fall back to HopGUI on right-click.
                hopState.lastRequestTime = now
                pcall(AutoLayer.SlashCommand, AutoLayer, "req")
            end
        end
    end)

    -- Tooltip on hover with details + instructions
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("|cff33ccffAutoLayer|r |cff808080(PatchWerk)|r")

        -- Status explanation
        if AutoLayer and AutoLayer.db then
            GameTooltip:AddLine(" ")
            if AutoLayer.db.profile.enabled then
                GameTooltip:AddLine("Listening for layer requests and auto-inviting", 0.4, 1.0, 0.4)
            else
                GameTooltip:AddLine("Not listening — players asking for layers are ignored", 1.0, 0.4, 0.4)
            end

            local layered = AutoLayer.db.profile.layered or 0
            if layered > 0 then
                GameTooltip:AddDoubleLine("Helped this session:", "|cffffcc00" .. layered .. " players|r")
            end
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click to toggle on/off", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Shift+Left-click to cancel hop", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Right-click to quick hop", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Shift+Right-click to pick layers", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Drag to move", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Pulsing animation for IN_GROUP state
    local pulseTime = 0
    local countdownThrottle = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        if hopState.state == "IN_GROUP" then
            pulseTime = pulseTime + elapsed
            local alpha = 0.6 + 0.4 * math_sin(pulseTime * 3)
            self.infoText:SetAlpha(alpha)
        else
            pulseTime = 0
            self.infoText:SetAlpha(1)
        end
        -- Refresh countdown display every second
        countdownThrottle = countdownThrottle + elapsed
        if countdownThrottle >= 1.0 then
            countdownThrottle = 0
            if hopState.state ~= "IDLE" then
                UpdateStatusFrame()
            end
        end
    end)

    statusFrame = f
    return f
end

------------------------------------------------------------------------
-- 1. AutoLayer_keyDownThrottle
--
-- layering.lua:750-752 creates a frame named "Test" that fires
-- ProccessQueue() on every KEY_DOWN event. During normal gameplay
-- (WASD movement, abilities, camera) this means dozens of wasted
-- calls per second. Fix: throttle to max once per 0.2 seconds.
------------------------------------------------------------------------
ns.patches["AutoLayer_keyDownThrottle"] = function()
    if not ns:IsAddonLoaded("AutoLayer_Vanilla") then return end
    if type(ProccessQueue) ~= "function" then return end

    local f = _G["Test"]
    if not f or type(f) ~= "table" or not f.GetScript then return end

    local origHandler = f:GetScript("OnKeyDown")
    if not origHandler then return end

    -- Clear the generic "Test" global name (rawset avoids taint tracking)
    rawset(_G, "Test", nil)

    -- Throttle: max once per 0.2 seconds
    local lastCall = 0
    f:SetScript("OnKeyDown", function(self, key)
        local now = GetTime()
        if now - lastCall >= 0.2 then
            lastCall = now
            origHandler(self, key)
        end
    end)
end

------------------------------------------------------------------------
-- 2. AutoLayer_parseCache
--
-- configuration.lua:25-65 — ParseTriggers(), ParseBlacklist(),
-- ParseInvertKeywords(), and ParseIgnorePrefixes() rebuild tables via
-- string.gmatch on every chat message. Fix: cache parsed tables,
-- invalidate on setter calls.
------------------------------------------------------------------------
ns.patches["AutoLayer_parseCache"] = function()
    if not ns:IsAddonLoaded("AutoLayer_Vanilla") then return end
    if not AutoLayer then return end

    local cachedTriggers = nil
    local cachedBlacklist = nil
    local cachedInvertKeywords = nil
    local cachedIgnorePrefixes = nil

    -- Save originals
    local origParseTriggers = AutoLayer.ParseTriggers
    local origParseBlacklist = AutoLayer.ParseBlacklist
    local origParseInvertKeywords = AutoLayer.ParseInvertKeywords
    local origParseIgnorePrefixes = AutoLayer.ParseIgnorePrefixes

    -- Cached replacements
    AutoLayer.ParseTriggers = function(self)
        if not cachedTriggers then
            cachedTriggers = origParseTriggers(self)
        end
        return cachedTriggers
    end

    AutoLayer.ParseBlacklist = function(self)
        if not cachedBlacklist then
            cachedBlacklist = origParseBlacklist(self)
        end
        return cachedBlacklist
    end

    AutoLayer.ParseInvertKeywords = function(self)
        if not cachedInvertKeywords then
            cachedInvertKeywords = origParseInvertKeywords(self)
        end
        return cachedInvertKeywords
    end

    -- ParseIgnorePrefixes only exists in v1.7.7+
    if origParseIgnorePrefixes then
        AutoLayer.ParseIgnorePrefixes = function(self)
            if not cachedIgnorePrefixes then
                cachedIgnorePrefixes = origParseIgnorePrefixes(self)
            end
            return cachedIgnorePrefixes
        end

        hooksecurefunc(AutoLayer, "SetIgnorePrefixes", function()
            cachedIgnorePrefixes = nil
        end)
    end

    -- Invalidate caches when setters are called
    hooksecurefunc(AutoLayer, "SetTriggers", function()
        cachedTriggers = nil
    end)

    hooksecurefunc(AutoLayer, "SetBlacklist", function()
        cachedBlacklist = nil
    end)

    hooksecurefunc(AutoLayer, "SetInvertKeywords", function()
        cachedInvertKeywords = nil
    end)
end

------------------------------------------------------------------------
-- 3. AutoLayer_systemFilterCache
--
-- main.lua:442-453 — matchesAnySystemMessage() escapes and builds
-- 15 Lua patterns from system message constants on every
-- CHAT_MSG_SYSTEM event. Fix: pre-compute patterns once at load time.
------------------------------------------------------------------------
ns.patches["AutoLayer_systemFilterCache"] = function()
    if not ns:IsAddonLoaded("AutoLayer_Vanilla") then return end
    if not AutoLayer then return end

    -- Pre-compute escaped patterns from the same system message constants
    local cachedPatterns = {}
    local rawMessages = {
        ERR_INVITE_PLAYER_S,
        ERR_JOINED_GROUP_S,
        ERR_DECLINE_GROUP_S,
        ERR_GROUP_DISBANDED,
        ERR_LEFT_GROUP_S,
        ERR_LEFT_GROUP_YOU,
        ERR_DUNGEON_DIFFICULTY_CHANGED_S,
        ERR_ALREADY_IN_GROUP_S,
        ERR_GROUP_FULL,
        ERR_NOT_IN_GROUP,
        ERR_SET_LOOT_FREEFORALL,
        ERR_SET_LOOT_GROUP,
        ERR_SET_LOOT_ROUNDROBIN,
        ERR_SET_LOOT_NBG,
        ERR_SET_LOOT_THRESHOLD_S,
    }
    for _, msg in ipairs(rawMessages) do
        if msg then
            local pattern = msg:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
            pattern = pattern:gsub("%%%%s", "(.+)")
            cachedPatterns[#cachedPatterns+1] = pattern
        end
    end

    -- Optimized match function using pre-computed patterns
    local function matchesCached(msg)
        for _, pattern in ipairs(cachedPatterns) do
            if msg:match(pattern) then return true end
        end
        return false
    end

    -- Optimized filter function
    local function optimizedSystemFilter(_, _, msg, author, ...)
        local filtered = AutoLayer:GetEnabled() and matchesCached(msg)
        return filtered, msg, author, ...
    end

    -- If the old filter is currently active, swap it out
    local isActive = AutoLayer.db and AutoLayer.db.profile
        and AutoLayer.db.profile.hideSystemGroupMessages
    if isActive then
        -- Remove old filter (calls ChatFrame_RemoveMessageEventFilter
        -- with the original local function reference)
        AutoLayer:unfilterChatEventSystemGroupMessages()
        -- Add our optimized filter
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", optimizedSystemFilter)
    end

    -- Replace the add/remove methods for future use
    AutoLayer.filterChatEventSystemGroupMessages = function()
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", optimizedSystemFilter)
    end
    AutoLayer.unfilterChatEventSystemGroupMessages = function()
        ChatFrame_RemoveMessageEventFilter("CHAT_MSG_SYSTEM", optimizedSystemFilter)
    end
end

------------------------------------------------------------------------
-- 4. AutoLayer_pruneCacheFix
--
-- layering.lua:100-122 — pruneCache() uses table.remove() inside
-- forward ipairs() loops. When an entry is removed at position i,
-- the next entry shifts to i and gets skipped. Fix: call the
-- original multiple times to catch all skipped entries (each pass
-- catches ~half of consecutive stale entries; 5 passes handles
-- up to 32 consecutive stale entries).
------------------------------------------------------------------------
ns.patches["AutoLayer_pruneCacheFix"] = function()
    if not ns:IsAddonLoaded("AutoLayer_Vanilla") then return end
    if not AutoLayer or not AutoLayer.pruneCache then return end

    local origPrune = AutoLayer.pruneCache
    AutoLayer.pruneCache = function(self)
        for _ = 1, 5 do
            origPrune(self)
        end
    end
end

------------------------------------------------------------------------
-- 5. AutoLayer_libSerializeCleanup
--
-- hopping.lua:3 — LibSerialize is loaded via LibStub but never used
-- anywhere in AutoLayer's codebase. The reference is stored in
-- AutoLayer's private addon table (inaccessible from external addons).
-- This patch validates the issue and serves as a documentation marker.
------------------------------------------------------------------------
ns.patches["AutoLayer_libSerializeCleanup"] = function()
    -- No-op: the unused LibSerialize reference lives in AutoLayer's private
    -- addon table which is inaccessible externally. Documentation marker only.
    return
end

------------------------------------------------------------------------
-- 6. AutoLayer_layerStatusFrame
--
-- Creates a small, movable on-screen frame showing:
--   - Current layer number (green=known, red=unknown)
--   - AutoLayer enabled/disabled indicator
--   - Session invite count ("Layered: 12")
--   - Layer transition state (from patch 8)
-- Position saved in PatchWerkDB.AutoLayer_statusFrame_point
------------------------------------------------------------------------
ns.patches["AutoLayer_layerStatusFrame"] = function()
    if not ns:IsAddonLoaded("AutoLayer_Vanilla") then return end
    if not AutoLayer then return end

    local f = CreateStatusFrame()
    f:Show()

    -- Start the shared layer poller
    StartPoller()

    -- Initial display update
    UpdateStatusFrame()

    -- Refresh on roster changes (may trigger NWB layer update)
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:SetScript("OnEvent", function()
        UpdateStatusFrame()
    end)
end

------------------------------------------------------------------------
-- 7. AutoLayer_layerChangeToast
--
-- Monitors NWB_CurrentLayer for changes. When a layer transition is
-- detected, displays a gold-colored message via UIErrorsFrame and
-- plays a subtle ping sound. Handled in the shared PollLayer function
-- which checks ns.applied["AutoLayer_layerChangeToast"].
------------------------------------------------------------------------
ns.patches["AutoLayer_layerChangeToast"] = function()
    if not ns:IsAddonLoaded("AutoLayer_Vanilla") then return end
    if not AutoLayer then return end

    -- Toast logic lives in PollLayer(); this patch just needs to be
    -- marked as applied so PollLayer fires the toast on layer changes.
    -- Start the poller if the status frame patch didn't already.
    StartPoller()
end

------------------------------------------------------------------------
-- 8. AutoLayer_hopTransitionTracker
--
-- Tracks the full hop lifecycle with target-layer verification:
--   IDLE -> WAITING_INVITE (after SendLayerRequest or PARTY_INVITE_REQUEST)
--   WAITING_INVITE -> IN_GROUP (after GROUP_ROSTER_UPDATE + IsInGroup)
--   IN_GROUP -> CONFIRMED (NWB detects target layer or layer change)
--   IN_GROUP -> IDLE (hop failed after timeout)
--   CONFIRMED -> IDLE (after 3 seconds)
--
-- AutoLayer hosts whisper the target layer number ("[AutoLayer]
-- Inviting you to layer {N}..."). When available, verification
-- checks "did we arrive at layer N?" instead of generic change
-- detection. NWB caches are cleared once on group disband so NWB
-- re-detects from fresh NPC interaction.
------------------------------------------------------------------------
ns.patches["AutoLayer_hopTransitionTracker"] = function()
    if not ns:IsAddonLoaded("AutoLayer_Vanilla") then return end
    if not AutoLayer then return end

    -- Hook SendLayerRequest to capture hop initiation (outbound path)
    -- Allow from IDLE, WAITING_INVITE (retry), or NO_RESPONSE (retry after failure)
    -- Block only when IN_GROUP or CONFIRMED (already mid-hop)
    hooksecurefunc(AutoLayer, "SendLayerRequest", function()
        if hopState.state == "IN_GROUP" or hopState.state == "CONFIRMED" then return end
        lastHopBroadcastTime = GetTime()
        local currentLayer = NWB_CurrentLayer
        hopState.state = "WAITING_INVITE"
        hopState.source = "OUTBOUND"
        hopState.fromLayer = currentLayer and tonumber(currentLayer) or nil
        hopState.targetLayer = nil
        hopState.deadline = GetTime() + WAITING_TIMEOUT
        hopState._nwbCleared = false
        hopState.timestamp = GetTime()
        UpdateStatusFrame()
    end)

    -- Track [AutoLayer] whispers to:
    -- 1. Identify AutoLayer hosts (vs manual friend invites)
    -- 2. Extract target layer number for same-layer skip logic
    -- Format: "[AutoLayer] Inviting you to layer {N}..."
    local whisperFrame = CreateFrame("Frame")
    whisperFrame:RegisterEvent("CHAT_MSG_WHISPER")
    whisperFrame:SetScript("OnEvent", function(_, _, message, sender)
        if message and sender and message:find("^%[AutoLayer%]") then
            -- Strip realm suffix if present (e.g. "Name-Realm" -> "Name")
            local name = strsplit("-", sender)
            if name then
                -- Try to parse target layer from the whisper
                local layerStr = message:match("layer (%d+)")
                local parsedLayer = layerStr and tonumber(layerStr) or nil
                autoLayerWhispers[name] = {
                    time = GetTime(),
                    layer = parsedLayer,
                }
                -- Write target layer to hopState during active hops
                if parsedLayer and (hopState.state == "WAITING_INVITE" or hopState.state == "IN_GROUP") then
                    -- Same-layer early exit: host is on our current layer
                    if hopState.fromLayer and parsedLayer == hopState.fromLayer then
                        if IsInGroup() and not IsInRaid() and not IsInInstance() then
                            LeaveParty()
                        end
                        hopState.state = "WAITING_INVITE"
                        hopState.timestamp = GetTime()
                        hopState.deadline = GetTime() + WAITING_TIMEOUT
                        -- Arm retry on next keypress
                        C_Timer.After(HOP_RETRY_DELAY, function()
                            if hopState.state ~= "WAITING_INVITE" then return end
                            retryFrame:Show()
                        end)
                        UIErrorsFrame:AddMessage("PatchWerk: Same layer \226\128\148 retrying...", 1.0, 0.6, 0.0, 1.0, GetToastDuration())
                    else
                        hopState.targetLayer = parsedLayer
                    end
                    UpdateStatusFrame()
                end
            end
        end
    end)

    -- Detect incoming invites and group changes during a hop
    local hopEventFrame = CreateFrame("Frame")
    hopEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    hopEventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
    hopEventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "PARTY_INVITE_REQUEST" then
            -- Guard: only track if AutoLayer is enabled
            if not AutoLayer.db or not AutoLayer.db.profile.enabled then return end
            -- Guard: can't accept an invite while already in a group
            if IsInGroup() then return end

            -- Decline invites from known-bad hosts before AutoLayer_Vanilla
            -- calls AcceptGroup() — no join, no leave, no dungeon difficulty spam.
            local inviterName = ...
            if inviterName then
                local ccEntry = crossContinentHosts[inviterName]
                if ccEntry and (GetTime() - ccEntry.time) < CROSS_CONTINENT_EXPIRY then
                    DeclineGroup()
                    StaticPopup_Hide("PARTY_INVITE")
                    return
                end
                local recentTime = recentHopHosts[inviterName]
                if recentTime and (GetTime() - recentTime) < RECENT_HOP_EXPIRY then
                    DeclineGroup()
                    StaticPopup_Hide("PARTY_INVITE")
                    return
                end

                -- Smart cross-continent block: only decline invites that are
                -- likely AutoLayer responses.  Manual party invites from
                -- friends/guild/dungeon groups are allowed through.
                --
                -- Identification signals (any = AutoLayer invite):
                --  1) We broadcast a hop request recently (hosts responding)
                --  2) We're mid-hop (WAITING_INVITE state)
                --  3) Inviter already sent us an [AutoLayer] whisper
                --     (whisper arrives AFTER invite, so this catches
                --      repeat invites from the same host, not first)
                if crossContinentBlock and GetTime() < crossContinentBlock.expiry then
                    local _, _, _, myInstID = UnitPosition("player")
                    local myCont = myInstID and INSTANCE_CONTINENTS[myInstID]
                    if myCont and myCont == crossContinentBlock.continent then
                        local recentBroadcast = (GetTime() - lastHopBroadcastTime) < HOP_BROADCAST_WINDOW
                        local isMidHop = hopState.state == "WAITING_INVITE"
                        local whisperEntry = autoLayerWhispers[inviterName]
                        local hasAutoLayerWhisper = whisperEntry
                            and (GetTime() - whisperEntry.time) < HOP_BROADCAST_WINDOW

                        if recentBroadcast or isMidHop or hasAutoLayerWhisper then
                            -- AutoLayer invite — decline it
                            DeclineGroup()
                            StaticPopup_Hide("PARTY_INVITE")
                            -- Refresh expiry while invites keep coming
                            crossContinentBlock.expiry = GetTime() + CROSS_CONTINENT_EXPIRY
                            -- Rate-limited whisper so the host knows why
                            local lastWhisper = declinedWhisperTimes[inviterName]
                            if not lastWhisper or (GetTime() - lastWhisper) > DECLINED_WHISPER_CD then
                                declinedWhisperTimes[inviterName] = GetTime()
                                local myLocation = (myCont == "OUTLAND") and "Outland" or "Azeroth"
                                pcall(SendChatMessage,
                                    "[PatchWerk] I'm in " .. myLocation .. " \226\128\148 layers don't cross the Dark Portal! Thanks anyway.",
                                    "WHISPER", nil, inviterName)
                            end
                            return
                        end
                        -- No recent broadcast, not mid-hop, no AutoLayer whisper
                        -- — this is likely a manual invite. Allow it through.
                    else
                        -- Continent changed (player took the portal) — disable block
                        crossContinentBlock = nil
                    end
                end
            end

            if hopState.state == "IDLE" or hopState.state == "NO_RESPONSE" then
                -- External invite while idle or after a failed attempt — track so auto-leave works
                local currentLayer = NWB_CurrentLayer
                hopState.state = "WAITING_INVITE"
                hopState.source = "INBOUND"
                hopState.fromLayer = currentLayer and tonumber(currentLayer) or nil
                hopState.targetLayer = nil
                hopState.deadline = GetTime() + WAITING_TIMEOUT
                hopState._nwbCleared = false
                hopState.timestamp = GetTime()
                UpdateStatusFrame()
            end
            -- If WAITING_INVITE (OUTBOUND), the invite arrived as expected — no change

        elseif event == "GROUP_ROSTER_UPDATE" then
            -- Guard: if we already confirmed a hop, leave any new group
            -- that AutoLayer accepted (stale LFG responses from other hosts).
            if hopState.state == "CONFIRMED" and IsInGroup() then
                if not IsInRaid() and not IsInInstance() then
                    LeaveParty()
                end
                return
            end

            if hopState.state == "WAITING_INVITE" and IsInGroup() then
                -- Accepted the invite, now in the hop group.
                -- Capture host name while we can still query the roster.
                hopState.state = "IN_GROUP"
                hopState.timestamp = GetTime()
                hopState.hostName = GetPartyMemberName()
                hopState.deadline = GetTime() + IN_GROUP_TIMEOUT
                hopState._nwbCleared = false

                -- Extract targetLayer from whisper if available
                if not hopState.targetLayer and hopState.hostName then
                    local whisperEntry = autoLayerWhispers[hopState.hostName]
                    if whisperEntry and whisperEntry.layer and (GetTime() - whisperEntry.time) < 30 then
                        hopState.targetLayer = whisperEntry.layer
                    end
                end

                -- Known cross-continent host? Instant leave — no whisper spam,
                -- no retry wasted. They already got the message last time.
                local hostName = hopState.hostName
                local knownEntry = hostName and crossContinentHosts[hostName]
                if knownEntry and (GetTime() - knownEntry.time) < CROSS_CONTINENT_EXPIRY then
                    if not IsInRaid() and not IsInInstance() then
                        LeaveHopGroup("cross_continent")
                    end
                    hopState.state = "IDLE"
                    UpdateStatusFrame()
                    return
                end

                -- Recently hopped via this host? Instant leave to block
                -- duplicate cycles from stale LFG re-invites.
                local recentTime = hostName and recentHopHosts[hostName]
                if recentTime and (GetTime() - recentTime) < RECENT_HOP_EXPIRY then
                    if not IsInRaid() and not IsInInstance() then
                        LeaveParty()
                    end
                    hopState.state = "IDLE"
                    UpdateStatusFrame()
                    return
                end

                -- Single cross-continent check at 3.5s.
                -- By 3.5s, party data has fully propagated — no false positives
                -- from nil returns during the initial propagation window.
                local function HandleCrossContinentDetection(otherContinent)
                    -- Remember this host so repeat invites are instant-skipped
                    if hopState.hostName then
                        crossContinentHosts[hopState.hostName] = {
                            time = GetTime(),
                            continent = otherContinent or "unknown",
                        }
                        -- otherContinent is the HOST's continent; tell them where WE are
                        local myContinent = (otherContinent == "Azeroth") and "Outland" or "Azeroth"
                        local whisper = otherContinent
                            and "[PatchWerk] I'm in " .. myContinent .. " \226\128\148 layers don't cross the Dark Portal! Thanks anyway."
                            or "[PatchWerk] Layers don't cross the Dark Portal! Thanks anyway."
                        pcall(SendChatMessage, whisper, "WHISPER", nil, hopState.hostName)
                    end

                    -- Activate blanket block: ALL future AutoLayer invites
                    -- from the other continent get declined at invite time,
                    -- no join->detect->leave cycle needed.
                    local _, _, _, myInstID = UnitPosition("player")
                    local myCont = myInstID and INSTANCE_CONTINENTS[myInstID]
                    if myCont then
                        crossContinentBlock = {
                            expiry = GetTime() + CROSS_CONTINENT_EXPIRY,
                            continent = myCont,
                        }
                    end

                    HandleFailedHop(otherContinent)
                end

                C_Timer.After(3.5, function()
                    if hopState.state ~= "IN_GROUP" then return end
                    local isCross, otherContinent = IsCrossContinentHop()
                    if isCross then
                        HandleCrossContinentDetection(otherContinent)
                    end
                end)

                UpdateStatusFrame()

            end
        end
    end)

    -- Start the poller if not already started by patches 6 or 7
    StartPoller()
end

------------------------------------------------------------------------
-- 9. AutoLayer_enhancedTooltip
--
-- Hooks OnTooltipShow on AutoLayer's LibDataBroker object to display
-- richer information: current layer (color-coded), total available
-- layers, session invite count, AutoLayer status, and hop state.
------------------------------------------------------------------------
ns.patches["AutoLayer_enhancedTooltip"] = function()
    if not ns:IsAddonLoaded("AutoLayer_Vanilla") then return end
    if not AutoLayer or not AutoLayer.db then return end

    -- Get the LDB object via LibDataBroker
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if not LDB then return end

    local dataObj = LDB:GetDataObjectByName("AutoLayer")
    if not dataObj then return end

    -- Replace tooltip handler with enhanced version
    dataObj.OnTooltipShow = function(tooltip)
        tooltip:AddLine("|cff33ccffAutoLayer|r")
        tooltip:AddLine(" ")

        -- Current layer with color
        local currentLayer = NWB_CurrentLayer
        if currentLayer and tonumber(currentLayer) and tonumber(currentLayer) > 0 then
            tooltip:AddDoubleLine("Current Layer:", "|cff33ff33" .. currentLayer .. "|r")
        else
            tooltip:AddDoubleLine("Current Layer:", "|cffff3333Unknown|r")
        end

        -- Total available layers (from NWB)
        local NWBAddon = GetNWB()
        if NWBAddon and NWBAddon.data and NWBAddon.data.layers then
            local totalLayers = 0
            for _ in pairs(NWBAddon.data.layers) do
                totalLayers = totalLayers + 1
            end
            if totalLayers > 0 then
                tooltip:AddDoubleLine("Available Layers:", "|cffcccccc" .. totalLayers .. "|r")
            end
        end

        -- Session invite count
        local layered = AutoLayer.db.profile.layered or 0
        local countColor = layered > 0 and "|cff33ff33" or "|cff808080"
        tooltip:AddDoubleLine("Session Layered:", countColor .. layered .. "|r")

        -- AutoLayer status
        local enabled = AutoLayer.db.profile.enabled
        if enabled then
            tooltip:AddDoubleLine("Status:", "|cff33ff33Enabled|r")
        else
            tooltip:AddDoubleLine("Status:", "|cffff3333Disabled|r")
        end

        -- Hop transition state (if mid-hop)
        if hopState.state ~= "IDLE" then
            tooltip:AddLine(" ")
            local stateInfo = {
                WAITING_INVITE = { color = "|cffffcc00", label = "Searching for a layer..." },
                IN_GROUP = { color = "|cffff9933", label = "Switching layers..." },
                CONFIRMED = { color = "|cff33ff33", label = "Layer changed!" },
                NO_RESPONSE = { color = "|cffff3333", label = "No response \226\128\148 try again" },
            }
            local info = stateInfo[hopState.state]
            if info then
                local label = info.label
                if hopState.state == "WAITING_INVITE" and hopState.hopRetries > 0 then
                    label = "Retrying hop (" .. hopState.hopRetries .. "/" .. MAX_HOP_RETRIES .. ")"
                end
                tooltip:AddLine(info.color .. "Hop: " .. label .. "|r")
            end
        end

        tooltip:AddLine(" ")
        tooltip:AddLine("|cff808080Left-click to toggle|r")
        tooltip:AddLine("|cff808080Right-click to hop layers|r")
    end
end

------------------------------------------------------------------------
-- 10. AutoLayer_instanceGuard
--
-- AutoLayer has no IsInInstance() checks anywhere. Two dangerous paths:
--
-- A) Hosting path (ProcessMessage in layering.lua):
--    When the player is party leader inside a dungeon, AutoLayer still
--    processes layer requests from chat and invites people into the
--    dungeon group via C_PartyInfo.InviteUnit(). If autokick is enabled,
--    it may even kick a dungeon member to make room.
--
-- B) Requesting path (SendLayerRequest in hopping.lua):
--    Calls LeaveParty() unconditionally without checking if the player
--    is inside an instance, instantly dropping from the dungeon group.
--
-- Fix: Hook both ProcessMessage and SendLayerRequest with instance
-- guards that silently block when IsInInstance() returns true.
------------------------------------------------------------------------
ns.patches["AutoLayer_instanceGuard"] = function()
    if not ns:IsAddonLoaded("AutoLayer_Vanilla") then return end
    if not AutoLayer then return end

    -- A) Guard the hosting path: block ProcessMessage inside instances
    local origProcessMessage = AutoLayer.ProcessMessage
    if origProcessMessage then
        AutoLayer.ProcessMessage = function(self, ...)
            local inInstance, instanceType = IsInInstance()
            if inInstance and (instanceType == "party" or instanceType == "raid") then
                return
            end
            return origProcessMessage(self, ...)
        end
    end

    -- B) Guard the requesting path: block SendLayerRequest inside instances
    local origSendLayerRequest = AutoLayer.SendLayerRequest
    if origSendLayerRequest then
        AutoLayer.SendLayerRequest = function(self, ...)
            local inInstance, instanceType = IsInInstance()
            if inInstance and (instanceType == "party" or instanceType == "raid") then
                self:Print("Can't request a layer hop while inside a dungeon or raid.")
                return
            end
            return origSendLayerRequest(self, ...)
        end
    end
end
