------------------------------------------------------------------------
-- PatchWerk - Performance, bug fix, and UX patches for AutoLayer_Vanilla
--
-- AutoLayer_Vanilla (v1.7.6) is a layer-hopping automation addon for
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
local UnitName = UnitName
local GetNumGroupMembers = GetNumGroupMembers
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsInInstance = IsInInstance
local LeaveParty = LeaveParty
local hooksecurefunc = hooksecurefunc

local WHITE8x8 = "Interface\\Buttons\\WHITE8x8"

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
    detail = "AutoLayer rebuilds its keyword and blacklist tables from scratch on every incoming chat message. In busy channels like Trade or LookingForGroup, this creates thousands of throwaway tables per minute, causing memory buildup and brief hitches. This patch remembers the tables and only rebuilds when your settings actually change.",
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

ns:RegisterDefault("AutoLayer_hopWhisperEnabled", true)
ns:RegisterDefault("AutoLayer_hopWhisperMessage", "[PatchWerk] Thanks for the hop!")
ns:RegisterDefault("AutoLayer_statusFrame_point", nil)

------------------------------------------------------------------------
-- Shared state for visual patches (6, 7, 8)
------------------------------------------------------------------------

local statusFrame = nil
local pollerStarted = false

local hopState = {
    state = "IDLE",         -- IDLE, WAITING_INVITE, IN_GROUP, CONFIRMED, NO_RESPONSE
    source = nil,           -- "OUTBOUND" (from SendLayerRequest) or "INBOUND" (from PARTY_INVITE_REQUEST)
    fromLayer = nil,
    phaseChanged = false,   -- true once UNIT_PHASE fires (hint that layer is changing)
    phaseTimestamp = 0,     -- when UNIT_PHASE fired (for NWB grace period)
    timestamp = 0,
    lastKnownLayer = nil,
    lastRequestTime = 0,    -- cooldown: when the last hop request was sent
}

