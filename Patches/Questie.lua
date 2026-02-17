------------------------------------------------------------------------
-- PatchWerk - Performance patches for Questie (Quest Helper)
--
-- Questie is the most popular quest helper addon for Classic, but its
-- event-driven update paths fire far more often than necessary on TBC
-- Classic Anniversary.  Multiple QUEST_LOG_UPDATE events per second
-- during active questing trigger full quest log scans, and quest
-- availability recalculations burst 4-6 times on state changes.
-- These patches address:
--   1. Questie_questLogThrottle        - Burst-throttle QUEST_LOG_UPDATE
--                                        processing to one scan per 0.5s
--   2. Questie_availableQuestsDebounce - Debounce CalculateAndDrawAll to
--                                        collapse rapid-fire burst calls
------------------------------------------------------------------------

local _, ns = ...

local pcall   = pcall
local GetTime = GetTime

------------------------------------------------------------------------
-- 1. Questie_questLogThrottle
--
-- QuestEventHandler.QuestLogUpdate() fires multiple times per second
-- during active questing (e.g. multiple events per mob kill).  Each
-- call performs a full quest log scan: ~75 GetQuestLogTitle calls plus
-- objective queries per quest entry.
--
-- Questie uses a module loader (QuestieLoader:ImportModule) to access
-- its internal modules.  We import QuestEventHandler and wrap
-- QuestLogUpdate with a 0.5s burst throttle so that only the first
-- call in any 0.5s window actually executes.
------------------------------------------------------------------------
ns.patches["Questie_questLogThrottle"] = function()
    if not QuestieLoader or not QuestieLoader.ImportModule then return end

    local ok, QEH = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestEventHandler")
    if not ok or not QEH or not QEH.QuestLogUpdate then return end

    local origQLU = QEH.QuestLogUpdate
    local lastScan = 0

    QEH.QuestLogUpdate = function(...)
        local now = GetTime()
        if (now - lastScan) < 0.5 then return end
        lastScan = now
        return origQLU(...)
    end
end

------------------------------------------------------------------------
-- 2. Questie_availableQuestsDebounce
--
-- AvailableQuests.CalculateAndDrawAll fires 4-6 times in rapid
-- succession on quest state changes (accept, complete, abandon).
-- Each call iterates the full quest database to recalculate which
-- quests are available.  Questie already cancels previous runs, but
-- the cancellation itself has overhead from coroutine teardown.
--
-- Fix: Add a 100ms debounce using C_Timer.  When CalculateAndDrawAll
-- is called multiple times in quick succession, only the final call
-- actually executes after the burst settles.
------------------------------------------------------------------------
ns.patches["Questie_availableQuestsDebounce"] = function()
    if not QuestieLoader or not QuestieLoader.ImportModule then return end

    local ok, AQ = pcall(QuestieLoader.ImportModule, QuestieLoader, "AvailableQuests")
    if not ok or not AQ or not AQ.CalculateAndDrawAll then return end

    local origCADA = AQ.CalculateAndDrawAll
    local pendingTimer = nil

    AQ.CalculateAndDrawAll = function(callback)
        if pendingTimer then
            pendingTimer:Cancel()
        end
        pendingTimer = C_Timer.NewTimer(0.1, function()
            pendingTimer = nil
            origCADA(callback)
        end)
    end
end

------------------------------------------------------------------------
-- 3. Questie_framePoolPrealloc
--
-- Questie creates map icon frames on-demand via CreateFrame when
-- displaying new quests.  The first time a batch of quest icons is
-- needed (zone transition, quest accept burst), the synchronous
-- CreateFrame calls cause a visible stutter.
--
-- Fix: Warm up the frame pool 3 seconds after login by borrowing and
-- immediately returning 20 frames.  This spreads the CreateFrame cost
-- over idle time instead of hitting it during active gameplay.
------------------------------------------------------------------------
ns.patches["Questie_framePoolPrealloc"] = function()
    if not QuestieLoader or not QuestieLoader.ImportModule then return end
    if not C_Timer or not C_Timer.NewTimer then return end

    local ok, QFP = pcall(QuestieLoader.ImportModule, QuestieLoader, "QuestieFramePool")
    if not ok or not QFP then return end
    if not QFP.GetFrame then return end

    C_Timer.NewTimer(3, function()
        local prealloc = {}
        for i = 1, 20 do
            local ok2, frame = pcall(QFP.GetFrame, QFP)
            if ok2 and frame and frame.Unload then
                prealloc[i] = frame
            else
                break
            end
        end
        for _, frame in ipairs(prealloc) do
            pcall(frame.Unload, frame)
        end
    end)
end
