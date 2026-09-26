local UPCoreTimerQueue = {}
local UPCoreTimerFrame = CreateFrame("Frame", "UPCoreTimerFrame", UIParent)

UPCoreTimerFrame:SetScript("OnUpdate", function()
	if UnitPlatesAddonIsLoaded and UnitPlatesPlayerEnteredWorld and (UnitPlatesElapsedTimeSinceFullyLoaded > UnitPlatesLoadDelay) then
		local currentTime = GetTime()
		local i = 1
		
		-- Iterate through the queue. We use a while loop because table.remove shifts indexes.
		while i <= table.getn(UPCoreTimerQueue) do
			local task = UPCoreTimerQueue[i]
			if currentTime >= task.executionTime then
				-- Time is up! Remove the task from the queue first to prevent double-execution
				table.remove(UPCoreTimerQueue, i)
				
				-- Execute the stored function with its original arguments
				if task.args then
					task.func(unpack(task.args))
				else
					task.func()
				end
			else
				-- Not ready yet, check the next one
				i = i + 1
			end
		end
	end
end)

-- PUBLIC API: Call this to delay any function
function UPCoreDelayCall(delayInSeconds, func, ...)
    table.insert(UPCoreTimerQueue, {
        executionTime = GetTime() + delayInSeconds,
        func = func,
        args = arg -- In 1.12/Lua 5.0, '...' is automatically packaged into the local 'arg' table
    })
end

function UPCoreGetCurrentPingSeconds()
	local down, up, lagHome, lagWorld = GetNetStats() --lagWorld is not in 1.12
	return lagHome / 1000
end

function UPCoreTrimString(s)
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

-- Format numbers
function UPCoreNum(num)
    if num < 1000 then
        return num
    elseif num >= 1000000 then
        return string.format('%.1fm', num/1000000)
    elseif num >= 1000 then
        return string.format('%.1fk', num/1000)
    end
end

function UPCoreRoundNum(input, places)
	if not places then places = 0 end
	
	if type(input) == "number" and type(places) == "number" then
		local pow = 1
		for i = 1, places do pow = pow * 10 end
		return math.floor(input * pow + 0.5) / pow
	end
end

function UPCoreAbbreviate(number)
	local sign = number < 0 and -1 or 1
	number = math.abs(number)

	if number > 1000000 then
		return UPCoreRoundNum(number/1000000*sign,2) .. "m"
	elseif number > 1000 then
		return UPCoreRoundNum(number/1000*sign,2) .. "k"
	end
	
	return number
end

------------------------------FRAME FUNCTIONS

-- Frame fading functions
-- (without the taint of UIFrameFade & the lag of AnimationGroups)
UnitPlatesFrameFadeFrame = CreateFrame('Frame')
UNITPLATES_FADEFRAMES = {}

function UPCoreFrameIsFading(frame)
    for index, value in pairs(UNITPLATES_FADEFRAMES) do
        if value == frame then
            return true
        end
    end
end

function UPCoreFrameFadeRemoveFrame(frame)
    tDeleteItem(UNITPLATES_FADEFRAMES, frame)
end

function UPCoreFrameFadeOnUpdate(self, elapsed)
    local frame, info
    for index, value in pairs(UNITPLATES_FADEFRAMES) do
        frame, info = value, value.fadeInfo

        if info.startDelay and info.startDelay > 0 then
            info.startDelay = info.startDelay - elapsed
        else
            info.fadeTimer = (info.fadeTimer and info.fadeTimer + elapsed) or 0

            if info.fadeTimer < info.timeToFade then
                -- perform animation in either direction
                if info.mode == 'IN' then
                    frame:SetAlpha(
                        (info.fadeTimer / info.timeToFade) *
                        (info.endAlpha - info.startAlpha) +
                        info.startAlpha
                    )
                elseif info.mode == 'OUT' then
                    frame:SetAlpha(
                        ((info.timeToFade - info.fadeTimer) / info.timeToFade) *
                        (info.startAlpha - info.endAlpha) + info.endAlpha
                    )
                end
            else
                -- animation has ended
                frame:SetAlpha(info.endAlpha)

                if info.fadeHoldTime and info.fadeHoldTime > 0 then
                    info.fadeHoldTime = info.fadeHoldTime - elapsed
                else
                    UPCoreFrameFadeRemoveFrame(frame)

                    if info.finishedFunc then
                        info.finishedFunc(frame)
                        info.finishedFunc = nil
                    end
                end
            end
        end
    end

    if table.getn(UNITPLATES_FADEFRAMES) == 0 then
        self:SetScript('OnUpdate', nil)
    end
