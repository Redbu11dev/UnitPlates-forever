local _G = _G
local addonName = "UnitPlates"

-- Handle modern secret values across all 12.0+ engine variants
local issecretvalue = (C_Secrets and C_Secrets.IsSecretValue)
    or (C_Secret and C_Secret.IsSecret)
    or _G.issecretvalue
    or function(val)
        if val == nil then return false end
        local ok, isSec = pcall(function() return C_Secrets and C_Secrets.IsSecretValue(val) end)
        return ok and isSec
    end

-------------------------------------------------
-- SETTINGS & CONFIGURATION
-------------------------------------------------
UnitPlatesSettings = UnitPlatesSettings or {}

local function LoadDefaultSettings()
    UnitPlatesSettings = {
        minimapIconPos = 0,
        showBuffs = true,
        onlyYourBuffs = false,
        ignoredBuffNames = "",
        showDebuffs = true,
        onlyYourDebuffs = false,
        ignoredDebuffNames = "",
        enableWoWTranslateSupport = true,
        enableChatBubbleHandling = true,
        overlapping = true,
        scale = 1.4,
        aurasInRow = 6,
        aurasInRowTrivial = 4,
        nameplateWidthPercent = 65,
        nameplateWidthPercentTrivial = 45,
        selectionGlowScale = 100,
        selectionGlowAlpha = 50       
    }
end

if next(UnitPlatesSettings) == nil then LoadDefaultSettings() end
if not UnitPlatesSettings.scale then UnitPlatesSettings.scale = 1.4 end
if not UnitPlatesSettings.nameplateWidthPercentTrivial then UnitPlatesSettings.nameplateWidthPercentTrivial = 45 end

local function IsNameIgnored(name, ignoredString)
    if not ignoredString or ignoredString == "" then return false end
    for word in string.gmatch(ignoredString, '([^,]+)') do
        word = word:match("^%s*(.-)%s*$")
        if string.lower(name) == string.lower(word) then return true end
    end
    return false
end

-------------------------------------------------
-- CONSTANTS & ASSETS
-------------------------------------------------
local UPConstants = {
    font = "Interface\\AddOns\\UnitPlates\\fonts\\INTERNATIONAL_FRIZQT__.ttf",
    baseHeight = 14,
}

-- Midnight / 12.0+ Secret Health Percent Curve (scales 0..1 to 0..100 engine-side)
local ScaleTo100Curve = (CurveConstants and CurveConstants.ScaleTo100)
if not ScaleTo100Curve and C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType then
    ScaleTo100Curve = C_CurveUtil.CreateCurve()
    ScaleTo100Curve:SetType(Enum.LuaCurveType.Linear)
    ScaleTo100Curve:AddPoint(0, 0)
    ScaleTo100Curve:AddPoint(1, 100)
end

local function GetFont() return UPConstants.font end

local powerColors = {
    [0] = {0, 0, 0.9, 1}, -- Mana
    [1] = {1, 0, 0, 1},   -- Rage
    [3] = {1, 1, 0, 1},   -- Energy
}

local classCoords = {
    ["WARRIOR"] = {0, 0.25, 0, 0.25}, ["MAGE"] = {0.25, 0.5, 0, 0.25},
    ["ROGUE"] = {0.5, 0.75, 0, 0.25}, ["DRUID"] = {0.75, 1, 0, 0.25},
    ["HUNTER"] = {0, 0.25, 0.25, 0.5}, ["SHAMAN"] = {0.25, 0.5, 0.25, 0.5},
    ["PRIEST"] = {0.5, 0.75, 0.25, 0.5}, ["WARLOCK"] = {0.75, 1, 0.25, 0.5},
    ["PALADIN"] = {0, 0.25, 0.5, 0.75}, ["DEATHKNIGHT"] = {0.25, 0.5, 0.5, 0.75},
}

local ActivePlates = {}

-------------------------------------------------
-- UTILS
-------------------------------------------------

-- Safely tests any value or function return without triggering secret boolean crashes
local function SafeBool(val)
    if val == nil then return false end
    if issecretvalue(val) then return false end
    local ok, isTrue = pcall(function() return val == true end)
    return ok and isTrue or false
end

local function SafeUnitCall(func, ...)
    if not func then return false end
    local ok, res = pcall(func, ...)
    if not ok or res == nil then return false end
    if issecretvalue(res) then return false end
    local okTest, isTrue = pcall(function() return res == true end)
    return okTest and isTrue or false
end

local function SafeUnitTruthy(func, ...)
    if not func then return false end
    local ok, res = pcall(func, ...)
    if not ok or res == nil then return false end
    if issecretvalue(res) then return false end
    local okTest, isTrue = pcall(function() return (res ~= false and res ~= nil) end)
    return okTest and isTrue or false
end

local function IsTrivial(unit)
    if not unit then return false end
    
    local okLevel, level = pcall(UnitLevel, unit)
    local isGray = false
    if okLevel and level and not issecretvalue(level) and level > 0 then
        local color = GetQuestDifficultyColor(level)
        if color and color.r > 0.4 and color.r < 0.6 and color.g > 0.4 and color.g < 0.6 then 
            isGray = true 
        end
    end
    
    local isCritter = false
    local okType, cType = pcall(UnitCreatureType, unit)
    if okType and cType and not issecretvalue(cType) then
        isCritter = (cType == "Critter" or cType == "CRITTER")
    end
    
    local isPet = false
    if UnitIsOtherPlayersPet and SafeUnitCall(UnitIsOtherPlayersPet, unit) then
        isPet = true
    elseif UnitIsBattlePet and SafeUnitCall(UnitIsBattlePet, unit) then
        isPet = true
    end
    
    return isGray or isCritter or isPet
end

-------------------------------------------------
-- UI BUILDERS (WITH BACKDROPS & MASKS)
-------------------------------------------------
local function ApplyMaskedBorders(targetFrame)
    local padding = 2.5
    
    -- Solid Black Background
    targetFrame.bgOffsetFrame = CreateFrame("Frame", nil, targetFrame, "BackdropTemplate")
    targetFrame.bgOffsetFrame:SetFrameLevel(targetFrame:GetFrameLevel() - 1)
    targetFrame.bgOffsetFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground", -- Guaranteed solid texture
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 0, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    targetFrame.bgOffsetFrame:SetBackdropColor(0, 0, 0, 1) -- SOLID BLACK
    targetFrame.bgOffsetFrame:SetBackdropBorderColor(0.1, 0.1, 0.1, 1)
    targetFrame.bgOffsetFrame:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -padding, padding)
    targetFrame.bgOffsetFrame:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", padding, -padding)

    -- Overlay Mask
    targetFrame.overlayMask = CreateFrame("Frame", nil, targetFrame, "BackdropTemplate")
    targetFrame.overlayMask:SetFrameLevel(targetFrame:GetFrameLevel() + 2)
    targetFrame.overlayMask:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, tileSize = 0, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    targetFrame.overlayMask:SetBackdropBorderColor(0, 0, 0, 1)
    targetFrame.overlayMask:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", -padding, padding)
    targetFrame.overlayMask:SetPoint("BOTTOMRIGHT", targetFrame, "BOTTOMRIGHT", padding, -padding)
end

local function CreateAuraIcon(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(16, 16)
    frame.icon = frame:CreateTexture(nil, "BACKGROUND")
    frame.icon:SetAllPoints()
    
    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints()
    frame.cooldown:SetReverse(true)
    frame.cooldown:SetHideCountdownNumbers(true)
    
    -- FIX: Create a dedicated frame ABOVE the cooldown spiral for the texts!
    frame.textFrame = CreateFrame("Frame", nil, frame)
    frame.textFrame:SetAllPoints()
    frame.textFrame:SetFrameLevel(frame.cooldown:GetFrameLevel() + 1)
    
    frame.count = frame.textFrame:CreateFontString(nil, "OVERLAY")
    frame.count:SetPoint("BOTTOMRIGHT", 2, -2)
    
    frame.cdText = frame.textFrame:CreateFontString(nil, "OVERLAY")
    frame.cdText:SetPoint("CENTER", 0, 0)
    
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.nextUpdate = (self.nextUpdate or 0) - elapsed
        if self.nextUpdate > 0 then return end
        self.nextUpdate = 0.1
        
        if self.duration and self.duration > 0 and self.expirationTime and self.expirationTime > 0 then
            local timeLeft = self.expirationTime - GetTime()
            if timeLeft > 0 then
                if timeLeft >= 3600 then
                    self.cdText:SetText(math.floor(timeLeft / 3600) .. "h")
                    self.cdText:SetTextColor(0.53, 0.81, 0.98)
                elseif timeLeft >= 60 then
                    self.cdText:SetText(math.floor(timeLeft / 60) .. "m")
                    self.cdText:SetTextColor(0.53, 0.81, 0.98)
                elseif timeLeft >= 1 then
                    self.cdText:SetText(math.floor(timeLeft))
                    if timeLeft <= 3 then self.cdText:SetTextColor(0.99, 0, 0)
                    elseif timeLeft <= 7 then self.cdText:SetTextColor(0.99, 0.99, 0)
                    else self.cdText:SetTextColor(0.8, 0.8, 1) end
                else
                    self.cdText:SetText(string.format("%.1f", timeLeft):sub(2))
                    self.cdText:SetTextColor(0.99, 0, 0)
                end
            else
                self.cdText:SetText("")
            end
        else
            self.cdText:SetText("")
        end
    end)
    
    frame:Hide()
    return frame
end

