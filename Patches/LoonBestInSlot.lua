------------------------------------------------------------------------
-- PatchWerk - Compatibility & QOL patches for LoonBestInSlot
--
-- LoonBestInSlot is a Best-in-Slot gear browser written for retail WoW
-- that has TBC data but uses several retail-only APIs.  These patches
-- fix the compatibility issues so it runs on TBC Classic Anniversary:
--   1. LoonBestInSlot_apiCompat         - Replace retail Item/Spell/
--                                          C_Item/C_Spell APIs with
--                                          classic GetItemInfo/GetSpellInfo
--   2. LoonBestInSlot_containerCompat   - Replace C_Container calls with
--                                          classic GetContainerNumSlots/
--                                          GetContainerItemLink
--   3. LoonBestInSlot_settingsCompat    - Replace Settings.OpenToCategory
--                                          with InterfaceOptionsFrame_
--                                          OpenToCategory
--   4. LoonBestInSlot_phaseUpdate       - Set CurrentPhase to 5 for TBC
--                                          Anniversary (all content live)
--   5. LoonBestInSlot_nilGuards         - Add nil-safety to AddItem,
--                                          AddGem, AddEnchant source
--                                          lookups
--   6. LoonBestInSlot_tooltipOptimize   - Optimise tooltip hot path:
--                                          avoid temp table from strsplit,
--                                          pre-compute class icon strings,
--                                          cache tooltip:GetName()
------------------------------------------------------------------------

local _, ns = ...

local pairs  = pairs
local tonumber = tonumber
local tostring = tostring
local string_match = string.match
local string_gsub  = string.gsub

