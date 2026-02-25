-- !PatchWerk/Shims.lua
-- TBC Classic Anniversary (Interface 20505) API compatibility shims.
-- Loads BEFORE all other addons via the "!" prefix naming convention.
-- Provides polyfills for modern WoW (retail/Cata/Wrath) APIs that addons
-- may reference but do not exist in TBC Classic.
--
-- Every shim is guarded so this file is safe to load on any WoW client version.
-- No Ace3 or library dependencies. No event handlers. File-scope code only.

------------------------------------------------------------------------
-- 1. RunNextFrame
-- Retail convenience wrapper around C_Timer.After with zero delay.
------------------------------------------------------------------------

if not RunNextFrame then
    RunNextFrame = function(fn) C_Timer.After(0, fn) end
end

------------------------------------------------------------------------
-- 2. C_AddOns
-- Retail moved addon management functions into the C_AddOns namespace.
-- In TBC Classic they are plain globals.
------------------------------------------------------------------------

if not C_AddOns then
    C_AddOns = {
        GetAddOnMetadata            = GetAddOnMetadata,
        IsAddOnLoaded               = IsAddOnLoaded,
        GetAddOnInfo                = GetAddOnInfo,
        GetNumAddOns                = GetNumAddOns,
        EnableAddOn                 = EnableAddOn,
        DisableAddOn                = DisableAddOn,
        LoadAddOn                   = LoadAddOn,
        IsAddOnLoadOnDemand         = IsAddOnLoadOnDemand,
        GetAddOnDependencies        = GetAddOnDependencies,
        GetAddOnOptionalDependencies = GetAddOnOptionalDependencies,
    }
end

-- Reverse shims: create globals from C_AddOns for addons that use the old API
if C_AddOns then
    if not IsAddOnLoaded then IsAddOnLoaded = C_AddOns.IsAddOnLoaded end
    if not GetAddOnMetadata then GetAddOnMetadata = C_AddOns.GetAddOnMetadata end
    if not GetAddOnInfo then GetAddOnInfo = C_AddOns.GetAddOnInfo end
    if not GetNumAddOns then GetNumAddOns = C_AddOns.GetNumAddOns end
end

------------------------------------------------------------------------
-- 3. C_CVar
-- Retail moved CVar access into C_CVar. TBC has plain globals.
------------------------------------------------------------------------

if not C_CVar then
    C_CVar = {
        GetCVar     = GetCVar,
        GetCVarBool = GetCVarBool,
        SetCVar     = SetCVar,
    }
end

------------------------------------------------------------------------
-- 4. C_Spell
-- Retail restructured spell queries into C_Spell with table-returning
-- functions. TBC Classic uses the positional-return GetSpellInfo global.
------------------------------------------------------------------------

