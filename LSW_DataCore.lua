-- ==============================================
do  -- 1. HEADER
    -- ==========================================
    -- LSW_dataCore.lua (Sirus 2026)  v0.0.1

    ---@class DataCore
    ---@field InitInterface fun(self: DataCore) Создает кнопку и чекер в ARL
    ---@field UpdateAllRdbPrices fun(self: DataCore) Пересчитывает золото в Rdb
    ---@field GetFormattedUpdateAge fun(self: DataCore): string Возвращает возраст цен

    LSW_DataCore = LSW_DataCore or {}     -- Создаем уникальный глобальный объект

    ---@class RecipeData
    ---@field spellCost number  Сумма стоимости всех реагентов
    ---@field spellValue number Рыночная цена создаваемого предмета
    ---@field itemID number     ID предмета-результата
    ---@field reagents table<number, number> Таблица: [itemID] = количество

    ---@class MetaData
    ---@field lastUpdate number   Время последнего обновления (UNIX)
    ---@field autoSync boolean    Флаг автоматической синхронизации
    ---@field totalEntries number Общее количество записей в базе

    ---@class DataCoreRdb : { [number]: RecipeData }
    ---@field Meta MetaData

    ---@type DataCoreRdb
    Rdb = Rdb or {}
    Rdb.Meta = Rdb.Meta or { lastUpdate = 0, autoSync = false, totalEntries = 0 }
end -- ===== header =========================

local DataCore = LSW_DataCore         -- Локальная ссылка для удобства внутри файла
local limit = 1000        -- ограничитель для теста
local wdcLim = 5        -- Watch Dog Counter
local debug = true

local function dprint(...)
    if debug then print("|cff00ffffLSW-CORE:|r", ...) end
end

local function DumpStructure(t, maxDepth, currentDepth)
    currentDepth = currentDepth or 0
    if currentDepth > maxDepth or type(t) ~= "table" then return end

    -- Формируем отступ (3 пробела за каждый уровень)
    local indent = string.rep("   ", currentDepth)

    for k, v in pairs(t) do
        local kType, vType = type(k), type(v)

        -- Если ключ - таблица, раскрываем его структуру в одну строку или отдельно
        local kDisplay = tostring(k)
        if kType == "table" then
            kDisplay = "[TABLE_ID: "..tostring(k).."]"
        end

        local vDisplay = (vType == "table") and "" or tostring(v)

        -- Выводим текущую строку
        print(string.format("%s %s / %s", indent, kDisplay, vDisplay))

        -- 1. РЕКУРСИЯ ДЛЯ КЛЮЧА (если это таблица)
        if kType == "table" then
            print(indent .. "   (Contents of Key-Table:)")
            DumpStructure(k, maxDepth, currentDepth + 1)
        end

        -- 2. РЕКУРСИЯ ДЛЯ ЗНАЧЕНИЯ (если это таблица)
        if vType == "table" then
            DumpStructure(v, maxDepth, currentDepth + 1)
        end
    end
end
--//-----------------------------------------------------------------------------

local function GetCostFromRdb(recipeID)
    local itemID = AckisRecipeList:GetRecipeData(recipeID, "item_id")
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


-- ПАРСЕР SKILLET (должен быть выше вызова LSW_UpdateARL)
local function GetReagentsFromSkillet(recipeID)
    if not Skillet or not Skillet.stitch then return nil end
    -- На Сирусе Skillet использует item_id как ключ в строке
    local targetItemID = AckisRecipeList:GetRecipeData(recipeID, "item_id")
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


function GetRecipeCostAnywhere(rID, rNbr)
    local recipeID = rID
    if not recipeID then return 0 end

    -- 1. ЦЕНА ПРЕДМЕТА (BoP - Best of price Auction, Vendor, Disenchant)
    local itemID = AckisRecipeList:GetRecipeData(recipeID, "item_id")
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

function DataCore:UpdateAllRdbPrices()
    if not LSW or not LSW.itemCache then 
        print("|cffff0000[LSW-Bridge]:|r Ошибка: itemCache не найден!")
        return 
    end

    for id, data in pairs(Rdb) do
        --dprint("for ".. tostring(id), tostring(data) .. " in pairs(" .. tostring(Rdb) .. ") do")
        if id % 30 == 1 then dprint("   предмет " .. id .. "   data " .. tostring(data)) end
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

--function DataCore:UpdateAllRdbPrices()
--    for id, data in pairs(Rdb) do
--        if type(id) == "number" and data.reagents then
--            local cost = 0
--            for rID, count in pairs(data.reagents) do
--                LSW.UpdateItemCost(rID) -- Прогрев кэша LSW
--                local cache = LSW.ItemCache(rID)
--                cost = cost + ((cache and cache.bestCost or 0) * count)
--            end
--            data.spellCost = cost
--            if data.itemID then
--                LSW.UpdateItemValue(data.itemID)
--                local v = LSW:GetItemCache(data.itemID)
--                data.spellValue = v and v.bestValue or 0
--            end
--        end
--    end
--    Rdb.Meta.lastUpdate = time()
--    print("|cff00ff00[LSW-Bridge]:|r База Rdb синхронизирована.")
--end


-- ==========================================
-- СКАНИРОВАНИЕ И НАПОЛНЕНИЕ БАЗЫ
-- ==========================================

 DataCore.Queue = {}
 DataCore.CurrentIndex = 1
 DataCore.IsScanning = false
 DataCore.Wdc = 0

