--WoWTranslate
local UPCompatWoWTranslateNameCachePrefix = "\1wt_name:"
local UPCompatWoWTranslateGuildCachePrefix = "\1wt_name:guild:"

function UPCompatWoWTranslateGetCachedNameTranslation(text)
	local cachedTranslation = nil
	if UnitPlatesSettings and UnitPlatesSettings.enableWoWTranslateSupport and WoWTranslate_API and WoWTranslate_API.IsAvailable() and text and (text ~= '') then
		cachedTranslation = WoWTranslate_CacheGet(UPCompatWoWTranslateNameCachePrefix..text)
		if (not cachedTranslation) or (cachedTranslation == '') then
			--try raw cache, why not?
			cachedTranslation = WoWTranslate_CacheGet(text)
		end
		if (not cachedTranslation) or (cachedTranslation == '') then
			--try from glossary, why not?
			cachedTranslation = WoWTranslateGlossary[text]
		end
	end
	return cachedTranslation
end

function UPCompatWoWTranslateGetCachedGuildTranslation(text)
	local cachedTranslation = nil
	if UnitPlatesSettings and UnitPlatesSettings.enableWoWTranslateSupport and WoWTranslate_API and WoWTranslate_API.IsAvailable() and text and (text ~= '') then		
		if (string.find(text, "'s Pet") or string.find(text, "'s Minion")) then
			local _, _, name, suffix = string.find(text, "^(.-)('s .+)")
			if name and suffix then
				--print(name)   -- Outputs: Blabla
				--print(suffix) -- Outputs: 's Pet
				
				local cachedNameTranslation = WoWTranslate_CacheGet(UPCompatWoWTranslateNameCachePrefix..name)
				if (not cachedNameTranslation) or (cachedNameTranslation == '') then
					--try raw cache, why not?
					cachedNameTranslation = WoWTranslate_CacheGet(name)
				end
				if (not cachedNameTranslation) or (cachedNameTranslation == '') then
					--try from glossary, why not?
					cachedNameTranslation = WoWTranslateGlossary[name]
				end
				
				if (cachedNameTranslation) and (cachedNameTranslation ~= '') then
					cachedTranslation = cachedNameTranslation..suffix
				end
			end
		else
			cachedTranslation = WoWTranslate_CacheGet(UPCompatWoWTranslateGuildCachePrefix..text)
			if (not cachedTranslation) or (cachedTranslation == '') then
				--try raw cache, why not?
				cachedTranslation = WoWTranslate_CacheGet(text)
			end
			if (not cachedTranslation) or (cachedTranslation == '') then
				--try from glossary, why not?
				cachedTranslation = WoWTranslateGlossary[text]
			end
		end
	end
	return cachedTranslation
end
--WoWTranslate END

function UPCompatGetHealthFromMobHealth(guid)
	local current, max
	
	if guid and (MobHealthDB) then
		local index
		if UnitIsPlayer(guid) then
			index = UnitName(guid)
		else
			index = UnitName(guid)..":"..UnitLevel(guid)
		end

		local table = MobHealthDB
		if (not (table and table[index])) then
			table = MobHealthPlayerDB
		end
		if (table and table[index]) then
			local s, e
			local pts
			local pct

			if ( type(table[index]) ~= "string" ) then
				frameHealthBarText:SetText(targethealth.."%")
			end
			s, e, pts, pct = strfind(table[index], "^(%d+)/(%d+)$")

			if ( pts and pct ) then
				pts = pts + 0
				pct = pct + 0
				if( pct ~= 0 ) then
					pointsPerPct = pts / pct
				else
					pointsPerPct = 0
				end
			end
			local currentPct = UnitHealth(guid)
			if ( pointsPerPct > 0 ) then
				current = (currentPct * pointsPerPct) + 0.5
				max = (100 * pointsPerPct) + 0.5
			end
		end
	end
	
	return current, max
end

function UPCompatGetHealthFromShaguTweaks(guid)
	local current, max
	
	if guid and ShaguTweaks and ShaguTweaks.libhealth then
		local name = UnitName(guid)
		local level = UnitLevel(guid)
		local curPct = UnitHealth(guid)
		local cur, maxHp, isReal = ShaguTweaks.libhealth:GetUnitHealthByName(name, level, curPct, 100)
		if isReal then
			current = cur
			max = maxHp
		end
	end
	
	return current, max
