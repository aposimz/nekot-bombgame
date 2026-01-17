-- 招待リスト
local function getNearbyPlayersServerIds(range)
    local result = {}
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    for _, playerIdx in ipairs(GetActivePlayers()) do
        if playerIdx ~= PlayerId() then
            local ped = GetPlayerPed(playerIdx)
            if ped ~= 0 then
                local coords = GetEntityCoords(ped)
                local dx, dy, dz = myCoords.x - coords.x, myCoords.y - coords.y, myCoords.z - coords.z
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist <= range then
                    local sid = GetPlayerServerId(playerIdx)
                    if sid and sid > 0 then
                        result[#result + 1] = { serverId = sid, name = GetPlayerName(playerIdx), distance = dist }
                    end
                end
            end
        end
    end
    table.sort(result, function(a, b) return a.distance < b.distance end)
    return result
end

RegisterNetEvent('bombgame:ui:openInviteList')
AddEventHandler('bombgame:ui:openInviteList', function()
    local players = getNearbyPlayersServerIds(Config.InviteRange or 25.0)
    local options = {}
    for _, p in ipairs(players or {}) do
        options[#options+1] = {
            title = ('%s (ID:%d)'):format(p.name or 'Player', p.serverId),
            onSelect = function()
                
                local input = lib.inputDialog('賭け金の入力', {
                    { type = 'number', label = '賭け金 ($)', required = false, min = (Config.Betting and Config.Betting.MinAmount) or 0, max = (Config.Betting and Config.Betting.MaxAmount) or 10000000000, default = (Config.Betting and Config.Betting.DefaultAmount) or 0 }
                })
                if not input then
                    TriggerEvent('bombgame:ui:openInviteList')
                    return
                end
                local amount = tonumber(input[1]) or 0
                amount = math.floor(math.max((Config.Betting and Config.Betting.MinAmount) or 0, math.min(amount, (Config.Betting and Config.Betting.MaxAmount) or 10000000000)))
                if amount >= 0 then
                    TriggerServerEvent('bombgame:invite', p.serverId, amount)
                else
                    TriggerEvent('bombgame:ui:openInviteList')
                end
            end
        }
    end
    lib.registerContext({
        id = 'bombgame_invite_menu',
        title = 'BombGame: 犯罪利用・悪用禁止',
        options = (function()
            if next(options) then return options end
            return {
                { title = '近くにプレイヤーがいません', disabled = true },
                { title = 'ゲームをキャンセル', description = '現在のゲームを終了', onSelect = function()
                    TriggerServerEvent('bombgame:cancel')
                end }
            }
        end)(),
        onClose = function()
            TriggerServerEvent('bombgame:cancel')
        end
    })
    lib.showContext('bombgame_invite_menu')
end)

RegisterNetEvent('bombgame:ui:openVehicleSetup')
AddEventHandler('bombgame:ui:openVehicleSetup', function()
    lib.registerContext({
        id = 'bombgame_vehicle_menu',
        title = 'BombGame: 車両登録',
        options = {
            {
                title = '今乗っている車を登録',
                onSelect = function()
                    TriggerEvent('bombgame:client:setup_vehicle')
                end
            }
        }
    })
    lib.showContext('bombgame_vehicle_menu')
    SetNuiFocusKeepInput(true)
end)

RegisterNetEvent('bombgame:ui:openNumberSelect')
AddEventHandler('bombgame:ui:openNumberSelect', function()
    local options = {}
    for i = 1, 25 do
        options[#options+1] = {
            title = ('数字 %02d'):format(i),
            onSelect = function()
                TriggerServerEvent('bombgame:number_select', i)
            end
        }
    end
    lib.registerContext({
        id = 'bombgame_number_menu',
        title = 'BombGame: 数字を選択',
        options = options
    })
    lib.showContext('bombgame_number_menu')
end)


