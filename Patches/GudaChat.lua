------------------------------------------------------------------------
-- PatchWerk - QOL tweaks for GudaChat (Chat)
--
-- Three independent patches:
--   1. arrowKeys    - Bare Up/Down cycles through sent message history
--                     (no Alt modifier needed, just like Prat)
--   2. tellTarget   - /tt slash command to whisper your current target
--   3. clearCommand - /clear and /clearall to wipe chat frame contents
------------------------------------------------------------------------

local _, ns = ...

-- Cache globals
local UnitName = UnitName
local UnitIsPlayer = UnitIsPlayer
local UnitRealmRelationship = UnitRealmRelationship
local ChatEdit_UpdateHeader = ChatEdit_UpdateHeader
local NUM_WINDOWS = NUM_CHAT_WINDOWS or 10
local LE_REALM_RELATION_SAME = LE_REALM_RELATION_SAME

------------------------------------------------------------------------
-- Patch 1: Arrow key message history (no Alt needed)
------------------------------------------------------------------------
ns:RegisterPatch("GudaChat", {
    key = "GudaChat_arrowKeys",
    label = "Arrow Key History",
    help = "Use bare Up/Down arrows to cycle sent messages in chat",
    detail = "By default, WoW requires Alt+Up/Down to scroll through previously sent messages. This removes the Alt requirement so bare Up/Down arrows cycle your message history, just like Prat.",
    impact = "QOL",
    impactLevel = "Low",
    category = "tweaks",
})

ns.patches["GudaChat_arrowKeys"] = function()
    if not ns:IsAddonLoaded("GudaChat") then return end

    -- Blizzard's ChatEdit_ActivateChat resets SetAltArrowKeyMode(true)
    -- every time the edit box gains focus.  Hook it to re-apply our
    -- override so bare Up/Down always cycles message history.
    hooksecurefunc("ChatEdit_ActivateChat", function(editBox)
        editBox:SetAltArrowKeyMode(false)
    end)
end

------------------------------------------------------------------------
-- Patch 2: /tt (tell target) slash command
------------------------------------------------------------------------
ns:RegisterPatch("GudaChat", {
    key = "GudaChat_tellTarget",
    label = "/tt Whisper Target",
    help = "Type /tt to whisper your current target",
    detail = "Adds the /tt slash command (ported from Prat). Type /tt followed by your message to whisper your current target without manually typing their name.",
    impact = "QOL",
    impactLevel = "Low",
    category = "tweaks",
})

ns.patches["GudaChat_tellTarget"] = function()
    if not ns:IsAddonLoaded("GudaChat") then return end

    local function OnTextChanged(editBox)
        local text = editBox:GetText()
        if not text then return end

        local command, msg = text:match("^(/%S+)%s(.*)$")
        if command ~= "/tt" then return end

        local target
        if UnitIsPlayer("target") then
            local unitname, realm = UnitName("target")
            if unitname then
                if realm and realm ~= ""
                   and UnitRealmRelationship
                   and UnitRealmRelationship("target") ~= LE_REALM_RELATION_SAME then
                    target = unitname .. "-" .. realm
                else
                    target = unitname
                end
            end
        end

        if not target then
            -- No valid player target - leave the text as-is so the user
            -- sees the error when they hit Enter
            return
        end

        editBox:SetAttribute("chatType", "WHISPER")
        editBox:SetAttribute("tellTarget", target)
        editBox:SetText(msg or "")
        ChatEdit_UpdateHeader(editBox)
    end

    for i = 1, NUM_WINDOWS do
        local eb = _G["ChatFrame" .. i .. "EditBox"]
        if eb then
            eb:HookScript("OnTextChanged", OnTextChanged)
        end
    end
end

------------------------------------------------------------------------
-- Patch 3: /clear and /clearall slash commands (ported from Prat)
------------------------------------------------------------------------
ns:RegisterPatch("GudaChat", {
    key = "GudaChat_clearCommand",
    label = "Clear Chat Command",
    help = "Adds /clear and /clearall slash commands to wipe chat windows",
    detail = "Ports Prat's /clear and /clearall commands for GudaChat users. /clear wipes the currently selected chat window, /cls is a short alias. /clearall wipes every chat window at once.",
    impact = "QOL",
    impactLevel = "Low",
    category = "tweaks",
})

ns.patches["GudaChat_clearCommand"] = function()
    if not ns:IsAddonLoaded("GudaChat") then return end

    -- /clear (/cls) — wipe the currently selected chat frame
    SLASH_GUDACHAT_CLEAR1 = "/clear"
    SLASH_GUDACHAT_CLEAR2 = "/cls"

    SlashCmdList["GUDACHAT_CLEAR"] = function()
        local cf = SELECTED_CHAT_FRAME
        if cf and cf.Clear then
            cf:Clear()
        end
    end

    -- /clearall (/clsall) — wipe every chat frame
    SLASH_GUDACHAT_CLEARALL1 = "/clearall"
    SLASH_GUDACHAT_CLEARALL2 = "/clsall"

    SlashCmdList["GUDACHAT_CLEARALL"] = function()
        for i = 1, NUM_WINDOWS do
            local cf = _G["ChatFrame" .. i]
            if cf and cf.Clear then
                cf:Clear()
            end
        end
    end
end
