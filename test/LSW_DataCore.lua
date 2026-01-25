-- ==============================================
do  -- 1. HEADER
    -- ==========================================
    -- LSW_dataCore.lua (Sirus 2026)  v0.0.1

    ---@class DataCore
    ---@field InitInterface fun(self: DataCore) Создает кнопку и чекер в ARL
    ---@field UpdateAllRdbPrices fun(self: DataCore) Пересчитывает золото в Rdb
    ---@field GetFormattedUpdateAge fun(self: DataCore): string Возвращает возраст цен
    LSW_DataCore = LSW_DataCore or {}     -- Создаем уникальный глобальный объект

    ---@class RdbEntry
    ---@field spellCost number  Сумма реагентов
    ---@field spellValue number Цена продажи результата
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
local debug = true
--local reagentsLoc = SPELL_REAGENTS:match("([^%s%p]+)")  -- Очищаем от всего, кроме букв (для русского и английского)
local reagentsLoc = SPELL_REAGENTS:gsub("[%s%p|n]", "") -- Удаляет пробелы, знаки препинания и переносы
local ARL = AckisRecipeList

-------------------------------------------------------------------------
local function dprint(...)
    if debug then print("|cff00ffffLSW-CORE:|r", ...) end
end

local function RdbInit()
    Rdb = Rdb or {}
    Rdb.Meta = Rdb.Meta or { lastUpdate = 0, autoSync = true }
    Rdb.Meta.Entries = Rdb.Meta.Entries or {}
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
            DumpStructure(v, keyStr, mDepth, cDepth + 1)
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

-- не используется
function DataCore:GetPrice(itemID)
    local aucPrice = LSW:GetAuctionPrice(itemID) or 0
    -- Получаем цену продажи NPC
    local _, _, _, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemID)
    local vendorBuyPrice = (sellPrice or 0) * 4 -- Цена покупки у вендора
    
    -- Приоритет: Аукцион, если цена адекватна. Иначе - вендор.
    -- (Здесь можно добавить логику, что если аукцион в 10 раз дороже вендора, игнорируем аук)
    if aucPrice > 0 and aucPrice < (vendorBuyPrice * 10) then
        return aucPrice
    else
        return vendorBuyPrice
    end
end


-- ==========================================
-- 2. ПОЛУЧЕНИЕ ЦЕНЫ, ОБНОВЛЕНИЕ ЦЕН БД
-- ==========================================

-- не используется
function GetRecipeCostAnywhere(rID, rNbr)
    local recipeID = rID
    if not recipeID then return 0 end
    
    -- 1. ЦЕНА ПРЕДМЕТА (BoP - Best of price Auction, Vendor, Disenchant)
    local itemID = ARL:GetRecipeData(recipeID, "item_id")
    if itemID then
        itemCost = (LSW.GetItemCost and LSW:GetItemCost(itemID)) or 0
--        dprint("#" .. rNbr .. "   GetItemCost - " .. itemCost)
end

-- 2. СЕБЕСТОИМОСТЬ (РЕАГЕНТЫ)
-- Проверка 1: Родной метод LSW (для известных)
local cost = (LSW and LSW.GetSkillCost and LSW:GetSkillCost(recipeID)) or 0
--    dprint("#" .. rNbr .. "   GetSkillCost - " .. cost)
if cost > 0 then return itemCost, cost end

cost = (LSW.GetSkillCost and LSW:GetSkillValue(recipeID)) or 0
--    dprint("#" .. rNbr .. "   GetSkillValue - " .. cost)
if cost > 0 then return itemCost, cost end

-- Проверка 2: Ваша накопленная база Rdb
cost = GetCostFromRdb(recipeID) or 0
--    dprint("#" .. rNbr .. "   GetReagentsFromRdb - " .. cost)
if cost > 0 then return itemCost, cost end

