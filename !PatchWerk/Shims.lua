-- !PatchWerk/Shims.lua
-- TBC Classic Anniversary (Interface 20505) API compatibility shims.
-- Loads BEFORE all other addons via the "!" prefix naming convention.
-- Provides polyfills for modern WoW (retail/Cata/Wrath) APIs that addons
-- may reference but do not exist in TBC Classic.
--
-- Every shim is guarded so this file is safe to load on any WoW client version.
-- No Ace3 or library dependencies. No event handlers. File-scope code only.
--
-- IMPORTANT: All global writes use rawset() to bypass _G's __newindex
-- metamethod. This prevents WoW's taint tracking from flagging our shims
-- as addon-owned, which would cause ADDON_ACTION_FORBIDDEN when Blizzard
-- secure code (e.g. SpellBookFrame → CastSpell) reads these globals.
-- Similarly, writes to Blizzard tables (Enum, metatables) use rawset()
-- to avoid tainting individual keys.

local rawset = rawset

------------------------------------------------------------------------
-- 1. RunNextFrame
-- Retail convenience wrapper around C_Timer.After with zero delay.
------------------------------------------------------------------------

if not RunNextFrame then
    rawset(_G, "RunNextFrame", function(fn) C_Timer.After(0, fn) end)
end

------------------------------------------------------------------------
-- 2. C_AddOns
-- Retail moved addon management functions into the C_AddOns namespace.
-- In TBC Classic they are plain globals.
--
-- IMPORTANT: Retail's C_AddOns.GetAddOnEnableState(addon, character) has
-- SWAPPED parameter order vs the Classic global GetAddOnEnableState(character, addon).
-- The wrapper below transparently converts the Retail calling convention
-- so addons like ElvUI that use C_AddOns.GetAddOnEnableState(addon, guid)
-- get the correct result from the Classic global.
------------------------------------------------------------------------

local _GetAddOnEnableState = GetAddOnEnableState

