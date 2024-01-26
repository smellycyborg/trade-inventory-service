local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Packages = ReplicatedStorage.Packages

local Knit = require(Packages.knit)
local Signal = require(Packages.signal)
local ItemNames = require(ReplicatedStorage:WaitForChild("ItemNames"))
local serverSignals = require(ServerStorage:WaitForChild("_serverSignals"))

local playerTabbedOut = serverSignals.playerTabbedOut

local Categories = {
    "Items", "Skills",
}

local DefaultItems = {
    Skills = "Dash", Items = "WoodenSword"
}

-- note: playerKey is player userId

local InventoryService = Knit.CreateService({
    Name = "InventoryService",
    Client = {
        InventoryChanged = Knit.CreateSignal(),
        EquippedChanged = Knit.CreateSignal(),
        PromptTradeRequest = Knit.CreateSignal(),
        PromptTradeProcessed = Knit.CreateSignal(),
        PromptTrade = Knit.CreateSignal(),
        DeclineTrade = Knit.CreateSignal(),
        UpdateAcceptedTab = Knit.CreateSignal(),
        UpdateTradingPlayer = Knit.CreateSignal(),
    },
    Signals = {
        updatePlayerSkills = Signal.new(),
    },
    InventoryPerPlayer = {},
    EquippedPerPlayer = {},
    TradesInProgress = {},
    TradesAccepted = {},
})

local function getOtherPlayer(otherPlayerName)
    local otherPlayer = nil
    for _, plr in Players:GetPlayers() do
        if otherPlayerName == plr.Name then
            return plr
        end
    end
    if not otherPlayer then
        return warn("Player was not found in the current game server.")
    end
end

function InventoryService:KnitInit()
    local function _cleanTrading(player)
        for tradeIndex, tradeInfo in self.TradesInProgress do
            if self.TradesAccepted[tradeIndex] then
                self.TradesAccepted[tradeIndex] = nil
            end

            if tradeInfo[player.UserId] then
                
                for playerKey, _ in tradeInfo do
                    local plr = Players:GetPlayerByUserId(playerKey)
                    if plr ~= player then
                        self.Client.DeclineTrade(plr)
                    end
                end

                self.TradesInProgress[tradeIndex] = nil
            end
        end
    end

    self.weldItemToHip = function(player, itemName)
        if string.len(itemName) <= 0 then
            return
        end
        
        local character = player.Character or player.CharacterAdded:Wait()
        local rootPart = character:WaitForChild("Torso")
        
        local sword = game.ReplicatedStorage.Items:FindFirstChild(itemName):Clone()
        local offset = CFrame.new(Vector3.new(1, -1, 0))
        local newPosition = rootPart.CFrame:ToWorldSpace(offset)
        
        sword.Parent = rootPart
        sword:SetPrimaryPartCFrame(newPosition)
        sword:SetAttribute("Sword", true)
        
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = rootPart
        weld.Part1 = sword.Handle
        weld.Parent = sword
    end

    local function characterAdded(character)
        local player = Players:GetPlayerFromCharacter(character)

        if string.len(self.EquippedPerPlayer[player]["Items"]) <= 0 then
            return
        end

        self.weldItemToHip(player, self.EquippedPerPlayer[player]["Items"])
    end

    local function playerAdded(player)
        self.InventoryPerPlayer[player] = {}
        self.EquippedPerPlayer[player] = {}

        for _, category in Categories do
            self.InventoryPerPlayer[player][category] = {}

            local value = category == "Items" and "" or {}
            self.EquippedPerPlayer[player][category] = value
        end

        player.CharacterAppearanceLoaded:Connect(characterAdded)
        -- print("InventoryService:  set inventory for player added.", self.InventoryPerPlayer[player])
    end

    local function playerRemoving(player)
        self.InventoryPerPlayer[player] = nil
        self.EquippedPerPlayer[player] = nil

        _cleanTrading(player)
    end

    for _, player in Players:GetPlayers() do
        task.spawn(playerAdded, player)
    end
    Players.PlayerAdded:Connect(playerAdded)
    Players.PlayerRemoving:Connect(playerRemoving)

    --print("InventoryService initialized.")
