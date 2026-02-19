------------------------------------------------------------------------
-- PatchWerk - Performance patch for QuestXP Tracker
--
-- QuestXP hooks QuestLog_Update via hooksecurefunc to display XP
-- values next to quest entries in the quest log.  This hook fires on
-- every scroll tick, hover, and quest state change, each time running
-- a full quest log scan (GetNumQuestLogEntries + GetQuestLogTitle for
-- every entry) and allocating a new headerXP table.  In a quest-heavy
-- log (20+ entries) this adds up to noticeable stutter when scrolling.
--
-- The hook also fires a second time for QuestLogEx support if that
-- addon is loaded, doubling the work.
--
-- This patch addresses:
--   1. QuestXP_questLogDebounce - Debounce the QuestLog_Update hook so
--                                  the full scan only runs once after
--                                  rapid-fire events settle (0.1 sec)
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("QuestXP", {
    key = "QuestXP_questLogDebounce",
    label = "Quest Log Debounce",
    help = "Debounces quest log updates so the full scan only runs once after rapid events.",
    detail = "QuestXP hooks every QuestLog_Update call to scan and annotate quest entries with XP values. This fires on every scroll tick, mouse hover, and quest state change — each time iterating the entire quest log and creating a new table. When you have many quests, scrolling the log causes repeated full scans that add up to noticeable stutter. This patch delays the scan by a tenth of a second so rapid-fire updates collapse into a single pass.",
    impact = "FPS",
    impactLevel = "Medium",
    category = "Performance",
    estimate = "Smoother quest log scrolling",
})

------------------------------------------------------------------------
-- 1. QuestXP_questLogDebounce
--
-- QuestXP stores its frame in a local variable (not exposed as a
-- global), so we locate it at runtime by scanning all frames with
-- EnumerateFrames() for one that has a QuestLog_Update method and
-- listens to the QUEST_DETAIL event — the unique fingerprint of the
-- QXP frame.
--
-- Once found, we replace QXP:QuestLog_Update with a debounced wrapper
-- that uses a hidden OnUpdate frame to delay execution by 0.1 seconds.
-- When multiple QuestLog_Update calls arrive in quick succession (as
-- happens during scrolling), the timer resets each time so only the
-- final call actually performs the quest log scan and UI update.
------------------------------------------------------------------------
ns.patches["QuestXP_questLogDebounce"] = function()
    if not ns:IsAddonLoaded("QuestXP") then return end

    -- QXPdb is the saved variable exposed by QuestXP.  If it does not
    -- exist the addon either did not load or the player is at level cap
    -- (in which case QuestXP skips its hooks entirely).
    if type(QXPdb) ~= "table" then return end

    -- Locate the QXP frame by scanning all frames for the unique
    -- combination of having a QuestLog_Update method and listening to
    -- QUEST_DETAIL — no other addon frame matches this fingerprint.
    local qxpFrame = nil
    local frame = EnumerateFrames()
    while frame do
        if type(frame.QuestLog_Update) == "function"
           and frame:IsEventRegistered("QUEST_DETAIL") then
            qxpFrame = frame
            break
        end
        frame = EnumerateFrames(frame)
    end

    if not qxpFrame then return end

    local origQuestLogUpdate = qxpFrame.QuestLog_Update

    -- Debounce timer using a hidden OnUpdate frame (avoids C_Timer
    -- allocations).  Same pattern as BugSack_searchThrottle.
    local DEBOUNCE_DELAY = 0.1
    local timerFrame = CreateFrame("Frame")
    timerFrame:Hide()

    local pendingAddonName = nil
    local elapsed = 0

    timerFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= DEBOUNCE_DELAY then
            self:Hide()
            if pendingAddonName then
                local name = pendingAddonName
                pendingAddonName = nil
                origQuestLogUpdate(qxpFrame, name)
            end
        end
    end)

    -- Replace the method on the QXP frame.  The existing hooksecurefunc
    -- closures call QXP:QuestLog_Update(addonName) which resolves to
    -- qxpFrame.QuestLog_Update(qxpFrame, addonName) — so replacing the
    -- method on the frame table intercepts all existing hook calls.
    qxpFrame.QuestLog_Update = function(self, addonName)
        pendingAddonName = addonName
        elapsed = 0
        timerFrame:Show()
    end
end
