local activeGames = {}
local playerToGameId = {}
local nextGameId = 1

local function logDebug(msg, ...)
    if Config and Config.Debug and Config.Debug.EnableLogs then
        local args = { ... }
        for i = 1, #args do
            if type(args[i]) == 'number' then
                args[i] = math.floor(args[i])
            end
        end
        print(('[nekot-bombgame][server] ' .. msg):format(table.unpack(args)))
    end
end

local QBCore = exports['qb-core'] and exports['qb-core']:GetCoreObject() or nil

if QBCore then
    QBCore.Functions.CreateCallback('bombgame:IsVehicleOwned', function(source, cb, plate)
        if Config.Debug.EnableLogs then
            print("DEBUG: Plate for query:", '"' .. plate .. '"')
        end
        
        local result = exports.oxmysql:singleSync('SELECT citizenid FROM player_vehicles WHERE plate = ?', { plate })
        
        if Config.Debug.EnableLogs then
            print("DEBUG: Query result:", json.encode(result))
        end
        
        if not result then
            cb(false, nil)
            return
        end
        
        local citizenId = result.citizenid
        
        if Config.Debug.EnableLogs then
            print("DEBUG: Citizen ID field:", citizenId)
        end
        
        if not citizenId then
            if Config.Debug.EnableLogs then
                print("DEBUG: No citizen ID found in record")
            end
            cb(false, nil)
            return
        end
        
        local currentPlayer = QBCore.Functions.GetPlayer(source)
        local currentCitizenId = currentPlayer.PlayerData.citizenid
        
        if Config.Debug.EnableLogs then
            print("DEBUG: Current citizenid:", currentCitizenId)
            print("DEBUG: Owner citizenid:", citizenId)
        end
        
        local isOwned = (currentCitizenId == citizenId)
        
        local ownerName = nil
        if isOwned then
            ownerName = currentPlayer.PlayerData.charinfo.firstname .. ' ' .. currentPlayer.PlayerData.charinfo.lastname
        end
        
        if Config.Debug.EnableLogs then
            print("DEBUG: Is owned:", isOwned)
        end
        cb(isOwned, ownerName)
    end)
end


local function qb_getBalance(playerId)
    if not QBCore then return 0 end
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player or not Player.PlayerData or not Player.PlayerData.money then return 0 end
    local bal = tonumber(Player.PlayerData.money['bank'] or 0) or 0
    return bal
end

local function qb_addMoney(playerId, amount)
    if not QBCore then return false end
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end
    Player.Functions.AddMoney('bank', amount)
    return true
end

local function qb_removeMoney(playerId, amount)
    if not QBCore then return false end
    local Player = QBCore.Functions.GetPlayer(playerId)
    if not Player then return false end
    return Player.Functions.RemoveMoney('bank', amount)
end

local function findGameForPlayer(src)
    for gid, game in pairs(activeGames) do
        if game.host == src or game.guest == src or game.invited == src then
            return gid, game
        end
    end
    return nil, nil
end

local function findWaitingInviteByHost(src)
    for gid, game in pairs(activeGames) do
        if game.host == src and game.state == 'waiting_invite' then
            return gid, game
        end
    end
    return nil, nil
end


local function clearGame(gameId, reason)
    local game = activeGames[gameId]
    if not game then return end

    if game.host then 
        playerToGameId[game.host] = nil
        logDebug('Reset host flag for player %d', game.host)
    end
    if game.guest then 
        playerToGameId[game.guest] = nil
        logDebug('Reset guest flag for player %d', game.guest)
    end

    TriggerClientEvent('bombgame:end', game.host or -1, reason or 'ended')
    if game.guest then TriggerClientEvent('bombgame:end', game.guest, reason or 'ended') end

    if game.invited and game.invited ~= game.host and game.invited ~= game.guest then
        TriggerClientEvent('bombgame:end', game.invited, reason or 'ended')
    end

    activeGames[gameId] = nil
    logDebug('Game %d cleared. reason=%s', gameId, reason or 'n/a')
end

local function startVehicleSetupTimeout(gid)
    local timeoutSec = (Config and Config.Timeouts and Config.Timeouts.VehicleSetup) or 45
    SetTimeout(timeoutSec * 1000, function()
        local game = activeGames[gid]
        if not game then return end
        if game.state == 'setup_vehicle' then
            if game.host then TriggerClientEvent('ox_lib:notify', game.host, { type = 'error', description = '車両登録がタイムアウトしました' }) end
            if game.guest then TriggerClientEvent('ox_lib:notify', game.guest, { type = 'error', description = '車両登録がタイムアウトしました' }) end
            clearGame(gid, 'timeout_vehicle')
        end
    end)
