local _G = getfenv(0)

local function UPApiGetAdditionalAuraPollingDelaySeconds()
	return 0

	-- local fallbackDelay = 0.2 --0.2 default fallback
    
    -- -- 1. Grab the raw setting
    -- local rawValue = UnitPlatesSettings.additionalAuraPollingDelaySeconds
    
    -- -- 2. If it's a string, swap any commas to periods so EU players don't break the parser
    -- if type(rawValue) == "string" then
        -- rawValue = string.gsub(rawValue, ",", ".")
    -- end
    
    -- -- 3. Attempt to convert to a mathematical number
    -- local delay = tonumber(rawValue)
    
    -- -- 4. If the conversion failed (nil) OR the number is negative, force the fallback
    -- if not delay or delay < 0 then
        -- return fallbackDelay
    -- end
    
    -- -- 5. If it passed all checks, return the valid, positive number
    -- return delay
end

UPApiScanTool = CreateFrame( "GameTooltip", "UPApiScanTool", nil, "GameTooltipTemplate" )
UPApiScanTool:SetOwner( WorldFrame, "ANCHOR_NONE" )
UPApiScanToolTextLine2 = _G["UPApiScanToolTextLeft2"] -- This is the line with <[Player]'s Pet>

--PUBLIC
function UPApiGetMyGUID()
	local _, xguid = UnitExists("player")
	return xguid
end

function UPApiGetGuildText(guid)
	UPApiScanTool:ClearLines()
	UPApiScanTool:SetUnit(guid)
	local scanTextLine2Text = UPApiScanToolTextLine2:GetText()
	
	local guild = nil
	
	if not string.find(scanTextLine2Text, "Level") then
		--local owner, _ = string.split("'",ownerText)
		guild = scanTextLine2Text
		-- if guild then
			-- print("guild: "..guild)
		-- end
	end
	
	if not guild then
		--then get guild from api
		guild = GetGuildInfo(guid)
	end
	
	return guild
end

--PUBLIC
function UPApiIsPet(guid)
	UPApiScanTool:ClearLines()
	UPApiScanTool:SetUnit(guid)
	local scanTextLine2Text = UPApiScanToolTextLine2:GetText()
	if not string.find(scanTextLine2Text, "Level") then
		if scanTextLine2Text and (string.find(scanTextLine2Text, "'s Pet") or string.find(scanTextLine2Text, "'s Minion")) then
			return true
		end
	end
	return false
end

local UPApiActionSlotScanner = CreateFrame("GameTooltip", "UPApiActionSlotScanner", nil, "GameTooltipTemplate")
UPApiActionSlotScanner:SetOwner(WorldFrame, "ANCHOR_NONE")
UPApiActionSlotScannerTextLeft1 = _G["UPApiActionSlotScannerTextLeft1"]

local cachedShootingSlot = 0
--PUBLIC
function UPApiIsTargetInShootingDistance()
	if cachedShootingSlot > 0 then
		UPApiActionSlotScanner:ClearLines()
        -- This tells the tooltip to load the information from action slot 'i'
        UPApiActionSlotScanner:SetAction(cachedShootingSlot)
		
		-- In 1.12, the first line of the tooltip is the name of the spell/item
        local text = UPApiActionSlotScannerTextLeft1:GetText()
        
        if (text == "Auto Shot") or (text == "Throw") or (text == "Shoot Bow") or (text == "Shoot Gun") or (text == "Shoot Crossbow") or (text == "Shoot") then
            --print("Found Auto Shot at slot " .. i)
			--return IsUsableAction(i) and IsActionInRange(i)
			return IsActionInRange(cachedShootingSlot) == 1
        end
	else
	--scan all
		for i = 1, 120 do
			UPApiActionSlotScanner:ClearLines()
			-- This tells the tooltip to load the information from action slot 'i'
			UPApiActionSlotScanner:SetAction(i)
			
			-- In 1.12, the first line of the tooltip is the name of the spell/item
			local text = UPApiActionSlotScannerTextLeft1:GetText()
			
			if (text == "Auto Shot") or (text == "Throw") or (text == "Shoot Bow") or (text == "Shoot Gun") or (text == "Shoot Crossbow") or (text == "Shoot") then
				--print("Found Auto Shot at slot " .. i)
				--return IsUsableAction(i) and IsActionInRange(i)
				cachedShootingSlot = i
				return IsActionInRange(i) == 1
			end
		end
	end
	
	return false
end

---------------------------------UNSORTED

function UPApiIsPartyLeader(guid)
	if not guid or not UnitExists(guid) then return false end
	
	-- 2. Check Party Group State
    if GetNumPartyMembers() > 0 then
       -- Check if the unit matches the designated party leader index
		local leaderIndex = GetPartyLeaderIndex()
		if leaderIndex > 0 and UnitIsUnit(guid, "party"..leaderIndex) then
			return true
		end
    end
	
	return false
end

function UPApiIsRaidLeader(guid)
	if not guid or not UnitExists(guid) then return false end
	
	if GetNumRaidMembers() > 0 then
        local targetName = UnitName(guid)
        for i = 1, GetNumRaidMembers() do
            local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
            if name == targetName and rank == 2 then
                return true
            end
        end
    end
	
	return false
end

function UPApiIsRaidAssistant(guid)
	if not guid or not UnitExists(guid) then return false end
	
	if GetNumRaidMembers() > 0 then
        local targetName = UnitName(guid)
        for i = 1, GetNumRaidMembers() do
            local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
            if name == targetName and rank == 1 then
                return true
            end
        end
    end
	
	return false
end

function UPApiIsTarget(guid)
	local unitExists, unitExistsGuid = UnitExists("target")	
	return unitExistsGuid and (unitExistsGuid == guid)
end

function UPApiGetCreatureType(guid)
	local creatureType = UnitCreatureType(guid)
	--most probably just an unknown type
	if (guid and (not creatureType)) then
		creatureType = "UNKNOWN"
	end
	if creatureType and creatureType ~= '' then
		creatureType = string.upper(creatureType)
	end
	
	return creatureType
end

function UPApiGetClassRaceGender(guid)
	local class = UnitClass(guid)
	local race = UnitRace(guid)
	if race then
		race = string.gsub(string.lower(race), " ", "")
		--print("name: "..name.." race: "..race)
	end
	local gender = UnitSex(guid)
	
	return class, race, gender
end

function UPApiGetLevelDifficultyColor(levelNumber)
	local levelDifficultyColor = {r = 0.9, g = 0.0, b = 0.0, a = 0.9} --defaults to red
	if levelNumber > 0 then
		levelDifficultyColor = GetDifficultyColor(levelNumber)
	end
	return levelDifficultyColor
end

function UPApiIsGrayLevel(levelNumber)
	local levelDifficultyColor = UPApiGetLevelDifficultyColor(levelNumber)
	if ((levelDifficultyColor.r == 0.5) and (levelDifficultyColor.g == 0.5) and (levelDifficultyColor.b == 0.5)) then
		return true
	else
		return false
	end
end