local function BuildNameplateUI(plate)
    local f = CreateFrame("Frame", nil, plate)
    f:SetAllPoints()
    f:SetScale(UnitPlatesSettings.scale or 1.4)
    f:SetIgnoreParentAlpha(true) -- Stay 100% visible
    f:EnableMouse(false) -- Allow mouse to pass to Blizzard Nameplate
    
    local width = UPConstants.baseHeight * (UnitPlatesSettings.nameplateWidthPercent / 10)
    local typeIconSize = UPConstants.baseHeight
    
-- Hide Blizzard UI visuals and hijack modern 12.x AurasFrame
    f:SetScript("OnUpdate", function(self)
        if plate.UnitFrame then
            local aurasFrame = plate.UnitFrame.AurasFrame or plate.UnitFrame.BuffFrame
            
            -- 1. Recursively hide all native child frames EXCEPT the AurasFrame
            for _, child in ipairs({plate.UnitFrame:GetChildren()}) do
                if child ~= aurasFrame then
                    child:SetAlpha(0)
                end
            end

            -- 2. Explicitly target known 12.x / Forever frames
            local explicitHide = {
                "healthBar", "HealthBar", "HealthBarsContainer",
                "castBar", "CastBar", "CastBarsContainer",
                "name", "NameText",
                "LevelFrame", "levelText", "LevelText", "PlayerLevelDiffFrame",
                "ClassificationFrame", "RaidTargetFrame", "threatIndicator",
                "SelectionHighlight", "AggroHighlight", "SoftTargetFrame", "WidgetContainer"
            }
            for _, key in ipairs(explicitHide) do
                if plate.UnitFrame[key] then
                    plate.UnitFrame[key]:SetAlpha(0)
                end
            end
            
            -- 3. Hide all direct textures / borders / fontstrings
            for _, region in ipairs({plate.UnitFrame:GetRegions()}) do
                local rType = region:GetObjectType()
                if rType == "Texture" or rType == "FontString" then
                    region:SetAlpha(0)
                end
            end

            -- Helper to style Blizzard icon textures and shrink countdown/stack fonts
            local function FormatAuraButton(btn, size)
                btn:SetAlpha(1)
                if btn:GetScale() ~= self:GetScale() then
                    btn:SetScale(self:GetScale())
                end
                btn:SetSize(size, size)
                
                -- Crop borders off the icon texture
                if btn.Icon then 
                    btn.Icon:SetAllPoints(btn) 
                    btn.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
                if btn.icon then 
                    btn.icon:SetAllPoints(btn)
                    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
                
                -- Hide default Blizzard borders, rings, and round masks
                if btn.Border then btn.Border:SetAlpha(0) end
                if btn.IconBorder then btn.IconBorder:SetAlpha(0) end
                if btn.Ring then btn.Ring:SetAlpha(0) end
                if btn.CircleMask then btn.CircleMask:Hide() end
                
                local cdFontSize = size * 0.45
                local stackFontSize = size * 0.38
                
                -- Direct fontstrings
                for _, r in ipairs({btn:GetRegions()}) do
                    if r:GetObjectType() == "FontString" then
                        r:SetFont(GetFont(), cdFontSize, "OUTLINE")
                    end
                end
                
                -- CountFrame (Stack Count)
                if btn.CountFrame then
                    for _, r in ipairs({btn.CountFrame:GetRegions()}) do
                        if r:GetObjectType() == "FontString" then
                            r:SetFont(GetFont(), stackFontSize, "OUTLINE")
                            r:ClearAllPoints()
                            r:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
                        end
                    end
                end
                
                -- Cooldown Timer (Duration Text)
                if btn.Cooldown then
                    for _, r in ipairs({btn.Cooldown:GetRegions()}) do
                        if r:GetObjectType() == "FontString" then
                            r:SetFont(GetFont(), cdFontSize, "OUTLINE")
                            r:ClearAllPoints()
                            r:SetPoint("CENTER", btn, "CENTER", 0, 0)
                        end
                    end
                    for _, c in ipairs({btn.Cooldown:GetChildren()}) do
                        for _, r in ipairs({c:GetRegions()}) do
                            if r:GetObjectType() == "FontString" then
                                r:SetFont(GetFont(), cdFontSize, "OUTLINE")
                                r:ClearAllPoints()
                                r:SetPoint("CENTER", btn, "CENTER", 0, 0)
                            end
                        end
                    end
                end
            end

            -- 4. Scrape & Separate Auras in Combat
            local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
            if aurasFrame then
                if inCombat then
                    aurasFrame:SetAlpha(1)
                    
                    local unit = self.unit
                    local maxPerRow = (unit and IsTrivial(unit)) and UnitPlatesSettings.aurasInRowTrivial or UnitPlatesSettings.aurasInRow
                    local topIconSize = (self.healthBar:GetWidth() / maxPerRow) - 2
                    local ccIconSize = UPConstants.baseHeight * 1.3 -- Proportional size for CC icons
                    local arrowSize = UPConstants.baseHeight * 1.875

                    local seen = {}

                    -- === TOP ROW: Standard Buffs & Debuffs ===
                    local topIndex = 0
                    local topContainers = {
                        aurasFrame.BuffListFrame,
                        aurasFrame.DebuffListFrame,
                    }
                    for _, container in ipairs(topContainers) do
                        if container then
                            container:SetAlpha(1)
                            for _, child in ipairs({container:GetChildren()}) do
                                if not seen[child] and child:IsShown() and (child.Icon or child.icon or child.Texture) then
                                    seen[child] = true
                                    
                                    child:ClearAllPoints()
                                    local col = topIndex % maxPerRow
                                    local row = math.floor(topIndex / maxPerRow)
                                    local xOffset = col * (topIconSize + 2)
                                    local yOffset = row * (topIconSize + 2)
                                    
                                    -- Sits at the exact Y anchor of your API auras container
                                    child:SetPoint("BOTTOMLEFT", self.auras, "BOTTOMLEFT", xOffset, yOffset)
                                    
                                    FormatAuraButton(child, topIconSize)
                                    topIndex = topIndex + 1
                                end
                            end
                        end
                    end

                    -- === RIGHT SIDE: Crowd Control / Priority Auras ===
                    local rightIndex = 0
                    local rightContainers = {
                        aurasFrame.CrowdControlListFrame,
                        aurasFrame.LossOfControlFrame,
                    }
                    -- Prevent overlapping the target arrow when targeted
                    local rightStartOffset = (self.targetRight and self.targetRight:IsShown()) and (arrowSize + 4) or 6
                    
                    for _, container in ipairs(rightContainers) do
                        if container then
                            container:SetAlpha(1)
                            for _, child in ipairs({container:GetChildren()}) do
                                if not seen[child] and child:IsShown() and (child.Icon or child.icon or child.Texture) then
                                    seen[child] = true
                                    
                                    child:ClearAllPoints()
                                    local xOffset = rightStartOffset + (rightIndex * (ccIconSize + 3))
                                    -- Vertically centered to the right of the healthbar
                                    child:SetPoint("LEFT", self.healthBar, "RIGHT", xOffset, 0)
                                    
                                    FormatAuraButton(child, ccIconSize)
                                    rightIndex = rightIndex + 1
                                end
                            end
                        end
                    end
                else
                    aurasFrame:SetAlpha(0)
                end
            end
        end
        self:SetAlpha(1)
    end)
	
    -- GLOW FRAME (Bottom Layer)
    f.glowFrame = CreateFrame("Frame", nil, f)
    f.glowFrame:SetFrameLevel(1)
    f.glowFrame:SetAllPoints()
    
    local glowScale = UnitPlatesSettings.selectionGlowScale / 100
    local glowAlpha = UnitPlatesSettings.selectionGlowAlpha / 100
    f.selectionGlow = f.glowFrame:CreateTexture(nil, "BACKGROUND")
    f.selectionGlow:SetTexture("Interface\\AddOns\\UnitPlates\\img\\dot")
    f.selectionGlow:SetVertexColor(0.3, 0.7, 1, glowAlpha)
    f.selectionGlow:SetSize((width * 2.6) * glowScale, (UPConstants.baseHeight * 4.5) * glowScale)
    f.selectionGlow:SetPoint("CENTER", -typeIconSize/2, 0)

    -- HEALTH BAR
    f.healthBar = CreateFrame("StatusBar", nil, f)
    f.healthBar:SetFrameLevel(3) -- Above Glow
    f.healthBar:SetSize(width, UPConstants.baseHeight)
    f.healthBar:SetPoint("CENTER", 0, 0)
    f.healthBar:SetStatusBarTexture("Interface\\AddOns\\UnitPlates\\img\\statusbar\\XPerl_StatusBar4")
    f.healthBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", -8)
    ApplyMaskedBorders(f.healthBar)

    -- POWER BAR
    f.powerBar = CreateFrame("StatusBar", nil, f)
    f.powerBar:SetFrameLevel(3)
    f.powerBar:SetSize(width, UPConstants.baseHeight / 2)
    f.powerBar:SetPoint("TOP", f.healthBar, "BOTTOM", 0, 0)
    f.powerBar:SetStatusBarTexture("Interface\\AddOns\\UnitPlates\\img\\statusbar\\XPerl_StatusBar7")
    ApplyMaskedBorders(f.powerBar)

    -- TYPE ICON
    f.typeIcon = CreateFrame("Frame", nil, f)
    f.typeIcon:SetFrameLevel(3)
    f.typeIcon:SetSize(typeIconSize, typeIconSize)
    f.typeIcon:SetPoint("RIGHT", f.healthBar, "LEFT", -1, 0)
    f.typeIcon.icon = f.typeIcon:CreateTexture(nil, "ARTWORK")
    f.typeIcon.icon:SetAllPoints()
    f.typeIcon.icon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\loading.tga")
    ApplyMaskedBorders(f.typeIcon)

    -- TEXT LAYER WRAPPER
    f.textLayerHost = CreateFrame("Frame", nil, f)
    f.textLayerHost:SetFrameLevel(f.healthBar:GetFrameLevel() + 5)
    f.textLayerHost:SetAllPoints()

    f.healthText = f.textLayerHost:CreateFontString(nil, "OVERLAY")
    f.healthText:SetFont(GetFont(), UPConstants.baseHeight * 0.625, "OUTLINE")
    f.healthText:SetPoint("BOTTOMRIGHT", f.healthBar, "BOTTOMRIGHT", -1, -(UPConstants.baseHeight * 0.3))
    
    f.healthPercent = f.textLayerHost:CreateFontString(nil, "OVERLAY")
    f.healthPercent:SetFont(GetFont(), UPConstants.baseHeight * 0.625, "OUTLINE")
    f.healthPercent:SetPoint("CENTER", f.healthBar, "CENTER", 0, 0)

    f.nameText = f.textLayerHost:CreateFontString(nil, "OVERLAY")
    f.nameText:SetFont(GameFontNormal:GetFont(), UPConstants.baseHeight * 0.6875, "OUTLINE")
    f.nameText:SetPoint("BOTTOM", f.healthBar, "TOP", 0, 2)
	
	-- GUILD / NPC OCCUPATION TEXT
    f.guildText = f.textLayerHost:CreateFontString(nil, "OVERLAY")
    f.guildText:SetFont(GameFontNormal:GetFont(), UPConstants.baseHeight * 0.6875, "OUTLINE")
    f.guildText:Hide()

    f.levelText = f.textLayerHost:CreateFontString(nil, "OVERLAY")
    f.levelText:SetFont(GetFont(), UPConstants.baseHeight * 0.625, "OUTLINE")
    f.levelText:SetPoint("BOTTOMLEFT", f.healthBar, "BOTTOMLEFT", 2, -(UPConstants.baseHeight * 0.3))

    f.powerText = f.textLayerHost:CreateFontString(nil, "OVERLAY")
    f.powerText:SetFont(GetFont(), UPConstants.baseHeight * 0.5, "OUTLINE")
    f.powerText:SetPoint("BOTTOMRIGHT", f.powerBar, "BOTTOMRIGHT", -1, -(UPConstants.baseHeight * 0.3))

    -- CAST BAR
    f.castBar = CreateFrame("StatusBar", nil, f, "BackdropTemplate")
    f.castBar:SetSize(width, UPConstants.baseHeight * 0.4)
    f.castBar:SetPoint("TOP", f.powerBar, "BOTTOM", 0, -5)
    f.castBar:SetStatusBarTexture("Interface\\AddOns\\UnitPlates\\img\\statusbar\\XPerl_StatusBar7")
    f.castBar:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = { left = -1, right = -1, top = -1, bottom = -1 }})
    f.castBar:SetBackdropColor(0, 0, 0, 1)
    f.castBar:SetBackdropBorderColor(0, 0, 0, 1)
    
    f.castIcon = f.castBar:CreateTexture(nil, "ARTWORK")
    f.castIcon:SetSize(14, 14)
    f.castIcon:SetPoint("RIGHT", f.castBar, "LEFT", -2, 0)
    
    f.castName = f.castBar:CreateFontString(nil, "OVERLAY")
    f.castName:SetFont(GameFontNormal:GetFont(), UPConstants.baseHeight * 0.6875, "OUTLINE")
    f.castName:SetPoint("TOP", f.castBar, "BOTTOM", 0, -2)
	
	f.castTime = f.castBar:CreateFontString(nil, "OVERLAY")
    f.castTime:SetFont(GetFont(), UPConstants.baseHeight * 0.5, "OUTLINE")
    f.castTime:SetPoint("BOTTOMRIGHT", f.castBar, "BOTTOMRIGHT", -1, -(UPConstants.baseHeight * 0.5 * 0.65))

    -- TARGET ARROWS
    local arrowSize = UPConstants.baseHeight * 1.875
    f.targetLeft = f:CreateTexture(nil, "ARTWORK")
    f.targetLeft:SetTexture("Interface\\AddOns\\UnitPlates\\img\\arrow_left")
    f.targetLeft:SetSize(arrowSize, arrowSize)
    f.targetLeft:SetPoint("LEFT", f.typeIcon, "LEFT", -arrowSize, 0)
    f.targetLeft:SetVertexColor(0.3, 0.7, 1, 1)
    
    f.targetRight = f:CreateTexture(nil, "ARTWORK")
    f.targetRight:SetTexture("Interface\\AddOns\\UnitPlates\\img\\arrow_right")
    f.targetRight:SetSize(arrowSize, arrowSize)
    f.targetRight:SetPoint("RIGHT", f.healthBar, "RIGHT", arrowSize, 0)
    f.targetRight:SetVertexColor(0.3, 0.7, 1, 1)

    -- ELITE / RARE BORDERS
    local rarityW, rarityH = UPConstants.baseHeight * 2.625, UPConstants.baseHeight * 2.75
    local rarityOffset = rarityW * 0.619
    f.rarityIcon = f:CreateTexture(nil, "ARTWORK")
    f.rarityIcon:SetSize(rarityW, rarityH)
    f.rarityIcon:SetPoint("RIGHT", f.typeIcon, "LEFT", rarityOffset, -1)
    f.rarityIcon:SetTexCoord(1, 0, 0, 1)

    f.rarityIconR = f:CreateTexture(nil, "ARTWORK")
    f.rarityIconR:SetSize(rarityW, rarityH)
    f.rarityIconR:SetPoint("LEFT", f.healthBar, "RIGHT", -rarityOffset, -1)

    -- COMBAT / PVP / SHOOTING / PET STATUS ICONS
    f.classIcon = f:CreateTexture(nil, "ARTWORK")
    f.classIcon:SetSize(UPConstants.baseHeight * 1.25, UPConstants.baseHeight * 1.25)
    f.classIcon:SetPoint("RIGHT", f.nameText, "LEFT", -2, 4)
    f.classIcon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")

    f.combatIcon = f:CreateTexture(nil, "OVERLAY")
    f.combatIcon:SetSize(UPConstants.baseHeight * 1.4, UPConstants.baseHeight * 1.4)
    f.combatIcon:SetPoint("LEFT", f.nameText, "RIGHT", 2, 0)
    f.combatIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    f.combatIcon:SetTexCoord(0.5, 1.0, 0.0, 0.5)

    f.pvpIcon = f:CreateTexture(nil, "ARTWORK")
    f.pvpIcon:SetSize(UPConstants.baseHeight * 1.8, UPConstants.baseHeight * 1.8)
    f.pvpIcon:SetPoint("LEFT", f.nameText, "RIGHT", -2, -UPConstants.baseHeight / 4.5)

    f.pvpRankIcon = f:CreateTexture(nil, "ARTWORK")
    f.pvpRankIcon:SetSize(UPConstants.baseHeight * 0.75, UPConstants.baseHeight * 0.75)
    f.pvpRankIcon:SetPoint("LEFT", f.pvpIcon, "RIGHT", 0, 0)

    f.shootingIcon = f:CreateTexture(nil, "OVERLAY")
    f.shootingIcon:SetSize(UPConstants.baseHeight * 0.9, UPConstants.baseHeight * 0.9)
    f.shootingIcon:SetPoint("LEFT", f.healthText, "RIGHT", 0, 0)
    f.shootingIcon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\combat\\arrow_target_1_32")

    f.petHappiness = f:CreateTexture(nil, "OVERLAY")
    f.petHappiness:SetSize(UPConstants.baseHeight * 1.1, UPConstants.baseHeight * 1.1)
    f.petHappiness:SetPoint("LEFT", f.nameText, "RIGHT", 0, 0)
    f.petHappiness:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
	
	-- QUEST ICON
    f.questIcon = f.textLayerHost:CreateTexture(nil, "OVERLAY")
    f.questIcon:SetSize(UPConstants.baseHeight * 1.1, UPConstants.baseHeight * 1.1)
    f.questIcon:SetPoint("RIGHT", f.nameText, "LEFT", -2, 0)
    f.questIcon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\quest\\slay")
    f.questIcon:Hide()

    -- COMBO POINTS
    f.combopoints = CreateFrame("Frame", nil, f)
    f.combopoints:SetFrameLevel(f.healthBar:GetFrameLevel() + 3)
    f.combopoints:SetSize(1, 1)
    f.combopoints.orbs = {}
    local cpSize = UPConstants.baseHeight * 0.5625
    local prevOrb = nil
    for i = 1, 5 do
        local cp = f.combopoints:CreateTexture(nil, "ARTWORK")
        cp:SetTexture("Interface\\AddOns\\UnitPlates\\Media\\combopoint-round")
        cp:SetSize(cpSize, cpSize)
        if i == 1 then
            cp:SetPoint("TOP", f.healthBar, "TOP", -(cpSize * 3), cpSize * 1.15)
        else
            cp:SetPoint("LEFT", prevOrb, "RIGHT", 1, 0)
        end
        f.combopoints.orbs[i] = cp
        prevOrb = cp
    end
    ApplyMaskedBorders(f.combopoints)
    f.combopoints.bgOffsetFrame:ClearAllPoints()
    f.combopoints.bgOffsetFrame:SetPoint("TOPLEFT", f.combopoints.orbs[1], "TOPLEFT", -3.75, 2.5)
    f.combopoints.bgOffsetFrame:SetPoint("BOTTOMRIGHT", f.combopoints.orbs[5], "BOTTOMRIGHT", 3.75, -2.5)
    f.combopoints.overlayMask:ClearAllPoints()
    f.combopoints.overlayMask:SetPoint("TOPLEFT", f.combopoints.orbs[1], "TOPLEFT", -3.75, 2.5)
    f.combopoints.overlayMask:SetPoint("BOTTOMRIGHT", f.combopoints.orbs[5], "BOTTOMRIGHT", 3.75, -2.5)

    -- AURAS CONTAINER
    f.auras = CreateFrame("Frame", nil, f)
    f.auras:SetSize(width, 20)
    f.auras:SetPoint("BOTTOM", f.nameText, "TOP", 0, 4)
    f.auras:SetFrameLevel(f.textLayerHost:GetFrameLevel() + 5)
    f.auraIcons = {}
    for i = 1, 16 do
        f.auraIcons[i] = CreateAuraIcon(f.auras)
    end

    f:Hide()
    return f
