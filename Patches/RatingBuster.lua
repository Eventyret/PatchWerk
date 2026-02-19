------------------------------------------------------------------------
-- PatchWerk - Performance patch for RatingBuster
--
-- RatingBuster uses TipHooker.lua to hook tooltip events.  Its
-- HandleTooltipSetItem function calls debugstack():find("OnUpdate")
-- on every OnTooltipSetItem fire to detect whether the tooltip was
-- set during an OnUpdate cycle (a workaround for ShoppingTooltip and
-- InspectFrame).  debugstack() is expensive because it captures the
-- full Lua call stack as a string every time.  When mousing over many
-- items (bags, auction house, vendor, etc.) this becomes a meaningful
-- CPU drain.
--
--   1. RatingBuster_debugstackOptimize - Replace debugstack() with
--      an inOnUpdate flag tracked via OnUpdate script wrappers.
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns.patchInfo[#ns.patchInfo + 1] = {
    key = "RatingBuster_debugstackOptimize",
    group = "RatingBuster",
    label = "TipHooker debugstack Bypass",
    help = "Replaces expensive debugstack() calls in RatingBuster's tooltip hooker with a lightweight flag check.",
    detail = "RatingBuster's TipHooker hooks OnTooltipSetItem on every tracked tooltip (GameTooltip, ShoppingTooltip1/2, ItemRefTooltip, etc.).  Each time OnTooltipSetItem fires, the handler calls debugstack():find(\"OnUpdate\") to detect if the tooltip was set during an OnUpdate cycle.  debugstack() captures the entire Lua call stack as a formatted string, which involves walking the stack, formatting frame names, line numbers, and concatenating them.  In scenarios with frequent tooltip updates (scrolling through bag items, browsing the auction house), this runs dozens of times per second.  This patch replaces the debugstack() check with a simple boolean flag that is set to true inside OnUpdate wrappers and checked in the tooltip handler, eliminating the stack capture entirely.",
    impact = "FPS",
    impactLevel = "Medium",
    category = "Performance",
    targetVersion = "2.1.4",
    estimate = "~5-15% tooltip processing improvement",
}

