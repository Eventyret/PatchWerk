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

-- Patch category system
local CATEGORY_COLORS = {
    Fixes       = "|cffff6666",   -- soft red
    Performance = "|cff66b3ff",   -- blue
    Tweaks      = "|cffe6b3ff",   -- lavender
}
local CATEGORY_LABELS = {
    Fixes       = "Fixes",
    Performance = "Performance",
    Tweaks      = "Tweaks",
}
local CATEGORY_DESC = {
    Fixes       = "Prevents crashes or errors on TBC Classic Anniversary",
    Performance = "Improves FPS, memory usage, or network performance",
    Tweaks      = "Improves addon behavior or fixes confusing display issues",
}

-- Patch metadata: labels, help text, detail tooltips, and impact info
local PATCH_INFO = {
    -- Details
    { key = "Details_hexFix",        group = "Details",  label = "Color Rendering Fix",
      help = "Fixes slow color calculations in damage meter bars.",
      detail = "Details recalculates bar colors 50+ times per window refresh using a slow method. This causes visible stuttering when you have multiple damage meter windows open during heavy combat, especially on Classic's older engine.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "Details_fadeHandler",   group = "Details",  label = "Idle Animation Saver",
      help = "Stops the fade system from wasting resources when no bars are animating.",
      detail = "The fade animation system runs constantly even when nothing is fading, wasting resources thousands of times per minute. The fix makes it sleep when idle and only wake up when bars actually need to fade.",
      impact = "FPS", impactLevel = "Low", category = "Performance" },
    { key = "Details_refreshCap",    group = "Details",  label = "Refresh Rate Cap",
      help = "Prevents the damage meter from refreshing way too fast, which can tank performance on Classic.",
      detail = "Details tries to refresh at 60fps when streamer mode is enabled, which is way too fast for Classic. This causes severe FPS drops during combat. The fix caps refreshes at 10 per second, which is still plenty responsive.",
      impact = "FPS", impactLevel = "High", category = "Performance" },
    { key = "Details_npcIdCache",    group = "Details",  label = "Enemy Info Cache",
      help = "Remembers enemy info so it doesn't have to figure it out again during every fight.",
      detail = "Details figures out enemy IDs using slow pattern matching, and redoes this dozens of times per refresh for the same enemies. During raid boss fights with many adds, this causes noticeable lag spikes when the meter updates.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "Details_formatCache",   group = "Details",  label = "Number Format Cache",
      help = "Caches formatted damage and heal numbers to avoid recalculating the same values.",
      detail = "Details formats the same damage totals repeatedly during each window refresh -- 10-50 times across multiple meter windows. This patch caches the last 200 formatted results so identical numbers are returned instantly instead of rebuilt every time.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    -- Plater
    { key = "Plater_fpsCheck",       group = "Plater",   label = "Timer Leak Fix",
      help = "Fixes a Plater bug that wastes memory by creating 60+ temporary timers per second.",
      detail = "Plater creates 60+ temporary objects every second just to track your FPS, which causes memory buildup over time. During heavy combat with many nameplates visible, this contributes to stuttering. The fix uses a single reusable tracker instead.",
      impact = "Memory", impactLevel = "High", category = "Performance" },
    { key = "Plater_healthText",     group = "Plater",   label = "Health Text Skip",
      help = "Skips nameplate health text updates when the value hasn't changed.",
      detail = "Plater reformats nameplate health text on every update even when HP hasn't changed. With 20-40 nameplates visible in a dungeon or raid, that's thousands of wasted text updates per second for no visual benefit.",
      impact = "FPS", impactLevel = "Low", category = "Performance" },
    { key = "Plater_auraAlign",      group = "Plater",   label = "Aura Icon Guard",
      help = "Skips reshuffling buff/debuff icons on nameplates when nothing changed.",
      detail = "Plater reshuffles buff and debuff icons on nameplates 200+ times per second during combat, creating throwaway data each time. This causes stutters when you have many visible nameplates with multiple buffs or debuffs active.",
      impact = "Memory", impactLevel = "Medium", category = "Performance" },
    -- Pawn
    { key = "Pawn_cacheIndex",       group = "Pawn",     label = "Fast Item Lookup",
      help = "Makes Pawn find item info much faster instead of searching through hundreds of entries.",
      detail = "Pawn searches through up to 200 cached items one by one every time you hover an item. When you're rapidly mousing over loot or vendor items, this causes tooltip lag where there's a visible delay before Pawn's upgrade arrows appear.",
      impact = "FPS", impactLevel = "High", category = "Performance" },
    { key = "Pawn_tooltipDedup",     group = "Pawn",     label = "Duplicate Tooltip Guard",
      help = "Stops Pawn from checking the same item multiple times when you mouse over it.",
      detail = "Multiple tooltip updates fire for the same item, causing Pawn to calculate upgrade scores 2-4 times per hover. This makes tooltips feel sluggish, especially with multiple stat scales enabled.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "Pawn_upgradeCache",     group = "Pawn",     label = "Upgrade Result Cache",
      help = "Remembers if an item is an upgrade so Pawn doesn't recheck all your gear on every hover.",
      detail = "Pawn recalculates upgrade comparisons against all your equipped gear for every item you hover, every single time. With 2-3 active stat scales, hovering loot during a dungeon run causes noticeable tooltip delays.",
      impact = "FPS", impactLevel = "High", category = "Performance" },
    -- TipTac
    { key = "TipTac_unitAppearanceGuard", group = "TipTac", label = "Non-Unit Tooltip Guard",
      help = "Stops TipTac from constantly updating when you're hovering items instead of players.",
      detail = "TipTac runs appearance updates constantly for every visible tooltip, including item and spell tooltips where no player or NPC is shown. This wastes resources when you're hovering items in bags or on vendors.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "TipTac_inspectCache",   group = "TipTac",   label = "Extended Inspect Cache",
      help = "Reduces inspect requests from every 5s to every 30s for recently inspected players.",
      detail = "TipTac re-inspects players every 5 seconds when you hover them, sending repeated requests to the server. In crowded cities or raids, this causes inspect delays for everyone. The fix extends the cache to 30 seconds.",
      impact = "Network", impactLevel = "Medium", category = "Performance" },
    -- Questie
    { key = "Questie_questLogThrottle", group = "Questie", label = "Quest Log Throttle",
      help = "Limits quest log refreshes to twice per second when multiple quests update at once.",
      detail = "Questie scans your entire quest log multiple times per second during active questing -- every mob kill, quest progress tick, and zone change triggers it. This causes noticeable FPS drops when you have 20+ active quests, especially in crowded quest hubs.",
      impact = "FPS", impactLevel = "High", category = "Performance" },
    { key = "Questie_availableQuestsDebounce", group = "Questie", label = "Quest Availability Batch",
      help = "Combines rapid quest availability checks into one update instead of several.",
      detail = "When you accept, complete, or abandon a quest, Questie recalculates all available quests 4-6 times in rapid succession. Each pass checks thousands of quests in its database, causing a brief freeze or stutter.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "Questie_framePoolPrealloc", group = "Questie", label = "Quest Icon Warmup",
      help = "Pre-creates quest map icons at login to prevent stuttering when entering new zones.",
      detail = "Questie creates quest map icons on-demand, causing brief stutters when you enter a new zone or accept several quests at once. This patch pre-creates icons during the loading screen so they're ready when needed, eliminating the stutter.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    -- LFGBulletinBoard
    { key = "LFGBulletinBoard_updateListDirty", group = "LFGBulletinBoard", label = "Smart List Refresh",
      help = "Skips the full group list rebuild when nothing actually changed.",
      detail = "The LFG panel rebuilds the entire group list every second while open, even when no new messages have arrived. This causes constant stuttering when browsing for groups, especially when you have 50+ listings visible.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "LFGBulletinBoard_sortSkip", group = "LFGBulletinBoard", label = "Sort Interval Throttle",
      help = "Limits group list sorting to once every 2 seconds.",
      detail = "The group list re-sorts every second regardless of changes. When you have a large list of group postings, this continuous sorting causes visible UI stuttering and makes it harder to click on entries.",
      impact = "FPS", impactLevel = "Low", category = "Performance" },
    -- Bartender4
    { key = "Bartender4_lossOfControlSkip", group = "Bartender4", label = "Unused Effect Skip",
      help = "Stops your action bars from constantly checking for stun/silence effects that don't exist on Classic.",
      detail = "Bartender4 scans all your action bar buttons for loss-of-control overlays (stun, silence, etc.) every time something happens in combat. These overlays don't exist on Classic, so every scan finds nothing and wastes resources. This adds up fast during busy fights.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "Bartender4_usableThrottle", group = "Bartender4", label = "Button Update Batch",
      help = "Combines rapid action bar updates into a single check instead of refreshing all buttons multiple times per second.",
      detail = "Your action bars refresh on every mana tick, target change, and buff change, causing all your buttons to be rechecked multiple times per second. During intense combat, this can cause button highlights and range coloring to feel sluggish. The fix batches these updates together so your bars stay responsive without the overhead.",
      impact = "FPS", impactLevel = "High", category = "Performance" },
    { key = "Bartender4_pressAndHoldGuard", group = "Bartender4", label = "Combat Error Flood Fix",
      help = "Stops a flood of error spam every time you enter combat caused by incompatible retail code.",
      detail = "TBC Anniversary includes newer action bar code meant for Retail WoW that conflicts with Bartender4 during combat. This triggers around 19 errors every time you enter combat, flooding your error log and wasting resources. The fix prevents the conflict from happening in the first place.",
      impact = "FPS", impactLevel = "High", category = "Fixes" },
    -- TitanPanel
    { key = "TitanPanel_reputationsOnUpdate", group = "TitanPanel", label = "Reputation Timer Fix",
      help = "Checks your reputation every 5 seconds instead of constantly.",
      detail = "The reputation plugin checks for updates every single frame even though it only needs to update every few seconds. This wastes 300+ checks per second just to see if it's time to refresh yet.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "TitanPanel_bagDebounce", group = "TitanPanel", label = "Bag Update Batch",
      help = "Counts bag contents once after looting instead of on every individual slot change.",
      detail = "Titan Panel scans all your bags on every individual bag change. When you loot multiple items quickly, this triggers 4-10 full bag scans in under a second, causing brief stutters. The fix waits for looting to finish before scanning once.",
      impact = "FPS", impactLevel = "Low", category = "Performance" },
    { key = "TitanPanel_performanceThrottle", group = "TitanPanel", label = "Performance Display Throttle",
      help = "Updates the FPS/memory display every 3s instead of every 1.5s.",
      detail = "The FPS and memory display updates every 1.5 seconds, checking memory usage across all loaded addons. Ironically, these frequent checks themselves contribute to the performance overhead being displayed.",
      impact = "FPS", impactLevel = "Low", category = "Performance" },
    -- OmniCC
    { key = "OmniCC_gcdSpellCache", group = "OmniCC", label = "Cooldown Status Cache",
      help = "Checks the Global Cooldown once per update instead of 20+ times.",
      detail = "Every time you press an ability and trigger the global cooldown, OmniCC checks it 20+ times across all your action bars. This creates micro-stuttering during ability spam, especially noticeable in PvP and fast raid rotations.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "OmniCC_ruleMatchCache", group = "OmniCC", label = "Display Rule Cache",
      help = "Remembers which cooldown display settings apply to each ability. Resets on profile change.",
      detail = "OmniCC figures out which display settings apply to each cooldown by checking every one against a list of rules. Since these never change during gameplay, it's doing hundreds of identical lookups for no reason.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "OmniCC_finishEffectGuard", group = "OmniCC", label = "Finish Effect Guard",
      help = "Skips cooldown finish animations for abilities that aren't close to coming off cooldown.",
      detail = "OmniCC tries to play cooldown-finished animations even for abilities that are nowhere near ready. The fix skips this wasted work unless an ability is actually within 2 seconds of being usable again.",
      impact = "FPS", impactLevel = "Low", category = "Performance" },
    -- Prat-3.0
    { key = "Prat_smfThrottle", group = "Prat", label = "Chat Layout Throttle",
      help = "Reduces chat window updates from 60 to 20 per second. Full speed when you mouse over chat.",
      detail = "With features like Hover Highlighting enabled, Prat recalculates every visible chat line 60 times per second. With 4 chat frames open that's thousands of updates per second. This patch drops it to 20 per second with no visible difference.",
      impact = "FPS", impactLevel = "High", category = "Performance" },
    { key = "Prat_timestampCache", group = "Prat", label = "Timestamp Cache",
      help = "Creates chat timestamps once per second instead of recalculating for every single message.",
      detail = "Prat rebuilds the timestamp text from scratch for every single chat message, even when 10 messages arrive in the same second. During busy raid chat or trade spam, this causes unnecessary frame drops.",
      impact = "Memory", impactLevel = "Low", category = "Performance" },
    { key = "Prat_bubblesGuard", group = "Prat", label = "Bubble Scan Guard",
      help = "Skips chat bubble scanning when no one is talking nearby.",
      detail = "Prat scans for chat bubbles 10 times per second even when you're completely alone or in an instance where no one is talking. The fix skips this entirely when no bubbles exist.",
      impact = "FPS", impactLevel = "Low", category = "Performance" },
    { key = "Prat_playerNamesThrottle", group = "Prat", label = "Player Info Throttle",
      help = "Throttles player name lookups during buff and debuff changes to 5 times per second.",
      detail = "Prat's player name coloring system reacts to every buff and debuff change in your raid to track player classes. In raids, these changes happen 20-50 times per second but player names never change when someone gains a buff. This patch limits those checks to 5 per second.",
      impact = "FPS", impactLevel = "Low", category = "Performance" },
    { key = "Prat_guildRosterThrottle", group = "Prat", label = "Guild Roster Rate Limit",
      help = "Stops Prat from requesting guild roster data in a feedback loop.",
      detail = "Prat requests a full guild roster refresh every time it receives a roster update from the server, creating a feedback loop that generates constant network traffic. In a large active guild with members logging in and out, this produces unnecessary server requests every few seconds. The fix limits roster requests to once per 15 seconds.",
      impact = "Network", impactLevel = "Medium", category = "Performance" },
    -- GatherMate2
    { key = "GatherMate2_minimapThrottle", group = "GatherMate2", label = "Minimap Pin Throttle",
      help = "Updates minimap gathering pins less often (20 instead of 60 times/sec) with no visible difference.",
      detail = "GatherMate2 updates your minimap gathering pins 60 times per second. This creates noticeable stuttering while flying or riding through zones with lots of nodes. The fix caps it at 20 per second -- still buttery smooth but much lighter.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "GatherMate2_rebuildGuard", group = "GatherMate2", label = "Stationary Rebuild Skip",
      help = "Skips minimap node rebuilds when you're standing still.",
      detail = "Every 2 seconds, GatherMate2 rebuilds all minimap nodes by recalculating distances and positions, even when you're standing still at the auction house. The fix skips these pointless rebuilds when you haven't moved.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "GatherMate2_cleuUnregister", group = "GatherMate2", label = "Remove Unused Combat Handler",
      help = "Removes leftover code in GatherMate2 that runs during every fight but does nothing useful.",
      detail = "GatherMate2 processes every combat log event during fights looking for gas cloud extraction, but this feature is completely unused in TBC. In raids, that's 200+ wasted checks per second during boss encounters.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    -- Quartz
    { key = "Quartz_castBarThrottle", group = "Quartz", label = "Cast Bar 30fps Cap",
      help = "Caps cast bar animations at 30fps -- looks identical, uses half the resources.",
      detail = "Quartz animates cast bars at 60fps, but you can't visually tell the difference between 60fps and 30fps on a 1-3 second cast. The fix caps it at 30fps, cutting the work in half with zero visual difference.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "Quartz_swingBarThrottle", group = "Quartz", label = "Swing Timer 30fps Cap",
      help = "Caps the swing timer at 30fps -- no visible difference on a 2-3 second swing.",
      detail = "The swing timer updates 60 times per second during auto-attack, but a 2-3 second swing looks identical at 30fps. This halves the animation work for melee classes and hunters.",
      impact = "FPS", impactLevel = "Low", category = "Performance" },
    { key = "Quartz_gcdBarThrottle", group = "Quartz", label = "GCD Bar 30fps Cap",
      help = "Caps the global cooldown bar at 30fps -- plenty smooth for a 1.5 second bar.",
      detail = "The GCD bar runs at 60fps during every 1.5 second global cooldown. That's complete overkill for such a short bar. The fix caps it at 30fps, which is still perfectly smooth.",
      impact = "FPS", impactLevel = "Low", category = "Performance" },
    { key = "Quartz_buffBucket", group = "Quartz", label = "Buff Bar Update Throttle",
      help = "Limits buff bar updates during rapid target switching to prevent unnecessary repetition.",
      detail = "The Buff module checks up to 72 buffs and debuffs on every target or focus change. During rapid tab-targeting or healer mouse-over targeting, this can fire dozens of times per second. This patch batches those updates so they happen at most 10 times per second with no visible delay.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    -- Auctionator
    { key = "Auctionator_ownerQueryThrottle", group = "Auctionator", label = "Auction Query Throttle",
      help = "Reduces server queries at the auction house from constant to once per second.",
      detail = "Auctionator queries the server 60 times per second while you're on the Selling or Cancelling tabs. Your auction data only changes when you post or cancel, not every frame. The fix limits queries to once per second.",
      impact = "Network", impactLevel = "High", category = "Performance" },
    { key = "Auctionator_throttleBroadcast", group = "Auctionator", label = "Timer Display Throttle",
      help = "Reduces the auction throttle timer display from 60 updates/sec to 2.",
      detail = "The auction throttle countdown timer updates 60 times per second just to show a number counting down. You don't need frame-perfect precision for a countdown. The fix drops it to 2 updates per second.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "Auctionator_priceAgeOptimize", group = "Auctionator", label = "Price Age Optimizer",
      help = "Makes price freshness calculations faster and lighter on memory.",
      detail = "Every time you hover over an item, Auctionator creates throwaway data, sorts it, then discards it just to check how old the price is. During quick auction scans this causes tooltip lag. The fix does it without any throwaway data.",
      impact = "Memory", impactLevel = "Medium", category = "Performance" },
    { key = "Auctionator_dbKeyCache", group = "Auctionator", label = "Price Lookup Cache",
      help = "Remembers item price lookups so Auctionator doesn't redo them every time you hover.",
      detail = "Auctionator converts item links to price lookups using expensive conversions every single time you hover an item. If you mouseover the same item 10 times, it does the same work 10 times. The fix remembers results.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    -- VuhDo
    { key = "VuhDo_debuffDebounce", group = "VuhDo", label = "Debuff Scan Batch",
      help = "During heavy AoE damage, combines debuff checks instead of running 100+ per second.",
      detail = "During heavy AoE damage in raids, VuhDo's debuff checker fires 100+ times per second as aura updates flood in. This creates raid frame stuttering during encounters like Lurker or Vashj. The fix combines checks within 33ms windows.",
      impact = "FPS", impactLevel = "High", category = "Performance" },
    { key = "VuhDo_rangeSkipDead", group = "VuhDo", label = "Skip Dead Range Checks",
      help = "Skips range checking on dead or disconnected raid members.",
      detail = "VuhDo checks range on every raid member continuously, making multiple checks per person per update. Dead and disconnected players obviously can't change range, but VuhDo checks them anyway. In a 25-man with deaths, that's a lot of wasted work.",
      impact = "FPS", impactLevel = "Low", category = "Performance" },
    { key = "VuhDo_inspectThrottle", group = "VuhDo", label = "Inspect Request Throttle",
      help = "Reduces server inspect requests from every 2 seconds to every 5 seconds.",
      detail = "VuhDo sends inspect requests to the server every 2.1 seconds to determine raid members' specs and roles. In a 25-man raid, this means continuous inspect traffic for the entire session as members join, leave, or go out of range. The fix spaces requests to every 5 seconds, cutting server traffic by 60%.",
      impact = "Network", impactLevel = "Medium", category = "Performance" },
    -- Cell
    { key = "Cell_debuffOrderMemo", group = "Cell", label = "Debuff Priority Cache",
      help = "Remembers the last debuff priority check to skip a duplicate lookup that happens every update.",
      detail = "Cell checks debuff priority twice in a row for the same debuff during updates -- once from the debuff scan and once from the raid debuff check. The fix remembers the last result and skips the duplicate lookup.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "Cell_customIndicatorGuard", group = "Cell", label = "Custom Indicator Guard",
      help = "Skips custom indicator processing when you don't have any set up.",
      detail = "Cell processes custom indicators for every aura on every raid frame, even if you don't have any custom indicators set up. Most players use default settings, so this is wasted work on every update. The fix detects this and skips the whole system.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "Cell_debuffGlowMemo", group = "Cell", label = "Debuff Glow Cache",
      help = "Remembers which debuffs should glow on your raid frames to avoid rechecking.",
      detail = "Cell checks which debuffs should glow immediately after checking their priority, using the same information both times. The fix remembers the last result and reuses it, cutting the work in half.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "Cell_inspectQueueThrottle", group = "Cell", label = "Inspect Queue Throttle",
      help = "Slows down Cell's inspect burst from 4 requests/sec to once per 1.5 seconds.",
      detail = "When you join a group, Cell's group info system fires inspect requests to the server every 0.25 seconds -- that's 4 per second. In a 25-man raid, it sends 24 inspect requests in just 6 seconds, most of which get silently dropped by the server and need retries. The fix spaces them to every 1.5 seconds, which the server handles cleanly.",
      impact = "Network", impactLevel = "Medium", category = "Performance" },
    -- BigDebuffs
    { key = "BigDebuffs_hiddenDebuffsHash", group = "BigDebuffs", label = "Fast Hidden Debuff Check",
      help = "Speeds up hidden debuff checks by using a smarter lookup method.",
      detail = "BigDebuffs scans through its hidden debuff list one by one for every aura on every unit frame. With 40 aura slots checked per unit, this adds up fast during raid encounters. The fix uses instant lookups instead of scanning the whole list.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "BigDebuffs_attachFrameGuard", group = "BigDebuffs", label = "Frame Anchor Cache",
      help = "Remembers where to place debuff icons instead of searching all frame addons every time.",
      detail = "BigDebuffs searches through 9 different frame integrations (ElvUI, Cell, NDui, etc.) on every single aura update to figure out where to place icons. It finds the same answer every time until you reload. The fix remembers which frames go with which units.",
      impact = "FPS", impactLevel = "High", category = "Performance" },
    -- EasyFrames
    { key = "EasyFrames_healthTextFix", group = "EasyFrames", label = "Health Text Fix",
      help = "Fixes confusing 'T' suffix on health numbers -- changes to standard K/M/B abbreviations.",
      detail = "EasyFrames uses 'T' for thousands (e.g. '36T' for 36,000 HP) which looks like trillions. It also mislabels values in the 1-9.9 million range as 'T'. The fix replaces the number formatting with standard K (thousands), M (millions), B (billions).",
      impact = "FPS", impactLevel = "Low", category = "Tweaks" },
    -- BugSack
    { key = "BugSack_settingsCompat", group = "BugSack", label = "Fix Settings Menu",
      help = "Stops BugSack from throwing errors when you try to open its settings panel.",
      detail = "BugSack's latest version tries to open its settings using a method that only works on Retail WoW. On TBC Classic Anniversary, clicking the settings option from the slash command, right-clicking the sack, or right-clicking the broker icon would cause an error instead of opening settings. This fix makes all three entry points open the settings panel correctly.",
      impact = "FPS", impactLevel = "High", category = "Fixes" },
    { key = "BugSack_formatCache", group = "BugSack", label = "Faster Error Viewing",
      help = "Speeds up scrolling through captured errors by remembering previously formatted text.",
      detail = "Every time you view an error in the sack, the addon re-processes and re-colors the entire error text from scratch, even if you already looked at it. When you have many errors captured, scrolling through them can feel sluggish as the addon does this heavy text processing repeatedly. This fix remembers the formatted result so each error is only processed once.",
      impact = "FPS", impactLevel = "Medium", category = "Performance" },
    { key = "BugSack_searchThrottle", group = "BugSack", label = "Smoother Search Typing",
      help = "Waits until you pause typing before searching, so the search box does not lag on every keypress.",
      detail = "The search box in BugSack tries to filter through all captured errors after every single keystroke. If you have hundreds of errors saved, this causes noticeable lag and stuttering while you type. This fix waits until you stop typing for a moment before running the search, keeping the input responsive.",
      impact = "FPS", impactLevel = "Low", category = "Performance" },
    -- LoonBestInSlot
    { key = "LoonBestInSlot_apiCompat", group = "LoonBestInSlot", label = "Fix Item Lookups",
      help = "Fixes item and spell info loading that would otherwise break on TBC Classic Anniversary.",
      detail = "LoonBestInSlot was built for Retail WoW and uses item and spell lookup methods that do not exist in TBC Classic Anniversary. Without this fix, the addon cannot load item names, icons, or spell info, causing widespread errors and making the addon unusable. This fix swaps in Classic-compatible lookups so everything loads correctly.",
      impact = "FPS", impactLevel = "High", category = "Fixes" },
    { key = "LoonBestInSlot_containerCompat", group = "LoonBestInSlot", label = "Fix Bag Scanning",
      help = "Fixes bag scanning so the addon can detect which gear you already own.",
      detail = "LoonBestInSlot scans your bags to mark items you already have, but it uses a bag-reading method that only exists in Retail WoW. On TBC Classic Anniversary, this causes errors when the addon tries to check your inventory. This fix uses the Classic-compatible bag scanning instead.",
      impact = "FPS", impactLevel = "High", category = "Fixes" },
    { key = "LoonBestInSlot_settingsCompat", group = "LoonBestInSlot", label = "Fix Settings Menu",
      help = "Fixes the /bis settings command and minimap button so they open the options panel without errors.",
      detail = "Typing '/bis settings' or right-clicking the minimap button tries to open the settings panel using a method that only exists in Retail WoW. On TBC Classic Anniversary, this causes an error instead of showing the options. This fix makes both entry points open the settings panel correctly.",
      impact = "FPS", impactLevel = "Medium", category = "Fixes" },
    { key = "LoonBestInSlot_phaseUpdate", group = "LoonBestInSlot", label = "Show All Phases",
      help = "Unlocks all Phase 1 through 5 gear in the item browser and tooltips.",
      detail = "LoonBestInSlot defaults to showing only Phase 1 items, which hides the majority of TBC gear from tooltips and the gear browser. Since TBC Classic Anniversary has all content through Phase 5 available, this fix unlocks all phases so you can see every relevant item.",
      impact = "FPS", impactLevel = "Low", category = "Tweaks" },
    { key = "LoonBestInSlot_nilGuards", group = "LoonBestInSlot", label = "Fix Missing Items",
      help = "Prevents the addon from breaking when certain items, gems, or enchants have incomplete data.",
      detail = "Some items, gems, or enchants in the database are missing source information (like which boss drops them). When the addon encounters one of these gaps, it crashes and stops loading all remaining items for that spec. This fix safely skips over missing entries so the rest of your gear list loads properly.",
      impact = "FPS", impactLevel = "Medium", category = "Fixes" },
    -- NovaInstanceTracker
    { key = "NovaInstanceTracker_weeklyResetGuard", group = "NovaInstanceTracker", label = "Fix Login Crash",
      help = "Prevents the addon from crashing every time you log in on TBC Classic Anniversary.",
      detail = "NovaInstanceTracker tries to calculate your weekly reset timer during login using a method that does not exist in TBC Classic Anniversary. This causes the addon to throw an error on every login, potentially breaking its tracking features. This fix safely handles the missing timer so the addon loads without errors.",
      impact = "FPS", impactLevel = "High", category = "Fixes" },
    { key = "NovaInstanceTracker_settingsCompat", group = "NovaInstanceTracker", label = "Fix Settings Menu",
      help = "Fixes the /nit config command so it opens the settings panel instead of throwing an error.",
      detail = "Typing '/nit config' to open the addon's settings tries to use a method that only exists in Retail WoW. On TBC Classic Anniversary, this causes a crash instead of showing the options panel. This fix makes the command open settings correctly on Classic.",
      impact = "FPS", impactLevel = "High", category = "Fixes" },
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
    Bartender4_pressAndHoldGuard = "Eliminates ~19 error popups per combat encounter",
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
    Prat_playerNamesThrottle = "~1-3 FPS in 25-man raids during heavy buff/debuff activity",
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
    BigDebuffs_hiddenDebuffsHash = "Faster debuff checks, biggest improvement with large debuff lists",
    BigDebuffs_attachFrameGuard = "~1-3 FPS during raid aura storms",
    -- EasyFrames
    EasyFrames_healthTextFix = "Correct K/M/B abbreviations on health text",
    -- BugSack
    BugSack_settingsCompat = "Fixes broken settings menu that would throw errors on Classic",
    BugSack_formatCache = "Faster scrolling through the error list when many errors are captured",
    BugSack_searchThrottle = "Smoother typing in the error search box without input lag",
    -- LoonBestInSlot
    LoonBestInSlot_apiCompat = "Fixes broken item and spell info that made the addon unusable on Classic",
    LoonBestInSlot_containerCompat = "Fixes bag scanning so owned items are detected correctly",
    LoonBestInSlot_settingsCompat = "Fixes settings menu that would throw errors on Classic",
    LoonBestInSlot_phaseUpdate = "All Phase 1-5 gear visible in the browser and tooltips",
    LoonBestInSlot_nilGuards = "Prevents the gear list from breaking when some item sources are missing",
    -- NovaInstanceTracker
    NovaInstanceTracker_weeklyResetGuard = "Fixes addon crash that happened every time you logged in",
    NovaInstanceTracker_settingsCompat = "Fixes settings menu that would crash on Classic",
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

-- Format a category badge string with color code
local function FormatCategoryBadge(category)
    if not category then return "" end
    local color = CATEGORY_COLORS[category] or CATEGORY_COLORS.Perf
    local label = CATEGORY_LABELS[category] or category
    return color .. "[" .. label .. "]|r"
end

---------------------------------------------------------------------------
-- GUI Panel (Multi-Page Interface)
---------------------------------------------------------------------------

-- Shared state across all pages
local pendingReload = false
local allCheckboxes = {}
local groupCheckboxes = {}
local groupCountLabels = {}
local statusLabels = {}
local collapsed = {}
local reloadBanners = {}
local relayoutFuncs = {}
local parentCategory = nil
local subCategories = {}
local mainDashboardRefresh = nil

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
    for gcKey, cbs in pairs(groupCheckboxes) do
        local active, total = 0, #cbs
        for _, cb in ipairs(cbs) do
            if ns:GetOption(cb.optionKey) then active = active + 1 end
        end
        local label = groupCountLabels[gcKey]
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

local function ComputeTally()
    local installedGroups, installedCount = {}, 0
    for _, g in ipairs(ns.addonGroups) do
        for _, dep in ipairs(g.deps) do
            if ns:IsAddonLoaded(dep) then
                installedGroups[g.id] = true
                installedCount = installedCount + 1
                break
            end
        end
    end
    local fps, mem, net, high = 0, 0, 0, 0
    local catTotal = { Fixes = 0, Performance = 0, Tweaks = 0 }
    local catActive = { Fixes = 0, Performance = 0, Tweaks = 0 }
    local totalActive = 0
    for _, p in ipairs(PATCH_INFO) do
        if catTotal[p.category] then catTotal[p.category] = catTotal[p.category] + 1 end
        if installedGroups[p.group] and ns:GetOption(p.key) then
            totalActive = totalActive + 1
            if p.impact == "FPS" then fps = fps + 1
            elseif p.impact == "Memory" then mem = mem + 1
            elseif p.impact == "Network" then net = net + 1 end
            if p.impactLevel == "High" then high = high + 1 end
            if catActive[p.category] then catActive[p.category] = catActive[p.category] + 1 end
        end
    end
    return {
        installed = installedCount, totalGroups = #ns.addonGroups,
        totalActive = totalActive, totalPatches = #PATCH_INFO,
        fps = fps, mem = mem, net = net, high = high,
        catTotal = catTotal, catActive = catActive,
    }
end

local function CreateReloadBanner(parent, pageKey)
    local banner = CreateFrame("Frame", nil, parent)
    banner:SetHeight(30)
    banner:Hide()
    local bg = banner:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.6, 0.4, 0.0, 0.25)
    local text = banner:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 12, 0)
    text:SetText("|cffffcc00Changes pending|r -- click Apply or /reload to take effect")
    local btn = CreateFrame("Button", nil, banner, "UIPanelButtonTemplate")
    btn:SetPoint("RIGHT", -8, 0)
    btn:SetSize(120, 20)
    btn:SetText("Apply (Reload)")
    btn:SetScript("OnClick", ReloadUI)
    reloadBanners[pageKey] = banner
    return banner
end

local function ShowReloadBanner()
    if not pendingReload then
        pendingReload = true
        for _, b in pairs(reloadBanners) do b:Show() end
        for _, fn in pairs(relayoutFuncs) do fn() end
    end
end

---------------------------------------------------------------------------
-- BuildCategoryPage — reusable group builder for one category
---------------------------------------------------------------------------
local function BuildCategoryPage(content, categoryFilter)
    local installedData, uninstalledData = {}, {}
    for _, groupInfo in ipairs(ns.addonGroups) do
        local groupId = groupInfo.id
        local patches = {}
        for _, p in ipairs(PATCHES_BY_GROUP[groupId] or {}) do
            if p.category == categoryFilter then table.insert(patches, p) end
        end
        if #patches == 0 then goto continue end
        local installed = false
        for _, dep in ipairs(groupInfo.deps) do
            if ns:IsAddonLoaded(dep) then installed = true; break end
        end
        local ck = groupId .. "_" .. categoryFilter
        if collapsed[ck] == nil then collapsed[ck] = true end

        local gf = CreateFrame("Frame", nil, content)
        local hf = CreateFrame("Frame", nil, gf)
        hf:SetPoint("TOPLEFT", 0, 0)
        hf:SetPoint("TOPRIGHT", 0, 0)
        hf:SetHeight(38)
        hf:EnableMouse(true)
        local sep = hf:CreateTexture(nil, "BACKGROUND")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", 12, -2)
        sep:SetPoint("TOPRIGHT", -12, -2)
        sep:SetTexture(0.6, 0.6, 0.6, installed and 0.35 or 0.15)
        local toggle = hf:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        toggle:SetPoint("TOPLEFT", 8, -12)
        toggle:SetText("|cff888888[+]|r")
        local hlabel = hf:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        hlabel:SetPoint("LEFT", toggle, "RIGHT", 4, 0)
        hlabel:SetText(installed and groupInfo.label or ("|cff666666" .. groupInfo.label .. "|r"))
        local gc = hf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        gc:SetPoint("LEFT", hlabel, "RIGHT", 10, 0)
        groupCountLabels[ck] = gc
        if not installed then
            local note = hf:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            note:SetPoint("LEFT", gc, "RIGHT", 8, 0)
            note:SetText("(not installed)")
        end
        local allOnBtn = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
        allOnBtn:SetPoint("TOPRIGHT", hf, "TOPRIGHT", -80, -8)
        allOnBtn:SetSize(60, 18)
        allOnBtn:SetText("All On")
        allOnBtn:GetFontString():SetFont(allOnBtn:GetFontString():GetFont(), 10)
        local allOffBtn = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
        allOffBtn:SetPoint("LEFT", allOnBtn, "RIGHT", 4, 0)
        allOffBtn:SetSize(60, 18)
        allOffBtn:SetText("All Off")
        allOffBtn:GetFontString():SetFont(allOffBtn:GetFontString():GetFont(), 10)
        local hoverBg = hf:CreateTexture(nil, "BACKGROUND")
        hoverBg:SetAllPoints()
        hoverBg:SetTexture(1, 1, 1, 0)
        hf:SetScript("OnEnter", function() hoverBg:SetTexture(1, 1, 1, 0.03) end)
        hf:SetScript("OnLeave", function() hoverBg:SetTexture(1, 1, 1, 0) end)

        local bf = CreateFrame("Frame", nil, gf)
        bf:SetPoint("TOPLEFT", hf, "BOTTOMLEFT", 0, 0)
        bf:SetPoint("TOPRIGHT", hf, "BOTTOMRIGHT", 0, 0)
        if not groupCheckboxes[ck] then groupCheckboxes[ck] = {} end

        local by = 0
        for _, pi in ipairs(patches) do
            local cb = CreateFrame("CheckButton", "PatchWerk_CB_" .. pi.key, bf, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", 20, by)
            cb.optionKey = pi.key
            if not installed then cb:Disable(); cb:SetAlpha(0.4) end
            local cbn = cb:GetName()
            local cbl = _G[cbn .. "Text"]
            if cbl then
                cbl:SetText(pi.label .. "  " .. FormatBadge(pi.impact, pi.impactLevel))
                cbl:SetFontObject(installed and "GameFontHighlight" or "GameFontDisable")
            end
            if pi.detail and cbl then
                local hb = CreateFrame("Frame", nil, bf)
                hb:SetSize(16, 16)
                hb:SetPoint("LEFT", cbl, "RIGHT", 4, 0)
                hb:EnableMouse(true)
                local qm = hb:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                qm:SetPoint("CENTER", 0, 0)
                qm:SetText("|cff66bbff(?)|r")
                if not installed then hb:SetAlpha(0.4) end
                hb:SetScript("OnEnter", function(self)
                    qm:SetText("|cffffffff(?)|r")
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("What does this fix?", 0.4, 0.8, 1.0)
                    GameTooltip:AddLine(pi.detail, 1, 0.82, 0, true)
                    local est = PATCH_ESTIMATES[pi.key]
                    if est then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Estimated gain: " .. est, 0.2, 0.9, 0.2, true)
                    end
                    GameTooltip:Show()
                end)
                hb:SetScript("OnLeave", function()
                    qm:SetText("|cff66bbff(?)|r")
                    GameTooltip:Hide()
                end)
            end
            local sb = bf:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            sb:SetPoint("TOPRIGHT", bf, "TOPRIGHT", -20, by - 5)
            table.insert(statusLabels, { key = pi.key, fontString = sb })
            local ht = bf:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            ht:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 26, 2)
            ht:SetPoint("RIGHT", bf, "RIGHT", -70, 0)
            ht:SetText(installed and pi.help or ("|cff555555" .. pi.help .. "|r"))
            ht:SetJustifyH("LEFT")
            ht:SetWordWrap(true)
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(pi.label, 1, 1, 1)
                GameTooltip:AddLine(pi.help, 1, 0.82, 0, true)
                if pi.impact then
                    GameTooltip:AddLine(" ")
                    local bc = BADGE_COLORS[pi.impact] or BADGE_COLORS.FPS
                    local lc = LEVEL_COLORS[pi.impactLevel] or LEVEL_COLORS.Medium
                    GameTooltip:AddLine(IMPACT_DESC[pi.impact] or pi.impact, bc.r, bc.g, bc.b)
                    local how = LEVEL_DESC[pi.impactLevel] or ""
                    if how ~= "" then GameTooltip:AddLine(how, lc.r, lc.g, lc.b) end
                end
                GameTooltip:AddLine(" ")
                if not installed then
                    GameTooltip:AddLine("Target addon not installed", 0.5, 0.5, 0.5)
                elseif ns.applied[pi.key] then
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
                if mainDashboardRefresh then mainDashboardRefresh() end
                ShowReloadBanner()
            end)
            table.insert(allCheckboxes, cb)
            table.insert(groupCheckboxes[ck], cb)
            by = by - 42
        end
        local bh = -by + 2
        bf:SetHeight(bh)
        local grpCbs = groupCheckboxes[ck]
        allOnBtn:SetScript("OnClick", function()
            for _, cb in ipairs(grpCbs) do ns:SetOption(cb.optionKey, true); cb:SetChecked(true) end
            RefreshStatusLabels(); RefreshGroupCounts()
            if mainDashboardRefresh then mainDashboardRefresh() end
            ShowReloadBanner()
        end)
        allOffBtn:SetScript("OnClick", function()
            for _, cb in ipairs(grpCbs) do ns:SetOption(cb.optionKey, false); cb:SetChecked(false) end
            RefreshStatusLabels(); RefreshGroupCounts()
            if mainDashboardRefresh then mainDashboardRefresh() end
            ShowReloadBanner()
        end)
        if not installed then
            allOnBtn:Disable(); allOffBtn:Disable()
            allOnBtn:SetAlpha(0.4); allOffBtn:SetAlpha(0.4)
        end
        local data = {
            ck = ck, gf = gf, hf = hf, bf = bf, toggle = toggle,
            hh = 38, bh = bh, installed = installed,
        }
        table.insert(installed and installedData or uninstalledData, data)
        ::continue::
    end
    local nif = CreateFrame("Frame", nil, content)
    nif:SetHeight(32)
    local niSep = nif:CreateTexture(nil, "BACKGROUND")
    niSep:SetHeight(1)
    niSep:SetPoint("TOPLEFT", 12, -4)
    niSep:SetPoint("TOPRIGHT", -12, -4)
    niSep:SetTexture(0.5, 0.5, 0.5, 0.4)
    local niLabel = nif:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    niLabel:SetPoint("TOPLEFT", 16, -12)
    niLabel:SetText("|cff666666Not Installed|r")
    if #uninstalledData == 0 then nif:Hide() end
    return installedData, uninstalledData, nif
end

---------------------------------------------------------------------------
-- Category Sub-Page Builder
---------------------------------------------------------------------------
local function CreateCategorySubPanel(name, catFilter, desc)
    local sub = CreateFrame("Frame")
    sub.name = name
    sub.parent = "PatchWerk"
    local built = false
    sub:SetScript("OnShow", function(self)
        if built then
            for _, cb in ipairs(allCheckboxes) do cb:SetChecked(ns:GetOption(cb.optionKey)) end
            RefreshStatusLabels(); RefreshGroupCounts()
            local b = reloadBanners[catFilter]
            if b then if pendingReload then b:Show() else b:Hide() end end
            if relayoutFuncs[catFilter] then relayoutFuncs[catFilter]() end
            return
        end
        built = true
        local sf = CreateFrame("ScrollFrame", "PatchWerk_Scroll_" .. catFilter, self, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 0, -10)
        sf:SetPoint("BOTTOMRIGHT", -26, 10)
        local content = CreateFrame("Frame")
        content:SetSize(580, 2000)
        sf:SetScrollChild(content)
        sf:SetScript("OnSizeChanged", function(s, w) if w and w > 0 then content:SetWidth(w) end end)
        local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText(name)
        local descFs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        descFs:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        descFs:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        descFs:SetText(desc)
        descFs:SetJustifyH("LEFT")
        local banner = CreateReloadBanner(content, catFilter)
        local headerBot = -50
        local iData, uData, nif = BuildCategoryPage(content, catFilter)
        local function Relayout()
            local y = headerBot
            if pendingReload then
                banner:ClearAllPoints()
                banner:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
                banner:SetPoint("RIGHT", content, "RIGHT", -12, 0)
                banner:Show(); y = y - 34
            else banner:Hide() end
            for _, dd in ipairs(iData) do
                dd.gf:ClearAllPoints()
                dd.gf:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                dd.gf:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                if collapsed[dd.ck] then
                    dd.bf:Hide(); dd.gf:SetHeight(dd.hh); y = y - dd.hh
                else
                    dd.bf:Show(); local h = dd.hh + dd.bh; dd.gf:SetHeight(h); y = y - h
                end
            end
            if #uData > 0 then
                nif:ClearAllPoints()
                nif:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                nif:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                nif:Show(); y = y - 32
            else nif:Hide() end
            for _, dd in ipairs(uData) do
                dd.gf:ClearAllPoints()
                dd.gf:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
                dd.gf:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                if collapsed[dd.ck] then
                    dd.bf:Hide(); dd.gf:SetHeight(dd.hh); y = y - dd.hh
                else
                    dd.bf:Show(); local h = dd.hh + dd.bh; dd.gf:SetHeight(h); y = y - h
                end
            end
            content:SetHeight(-y + 20)
        end
        relayoutFuncs[catFilter] = Relayout
        for _, dd in ipairs(iData) do
            dd.hf:SetScript("OnMouseDown", function()
                collapsed[dd.ck] = not collapsed[dd.ck]
                dd.toggle:SetText(collapsed[dd.ck] and "|cff888888[+]|r" or "|cff888888[-]|r")
                Relayout()
            end)
        end
        for _, dd in ipairs(uData) do
            dd.hf:SetScript("OnMouseDown", function()
                collapsed[dd.ck] = not collapsed[dd.ck]
                dd.toggle:SetText(collapsed[dd.ck] and "|cff888888[+]|r" or "|cff888888[-]|r")
                Relayout()
            end)
        end
        Relayout()
    end)
    return sub
end

---------------------------------------------------------------------------
-- About Sub-Page
---------------------------------------------------------------------------
local function CreateAboutPanel()
    local ap = CreateFrame("Frame")
    ap.name = "About"
    ap.parent = "PatchWerk"
    local built = false
    ap:SetScript("OnShow", function(self)
        if built then return end
        built = true
        local sf = CreateFrame("ScrollFrame", "PatchWerk_Scroll_About", self, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 0, -10)
        sf:SetPoint("BOTTOMRIGHT", -26, 10)
        local content = CreateFrame("Frame")
        content:SetSize(580, 800)
        sf:SetScrollChild(content)
        sf:SetScript("OnSizeChanged", function(s, w) if w and w > 0 then content:SetWidth(w) end end)
        local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("|cff33ccffPatchWerk|r")
        local ver = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        ver:SetPoint("LEFT", title, "RIGHT", 6, 0)
        ver:SetText("v" .. ns.VERSION)
        local author = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        author:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        author:SetText("by |cffffd100Eventyret|r  (|cff8788EEHexusPlexus|r - Thunderstrike EU)")
        local flavor = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        flavor:SetPoint("TOPLEFT", author, "BOTTOMLEFT", 0, -12)
        flavor:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        flavor:SetJustifyH("LEFT"); flavor:SetWordWrap(true)
        flavor:SetText(
            "No enrage timer. No tank swap. Just pure, uninterrupted performance.\n\n" ..
            "PatchWerk fixes performance problems hiding inside your other addons -- " ..
            "things like addons refreshing way too fast, doing the same work twice, " ..
            "or leaking memory like a boss with no mechanics. Your addons keep " ..
            "working exactly the same, just without the lag.\n\n" ..
            "All patches are enabled by default and everything is safe to toggle. " ..
            "Most players can just leave it all on and enjoy the extra frames. " ..
            "If Patchwerk himself had this kind of efficiency, he wouldn't need " ..
            "a hateful strike.")
        local legendSep = content:CreateTexture(nil, "BACKGROUND")
        legendSep:SetHeight(1)
        legendSep:SetPoint("TOPLEFT", flavor, "BOTTOMLEFT", -4, -16)
        legendSep:SetPoint("RIGHT", content, "RIGHT", -16, 0)
        legendSep:SetTexture(0.6, 0.6, 0.6, 0.35)
        local legendTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        legendTitle:SetPoint("TOPLEFT", legendSep, "BOTTOMLEFT", 4, -8)
        legendTitle:SetText("Badge Legend")
        local legendText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        legendText:SetPoint("TOPLEFT", legendTitle, "BOTTOMLEFT", 0, -6)
        legendText:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        legendText:SetJustifyH("LEFT"); legendText:SetWordWrap(true)
        legendText:SetText(
            "|cffff9999Categories:|r\n" ..
            "  |cffff6666[Fixes]|r  Crash or error fix for TBC Classic Anniversary\n" ..
            "  |cff66b3ff[Performance]|r  FPS, memory, or network optimization\n" ..
            "  |cffe6b3ff[Tweaks]|r  Behavior or display improvement\n\n" ..
            "|cff99ccffImpact Type:|r\n" ..
            "  |cff33e633[FPS]|r  Smoother gameplay\n" ..
            "  |cff33cce6[Memory]|r  Less memory usage and fewer slowdowns\n" ..
            "  |cffff9933[Network]|r  Less server traffic\n\n" ..
            "|cffffffccImpact Level:|r\n" ..
            "  |cffffd100High|r  Very noticeable improvement\n" ..
            "  |cffbfbfbfMedium|r  Helps in busy situations\n" ..
            "  |cff996633Low|r  Small improvement")
        local cmdSep = content:CreateTexture(nil, "BACKGROUND")
        cmdSep:SetHeight(1)
        cmdSep:SetPoint("TOPLEFT", legendText, "BOTTOMLEFT", -4, -16)
        cmdSep:SetPoint("RIGHT", content, "RIGHT", -16, 0)
        cmdSep:SetTexture(0.6, 0.6, 0.6, 0.35)
        local cmdTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        cmdTitle:SetPoint("TOPLEFT", cmdSep, "BOTTOMLEFT", 4, -8)
        cmdTitle:SetText("Slash Commands")
        local cmdText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        cmdText:SetPoint("TOPLEFT", cmdTitle, "BOTTOMLEFT", 0, -6)
        cmdText:SetPoint("RIGHT", content, "RIGHT", -20, 0)
        cmdText:SetJustifyH("LEFT"); cmdText:SetWordWrap(true)
        cmdText:SetText(
            "|cffffd100/pw|r or |cffffd100/patchwerk|r  Open main settings panel\n" ..
            "|cffffd100/pw fixes|r  Open Fixes page\n" ..
            "|cffffd100/pw performance|r  Open Performance page\n" ..
            "|cffffd100/pw tweaks|r  Open Tweaks page\n" ..
            "|cffffd100/pw about|r  Open this page\n" ..
            "|cffffd100/pw status|r  Print patch status to chat\n" ..
            "|cffffd100/pw toggle <name>|r  Toggle a specific patch\n" ..
            "|cffffd100/pw reset|r  Reset all settings to defaults\n" ..
            "|cffffd100/pw help|r  Show command help in chat")
        content:SetHeight(800)
    end)
    return ap
end

---------------------------------------------------------------------------
-- Main "At a Glance" Dashboard Page
---------------------------------------------------------------------------
local function CreateMainPanel()
    local panel = CreateFrame("Frame")
    panel.name = "PatchWerk"
    local built = false
    local mainCountLabel, mainCatLabel, mainTallyLabel
    local cardCounts = {}
    local function RefreshDashboard()
        if not mainCountLabel then return end
        local t = ComputeTally()
        mainCountLabel:SetText(t.installed .. " of " .. t.totalGroups .. " supported addons installed — " ..
            "|cff33e633" .. t.totalActive .. "/" .. t.totalPatches .. " patches active|r")
        local parts = {}
        if t.catActive.Performance > 0 then table.insert(parts, "|cff66b3ff" .. t.catActive.Performance .. " Performance|r") end
        if t.catActive.Fixes > 0 then table.insert(parts, "|cffff6666" .. t.catActive.Fixes .. " Fixes|r") end
        if t.catActive.Tweaks > 0 then table.insert(parts, "|cffe6b3ff" .. t.catActive.Tweaks .. " Tweaks|r") end
        mainCatLabel:SetText(#parts > 0 and table.concat(parts, "  |cff666666|||r  ") or "|cff808080No active patches|r")
        local iparts = {}
        if t.fps > 0 then table.insert(iparts, "|cff33e633" .. t.fps .. " FPS|r") end
        if t.mem > 0 then table.insert(iparts, "|cff33cce6" .. t.mem .. " Memory|r") end
        if t.net > 0 then table.insert(iparts, "|cffff9933" .. t.net .. " Network|r") end
        if #iparts > 0 then
            local txt = table.concat(iparts, "  |cff666666|||r  ")
            if t.high > 0 then txt = txt .. "  —  |cffffd100" .. t.high .. " high-impact|r" end
            mainTallyLabel:SetText(txt)
        else
            mainTallyLabel:SetText("|cff808080No active patches for installed addons|r")
        end
        for cat, fs in pairs(cardCounts) do
            if t.catTotal[cat] then fs:SetText(t.catTotal[cat] .. " patches") end
        end
    end
    mainDashboardRefresh = RefreshDashboard
    panel:SetScript("OnShow", function(self)
        if built then
            RefreshDashboard()
            local b = reloadBanners["main"]
            if b then if pendingReload then b:Show() else b:Hide() end end
            if relayoutFuncs["main"] then relayoutFuncs["main"]() end
            return
        end
        built = true
        local sf = CreateFrame("ScrollFrame", "PatchWerk_Scroll_Main", self, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 0, -10)
        sf:SetPoint("BOTTOMRIGHT", -26, 10)
        local content = CreateFrame("Frame")
        content:SetSize(580, 800)
        sf:SetScrollChild(content)
        sf:SetScript("OnSizeChanged", function(s, w) if w and w > 0 then content:SetWidth(w) end end)
        local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("PatchWerk")
        local ver = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        ver:SetPoint("LEFT", title, "RIGHT", 6, 0)
        ver:SetText("v" .. ns.VERSION)
        local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        subtitle:SetText("Performance patches for popular addons")
        subtitle:SetJustifyH("LEFT")
        mainCountLabel = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        mainCountLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -6)
        mainCountLabel:SetJustifyH("LEFT")
        mainCatLabel = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        mainCatLabel:SetPoint("TOPLEFT", mainCountLabel, "BOTTOMLEFT", 0, -2)
        mainCatLabel:SetJustifyH("LEFT")
        mainTallyLabel = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        mainTallyLabel:SetPoint("TOPLEFT", mainCatLabel, "BOTTOMLEFT", 0, -2)
        mainTallyLabel:SetJustifyH("LEFT")
        local banner = CreateReloadBanner(content, "main")
        local cardsTop = -110
        local cardDefs = {
            { name = "Fixes", color = {1,0.4,0.4}, catID = "PatchWerk_Fixes", desc = "Prevents crashes and errors" },
            { name = "Performance", color = {0.4,0.7,1}, catID = "PatchWerk_Performance", desc = "FPS, memory, and network optimizations" },
            { name = "Tweaks", color = {0.9,0.7,1}, catID = "PatchWerk_Tweaks", desc = "Behavior improvements" },
            { name = "About", color = {0.6,0.6,0.6}, catID = "PatchWerk_About", desc = "Info, commands, and credits" },
        }
        local cardFrames = {}
        local function Relayout()
            local y = cardsTop
            if pendingReload then
                banner:ClearAllPoints()
                banner:SetPoint("TOPLEFT", content, "TOPLEFT", 12, y)
                banner:SetPoint("RIGHT", content, "RIGHT", -12, 0)
                banner:Show(); y = y - 34
            else banner:Hide() end
            for _, card in ipairs(cardFrames) do
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
                card:SetPoint("RIGHT", content, "RIGHT", -16, 0)
                y = y - 52
            end
            if panel.resetBtn then
                panel.resetBtn:ClearAllPoints()
                panel.resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y - 10)
            end
            content:SetHeight(-(y - 10) + 60)
        end
        relayoutFuncs["main"] = Relayout
        for _, def in ipairs(cardDefs) do
            local card = CreateFrame("Frame", nil, content)
            card:SetHeight(44)
            card:EnableMouse(true)
            local bg = card:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture(0.12, 0.12, 0.12, 0.8)
            local bar = card:CreateTexture(nil, "ARTWORK")
            bar:SetPoint("TOPLEFT", 0, 0); bar:SetPoint("BOTTOMLEFT", 0, 0)
            bar:SetWidth(4)
            bar:SetTexture(def.color[1], def.color[2], def.color[3], 1)
            local ct = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            ct:SetPoint("TOPLEFT", 14, -6)
            ct:SetText(def.name)
            if def.name ~= "About" then
                local countFs = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                countFs:SetPoint("LEFT", ct, "RIGHT", 8, 0)
                cardCounts[def.name] = countFs
            end
            local cd = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            cd:SetPoint("TOPLEFT", ct, "BOTTOMLEFT", 0, -2)
            cd:SetText("|cff999999" .. def.desc .. "|r")
            local arrow = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            arrow:SetPoint("RIGHT", -12, 0)
            arrow:SetText("|cff666666>|r")
            card:SetScript("OnEnter", function()
                bg:SetTexture(0.18, 0.18, 0.18, 0.9)
                arrow:SetText("|cffcccccc>|r")
            end)
            card:SetScript("OnLeave", function()
                bg:SetTexture(0.12, 0.12, 0.12, 0.8)
                arrow:SetText("|cff666666>|r")
            end)
            local targetID = def.catID
            card:SetScript("OnMouseDown", function()
                if Settings and Settings.OpenToCategory then
                    Settings.OpenToCategory(targetID)
                elseif InterfaceOptionsFrame_OpenToCategory and subCategories[def.name] then
                    InterfaceOptionsFrame_OpenToCategory(subCategories[def.name])
                    InterfaceOptionsFrame_OpenToCategory(subCategories[def.name])
                end
            end)
            table.insert(cardFrames, card)
        end
        local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        resetBtn:SetSize(160, 26)
        resetBtn:SetText("Reset to Defaults (All On)")
        resetBtn:SetScript("OnClick", function()
            if PatchWerkDB then
                wipe(PatchWerkDB)
                for key, value in pairs(ns.defaults) do PatchWerkDB[key] = value end
            end
            for _, cb in ipairs(allCheckboxes) do cb:SetChecked(ns:GetOption(cb.optionKey)) end
            RefreshStatusLabels(); RefreshGroupCounts(); RefreshDashboard()
            ShowReloadBanner()
            ns:Print("Settings reset to defaults. Reload to apply.")
        end)
        panel.resetBtn = resetBtn
        local reloadBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        reloadBtn:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
        reloadBtn:SetSize(140, 26)
        reloadBtn:SetText("Apply Changes (Reload)")
        reloadBtn:SetScript("OnClick", ReloadUI)
        RefreshDashboard()
        Relayout()
    end)
    return panel
end

---------------------------------------------------------------------------
-- Register All Panels
---------------------------------------------------------------------------
local function RegisterAllPanels()
    local mainPanel = CreateMainPanel()
    ns.optionsPanel = mainPanel
    if Settings and Settings.RegisterCanvasLayoutCategory then
        parentCategory = Settings.RegisterCanvasLayoutCategory(mainPanel, "PatchWerk")
        parentCategory.ID = "PatchWerk"
        Settings.RegisterAddOnCategory(parentCategory)
        ns.settingsCategoryID = "PatchWerk"
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(mainPanel)
    end
    local subDefs = {
        { name = "Fixes", filter = "Fixes", desc = "Patches that prevent crashes or errors on TBC Classic Anniversary" },
        { name = "Performance", filter = "Performance", desc = "Optimizations for FPS, memory usage, and network traffic" },
        { name = "Tweaks", filter = "Tweaks", desc = "Behavior and display improvements" },
    }
    for _, def in ipairs(subDefs) do
        local subPanel = CreateCategorySubPanel(def.name, def.filter, def.desc)
        subCategories[def.name] = subPanel
        if Settings and parentCategory then
            local sc = Settings.RegisterCanvasLayoutSubcategory(parentCategory, subPanel, def.name)
            sc.ID = "PatchWerk_" .. def.filter
            Settings.RegisterAddOnCategory(sc)
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(subPanel)
        end
    end
    local aboutPanel = CreateAboutPanel()
    subCategories["About"] = aboutPanel
    if Settings and parentCategory then
        local sc = Settings.RegisterCanvasLayoutSubcategory(parentCategory, aboutPanel, "About")
        sc.ID = "PatchWerk_About"
        Settings.RegisterAddOnCategory(sc)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(aboutPanel)
    end
end

---------------------------------------------------------------------------
-- Navigate to Sub-Page
---------------------------------------------------------------------------
local function OpenSubPage(pageKey)
    local catID = "PatchWerk_" .. pageKey
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(catID)
    elseif InterfaceOptionsFrame_OpenToCategory and subCategories[pageKey] then
        InterfaceOptionsFrame_OpenToCategory(subCategories[pageKey])
        InterfaceOptionsFrame_OpenToCategory(subCategories[pageKey])
    end
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
                local catBadge = FormatCategoryBadge(p.category)
                ns:Print("  " .. catBadge .. " " .. p.label .. ": " .. status)
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
    elseif cmd == "fixes" then
        OpenSubPage("Fixes")
    elseif cmd == "performance" or cmd == "perf" then
        OpenSubPage("Performance")
    elseif cmd == "tweaks" then
        OpenSubPage("Tweaks")
    elseif cmd == "about" then
        OpenSubPage("About")
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
        ns:Print("  /pw                Open settings panel")
        ns:Print("  /pw fixes          Open Fixes page")
        ns:Print("  /pw performance    Open Performance page")
        ns:Print("  /pw tweaks         Open Tweaks page")
        ns:Print("  /pw about          Open About page")
        ns:Print("  /pw status         Show all patch status")
        ns:Print("  /pw toggle X       Toggle a patch on/off")
        ns:Print("  /pw reset          Reset to defaults")
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
    RegisterAllPanels()
end)