end

-------------------------------------------------
-- UPDATE LOGIC
-------------------------------------------------
local function ApplyDynamicWidth(f, unit)
    local isTriv = IsTrivial(unit)
    local pct = isTriv and UnitPlatesSettings.nameplateWidthPercentTrivial or UnitPlatesSettings.nameplateWidthPercent
    local width = UPConstants.baseHeight * (pct / 10)
    
    f.healthBar:SetWidth(width)
    f.powerBar:SetWidth(width)
    f.castBar:SetWidth(width)
    f.auras:SetWidth(width)
    
    local glowScale = UnitPlatesSettings.selectionGlowScale / 100
    f.selectionGlow:SetWidth((width * 2.6) * glowScale)
end

local function UpdateHealth(f, unit)
    if not unit then return end

    -- Safe target query: avoids `<secret boolean> and "target"` crash
    local isTarget = SafeUnitCall(UnitIsUnit, unit, "target")
    local queryUnit = isTarget and "target" or unit
    
    local hp = UnitHealth(queryUnit)
    local maxHp = UnitHealthMax(queryUnit)
    
    f.healthBar:SetMinMaxValues(0, maxHp)
    f.healthBar:SetValue(hp)

    -- === 1. NON-SECRET VALUES ===
    if not issecretvalue(hp) and not issecretvalue(maxHp) then
        if maxHp <= 0 then maxHp = 1 end
        local pct = math.floor((hp / maxHp) * 100)
        
        f.healthText:SetText(UPCoreAbbreviate(hp))
        
        local inCombat = SafeUnitCall(UnitAffectingCombat, queryUnit)
        if pct < 100 or inCombat then
            f.healthPercent:SetText(pct .. "%")
        else
            f.healthPercent:SetText("")
        end

    -- === 2. SECRET VALUES (Combat / Dungeons) ===
    else
        if AbbreviateNumbers then
            f.healthText:SetFormattedText("%s", AbbreviateNumbers(hp))
        elseif AbbreviateLargeNumbers then
            f.healthText:SetFormattedText("%s", AbbreviateLargeNumbers(hp))
        else
            f.healthText:SetFormattedText("%s", hp)
        end
        
        local showedPercent = false

        if UnitHealthPercent then
            local curve = CurveConstants and CurveConstants.ScaleTo100 or ScaleTo100Curve
            local success = pcall(function()
                local pct = curve and UnitHealthPercent(queryUnit, true, curve) or UnitHealthPercent(queryUnit)
                f.healthPercent:SetFormattedText("%.0f%%", pct)
            end)
            if success then showedPercent = true end
        end

        if not showedPercent and f:GetParent() and f:GetParent().UnitFrame then
            local uf = f:GetParent().UnitFrame
            local blizzBar = uf.healthBar or (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar)
            local blizzText = blizzBar and (blizzBar.TextString or blizzBar.statusText or blizzBar.Text)
            
            if blizzText and blizzText.GetText and blizzText:GetText() then
                f.healthPercent:SetFormattedText("%s", blizzText:GetText())
                showedPercent = true
            end
        end

        if not showedPercent then
            f.healthPercent:SetText("")
        end
    end

    local r, g, b = UnitSelectionColor(unit)
    local texture = "Interface\\AddOns\\UnitPlates\\img\\statusbar\\XPerl_StatusBar4"
    local nameColor = {1, 1, 1, 1}

    local isTapped = false
    if UnitIsTapDenied then 
        isTapped = SafeUnitCall(UnitIsTapDenied, unit)
    elseif UnitIsTapped then 
        isTapped = SafeUnitCall(UnitIsTapped, unit) and not SafeUnitCall(UnitIsTappedByPlayer, unit) 
    end

    local isPlayer = SafeUnitCall(UnitIsPlayer, unit)
    local inParty = isPlayer and SafeUnitTruthy(UnitInParty, unit)
    local inRaid = isPlayer and not inParty and SafeUnitTruthy(UnitInRaid, unit)

    local inCombatUnit = SafeUnitCall(UnitAffectingCombat, unit)
    local isFriend = SafeUnitCall(UnitIsFriend, "player", unit)
    local isTargetingMe = false
    if unit and not issecretvalue(unit) then
        isTargetingMe = SafeUnitCall(UnitIsUnit, unit .. "target", "player")
    end

    -- Threat Check (Enemy targeting you)
    local isThreatMob = false
    local okThreat, resThreat = pcall(function()
        return (not isPlayer) and inCombatUnit and (not isFriend) and isTargetingMe
    end)
    if okThreat and resThreat then
        isThreatMob = true
    end

    if isTapped then
        r, g, b = 0.235, 0.227, 0.235
    elseif isThreatMob then
        -- Enemy targeting you: Threat Red
        r, g, b = 0.85, 0, 0
        nameColor = {0.9, 0, 0, 1}
        texture = "Interface\\AddOns\\UnitPlates\\img\\statusbar\\XPerl_StatusBar"
    elseif inParty then
        -- Party Member: Soft Blue (0.4, 0.6, 1.0)
        r, g, b = 0.4, 0.6, 1.0
        nameColor = {0.4, 0.6, 1.0, 1.0}
    elseif inRaid then
        -- Raid Member: Orange (0.85, 0.45, 0.15)
        r, g, b = 0.85, 0.45, 0.15
        nameColor = {0.85, 0.45, 0.15, 1.0}
    end

    f.healthBar:SetStatusBarColor(r, g, b)
    f.healthBar:SetStatusBarTexture(texture)
    f.nameText:SetTextColor(unpack(nameColor))