-- Проверка 3: Если в вашей базе нет, лезем в SkilletDB
--    dprint("   cost " .. cost .. "   SkilletDB " .. tostring(SkilletDB) .. "   # " .. #SkilletDB)
if (not cost or cost == 0) and SkilletDB then
    --        dprint("   if not cost and SkilletDB   ok")
    local skilletData = GetReagentsFromSkillet(recipeID)
    --        dprint("#" .. rNbr .. "   GetReagentsFromSkillet (data) - " .. tostring(skilletData))
    if skilletData then
        for id, count in pairs(skilletData) do
            local price = LSW:GetItemCost(id) or 0
            cost = cost + (price * count)
            --                dprint("#" .. rNbr .. "   GetReagentsFromSkillet (cost) - " .. cost)
        end
    end
    if cost > 0 then return itemCost, cost end
end
return 0
end

--  обновление цен бд, предполагается запуск по закрытию окна аукциона (хук) + таймер 6+ часов
function DataCore:UpdateAllRdbPrices()
    RdbInit()
    if not LSW or not LSW.itemCache then 
        print("|cffff0000[LSW-Bridge]:|r Ошибка: itemCache не найден!")
        return 
    end
    
    for id, data in pairs(Rdb) do
        --dprint("for ".. tostring(id), tostring(data) .. " in pairs(" .. tostring(Rdb) .. ") do")
        if id then dprint("   предмет " .. type(id) .. "   data " .. type(data)) end
        if type(id) == "number" and data.reagents then
            local cost = 0
            for rID, count in pairs(data.reagents) do
                --dprint("rID " .. rID .. "   count ".. count)
                
                LSW.UpdateItemCost(rID)         -- Прогреваем цену в LSW
                
                -- Достаем результат напрямую из кеша
                local cache = LSW.itemCache[rID]
                local bestCost = (cache and cache.bestCost) or 0
                cost = cost + (bestCost * count)
                if id % 30 == 1 then dprint("   реагент " .. rID .. "   cost " .. bestCost) end
            end
            data.spellCost = cost
            
            -- Обновляем цену самого результата (Profit)
            if data.itemID then
                LSW.UpdateItemValue(data.itemID)
                local vCache = LSW.itemCache[data.itemID]
                data.spellValue = (vCache and vCache.bestValue) or 0
                if id % 30 == 1 then dprint("   предмет " .. data.itemID .. "  цена " .. cost) end
            else

            end
            --if id % 30 == 1 then dprint("   предмет " .. data.itemID .. "  цена " .. cost) end
        end
    end
    Rdb.Meta.lastUpdate = time()
    print("|cff00ff00[LSW-Bridge]:|r База Rdb успешно синхронизирована (" .. time() .. ")")
end

-- ==========================================
-- СКАНИРОВАНИЕ И НАПОЛНЕНИЕ БАЗЫ
-- ==========================================
-- Сканируем базу рецептов AckisRecipeList, из фрейма, все рецепты выбранной профессии
-- через тултип в котором есть все реагенты. "Frame" Processor, PrepareQueue(), ScanStep(), GetScanner()
-- делается один раз на каждую профессию, далее не требуется
DataCore.purge = true
DataCore.Queue = {}
DataCore.CurrentIndex = 1
DataCore.IsScanning = false
DataCore.Wdc = 0


--- создание очереди рецептов, данных о которых нет в базе
function DataCore:PrepareQueue()
    RdbInit()
    if not ARL or not ARL.Frame then dprint("Ошибка! ARL еще не загружен.|r") return end
    local entries = ARL.Frame.list_frame.entries        -- количество записей ARL
    local prof = ARL:GetRecipeData(entries[1].recipe_id, "profession")    -- профессия
    -- обнуляем кол-во записей в базе для этой профессии, если надо
    if not Rdb.Meta.Entries[prof] or DataCore.purge then Rdb.Meta.Entries[prof] = 0 end 
    self.Queue = {}    -- Очищаем очередь перед заполнением
    local count_new = 0
    local count_total = 0
    
    -- сверяем количество рецептов в списке АРЛ с соответствующим значением в базе
    local str = string.format("%s рецептов в Rdb %d   в ARL %d", prof, Rdb.Meta.Entries[prof], #entries)
    if Rdb.Meta.Entries[prof] > #entries and not DataCore.purge then
        print(str .. " Обновление не требуется") return
    end
    print(str .. " создание очереди")

    -- Проходим по текущим записям ARL
    for i, entry in pairs(entries) do
        local spellID = entry["recipe_id"]

        -- Если spellID нет в базе или принудительное обновление
        if not Rdb[spellID] or DataCore.purge then
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
    dprint("Scan Queue " .. tostring(self.CurrentIndex) .. "  spellID " .. tostring(spellID))

    local entries = ARL.Frame.list_frame.entries        -- количество записей ARL
    local prof = ARL:GetRecipeData(entries[1].recipe_id, "profession")    -- профессия

    -- Попытка получить данные
    local link = GetSpellLink(spellID)
    --dprint("  GetSpellLink(" .. spellID .. ") = " .. tostring(link))
    if not link then dprint("SCAN WAIT") return "WAIT" end -- Сервер еще не отдал линк спелла

    -- тултип умения
    local scanner = self:GetScanner()   -- Ваш скрытый тултип
    if self.Wdc == 0 then               -- если умение новое, активируем тултип
        scanner:SetHyperlink(link)
    end

    -- Парсинг 2 строки тултипа на предмет реагентов
    local lineText = _G["DataCoreScannerTooltipTextLeft2"]:GetText() or ""

    if lineText:find(reagentsLoc) then -- if lineText:find("Реагенты:") then
        if not Rdb[spellID] or DataCore.purge then  -- еще нет такого предмета в базе
            Rdb[spellID] = {}
            dprint("записей в базе " .. Rdb.Meta.Entries[prof])
            Rdb.Meta.Entries[prof] = Rdb.Meta.Entries[prof] + 1
            dprint("записей в базе " .. Rdb.Meta.Entries[prof])
            dprint("  New Item: " .. tostring(Rdb[spellID].itemID))
        end
        Rdb[spellID] = {}
        Rdb[spellID].itemID = ARL:GetRecipeData(spellID, "item_id")

        local data = lineText:match("Реагенты:%s*(.*)")     -- Извлекаем всё после "Реагенты:"
        dprint("0 " .. data)
        if data then
            --dprint("1 " .. data)
            -- Чистим мусор: цвета и невидимые переносы [N]
            data = data:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%c", " "):gsub("|n", "")
            dprint("1 " .. data)

            for part in data:gmatch("[^,]+") do
                dprint("2 " .. part)

                part = part:trim()
                -- 1. Сначала пробуем вытащить имя и число из скобок: "Имя (2)"
                local name, count = part:match("^(.-)%s*%(%d+%)")
                dprint("name " .. name .. "  count " .. count)
                local cValue = part:match("%((%d+)%)") or 1
                dprint("cValue" .. cValue)

                -- 2. Если скобок не было, значит это "Имя" (кол-во 1) или "Имя 2"
                if not name then
                    name, cValue = part:match("^(.-)%s*(%d*)$")
                    dprint("name " .. name .. "  cValue " .. cValue)
                    cValue = tonumber(cValue) or 1
                end

                name = name:trim()
                -- Теперь GetItemInfo точно получит "Сребролист", а не "Сребролист (2)"
                local _, itemLink = GetItemInfo(name) 
                    dprint("GetItemInfo(" .. name .. ") " .. tostring(itemLink) .. "   кол-во " .. tostring(count))

                    if itemLink then
                        --dprint("itemLink ok")
                        local itemID = itemLink:match("item:(%d+)")
                        if not Rdb[spellID] then
                            Rdb[spellID] = { reagents = {} }
                        else 
                            dprint("  exist " .. spellID)
                        end
                        if not Rdb[spellID].reagents then Rdb[spellID].reagents = {} end -- Доп. защита
                        Rdb[spellID].reagents[tonumber(itemID)] = tonumber(count) or 1

                        self.Wdc = 100 -- Флаг успеха
                    else
                        if self.Wdc >= wdcLim * count then
                            self.Wdc = 0
                            return "NEXT"
                        else
                        self.Wdc = self.Wdc + 1
                        return "WAIT"  -- Если предмета нет в кэше, запрашиваем и ждем тик
                    end
                end
            end
        end
    end

        -- 3. Несколько попыток если данные не получены
    if self.Wdc >= wdcLim then       -- WatchDogCounter
        if self.Wdc < 100 then dprint("  SCAN FALED") else dprint("  SCAN SUCCESS") end
        self.Wdc = 0
        return "NEXT"
    else
        self.Wdc = self.Wdc + 1
        dprint("WDC WAIT " .. self.Wdc)
        return "WAIT"
    end
end


-- Этот Невидимый Фрейм-пульс будет обрабатывать логику ожидания.
-- Если сервер «молчит» (вернул nil), контроллер просто подождет следующего кадра, не блокируя игру.
DataCore.Processor = CreateFrame("Frame")
    -- Создаем визуальную строку на фрейме Processor
    DataCore.Processor.text = DataCore.Processor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    DataCore.Processor.text:SetPoint("CENTER", UIParent, "CENTER", 0, 150) -- Центр экрана

    DataCore.Processor:Hide() -- По умолчанию выключен

    DataCore.Processor:SetScript("OnUpdate", function(self, elapsed)
    local spellID = DataCore.Queue[DataCore.CurrentIndex] or "DONE"
    self.text:SetText(string.format("Scan: %d/%d | ID: %s", DataCore.CurrentIndex, #DataCore.Queue, tostring(spellID)))
    -- Ограничитель скорости (раз в 0.05 сек), чтобы не спамить в пустую
    self.timer = (self.timer or 0) + elapsed
    if self.timer < 0.05 then return end
    self.timer = 0

    local status = DataCore:ScanStep()
    --dprint("ScanStep status " .. tostring(status))

    if status == "NEXT" then
        DataCore.CurrentIndex = DataCore.CurrentIndex + 1
        -- Чек-поинт каждые 10 рецептов
        if DataCore.CurrentIndex % 10 == 0 then
            print(string.format("|cff00ff00[DataCore]:|r Прогресс %d/%d", DataCore.CurrentIndex, # DataCore.Queue))
        end

    elseif status == "COMPLETED" then
        print("[DataCore]:|r Скан всей базы завершен успешно!")
        self:Hide()
    elseif status == "WAIT" then
        -- Просто пропускаем тик, ждем ответа сервера
    end
end)


function SyncRdbWithLSW()
    -- Проверяем, что LSW и его кэш доступны
    if not LSW or not LSW.recipeCache or not LSW.recipeCache.reagents then 
        return 
    end

    local count = 0
    local lswReagents = LSW.recipeCache.reagents

    -- Проходим по всем рецептам, которые LSW просканировал в текущем окне
    for spellID, reagents_tbl in pairs(lswReagents) do
        -- Если этого рецепта еще нет в нашей постоянной базе Rdb
        if spellID and not Rdb[spellID] then
            local tempReagents = {}
            local hasReagents = false

            for itemID, quantity in pairs(reagents_tbl) do
                tempReagents[itemID] = quantity
                hasReagents = true
            end

            if hasReagents then
                Rdb[spellID] = tempReagents
                count = count + 1
                -- dprint("Синхронизирован рецепт: " .. spellID)
            end
        end
    end

    if count > 0 then
        print("База Rdb пополнена из кэша LSW на " .. count .. " рецептов.")
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


--[[-- Подписываемся на событие открытие окна профессии
local CoreFrame = CreateFrame("Frame")
CoreFrame:RegisterEvent("TRADE_SKILL_SHOW")
--CoreFrame:RegisterEvent("TRADE_SKILL_UPDATE")
    CoreFrame:SetScript("OnEvent", function(self, event)
    -- Сканируем через 0.5 сек после открытия, чтобы данные прогрузились
    C_Timer:After(0.5, SyncRdbWithLSW)
end)


if Rdb.Meta.autoSync and (GetTime() - Rdb.Meta.lastUpdate > 21600) then
    LSW.UpdateRecipePrices()
    Rdb.Meta.lastUpdate = GetTime()
end]]


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

function DataCore:InitInterface()
    local parent = _G["ARL_MainPanel"]
    if not parent or LSW_UpBtn then return end

    -- Кнопка "up Rdb"
    local btn = CreateFrame("Button", "LSW_UpBtn", parent, "UIPanelButtonTemplate")
    btn:SetSize(50, 20)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -50, -37)
    btn:SetText("updb")

    -- Тултип с таймером
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Обновление цен Rdb")
        GameTooltip:AddLine("Последнее: " .. DataCore:GetFormattedUpdateAge(), 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Логика клика (КД 1 мин)
    btn:SetScript("OnClick", function()
        if (GetTime() - (self.lastClick or 0)) > 60 then
            self.lastClick = GetTime()
            LSW.UpdateRecipePrices() -- Запуск глобального кэша LSW
            print("|cff00ff00[LSW-Bridge]:|r Запущен пересчет цен...")
        else
            print("|cff00ff00[LSW-Bridge]:|r Подождите 1 минуту.")
        end
    end)

    -- Чекер "auto"
    local chk = CreateFrame("CheckButton", "LSW_AutoSyncCheck", parent, "UICheckButtonTemplate")
    chk:SetSize(24, 24)
    chk:SetPoint("RIGHT", btn, "LEFT", -5, 0)
    _G[chk:GetName() .. "Text"]:SetText("auto")
    
    -- Безопасное получение значения из глобальной таблицы
    local isAutoSync = (Rdb and Rdb.Meta and Rdb.Meta.autoSync) or false
    chk:SetChecked(isAutoSync)
    --chk:SetChecked(Rdb.Meta.autoSync)

    chk:SetScript("OnClick", function(self)
        if not Rdb.Meta then Rdb.Meta = {} end -- Доп. защита
        Rdb.Meta.autoSync = self:GetChecked()
    end)
    --chk:SetScript("OnClick", function(self)
    --    Rdb.Meta.autoSync = self:GetChecked()
    --end)
end


-- Инициализация при загрузке
local startupFrame = CreateFrame("Frame")
startupFrame:RegisterEvent("PLAYER_LOGIN")
startupFrame:SetScript("OnEvent", function()
    if Rdb.Meta then dprint("Rdb.Meta before ok") else dprint("Rdb.Meta before NOT ok") end
    RdbInit()
    if Rdb.Meta then dprint("Rdb.Meta after ok") else dprint("Rdb.Meta after NOT ok") end
    -- 1. Создаем интерфейс через глобальный объект
    if LSW_DataCore and LSW_DataCore.InitInterface then
        LSW_DataCore:InitInterface()
    end

end)