if not C_Spell then
    local _GetSpellInfo     = GetSpellInfo
    local _GetSpellCooldown = GetSpellCooldown
    local _GetSpellCharges  = GetSpellCharges
    local _GetSpellLink     = GetSpellLink
    local _IsUsableSpell    = IsUsableSpell
    local _GetSpellDesc     = GetSpellDescription

    C_Spell = {}

    function C_Spell.GetSpellName(spellID)
        return (_GetSpellInfo(spellID))
    end

    -- Returns a named table instead of positional values
    function C_Spell.GetSpellInfo(spellID)
        local name, rank, icon, castTime, minRange, maxRange, id = _GetSpellInfo(spellID)
        if not name then return nil end
        return {
            name           = name,
            iconID         = icon,
            originalIconID = icon,
            castTime       = castTime,
            minRange       = minRange,
            maxRange       = maxRange,
            spellID        = id,
        }
    end

    -- Returns icon twice; callers use both select(1,...) and select(2,...)
    function C_Spell.GetSpellTexture(spellID)
        local _, _, icon = _GetSpellInfo(spellID)
        return icon, icon
    end

    function C_Spell.DoesSpellExist(spellID)
        return _GetSpellInfo(spellID) ~= nil
    end

    -- Rank is the 2nd return of GetSpellInfo in TBC
    function C_Spell.GetSpellSubtext(spellID)
        local _, rank = _GetSpellInfo(spellID)
        return rank
    end

    function C_Spell.GetSpellDescription(spellID)
        return _GetSpellDesc(spellID)
    end

    -- Returns a named table instead of positional values
    function C_Spell.GetSpellCooldown(spellID)
        local start, duration, enabled = _GetSpellCooldown(spellID)
        if not start then return nil end
        return {
            startTime = start,
            duration  = duration,
            isEnabled = enabled,
            modRate   = 1,
        }
    end

    -- Returns a named table instead of positional values
    function C_Spell.GetSpellCharges(spellID)
        local charges, maxCharges, start, duration, rate = _GetSpellCharges(spellID)
        if not charges then return nil end
        return {
            currentCharges    = charges,
            maxCharges        = maxCharges,
            cooldownStartTime = start,
            cooldownDuration  = duration,
            chargeModRate     = rate or 1,
        }
    end

    function C_Spell.GetSpellLink(spellID)
        return _GetSpellLink(spellID)
    end

    function C_Spell.IsSpellUsable(spellID)
        return _IsUsableSpell(spellID)
    end

    -- No-op: retail uses this to request async spell data loading
    function C_Spell.RequestLoadSpellData() end

    function C_Spell.GetSpellCooldownDuration(spellID)
        local _, duration = _GetSpellCooldown(spellID)
        return duration or 0
    end

    -- In TBC Classic spell data is always available synchronously
    function C_Spell.IsSpellDataCached(spellID)
        return _GetSpellInfo(spellID) ~= nil
    end
end

------------------------------------------------------------------------
-- 5. C_Item
-- Retail moved item queries into C_Item. TBC has plain globals.
-- Also stubs ItemLocation-based APIs that have no TBC equivalent.
------------------------------------------------------------------------

if not C_Item then
    local _GetItemInfo          = GetItemInfo
    local _GetItemInfoInstant   = GetItemInfoInstant
    local _GetItemIcon          = GetItemIcon

    C_Item = {
        -- Direct aliases of TBC globals
        GetItemInfo          = _GetItemInfo,
        GetItemInfoInstant   = _GetItemInfoInstant,
        GetItemCount         = GetItemCount,
        GetItemFamily        = GetItemFamily,
        IsEquippableItem     = IsEquippableItem,
        IsItemInRange        = IsItemInRange,
        IsCurrentItem        = IsCurrentItem,
        IsUsableItem         = IsUsableItem,
        GetItemSpell         = GetItemSpell,
        GetItemQualityColor  = GetItemQualityColor,
        GetItemCooldown      = GetItemCooldown,
    }

    -- Custom shims using different TBC global names or return positions
    function C_Item.GetItemIconByID(itemID)
        return _GetItemIcon(itemID)
    end

    function C_Item.GetItemQualityByID(itemID)
        return select(3, _GetItemInfo(itemID))
    end

    function C_Item.GetItemMaxStackSizeByID(itemID)
        return select(8, _GetItemInfo(itemID))
    end

    function C_Item.DoesItemExistByID(itemID)
        return _GetItemInfo(itemID) ~= nil
    end

    -- No-op: retail uses this to request async item data loading
    function C_Item.RequestLoadItemDataByID() end

    -- In TBC Classic item data is always available synchronously
    function C_Item.IsItemDataCachedByID(itemID)
        return _GetItemInfo(itemID) ~= nil
    end

    -- ItemLocation-based stubs (no TBC equivalent)
    function C_Item.DoesItemExist()         return false end
    function C_Item.IsLocked()              return false end
    function C_Item.GetItemID()             return 0 end
    function C_Item.GetItemLink()           return nil end
    function C_Item.GetItemIcon()           return nil end
    function C_Item.IsItemBindToAccountUntilEquip() return false end
    function C_Item.IsItemKeystoneByID()    return false end