end
--[[
    info = {
        mode            = "IN" (nil) or "OUT",
        startAlpha      = alpha value to start at,
        endAlpha        = alpha value to end at,
        timeToFade      = duration of animation,
        startDelay      = seconds to wait before starting animation,
        fadeHoldTime    = seconds to wait after ending animation before calling finishedFunc,
        finishedFunc    = function to call after animation has ended,
    }

    If you plan to reuse `info`, it should be passed as a single table,
    NOT a reference, as the table will be directly edited.
]]
function UPCoreFrameFade(frame, info)
    if not frame then return end
    if UPCoreFrameIsFading(frame) then
        -- cancel the current operation
        -- the code calling this should make sure not to interrupt a
        -- necessary finishedFunc. This will entirely skip it.
        UPCoreFrameFadeRemoveFrame(frame)
    end

    info        = info or {}
    info.mode   = info.mode or 'IN'

    if info.mode == 'IN' then
        info.startAlpha = info.startAlpha or 0
        info.endAlpha   = info.endAlpha or 1
    elseif info.mode == 'OUT' then
        info.startAlpha = info.startAlpha or 1
        info.endAlpha   = info.endAlpha or 0
    end

    frame:SetAlpha(info.startAlpha)
    frame.fadeInfo = info

    tinsert(UNITPLATES_FADEFRAMES, frame)
    UnitPlatesFrameFadeFrame:SetScript("OnUpdate", function()
		UPCoreFrameFadeOnUpdate(UnitPlatesFrameFadeFrame, arg1)
	end)
end

function UPCoreFadeCastWarningFrame(self, from, to, duration, end_delay, callback)
	UPCoreFrameFadeRemoveFrame(self)

	self:Show()
	self:SetAlpha(from)

	UPCoreFrameFade(self, {
		mode = "OUT",
		startAlpha = from,
		endAlpha = to,
		timeToFade = duration,
		fadeHoldTime = end_delay,
		finishedFunc = function(self)
			if to == 0 then
				self:Hide()
			else
				self:SetAlpha(to)
			end

			if callback then
				callback(self)
			end
		end
	})
end

-----------------
--debuff cooldownframe emulation
function UPCoreCreateQuadrant(parent, point)
    local tex = parent:CreateTexture(nil, "OVERLAY")
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetVertexColor(0, 0, 0, 0.4) -- Semi-transparent black
    tex:SetWidth(parent:GetWidth()/2)
	tex:SetHeight(parent:GetHeight()/2)
    tex:SetPoint(point, parent, point)
    return tex
end
--debuff cooldownframe emulation END

------------------------------FRAME FUNCTIONS END

-----------------
--Drop this cache on instance change (and zone/phase change? party/raid leave as well?)
UPCoreNameGuidCacheMap = {
	["-testname"] = "-testguid"
}

function UPCoreClearNameGuidCacheMap(name)
	UPCoreNameGuidCacheMap = {}
end

function UPCoreStoreGuidForName(name, guid)
	if name then
		UPCoreNameGuidCacheMap[name] = guid
	end
end

function UPCoreGetGuidForName(name)
	return UPCoreNameGuidCacheMap[name]
end

------------------

