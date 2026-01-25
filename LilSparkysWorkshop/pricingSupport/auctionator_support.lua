---@diagnostic disable: undefined-global





-- auctionatorsupport


do

	local function DisenchantValue(itemID)
		return Atr_GetDisenchantValue(itemID)
	end


    local function AuctionPrice(itemID)
	    local p2 = Auctionator.API.v1.GetAuctionPriceByItemID("LSW", itemID)
		if p2 then return p2
--		else
--			p2 = Atr_GetAuctionBuyout(itemID)
--           	return p2
		end
--        return 0
    end


	local function Init()
		LSW:ChatMessage("LilSparky's Workshop adding Auctionator support")

		LSW:RegisterAlgorithm("Auctionator", AuctionPrice)

		LSW.disenchantValue = DisenchantValue
	end


	local function Test(index)
		if Auctionator.API.v1.GetAuctionPriceByItemID or Atr_GetAuctionBuyout then
			return true
		end

		return false
	end

	LSW:RegisterPricingSupport("Auctionator", Test, Init)
end
    