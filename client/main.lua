local QBCore = exports['qb-core']:GetCoreObject()

local currentGameId = nil
local vehicleConfirmOpen = false
local nextConfirmShowAt = 0
local vehicleConfirmSuppressed = false
local vehicleSelectionDone = false
local vehicleConfirmThreadActive = false

local function notify(data)
    TriggerEvent('ox_lib:notify', data)
end

-- 車両登録前のチェック関数（車両クラス + 所有者チェック）
local function validateVehicle(vehicle)
    local vehClass = GetVehicleClass(vehicle)
    
    if Config.Debug.EnableLogs then
        print("DEBUG: Vehicle class =", vehClass)
    end
    
    local excludedClasses = Config.VehicleRegistration.ExcludedClasses or {}
    for _, class in ipairs(excludedClasses) do
        if vehClass == class then
            if Config.Debug.EnableLogs then
                print("DEBUG: Excluded class detected:", class)
            end
            notify({ type = 'error', description = 'この車両は登録できません（除外対象クラス）' })
            return false
        end
    end
    
    if Config.VehicleRegistration.RequireOwnership then
        local plate = QBCore.Functions.GetPlate(vehicle)
        local playerName = GetPlayerName(PlayerId())
        
        if Config.Debug.EnableLogs then
            print("DEBUG: Vehicle plate:", plate)
            print("DEBUG: Player name:", playerName)
        end
        
        local isOwned = nil
        local ownerName = nil
        QBCore.Functions.TriggerCallback('bombgame:IsVehicleOwned', function(owned, owner)
            isOwned = owned
            ownerName = owner
        end, plate)
        
        while isOwned == nil do
            Wait(10)
        end
        
        if Config.Debug.EnableLogs then
            print("DEBUG: Vehicle owner:", ownerName or "Unknown")
            print("DEBUG: Current player:", playerName)
        end
        
        if not isOwned then
            if Config.Debug.EnableLogs then
                print("DEBUG: Vehicle ownership check failed - not owned")
            end
            notify({ type = 'error', description = '所有していない車両は登録できません' })
            return false
        end
        
        if Config.Debug.EnableLogs then
            print("DEBUG: Vehicle ownership check passed")
        end
    end
    
    if Config.Debug.EnableLogs then
        print("DEBUG: Vehicle validation passed")
    end
    return true
end


RegisterNetEvent('bombgame:start', function(gid)
    currentGameId = gid
    notify({ type = 'inform', description = '対戦相手を選択してください' })
    TriggerEvent('bombgame:ui:openInviteList')
end)

RegisterNetEvent('bombgame:invited', function(hostId, gid, betAmount)
    if exports and exports.ox_lib and exports.ox_lib.hideContext then
        exports.ox_lib:hideContext(true)
    end
    currentGameId = gid
    if exports and exports.ox_lib and exports.ox_lib.registerContext then
        local hostIdx = GetPlayerFromServerId and GetPlayerFromServerId(hostId) or -1
        local hostName = (hostIdx and hostIdx ~= -1) and GetPlayerName(hostIdx) or ('ID:' .. tostring(hostId))
        exports.ox_lib:registerContext({
            id = 'bombgame_invite_menu',
            title = ('BombGame: 招待 from %s (ID:%s)'):format(hostName, tostring(hostId)),
            options = {
                { title = '参加する', description = (betAmount and betAmount > 0) and ('賭け金: $%d'):format(betAmount) or nil, onSelect = function() TriggerServerEvent('bombgame:accept', currentGameId) end },
                { title = '断る', onSelect = function() TriggerServerEvent('bombgame:decline', currentGameId) end },
            },
            onClose = function()
                TriggerServerEvent('bombgame:cancel')
            end
        })
        exports.ox_lib:showContext('bombgame_invite_menu')
    end
end)

