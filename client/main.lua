local QBCore = exports[Config.Core]:GetCoreObject()

local signedIn = false
local CachedNet = nil
local blip = nil

-- Functions

function notification(title, msg, action)
    if Config.NotificationStyle == 'phone' then
        TriggerEvent('qb-phone:client:CustomNotification', title, msg, 'fas fa-user', '#b3e0f2', 5000)
    elseif Config.NotificationStyle == 'qbcore' then
        if title then
            QBCore.Functions.Notify(title..': '..msg, action, 5000)
        else
            QBCore.Functions.Notify(msg, action, 5000)
        end
    end
end

function CreateBlip(coords)
    blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipScale(blip, 0.7)
	SetBlipColour(blip, 3)
	SetBlipRoute(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName('Tow Call')
    EndTextCommandSetBlipName(blip)
end

local function RayCast(origin, target, options, ignoreEntity, radius)
    local handle = StartShapeTestSweptSphere(origin.x, origin.y, origin.z, target.x, target.y, target.z, radius, options, ignoreEntity, 0)
    return GetShapeTestResult(handle)
end

local function RequestControl(entity)
	local timeout = false
	if not NetworkHasControlOfEntity(entity) then
		NetworkRequestControlOfEntity(entity)

		SetTimeout(1000, function () timeout = true end)

		while not NetworkHasControlOfEntity(entity) and not timeout do
			NetworkRequestControlOfEntity(entity)
			Wait(100)
		end
	end
	return NetworkHasControlOfEntity(entity)
end

local function GetAttachOffset(pTarget)
	local model = GetEntityModel(pTarget)
	local minDim, maxDim = GetModelDimensions(model)
	local vehSize = maxDim - minDim
	return vector3(0, -(vehSize.y / 2), 0.4 - minDim.z)
end

local function GetEntityBehindTowTruck(towTruck, towDistance, towRadius)
    local forwardVector = GetEntityForwardVector(towTruck)
    local originCoords = GetEntityCoords(towTruck)
    local targetCoords = originCoords + (forwardVector * towDistance)

    local _, hit, _, _, targetEntity = RayCast(originCoords, targetCoords, 30, towTruck, towRadius or 0.2)

    return targetEntity
end

local function FindVehicleAttachedToVehicle(pVehicle)
	local handle, vehicle = FindFirstVehicle()
    local success

	repeat
		if GetEntityAttachedTo(vehicle) == pVehicle then
			return vehicle
		end

        success, vehicle = FindNextVehicle(handle)
	until not success

	EndFindVehicle(handle)
end

local function attachVehicleToBed(flatbed, target)
    local distance = #(GetEntityCoords(target) - GetEntityCoords(flatbed)) 
    local speed = GetEntitySpeed(target)

    if distance <= 15 and speed <= 3.0 then
        local offset = GetAttachOffset(target)
        if not offset then return end

        local hasControlOfTow = RequestControl(flatbed)
        local hasControlOfTarget = RequestControl(target)

        if hasControlOfTow and hasControlOfTarget then
            AttachEntityToEntity(target, flatbed, GetEntityBoneIndexByName(flatbed, 'bodyshell'), offset.x, offset.y, offset.z, 0, 0, 0, 1, 1, 0, 0, 0, 1)
            SetCanClimbOnEntity(target, false)
        end
    end
end

local function isTowVehicle(vehicle)
    local retval = false
    if GetEntityModel(vehicle) == GetHashKey("flatbed") then
        retval = true
    end
    return retval
end

local function getSpawn()
    for _, v in pairs(Config.VehicleSpawns) do
        if not IsAnyVehicleNearPoint(v.x, v.y, v.z, 4) then
            return v
        end
    end
end

local function signIn()
    local coords = getSpawn()
    if not coords then return QBCore.Functions.Notify("There's a vehicle in the way", 'error', 5000) end

    if Config.RenewedPhone and not exports[Config.Phone]:hasPhone() then return QBCore.Functions.Notify("You don\'t have a phone", 'error', 5000) end
    if signedIn then return end

    TriggerServerEvent('brazzers-tow:server:signIn', coords)
end

local function signOut()
    if not signedIn then return end
    TriggerServerEvent('brazzers-tow:server:forceSignOut')
end

local function forceSignOut()
    if not signedIn then return end

    signedIn = false
    notification("CURRENT", "You have signed out!", 'primary')
    RemoveBlip(blip)
end

RegisterNetEvent('brazzers-tow:client:truckSpawned', function(NetID, plate)
    if NetID and plate then
        CachedNet = NetID
        local vehicle = NetToVeh(NetID)
        exports[Config.Fuel]:SetFuel(vehicle, 100.0)
        TriggerServerEvent("qb-vehiclekeys:server:AcquireVehicleKeys", plate)
        notification("CURRENT", "You have signed in, vehicle outside", 'primary')
    end
    signedIn = true
end)

RegisterNetEvent('brazzers-tow:client:hookVehicle', function()
    local flatbed = NetworkGetEntityFromNetworkId(CachedNet)
    if not flatbed then return notification(_, 'Tow truck doesn\'t exist', 'error') end

    local target = GetEntityBehindTowTruck(flatbed, -8, 0.7)
    if not target or target == 0 then return notification(_, 'No vehicle found', 'error') end

    local targetModel = GetEntityModel(target)
    local targetClass = GetVehicleClass(target)
    local towTruckDriver = GetPedInVehicleSeat(NetworkGetEntityFromNetworkId(CachedNet), -1)

    if (Config.BlacklistedModels[targetModel] or Config.BlacklistedClasses[targetClass]) then
        return notification(_, 'You cannot tow this type of vehicle', 'error')
    end

    local targetDriver = GetPedInVehicleSeat(target, -1)
    if targetDriver ~= 0 then return notification(_, 'Vehicle must be empty', 'error') end

    if flatbed == target then return end
    if not isTowVehicle(flatbed) then return notification(_, 'You do not have a tow truck', 'error') end
    if GetEntityType(target) ~= 2 then return end

    local state = Entity(flatbed).state.FlatBed
    if not state then return end
    if state.carAttached then return notification(_, 'There is a vehicle attached already', 'error') end

    local towTruckCoords, targetCoords = GetEntityCoords(flatbed), GetEntityCoords(target)
    local distance = #(targetCoords - towTruckCoords)

    if distance <= 10 then
        TaskTurnPedToFaceCoord(PlayerPedId(), targetCoords, 1.0)
        Wait(1000)
        -- Animation

        QBCore.Functions.Progressbar("filling_nitrous", "Hooking up vehicle", 2500, false, false, {
            disableMovement = true,
            disableCarMovement = false,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function()
            QBCore.Functions.Progressbar("filling_nitrous", "Towing vehicle", 2500, false, false, {
                disableMovement = true,
                disableCarMovement = false,
                disableMouse = false,
                disableCombat = true,
            }, {}, {}, {}, function()
                local playerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(towTruckDriver))
                
                if playerId and playerId ~= 0 then
                    local targetNetId = NetworkGetNetworkIdFromEntity(target)
                    SetNetworkIdCanMigrate(targetNetId, true)
                    SetNetworkIdExistsOnAllMachines(targetNetId, true)
                    NetworkRegisterEntityAsNetworked(VehToNet(targetNetId))

                    TriggerServerEvent('brazzers-tow:server:syncActions', playerId, flatbed, targetNetId)
                else
                    attachVehicleToBed(flatbed, target)
                end

                TriggerServerEvent('brazzers-tow:server:syncHook', true, CachedNet, NetworkGetNetworkIdFromEntity(target))
            end, function()
                notification(_, 'Canceled', 'error')
            end)
        end, function()
            notification(_, 'Canceled', 'error')
        end)
    end
end)

RegisterNetEvent('brazzers-tow:client:unHookVehicle', function()
    local flatbed = NetworkGetEntityFromNetworkId(CachedNet)
    if not flatbed then return notification(_, 'Tow truck doesn\'t exist', 'error') end

    local target = FindVehicleAttachedToVehicle(flatbed)
    if not target or target == 0 then return end
    if flatbed == target then return end

    local state = Entity(flatbed).state.FlatBed
    if not state then return end
    if not state.carAttached then return notification(_, 'There is no vehicle attached to the bed', 'error') end

    TaskTurnPedToFaceEntity(PlayerPedId(), flatbed, 1.0)
    Wait(1000)
    -- Animation

    QBCore.Functions.Progressbar("untowing_vehicle", "Untowing vehicle", 2500, false, false, {
        disableMovement = true,
        disableCarMovement = false,
        disableMouse = false,
        disableCombat = true,
    }, {}, {}, {}, function()
        QBCore.Functions.Progressbar("unhooking_vehicle", "Unhooking vehicle", 2500, false, false, {
            disableMovement = true,
            disableCarMovement = false,
            disableMouse = false,
            disableCombat = true,
        }, {}, {}, {}, function()
            if not IsEntityAttachedToEntity(target, flatbed) then return notification(_, 'No vehicle attached', 'error') end

            local targetNetId = NetworkGetNetworkIdFromEntity(target)
            SetNetworkIdCanMigrate(targetNetId, true)
            SetNetworkIdExistsOnAllMachines(targetNetId, true)
            NetworkRegisterEntityAsNetworked(VehToNet(targetNetId))

            TriggerServerEvent('brazzers-tow:server:syncActions', nil, flatbed, targetNetId)
            TriggerServerEvent('brazzers-tow:server:syncHook', false, CachedNet, nil)
        end, function()
            notification(_, 'Canceled', 'error')
        end)
    end, function()
        notification(_, 'Canceled', 'error')
    end)
end)

RegisterNetEvent('brazzers-tow:client:syncActions', function(towTruck, target, syncAttach)
    local flatbed = towTruck
    local vehicle = NetworkGetEntityFromNetworkId(target)

    if syncAttach then -- This syncs attaching if a player is inside the tow trucks driver seat
        if DoesEntityExist(vehicle) then
            attachVehicleToBed(flatbed, vehicle)
            return
        end
    end

    if DoesEntityExist(vehicle) then
        print("SYNCING")
        local drop = GetOffsetFromEntityInWorldCoords(vehicle, 0.0,-5.5,0.0)

        if IsEntityAttachedToEntity(vehicle, flatbed) then
            DetachEntity(vehicle, true, true)
            Wait(100)
            SetEntityCoords(vehicle, drop)
            Wait(100)
            SetVehicleOnGroundProperly(vehicle)
        end
    end
end)

RegisterCommand('starttow', function()
    TriggerServerEvent('brazzers-tow:server:signIn', true)
end)

RegisterCommand('markfortow', function()
    TriggerEvent('brazzers-tow:client:requestTowTruck')
end)

RegisterCommand('checktow', function()
    local vehicle = QBCore.Functions.GetClosestVehicle()
    local plate = QBCore.Functions.GetPlate(vehicle)
    TriggerServerEvent('brazzers-tow:server:towVehicle', plate)
end)

RegisterCommand('hookvehicle', function()
    TriggerEvent('brazzers-tow:client:hookVehicle')
end)

RegisterCommand('hookvehicle2', function()
    TriggerEvent('brazzers-tow:client:unHookVehicle')
end)

RegisterCommand('depotvehicle', function()
    local vehicle = QBCore.Functions.GetClosestVehicle()
    local plate = QBCore.Functions.GetPlate(vehicle)
    TriggerServerEvent('brazzers-tow:server:depotVehicle', plate, false, 'check')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        RemoveBlip(blip)
    end
 end)







-- Threads

CreateThread(function()
    exports[Config.Target]:AddBoxZone("tow_signin", Config.LaptopCoords, 0.2, 0.4, {
        name = "tow_signin",
        heading = 117.93,
        debugPoly = false,
        minZ = Config.LaptopCoords.z,
        maxZ = Config.LaptopCoords.z + 1.0,
        }, {
            options = {
            {
                action = function()
                    signIn()
                end,
                icon = 'fas fa-hands',
                label = 'Sign In',
                canInteract = function()
                    if not signedIn then return true end
                end,
            },
            {
                action = function()
                    signOut()
                end,
                icon = 'fas fa-hands',
                label = 'Sign Out',
                canInteract = function()
                    if signedIn then return true end
                end,
            },
        },
        distance = 1.0,
    })
end)