end

function InventoryService:KnitStart()
    DataService = Knit.GetService("DataService")

    local function onUpdateInventory(player, inventory, equipped)
        local playerInventory = self.InventoryPerPlayer[player]
        local playerEquipped = self.EquippedPerPlayer[player]

        local function _giveSkills()
            local skills = {"fireBall", "ghost"}
            for _, skill in skills do
                self:AddItem(player, "Skills", skill)
            end
            DataService:updateData(player, "Skills", self.InventoryPerPlayer[player]["Skills"])
        end

        local function _addAllItems()
            for _, rarity in ItemNames do
                for _, itemName in rarity["Items"] do
                    self:AddItem(player, "Items", itemName)
                end
            end
        end

        for key, value in inventory do
            self.InventoryPerPlayer[player][key] = value
        end
        for key, value in equipped do
            self.EquippedPerPlayer[player][key] = value
        end

        if not table.find(self.InventoryPerPlayer[player]["Skills"], "superSumo") then
            self:AddItem(player, "Skills", "superSumo")
            self:EquipItem(player, {"Skills", "superSumo"})

            DataService:updateData(player, "Skills", self.InventoryPerPlayer[player]["Skills"])
            DataService:updateData(player, "equippedSkill", self.EquippedPerPlayer[player]["Skills"])
        end

        if not table.find(self.InventoryPerPlayer[player]["Skills"], "fireBall") then
            _giveSkills()
        end

        if not self.InventoryPerPlayer[player]["Items"]["WoodenSword"] then
            self:AddItem(player, "Items", "WoodenSword")
            self:EquipItem(player, {"Items", "WoodenSword"})

            DataService:updateData(player, "equippedItem", "WoodenSword")
            DataService:updateData(player, "Items", self.InventoryPerPlayer[player]["Items"])
        end

        -- addings items per player name
        if player.Name == "crockpoti" then
            self.EquippedPerPlayer[player]["Items"] = "BoneSword"
            _addAllItems()
        elseif player.Name == "savian22" or player.Name == "thememermonkey" then
            self.EquippedPerPlayer[player]["Items"] = "IceDragon"
            _addAllItems()
        elseif player.Name == "Player1" then
            self:AddItem(player, "Skills", "fireBall")
            DataService:updateData(player, "Skills", self.InventoryPerPlayer[player]["Skills"])
        end

        self.Signals.updatePlayerSkills:Fire(player, self.EquippedPerPlayer[player]["Skills"])
        self.Client.InventoryChanged:Fire(player, self.InventoryPerPlayer[player])
        self.Client.EquippedChanged:Fire(player, self.EquippedPerPlayer[player])

        if not player.Character then
            player.CharacterAdded:Wait()
        end

        if not player.Character:FindFirstChild("Torso"):FindFirstChild(self.EquippedPerPlayer[player]["Items"]) then
            self.weldItemToHip(player, self.EquippedPerPlayer[player]["Items"])
        end

        -- warn("InventoryService:  should be updating inventory.", self.InventoryPerPlayer[player])
    end

    local function onUpdateEquipped(player, equipped)
        for key, value in equipped do
            self.EquippedPerPlayer[player][key] = value
        end
        self.Client.EquippedChanged:Fire(player, self.EquippedPerPlayer[player])
    end

    DataService.Signals.updateInventory:Connect(onUpdateInventory)
    DataService.Signals.updateEquipped:Connect(onUpdateEquipped)
    -- print("InventoryService started.")
end