end


------------------------------------------------------------------------------------

--pfquest compatibility
-- local UPCompatIsFirstPfQuestLoad = true

local UPComapt_PFQUEST_SWORD_ICON = "Interface\\AddOns\\UnitPlates\\img\\quest\\slay"
local UPComapt_PFQUEST_BAG_ICON = "Interface\\AddOns\\UnitPlates\\img\\quest\\loot"
local UPComapt_PFQUEST_TURNIN_ICON = "Interface\\AddOns\\UnitPlates\\img\\quest\\turnin_yellow"

UPCompatPfQuestQuestObjectives = {}

local function UPCompatPfQuestScanQuestObjectives()
    UPCompatPfQuestQuestObjectives = {}

    if not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] or not pfDB["quests"]["enUS"] then
        return
    end

    local activeQuests = {}
    local completedQuestTitles = {}
    
    -- 1. Scan the actual Quest Log
    for qid = 1, GetNumQuestLogEntries() do
        local questTitle, _, _, _, _, complete = GetQuestLogTitle(qid)
        
        if questTitle then
            if complete == 1 then
                -- Quest is finished, flag for turn-in mapping
                completedQuestTitles[questTitle] = true
            else
                -- Quest is active, fetch objectives
                activeQuests[questTitle] = {}
                local numObjectives = GetNumQuestLeaderBoards(qid)
                
                if numObjectives and numObjectives > 0 then
                    for i = 1, numObjectives do
                        local text, objType, finished = GetQuestLogLeaderBoard(i, qid)
                        if text and not finished then
                            local _, _, objName, current, total = string.find(text, "(.*):%s*(%d+)%s*/%s*(%d+)")
                            
                            if objName then
                                objName = string.gsub(objName, "^%s*(.-)%s*$", "%1")
                                table.insert(activeQuests[questTitle], {
                                    objective = objName,
                                    current = tonumber(current) or 0,
                                    total = tonumber(total) or 1
                                })
                            else
                                table.insert(activeQuests[questTitle], {
                                    objective = text,
                                    current = 0,
                                    total = 1
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Match Quest Log against pfDB
    for questId, localizedData in pairs(pfDB["quests"]["enUS"]) do
        local questTitle = localizedData["T"]

        if questTitle then
            local questData = pfDB["quests"]["data"][questId]
            
            if questData then
                -- CASE A: TURN-IN (?)
                if completedQuestTitles[questTitle] then
                    -- questData["end"]["U"] contains the NPC IDs to hand the quest into
                    if questData["end"] and questData["end"]["U"] then
                        for _, unitId in pairs(questData["end"]["U"]) do
                            local npcName = pfDB["units"]["enUS"][unitId]
                            if npcName then
                                -- Assign the turn-in icon
                                UPCompatPfQuestQuestObjectives[npcName] = UPComapt_PFQUEST_TURNIN_ICON
                            end
                        end
                    end

                -- CASE B: ACTIVE OBJECTIVES (Sword/Bag)
                elseif activeQuests[questTitle] then
                    -- KILL OBJECTIVES
                    if questData["obj"] and questData["obj"]["U"] then
                        for _, unitId in pairs(questData["obj"]["U"]) do
                            local targetName = pfDB["units"]["enUS"][unitId]
                            if targetName then
                                for _, activeObj in ipairs(activeQuests[questTitle]) do
                                    local objStr = type(activeObj) == "table" and activeObj.objective or activeObj
                                    local current = type(activeObj) == "table" and activeObj.current or 0
                                    local total   = type(activeObj) == "table" and activeObj.total or 1

                                    if type(objStr) == "string" then
                                        local objNameBase = string.gsub(objStr, " slain$", "")
                                        objNameBase = string.gsub(objNameBase, " killed$", "")
                                        
                                        if objNameBase == targetName or string.find(objStr, targetName, 1, true) then
                                            -- Only apply if a higher-priority icon (like turn-in) hasn't already been set for this NPC
                                            if current < total and not UPCompatPfQuestQuestObjectives[targetName] then
                                                UPCompatPfQuestQuestObjectives[targetName] = UPComapt_PFQUEST_SWORD_ICON
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end

                    -- LOOT OBJECTIVES
                    if questData["obj"] and questData["obj"]["I"] then
                        for _, itemId in pairs(questData["obj"]["I"]) do
                            local itemName = pfDB["items"]["enUS"][itemId]
                            local itemData = pfDB["items"]["data"][itemId]

                            if itemName and itemData and itemData["U"] then
                                for unitId, _ in pairs(itemData["U"]) do
                                    local npcName = pfDB["units"]["enUS"][unitId]
                                    if npcName then
                                        for _, activeObj in ipairs(activeQuests[questTitle]) do
                                            local objStr = type(activeObj) == "table" and activeObj.objective or activeObj
                                            local current = type(activeObj) == "table" and activeObj.current or 0
                                            local total   = type(activeObj) == "table" and activeObj.total or 1

                                            if type(objStr) == "string" and string.find(objStr, itemName, 1, true) then
                                                -- Only apply if a higher-priority icon hasn't already been set
                                                if current < total and not UPCompatPfQuestQuestObjectives[npcName] then
                                                    UPCompatPfQuestQuestObjectives[npcName] = UPComapt_PFQUEST_BAG_ICON
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- local function UPCompatPfQuestScanQuestObjectives()
    -- UPCompatPfQuestQuestObjectives = {}

    -- if not pfDB or not pfDB["quests"] or not pfDB["quests"]["data"] or not pfDB["quests"]["enUS"] then
        -- return
    -- end

    -- local activeQuests = {}
    
    -- -- 1. Scan the actual Quest Log
    -- for qid = 1, GetNumQuestLogEntries() do
        -- local questTitle, _, _, _, _, _, complete = GetQuestLogTitle(qid)
        -- if questTitle and complete ~= 1 then
            -- activeQuests[questTitle] = {}
            -- local numObjectives = GetNumQuestLeaderBoards(qid)
			
			-- if (numObjectives == nil) or numObjectives < 1 then
				-- --do nothing
			-- else
				-- for i = 1, numObjectives do
					-- local text, objType, finished = GetQuestLogLeaderBoard(i, qid)
					-- if text and not finished then
						-- -- 1.12 regex is picky; we match the name and the numbers
						-- local _, _, objName, current, total = string.find(text, "(.*):%s*(%d+)%s*/%s*(%d+)")
						
						-- if objName then
							-- objName = string.gsub(objName, "^%s*(.-)%s*$", "%1") -- Trim whitespace
							-- table.insert(activeQuests[questTitle], {
								-- objective = objName,
								-- current = tonumber(current) or 0,
								-- total = tonumber(total) or 1
							-- })
						-- else
							-- -- FALLBACK: If it's a "Talk to" or "Special" objective without 0/1 numbers
							-- table.insert(activeQuests[questTitle], {
								-- objective = text,
								-- current = 0,
								-- total = 1
							-- })
						-- end
					-- end
				-- end
			-- end
        -- end
    -- end

    -- -- 2. Match Quest Log against pfDB
    -- for questId, localizedData in pairs(pfDB["quests"]["enUS"]) do
        -- local questTitle = localizedData["T"]

        -- if questTitle and activeQuests[questTitle] then
            -- local questData = pfDB["quests"]["data"][questId]
            -- if questData and questData["obj"] then
                
				-- -- CASE A: KILL OBJECTIVES
				-- if questData["obj"]["U"] then
					-- for _, unitId in pairs(questData["obj"]["U"]) do
						-- local targetName = pfDB["units"]["enUS"][unitId]
						-- if targetName and activeQuests[questTitle] then
							-- for _, activeObj in ipairs(activeQuests[questTitle]) do
								-- -- VITAL SAFETY CHECK
								-- local objStr = type(activeObj) == "table" and activeObj.objective or activeObj
								-- local current = type(activeObj) == "table" and activeObj.current or 0
								-- local total   = type(activeObj) == "table" and activeObj.total or 1

								-- if type(objStr) == "string" then
									-- -- FIX: Use string.gsub(string, pattern, replacement) instead of string:gsub()
									-- local objNameBase = string.gsub(objStr, " slain$", "")
									-- objNameBase = string.gsub(objNameBase, " killed$", "")
									
									-- if objNameBase == targetName or string.find(objStr, targetName, 1, true) then
										-- if current < total then
											-- UPCompatPfQuestQuestObjectives[targetName] = UPComapt_PFQUEST_SWORD_ICON
										-- end
									-- end
								-- end
							-- end
						-- end
					-- end
				-- end

				-- -- CASE B: LOOT OBJECTIVES
				-- if questData["obj"]["I"] then
					-- for _, itemId in pairs(questData["obj"]["I"]) do
						-- local itemName = pfDB["items"]["enUS"][itemId]
						-- local itemData = pfDB["items"]["data"][itemId]

						-- if itemName and itemData and itemData["U"] then
							-- for unitId, _ in pairs(itemData["U"]) do
								-- local npcName = pfDB["units"]["enUS"][unitId]
								-- if npcName and activeQuests[questTitle] then
									-- for _, activeObj in ipairs(activeQuests[questTitle]) do
										-- local objStr = type(activeObj) == "table" and activeObj.objective or activeObj
										-- local current = type(activeObj) == "table" and activeObj.current or 0
										-- local total   = type(activeObj) == "table" and activeObj.total or 1

										-- -- FIX: Use string.find(string, ...) instead of string:find()
										-- if type(objStr) == "string" and string.find(objStr, itemName, 1, true) then
											-- if current < total then
												-- UPCompatPfQuestQuestObjectives[npcName] = UPComapt_PFQUEST_BAG_ICON
											-- end
										-- end
									-- end
								-- end
							-- end
						-- end
					-- end
				-- end
                
            -- end
        -- end
    -- end
	
	-- -- UPCompatIsFirstPfQuestLoad = false
-- end

-- Variables for pfquest debouncing
local UPCompatPfQuestPendingScan = false
local UPCompatPfQuestDebounceTimer = 0

local function UPCompatPfQuestScanWithDebounce()
	-- 1. Do nothing if no scan has been requested
	if not UPCompatPfQuestPendingScan then return end
	
	-- 2. Ensure pfQuest has finished building its localization caches
	if not (pfDatabase and pfDatabase.localized) then return end

	-- 3. Run the debounce timer (arg1 in Vanilla WoW is elapsed time in seconds)
	UPCompatPfQuestDebounceTimer = UPCompatPfQuestDebounceTimer + arg1
	
	-- 4. If 0.2 seconds have passed since the LAST event fired, execute the scan
	if UPCompatPfQuestDebounceTimer > 0.2 then
		UPCompatPfQuestPendingScan = false
		UPCompatPfQuestDebounceTimer = 0
		
		UPCompatPfQuestScanQuestObjectives()
	end
end

local function UPCompatPfQuestOnEvent(event)
	if event == "QUEST_LOG_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" then
		
		-- Assuming you track these variables elsewhere as intended
		if UnitPlatesAddonIsLoaded and UnitPlatesPlayerEnteredWorld then
			
			-- Instead of running the heavy scan directly, we queue it and reset the timer.
			-- This safely merges 15 simultaneous login events into 1 single scan.
			UPCompatPfQuestPendingScan = true
			UPCompatPfQuestDebounceTimer = 0 
			
		end
	end
end

--pfquest compatibility END


--UPCompatFrame
local UPCompatFrame = CreateFrame("Frame", "UPCompatFrameFrame", UIParent)
UPCompatFrame:SetFrameStrata("LOW")
UPCompatFrame.TimeToCheck = 0
UPCompatFrame.numFrames = 0

UPCompatFrame:RegisterEvent("QUEST_LOG_UPDATE")
UPCompatFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
UPCompatFrame:RegisterEvent("ZONE_CHANGED")
UPCompatFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

--UPCompatFrame:RegisterEvent("ADDON_LOADED")

UPCompatFrame:SetScript("OnUpdate", function()
	UPCompatPfQuestScanWithDebounce()
end)

UPCompatFrame:SetScript("OnEvent", function()
	UPCompatPfQuestOnEvent(event)
end)
--UPCompatFrame END