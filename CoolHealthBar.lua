local _G = _G

SLASH_COOLHEALTHBAR1 = '/coolhealthbar'
SLASH_COOLHEALTHBAR2 = '/chb'
SlashCmdList["COOLHEALTHBAR"] = function(msg)
  coolHealthBarOptionsFrame:Show()
end

------------------
-- Helper function to check for Patch 12.0.5+ secret values
local issecretvalue = _G.issecretvalue or function() return false end

-- Midnight / 12.0+ Secret Health Percent Curve
local ScaleTo100Curve = (CurveConstants and CurveConstants.ScaleTo100)
if not ScaleTo100Curve and C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType then
    ScaleTo100Curve = C_CurveUtil.CreateCurve()
    ScaleTo100Curve:SetType(Enum.LuaCurveType.Linear)
    ScaleTo100Curve:AddPoint(0, 0)
    ScaleTo100Curve:AddPoint(1, 100)
end
------------------

local addonIsLoaded = false
local playerEnteredWorld = false
local playerIsInCombatLockdown = false

local currentHp = 0
local maxHp = 0
local currentPower = 0
local maxPower = 0

local anyWatchedBuffFound = false

-- Texture & Spell Name Cache
local CachedTextureToName = {}
local CachedSpellNameToTexture = {}
local CachedSpellDuration = {}

-- Active tracked buff states (survives combat lockdowns)
local ActiveWatchedL1 = nil
local ActiveWatchedR1 = nil

-- Pre-seed common consumable textures
local CommonConsumables = {
    [133939] = "Food",
    [134062] = "Food",
    [132800] = "Drink",
    [132794] = "Drink",
    [132805] = "Drink",
    [132792] = "Drink",
}
for tex, name in pairs(CommonConsumables) do
    CachedTextureToName[tex] = name
    CachedSpellNameToTexture[string.upper(name)] = tex
end

local mainFrame = CreateFrame("Frame", "CoolHealthBarMainFrame", UIParent, "BackdropTemplate")
mainFrame:SetFrameStrata("LOW")
mainFrame.TimeToCheck = 0

local function trimString(s)
  local l = 1
  while strsub(s,l,l) == ' ' do
    l = l+1
  end
  local r = strlen(s)
  while strsub(s,r,r) == ' ' do
    r = r-1
  end
  return strsub(s,l,r)
end

-- Index Spellbook spells so we can identify auras by name & texture
local function UpdateSpellbookCache()
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local numLines = C_SpellBook.GetNumSpellBookSkillLines()
        for i = 1, numLines do
            local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if skillLineInfo then
                local offset = skillLineInfo.itemIndexOffset
                local numEntries = skillLineInfo.numSpellBookItems
                for s = offset + 1, offset + numEntries do
                    local itemInfo = C_SpellBook.GetSpellBookItemInfo(s, Enum.SpellBookSpellBank.Player)
                    if itemInfo and itemInfo.name and itemInfo.iconID then
                        CachedTextureToName[itemInfo.iconID] = itemInfo.name
                        CachedSpellNameToTexture[string.upper(itemInfo.name)] = itemInfo.iconID
                    end
                end
            end
        end
    elseif GetNumSpellTabs then
        local numTabs = GetNumSpellTabs()
        for t = 1, numTabs do
            local _, _, offset, numEntries = GetSpellTabInfo(t)
            for s = offset + 1, offset + numEntries do
                local spellName = GetSpellBookItemName(s, "spell")
                local spellTexture = GetSpellBookItemTexture(s, "spell")
                if spellName and spellTexture then
                    CachedTextureToName[spellTexture] = spellName
                    CachedSpellNameToTexture[string.upper(spellName)] = spellTexture
                end
            end
        end
    end
end

-- Secret-Safe Pattern Matcher
local function MatchesWatchPattern(buffName, buffTexture, watchList, useExact)
    if not watchList or #watchList == 0 then return false end

    -- 1. Direct name match (when non-secret)
    if buffName and buffName ~= "Unknown" and not issecretvalue(buffName) then
        local upperName = string.upper(buffName)
        for _, pattern in ipairs(watchList) do
            local upperPattern = string.upper(pattern)
            if useExact then
                if upperName == upperPattern then return true end
            else
                if string.find(upperName, upperPattern, 1, true) then return true end
            end
        end
    end

    -- 2. Resolve via non-secret texture lookup
    if buffTexture and not issecretvalue(buffTexture) then
        if CachedTextureToName[buffTexture] then
            local cachedName = string.upper(CachedTextureToName[buffTexture])
            for _, pattern in ipairs(watchList) do
                local upperPattern = string.upper(pattern)
                if useExact then
                    if cachedName == upperPattern then return true end
                else
                    if string.find(cachedName, upperPattern, 1, true) then return true end
                end
            end
        end

        for _, pattern in ipairs(watchList) do
            local upperPattern = string.upper(pattern)
            for spellName, texture in pairs(CachedSpellNameToTexture) do
                if (useExact and spellName == upperPattern) or (not useExact and string.find(spellName, upperPattern, 1, true)) then
                    if texture == buffTexture then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local buffWatchL1Names = {}
local buffWatchR1Names = {}

-- Update individual buff slot display
local function UpdateBuffSlot(slot, aura)
    if not aura or not aura.icon then
        slot:Hide()
        return
    end

    slot.icon:SetTexture(aura.icon)
    
    if slot.cooldown then
        if aura.startTime and aura.duration and aura.duration > 0 then
            slot.cooldown:SetCooldown(aura.startTime, aura.duration)
            slot.cooldown:Show()
        else
            slot.cooldown:Hide()
        end
    end
    
    if aura.durationText and aura.durationText ~= "" then
        slot.textDuration:SetFormattedText("%s", aura.durationText)
    else
        slot.textDuration:SetText("")
    end

    if aura.countText and aura.countText ~= "" then
        slot.textCount:SetFormattedText("%s", aura.countText)
    else
        slot.textCount:SetText("")
    end
    
    slot:Show()
end

-- Process live spellcasts (catches Seal swaps and Holy Shield in combat)
local function OnSpellCastSucceeded(spellIdentifier)
    if not spellIdentifier then return end
    
    local spellName, spellTexture
    if type(spellIdentifier) == "number" then
        local sInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellIdentifier)
        spellName = sInfo and sInfo.name or (GetSpellInfo and GetSpellInfo(spellIdentifier))
        spellTexture = sInfo and sInfo.iconID or (GetSpellTexture and GetSpellTexture(spellIdentifier))
    else
        spellName = tostring(spellIdentifier)
        spellTexture = GetSpellTexture and GetSpellTexture(spellName)
    end
    
    if not spellName then return end
    local upperSpellName = string.upper(spellName)
    
    -- -- Judgement releases/consumes your active Seal
    -- if string.find(upperSpellName, "JUDGEMENT") or string.find(upperSpellName, "JUDGMENT") then
        -- if ActiveWatchedL1 and ActiveWatchedL1.isSeal then
            -- ActiveWatchedL1 = nil
            -- mainFrame.buffWatchL1:Hide()
        -- end
        -- return
    -- end
    
    -- Check if the cast spell matches Left 1 (e.g. Seal of Command / Righteousness)
    if MatchesWatchPattern(spellName, spellTexture, buffWatchL1Names, CoolHealthBarSettings.useExactNamingL1) then
        local isSeal = (string.find(upperSpellName, "SEAL OF") ~= nil)
        local dur = CachedSpellDuration[upperSpellName] or (isSeal and 30) or 30
        ActiveWatchedL1 = {
            name = spellName,
            icon = spellTexture,
            spellId = spellIdentifier,
            startTime = GetTime(),
            duration = dur,
            isSeal = isSeal,
        }
        UpdateBuffSlot(mainFrame.buffWatchL1, ActiveWatchedL1)
        anyWatchedBuffFound = true
    end
    
    -- Check if the cast spell matches Right 1 (e.g. Holy Shield)
    if MatchesWatchPattern(spellName, spellTexture, buffWatchR1Names, CoolHealthBarSettings.useExactNamingR1) then
        local dur = CachedSpellDuration[upperSpellName] or (string.find(upperSpellName, "HOLY SHIELD") and 10) or 10
        ActiveWatchedR1 = {
            name = spellName,
            icon = spellTexture,
            spellId = spellIdentifier,
            startTime = GetTime(),
            duration = dur,
        }
        UpdateBuffSlot(mainFrame.buffWatchR1, ActiveWatchedR1)
        anyWatchedBuffFound = true
    end
