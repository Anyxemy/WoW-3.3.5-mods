-- =========================================================
--			LSW_dataCore.lua (Sirus 2026)  v0.1.0
-- =========================================================
---@region data

	---@class DataCore
	---@field Init fun(self: DataCore)
	---@field UpdateRdbSkills fun(self: DataCore) 0 Сканирование и обновление рецептов в базе
	---@field PrepareQueue fun(self: DataCore) 1 Создает очередь рецептов
	---@field Processor fun(self: DataCore) 2 Организует обработку очереди сканирования рецептов
	---@field GetScanner fun(self: DataCore) 3 для сканера тултипа
	---@field ScanStep fun(self: DataCore): string 4 сканер тултипа, вычленяет реагенты из строк
	---@field GetCost fun(self: DataCoreRdb): string возвращает строку с ценами
	---@field RdbFlush fun(self: DataCore) Очистка базы
	---@field ForceLoadDatabase fun(self: DataCore)	 сканирование рецептов в файлах профессий
	---@field Proc table	фрейм обработчика очереди
	---@field flush number       -- перезапись имеющихся данных
	---@field Queue table
	---@field CurrentIndex number
	---@field wdc number    -- WatchDogCounter
	---@field prof string -- текущая профессия
	---@field arl_initialised boolean
	LSW_DataCore = LSW_DataCore or {}     -- Создаем уникальный глобальный объект

	---@class RdbEntry
	---@field itemID number     ID предмета результата
	---@field reagents table < number, number > [itemID] = количество

	---@class MetaData
	---@field lastUpdate number   Время последнего обновления (UNIX)
	---@field autoSync boolean    Флаг автоматической синхронизации
	---@field Entries table < string, number>      Количество записей в базе по профессиям (key)

	---@class DataCoreRdb : { [number]: RdbEntry }
	---@field Meta MetaData

	---@type DataCoreRdb
	Rdb = Rdb or {}

	Rdb.Meta = Rdb.Meta or { lastUpdate = 0, autoSync = true }
	Rdb.Meta.Entries = Rdb.Meta.Entries or {}

	local DataCore = LSW_DataCore         -- Локальная ссылка для удобства внутри файла
	local wdcLim = 2        -- Watch Dog Counter
	LSW_DEBUG = false
	--local reagentsLoc = SPELL_REAGENTS:match("([^%s%p]+)")  -- Очищаем от всего, кроме букв (для русского и английского)
	local reagentsLoc = SPELL_REAGENTS:gsub("[|n]", "") -- Удаляет пробелы, знаки препинания и переносы
	local ARL = AckisRecipeList


---@endregion data -----------------------------------------------------------------------

local function dprint(...)
	if LSW_DEBUG then print("|cff00ffffLSW-CORE:|r", ...) end
end

function Rtest(t)
	dprint("  Rdb[3275].ItemID " .. tostring(Rdb[t].itemID))
end

function DataCore:RdbFlush()
	Rdb = {}
end

--- Выводит структуру таблицы в чат с учетом вложенности
---@param t table Таблица для парсинга
---@param maxDepth? number Максимальная глубина (по умолчанию 2)
---@param currentDepth? number Текущая глубина для рекурсии (внутренний параметр)
---@param name? string Название таблицы (опционально)
function DumpStructure(t, maxDepth, currentDepth, name)
	-- 1. Инициализация параметров
	local cDepth = currentDepth or 0
	local mDepth = maxDepth or 2
	local n = name or "ROOT"
	local indent = string.rep("  ", cDepth)
	-- 2. Проверка лимита (теперь точно число с числом)
	if cDepth > mDepth then
		print(indent .. "[" .. n .. "] = { ... }")
		return
	end
	print(indent .. "[" .. n .. "]")
	for k, v in pairs(t) do
		local keyStr = tostring(k)
		if type(v) == "table" then
			-- 3. ВАЖНО: передаем параметры в строгом порядке
			DumpStructure(v, mDepth, cDepth + 1, keyStr)
		else
			print(indent .. "  " .. keyStr .. " = " .. tostring(v))
		end
	end
end

--//-----------------------------------------------------------------------------

