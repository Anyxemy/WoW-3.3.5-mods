
-- arl_support.lua v0.7.0 (Sirus 3.3.5)
local LSW_DEBUG = false

local function dprint(...)
    if LSW_DEBUG then
        print("|cff00ff00LSW-ARL-DEBUG:|r", ...)
    end
end

local function GetFormattedPrice(amount)
    if not amount or amount <= 0 then return "|cff8080800|r" end
    if LSW and LSW.FormatMoney then 
        return LSW:FormatMoney(amount, true) 
    end
    return math.floor(amount / 10000) .. "g"
end


local function LSW_UpdateARL()
    local frame = AckisRecipeList.Frame
    if not frame or not frame.list_frame or not frame.list_frame:IsVisible() then return end

    local list_frame = frame.list_frame
    local buttons = list_frame.entry_buttons
    local entries = list_frame.entries

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

        -- data.recipe_id — это ID заклинания (spellID)
        if btn:IsVisible() and data and data.recipe_id and data.type == "header" then
            local spellID = data.recipe_id
            --local itemCost, skillCost = GetRecipeCostAnywhere(spellID, i)    -- rID - recipe, i - recipe list position
            -- Вместо вызова тяжелой функции GetRecipeCostAnywhere
            local cached = Rdb[spellID]
            if cached and cached.spellCost then
                local skillCost = cached.spellCost
                local itemCost = cached.spellValue -- Заранее сохраненный BOP
                -- ... форматирование и SetText ...
                if itemCost and itemCost > 0 or skillCost and skillCost > 0 then
                    local mktStr = GetFormattedPrice(itemCost)
                    local regStr = GetFormattedPrice(skillCost)

                    -- Подсветка профитности (опционально)
                    local color = "|cffffffff"
                    if (itemCost and itemCost > 0) and (skillCost and skillCost > 0) then
                        if tonumber(itemCost) > tonumber(skillCost) then color = "|cff00ff00" end -- Профит
                        if tonumber(itemCost) < tonumber(skillCost) then color = "|cffff0000" end -- Убыток
                    end

                    btn.lswText:SetText(string.format("%-5s%-5s|r | |cffaaaaaa%s|r", color, mktStr, regStr))
                    btn.lswText:Show()
                end
            else
                -- Если данных еще нет в Rdb, запускаем разовый расчет (не в цикле скролла!)
                -- Или просто пишем "...", пока Processor не доберется до этого ID
                btn.lswText:SetText("...") 
            end
        end
    end
end



-- ==========================================
-- 4. ИНИЦИАЛИЗАЦИЯ, СОБИТИЯ И ХУКИ
-- ==========================================


-- Инициализация без изменений
local function InitARL()
    local frame = AckisRecipeList.Frame
    if frame and frame.list_frame then
        local lf = frame.list_frame
        
        -- Хук на обновление списка (скролл, фильтры)
        hooksecurefunc(lf, "Update", function() 
            C_Timer:After(0.1, LSW_UpdateARL) 
        end)
        
        -- Хук на открытие самого окна
        frame:HookScript("OnShow", function()
            C_Timer:After(0.2, LSW_UpdateARL)
        end)

        -- Если окно УЖЕ открыто в момент загрузки скрипта (например /reload)
        if frame:IsVisible() then
            LSW_UpdateARL()
        end
        
        print("|cff00ff00LSW-ARL:|r Мост активирован. Цены загружаются при открытии.")
        return true
    end
    return false
end


local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function(self, elap)
    self.t = (self.t or 0) + elap
    if self.t > 2 then
        if InitARL() then self:SetScript("OnUpdate", nil) end
        self.t = 0
    end
end)
