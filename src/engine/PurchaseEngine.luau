--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")

local ReceiptStore = DataStoreService:GetDataStore("PurchaseReceipts_v1")
local PurchaseEngine = {}

-- Product ID to handler mapping
local productHandlers = {
	[123456789] = function(player: Player, receiptInfo: MarketplaceService.ProcessReceiptInfo)
		-- Grant 100 Coins
		print(`Granted 100 coins to {player.Name}`)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
}

MarketplaceService.ProcessReceipt = function(receiptInfo: MarketplaceService.ProcessReceiptInfo)
	local playerId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId
	local receiptId = tostring(receiptInfo.PurchaseId)
	
	local handler = productHandlers[productId]
	if not handler then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	-- Idempotency check: Has this receipt ID already been processed?
	local success, isProcessed = pcall(function()
		return ReceiptStore:GetAsync("Receipt_" .. receiptId)
	end)
	
	if success and isProcessed then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	
	-- Execute the reward logic
	local decision = handler(game.Players:GetPlayerByUserId(playerId), receiptInfo)
	
	if decision == Enum.ProductPurchaseDecision.PurchaseGranted then
		-- Mark as processed only AFTER successful reward
		pcall(function()
			ReceiptStore:SetAsync("Receipt_" .. receiptId, true)
		end)
	end
	
	return decision
end

return PurchaseEngine