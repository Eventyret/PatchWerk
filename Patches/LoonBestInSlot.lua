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
------------------------------------------------------------------------

local _, ns = ...

------------------------------------------------------------------------
-- Patch metadata (consumed by Options.lua for the settings GUI)
------------------------------------------------------------------------
ns:RegisterPatch("LoonBestInSlot", {
    key = "LoonBestInSlot_apiCompat", label = "Fix Item Lookups",
    help = "Fixes item and spell info loading that would otherwise break on TBC Classic Anniversary.",
    detail = "LoonBestInSlot was built for Retail WoW and uses item and spell lookup methods that do not exist in TBC Classic Anniversary. Without this fix, the addon cannot load item names, icons, or spell info, causing widespread errors and making the addon unusable. This fix swaps in Classic-compatible lookups so everything loads correctly.",
    impact = "FPS", impactLevel = "High", category = "Fixes",
    estimate = "Fixes broken item and spell info that made the addon unusable on Classic",
})
ns:RegisterPatch("LoonBestInSlot", {
    key = "LoonBestInSlot_containerCompat", label = "Fix Bag Scanning",
    help = "Fixes bag scanning so the addon can detect which gear you already own.",
    detail = "LoonBestInSlot scans your bags to mark items you already have, but it uses a bag-reading method that only exists in Retail WoW. On TBC Classic Anniversary, this causes errors when the addon tries to check your inventory. This fix uses the Classic-compatible bag scanning instead.",
    impact = "FPS", impactLevel = "High", category = "Fixes",
    estimate = "Fixes bag scanning so owned items are detected correctly",
})
ns:RegisterPatch("LoonBestInSlot", {
    key = "LoonBestInSlot_settingsCompat", label = "Fix Settings Menu",
    help = "Fixes the /bis settings command and minimap button so they open the options panel without errors.",
    detail = "Typing '/bis settings' or right-clicking the minimap button tries to open the settings panel using a method that only exists in Retail WoW. On TBC Classic Anniversary, this causes an error instead of showing the options. This fix makes both entry points open the settings panel correctly.",
    impact = "FPS", impactLevel = "Medium", category = "Fixes",
    estimate = "Fixes settings menu that would throw errors on Classic",
})
ns:RegisterPatch("LoonBestInSlot", {
    key = "LoonBestInSlot_phaseUpdate", label = "Set Current Phase",
    help = "Sets the gear browser phase to match TBC Classic Anniversary content.",
    detail = "LoonBestInSlot defaults CurrentPhase to 1 which is correct for the current TBC Classic Anniversary release. This patch ensures the phase stays in sync as new content unlocks. Update PatchWerk when new phases release.",
    impact = "FPS", impactLevel = "Low", category = "Tweaks",
    estimate = "Gear browser matches available content",
})
ns:RegisterPatch("LoonBestInSlot", {
    key = "LoonBestInSlot_nilGuards", label = "Fix Missing Items",
    help = "Prevents the addon from breaking when certain items, gems, or enchants have incomplete data.",
    detail = "Some items, gems, or enchants in the database are missing source information (like which boss drops them). When the addon encounters one of these gaps, it crashes and stops loading all remaining items for that spec. This fix safely skips over missing entries so the rest of your gear list loads properly.",
    impact = "FPS", impactLevel = "Medium", category = "Fixes",
    estimate = "Prevents the gear list from breaking when some item sources are missing",
})

local pairs  = pairs
local tonumber = tonumber
local tostring = tostring
local string_match = string.match

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
        rawset(SlashCmdList, "LOONBESTINSLOT", function(command)
            command = (command or ""):lower()
            if command == "settings" then
                openSettings()
            else
                origSlash(command)
            end
        end)
    end

    -- 3b. Hook the LibDataBroker minimap button OnClick
    -- The LDB data object is registered on PLAYER_ENTERING_WORLD, so it
    -- doesn't exist yet at ADDON_LOADED time.  Defer the hook.
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    hookFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        C_Timer.After(0, function()
            local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
            if LDB then
                local dataObj = LDB:GetDataObjectByName("LoonBestInSlot")
                if dataObj and dataObj.OnClick then
                    local origOnClick = dataObj.OnClick
                    dataObj.OnClick = function(clickSelf, button)
                        if button == "RightButton" then
                            openSettings()
                        else
                            origOnClick(clickSelf, button)
                        end
                    end
                end
            end
        end)
    end)
end

------------------------------------------------------------------------
-- 4. LoonBestInSlot_phaseUpdate  (QOL fix)
--
-- LoonBestInSlot defaults CurrentPhase to 1.  This patch sets the phase
-- to match TBC Classic Anniversary's current content release.
-- Update this value as new phases unlock.
--
-- Phase 1: Karazhan, Gruul's Lair, Magtheridon's Lair
-- Phase 2: Serpentshrine Cavern, Tempest Keep
-- Phase 3: Hyjal Summit, Black Temple
-- Phase 4: Zul'Aman
-- Phase 5: Sunwell Plateau
------------------------------------------------------------------------
ns.patches["LoonBestInSlot_phaseUpdate"] = function()
    if not LBIS then return end

    LBIS.CurrentPhase = 1
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