end

-- Periodic Scanner
mainFrame:SetScript("OnUpdate", function(self, elapsed)
    mainFrame.TimeToCheck = mainFrame.TimeToCheck - elapsed
    if mainFrame.TimeToCheck > 0 then return end
    mainFrame.TimeToCheck = 0.05
	
	anyWatchedBuffFound = false
	local buffL1Found = false
	local buffR1Found = false
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
	
    -- === 1. Out of Combat: Scan C_UnitAuras and seed active states ===
    if not inCombat and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for _, filter in ipairs({"HELPFUL", "HARMFUL"}) do
            for i = 1, 40 do
                local success, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
                if success and data and data.icon and data.name and not issecretvalue(data.name) then
                    CachedTextureToName[data.icon] = data.name
                    CachedSpellNameToTexture[string.upper(data.name)] = data.icon
                    
                    local dur = data.duration or 0
                    if dur > 0 and not issecretvalue(dur) then
                        CachedSpellDuration[string.upper(data.name)] = dur
                    end

                    local timeLeft = 0
                    if data.expirationTime and not issecretvalue(data.expirationTime) and data.expirationTime > 0 then
                        timeLeft = data.expirationTime - GetTime()
                        if timeLeft < 0 then timeLeft = 0 end
                    end

                    -- Check L1 match
                    if not buffL1Found and MatchesWatchPattern(data.name, data.icon, buffWatchL1Names, CoolHealthBarSettings.useExactNamingL1) then
                        local isSeal = (string.find(string.upper(data.name), "SEAL OF") ~= nil)
                        ActiveWatchedL1 = {
                            name = data.name,
                            icon = data.icon,
                            spellId = data.spellId,
                            startTime = GetTime() - (dur - timeLeft),
                            duration = dur > 0 and dur or 30,
                            durationText = (timeLeft > 0) and tostring(math.floor(timeLeft)) or "",
                            countText = (data.applications and data.applications > 1) and tostring(data.applications) or "",
                            isSeal = isSeal,
                        }
                        buffL1Found = true
                    end

                    -- Check R1 match
                    if not buffR1Found and MatchesWatchPattern(data.name, data.icon, buffWatchR1Names, CoolHealthBarSettings.useExactNamingR1) then
                        ActiveWatchedR1 = {
                            name = data.name,
                            icon = data.icon,
                            spellId = data.spellId,
                            startTime = GetTime() - (dur - timeLeft),
                            duration = dur > 0 and dur or 10,
                            durationText = (timeLeft > 0) and tostring(math.floor(timeLeft)) or "",
                            countText = (data.applications and data.applications > 1) and tostring(data.applications) or "",
                        }
                        buffR1Found = true
                    end
                else
                    break
                end
            end
        end
    end

    -- === 2. Manage L1 State & Timers ===
    if ActiveWatchedL1 then
        if ActiveWatchedL1.duration and ActiveWatchedL1.duration > 0 and ActiveWatchedL1.startTime then
            local rem = ActiveWatchedL1.duration - (GetTime() - ActiveWatchedL1.startTime)
            if rem <= 0 then
                ActiveWatchedL1 = nil
                mainFrame.buffWatchL1:Hide()
            else
                ActiveWatchedL1.durationText = tostring(math.floor(rem))
                UpdateBuffSlot(mainFrame.buffWatchL1, ActiveWatchedL1)
                buffL1Found = true
                anyWatchedBuffFound = true
            end
        else
            UpdateBuffSlot(mainFrame.buffWatchL1, ActiveWatchedL1)
            buffL1Found = true
            anyWatchedBuffFound = true
        end
    else
        mainFrame.buffWatchL1:Hide()
    end

    -- === 3. Manage R1 State & Timers ===
    if ActiveWatchedR1 then
        if ActiveWatchedR1.duration and ActiveWatchedR1.duration > 0 and ActiveWatchedR1.startTime then
            local rem = ActiveWatchedR1.duration - (GetTime() - ActiveWatchedR1.startTime)
            if rem <= 0 then
                ActiveWatchedR1 = nil
                mainFrame.buffWatchR1:Hide()
            else
                ActiveWatchedR1.durationText = tostring(math.floor(rem))
                UpdateBuffSlot(mainFrame.buffWatchR1, ActiveWatchedR1)
                buffR1Found = true
                anyWatchedBuffFound = true
            end
        else
            UpdateBuffSlot(mainFrame.buffWatchR1, ActiveWatchedR1)
            buffR1Found = true
            anyWatchedBuffFound = true
        end
    else
        mainFrame.buffWatchR1:Hide()
    end
end)