------------------------------------------------------------------------
-- 1. LoonBestInSlot_apiCompat  (Bug fix - Critical)
--
-- LoonBestInSlot uses retail-only APIs:
--   * Item:CreateFromItemID / itemCache:ContinueOnItemLoad
--   * C_Item.GetItemInfoInstant
--   * Spell:CreateFromSpellID / spellCache:ContinueOnSpellLoad
--   * C_Spell.GetSpellTexture
--
-- None of these exist in TBC Classic Anniversary.  Replace LBIS:GetItemInfo
-- and LBIS:GetSpellInfo with implementations that use the classic global
-- GetItemInfo(itemId) and GetSpellInfo(spellId) functions.
--
-- The replacement preserves:
--   * The server-side item cache (LBISServerSettings.ItemCache)
--   * The spell cache (LBIS.SpellCache)
--   * The same return object shapes
--   * The caching-decision guard (only cache if name exists and
--     LBIS.ItemSources has an entry)
------------------------------------------------------------------------
ns.patches["LoonBestInSlot_apiCompat"] = function()
    if not LBIS then return end
    if not LBIS.GetItemInfo then return end

    -- Rebuild the itemSlots mapping that the original uses (defined as a
    -- local in Common.lua, so we cannot access it directly).  We need
    -- LBIS.L to exist for the localised slot names.
    local L = LBIS.L
    if not L then return end

    local itemSlots = {}
    itemSlots["INVTYPE_NON_EQUIP"]       = L["None"]
    itemSlots["INVTYPE_HEAD"]            = L["Head"]
    itemSlots["INVTYPE_NECK"]            = L["Neck"]
    itemSlots["INVTYPE_SHOULDER"]        = L["Shoulder"]
    itemSlots["INVTYPE_BODY"]            = L["Shirt"]
    itemSlots["INVTYPE_CHEST"]           = L["Chest"]
    itemSlots["INVTYPE_WAIST"]           = L["Waist"]
    itemSlots["INVTYPE_LEGS"]            = L["Legs"]
    itemSlots["INVTYPE_FEET"]            = L["Feet"]
    itemSlots["INVTYPE_WRIST"]           = L["Wrist"]
    itemSlots["INVTYPE_HAND"]            = L["Hands"]
    itemSlots["INVTYPE_FINGER"]          = L["Ring"]
    itemSlots["INVTYPE_TRINKET"]         = L["Trinket"]
    itemSlots["INVTYPE_WEAPON"]          = L["Main Hand"] .. "/" .. L["Off Hand"]
    itemSlots["INVTYPE_SHIELD"]          = L["Off Hand"]
    itemSlots["INVTYPE_RANGED"]          = L["Ranged/Relic"]
    itemSlots["INVTYPE_CLOAK"]           = L["Back"]
    itemSlots["INVTYPE_BAG"]             = L["Bag"]
    itemSlots["INVTYPE_TABARD"]          = L["Tabard"]
    itemSlots["INVTYPE_ROBE"]            = L["Chest"]
    itemSlots["INVTYPE_WEAPONMAINHAND"]  = L["Main Hand"]
    itemSlots["INVTYPE_2HWEAPON"]        = L["Two Hand"]
    itemSlots["INVTYPE_WEAPONOFFHAND"]   = L["Off Hand"]
    itemSlots["INVTYPE_HOLDABLE"]        = L["Off Hand"]
    itemSlots["INVTYPE_AMMO"]            = L["Ammo"]
    itemSlots["INVTYPE_THROWN"]           = L["Ranged/Relic"]
    itemSlots["INVTYPE_RANGEDRIGHT"]     = L["Ranged/Relic"]
    itemSlots["INVTYPE_QUIVER"]          = L["Quiver"]
    itemSlots["INVTYPE_RELIC"]           = L["Ranged/Relic"]

    -- Replace LBIS:GetItemInfo
    -- Original signature: LBIS:GetItemInfo(itemId, returnFunc)
    function LBIS:GetItemInfo(itemId, returnFunc)
        if itemId == nil or not itemId or itemId <= 0 then
            returnFunc({ Name = nil, Link = nil, Quality = nil, Type = nil, SubType = nil, Texture = nil, Class = nil, Slot = nil })
            return
        end

        local cachedItem = LBISServerSettings and LBISServerSettings.ItemCache and LBISServerSettings.ItemCache[itemId]

        if cachedItem then
            returnFunc(cachedItem)
            return
        end

        -- Classic TBC GetItemInfo:
        -- name, link, quality, iLevel, reqLevel, itemType, subType, stackCount, equipSlot, texture, sellPrice = GetItemInfo(itemId)
        local name, link, quality, _, _, itemType, subType, _, equipSlot, texture = GetItemInfo(itemId)

        local newItem = {
            Id       = itemId,
            Name     = name,
            Link     = link,
            Quality  = quality,
            Type     = itemType,
            SubType  = subType,
            Texture  = texture,
            Class    = nil,   -- classic GetItemInfo does not return classId; not needed for display
            Slot     = equipSlot and itemSlots[equipSlot] or nil,
        }

        -- Only persist to cache if the item loaded and we have source data
        if name and LBIS.ItemSources and LBIS.ItemSources[itemId] ~= nil then
            LBISServerSettings.ItemCache[itemId] = newItem
        end

        returnFunc(newItem)
    end

    -- Replace LBIS:GetSpellInfo
    -- Original signature: LBIS:GetSpellInfo(spellId, returnFunc)
    function LBIS:GetSpellInfo(spellId, returnFunc)
        if not spellId or spellId <= 0 then
            returnFunc({ Name = nil, Link = nil, Quality = nil, Type = nil, SubType = nil, Texture = nil })
            return
        end

        local cachedSpell = LBIS.SpellCache[spellId]

        if cachedSpell then
            returnFunc(cachedSpell)
            return
        end

        -- Classic TBC GetSpellInfo:
        -- name, rank, icon, castTime, minRange, maxRange = GetSpellInfo(spellId)
        local name, rank, icon = GetSpellInfo(spellId)

        local newSpell = {
            Id      = spellId,
            Name    = name,
            SubText = rank,
            Texture = icon,
        }

        if name then
            LBIS.SpellCache[spellId] = newSpell
        end

        returnFunc(newSpell)
    end
end