------------------------------------------------------------------------
-- 1. RatingBuster_debugstackOptimize
--
-- TipHooker.lua defines a local function HandleTooltipSetItem(tooltip)
-- that calls debugstack():find("OnUpdate") on line 34 to detect if
-- OnTooltipSetItem was triggered from within an OnUpdate handler.
-- This is used as a workaround for ShoppingTooltip and InspectFrame,
-- which fire OnUpdate before OnTooltipSetItem each frame.
--
-- The function is installed via:
--   tooltip:HookScript("OnTooltipSetItem", HandleTooltipSetItem)
-- for each tooltip in the tooltips table (GameTooltip, ShoppingTooltip1,
-- ShoppingTooltip2, ItemRefTooltip, etc.).
--
-- Fix approach:
--   a) We retrieve the hooked OnTooltipSetItem script from a known
--      tooltip (GameTooltip) and walk its upvalue chain to find the
--      original HandleTooltipSetItem function.
--   b) From HandleTooltipSetItem we extract its upvalues: RunHandler,
--      QueueUpdate, directUpdateTypes (the pieces it needs).
--   c) We build a replacement function that uses a simple boolean flag
--      (inOnUpdate) instead of debugstack().
--   d) We wrap each tooltip's OnUpdate script to set inOnUpdate = true
--      before dispatching and false afterwards, so the flag is accurate
--      whenever HandleTooltipSetItem runs.
--   e) We swap the HandleTooltipSetItem upvalue reference inside the
--      HookScript wrapper so the new function is called instead.
------------------------------------------------------------------------
ns.patches["RatingBuster_debugstackOptimize"] = function()
    if not ns:IsAddonLoaded("RatingBuster") then return end

    -- The list of tooltip names that TipHooker hooks (must match TipHooker.lua)
    local tooltipNames = {
        "GameTooltip",
        "ShoppingTooltip1",
        "ShoppingTooltip2",
        "ItemRefTooltip",
        "ItemRefShoppingTooltip1",
        "ItemRefShoppingTooltip2",
        "AtlasLootTooltip",
    }

    -- Step 1: Find a tooltip that has the OnTooltipSetItem hook installed.
    -- We use GameTooltip as the primary candidate since it's always present.
    local refTooltip = _G["GameTooltip"]
    if not refTooltip then return end

    local hookScript = refTooltip:GetScript("OnTooltipSetItem")
    if not hookScript then return end

    -- Step 2: Walk upvalues of the HookScript wrapper to find the
    -- original HandleTooltipSetItem function.  HookScript creates a
    -- wrapper closure that stores the hooked function as an upvalue.
    -- The upvalue we are looking for is a function that has
    -- directUpdateTypes as one of its own upvalues, which uniquely
    -- identifies HandleTooltipSetItem among TipHooker's functions.

    local getupvalue = debug.getupvalue
    local setupvalue = debug.setupvalue

    -- Recursively search for HandleTooltipSetItem in the upvalue tree.
    -- HookScript may nest one or two levels deep depending on how many
    -- scripts were hooked.
    local function findHandleTooltipSetItem(fn, depth)
        if not fn or depth > 5 then return nil, nil, nil end
        for i = 1, 20 do
            local name, val = getupvalue(fn, i)
            if not name then break end
            if type(val) == "function" then
                -- Check if this function has directUpdateTypes as an upvalue,
                -- which uniquely identifies HandleTooltipSetItem.
                for j = 1, 20 do
                    local uname, uval = getupvalue(val, j)
                    if not uname then break end
                    if uname == "directUpdateTypes" and type(uval) == "table" then
                        return val, fn, i
                    end
                end
                -- Recurse into nested wrappers
                local found, parent, idx = findHandleTooltipSetItem(val, depth + 1)
                if found then return found, parent, idx end
            end
        end
        return nil, nil, nil
    end

    local origHandleTooltipSetItem, parentFn, parentIdx = findHandleTooltipSetItem(hookScript, 0)
    if not origHandleTooltipSetItem then return end

    -- Step 3: Extract the upvalues we need from the original function.
    -- HandleTooltipSetItem references these locals from TipHooker.lua:
    --   RunHandler      (function) - calls the actual RatingBuster handler
    --   QueueUpdate     (function) - defers tooltip update to next OnUpdate
    --   directUpdateTypes (table)  - { ["GameTooltip"]=true, ["CheckButton"]=true }
    --   HandleUpdate    (function) - processes queued tooltip updates

    local RunHandler, QueueUpdate, directUpdateTypes, HandleUpdate
    for i = 1, 20 do
        local name, val = getupvalue(origHandleTooltipSetItem, i)
        if not name then break end
        if name == "RunHandler" then RunHandler = val
        elseif name == "QueueUpdate" then QueueUpdate = val
        elseif name == "directUpdateTypes" then directUpdateTypes = val
        elseif name == "HandleUpdate" then HandleUpdate = val
        end
    end

    if not RunHandler or not QueueUpdate or not directUpdateTypes then return end

    -- Step 4: Create the inOnUpdate flag and the replacement function.
    -- The flag is shared across all tooltip OnUpdate wrappers.
    local inOnUpdate = false

    -- Replacement for HandleTooltipSetItem that checks the flag instead
    -- of calling debugstack().  The logic is otherwise identical to the
    -- original TipHooker.lua implementation.
    local function PatchedHandleTooltipSetItem(tooltip)
        local owner = tooltip:GetOwner()
        -- Original check: directUpdateTypes match OR inside an OnUpdate cycle.
        -- We replace debugstack():find("OnUpdate") with the inOnUpdate flag.
        if (owner and owner.GetObjectType and directUpdateTypes[owner:GetObjectType()]) or inOnUpdate then
            RunHandler(tooltip)
        elseif owner then
            QueueUpdate(tooltip)
            if not tooltip:GetScript("OnUpdate") then
                -- Workaround for ItemRefTooltip cannibalizing its OnUpdate handler
                tooltip:SetScript("OnUpdate", function(self)
                    if HandleUpdate then
                        HandleUpdate(self)
                    end
                    self:SetScript("OnUpdate", nil)
                end)
            end
        end
    end

    -- Step 5: Replace the HandleTooltipSetItem reference in the hook wrapper.
    -- We do this by setting the upvalue in the parent closure (the HookScript
    -- wrapper) that holds a reference to the original function.
    setupvalue(parentFn, parentIdx, PatchedHandleTooltipSetItem)

    -- Step 6: For every tooltip in the list, replace HandleTooltipSetItem
    -- in their HookScript wrappers and wrap their OnUpdate scripts to
    -- manage the inOnUpdate flag.
    --
    -- We also hook SetScript so that any FUTURE OnUpdate scripts (such as
    -- the dynamic one-shot handler TipHooker sets on ItemRefTooltip) are
    -- automatically wrapped with the flag.  A recursion guard prevents the
    -- hooksecurefunc from re-entering itself when it calls SetScript.
    local wrapping = false  -- recursion guard for SetScript hook

    for _, tooltipName in ipairs(tooltipNames) do
        local tooltip = _G[tooltipName]
        if tooltip then
            -- 6a) Replace HandleTooltipSetItem in this tooltip's OnTooltipSetItem hook
            local tipHookScript = tooltip:GetScript("OnTooltipSetItem")
            if tipHookScript then
                local _, tipParent, tipIdx = findHandleTooltipSetItem(tipHookScript, 0)
                if tipParent and tipIdx then
                    setupvalue(tipParent, tipIdx, PatchedHandleTooltipSetItem)
                end
            end

            -- 6b) Wrap any currently-installed OnUpdate script with flag management.
            local existingOnUpdate = tooltip:GetScript("OnUpdate")
            if existingOnUpdate then
                wrapping = true
                tooltip:SetScript("OnUpdate", function(self, elapsed)
                    inOnUpdate = true
                    existingOnUpdate(self, elapsed)
                    inOnUpdate = false
                end)
                wrapping = false
            end

            -- 6c) Hook SetScript so that any future OnUpdate handler is
            -- automatically wrapped with the inOnUpdate flag.  The hook fires
            -- AFTER SetScript has already installed the handler, so we read
            -- back the installed handler, wrap it, and re-install.
            hooksecurefunc(tooltip, "SetScript", function(self, scriptType)
                if wrapping then return end         -- prevent recursion
                if scriptType ~= "OnUpdate" then return end
                local current = self:GetScript("OnUpdate")
                if not current then return end
                wrapping = true
                self:SetScript("OnUpdate", function(frame, elapsed)
                    inOnUpdate = true
                    current(frame, elapsed)
                    inOnUpdate = false
                end)
                wrapping = false
            end)
        end
    end
end
