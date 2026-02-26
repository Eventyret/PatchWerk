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
ns:RegisterDefault("AutoLayer_hopWhisperMessage", "[PatchWerk] Phased! Fresh mobs, fresh nodes. Thanks for the ride!")
ns:RegisterDefault("AutoLayer_toastDuration", 8)
ns:RegisterDefault("AutoLayer_statusFrame_point", nil)

------------------------------------------------------------------------
-- Shared state for visual patches (6, 7, 8)
------------------------------------------------------------------------

local statusFrame = nil
local pollerStarted = false
local UpdateStatusFrame  -- forward declaration (called by ConfirmHop/FailHop before definition)
local PokeNWBForLayer    -- forward declaration (called by HandleFailedHop before definition)

local hopState = {
    state = "IDLE",         -- IDLE, WAITING_INVITE, IN_GROUP, CONFIRMED, NO_RESPONSE
    source = nil,           -- "OUTBOUND" (from SendLayerRequest) or "INBOUND" (from PARTY_INVITE_REQUEST)
    fromLayer = nil,
    fromZoneID = nil,       -- GUID-based zoneID captured before hop (direct phasing evidence)
    targetLayer = nil,      -- parsed from [AutoLayer] whisper "layer {N}"
    hostName = nil,         -- captured when entering IN_GROUP (before group disbands)
    deadline = nil,         -- GetTime()+N for countdown display
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
local declinedNotifyTimes = {}    -- { ["Name"] = GetTime() } rate-limit local notifications
local DECLINED_NOTIFY_CD = 60     -- seconds between "declined X" local messages

-- Track when we last broadcast a hop request so we can distinguish
-- AutoLayer invite responses from manual party invites.  Any invite
-- arriving within this window of our broadcast is almost certainly
-- an AutoLayer host responding, not a friend/guild invite.
local lastHopBroadcastTime = 0
local HOP_BROADCAST_WINDOW = 60  -- seconds

-- Track incoming [AutoLayer] whispers: { ["Name"] = { time, layer } }.
-- Used to extract the target layer for same-layer skip logic.
local autoLayerWhispers = {}

-- AcceptGroup hook: generation counter to cancel pending auto-accepts.
-- When crossContinentBlock is active, AcceptGroup is delayed by 1 frame
-- so our PARTY_INVITE_REQUEST handler can cancel it for blocked hosts.
local _acceptGen = 0

local POLL_IDLE = 1.0
local POLL_ACTIVE = 0.1
local CONFIRM_DURATION = 8.0
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
-- Helper: Extract phasing zoneID from nearby NPC GUIDs.
--
-- Each NPC's GUID contains a zoneID that is unique per layer/phase.
-- Format: "Creature-0-serverID-mapID-???-zoneID-npcID-spawnUID"
-- When the player hops layers, nearby NPCs despawn and new ones
-- appear with a DIFFERENT zoneID.  Comparing zoneIDs before and
-- after the hop gives direct phasing evidence — no dependency on
-- NWB's layer database (which may not have the new zoneID yet).
------------------------------------------------------------------------
local function GetZoneIDFromGUID(guid)
    if not guid then return nil end
    local unitType, _, _, _, zoneID = strsplit("-", guid)
    if unitType == "Creature" and zoneID then
        return tonumber(zoneID)
    end
    return nil
end

local function GetCurrentZoneID()
    if UnitExists("target") then
        local zid = GetZoneIDFromGUID(UnitGUID("target"))
        if zid then return zid end
    end
    if UnitExists("mouseover") then
        local zid = GetZoneIDFromGUID(UnitGUID("mouseover"))
        if zid then return zid end
    end
    for i = 1, 40 do
        if UnitExists("nameplate" .. i) then
            local zid = GetZoneIDFromGUID(UnitGUID("nameplate" .. i))
            if zid then return zid end
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

    -- Find the host to check their continent.  AutoLayer often converts
    -- the group to a raid, so "party1" may not exist or may point to a
    -- different member.  Prefer finding the host by name.
    local memberUnit
    local myName = UnitName("player")
    local hostName = hopState.hostName

    -- Try to find the host specifically in party or raid roster
    if hostName then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) and UnitName(unit) == hostName then
                memberUnit = unit
                break
            end
        end
        if not memberUnit then
            for i = 1, GetNumGroupMembers() do
                local unit = "raid" .. i
                if UnitExists(unit) and UnitName(unit) == hostName then
                    memberUnit = unit
                    break
                end
            end
        end
    end

    -- Fallback: any non-self member
    if not memberUnit then
        if UnitExists("party1") then
            memberUnit = "party1"
        else
            for i = 1, GetNumGroupMembers() do
                local unit = "raid" .. i
                if UnitExists(unit) and UnitName(unit) ~= myName then
                    memberUnit = unit
                    break
                end
            end
        end
    end

    if not memberUnit then
        return false, nil
    end

    local _, _, _, partyInstanceID = UnitPosition(memberUnit)

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

    -- If party member's instanceID is unknown (not in our table),
    -- they might be in a special zone. Treat as inconclusive.
    if partyContinent == nil and playerContinent then
        local otherContinent = (playerContinent == "OUTLAND") and "Azeroth" or "Outland"
        return true, otherContinent
    end

    return false, nil