end

local function UpdatePower(f, unit)
    if not unit then return end
    local isTarget = SafeUnitCall(UnitIsUnit, unit, "target")
    local queryUnit = isTarget and "target" or unit
    
    local maxPower = UnitPowerMax(queryUnit)
    local power = UnitPower(queryUnit)
    local pType = UnitPowerType(queryUnit)
    
    local hasPower = true
    if not issecretvalue(maxPower) then
        if maxPower <= 0 then hasPower = false end
    end
    
    if hasPower then
        f.powerBar:SetMinMaxValues(0, maxPower)
        f.powerBar:SetValue(power)
        
        local color = powerColors[pType] or powerColors[3]
        f.powerBar:SetStatusBarColor(unpack(color))
        f.powerBar:Show()
        
        if not issecretvalue(power) then
            f.powerText:SetText(UPCoreAbbreviate(power))
        else
            if AbbreviateNumbers then
                f.powerText:SetFormattedText("%s", AbbreviateNumbers(power))
            else
                f.powerText:SetFormattedText("%s", power)
            end
        end
    else
        f.powerBar:Hide()
        f.powerText:SetText("")
    end
end

local function UpdateComboPoints(f, unit)
    if not unit then return end
    if SafeUnitCall(UnitIsUnit, unit, "target") then
        local points = UnitPower("player", 4)
        if not issecretvalue(points) and points > 0 then
            for i = 1, 5 do
                if i <= points then
                    f.combopoints.orbs[i]:SetVertexColor(1, 0.224, 0.027, 1)
                else
                    f.combopoints.orbs[i]:SetVertexColor(0.3, 0.3, 0.3, 1)
                end
            end
            f.combopoints:Show()
            return
        end
    end
    f.combopoints:Hide()
end