------------------------------------------------------------------------
-- 2. LoonBestInSlot_containerCompat  (Bug fix)
--
-- UserItemCache.lua uses C_Container.GetContainerNumSlots and
-- C_Container.GetContainerItemLink which do not exist in TBC Classic
-- Anniversary.  The global functions GetContainerNumSlots(bag) and
-- GetContainerItemLink(bag, slot) are the classic equivalents.
--
-- The problematic calls live inside the local function readBagsWithApi()
-- which is called from LBIS:BuildItemCache().  Since readBagsWithApi is
-- a local we cannot replace it directly; instead we replace the entire
-- LBIS:BuildItemCache with an equivalent that uses the classic globals.
------------------------------------------------------------------------
ns.patches["LoonBestInSlot_containerCompat"] = function()
    if not LBIS then return end
    if not LBIS.BuildItemCache then return end

    -- The wowSlotCodes list used by BuildItemCache (duplicated from
    -- UserItemCache.lua since it is a local there)
    local wowSlotCodes = {
        "HEADSLOT", "NECKSLOT", "SHOULDERSLOT", "CHESTSLOT",
        "WAISTSLOT", "LEGSSLOT", "FEETSLOT", "WRISTSLOT",
        "HANDSSLOT", "FINGER0SLOT", "FINGER1SLOT",
        "TRINKET0SLOT", "TRINKET1SLOT", "BACKSLOT",
        "MAINHANDSLOT", "SECONDARYHANDSLOT",
    }

    function LBIS:BuildItemCache()
        if LBIS.UserItemCacheBuilt then
            return
        end

        -- Clear existing user items
        for k in pairs(LBIS.UserItems) do
            LBIS.UserItems[k] = nil
        end

        -- Read equipped items (unchanged - uses classic-compatible APIs)
        for _, slotCode in ipairs(wowSlotCodes) do
            local itemLink = GetInventoryItemLink("player", GetInventorySlotInfo(slotCode))
            if itemLink then
                local itemId = LBIS:GetItemIdFromLink(itemLink)
                LBIS.UserItems[tonumber(itemId)] = "player"
                LBIS.UserSlotCache[slotCode] = itemId
            end
        end

        -- Read bags using whichever container API is available
        local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
        local GetItemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
        if not GetNumSlots or not GetItemLink then return end

        for bag = -1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
            for slot = 1, GetNumSlots(bag) do
                local itemLink = GetItemLink(bag, slot)
                if itemLink then
                    local itemId = LBIS:GetItemIdFromLink(itemLink)
                    if bag < 0 or bag > NUM_BAG_SLOTS then
                        LBIS.UserItems[tonumber(itemId)] = "bank"
                    else
                        LBIS.UserItems[tonumber(itemId)] = "bag"
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- 3. LoonBestInSlot_settingsCompat  (Bug fix)
--
-- LoonBestInSlot calls Settings.OpenToCategory("Loon Best In Slot") in
-- two places:
--   * The /bis settings slash command handler
--   * The minimap button right-click handler
--
-- Settings.OpenToCategory does not exist in TBC Classic Anniversary.
-- The classic equivalent is InterfaceOptionsFrame_OpenToCategory().
--
-- We hook the slash command handler and the LibDataBroker OnClick
-- callback to intercept the settings call.
------------------------------------------------------------------------
ns.patches["LoonBestInSlot_settingsCompat"] = function()
    if not LBIS then return end

    -- Helper: open settings panel using the classic API
    local function openSettings()
        if InterfaceOptionsFrame_OpenToCategory then
            -- Call twice: first call selects the parent category,
            -- second call scrolls to and selects the subcategory.
            -- This is a well-known quirk of the classic API.
            InterfaceOptionsFrame_OpenToCategory("Loon Best In Slot")
            InterfaceOptionsFrame_OpenToCategory("Loon Best In Slot")
        end
    end

    -- 3a. Hook the slash command handler
    local origSlash = SlashCmdList["LOONBESTINSLOT"]
    if origSlash then
        SlashCmdList["LOONBESTINSLOT"] = function(command)
            command = (command or ""):lower()
            if command == "settings" then
                openSettings()
            else
                origSlash(command)
            end
        end
    end

    -- 3b. Hook the LibDataBroker minimap button OnClick
    -- The LDB data object is registered under "LoonBestInSlot".
    -- We need LibDataBroker to access it.
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if LDB then
        local dataObj = LDB:GetDataObjectByName("LoonBestInSlot")
        if dataObj and dataObj.OnClick then
            local origOnClick = dataObj.OnClick
            dataObj.OnClick = function(self, button)
                if button == "RightButton" then
                    openSettings()
                else
                    origOnClick(self, button)
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- 4. LoonBestInSlot_phaseUpdate  (QOL fix)
--
-- LoonBestInSlot defaults CurrentPhase to 1, which hides all Phase 2-5
-- items from the browser and tooltips.  TBC Classic Anniversary has all
-- content through Phase 5 available.  Set CurrentPhase = 5 so all items
-- are visible.
------------------------------------------------------------------------
ns.patches["LoonBestInSlot_phaseUpdate"] = function()
    if not LBIS then return end

    LBIS.CurrentPhase = 5
end