function DataCore:PrepareQueue()
    local ARL = _G.AckisRecipeList
    if not ARL or not ARL.Frame then
        dprint("|cffff0000[LSW-CORE]: Ошибка! ARL еще не загружен.|r")
        return
    end

    self.Queue = {}    -- Очищаем очередь перед заполнением
    local count_new = 0
    local count_total = 0

    -- Проходим по текущим записям ARL
    for i, entry in pairs(ARL.Frame.list_frame.entries) do
        if i > limit then dprint(" Limit " .. limit) return end   -- LIMIT
        local spellID = entry["recipe_id"]

        -- ПРОВЕРКА: Нужно ли нам это сканировать?
        -- Если ID нет в базе ИЛИ в базе нет реагентов или в базе нет itemID
        if not Rdb[spellID] or not Rdb[spellID].reagents or next(Rdb[spellID].reagents) == nil or not Rdb[spellID].itemID then
            table.insert(self.Queue, spellID)
            count_total = count_total + 1
            count_new = count_new + 1
            dprint("Queues " .. #self.Queue, "   New #" .. tostring(count_new))
        end
    end

    dprint(string.format("Очередь готова. Всего в списке: %d, Новых для скана: %d", count_total, count_new))
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
    --dprint("Scan Queue " .. tostring(self.CurrentIndex) .. "  spellID " .. tostring(spellID))
    if not spellID then return "COMPLETED" end

    -- Попытка получить данные
    local link = GetSpellLink(spellID)
    --dprint("  GetSpellLink(" .. spellID .. ") = " .. tostring(link))
    if not link then return "WAIT" end -- Сервер еще не отдал линк спелла

    -- Проверка тултипа
    local scanner = self:GetScanner() -- Ваш скрытый тултип
    if self.Wdc == 0 then
        scanner:SetHyperlink(link)
    end

    -- Парсинг строк тултипа на предмет реагентов
    local lineText = _G["DataCoreScannerTooltipTextLeft2"]:GetText() or ""

    if lineText:find("Реагенты:") then
        if not Rdb[spellID] then Rdb[spellID] = 0 end
        if not Rdb[spellID].itemID then Rdb[spellID].itemID = AckisRecipeList:GetItemData(spellID, "itemID")
            dprint("  новый предмет " .. tostring(Rdb[spellID].itemID))
         end

        local data = lineText:match("Реагенты:%s*(.*)")     -- Извлекаем всё после "Реагенты:"
        if data then
            --dprint("1 " .. data)
            -- Чистим мусор: цвета и невидимые переносы [N]
            data = data:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%c", " "):gsub("|n", "")
            ----dprint("1 " .. data)

            for part in data:gmatch("[^,]+") do
                --dprint("2 " .. part)

                part = part:trim()
                -- 1. Сначала пробуем вытащить имя и число из скобок: "Имя (2)"
                local name, count = part:match("^(.-)%s*%(%d+%)")
                local cValue = part:match("%((%d+)%)") or 1

                -- 2. Если скобок не было, значит это "Имя" (кол-во 1) или "Имя 2"
                if not name then
                    name, cValue = part:match("^(.-)%s*(%d*)$")
                    cValue = tonumber(cValue) or 1
                end

                name = name:trim()
                -- Теперь GetItemInfo точно получит "Сребролист", а не "Сребролист (2)"
                local _, itemLink = GetItemInfo(name) 
                    --dprint("GetItemInfo(" .. name .. ") " .. tostring(itemLink))

                    if itemLink then
                        --dprint("itemLink ok")
                        local itemID = itemLink:match("item:(%d+)")
                        if not Rdb[spellID] then
                            dprint("  New record! spellID " .. spellID)
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

        -- 3. Решаем, идти ли дальше
    if self.Wdc >= wdcLim then       -- WatchDogCounter
        self.Wdc = 0
        return "NEXT"
    else
        self.Wdc = self.Wdc + 1
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

        -- Ограничитель для теста limit
        if DataCore.CurrentIndex > limit then
            print("|cff00ff00[DataCore]:|r Тестовый лимит " .. limit .. " достигнут.")
            self:Hide()
        end
    elseif status == "COMPLETED" then
        print("|cff00ff00[DataCore]:|r Скан всей базы завершен успешно!")
        self:Hide()
    elseif status == "WAIT" then
        --dprint("Wait ...")
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
    btn:SetText("up Rdb")

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
    -- 1. Создаем интерфейс через глобальный объект
    if LSW_DataCore and LSW_DataCore.InitInterface then
        LSW_DataCore:InitInterface() 
    end

    -- 2. Ставим хук (исправлено: hooksecurefunc)
    if LSW and LSW.UpdateSingleRecipePrice then
        -- hooksecurefunc — стандартная функция API WoW
        hooksecurefunc(LSW, "UpdateSingleRecipePrice", function()
            -- Проверка завершения прогресс-бара LSW
            if LSW.progressBar and LSW.progressBar.curr == LSW.progressBar.max then
                if LSW_DataCore.UpdateAllRdbPrices then
                    LSW_DataCore:UpdateAllRdbPrices()
                    print("|cff00ff00[LSW-Bridge]:|r Цены в Rdb успешно синхронизированы.")
                end
            end
        end)
    end
end)

--local startupFrame = CreateFrame("Frame")
--startupFrame:RegisterEvent("PLAYER_LOGIN")
--startupFrame:SetScript("OnEvent", function()
--    -- Создаем кнопку и чекер, когда интерфейс готов
--    DataCore:InitInterface() 
--
--    -- Хук на завершение прогресс-бара LSW
--    if LSW and LSW.UpdateSingleRecipePrice then
--        hooksecurefn(LSW, "UpdateSingleRecipePrice", function()
--            -- Если прогресс-бар LSW дошел до конца
--            if LSW.progressBar and LSW.progressBar.curr == LSW.progressBar.max then
--                DataCore:UpdateAllRdbPrices()
--                print("|cff00ff00[LSW-Bridge]:|r Цены в Rdb успешно синхронизированы.")
--            end
--        end)
--    end
--end)
