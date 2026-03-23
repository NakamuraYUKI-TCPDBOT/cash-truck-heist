local npc, heistBlip, exchangeBlip = nil, nil, nil
local heistActive, heistLocation, truck, guards = false, nil, nil, {}
local bombTimer, bombActive, guardsAttacked, bombProp = 0, false, false, nil
local showBombCountdown, bombCountdownValue = false, 0
local lootPos = nil
local lootCollected = false
local truckCoords = nil
local exchangeVeh = nil
local escortVeh = nil
local npcLocked = false
local placingBomb = false
local heistOwnerClient = nil
local truckSpawnedClient = false
local truckRequested = false

----------------------------
-- 共用項目
----------------------------
function DrawText3D(coords, text)
    SetTextScale(0.3, 0.3)
    SetTextFont(1)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

function loadModel(model)
    if type(model) == 'number' then
        model = model
    else
        model = GetHashKey(model)
    end
    while not HasModelLoaded(model) do
        RequestModel(model)
        Citizen.Wait(0)
    end
end

function loadAnimDict(dict)
    while not HasAnimDictLoaded(dict) do
        RequestAnimDict(dict)
        Citizen.Wait(0)
    end
end

function addBlip(coords, sprite, colour, text)
    local blip = AddBlipForCoord(coords)
    SetBlipSprite(blip, sprite)
    SetBlipColour(blip, colour)
    SetBlipScale(blip, 1.0)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(text)
    EndTextCommandSetBlipName(blip)
    return blip
end

GrabCash = {
    animations = {
        {'enter', 'enter_bag', 'enter_cash'},
        {'grab', 'grab_bag', 'grab_cash'},
        {'grab', 'grab_bag', 'grab_cash'},
        {'exit', 'exit_bag'}
    }
}

----------------------------
-- 1. 受注関係NPC
----------------------------
Citizen.CreateThread(function()
    local npcConfig = Config.CashTruckHeist.npc
    local model = GetHashKey(npcConfig.model)
    loadModel(model)
    npc = CreatePed(4, model, npcConfig.coords.x, npcConfig.coords.y, npcConfig.coords.z - 1.0, npcConfig.heading,false, true)
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    FreezeEntityPosition(npc, true)
    exports.ox_target:addLocalEntity(npc, {
        {
            name = 'cash_truck_heist_start',
            icon = 'fa-solid fa-truck',
            label = '現金輸送車強盗を始める',
            distance = 2.5,
            canInteract = function()
                return not heistActive and not npcLocked
            end,
            onSelect = function()
                TriggerServerEvent('cash-truck-heist:requestStart')
            end
        }
    })
end)

-- リセットNPC
Citizen.CreateThread(function()
    local npcConfig = Config.CashTruckHeist.resetnpc
    local model = GetHashKey(npcConfig.model)
    loadModel(model)
    local resetnpc = CreatePed(4, model, npcConfig.coords.x, npcConfig.coords.y, npcConfig.coords.z - 1.0, npcConfig.heading,false, true)
    SetEntityInvincible(resetnpc, true)
    SetBlockingOfNonTemporaryEvents(resetnpc, true)
    FreezeEntityPosition(resetnpc, true)
    exports.ox_target:addLocalEntity(resetnpc, {
        {
            name = 'cash_truck_heist_reset',
            icon = 'fa-solid fa-rotate',
            label = '強盗をリセットする',
            distance = 2.5,
            canInteract = function()
                return heistActive
                and heistOwnerClient
                and GetPlayerServerId(PlayerId()) == heistOwnerClient
                and not truckSpawnedClient
            end,
            onSelect = function()
                TriggerServerEvent('cash-truck-heist:forceReset')
            end
        }
    })
end)

RegisterNetEvent('cash-truck-heist:setOwner', function(id)
    heistOwnerClient = id
end)