------------------------------------------------------------------------
-- 5. LoonBestInSlot_nilGuards  (Bug fix)
--
-- LBIS:AddItem, LBIS:AddGem, and LBIS:AddEnchant access .SourceType,
-- .DesignId etc. on source lookup tables (LBIS.ItemSources,
-- LBIS.GemSources, LBIS.EnchantSources).  If the source entry is nil
-- (missing data), these accesses throw an error and halt loading of all
-- subsequent items for that spec.
--
-- Fix: Wrap each function to nil-check the source before the original
-- accesses it, and skip the item gracefully if the source is missing.
------------------------------------------------------------------------
ns.patches["LoonBestInSlot_nilGuards"] = function()
    if not LBIS then return end

    -- 5a. LBIS:AddItem - guard LBIS.ItemSources[itemId]
    local origAddItem = LBIS.AddItem
    if origAddItem then
        function LBIS:AddItem(bisEntry, id, slot, bis)
            if not id or id == "" then return end
            local itemId = tonumber(id)
            if itemId and LBIS.ItemSources and not LBIS.ItemSources[itemId] then
                -- Source data missing; skip this item to prevent nil access
                return
            end
            return origAddItem(self, bisEntry, id, slot, bis)
        end
    end

    -- 5b. LBIS:AddGem - guard LBIS.GemSources[gemId]
    local origAddGem = LBIS.AddGem
    if origAddGem then
        function LBIS:AddGem(bisEntry, id, quality, isMeta)
            if not id or id == "" then return end
            local gemId = tonumber(id)
            if gemId and LBIS.GemSources and not LBIS.GemSources[gemId] then
                -- Source data missing; skip this gem to prevent nil access
                return
            end
            return origAddGem(self, bisEntry, id, quality, isMeta)
        end
    end

    -- 5c. LBIS:AddEnchant - guard LBIS.EnchantSources[enchantId]
    local origAddEnchant = LBIS.AddEnchant
    if origAddEnchant then
        function LBIS:AddEnchant(bisEntry, id, slot)
            if not id or id == "" then return end
            local enchantId = tonumber(id)
            if enchantId and LBIS.EnchantSources and not LBIS.EnchantSources[enchantId] then
                -- Source data missing; skip this enchant to prevent nil access
                return
            end
            return origAddEnchant(self, bisEntry, id, slot)
        end
    end
end

