--@curseforge-project-slug: libthingsload@
---------------------------------------------------------------
-- LibThingsLoad - Library for load quests, items and spells --
---------------------------------------------------------------
local MAJOR_VERSION, MINOR_VERSION = "LibThingsLoad-1.0", 11
local lib, oldminor = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
if not lib then return end


local type, next, xpcall, setmetatable, CallErrorHandler, C_Item, C_Spell = type, next, xpcall, setmetatable, CallErrorHandler, C_Item, C_Spell
local DoesItemExistByID, IsItemDataCachedByID, ITEM_QUALITY_COLORS = C_Item.DoesItemExistByID, C_Item.IsItemDataCachedByID, ITEM_QUALITY_COLORS
local GetItemInfo = GetItemInfo or C_Item.GetItemInfo
local GetDetailedItemLevelInfo = GetDetailedItemLevelInfo or C_Item.GetDetailedItemLevelInfo
local GetItemInfoInstant = GetItemInfoInstant or C_Item.GetItemInfoInstant
local DoesSpellExist, IsSpellDataCached = C_Spell.DoesSpellExist, C_Spell.IsSpellDataCached
local GetSpellSubtext = GetSpellSubtext or C_Spell.GetSpellSubtext
local GetSpellLink = GetSpellLink or C_Spell.GetSpellLink
local GetSpellTexture = GetSpellTexture or C_Spell.GetSpellTexture
local GetSpellDescription = GetSpellDescription or C_Spell.GetSpellDescription


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


function listener:ITEM_DATA_LOAD_RESULT(...)
	self:fireCallbacks(self.types.item, ...)
end


function listener:SPELL_DATA_LOAD_RESULT(...)
	self:fireCallbacks(self.types.spell, ...)
end


if listener.types.quest then
	function listener:QUEST_DATA_LOAD_RESULT(...)
		self:fireCallbacks(self.types.quest, ...)
	end
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


function listener:fill(loadType, p, doesExist, isCached, t, ...)
	if type(t) == "number" then t = {t, ...} end

	if type(t) == "table" then
		local pt = p[loadType] or {}
		p[loadType] = pt

		pt.count = pt.count or 0
		pt.total = pt.total or 0

		if doesExist then
			for i = 1, #t do
				local id = t[i]

				if pt[id] == nil then
					if doesExist(id) then
						if isCached(id) then
							pt[id] = true
							pt.count = pt.count + 1
						else
							pt[id] = -1
							self:loadID(loadType, id, p)
						end
					else
						pt[id] = false
						pt.count = pt.count + 1
					end
					pt.total = pt.total + 1
				end
			end
		else
			for i = 1, #t do
				local id = t[i]

				if pt[id] == nil then
					pt[id] = -1
					self:loadID(loadType, id, p)
					pt.total = pt.total + 1
				end
			end
		end
	else
		error("Bad arguments (table of IDs or IDs expected)")
	end
end


function listener:fillByKey(loadType, p, doesExist, isCached, t)
	if type(t) == "table" then
		local pt = p[loadType] or {}
		p[loadType] = pt

		pt.count = pt.count or 0
		pt.total = pt.total or 0

		if doesExist then
			for id in next, t do
				if pt[id] == nil then
					if doesExist(id) then
						if isCached(id) then
							pt[id] = true
							pt.count = pt.count + 1
						else
							pt[id] = -1
							self:loadID(loadType, id, p)
						end
					else
						pt[id] = false
						pt.count = pt.count + 1
					end
					pt.total = pt.total + 1
				end
			end
		else
			for id in next, t do
				if pt[id] == nil then
					pt[id] = -1
					self:loadID(loadType, id, p)
					pt.total = pt.total + 1
				end
			end
		end
	else
		error("Bad arguments (table expected)")
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
	self._then = callback
	if listener:checkThen(self) then
		self:_then()
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
	listener:fill(listener.types.item, self, DoesItemExistByID, IsItemDataCachedByID, ...)
	return self
end


function methods:AddItemsByKey(t)
	listener:fillByKey(listener.types.item, self, DoesItemExistByID, IsItemDataCachedByID, t)
	return self
end


function methods:AddSpells(...)
	listener:fill(listener.types.spell, self, DoesSpellExist, IsSpellDataCached, ...)
	return self
end


function methods:AddSpellsByKey(t)
	listener:fillByKey(listener.types.spell, self, DoesSpellExist, IsSpellDataCached, t)
	return self
end


if listener.types.quest then
	function methods:AddQuests(...)
		listener:fill(listener.types.quest, self, nil, nil, ...)
		return self
	end


	function methods:AddQuestsByKey(t)
		listener:fillByKey(listener.types.quest, self, nil, nil, t)
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