---------------------------------UNSORTED END

---------------TOTEMS
local UPApiTotemNameToIconList = {
  ["Disease Cleansing Totem"] = "spell_nature_diseasecleansingtotem",
  ["Earth Elemental Totem"] = "spell_nature_earthelemental_totem",
  ["Earthbind Totem"] = "spell_nature_strengthofearthtotem02",
  ["Fire Elemental Totem"] = "spell_fire_elemental_totem",
  ["Fire Nova Totem"] = "spell_fire_sealoffire",
  ["Fire Resistance Totem"] = "spell_fireresistancetotem_01",
  ["Flametongue Totem"] = "spell_nature_guardianward",
  ["Frost Resistance Totem"] = "spell_frostresistancetotem_01",
  ["Grace of Air Totem"] = "spell_nature_invisibilitytotem",
  ["Grounding Totem"] = "spell_nature_groundingtotem",
  ["Healing Stream Totem"] = "Inv_spear_04",
  ["Magma Totem"] = "spell_fire_selfdestruct",
  ["Mana Spring Totem"] = "spell_nature_manaregentotem",
  ["Mana Tide Totem"] = "spell_frost_summonwaterelemental",
  ["Nature Resistance Totem"] = "spell_nature_natureresistancetotem",
  ["Poison Cleansing Totem"] = "spell_nature_poisoncleansingtotem",
  ["Searing Totem"] = "spell_fire_searingtotem",
  ["Sentry Totem"] = "spell_nature_removecurse",
  ["Stoneclaw Totem"] = "spell_nature_stoneclawtotem",
  ["Stoneskin Totem"] = "spell_nature_stoneskintotem",
  ["Strength of Earth Totem"] = "spell_nature_earthbindtotem",
  ["Totem of Wrath"] = "spell_fire_totemofwrath",
  ["Tremor Totem"] = "spell_nature_tremortotem",
  ["Windfury Totem"] = "spell_nature_windfury",
  ["Windwall Totem"] = "spell_nature_earthbind",
  ["Wrath of Air Totem"] = "spell_nature_slowingtotem"
}

function UpApiGetTotemIconForName(name)
	for totem, icon in pairs(UPApiTotemNameToIconList) do
		if string.find(name, totem) then
			return ("Interface\\Icons\\"..icon)
		end
	end
	return nil
	--return ("Interface\\Icons\\".."spell_nature_slowingtotem")
end

function UPApiIsTotem(name)
	local totemIcon = UpApiGetTotemIconForName(name)
	if totemIcon then
		return true
	end
	return false
	-- return true
end
---------------TOTEMS END

------------------------------AURAS

local UPApiGuidAurasCache = {}

-- A helper to get or create the sub-table for a GUID
local function UPApiGetGuidAurasCache(guid)
    if not UPApiGuidAurasCache[guid] then
        UPApiGuidAurasCache[guid] = {}
    end
    return UPApiGuidAurasCache[guid]
end

local function UPApiPutIntoAurasCache(guid, spellId, name, texture, count, debuffType, duration, startTime, expirationTime, isDebuff, isMyAura, casterGuid)
    if not guid or not name then return end
    
    local cache = UPApiGetGuidAurasCache(guid)
	
	local localIsMyAura = nil
	local localCasterGuid = nil
	
	-- if cache[name] and cache[name].isMyAura then
		-- localIsMyAura = cache[name].isMyAura
	-- end
	
	if cache[name] then
		if cache[name].isMyAura ~= nil then
			localIsMyAura = cache[name].isMyAura
		end
		if cache[name].casterGuid ~= nil then
			localCasterGuid = cache[name].casterGuid
		end
	end
	
	if isMyAura ~= nil then
		localIsMyAura = isMyAura
	end
	if casterGuid ~= nil then
		localCasterGuid = casterGuid
	end
	
	-- if isMyAura then
		-- print("UPApiPutIntoAurasCache: name: "..tostring(name))
		-- print("UPApiPutIntoAurasCache: ismyaura p: "..tostring(isMyAura))
		-- print("UPApiPutIntoAurasCache: ismyaura local: "..tostring(localIsMyAura))
	-- end
    
    cache[name] = {
        spellId = spellId,
		name = name,
		texture = texture,
		count = count,
		debuffType = debuffType,
		duration = duration,
		startTime = startTime,
		expirationTime = expirationTime,
		isDebuff = isDebuff,
		isMyAura = localIsMyAura,
		casterGuid = localCasterGuid
    }
end

local function UPApiUnitHasBuff(unitGUID, expectedName)
	local hasBuff = false
	
	-- local buffName, buffRank = GetPlayerBuffName(1)
	-- print("debug: "..buffName.."/"..buffRank)
	
    -- for i=0,40 do
		-- local bId,bCancel = GetPlayerBuff(i,"HELPFUL|HARMFUL|PASSIVE")
		-- if(bId >= 0) then			
			-- local buffName, bufftexture, buffSecondsLeft, buffCount = getBuffInfo(bId, bCancel)
			-- --print(i.." debug buffName: "..buffName.." bufftexture: "..bufftexture.." buffSecondsLeft: "..buffSecondsLeft.." buffCount: "..buffCount)
			-- if not buffName then
				-- break
			-- end
			
			-- if buffName == expectedName then
				-- hasBuff = true
				-- break 
			-- end
		-- end
    -- end 
	
	-- 2. Scan Buffs
    local i = 1
    while true do
        local texture, count, spellId = UnitBuff(unitGUID, i)
        if not texture then break end -- No more buffs
        
		local name, rank, icon, spellMinRange, spellMaxRange = SpellInfo(spellId)
        if name == expectedName then
            return true
        end
        i = i + 1
    end
	
	return hasBuff
end

-- Returns false if it is BUFF, true if it is DEBUFF or nil if it exists on the unit
local function UPApiGetAuraTypeOnUnit(unitGUID, targetSpellId)
    if not unitGUID or not targetSpellId then return nil end
	--local name, rank, icon, spellMinRange, spellMaxRange = SpellInfo(spellId)

    -- 1. Scan Debuffs first (usually what we care about for hostile mobs)
    local i = 1
    while true do
        -- SuperWoW: UnitDebuff returns (texture, count, debuffType, spellId)
        local texture, count, debuffType, spellId = UnitDebuff(unitGUID, i)
        if not texture then break end -- No more debuffs
        
        if spellId == targetSpellId then
            --return "DEBUFF"
			return true
        end
        i = i + 1
    end

    -- 2. Scan Buffs
    i = 1
    while true do
        local texture, count, spellId = UnitBuff(unitGUID, i)
        if not texture then break end -- No more buffs
        
        if spellId == targetSpellId then
            --return "BUFF"
			return false
        end
        i = i + 1
    end

    return nil
end