end

------------------------------------------------------------------------
-- 6. C_Container
-- Retail moved container/bag APIs into C_Container. TBC has plain globals.
-- GetContainerItemInfo is wrapped to return a named table (retail format).
------------------------------------------------------------------------

if not C_Container then
    local _GetContainerItemInfo = GetContainerItemInfo

    C_Container = {
        -- Direct aliases
        GetContainerNumSlots     = GetContainerNumSlots,
        GetContainerItemLink     = GetContainerItemLink,
        GetContainerNumFreeSlots = GetContainerNumFreeSlots,
        GetContainerItemID       = GetContainerItemID,
        PickupContainerItem      = PickupContainerItem,
        UseContainerItem         = UseContainerItem,
        ContainerIDToInventoryID = ContainerIDToInventoryID,
        GetItemCooldown          = GetItemCooldown,
    }

    -- TBC returns positional values; retail returns a named table
    function C_Container.GetContainerItemInfo(bag, slot)
        local texture, count, locked, quality, readable, lootable, link, isFiltered, noValue, itemID = _GetContainerItemInfo(bag, slot)
        if not texture then return nil end
        return {
            iconFileID = texture,
            stackCount = count,
            isLocked   = locked,
            quality    = quality,
            isReadable = readable,
            hasLoot    = lootable,
            hyperlink  = link,
            isFiltered = isFiltered,
            hasNoValue = noValue,
            itemID     = itemID,
        }
    end

    -- Stubs for retail-only sorting APIs
    function C_Container.GetSortBagsRightToLeft()    return false end
    function C_Container.SetSortBagsRightToLeft()    end
    function C_Container.GetInsertItemsLeftToRight()  return false end
    function C_Container.SetInsertItemsLeftToRight()  end
end

------------------------------------------------------------------------
-- 7. C_UnitAuras
-- Retail restructured UnitAura into C_UnitAuras with table returns.
-- TBC uses the positional-return UnitAura global.
------------------------------------------------------------------------

if not C_UnitAuras then
    local _UnitAura = UnitAura

    C_UnitAuras = {}

    function C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        local name, icon, count, debuffType, duration, expirationTime,
              source, isStealable, nameplateShowAll, spellId, canApplyAura,
              isBossDebuff, castByPlayer, _, timeMod = _UnitAura(unit, index, filter)
        if not name then return nil end
        return {
            name              = name,
            icon              = icon,
            applications      = count,
            dispelName        = debuffType,
            duration          = duration,
            expirationTime    = expirationTime,
            sourceUnit        = source,
            isStealable       = isStealable,
            spellId           = spellId,
            canApplyAura      = canApplyAura,
            isBossDebuff      = isBossDebuff,
            castByPlayer      = castByPlayer,
            nameplateShowAll  = nameplateShowAll,
            timeMod           = timeMod,
        }
    end

    function C_UnitAuras.GetBuffDataByIndex(unit, index)
        return C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
    end

    function C_UnitAuras.GetDebuffDataByIndex(unit, index)
        return C_UnitAuras.GetAuraDataByIndex(unit, index, "HARMFUL")
    end

    function C_UnitAuras.GetAuraDataBySpellName(unit, spellName, filter)
        for i = 1, 40 do
            local data = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
            if not data then return nil end
            if data.name == spellName then return data end
        end
        return nil
    end

    function C_UnitAuras.IsAuraFilteredOutByInstanceID()
        return false
    end
end

------------------------------------------------------------------------
-- 8. C_CurrencyInfo
-- Retail currency API. TBC has no equivalent token/currency system in
-- the same form, so these return safe empty defaults.
------------------------------------------------------------------------

if not C_CurrencyInfo then
    C_CurrencyInfo = {}

    function C_CurrencyInfo.GetCurrencyInfo()
        return {
            name                    = "",
            quantity                = 0,
            iconFileID              = 0,
            maxQuantity             = 0,
            canEarnPerWeek          = 0,
            quantityEarnedThisWeek  = 0,
        }
    end

    function C_CurrencyInfo.GetCurrencyLink()
        return nil
    end
