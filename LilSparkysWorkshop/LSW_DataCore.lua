-- ==============================================
do  -- 1. HEADER
    -- ==========================================
    -- LSW_dataCore.lua (Sirus 2026)  v0.0.1

    ---@class DataCore
    ---@field Init fun(self: DataCore)
    ---@field InitInterface fun(self: DataCore) Создает кнопку и чекер в ARL
    ---@field PrepareQueue fun(self: DataCore)
    ---@field GetScanner fun(self: DataCore)
    ---@field ScanStep fun(self: DataCore)
    ---@field Processor fun(self: DataCore) Организует обработку очереди сканирования рецептов
    ---@field RdbFlush fun(self: DataCore) Очистка базы
    ---@field UpdateRdbSkills fun(self: DataCore) Сканирование и обновление рецептов в базе
    ---@field UpdateRdbPrices fun(self: DataCore) Обновление цен в базе
    ---@field flush boolean       -- перезапись имеющихся данных
    ---@field Queue table
    ---@field CurrentIndex number
    ---@field wdc number    -- WatchDogCounter
    ---@field prof string -- текущая профессия
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
end -- ===== header =========================

local DataCore = LSW_DataCore         -- Локальная ссылка для удобства внутри файла
local wdcLim = 2        -- Watch Dog Counter
local LSW_DEBUG = false
--local reagentsLoc = SPELL_REAGENTS:match("([^%s%p]+)")  -- Очищаем от всего, кроме букв (для русского и английского)
local reagentsLoc = SPELL_REAGENTS:gsub("[|n]", "") -- Удаляет пробелы, знаки препинания и переносы
local ARL = AckisRecipeList

-------------------------------------------------------------------------

local function dprint(...)
    if LSW_DEBUG then print("|cff00ffffLSW-CORE:|r", ...) end
end

function Rtest(t)
    dprint("  Rdb[3275].ItemID " .. tostring(Rdb[t].itemID))
end

function DataCore:Rdbflush()
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

-- не используется
local function GetCostFromRdb(recipeID)
    local itemID = ARL:GetRecipeData(recipeID, "item_id")
    local reagents = itemID and Rdb[itemID] or {}
    --    dprint("   GetRdb " .. type(reagents), itemID, Rdb[itemID])
    if not reagents then return 0 end
    local total = 0
    for i, count in pairs(reagents) do
        local price = LSW:GetItemCost(i) or 0
        total = total + (price * count)
    end
    return total
end


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
--#region Prices 2. ПОЛУЧЕНИЕ ЦЕНЫ
--- ==========================================

--- получение цен предмета и реагентов по recipe_id (запрос из arl)
--- @param recipe_id number skill_id
--- @return string rStr возврат форматированной строки цен
function GetCost(recipe_id)
    local rID = recipe_id
    if not rID then dprint("No recipeID for GetCost") return "---" end
    local cost, value, price, hilight = 0, 0, 0, false
    local sCost, sValue, iName, rName, rStr = "-", "-", "no item name", "no reagent name", "---"
    local s
    local sName, _ = GetSpellInfo(rID) or "No Skill name"
    dprint("--- Рецепт:  " .. sName .. " --- id " .. rID)

    -- 1. VALUE - ЦЕНА РЕЗУЛЬТАТА УМЕНИЯ - ПРЕДМЕТ ('a' - auction 'v' - vendor)

    -- LSW:SkillCost LSW:SkillValue НЕ ПОКАЗЫВАЮТ НЕИЗВЕСТНЫЕ РЕЦЕПТЫ!
    local itemID = Rdb[rID] and Rdb[rID].itemID or ARL:GetRecipeData(rID, "item_id")
    iName, _ = GetItemInfo(itemID) or "Name not found", ""

    value, s = LSW:GetSkillValue(rID) or 0, ''
    dprint(iName .. "  GetSkillValue - " .. value, s .. "   id ".. itemID)

    if value <= 0 and itemID and LSW then
        value, s = LSW:GetItemCost(itemID) or 0, ""
        dprint(iName .. "  GetItemCost - " .. value, s .. "   id ".. itemID)
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

--#endregion

-- ==========================================
--#region Update Rdb  3. ОБНОВЛЕНИЕ И НАПОЛНЕНИЕ БАЗЫ
-- ==========================================
-- Сканируем базу рецептов AckisRecipeList, из фрейма, все рецепты выбранной профессии
-- через тултип в котором есть все реагенты. "Frame" Processor, PrepareQueue(), ScanStep(), GetScanner()
-- делается один раз на каждую профессию, далее не требуется

---Обновление базы умений при открытом окне AckisRecipeList
function DataCore:UpdateRdbSkills()
    DataCore.flush = true
    DataCore.Queue = {}
    DataCore.CurrentIndex = 1
    DataCore.wdc = 0
    DataCore.prof = ""
    DataCore:PrepareQueue()
    DataCore.Processor()
    DataCore.Proc:Show()    -- запуск обработчика (фрейм)
end