local function UPApiSyncAurasCacheWithActual(guid)
	--print("UPApiSyncAurasCacheWithActual "..auraName.." from UPApiPendingAuraRefreshes isDebuff: "..tostring(isDebuff))


	local actualUnitAuras = {} --both debuffs and buffs in case buff/debuff gets assigned wrong
	for i = 1, 16 do
		local texture, count, debuffType, spellId
		texture, count, spellId = UnitBuff(guid, i)
		-- In WoW, the loop continues until it hits a nil name (end of auras)
		if not texture then 
			break 
		end
		
		local name, rank, icon, spellMinRange, spellMaxRange = SpellInfo(spellId)
		--print("aura name1: "..tostring(name))
		
		actualUnitAuras[name] = { 
			spellId = spellId,
			name = name,
			texture = texture,
			count = count,
			debuffType = debuffType,
			isDebuff = false
		}
	end
	for i = 1, 16 do
		local texture, count, debuffType, spellId
		texture, count, debuffType, spellId = UnitDebuff(guid, i)
		-- In WoW, the loop continues until it hits a nil name (end of auras)
		if not texture then 
			break 
		end
		
		local name, rank, icon, spellMinRange, spellMaxRange = SpellInfo(spellId)
		--print("aura name1: "..tostring(name))
		
		actualUnitAuras[name] = { 
			spellId = spellId,
			name = name,
			texture = texture,
			count = count,
			debuffType = debuffType,
			isDebuff = true
		}
	end
	
	-- SYNC: Remove from Cache if not on Unit
    local cache = UPApiGetGuidAurasCache(guid)
    for cachedName, cachedData in pairs(cache) do
        if not actualUnitAuras[cachedName] then
			-- The aura is in our cache but no longer on the unit (faded/dispelled)
			cache[cachedName] = nil 
		else
			-- It's still there! Update the count/texture/isDebuff in case they changed
			cachedData.count = actualUnitAuras[cachedName].count
			cachedData.texture = actualUnitAuras[cachedName].texture
			cachedData.isDebuff = actualUnitAuras[cachedName].isDebuff
		end
    end
	
	-- -- INFINITE DURATION HANDLER: Add paladin auras, warrior stances etc.
    for actualName, actualData in pairs(actualUnitAuras) do
        -- If it's not in our cache yet, check if it's an "Infinite" spell
		--print("adding "..actualName.." as infinite aura")
        --if not cache[actualName] and UPLibAuraDurationsByRank[actualName] and (UPLibAuraDurationsByRank[actualName][0] == -1) then
		if not cache[actualName] and (UPLibAuraDurationsGetAuraDuration(actualName, 0, nil) == -1) then
			--guid, spellId, name, texture, count, debuffType, duration, startTime, expirationTime, isDebuff
			--print("adding "..actualName.." as infinite aura")
            UPApiPutIntoAurasCache(
                guid, 
                actualData.spellId, 
                actualName, 
                actualData.texture, 
                actualData.count, 
                nil, -- debuffType
                -1,   -- duration (-1 = infinite)
                -1, -- startTime
                -1,   -- expirationTime (-1 = never)
                UPApiGetAuraTypeOnUnit(guid, actualData.spellId), --isDebuff
				nil, --unknown (isMyAura)
				nil  -- unknown (casterGuid)
            )
		elseif not cache[actualName] and (UPLibAuraDurationsGetAuraDuration(actualName, 0, nil) ~= nil and UPLibAuraDurationsGetAuraDuration(actualName, 0, nil) > 0) then
			--assume max duration on auras that are not in cache
			local xDuration = UPLibAuraDurationsGetAuraDuration(actualName, 0, nil)
			if (xDuration ~= nil) then
				local xStartTime = GetTime()
				local xExpirationTime = xStartTime+xDuration
				UPApiPutIntoAurasCache(
					guid, 
					actualData.spellId, 
					actualName, 
					actualData.texture, 
					actualData.count, 
					nil, -- debuffType
					xDuration,   -- duration (-1 = infinite)
					xStartTime, -- startTime
					xExpirationTime,   -- expirationTime (-1 = never)
					UPApiGetAuraTypeOnUnit(guid, actualData.spellId), --isDebuff
					nil, --unknown (isMyAura)
					nil  -- unknown (casterGuid)
				)
			end
        end
    end
end

local function UPApiCacheInAuraIfValid(guid, auraName, isDebuff, isMyAura, casterGuid)

	-- print("UPApiCacheInAuraIfValid "..auraName.." from UPApiPendingAuraRefreshes isDebuff: "..tostring(isDebuff))
	
	-- if (isDebuff == nil) then
		-- print("UPApiCacheInAuraIfValid "..auraName.." from UPApiPendingAuraRefreshes isDebuff is nil")
	-- end

	-- if isMyAura then
		-- print("UPApiCacheInAuraIfValid: name: "..tostring(auraName))
		-- print("UPApiCacheInAuraIfValid: ismyaura p: "..tostring(isMyAura))
	-- end

	--print("new aura cache data0: "..tostring(guid).." "..tostring(auraName).." "..tostring(isDebuff))

	if (isDebuff == true) or (isDebuff == nil) then
		--check for unit debuffs with same name
		for i = 1, 16 do
			local texture, count, debuffType, spellId, add1, add2, add3, add4 = UnitDebuff(guid, i)
			local name, rank, icon, spellMinRange, spellMaxRange = SpellInfo(spellId)
			if rank == nil or rank == '' then
				rank = "Rank 0"
			end
			--parse rank into number
			--local rankNumber = tonumber(string.match(rank, "(%d+)"))
			local _, _, rankNumberStr = string.find(rank, "(%d+)")
			local rankNumber = tonumber(rankNumberStr)
			
			-- print("auraName: "..tostring(auraName))
			-- print("name: "..tostring(name))
			-- print("rank: "..tostring(rank))
			-- print("texture: "..tostring(texture))
			-- print("count: "..tostring(count))
			
			if auraName == name then
				--rank can be empty string (then use 0)
				-- print("rank: "..tostring(rank))
				-- print("texture: "..tostring(texture))
				-- print("count: "..tostring(count))
				
				local duration = UPLibAuraDurationsGetAuraDuration(name, rankNumber, isMyAura)
				if duration == nil then
					--exit early
					break
				end			
				--duration is in seconds, GetTime() is also in seconds, floating (like 9.53 seconds)
				--put into cache
				local startTime = GetTime()
				local expirationTime = startTime+duration
				-- print("UPApiCacheInAuraIfValid1 "..auraName.." from UPApiPendingAuraRefreshes")
				UPApiPutIntoAurasCache(
					guid,
					spellId,
					name,
					texture,
					count,
					debuffType,
					duration,
					startTime,
					expirationTime,
					true,
					isMyAura, --can be nil
					casterGuid -- Passed down
				)
				
				--print("new aura cache data: "..tostring(name).." "..tostring(startTime).." "..tostring(expirationTime).." "..tostring(duration))
				
				--break loop (found it)
				break
			end
		end
	end
	if (isDebuff == false) or (isDebuff == nil) then
		--check for unit buffs with same name
		for i = 1, 16 do
			local texture, count, spellId, add1, add2, add3, add4 = UnitBuff(guid, i)
			local name, rank, icon, spellMinRange, spellMaxRange = SpellInfo(spellId)
			if rank == nil or rank == '' then
				rank = "Rank 0"
			end
			--parse rank into number
			--local rankNumber = tonumber(string.match(rank, "(%d+)"))
			local _, _, rankNumberStr = string.find(rank, "(%d+)")
			local rankNumber = tonumber(rankNumberStr)
			
			-- print("auraName: "..tostring(auraName))
			-- print("name: "..tostring(name))
			-- print("rank: "..tostring(rank))
			-- print("texture: "..tostring(texture))
			-- print("count: "..tostring(count))
			
			if auraName == name then
				--rank can be empty string (then use 0)
				-- print("rank: "..tostring(rank))
				-- print("texture: "..tostring(texture))
				-- print("count: "..tostring(count))
				
				local duration = UPLibAuraDurationsGetAuraDuration(name, rankNumber, isMyAura)
				if duration == nil then
					--exit early
					break
				end			
				--duration is in seconds, GetTime() is also in seconds, floating (like 9.53 seconds)
				--put into cache
				local startTime = GetTime()
				local expirationTime = startTime+duration
				-- print("UPApiCacheInAuraIfValid2 "..auraName.." from UPApiPendingAuraRefreshes")
				UPApiPutIntoAurasCache(
					guid,
					spellId,
					name,
					texture,
					count,
					debuffType,
					duration,
					startTime,
					expirationTime,
					false,
					isMyAura, --can be nil
					casterGuid -- Passed down
				)
				
				--break loop (found it)
				break
			end
		end
	end
	
	--now also compare actual auras with this, and remove if it is not in actual auras
	--UPApiSyncAurasCacheWithActual(guid)
	-- if overrideSyncDelay then
		-- UPCoreDelayCall(
			-- overrideSyncDelay,
			-- UPApiSyncAurasCacheWithActual,
			-- guid
		-- )
	-- else
		-- UPCoreDelayCall(
			-- UPApiGetAdditionalAuraPollingDelaySeconds() + UPCoreGetCurrentPingSeconds(),
			-- UPApiSyncAurasCacheWithActual,
			-- guid
		-- )
	-- end
	UPCoreDelayCall(
		UPApiGetAdditionalAuraPollingDelaySeconds() + UPCoreGetCurrentPingSeconds(),
		UPApiSyncAurasCacheWithActual,
		guid
	)
	
