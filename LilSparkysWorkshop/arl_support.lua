--------------------------------------------
-- arl_support.lua v0.1.0 (Sirus 3.3.5)
--------------------------------------------
---@class Asup
---@field Init fun(self: Asup)      Init
---@field Interface fun(self: Asup) Init
---@field OnOpenARL fun(self: Asup): boolean установка хуков при первом открытии (scan btn in skillet)
---@field OnShow fun(self: Asup)
---@field OnUpdate fun(self: Asup)  main work function
---@field GetFormatAge fun(self: Asup): string
---@field updb string update db button
---@field hooked_ARL boolean флаг инициализации ARL
Asup = {}
cnt = 0


--- Возвращает возраст цен в читаемом виде
function Asup.GetFormatAge()
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

--- РИСУЕТ ЦЕНЫ В ОКНЕ ARL ---
function Asup:OnUpdate()
    local frame = AckisRecipeList.Frame.list_frame
    if not AckisRecipeList.Frame or not frame or not frame:IsVisible() then return end

    local buttons = frame.entry_buttons
    local entries = frame.entries

    for i = 1, #buttons do
        local btn = buttons[i]
        local sIdx = btn.string_index 
        local data = sIdx and entries[sIdx]

        if not btn.lswText then
            btn.lswText = btn:CreateFontString(nil, "OVERLAY")
            btn.lswText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE") 
            btn.lswText:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
            btn.lswText:SetJustifyH("RIGHT")
        end

        btn.lswText:Hide()

        if btn:IsVisible() and data and data.recipe_id and data.type == "header" then
            btn.lswText:SetText(LSW_DataCore:GetCost(data.recipe_id) or "---")
            btn.lswText:Show()
        else
            btn.lswText:SetText("...")
        end
    end
end

function Asup:OnShow()

end

---=============================================
---@region interface    ИНТЕРФЕЙС
   ---==========================================

function Asup:Interface()
    local parent = _G["ARL_MainPanel"]
    if not parent or Asup.updb then return end

	-- Кнопка "upRdb"
	local btnRdbUpd = CreateFrame("Button", "upd b", parent, "UIPanelButtonTemplate")
	btnRdbUpd:SetSize(38, 16)
	btnRdbUpd:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -184, -55)
	btnRdbUpd:SetText("scan")

	-- Тултип с таймером
	btnRdbUpd:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Обновление базы рецептов")
		GameTooltip:AddLine("Последнее: " .. Asup:GetFormatAge(), 1, 1, 1)
		GameTooltip:AddLine("(обновление базы рецептов для цен, не базы самой ARL)") GameTooltip:Show()
	end)

	btnRdbUpd:SetScript("OnLeave", function() GameTooltip:Hide() end)

	-- Логика клика (КД 1 мин)
	btnRdbUpd:SetScript("OnClick", function()
		if (GetTime() - (self.lastClick or 0)) > 5 then
			self.lastClick = GetTime()
			LSW_DataCore:UpdateRdbSkills() -- Запуск обновления базы
			print("|cff00ff00[LSW-Bridge]:|r Запущено обновление бызы рецептов ...")
		else
			print("|cff00ff00[LSW-Bridge]:|r Подождите пожалуйста секундочку.")
		end
	end)

	-- Чекер "auto"
	local chk = CreateFrame("CheckButton", "LSW_AutoSyncCheck", parent, "UICheckButtonTemplate")
	chk:SetSize(18, 18)
	chk:SetPoint("RIGHT", btnRdbUpd, "LEFT", 0, 0)
	_G[chk:GetName() .. "Text"]:SetText("")
	-- Установка значения из глобальной таблицы
	chk:SetChecked(LSW_DataCore.flush)

	chk:SetScript("OnClick", function(self)
		LSW_DataCore.flush = self:GetChecked()
	end)
	-- Тултип для чекера
	chk:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Сбросить и обновить")
		GameTooltip:Show()
	end)

	btnRdbUpd:SetScript("OnLeave", function() GameTooltip:Hide() end)
	chk:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btnRdbUpd:Show()
    chk:Show()
end

---@endregion interface
---==========================================
---@region hooks    СОБЫТИЯ И ХУКИ
---==========================================

function Asup:OnOpenARL()