function UPCoreStyleBalloon(f)	

	local r = {f:GetRegions()}
	for _, v in pairs(r) do
		if  v:GetObjectType() == 'FontString' then
			f.textstring = v
			break
		end
	end
  
	if not f.skinned then
		local r = {f:GetRegions()}
		for _, v in pairs(r) do
			v:Hide()
		end

		f.chatBubble = CreateFrame("Frame", nil, f)
		f.chatBubble:SetHeight(5)
		f.chatBubble:SetWidth(5)
		f.chatBubble:SetPoint("BOTTOM", f, "TOP", 0, 0)

		local insets = 16 --8

		f.chatBubble:SetBackdrop({
			bgFile = "Interface\\Tooltips\\ChatBubble-Background",
			edgeFile = "Interface\\Tooltips\\ChatBubble-Backdrop",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = insets, right = insets, top = insets, bottom = insets }
		})
		f.chatBubble:SetBackdropColor(1,1,1,1)
		f.chatBubble:SetBackdropBorderColor(1,1,1,1)

		f.chatBubble.fontMeasure = f.chatBubble:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.chatBubble.font = f.chatBubble:CreateFontString(nil, "OVERLAY", "GameFontNormal")

		UPCoreUpdateCustomBalloonText(f, f.textstring:GetText())

		f.chatBubble.font:SetPoint("CENTER", f.chatBubble, "CENTER", 0, 0)
		f.chatBubble.font:SetJustifyH("CENTER")

		f.chatBubble.tail = f.chatBubble:CreateTexture(nil, "OVERLAY")
		f.chatBubble.tail:SetTexture("Interface/Tooltips/ChatBubble-Tail")
		f.chatBubble.tail:SetWidth(24)
		f.chatBubble.tail:SetHeight(18)
		f.chatBubble.tail:SetPoint("TOP", f.chatBubble, "BOTTOM", -10, 4)
		f.chatBubble:Show()
		
		f.textstring:SetFont(STANDARD_TEXT_FONT, 10)
		f:SetFrameStrata("LOW")
		f.skinned = true
	end
	UPCoreUpdateCustomBalloonText(f, f.textstring:GetText())  
end

function UPCoreUpdateCustomBalloonText(f, text)	
	if f.chatBubble.font:GetText() == text then
		return nil
	end

	local minHeight = 20

	local minWidth = 50
	local maxWidth = 300
	f.chatBubble.fontMeasure:SetText(text)

	f.chatBubble.font:SetText(text)
	f.chatBubble.font:SetTextColor(f.textstring:GetTextColor())
	
	local maxOfMin = math.max(minWidth, f.chatBubble.fontMeasure:GetWidth())
	f.chatBubble.font:SetWidth(math.min(maxOfMin, maxWidth))
	
	f.chatBubble:SetWidth(f.chatBubble.font:GetWidth() + 48)
	f.chatBubble:SetHeight(math.max(f.chatBubble.font:GetHeight(), minHeight) + 32)
end

function UPCoreIsBalloon(f)
  if f:GetName() then return end
  if not f:GetRegions() then return end
  return f:GetRegions():GetTexture() == [[Interface\Tooltips\ChatBubble-Background]]
end

function UPCoreIsNameplate(frame)
	-- if frame:GetName() then
		-- return false
	-- end
	-- --local o = select(2, frame:GetRegions())
	-- local _, o = frame:GetRegions()
	-- return (o and o:GetObjectType() == "Texture" and o:GetTexture() == [[Interface\Tooltips\Nameplate-Border]])
	
	if frame:GetObjectType() ~= "Button" then return nil end
	local regions = frame:GetRegions()

	if not regions then return nil end
	if not regions.GetObjectType then return nil end
	if not regions.GetTexture then return nil end
	
	--if not frame.name then return nil end

	if regions:GetObjectType() ~= "Texture" then return nil end
	return regions:GetTexture() == "Interface\\Tooltips\\Nameplate-Border" or nil
end

-- function UPCoreGetNameplateByUnitId(unitId)
	-- local frames = {WorldFrame:GetChildren()} -- Pack them into a table
	-- local framesCount = table.getn(frames)
	-- for i = 1, framesCount do
		-- local f = frames[i]
		-- if f.kui and (f.kui.unitId == unitId) then
			-- return f.kui
		-- end
	-- end
	
	
	-- return nil
-- end

-- function UPCoreGetNameplateByName(name)
	-- local frames = {WorldFrame:GetChildren()} -- Pack them into a table
	-- local framesCount = table.getn(frames)
	-- for i = 1, framesCount do
		-- local f = frames[i]
		-- if f.kui and (f.kui.oldName:GetText() == name) then
			-- return f.kui
		-- end
	-- end
	
	-- return nil
-- end

-----------------------------------------------------------