end

local function startInviteTimeout(gid)
    local timeoutSec = (Config and Config.Timeouts and Config.Timeouts.Invite) or 30
    SetTimeout(timeoutSec * 1000, function()
        local game = activeGames[gid]
        if not game then return end
        if game.state == 'waiting_invite' and game.invited and not game.guest then
            local hostId = game.host
            if hostId then
                TriggerClientEvent('ox_lib:notify', hostId, {
                    type = 'inform',
                    description = '招待がタイムアウトしました。/bombgame を再実行してください'
                })
            end
            local invitedId = game.invited
            if invitedId then
                TriggerClientEvent('ox_lib:notify', invitedId, {
                    type = 'error',
                    description = '招待がタイムアウトしました'
                })
            end
            logDebug('Game %d invite timeout -> clear', gid)
            clearGame(gid, 'invite_timeout')
        end
    end)
end

local function startNumberSelectTimeout(gid)
    local timeoutSec = (Config and Config.Timeouts and Config.Timeouts.NumberSelect) or 60
    SetTimeout(timeoutSec * 1000, function()
        local game = activeGames[gid]
        if not game then return end
        if game.state == 'select_number' then
            if game.host then TriggerClientEvent('ox_lib:notify', game.host, { type = 'error', description = '数字選択がタイムアウトしました' }) end
            if game.guest then TriggerClientEvent('ox_lib:notify', game.guest, { type = 'error', description = '数字選択がタイムアウトしました' }) end
            clearGame(gid, 'timeout_select')
        end
    end)
end

local function startTurnTimeout(gid, expectedTurn)
    local timeoutSec = (Config and Config.Timeouts and Config.Timeouts.Turn) or 30
    SetTimeout(timeoutSec * 1000, function()
        local game = activeGames[gid]
        if not game then return end
        if game.state == 'in_turn' and game.turn == expectedTurn then
            if game.host then TriggerClientEvent('ox_lib:notify', game.host, { type = 'error', description = 'ターン操作がタイムアウトしました' }) end
            if game.guest then TriggerClientEvent('ox_lib:notify', game.guest, { type = 'error', description = 'ターン操作がタイムアウトしました' }) end
            clearGame(gid, 'timeout_turn')
        end
    end)
end

AddEventHandler('playerDropped', function()
    local src = source
    local gid = playerToGameId[src]
    if gid then
        clearGame(gid, 'playerDropped')
        return
    end
    
    for agid, ag in pairs(activeGames) do
        if ag.host == src or ag.guest == src or ag.invited == src then
            clearGame(agid, 'playerDropped')
            return
        end
    end
end)

local function handleStartCommand(src, args, raw)
    if args and args[1] and args[1] == 'reset' then
        local gid = playerToGameId[src]
        if gid and activeGames[gid] then
            clearGame(gid, 'cancelled_by_command')
            TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = 'ゲームをリセットしました' })
        else
            TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = '参加中のゲームはありません' })
        end
        return
    end

    do
        local egid, egame = findGameForPlayer(src)
        if egid and egame then
            if egame.state == 'waiting_invite' and egame.host == src then
                clearGame(egid, 'host_restart')
            else
                TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = '既にゲームに参加中です（/bombgame reset でリセット）' })
                return
            end
        end
    end
    local gid = nextGameId
    nextGameId = nextGameId + 1
    activeGames[gid] = { id = gid, host = src, state = 'waiting_invite' }
    TriggerClientEvent('bombgame:start', src, gid)
    logDebug('Host %d started game %d', src, gid)
end

-- RegisterCommand('bombgame', function(src, args, raw)
--     handleStartCommand(src, args, raw)
-- end, false)
RegisterCommand('bombgame', function(src, args, raw)
    handleStartCommand(src, args, raw)
end, false)

-- ラジアルメニュー用のゲーム開始イベント
RegisterNetEvent('bombgame:startFromMenu', function()
    local src = source
    handleStartCommand(src, {}, '')
end)

TriggerEvent('chat:addSuggestion', '/bombgame', 'ミニゲーム:犯罪利用・悪用禁止', {
    { name = 'reset', help = '現在のゲームをリセット' }
})

