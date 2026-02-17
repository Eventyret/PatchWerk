-- Options: GUI settings panel and slash command interface for PatchWerk
--
-- Provides a scrollable Blizzard Interface Options panel with patch toggles
-- grouped by target addon, impact badges, and user-friendly descriptions.

local _, ns = ...

-- Impact badge colors
local BADGE_COLORS = {
    FPS     = { r = 0.2, g = 0.9, b = 0.2 },   -- green
    Memory  = { r = 0.2, g = 0.8, b = 0.9 },   -- cyan
    Network = { r = 1.0, g = 0.6, b = 0.2 },   -- orange
}

local LEVEL_COLORS = {
    High   = { r = 1.0, g = 0.82, b = 0.0 },  -- gold
    Medium = { r = 0.75, g = 0.75, b = 0.75 }, -- silver
    Low    = { r = 0.6, g = 0.4, b = 0.2 },    -- bronze
}

-- Patch metadata: labels, help text, detail tooltips, and impact info
local PATCH_INFO = {
    -- Details
    { key = "Details_hexFix",        group = "Details",  label = "Color Rendering Fix",
      help = "Fixes slow color calculations in damage meter bars.",
      detail = "Details converts RGB values to hex strings 50+ times per window refresh using slow character-by-character work. This causes visible stuttering when you have multiple damage meter windows open during heavy combat, especially on Classic's older engine.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Details_fadeHandler",   group = "Details",  label = "Idle Animation Saver",
      help = "Stops the fade system from wasting resources when no bars are animating.",
      detail = "The fade animation system runs constantly even when nothing is fading, wasting resources thousands of times per minute. The fix makes it sleep when idle and only wake up when bars actually need to fade.",
      impact = "FPS", impactLevel = "Low" },
    { key = "Details_refreshCap",    group = "Details",  label = "Refresh Rate Cap",
      help = "Prevents the damage meter from refreshing way too fast, which can tank performance on Classic.",
      detail = "Details tries to refresh at 60fps when streamer mode is enabled, which is way too fast for Classic. This causes severe FPS drops during combat. The fix caps refreshes at 10 per second, which is still plenty responsive.",
      impact = "FPS", impactLevel = "High" },
    { key = "Details_npcIdCache",    group = "Details",  label = "Enemy Info Cache",
      help = "Remembers enemy info so it doesn't have to figure it out again during every fight.",
      detail = "Details figures out enemy IDs using slow pattern matching, and redoes this dozens of times per refresh for the same enemies. During raid boss fights with many adds, this causes noticeable lag spikes when the meter updates.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Details_formatCache",   group = "Details",  label = "Number Format Cache",
      help = "Caches formatted damage and heal numbers to avoid recalculating the same values.",
      detail = "Details formats the same damage totals repeatedly during each window refresh -- 10-50 times across multiple meter windows. This patch caches the last 200 formatted results so identical numbers are returned instantly instead of rebuilt every time.",
      impact = "FPS", impactLevel = "Medium" },
    -- Plater
    { key = "Plater_fpsCheck",       group = "Plater",   label = "Timer Leak Fix",
      help = "Fixes a Plater bug that wastes memory by creating 60+ temporary timers per second.",
      detail = "Plater creates 60+ temporary objects every second just to track your FPS, which causes memory buildup over time. During heavy combat with many nameplates visible, this contributes to stuttering. The fix uses a single reusable tracker instead.",
      impact = "Memory", impactLevel = "High" },
    { key = "Plater_healthText",     group = "Plater",   label = "Health Text Skip",
      help = "Skips nameplate health text updates when the value hasn't changed.",
      detail = "Plater reformats nameplate health text on every update even when HP hasn't changed. With 20-40 nameplates visible in a dungeon or raid, that's thousands of wasted text updates per second for no visual benefit.",
      impact = "FPS", impactLevel = "Low" },
    { key = "Plater_auraAlign",      group = "Plater",   label = "Aura Icon Guard",
      help = "Skips reshuffling buff/debuff icons on nameplates when nothing changed.",
      detail = "Plater reshuffles buff and debuff icons on nameplates 200+ times per second during combat, creating throwaway data each time. This causes stutters when you have many visible nameplates with multiple buffs or debuffs active.",
      impact = "Memory", impactLevel = "Medium" },
    -- Pawn
    { key = "Pawn_cacheIndex",       group = "Pawn",     label = "Fast Item Lookup",
      help = "Makes Pawn find item info much faster instead of searching through hundreds of entries.",
      detail = "Pawn searches through up to 200 cached items one by one every time you hover an item. When you're rapidly mousing over loot or vendor items, this causes tooltip lag where there's a visible delay before Pawn's upgrade arrows appear.",
      impact = "FPS", impactLevel = "High" },
    { key = "Pawn_tooltipDedup",     group = "Pawn",     label = "Duplicate Tooltip Guard",
      help = "Stops Pawn from checking the same item multiple times when you mouse over it.",
      detail = "Multiple tooltip updates fire for the same item, causing Pawn to calculate upgrade scores 2-4 times per hover. This makes tooltips feel sluggish, especially with multiple stat scales enabled.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Pawn_upgradeCache",     group = "Pawn",     label = "Upgrade Result Cache",
      help = "Remembers if an item is an upgrade so Pawn doesn't recheck all your gear on every hover.",
      detail = "Pawn recalculates upgrade comparisons against all your equipped gear for every item you hover, every single time. With 2-3 active stat scales, hovering loot during a dungeon run causes noticeable tooltip delays.",
      impact = "FPS", impactLevel = "High" },
    -- TipTac
    { key = "TipTac_unitAppearanceGuard", group = "TipTac", label = "Non-Unit Tooltip Guard",
      help = "Stops TipTac from constantly updating when you're hovering items instead of players.",
      detail = "TipTac runs appearance updates constantly for every visible tooltip, including item and spell tooltips where no player or NPC is shown. This wastes resources when you're hovering items in bags or on vendors.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "TipTac_inspectCache",   group = "TipTac",   label = "Extended Inspect Cache",
      help = "Reduces inspect requests from every 5s to every 30s for recently inspected players.",
      detail = "TipTac re-inspects players every 5 seconds when you hover them, sending repeated requests to the server. In crowded cities or raids, this causes inspect delays for everyone. The fix extends the cache to 30 seconds.",
      impact = "Network", impactLevel = "Medium" },
    -- Questie
    { key = "Questie_questLogThrottle", group = "Questie", label = "Quest Log Throttle",
      help = "Limits quest log refreshes to twice per second when multiple quests update at once.",
      detail = "Questie scans your entire quest log multiple times per second during active questing -- every mob kill, quest progress tick, and zone change triggers it. This causes noticeable FPS drops when you have 20+ active quests, especially in crowded quest hubs.",
      impact = "FPS", impactLevel = "High" },
    { key = "Questie_availableQuestsDebounce", group = "Questie", label = "Quest Availability Batch",
      help = "Combines rapid quest availability checks into one update instead of several.",
      detail = "When you accept, complete, or abandon a quest, Questie recalculates all available quests 4-6 times in rapid succession. Each pass checks thousands of quests in its database, causing a brief freeze or stutter.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Questie_framePoolPrealloc", group = "Questie", label = "Frame Pool Warmup",
      help = "Pre-creates quest icon frames at login to prevent stuttering when entering new zones.",
      detail = "Questie creates map icon frames on-demand, causing brief stutters when you enter a new zone or accept several quests at once. This patch pre-creates 20 frames during the loading screen so they're ready when needed, eliminating the stutter.",
      impact = "FPS", impactLevel = "Medium" },
    -- LFGBulletinBoard
    { key = "LFGBulletinBoard_updateListDirty", group = "LFGBulletinBoard", label = "Smart List Refresh",
      help = "Skips the full group list rebuild when nothing actually changed.",
      detail = "The LFG panel rebuilds the entire group list every second while open, even when no new messages have arrived. This causes constant stuttering when browsing for groups, especially when you have 50+ listings visible.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "LFGBulletinBoard_sortSkip", group = "LFGBulletinBoard", label = "Sort Interval Throttle",
      help = "Limits group list sorting to once every 2 seconds.",
      detail = "The group list re-sorts every second regardless of changes. When you have a large list of group postings, this continuous sorting causes visible UI stuttering and makes it harder to click on entries.",
      impact = "FPS", impactLevel = "Low" },
    -- Bartender4
    { key = "Bartender4_lossOfControlSkip", group = "Bartender4", label = "Loss of Control Skip",
      help = "Stops pointless 120-button scans for loss-of-control effects that don't exist on Classic.",
      detail = "Bartender4 scans all 120 action buttons for loss-of-control effects on every event, but these effects don't exist on Classic. This wastes resources constantly during combat for checks that always find nothing.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Bartender4_usableThrottle", group = "Bartender4", label = "Button State Batch",
      help = "Combines rapid action bar updates (triggered on every mana tick) into a single check.",
      detail = "Action bars update on every mana tick, target change, and buff/debuff change, causing Bartender4 to recheck all 120 buttons multiple times per second. During intense combat, this can make button highlights and range coloring feel sluggish.",
      impact = "FPS", impactLevel = "High" },
    { key = "Bartender4_pressAndHoldGuard", group = "Bartender4", label = "Combat SetAttribute Fix",
      help = "Stops 19x ADDON_ACTION_BLOCKED errors from Blizzard's backported press-and-hold code.",
      detail = "TBC Anniversary backported retail ActionButton code that calls SetAttribute() on hidden Blizzard bar buttons during combat. Since Bartender4 manages these buttons, the protected call is blocked, flooding BugSack with ~19 errors per combat entry. The fix adds an InCombatLockdown() guard.",
      impact = "FPS", impactLevel = "High" },
    -- TitanPanel
    { key = "TitanPanel_reputationsOnUpdate", group = "TitanPanel", label = "Reputation Timer Fix",
      help = "Checks your reputation every 5 seconds instead of constantly.",
      detail = "The reputation plugin checks for updates every single frame even though it only needs to update every few seconds. This wastes 300+ checks per second just to see if it's time to refresh yet.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "TitanPanel_bagDebounce", group = "TitanPanel", label = "Bag Update Batch",
      help = "Counts bag contents once after looting instead of on every individual slot change.",
      detail = "Titan Panel scans all your bags on every individual bag change. When you loot multiple items quickly, this triggers 4-10 full bag scans in under a second, causing brief stutters. The fix waits for looting to finish before scanning once.",
      impact = "FPS", impactLevel = "Low" },
    { key = "TitanPanel_performanceThrottle", group = "TitanPanel", label = "Performance Display Throttle",
      help = "Updates the FPS/memory display every 3s instead of every 1.5s.",
      detail = "The FPS and memory display updates every 1.5 seconds, checking memory usage across all loaded addons. Ironically, these frequent checks themselves contribute to the performance overhead being displayed.",
      impact = "FPS", impactLevel = "Low" },
    -- OmniCC
    { key = "OmniCC_gcdSpellCache", group = "OmniCC", label = "Cooldown Status Cache",
      help = "Checks the Global Cooldown once per update instead of 20+ times.",
      detail = "Every time you press an ability and trigger the global cooldown, OmniCC checks it 20+ times across all your action bars. This creates micro-stuttering during ability spam, especially noticeable in PvP and fast raid rotations.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "OmniCC_ruleMatchCache", group = "OmniCC", label = "Display Rule Cache",
      help = "Remembers which cooldown display settings apply to each ability. Resets on profile change.",
      detail = "OmniCC figures out which display settings apply to each cooldown by checking every one against a list of rules. Since these never change during gameplay, it's doing hundreds of identical lookups for no reason.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "OmniCC_finishEffectGuard", group = "OmniCC", label = "Finish Effect Guard",
      help = "Skips cooldown finish animations for abilities that aren't close to coming off cooldown.",
      detail = "OmniCC tries to play cooldown-finished animations even for abilities that are nowhere near ready. The fix skips this wasted work unless an ability is actually within 2 seconds of being usable again.",
      impact = "FPS", impactLevel = "Low" },
    -- Prat-3.0
    { key = "Prat_smfThrottle", group = "Prat", label = "Chat Layout Throttle",
      help = "Reduces chat window updates from 60 to 20 per second. Full speed when you mouse over chat.",
      detail = "With features like Hover Highlighting enabled, Prat recalculates every visible chat line 60 times per second. With 4 chat frames open that's thousands of updates per second. This patch drops it to 20 per second with no visible difference.",
      impact = "FPS", impactLevel = "High" },
    { key = "Prat_timestampCache", group = "Prat", label = "Timestamp Cache",
      help = "Creates chat timestamps once per second instead of recalculating for every single message.",
      detail = "Prat rebuilds the timestamp text from scratch for every single chat message, even when 10 messages arrive in the same second. During busy raid chat or trade spam, this causes unnecessary frame drops.",
      impact = "Memory", impactLevel = "Low" },
    { key = "Prat_bubblesGuard", group = "Prat", label = "Bubble Scan Guard",
      help = "Skips chat bubble scanning when no one is talking nearby.",
      detail = "Prat scans for chat bubbles 10 times per second even when you're completely alone or in an instance where no one is talking. The fix skips this entirely when no bubbles exist.",
      impact = "FPS", impactLevel = "Low" },
    { key = "Prat_playerNamesThrottle", group = "Prat", label = "Player Info Throttle",
      help = "Throttles player name lookups during aura updates to 5 times per second.",
      detail = "Prat's PlayerNames module processes UNIT_AURA events to track player class and name info for chat coloring. In raids, these events fire 20-50 times per second but player names never change on aura updates. This patch throttles the handler to 5Hz.",
      impact = "FPS", impactLevel = "Low" },
    { key = "Prat_guildRosterThrottle", group = "Prat", label = "Guild Roster Rate Limit",
      help = "Stops Prat from requesting guild roster data in a feedback loop.",
      detail = "Prat requests a full guild roster refresh every time it receives a roster update from the server, creating a feedback loop that generates constant network traffic. In a large active guild with members logging in and out, this produces unnecessary server requests every few seconds. The fix limits roster requests to once per 15 seconds.",
      impact = "Network", impactLevel = "Medium" },
    -- GatherMate2
    { key = "GatherMate2_minimapThrottle", group = "GatherMate2", label = "Minimap Pin Throttle",
      help = "Updates minimap gathering pins less often (20 instead of 60 times/sec) with no visible difference.",
      detail = "GatherMate2 updates your minimap gathering pins 60 times per second. This creates noticeable stuttering while flying or riding through zones with lots of nodes. The fix caps it at 20 per second -- still buttery smooth but much lighter.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "GatherMate2_rebuildGuard", group = "GatherMate2", label = "Stationary Rebuild Skip",
      help = "Skips minimap node rebuilds when you're standing still.",
      detail = "Every 2 seconds, GatherMate2 rebuilds all minimap nodes by recalculating distances and positions, even when you're standing still at the auction house. The fix skips these pointless rebuilds when you haven't moved.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "GatherMate2_cleuUnregister", group = "GatherMate2", label = "Remove Unused Combat Handler",
      help = "Removes leftover code in GatherMate2 that runs during every fight but does nothing useful.",
      detail = "GatherMate2 processes every combat log event during fights looking for gas cloud extraction, but this feature is completely unused in TBC. In raids, that's 200+ wasted checks per second during boss encounters.",
      impact = "FPS", impactLevel = "Medium" },
    -- Quartz
    { key = "Quartz_castBarThrottle", group = "Quartz", label = "Cast Bar 30fps Cap",
      help = "Caps cast bar animations at 30fps -- looks identical, uses half the resources.",
      detail = "Quartz animates cast bars at 60fps, but you can't visually tell the difference between 60fps and 30fps on a 1-3 second cast. The fix caps it at 30fps, cutting the work in half with zero visual difference.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Quartz_swingBarThrottle", group = "Quartz", label = "Swing Timer 30fps Cap",
      help = "Caps the swing timer at 30fps -- no visible difference on a 2-3 second swing.",
      detail = "The swing timer updates 60 times per second during auto-attack, but a 2-3 second swing looks identical at 30fps. This halves the animation work for melee classes and hunters.",
      impact = "FPS", impactLevel = "Low" },
    { key = "Quartz_gcdBarThrottle", group = "Quartz", label = "GCD Bar 30fps Cap",
      help = "Caps the global cooldown bar at 30fps -- plenty smooth for a 1.5 second bar.",
      detail = "The GCD bar runs at 60fps during every 1.5 second global cooldown. That's complete overkill for such a short bar. The fix caps it at 30fps, which is still perfectly smooth.",
      impact = "FPS", impactLevel = "Low" },
    { key = "Quartz_buffBucket", group = "Quartz", label = "Buff Bar Update Throttle",
      help = "Limits buff bar updates during rapid target switching to once per 100ms.",
      detail = "The Buff module iterates up to 72 auras (32 buffs + 40 debuffs) on every target or focus change. During rapid tab-targeting or healer mouse-over targeting, this can fire dozens of times per second. This patch throttles it to 10Hz with no visible delay.",
      impact = "FPS", impactLevel = "Medium" },
    -- Auctionator
    { key = "Auctionator_ownerQueryThrottle", group = "Auctionator", label = "Auction Query Throttle",
      help = "Reduces server queries at the auction house from constant to once per second.",
      detail = "Auctionator queries the server 60 times per second while you're on the Selling or Cancelling tabs. Your auction data only changes when you post or cancel, not every frame. The fix limits queries to once per second.",
      impact = "Network", impactLevel = "High" },
    { key = "Auctionator_throttleBroadcast", group = "Auctionator", label = "Timer Display Throttle",
      help = "Reduces the auction throttle timer display from 60 updates/sec to 2.",
      detail = "The auction throttle countdown timer updates 60 times per second just to show a number counting down. You don't need frame-perfect precision for a countdown. The fix drops it to 2 updates per second.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Auctionator_priceAgeOptimize", group = "Auctionator", label = "Price Age Optimizer",
      help = "Makes price freshness calculations faster and lighter on memory.",
      detail = "Every time you hover over an item, Auctionator creates throwaway data, sorts it, then discards it just to check how old the price is. During quick auction scans this causes tooltip lag. The fix does it without any throwaway data.",
      impact = "Memory", impactLevel = "Medium" },
    { key = "Auctionator_dbKeyCache", group = "Auctionator", label = "Price Lookup Cache",
      help = "Remembers item price lookups so Auctionator doesn't redo them every time you hover.",
      detail = "Auctionator converts item links to price lookups using expensive conversions every single time you hover an item. If you mouseover the same item 10 times, it does the same work 10 times. The fix remembers results.",
      impact = "FPS", impactLevel = "Medium" },
    -- VuhDo
    { key = "VuhDo_debuffDebounce", group = "VuhDo", label = "Debuff Scan Batch",
      help = "During heavy AoE damage, combines debuff checks instead of running 100+ per second.",
      detail = "During heavy AoE damage in raids, VuhDo's debuff checker fires 100+ times per second as aura updates flood in. This creates raid frame stuttering during encounters like Lurker or Vashj. The fix combines checks within 33ms windows.",
      impact = "FPS", impactLevel = "High" },
    { key = "VuhDo_rangeSkipDead", group = "VuhDo", label = "Skip Dead Range Checks",
      help = "Skips range checking on dead or disconnected raid members.",
      detail = "VuhDo checks range on every raid member continuously, making multiple checks per person per update. Dead and disconnected players obviously can't change range, but VuhDo checks them anyway. In a 25-man with deaths, that's a lot of wasted work.",
      impact = "FPS", impactLevel = "Low" },
    { key = "VuhDo_inspectThrottle", group = "VuhDo", label = "Inspect Request Throttle",
      help = "Reduces server inspect requests from every 2 seconds to every 5 seconds.",
      detail = "VuhDo sends a NotifyInspect server request every 2.1 seconds to determine raid members' specs and roles. In a 25-man raid, this means continuous inspect traffic for the entire session as members join, leave, or go out of range. The fix spaces requests to every 5 seconds, cutting server traffic by 60%.",
      impact = "Network", impactLevel = "Medium" },
    -- Cell
    { key = "Cell_debuffOrderMemo", group = "Cell", label = "Debuff Priority Cache",
      help = "Remembers the last debuff priority check to skip a duplicate lookup that happens every update.",
      detail = "Cell checks debuff priority twice in a row for the same debuff during updates -- once from the debuff scan and once from the raid debuff check. The fix remembers the last result and skips the duplicate lookup.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Cell_customIndicatorGuard", group = "Cell", label = "Custom Indicator Guard",
      help = "Skips custom indicator processing when you don't have any set up.",
      detail = "Cell processes custom indicators for every aura on every raid frame, even if you don't have any custom indicators set up. Most players use default settings, so this is wasted work on every update. The fix detects this and skips the whole system.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Cell_debuffGlowMemo", group = "Cell", label = "Debuff Glow Cache",
      help = "Remembers which debuffs should glow on your raid frames to avoid rechecking.",
      detail = "Cell checks which debuffs should glow immediately after checking their priority, using the same information both times. The fix remembers the last result and reuses it, cutting the work in half.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "Cell_inspectQueueThrottle", group = "Cell", label = "Inspect Queue Throttle",
      help = "Slows down Cell's inspect burst from 4 requests/sec to once per 1.5 seconds.",
      detail = "When you join a group, Cell's LibGroupInfo fires NotifyInspect server requests every 0.25 seconds -- that's 4 per second. In a 25-man raid, it sends 24 inspect requests in just 6 seconds, most of which get silently dropped by the server and need retries. The fix spaces them to every 1.5 seconds, which the server handles cleanly.",
      impact = "Network", impactLevel = "Medium" },
    -- BigDebuffs
    { key = "BigDebuffs_hiddenDebuffsHash", group = "BigDebuffs", label = "Fast Hidden Debuff Check",
      help = "Speeds up hidden debuff checks by using a smarter lookup method.",
      detail = "BigDebuffs scans through its hidden debuff list one by one for every aura on every unit frame. With 40 aura slots checked per unit, this adds up fast during raid encounters. The fix uses instant lookups instead of scanning the whole list.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "BigDebuffs_attachFrameGuard", group = "BigDebuffs", label = "Frame Anchor Cache",
      help = "Remembers where to place debuff icons instead of searching all frame addons every time.",
      detail = "BigDebuffs searches through 9 different frame integrations (ElvUI, Cell, NDui, etc.) on every single aura update to figure out where to place icons. It finds the same answer every time until you reload. The fix remembers which frames go with which units.",
      impact = "FPS", impactLevel = "High" },
    -- EasyFrames
    { key = "EasyFrames_healthTextFix", group = "EasyFrames", label = "Health Text Fix",
      help = "Fixes confusing 'T' suffix on health numbers -- changes to standard K/M/B abbreviations.",
      detail = "EasyFrames uses 'T' for thousands (e.g. '36T' for 36,000 HP) which looks like trillions. It also mislabels values in the 1-9.9 million range as 'T'. The fix replaces the number formatting with standard K (thousands), M (millions), B (billions).",
      impact = "FPS", impactLevel = "Low" },
    -- BugSack
    { key = "BugSack_settingsCompat", group = "BugSack", label = "Settings API Compat",
      help = "Fixes Settings.OpenToCategory calls that crash on TBC Classic Anniversary.",
      detail = "BugSack's latest version uses the Retail Settings.OpenToCategory API in three places (slash command, sack right-click, LDB right-click). This API does not exist in TBC Classic. The fix replaces these calls with InterfaceOptionsFrame_OpenToCategory which works on Classic.",
      impact = "FPS", impactLevel = "High" },
    { key = "BugSack_formatCache", group = "BugSack", label = "Format Result Cache",
      help = "Caches formatted error text to avoid redundant string processing on repeated views.",
      detail = "FormatError runs 15 gsub calls (8 for stack colorization, 7 for locals colorization) every time an error is displayed, even if the same error was already formatted. With many errors, scrolling through the sack causes repeated expensive string work. The fix caches the result on the error object and invalidates when the counter changes.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "BugSack_searchThrottle", group = "BugSack", label = "Search Debounce",
      help = "Delays search filtering until you stop typing, preventing lag on every keystroke.",
      detail = "The sack's search box runs filterSack on every OnTextChanged event, doing a linear string.find scan across all captured errors' message, stack, and locals fields. With hundreds of errors, this causes noticeable input lag while typing. The fix debounces the search with a 0.3 second idle delay.",
      impact = "FPS", impactLevel = "Low" },
    -- LoonBestInSlot
    { key = "LoonBestInSlot_apiCompat", group = "LoonBestInSlot", label = "Item/Spell API Compat",
      help = "Replaces retail Item:CreateFromItemID and Spell:CreateFromSpellID with classic equivalents.",
      detail = "LoonBestInSlot uses retail-only APIs (Item:CreateFromItemID, C_Item.GetItemInfoInstant, Spell:CreateFromSpellID, C_Spell.GetSpellTexture) that do not exist in TBC Classic Anniversary. The fix replaces LBIS:GetItemInfo and LBIS:GetSpellInfo with implementations using the classic GetItemInfo() and GetSpellInfo() globals, preserving the same cache logic and return object shapes.",
      impact = "FPS", impactLevel = "High" },
    { key = "LoonBestInSlot_containerCompat", group = "LoonBestInSlot", label = "Container API Compat",
      help = "Replaces C_Container calls with classic GetContainerNumSlots/GetContainerItemLink.",
      detail = "The user item cache scans bags using C_Container.GetContainerNumSlots and C_Container.GetContainerItemLink which do not exist in TBC Classic. The fix replaces LBIS:BuildItemCache to use the classic global equivalents.",
      impact = "FPS", impactLevel = "High" },
    { key = "LoonBestInSlot_settingsCompat", group = "LoonBestInSlot", label = "Settings Panel Compat",
      help = "Replaces Settings.OpenToCategory with InterfaceOptionsFrame_OpenToCategory for Classic.",
      detail = "The slash command handler (/bis settings) and minimap button right-click call Settings.OpenToCategory which does not exist in TBC Classic. The fix hooks both entry points to use InterfaceOptionsFrame_OpenToCategory instead.",
      impact = "FPS", impactLevel = "Medium" },
    { key = "LoonBestInSlot_phaseUpdate", group = "LoonBestInSlot", label = "Phase 5 Unlock",
      help = "Sets CurrentPhase to 5 so all TBC Anniversary items are visible in the browser.",
      detail = "LoonBestInSlot defaults to Phase 1, hiding all Phase 2-5 items from tooltips and the gear browser. TBC Classic Anniversary has all content through Phase 5 available. The fix sets CurrentPhase to 5 at load time.",
      impact = "FPS", impactLevel = "Low" },
    { key = "LoonBestInSlot_nilGuards", group = "LoonBestInSlot", label = "Missing Source Guards",
      help = "Prevents Lua errors when item, gem, or enchant source data is missing.",
      detail = "LBIS:AddItem, LBIS:AddGem, and LBIS:AddEnchant access properties on source lookup tables (ItemSources, GemSources, EnchantSources) without checking for nil. If any source entry is missing, the error halts loading of all subsequent items for that spec. The fix wraps each function with a nil check.",
      impact = "FPS", impactLevel = "Medium" },
    -- NovaInstanceTracker
    { key = "NovaInstanceTracker_weeklyResetGuard", group = "NovaInstanceTracker", label = "Weekly Reset API Guard",
      help = "Prevents a crash on login from missing C_DateAndTime API in TBC Classic.",
      detail = "NovaInstanceTracker calls C_DateAndTime.GetSecondsUntilWeeklyReset() during initialization without checking if the API exists. This API is not available in TBC Classic Anniversary, causing the addon to error on every login. The fix adds a nil guard so the function returns safely.",
      impact = "FPS", impactLevel = "High" },
    { key = "NovaInstanceTracker_settingsCompat", group = "NovaInstanceTracker", label = "Settings Panel Compat",
      help = "Fixes the /nit config command that crashes on TBC Classic due to missing Settings API.",
      detail = "The openConfig function calls Settings.OpenToCategory which only exists in Retail 10.0+. On TBC Classic this crashes when the user tries to open settings. The fix falls back to InterfaceOptionsFrame_OpenToCategory.",
      impact = "FPS", impactLevel = "High" },
}