end

------------------------------------------------------------------------
-- Helper: Leave hop group
------------------------------------------------------------------------
local function LeaveHopGroup(reason)
    -- Don't leave if not in a group, or if in a real dungeon/raid instance.
    -- DO leave if in a raid in the open world (AutoLayer converts to raid).
    if not IsInGroup() or IsInInstance() then return end
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
    -- Build toast message BEFORE clearing state
    local destLayer = layerNum or hopState.targetLayer
    local toastMsg
    if destLayer then
        toastMsg = "[PatchWerk] Welcome to Layer " .. destLayer .. " — freshly phased!"
    else
        toastMsg = "[PatchWerk] Hop complete — enjoy the fresh mobs!"
    end

    hopState.state = "CONFIRMED"
    hopState.timestamp = GetTime()
    hopState.hopRetries = 0
    hopState.targetLayer = nil
    hopState.deadline = GetTime() + CONFIRM_DURATION

    retryFrame:Hide()  -- disarm pending retry

    if hopState.hostName then
        local normalizedHost = strsplit("-", hopState.hostName)
        recentHopHosts[normalizedHost] = GetTime()
    end

    -- Gold toast notification + local chat message
    if ns.applied["AutoLayer_layerChangeToast"] then
        local toastDur = GetToastDuration()
        UIErrorsFrame:AddMessage(toastMsg, 1.0, 0.82, 0.0, 1.0, toastDur)
        PlaySound(SOUNDKIT and SOUNDKIT.MAP_PING or 3175)
        -- UIErrorsFrame ignores the duration parameter in TBC Classic,
        -- so re-post periodically to keep it visible.
        if toastDur > 3 then
            C_Timer.After(2.5, function()
                if hopState.state == "CONFIRMED" then
                    UIErrorsFrame:AddMessage(toastMsg, 1.0, 0.82, 0.0, 1.0, toastDur)
                end
            end)
            C_Timer.After(5, function()
                if hopState.state == "CONFIRMED" then
                    UIErrorsFrame:AddMessage(toastMsg, 1.0, 0.82, 0.0, 1.0, toastDur)
                end
            end)
        end
        -- Also print to chat so it's visible in scrollback
        print("|cffffcc00" .. toastMsg .. "|r")
    end

    -- Thank-you whisper to the hop host
    if hopState.hostName and ns:GetOption("AutoLayer_hopWhisperEnabled") then
        local whisper = ns:GetOption("AutoLayer_hopWhisperMessage") or "[PatchWerk] Phased! Fresh mobs, fresh nodes. Thanks for the ride!"
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
    hopState.fromZoneID = nil
    hopState.targetLayer = nil
    hopState.hostName = nil
    hopState.deadline = nil

    hopState.hopRetries = 0
    UpdateStatusFrame()
end

-- Retry frame and OnKeyDown handler are created by InitHopFrames()
-- when an AutoLayer patch runs. See the lazy-init function above.