--- создание очереди рецептов, данных о которых нет в базе
function DataCore:PrepareQueue()
    if not ARL or not ARL.Frame then dprint("Ошибка! ARL еще не загружен.|r") return end
    local entrCount = 0
    local entries = ARL.Frame.list_frame.entries        -- список рецептов ARL
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
            Rdb[spellID] = {}
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
            Rdb[spellID] = { skillCost, skillValue, itemID, reagents = {} }
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
                if not name then dprint("reagent name no found (str 320)") return end

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
    DataCore.Proc = CreateFrame("Frame")
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
        --dprint("ScanStep status " .. tostring(status))

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

--
function onUpdateARL()
    -- Проверяем, что ARL и его кэш доступны
    if not ARL or not ARL.Frame or not ARL.Frame.list_frame then
        return
    end

end

-- ==========================================
-- 3. СОБЫТИЯ И ХУКИ
-- ==========================================

local frame = CreateFrame("Frame", "LSWBridgeEventFrame")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", function(self, event)
    if event == "AUCTION_HOUSE_CLOSED" then
        -- Проверяем: включено ли "auto" и прошло ли 6 часов (21600 сек)
        local now = time()
        local last = Rdb.Meta.lastUpdate or 0

        if Rdb.Meta.autoSync and (now - last) > 21600 then 
            LSW.UpdateRecipePrices() 
            Rdb.Meta.lastUpdate = now
            print("|cff00ff00[LSW-Bridge]:|r Авто-обновление цен запущено...")
        end
    end
end)


-- Подписываемся на событие открытие окна профессии
local CoreFrame = CreateFrame("Frame")
CoreFrame:RegisterEvent("ARL_MainFrame_SHOW")
CoreFrame:RegisterEvent("ARL_UPDATE")
    CoreFrame:SetScript("OnEvent", function(self, event)
    -- Сканируем через 0.5 сек после открытия, чтобы данные прогрузились
    C_Timer:After(0.5, onUpdateARL)
end)

-- таймер на 6 часов
if Rdb.Meta.autoSync and (GetTime() - Rdb.Meta.lastUpdate > 21600) then
--    LSW.UpdateRecipePrices()
    Rdb.Meta.lastUpdate = GetTime()
end


-- ==========================================
-- 3. ИНИЦИАЛИЗАЦИЯ И ИНТЕРФЕЙС
-- ==========================================
--- Возвращает возраст цен в читаемом виде
--- @return string
function DataCore:GetFormattedUpdateAge()
    local last = Rdb and Rdb.Meta and Rdb.Meta.lastUpdate or 0
    if last == 0 then return "никогда" end
    local age = time() - last
    if age < 60 then return "только что" end
    local hours = math.floor(age / 3600)
    local mins = math.floor((age % 3600) / 60)
    if hours > 0 then
        return string.format("%d ч. %d мин. назад", hours, mins)
    else
        return string.format("%d мин. назад", mins)
    end
end


function DataCore:Init()
    Rdb = Rdb or {}
    Rdb.Meta = Rdb.Meta or { lastUpdate = 0, autoSync = true }
    Rdb.Meta.Entries = Rdb.Meta.Entries or {}
end

function DataCore:InitInterface()
local parent = _G["ARL_MainPanel"]
if not parent or LSW_UpBtn then return end

    -- Кнопка "upRdb"
    local btn = CreateFrame("Button", "upRdb", parent, "UIPanelButtonTemplate")
    btn:SetSize(40, 17)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -170, -50)
    btn:SetText("updb")

    -- Тултип с таймером
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Обновление умений Rdb")
        GameTooltip:AddLine("Последнее: " .. DataCore:GetFormattedUpdateAge(), 1, 1, 1)
        GameTooltip:Show()
    end)    
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Логика клика (КД 1 мин)
    btn:SetScript("OnClick", function()
        if (GetTime() - (self.lastClick or 0)) > 60 then
            self.lastClick = GetTime()
            DataCore.UpdateRdbSkills() -- Запуск обновления базы
            print("|cff00ff00[LSW-Bridge]:|r Запущено обновление бызы рецептов ...")
        else
            print("|cff00ff00[LSW-Bridge]:|r Подождите 1 минуту.")
        end    
    end)    

    -- Чекер "auto"
    local chk = CreateFrame("CheckButton", "LSW_AutoSyncCheck", parent, "UICheckButtonTemplate")
    chk:SetSize(24, 24)
    chk:SetPoint("RIGHT", btn, "LEFT", -5, 0)
    _G[chk:GetName() .. "Text"]:SetText("auto")

    -- Установка значения из глобальной таблицы
    chk:SetChecked(Rdb.Meta.autoSync)

    chk:SetScript("OnClick", function(self)
        Rdb.Meta.autoSync = self:GetChecked()
    end)    
end    


-- Инициализация при загрузке
local startupFrame = CreateFrame("Frame")
startupFrame:RegisterEvent("PLAYER_LOGIN")
startupFrame:SetScript("OnEvent", function()
    LSW_DataCore:Init()
    -- 1. Создаем интерфейс через глобальный объект
    if LSW_DataCore and LSW_DataCore.InitInterface then
        LSW_DataCore:InitInterface()
    end

end)