-- Estimated performance improvement per patch (shown in detail tooltip)
local PATCH_ESTIMATES = {
    -- Details
    Details_hexFix = "~1-2 FPS in combat with multiple meter windows",
    Details_fadeHandler = "Eliminates idle CPU waste when no bars are fading",
    Details_refreshCap = "~3-8 FPS in combat with streamer mode enabled",
    Details_npcIdCache = "~1-3 FPS during large pulls with many adds",
    Details_formatCache = "~1-2 FPS with multiple meter windows open",
    -- Plater
    Plater_fpsCheck = "~2-4 FPS, fewer garbage collection stutters",
    Plater_healthText = "~0.5-1 FPS with 20+ nameplates visible",
    Plater_auraAlign = "~1-3 FPS with many nameplates in combat",
    -- Pawn
    Pawn_cacheIndex = "Noticeably snappier tooltips when hovering items",
    Pawn_tooltipDedup = "Faster tooltip display with multiple stat scales",
    Pawn_upgradeCache = "Instant upgrade arrows on items you've seen before",
    -- TipTac
    TipTac_unitAppearanceGuard = "~0.5-1 FPS while hovering items in bags",
    TipTac_inspectCache = "80% fewer inspect requests, less server lag",
    -- Questie
    Questie_questLogThrottle = "~2-4 FPS during active questing with 20+ quests",
    Questie_availableQuestsDebounce = "Eliminates brief freeze on quest accept/complete",
    Questie_framePoolPrealloc = "Smoother zone transitions, no icon stutter",
    -- LFGBulletinBoard
    LFGBulletinBoard_updateListDirty = "~1-3 FPS while browsing the LFG panel",
    LFGBulletinBoard_sortSkip = "~0.5-1 FPS, more stable clickable list entries",
    -- Bartender4
    Bartender4_lossOfControlSkip = "~1-2 FPS in combat on Classic",
    Bartender4_usableThrottle = "~2-4 FPS during mana-heavy combat",
    Bartender4_pressAndHoldGuard = "Eliminates ~19 ADDON_ACTION_BLOCKED errors per combat",
    -- TitanPanel
    TitanPanel_reputationsOnUpdate = "~0.5-1 FPS from eliminating 300+ idle checks/sec",
    TitanPanel_bagDebounce = "Eliminates brief stutter when looting multiple items",
    TitanPanel_performanceThrottle = "~0.5-1 FPS, less ironic performance overhead",
    -- OmniCC
    OmniCC_gcdSpellCache = "~1-2 FPS during ability rotation",
    OmniCC_ruleMatchCache = "Reduced microstutter when multiple cooldowns trigger",
    OmniCC_finishEffectGuard = "~0.5-1 FPS during active combat with many abilities",
    -- Prat-3.0
    Prat_smfThrottle = "~5-10 FPS when chat is visible, huge gain in raids",
    Prat_timestampCache = "Less memory growth in high-traffic chat channels",
    Prat_bubblesGuard = "Reduces baseline overhead while solo or in instances",
    Prat_playerNamesThrottle = "~1-3 FPS in 25-man raids during heavy aura activity",
    Prat_guildRosterThrottle = "Eliminates guild roster feedback loop network traffic",
    -- GatherMate2
    GatherMate2_minimapThrottle = "~2-4 FPS while moving through gathering zones",
    GatherMate2_rebuildGuard = "Eliminates minimap stutter when standing still",
    GatherMate2_cleuUnregister = "~1-2 FPS in raid combat",
    -- Quartz
    Quartz_castBarThrottle = "~1-2 FPS with multiple cast bars visible",
    Quartz_swingBarThrottle = "~0.5-1 FPS for melee classes during combat",
    Quartz_gcdBarThrottle = "~0.5-1 FPS during ability spam",
    Quartz_buffBucket = "~1-2 FPS for healers during rapid target switching",
    -- Auctionator
    Auctionator_ownerQueryThrottle = "~10-20 FPS at the auction house",
    Auctionator_throttleBroadcast = "~1-2 FPS during AH operations",
    Auctionator_priceAgeOptimize = "Less memory growth during long AH sessions",
    Auctionator_dbKeyCache = "Snappier tooltip on frequently hovered AH items",
    -- VuhDo
    VuhDo_debuffDebounce = "~2-5 FPS in 25-man raids during AoE encounters",
    VuhDo_rangeSkipDead = "~1-3 FPS during wipe recovery and rez phases",
    VuhDo_inspectThrottle = "60% fewer inspect server requests in raids",
    -- Cell
    Cell_debuffOrderMemo = "~1-2 FPS during debuff-heavy encounters",
    Cell_customIndicatorGuard = "~1-2 FPS for users without custom indicators",
    Cell_debuffGlowMemo = "~0.5-1 FPS during raid debuff tracking",
    Cell_inspectQueueThrottle = "83% fewer inspect server requests on group join",
    -- BigDebuffs
    BigDebuffs_hiddenDebuffsHash = "Future-proofs for retail, minimal TBC impact",
    BigDebuffs_attachFrameGuard = "~1-3 FPS during raid aura storms",
    -- EasyFrames
    EasyFrames_healthTextFix = "Correct K/M/B abbreviations on health text",
    -- BugSack
    BugSack_settingsCompat = "Prevents Lua errors when opening BugSack settings on Classic",
    BugSack_formatCache = "Faster sack navigation with many captured errors",
    BugSack_searchThrottle = "Smoother typing in the error search box",
    -- LoonBestInSlot
    LoonBestInSlot_apiCompat = "Prevents Lua errors from missing retail Item/Spell/C_Item/C_Spell APIs",
    LoonBestInSlot_containerCompat = "Prevents Lua errors from missing C_Container API",
    LoonBestInSlot_settingsCompat = "Prevents Lua errors when opening settings on Classic",
    LoonBestInSlot_phaseUpdate = "All Phase 1-5 gear visible in browser and tooltips",
    LoonBestInSlot_nilGuards = "Prevents cascading Lua errors from missing source data",
    -- NovaInstanceTracker
    NovaInstanceTracker_weeklyResetGuard = "Prevents addon crash on every login",
    NovaInstanceTracker_settingsCompat = "Prevents crash when opening settings on Classic",
}