RegisterNetEvent('bombgame:invite', function(targetId, betAmount)
    local src = source
    local gid, game = findWaitingInviteByHost(src)
    if not gid or not game then return end
    if betAmount and betAmount > 0 then
        local minA = (Config.Betting and Config.Betting.MinAmount) or 0
        local maxA = (Config.Betting and Config.Betting.MaxAmount) or 10000000000
        betAmount = math.floor(math.max(minA, math.min(betAmount, maxA)))
        local hostBal = qb_getBalance(src)
        logDebug('Host %d balance: %d, required: %d', src, hostBal, betAmount)
        if hostBal < betAmount then
            TriggerClientEvent('ox_lib:notify', src, { 
                type = 'error', 
                description = string.format('所持金が足りません。残高: $%d, 必要: $%d', hostBal, betAmount) 
            })
            return
        end
    end
    if playerToGameId[targetId] then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = '相手は既に参加中です' })
        return
    end

    do
        local tgid, tgame = findGameForPlayer(targetId)
        if tgid and tgame then
            if not (tgame.state == 'waiting_invite' and tgame.host == targetId) then
                TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = '相手は既に参加中です' })
                return
            end
        end
    end

    local hostPed = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetId)
    if not hostPed or hostPed == 0 or not targetPed or targetPed == 0 then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = '対象が無効です' })
        return
    end

    local hc = GetEntityCoords(hostPed)
    local tc = GetEntityCoords(targetPed)
    local dx, dy, dz = (hc.x - tc.x), (hc.y - tc.y), (hc.z - tc.z)
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist > (Config.InviteRange or 25.0) then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = '対象は範囲外です' })
        return
    end
    game.invited = targetId
    game.betAmount = betAmount and math.floor(betAmount) or ((Config.Betting and Config.Betting.DefaultAmount) or 0)
    TriggerClientEvent('bombgame:invited', targetId, src, gid, game.betAmount)
    logDebug('Host %d invited %d for game %d bet=%s', src, targetId, gid, tostring(game.betAmount))
    startInviteTimeout(gid)
end)

RegisterNetEvent('bombgame:accept', function(gid)
    local src = source
    local game = activeGames[gid]
    if not game or game.invited ~= src or game.guest then return end

    if game.betAmount and game.betAmount > 0 then
        local minA = (Config.Betting and Config.Betting.MinAmount) or 0
        local maxA = (Config.Betting and Config.Betting.MaxAmount) or 10000000000
        local required = math.floor(math.max(minA, math.min(game.betAmount, maxA)))
        local guestBal = qb_getBalance(src)
        logDebug('Guest %d balance: %d, required: %d', src, guestBal, required)
        if guestBal < required then
            TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = '所持金が足りません' })
            game.invited = nil
            TriggerClientEvent('bombgame:declined', game.host, src)
            return
        end
    end

    do
        local hgid, hgame = findWaitingInviteByHost(src)
        if hgid and hgame then
            clearGame(hgid, 'replaced_by_accept')
        end
    end
    game.guest = src
    game.state = 'setup_vehicle'
    TriggerClientEvent('bombgame:accepted', game.host, src)
    TriggerClientEvent('bombgame:accepted', src, game.host)
    logDebug('Guest %d accepted for game %d', src, gid)
    startVehicleSetupTimeout(gid)
end)

RegisterNetEvent('bombgame:decline', function(gid)
    local src = source
    local game = activeGames[gid]
    if not game or game.invited ~= src or game.guest then return end
    game.invited = nil
    TriggerClientEvent('bombgame:declined', game.host, src)
    logDebug('Guest %d declined for game %d', src, gid)
end)

RegisterNetEvent('bombgame:setup_vehicle', function(entityNetId)
    local src = source
    local gid, game
    for _gid, g in pairs(activeGames) do
        if g.state == 'setup_vehicle' and (g.host == src or g.guest == src) then
            gid, game = _gid, g
            break
        end
    end
    if not game then return end
    
    local vehicle = NetworkGetEntityFromNetworkId(entityNetId)
    if not DoesEntityExist(vehicle) then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = '車両が見つかりません' })
        return
    end
    
    if not playerToGameId[src] then
        playerToGameId[src] = gid
        logDebug('Mapped %d to game %d at setup_vehicle()', src, gid)
    end
    game.vehicles = game.vehicles or {}
    game.readyVehicle = game.readyVehicle or {}
    game.vehicles[src] = entityNetId
    game.readyVehicle[src] = true
    
    local playerName = GetPlayerName(src) or "Unknown"
    local plate = GetVehicleNumberPlateText(vehicle)
    print(string.format("[nekot-bombgame] PARTICIPANT: %s:%s", playerName, plate))
    
    logDebug('Player %d set vehicle %s in game %d', src, tostring(entityNetId), gid)
    if game.readyVehicle[game.host] and game.readyVehicle[game.guest] then
        game.state = 'select_number'
        TriggerClientEvent('bombgame:vehicle_setup_done', game.host)
        if game.guest then TriggerClientEvent('bombgame:vehicle_setup_done', game.guest) end
        startNumberSelectTimeout(gid)
    end
