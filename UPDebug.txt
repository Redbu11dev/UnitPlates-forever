UPDebugMissingSpells = UPDebugMissingSpells or {}

local function UPDebugInitUPDebugMissingSpellsEntry(keyName)
	if (not UPDebugMissingSpells[keyName]) then
        UPDebugMissingSpells[keyName] = {
			lastSeen = nil -- Useful if you want to clear old data later
        }
    end
end

function UPDebugStoreUPDebugMissingSpellsEntry(spellName, rankNumber)
	local keyName = tostring(spellName).." Rank "..tostring(rankNumber)
    if keyName then
		if not UPDebugMissingSpells[keyName] then 
			UPDebugInitUPDebugMissingSpellsEntry(keyName)
		end
		UPDebugMissingSpells[keyName].lastSeen = date("%m/%d/%y %H:%M:%S") -- Useful if you want to clear old data later
    end
end

function UPDebugClearUPDebugMissingSpells()
	UPDebugMissingSpells = {}
end