end

------------------------------------------------------------------------
-- 9. C_PlayerInteractionManager
-- Retail API for tracking NPC interaction windows (merchant, banker, etc).
-- TBC has no centralised interaction manager.
------------------------------------------------------------------------

if not C_PlayerInteractionManager then
    C_PlayerInteractionManager = {}

    function C_PlayerInteractionManager.IsInteractingWithNpcOfType()
        return false
    end

    function C_PlayerInteractionManager.ClearInteraction() end

    function C_PlayerInteractionManager.GetCurrentInteractionType()
        return nil
    end
end

------------------------------------------------------------------------
-- 10. C_DeathInfo
-- Retail API for death/corpse location data.
------------------------------------------------------------------------

if not C_DeathInfo then
    C_DeathInfo = {}

    function C_DeathInfo.GetCorpseMapPosition()      return nil end
    function C_DeathInfo.GetDeathReleasePosition()    return nil end
    function C_DeathInfo.GetSelfResurrectOptions()    return {} end
end

------------------------------------------------------------------------
-- 11. C_BattleNet
-- Retail Battle.net social API.
------------------------------------------------------------------------

if not C_BattleNet then
    C_BattleNet = {}

    function C_BattleNet.GetCurrentRegion()
        if GetCurrentRegion then
            return GetCurrentRegion()
        end
        return 1
    end
end

------------------------------------------------------------------------
-- 12. C_ToyBox
-- Retail toy collection API. TBC Classic has no toy box system.
------------------------------------------------------------------------

if not C_ToyBox then
    C_ToyBox = {}

    function C_ToyBox.GetToyInfo()      return nil end
    function C_ToyBox.IsToyUsable()     return false end
    function C_ToyBox.GetNumTotalDisplayedToys() return 0 end
    function C_ToyBox.GetNumLearnedDisplayedToys() return 0 end
end

------------------------------------------------------------------------
-- 13. C_MountJournal
-- Retail mount journal API. TBC Classic has no mount journal.
------------------------------------------------------------------------

if not C_MountJournal then
    C_MountJournal = {}

    function C_MountJournal.GetMountInfoByID()      return nil end
    function C_MountJournal.GetMountInfoExtraByID()  return nil end
    function C_MountJournal.GetNumMounts()           return 0 end
    function C_MountJournal.GetNumDisplayedMounts()  return 0 end
end

------------------------------------------------------------------------
-- 14. Misc stubs
-- Small namespaces that various addons may reference.
------------------------------------------------------------------------

if not C_System then
    C_System = {
        GetFrameStack = function() return {} end,
    }
end

if not C_EventUtils then
    C_EventUtils = {
        IsEventValid = function() return true end,
    }
end

if not C_SpecializationInfo then
    C_SpecializationInfo = {
        GetPvpTalentSlotInfo = function() return nil end,
    }
end

if not C_Seasons then
    C_Seasons = {
        HasActiveSeason = function() return false end,
        GetActiveSeason = function() return 0 end,
    }
end

------------------------------------------------------------------------
-- 15. Enum tables
-- Retail exposes many constants through the global Enum table.
-- These values must match retail exactly as addons compare against them.
------------------------------------------------------------------------

if not Enum then Enum = {} end

if not Enum.ItemClass then
    Enum.ItemClass = {
        Consumable    = 0,
        Container     = 1,
        Weapon        = 2,
        Gem           = 3,
        Armor         = 4,
        Reagent       = 5,
        Projectile    = 6,
        Tradegoods    = 7,
        ItemEnhancement = 8,
        Recipe        = 9,
        Quiver        = 11,
        Questitem     = 12,
        Key           = 13,
        Miscellaneous = 15,
        Glyph         = 16,
        Battlepet     = 17,
        Profession    = 19,
    }
end