RegisterNetEvent('bombgame:accepted', function(opponentId)
    notify({ type = 'success', description = ('参加が確定しました。相手: %s'):format(opponentId) })
    if vehicleSelectionDone or vehicleConfirmThreadActive then
        return
    end
    vehicleConfirmThreadActive = true
    local timeoutSec = (Config and Config.Timeouts and Config.Timeouts.VehicleSetup) or 30
    SendNUIMessage({ action = 'vehicle_message', show = true, message = ('%d秒以内に車に乗り、登録を完了してください。'):format(timeoutSec) })
    CreateThread(function()
        local confirmed = false
        local lastVehicle = 0
        
        while not confirmed and not vehicleSelectionDone and currentGameId do
            Wait(100)
            local ped = PlayerPedId()
            
            if IsPedInAnyVehicle(ped, false) then
                local veh = GetVehiclePedIsIn(ped, false)
                
                if veh ~= lastVehicle and veh ~= 0 and GetGameTimer() >= nextConfirmShowAt then
                    if exports and exports.ox_lib and exports.ox_lib.registerContext and not vehicleConfirmOpen and not vehicleConfirmSuppressed then
                        vehicleConfirmOpen = true
                        exports.ox_lib:hideContext(true)
                        exports.ox_lib:registerContext({
                            id = 'bombgame_vehicle_confirm',
                            title = 'この車を登録しますか？',
                            options = {
                                { title = 'はい', onSelect = function()
                                    if not validateVehicle(veh) then
                                        vehicleConfirmOpen = false
                                        nextConfirmShowAt = GetGameTimer() + 5000
                                        exports.ox_lib:hideContext()
                                    else
                                        local netId = NetworkGetNetworkIdFromEntity(veh)
                                        vehicleConfirmSuppressed = true
                                        TriggerServerEvent('bombgame:setup_vehicle', netId)
                                        confirmed = true
                                        vehicleSelectionDone = true
                                        vehicleConfirmOpen = false
                                        nextConfirmShowAt = 0
                                        SendNUIMessage({ action = 'vehicle_message', show = false })
                                        exports.ox_lib:hideContext()
                                    end
                                end },
                                { title = 'いいえ', onSelect = function()
                                    vehicleConfirmOpen = false
                                    nextConfirmShowAt = GetGameTimer() + 5000
                                    exports.ox_lib:hideContext()
                                end },
                            }
                        })
                        exports.ox_lib:showContext('bombgame_vehicle_confirm')
                    end
                    lastVehicle = veh
                end
            else
                lastVehicle = 0
            end
        end
        vehicleConfirmOpen = false
        nextConfirmShowAt = 0
        vehicleConfirmThreadActive = false
    end)
end)

RegisterNetEvent('bombgame:declined', function(opponentId)
    notify({ type = 'error', description = ('%s は参加を拒否しました'):format(opponentId) })
    TriggerEvent('bombgame:ui:openInviteList')
end)

RegisterNetEvent('bombgame:vehicle_setup_done', function()
    if exports and exports.ox_lib and exports.ox_lib.hideContext then
        exports.ox_lib:hideContext()
    end
    vehicleSelectionDone = true
    vehicleConfirmSuppressed = false
    vehicleConfirmThreadActive = false
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUIMessage({ action = 'mode', mode = 'select' })
end)

RegisterNetEvent('bombgame:turn_start', function(turnPlayer)
    local isMine = (turnPlayer == PlayerId()) or (GetPlayerServerId(PlayerId()) == turnPlayer)
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(true)
    SendNUIMessage({ action = 'mode', mode = 'turn', yourTurn = isMine, turn = turnPlayer })
end)

RegisterNetEvent('bombgame:countdown', function(gid, winner, loser)
    if currentGameId ~= gid then return end
    local mySid = GetPlayerServerId(PlayerId())
    local role = 'spectator'
    if mySid == winner then
        role = 'winner'
    elseif mySid == loser then
        role = 'loser'
    end
    SendNUIMessage({ action = 'countdown', seconds = (Config.Timeouts.Countdown or 10), role = role })
end)

RegisterNetEvent('bombgame:turn_guess', function(guess, whoServerId)
    local mySid = GetPlayerServerId(PlayerId())
    local mine = (whoServerId == mySid)
    SendNUIMessage({ action = 'turn_guess', guess = guess, mine = mine })
end)

RegisterNetEvent('bombgame:explode', function(vehicleNetId)
    if not vehicleNetId then return end
    local veh = NetToVeh(vehicleNetId)
    if veh and DoesEntityExist(veh) then
        local coords = GetEntityCoords(veh)
        AddExplosion(coords.x, coords.y, coords.z, 2, 1.0, true, false, 1.0)
    end
end)

RegisterNetEvent('bombgame:end', function(reason)
    currentGameId = nil
    if exports and exports.ox_lib and exports.ox_lib.hideContext then
        exports.ox_lib:hideContext(true)
    end
    SendNUIMessage({ action = 'close' })
    SendNUIMessage({ action = 'vehicle_message', show = false })
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    vehicleConfirmOpen = false
    vehicleConfirmSuppressed = false
    vehicleSelectionDone = false
    vehicleConfirmThreadActive = false
    nextConfirmShowAt = 0
    
    if reason == 'timeout_vehicle' then
        notify({ type = 'error', description = '車両登録がタイムアウトしました' })
    elseif reason == 'timeout_select' then
        notify({ type = 'error', description = '数字選択がタイムアウトしました' })
    elseif reason == 'timeout_turn' then
        notify({ type = 'error', description = 'ターン操作がタイムアウトしました' })
    elseif reason == 'invite_timeout' then
        notify({ type = 'error', description = '招待がタイムアウトしました' })
    elseif reason == 'finished' or reason == 'cancelled' or reason == 'cancelled_by_command' then
        notify({ type = 'inform', description = 'ゲーム終了: ' .. tostring(reason) })
    end
end)

RegisterNetEvent('bombgame:client:setup_vehicle', function()
    if not currentGameId then return end
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        notify({ type = 'error', description = '車両に乗っていません' })
        return
    end
    local veh = GetVehiclePedIsIn(ped, false)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    TriggerServerEvent('bombgame:setup_vehicle', netId)
end)


