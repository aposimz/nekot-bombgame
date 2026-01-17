Config = {}

-- 招待可能距離（メートル）
Config.InviteRange = 25.0

-- タイムアウト（秒）
Config.Timeouts = {
    Invite = 15,
    VehicleSetup = 30,
    NumberSelect = 60,
    Turn = 300,
    Countdown = 10
}

-- デバッグ設定
Config.Debug = {
    EnableLogs = false  -- デバッグログを有効にするかどうか
}

-- 賭け金設定
Config.Betting = {
    MinAmount = 0,
    MaxAmount = 10000000000, -- 100億　あげすぎないように
    DefaultAmount = 0
}

-- 車両登録制限
Config.VehicleRegistration = {
    ExcludedClasses = {18, 15, 16}, -- 除外する車両クラス
    RequireOwnership = true,     -- 所有車のみ登録可能
}
--[[ 車両クラス一覧
0: Compacts
1: Sedans
2: SUVs
3: Coupes
4: Muscle
5: Sports Classics
6: Sports
7: Super
8: Motorcycles
9: Off-road
10: Industrial
11: Utility
12: Vans
13: Cycles
14: Boats
15: Helicopters
16: Planes
17: Service
18: Emergency
19: Military
20: Commercial
21: Trains
]]