-- Build lookup for patches by group
local PATCHES_BY_GROUP = {}
for _, p in ipairs(PATCH_INFO) do
    if not PATCHES_BY_GROUP[p.group] then
        PATCHES_BY_GROUP[p.group] = {}
    end
    table.insert(PATCHES_BY_GROUP[p.group], p)
end

-- Case-insensitive patch name resolver for slash commands
local PATCH_NAMES_LOWER = {}
for _, p in ipairs(PATCH_INFO) do
    PATCH_NAMES_LOWER[p.key:lower()] = p.key
end

-- Human-readable impact descriptions for tooltips
local IMPACT_DESC = {
    FPS = "Smoother gameplay",
    Memory = "Less memory usage",
    Network = "Less server traffic",
}
local LEVEL_DESC = {
    High = "very noticeable improvement",
    Medium = "helps in busy situations",
    Low = "small improvement",
}

-- Format an impact badge string with color codes
local function FormatBadge(impact, level)
    if not impact then return "" end
    local bc = BADGE_COLORS[impact] or BADGE_COLORS.FPS
    local lc = LEVEL_COLORS[level] or LEVEL_COLORS.Medium
    return string.format("|cff%02x%02x%02x[%s]|r |cff%02x%02x%02x%s|r",
        bc.r * 255, bc.g * 255, bc.b * 255, impact,
        lc.r * 255, lc.g * 255, lc.b * 255, level or "")