function lib:ItemsByKey(t)
	return self:CreatePromise():AddItemsByKey(t)
end


function lib:Spells(...)
	return self:CreatePromise():AddSpells(...)
end


function lib:SpellsByKey(t)
	return self:CreatePromise():AddSpellsByKey(t)
end


if listener.types.quest then
	function lib:Quests(...)
		return self:CreatePromise():AddQuests(...)
	end


	function lib:QuestsByKey(t)
		return self:CreatePromise():AddQuestsByKey(t)
	end
end


function lib:Everythings(items, spells, quests)
	local p = self:CreatePromise()
	if items then p:AddItems(items) end
	if spells then p:AddSpells(spells) end
	if quests and p.AddQuests then p:AddQuests(quests) end
	return p
end


function lib:EverythingsByKey(items, spells, quests)
	local p = self:CreatePromise()
	if items then p:AddItemsByKey(items) end
	if spells then p:AddSpellsByKey(spells) end
	if quests and p.AddQuestsByKey then p:AddQuestsByKey(quests) end
	return p
end


-- ITEM UTILS
function lib:GetItemInfo(itemID)
	return GetItemInfo(itemID)
end


function lib:GetItemIcon(itemID)
	return C_Item.GetItemIconByID(itemID)
end


function lib:GetItemName(itemID)
	return C_Item.GetItemNameByID(itemID)
end


function lib:GetItemLink(itemID)
	local _, link = self:GetItemInfo(itemID)
	return link
end


function lib:GetItemQuality(itemID)
	return C_Item.GetItemQualityByID(itemID)
end


function lib:GetItemQualityColor(itemID)
	return ITEM_QUALITY_COLORS[self:GetItemQuality(itemID)]
end


function lib:GetItemQualityColorRGB(itemID)
	return self:GetItemQualityColor(itemID).color:GetRGB()
end


function lib:GetItemCurrentLevel(itemID)
	return GetDetailedItemLevelInfo(itemID)
end


function lib:GetItemMaxStackSize(itemID)
	return C_Item.GetItemMaxStackSizeByID(itemID)
end


function lib:IsItemStackable(itemID)
	local maxStackSize = self:GetItemMaxStackSize(itemID)
	return maxStackSize and maxStackSize > 1
end


function lib:GetItemInventoryType(itemID)
	return C_Item.GetItemInventoryTypeByID(itemID)
end


function lib:GetItemInventoryTypeName(itemID)
	local _,_,_, itemEquipLoc = GetItemInfoInstant(itemID)
	return itemEquipLoc
end


function lib:IsItemDataCached(itemID)
	return IsItemDataCachedByID(itemID)
end


-- SPELL UTILS
if C_Spell.GetSpellInfo then
	function lib:GetSpellInfo(spellID)
		return C_Spell.GetSpellInfo(spellID)
	end
else
	local GetSpellinfo = GetSpellinfo
	function lib:GetSpellInfo(spellID)
		local name, _, icon, castTime, minRange, maxRange, spellID, originalIcon = GetSpellInfo(spellID)
		return {
			name = name,
			iconID = icon,
			originalIconID = originalIcon,
			castTime = castTime,
			minRange = minRange,
			maxRange = maxRange,
			spellID = spellID,
		}
	end
end


if C_Spell.GetSpellCooldown then
	function lib:GetSpellCooldown(spellID)
		return C_Spell.GetSpellCooldown(spellID)
	end
else
	local GetSpellCooldown = GetSpellCooldown
	function lib:GetSpellCooldown(spellID)
		local start, duration, enabled, modRate = GetSpellCooldown(spellID)
		return {
			startTime = start,
			duration = duration,
			isEnabled = enabled == 0,
			modRate = modRate,
		}
	end
end


if C_Spell.GetSpellName then
	function lib:GetSpellName(spellID)
		return C_Spell.GetSpellName(spellID)
	end
else
	function lib:GetSpellName(spellID)
		return self:GetSpellInfo(spellID).name
	end
end


function lib:GetSpellSubtext(spellID)
	return GetSpellSubtext(spellID)
end


function lib:GetSpellFullName(spellID)
	local name = self:GetSpellName(spellID)
	local subText = self:GetSpellSubtext(spellID)
	return subText and #subText > 0 and name.."("..subText..")" or name
end


function lib:GetSpellLink(...)
	return GetSpellLink(...)
end


function lib:GetSpellTexture(spellID)
	return GetSpellTexture(spellID)
end


function lib:GetSpellDescription(spellID)
	return GetSpellDescription(spellID)
end


function lib:IsSpellDataCached(spellID)
	return IsSpellDataCached(spellID)
end