mainFrame:SetScript("OnEvent", function(self, event, ...)
	local arg1 = ...

	if event == "ADDON_LOADED" and arg1 == "CoolHealthBar" then
		mainFrame:UnregisterEvent("ADDON_LOADED")
		
	elseif event == "PLAYER_ENTERING_WORLD" then
		if not addonIsLoaded then
			addonIsLoaded = true
			CoolHealthBar_OnLoad()
		end
		UpdateSpellbookCache()
		UpdateHealth()
		UpdatePower()
		
	elseif event == "SPELLS_CHANGED" then
		UpdateSpellbookCache()
        
    -- Instantly catches live seal swaps and buff casts in combat!
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
        local _, castGUID, spellID = ...
        OnSpellCastSucceeded(spellID or castGUID)
        
	elseif (event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH") and arg1 == "player" then
		UpdateHealth()
	elseif (event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER") and arg1 == "player" then
		UpdatePower()
	elseif event == "PLAYER_REGEN_DISABLED" then
		playerIsInCombatLockdown = true
		ChangeHealthBarVisibility()
	elseif event == "PLAYER_REGEN_ENABLED" then
		playerIsInCombatLockdown = false
		ChangeHealthBarVisibility()
	end
end)

mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("ADDON_LOADED")
mainFrame:RegisterEvent("SPELLS_CHANGED")
mainFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

local barAlpha = 1
local statusBarTexture = "Interface\\AddOns\\CoolHealthBar\\img\\statusbar\\XPerl_StatusBar7"

function UpdateHealth()
	currentHp = UnitHealth("player")
	maxHp = UnitHealthMax("player")
	
	mainFrame.health:SetMinMaxValues(0, maxHp)
	mainFrame.health:SetValue(currentHp)
	
	-- 1. NON-SECRET VALUES
	if not issecretvalue(currentHp) and not issecretvalue(maxHp) then
		if maxHp <= 0 then maxHp = 1 end
		local healthPercent = math.floor((currentHp / maxHp) * 100)
		
		if healthPercent <= 30 then
			mainFrame.health:SetStatusBarColor(1, 0, 0, barAlpha)
		elseif healthPercent <= 60 then
			mainFrame.health:SetStatusBarColor(1, 1, 0, barAlpha)
		else
			mainFrame.health:SetStatusBarColor(0, 1, 0, barAlpha)
		end
		
		mainFrame.health.text:SetFormattedText("%d / %d (%d%%)", currentHp, maxHp, healthPercent)
	-- 2. SECRET VALUES (Combat)
	else
		mainFrame.health:SetStatusBarColor(0, 1, 0, barAlpha)
		
		local curStr = currentHp
		local maxStr = maxHp
		
		if UnitHealthPercent then
			local curve = CurveConstants and CurveConstants.ScaleTo100 or ScaleTo100Curve
			local pct = curve and UnitHealthPercent("player", true, curve) or UnitHealthPercent("player")
			mainFrame.health.text:SetFormattedText("%s / %s (%.0f%%)", curStr, maxStr, pct)
		else
			mainFrame.health.text:SetFormattedText("%s / %s", curStr, maxStr)
		end
	end
	
	ChangeHealthBarVisibility()
end

function UpdatePower()
	currentPower = UnitPower("player")
	maxPower = UnitPowerMax("player")
	
	mainFrame.power:SetMinMaxValues(0, maxPower)
	mainFrame.power:SetValue(currentPower)
	
	local powerType = UnitPowerType("player")
	if powerType == 0 then
		mainFrame.power:SetStatusBarColor(0, 0, 1, barAlpha)
	elseif powerType == 1 then
		mainFrame.power:SetStatusBarColor(1, 0, 0, barAlpha)
	else
		mainFrame.power:SetStatusBarColor(1, 1, 0, barAlpha)
	end
	
	-- 1. NON-SECRET VALUES (Out of combat)
	if not issecretvalue(currentPower) and not issecretvalue(maxPower) then
		if maxPower <= 0 then maxPower = 1 end
		local powerPercent = math.floor((currentPower / maxPower) * 100)
		mainFrame.power.text:SetFormattedText("%d / %d (%d%%)", currentPower, maxPower, powerPercent)
	-- 2. SECRET VALUES (Combat / In-dungeon)
	else
		local curPStr = currentPower
		local maxPStr = maxPower
		
		local showedPct = false
		if UnitPowerPercent then
			local curve = CurveConstants and CurveConstants.ScaleTo100 or ScaleTo100Curve
			-- Signature: UnitPowerPercent(unit, powerType, unmodified, curve)
			local ok, pct = pcall(function()
				return UnitPowerPercent("player", powerType, false, curve)
			end)
			if not ok or not pct then
				ok, pct = pcall(function()
					return UnitPowerPercent("player", nil, false, curve)
				end)
			end
			if not ok or not pct then
				ok, pct = pcall(function()
					return UnitPowerPercent("player")
				end)
			end
			
			if ok and pct then
				mainFrame.power.text:SetFormattedText("%s / %s (%.0f%%)", curPStr, maxPStr, pct)
				showedPct = true
			end
		end

		if not showedPct then
			mainFrame.power.text:SetFormattedText("%s / %s", curPStr, maxPStr)
		end
	end
	
	ChangeHealthBarVisibility()
end

function ChangeHealthBarVisibility()
	local shouldShow = true
	
	local function IsHpNotFull()
		if issecretvalue(currentHp) or issecretvalue(maxHp) then return false end
		return currentHp < maxHp
	end
	
	local function IsPowerNotFull(pType)
		if issecretvalue(currentPower) or issecretvalue(maxPower) then return false end
		if pType == 1 then 
			return currentPower > 0
		else
			return currentPower < maxPower
		end
	end

	if CoolHealthBarSettings.alwaysShowOutOfCombat then
		shouldShow = true
	elseif CoolHealthBarSettings.showOutOfCombatWhenNotFull then
		local powerType = UnitPowerType("player")
		local inCombat = UnitAffectingCombat("player") or playerIsInCombatLockdown
		
		if inCombat or IsHpNotFull() or IsPowerNotFull(powerType) or anyWatchedBuffFound then
			shouldShow = true
		else
			shouldShow = false
		end
	else
		if (UnitAffectingCombat("player") or playerIsInCombatLockdown) then
			shouldShow = true
		else
			shouldShow = false
		end
	end
	
	if UnitIsDeadOrGhost("player") then
		shouldShow = false
	end
	
	if shouldShow then
		mainFrame:Show()
	else
		mainFrame:Hide()
	end
end

function CoolHealthBar_OnLoad()
	initSettings()
	
	print(string.format("%s by Redbu11 is loaded successfully\nThank you for using my addon", "CoolHealthBar"))

	mainFrame:RegisterEvent("UNIT_HEALTH")
	mainFrame:RegisterEvent("UNIT_MAXHEALTH")
	mainFrame:RegisterEvent("UNIT_POWER_UPDATE")
	mainFrame:RegisterEvent("UNIT_MAXPOWER")
	mainFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	mainFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	
	mainFrame:SetWidth(math.max(1, CoolHealthBarSettings.barsWidth+8))
	mainFrame:SetHeight(math.max(1, CoolHealthBarSettings.healthBarHeight+CoolHealthBarSettings.powerBarHeight+8))
	mainFrame:SetPoint("CENTER", UIParent, "CENTER", CoolHealthBarSettings.offsetX, CoolHealthBarSettings.offsetY)
	
	mainFrame:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	mainFrame:SetBackdropColor(0,0,0,.5)
	
	mainFrame.health = CreateFrame("StatusBar", nil, mainFrame, "BackdropTemplate")
	mainFrame.health:SetFrameLevel(1)
	mainFrame.health:SetOrientation("HORIZONTAL")
	mainFrame.health:SetStatusBarTexture(statusBarTexture)
	mainFrame.health:SetStatusBarColor(0, 1, 0, barAlpha)
	mainFrame.health:SetPoint("TOP", mainFrame, "TOP", 0, -4)
	mainFrame.health:SetWidth(math.max(1, CoolHealthBarSettings.barsWidth))
	mainFrame.health:SetHeight(math.max(1, CoolHealthBarSettings.healthBarHeight))
	mainFrame.health:SetMinMaxValues(0, UnitHealthMax("player"))
	mainFrame.health:SetValue(UnitHealth("player"))
	mainFrame.health.text = mainFrame.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mainFrame.health.text:SetPoint("RIGHT", mainFrame.health, "RIGHT", -2, -8)
	mainFrame.health.text:SetTextColor(1,1,1,barAlpha)
	mainFrame.health.text:SetFont("Interface\\AddOns\\CoolHealthBar\\fonts\\francois.ttf", 12, "OUTLINE")
	mainFrame.health.text:SetJustifyH("RIGHT")
	mainFrame.health.text:SetText("health")
	
	mainFrame.health:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		edgeSize = 4,
		insets = { left = 0, right = 0, top = 0, bottom = 0 },
	})
	mainFrame.health:SetBackdropColor(0,0,0,.5)
	mainFrame.health:Show()
	
	mainFrame.power = CreateFrame("StatusBar", nil, mainFrame, "BackdropTemplate")
	mainFrame.power:SetFrameLevel(1)
	mainFrame.power:SetOrientation("HORIZONTAL")
	mainFrame.power:SetStatusBarTexture(statusBarTexture)
	mainFrame.power:SetStatusBarColor(0, 0, 1, barAlpha)
	mainFrame.power:SetPoint("TOP", mainFrame.health, "BOTTOM", 0, 0)
	mainFrame.power:SetWidth(math.max(1, CoolHealthBarSettings.barsWidth))
	mainFrame.power:SetHeight(math.max(1, CoolHealthBarSettings.powerBarHeight))
	mainFrame.power:SetMinMaxValues(0, UnitPowerMax("player"))
	mainFrame.power:SetValue(UnitPower("player"))
	mainFrame.power.text = mainFrame.power:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mainFrame.power.text:SetPoint("RIGHT", mainFrame.power, "RIGHT", -2, -8)
	mainFrame.power.text:SetTextColor(1,1,1,barAlpha)
	mainFrame.power.text:SetFont("Interface\\AddOns\\CoolHealthBar\\fonts\\francois.ttf", 12, "OUTLINE")
	mainFrame.power.text:SetJustifyH("RIGHT")
	mainFrame.power.text:SetText("power")
	
	mainFrame.power:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		edgeSize = 4,
		insets = { left = 0, right = 0, top = 0, bottom = 0 },
	})
	mainFrame.power:SetBackdropColor(0,0,0,.5)
	mainFrame.power:Show()
	
	local borderImageSize = 80
	
	mainFrame.borderImageL = CreateFrame("Frame", nil, mainFrame)
	mainFrame.borderImageL:SetFrameLevel(0)
	mainFrame.borderImageL:SetPoint("RIGHT", mainFrame, "LEFT", 3, 0)
	mainFrame.borderImageL:SetHeight(borderImageSize)
	mainFrame.borderImageL:SetWidth(borderImageSize)
	mainFrame.borderImageL.icon = mainFrame.borderImageL:CreateTexture(nil, "BORDER")
	mainFrame.borderImageL.icon:SetTexCoord(1, 0, 0, 1)
	mainFrame.borderImageL.icon:SetVertexColor(0.7, 0.7, 0.7, 1)
	mainFrame.borderImageL.icon:SetAllPoints()
	mainFrame.borderImageL.icon:SetTexture("Interface\\AddOns\\CoolHealthBar\\img\\sword_256")
	mainFrame.borderImageL:Show()

	mainFrame.borderImageR = CreateFrame("Frame", nil, mainFrame)
	mainFrame.borderImageR:SetFrameLevel(0)
	mainFrame.borderImageR:SetPoint("LEFT", mainFrame, "RIGHT", -3, 0)
	mainFrame.borderImageR:SetHeight(borderImageSize)
	mainFrame.borderImageR:SetWidth(borderImageSize)
	mainFrame.borderImageR.icon = mainFrame.borderImageR:CreateTexture(nil, "BORDER")
	mainFrame.borderImageR.icon:SetVertexColor(0.7, 0.7, 0.7, 1)
	mainFrame.borderImageR.icon:SetAllPoints()
	mainFrame.borderImageR.icon:SetTexture("Interface\\AddOns\\CoolHealthBar\\img\\sword_256")
	mainFrame.borderImageR:Show()
	
	-- BuffWatch L1
	mainFrame.buffWatchL1 = CreateFrame("Frame", nil, mainFrame)
	mainFrame.buffWatchL1:SetPoint("BOTTOMLEFT", mainFrame.health, "TOPLEFT", 0, 2)
	mainFrame.buffWatchL1:SetHeight(math.max(1, CoolHealthBarSettings.buffWatchSize))
	mainFrame.buffWatchL1:SetWidth(math.max(1, CoolHealthBarSettings.buffWatchSize))
	mainFrame.buffWatchL1.icon = mainFrame.buffWatchL1:CreateTexture(nil, "BACKGROUND")
	mainFrame.buffWatchL1.icon:SetTexture("Interface\\Icons\\Spell_Holy_AuraOfLight")
	mainFrame.buffWatchL1.icon:SetAllPoints()
	
	mainFrame.buffWatchL1.cooldown = CreateFrame("Cooldown", nil, mainFrame.buffWatchL1, "CooldownFrameTemplate")
	mainFrame.buffWatchL1.cooldown:SetAllPoints()
	mainFrame.buffWatchL1.cooldown:SetReverse(true)
	mainFrame.buffWatchL1.cooldown:SetHideCountdownNumbers(true)
	
	mainFrame.buffWatchL1.textDuration = mainFrame.buffWatchL1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mainFrame.buffWatchL1.textDuration:SetPoint("CENTER", mainFrame.buffWatchL1, "CENTER", 0, 0)
	mainFrame.buffWatchL1.textDuration:SetTextColor(1,1,1,barAlpha)
	mainFrame.buffWatchL1.textDuration:SetFont("Fonts\\FRIZQT__.TTF", math.max(1, CoolHealthBarSettings.buffWatchSize/2), "OUTLINE")
	mainFrame.buffWatchL1.textDuration:SetJustifyH("CENTER")
	
	mainFrame.buffWatchL1.textCount = mainFrame.buffWatchL1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mainFrame.buffWatchL1.textCount:SetPoint("BOTTOMRIGHT", mainFrame.buffWatchL1, "BOTTOMRIGHT", -math.max(0.1, CoolHealthBarSettings.buffWatchSize/20), math.max(0.1, CoolHealthBarSettings.buffWatchSize/10))
	mainFrame.buffWatchL1.textCount:SetTextColor(1,1,1,barAlpha)
	mainFrame.buffWatchL1.textCount:SetFont("Fonts\\FRIZQT__.TTF", math.max(1, CoolHealthBarSettings.buffWatchSize/4), "OUTLINE")
	mainFrame.buffWatchL1.textCount:SetJustifyH("RIGHT")
	mainFrame.buffWatchL1:Show()
	
	-- BuffWatch R1
	mainFrame.buffWatchR1 = CreateFrame("Frame", nil, mainFrame)
	mainFrame.buffWatchR1:SetPoint("BOTTOMRIGHT", mainFrame.health, "TOPRIGHT", 0, 2)
	mainFrame.buffWatchR1:SetHeight(math.max(1, CoolHealthBarSettings.buffWatchSize))
	mainFrame.buffWatchR1:SetWidth(math.max(1, CoolHealthBarSettings.buffWatchSize))
	mainFrame.buffWatchR1.icon = mainFrame.buffWatchR1:CreateTexture(nil, "BACKGROUND")
	mainFrame.buffWatchR1.icon:SetTexture("Interface\\Icons\\Spell_Holy_AuraOfLight")
	mainFrame.buffWatchR1.icon:SetAllPoints()
	
	mainFrame.buffWatchR1.cooldown = CreateFrame("Cooldown", nil, mainFrame.buffWatchR1, "CooldownFrameTemplate")
	mainFrame.buffWatchR1.cooldown:SetAllPoints()
	mainFrame.buffWatchR1.cooldown:SetReverse(true)
	mainFrame.buffWatchR1.cooldown:SetHideCountdownNumbers(true)
	
	mainFrame.buffWatchR1.textDuration = mainFrame.buffWatchR1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mainFrame.buffWatchR1.textDuration:SetPoint("CENTER", mainFrame.buffWatchR1, "CENTER", 0, 0)
	mainFrame.buffWatchR1.textDuration:SetTextColor(1,1,1,barAlpha)
	mainFrame.buffWatchR1.textDuration:SetFont("Fonts\\FRIZQT__.TTF", math.max(1, CoolHealthBarSettings.buffWatchSize/2), "OUTLINE")
	mainFrame.buffWatchR1.textDuration:SetJustifyH("CENTER")
	
	mainFrame.buffWatchR1.textCount = mainFrame.buffWatchR1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mainFrame.buffWatchR1.textCount:SetPoint("BOTTOMRIGHT", mainFrame.buffWatchR1, "BOTTOMRIGHT", -math.max(0.1, CoolHealthBarSettings.buffWatchSize/20), math.max(0.1, CoolHealthBarSettings.buffWatchSize/10))
	mainFrame.buffWatchR1.textCount:SetTextColor(1,1,1,barAlpha)
	mainFrame.buffWatchR1.textCount:SetFont("Fonts\\FRIZQT__.TTF", math.max(1, CoolHealthBarSettings.buffWatchSize/4), "OUTLINE")
	mainFrame.buffWatchR1.textCount:SetJustifyH("RIGHT")
	mainFrame.buffWatchR1:Show()
	
	applyAllSettings()
