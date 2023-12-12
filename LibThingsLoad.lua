--@curseforge-project-slug: libthingsload@
---------------------------------------------------------------
-- LibThingsLoad - Library for load quests, items and spells --
---------------------------------------------------------------
local MAJOR_VERSION, MINOR_VERSION = "LibThingsLoad-1.0", 2
local lib, oldminor = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
if not lib then return end


local type, next, tremove, setmetatable, C_Item, C_Spell = type, next, tremove, setmetatable, C_Item, C_Spell


if not lib._listener then
	lib._listener = CreateFrame("Frame")
	lib._listener:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
	lib._listener:RegisterEvent("QUEST_DATA_LOAD_RESULT")
	lib._listener:RegisterEvent("ITEM_DATA_LOAD_RESULT")
	lib._listener:RegisterEvent("SPELL_DATA_LOAD_RESULT")
	lib._listener.types = {
		quest = "quest",
		item = "item",
		spell = "spell",
	}
	lib._listener.accessors = {
		[lib._listener.types.quest] = C_QuestLog.RequestLoadQuestByID,
		[lib._listener.types.item] = C_Item.RequestLoadItemDataByID,
		[lib._listener.types.spell] = C_Spell.RequestLoadSpellData,
	}
	lib._listener[lib._listener.types.quest] = {}
	lib._listener[lib._listener.types.item] = {}
	lib._listener[lib._listener.types.spell] = {}
	lib._meta = {__index = {}}
end
local listener = lib._listener


function listener:QUEST_DATA_LOAD_RESULT(...)
	self:FireCallbacks(self.types.quest, ...)
end


function listener:ITEM_DATA_LOAD_RESULT(...)
	self:FireCallbacks(self.types.item, ...)
end


function listener:SPELL_DATA_LOAD_RESULT(...)
	self:FireCallbacks(self.types.spell, ...)
end


function listener:checkThen(p)
	local i, j = 0, 0
	for k, loadType in next, self.types do
		i = i + 1
		if not p[loadType] or p[loadType].count == p[loadType].total then j = j + 1 end
	end
	return i == j
end


function listener:FireCallbacks(loadType, id, success)
	local ps = self[loadType][id]
	if ps then
		local i = 1
		local p = ps[i]
		while p do
			local pt = p[loadType]

			if pt[id] == -1 then
				pt[id] = success
				pt.count = pt.count + 1

				if success then if p._thenForAll then p:_thenForAll(id, loadType) end
				elseif p._fail then p:_fail(id, loadType) end

				if pt.count == pt.total then
					if p._then and self:checkThen(p) then p:_then() end
					tremove(ps, i)
				else
					i = i + 1
				end
			else
				i = i + 1
			end

			p = ps[i]
		end
	end
end


function listener:loadID(loadType, id, p)
	self[loadType][id] = self[loadType][id] or {}
	self[loadType][id][#self[loadType][id] + 1] = p
	self.accessors[loadType](id)
end


function listener:checkQuests(p)
	for questID, status in next, p[self.types.quest] do
		if status == -1 then
			self:loadID(self.types.quest, questID, p)
		end
	end
end


function listener:checkItems(p)
	for itemID, status in next, p[self.types.item] do
		if status == -1 then
			local pt = p[self.types.item]

			if C_Item.DoesItemExistByID(itemID) then
				local isCached = C_Item.IsItemDataCachedByID(itemID)

				if isCached then
					pt[itemID] = isCached
					pt.count = pt.count + 1
				else
					self:loadID(self.types.item, itemID, p)
				end
			else
				pt[itemID] = false
				pt.count = pt.count + 1
			end
		end
	end
end


function listener:checkSpell(p)
	for spellID, status in next, p[self.types.spell] do
		if status == -1 then
			local pt = p[self.types.spell]

			if C_Spell.DoesSpellExist(spellID) then
				local isCached = C_Spell.IsSpellDataCached(spellID)

				if isCached then
					pt[spellID] = isCached
					pt.count = pt.count + 1
				else
					self:loadID(self.types.spell, spellID, p)
				end
			else
				pt[spellID] = false
				pt.count = pt.count + 1
			end
		end
	end
end


function listener:fill(loadType, p, ids, ...)
	local t = {}
	p[loadType] = t

	if type(ids) == "number" then ids = {ids, ...} end

	if type(ids) == "table" then
		t.count = 0
		t.total = #ids

		for i = 1, t.total do
			t[ids[i]] = -1
		end
	else
		error("Bad arguments (table of IDs or IDs expected)")
	end
end


---------------------------------------------
-- PROMISE METHODS
---------------------------------------------
local methods = lib._meta.__index


local function checkStatus(loadType, p, status, callback)
	if p[loadType] then
		for id, idStatus in next, p[loadType] do
			if idStatus == status then
				callback(p, id, loadType)
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
	for k, loadType in next, listener.types do
		checkStatus(loadType, self, true, callback)
	end
	return self:ThenForAll(callback)
end


function methods:Fail(callback)
	self._fail = callback
	return self
end


function methods:FailWithChecked(callback)
	for k, loadType in next, listener.types do
		checkStatus(loadType, self, false, callback)
	end
	return self:Fail(callback)
end


function methods:AddQuests(...)
	if not self[listener.types.quest] then
		listener:fill(listener.types.quest, self, ...)
		listener:checkQuests(self)
		return self
	else
		error("Quests table already exists")
	end
end


function methods:AddItems(...)
	if not self[listener.types.item] then
		listener:fill(listener.types.item, self, ...)
		listener:checkItems(self)
		return self
	else
		error("Items table already exists")
	end
end


function methods:AddSpells(...)
	if not self[listener.types.spell] then
		listener:fill(listener.types.spell, self, ...)
		listener:checkSpell(self)
		return self
	else
		error("Spells table already exists")
	end
end


function methods:IsQuestCached(questID)
	return self[listener.types.quest] and self[listener.types.quest][questID] == true
end


function methods:IsItemCached(itemID)
	return self[listener.types.item] and self[listener.types.item][itemID] == true
end


function methods:IsSpellCached(spellID)
	return self[listener.types.spell] and self[listener.types.spell][spellID] == true
end


---------------------------------------------
-- LIBRARY METHODS
---------------------------------------------
function lib:CreatePromise()
	return setmetatable({}, self._meta)
end


function lib:Quests(...)
	return self:CreatePromise():AddQuests(...)
end


function lib:Items(...)
	return self:CreatePromise():AddItems(...)
end


function lib:Spells(...)
	return self:CreatePromise():AddSpells(...)
end


function lib:Everythings(quests, items, spells)
	local p = self:CreatePromise()
	if quests then p:AddQuests(quests) end
	if items then p:AddItems(items) end
	if spells then p:AddSpells(spells) end
	return p
end