------------------------------------------------------------------------
-- 6. LoonBestInSlot_tooltipOptimize  (Performance)
--
-- The tooltip hot path in UpdateTooltips.lua has three inefficiencies:
--
--   a) Item ID extraction uses `{strsplit(":", itemString)}[2]` which
--      creates a temporary table of all colon-separated fields just to
--      grab the second one.  Replace with string.match for the item ID.
--
--   b) The buildTooltip function reconstructs the class icon font string
--      on every tooltip line:
--        "|T" .. iconpath .. ":14:14:::256:256:" .. iconOffset(...) .. "|t"
--      These are constant per class.  Pre-compute them once at patch
--      time and look them up by class name.
--
--   c) tooltip:GetName() is called multiple times per tooltip event
--      (once in onTooltipSetItem guard, once in onTooltipCleared).
--      Cache the name in a local.
--
-- We cannot directly replace the local functions in UpdateTooltips.lua,
-- but we CAN replace the hookScript stubs that were installed on the
-- tooltips.  The addon uses a custom hookScript function that stores
-- control tables keyed by [tooltip][script].  The prehook is stored at
-- control[1].  However, the hookStore is local and inaccessible.
--
-- Alternative approach: The addon registers tooltip hooks via
-- OnTooltipSetItem / OnTooltipCleared / OnTooltipSetSpell scripts.
-- We can re-set these scripts on the known tooltips with optimised
-- versions that call LBIS:GetItemInfo (which we already patched above).
--
-- Since the tooltip registration happens on PLAYER_ENTERING_WORLD and
-- our patches run on ADDON_LOADED (which fires before PEW), we hook
-- LBIS.RegisterEvent to intercept the PEW registration and install our
-- own optimised handlers instead.  Actually, the simpler approach is:
-- the hooks are already installed by the time ADDON_LOADED fires for
-- PatchWerk (since LoonBestInSlot loads first and PEW may have fired).
-- We just re-set the scripts on the known tooltip frames.
------------------------------------------------------------------------
ns.patches["LoonBestInSlot_tooltipOptimize"] = function()
    if not LBIS then return end
    if not LBIS.GetItemInfo then return end
    if not LBIS.ClassSpec then return end
    if not LBIS.ENGLISH_CLASS then return end

    -- Pre-compute class icon font strings
    local iconpath = "Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes"
    local iconCutoff = 6

    local function iconOffset(col, row)
        local offsetString = (col * 64 + iconCutoff) .. ":" .. ((col + 1) * 64 - iconCutoff)
        return offsetString .. ":" .. (row * 64 + iconCutoff) .. ":" .. ((row + 1) * 64 - iconCutoff)
    end

    -- Build the class icon cache: classNameUpper -> font string
    local classIconCache = {}
    if CLASS_ICON_TCOORDS then
        for className, coords in pairs(CLASS_ICON_TCOORDS) do
            classIconCache[className] = "|T" .. iconpath .. ":14:14:::256:256:" .. iconOffset(coords[1] * 4, coords[3] * 4) .. "|t"
        end
    end

    -- Local references to functions that will be used in the hot path
    local FindInPhase = LBIS.FindInPhase

    local function isInEnabledPhase(phaseText)
        if phaseText == "" then
            return true
        end
        if LBISSettings.PhaseTooltip[LBIS.L["PreRaid"]] and LBIS.CurrentPhase >= 0 then
            if LBIS:FindInPhase(phaseText, "0") then return true end
        end
        if LBISSettings.PhaseTooltip[LBIS.L["Phase 1"]] and LBIS.CurrentPhase >= 1 then
            if LBIS:FindInPhase(phaseText, "1") then return true end
        end
        if LBISSettings.PhaseTooltip[LBIS.L["Phase 2"]] and LBIS.CurrentPhase >= 2 then
            if LBIS:FindInPhase(phaseText, "2") then return true end
        end
        if LBISSettings.PhaseTooltip[LBIS.L["Phase 3"]] and LBIS.CurrentPhase >= 3 then
            if LBIS:FindInPhase(phaseText, "3") then return true end
        end
        if LBISSettings.PhaseTooltip[LBIS.L["Phase 4"]] and LBIS.CurrentPhase >= 4 then
            if LBIS:FindInPhase(phaseText, "4") then return true end
        end
        if LBISSettings.PhaseTooltip[LBIS.L["Phase 5"]] and LBIS.CurrentPhase >= 5 then
            if LBIS:FindInPhase(phaseText, "5") then return true end
        end
        if LBIS.CurrentPhase >= 99 then
            if LBIS:FindInPhase(phaseText, "99") then return true end
        end
        return false
    end

    local function buildCombinedTooltip(entry, combinedTooltip, foundCustom)
        local classCount = {}
        local combinedSpecs = {}

        for k, v in pairs(entry) do
            if LBISSettings.Tooltip[k] and isInEnabledPhase(v.Phase) and foundCustom[k] == nil then
                local classSpec = LBIS.ClassSpec[k]

                classCount[classSpec.Class .. v.Bis .. v.Phase] = (classCount[classSpec.Class .. v.Bis .. v.Phase] or 0) + 1
                if combinedSpecs[classSpec.Class .. v.Bis .. v.Phase] == nil then
                    combinedSpecs[classSpec.Class .. v.Bis .. v.Phase] = { Class = classSpec.Class, Spec = classSpec.Spec, Bis = v.Bis, Phase = v.Phase }
                else
                    combinedSpecs[classSpec.Class .. v.Bis .. v.Phase].Spec = combinedSpecs[classSpec.Class .. v.Bis .. v.Phase].Spec .. ", " .. classSpec.Spec
                end
            end
        end

        for _, v in pairs(combinedSpecs) do
            if v.Class ~= "Druid" and classCount[v.Class .. v.Bis .. v.Phase] == 3 then
                v.Spec = ""
            elseif v.Class == "Druid" and classCount[v.Class .. v.Bis .. v.Phase] == 4 then
                v.Spec = ""
            end
            table.insert(combinedTooltip, { Class = v.Class, Spec = v.Spec, Bis = v.Bis, Phase = v.Phase })
        end
    end

    local function buildCustomTooltip(priorityEntry, combinedTooltip)
        local foundCustom = {}
        if LBISSettings.ShowCustom and priorityEntry ~= nil then
            for k, v in pairs(priorityEntry) do
                local classSpec = LBIS.ClassSpec[k]
                foundCustom[k] = true
                table.insert(combinedTooltip, { Class = classSpec.Class, Spec = classSpec.Spec, Bis = v.TooltipText, Phase = "" })
            end
        end
        return foundCustom
    end

    -- Optimised buildTooltip: uses pre-computed class icon font strings
    local function buildTooltip(tooltip, combinedTooltip)
        if #combinedTooltip > 0 then
            local r, g, b = .9, .8, .5
            tooltip:AddLine(" ", r, g, b, true)
            tooltip:AddLine(LBIS.L["# Best for:"], r, g, b, true)
        end

        for _, v in pairs(combinedTooltip) do
            local classUpper = LBIS.ENGLISH_CLASS[v.Class]:upper()
            local color = RAID_CLASS_COLORS[classUpper]
            -- Use pre-computed icon string instead of rebuilding per line
            local classfontstring = classIconCache[classUpper] or ""

            if v.Phase == "0" or v.Phase == "99" then
                tooltip:AddDoubleLine(classfontstring .. " " .. v.Class .. " " .. v.Spec, v.Bis, color.r, color.g, color.b, color.r, color.g, color.b, true)
            else
                tooltip:AddDoubleLine(classfontstring .. " " .. v.Class .. " " .. v.Spec, v.Bis .. " " .. string_gsub(v.Phase, "0", "P"), color.r, color.g, color.b, color.r, color.g, color.b, true)
            end
        end
    end

    -- Optimised tooltip handlers
    local tooltip_modified = {}

    local function onTooltipSetItem(tooltip)
        local tipName = tooltip:GetName()  -- cache GetName() in a local
        if tooltip_modified[tipName] then
            return
        end
        tooltip_modified[tipName] = true

        local _, itemLink = tooltip:GetItem()
        if not itemLink then return end

        -- Optimisation: use string.match to extract item ID directly
        -- instead of {strsplit(":", itemString)}[2] which creates a
        -- temporary table of all colon-separated fields
        local itemId = tonumber(string_match(itemLink, "item:(%d+)"))
        if not itemId then return end

        LBIS:GetItemInfo(itemId, function(item)
            local combinedTooltip = {}
            local foundCustom = {}

            if LBIS.CustomEditList and LBIS.CustomEditList.Items and LBIS.CustomEditList.Items[itemId] then
                foundCustom = buildCustomTooltip(LBIS.CustomEditList.Items[itemId], combinedTooltip)
            end

            local itemEntries = {}
            if LBIS.ItemsByIdAndSpec[itemId] then
                for key, entry in pairs(LBIS.ItemsByIdAndSpec[itemId]) do
                    itemEntries[key] = entry
                end
            end

            if LBIS.TierSources and LBIS.TierSources[itemId] then
                for _, v in pairs(LBIS.TierSources[itemId]) do
                    if LBIS.CustomEditList and LBIS.CustomEditList.Items and LBIS.CustomEditList.Items[v] then
                        foundCustom = buildCustomTooltip(LBIS.CustomEditList.Items[v], combinedTooltip)
                    end

                    if LBIS.ItemsByIdAndSpec[v] then
                        for key, entry in pairs(LBIS.ItemsByIdAndSpec[v]) do
                            itemEntries[key] = entry
                        end
                    end
                end
            end

            buildCombinedTooltip(itemEntries, combinedTooltip, foundCustom)
            buildTooltip(tooltip, combinedTooltip)
        end)
    end

    local function onTooltipCleared(tooltip)
        tooltip_modified[tooltip:GetName()] = nil
    end

    local function onTooltipSetSpell(tooltip)
        local _, spellId = tooltip:GetSpell()
        if not spellId then return end

        local combinedTooltip = {}

        if LBIS.SpellsByIdAndSpec[spellId] then
            buildCombinedTooltip(LBIS.SpellsByIdAndSpec[spellId], combinedTooltip, {})
        end

        buildTooltip(tooltip, combinedTooltip)
    end

    -- The original addon hooks tooltips on PLAYER_ENTERING_WORLD via
    -- a custom hookScript() function that calls tip:SetScript() with a
    -- stub that chains prehook -> original.  We need to replace those
    -- stubs with our optimised handlers.
    --
    -- Since PatchWerk patches run on ADDON_LOADED and the original
    -- hooks are installed on PLAYER_ENTERING_WORLD (which fires after),
    -- we register our own PEW handler with a one-frame delay to ensure
    -- the original hooks are in place before we overwrite them.
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hookFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- Defer one frame to ensure original hooks are in place
        C_Timer.After(0, function()
            local tooltips = {
                GameTooltip,
                ShoppingTooltip1,
                ShoppingTooltip2,
                ItemRefTooltip,
                ItemRefShoppingTooltip1,
                ItemRefShoppingTooltip2,
            }

            for _, tip in ipairs(tooltips) do
                if tip then
                    tip:SetScript("OnTooltipSetItem", onTooltipSetItem)
                    tip:SetScript("OnTooltipSetSpell", onTooltipSetSpell)
                    tip:SetScript("OnTooltipCleared", onTooltipCleared)
                end
            end
        end)
    end)
end