end

    --local watcher = CreateFrame("Frame", "AsupFrame")
    --watcher:SetScript("OnUpdate", function(self, elap)
    --    self.t = (self.t or 0) + elap
    --    if self.t > 2 then
    --        if Asup:OnOpenARL() then self:SetScript("OnUpdate", nil) end
    --        self.t = 0
    --    else
    --        cnt = cnt + 1
    --        print(cnt)
    --    end
    --end)

    -- Подписываемся на событие открытие окна профессии
    --local AsupFrame = CreateFrame("Frame", "AsupFrame")
    --AsupFrame:RegisterEvent("TRADE_SKILL_SHOW")
    --    AsupFrame:SetScript("OnEvent", function(self, event)
    --    -- Сканируем через 0.5 сек после открытия, чтобы данные прогрузились
    --    C_Timer:After(0.5, OnOpenARL("trade"))
    --end)

    -- таймер на 6 часов
    --if Rdb.Meta.autoSync and (GetTime() - Rdb.Meta.lastUpdate > 21600) then
    --    LSW.UpdateRecipePrices()
    --    Rdb.Meta.lastUpdate = GetTime()
    --end

---@endregion hooks    
---==========================================
---@region init     ИНИЦИАЛИЗАЦИЯ
---==========================================

-- 1. Ждем появления кнопки Scan в окне профессий
--local f = CreateFrame("Frame", "Asup")
--f:RegisterEvent("TRADE_SKILL_SHOW")
--f:SetScript("OnEvent", function()
--    -- Кнопка ARL обычно называется AckisRecipeList.scan_button или аналогично
--    local scanBtn = AckisRecipeList.scan_button -- or _G["ARL_ScanButton"] 
--print("scan for scan activated")
--    if scanBtn and not scanBtn.isHooked then
--        hooksecurefunc(scanBtn, "OnClick", function()
--            -- 2. Кнопка нажата, фрейм MainPanel создается ПРЯМО СЕЙЧАС
--            -- Даем один кадр, чтобы ARL успел его проинициализировать
--            C_Timer.After(0.1, function()
--                print("ARL coming")
--                if AckisRecipeList.Frame and not AckisRecipeList.Frame.isHooked then
--                    -- 3. Теперь ставим хук на само наполнение списка
--                    hooksecurefunc(AckisRecipeList.Frame, "DisplayScan", function()
--                        DataCore:SyncVisiblePrices() -- Твой финальный вывод
--                    end)
--                    AckisRecipeList.Frame.isHooked = true
--                end
--            end)
--        end)
--        scanBtn.isHooked = true
--    end
--end)

-- Инициализация
--if not AckisRecipeList then return end
--if not Asup.hooked_ARL then
local cnt2, tic, now, lastUpdate = 0, 0, 0, 0
Asup.hooked_ARL, isPending = false, false
--    AckisRecipeList:TRADE_SKILL_UPDATE()
    hooksecurefunc(AckisRecipeList, "Scan", function()
        if not Asup.hooked_ARL then
            now = GetTime()
            tic = now - lastUpdate
            lastUpdate = now
            cnt = cnt + 1
            print("1  " .. cnt .. tic .. "  " .. now .. tostring(Asup.hooked_ARL))
            if tic > 0.5 then -- "Не беспокоить!"
                C_Timer:After(0.5, function() Asup:Init() end)
    end end end)

function Asup:Init()
    cnt2 = cnt2 + 1
    print("2  ", cnt, cnt2, tic, "  ", now, tostring(Asup.hooked_ARL))
    -- 1. Проверяем наличие фрейма. Если его нет, не выходим, а ждем!
    if not AckisRecipeList.Frame then return end
    if Asup.hooked_ARL then print("hooked 1") return end  -- Защита от дублей
    Asup.hooked_ARL = true              -- закрываем за собой дверь
    print("hooked 2")
    Asup:Interface()


    local frame = AckisRecipeList.Frame.list_frame
    -- 2. Хук на обновление списка (скролл, фильтры)
    hooksecurefunc(frame, "Update", function()
        C_Timer:After(0.1, function() Asup:OnUpdate() end)
    end)

    frame:HookScript("OnShow", function()
        C_Timer:After(0.7, function() Asup:OnShow() end)
        --C_Timer:After(0.7, function() LSW_DataCore:OpenARL(frame))
    end)
    ---- Если окно УЖЕ открыто в момент загрузки скрипта (например /reload)
    if frame:IsVisible() then
        Asup:OnUpdate()
    end
    print("|cff00ff00LSW-ARL:|r ARL hooks up.")
end

---@endregion init ----------------------------------------------------