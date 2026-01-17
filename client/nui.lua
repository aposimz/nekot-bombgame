-- 選択はNUI内で保持、OKで送信

RegisterNUICallback('ui:guess', function(data, cb)
    local n = tonumber(data and data.n)
    if n and n >= 1 and n <= 25 then
        TriggerServerEvent('bombgame:turn_action', n)
    end
    cb(1)
end)

RegisterNUICallback('ui:cancel', function(_, cb)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    cb(1)
    TriggerServerEvent('bombgame:cancel')
end)

RegisterNUICallback('ui:ok', function(data, cb)
    local n = tonumber(data and data.n)
    if n and n >= 1 and n <= 25 then
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            TriggerEvent('ox_lib:notify', { type = 'error', description = '決定するには車に乗ってください' })
            SetNuiFocus(false, false)
            cb(1)
            return
        end
        TriggerServerEvent('bombgame:number_select', n)
    end
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    cb(1)
end)


