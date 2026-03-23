Config = {}

Config.CashTruckHeist = {

    framework = "Qbox",

    police = {
        jobs = {"police","police2"},
        required = 1
    },

    cooldown = 60 * 60,

    dispatch = {
        enabled = true,
        code = "10-90",
        message = "現金輸送車襲撃",
        sprite = 67,
        colour = 3,
        scale = 1.2,
        time = 5
    },

    -- 受注用NPC
    npc = {
        coords = vector3(-695.25, -764.21, 33.68),
        heading = 0,
        model = "s_m_m_security_01"
    },

    -- リセットNPC
    resetnpc = {
        coords = vector3(-693.43, -761.94, 33.68),
        heading = 90.00,
        model = "a_m_m_hasjew_01"
    },

    -- 輸送車
    truck = {
        model = "stockade",
        locations = {
            {coords = vector3(89.88, -1928.52, 20.8), heading = 45.07},
            {coords = vector3(1368.27, -578.57, 74.38), heading = 65.73},
            {coords = vector3(-1155.85, -1760.05, 3.98), heading = 299.79},
            {coords = vector3(-614.66, 188.96, 69.7), heading = 95.17},
            {coords = vector3(55.77, -2552.64, 6.0), heading = 266.49}
        }
    },

    -- 護衛NPC
    guard = {
        model = "s_m_m_security_01",
        health = 1000,
        armor = 500
    },

    -- 爆弾
    bomb = {
        item = "cashtruckbomb",
        timer = 5
    },

    -- 報酬
    reward = {
        items = {
            {name = "cashtruckheist_blackmoney", amount = 30}
        }
    },

    -- 換金所
    exchange = {
        coords = vector3(-513.0,-599.31,24.5),
        items = {
            {name = "cashtruckheist_blackmoney", price = 5000}
        }
    }
}