end

---------------------------------------------------------------------------
-- GUI Panel
---------------------------------------------------------------------------

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "PatchWerk"

    local checkboxes = {}
    local groupCheckboxes = {} -- [groupId] = { cb1, cb2, ... }
    local groupCountLabels = {} -- [groupId] = fontString
    local statusLabels = {}
    local contentBuilt = false
    local tallyLabel = nil

    local function RefreshStatusLabels()
        for _, info in ipairs(statusLabels) do
            local enabled = ns:GetOption(info.key)
            local applied = ns.applied[info.key]
            if applied then
                info.fontString:SetText("|cff33e633Active|r")
            elseif enabled and not applied then
                info.fontString:SetText("|cffffff00Reload|r")
            elseif not enabled then
                info.fontString:SetText("|cff808080Off|r")
            else
                info.fontString:SetText("")
            end
        end
    end

    local function RefreshGroupCounts()
        for groupId, cbs in pairs(groupCheckboxes) do
            local active = 0
            local total = #cbs
            for _, cb in ipairs(cbs) do
                if ns:GetOption(cb.optionKey) then
                    active = active + 1
                end
            end
            local label = groupCountLabels[groupId]
            if label then
                if active == total then
                    label:SetText("|cff33e633" .. active .. "/" .. total .. " active|r")
                elseif active > 0 then
                    label:SetText("|cffffff00" .. active .. "/" .. total .. " active|r")
                else
                    label:SetText("|cff808080" .. active .. "/" .. total .. " active|r")
                end
            end
        end
    end

    local function RefreshTally()
        if not tallyLabel then return end
        local installedGroups = {}
        for _, groupInfo in ipairs(ns.addonGroups) do
            for _, dep in ipairs(groupInfo.deps) do
                if ns:IsAddonLoaded(dep) then
                    installedGroups[groupInfo.id] = true
                    break
                end
            end
        end
        local fpsCount, memCount, netCount, highCount = 0, 0, 0, 0
        for _, p in ipairs(PATCH_INFO) do
            if installedGroups[p.group] and ns:GetOption(p.key) then
                if p.impact == "FPS" then
                    fpsCount = fpsCount + 1
                elseif p.impact == "Memory" then
                    memCount = memCount + 1
                elseif p.impact == "Network" then
                    netCount = netCount + 1
                end
                if p.impactLevel == "High" then
                    highCount = highCount + 1
                end
            end
        end
        local total = fpsCount + memCount + netCount
        if total > 0 then
            local parts = {}
            if fpsCount > 0 then
                table.insert(parts, "|cff33e633" .. fpsCount .. " FPS|r")
            end
            if memCount > 0 then
                table.insert(parts, "|cff33cce6" .. memCount .. " Memory|r")
            end
            if netCount > 0 then
                table.insert(parts, "|cffff9933" .. netCount .. " Network|r")
            end
            local text = "Improving:  " .. table.concat(parts, "  |cff666666|||r  ")
            if highCount > 0 then
                text = text .. "    |cffffd100" .. highCount .. " high-impact|r"
            end
            tallyLabel:SetText(text)
        else
            tallyLabel:SetText("|cff808080No active patches for installed addons|r")
        end
    end

    local function BuildContent()
        if contentBuilt then return end
        contentBuilt = true

        local scrollFrame = CreateFrame("ScrollFrame", "PatchWerk_OptionsScroll", panel, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 0, -10)
        scrollFrame:SetPoint("BOTTOMRIGHT", -26, 10)

        local content = CreateFrame("Frame")
        content:SetSize(580, 2000)
        scrollFrame:SetScrollChild(content)

        scrollFrame:SetScript("OnSizeChanged", function(self, w)
            if w and w > 0 then content:SetWidth(w) end
        end)

        -- Helpers
        local function AddSeparator(y, alpha)
            local line = content:CreateTexture(nil, "ARTWORK")
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", 12, y)
            line:SetPoint("TOPRIGHT", -12, y)
            line:SetTexture(0.6, 0.6, 0.6, alpha or 0.25)
            return y - 8
        end

        -- Title
        local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("PatchWerk")

        local version = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        version:SetPoint("LEFT", title, "RIGHT", 6, 0)
        version:SetText("v" .. ns.VERSION)

        local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        subtitle:SetText("Performance patches for popular addons. Toggle patches below, then /reload.")
        subtitle:SetJustifyH("LEFT")

        -- Active count
        local activeCount = 0
        for _ in pairs(ns.applied) do activeCount = activeCount + 1 end
        local totalCount = #PATCH_INFO

        local countText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        countText:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -2)
        countText:SetText("|cff33e633" .. activeCount .. "/" .. totalCount .. " patches active|r")
        countText:SetJustifyH("LEFT")

        -- Patch category breakdown (FPS / Memory / Network)
        tallyLabel = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        tallyLabel:SetPoint("TOPLEFT", countText, "BOTTOMLEFT", 0, -2)
        tallyLabel:SetJustifyH("LEFT")

        -- Safety reassurance
        local safetyText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        safetyText:SetPoint("TOPLEFT", tallyLabel, "BOTTOMLEFT", 0, -4)
        safetyText:SetText("All patches are safe to toggle. They only affect performance, never gameplay.")
        safetyText:SetJustifyH("LEFT")

        -- Badge legend
        local legendText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        legendText:SetPoint("TOPLEFT", safetyText, "BOTTOMLEFT", 0, -6)
        legendText:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        legendText:SetJustifyH("LEFT")
        legendText:SetWordWrap(true)
        legendText:SetText(
            "|cff33e633[FPS]|r Smoother gameplay, less stuttering   " ..
            "|cff33cce6[Memory]|r Fewer slowdowns over long sessions   " ..
            "|cffff9933[Network]|r Less lag and server traffic\n" ..
            "Impact:  |cffffd100High|r = very noticeable    " ..
            "|cffbfbfbfMedium|r = helps in busy situations    " ..
            "|cff996633Low|r = small improvement"
        )

        local yOffset = -128

        -- Build addon group sections
        for _, groupInfo in ipairs(ns.addonGroups) do
            local groupId = groupInfo.id
            local groupPatches = PATCHES_BY_GROUP[groupId]
            if not groupPatches then groupPatches = {} end

            -- Check if any dep for this group is loaded
            local installed = false
            for _, dep in ipairs(groupInfo.deps) do
                if ns:IsAddonLoaded(dep) then
                    installed = true
                    break
                end
            end

            -- Group separator
            yOffset = yOffset - 6
            yOffset = AddSeparator(yOffset, installed and 0.35 or 0.15)

            -- Group header (larger font)
            local header = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            header:SetPoint("TOPLEFT", 16, yOffset)
            if installed then
                header:SetText(groupInfo.label)
            else
                header:SetText("|cff666666" .. groupInfo.label .. "|r")
            end

            -- Active count per group (right-aligned next to header)
            local groupCount = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            groupCount:SetPoint("LEFT", header, "RIGHT", 10, 0)
            groupCountLabels[groupId] = groupCount

            -- Not installed label
            if not installed then
                local note = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                note:SetPoint("LEFT", groupCount, "RIGHT", 8, 0)
                note:SetText("(not installed)")
            end

            -- Enable All / Disable All buttons (right side of header)
            local enableAllBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            enableAllBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", -80, yOffset + 2)
            enableAllBtn:SetSize(60, 18)
            enableAllBtn:SetText("All On")
            enableAllBtn:GetFontString():SetFont(enableAllBtn:GetFontString():GetFont(), 10)

            local disableAllBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
            disableAllBtn:SetPoint("LEFT", enableAllBtn, "RIGHT", 4, 0)
            disableAllBtn:SetSize(60, 18)
            disableAllBtn:SetText("All Off")
            disableAllBtn:GetFontString():SetFont(disableAllBtn:GetFontString():GetFont(), 10)

            yOffset = yOffset - 24

            -- Init group checkbox tracking
            groupCheckboxes[groupId] = {}

            for _, patchInfo in ipairs(groupPatches) do
                local cb = CreateFrame("CheckButton", "PatchWerk_CB_" .. patchInfo.key, content, "UICheckButtonTemplate")
                cb:SetPoint("TOPLEFT", 20, yOffset)
                cb.optionKey = patchInfo.key

                -- Disable checkbox interaction for uninstalled addons
                if not installed then
                    cb:Disable()
                    cb:SetAlpha(0.4)
                end

                local cbName = cb:GetName()
                local cbLabel = _G[cbName .. "Text"]
                if cbLabel then
                    -- Label with impact badge inline
                    local badge = FormatBadge(patchInfo.impact, patchInfo.impactLevel)
                    cbLabel:SetText(patchInfo.label .. "  " .. badge)
                    cbLabel:SetFontObject(installed and "GameFontHighlight" or "GameFontDisable")
                end

                -- Detail tooltip (?) button
                if patchInfo.detail and cbLabel then
                    local helpBtn = CreateFrame("Frame", nil, content)
                    helpBtn:SetSize(16, 16)
                    helpBtn:SetPoint("LEFT", cbLabel, "RIGHT", 4, 0)
                    helpBtn:EnableMouse(true)

                    local qmark = helpBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                    qmark:SetPoint("CENTER", 0, 0)
                    qmark:SetText("|cff66bbff(?)|r")

                    if not installed then
                        helpBtn:SetAlpha(0.4)
                    end

                    helpBtn:SetScript("OnEnter", function(self)
                        qmark:SetText("|cffffffff(?)|r")
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText("What does this fix?", 0.4, 0.8, 1.0)
                        GameTooltip:AddLine(patchInfo.detail, 1, 0.82, 0, true)
                        local est = PATCH_ESTIMATES[patchInfo.key]
                        if est then
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine("Estimated gain: " .. est, 0.2, 0.9, 0.2, true)
                        end
                        GameTooltip:Show()
                    end)
                    helpBtn:SetScript("OnLeave", function()
                        qmark:SetText("|cff66bbff(?)|r")
                        GameTooltip:Hide()
                    end)
                end

                -- Status badge (right side)
                local statusBadge = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                statusBadge:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, yOffset - 5)
                table.insert(statusLabels, { key = patchInfo.key, fontString = statusBadge })

                -- Help text
                local helpText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                helpText:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 26, 2)
                helpText:SetPoint("RIGHT", content, "RIGHT", -70, 0)
                helpText:SetText(installed and patchInfo.help or ("|cff555555" .. patchInfo.help .. "|r"))
                helpText:SetJustifyH("LEFT")
                helpText:SetWordWrap(true)

                -- Tooltip
                cb:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(patchInfo.label, 1, 1, 1)
                    GameTooltip:AddLine(patchInfo.help, 1, 0.82, 0, true)
                    if patchInfo.impact then
                        GameTooltip:AddLine(" ")
                        local bc = BADGE_COLORS[patchInfo.impact] or BADGE_COLORS.FPS
                        local lc = LEVEL_COLORS[patchInfo.impactLevel] or LEVEL_COLORS.Medium
                        local what = IMPACT_DESC[patchInfo.impact] or patchInfo.impact
                        local how = LEVEL_DESC[patchInfo.impactLevel] or ""
                        GameTooltip:AddLine(what, bc.r, bc.g, bc.b)
                        if how ~= "" then
                            GameTooltip:AddLine(how, lc.r, lc.g, lc.b)
                        end
                    end
                    GameTooltip:AddLine(" ")
                    if not installed then
                        GameTooltip:AddLine("Target addon not installed", 0.5, 0.5, 0.5)
                    elseif ns.applied[patchInfo.key] then
                        GameTooltip:AddLine("Status: Active", 0, 1, 0)
                    else
                        GameTooltip:AddLine("Requires /reload to take effect", 1, 1, 0)
                    end
                    GameTooltip:Show()
                end)
                cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

                cb:SetScript("OnClick", function(self)
                    ns:SetOption(self.optionKey, self:GetChecked() and true or false)
                    RefreshStatusLabels()
                    RefreshGroupCounts()
                    RefreshTally()
                end)

                table.insert(checkboxes, cb)
                table.insert(groupCheckboxes[groupId], cb)
                yOffset = yOffset - 42
            end

            -- Wire up Enable/Disable All buttons
            local grpCbs = groupCheckboxes[groupId]
            enableAllBtn:SetScript("OnClick", function()
                for _, cb in ipairs(grpCbs) do
                    ns:SetOption(cb.optionKey, true)
                    cb:SetChecked(true)
                end
                RefreshStatusLabels()
                RefreshGroupCounts()
                RefreshTally()
            end)
            disableAllBtn:SetScript("OnClick", function()
                for _, cb in ipairs(grpCbs) do
                    ns:SetOption(cb.optionKey, false)
                    cb:SetChecked(false)
                end
                RefreshStatusLabels()
                RefreshGroupCounts()
                RefreshTally()
            end)

            if not installed then
                enableAllBtn:Disable()
                disableAllBtn:Disable()
                enableAllBtn:SetAlpha(0.4)
                disableAllBtn:SetAlpha(0.4)
            end

            yOffset = yOffset - 2
        end

        -- Bottom buttons
        yOffset = yOffset - 6
        yOffset = AddSeparator(yOffset, 0.35)

        local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        resetBtn:SetPoint("TOPLEFT", 16, yOffset)
        resetBtn:SetSize(160, 26)
        resetBtn:SetText("Reset to Defaults (All On)")
        resetBtn:SetScript("OnClick", function()
            if PatchWerkDB then
                wipe(PatchWerkDB)
                for key, value in pairs(ns.defaults) do
                    PatchWerkDB[key] = value
                end
            end
            for _, cb in ipairs(checkboxes) do
                cb:SetChecked(ns:GetOption(cb.optionKey))
            end
            RefreshStatusLabels()
            RefreshGroupCounts()
            RefreshTally()
            ns:Print("Settings reset to defaults. Reload to apply.")
        end)

        local reloadBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        reloadBtn:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
        reloadBtn:SetSize(140, 26)
        reloadBtn:SetText("Apply Changes (Reload)")
        reloadBtn:SetScript("OnClick", ReloadUI)

        yOffset = yOffset - 40

        -- About section
        yOffset = yOffset - 10
        yOffset = AddSeparator(yOffset, 0.35)

        local aboutHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        aboutHeader:SetPoint("TOPLEFT", 16, yOffset)
        aboutHeader:SetText("About")
        yOffset = yOffset - 20

        local aboutText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        aboutText:SetPoint("TOPLEFT", 16, yOffset)
        aboutText:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        aboutText:SetJustifyH("LEFT")
        aboutText:SetWordWrap(true)
        aboutText:SetText(
            "|cff33ccffPatchWerk|r v" .. ns.VERSION .. "\n" ..
            "by |cffffd100Eventyret|r  (|cff8788EEHexusPlexus|r - Thunderstrike EU)\n" ..
            "\n" ..
            "No enrage timer. No tank swap. Just pure, uninterrupted performance.\n" ..
            "\n" ..
            "PatchWerk fixes performance problems hiding inside your other addons -- " ..
            "things like addons refreshing way too fast, doing the same work twice, " ..
            "or leaking memory like a boss with no mechanics. Your addons keep " ..
            "working exactly the same, just without the lag.\n" ..
            "\n" ..
            "All patches are enabled by default and everything is safe to toggle. " ..
            "Most players can just leave it all on and enjoy the extra frames. " ..
            "If Patchwerk himself had this kind of efficiency, he wouldn't need " ..
            "a hateful strike.\n" ..
            "\n" ..
            "|cff808080Slash commands:|r  |cffffd100/pw|r or |cffffd100/patchwerk|r to open this panel  " ..
            "|cff808080||  |cffffd100/pw status|r for a chat summary  " ..
            "|cff808080||  |cffffd100/pw help|r for all commands"
        )
        local aboutHeight = aboutText:GetStringHeight() or 80
        yOffset = yOffset - aboutHeight - 10

        content:SetHeight(-yOffset + 20)
    end

    panel:SetScript("OnShow", function()
        BuildContent()
        local sf = PatchWerk_OptionsScroll
        if sf then
            local w = sf:GetWidth()
            if w and w > 0 then sf:GetScrollChild():SetWidth(w) end
        end
        for _, cb in ipairs(checkboxes) do
            cb:SetChecked(ns:GetOption(cb.optionKey))
        end
        RefreshStatusLabels()
        RefreshGroupCounts()
        RefreshTally()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "PatchWerk")
        category.ID = "PatchWerk"
        Settings.RegisterAddOnCategory(category)
        ns.settingsCategoryID = "PatchWerk"
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    ns.optionsPanel = panel
    return panel
