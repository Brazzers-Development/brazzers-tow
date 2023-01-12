local QBCore = exports[Config.Core]:GetCoreObject()

local function getReward(source)
    local Player = QBCore.Functions.GetPlayer(source)
    local repAmount = Player.PlayerData.metadata[Config.RepName]

    for k, _ in pairs(Config.RepLevels) do
        if repAmount >= Config.RepLevels[k]['repNeeded'] then
            return Config.RepLevels[k]['reward']
        end
    end
end

local function getMultiplier(source)
    local Player = QBCore.Functions.GetPlayer(source)
    local repAmount = Player.PlayerData.metadata[Config.RepName]

    for k, _ in pairs(Config.RepLevels) do
        if repAmount >= Config.RepLevels[k]['repNeeded'] then
            return Config.RepLevels[k]['reward']
        end
    end
end

function notification(source, title, msg, action)
    if Config.NotificationStyle == 'phone' then
        TriggerClientEvent('qb-phone:client:CustomNotification', source, title, msg, 'fas fa-user', '#b3e0f2', 5000)
    elseif Config.NotificationStyle == 'qbcore' then
        TriggerClientEvent('QBCore:Notify', source, msg, action)
    end
end

function createVehicle(source)
    while not QBCore do Wait(250) end

    local Player = QBCore.Functions.GetPlayer(source)
    local metaData = Player.PlayerData.metadata[Config.RepName] or 0

    local vehicle = {}
    local class = nil
    local chance = math.random(1, 100)

    if chance <= Config.RepLevels['S']['chance'] then
        if metaData >= Config.RepLevels['S']['repNeeded'] then
            class = 'S'
        else
            createVehicle(source)
        end
    elseif chance <= Config.RepLevels['A']['chance'] then
        if metaData >= Config.RepLevels['A']['repNeeded'] then
            class = 'A'
        else
            createVehicle(source)
        end
    elseif chance <= Config.RepLevels['B']['chance'] then
        if metaData >= Config.RepLevels['B']['repNeeded'] then
            class = 'B'
        else
            createVehicle(source)
        end
    elseif chance <= Config.RepLevels['C']['chance'] then
        if metaData >= Config.RepLevels['C']['repNeeded'] then
            class = 'C'
        else
            createVehicle(source)
        end
    else
        class = 'D'
    end

    Wait(0)

    if not class then return createVehicle(source) end

    for k, v in pairs(QBCore.Shared.Vehicles) do
        if v['category'] and v['category'] == class then
            vehicle[#vehicle + 1] = k
        end
    end
    if vehicle == 0 then return false end
    local index = vehicle[math.random(1, #vehicle)]
    local vehicle = QBCore.Shared.Vehicles[index]['model']
    if Config.Debug then print('Creating Vehicle: '..vehicle) end
    return vehicle
end

function moneyEarnings(source, class, inGroup)
    if not class then class = 'D' end
    if Config.Debug then print('Vehicle Class: '..class) end
    local Player = QBCore.Functions.GetPlayer(source)
    local payout = Config.Payout[Config.PayoutType][class]['payout']
    if not payout then payout = Config.BasePay end
    
    if Config.GroupExtraMoney and inGroup then
        local groupExtra = Config.GroupExtraMoney
        payout = payout + (math.ceil(payout * groupExtra))
    end

    Player.Functions.AddMoney('cash', math.ceil(payout))
    TriggerClientEvent('QBCore:Notify', source, Config.Lang['primary'][11]..''..payout)
end

function metaEarnings(source, inGroup)
    local Player = QBCore.Functions.GetPlayer(source)

    local curRep = Player.PlayerData.metadata[Config.RepName]
    local reward = getReward(source)

    if Config.AllowRep then
        local extra = getMultiplier(source)
        reward += extra
    end

    if Config.GroupExtraRep and inGroup then
        local groupExtra = Config.GroupExtraRep
        reward = reward + (math.ceil(reward * groupExtra))
    end

    Player.Functions.SetMetaData(Config.RepName, math.ceil((curRep + reward)))
end