-- не используется  -- ПАРСЕР SKILLET
local function GetReagentsFromSkillet(recipeID)
	if not Skillet or not Skillet.stitch then return nil end
	-- На Сирусе Skillet использует item_id как ключ в строке
	local targetItemID = ARL:GetRecipeData(recipeID, "item_id")
	--dprint("   SkilletDB serching for item_id " .. tostring(targetItemID) .. " (recipe_id " .. tostring(recipeID) .. ")")
	-- Проходим по базе SkilletDB
	for server, serverData in pairs(SkilletDB.servers) do
		for charName, charData in pairs(serverData.recipes or {}) do
			for skillName, recipes in pairs(charData) do
				for _, recipeStr in pairs(recipes) do
					-- Используем родной декодер Skillet
					local s = Skillet.stitch:DecodeRecipe(recipeStr)
									if s and s.link then
						-- Извлекаем ID из декодированной ссылки
						local itemID = tonumber(s.link:match(":(%d+)"))
											if itemID == targetItemID then
							--dprint("   Found targetID - " .. itemID, server, charName, skillName)
							local result = {}
							-- Перебираем реагенты внутри объекта s
							for i = 1, #s do
								local reagent = s[i]
								local reagentID = tonumber(reagent.link:match("item:(%d+)"))
								--dprint("   #" .. i, reagent, reagentID)
								if reagentID then
									result[reagentID] = reagent.needed
									--dprint("   result ".. tostring(result))
								end
							end
							return result
						end
					end
				end
			end
		end
	end
end


--- ==========================================
---@region prices 2. ПОЛУЧЕНИЕ ЦЕНЫ
--- ==========================================

--- получение цен предмета и реагентов по recipe_id (запрос из arl)
--- @param self number skill_id
--- @param recipe_id number skill_id
--- @return string rStr возврат форматированной строки цен
function DataCore:GetCost(recipe_id)
	local rID = recipe_id
	if not rID then dprint("No recipeID for GetCost") return "---" end
	local cost, value, price, hilight = 0, 0, 0, false
	local sCost, sValue, iName, rName, rStr = "-", "-", "no item name", "no reagent name", "---"
	local s
	local sName, _ = GetSpellInfo(rID) or "No Skill name", nil
	dprint("--- Рецепт:  " .. sName .. " --- id " .. rID)

	-- 1. VALUE - ЦЕНА РЕЗУЛЬТАТА УМЕНИЯ - ПРЕДМЕТ ('a' - auction 'v' - vendor)

	-- LSW:SkillCost LSW:SkillValue НЕ ПОКАЗЫВАЮТ НЕИЗВЕСТНЫЕ РЕЦЕПТЫ!
	local itemID = Rdb[rID] and Rdb[rID].itemID or ARL:GetRecipeData(rID, "item_id")
	iName, _ = GetItemInfo(itemID) or "Name not found", ""

	value, s = LSW:GetSkillValue(rID) or 0, ''
	dprint(iName .. "  GetSkillValue - " .. tostring(value), s .. "   id ".. tostring(itemID))

	if value <= 0 and itemID and LSW then
		value, s = LSW:GetItemCost(itemID) or 0, ""
		dprint(iName .. "  GetItemCost - " .. tostring(value), s .. "   id ".. tostring(itemID))
	end

	-- 2. COST - ЦЕНА ИСПОЛЬЗОВАНИЯ УМЕНИЯ - РЕАГЕНТЫ, СЕБЕСТОИМОСТЬ
	cost = LSW:GetSkillCost(rID) or 0

	if cost <= 0 and LSW and Rdb and Rdb[rID] and Rdb[rID].reagents then
		for k, v in pairs(Rdb[rID].reagents) do     -- берем реагенты из базы
			price = (LSW:GetItemCost(k) or 0)
			cost = cost + price * v        -- складываем их цены
			rName, _ = GetItemInfo(k) or "Reagent name not found", ""
			dprint("  " .. rName .. " - " .. cost .. "   id ".. k)
		end
	else
		if cost > 0 then dprint(sName .. "  GetSkillCost - " .. cost .. "   id ".. rID) end
	end

	if value > cost then hilight = true end
	sValue = LSW:FormatMoney(value, hilight) or "-"
	sCost = LSW:FormatMoney(cost, hilight) or "-"
	rStr = string.format("%-4s%-1s %-4s", sValue, s, sCost)
	return rStr