----------------------------
-- 2. サーバーから現場座標通知→ブリップ作成
----------------------------
RegisterNetEvent('cash-truck-heist:notifyLocation', function(location)
    heistActive = true
    lootCollected = false
    bombActive = false
    guardsAttacked = false
    bombTimer = 0
    lootPos = nil
    bombProp = nil
    truck, guards, bombActive, bombTimer, guardsAttacked = nil, {}, false, 0, false
    heistLocation = location
    if heistBlip then
        RemoveBlip(heistBlip)
        heistBlip = nil
    end
    heistBlip = AddBlipForCoord(location.coords.x, location.coords.y, location.coords.z)
    SetBlipSprite(heistBlip, 67)
    SetBlipColour(heistBlip, 5)
    SetBlipScale(heistBlip, 1.0)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("現金輸送車")
    EndTextCommandSetBlipName(heistBlip)
    truckCoords = location.coords
    exports.qbx_core:Notify("ここに現金輸送車がいるみたいだ", "inform", 5000)
    CreateThread(function()
        Wait(5000)
        exports.qbx_core:Notify("現金輸送車用爆弾がいる", "inform", 10000)
    end)
end)


----------------------------
-- 3. 現場到着→サーバーに通知して車両スポーン
----------------------------
RegisterNetEvent('cash-truck-heist:setTruckSpawned', function(state)
    truckSpawnedClient = state
end)
Citizen.CreateThread(function()
    while true do
        Wait(1000)
        if heistActive and heistLocation and not truck and not truckRequested then
            local player = PlayerPedId()
            local dist = #(GetEntityCoords(player) - heistLocation.coords)
            if dist < 80.0 then
                TriggerServerEvent('cash-truck-heist:spawnTruck')
                truckRequested = true
            end
        end
    end
end)