end

---------------------------------------------------------------------------
-- Slash Commands
---------------------------------------------------------------------------

local function ShowStatus()
    ns:Print("Patch Status (v" .. ns.VERSION .. "):")
    ns:Print("-----------------------------")
    for _, groupInfo in ipairs(ns.addonGroups) do
        local installed = false
        for _, dep in ipairs(groupInfo.deps) do
            if ns:IsAddonLoaded(dep) then installed = true; break end
        end

        local groupPatches = PATCHES_BY_GROUP[groupInfo.id]
        if groupPatches and #groupPatches > 0 then
            if installed then
                ns:Print("|cffffffff" .. groupInfo.label .. "|r")
            else
                ns:Print("|cff666666" .. groupInfo.label .. " (not installed)|r")
            end

            for _, p in ipairs(groupPatches) do
                local enabled = ns:GetOption(p.key)
                local applied = ns.applied[p.key]
                local status
                if applied then
                    status = "|cff00ff00active|r"
                elseif enabled and installed then
                    status = "|cffffff00enabled (reload needed)|r"
                elseif not installed then
                    status = "|cff666666not installed|r"
                else
                    status = "|cffff0000disabled|r"
                end
                ns:Print("  " .. p.label .. ": " .. status)
            end
        end
    end
end

local function HandleToggle(input)
    local patchKey = PATCH_NAMES_LOWER[input:lower()]
    if not patchKey then
        ns:Print("Unknown patch: " .. tostring(input))
        ns:Print("Use /patchwerk status to see available patches.")
        return
    end

    local current = ns:GetOption(patchKey)
    ns:SetOption(patchKey, not current)
    local newState = not current and "|cff00ff00enabled|r" or "|cffff0000disabled|r"
    ns:Print(patchKey .. " is now " .. newState .. ". Reload UI to apply.")