end

function loadCoolHealthBarDefaultSettings()
	CoolHealthBarSettings = {
		minimapIconPos = 0,
		showOutOfCombatWhenNotFull=true,
		alwaysShowOutOfCombat=false,
		barsWidth = 400,
		healthBarHeight = 20,
		powerBarHeight = 10,

		offsetY = -327,
		offsetX = 0,
		buffWatchSize = 60,
		buffWatchL1Sequence = "seal of",
		useExactNamingL1 = false,
		buffWatchR1Sequence = "holy shield,drink,food",
		useExactNamingR1 = false
	}
end

function loadCoolHealthBarSettings() 
	if CoolHealthBarSettings == nil then
		loadCoolHealthBarDefaultSettings()
		print("unable to load CoolHealthbar saved data, backing up to defaults")
	else
		if CoolHealthBarSettings.minimapIconPos == nil then
			CoolHealthBarSettings.minimapIconPos=0
		end
		if CoolHealthBarSettings.showOutOfCombatWhenNotFull == nil then
			CoolHealthBarSettings.showOutOfCombatWhenNotFull=true
		end
		if CoolHealthBarSettings.alwaysShowOutOfCombat == nil then
			CoolHealthBarSettings.alwaysShowOutOfCombat=false
		end
		if CoolHealthBarSettings.barsWidth == nil then
			CoolHealthBarSettings.barsWidth=400
		end
		if CoolHealthBarSettings.healthBarHeight == nil then
			CoolHealthBarSettings.healthBarHeight=20
		end
		if CoolHealthBarSettings.powerBarHeight == nil then
			CoolHealthBarSettings.powerBarHeight=10
		end
		if CoolHealthBarSettings.offsetY == nil then
			CoolHealthBarSettings.offsetY=-327
		end
		if CoolHealthBarSettings.offsetX == nil then
			CoolHealthBarSettings.offsetX=0
		end
		if CoolHealthBarSettings.buffWatchSize == nil then
			CoolHealthBarSettings.buffWatchSize=60
		end
		if CoolHealthBarSettings.buffWatchL1Sequence == nil then
			CoolHealthBarSettings.buffWatchL1Sequence="seal of"
		end
		if CoolHealthBarSettings.useExactNamingL1 == nil then
			CoolHealthBarSettings.useExactNamingL1=false
		end
		if CoolHealthBarSettings.buffWatchR1Sequence == nil then
			CoolHealthBarSettings.buffWatchR1Sequence="holy shield,drink,food"
		end
		if CoolHealthBarSettings.useExactNamingR1 == nil then
			CoolHealthBarSettings.useExactNamingR1=false
		end
		print("CoolHealthBar saved data loaded")
	end