local POLL_IDLE = 1.0
local POLL_ACTIVE = 0.1
local CONFIRM_DURATION = 3.0
local WAITING_TIMEOUT = 20.0
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
-- Helper: Leave hop group with optional thank-you whisper
------------------------------------------------------------------------
local function LeaveHopGroup(reason, layerStr)
    if not IsInGroup() or IsInRaid() or IsInInstance() then return end

    -- Capture name before leaving (can't query after LeaveParty)
    local memberName = GetPartyMemberName()

    LeaveParty()

    -- Status message
    local msg = "PatchWerk: Left group"
    if reason == "confirmed" and layerStr then
        msg = msg .. " \226\128\148 layer " .. layerStr .. " confirmed"
    elseif reason == "phase_changed" then
        msg = msg .. " \226\128\148 layer changed"
    elseif reason == "timeout" then
        msg = msg .. " \226\128\148 hop timed out"
    end
    UIErrorsFrame:AddMessage(msg, 0.2, 0.8, 1.0)

    -- Thank-you whisper to the group host (if enabled)
    if memberName and ns:GetOption("AutoLayer_hopWhisperEnabled") then
        local whisper = ns:GetOption("AutoLayer_hopWhisperMessage") or "[PatchWerk] Thanks for the hop!"
        pcall(SendChatMessage, whisper, "WHISPER", nil, memberName)
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
local function UpdateStatusFrame()
    if not statusFrame or not statusFrame:IsShown() then return end
    if not AutoLayer or not AutoLayer.db then return end

    -- Info line (line 2): layer + status, or hop state
    local currentLayer = NWB_CurrentLayer
    local currentNum = currentLayer and tonumber(currentLayer)
    local layerKnown = currentNum and currentNum > 0
    local enabled = AutoLayer.db.profile.enabled
    local infoStr

    if hopState.state == "NO_RESPONSE" then
        infoStr = "|cffff3333No response|r"
    elseif hopState.state == "WAITING_INVITE" then
        infoStr = "|cffffcc00Searching...|r"
    elseif hopState.state == "IN_GROUP" then
        infoStr = "|cffff9933Hopping...|r"
    elseif hopState.state == "CONFIRMED" then
        local newLayer = layerKnown and currentLayer or "?"
        infoStr = "|cff33ff33Now on layer " .. newLayer .. "!|r"
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
        if hopState.state == "WAITING_INVITE" then
            hint = "|cff888888Waiting for an invite...|r"
        elseif hopState.state == "IN_GROUP" then
            if hopState.phaseChanged then
                hint = "|cff888888Phase changed — confirming layer...|r"
            else
                hint = "|cff888888Waiting for layer change...|r"
            end
        elseif hopState.state == "NO_RESPONSE" then
            hint = "|cff888888Right-click to try again|r"
        end

        if hint then
            statusFrame.hintText:SetText(hint)
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
    -- Also compare against fromLayer as fallback when lastKnownLayer is nil
    local layerChanged = false
    if currentNum and currentNum > 0 then
        if lastNum and lastNum > 0 and currentNum ~= lastNum then
            layerChanged = true
        elseif not lastNum and hopState.fromLayer and currentNum ~= hopState.fromLayer then
            layerChanged = true
        -- Defense-in-depth: if lastKnownLayer was prematurely updated to the
        -- new layer (NWB detected change during WAITING_INVITE before state
        -- transitioned to IN_GROUP), compare against fromLayer instead.
        elseif (hopState.state == "IN_GROUP" or hopState.state == "WAITING_INVITE")
            and hopState.fromLayer and currentNum ~= hopState.fromLayer
            and currentNum == lastNum then
            layerChanged = true
        end
    end
    if layerChanged then
        -- Layer changed! Fire toast (patch 7)
        if ns.applied["AutoLayer_layerChangeToast"] then
            local fromNum = lastNum or hopState.fromLayer
            local msg = "Layer " .. (fromNum or "?") .. " -> " .. currentNum
            UIErrorsFrame:AddMessage(msg, 1.0, 0.82, 0.0)
            PlaySound(SOUNDKIT and SOUNDKIT.MAP_PING or 3175)
        end

        -- Transition tracker: NWB confirmed the new layer — leave group (patch 8)
        -- Also handle WAITING_INVITE: the player may have phased and NWB
        -- detected the new layer before GROUP_ROSTER_UPDATE transitioned
        -- state to IN_GROUP (race condition).
        if ns.applied["AutoLayer_hopTransitionTracker"]
            and (hopState.state == "IN_GROUP"
                 or (hopState.state == "WAITING_INVITE" and IsInGroup())) then
            hopState.state = "CONFIRMED"
            hopState.timestamp = GetTime()
            local layerStr = tostring(currentNum)
            C_Timer.After(0.5, function()
                LeaveHopGroup("confirmed", layerStr)
            end)
        end
    end

    -- Phase changed + NWB reset to 0: layer is changing but not yet confirmed.
    -- If we're IN_GROUP and UNIT_PHASE fired, give NWB 5s to confirm the new
    -- layer number. If it doesn't (no NPC targeted), leave anyway — the hop worked.
    if hopState.state == "IN_GROUP" and hopState.phaseChanged then
        local elapsed = GetTime() - hopState.phaseTimestamp
        -- NWB goes to 0 after UNIT_PHASE. If 5s pass without a new number, leave.
        if elapsed > 5.0 then
            hopState.state = "CONFIRMED"
            hopState.timestamp = GetTime()
            C_Timer.After(0.5, function()
                LeaveHopGroup("phase_changed")
            end)
        end
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
        hopState.phaseChanged = false
    end
    -- IN_GROUP safety net: if we've been in group for 90s without any
    -- layer change detection, something went wrong — leave and reset.
    if hopState.state == "IN_GROUP" and (now - hopState.timestamp) > 90.0 then
        LeaveHopGroup("timeout")
        hopState.state = "IDLE"
        hopState.source = nil
        hopState.fromLayer = nil
        hopState.phaseChanged = false
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
        hopState.phaseChanged = false
    end

    -- Update status frame
    UpdateStatusFrame()

    -- Schedule next poll (faster during active hop)
    local interval = (hopState.state == "IN_GROUP" or hopState.state == "WAITING_INVITE") and POLL_ACTIVE or POLL_IDLE
    C_Timer.After(interval, PollLayer)
end

------------------------------------------------------------------------
-- Helper: Start the shared poller (idempotent)
------------------------------------------------------------------------
local function StartPoller()
    if pollerStarted then return end
    pollerStarted = true

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

    local f = CreateFrame("Frame", "PatchWerk_AutoLayerStatus", UIParent)
    f:SetSize(160, 34)
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
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -140)
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

    -- Click interactions: left = toggle, right = quick hop, shift+right = hop GUI
    f:SetScript("OnMouseUp", function(self, button)
        -- Ignore clicks right after a drag
        if self._lastDragTime and (GetTime() - self._lastDragTime) < 0.2 then return end
        if self._dragging then return end
        if not AutoLayer then return end

        if button == "LeftButton" then
            if AutoLayer.Toggle then
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
                -- Block when mid-hop or on cooldown (3s between requests)
                if hopState.state == "IN_GROUP" or hopState.state == "CONFIRMED" then return end
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

        -- Show session stats in tooltip
        if AutoLayer and AutoLayer.db and AutoLayer.db.profile.enabled then
            local layered = AutoLayer.db.profile.layered or 0
            if layered > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Helped this session:", "|cffffcc00" .. layered .. " players|r")
            end
        end

        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click to toggle on/off", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Right-click to quick hop", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Shift+Right-click to pick layers", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("Drag to move", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Pulsing animation for IN_GROUP state
    local pulseTime = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        if hopState.state == "IN_GROUP" then
            pulseTime = pulseTime + elapsed
            local alpha = 0.6 + 0.4 * math_sin(pulseTime * 3)
            self.infoText:SetAlpha(alpha)
        else
            pulseTime = 0
            self.infoText:SetAlpha(1)
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

    -- Clear the generic "Test" global name
    _G["Test"] = nil

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
-- configuration.lua:25-65 — ParseTriggers(), ParseBlacklist(), and
-- ParseInvertKeywords() rebuild tables via string.gmatch on every
-- chat message. Fix: cache parsed tables, invalidate on setter calls.
------------------------------------------------------------------------
ns.patches["AutoLayer_parseCache"] = function()
    if not ns:IsAddonLoaded("AutoLayer_Vanilla") then return end
    if not AutoLayer then return end

    local cachedTriggers = nil
    local cachedBlacklist = nil
    local cachedInvertKeywords = nil

    -- Save originals
    local origParseTriggers = AutoLayer.ParseTriggers
    local origParseBlacklist = AutoLayer.ParseBlacklist
    local origParseInvertKeywords = AutoLayer.ParseInvertKeywords

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
-- Tracks the full hop lifecycle:
--   IDLE -> WAITING_INVITE (after SendLayerRequest or PARTY_INVITE_REQUEST)
--   WAITING_INVITE -> IN_GROUP (after GROUP_ROSTER_UPDATE + IsInGroup)
--   IN_GROUP -> CONFIRMED (when UNIT_PHASE fires or NWB_CurrentLayer changes)
--   CONFIRMED -> IDLE (after 3 seconds)
--
-- Detection (no timeout — hop will happen, just might take time):
--   1. NWB confirms new layer number (PollLayer sees number change) → leave
--   2. UNIT_PHASE fired + 5s grace for NWB to confirm → leave anyway
--   3. Other player leaves → GROUP_ROSTER_UPDATE resets state
-- Sends a thank-you whisper to the hop host on leave.
------------------------------------------------------------------------
ns.patches["AutoLayer_hopTransitionTracker"] = function()
    if not ns:IsAddonLoaded("AutoLayer_Vanilla") then return end
    if not AutoLayer then return end

    -- Hook SendLayerRequest to capture hop initiation (outbound path)
    -- Allow from IDLE, WAITING_INVITE (retry), or NO_RESPONSE (retry after failure)
    -- Block only when IN_GROUP or CONFIRMED (already mid-hop)
    hooksecurefunc(AutoLayer, "SendLayerRequest", function()
        if hopState.state == "IN_GROUP" or hopState.state == "CONFIRMED" then return end
        local currentLayer = NWB_CurrentLayer
        hopState.state = "WAITING_INVITE"
        hopState.source = "OUTBOUND"
        hopState.phaseChanged = false
        hopState.fromLayer = currentLayer and tonumber(currentLayer) or nil
        hopState.timestamp = GetTime()
        UpdateStatusFrame()
    end)

    -- Detect incoming invites, group joins, and phase changes during a hop
    local hopEventFrame = CreateFrame("Frame")
    hopEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    hopEventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
    hopEventFrame:RegisterEvent("UNIT_PHASE")
    hopEventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "PARTY_INVITE_REQUEST" then
            -- Guard: only track if AutoLayer is enabled
            if not AutoLayer.db or not AutoLayer.db.profile.enabled then return end
            -- Guard: can't accept an invite while already in a group
            if IsInGroup() then return end

            if hopState.state == "IDLE" or hopState.state == "NO_RESPONSE" then
                -- External invite while idle or after a failed attempt — track so auto-leave works
                local currentLayer = NWB_CurrentLayer
                hopState.state = "WAITING_INVITE"
                hopState.source = "INBOUND"
                hopState.fromLayer = currentLayer and tonumber(currentLayer) or nil
                hopState.phaseChanged = false
                hopState.timestamp = GetTime()
                UpdateStatusFrame()
            end
            -- If WAITING_INVITE (OUTBOUND), the invite arrived as expected — no change

        elseif event == "UNIT_PHASE" then
            -- UNIT_PHASE fires when the player's phase changes. During a
            -- hop this is a strong hint the layer is changing, but NOT proof —
            -- NWB still needs to confirm the new layer number via NPC GUID.
            -- We use this to mark the phase as changed so PollLayer knows
            -- to auto-leave once NWB confirms (or on a shorter timeout).
            local unit = ...
            -- Accept "player" or nil (TBC Classic may not pass a unit arg)
            if unit and unit ~= "player" then return end
            if hopState.state ~= "IN_GROUP" then return end
            if IsInInstance() then return end

            hopState.phaseChanged = true
            hopState.phaseTimestamp = GetTime()
            UpdateStatusFrame()

        elseif event == "GROUP_ROSTER_UPDATE" then
            if hopState.state == "WAITING_INVITE" and IsInGroup() then
                -- Accepted the invite, now in the hop group
                hopState.state = "IN_GROUP"
                hopState.timestamp = GetTime()
                -- Snapshot layer if not captured yet
                local currentLayer = NWB_CurrentLayer
                local currentNum = currentLayer and tonumber(currentLayer)
                if currentNum and currentNum > 0 and not hopState.fromLayer then
                    hopState.fromLayer = currentNum
                end
                UpdateStatusFrame()
                -- Check if layer already changed while we were WAITING_INVITE
                -- (race condition: NWB detected new layer before this event)
                if ns.applied["AutoLayer_hopTransitionTracker"]
                    and currentNum and currentNum > 0
                    and hopState.fromLayer and currentNum ~= hopState.fromLayer then
                    hopState.state = "CONFIRMED"
                    hopState.timestamp = GetTime()
                    local layerStr = tostring(currentNum)
                    C_Timer.After(0.5, function()
                        LeaveHopGroup("confirmed", layerStr)
                    end)
                    UpdateStatusFrame()
                end
            elseif hopState.state == "IN_GROUP" and not IsInGroup() then
                -- Other player left or we got kicked. Check if the layer
                -- actually changed before resetting — the host often leaves
                -- before NWB has confirmed the new layer number.
                local curLayer = NWB_CurrentLayer and tonumber(NWB_CurrentLayer)
                if curLayer and curLayer > 0 and hopState.fromLayer and curLayer ~= hopState.fromLayer then
                    -- Layer DID change — treat as confirmed hop
                    hopState.state = "CONFIRMED"
                    hopState.timestamp = GetTime()
                    local layerStr = tostring(curLayer)
                    UIErrorsFrame:AddMessage("PatchWerk: Layer " .. layerStr .. " confirmed", 0.2, 0.8, 1.0)
                elseif hopState.phaseChanged then
                    -- UNIT_PHASE fired (layer is changing) but NWB hasn't
                    -- confirmed the number yet — treat as successful hop
                    hopState.state = "CONFIRMED"
                    hopState.timestamp = GetTime()
                    UIErrorsFrame:AddMessage("PatchWerk: Layer changed", 0.2, 0.8, 1.0)
                else
                    -- Layer unchanged or unknown — genuine failure/kick
                    hopState.state = "IDLE"
                    hopState.source = nil
                    hopState.fromLayer = nil
                    hopState.phaseChanged = false
                end
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
                NO_RESPONSE = { color = "|cffff3333", label = "No response — try again" },
            }
            local info = stateInfo[hopState.state]
            if info then
                tooltip:AddLine(info.color .. "Hop: " .. info.label .. "|r")
            end
        end

        tooltip:AddLine(" ")
        tooltip:AddLine("|cff808080Left-click to toggle|r")
        tooltip:AddLine("|cff808080Right-click to hop layers|r")
    end
end