if not Enum.ItemArmorSubclass then
    Enum.ItemArmorSubclass = {
        Generic  = 0,
        Cloth    = 1,
        Leather  = 2,
        Mail     = 3,
        Plate    = 4,
        Cosmetic = 5,
        Shield   = 6,
        Libram   = 7,
        Idol     = 8,
        Totem    = 9,
        Sigil    = 10,
        Relic    = 11,
    }
end

if not Enum.ItemWeaponSubclass then
    Enum.ItemWeaponSubclass = {
        Axe1H        = 0,
        Axe2H        = 1,
        Bows         = 2,
        Guns         = 3,
        Mace1H       = 4,
        Mace2H       = 5,
        Polearm      = 6,
        Sword1H      = 7,
        Sword2H      = 8,
        Warglaive    = 9,
        Staff        = 10,
        Unarmed      = 13,
        Generic      = 14,
        Dagger       = 15,
        Thrown        = 16,
        Crossbow     = 18,
        Wand         = 19,
        Fishingpole  = 20,
    }
end

if not Enum.ItemMiscellaneousSubclass then
    Enum.ItemMiscellaneousSubclass = {
        Junk          = 0,
        Reagent       = 1,
        CompanionPet  = 2,
        Holiday       = 3,
        Other         = 4,
        Mount         = 5,
    }
end

if not Enum.ItemQuality then
    Enum.ItemQuality = {
        Poor      = 0,
        Common    = 1,
        Standard  = 1,
        Uncommon  = 2,
        Good      = 2,
        Rare      = 3,
        Epic      = 4,
        Legendary = 5,
        Artifact  = 6,
        Heirloom  = 7,
        WoWToken  = 8,
    }
end

if not Enum.ItemBind then
    Enum.ItemBind = {
        None      = 0,
        OnAcquire = 1,
        OnEquip   = 2,
        OnUse     = 3,
        Quest     = 4,
    }
end

if not Enum.BagIndex then
    Enum.BagIndex = {
        Backpack     = 0,
        Bag_1        = 1,
        Bag_2        = 2,
        Bag_3        = 3,
        Bag_4        = 4,
        Bank         = -1,
        BankBag_1    = 5,
        BankBag_2    = 6,
        BankBag_3    = 7,
        BankBag_4    = 8,
        BankBag_5    = 9,
        BankBag_6    = 10,
        BankBag_7    = 11,
        Reagentbank  = -3,
        Keyring      = -2,
    }
end

if not Enum.PowerType then
    Enum.PowerType = {
        Mana          = 0,
        Rage          = 1,
        Focus         = 2,
        Energy        = 3,
        ComboPoints   = 4,
        Runes         = 5,
        RunicPower    = 6,
        SoulShards    = 7,
        LunarPower    = 8,
        HolyPower     = 9,
        Alternate     = 10,
        Maelstrom     = 11,
        Chi           = 12,
        Insanity      = 13,
        ArcaneCharges = 16,
        Fury          = 17,
        Pain          = 18,
        Essence       = 19,
        Happiness     = 4,
        Balance       = 20,
    }
end

if not Enum.PlayerInteractionType then
    Enum.PlayerInteractionType = {
        None                    = 0,
        TradePartner            = 1,
        Banker                  = 2,
        GuildBanker             = 3,
        Merchant                = 5,
        Trainer                 = 6,
        Binder                  = 7,
        Auctioneer              = 10,
        MailInfo                = 17,
        ScrappingMachine        = 18,
        VoidStorageBanker       = 19,
        SpiritHealer            = 20,
        ChromieTime             = 21,
        CovenantSanctum         = 22,
        ProfessionsCustomerOrder = 23,
        ItemUpgrade             = 24,
        AccountBanker           = 25,
    }
end

if not Enum.VoiceTtsDestination then
    Enum.VoiceTtsDestination = {
        LocalPlayback = 0,
    }
end