local function UpdateUnitInfo(f, unit)
    if not unit then return end

    -- Safe Unit Name handling
    local okName, name = pcall(UnitName, unit)
    if okName and name then
        if issecretvalue(name) then
            f.nameText:SetFormattedText("%s", name)
        else
            f.nameText:SetText(name)
        end
    else
        f.nameText:SetText("")
    end
    
    -- Safe Guild Name handling
    local guildName = nil
    local myGuild = nil
    local okMyG, myG = pcall(GetGuildInfo, "player")
    if okMyG and myG and not issecretvalue(myG) then myGuild = myG end

    local isPlayer = SafeUnitCall(UnitIsPlayer, unit)

    if isPlayer then
        local okG, gName = pcall(GetGuildInfo, unit)
        if okG and gName then
            guildName = gName
        end
    else
        -- Scrape NPC occupation/title or Pet owner from the tooltip
        if C_TooltipInfo then
            local success, tooltipData = pcall(C_TooltipInfo.GetUnit, unit)
            if success and tooltipData and tooltipData.lines and tooltipData.lines[2] then
                local line2 = tooltipData.lines[2].leftText
                if line2 and not issecretvalue(line2) then
                    if not string.match(line2, "^Level") and not string.match(line2, "^%?%?") then
                        guildName = string.gsub(line2, "^<(.-)>$", "%1")
                    end
                end
            end
        end
    end

    -- Format & Stack Guild Text with Party/Raid/Guild Coloring
    if guildName then
        local isSecretGuild = issecretvalue(guildName)
        local isMyGuild = not isSecretGuild and myGuild and not issecretvalue(myGuild) and (guildName == myGuild)
        local inParty = isPlayer and SafeUnitTruthy(UnitInParty, unit)
        local inRaid = isPlayer and not inParty and SafeUnitTruthy(UnitInRaid, unit)

        if not isSecretGuild and guildName ~= "" then
            f.guildText:SetText("<" .. guildName .. ">")
        elseif isSecretGuild then
            f.guildText:SetFormattedText("<%s>", guildName)
        else
            f.guildText:SetText("")
        end

        -- Priority: Same Guild (Green) > Party (Light Blue) > Raid (Orange) > Default White
        if isMyGuild then
            f.guildText:SetTextColor(0, 0.999, 0, 1)
        elseif inParty then
            f.guildText:SetTextColor(0.4, 0.6, 1.0, 1.0)
        elseif inRaid then
            f.guildText:SetTextColor(0.85, 0.45, 0.15, 1.0)
        else
            f.guildText:SetTextColor(1, 1, 1, 1)
        end

        f.guildText:Show()
        f.guildText:ClearAllPoints()
        f.guildText:SetPoint("BOTTOM", f.healthBar, "TOP", 0, 2)
        f.nameText:ClearAllPoints()
        f.nameText:SetPoint("BOTTOM", f.guildText, "TOP", 0, 2)
    else
        f.guildText:Hide()
        f.nameText:ClearAllPoints()
        f.nameText:SetPoint("BOTTOM", f.healthBar, "TOP", 0, 2)
    end
    
    -- Safe Level handling
    local okLevel, level = pcall(UnitLevel, unit)
    level = (okLevel and level) or 0
    if issecretvalue(level) then
        f.levelText:SetFormattedText("%s", level)
        f.levelText:SetTextColor(1, 1, 1)
    elseif level <= 0 then
        f.levelText:SetText("??")
        f.levelText:SetTextColor(1, 0, 0)
    else
        f.levelText:SetText(level)
        local color = GetQuestDifficultyColor(level)
        if color then
            f.levelText:SetTextColor(color.r, color.g, color.b)
        end
    end

    -- Safe Race, Class, & PVP Badge handling
    if isPlayer then
        local okRace, race = pcall(UnitRace, unit)
        local okSex, gender = pcall(UnitSex, unit)
        if okRace and not issecretvalue(race) and race then
            local cleanRace = string.gsub(string.lower(race), " ", "")
            local gStr = (okSex and not issecretvalue(gender) and gender == 3) and "female" or "male"
			-- print("cleanRace "..cleanRace)
			-- print("gStr "..gStr)
            f.typeIcon.icon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\races\\" .. cleanRace .. "_" .. gStr .. ".tga")
        else
            f.typeIcon.icon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\loading.tga")
        end
        
        local okClass, class = pcall(UnitClass, unit)
        if okClass and not issecretvalue(class) and class and classCoords[class] then
            f.classIcon:SetTexCoord(unpack(classCoords[class]))
            f.classIcon:Show()
        else
            f.classIcon:Hide()
        end
        
        local rank = 0
        if UnitPVPRank then 
            local okRank, rVal = pcall(UnitPVPRank, unit)
            if okRank and not issecretvalue(rVal) and rVal then rank = rVal end
        end
        if rank > 0 then
            f.pvpRankIcon:SetTexture(string.format("Interface\\PVPRankBadges\\PVPRank%02d", rank))
            f.pvpRankIcon:Show()
        else
            f.pvpRankIcon:Hide()
        end
    else
        local okType, cType = pcall(UnitCreatureType, unit)
        if okType and not issecretvalue(cType) and cType then
            f.typeIcon.icon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\creaturetypes\\" .. string.upper(cType) .. ".tga")
        else
            f.typeIcon.icon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\creaturetypes\\UNKNOWN.tga")
        end
        f.classIcon:Hide()
        f.pvpRankIcon:Hide()
    end

    -- Safe PVP Icon logic (No secret boolean comparisons!)
    local isFFA = UnitIsPVPFreeForAll and SafeUnitCall(UnitIsPVPFreeForAll, unit)
    local isPvP = UnitIsPVP and SafeUnitCall(UnitIsPVP, unit)
    
    local fac = nil
    if UnitFactionGroup then
        local ok, res = pcall(UnitFactionGroup, unit)
        if ok and not issecretvalue(res) and res then fac = res end
    end
    
    if isFFA then
        f.pvpIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-FFA")
        f.pvpIcon:Show()
    elseif isPvP and fac and (fac == "Horde" or fac == "Alliance") then
        f.pvpIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. fac)
        f.pvpIcon:Show()
    else
        f.pvpIcon:Hide()
    end

    -- Safe Elite / Rare classification
    local okClassif, classif = pcall(UnitClassification, unit)
    if okClassif and not issecretvalue(classif) and classif then
        if classif == "elite" then
            f.rarityIcon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\frame_elite"); f.rarityIcon:SetVertexColor(1, 1, 0, 1); f.rarityIcon:Show()
            f.rarityIconR:SetTexture("Interface\\AddOns\\UnitPlates\\img\\frame_elite"); f.rarityIconR:SetVertexColor(1, 1, 0, 1); f.rarityIconR:Show()
        elseif classif == "rareelite" then
            f.rarityIcon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\frame_elite"); f.rarityIcon:SetVertexColor(1, 1, 1, 1); f.rarityIcon:Show()
            f.rarityIconR:SetTexture("Interface\\AddOns\\UnitPlates\\img\\frame_elite"); f.rarityIconR:SetVertexColor(1, 1, 1, 1); f.rarityIconR:Show()
        elseif classif == "rare" then
            f.rarityIcon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\frame_rare"); f.rarityIcon:SetVertexColor(1, 1, 1, 1); f.rarityIcon:Show()
            f.rarityIconR:SetTexture("Interface\\AddOns\\UnitPlates\\img\\frame_rare"); f.rarityIconR:SetVertexColor(1, 1, 1, 1); f.rarityIconR:Show()
        elseif classif == "boss" then
            f.rarityIcon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\frame_elite"); f.rarityIcon:SetVertexColor(0.5, 0, 0, 1); f.rarityIcon:Show()
            f.rarityIconR:SetTexture("Interface\\AddOns\\UnitPlates\\img\\frame_elite"); f.rarityIconR:SetVertexColor(0.5, 0, 0, 1); f.rarityIconR:Show()
        else
            f.rarityIcon:Hide()
            f.rarityIconR:Hide()
        end
    else
        f.rarityIcon:Hide()
        f.rarityIconR:Hide()
    end

    local inCombat = UnitAffectingCombat and SafeUnitCall(UnitAffectingCombat, unit)
    if inCombat then f.combatIcon:Show() else f.combatIcon:Hide() end

    -- Safe Pet Happiness
    local isPetUnit = false
    if UnitIsUnit then
        isPetUnit = SafeUnitCall(UnitIsUnit, unit, "pet")
    end
    if GetPetHappiness and isPetUnit then
        local okHap, hap = pcall(GetPetHappiness)
        if okHap and not issecretvalue(hap) and hap then
            if hap == 1 then f.petHappiness:SetTexCoord(0.375, 0.5625, 0, 0.359375); f.petHappiness:Show()
            elseif hap == 2 then f.petHappiness:SetTexCoord(0.1875, 0.375, 0, 0.359375); f.petHappiness:Show()
            else f.petHappiness:Hide() end
        else
            f.petHappiness:Hide()
        end
    else
        f.petHappiness:Hide()
    end

    -- Safe Range Checker
    local canAttack = UnitCanAttack and SafeUnitCall(UnitCanAttack, "player", unit)

    if canAttack then
        local success, inRangeAuto = pcall(IsSpellInRange, "Auto Shot", unit)
        local success2, inRangeShoot = pcall(IsSpellInRange, "Shoot", unit)
        if (success and inRangeAuto == 1) or (success2 and inRangeShoot == 1) then
            f.shootingIcon:Show()
        else
            f.shootingIcon:Hide()
        end
    else
        f.shootingIcon:Hide()
    end
    
    if f.classIcon:IsShown() then
        f.auras:SetPoint("BOTTOM", f.nameText, "TOP", 0, (UPConstants.baseHeight * 1.25) / 2 + 4)
    else
        f.auras:SetPoint("BOTTOM", f.nameText, "TOP", 0, 4)
    end
	
	-- Safe Quest Icon Scraping (Protected against secret strings)
    f.questIcon:Hide()
    if not isPlayer and C_TooltipInfo then
        local success, tooltipData = pcall(C_TooltipInfo.GetUnit, unit)
        
        if success and tooltipData and tooltipData.lines then
            for _, line in ipairs(tooltipData.lines) do
                local txt = line.leftText
                if txt and not issecretvalue(txt) then
                    local isQuestLine = false
                    
                    local currentStr, totalStr = string.match(txt, "(%d+)%s*/%s*(%d+)")
                    local hasProgress = (currentStr ~= nil)
                    local isComplete = false
                    
                    if hasProgress then
                        local c = tonumber(currentStr)
                        local t = tonumber(totalStr)
                        if c and t and c >= t then isComplete = true end
                    end
                    
                    if not isComplete then
                        if Enum and Enum.TooltipDataLineType and line.type == Enum.TooltipDataLineType.QuestObjective then
                            isQuestLine = true
                        elseif line.type == 8 or hasProgress then
                            isQuestLine = true
                        end
                        
                        if isQuestLine then
                            local lowerTxt = string.lower(txt)
                            local rawName = okName and name
                            local lowerName = (rawName and not issecretvalue(rawName)) and string.lower(rawName) or ""
                            
                            local isInteract = string.find(lowerTxt, "speak") or string.find(lowerTxt, "return") or string.find(lowerTxt, "interact") or string.find(lowerTxt, "talk")
                            local isKill = string.find(lowerTxt, "slain") or string.find(lowerTxt, "kill") or string.find(lowerTxt, "destroy") or string.find(lowerTxt, "defeat") or string.find(lowerTxt, "eliminate")
                            
                            if not isKill and lowerName ~= "" then
                                local strippedTxt = string.gsub(lowerTxt, "[%d/:]", "")
                                strippedTxt = string.match(strippedTxt, "^%s*(.-)%s*$") or strippedTxt
                                if strippedTxt == lowerName or strippedTxt == lowerName .. "s" then
                                    isKill = true
                                end
                            end
                            
                            if isInteract then
                                f.questIcon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\quest\\exclamation_yellow")
                            elseif isKill then
                                f.questIcon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\quest\\slay")
                            elseif hasProgress then
                                f.questIcon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\quest\\loot")
                            else
                                f.questIcon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\quest\\exclamation_yellow")
                            end
                            
                            f.questIcon:Show()
                            break
                        end
                    end
                end
            end
        end
    end
    
    ApplyDynamicWidth(f, unit)
