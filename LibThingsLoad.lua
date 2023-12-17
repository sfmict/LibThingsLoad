--@curseforge-project-slug: libthingsload@
---------------------------------------------------------------
-- LibThingsLoad - Library for load quests, items and spells --
---------------------------------------------------------------
local MAJOR_VERSION, MINOR_VERSION = "LibThingsLoad-1.0", 5
local lib, oldminor = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
if not lib then return end


local type, next, xpcall, setmetatable, CallErrorHandler, C_Item, C_Spell = type, next, xpcall, setmetatable, CallErrorHandler, C_Item, C_Spell
local DoesItemExistByID, IsItemDataCachedByID, GetItemInfo, ITEM_QUALITY_COLORS, GetDetailedItemLevelInfo, GetItemInfoInstant = C_Item.DoesItemExistByID, C_Item.IsItemDataCachedByID, GetItemInfo, ITEM_QUALITY_COLORS, GetDetailedItemLevelInfo, GetItemInfoInstant
local DoesSpellExist, IsSpellDataCached, GetSpellInfo, GetSpellSubtext, GetSpellTexture, GetSpellDescription = C_Spell.DoesSpellExist, C_Spell.IsSpellDataCached, GetSpellInfo, GetSpellSubtext, GetSpellTexture, GetSpellDescription


if not lib._listener then
	lib._listener = CreateFrame("Frame")
	lib._listener:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
	lib._listener:RegisterEvent("ITEM_DATA_LOAD_RESULT")
	lib._listener:RegisterEvent("SPELL_DATA_LOAD_RESULT")
	lib._listener.types = {
		item = "item",
		spell = "spell",
	}
	lib._listener.accessors = {
		[lib._listener.types.item] = C_Item.RequestLoadItemDataByID,
		[lib._listener.types.spell] = C_Spell.RequestLoadSpellData,
	}
	lib._listener[lib._listener.types.item] = {}
	lib._listener[lib._listener.types.spell] = {}
	lib._meta = {__index = {}}

	if C_EventUtils.IsEventValid("QUEST_DATA_LOAD_RESULT") then
		lib._listener:RegisterEvent("QUEST_DATA_LOAD_RESULT")
		lib._listener.types.quest = "quest"
		lib._listener.accessors[lib._listener.types.quest] = C_QuestLog.RequestLoadQuestByID
		lib._listener[lib._listener.types.quest] = {}
	end
end
local listener = lib._listener


function listener:QUEST_DATA_LOAD_RESULT(...)
	self:fireCallbacks(self.types.quest, ...)
end


function listener:ITEM_DATA_LOAD_RESULT(...)
	self:fireCallbacks(self.types.item, ...)
end


function listener:SPELL_DATA_LOAD_RESULT(...)
	self:fireCallbacks(self.types.spell, ...)
end


function listener:checkThen(p)
	local i, j = 0, 0
	for k, loadType in next, self.types do
		i = i + 1
		if not p[loadType] or p[loadType].count == p[loadType].total then j = j + 1 end
	end
	return i == j
end


function listener:firePromiseCallbacks(loadType, p, id, success)
	local pt = p[loadType]

	if pt[id] == -1 then
		pt[id] = success
		pt.count = pt.count + 1

		if success then if p._thenForAll then p:_thenForAll(id, loadType) end
		elseif p._fail then p:_fail(id, loadType) end
		if pt.count == pt.total and p._then and self:checkThen(p) then p:_then() end
	end
end


function listener:fireCallbacks(loadType, id, success)
	local ps = self[loadType][id]
	if ps then
		self[loadType][id] = nil

		for i = 1, #ps do
			xpcall(self.firePromiseCallbacks, CallErrorHandler, self, loadType, ps[i], id, success)
		end
	end
end


function listener:loadID(loadType, id, p)
	self[loadType][id] = self[loadType][id] or {}
	local index = #self[loadType][id] + 1
	self[loadType][id][index] = p
	if index == 1 then self.accessors[loadType](id) end