end

---@endregion prices

-- ==========================================
---@region Update Rdb  3. ОБНОВЛЕНИЕ И НАПОЛНЕНИЕ БАЗЫ
-- ==========================================


function DataCore:ForceLoadDatabase(profName)
    -- profName должен быть "FirstAid", "Alchemy" и т.д.
    local initFunc = "Init" .. profName
    
    if AckisRecipeList[initFunc] then
        -- 1. Вызываем функцию. Она "прочитает" файл за нас.
        local count = AckisRecipeList[initFunc](AckisRecipeList)
        
        -- 2. Теперь данные в памяти. Проходим по ним:
        for spellID, recipe in pairs(AckisRecipeList.recipe_list) do
            -- Проверяем, что этот рецепт из той базы, которую мы только что загрузили
            -- (ARL сваливает всё в одну кучу, поэтому фильтруем)
            local itemID = recipe.recipe_item
            if itemID and not Rdb[itemID] then
                -- Записываем в нашу Rdb
                Rdb[itemID] = {}
            end
        end
        print("Загружено из файла " .. profName .. ".lua: " .. count .. " рецептов.")
    end
end



-- Сканируем базу рецептов AckisRecipeList, из фрейма, все рецепты выбранной профессии
-- через тултип в котором есть все реагенты. "Frame" Processor, PrepareQueue(), ScanStep(), GetScanner()
-- делается один раз на каждую профессию, далее не требуется

---Обновление базы умений при открытом окне AckisRecipeList
function DataCore:UpdateRdbSkills()
--	DataCore.flush = 1
	DataCore.Queue = {}
	DataCore.CurrentIndex = 1
	DataCore.wdc = 0
	DataCore.prof = ""
	DataCore:PrepareQueue()		-- подготовка очереди рецептов
	DataCore:Processor()		-- запуск обработчика очереди (фрейм)
	DataCore.Proc:Show()
end