if not C_AddOns then
    rawset(_G, "C_AddOns", {
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
        GetAddOnEnableState         = function(addon, character)
            if _GetAddOnEnableState then
                -- Classic API order: (character, addon)
                -- Retail callers may pass a GUID; classic expects a name or nil
                if type(character) == "string" and (character:find("%-") or #character > 12) then
                    character = nil
                end
                return _GetAddOnEnableState(character, addon)
            end
            return 2 -- assume enabled
        end,
    })
end

-- Reverse shims: create globals from C_AddOns for addons that use the old API
if C_AddOns then
    if not IsAddOnLoaded then rawset(_G, "IsAddOnLoaded", C_AddOns.IsAddOnLoaded) end
    if not GetAddOnMetadata then rawset(_G, "GetAddOnMetadata", C_AddOns.GetAddOnMetadata) end
    if not GetAddOnInfo then rawset(_G, "GetAddOnInfo", C_AddOns.GetAddOnInfo) end
    if not GetNumAddOns then rawset(_G, "GetNumAddOns", C_AddOns.GetNumAddOns) end
end

-- Gap-fill: ensure GetAddOnEnableState exists even if C_AddOns was
-- provided natively but is missing this specific function.
if C_AddOns and not C_AddOns.GetAddOnEnableState then
    rawset(C_AddOns, "GetAddOnEnableState", function(addon, character)
        if _GetAddOnEnableState then
            if type(character) == "string" and (character:find("%-") or #character > 12) then
                character = nil
            end
            return _GetAddOnEnableState(character, addon)
        end
        return 2
    end)
end

------------------------------------------------------------------------
-- 3. C_CVar
-- Retail moved CVar access into C_CVar. TBC has plain globals.
------------------------------------------------------------------------

if not C_CVar then
    rawset(_G, "C_CVar", {
        GetCVar     = GetCVar,
        GetCVarBool = GetCVarBool,
        SetCVar     = SetCVar,
    })
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

    local tbl = {}
    rawset(_G, "C_Spell", tbl)

    function tbl.GetSpellName(spellID)
        return (_GetSpellInfo(spellID))
    end

    -- Returns a named table instead of positional values
    function tbl.GetSpellInfo(spellID)
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
    function tbl.GetSpellTexture(spellID)
        local _, _, icon = _GetSpellInfo(spellID)
        return icon, icon
    end

    function tbl.DoesSpellExist(spellID)
        return _GetSpellInfo(spellID) ~= nil
    end

    -- Rank is the 2nd return of GetSpellInfo in TBC
    function tbl.GetSpellSubtext(spellID)
        local _, rank = _GetSpellInfo(spellID)
        return rank
    end

    function tbl.GetSpellDescription(spellID)
        return _GetSpellDesc(spellID)
    end

    -- Returns a named table instead of positional values
    function tbl.GetSpellCooldown(spellID)
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
    function tbl.GetSpellCharges(spellID)
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

    function tbl.GetSpellLink(spellID)
        return _GetSpellLink(spellID)
    end

    function tbl.IsSpellUsable(spellID)
        return _IsUsableSpell(spellID)
    end

    -- No-op: retail uses this to request async spell data loading
    function tbl.RequestLoadSpellData() end

    function tbl.GetSpellCooldownDuration(spellID)
        local _, duration = _GetSpellCooldown(spellID)
        return duration or 0
    end

    -- In TBC Classic spell data is always available synchronously
    function tbl.IsSpellDataCached(spellID)
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

    local tbl = {
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
    rawset(_G, "C_Item", tbl)

    -- Custom shims using different TBC global names or return positions
    function tbl.GetItemIconByID(itemID)
        return _GetItemIcon(itemID)
    end

    function tbl.GetItemQualityByID(itemID)
        return select(3, _GetItemInfo(itemID))
    end

    function tbl.GetItemMaxStackSizeByID(itemID)
        return select(8, _GetItemInfo(itemID))
    end

    function tbl.DoesItemExistByID(itemID)
        return _GetItemInfo(itemID) ~= nil
    end

    -- No-op: retail uses this to request async item data loading
    function tbl.RequestLoadItemDataByID() end

    -- In TBC Classic item data is always available synchronously
    function tbl.IsItemDataCachedByID(itemID)
        return _GetItemInfo(itemID) ~= nil
    end

    -- ItemLocation-based stubs (no TBC equivalent)
    function tbl.DoesItemExist()         return false end
    function tbl.IsLocked()              return false end
    function tbl.GetItemID()             return 0 end
    function tbl.GetItemLink()           return nil end
    function tbl.GetItemIcon()           return nil end
    function tbl.IsItemBindToAccountUntilEquip() return false end
    function tbl.IsItemKeystoneByID()    return false end
end

------------------------------------------------------------------------
-- 6. C_Container
-- Retail moved container/bag APIs into C_Container. TBC has plain globals.
-- GetContainerItemInfo is wrapped to return a named table (retail format).
------------------------------------------------------------------------

if not C_Container then
    local _GetContainerItemInfo = GetContainerItemInfo

    local tbl = {
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
    rawset(_G, "C_Container", tbl)

    -- TBC returns positional values; retail returns a named table
    function tbl.GetContainerItemInfo(bag, slot)
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
    function tbl.GetSortBagsRightToLeft()    return false end
    function tbl.SetSortBagsRightToLeft()    end
    function tbl.GetInsertItemsLeftToRight()  return false end
    function tbl.SetInsertItemsLeftToRight()  end
end

------------------------------------------------------------------------
-- 6b. ContainerFrame1.UpdateCurrencyFrames guard
-- BagBrother/Bagnon checks `if ContainerFrame1.UpdateCurrencyFrames then`
-- and assumes it's a function. In TBC Classic Anniversary it may exist as
-- a non-function value (XML mixin attribute), causing hooksecurefunc() to
-- error. Clear it so BagBrother takes its safe fallback path.
------------------------------------------------------------------------

if ContainerFrame1 and ContainerFrame1.UpdateCurrencyFrames
   and type(ContainerFrame1.UpdateCurrencyFrames) ~= "function" then
    ContainerFrame1.UpdateCurrencyFrames = nil
end

------------------------------------------------------------------------
-- 7. C_UnitAuras
-- Retail restructured UnitAura into C_UnitAuras with table returns.
-- TBC uses the positional-return UnitAura global.
------------------------------------------------------------------------

if not C_UnitAuras then
    local _UnitAura = UnitAura

    local tbl = {}
    rawset(_G, "C_UnitAuras", tbl)

    function tbl.GetAuraDataByIndex(unit, index, filter)
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

    function tbl.GetBuffDataByIndex(unit, index)
        return tbl.GetAuraDataByIndex(unit, index, "HELPFUL")
    end

    function tbl.GetDebuffDataByIndex(unit, index)
        return tbl.GetAuraDataByIndex(unit, index, "HARMFUL")
    end

    function tbl.GetAuraDataBySpellName(unit, spellName, filter)
        for i = 1, 40 do
            local data = tbl.GetAuraDataByIndex(unit, i, filter)
            if not data then return nil end
            if data.name == spellName then return data end
        end
        return nil
    end

    function tbl.IsAuraFilteredOutByInstanceID()
        return false
    end
end

------------------------------------------------------------------------
-- 8. C_CurrencyInfo
-- Retail currency API. TBC has no equivalent token/currency system in
-- the same form, so these return safe empty defaults.
------------------------------------------------------------------------

if not C_CurrencyInfo then
    local tbl = {}
    rawset(_G, "C_CurrencyInfo", tbl)

    function tbl.GetCurrencyInfo()
        return {
            name                    = "",
            quantity                = 0,
            iconFileID              = 0,
            maxQuantity             = 0,
            canEarnPerWeek          = 0,
            quantityEarnedThisWeek  = 0,
        }
    end

    function tbl.GetCurrencyLink()
        return nil
    end
end

------------------------------------------------------------------------
-- 9. C_PlayerInteractionManager
-- Retail API for tracking NPC interaction windows (merchant, banker, etc).
-- TBC has no centralised interaction manager.
------------------------------------------------------------------------

if not C_PlayerInteractionManager then
    local tbl = {}
    rawset(_G, "C_PlayerInteractionManager", tbl)

    function tbl.IsInteractingWithNpcOfType()
        return false
    end

    function tbl.ClearInteraction() end

    function tbl.GetCurrentInteractionType()
        return nil
    end
end

------------------------------------------------------------------------
-- 10. C_DeathInfo
-- Retail API for death/corpse location data.
------------------------------------------------------------------------

if not C_DeathInfo then
    local tbl = {}
    rawset(_G, "C_DeathInfo", tbl)

    function tbl.GetCorpseMapPosition()      return nil end
    function tbl.GetDeathReleasePosition()    return nil end
    function tbl.GetSelfResurrectOptions()    return {} end
end

------------------------------------------------------------------------
-- 11. C_BattleNet
-- Retail Battle.net social API.
------------------------------------------------------------------------

if not C_BattleNet then
    local tbl = {}
    rawset(_G, "C_BattleNet", tbl)

    function tbl.GetCurrentRegion()
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
    local tbl = {}
    rawset(_G, "C_ToyBox", tbl)

    function tbl.GetToyInfo()      return nil end
    function tbl.IsToyUsable()     return false end
    function tbl.GetNumTotalDisplayedToys() return 0 end
    function tbl.GetNumLearnedDisplayedToys() return 0 end
end

------------------------------------------------------------------------
-- 13. C_MountJournal
-- Retail mount journal API. TBC Classic has no mount journal.
------------------------------------------------------------------------

if not C_MountJournal then
    local tbl = {}
    rawset(_G, "C_MountJournal", tbl)

    function tbl.GetMountInfoByID()      return nil end
    function tbl.GetMountInfoExtraByID()  return nil end
    function tbl.GetNumMounts()           return 0 end
    function tbl.GetNumDisplayedMounts()  return 0 end
end

------------------------------------------------------------------------
-- 14. Misc stubs
-- Small namespaces that various addons may reference.
------------------------------------------------------------------------

if not C_System then
    rawset(_G, "C_System", {
        GetFrameStack = function() return {} end,
    })
end

if not C_EventUtils then
    rawset(_G, "C_EventUtils", {
        IsEventValid = function() return true end,
    })
end

if not C_SpecializationInfo then
    rawset(_G, "C_SpecializationInfo", {
        GetPvpTalentSlotInfo = function() return nil end,
    })
end

if not C_Seasons then
    rawset(_G, "C_Seasons", {
        HasActiveSeason = function() return false end,
        GetActiveSeason = function() return 0 end,
    })
end

------------------------------------------------------------------------
-- 15. Enum tables
-- Retail exposes many constants through the global Enum table.
-- These values must match retail exactly as addons compare against them.
-- All writes use rawset() to avoid tainting the Blizzard-owned Enum table.
------------------------------------------------------------------------

if not Enum then rawset(_G, "Enum", {}) end

if not Enum.ItemClass then
    rawset(Enum, "ItemClass", {
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
    })
end

if not Enum.ItemArmorSubclass then
    rawset(Enum, "ItemArmorSubclass", {
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
    })
end

if not Enum.ItemWeaponSubclass then
    rawset(Enum, "ItemWeaponSubclass", {
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
    })
end

if not Enum.ItemMiscellaneousSubclass then
    rawset(Enum, "ItemMiscellaneousSubclass", {
        Junk          = 0,
        Reagent       = 1,
        CompanionPet  = 2,
        Holiday       = 3,
        Other         = 4,
        Mount         = 5,
    })
end

if not Enum.ItemQuality then
    rawset(Enum, "ItemQuality", {
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
    })
end

if not Enum.ItemBind then
    rawset(Enum, "ItemBind", {
        None      = 0,
        OnAcquire = 1,
        OnEquip   = 2,
        OnUse     = 3,
        Quest     = 4,
    })
end

if not Enum.BagIndex then
    rawset(Enum, "BagIndex", {
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
    })
end

if not Enum.PowerType then
    rawset(Enum, "PowerType", {
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
    })
end

if not Enum.PlayerInteractionType then
    rawset(Enum, "PlayerInteractionType", {
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
    })
end

if not Enum.VoiceTtsDestination then
    rawset(Enum, "VoiceTtsDestination", {
        LocalPlayback = 0,
    })
end

-- NOTE: Enum.SpellBookSpellBank intentionally NOT shimmed.
-- Writing to Enum.SpellBookSpellBank taints the global Enum table key,
-- and Blizzard's SpellBookFrame reads it in a secure execution path.
-- This caused ADDON_ACTION_FORBIDDEN on CastSpell() in the spellbook.
-- TBC Classic uses string-based "spell"/"pet" APIs; addons that need
-- this enum already guard with fallbacks (e.g., "... or 'player'").

if not Enum.BagSlotFlags then
    rawset(Enum, "BagSlotFlags", {
        DisableAutoSort      = 1,
        ExcludeJunkSell      = 2,
        ExpansionCurrent     = 4,
        ExpansionLegacy      = 8,
        ClassEquipment       = 16,
        ClassConsumables      = 32,
        ClassProfessionGoods  = 64,
        ClassReagents         = 128,
        ClassJunk             = 256,
    })
end

if not Enum.SeasonID then
    rawset(Enum, "SeasonID", {
        NoSeason          = 0,
        SeasonOfMastery   = 1,
        SeasonOfDiscovery = 2,
        Hardcore          = 3,
        FreshHardcore     = 4,
        Fresh             = 5,
        Placeholder       = 99,
    })
end

if not Enum.UIMapType then
    rawset(Enum, "UIMapType", {
        Cosmic    = 0,
        World     = 1,
        Continent = 2,
        Zone      = 3,
        Dungeon   = 4,
        Micro     = 5,
        Orphan    = 6,
    })
end

------------------------------------------------------------------------
-- 16. SetColorTexture (Texture metatable patch)
-- Retail Texture objects have SetColorTexture(r,g,b,a) which creates a
-- solid-color texture. TBC Classic does NOT have this method.
-- We patch the shared Texture metatable so ALL textures gain the method.
-- Uses WHITE8x8 + SetVertexColor as the safe TBC workaround.
-- Uses rawset() on the metatable __index to avoid tainting the shared
-- Blizzard metatable that secure frames (including SpellBookFrame) use.
------------------------------------------------------------------------

do
    local tmpFrame   = CreateFrame("Frame")
    local tmpTexture = tmpFrame:CreateTexture()
    local mt  = getmetatable(tmpTexture)
    local idx = mt and mt.__index
    if idx and not idx.SetColorTexture then
        rawset(idx, "SetColorTexture", function(self, r, g, b, a)
            self:SetTexture("Interface\\Buttons\\WHITE8x8")
            self:SetVertexColor(r, g, b, a or 1)
        end)
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

    local tbl = {}
    rawset(_G, "EventRegistry", tbl)

    function tbl:RegisterFrameEventAndCallback(event, callback, owner)
        nextHandle = nextHandle + 1
        local handle = nextHandle
        if not frameCallbacks[event] then
            frameCallbacks[event] = {}
            frame:RegisterEvent(event)
        end
        frameCallbacks[event][handle] = { callback = callback, owner = owner }
        return handle
    end

    function tbl:RegisterFrameEventAndCallbackWithHandle(event, callback)
        return self:RegisterFrameEventAndCallback(event, callback, nil)
    end

    function tbl:UnregisterFrameEvent(event, handle)
        local cbs = frameCallbacks[event]
        if not cbs then return end
        cbs[handle] = nil
        if not next(cbs) then
            frameCallbacks[event] = nil
            frame:UnregisterEvent(event)
        end
    end

    function tbl:UnregisterFrameEventAndCallback(event, handle)
        self:UnregisterFrameEvent(event, handle)
    end

    function tbl:RegisterCallback(eventName, callback, owner)
        if not customCallbacks[eventName] then
            customCallbacks[eventName] = {}
        end
        customCallbacks[eventName][owner or callback] = callback
    end

    function tbl:UnregisterCallback(eventName, owner)
        local cbs = customCallbacks[eventName]
        if cbs then
            cbs[owner] = nil
        end
    end

    function tbl:TriggerEvent(eventName, ...)
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
    rawset(_G, "MenuResponse", { Close = 1, Refresh = 2 })
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

    local tbl = {}
    rawset(_G, "MenuUtil", tbl)

    function tbl.CreateContextMenu(anchor, generatorFn, ...)
        local rootDesc = CreateRootDescription()
        generatorFn(anchor, rootDesc, ...)
        EasyMenu(rootDesc:_GetItems(), menuFrame, anchor or "cursor", 0, 0, "MENU")
    end

    function tbl.CreateRootMenuDescription()
        return CreateRootDescription()
    end

    function tbl.CreateRadioMenu(anchor, isSelectedFn, setSelectedFn, ...)
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

    function tbl.CreateCheckboxContextMenu(anchor, isSelectedFn, onClickFn, ...)
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

    function tbl.ShowTooltip(button, tooltipFn)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        tooltipFn(GameTooltip)
        GameTooltip:Show()
    end

    function tbl.HideTooltip()
        GameTooltip:Hide()
    end

    function tbl.HookTooltipScripts(frame, tooltipFn)
        frame:HookScript("OnEnter", function(self)
            tbl.ShowTooltip(self, tooltipFn)
        end)
        frame:HookScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    function tbl.GetElementText(desc)
        return desc and desc.text
    end
end

------------------------------------------------------------------------
-- 19. Settings
-- Retail interface options API. Bridges to TBC's InterfaceOptionsFrame.
------------------------------------------------------------------------

if not Settings then
    local tbl = {}
    rawset(_G, "Settings", tbl)

    function tbl.OpenToCategory(categoryIDOrFrame)
        if InterfaceOptionsFrame_OpenToCategory then
            -- Intentional double-call: Blizzard workaround for the panel
            -- not opening correctly on the first call.
            InterfaceOptionsFrame_OpenToCategory(categoryIDOrFrame)
            InterfaceOptionsFrame_OpenToCategory(categoryIDOrFrame)
        end
    end

    function tbl.RegisterCanvasLayoutCategory(frame, name)
        frame.name = name
        local cat = { ID = name, _frame = frame }
        function cat:GetID() return self.ID end
        return cat
    end

    function tbl.RegisterCanvasLayoutSubcategory(parentCat, frame, name)
        frame.name   = name
        frame.parent = parentCat.ID
        local cat = { ID = name, _frame = frame }
        function cat:GetID() return self.ID end
        return cat
    end

    function tbl.RegisterAddOnCategory(cat)
        if cat and cat._frame and InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(cat._frame)
        end
    end

    function tbl.GetCategory(id)
        return {
            ID = id,
            GetID = function(self) return self.ID end,
        }
    end

    -- Safety stubs: ElvUI's ActionBars module calls Settings.GetValue()
    -- unconditionally inside SettingsPanel_OnHide.  If SettingsPanel exists
    -- but Settings was shimmed (rather than native), these prevent a nil crash.
    function tbl.GetValue()
        return false
    end

    function tbl.SetValue() end
end
