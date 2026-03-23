local function cashtruckheist(data)
    local coords = data.coords

    local dispatchData = {
        message = locale('cashtruckheist'),
        codeName = 'CashTruckHeist',
        code = '10-90',
        icon = 'fas fa-truck',
        priority = 2,
        coords = coords,
        gender = GetPlayerGender(),
        street = GetStreetAndZone(coords),
        alertTime = nil,
        jobs = { 'leo' }
    }

    TriggerServerEvent('ps-dispatch:server:notify', dispatchData)
end

exports('cashtruckheist', cashtruckheist)