end

local function UpdateAuras(f, unit)
    -- Early exit: If in combat, hide our custom API auras and let the OnUpdate scrape the default ones
    local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
    if inCombat then
        for i = 1, #f.auraIcons do f.auraIcons[i]:Hide() end
        return 
    end

    -- Hide existing custom icons before rebuilding
    for i = 1, #f.auraIcons do f.auraIcons[i]:Hide() end
    
    local isTriv = IsTrivial(unit)
    local maxPerRow = isTriv and UnitPlatesSettings.aurasInRowTrivial or UnitPlatesSettings.aurasInRow
    local iconSize = (f.healthBar:GetWidth() / maxPerRow) - 2

    local buffs = {}
    local debuffs = {}
    
    -- PLATYNATOR TRICK: INCLUDE_NAME_PLATE_ONLY allows combat queries on nameplates!
    if UnitPlatesSettings.showBuffs then
        local filter = UnitPlatesSettings.onlyYourBuffs and "HELPFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY" or "HELPFUL|INCLUDE_NAME_PLATE_ONLY"
        for i = 1, 40 do
            local success, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if success then
                if not data then break end -- Cleanly exit when out of auras
                table.insert(buffs, data)
            end
        end
    end
    
    if UnitPlatesSettings.showDebuffs then
        local filter = UnitPlatesSettings.onlyYourDebuffs and "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY" or "HARMFUL|INCLUDE_NAME_PLATE_ONLY"
        for i = 1, 40 do
            local success, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if success then
                if not data then break end -- Cleanly exit when out of auras
                table.insert(debuffs, data)
            end
        end
    end

    local iconIndex = 1
    local buffCount = 0
    local debuffCount = 0

    for _, auraData in ipairs(buffs) do
        local name = auraData.name
        
        -- SAFEGUARD: If name is a secret value, bypass the ignore list but STILL SHOW IT
        local isIgnored = false
        if name and not issecretvalue(name) then
            isIgnored = IsNameIgnored(name, UnitPlatesSettings.ignoredBuffNames)
        end
        
        if not isIgnored then
            if not (UnitPlatesSettings.onlyYourBuffs and auraData.sourceUnit ~= "player") then
                if iconIndex <= #f.auraIcons then
                    local icon = f.auraIcons[iconIndex]
                    icon:SetSize(iconSize, iconSize)
                    
                    local col = buffCount % maxPerRow
                    local row = math.floor(buffCount / maxPerRow)
                    local yOffset = row * (iconSize + 2)
                    
                    icon:SetPoint("BOTTOMLEFT", col * (iconSize + 2), yOffset)
                    icon.cdText:SetFont(GetFont(), iconSize * 0.4, "OUTLINE")
                    icon.count:SetFont(GetFont(), iconSize * 0.35, "OUTLINE")
                    
                    local texture = auraData.icon
                    if issecretvalue(texture) then texture = "Interface\\Icons\\INV_Misc_QuestionMark" end
                    icon.icon:SetTexture(texture)
                    
                    local count = auraData.applications or 0
                    if issecretvalue(count) then count = 0 end
                    icon.count:SetText(count > 1 and count or "")
                    
                    local duration = auraData.duration or 0
                    local expirationTime = auraData.expirationTime or 0
                    
                    icon.duration = duration
                    icon.expirationTime = expirationTime
                    
                    -- SetCooldown natively accepts secret values!
                    if duration > 0 or issecretvalue(duration) then
                        icon.cooldown:SetCooldown(expirationTime - duration, duration)
                        icon.cooldown:Show()
                    else
                        icon.cooldown:Hide()
                        icon.cdText:SetText("")
                    end
                    
                    icon:Show()
                    iconIndex = iconIndex + 1
                    buffCount = buffCount + 1
                end
            end
        end
    end

    local buffRows = math.ceil(buffCount / maxPerRow)
    local debuffStartY = buffRows * (iconSize + 2)
    if buffCount > 0 then debuffStartY = debuffStartY + (iconSize * 0.3) end -- Spacer gap

    for _, auraData in ipairs(debuffs) do
        local name = auraData.name
        
        -- SAFEGUARD: If name is a secret value, bypass the ignore list but STILL SHOW IT
        local isIgnored = false
        if name and not issecretvalue(name) then
            isIgnored = IsNameIgnored(name, UnitPlatesSettings.ignoredDebuffNames)
        end
        
        if not isIgnored then
            if not (UnitPlatesSettings.onlyYourDebuffs and not auraData.isBossAura and auraData.sourceUnit ~= "player") then
                if iconIndex <= #f.auraIcons then
                    local icon = f.auraIcons[iconIndex]
                    icon:SetSize(iconSize, iconSize)
                    
                    local col = debuffCount % maxPerRow
                    local row = math.floor(debuffCount / maxPerRow)
                    local yOffset = debuffStartY + (row * (iconSize + 2))
                    
                    icon:SetPoint("BOTTOMLEFT", col * (iconSize + 2), yOffset)
                    icon.cdText:SetFont(GetFont(), iconSize * 0.4, "OUTLINE")
                    icon.count:SetFont(GetFont(), iconSize * 0.35, "OUTLINE")
                    
                    local texture = auraData.icon
                    if issecretvalue(texture) then texture = "Interface\\Icons\\INV_Misc_QuestionMark" end
                    icon.icon:SetTexture(texture)
                    
                    local count = auraData.applications or 0
                    if issecretvalue(count) then count = 0 end
                    icon.count:SetText(count > 1 and count or "")
                    
                    local duration = auraData.duration or 0
                    local expirationTime = auraData.expirationTime or 0
                    
                    icon.duration = duration
                    icon.expirationTime = expirationTime
                    
                    -- SetCooldown natively accepts secret values!
                    if duration > 0 or issecretvalue(duration) then
                        icon.cooldown:SetCooldown(expirationTime - duration, duration)
                        icon.cooldown:Show()
                    else
                        icon.cooldown:Hide()
                        icon.cdText:SetText("")
                    end
                    
                    icon:Show()
                    iconIndex = iconIndex + 1
                    debuffCount = debuffCount + 1
                end
            end
        end
    end
end

local function UpdateCastBar(f, unit)
    local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible
    local isChannel = false

    if UnitCastingInfo then
        name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible = UnitCastingInfo(unit)
    end
    
    if not name and UnitChannelInfo then
        name, text, texture, startTime, endTime, isTradeSkill, notInterruptible = UnitChannelInfo(unit)
        isChannel = true
    end

    if name then
        if issecretvalue(startTime) or issecretvalue(endTime) then
            f.castBar:SetMinMaxValues(startTime, endTime)
            f.castBar:SetScript("OnUpdate", function(self) self:SetValue(GetTime() * 1000) end)
        else
            f.castBar:SetMinMaxValues(startTime / 1000, endTime / 1000)
            f.castBar:SetScript("OnUpdate", function(self) self:SetValue(GetTime()) end)
        end
        
        f.castBar:SetReverseFill(isChannel)
        f.castName:SetFormattedText("%s", name)
        f.castIcon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        
        if not issecretvalue(notInterruptible) and notInterruptible then
            f.castBar:SetStatusBarColor(0.8, 0.1, 0.1)
        else
            f.castBar:SetStatusBarColor(1, 0.7, 0)
        end
        f.castBar:Show()
    else
        f.castBar:Hide()
        f.castBar:SetScript("OnUpdate", nil)
    end
end