end

--PUBLIC
function UpApiGetUnitAuras(guid, getBuffs, onlyMineBuffs, getDebuffs, onlyMineDebuffs, ignoredBuffNames, ignoredDebuffNames)	
	--UPApiSyncAurasCacheWithActual(guid)
	UPCoreDelayCall(
		UPApiGetAdditionalAuraPollingDelaySeconds() + UPCoreGetCurrentPingSeconds(),
		UPApiSyncAurasCacheWithActual,
		guid
	)

	local maxAuras = 80 -- maybe it could be more than 16, whatever
	local unitBuffs = {}
	local unitDebuffs = {}
	
	if not guid or not UnitExists(guid) then
		return nil
	end
	
	local cache = UPApiGetGuidAurasCache(guid)
	for cachedName, cachedData in pairs(cache) do
		local spellId = cachedData.spellId
		local name = cachedData.name
		local texture = cachedData.texture
		local count = cachedData.count
		local debuffType = cachedData.debuffType
		local duration = cachedData.duration
		local startTime = cachedData.startTime
		local expirationTime = cachedData.expirationTime
		local isDebuff = cachedData.isDebuff
		local isMyAura = cachedData.isMyAura
		local casterGuid = cachedData.casterGuid -- Retrieve it
		
		--print("aura name1: "..tostring(name))
		
		if getBuffs and (not isDebuff) then
			local nameIsIgnored = false
			for _, ignoredBuffName in ipairs(ignoredBuffNames) do
				if (string.upper(name) == string.upper(ignoredBuffName)) then
					nameIsIgnored = true
					break
				end
			end
			
			if (not nameIsIgnored) and (not (onlyMineBuffs and (not isMyAura))) then
				table.insert(unitBuffs, {
					spellId = spellId,
					name = name,
					texture = texture,
					count = count,
					debuffType = debuffType,
					duration = duration,
					startTime = startTime,
					expirationTime = expirationTime,
					isDebuff = false,
					--isMyAura = nil,
					casterGuid = casterGuid -- Add to return table
				})
			end
		end
		
		if getDebuffs and (isDebuff) then
			local nameIsIgnored = false
			for _, ignoredDebuffName in ipairs(ignoredDebuffNames) do
				if (string.upper(name) == string.upper(ignoredDebuffName)) then
					nameIsIgnored = true
					break
				end
			end
			
			if (not nameIsIgnored) and (not (onlyMineDebuffs and (not isMyAura))) then
				table.insert(unitDebuffs, {
					spellId = spellId,
					name = name,
					texture = texture,
					count = count,
					debuffType = debuffType,
					duration = duration,
					startTime = startTime,
					expirationTime = expirationTime,
					isDebuff = true,
					--isMyAura = nil,
					casterGuid = casterGuid -- Add to return table
				})
				
				--print("new aura poll: "..tostring(name).." "..tostring(startTime).." "..tostring(expirationTime).." "..tostring(duration))
			end
		end
	end
	
	--sort by expirationTime DESC
	table.sort(unitBuffs, function(a, b)
		return a.expirationTime > b.expirationTime
	end)
	
	--sort by expirationTime DESC
	table.sort(unitDebuffs, function(a, b)
		return a.expirationTime > b.expirationTime
	end)
	
	local allAuras = {}
	
	-- Copy Buffs
	for _, data in ipairs(unitBuffs) do
		table.insert(allAuras, data)
	end
	
	-- Copy Debuffs
	for _, data in ipairs(unitDebuffs) do
		table.insert(allAuras, data)
	end
	
	return allAuras
end

------------------------------AURAS END

--CASTING
local UPApiCastCache = {}

-- -- Helper to get or create a cache entry
local function UPApiGetCastEntry(guid)
    if not UPApiCastCache[guid] then
        UPApiCastCache[guid] = { 
            name = nil,
			icon = nil,
            startTime = 0, 
            endTime = 0, 
            interruptible = true, 
            isChannel = false 
        }
    end
    return UPApiCastCache[guid]
end

--PUBLIC
function UPApiUnitCastingInfo(guid)
	local spellName = nil
	local spellNameSecondary = nil
	local spellDisplayName = nil
	local spellIcon = nil
	local spellStartTimeMillis = nil
	local spellEndTimeMillis = nil
	local spellIsTradeSkill = nil
	local isChannel = nil
	
	local entry = UPApiGetCastEntry(guid)
	
	spellName = entry.name
	spellIcon = entry.icon
	spellStartTimeMillis = entry.startTime
	spellEndTimeMillis = entry.endTime
	isChannel = entry.isChannel
	
	return spellName, spellNameSecondary, spellDisplayName, spellIcon, spellStartTimeMillis, spellEndTimeMillis, spellIsTradeSkill, isChannel
