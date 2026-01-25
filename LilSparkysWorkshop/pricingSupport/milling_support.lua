---@diagnostic disable: ambiguity-1, redundant-parameter



-- milling support





local enabled = true


do
-- results : [pigment][herb] = numMilled
	local millingResults = {
		[3358] = { -- Khadgar\'s Whisker
			[43105] = 1, --Indigo Pigment
			[39339] = 3, --Emerald Pigment
		},
		[765] = { -- Silverleaf
			[39151] = 3, --Alabaster Pigment
		},
		[8831] = { -- Purple Lotus
			[39340] = 2.5, --Violet Pigment
			[43106] = 0.5, --Ruby Pigment
		},
		[2453] = { -- Bruiseweed
			[43103] = 1, --Verdant Pigment
			[39334] = 3, --Dusky Pigment
		},
		[13463] = { -- Dreamfoil
			[39341] = 2.5, --Silvery Pigment
			[43107] = 0.5, --Sapphire Pigment
		},
		[13464] = { -- Golden Sansam
			[39341] = 2.5, --Silvery Pigment
			[43107] = 0.5, --Sapphire Pigment
		},
		[13465] = { -- Mountain Silversage
			[39341] = 3, --Silvery Pigment
			[43107] = 1, --Sapphire Pigment
		},
		[785] = { -- Mageroyal
			[43103] = 0.5, --Verdant Pigment
			[39334] = 2.5, --Dusky Pigment
		},
		[36901] = { -- Goldclover
			[43109] = 0.5, --Icy Pigment
			[39343] = 2.5, --Azure Pigment
		},
		[8836] = { -- Arthas\' Tears
			[39340] = 2.5, --Violet Pigment
			[43106] = 0.5, --Ruby Pigment
		},
		[36905] = { -- Lichbloom
			[43109] = 1, --Icy Pigment
			[39343] = 3, --Azure Pigment
		},
		[36907] = { -- Talandra\'s Rose
			[43109] = 0.5, --Icy Pigment
			[39343] = 2.5, --Azure Pigment
		},
		[8838] = { -- Sungrass
			[39340] = 2.5, --Violet Pigment
			[43106] = 0.5, --Ruby Pigment
		},
		[4625] = { -- Firebloom
			[39340] = 2.5, --Violet Pigment
			[43106] = 0.5, --Ruby Pigment
		},
		[8839] = { -- Blindweed
			[39340] = 3, --Violet Pigment
			[43106] = 1, --Ruby Pigment
		},
		[3369] = { -- Grave Moss
			[43104] = 0.5, --Burnt Pigment
			[39338] = 2.5, --Golden Pigment
		},
		[3818] = { -- Fadeleaf
			[43105] = 0.5, --Indigo Pigment
			[39339] = 2.5, --Emerald Pigment
		},
		[22785] = { -- Felweed
			[39342] = 3, --Nether Pigment
			[43108] = 0.5, --Ebon Pigment
		},
		[22786] = { -- Dreaming Glory
			[39342] = 2.5, --Nether Pigment
			[43108] = 0.5, --Ebon Pigment
		},
		[22787] = { -- Ragveil
			[39342] = 2.5, --Nether Pigment
			[43108] = 0.5, --Ebon Pigment
		},
		[8845] = { -- Ghost Mushroom
			[39340] = 3, --Violet Pigment
			[43106] = 1, --Ruby Pigment
		},
		[22790] = { -- Ancient Lichen
			[39342] = 3, --Nether Pigment
			[43108] = 1, --Ebon Pigment
		},
		[8846] = { -- Gromsblood
			[39340] = 3, --Violet Pigment
			[43106] = 1, --Ruby Pigment
		},
		[22792] = { -- Nightmare Vine
			[39342] = 3, --Nether Pigment
			[43108] = 1, --Ebon Pigment
		},
		[2449] = { -- Earthroot
			[39151] = 3, --Alabaster Pigment
		},
		[3355] = { -- Wild Steelbloom
			[43104] = 0.5, --Burnt Pigment
			[39338] = 2.5, --Golden Pigment
		},
		[3820] = { -- Stranglekelp
			[43103] = 1, --Verdant Pigment
			[39334] = 3, --Dusky Pigment
		},
		[2450] = { -- Briarthorn
			[43103] = 0.5, --Verdant Pigment
			[39334] = 3, --Dusky Pigment
		},
		[36904] = { -- Tiger Lily
			[43109] = 0.5, --Icy Pigment
			[39343] = 3, --Azure Pigment
		},
		[36906] = { -- Icethorn
			[43109] = 1, --Icy Pigment
			[39343] = 3, --Azure Pigment
		},
		[39969] = { -- Fire Seed
			[39343] = 2.5, --Azure Pigment
		},
		[3821] = { -- Goldthorn
			[43105] = 0.5, --Indigo Pigment
			[39339] = 2.5, --Emerald Pigment
		},
		[22793] = { -- Mana Thistle
			[39342] = 3, --Nether Pigment
			[43108] = 1, --Ebon Pigment
		},
		[22791] = { -- Netherbloom
			[39342] = 3, --Nether Pigment
			[43108] = 1, --Ebon Pigment
		},
		[22789] = { -- Terocone
			[39342] = 2.5, --Nether Pigment
			[43108] = 0.5, --Ebon Pigment
		},
		[3819] = { -- Wintersbite
			[43105] = 1, --Indigo Pigment
			[39339] = 3, --Emerald Pigment
		},
		[3357] = { -- Liferoot
			[43104] = 1, --Burnt Pigment
			[39338] = 3, --Golden Pigment
		},
		[13466] = { -- Plaguebloom
			[39341] = 3, --Silvery Pigment
			[43107] = 1, --Sapphire Pigment
		},
		[13467] = { -- Icecap
			[39341] = 3, --Silvery Pigment
			[43107] = 1, --Sapphire Pigment
		},
		[3356] = { -- Kingsblood
			[43104] = 1, --Burnt Pigment
			[39338] = 3, --Golden Pigment
		},
		[2447] = { -- Peacebloom
			[39151] = 3, --Alabaster Pigment
		},
		[2452] = { -- Swiftthistle
			[43103] = 0.5, --Verdant Pigment
			[39334] = 3, --Dusky Pigment
		},
		[36903] = { -- Adder\'s Tongue
			[43109] = 1.25, --Icy Pigment
			[39343] = 3, --Azure Pigment
		},
		[37921] = { -- Deadnettle
			[43109] = 0.5, --Icy Pigment
			[39343] = 3, --Azure Pigment
		},
		[39970] = { -- Fire Leaf
			[43109] = 0.5, --Icy Pigment
			[39343] = 2.5, --Azure Pigment
		},
	}

	local millBrackets =
	{
		[2449] = 1,
		[2447] = 1,
		[765] = 1,

		[2450] = 25,
		[2453] = 25,
		[785] = 25,
		[3820] = 25,
		[2452] = 25,

		[3369] = 75,
		[3356] = 75,
		[3357] = 75,
		[3355] = 75,

		[3818] = 125,
		[3821] = 125,
		[3358] = 125,
		[3819] = 125,

		[8836] = 175,
		[8839] = 175,
		[4625] = 175,
		[8845] = 175,
		[8846] = 175,
		[8831] = 175,
		[8838] = 175,

		[13463] = 225,
		[13464] = 225,
		[13467] = 225,
		[13465] = 225,
		[13466] = 225,

		[22790] = 275,
		[22786] = 275,
		[22785] = 275,
		[22793] = 275,
		[22791] = 275,
		[22792] = 275,
		[22787] = 275,
		[22789] = 275,

		[36903] = 325,
		[37921] = 325,
		[39970] = 325,
		[36901] = 325,
		[36906] = 325,
		[36905] = 325,
		[36907] = 325,
		[36904] = 325,
	}


	local millingLevels = {
		[1] = { "playerMillLevel", 1},
		[25] = { "playerMillLevel", 25},
		[75] = { "playerMillLevel", 75},
		[125] = { "playerMillLevel", 125},
		[175] = { "playerMillLevel", 175},
		[225] = { "playerMillLevel", 225},
		[275] = { "playerMillLevel", 275},
		[325] = { "playerMillLevel", 325},
	}

	local pigmentSources = {}


	local function BuildPigmentSources()
		for herbID, pigmentTable in pairs(millingResults) do
			for pigmentID, count in pairs(pigmentTable) do
				if not pigmentSources[pigmentID] then
					pigmentSources[pigmentID] = {}
				end

				pigmentSources[pigmentID][herbID] = count
			end
		end
	end


	-- spoof recipes for milled herbs -> pigments
	local function AddToRecipeCache()
		for herbID, pigmentTable in pairs(millingResults) do
			local reagentTable = {}
			local recipeName = "Mill "..(GetItemInfo(herbID) or "item:"..herbID)

			reagentTable[herbID] = 5

			LSW:AddRecipe(-herbID, recipeName, pigmentTable, reagentTable, millingLevels[herbID])
		end
	end



	local function GetMillingSources(itemID)
		return millingResults[itemID]
	end


	local function GetMillingValue(itemID)
		local millingTable = millingResults[itemID]

		local value = 0

		if (millingTable) then
			for pigmentID, count in pairs(millingTable) do
				value = value + (LSW.auctionValue(pigmentID) or 0) * (count or 1)
			end

			return value
		end
	end


	local function GetPigmentSources(itemID)
		return pigmentSources[itemID]
	end



	local function Init()
--		LSW:ChatMessage("LilSparky's Workshop adding native Milling support")

		BuildPigmentSources()
		AddToRecipeCache()

		LSW.getMillingValue = GetMillingValue
		LSW.getMillingResults = GetMillingSources
		LSW.getPigmentSources = GetPigmentSources
	end


	local function Test(index)
		if enabled then
			return true
		end

		return false
	end

	LSW:RegisterPricingSupport("Milling", Test, Init)
end