local function UpdateTarget(f, unit)
    if not unit then return end
    if SafeUnitCall(UnitIsUnit, unit, "target") then
        f.targetLeft:Show()
        f.targetRight:Show()
        f.selectionGlow:Show()
        f:SetFrameLevel(100)
    else
        f.targetLeft:Hide()
        f.targetRight:Hide()
        f.selectionGlow:Hide()
        f:SetFrameLevel(10)
    end
    UpdateComboPoints(f, unit)
end

-------------------------------------------------
-- EVENT HANDLER
-------------------------------------------------
local MainFrame = CreateFrame("Frame")
MainFrame:RegisterEvent("ADDON_LOADED")
MainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
MainFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
MainFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
MainFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
MainFrame:RegisterEvent("UNIT_HEALTH")
MainFrame:RegisterEvent("UNIT_MAXHEALTH")
MainFrame:RegisterEvent("UNIT_POWER_UPDATE")
MainFrame:RegisterEvent("UNIT_MAXPOWER")
MainFrame:RegisterEvent("UNIT_AURA")
MainFrame:RegisterEvent("UNIT_SPELLCAST_START")
MainFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
MainFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
MainFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
MainFrame:RegisterEvent("UNIT_FACTION")
MainFrame:RegisterEvent("UNIT_THREAT_LIST_UPDATE")

MainFrame:SetScript("OnEvent", function(self, event, unit, ...)
    if event == "ADDON_LOADED" and unit == addonName then
        LoadDefaultSettings()
    elseif event == "PLAYER_ENTERING_WORLD" then
        SetCVar("nameplateShowEnemies", 1)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if not plate then return end
        
        if not plate.UPFrame then
            plate.UPFrame = BuildNameplateUI(plate)
        end
        
        plate.UPFrame.unit = unit
        plate.UPFrame:Show()
        ActivePlates[unit] = plate.UPFrame
        
        UpdateUnitInfo(plate.UPFrame, unit)
        UpdateHealth(plate.UPFrame, unit)
        UpdatePower(plate.UPFrame, unit)
        UpdateAuras(plate.UPFrame, unit)
        UpdateCastBar(plate.UPFrame, unit)
        UpdateTarget(plate.UPFrame, unit)

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate and plate.UPFrame then
            plate.UPFrame:Hide()
            plate.UPFrame.unit = nil
        end
        ActivePlates[unit] = nil

    elseif event == "PLAYER_TARGET_CHANGED" then
        for u, f in pairs(ActivePlates) do
            UpdateHealth(f, u)
            UpdateTarget(f, u)
        end

    elseif ActivePlates[unit] then
        local f = ActivePlates[unit]
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_FACTION" or event == "UNIT_THREAT_LIST_UPDATE" then
            UpdateHealth(f, unit)
            UpdateUnitInfo(f, unit)
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
            UpdatePower(f, unit)
            if unit == "player" then
                for u, frame in pairs(ActivePlates) do UpdateComboPoints(frame, u) end
            end
        elseif event == "UNIT_AURA" then
            UpdateAuras(f, unit)
        elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
            UpdateCastBar(f, unit)
        elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            f.castBar:Hide()
            f.castBar:SetScript("OnUpdate", nil)
        end
    end
    
    if unit == "player" and event == "UNIT_POWER_UPDATE" then
        for u, frame in pairs(ActivePlates) do UpdateComboPoints(frame, u) end
    end
end)

-------------------------------------------------
-- OPTIONS MENU
-------------------------------------------------
SLASH_UNITPLATES1 = "/unitplates"
SLASH_UNITPLATES2 = "/up"

local OptionsFrame = CreateFrame("Frame", "UnitPlatesOptionsFrame", UIParent, "BackdropTemplate")
SlashCmdList["UNITPLATES"] = function() OptionsFrame:Show() end

