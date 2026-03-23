local heistActive = false
local cooldown = 0
local currentPlayer = nil
local heistLocation = nil
local heistBombPlaced = false
local truckSpawned = false
local heistOwner = nil

-------------------------
-- 警察人数
-------------------------
local function IsPoliceJob(job)
    for _,name in ipairs(Config.CashTruckHeist.police.jobs) do
        if job == name then
            return true
        end
    end
    return false
end

local function GetPoliceCount()
    local count = 0
    for _, id in pairs(GetPlayers()) do
        local Player = exports.qbx_core:GetPlayer(tonumber(id))
        if Player and Player.PlayerData.job then
            local job = Player.PlayerData.job
            if job.onduty and IsPoliceJob(job.name) then
                count = count + 1
            end
        end
    end
    return count
end

-------------------------
-- 強盗終了
-------------------------
local function finishHeist()
    heistActive = false
    currentPlayer = nil
    heistLocation = nil
    heistBombPlaced = false
    truckSpawned = false
    heistOwner = nil
    TriggerClientEvent('cash-truck-heist:lockNPC',-1,false)
    TriggerClientEvent('cash-truck-heist:cleanupEntities', -1)
    TriggerClientEvent('cash-truck-heist:setTruckSpawned', -1, false)
    TriggerClientEvent('cash-truck-heist:setOwner', -1, nil)