function InventoryService:AddItem(player, category, itemName, amount)
    local playerInventory = self.InventoryPerPlayer[player]
    amount = amount or 1

    if category == "Items" then
        if not playerInventory[category][itemName] then
            playerInventory[category][itemName] = 1
        else
            playerInventory[category][itemName] += amount
        end
    elseif category == "Skills" then
        if table.find(playerInventory[category], itemName) then
            player:FindFirstChild("Diamonds").Value += 10000
            return warn("Player already has that skill.  have added diamonds instead.")
        else
            table.insert(playerInventory[category], itemName)
        end
    end
    
    -- if table.find(playerInventory[category], itemName) then
    --     return warn("InventoryService:  player already has item in their inventory.")
    -- end

    -- table.insert(playerInventory[category], itemName)

    self.Client.InventoryChanged:Fire(player, self.InventoryPerPlayer[player])
    for key, value in self.InventoryPerPlayer[player] do
        DataService:updateData(player, key, value)
    end
end

function InventoryService:RemoveItem(player, category, itemName, amount)
    amount = amount or 1

    local playerInventory = self.InventoryPerPlayer[player]

    if not playerInventory[category][itemName] then
        return
    end

    if playerInventory[category][itemName] <= 0 then
        return
    else
        playerInventory[category][itemName] -= amount
    end

    self.Client.InventoryChanged:Fire(player, self.InventoryPerPlayer[player])
    for key, value in self.InventoryPerPlayer[player] do
        DataService:updateData(player, key, value)
    end

    -- if not table.find(playerInventory[category], itemName) then
    --     return warn("InventoryService:  play does not have item in their inventory.")
    -- end

    -- table.remove(playerInventory[category], table.find(playerInventory[category], itemName))
end

function InventoryService:EquipItem(player, args)
    local playerInventory = InventoryService.InventoryPerPlayer[player]
    local playerEquipped = InventoryService.EquippedPerPlayer[player]

    local category, itemName = table.unpack(args)

    -- warn("Equip Item Name:  ", itemName)

    if playerEquipped[category] == itemName then
        return false, "InventoryService:  player already has the item equipped."
    end

    if category == "Skills" then
        if not table.find(playerInventory[category], itemName) then
            return false, "InventoryService:  player does not own skill."
        end
    elseif category == "Items" then
        if not playerInventory[category][itemName] then
            return false, "InventoryService:  player does not own item."
        else
            local character = player.Character
            if not character then
                return
            end

            local torso = character:WaitForChild("Torso", 5)
            if not torso then
                return
            end

            for _, model in torso:GetChildren() do
                if model:GetAttribute("Sword") and model:IsA("Model") then
                    model:Destroy()
                end
            end
        
            self.weldItemToHip(player, itemName)
        end
    end

    playerEquipped[category] = itemName

    for key, value in self.EquippedPerPlayer[player] do
        local keyToSend = ""

        if key == "Items" then
            keyToSend = "equippedItem"
        elseif key == "Skills" then
            keyToSend = "equippedSkill"
        end
        
        -- warn("supposed to have updated equipped item" , key, keyToSend)
        DataService:updateData(player, keyToSend, value)
    end

    print("Player has updated equipped ", self.EquippedPerPlayer[player])

    return self.EquippedPerPlayer[player]
end

function InventoryService:UnequipItem(player, args)
    local playerInventory = InventoryService.InventoryPerPlayer[player]
    local playerEquipped = InventoryService.EquippedPerPlayer[player]

    local category, itemName = table.unpack(args)

    if not playerInventory[category][itemName] then
        return false--, warn("InventoryService:  play does not have item in their inventory.")
    elseif playerEquipped[category] ~= itemName then
        return false--, warn("InventoryService:  does not have the item equipped.")
    end

    -- if not table.find(playerInventory[category], itemName) then
    --     return false, warn("InventoryService:  play does not have item in their inventory.")
    -- elseif playerEquipped[category] ~= itemName then
    --     return false, warn("InventoryService:  does not have the item equipped.")
    -- end

    playerEquipped[category] = DefaultItems[category]

    for key, value in self.EquippedPerPlayer[player] do
        local keyToSend = ""

        if key == "Items" then
            keyToSend = "equippedItem"
        elseif key == "Skills" then
            keyToSend = "equippedSkill"
        end
        
        DataService:updateData(player, keyToSend, value)
    end

    return self.EquippedPerPlayer[player]