----------------------------
-- 4. 車両・NPCスポーン
----------------------------
RegisterNetEvent('cash-truck-heist:spawnTruckAndGuards', function(location)
    loadModel(Config.CashTruckHeist.truck.model)
    truck = CreateVehicle(GetHashKey(Config.CashTruckHeist.truck.model),location.coords.x,location.coords.y,location.coords.z,location.heading,true,false)
    if heistBlip then RemoveBlip(heistBlip) end
    heistBlip = AddBlipForEntity(truck)
    SetBlipSprite(heistBlip, 67)
    SetBlipColour(heistBlip, 5)
    SetBlipScale(heistBlip, 1.0)
    SetVehicleOnGroundProperly(truck)
    SetVehicleDoorsLocked(truck, 1)
    SetVehicleEngineOn(truck, true, true, false)
    SetEntityAsMissionEntity(truck, true, true)
    truckCoords = GetEntityCoords(truck)
    loadModel(Config.CashTruckHeist.guard.model)
    local truckDriver = nil
    for seat = -1, 1 do
        local ped = CreatePedInsideVehicle(truck,4,GetHashKey(Config.CashTruckHeist.guard.model),seat,true,false)
        SetEntityAsMissionEntity(ped, true, true)
        SetPedRelationshipGroupHash(ped, GetHashKey("HATES_PLAYER"))
        SetPedCombatAttributes(ped, 46, true)
        SetPedFleeAttributes(ped, 0, false)
        SetPedAccuracy(ped, 70)
        SetEntityMaxHealth(ped, Config.CashTruckHeist.guard.health)
        SetEntityHealth(ped, Config.CashTruckHeist.guard.health)
        SetPedArmour(ped, Config.CashTruckHeist.guard.armor)
        GiveWeaponToPed(ped, GetHashKey("WEAPON_ASSAULTRIFLE"), 250, false, true)
        guards[#guards+1] = ped
        if seat == -1 then
            truckDriver = ped
        end
    end
    TaskVehicleDriveToCoordLongrange(truckDriver,truck,location.coords.x + 300.0,location.coords.y + 300.0,location.coords.z,25.0,786603,5.0)
    -- 護衛車
    loadModel("granger")
    local escortOffset1 = GetOffsetFromEntityInWorldCoords(truck, 0.0, -8.0, 0.0)
    escortVeh = CreateVehicle(GetHashKey("granger"),escortOffset1.x,escortOffset1.y,escortOffset1.z,location.heading,true,false)
    SetVehicleOnGroundProperly(escortVeh)
    SetVehicleEngineOn(escortVeh, true, true, false)
    local escortDriver1 = nil
    for seat = -1, 2 do
        local ped = CreatePedInsideVehicle(escortVeh,4,GetHashKey(Config.CashTruckHeist.guard.model),seat,true,false)
        SetPedRelationshipGroupHash(ped, GetHashKey("HATES_PLAYER"))
        SetPedCombatAttributes(ped, 46, true)
        SetPedFleeAttributes(ped, 0, false)
        GiveWeaponToPed(ped, GetHashKey("WEAPON_ASSAULTRIFLE"), 250, false, true)
        guards[#guards+1] = ped
        if seat == -1 then
            escortDriver1 = ped
        end
    end
    CreateThread(function()
        Wait(2000)
        while heistActive and DoesEntityExist(escortVeh) and DoesEntityExist(truck) do
            Wait(2000)
            if escortDriver1 and DoesEntityExist(escortDriver1) then
                if not IsPedInVehicle(escortDriver1, escortVeh, false) then
                    TaskWarpPedIntoVehicle(escortDriver1, escortVeh, -1)
                end
                local dist = #(GetEntityCoords(escortVeh) - GetEntityCoords(truck))
                if dist > 10.0 then
                    TaskVehicleDriveToCoord(escortDriver1,escortVeh,GetEntityCoords(truck),40.0,0,GetEntityModel(escortVeh),786603,5.0,true)
                else
                    TaskVehicleFollow(escortDriver1,escortVeh,truck,12.0,786603,2.0)
                end
            end
        end
    end)
end)

----------------------------
-- 5. NPC攻撃
----------------------------
RegisterNetEvent('cash-truck-heist:guardsAttack', function()
    local player = PlayerPedId()
    if escortVeh and DoesEntityExist(escortVeh) then
        SetVehicleEngineOn(escortVeh,false,true,true)
        local driver = GetPedInVehicleSeat(escortVeh,-1)
        if driver and driver ~= 0 then
            TaskVehicleTempAction(driver, escortVeh, 27, 3000)
        end
    end
    Wait(1200)
    for _, ped in ipairs(guards) do
    if DoesEntityExist(ped) and not IsEntityDead(ped) then
        if IsPedInAnyVehicle(ped) then
            local veh = GetVehiclePedIsIn(ped,false)
            ClearPedTasksImmediately(ped)
            SetPedCanRagdoll(ped, false)
            TaskLeaveVehicle(ped, veh, 0)
            Wait(500)
            SetPedCanRagdoll(ped, true)
            CreateThread(function()
                Wait(1500)
                if IsPedInAnyVehicle(ped) then
                    TaskLeaveVehicle(ped, veh, 16)
                end
            end)
        end
        SetPedCombatAttributes(ped, 46, true)
        SetPedCombatMovement(ped, 2)
        SetPedCombatRange(ped, 2)
        TaskCombatPed(ped, PlayerPedId(), 0, 16)
    end
end
    Wait(2000)
    for _, ped in ipairs(guards) do
        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            SetPedCombatAttributes(ped,46,true)
            SetPedCombatMovement(ped,2)
            SetPedCombatRange(ped,2)
            SetPedCombatAbility(ped,2)
            TaskCombatPed(ped,player,0,16)
        end
    end
    exports.qbx_core:Notify("護衛がいるみたいだ...", "error", 5000)
end)
----------------------------
-- 6.車停止
----------------------------
Citizen.CreateThread(function()
    while true do
        Wait(1000)
        if truck and heistActive and not guardsAttacked then
            if DoesEntityExist(truck) then
                local speed = GetEntitySpeed(truck) * 3.6
                if speed < 3.0 then
                    guardsAttacked = true
                    TriggerEvent('cash-truck-heist:guardsAttack')
                end

            end

        end
    end
end)
----------------------------
-- 7. 爆弾設置
----------------------------
Citizen.CreateThread(function()
        while true do
        Wait(0)
        if truck and heistActive and not bombActive and not placingBomb then
            local player = PlayerPedId()
            local playerCoords = GetEntityCoords(player)
            local boneIndex = GetEntityBoneIndexByName(truck, "handle_pside_r")
            if boneIndex ~= -1 then
                local rearDoor = GetWorldPositionOfEntityBone(truck, boneIndex)
                local dist = #(playerCoords - rearDoor)
                if dist < 2.5 then
                    DrawText3D(vector3(rearDoor.x, rearDoor.y, rearDoor.z + 0.7), "[E] 現金輸送車用爆弾を設置")
                    if IsControlJustReleased(0, 38) then
                        placingBomb = true
                        TriggerServerEvent('cash-truck-heist:tryPlaceBomb')
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('cash-truck-heist:placeBombResult', function(success, msg)
    placingBomb = false
    if success then
        local boneIndex = GetEntityBoneIndexByName(truck, "handle_pside_r")
        local pos
        local heading
        if boneIndex ~= -1 then
            pos = GetWorldPositionOfEntityBone(truck, boneIndex)
            heading = GetEntityHeading(truck)
        else
            pos = GetEntityCoords(truck)
            heading = GetEntityHeading(truck)
        end
        lootPos = pos
        PlantBombAnim(pos, heading)
        bombActive = true
        exports.qbx_core:Notify("現金輸送車用爆弾を設置した", "success", 3000)
        TriggerServerEvent('cash-truck-heist:startBomb')
    else
        bombActive = false
        exports.qbx_core:Notify(msg or "現金輸送車用爆弾を忘れているみたいだ...", "error", 3000)
    end
end)

function PlantBombAnim(pos, heading)
    loadAnimDict("anim@heists@ornate_bank@thermal_charge")
    loadModel("hei_p_m_bag_var22_arm_s")
    loadModel("prop_bomb_01")
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityHeading(ped, heading)
    Wait(100)
    local rotx, roty, rotz = table.unpack(vec3(GetEntityRotation(ped)))
    local bagscene = NetworkCreateSynchronisedScene(pos.x,pos.y,pos.z,rotx,roty,rotz,2,false,false,1065353216,0,1.3)
    local bag = CreateObject(`hei_p_m_bag_var22_arm_s`, pos.x, pos.y, pos.z, true, true, false)
    SetEntityCollision(bag, false, true)
    local x, y, z = table.unpack(GetEntityCoords(ped))
    local charge = CreateObject(`prop_bomb_01`, x, y, z + 0.2, true, true, true)
    SetEntityCollision(charge, false, true)
    AttachEntityToEntity(charge,ped,GetPedBoneIndex(ped, 28422),0,0,0,0,0,200.0,true,true,false,true,1,true)
    NetworkAddPedToSynchronisedScene(ped,bagscene,"anim@heists@ornate_bank@thermal_charge","thermal_charge",1.5,-4.0,1,16,1148846080,0)
    NetworkAddEntityToSynchronisedScene(bag,bagscene,"anim@heists@ornate_bank@thermal_charge","bag_thermal_charge",4.0,-8.0,1)
    SetPedComponentVariation(ped, 5, 0, 0, 0)
    NetworkStartSynchronisedScene(bagscene)
    Wait(5000)
    DetachEntity(charge, 1, 1)
    FreezeEntityPosition(charge, true)
    DeleteObject(bag)
    NetworkStopSynchronisedScene(bagscene)
    FreezeEntityPosition(ped, false)
    bombProp = charge
end

----------------------------
-- 8. 爆破カウントダウン
----------------------------
RegisterNetEvent('cash-truck-heist:bombCountdown', function(seconds)
    bombTimer = seconds
    bombCountdownValue = seconds
    showBombCountdown = true
    Citizen.CreateThread(function()
        while bombCountdownValue > 0 do
            Wait(1000)
            bombCountdownValue = bombCountdownValue - 1
        end
        showBombCountdown = false
        if bombProp and DoesEntityExist(bombProp) then
            DeleteEntity(bombProp)
            bombProp = nil
        end
        local pos = GetEntityCoords(truck)
        AddExplosion(pos.x, pos.y, pos.z, 2, 5.0, true, false, 15.0)
        SetVehicleDoorBroken(truck, 2, true)
        SetVehicleDoorBroken(truck, 3, true)
        TriggerServerEvent('cash-truck-heist:bombExploded')
    end)
end)

Citizen.CreateThread(function()
    while true do
        Wait(0)
        if showBombCountdown and bombCountdownValue > 0 then
            SetTextFont(1)
            SetTextProportional(1)
            SetTextScale(0.3, 0.3)
            SetTextColour(255, 255, 255, 255)
            SetTextEntry("STRING")
            AddTextComponentString("爆破まで: ~r~"..bombCountdownValue.."~s~ 秒")
            DrawText(0.45, 0.85)
        end
    end
end)

----------------------------
-- 9. 報酬回収UI
----------------------------
RegisterNetEvent('cash-truck-heist:enableLoot', function()
    CreateThread(function()
        while not lootPos do
            Wait(100)
        end
        local collecting = false
        while heistActive do
            Wait(0)
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local dist = #(coords - lootPos)
            if dist < 2.0 and not lootCollected and not collecting then
                DrawText3D(vector3(lootPos.x, lootPos.y, lootPos.z + 0.7), "[E] 金品を回収する")
                if IsControlJustReleased(0, 38) then
                    collecting = true
                    local animDict = "anim@scripted@heist@ig1_table_grab@cash@male@"
                    local stackModel = `h4_prop_h4_cash_stack_01a`
                    loadAnimDict(animDict)
                    loadModel(stackModel)
                    loadModel("hei_p_m_bag_var22_arm_s")
                    local bag = CreateObject(`hei_p_m_bag_var22_arm_s`, coords, true, true, false)
                    local sceneObject = CreateObject(stackModel, lootPos.x, lootPos.y, lootPos.z - 0.5, true, true, false)
                    local scenePos = GetEntityCoords(sceneObject)
                    local sceneRot = GetEntityRotation(sceneObject)
                    local scenes = {}
                    for i = 1, #GrabCash.animations do
                        scenes[i] = NetworkCreateSynchronisedScene(scenePos, sceneRot, 2, true, false, 1065353216, 0, 1.0)
                        NetworkAddPedToSynchronisedScene(ped, scenes[i], animDict, GrabCash.animations[i][1], 4.0, -4.0, 1033, 0, 1000.0, 0)
                        NetworkAddEntityToSynchronisedScene(bag, scenes[i], animDict, GrabCash.animations[i][2], 1.0, -1.0, 1148846080)
                        if i == 2 then
                            NetworkAddEntityToSynchronisedScene(sceneObject, scenes[i], animDict, GrabCash.animations[i][3], 1.0, -1.0, 1148846080)
                        end
                    end
                    FreezeEntityPosition(ped, true)
                    NetworkStartSynchronisedScene(scenes[1])
                    NetworkStartSynchronisedScene(scenes[2])
                    local success = lib.progressBar({
                        duration = 13500,
                        label = "金品を回収中...",
                        useWhileDead = false,
                        canCancel = true,
                        disable = {
                            move = true,
                            car = true,
                            combat = true
                        }
                    })
                    ClearPedTasksImmediately(ped)
                    FreezeEntityPosition(ped, false)
                    if success then
                        if DoesEntityExist(sceneObject) then
                            DeleteEntity(sceneObject)
                        end
                        NetworkStartSynchronisedScene(scenes[4])
                        Wait(2000)
                        if DoesEntityExist(bag) then
                            DeleteEntity(bag)
                        end
                        TriggerServerEvent('cash-truck-heist:collectReward')
                        exports.qbx_core:Notify("回収終了　さっさと引き上げるぞ", "success")
                        lootCollected = true
                        collecting = false
                    else
                        if DoesEntityExist(sceneObject) then
                            DeleteEntity(sceneObject)
                        end
                        if DoesEntityExist(bag) then
                            DeleteEntity(bag)
                        end
                        collecting = false
                        lootCollected = false
                        exports.qbx_core:Notify("回収をキャンセルした", "error")
                    end
                end
            end
            if lootCollected then
                break
            end
        end
    end)
end)

----------------------------
-- 10. 金品回収後：車両から離れたら換金所ブリップ出現＆通知、車両ブリップ削除＆目印車スポーン
----------------------------
RegisterNetEvent('cash-truck-heist:lootCollected', function()
    Citizen.CreateThread(function()
        local player = PlayerPedId()
        while true do
            Wait(1000)
            if truckCoords then
                local dist = #(GetEntityCoords(player) - truckCoords)
                if dist > 40.0 then
                    if heistBlip then RemoveBlip(heistBlip) heistBlip = nil end
                    local ex = Config.CashTruckHeist.exchange.coords
                    if exchangeBlip then RemoveBlip(exchangeBlip) end
                    exchangeBlip = addBlip(ex, 500, 2, "換金場所")
                    SetBlipRoute(exchangeBlip, true)
                    TriggerEvent('cash-truck-heist:startExchangeCheck')
                    exports.qbx_core:Notify("換金場所はGPSで確認しろ", "success")
                    local offset = vector3(5, -5, 0)
                    local vehPos = ex + offset
                    local vehModel = GetHashKey("dubsta2")
                    loadModel(vehModel)
                    if exchangeVeh and DoesEntityExist(exchangeVeh) then DeleteEntity(exchangeVeh) end
                    exchangeVeh = CreateVehicle(vehModel, vehPos.x, vehPos.y, vehPos.z, 0.0, true, false)
                    SetEntityAsMissionEntity(exchangeVeh, true, true)
                    break
                end
            else
                break
            end
        end
    end)
end)

----------------------------
-- 11. 換金処理
----------------------------
RegisterNetEvent('cash-truck-heist:startExchangeCheck', function()
    Citizen.CreateThread(function()
        while true do
            Wait(1000)
            if exchangeBlip then
                local player = PlayerPedId()
                local dist = #(GetEntityCoords(player) - Config.CashTruckHeist.exchange.coords)
                if dist < 10.0 then
                    TriggerServerEvent('cash-truck-heist:tryExchange')
                    if exchangeBlip then
                        RemoveBlip(exchangeBlip)
                        exchangeBlip = nil
                    end
                    break
                end
            else
                break
            end

        end

    end)

end)

RegisterNetEvent('cash-truck-heist:playExchangeMovie', function()
    if truck and DoesEntityExist(truck) then DeleteEntity(truck) truck = nil end
    if escortVeh and DoesEntityExist(escortVeh) then DeleteEntity(escortVeh)escortVeh = nil end
    if guards and #guards > 0 then
        for _, ped in ipairs(guards) do
            if DoesEntityExist(ped) then DeleteEntity(ped) end
        end
        guards = {}
    end
    if bombProp and DoesEntityExist(bombProp) then DeleteEntity(bombProp) bombProp = nil end
    if exchangeVeh and DoesEntityExist(exchangeVeh) then DeleteEntity(exchangeVeh) exchangeVeh = nil end
    if heistBlip then RemoveBlip(heistBlip) heistBlip = nil end
    if exchangeBlip then RemoveBlip(exchangeBlip) exchangeBlip = nil end
    heistActive = false
    heistLocation = nil
    truckCoords = nil
    lootPos = nil
    lootCollected = false
    PlayCutscene('hs3f_all_drp3', Config.CashTruckHeist.exchange.coords, 0.0)
    TriggerServerEvent('cash-truck-heist:heistFinished')
end)

----------------------------
-- 換金ムービー
----------------------------
function PlayCutscene(cut, coords, heading)
    while not HasThisCutsceneLoaded(cut) do 
        RequestCutscene(cut, 8)
        Wait(0) 
    end
    local cutHeading = (heading or 0.0) + 90.0
    CreateCutscene(false, coords, cutHeading)
    FinishCutscene(coords)
    RemoveCutscene()
    DoScreenFadeIn(500)
end

function CreateCutscene(change, coords, heading)
    local ped = PlayerPedId()
    local clone = ClonePedEx(ped, 0.0, false, true, 1)
    local clone2 = ClonePedEx(ped, 0.0, false, true, 1)
    local clone3 = ClonePedEx(ped, 0.0, false, true, 1)
    local clone4 = ClonePedEx(ped, 0.0, false, true, 1)
    local clone5 = ClonePedEx(ped, 0.0, false, true, 1)

    SetBlockingOfNonTemporaryEvents(clone, true)
    SetEntityVisible(clone, false, false)
    SetEntityInvincible(clone, true)
    SetEntityCollision(clone, false, false)
    FreezeEntityPosition(clone, true)
    SetPedHelmet(clone, false)
    RemovePedHelmet(clone, true)
    
    if change then
        SetCutsceneEntityStreamingFlags('MP_2', 0, 1)
        RegisterEntityForCutscene(ped, 'MP_2', 0, GetEntityModel(ped), 64)
        SetCutsceneEntityStreamingFlags('MP_1', 0, 1)
        RegisterEntityForCutscene(clone2, 'MP_1', 0, GetEntityModel(clone2), 64)
    else
        SetCutsceneEntityStreamingFlags('MP_1', 0, 1)
        RegisterEntityForCutscene(ped, 'MP_1', 0, GetEntityModel(ped), 64)
        SetCutsceneEntityStreamingFlags('MP_2', 0, 1)
        RegisterEntityForCutscene(clone2, 'MP_2', 0, GetEntityModel(clone2), 64)
    end

    SetCutsceneEntityStreamingFlags('MP_3', 0, 1)
    RegisterEntityForCutscene(clone3, 'MP_3', 0, GetEntityModel(clone3), 64)
    SetCutsceneEntityStreamingFlags('MP_4', 0, 1)
    RegisterEntityForCutscene(clone4, 'MP_4', 0, GetEntityModel(clone4), 64)
    SetCutsceneEntityStreamingFlags('MP_5', 0, 1)
    RegisterEntityForCutscene(clone5, 'MP_5', 0, GetEntityModel(clone5), 64)
    Wait(10)
    if coords then
        StartCutsceneAtCoords(coords, heading or 90.0)
    else
        StartCutscene(0)
    end
    Wait(10)
    ClonePedToTarget(clone, ped)
    Wait(10)
    DeleteEntity(clone)
    DeleteEntity(clone2)
    DeleteEntity(clone3)
    DeleteEntity(clone4)
    DeleteEntity(clone5)
    Wait(50)
    DoScreenFadeIn(250)
end

function FinishCutscene(coords)
    if coords then
        local tripped = false
        repeat
            Wait(0)
            if (GetCutsceneTotalDuration() - GetCutsceneTime() <= 250) then
                DoScreenFadeOut(250)
                tripped = true
            end
        until not IsCutscenePlaying()
        if (not tripped) then
            DoScreenFadeOut(100)
            Wait(150)
        end
        local afterMoviePos = vector3(coords.x + 2.0, coords.y, coords.z)
        SetEntityCoords(PlayerPedId(), afterMoviePos.x, afterMoviePos.y, afterMoviePos.z, false, false, false, true)
        DoScreenFadeIn(500)
        return
    else
        Wait(18500)
        StopCutsceneImmediately()
    end
end

----------------------------
-- その他：通知・リセット・エンティティ削除
----------------------------
RegisterNetEvent('cash-truck-heist:notify', function(msg)
    exports.qbx_core:Notify(msg, "inform", 5000)
end)

RegisterNetEvent('cash-truck-heist:lockNPC', function(lock)
    npcLocked = lock
end)

RegisterNetEvent('cash-truck-heist:cleanupEntities', function()
    if truck and DoesEntityExist(truck) then DeleteEntity(truck) truck = nil end
    if guards and #guards > 0 then
        for _, ped in ipairs(guards) do
            if DoesEntityExist(ped) then DeleteEntity(ped) end
        end
        guards = {}
    end
    if escortVeh and DoesEntityExist(escortVeh) then
        DeleteEntity(escortVeh)
        escortVeh = nil
    end
    if bombProp and DoesEntityExist(bombProp) then DeleteEntity(bombProp) bombProp = nil end
    if exchangeVeh and DoesEntityExist(exchangeVeh) then DeleteEntity(exchangeVeh) exchangeVeh = nil end
    if heistBlip then RemoveBlip(heistBlip) heistBlip = nil end
    if exchangeBlip then RemoveBlip(exchangeBlip) exchangeBlip = nil end
    heistActive = false
    heistLocation = nil
    truckCoords = nil
    lootPos = nil
    lootCollected = false
    bombActive = false
    guardsAttacked = false
    bombTimer = 0
    showBombCountdown = false
    bombCountdownValue = 0
    truckRequested = false
    truckSpawnedClient = false
end)

----------------------------
-- Dispatch Alert
----------------------------
RegisterNetEvent('cash-truck-heist:dispatchAlert', function(coords)
    exports['ps-dispatch']:cashtruckheist({
        coords = coords
    })
end)