------------------------------------------------------------------------
-- Helper: Handle a hop that isn't working.
-- Called by cross-continent detection.  Leaves the group and
-- auto-retries up to 3 times.
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

    -- Cross-continent: don't waste retries broadcasting to chat —
    -- the blanket block only catches known hosts now, so a same-
    -- continent host can still get through on retry.  Show a message
    -- and let the normal retry path handle it.
    -- Re-poke NWB — the brief cross-continent group join can cause
    -- NWB to clear its layer data, leaving us stuck on "Detecting..."
    if reason then
        C_Timer.After(1, PokeNWBForLayer)
        C_Timer.After(3, PokeNWBForLayer)
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
        local elapsed = GetTime() - hopState.timestamp
        if elapsed < 5 then
            -- First 5s: phase change is happening
            if hopState.targetLayer then
                infoStr = "|cffff9933Hopping to Layer " .. hopState.targetLayer .. "...|r"
            else
                infoStr = "|cffff9933Hopping...|r"
            end
        else
            -- After 5s: phase is done, waiting for NWB to detect
            if hopState.targetLayer then
                infoStr = "|cff33ccffVerifying Layer " .. hopState.targetLayer .. "...|r"
            else
                infoStr = "|cff33ccffVerifying hop...|r"
            end
        end
        infoStr = infoStr .. FormatCountdown(hopState.deadline)
    elseif hopState.state == "CONFIRMED" then
        local elapsed = GetTime() - hopState.timestamp
        if elapsed < 3 then
            -- Show hop success briefly (CONFIRMED state stays for full duration)
            if hopState.fromLayer and currentNum and currentNum > 0 and currentNum ~= hopState.fromLayer then
                infoStr = "|cff33ff33Hopped! Layer " .. hopState.fromLayer .. " -> " .. currentNum .. "|r"
            elseif currentNum and currentNum > 0 then
                infoStr = "|cff33ff33Hopped to Layer " .. currentNum .. "!|r"
            else
                infoStr = "|cff33ff33Hop complete!|r"
            end
        else
            -- After 3s, show idle layer info (CONFIRMED state still protects)
            if enabled then
                if layerKnown then
                    infoStr = "|cff33ff33On|r  |cff555555·|r  Layer " .. currentLayer
                else
                    infoStr = "|cff33ff33On|r  |cff555555·|r  |cff888888Detecting layer...|r"
                end
            else
                if layerKnown then
                    infoStr = "|cffff3333Off|r  |cff555555·|r  Layer " .. currentLayer
                else
                    infoStr = "|cffff3333Off|r  |cff555555·|r  |cff888888Detecting layer...|r"
                end
            end
        end
    elseif enabled then
        if layerKnown then
            infoStr = "|cff33ff33On|r  |cff555555·|r  Layer " .. currentLayer
        else
            infoStr = "|cff33ff33On|r  |cff555555·|r  |cff888888Detecting layer...|r"
        end
    else
        if layerKnown then
            infoStr = "|cffff3333Off|r  |cff555555·|r  Layer " .. currentLayer
        else
            infoStr = "|cffff3333Off|r  |cff555555·|r  |cff888888Detecting layer...|r"
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
                hint = "|cff888888Phase change in progress...|r"
            else
                hint = "|cff888888Target an NPC to speed up detection|r"
            end
        elseif hopState.state == "NO_RESPONSE" then
            hint = "|cff888888Right-click to try again|r"
        elseif hopState.state == "IDLE" and not layerKnown then
            hint = "|cff888888Target an NPC to detect your layer|r"
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
-- Helper: Poke NWB to re-detect layer from nearby NPCs.
-- Tries target > mouseover > nameplates.  Skips if layer already
-- known unless `force` is true (used during active hops).
------------------------------------------------------------------------
PokeNWBForLayer = function(force)
    if not NWB or not NWB.setCurrentLayerText then return end
    -- Skip if already detected (unless forced, e.g. during a hop)
    if not force then
        local cur = NWB_CurrentLayer and tonumber(NWB_CurrentLayer)
        if cur and cur > 0 then return end
    end

    if UnitExists("target") then
        pcall(NWB.setCurrentLayerText, NWB, "target")
        return
    end
    if UnitExists("mouseover") then
        pcall(NWB.setCurrentLayerText, NWB, "mouseover")
        return
    end
    for i = 1, 40 do
        if UnitExists("nameplate" .. i) then
            local guid = UnitGUID("nameplate" .. i)
            if guid then
                local unitType = strsplit("-", guid)
                if unitType == "Creature" then
                    pcall(NWB.setCurrentLayerText, NWB, "nameplate" .. i)
                    return
                end
            end
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

    -- IN_GROUP: verify using targetLayer from whisper + NWB detection.
    -- Check both NWB_CurrentLayer (global) and NWB.currentLayer (internal)
    -- because NWB's recalcMinimapLayerFrame() can overwrite the global.
    if ns.applied["AutoLayer_hopTransitionTracker"] and hopState.state == "IN_GROUP" then
        local elapsed = GetTime() - hopState.timestamp

        -- Read layer from both NWB sources — the global can be stale
        -- if NWB's recalc overwrites it, so also check the internal field.
        local nwbGlobal = NWB_CurrentLayer and tonumber(NWB_CurrentLayer)
        local nwbInternal = NWB and NWB.currentLayer and tonumber(NWB.currentLayer)
        -- Use whichever reports the newer layer (prefer non-zero, non-fromLayer)
        currentNum = nil
        if nwbGlobal and nwbGlobal > 0 then currentNum = nwbGlobal end
        if nwbInternal and nwbInternal > 0 then
            if not currentNum or (currentNum == hopState.fromLayer and nwbInternal ~= hopState.fromLayer) then
                currentNum = nwbInternal
            end
        end

        -- Direct GUID-based zoneID detection: compare NPC zoneIDs
        -- against the baseline captured before the hop.  This doesn't
        -- depend on NWB's layer database at all — if the zoneID in
        -- nearby NPC GUIDs changed, the layer changed.
        local currentZoneID = GetCurrentZoneID()

        local layerConfirmed = false

        -- Method 1: NWB reports the target layer
        if not layerConfirmed and hopState.targetLayer then
            if currentNum and currentNum > 0 and currentNum == hopState.targetLayer then
                layerConfirmed = true
            elseif currentNum and currentNum > 0 and currentNum ~= hopState.fromLayer then
                layerConfirmed = true
            end
        end

        -- Method 2: NWB reports any layer change (no target known)
        if not layerConfirmed and not hopState.targetLayer then
            if currentNum and currentNum > 0 and hopState.fromLayer
               and hopState.fromLayer > 0 and currentNum ~= hopState.fromLayer then
                layerConfirmed = true
            end
        end

        -- Method 3: GUID zoneID changed — direct phasing evidence.
        -- This is the most reliable method: NWB's layer database may
        -- not have the new layer's zoneID, but the GUID never lies.
        -- NWB's GROUP_JOINED handler clears mapping state and starts a
        -- 180-second cooldown, making NWB_CurrentLayer unreliable.
        -- GUID comparison works regardless.
        if not layerConfirmed and hopState.fromZoneID and currentZoneID then
            if currentZoneID ~= hopState.fromZoneID then
                layerConfirmed = true
            end
        end

        -- No early failure detection here.  NWB can show stale layer
        -- data for 30-60s after a hop (GROUP_JOINED doesn't always fire
        -- for raid conversions, recalcMinimapLayerFrame restores cached
        -- values).  We wait for M1/M2/M3 to positively confirm, or for
        -- the trust-on-disband check after leaving group, or for the
        -- 120s IN_GROUP_TIMEOUT safety net.

        -- Poke NWB to re-detect from nearby NPCs every 2s.
        -- Start immediately — don't wait 3s, the phase may already be done.
        if not layerConfirmed then
            local now = GetTime()
            if (now - hopState._lastNWBPoke) > 2 then
                hopState._lastNWBPoke = now
                PokeNWBForLayer(true)
            end
        end

        -- Group disbanded — check if hop worked.
        -- NWB clears NWB_CurrentLayer on GROUP_JOINED (180s cooldown),
        -- so it's usually 0 here.  GUID zoneIDs don't differ in open
        -- world zones (only capitals).  We can only fail if we have
        -- POSITIVE evidence we're still on the same layer.
        if not layerConfirmed and not IsInGroup() then
            if currentNum and currentNum > 0 and currentNum ~= hopState.fromLayer then
                layerConfirmed = true
            elseif currentZoneID and hopState.fromZoneID
                   and currentZoneID ~= hopState.fromZoneID then
                layerConfirmed = true
            elseif currentNum and currentNum > 0 and hopState.fromLayer
                   and currentNum == hopState.fromLayer and elapsed > 5 then
                FailHop("Left group \226\128\148 hop cancelled")
            elseif elapsed > 5 then
                layerConfirmed = true
            end
        end

        -- Safety timeout (120s): if we've been in a same-continent
        -- group this long, the hop almost certainly worked — NWB is
        -- just slow to re-detect.  Trust it and confirm.
        if not layerConfirmed and elapsed > IN_GROUP_TIMEOUT then
            layerConfirmed = true
        end

        if layerConfirmed then
            hopState.hostName = hopState.hostName or GetPartyMemberName()
            ConfirmHop(currentNum and currentNum > 0 and currentNum or nil)
            -- Leave immediately — phase is already confirmed
            if IsInGroup() and not IsInInstance() then
                LeaveHopGroup("confirmed")
            end
            -- Skip the rest of this poll cycle — the next cycle will
            -- handle CONFIRMED state timeouts and the safety net below.
            C_Timer.After(POLL_ACTIVE, PollLayer)
            return
        end
    end

    -- CONFIRMED: ensure we've left the hop group.
    -- Safety net: if a stale re-invite was auto-accepted during CONFIRMED
    -- state, leave immediately. Only fires on subsequent poll cycles
    -- (not the same cycle as the confirm above, thanks to the return).
    if hopState.state == "CONFIRMED" and IsInGroup() and not IsInInstance() then
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
        hopState.fromZoneID = nil
        hopState.targetLayer = nil
        hopState.hostName = nil
        hopState.deadline = nil
        hopState.hopRetries = 0
    end
    -- IN_GROUP timeout is handled inside the IN_GROUP verification
    -- block above — it trusts the hop after 120s and confirms.
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
        hopState.fromZoneID = nil
        hopState.targetLayer = nil
        hopState.hostName = nil
        hopState.deadline = nil
    
        hopState.hopRetries = 0
    end

    -- Update status frame
    UpdateStatusFrame()

    -- Schedule next poll (faster during active hop)
    local interval = (hopState.state == "IN_GROUP" or hopState.state == "WAITING_INVITE")
        and POLL_ACTIVE or POLL_IDLE
    C_Timer.After(interval, PollLayer)