end
--CASTING END

function UPApiIsUnitTargetingMe(guid)
    local targetToken = guid.."target" --dark magic
    if UnitExists(targetToken) then
        -- Compare the GUIDs
        if UnitName(targetToken) == UnitName("player") then
            return true
        end
    end
    return false
end

local UPApiPendingAuraRefreshes = {}
local UPApiPendingAoEAuraRefreshes = {} --special for AoE casts
--local UPApiPlayerGUIDPlaceholder = "You"
local UPApiLastFadedSeals = {}


------------------------------ApiFrame
local UPApiFrame = CreateFrame("Frame", "UPApiFrameFrame", UIParent)
UPApiFrame:SetFrameStrata("LOW")
UPApiFrame.TimeToCheck = 0
UPApiFrame.numFrames = 0

UPApiFrame:RegisterEvent("RAW_COMBATLOG")
UPApiFrame:RegisterEvent("UNIT_CASTEVENT")
UPApiFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
UPApiFrame:RegisterEvent("SPELLS_CHANGED")

UPApiFrame:SetScript("OnUpdate", function()
	if UnitPlatesAddonIsLoaded and UnitPlatesPlayerEnteredWorld and (UnitPlatesElapsedTimeSinceFullyLoaded > UnitPlatesLoadDelay) then
		local currentTime = GetTime()
		
		for casterGUID, spells in pairs(UPApiPendingAuraRefreshes) do
			for spellName, data in pairs(spells) do
			
				--cache in once early (it will be removed if wrong anyways)
				-- if (currentTime - data.time) > (math.max(0.2 + UPCoreGetCurrentPingSeconds())) then
					-- UPApiCacheInAuraIfValid(
						-- data.targetGUID,
						-- spellName,
						-- data.isDebuff or auraType,
						-- data.isMyAura,
						-- 0.01
					-- )
				-- end
				
				-- If 0.2 seconds pass without a failure combat log, commit it!
				-- need a higher delay, it may not be in the ACTUAL buff/debuff list YET!!!
				if (currentTime - data.time) > (0.2 + UPCoreGetCurrentPingSeconds()) then --used to be 0.5	
				
					-- local isDebuff = UPApiGetAuraTypeOnUnit(data.targetGUID, data.spellId)
					
					-- if data.isMyAura then
						-- print("UPApiPendingAuraRefreshes release for "..spellName.." auraType: "..tostring(auraType))
					-- end
					
					--print("UPApiPendingAuraRefreshes release for "..spellName.." auraType: "..tostring(auraType))
					
					-- 1. Snapshot the variables for this specific loop iteration
					local pTarget = data.targetGUID
					local pSpell = spellName
					local pDebuff = data.isDebuff or UPApiGetAuraTypeOnUnit(data.targetGUID, data.spellId)
					local pMine = data.isMyAura
					local pCaster = casterGUID
					
					-- print("UPCoreDelayCall "..spellName.." from UPApiPendingAuraRefreshes")
					UPCoreDelayCall(
						UPApiGetAdditionalAuraPollingDelaySeconds() + UPCoreGetCurrentPingSeconds(), 
						function()
							UPApiCacheInAuraIfValid(pTarget, pSpell, pDebuff, pMine, pCaster)
						end
					)
					
					-- UPCoreDelayCall(
						-- UPApiGetAdditionalAuraPollingDelaySeconds() + UPCoreGetCurrentPingSeconds(),
						-- UPApiCacheInAuraIfValid,
						-- pTarget,
						-- pSpell,
						-- pDebuff,
						-- pMine,
						-- pCaster
					-- )
					
					-- UPCoreDelayCall(
						-- UPApiGetAdditionalAuraPollingDelaySeconds() + UPCoreGetCurrentPingSeconds(), 
						-- UPApiCacheInAuraIfValid, 
						-- data.targetGUID, 
						-- spellName, 
						-- data.isDebuff or auraType, 
						-- data.isMyAura,
						-- casterGUID -- Pass the key from the loop
					-- )
				
					-- UPApiCacheInAuraIfValid(
						-- data.targetGUID,
						-- spellName,
						-- data.isDebuff or auraType,
						-- data.isMyAura
					-- )
					spells[spellName] = nil
				end
			end
			
			-- Memory cleanup: Delete empty caster tables
			if next(spells) == nil then
				UPApiPendingAuraRefreshes[casterGUID] = nil
			end
		end
		
		
		
		--AoE
		for casterGUID, spells in pairs(UPApiPendingAoEAuraRefreshes) do
			for spellName, targets in pairs(spells) do
				for targetGUID, data in pairs(targets) do
			
					-- If 0.2 seconds pass without a failure combat log, commit it!
					if (currentTime - data.time) > (0.2 + UPCoreGetCurrentPingSeconds()) then					
					
						-- local isDebuff = UPApiGetAuraTypeOnUnit(targetGUID, data.spellId)
						
						-- 1. Snapshot the variables for the AoE loop iteration
						local pTarget = targetGUID
						local pSpell = spellName
						local pDebuff = data.isDebuff or UPApiGetAuraTypeOnUnit(targetGUID, data.spellId)
						local pMine = data.isMyAura
						local pCaster = casterGUID
						
						-- 2. Pass them inside a parameter-less anonymous function
						UPCoreDelayCall(
							UPApiGetAdditionalAuraPollingDelaySeconds() + UPCoreGetCurrentPingSeconds(), 
							function()
								UPApiCacheInAuraIfValid(pTarget, pSpell, pDebuff, pMine, pCaster)
							end
						)
						
						-- UPCoreDelayCall(
							-- UPApiGetAdditionalAuraPollingDelaySeconds() + UPCoreGetCurrentPingSeconds(), 
							-- UPApiCacheInAuraIfValid, 
							-- targetGUID, 
							-- spellName, 
							-- data.isDebuff or auraType, 
							-- data.isMyAura,
							-- casterGUID -- Pass the key from the loop
						-- )
						
						-- Clear this target out of the queue
						targets[targetGUID] = nil
					end
				end
				
				-- Memory cleanup: Delete empty spell tables
				if next(targets) == nil then
					spells[spellName] = nil
				end
			end
			
			-- Memory cleanup: Delete empty caster tables
			if next(spells) == nil then
				UPApiPendingAoEAuraRefreshes[casterGUID] = nil
			end
		end
		
		
	end
end)