end

function applyAllSettings()
	ChangeHealthBarVisibility()
	
	mainFrame:SetPoint("CENTER", UIParent, "CENTER", CoolHealthBarSettings.offsetX, CoolHealthBarSettings.offsetY)
	
	mainFrame:SetWidth(math.max(1, CoolHealthBarSettings.barsWidth+8))
	mainFrame:SetHeight(math.max(1, CoolHealthBarSettings.healthBarHeight+CoolHealthBarSettings.powerBarHeight+8))
	
	mainFrame.health:SetWidth(math.max(1, CoolHealthBarSettings.barsWidth))
	mainFrame.health:SetHeight(math.max(1, CoolHealthBarSettings.healthBarHeight))
	
	mainFrame.power:SetWidth(math.max(1, CoolHealthBarSettings.barsWidth))
	mainFrame.power:SetHeight(math.max(1, CoolHealthBarSettings.powerBarHeight))
	
	mainFrame.buffWatchL1:SetHeight(math.max(1, CoolHealthBarSettings.buffWatchSize))
	mainFrame.buffWatchL1:SetWidth(math.max(1, CoolHealthBarSettings.buffWatchSize))
	mainFrame.buffWatchL1.textDuration:SetFont("Fonts\\FRIZQT__.TTF", math.max(1, CoolHealthBarSettings.buffWatchSize/2), "OUTLINE")
	mainFrame.buffWatchL1.textCount:SetFont("Fonts\\FRIZQT__.TTF", math.max(1, CoolHealthBarSettings.buffWatchSize/4), "OUTLINE")
	mainFrame.buffWatchL1.textCount:SetPoint("BOTTOMRIGHT", mainFrame.buffWatchL1, "BOTTOMRIGHT", -math.max(0.1, CoolHealthBarSettings.buffWatchSize/20), math.max(0.1, CoolHealthBarSettings.buffWatchSize/10))
	
	mainFrame.buffWatchR1:SetHeight(math.max(1, CoolHealthBarSettings.buffWatchSize))
	mainFrame.buffWatchR1:SetWidth(math.max(1, CoolHealthBarSettings.buffWatchSize))
	mainFrame.buffWatchR1.textDuration:SetFont("Fonts\\FRIZQT__.TTF", math.max(1, CoolHealthBarSettings.buffWatchSize/2), "OUTLINE")
	mainFrame.buffWatchR1.textCount:SetFont("Fonts\\FRIZQT__.TTF", math.max(1, CoolHealthBarSettings.buffWatchSize/4), "OUTLINE")
	mainFrame.buffWatchR1.textCount:SetPoint("BOTTOMRIGHT", mainFrame.buffWatchR1, "BOTTOMRIGHT", -math.max(0.1, CoolHealthBarSettings.buffWatchSize/20), math.max(0.1, CoolHealthBarSettings.buffWatchSize/10))
	
	buffWatchL1Names = {}
	for word in string.gmatch(CoolHealthBarSettings.buffWatchL1Sequence, '([^,]+)') do
		table.insert(buffWatchL1Names, trimString(word))
	end
	
	buffWatchR1Names = {}
	for word in string.gmatch(CoolHealthBarSettings.buffWatchR1Sequence, '([^,]+)') do
		table.insert(buffWatchR1Names, trimString(word))
	end
	
	UpdateHealth()
	UpdatePower()
end

coolHealthBarOptionsFrame = CreateFrame("Frame", "coolHealthBarOptionsFrame", UIParent, "BackdropTemplate")