end

--// Trading
function InventoryService:promptTradeRequest(playerRequested, otherPlayer)
    for tradeIndex, tradeInfo in self.TradesInProgress do
        if tradeInfo[otherPlayer.UserId] or tradeInfo[playerRequested.UserId] then
            return false, warn("already trading, can request to trade.")
        end
    end

    self.Client.PromptTradeRequest:Fire(otherPlayer, playerRequested)

    return true
end

function InventoryService:promptTradeRequestProcessed(playerResponded, otherPlayer, response)
    -- print("server has regstered trade response as ", response)

    if not response then
        self.Client.PromptTradeProcessed:Fire(otherPlayer, response)

        return
    end

    local newIndex = HttpService:GenerateGUID()
    self.TradesInProgress[newIndex] = {
        [playerResponded.UserId] = {},
        [otherPlayer.UserId] = {},
    }

    playerTabbedOut:Fire({playerResponded, otherPlayer})

    -- print("server has set new trade ", self.TradesInProgress[newIndex])
    self.Client.UpdateTradingPlayer:Fire(otherPlayer, playerResponded)
    for _, player in {playerResponded, otherPlayer} do
        self.Client.PromptTrade:Fire(player, self.TradesInProgress[newIndex])

        print("have prompted trade for ", player.Name)
    end
end

function InventoryService:addTradeItem(player, itemName)
    assert(itemName, "Attempt to index nil with argument 2 'itemName")

    if self.InventoryPerPlayer[player]["Items"][itemName] <= 0 then
        return warn("you don't have this item in your invetnory, check the spinner.")
    end

    -- warn("trading data:  ", self.TradesInProgress)
    for tradeIndex, tradeInfo in self.TradesInProgress do
        if tradeInfo[player.UserId] then
            if not self.TradesInProgress[tradeIndex][player.UserId][itemName] then
                self.TradesInProgress[tradeIndex][player.UserId][itemName] = 0
            end

            if self.InventoryPerPlayer[player]["Items"][itemName] <= tradeInfo[player.UserId][itemName] then
                return warn("you cannot trade this item anymore.")
            end

            self.TradesInProgress[tradeIndex][player.UserId][itemName] += 1

            for playerKey, _ in tradeInfo do
                local plr = Players:GetPlayerByUserId(playerKey)
                self.Client.PromptTrade:Fire(plr, self.TradesInProgress[tradeIndex])
            end

            return tradeInfo[player]
        end
    end
end

function InventoryService:deleteTradeItem(player, itemName)
    assert(itemName, "Attempt to index nil with argument 2 'itemName")

    for tradeIndex, tradeInfo in self.TradesInProgress do
        if tradeInfo[player.UserId] then
            self.TradesInProgress[tradeIndex][player.UserId][itemName] -= 1
            if self.TradesInProgress[tradeIndex][player.UserId][itemName] <= 0 then
                self.TradesInProgress[tradeIndex][player.UserId][itemName] = nil
            end

            for playerKey, _ in tradeInfo do
                local plr = Players:GetPlayerByUserId(playerKey)
                self.Client.PromptTrade:Fire(plr, self.TradesInProgress[tradeIndex])
            end

            return tradeInfo[player.UserId]
        end
    end
end