end


function listener:fill(loadType, p, ids, ...)
	local t = p[loadType] or {}
	p[loadType] = t

	if type(ids) == "number" then ids = {ids, ...} end

	if type(ids) == "table" then
		t.count = t.count or 0
		t.total = t.total or 0

		for i = 1, #ids do
			if t[ids[i]] == nil then
				t[ids[i]] = -2
				t.total = t.total + 1
			end
		end

		return ids, t
	else
		error("Bad arguments (table of IDs or IDs expected)")
	end
end


---------------------------------------------
-- PROMISE METHODS
---------------------------------------------
local methods = lib._meta.__index


local function checkStatus(p, status, callback)
	for k, loadType in next, listener.types do
		if p[loadType] then
			for id, idStatus in next, p[loadType] do
				if idStatus == status then
					callback(p, id, loadType)
				end
			end
		end
	end
end


function methods:Then(callback)
	if listener:checkThen(self) then
		callback(self)
	else
		self._then = callback
	end
	return self
end


function methods:ThenForAll(callback)
	self._thenForAll = callback
	return self
end


function methods:ThenForAllWithCached(callback)
	checkStatus(self, true, callback)
	return self:ThenForAll(callback)
end


function methods:Fail(callback)
	self._fail = callback
	return self
end


function methods:FailWithChecked(callback)
	checkStatus(self, false, callback)
	return self:Fail(callback)
end


function methods:AddItems(...)
	local loadType = listener.types.item
	local t, pt = listener:fill(loadType, self, ...)

	for i = 1, #t do
		local itemID = t[i]

		if pt[itemID] == -2 then
			if DoesItemExistByID(itemID) then
				if IsItemDataCachedByID(itemID) then
					pt[itemID] = true
					pt.count = pt.count + 1
				else
					pt[itemID] = -1
					listener:loadID(loadType, itemID, self)
				end
			else
				pt[itemID] = false
				pt.count = pt.count + 1
			end
		end
	end

	return self
end


function methods:AddSpells(...)
	local loadType = listener.types.spell
	local t, pt = listener:fill(loadType, self, ...)

	for i = 1, #t do
		local spellID = t[i]

		if pt[spellID] == -2 then
			if DoesSpellExist(spellID) then
				if IsSpellDataCached(spellID) then
					pt[spellID] = true
					pt.count = pt.count + 1
				else
					pt[spellID] = -1
					listener:loadID(loadType, spellID, self)
				end
			else
				pt[spellID] = false
				pt.count = pt.count + 1
			end
		end
	end

	return self
end


if listener.types.quest then
	function methods:AddQuests(...)
		local loadType = listener.types.quest
		local t, pt = listener:fill(loadType, self, ...)

		for i = 1, #t do
			local questID = t[i]

			if pt[questID] == -2 then
				pt[questID] = -1
				listener:loadID(loadType, questID, self)
			end
		end

		return self
	end
end


function methods:IsItemCached(itemID)
	return (self[listener.types.item] and self[listener.types.item][itemID]) == true
end


function methods:IsSpellCached(spellID)
	return (self[listener.types.spell] and self[listener.types.spell][spellID]) == true
end


if listener.types.quest then
	function methods:IsQuestCached(questID)
		return (self[listener.types.quest] and self[listener.types.quest][questID]) == true
	end
end


---------------------------------------------
-- LIBRARY METHODS
---------------------------------------------
function lib:CreatePromise()
	return setmetatable({}, self._meta)
end


function lib:Items(...)
	return self:CreatePromise():AddItems(...)
end


function lib:Spells(...)
	return self:CreatePromise():AddSpells(...)
end


if listener.types.quest then
	function lib:Quests(...)
		return self:CreatePromise():AddQuests(...)
	end
end


function lib:Everythings(items, spells, quests)
	local p = self:CreatePromise()
	if items then p:AddItems(items) end
	if spells then p:AddSpells(spells) end
	if quests and p.AddQuests then p:AddQuests(quests) end
	return p
end