--- создание очереди рецептов, данных о которых нет в базе
function DataCore:PrepareQueue()
	if not ARL or not ARL.Frame then dprint("Ошибка! ARL еще не загружен.|r") return end
	local entrCount = 0
	local entries = ARL.Frame.list_frame.entries   -- сразу копируем список рецептов ARL и работаем с ним
	for i = 1, #entries do if entries[i].type == "header" then entrCount = entrCount + 1 end end
	dprint("кол-во умений в списке АРЛ: " .. entrCount .. "   строк всего " .. #entries)
	local prof = ARL:GetRecipeData(entries[1].recipe_id, "profession")    -- профессия
	DataCore.prof = prof

	-- обнуляем кол-во записей в базе для этой профессии, если надо
	if prof and not Rdb.Meta.Entries[prof] or DataCore.flush then Rdb.Meta.Entries[prof] = 0 end 
	self.Queue = {}    -- Очищаем очередь перед заполнением
	local count_new, count_total = 0, 0
	-- сверяем количество рецептов в списке АРЛ с соответствующим значением в базе
	local str = string.format("%s рецептов в Rdb %d   в ARL %d", prof, Rdb.Meta.Entries[prof], #entries)
	if Rdb.Meta.Entries[prof] > #entries and not DataCore.flush then
		print(str .. " Обновление не требуется") return
	end
	print(str .. " создание очереди")

	-- Проходим по текущим записям ARL
	for i = 1, #entries do
		local spellID = entries[i].recipe_id

		-- Если spellID нет в базе или принудительное обновление
		if spellID and entries[i].type == "header" and (not Rdb[spellID] or DataCore.flush) then
			Rdb[spellID].itemID = nil Rdb[spellID].reagents = {}
			table.insert(self.Queue, spellID)
			count_total = count_total + 1
			count_new = count_new + 1
			--dprint("Queues " .. #self.Queue, "   New #" .. tostring(count_new))
		end
	end

	dprint(string.format("Очередь готова. Всего в списке %d  (новых %d))", count_total, count_new))
end

-- Функция для получения или создания сканера
function DataCore:GetScanner()
	local name = "DataCoreScannerTooltip"
	if not _G[name] then
		local scanner = CreateFrame("GameTooltip", name, nil, "GameTooltipTemplate")
		scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
	end
	--dprint("Scanner " .. tostring(_G[name]))
	return _G[name]
end

-- 2. Обработка "Шага" (Step Logic) Это сердце сканера. Функция проверяет один рецепт.
-- Если всё ОK — возвращает true (можно идти дальше). Если сервер выдал nil — возвращает false (стоим и ждем).
function DataCore:ScanStep()
	local spellID = self.Queue[self.CurrentIndex]
	if not spellID then return "COMPLETED" end
	sSpell, _ = GetSpellInfo(spellID) or "Unknown Spell", ""
	dprint("Scan Queue " .. tostring(self.CurrentIndex) .. sSpell .. "  id " .. tostring(spellID))

	-- Попытка получить данные
	local link = GetSpellLink(spellID)
	--dprint("  GetSpellLink(" .. spellID .. ") = " .. tostring(link))
	if not link then dprint("SCAN WAIT") return "WAIT" end -- Сервер еще не отдал линк спелла

	-- тултип умения
	local scanner = self:GetScanner()   -- Ваш скрытый тултип
	if self.wdc == 0 then               -- если умение новое, активируем тултип
		scanner:SetHyperlink(link)
	end

	-- Парсинг строк тултипа на предмет реагентов
	tooltip = _G["DataCoreScannerTooltip"]
	lines = tooltip:NumLines()
	for i = 1, lines do
		_, line = _G["DataCoreScannerTooltipTextLeft"..i]:GetText():match("("..reagentsLoc..")(.*)")
		if line then
			Rdb[spellID].reagents = {} Rdb[spellID].itemID = nil
			dprint(Rdb.Meta.Entries[DataCore.prof])
			Rdb.Meta.Entries[DataCore.prof] = Rdb.Meta.Entries[DataCore.prof] + 1
			Rdb[spellID].itemID = ARL:GetRecipeData(spellID, "item_id")
			--dprint(string.format("str %d  New Item: %s", i, GetItemInfo(Rdb[spellID].itemID)))
			-- Чистим мусор: цвета и невидимые переносы [N]
			line = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%c", " "):gsub("|n", "")
			dprint("1 " .. line)

			for reag in line:gmatch("[^,]+") do
				dprint("2 " .. reag)

				reag = reag:trim()
				-- 1. Сначала пробуем вытащить имя и число из скобок: "Имя (2)"
				local name, count = reag:match("^(.-)%s*%(%d+%)")
				count = reag:match("%((%d+)%)") or 1

				-- 2. Если скобок не было, значит это "Имя" (кол-во 1) или "Имя 2"
				if not name then
					name = reag
				end
				name = name:trim()
				if not name then dprint("reagent name not found (str 320)") break end

				dprint("name " .. name .. "  count " .. tostring(count))
				-- Теперь GetItemInfo точно получит "Сребролист", а не "Сребролист (2)"
				local nazv, itemLink = GetItemInfo(name)-- or "no name", nil
				dprint("324 ", tostring(nazv), "   link ", tostring(itemLink), "   кол-во ", tostring(count))

				if itemLink then
					local itemID = tonumber(itemLink:match("item:(%d+)"))
					dprint("reagent " .. tostring(itemID))
					Rdb[spellID].reagents[itemID] = tonumber(count) or 1
					local col = Rdb[spellID].reagents[itemID] or 0
					dprint("Rdb itemID col-vo ", col)
					dprint(tostring(nazv) .. " (Rdb) id " .. tostring(itemID) .. "   count " .. tostring(Rdb[spellID].reagents[itemID]))

					self.wdc = 100 -- Флаг успеха
				else --dprint("No itemLink " .. name) return end
					if self.wdc >= wdcLim then
						self.wdc = 0
						dprint("  SCAN FALED")
						return "NEXT"
					else
						self.wdc = self.wdc + 1
						dprint("WDC REAGENT WAIT " .. self.wdc)
						return "WAIT"  -- Если предмета нет в кэше, запрашиваем и ждем тик
					end
				end
			end
		end
	end
	--dprint("  New Item: " .. tostring(Rdb[spellID].itemID))

	-- 3. Несколько попыток если данные не получены
	if self.wdc >= wdcLim then       -- WatchDogCounter
		if self.wdc < 100 then dprint("  SCAN FALED") else dprint("  SCAN SUCCESS") end
		self.wdc = 0
		return "NEXT"
	else
		self.wdc = self.wdc + 1
		dprint("WDC WAIT " .. self.wdc)
		return "WAIT"
	end
end

function DataCore:Processor()
	-- Этот Невидимый Фрейм-пульс будет обрабатывать логику ожидания.
	-- Если сервер «молчит» (вернул nil), контроллер просто подождет следующего кадра, не блокируя игру.
	local name = "LSW_DataCore_Processor"
	if not _G[name] then
		DataCore.Proc = CreateFrame("Frame", name) end
	-- Создаем визуальную строку на фрейме Processor
	DataCore.Proc.text = DataCore.Proc:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	DataCore.Proc.text:SetPoint("CENTER", UIParent, "CENTER", 0, 150) -- Центр экрана

	DataCore.Proc:Hide() -- По умолчанию выключен
	DataCore.Proc:SetScript("OnUpdate", function(self, elapsed)
		local spellID = DataCore.Queue[DataCore.CurrentIndex] or "DONE"
		self.text:SetText(string.format("Scan: %d/%d | ID: %s", DataCore.CurrentIndex, #DataCore.Queue, tostring(spellID)))
		-- Ограничитель скорости (раз в 0.05 сек), чтобы не спамить в пустую
		self.timer = (self.timer or 0) + elapsed
		if self.timer < 0.02 then return end
		self.timer = 0

		local status = DataCore:ScanStep()
		dprint("(processor) ScanStep status " .. tostring(status))

		if status == "NEXT" then
			DataCore.CurrentIndex = DataCore.CurrentIndex + 1
			-- Чек-поинт каждые 10 рецептов
			if DataCore.CurrentIndex % 10 == 0 then
				print(string.format("|cff00ff00[DataCore]:|r Прогресс %d/%d", tostring(DataCore.CurrentIndex), #DataCore.Queue))
			end

		elseif status == "COMPLETED" then
			print("[DataCore]:|r Скан всей базы завершен успешно!")
			self:Hide()
		elseif status == "WAIT" then
			-- Просто пропускаем тик, ждем ответа сервера
		end
	end)
end
---@endregion Update Rdb ----------------------------------------------------------

-- ==========================================
-- 3. СОБЫТИЯ И ХУКИ
-- ==========================================

-- определение необходимости пополнения и запуск обновления базы
function DataCore:OpenARL()
	if not ARL or not ARL.Frame then dprint("Ошибка! ARL еще не загружен.|r") return end
	local entrCount = 0
	local entries = ARL.Frame.list_frame.entries        -- список рецептов ARL
	for i = 1, #entries do if entries[i].type == "header" then entrCount = entrCount + 1 end end
	dprint("кол-во умений в списке АРЛ: " .. entrCount .. "   строк всего " .. #entries)
	local prof = ARL:GetRecipeData(entries[1].recipe_id, "profession") or ""   -- профессия
	DataCore.prof = prof or ""

	-- Сравниваем кол-во записей в базе для этой профессии
	if not Rdb.Meta and not Rdb.Meta.Entries then return end
	local profRdb = Rdb.Meta.Entries[prof] or 0
	dprint(prof, tostring(entrCount), "/", tostring(entries), "   Rdb ", tostring(profRdb))
	if entrCount > profRdb then
		print("ОБНОВЛЕНИЕ БАЗЫ ", prof, entrCount, "/", profRdb)
		self:UpdateRdbSkills()
	else
		print("Обновление не требуется", prof, entrCount, "/", profRdb)
	end
end

-- ==========================================
--		ИНИЦИАЛИЗАЦИЯ И ИНТЕРФЕЙС
-- ==========================================

function DataCore:Init()
	Rdb = Rdb or {}
	Rdb.Meta = Rdb.Meta or {}
	Rdb.Meta = Rdb.Meta or { lastUpdate = 0, autoSync = true }
	Rdb.Meta.Entries = Rdb.Meta.Entries or {}
end

-- Инициализация при загрузке
local startupFrame = CreateFrame("Frame")
startupFrame:RegisterEvent("PLAYER_LOGIN")
startupFrame:SetScript("OnEvent", function()
	LSW_DataCore:Init()
--	Asup:Init()
end)