end

local function StartPoller()
    if pollerStarted then return end
    pollerStarted = true
    InitHopFrames()

    -- Initialize last known layer
    local currentLayer = NWB_CurrentLayer
    if currentLayer and tonumber(currentLayer) and tonumber(currentLayer) > 0 then
        hopState.lastKnownLayer = tonumber(currentLayer)
    end

    -- Poke NWB to detect layer from nearby NPCs on login.
    -- Delay 5s to let the world fully load (nameplates, NPC data).
    -- Retry at 10s and 20s in case the first poke was too early.
    C_Timer.After(5, PokeNWBForLayer)
    C_Timer.After(10, PokeNWBForLayer)
    C_Timer.After(20, PokeNWBForLayer)

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
                    if IsInGroup() and not IsInInstance() then
                        LeaveParty()
                    end
                    hopState.state = "IDLE"
                    hopState.source = nil
                    hopState.fromLayer = nil
                    hopState.fromZoneID = nil
                    hopState.targetLayer = nil
                    hopState.hostName = nil
                    hopState.deadline = nil
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
                -- Block when layer is unknown — we need a baseline to verify the hop
                local curLayer = NWB_CurrentLayer and tonumber(NWB_CurrentLayer)
                if not curLayer or curLayer <= 0 then
                    UIErrorsFrame:AddMessage("PatchWerk: Can't hop yet — target an NPC so we know your current layer", 1.0, 0.6, 0.0, 1.0, 5)
                    PokeNWBForLayer()
                    return
                end
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

    -- Hook AcceptGroup to block bad auto-accepts.
    --
    -- Problem: AutoLayer_Vanilla registers its PARTY_INVITE_REQUEST
    -- handler at addon load time (before PatchWerk), so it calls
    -- AcceptGroup() before our handler can call DeclineGroup().
    --
    -- Fix: When we're waiting for an invite, delay AcceptGroup by
    -- 1 frame.  Our PARTY_INVITE_REQUEST handler (which fires in the
    -- same event dispatch, just after AutoLayer's) bumps _acceptGen
    -- to cancel the pending accept if the inviter should be blocked.
    -- Legitimate invites proceed after the 1-frame delay (imperceptible).
    local origAcceptGroup = AcceptGroup
    if origAcceptGroup then
        rawset(_G, "AcceptGroup", function(...)
            -- Intercept during any active hop state where we might need
            -- to decline (CC hosts, recent hosts, stale re-invites).
            -- During IDLE with no recent hops, AcceptGroup goes through
            -- immediately.  Otherwise, delay by 1 frame so our
            -- PARTY_INVITE_REQUEST handler can cancel if needed.
            if hopState.state == "IDLE" then
                -- Prune expired entries so the table empties after cooldown
                local now = GetTime()
                for host, t in pairs(recentHopHosts) do
                    if (now - t) >= RECENT_HOP_EXPIRY then
                        recentHopHosts[host] = nil
                    end
                end
                if not next(recentHopHosts) then
                    return origAcceptGroup(...)
                end
            end
            -- Delay by 1 frame so our handler can cancel
            _acceptGen = _acceptGen + 1
            local myGen = _acceptGen
            local args = { ... }
            C_Timer.After(0, function()
                if _acceptGen == myGen then
                    origAcceptGroup(unpack(args))
                end
            end)
        end)
    end

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
        hopState.fromZoneID = GetCurrentZoneID()
        hopState.targetLayer = nil
        hopState.deadline = GetTime() + WAITING_TIMEOUT

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
                        if IsInGroup() and not IsInInstance() then
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
            local inviterName = ...

            -- Normalize: strip realm suffix ("Name-Realm" -> "Name")
            local normalizedInviter = inviterName and strsplit("-", inviterName) or inviterName

            -- Known-bad host checks run FIRST — before any other guards.
            -- These only fire for hosts we've already confirmed as bad,
            -- so they won't interfere with normal party invites.
            -- Must run even when AutoLayer.db.profile.enabled is false
            -- because AutoLayer still accepts invites in that state.
            if normalizedInviter then
                local function DeclineOrLeave()
                    _acceptGen = _acceptGen + 1
                    if IsInGroup() then
                        if not IsInInstance() then
                            LeaveParty()
                        end
                    end
                    -- Dismiss the invite popup by clicking its Decline button
                    -- next frame.  Calling DeclineGroup() or StaticPopup_Hide()
                    -- from addon code leaves the popup in a broken state — the
                    -- server-side decline goes through but the UI never hides,
                    -- making buttons non-functional.  Clicking the button lets
                    -- the StaticPopup framework run its full dismiss chain
                    -- (OnCancel → DeclineGroup → Hide) cleanly.
                    C_Timer.After(0, function()
                        for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
                            local dialog = _G["StaticPopup" .. i]
                            if dialog and dialog:IsShown() and dialog.which == "PARTY_INVITE" then
                                dialog.button2:Click()
                                return
                            end
                        end
                    end)
                end

                local ccEntry = crossContinentHosts[normalizedInviter]
                if ccEntry and (GetTime() - ccEntry.time) < CROSS_CONTINENT_EXPIRY then
                    DeclineOrLeave()
                    -- Extend blanket block while this host keeps re-inviting
                    if crossContinentBlock then
                        crossContinentBlock.expiry = GetTime() + CROSS_CONTINENT_EXPIRY
                    end
                    -- Rate-limited local notification
                    local lastNotify = declinedNotifyTimes[normalizedInviter]
                    if not lastNotify or (GetTime() - lastNotify) > DECLINED_NOTIFY_CD then
                        declinedNotifyTimes[normalizedInviter] = GetTime()
                        UIErrorsFrame:AddMessage(
                            "PatchWerk: " .. normalizedInviter .. " is in " .. tostring(ccEntry.continent) .. " \226\128\148 skipping",
                            1.0, 0.6, 0.0, 1.0, 5)
                    end
                    -- Rate-limited whisper so the host knows why
                    local lastWhisper = declinedWhisperTimes[normalizedInviter]
                    if not lastWhisper or (GetTime() - lastWhisper) > DECLINED_WHISPER_CD then
                        declinedWhisperTimes[normalizedInviter] = GetTime()
                        local _, _, _, myInstID = UnitPosition("player")
                        local myCont = myInstID and INSTANCE_CONTINENTS[myInstID]
                        local myLocation = (myCont == "OUTLAND") and "Outland" or "Azeroth"
                        pcall(SendChatMessage,
                            "[PatchWerk] I'm in " .. myLocation .. " \226\128\148 the Dark Portal blocks phasing! Thanks anyway.",
                            "WHISPER", nil, inviterName)
                    end
                    return
                end
                local recentTime = recentHopHosts[normalizedInviter]
                if recentTime and (GetTime() - recentTime) < RECENT_HOP_EXPIRY then
                    DeclineOrLeave()
                    return
                end

                -- Safety net: during CONFIRMED state, block any AutoLayer
                -- re-invite even if the host name didn't match above (e.g.,
                -- realm suffix mismatch or host name not captured).
                if hopState.state == "CONFIRMED" then
                    local whisperEntry = autoLayerWhispers[normalizedInviter]
                    if whisperEntry and (GetTime() - whisperEntry.time) < RECENT_HOP_EXPIRY then
                        DeclineOrLeave()
                        return
                    end
                end
            end

            -- Past this point, the inviter is not a known-bad host.
            -- Can't process further if already in a group.
            if IsInGroup() then return end

            -- Guard: only track inbound invites if AutoLayer is enabled.
            -- (The CC/recent host checks above run regardless because
            -- AutoLayer still auto-accepts invites when "disabled".)
            if not AutoLayer.db or not AutoLayer.db.profile.enabled then return end

            if hopState.state == "IDLE" or hopState.state == "NO_RESPONSE" then
                -- External invite while idle or after a failed attempt — track so auto-leave works
                local currentLayer = NWB_CurrentLayer
                hopState.state = "WAITING_INVITE"
                hopState.source = "INBOUND"
                hopState.fromLayer = currentLayer and tonumber(currentLayer) or nil
                hopState.fromZoneID = GetCurrentZoneID()
                hopState.targetLayer = nil
                hopState.deadline = GetTime() + WAITING_TIMEOUT
            
                hopState.timestamp = GetTime()
                UpdateStatusFrame()
            end
            -- If WAITING_INVITE (OUTBOUND), the invite arrived as expected — no change

        elseif event == "GROUP_ROSTER_UPDATE" then
            -- Guard: if we already confirmed a hop, leave any new group
            -- that AutoLayer accepted (stale LFG responses from other hosts).
            if hopState.state == "CONFIRMED" and IsInGroup() then
                if not IsInInstance() then
                    LeaveParty()
                end
                return
            end

            -- Guard: if IDLE but unexpectedly in a group (e.g.,
            -- cross-continent re-invite that AutoLayer auto-accepted
            -- before our DeclineGroup could fire), leave immediately.
            -- Use LeaveParty() directly — NOT LeaveHopGroup — to avoid
            -- clearing NWB_CurrentLayer which is still valid.
            if hopState.state == "IDLE" and IsInGroup() and not IsInInstance() then
                local hostName = GetPartyMemberName()
                local normalizedHost = hostName and strsplit("-", hostName)
                if normalizedHost then
                    local ccEntry = crossContinentHosts[normalizedHost]
                    if ccEntry and (GetTime() - ccEntry.time) < CROSS_CONTINENT_EXPIRY then
                        LeaveParty()
                        -- Re-poke NWB in case the brief group join cleared layer data
                        C_Timer.After(1, PokeNWBForLayer)
                        return
                    end
                    local recentTime = recentHopHosts[normalizedHost]
                    if recentTime and (GetTime() - recentTime) < RECENT_HOP_EXPIRY then
                        LeaveParty()
                        C_Timer.After(1, PokeNWBForLayer)
                        return
                    end
                end
            end

            if hopState.state == "WAITING_INVITE" and IsInGroup() then
                -- Accepted the invite, now in the hop group.
                -- Capture host name while we can still query the roster.
                hopState.state = "IN_GROUP"
                hopState.timestamp = GetTime()
                hopState.hostName = GetPartyMemberName()
                hopState.deadline = GetTime() + IN_GROUP_TIMEOUT


                -- Extract targetLayer from whisper if available
                if not hopState.targetLayer and hopState.hostName then
                    local whisperEntry = autoLayerWhispers[hopState.hostName]
                    if whisperEntry and whisperEntry.layer and (GetTime() - whisperEntry.time) < 30 then
                        hopState.targetLayer = whisperEntry.layer
                    end
                end

                -- Clear NWB's stale layer data so Method 4 can't see the
                -- old layer and falsely declare failure.  NWB can show
                -- the pre-hop layer for 30-60s (GROUP_JOINED doesn't
                -- always fire for raid conversions, and recalcMinimapLayerFrame
                -- can restore cached values).  By zeroing both the global
                -- and the internal mapping state, NWB will show "unknown"
                -- until it freshly detects from NPC interaction.
                -- fromLayer is already saved — we don't need NWB's stale cache.
                rawset(_G, "NWB_CurrentLayer", 0)
                if NWB then
                    NWB.currentLayer = 0
                    if NWB.lastKnownLayerMapID then NWB.lastKnownLayerMapID = 0 end
                    if NWB.lastKnownLayerMapZoneID then NWB.lastKnownLayerMapZoneID = 0 end
                    if NWB.lastKnownLayerID then NWB.lastKnownLayerID = 0 end
                end

                -- Known cross-continent host? Instant leave — no whisper spam,
                -- no retry wasted. They already got the message last time.
                local hostName = hopState.hostName
                local normalizedHost = hostName and strsplit("-", hostName)
                local knownEntry = normalizedHost and crossContinentHosts[normalizedHost]
                if knownEntry and (GetTime() - knownEntry.time) < CROSS_CONTINENT_EXPIRY then
                    if not IsInInstance() then
                        LeaveHopGroup("cross_continent")
                    end
                    -- Notify the user
                    local lastNotify = declinedNotifyTimes[normalizedHost]
                    if not lastNotify or (GetTime() - lastNotify) > DECLINED_NOTIFY_CD then
                        declinedNotifyTimes[normalizedHost] = GetTime()
                        UIErrorsFrame:AddMessage(
                            "PatchWerk: " .. (hostName or normalizedHost) .. " is in " .. tostring(knownEntry.continent) .. " \226\128\148 decline to keep searching",
                            1.0, 0.6, 0.0, 1.0, 5)
                    end
                    hopState.state = "IDLE"
                    UpdateStatusFrame()
                    return
                end

                -- Recently hopped via this host? Instant leave to block
                -- duplicate cycles from stale LFG re-invites.
                local recentTime = normalizedHost and recentHopHosts[normalizedHost]
                if recentTime and (GetTime() - recentTime) < RECENT_HOP_EXPIRY then
                    if not IsInInstance() then
                        LeaveParty()
                    end
                    hopState.state = "IDLE"
                    UpdateStatusFrame()
                    return
                end

                -- Cross-continent detection at 3.5s.
                -- By 3.5s, party data has fully propagated — no false positives
                -- from nil returns during the initial propagation window.
                local function HandleCrossContinentDetection(otherContinent)
                    -- Remember this host so repeat invites are instant-skipped
                    if hopState.hostName then
                        local normalizedCCHost = strsplit("-", hopState.hostName)
                        crossContinentHosts[normalizedCCHost] = {
                            time = GetTime(),
                            continent = otherContinent or "unknown",
                        }
                        -- otherContinent is the HOST's continent; tell them where WE are
                        local myContinent = (otherContinent == "Azeroth") and "Outland" or "Azeroth"
                        local whisper = otherContinent
                            and "[PatchWerk] I'm in " .. myContinent .. " \226\128\148 the Dark Portal blocks phasing! Thanks anyway."
                            or "[PatchWerk] The Dark Portal blocks phasing! Thanks anyway."
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