-- NOTE: Enum.SpellBookSpellBank intentionally NOT shimmed.
-- Writing to Enum.SpellBookSpellBank taints the global Enum table key,
-- and Blizzard's SpellBookFrame reads it in a secure execution path.
-- This caused ADDON_ACTION_FORBIDDEN on CastSpell() in the spellbook.
-- TBC Classic uses string-based "spell"/"pet" APIs; addons that need
-- this enum already guard with fallbacks (e.g., "... or 'player'").

if not Enum.BagSlotFlags then
    Enum.BagSlotFlags = {
        DisableAutoSort      = 1,
        ExcludeJunkSell      = 2,
        ExpansionCurrent     = 4,
        ExpansionLegacy      = 8,
        ClassEquipment       = 16,
        ClassConsumables      = 32,
        ClassProfessionGoods  = 64,
        ClassReagents         = 128,
        ClassJunk             = 256,
    }
end

if not Enum.SeasonID then
    Enum.SeasonID = {
        NoSeason          = 0,
        SeasonOfMastery   = 1,
        SeasonOfDiscovery = 2,
        Hardcore          = 3,
        FreshHardcore     = 4,
        Fresh             = 5,
        Placeholder       = 99,
    }
end

if not Enum.UIMapType then
    Enum.UIMapType = {
        Cosmic    = 0,
        World     = 1,
        Continent = 2,
        Zone      = 3,
        Dungeon   = 4,
        Micro     = 5,
        Orphan    = 6,
    }
end

------------------------------------------------------------------------
-- 16. SetColorTexture (Texture metatable patch)
-- Retail Texture objects have SetColorTexture(r,g,b,a) which creates a
-- solid-color texture. TBC Classic does NOT have this method.
-- We patch the shared Texture metatable so ALL textures gain the method.
-- Uses WHITE8x8 + SetVertexColor as the safe TBC workaround.
------------------------------------------------------------------------

do
    local tmpFrame   = CreateFrame("Frame")
    local tmpTexture = tmpFrame:CreateTexture()
    local mt  = getmetatable(tmpTexture)
    local idx = mt and mt.__index
    if idx and not idx.SetColorTexture then
        idx.SetColorTexture = function(self, r, g, b, a)
            self:SetTexture("Interface\\Buttons\\WHITE8x8")
            self:SetVertexColor(r, g, b, a or 1)
        end
    end
end

------------------------------------------------------------------------
-- 17. EventRegistry
-- Retail global event dispatch system used by modern addons and
-- Blizzard UI code alike. Supports both WoW frame events and custom
-- named events with owner/handle-based registration.
------------------------------------------------------------------------

if not EventRegistry then
    local frame = CreateFrame("Frame")
    local frameCallbacks  = {}   -- [event] = { [handle] = { callback, owner } }
    local customCallbacks = {}   -- [eventName] = { [owner] = callback }
    local nextHandle = 0

    frame:SetScript("OnEvent", function(_, event, ...)
        local cbs = frameCallbacks[event]
        if not cbs then return end
        for handle, entry in pairs(cbs) do
            entry.callback(entry.owner or handle, ...)
        end
    end)

    EventRegistry = {}

    function EventRegistry:RegisterFrameEventAndCallback(event, callback, owner)
        nextHandle = nextHandle + 1
        local handle = nextHandle
        if not frameCallbacks[event] then
            frameCallbacks[event] = {}
            frame:RegisterEvent(event)
        end
        frameCallbacks[event][handle] = { callback = callback, owner = owner }
        return handle
    end

    function EventRegistry:RegisterFrameEventAndCallbackWithHandle(event, callback)
        return self:RegisterFrameEventAndCallback(event, callback, nil)
    end

    function EventRegistry:UnregisterFrameEvent(event, handle)
        local cbs = frameCallbacks[event]
        if not cbs then return end
        cbs[handle] = nil
        if not next(cbs) then
            frameCallbacks[event] = nil
            frame:UnregisterEvent(event)
        end
    end

    function EventRegistry:UnregisterFrameEventAndCallback(event, handle)
        self:UnregisterFrameEvent(event, handle)
    end

    function EventRegistry:RegisterCallback(eventName, callback, owner)
        if not customCallbacks[eventName] then
            customCallbacks[eventName] = {}
        end
        customCallbacks[eventName][owner or callback] = callback
    end

    function EventRegistry:UnregisterCallback(eventName, owner)
        local cbs = customCallbacks[eventName]
        if cbs then
            cbs[owner] = nil
        end
    end

    function EventRegistry:TriggerEvent(eventName, ...)
        local cbs = customCallbacks[eventName]
        if not cbs then return end
        for owner, callback in pairs(cbs) do
            callback(owner, ...)
        end
    end