end

local function HandleReset()
    if PatchWerkDB then
        wipe(PatchWerkDB)
        for key, value in pairs(ns.defaults) do
            PatchWerkDB[key] = value
        end
    end
    ns:Print("All settings reset to defaults. Reload UI to apply.")
end

SLASH_PATCHWERK1 = "/patchwerk"
SLASH_PATCHWERK2 = "/pw"

SlashCmdList["PATCHWERK"] = function(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end

    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "" then
        if ns.settingsCategoryID and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(ns.settingsCategoryID)
        elseif InterfaceOptionsFrame_OpenToCategory and ns.optionsPanel then
            InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
            InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
        else
            ShowStatus()
        end
    elseif cmd == "status" then
        ShowStatus()
    elseif cmd == "toggle" and args[2] then
        HandleToggle(args[2])
    elseif cmd == "reset" then
        HandleReset()
    elseif cmd == "config" or cmd == "options" then
        if ns.settingsCategoryID and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(ns.settingsCategoryID)
        elseif InterfaceOptionsFrame_OpenToCategory and ns.optionsPanel then
            InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
            InterfaceOptionsFrame_OpenToCategory(ns.optionsPanel)
        else
            ShowStatus()
        end
    elseif cmd == "help" then
        ns:Print("Usage:")
        ns:Print("  /patchwerk              Open settings panel")
        ns:Print("  /patchwerk status       Show all patch status")
        ns:Print("  /patchwerk toggle X     Toggle a patch on/off")
        ns:Print("  /patchwerk reset        Reset to defaults")
        ns:Print("  /patchwerk help         Show this help")
    else
        ShowStatus()
    end
end

---------------------------------------------------------------------------
-- Initialization
---------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    CreateOptionsPanel()
end)