function initSettings()
	loadCoolHealthBarSettings()
	
	coolHealthBarOptionsFrame:SetMovable(true)
	coolHealthBarOptionsFrame:EnableMouse(true)
	
	coolHealthBarOptionsFrame:SetScript("OnMouseDown", function(self, button)
	  if button == "LeftButton" and not coolHealthBarOptionsFrame.isMoving then
	   coolHealthBarOptionsFrame:StartMoving()
	   coolHealthBarOptionsFrame.isMoving = true
	  end
	end)
	coolHealthBarOptionsFrame:SetScript("OnMouseUp", function(self, button)
	  if button == "LeftButton" and coolHealthBarOptionsFrame.isMoving then
	   coolHealthBarOptionsFrame:StopMovingOrSizing()
	   coolHealthBarOptionsFrame.isMoving = false
	  end
	end)
	coolHealthBarOptionsFrame:SetScript("OnHide", function(self)
	  if ( coolHealthBarOptionsFrame.isMoving ) then
	   coolHealthBarOptionsFrame:StopMovingOrSizing()
	   coolHealthBarOptionsFrame.isMoving = false
	  end
	end)
	
	coolHealthBarOptionsFrame:SetWidth(500)
	coolHealthBarOptionsFrame:SetHeight(500)
	coolHealthBarOptionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)	
	
	coolHealthBarOptionsFrame:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	coolHealthBarOptionsFrame:SetBackdropColor(0,0,0,.5)
	
	coolHealthBarOptionsFrame.title = coolHealthBarOptionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	coolHealthBarOptionsFrame.title:SetPoint("TOP", coolHealthBarOptionsFrame, "TOP", 0, -8)
	coolHealthBarOptionsFrame.title:SetTextColor(1,1,1,barAlpha)
	coolHealthBarOptionsFrame.title:SetFont("Interface\\AddOns\\CoolHealthBar\\fonts\\francois.ttf", 12, "OUTLINE")
	coolHealthBarOptionsFrame.title:SetJustifyH("LEFT")
	coolHealthBarOptionsFrame.title:SetText("CoolHealthBar options")
	
	local closeButton = CreateFrame("Button", nil, coolHealthBarOptionsFrame, "UIPanelButtonTemplate")
	closeButton:SetPoint("TOPRIGHT",0,0)
	closeButton:SetWidth(50)
	closeButton:SetHeight(25)
	closeButton:SetText("Close")
	closeButton:SetScript("OnClick", function()
		coolHealthBarOptionsFrame:Hide()
	end)
	
	local setDefaultsButton = CreateFrame("Button", nil, coolHealthBarOptionsFrame, "UIPanelButtonTemplate")
	setDefaultsButton:SetPoint("BOTTOMLEFT",coolHealthBarOptionsFrame,"BOTTOMLEFT",0,0)
	setDefaultsButton:SetWidth(200)
	setDefaultsButton:SetHeight(40)
	setDefaultsButton:SetText("Set defaults & Reload")
	setDefaultsButton:SetScript("OnClick", function()
		loadCoolHealthBarDefaultSettings()
		ReloadUI()
	end)
	
	local saveButton = CreateFrame("Button", nil, coolHealthBarOptionsFrame, "UIPanelButtonTemplate")
	saveButton:SetPoint("BOTTOMRIGHT",coolHealthBarOptionsFrame,"BOTTOMRIGHT",0,0)
	saveButton:SetWidth(200)
	saveButton:SetHeight(40)
	saveButton:SetText("Save & Reload")
	saveButton:SetScript("OnClick", function()
		ReloadUI()
	end)
	
	coolHealthBarOptionsFrame.scrollFrame = CreateFrame("ScrollFrame", "CoolHealthBarOptionsFrame_ScrollFrame", coolHealthBarOptionsFrame, "UIPanelScrollFrameTemplate")
	coolHealthBarOptionsFrame.scrollFrame:SetHeight(coolHealthBarOptionsFrame:GetHeight())
	coolHealthBarOptionsFrame.scrollBar = _G[coolHealthBarOptionsFrame.scrollFrame:GetName() .. "ScrollBar"]
    coolHealthBarOptionsFrame.scrollFrame:SetWidth(coolHealthBarOptionsFrame:GetWidth())
	coolHealthBarOptionsFrame.scrollFrame:SetPoint("TOPLEFT", 10, -30)
	coolHealthBarOptionsFrame.scrollFrame:SetPoint("BOTTOMRIGHT", -30, 50)

	local scrollChild = CreateFrame("Frame", nil, coolHealthBarOptionsFrame.scrollFrame)
	scrollChild:SetWidth(coolHealthBarOptionsFrame:GetWidth()-18)
	scrollChild:SetHeight(1) 
	coolHealthBarOptionsFrame.scrollFrame:SetScrollChild(scrollChild)
		
	local showOutOfCombatCheckbox = CreateFrame("CheckButton", "showOutOfCombatCheckbox", scrollChild, "UICheckButtonTemplate")
	showOutOfCombatCheckbox:SetPoint("TOPLEFT",8,-24)
	_G[showOutOfCombatCheckbox:GetName() .. 'Text']:SetText("Show out of combat (if HP or power not full)")
	showOutOfCombatCheckbox:SetChecked(CoolHealthBarSettings.showOutOfCombatWhenNotFull)
	showOutOfCombatCheckbox.tooltip = "This is where you place MouseOver Text."
	showOutOfCombatCheckbox:SetScript("OnClick", function()
		CoolHealthBarSettings.showOutOfCombatWhenNotFull=not CoolHealthBarSettings.showOutOfCombatWhenNotFull
		applyAllSettings()
	end)
	
	local alwaysShowOutOfCombatCheckbox = CreateFrame("CheckButton", "alwaysShowOutOfCombatCheckbox", scrollChild, "UICheckButtonTemplate")
	alwaysShowOutOfCombatCheckbox:SetPoint("TOP", showOutOfCombatCheckbox, "BOTTOM", 0, -0)
	_G[alwaysShowOutOfCombatCheckbox:GetName() .. 'Text']:SetText("ALWAYS Show out of combat")
	alwaysShowOutOfCombatCheckbox:SetChecked(CoolHealthBarSettings.alwaysShowOutOfCombat)
	alwaysShowOutOfCombatCheckbox.tooltip = "This is where you place MouseOver Text."
	alwaysShowOutOfCombatCheckbox:SetScript("OnClick", function()
		CoolHealthBarSettings.alwaysShowOutOfCombat=not CoolHealthBarSettings.alwaysShowOutOfCombat
		applyAllSettings()
	end)
	
	local offsetYInputTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	offsetYInputTitle:SetPoint("TOPLEFT", alwaysShowOutOfCombatCheckbox, "BOTTOMLEFT", 4, -8)
	offsetYInputTitle:SetTextColor(0.999,0.819,0,barAlpha)
	offsetYInputTitle:SetJustifyH("LEFT")
	offsetYInputTitle:SetText("Offset Y: ")
	
	local offsetYInput = CreateFrame("EditBox", nil, scrollChild, "BackdropTemplate")
	offsetYInput:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	offsetYInput:SetBackdropColor(0,0,0,.5)
	offsetYInput:SetTextInsets(5, 5, 5, 5)
	offsetYInput:SetTextColor(1,1,1,1)
	offsetYInput:SetJustifyH("CENTER")
	offsetYInput:SetWidth(80)
	offsetYInput:SetHeight(26)
	offsetYInput:SetPoint("LEFT", offsetYInputTitle, "RIGHT", 0, 0)
	offsetYInput:SetFontObject("GameFontNormal")
	offsetYInput:SetAutoFocus(false)
	offsetYInput:SetText(""..CoolHealthBarSettings.offsetY)
	offsetYInput:SetScript("OnTextChanged", function(self)
		local inputValue = tonumber(self:GetText())
		if not inputValue then
			self:SetText(""..CoolHealthBarSettings.offsetY)
		else
			CoolHealthBarSettings.offsetY = inputValue
			self:SetText(CoolHealthBarSettings.offsetY)
			applyAllSettings()
		end
	end)
	
	local offsetXInputTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	offsetXInputTitle:SetPoint("TOPLEFT", offsetYInputTitle, "BOTTOMLEFT", 0, -16)
	offsetXInputTitle:SetTextColor(0.999,0.819,0,barAlpha)
	offsetXInputTitle:SetJustifyH("LEFT")
	offsetXInputTitle:SetText("Offset X: ")
	
	local offsetXInput = CreateFrame("EditBox", nil, scrollChild, "BackdropTemplate")
	offsetXInput:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	offsetXInput:SetBackdropColor(0,0,0,.5)
	offsetXInput:SetTextInsets(5, 5, 5, 5)
	offsetXInput:SetTextColor(1,1,1,1)
	offsetXInput:SetJustifyH("CENTER")
	offsetXInput:SetWidth(80)
	offsetXInput:SetHeight(26)
	offsetXInput:SetPoint("LEFT", offsetXInputTitle, "RIGHT", 0, 0)
	offsetXInput:SetFontObject("GameFontNormal")
	offsetXInput:SetAutoFocus(false)
	offsetXInput:SetText(""..CoolHealthBarSettings.offsetX)
	offsetXInput:SetScript("OnTextChanged", function(self)
		local inputValue = tonumber(self:GetText())
		if not inputValue then
			self:SetText(""..CoolHealthBarSettings.offsetX)
		else
			CoolHealthBarSettings.offsetX = inputValue
			self:SetText(CoolHealthBarSettings.offsetX)
			applyAllSettings()
		end
	end)
	
	local barWidthInputTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	barWidthInputTitle:SetPoint("TOPLEFT", offsetXInputTitle, "BOTTOMLEFT", 0, -16)
	barWidthInputTitle:SetTextColor(0.999,0.819,0,barAlpha)
	barWidthInputTitle:SetJustifyH("LEFT")
	barWidthInputTitle:SetText("Bar width: ")
	
	local barWidthInput = CreateFrame("EditBox", nil, scrollChild, "BackdropTemplate")
	barWidthInput:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	barWidthInput:SetBackdropColor(0,0,0,.5)
	barWidthInput:SetTextInsets(5, 5, 5, 5)
	barWidthInput:SetTextColor(1,1,1,1)
	barWidthInput:SetJustifyH("CENTER")
	barWidthInput:SetWidth(80)
	barWidthInput:SetHeight(26)
	barWidthInput:SetPoint("LEFT", barWidthInputTitle, "RIGHT", 0, 0)
	barWidthInput:SetFontObject("GameFontNormal")
	barWidthInput:SetAutoFocus(false)
	barWidthInput:SetText(""..CoolHealthBarSettings.barsWidth)
	barWidthInput:SetScript("OnTextChanged", function(self)
		local inputValue = tonumber(self:GetText())
		if not inputValue then
			self:SetText(""..CoolHealthBarSettings.barsWidth)
		else
			CoolHealthBarSettings.barsWidth = inputValue
			self:SetText(CoolHealthBarSettings.barsWidth)
			applyAllSettings()
		end
	end)
	
	local hpBarHeightInputTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	hpBarHeightInputTitle:SetPoint("TOPLEFT", barWidthInputTitle, "BOTTOMLEFT", 0, -16)
	hpBarHeightInputTitle:SetTextColor(0.999,0.819,0,barAlpha)
	hpBarHeightInputTitle:SetJustifyH("LEFT")
	hpBarHeightInputTitle:SetText("HP bar height: ")
	
	local hpBarHeightInput = CreateFrame("EditBox", nil, scrollChild, "BackdropTemplate")
	hpBarHeightInput:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	hpBarHeightInput:SetBackdropColor(0,0,0,.5)
	hpBarHeightInput:SetTextInsets(5, 5, 5, 5)
	hpBarHeightInput:SetTextColor(1,1,1,1)
	hpBarHeightInput:SetJustifyH("CENTER")
	hpBarHeightInput:SetWidth(80)
	hpBarHeightInput:SetHeight(26)
	hpBarHeightInput:SetPoint("LEFT", hpBarHeightInputTitle, "RIGHT", 0, 0)
	hpBarHeightInput:SetFontObject("GameFontNormal")
	hpBarHeightInput:SetAutoFocus(false)
	hpBarHeightInput:SetText(""..CoolHealthBarSettings.healthBarHeight)
	hpBarHeightInput:SetScript("OnTextChanged", function(self)
		local inputValue = tonumber(self:GetText())
		if not inputValue then
			self:SetText(""..CoolHealthBarSettings.healthBarHeight)
		else
			CoolHealthBarSettings.healthBarHeight = inputValue
			self:SetText(CoolHealthBarSettings.healthBarHeight)
			applyAllSettings()
		end
	end)
	
	local powerBarHeightInputTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	powerBarHeightInputTitle:SetPoint("TOPLEFT", hpBarHeightInputTitle, "BOTTOMLEFT", 0, -16)
	powerBarHeightInputTitle:SetTextColor(0.999,0.819,0,barAlpha)
	powerBarHeightInputTitle:SetJustifyH("LEFT")
	powerBarHeightInputTitle:SetText("Power bar height: ")
	
	local powerBarHeightInput = CreateFrame("EditBox", nil, scrollChild, "BackdropTemplate")
	powerBarHeightInput:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	powerBarHeightInput:SetBackdropColor(0,0,0,.5)
	powerBarHeightInput:SetTextInsets(5, 5, 5, 5)
	powerBarHeightInput:SetTextColor(1,1,1,1)
	powerBarHeightInput:SetJustifyH("CENTER")
	powerBarHeightInput:SetWidth(80)
	powerBarHeightInput:SetHeight(26)
	powerBarHeightInput:SetPoint("LEFT", powerBarHeightInputTitle, "RIGHT", 0, 0)
	powerBarHeightInput:SetFontObject("GameFontNormal")
	powerBarHeightInput:SetAutoFocus(false)
	powerBarHeightInput:SetText(""..CoolHealthBarSettings.powerBarHeight)
	powerBarHeightInput:SetScript("OnTextChanged", function(self)
		local inputValue = tonumber(self:GetText())
		if not inputValue then
			self:SetText(""..CoolHealthBarSettings.powerBarHeight)
		else
			CoolHealthBarSettings.powerBarHeight = inputValue
			self:SetText(CoolHealthBarSettings.powerBarHeight)
			applyAllSettings()
		end
	end)
	
	local buffWatchSectionTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	buffWatchSectionTitle:SetPoint("TOPLEFT", powerBarHeightInputTitle, "BOTTOMLEFT", 0, -16)
	buffWatchSectionTitle:SetTextColor(1,1,1,barAlpha)
	buffWatchSectionTitle:SetJustifyH("LEFT")
	buffWatchSectionTitle:SetText("Buff watch")
	
	local buffWatchSizeInputTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	buffWatchSizeInputTitle:SetPoint("TOPLEFT", buffWatchSectionTitle, "BOTTOMLEFT", 0, -16)
	buffWatchSizeInputTitle:SetTextColor(0.999,0.819,0,barAlpha)
	buffWatchSizeInputTitle:SetJustifyH("LEFT")
	buffWatchSizeInputTitle:SetText("Buff watch size: ")
	
	local buffWatchSizeInput = CreateFrame("EditBox", nil, scrollChild, "BackdropTemplate")
	buffWatchSizeInput:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	buffWatchSizeInput:SetBackdropColor(0,0,0,.5)
	buffWatchSizeInput:SetTextInsets(5, 5, 5, 5)
	buffWatchSizeInput:SetTextColor(1,1,1,1)
	buffWatchSizeInput:SetJustifyH("CENTER")
	buffWatchSizeInput:SetWidth(80)
	buffWatchSizeInput:SetHeight(26)
	buffWatchSizeInput:SetPoint("LEFT", buffWatchSizeInputTitle, "RIGHT", 0, 0)
	buffWatchSizeInput:SetFontObject("GameFontNormal")
	buffWatchSizeInput:SetAutoFocus(false)
	buffWatchSizeInput:SetText(""..CoolHealthBarSettings.buffWatchSize)
	buffWatchSizeInput:SetScript("OnTextChanged", function(self)
		local inputValue = tonumber(self:GetText())
		if not inputValue then
			self:SetText(""..CoolHealthBarSettings.buffWatchSize)
		else
			CoolHealthBarSettings.buffWatchSize = inputValue
			self:SetText(CoolHealthBarSettings.buffWatchSize)
			applyAllSettings()
		end
	end)
	
	local buffWatchSectionDescription = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	buffWatchSectionDescription:SetPoint("TOPLEFT", buffWatchSizeInputTitle, "BOTTOMLEFT", 0, -16)
	buffWatchSectionDescription:SetTextColor(1,1,1,barAlpha)
	buffWatchSectionDescription:SetJustifyH("LEFT")
	buffWatchSectionDescription:SetText("Specify buff names in format (case insensitive, separate with comma):")
	
	local buffWatchSectionDescription2 = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	buffWatchSectionDescription2:SetPoint("TOPLEFT", buffWatchSectionDescription, "BOTTOMLEFT", 0, -16)
	buffWatchSectionDescription2:SetTextColor(1,1,1,barAlpha)
	buffWatchSectionDescription2:SetJustifyH("LEFT")
	buffWatchSectionDescription2:SetText("(Leave blank to hide)")
	
	local buffWatchSectionDescription3 = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	buffWatchSectionDescription3:SetPoint("TOPLEFT", buffWatchSectionDescription2, "BOTTOMLEFT", 0, -4)
	buffWatchSectionDescription3:SetTextColor(1,1,1,barAlpha)
	buffWatchSectionDescription3:SetJustifyH("LEFT")
	buffWatchSectionDescription3:SetText("seal of, holy shield")
	
	local useExactNamingL1Checkbox = CreateFrame("CheckButton", "useExactNamingL1Checkbox", scrollChild, "UICheckButtonTemplate")
	useExactNamingL1Checkbox:SetPoint("TOPLEFT", buffWatchSectionDescription3, "BOTTOMLEFT", 0, -16)
	_G[useExactNamingL1Checkbox:GetName() .. 'Text']:SetText("Use exact buff names (For buff watch left 1)")
	useExactNamingL1Checkbox:SetChecked(CoolHealthBarSettings.useExactNamingL1)
	useExactNamingL1Checkbox.tooltip = "Use exact buff names (For buff watch left 1)"
	useExactNamingL1Checkbox:SetScript("OnClick", function()
		CoolHealthBarSettings.useExactNamingL1=not CoolHealthBarSettings.useExactNamingL1
		applyAllSettings()
	end)
	
	local buffWatchL1Title = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	buffWatchL1Title:SetPoint("TOPLEFT", useExactNamingL1Checkbox, "BOTTOMLEFT", 0, -4)
	buffWatchL1Title:SetTextColor(0.999,0.819,0,barAlpha)
	buffWatchL1Title:SetJustifyH("LEFT")
	buffWatchL1Title:SetText("Buff watch (Left 1): ")
	
	local buffWatchL1Input = CreateFrame("EditBox", nil, scrollChild, "BackdropTemplate")
	buffWatchL1Input:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	buffWatchL1Input:SetBackdropColor(0,0,0,.5)
	buffWatchL1Input:SetTextInsets(5, 5, 5, 5)
	buffWatchL1Input:SetTextColor(1,1,1,1)
	buffWatchL1Input:SetJustifyH("LEFT")
	buffWatchL1Input:SetWidth(280)
	buffWatchL1Input:SetHeight(26)
	buffWatchL1Input:SetPoint("LEFT", buffWatchL1Title, "RIGHT", 0, 0)
	buffWatchL1Input:SetFontObject("GameFontNormal")
	buffWatchL1Input:SetAutoFocus(false)
	buffWatchL1Input:SetText(""..CoolHealthBarSettings.buffWatchL1Sequence)
	buffWatchL1Input:SetScript("OnTextChanged", function(self)
		local inputValue = self:GetText()
		if not inputValue then
			self:SetText(""..CoolHealthBarSettings.buffWatchL1Sequence)
		else
			CoolHealthBarSettings.buffWatchL1Sequence = inputValue
			self:SetText(""..CoolHealthBarSettings.buffWatchL1Sequence)
			applyAllSettings()
		end
	end)
	
	local useExactNamingR1Checkbox = CreateFrame("CheckButton", "useExactNamingR1Checkbox", scrollChild, "UICheckButtonTemplate")
	useExactNamingR1Checkbox:SetPoint("TOPLEFT", buffWatchL1Title, "BOTTOMLEFT", 0, -16)
	_G[useExactNamingR1Checkbox:GetName() .. 'Text']:SetText("Use exact buff names (For buff watch right 1)")
	useExactNamingR1Checkbox:SetChecked(CoolHealthBarSettings.useExactNamingR1)
	useExactNamingR1Checkbox.tooltip = "Use exact buff names (For buff watch right 1)"
	useExactNamingR1Checkbox:SetScript("OnClick", function()
		CoolHealthBarSettings.useExactNamingR1=not CoolHealthBarSettings.useExactNamingR1
		applyAllSettings()
	end)
	
	local buffWatchR1Title = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	buffWatchR1Title:SetPoint("TOPLEFT", useExactNamingR1Checkbox, "BOTTOMLEFT", 0, -4)
	buffWatchR1Title:SetTextColor(0.999,0.819,0,barAlpha)
	buffWatchR1Title:SetJustifyH("LEFT")
	buffWatchR1Title:SetText("Buff watch (Right 1): ")
	
	local buffWatchR1Input = CreateFrame("EditBox", nil, scrollChild, "BackdropTemplate")
	buffWatchR1Input:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	buffWatchR1Input:SetBackdropColor(0,0,0,.5)
	buffWatchR1Input:SetTextInsets(5, 5, 5, 5)
	buffWatchR1Input:SetTextColor(1,1,1,1)
	buffWatchR1Input:SetJustifyH("LEFT")
	buffWatchR1Input:SetWidth(280)
	buffWatchR1Input:SetHeight(26)
	buffWatchR1Input:SetPoint("LEFT", buffWatchR1Title, "RIGHT", 0, 0)
	buffWatchR1Input:SetFontObject("GameFontNormal")
	buffWatchR1Input:SetAutoFocus(false)
	buffWatchR1Input:SetText(""..CoolHealthBarSettings.buffWatchR1Sequence)
	buffWatchR1Input:SetScript("OnTextChanged", function(self)
		local inputValue = self:GetText()
		if not inputValue then
			self:SetText(""..CoolHealthBarSettings.buffWatchR1Sequence)
		else
			CoolHealthBarSettings.buffWatchR1Sequence = inputValue
			self:SetText(""..CoolHealthBarSettings.buffWatchR1Sequence)
			applyAllSettings()
		end
	end)
	
	coolHealthBarOptionsFrame:Hide()