end

------------------------------------------------------------------------
-- 18. MenuUtil + MenuResponse
-- Retail context-menu system. Bridges to TBC's EasyMenu/UIDropDownMenu.
-- MenuResponse is a simple enum used by menu callbacks.
------------------------------------------------------------------------

if not MenuResponse then
    MenuResponse = { Close = 1, Refresh = 2 }
end

if not MenuUtil then
    -- Reusable dropdown frame for EasyMenu display
    local menuFrame = CreateFrame("Frame", "PatchWerkMenuUtilFrame", UIParent, "UIDropDownMenuTemplate")

    -- Creates a rootDescription object that accumulates menu items
    local function CreateRootDescription()
        local items = {}

        local desc = {}

        -- Internal helper: create a sub-description that inserts into a parent entry's menuList
        local function CreateSubDescription(parentEntry)
            local sub = {}
            local subItems = {}

            function sub:CreateTitle(text)
                subItems[#subItems + 1] = { text = text, isTitle = true, notCheckable = true }
                parentEntry.hasArrow = true
                parentEntry.menuList = subItems
                return self
            end

            function sub:CreateButton(text, callback)
                local entry = { text = text, notCheckable = true, func = callback }
                subItems[#subItems + 1] = entry
                parentEntry.hasArrow = true
                parentEntry.menuList = subItems
                return CreateSubDescription(entry)
            end

            function sub:CreateCheckbox(text, isSelectedFn, onClickFn, data)
                subItems[#subItems + 1] = {
                    text       = text,
                    checked    = isSelectedFn,
                    isNotRadio = true,
                    func       = function() onClickFn(data) end,
                }
                parentEntry.hasArrow = true
                parentEntry.menuList = subItems
            end

            function sub:CreateRadio(text, isSelectedFn, onClickFn, value)
                subItems[#subItems + 1] = {
                    text    = text,
                    checked = function() return isSelectedFn(value) end,
                    func    = function() onClickFn(value) end,
                }
                parentEntry.hasArrow = true
                parentEntry.menuList = subItems
            end

            function sub:CreateDivider()
                subItems[#subItems + 1] = { text = "", disabled = true, notCheckable = true }
            end

            function sub:SetTag() end
            function sub:SetScrollMode() end

            function sub:EnumerateElementDescriptions()
                local i = 0
                return function()
                    i = i + 1
                    return subItems[i]
                end
            end

            function sub:Insert(element, index)
                table.insert(subItems, index, element)
                parentEntry.hasArrow = true
                parentEntry.menuList = subItems
            end

            return sub
        end

        function desc:CreateTitle(text)
            items[#items + 1] = { text = text, isTitle = true, notCheckable = true }
            return self
        end

        function desc:CreateButton(text, callback)
            local entry = { text = text, notCheckable = true, func = callback }
            items[#items + 1] = entry
            return CreateSubDescription(entry)
        end

        function desc:CreateCheckbox(text, isSelectedFn, onClickFn, data)
            items[#items + 1] = {
                text       = text,
                checked    = isSelectedFn,
                isNotRadio = true,
                func       = function() onClickFn(data) end,
            }
        end

        function desc:CreateRadio(text, isSelectedFn, onClickFn, value)
            items[#items + 1] = {
                text    = text,
                checked = function() return isSelectedFn(value) end,
                func    = function() onClickFn(value) end,
            }
        end

        function desc:CreateDivider()
            items[#items + 1] = { text = "", disabled = true, notCheckable = true }
        end

        function desc:SetTag() end
        function desc:SetScrollMode() end

        function desc:EnumerateElementDescriptions()
            local i = 0
            return function()
                i = i + 1
                return items[i]
            end
        end

        function desc:Insert(element, index)
            table.insert(items, index, element)
        end

        -- Internal: get the raw items table for EasyMenu
        function desc:_GetItems()
            return items
        end

        return desc
    end

    MenuUtil = {}

    function MenuUtil.CreateContextMenu(anchor, generatorFn, ...)
        local rootDesc = CreateRootDescription()
        generatorFn(anchor, rootDesc, ...)
        EasyMenu(rootDesc:_GetItems(), menuFrame, anchor or "cursor", 0, 0, "MENU")
    end

    function MenuUtil.CreateRootMenuDescription()
        return CreateRootDescription()
    end

    function MenuUtil.CreateRadioMenu(anchor, isSelectedFn, setSelectedFn, ...)
        local items = {}
        local args = { ... }
        for i = 1, #args, 2 do
            local label = args[i]
            local value = args[i + 1]
            items[#items + 1] = {
                text    = label,
                checked = function() return isSelectedFn(value) end,
                func    = function() setSelectedFn(value) end,
            }
        end
        EasyMenu(items, menuFrame, anchor or "cursor", 0, 0, "MENU")
    end

    function MenuUtil.CreateCheckboxContextMenu(anchor, isSelectedFn, onClickFn, ...)
        local items = {}
        local args = { ... }
        for i = 1, #args do
            local entry = args[i]
            if type(entry) == "table" then
                items[#items + 1] = {
                    text       = entry.text or entry[1] or "",
                    checked    = function() return isSelectedFn(entry) end,
                    isNotRadio = true,
                    func       = function() onClickFn(entry) end,
                }
            end
        end
        EasyMenu(items, menuFrame, anchor or "cursor", 0, 0, "MENU")
    end

    function MenuUtil.ShowTooltip(button, tooltipFn)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        tooltipFn(GameTooltip)
        GameTooltip:Show()
    end

    function MenuUtil.HideTooltip()
        GameTooltip:Hide()
    end

    function MenuUtil.HookTooltipScripts(frame, tooltipFn)
        frame:HookScript("OnEnter", function(self)
            MenuUtil.ShowTooltip(self, tooltipFn)
        end)
        frame:HookScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    function MenuUtil.GetElementText(desc)
        return desc and desc.text
    end
end

------------------------------------------------------------------------
-- 19. Settings
-- Retail interface options API. Bridges to TBC's InterfaceOptionsFrame.
------------------------------------------------------------------------

if not Settings then
    Settings = {}

    function Settings.OpenToCategory(categoryIDOrFrame)
        if InterfaceOptionsFrame_OpenToCategory then
            -- Intentional double-call: Blizzard workaround for the panel
            -- not opening correctly on the first call.
            InterfaceOptionsFrame_OpenToCategory(categoryIDOrFrame)
            InterfaceOptionsFrame_OpenToCategory(categoryIDOrFrame)
        end
    end

    function Settings.RegisterCanvasLayoutCategory(frame, name)
        frame.name = name
        local cat = { ID = name, _frame = frame }
        function cat:GetID() return self.ID end
        return cat
    end

    function Settings.RegisterCanvasLayoutSubcategory(parentCat, frame, name)
        frame.name   = name
        frame.parent = parentCat.ID
        local cat = { ID = name, _frame = frame }
        function cat:GetID() return self.ID end
        return cat
    end

    function Settings.RegisterAddOnCategory(cat)
        if cat and cat._frame and InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(cat._frame)
        end
    end

    function Settings.GetCategory(id)
        return {
            ID = id,
            GetID = function(self) return self.ID end,
        }
    end
end