function InventoryService:acceptTrade(playerAccepting)
    local tradeProcessed = false

    local function swapToAdd(player, tab)
        for plr, items in tab do
            if plr ~= player.UserId then
                for itemName, amount in items do
                    self:AddItem(player, "Items", itemName, amount)
                end
            end
        end
    end

    local function updateAcceptedTab(tab, acceptedTab)
        for playerKey, _ in tab do
            local player = Players:GetPlayerByUserId(playerKey)
            self.Client.UpdateAcceptedTab:Fire(player, acceptedTab)
        end
    end

    for tradeIndex, tradeInfo in self.TradesInProgress do
        if tradeInfo[playerAccepting.UserId] then
            
            if not self.TradesAccepted[tradeIndex] then
                self.TradesAccepted[tradeIndex] = {}
            end

            if table.find(self.TradesAccepted[tradeIndex], playerAccepting) then
                return warn("player has already accepted trade.")
            end

            table.insert(self.TradesAccepted[tradeIndex], playerAccepting)
            updateAcceptedTab(self.TradesInProgress[tradeIndex], self.TradesAccepted[tradeIndex])

            local playersAccepted = 0
            for _, _player in self.TradesAccepted[tradeIndex] do
                playersAccepted+=1
            end

            if playersAccepted >= 2 then

                for playerKey, items in tradeInfo do
                    if next(items) then
                        for itemName, amount in items do
                            local plr = Players:GetPlayerByUserId(playerKey)
                            self:RemoveItem(plr, "Items", itemName, amount)
                        end
                    end

                    local plr = Players:GetPlayerByUserId(playerKey)
                    swapToAdd(plr, tradeInfo)

                    tradeProcessed = true
                    self.Client.PromptTrade:Fire(plr, {}, tradeProcessed)
                end
            end
        end

        if tradeProcessed then
            self.TradesInProgress[tradeIndex] = nil
            self.TradesAccepted[tradeIndex] = nil
        end
    end

    warn("trade has been completed and processed, here's the result.", tradeProcessed)
end

function InventoryService:declineTrade(playerDeclining)
    for tradeIndex, tradeInfo in self.TradesInProgress do
        if tradeInfo[playerDeclining.UserId] then
            for playerKey, _ in tradeInfo do
                if playerKey ~= playerDeclining.UserId then
                    local plr = Players:GetPlayerByUserId(playerKey)
                    self.Client.DeclineTrade:Fire(plr)
                    self.TradesInProgress[tradeIndex] = nil

                    if self.TradesAccepted[tradeIndex] then
                        self.TradesAccepted[tradeIndex] = nil
                    end
                end
            end
        end
    end
end

function InventoryService.Client:addTradeItem(player, itemName)
    return self.Server:addTradeItem(player, itemName)
end

function InventoryService.Client:deleteTradeItem(player, itemName)
    return self.Server:deleteTradeItem(player, itemName)
end

function InventoryService.Client:acceptTrade(playerAccepting)
    return self.Server:acceptTrade(playerAccepting)
end

function InventoryService.Client:declineTrade(playerDeclining)
    return self.Server:declineTrade(playerDeclining)
end

function InventoryService.Client:promptTradeRequest(playerRequested, otherPlayer)
    return self.Server:promptTradeRequest(playerRequested, otherPlayer)
end

function InventoryService.Client:promptTradeRequestProcessed(playerResponded, otherPlayer, response)
    return self.Server:promptTradeRequestProcessed(playerResponded, otherPlayer, response)
end

function InventoryService:getInventory(player)
    repeat
        task.wait(0.1)
        
    until next(self.InventoryPerPlayer[player]["Items"])
    return self.InventoryPerPlayer[player], self.EquippedPerPlayer[player]
end

function InventoryService.Client:EquipItem(player, args)
    return self.Server:EquipItem(player, args)
end

function InventoryService.Client:UnequipItem(player, args)
    return self.Server:UnequipItem(player, args)
end

function InventoryService.Client:getInventory(player)
    return self.Server:getInventory(player)
end

function InventoryService:getEquippedSkill(player)
    return self.EquippedPerPlayer[player]["Skills"]
end

return InventoryService