end

-------------------------------------------------
-- MINIMAP BUTTON
-------------------------------------------------
local CHBMinimapButton = CreateFrame("Button", "CHBMainMenuBarToggler", Minimap)
CHBMinimapButton:SetSize(31, 31)
CHBMinimapButton:SetFrameLevel(8)
CHBMinimapButton:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
CHBMinimapButton:SetMovable(true)
CHBMinimapButton:EnableMouse(true)

local overlay = CHBMinimapButton:CreateTexture(nil, "OVERLAY")
overlay:SetSize(53, 53)
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
overlay:SetPoint("TOPLEFT")

local icon = CHBMinimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetTexture("Interface\\Icons\\Spell_ChargeNegative")
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
icon:SetPoint("TOPLEFT", 7, -5)
CHBMinimapButton.icon = icon

-- Universal circular positioning around the true center of the Minimap
local function UpdateMinimapButtonPosition(angle)
    local rad = math.rad(angle or 0)
    -- Places the button center directly along the circular border
    local radius = (Minimap:GetWidth() / 2) + 5
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    
    CHBMinimapButton:ClearAllPoints()
    CHBMinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

CHBMinimapButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        coolHealthBarOptionsFrame:SetShown(not coolHealthBarOptionsFrame:IsShown())
    end
end)

CHBMinimapButton:RegisterForDrag("RightButton")
CHBMinimapButton:SetScript("OnDragStart", function(self)
    self:StartMoving()
    self:SetScript("OnUpdate", function()
        local cursorX, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cursorX = cursorX / scale
        cursorY = cursorY / scale

        local miniX, miniY = Minimap:GetCenter()
        if not miniX or not miniY then return end

        -- Calculate true angle relative to the Minimap center
        local angle = math.deg(math.atan2(cursorY - miniY, cursorX - miniX))
        if angle < 0 then
            angle = angle + 360
        end

        CoolHealthBarSettings.minimapIconPos = angle
        UpdateMinimapButtonPosition(angle)
    end)
end)

CHBMinimapButton:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetScript("OnUpdate", nil)
end)

CHBMinimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("CoolHealthBar")
    GameTooltip:AddLine("Left-click to show options\nRight-click and drag to move", 1, 1, 1)
    GameTooltip:Show()
end)

CHBMinimapButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

C_Timer.After(0.5, function()
    local pos = (CoolHealthBarSettings and CoolHealthBarSettings.minimapIconPos) or 220
    UpdateMinimapButtonPosition(pos)
end)