end
-------------------------
-- 受注
-------------------------
RegisterNetEvent('cash-truck-heist:requestStart',function()
    local src = source
    if GetPoliceCount() < Config.CashTruckHeist.police.required then
        TriggerClientEvent('cash-truck-heist:notify',src,"強盗ができるだけの警察がいない...")
        return
    end
    if heistActive then
        TriggerClientEvent('cash-truck-heist:notify',src,"現在ほかのプレイヤーが進行中です")
        return
    end
    if os.time() < cooldown then
        local remain = cooldown - os.time()
        TriggerClientEvent('cash-truck-heist:notify',src,("クールダウン中です あと%d分%d秒"):format(math.floor(remain/60),remain%60))
        return
    end
    heistOwner = src
    local locations = Config.CashTruckHeist.truck.locations
    heistLocation = locations[math.random(#locations)]
    heistActive = true
    currentPlayer = src
    truckSpawned = false
    cooldown = os.time() + Config.CashTruckHeist.cooldown
    TriggerClientEvent('cash-truck-heist:notifyLocation',src,heistLocation)
    TriggerClientEvent('cash-truck-heist:lockNPC',-1,true)
    TriggerClientEvent('cash-truck-heist:setOwner', -1, src)
end)

-------------------------
-- 車両スポーンと警察通知
-------------------------
RegisterNetEvent('cash-truck-heist:spawnTruck', function()
    local src = source
    if src ~= currentPlayer then return end
    if truckSpawned then return end
    truckSpawned = true
    TriggerClientEvent('cash-truck-heist:setTruckSpawned', -1, true)
    TriggerClientEvent('cash-truck-heist:spawnTruckAndGuards', currentPlayer, heistLocation)
    if Config.CashTruckHeist.dispatch.enabled then
        TriggerClientEvent(
            'cash-truck-heist:dispatchAlert',
            currentPlayer,
            {
                coords = heistLocation.coords
            }
        )
    end
end)

-------------------------
-- 停止・攻撃
-------------------------
RegisterNetEvent('cash-truck-heist:truckStopped',function()
    if source ~= currentPlayer then return end
    TriggerClientEvent('cash-truck-heist:guardsAttack',currentPlayer)
end)

-------------------------
-- 爆弾設置
-------------------------
RegisterNetEvent('cash-truck-heist:tryPlaceBomb',function()
    local src = source
    if src ~= currentPlayer then
        TriggerClientEvent('cash-truck-heist:placeBombResult',src,false,"あなたはこのミッションの受注者ではありません。")
        return
    end
    if heistBombPlaced then
        TriggerClientEvent('cash-truck-heist:placeBombResult',src,false,"すでに爆弾が設置されています。")
        return
    end
    local item = Config.CashTruckHeist.bomb.item
    local count = exports.ox_inventory:GetItem(src,item,nil,true)
    if count and count > 0 then
        exports.ox_inventory:RemoveItem(src,item,1)
        heistBombPlaced = true
        TriggerClientEvent('cash-truck-heist:placeBombResult',src,true)
    else
        TriggerClientEvent('cash-truck-heist:placeBombResult',src,false,"現金輸送車用爆弾が必要です！")
    end
end)

-------------------------
-- タイマー
-------------------------
RegisterNetEvent('cash-truck-heist:startBomb',function()
    local src = source
    if src ~= currentPlayer then return end
    TriggerClientEvent('cash-truck-heist:bombCountdown',src,Config.CashTruckHeist.bomb.timer)
end)

RegisterNetEvent('cash-truck-heist:bombExploded',function()
    local src = source
    if src ~= currentPlayer then return end
    TriggerClientEvent('cash-truck-heist:enableLoot', src)
end)
-------------------------
-- 金品回収
-------------------------
RegisterNetEvent('cash-truck-heist:collectReward',function()
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    for _,item in ipairs(Config.CashTruckHeist.reward.items) do
        exports.ox_inventory:AddItem(src, item.name, item.amount)
    end
    TriggerClientEvent('cash-truck-heist:lootCollected',src)
end)

-------------------------
-- 換金ムービー
-------------------------
RegisterNetEvent('cash-truck-heist:tryExchange', function()
    print("TRY EXCHANGE", source)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    if not Player then return end
    local totalMoney = 0
    local removeList = {}
    for _, item in ipairs(Config.CashTruckHeist.exchange.items) do
        local count = exports.ox_inventory:Search(src, 'count', item.name)
        if count and count > 0 then
            totalMoney = totalMoney + (item.price * count)
            table.insert(removeList, {
                name = item.name,
                amount = count
            })
        end
    end
    if totalMoney <= 0 then
        TriggerClientEvent('ox_lib:notify', src, {
            description = "換金できるアイテムがありません",
            type = "error"
        })
        TriggerClientEvent('cash-truck-heist:cleanupEntities', src)
        finishHeist()
        return
    end
    TriggerClientEvent('cash-truck-heist:playExchangeMovie', src)
    SetTimeout(7000, function()
        for _, item in ipairs(removeList) do
            local currentCount = exports.ox_inventory:Search(src, 'count', item.name)
            if currentCount and currentCount > 0 then
                exports.ox_inventory:RemoveItem(src, item.name, math.min(item.amount, currentCount))
            end
        end
        exports.qbx_core:AddMoney(src, "cash", totalMoney)
        TriggerClientEvent('ox_lib:notify', src, {
            description = "換金完了 $" .. totalMoney .. " を受け取った",
            type = "success"
        })

        finishHeist()
    end)
end)

-------------------------
-- 管理コマンド・リセットおじ
-------------------------
RegisterCommand('cashtruckreset', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if Player and Player.PlayerData.job and IsPoliceJob(Player.PlayerData.job.name) then
        finishHeist()
        TriggerClientEvent('ox_lib:notify', source, {
            description = "車両やNPCを削除しました",
            type = "success"
        })
    end
end, false)

RegisterCommand('cashtruckrestart', function(source)
    local Player = exports.qbx_core:GetPlayer(source)
    if Player and Player.PlayerData.job and IsPoliceJob(Player.PlayerData.job.name) then
        cooldown = 0
        finishHeist()
        TriggerClientEvent('ox_lib:notify', source, {
            description = "警察によってクールタイムが解除されました",
            type = "success"
        })
    end
end, false)

RegisterNetEvent('cash-truck-heist:forceReset', function()
    local src = source
    if src ~= heistOwner then
        TriggerClientEvent('ox_lib:notify', src, {
            description = "この強盗をリセットできるのは受注者のみです",
            type = "error"
        })
        return
    end
    if truckSpawned then
        TriggerClientEvent('ox_lib:notify', src, {
            description = "すでに輸送車が出現しているためリセットできません",
            type = "error"
        })
        return
    end
    cooldown = 0
    TriggerClientEvent('cash-truck-heist:cleanupEntities', -1)
    TriggerClientEvent('ox_lib:notify', src, {
        description = "強盗をリセットしました",
        type = "success"
    })
    heistOwner = nil
    TriggerClientEvent('cash-truck-heist:setOwner', -1, nil)
    finishHeist()
end)