end)

RegisterNetEvent('bombgame:number_select', function(number)
    local src = source
    local gid = playerToGameId[src]
    local game = gid and activeGames[gid]
    if not game or game.state ~= 'select_number' then return end
    game.numbers = game.numbers or {}
    if number < 1 or number > 25 then return end
    
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = 'プレイヤーが無効です' })
        return
    end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = '車に乗っていません（決定できません）' })
        return
    end
    game.numbers[src] = number
    logDebug('Player %d selected number %d in game %d', src, number, gid)
    if game.numbers[game.host] and game.numbers[game.guest] then
        local coin = math.random(0, 1)
        game.turn = coin == 0 and game.host or game.guest
        game.state = 'in_turn'
        TriggerClientEvent('bombgame:turn_start', game.host, game.turn)
        TriggerClientEvent('bombgame:turn_start', game.guest, game.turn)
        logDebug('Game %d turn start, first=%d', gid, game.turn)
        startTurnTimeout(gid, game.turn)
    end
end)

RegisterNetEvent('bombgame:turn_action', function(guess)
    local src = source
    local gid = playerToGameId[src]
    local game = gid and activeGames[gid]
    if not game or game.state ~= 'in_turn' or game.turn ~= src then return end
    if guess < 1 or guess > 25 then return end
    local opponent = (src == game.host) and game.guest or game.host
    local hit = game.numbers and (game.numbers[opponent] == guess)

    if game.host then TriggerClientEvent('bombgame:turn_guess', game.host, guess, src) end
    if game.guest then TriggerClientEvent('bombgame:turn_guess', game.guest, guess, src) end
    if hit then
        game.state = 'countdown'
        game.winner = src
        game.loser = opponent

        if game.betAmount and game.betAmount > 0 then
            local minA = (Config.Betting and Config.Betting.MinAmount) or 0
            local maxA = (Config.Betting and Config.Betting.MaxAmount) or 10000000000
            local amount = math.floor(math.max(minA, math.min(game.betAmount, maxA)))
            logDebug('Transferring $%d from player %d to player %d', amount, game.loser, game.winner)
            local ok1 = qb_removeMoney(game.loser, amount)
            local ok2 = qb_addMoney(game.winner, amount)
            logDebug('Transfer result: remove=%s, add=%s', tostring(ok1), tostring(ok2))
            if ok2 then
                if game.winner then TriggerClientEvent('ox_lib:notify', game.winner, { type = 'success', description = ('+$%d'):format(amount) }) end
            end
            if ok1 then
                if game.loser then TriggerClientEvent('ox_lib:notify', game.loser, { type = 'error', description = ('-$%d'):format(amount) }) end
            end
        end
        TriggerClientEvent('bombgame:countdown', -1, gid, game.winner, game.loser)
        logDebug('Game %d guessed correctly. winner=%d loser=%d', gid, src, opponent)
        SetTimeout((Config.Timeouts.Countdown or 10) * 1000, function()
            if not activeGames[gid] then return end
            TriggerClientEvent('bombgame:explode', opponent, game.vehicles and game.vehicles[opponent])
            TriggerClientEvent('bombgame:end', game.host, 'finished')
            if game.guest then TriggerClientEvent('bombgame:end', game.guest, 'finished') end
            clearGame(gid, 'finished')
        end)
    else
        game.turn = opponent
        TriggerClientEvent('bombgame:turn_start', game.host, game.turn)
        TriggerClientEvent('bombgame:turn_start', game.guest, game.turn)
        startTurnTimeout(gid, game.turn)
    end
end)

RegisterNetEvent('bombgame:cancel', function()
    local src = source
    local gid = playerToGameId[src]
    local game = gid and activeGames[gid]
    if game then
        if game.state == 'countdown' then return end
        clearGame(gid, 'cancelled')
        return
    end

    for agid, ag in pairs(activeGames) do
        if ag.state == 'waiting_invite' then
            if ag.invited == src then
                if ag.host then
                    TriggerClientEvent('ox_lib:notify', ag.host, { type = 'error', description = '相手が招待画面を閉じたため、ゲームを終了しました' })
                end
                clearGame(agid, 'invited_cancel')
                return
            end
            if ag.host == src then
                clearGame(agid, 'host_cancelled_waiting')
                return
            end
        elseif ag.state == 'setup_vehicle' and (ag.host == src or ag.guest == src) then
            clearGame(agid, 'setup_cancelled')
            return
        end
    end
end)

AddEventHandler('onResourceStop', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    for gid, _ in pairs(activeGames) do
        clearGame(gid, 'resourceStop')
    end
end)