local function BuildOptionsUI()
    OptionsFrame:SetSize(500, 500)
    OptionsFrame:SetPoint("CENTER")
    OptionsFrame:SetMovable(true)
    OptionsFrame:EnableMouse(true)
    OptionsFrame:RegisterForDrag("LeftButton")
    OptionsFrame:SetScript("OnDragStart", OptionsFrame.StartMoving)
    OptionsFrame:SetScript("OnDragStop", OptionsFrame.StopMovingOrSizing)
    
    OptionsFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
        edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    OptionsFrame:SetBackdropColor(0, 0, 0, 0.8)
    OptionsFrame:Hide()

    local title = OptionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -12)
    title:SetText("UnitPlates Options\n(Some settings require /reload)")

    local closeBtn = CreateFrame("Button", nil, OptionsFrame, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 25)
    closeBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() OptionsFrame:Hide() end)
    
    local defaultBtn = CreateFrame("Button", nil, OptionsFrame, "UIPanelButtonTemplate")
    defaultBtn:SetSize(160, 25)
    defaultBtn:SetPoint("BOTTOMLEFT", 10, 10)
    defaultBtn:SetText("Set defaults & Reload")
    defaultBtn:SetScript("OnClick", function() LoadDefaultSettings(); ReloadUI() end)

    local scrollFrame = CreateFrame("ScrollFrame", "UPScrollFrame", OptionsFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 45)

    local container = CreateFrame("Frame", nil, scrollFrame)
    container:SetSize(440, 800)
    scrollFrame:SetScrollChild(container)

    -- === AURAS SECTION ===
    local aurasTitle = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    aurasTitle:SetPoint("TOPLEFT", 8, -10)
    aurasTitle:SetTextColor(0.999, 0.819, 0)
    aurasTitle:SetText("--- AURAS:")

    local sldAuraRow = CreateFrame("Slider", "UPAuraRowSlider", container, "OptionsSliderTemplate")
    sldAuraRow:SetPoint("TOPLEFT", aurasTitle, "BOTTOMLEFT", 0, -20)
    sldAuraRow:SetWidth(350)
    sldAuraRow:SetMinMaxValues(4, 20)
    sldAuraRow:SetValueStep(1)
    sldAuraRow:SetValue(UnitPlatesSettings.aurasInRow)
    _G[sldAuraRow:GetName().."Low"]:SetText("4")
    _G[sldAuraRow:GetName().."High"]:SetText("20")
    _G[sldAuraRow:GetName().."Text"]:SetText("Auras in row: " .. UnitPlatesSettings.aurasInRow)
    sldAuraRow:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        UnitPlatesSettings.aurasInRow = val
        _G[self:GetName().."Text"]:SetText("Auras in row: " .. val)
    end)
    
    local sldAuraRowT = CreateFrame("Slider", "UPAuraRowTSlider", container, "OptionsSliderTemplate")
    sldAuraRowT:SetPoint("TOPLEFT", sldAuraRow, "BOTTOMLEFT", 0, -25)
    sldAuraRowT:SetWidth(350)
    sldAuraRowT:SetMinMaxValues(4, 20)
    sldAuraRowT:SetValueStep(1)
    sldAuraRowT:SetValue(UnitPlatesSettings.aurasInRowTrivial)
    _G[sldAuraRowT:GetName().."Low"]:SetText("4")
    _G[sldAuraRowT:GetName().."High"]:SetText("20")
    _G[sldAuraRowT:GetName().."Text"]:SetText("Auras in row (Trivials): " .. UnitPlatesSettings.aurasInRowTrivial)
    sldAuraRowT:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        UnitPlatesSettings.aurasInRowTrivial = val
        _G[self:GetName().."Text"]:SetText("Auras in row (Trivials): " .. val)
    end)

    local chkBuffs = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    chkBuffs:SetPoint("TOPLEFT", sldAuraRowT, "BOTTOMLEFT", 0, -15)
    chkBuffs.Text:SetText("Show Buffs")
    chkBuffs:SetChecked(UnitPlatesSettings.showBuffs)
    chkBuffs:SetScript("OnClick", function(self) UnitPlatesSettings.showBuffs = self:GetChecked() end)

    local chkMineBuffs = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    chkMineBuffs:SetPoint("TOPLEFT", chkBuffs, "BOTTOMLEFT", 0, 0)
    chkMineBuffs.Text:SetText("Show only your buffs")
    chkMineBuffs:SetChecked(UnitPlatesSettings.onlyYourBuffs)
    chkMineBuffs:SetScript("OnClick", function(self) UnitPlatesSettings.onlyYourBuffs = self:GetChecked() end)

    local buffIgnoreTitle = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buffIgnoreTitle:SetPoint("TOPLEFT", chkMineBuffs, "BOTTOMLEFT", 0, -5)
    buffIgnoreTitle:SetText("Ignore buff names:")
    local buffIgnoreInput = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    buffIgnoreInput:SetPoint("TOPLEFT", buffIgnoreTitle, "BOTTOMLEFT", 0, -5)
    buffIgnoreInput:SetSize(280, 26)
    buffIgnoreInput:SetFontObject("GameFontNormal")
    buffIgnoreInput:SetAutoFocus(false)
    buffIgnoreInput:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/DialogFrame/UI-DialogBox-Border", edgeSize=12, insets={left=2, right=2, top=2, bottom=2}})
    buffIgnoreInput:SetBackdropColor(0,0,0,0.8)
    buffIgnoreInput:SetTextInsets(5, 5, 5, 5)
    buffIgnoreInput:SetText(UnitPlatesSettings.ignoredBuffNames)
    buffIgnoreInput:SetScript("OnTextChanged", function(self) UnitPlatesSettings.ignoredBuffNames = self:GetText() end)

    local chkDebuffs = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    chkDebuffs:SetPoint("TOPLEFT", buffIgnoreInput, "BOTTOMLEFT", 0, -15)
    chkDebuffs.Text:SetText("Show Debuffs")
    chkDebuffs:SetChecked(UnitPlatesSettings.showDebuffs)
    chkDebuffs:SetScript("OnClick", function(self) UnitPlatesSettings.showDebuffs = self:GetChecked() end)

    local chkMineDebuffs = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    chkMineDebuffs:SetPoint("TOPLEFT", chkDebuffs, "BOTTOMLEFT", 0, 0)
    chkMineDebuffs.Text:SetText("Show only your debuffs")
    chkMineDebuffs:SetChecked(UnitPlatesSettings.onlyYourDebuffs)
    chkMineDebuffs:SetScript("OnClick", function(self) UnitPlatesSettings.onlyYourDebuffs = self:GetChecked() end)

    local debuffIgnoreTitle = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    debuffIgnoreTitle:SetPoint("TOPLEFT", chkMineDebuffs, "BOTTOMLEFT", 0, -5)
    debuffIgnoreTitle:SetText("Ignore debuff names:")
    local debuffIgnoreInput = CreateFrame("EditBox", nil, container, "BackdropTemplate")
    debuffIgnoreInput:SetPoint("TOPLEFT", debuffIgnoreTitle, "BOTTOMLEFT", 0, -5)
    debuffIgnoreInput:SetSize(280, 26)
    debuffIgnoreInput:SetFontObject("GameFontNormal")
    debuffIgnoreInput:SetAutoFocus(false)
    debuffIgnoreInput:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/DialogFrame/UI-DialogBox-Border", edgeSize=12, insets={left=2, right=2, top=2, bottom=2}})
    debuffIgnoreInput:SetBackdropColor(0,0,0,0.8)
    debuffIgnoreInput:SetTextInsets(5, 5, 5, 5)
    debuffIgnoreInput:SetText(UnitPlatesSettings.ignoredDebuffNames)
    debuffIgnoreInput:SetScript("OnTextChanged", function(self) UnitPlatesSettings.ignoredDebuffNames = self:GetText() end)

    -- === UI SECTION ===
    local uiTitle = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    uiTitle:SetPoint("TOPLEFT", debuffIgnoreInput, "BOTTOMLEFT", 0, -25)
    uiTitle:SetTextColor(0.999, 0.819, 0)
    uiTitle:SetText("--- UI:")

    local chkOverlap = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    chkOverlap:SetPoint("TOPLEFT", uiTitle, "BOTTOMLEFT", 0, -5)
    chkOverlap.Text:SetText("Overlapping (Recommended)")
    chkOverlap:SetChecked(UnitPlatesSettings.overlapping)
    chkOverlap:SetScript("OnClick", function(self) UnitPlatesSettings.overlapping = self:GetChecked() end)

    local sldScale = CreateFrame("Slider", "UPScaleSlider", container, "OptionsSliderTemplate")
    sldScale:SetPoint("TOPLEFT", chkOverlap, "BOTTOMLEFT", 0, -20)
    sldScale:SetWidth(350)
    sldScale:SetMinMaxValues(0.5, 3.0)
    sldScale:SetValueStep(0.1)
    sldScale:SetValue(UnitPlatesSettings.scale)
    _G[sldScale:GetName().."Low"]:SetText("0.5")
    _G[sldScale:GetName().."High"]:SetText("3.0")
    _G[sldScale:GetName().."Text"]:SetText("Scale: " .. UnitPlatesSettings.scale)
    sldScale:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val * 10 + 0.5) / 10
        UnitPlatesSettings.scale = val
        _G[self:GetName().."Text"]:SetText("Scale: " .. val)
        for _, f in pairs(ActivePlates) do f:SetScale(val) end
    end)
    
    local sldGlowScale = CreateFrame("Slider", "UPGlowScaleSlider", container, "OptionsSliderTemplate")
    sldGlowScale:SetPoint("TOPLEFT", sldScale, "BOTTOMLEFT", 0, -25)
    sldGlowScale:SetWidth(350)
    sldGlowScale:SetMinMaxValues(100, 300)
    sldGlowScale:SetValueStep(1)
    sldGlowScale:SetValue(UnitPlatesSettings.selectionGlowScale)
    _G[sldGlowScale:GetName().."Low"]:SetText("100%")
    _G[sldGlowScale:GetName().."High"]:SetText("300%")
    _G[sldGlowScale:GetName().."Text"]:SetText("Selection glow scale %: " .. UnitPlatesSettings.selectionGlowScale)
    sldGlowScale:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        UnitPlatesSettings.selectionGlowScale = val
        _G[self:GetName().."Text"]:SetText("Selection glow scale %: " .. val)
    end)
    
    local sldGlowAlpha = CreateFrame("Slider", "UPGlowAlphaSlider", container, "OptionsSliderTemplate")
    sldGlowAlpha:SetPoint("TOPLEFT", sldGlowScale, "BOTTOMLEFT", 0, -25)
    sldGlowAlpha:SetWidth(350)
    sldGlowAlpha:SetMinMaxValues(0, 100)
    sldGlowAlpha:SetValueStep(1)
    sldGlowAlpha:SetValue(UnitPlatesSettings.selectionGlowAlpha)
    _G[sldGlowAlpha:GetName().."Low"]:SetText("0%")
    _G[sldGlowAlpha:GetName().."High"]:SetText("100%")
    _G[sldGlowAlpha:GetName().."Text"]:SetText("Selection glow alpha %: " .. UnitPlatesSettings.selectionGlowAlpha)
    sldGlowAlpha:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        UnitPlatesSettings.selectionGlowAlpha = val
        _G[self:GetName().."Text"]:SetText("Selection glow alpha %: " .. val)
    end)
    
    local sldWidth = CreateFrame("Slider", "UPWidthSlider", container, "OptionsSliderTemplate")
    sldWidth:SetPoint("TOPLEFT", sldGlowAlpha, "BOTTOMLEFT", 0, -25)
    sldWidth:SetWidth(350)
    sldWidth:SetMinMaxValues(40, 200)
    sldWidth:SetValueStep(1)
    sldWidth:SetValue(UnitPlatesSettings.nameplateWidthPercent)
    _G[sldWidth:GetName().."Low"]:SetText("40%")
    _G[sldWidth:GetName().."High"]:SetText("200%")
    _G[sldWidth:GetName().."Text"]:SetText("Nameplate width %: " .. UnitPlatesSettings.nameplateWidthPercent)
    sldWidth:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        UnitPlatesSettings.nameplateWidthPercent = val
        _G[self:GetName().."Text"]:SetText("Nameplate width %: " .. val)
    end)

    local sldWidthT = CreateFrame("Slider", "UPWidthTSlider", container, "OptionsSliderTemplate")
    sldWidthT:SetPoint("TOPLEFT", sldWidth, "BOTTOMLEFT", 0, -25)
    sldWidthT:SetWidth(350)
    sldWidthT:SetMinMaxValues(40, 200)
    sldWidthT:SetValueStep(1)
    sldWidthT:SetValue(UnitPlatesSettings.nameplateWidthPercentTrivial)
    _G[sldWidthT:GetName().."Low"]:SetText("40%")
    _G[sldWidthT:GetName().."High"]:SetText("200%")
    _G[sldWidthT:GetName().."Text"]:SetText("Nameplate width % (Trivials): " .. UnitPlatesSettings.nameplateWidthPercentTrivial)
    sldWidthT:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        UnitPlatesSettings.nameplateWidthPercentTrivial = val
        _G[self:GetName().."Text"]:SetText("Nameplate width % (Trivials): " .. val)
    end)
end
BuildOptionsUI()

-------------------------------------------------
-- MINIMAP BUTTON
-------------------------------------------------
local UPMinimapButton = CreateFrame("Button", "UPMainMenuBarToggler", Minimap)
UPMinimapButton:SetSize(31, 31)
UPMinimapButton:SetFrameLevel(8)
UPMinimapButton:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
UPMinimapButton:SetMovable(true)
UPMinimapButton:EnableMouse(true)

local overlay = UPMinimapButton:CreateTexture(nil, "OVERLAY")
overlay:SetSize(53, 53)
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
overlay:SetPoint("TOPLEFT")

local icon = UPMinimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetTexture("Interface\\AddOns\\UnitPlates\\img\\minimap\\minimap_icon")
if not icon:GetTexture() then icon:SetTexture("Interface\\Icons\\Spell_ChargeNegative") end
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
icon:SetPoint("TOPLEFT", 7, -5)

-- Universal circular positioning around the true center of the Minimap
local function UpdateMinimapButtonPosition(angle)
    local rad = math.rad(angle or 0)
    -- Places the button center directly along the circular border
    local radius = (Minimap:GetWidth() / 2) + 5
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    
    UPMinimapButton:ClearAllPoints()
    UPMinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

UPMinimapButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        OptionsFrame:SetShown(not OptionsFrame:IsShown())
    end
end)

UPMinimapButton:RegisterForDrag("RightButton")
UPMinimapButton:SetScript("OnDragStart", function(self)
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

        UnitPlatesSettings.minimapIconPos = angle
        UpdateMinimapButtonPosition(angle)
    end)
end)

UPMinimapButton:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetScript("OnUpdate", nil)
end)

UPMinimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("UnitPlates")
    GameTooltip:AddLine("Left-click to show options\nRight-click and drag to move", 1, 1, 1)
    GameTooltip:Show()
end)

UPMinimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

C_Timer.After(0.5, function()
    local pos = (UnitPlatesSettings and UnitPlatesSettings.minimapIconPos) or 200
    UpdateMinimapButtonPosition(pos)
end)