UPApiFrame:SetScript("OnEvent", function()
	if event == "ACTIONBAR_SLOT_CHANGED" or event == "SPELLS_CHANGED" then
		cachedShootingSlot = 0
	end
	
	if event == "RAW_COMBATLOG" then
	
	--print("raw combat log event: "..arg2)
	
	--here I can keep track of last faded seal on unit
	if arg2 and (string.find(arg2, "Seal") and string.find(arg2, "fades")) then
		--print("raw combat log event: "..arg2)
		
		-- Pattern A: Fades from the player ("Seal of X fades from you.")
		local _, _, sealName = string.find(arg2, "^(Seal.-) fades from you%.")
		if sealName then
			UPApiLastFadedSeals[UPApiGetMyGUID()] = sealName
		else
			-- Pattern B: Fades from others ("Seal of X fades from 0xABC123.")
			local _, _, sealName, guid = string.find(arg2, "^(Seal.-) fades from (0x%x+)%.")
			if sealName and guid then
				UPApiLastFadedSeals[guid] = sealName
			end
		end
	end
	
	--if you are paladin
	local localizedClass, englishClass = UnitClass("player")
	--if "You hit guid for x damage" then refresh your judgements
	--CASE JUDGEMENT IS YOURS
	if arg2 and (string.find(arg2, "You hit") or string.find(arg2, "You crit")) then
		--refresh your judgements
		--print("judgement refresh 1: "..arg2)
		
		local _, _, hitGuid = string.find(arg2, "You hit (0x%x+)")
		if not hitGuid then
			_, _, hitGuid = string.find(arg2, "You crit (0x%x+)")
		end
		
		if hitGuid then
			--print("judgement refresh 2: "..hitGuid)
			-- Grab the target's current aura cache
			local cache = UPApiGetGuidAurasCache(hitGuid)
			
			-- The standard Vanilla Paladin judgements that refresh on melee hits

			local currentTime = GetTime()

			for _, judgementName in ipairs(UPLibPaladinRefreshableJudgements) do
				local auraData = cache[judgementName]				
				
				--If the target has this judgement, and we track it in our cache, refresh it
				--no way to know if the judgement is yours
				if auraData and auraData.isMyAura then
					-- Grab the duration from your external duration library (defaulting to 10s if nil)
					local duration = UPLibAuraDurationsGetAuraDuration(judgementName, 0, auraData.isMyAura) or 10.0
					
					-- Reset the timers to simulate the silent server refresh
					auraData.startTime = currentTime
					auraData.expirationTime = currentTime + duration
					
					--print("judgement refresh 3: "..hitGuid)
					
					-- Optional debugging:
					--print("judgement refresh 4: " .. judgementName .. " on " .. hitGuid)
				end
			end
		end
	end
	--CASE JUDGEMENT IS NOT YOURS
	if arg2 and (string.find(arg2, "hits") or string.find(arg2, "crits")) then
		
		-- Capture BOTH the attacker's GUID and the mob's GUID
		local _, _, attackerGuid, hitGuid = string.find(arg2, "^(0x%x+) hits (0x%x+)")
		if not attackerGuid then
			_, _, attackerGuid, hitGuid = string.find(arg2, "^(0x%x+) crits (0x%x+)")
		end
		
		--print("judgement refresh 1: "..arg2)
		
		--print("judgement refresh 1: "..attackerGuid)
		--print("judgement refresh 1: "..hitGuid)
		
		if attackerGuid and hitGuid then
			local cache = UPApiGetGuidAurasCache(hitGuid)
			local currentTime = GetTime()

			for _, judgementName in ipairs(UPLibPaladinRefreshableJudgements) do
				local auraData = cache[judgementName]	

				--print("---111Refreshed1 " .. judgementName .. " on " .. hitGuid .. " for caster " .. attackerGuid)
				
				-- if auraData then
					-- print(tostring(auraData))
					-- print(tostring(auraData.casterGuid))
					-- print(tostring(auraData.spellId))
				-- end
				
				-- Check if the aura exists, is NOT yours, AND the attacker is the one who cast it
				if auraData and (not auraData.isMyAura) and (auraData.casterGuid == attackerGuid) then
					local duration = UPLibAuraDurationsGetAuraDuration(judgementName, 0, auraData.isMyAura) or 10.0
					
					-- Reset the timers to simulate the silent server refresh
					auraData.startTime = currentTime
					auraData.expirationTime = currentTime + duration
					
					-- Optional debugging:
					-- print("000Refreshed " .. judgementName .. " on " .. hitGuid .. " for caster " .. attackerGuid)
				end
			end
		end
	end
	
	--if arg2 and (string.find(arg2, "missed") or string.find(arg2, "dodged") or string.find(arg2, "parried") or string.find(arg2, "resisted") or string.find(arg2, "failed")) then
	-- if arg2 and (string.find(arg2, "missed") or string.find(arg2, "dodged") or string.find(arg2, "parried") or string.find(arg2, "resisted")) then
	if arg2 and (
			string.find(arg2, "dodged") or 
            string.find(arg2, "parried") or 
            (string.find(arg2, "resisted") and (not string.find(arg2, "resisted)"))) or
            (string.find(arg2, "blocked") and (not string.find(arg2, "blocked)"))) or
            string.find(arg2, "evaded") or 
            string.find(arg2, "deflected") or 
			 
			string.find(arg2, "missed") or
			string.find(arg2, "immune")
			)
             --string.find(arg2, "fail")) 
			 then
		--print(arg1)
		--print(arg2)
		
		-- if string.find(arg2, "resisted") then
			-- print(arg1)
			-- print(arg2)
		-- end
		
		local failedSpellName = nil
		local failedTargetGUID = nil
		local failedCasterGUID = nil
		
		-- 2. Pattern A: MY failures ("Your Rend is/was parried by 0x...")
		local _, _, spell, target = string.find(arg2, "^Your (.-) is .- (0x%x+)")
		if not spell then
			_, _, spell, target = string.find(arg2, "^Your (.-) was .- (0x%x+)")
		end
		if not spell then
			_, _, spell, target = string.find(arg2, "^Your (.-) missed (0x%x+)")
		end
		if not spell then
			_, _, spell, target = string.find(arg2, "^Your (.-) failed%. .- (0x%x+)")
		end
		
		if spell and target then
			failedSpellName = spell
			failedTargetGUID = target
			--failedCasterGUID = UPApiPlayerGUID -- Mapped from our UNIT_CASTEVENT catch
			failedCasterGUID = UPApiGetMyGUID()
		else
			-- 3. Pattern B: OTHERS' failures ("0xABC...'s Rend was/is parried by 0xDEF...")
			local _, _, caster, spell, target = string.find(arg2, "^(0x%x+)'s (.-) was .- (0x%x+)")
			if not caster then
				_, _, caster, spell, target = string.find(arg2, "^(0x%x+)'s (.-) is .- (0x%x+)")
			end
			if not caster then
				_, _, caster, spell, target = string.find(arg2, "^(0x%x+)'s (.-) missed (0x%x+)")
			end
			if not caster then
				_, _, caster, spell, target = string.find(arg2, "^(0x%x+)'s (.-) failed%. .- (0x%x+)")
			end
			
			if caster and spell and target then
				failedCasterGUID = caster
				failedSpellName = spell
				failedTargetGUID = target
			else			
			--print out or report failed case
			-- print("UPApiPendingAuraRefreshes unparsed event:")
			-- print(arg1)
			-- print(arg2)
			end
		end
		
		-- 4. If we parsed a failure, delete it from the waiting room!
		if failedCasterGUID and failedSpellName and UPApiPendingAuraRefreshes[failedCasterGUID] then
			if UPApiPendingAuraRefreshes[failedCasterGUID][failedSpellName] then
				-- Verify the target GUID matches just to be bulletproof
				if UPApiPendingAuraRefreshes[failedCasterGUID][failedSpellName].targetGUID == failedTargetGUID then
					UPApiPendingAuraRefreshes[failedCasterGUID][failedSpellName] = nil
				end
			end
		end
		
		if failedCasterGUID and failedSpellName and failedTargetGUID and UPApiPendingAoEAuraRefreshes[failedCasterGUID] then
			if UPApiPendingAoEAuraRefreshes[failedCasterGUID][failedSpellName] then
				-- Directly clear this specific target from the waiting room
				if UPApiPendingAoEAuraRefreshes[failedCasterGUID][failedSpellName][failedTargetGUID] then
					UPApiPendingAoEAuraRefreshes[failedCasterGUID][failedSpellName][failedTargetGUID] = nil
				end
				
				-- -- Clean up empty spell table
				-- if next(UPApiPendingAoEAuraRefreshes[failedCasterGUID][failedSpellName]) == nil then
					-- UPApiPendingAoEAuraRefreshes[failedCasterGUID][failedSpellName] = nil
				-- end
			end
			
			-- -- Clean up empty caster table
			-- if next(UPApiPendingAoEAuraRefreshes[failedCasterGUID]) == nil then
				-- UPApiPendingAoEAuraRefreshes[failedCasterGUID] = nil
			-- end
		end
		
	end
	
		-- if string.find(arg2, "Feed Pet") then
			-- print(arg1)
			-- print(arg2)
		-- end
		--arg1 is event name
		--if string.find(arg2, "Rend") then
		--if string.find(arg2, "fades") then
		-- if string.find(arg2, "gain") or string.find(arg2, "afflicted") then
			-- print("event: "..tostring(event))
			-- print("arg1: "..tostring(arg1))--guid
			-- print("arg2: "..tostring(arg2))
			-- print("arg3: "..tostring(arg3))
			-- print("arg4: "..tostring(arg4))
			-- print("arg5: "..tostring(arg5))
		-- end
		
		if arg1 == "CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS" 
		or arg1 == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS" 
		or arg1 == "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS"
		or arg1 == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" --for pet
		then
			-- if string.find(arg2, "Feed Pet") then
				-- print(arg2)
			-- end
			
			-- if string.find(arg2, "Rend") then
				-- print(arg2)
			-- end
		
		
			local _, _, guid, auraName = string.find(arg2, "^(0x%x+)%sgains%s([^%d].-)%.$")
			if guid and auraName then
				-- print("assumed buff gain: ")
				-- print("guid: "..tostring(guid))
				-- print("auraName: "..tostring(auraName))
				
				-- if string.find(arg2, "Feed Pet") then
					-- print(arg2)
				-- end
				
				local isMyAura = nil --source is unknown
				-- if arg1 == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" then
					-- isMyAura = true
				-- end
				
				--put it into cache here
				-- UPApiCacheInAuraIfValid(
					-- guid,
					-- auraName,
					-- false,
					-- isMyAura
				-- )
				
				UPCoreDelayCall(
					UPApiGetAdditionalAuraPollingDelaySeconds() + UPCoreGetCurrentPingSeconds(), 
					UPApiCacheInAuraIfValid, 
					guid,
					auraName,
					false,
					isMyAura
				)
			end
		end
		
		if arg1 == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" 
		or arg1 == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE" 
		or arg1 == "CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE"
		or arg1 == "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE" --for pet
		then
			-- if string.find(arg2, "Feed Pet") then
				-- print(arg2)
			-- end
			
			-- if string.find(arg2, "Rend") then
				-- print(arg2)
			-- end
			
			-- -- 1. PARSE OTHER PLAYERS / PETS ("Thrall's Rend missed...")
			-- local _, _, cName, sName = string.find(msg, "^(0x%x+)'s%s(.-)%swas%sdodged%sby(.-) missed")
			-- if not cName then _, _, cName, sName = string.find(msg, "([^']+)'s (.-) was dodged") end
			-- if not cName then _, _, cName, sName = string.find(msg, "([^']+)'s (.-) was parried") end
			-- if not cName then _, _, cName, sName = string.find(msg, "([^']+)'s (.-) was resisted") end
			-- if not cName then _, _, cName, sName = string.find(msg, "([^']+)'s (.-) failed") end
		
			local _, _, guid, auraName = string.find(arg2, "^(0x%x+)%sis%safflicted%sby%s(.-)%.$")
			if guid and auraName then
				-- print("assumed debuff gain: ")
				-- print("guid: "..tostring(guid))
				-- print("auraName: "..tostring(auraName))
				
				local isMyAura = nil --source is unknown
				-- if arg1 == "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE" then
					-- isMyAura = true
				-- end
				
				--put it into cache here
				-- UPApiCacheInAuraIfValid(
					-- guid,
					-- auraName,
					-- true,
					-- isMyAura
				-- )				
				
				UPCoreDelayCall(
					UPApiGetAdditionalAuraPollingDelaySeconds() + UPCoreGetCurrentPingSeconds(), 
					UPApiCacheInAuraIfValid, 
					guid,
					auraName,
					true,
					isMyAura
				)
			end
		end
	end
	
	if event == "UNIT_CASTEVENT" then
		local casterGUID, targetGUID, eventType, spellId, duration = arg1, arg2, arg3, arg4, arg5
	
		if eventType == "MAINHAND" or eventType == "OFFHAND" then return nil end
		
		--local casterName = UnitName(casterGUID)
		--local targetName = UnitName(targetGUID)
		
		local spellName, spellRank, spellTexture, spellMinRange, spellMaxRange = SpellInfo(spellId)
		
		--spellName = nil
		if not spellName then
			--print("adasdasd")
			return nil
		end
		
		-- if string.find(spellName, "Rend") then
			-- print(eventType)
		-- end
		
		-- print("OnUnitCastEvent")
		-- print("casterName: ".. casterName)
		-- print("casterGUID: ".. casterGUID)
		-- print("targetGUID: ".. targetGUID)
		-- print("eventType: ".. eventType)
		-- print("spellId: ".. spellId)
		-- print("spellName: ".. spellName)
		-- print("spellTexture: ".. spellTexture)
		-- print("duration: ".. duration)
		
		local entry = UPApiGetCastEntry(casterGUID)
		
		local currTime = GetTime() * 1000
		if eventType == "START" or eventType == "CHANNEL" then
			entry.name = spellName
			entry.icon = spellTexture
			entry.startTime = currTime
			entry.endTime = currTime + duration
			entry.isChannel = (eventType == "CHANNEL")
			entry.interruptible = true -- SuperWoW doesn't always provide this in arg, 
									   -- you may need a separate list for boss spells
		elseif eventType == "CAST" then
			-- print("cast event for: "..spellName)
			-- print("cast event for: "..spellName.." targetGUID: "..targetGUID.." spellId: "..spellId)
			--entry.name = nil
			--entry.endTime = 0
			
			-- Capture our own GUID dynamically so we can map "Your" logs later
			local isMyAura = nil
			--local realCasterGuid = casterGUID
			if UnitName(casterGUID) == UnitName("player") then
				--casterGUID = UPApiPlayerGUIDPlaceholder
				isMyAura = true
			end
			-- local realCasterGuid = casterGUID
			-- if realCasterGuid == UPApiPlayerGUIDPlaceholder then
				-- local _, xguid = UnitExists("player")
				-- realCasterGuid = xguid
			-- end
			
			-- AOE CASE: Handle AoE (no targetGUID) Refreshes for ALL Casters
			-- if ((not targetGUID) or targetGUID == "") and UPLibAoeAuraNames[spellName] then
			--probably I don't care for separate spell list (it should not have targetGUID only in valid case anyways)
			if ((not targetGUID) or targetGUID == "") and UPLibAuraDurationsByRank[spellName] then
				-- Parse the rank number from the cast event
				local _, _, rankNumberStr = string.find(spellRank or "", "(%d+)")
				local rankNumber = tonumber(rankNumberStr) or 0
				
				local aoeDuration = UPLibAuraDurationsGetAuraDuration(spellName, rankNumber, isMyAura)
				
				if aoeDuration and aoeDuration > 0 then
					local currentTime = GetTime()
					
					if not UPApiPendingAoEAuraRefreshes[casterGUID] then
						UPApiPendingAoEAuraRefreshes[casterGUID] = {}
					end
					
					-- 2. Initialize the spell's table if missing
					if not UPApiPendingAoEAuraRefreshes[casterGUID][spellName] then
						UPApiPendingAoEAuraRefreshes[casterGUID][spellName] = {}
					end
					
					--first find out who is currently affected by this aura
					--if I find a way to check for spell and target distance, then I can do it here
					--Basically here we decide WHO CAN BE AFFECTED BY THIS CAST
					for cachedGuid, cacheData in pairs(UPApiGuidAurasCache) do
						if cacheData[spellName] then
							--maybe put only visible nameplates affected by this aura???
							--now we assume that everyone who has this aura will be affected
							-- Put the cast in the waiting room
							--must allow duplicates somehow? because right now it simply overwrites
							UPApiPendingAoEAuraRefreshes[casterGUID][spellName][cachedGuid] = {
								--targetGUID = cachedGuid, --we don't have target guid here
								time = currentTime,
								isDebuff = nil, --auraType is unreliable here
								isMyAura = isMyAura,
								spellId = spellId
							}
						end
					end
					
					--also apply/refresh immediately if has no target and has this aura on itself? (for seals and alike)
					--refresh immediately
					UPApiCacheInAuraIfValid(casterGUID, spellName, nil, isMyAura, casterGUID)
					--if UPApiUnitHasBuff(casterGUID, spellName) then
						-- local xcache = UPApiGetGuidAurasCache(casterGUID)
						-- local xcurrentTime = GetTime()
						-- local xauraData = xcache[spellName]						
						-- if xauraData then
							-- local xduration = UPLibAuraDurationsGetAuraDuration(spellName, rankNumber, isMyAura) or 10.0
							
							-- -- Reset the timers to simulate the silent server refresh
							-- xauraData.startTime = xcurrentTime
							-- xauraData.expirationTime = xcurrentTime + xduration
						-- end
					--end
				end
			end
			-- AOE CASE END
			
			
			if targetGUID and spellId then
			
				--need to handle JUDGEMENT cast
			
				--local auraType = UPApiGetAuraTypeOnUnit(targetGUID, spellId)
				
				-- if isMyAura then
					-- print("cast event for: "..spellName.." auraType: "..tostring(auraType))
				-- end
			
				-- if auraType == "BUFF" then
					-- UPApiCacheInAuraIfValid(targetGUID, spellName, false)
				-- elseif auraType == "DEBUFF" then
					-- UPApiCacheInAuraIfValid(targetGUID, spellName, true)
				-- end
				
				--auraType is unreliable here
				--if auraType == "BUFF" or auraType == "DEBUFF" then
					if not UPApiPendingAuraRefreshes[casterGUID] then
						UPApiPendingAuraRefreshes[casterGUID] = {}
					end
					
					-- if isMyAura then
						-- print("cast waiting room for: "..spellName.." isMyAura: "..tostring(isMyAura))
					-- end
					
					if spellName == "Judgement" then						
						local expectedJudgement = nil
	
						-- 1. Check if we recorded a Seal fading a split second ago
						local fadedSeal = UPApiLastFadedSeals[casterGUID]
						if fadedSeal then
							expectedJudgement = string.gsub(fadedSeal, "Seal", "Judgement")
						end
						
						-- 2. Fallback: Check if the buff is somehow still active on them
						if not expectedJudgement then
							for _, sealName in ipairs(UPLibPaladinRefreshableSeals) do
								if UPApiUnitHasBuff(casterGUID, sealName) then
									expectedJudgement = string.gsub(sealName, "Seal", "Judgement")
									break
								end
							end
						end
						
						-- 3. Apply the transformation and clear the cache
						if expectedJudgement then
							spellName = expectedJudgement
							--print("Transformed cast to: " .. spellName)
							
							-- Clear it so we don't accidentally reuse it later
							UPApiLastFadedSeals[casterGUID] = nil
						else
							--print("Warning: Could not determine which Judgement was cast by " .. casterGUID)
						end
						
						-- print(""..spellName)
						-- print("Judgement cast by: "..casterGUID)
					end
					
					-- if string.find(spellName, "dodged") then
					-- end
					
					-- Put the cast in the waiting room
					UPApiPendingAuraRefreshes[casterGUID][spellName] = {
						targetGUID = targetGUID,
						time = GetTime(),
						isDebuff = nil, --auraType is unreliable here
						isMyAura = isMyAura,
						spellId = spellId
					}
					
					-- print("put "..spellName.." into UPApiPendingAuraRefreshes")
					
					--also apply/refresh immediately if has no target and has this aura on it? (for buffs and alike)
					--refresh immediately
					-- UPApiCacheInAuraIfValid(realCasterGuid, spellName, nil, isMyAura, realCasterGuid)
					--if UPApiUnitHasBuff(casterGUID, spellName) then
						-- local xcache = UPApiGetGuidAurasCache(targetGUID)
						-- local xcurrentTime = GetTime()
						-- local xauraData = xcache[spellName]						
						-- if xauraData then
							-- local xduration = UPLibAuraDurationsGetAuraDuration(spellName, rankNumber, isMyAura) or 10.0
							
							-- -- Reset the timers to simulate the silent server refresh
							-- xauraData.startTime = xcurrentTime
							-- xauraData.expirationTime = xcurrentTime + xduration
						-- end
					--end
				--end
			end
		elseif eventType == "FAIL" then
			--print(""..spellName.." ".."FAIL")
			-- Clear the cast
			entry.name = nil
			entry.endTime = 0
		end
	end
end)
------------------------------ApiFrame END

