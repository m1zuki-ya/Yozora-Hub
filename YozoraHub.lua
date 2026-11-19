if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local CONFIG_FILE = "YozoraHub_Config.json"
local SCRIPT_FILE = "YozoraHub_Autorun.lua"
local VERSION = "0.1.0 (Beta*)"
local BUILD_DATE = "November 19 / 2026"
local DISCORD_INVITE = "https://discord.gg/avV2G2jB3F"
local MENU_KEY = Enum.KeyCode.LeftControl

local Settings = {
    AutoFarm = false,
    ESP = false,
    AntiFling = false,
    AntiAFK = false,
    AvoidMurderer = false,
    AutoRespawnFull = false,
    KillAllFull = false,
    ShootMurdererFull = false,
    AutoRejoin = false,
    PickGun = false,
    -- Игрок: движение, физика, видимость
    PlayerSpeed = 16,
    PlayerJump = 50,
    PlayerGravity = 196.2,
    FlySpeed = 45,
    NoClip = false,
    InfiniteJumps = false,
    WallHop = false,
    SpeedGlitch = false,
    Bhop = false,
    Spin = false,
    Fly = false,
    XRay = false,
    Invisible = false,
    AutoExecute = true,
    FarmMethod = "classic", -- classic | undermap
    SpeedClassic = 24,
    SpeedUnderMap = 21,
    TotalCoins = 0,
    Language = "en",
    UI = {}, -- настройки внешнего вида меню
    EspOpt = {}, -- настройки ESP
    VisOpt = {}, -- настройки визуала
    Combat = {}, -- настройки боя (аим)
}

local Stats = { Session = 0, Rate = 0, Status = "off" }

-- ==========================================
-- 0. Защита от повторного запуска
-- ==========================================
-- Старые подключения/циклы предыдущего запуска отключаются, чтобы не копились дубли
for _, key in ipairs({ "YozoraHub_KeyConn", "YozoraHub_IdleConn" }) do
    if _G[key] then
        pcall(function() _G[key]:Disconnect() end)
        _G[key] = nil
    end
end
if _G.YozoraHub_Cleanup then
    pcall(_G.YozoraHub_Cleanup)
end

local RunId = {}
local Connections = {}
_G.YozoraHub_RunId = RunId
_G.YozoraHub_Cleanup = function()
    -- после очистки циклы с Alive() перестают работать (Cleanup можно звать вручную)
    _G.YozoraHub_Cleaned = RunId
    -- финальное сохранение настроек, если конфиг-система уже инициализирована
    if _G.YozoraHub_SaveNow then pcall(_G.YozoraHub_SaveNow) end
    -- Ошибка одного connection не должна прерывать очистку остальных.
    for i = #Connections, 1, -1 do
        local connection = Connections[i]
        pcall(function()
            if connection and connection.Connected then
                connection:Disconnect()
            end
        end)
        Connections[i] = nil
    end
    if _G.YozoraHub_AntiFlingRestore then pcall(_G.YozoraHub_AntiFlingRestore) end
    if _G.YozoraHub_PlayerRestore then pcall(_G.YozoraHub_PlayerRestore) end
    if _G.YozoraHub_FarmCollisionRestore then pcall(_G.YozoraHub_FarmCollisionRestore) end
    if _G.YozoraHub_EspStop then pcall(_G.YozoraHub_EspStop) end
    if _G.YozoraHub_VisualStop then pcall(_G.YozoraHub_VisualStop) end
    if _G.YozoraHub_CombatStop then pcall(_G.YozoraHub_CombatStop) end
end

local function Alive()
    return _G.YozoraHub_RunId == RunId and _G.YozoraHub_Cleaned ~= RunId
end

-- Пока открыт попап/дропдаун, Track() складывает соединения в его Conns —
-- иначе каждое открытие дропдауна навсегда оставалось в Connections (утечка)
local TrackSink

local function Track(connection)
    table.insert(TrackSink or Connections, connection)
    return connection
end

-- ==========================================
-- 1. Config
-- ==========================================
-- Копия настроек только из значений, которые умеет хранить JSON (числа без NaN/inf, строки, булевы, таблицы)
local function Sanitize(value, depth)
    depth = depth or 0
    local kind = type(value)
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    if kind == "string" or kind == "boolean" then return value end
    if kind == "table" and depth < 8 then
        local copy = {}
        for key, item in pairs(value) do
            if type(key) == "string" then
                local safe = Sanitize(item, depth + 1)
                if safe ~= nil then copy[key] = safe end
            end
        end
        return copy
    end
    return nil
end

-- Состояние последнего сохранения (показывается в Настройки, Конфиги)
local ConfigStatus = { ok = nil, at = 0, text = "" }

local function SaveConfig()
    if not writefile then
        ConfigStatus.ok, ConfigStatus.at, ConfigStatus.text = false, os.time(), "writefile is not supported"
        return
    end
    local ok, err = pcall(function()
        -- резервная копия прошлого конфига: если новый побьётся (сбой при записи),
        -- старый можно вернуть руками
        if isfile and isfile(CONFIG_FILE) then
            writefile(CONFIG_FILE .. ".bak", readfile(CONFIG_FILE))
        end
        writefile(CONFIG_FILE, HttpService:JSONEncode(Sanitize(Settings)))
    end)
    ConfigStatus.ok, ConfigStatus.at = ok, os.time()
    ConfigStatus.text = ok and "" or tostring(err)
    if not ok then
        warn("[Yozora Hub] could not save config: " .. tostring(err))
    end
end

-- Cleanup зовёт это при выгрузке: последние изменения не теряются
_G.YozoraHub_SaveNow = SaveConfig

local function LoadConfig()
    if not (isfile and readfile and isfile(CONFIG_FILE)) then return end
    local ok, err = pcall(function()
        local decoded = HttpService:JSONDecode(readfile(CONFIG_FILE))
        if type(decoded) ~= "table" then return end
        for k, v in pairs(decoded) do
            if Settings[k] ~= nil and type(v) == type(Settings[k]) then
                Settings[k] = v
            end
        end
    end)
    if not ok then
        warn("[Yozora Hub] could not read config: " .. tostring(err))
    end
    -- быстрее ~22-24 студов/с уже подозрительно для античита
    Settings.SpeedClassic = math.clamp(Settings.SpeedClassic, 8, 24)
    Settings.SpeedUnderMap = math.clamp(Settings.SpeedUnderMap, 8, 22)
    if Settings.FarmMethod ~= "classic" and Settings.FarmMethod ~= "undermap" then
        Settings.FarmMethod = "classic"
    end
    -- noRender глушит 3D-рендер: если сохранить и перезапуститься — чёрный экран
    if type(Settings.VisOpt) == "table" then
        Settings.VisOpt.noRender = false
    end
end

LoadConfig()

-- ==========================================
-- 2. Auto Execute on Teleport
-- ==========================================
-- Глобалы экзекуторов: теневые локальные, чтобы анализатор не ругался
-- (значения читаются один раз при старте, поведение не меняется)
local syn = rawget(_G, "syn")
local fluxus = rawget(_G, "fluxus")

local QueueTeleport = queue_on_teleport
    or (syn and syn.queue_on_teleport)
    or (fluxus and fluxus.queue_on_teleport)
    or queueonteleport

local autorunQueued = false

-- Ставит автозапуск в очередь на следующий телепорт (один раз за сессию:
-- повторная постановка дала бы дубли)
local function QueueAutorun()
    if autorunQueued or not QueueTeleport or not Settings.AutoExecute then return end

    local queued = false
    local ok = pcall(function()
        if isfile and readfile and isfile(SCRIPT_FILE) then
            QueueTeleport(('loadstring(readfile("%s"))()'):format(SCRIPT_FILE))
            queued = true
        elseif type(_G.YozoraHub_ScriptSource) == "string"
            and _G.YozoraHub_ScriptSource ~= "" then
            QueueTeleport(_G.YozoraHub_ScriptSource)
            queued = true
        end
    end)

    -- При отсутствии файла/ошибке executor можно повторить попытку позже.
    if ok and queued then autorunQueued = true end
end

Track(LocalPlayer.OnTeleport:Connect(function()
    QueueAutorun()
end))

-- ==========================================
-- 3. Helpers
-- ==========================================
local function New(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props) do
        obj[k] = v
    end
    obj.Parent = parent -- parent последним, чтобы не триггерить лишние пересчёты
    return obj
end

-- Безопасный доступ к Enum.Font по имени: часть шрифтов (напр. GothamSemibold)
-- может отсутствовать в новых API Roblox — тогда берём запасной
local function FontByName(name, fallback)
    local ok, value = pcall(function() return Enum.Font[name] end)
    return (ok and value) or fallback
end

local CurrentTween = nil

local function CancelTween()
    if CurrentTween then
        CurrentTween:Cancel()
        CurrentTween = nil
    end
end

local FarmSetEnabled = function() end -- реализована в секции Auto Farm

local function FormatNumber(n)
    n = tonumber(n) or 0
    if n >= 1000000 then return ("%.1fM"):format(n / 1000000) end
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n))
end

-- ==========================================
-- 4. ESP: настройки (рисование ESP находится ниже, после секции ролей)
-- ==========================================
local function HasTool(player, name)
    local character = player.Character
    local backpack = player:FindFirstChildOfClass("Backpack")
    return (character and character:FindFirstChild(name))
        or (backpack and backpack:FindFirstChild(name))
end

local ESP_DEFAULTS = {
    -- роли и цвета
    murderer = true, sheriff = true, hero = true, innocent = true,
    murdererColour = "ff4040", sheriffColour = "5096ff", heroColour = "ffd23c", innocentColour = "5ae682",
    -- фильтры
    maxDist = 1500, fade = true, visCheck = false, dimHidden = true, smooth = 35,
    -- текст
    name = true, nameMode = "Display", role = true, weapon = true, distance = true, distUnit = "Studs",
    textSize = 13, textOutline = true,
    -- рамка и здоровье
    box = true, boxStyle = "Corners", boxThickness = 1, cornerSize = 22, boxWidth = 50, boxOutline = true,
    boxFill = false, boxFillAlpha = 12, boxColMode = "Role", boxColour = "ffffff",
    -- чамсы
    chams = false, chamsFill = 0.55, chamsOutline = 0, chamsThrough = true, chamsRole = true,
    chamsColour = "ff4646", chamsHidden = "966eff", chamsMaxDist = 0,
    -- скелет, трассеры, стрелки, пистолет
    skeleton = false, boneThick = 1.5, boneRole = true, boneColour = "ebebeb", headDot = false, skelMaxDist = 300,
    tracer = false, tracerFrom = "Bottom", tracerTo = "Feet", tracerThick = 1, tracerAlpha = 0.6,
    tracerRole = true, tracerColour = "ebebeb",
    arrows = false, arrowRadius = 170, arrowSize = 10,
    gunEsp = false, gunColour = "ffd23c",
}

if type(Settings.EspOpt) ~= "table" then Settings.EspOpt = {} end

-- Функции ESP-модуля подключаются позже (секция 9b).
-- changed() остаётся пустым хуком: ESP перечитывает EspOpt() каждый кадр,
-- поэтому мгновенное применение изменений и так происходит в Step()
local Esp = {
    changed = function() end,
    setEnabled = function() end,
    clear = function() end,
}

local function EspOpt(key)
    local value = Settings.EspOpt[key]
    local default = ESP_DEFAULTS[key]
    if value == nil or type(value) ~= type(default) then return default end
    return value
end

local function SetEspOpt(key, value)
    Settings.EspOpt[key] = value
    Esp.changed(key)
end

local EspColorCache = {}
local function EspColour(key)
    local hex = EspOpt(key)
    local color = EspColorCache[hex]
    if not color then
        local ok, value = pcall(Color3.fromHex, tostring(hex))
        color = ok and value or Color3.new(1, 1, 1)
        EspColorCache[hex] = color
    end
    return color
end

local function ClearESP()
    Esp.clear()
end


-- ==========================================
-- 4b. Визуал: настройки по умолчанию (модуль находится ниже, секция 9c)
-- ==========================================
local VIS_DEFAULTS = {
    -- мир: освещение
    worldOn = false, preset = "Original", tech = "Game",
    brightOn = false, brightness = 2, timeOn = false, time = 14,
    ambientOn = false, ambient = "969696", outdoor = "aaaaaa",
    exposureOn = false, exposure = 0, noShadows = false, shadowSoftOn = false, shadowSoft = 0.5,
    -- туман, атмосфера, облака
    fogOn = false, fogStart = 0, fogEnd = 2000, fogColour = "bebebe",
    atmosOn = false, density = 0.28, offset = 0.1, haze = 1, glare = 0.1, atmosColour = "c7d3e6", decay = "6e788c",
    noAtmos = false, noPost = false,
    cloudsOn = false, cloudCover = 0.35, cloudDensity = 0.35, cloudColour = "ffffff",
    -- цвет и пост-эффекты
    gradeOn = false, gradeBright = 0, contrast = 0, saturation = 0, tint = "ffffff",
    bloomOn = false, bloomIntensity = 0.3, bloomSize = 24, bloomThreshold = 1.2,
    raysOn = false, raysIntensity = 0.06, raysSpread = 0.8,
    dofOn = false, dofFar = 0.14, dofFocus = 50, dofRadius = 60,
    vignetteOn = false, vignette = 35,
    materials = "Game",
    -- небо
    sky = "Game", skyDetailsOn = false, stars = 3000, sunSize = 21, moonSize = 11, celestial = true,
    -- погода
    weather = "Off", scene = "", weatherAmount = 60, weatherOpacity = 80, weatherScale = 1, weatherSpeed = 100,
    weatherRadius = 30, weatherWind = 6, weatherWindAngle = 45, weatherSound = false, weatherVolume = 60,
    weatherColourOn = false, weatherColour = "ffffff", weatherShelter = true,
    -- экран
    fovOn = false, fov = 90, stretch = 0, fpsOn = false, fpsCap = 144, noRender = false,
    -- ауры
    aura = "Off", auraColMode = "Accent", auraColour = "ff80ab", auraSize = 1, auraRate = 1,
    auraGlow = false, auraOutline = false, auraTrail = false,
}

local VIS_PRESET_NAMES = { "Original", "Natural", "Cinematic", "Golden Hour", "Dusk", "Night", "Moonlight", "Vivid",
    "Overcast", "Noir", "Neon", "Sakura", "Summer", "Autumn", "Frostbite", "Toxic", "Horror", "Competitive" }
local VIS_WEATHER_NAMES = { "Off", "Snow", "Blossom", "Leaves", "Fireflies", "Mist", "Embers", "Ash", "Pollen" }
local VIS_MATERIAL_NAMES = { "Game", "HD Realistic", "HD Worn", "HD Wet" }
local VIS_SCENE_NAMES = { "Misty Morning", "Snow Day", "Blizzard", "Winter Night", "Cherry Blossom", "Autumn", "Golden Pollen", "Firefly Night", "Bonfire Night", "Volcano" }
local VIS_SKY_NAMES = { "Realistic Sky", "Cloudy Day", "Mountain Valley", "Mirror Clouds", "Dark Storm", "Rain Sky", "Anime Sky", "Anime Ocean", "Heavenly Clouds", "Rainbow Clouds", "Violet Dream", "Cartoon Sky", "Pastel Sky", "Pink Sky", "Minecraft Sky", "Blood Sky", "Moonlit Night", "Starry Night", "Space Sky", "Earth Orbit", "Pink Nebula", "Rainbow Galaxy", "Clear Blue", "Realistic Day", "Cumulus", "Golden Clouds", "Golden Haze", "Sunset", "Fiery Sunset", "Amber Dusk", "Classic Dusk", "Rose Dusk", "Mountain Sunset", "Overcast", "Storm", "Foggy Sea", "Whiteout", "Night Mountains", "Aurora Fjord", "Aurora Lake", "Aurora Teal", "City Night", "Purple Nebula", "Neon Dusk" }

if type(Settings.VisOpt) ~= "table" then Settings.VisOpt = {} end

local Visual = {
    changed = function() end, refreshUI = function() end,
    applyPreset = function() end, applyScene = function() end,
}

local function VisOpt(key)
    local value = Settings.VisOpt[key]
    local default = VIS_DEFAULTS[key]
    if value == nil or type(value) ~= type(default) then return default end
    return value
end

local function SetVisOpt(key, value)
    Settings.VisOpt[key] = value
    Visual.changed(key)
end

local VisColorCache = {}
local function VisColor(key)
    local hex = VisOpt(key)
    local color = VisColorCache[hex]
    if not color then
        local ok, value = pcall(Color3.fromHex, tostring(hex))
        color = ok and value or Color3.new(1, 1, 1)
        VisColorCache[hex] = color
    end
    return color
end

-- ==========================================
-- 4c. Combat: настройки (модуль аима ниже, секция 9a)
-- ==========================================
local COMBAT_DEFAULTS = {
    -- Sheriff: Silent Aim и режимы аима
    silentAim = false,
    autoShoot = false,
    autoEquip = true,
    autoShootDelay = 250,     -- мс между попытками выстрела
    -- предсказание движения цели
    gunPrediction = "Remi",   -- Remi | Ubuntu | Electro | Tiancai | Revert | Flux
    tiancaiOffset = 100,      -- сдвиг режима Tiancai (в %)
    piercer = false,          -- origin выстрела у самой цели (сквозь стены)
    triggerBot = false,       -- авто-выстрел, когда цель у прицела
    triggerRadius = 40,       -- радиус триггера (пиксели)
    triggerWall = true,       -- триггер только по видимой цели
    aimlock = false,          -- камера следует за убийцей
    pingComp = true,
    calibrate = true,         -- автокалибровка упреждения по попаданиям
    -- Knife Aim (аим броска ножа)
    knifeAim = false,
    knifeTarget = "Cursor",       -- Cursor (у курсора) | Closest (ближайший)
    knifeSheriffFirst = true,     -- приоритет шерифа/героя
    knifeMaxDist = 250,
    knifeWall = true,
    knifePrediction = "Dynamic",  -- Dynamic (скорость*2) | Instant (без упреждения)
    knifeMarker = true,
    knifeLMB = false,             -- бросок на ЛКМ (иначе только ПКМ/E/клавиша/кнопка)
    autoThrow = false,
    autoThrowRange = 70,
    throwKey = "",
    -- Подбор пистолета: невиновный берёт брошенный пистолет
    pickGun = false,
    -- Убийца: коснуться всех ножом (без телепорта)
    killAll = false,
    -- Kill Aura: авто-касание всех в радиусе (убийца)
    killAura = false,
    killAuraRange = 10,
    -- Фарм «выстрел при полном мешке»: стрелять сквозь стены (origin у цели)
    farmPiercer = true,
}

if type(Settings.Combat) ~= "table" then Settings.Combat = {} end

-- Заглушки: реальные функции задаёт секция 9a (Combat-движок)
local Combat = {
    changed = function() end,
    throwNow = function() end,
    HookName = function() return "-" end,
    TargetName = function() return "-" end,
    LeadInfo = function() return "-" end,
    ShotsInfo = function() return "-" end,
    KnifeInfo = function() return "-" end,
}

local function CombatOpt(key)
    local value = Settings.Combat[key]
    local default = COMBAT_DEFAULTS[key]
    if value == nil or type(value) ~= type(default) then return default end
    return value
end

local combatSavePending = false
local function SetCombatOpt(key, value)
    Settings.Combat[key] = value
    Combat.changed(key)
    if not combatSavePending then
        combatSavePending = true
        task.delay(0.8, function()
            combatSavePending = false
            SaveConfig()
        end)
    end
end

-- Нужны ли движку данные ролей (опрос GetPlayerData чаще включается)
local function CombatWanted()
    local c = Settings.Combat
    if type(c) ~= "table" then return false end
    return c.silentAim == true or c.autoShoot == true or c.triggerBot == true
        or c.aimlock == true or c.knifeAim == true
        or c.autoThrow == true or c.pickGun == true or c.killAura == true
end

-- ==========================================
-- 5. UI
-- ==========================================

-- ---------- Локализация (English / Русский / Čeština) ----------
local Lang = {
    en = {
        search = "Search",
        tab_farm = "Farm",
        tab_player = "Player",
        tab_visual = "Visuals",
        tab_settings = "Settings",
        sub_farm = "Auto farm and statistics",
        sub_player = "Protection and character behavior",
        sub_visual = "Player highlights",
        sub_settings = "Script options",
        card_stats = "Statistics",
        card_farm = "Farm",
        card_protect = "Protection",
        card_esp = "ESP",
        card_interface = "Interface",
        card_script = "Script",
        stat_collected = "Collected",
        stat_status = "Status",
        stat_rate = "Per hour",
        stat_total = "Total",
        status_off = "Off",
        status_farming = "Farming",
        status_wait_coins = "Waiting for coins",
        status_wait_round = "Waiting for round",
        status_no_char = "No character",
        status_bag_full = "Bag full",
        status_avoiding = "Avoiding murderer",
        status_killing = "Killing players",
        status_spectating = "Spectating",
        status_picking_gun = "Picking up gun",
        farm_speed = "Farm speed",
        farm_method = "Farm method",
        method_classic = "Classic (fast)",
        method_undermap = "Under map",
        speed_classic = "Classic speed",
        speed_undermap = "Under map speed",
        card_safety = "Safety",
        card_full = "Full bag",
        card_connection = "Connection",
        auto_farm = "Auto farm",
        avoid_murderer = "Avoid murderer",
        respawn_full = "Respawn when bag is full",
        kill_all_full = "Kill all when bag is full (murderer)",
        auto_rejoin = "Auto rejoin on kick",
        pick_gun = "Pick up gun",
        anti_fling = "Anti-Fling (fling protection)",
        anti_afk = "Anti-AFK (prevent idle kick)",
        esp_roles = "Role highlight",
        esp_legend = "🔴 Murderer    🔵 Sheriff    🟢 Innocent",
        language = "Language",
        auto_execute = "Auto execute after teleport",
        menu_hint = "Show or hide the menu: Left Ctrl",
    },
    ru = {
        search = "Поиск",
        tab_farm = "Фарм",
        tab_player = "Игрок",
        tab_visual = "Визуал",
        tab_settings = "Настройки",
        sub_farm = "Автофарм и статистика",
        sub_player = "Защита и поведение персонажа",
        sub_visual = "Подсветка игроков",
        sub_settings = "Параметры скрипта",
        card_stats = "Статистика",
        card_farm = "Фарм",
        card_protect = "Защита",
        card_esp = "ESP",
        card_interface = "Интерфейс",
        card_script = "Скрипт",
        stat_collected = "Собрано",
        stat_status = "Статус",
        stat_rate = "В час",
        stat_total = "Всего",
        status_off = "Выключен",
        status_farming = "Фармлю",
        status_wait_coins = "Жду монеты",
        status_wait_round = "Жду раунд",
        status_no_char = "Нет персонажа",
        status_bag_full = "Мешок полон",
        status_avoiding = "Избегаю убийцу",
        status_killing = "Убиваю игроков",
        status_spectating = "Наблюдаю",
        status_picking_gun = "Беру пистолет",
        farm_speed = "Скорость фарма",
        farm_method = "Метод фарма",
        method_classic = "Классический (быстрый)",
        method_undermap = "Под картой",
        speed_classic = "Скорость классического",
        speed_undermap = "Скорость под картой",
        card_safety = "Безопасность",
        card_full = "Полный мешок",
        card_connection = "Соединение",
        auto_farm = "Автофарм",
        avoid_murderer = "Избегать убийцу",
        respawn_full = "Авто-респавн при полном мешке",
        kill_all_full = "Убить всех при полном мешке (убийца)",
        auto_rejoin = "Авто-перезаход при кике",
        pick_gun = "Подбирать пистолет",
        anti_fling = "Anti-Fling (защита от флинга)",
        anti_afk = "Anti-AFK (не кикать за бездействие)",
        esp_roles = "Подсветка ролей",
        esp_legend = "🔴 Убийца    🔵 Шериф    🟢 Невиновный",
        language = "Язык",
        auto_execute = "Автозапуск после телепорта",
        menu_hint = "Показать или скрыть меню: Left Ctrl",
    },
    cs = {
        search = "Hledat",
        tab_farm = "Farma",
        tab_player = "Hráč",
        tab_visual = "Vizuál",
        tab_settings = "Nastavení",
        sub_farm = "Auto farma a statistiky",
        sub_player = "Ochrana a chování postavy",
        sub_visual = "Zvýraznění hráčů",
        sub_settings = "Možnosti skriptu",
        card_stats = "Statistiky",
        card_farm = "Farma",
        card_protect = "Ochrana",
        card_esp = "ESP",
        card_interface = "Rozhraní",
        card_script = "Skript",
        stat_collected = "Nasbíráno",
        stat_status = "Stav",
        stat_rate = "Za hodinu",
        stat_total = "Celkem",
        status_off = "Vypnuto",
        status_farming = "Farmím",
        status_wait_coins = "Čekám na mince",
        status_wait_round = "Čekám na kolo",
        status_no_char = "Žádná postava",
        status_bag_full = "Pytel plný",
        status_avoiding = "Vyhýbám se vrahovi",
        status_killing = "Zabíjím hráče",
        status_spectating = "Sleduji",
        status_picking_gun = "Beru zbraň",
        farm_speed = "Rychlost farmy",
        farm_method = "Metoda farmy",
        method_classic = "Klasická (rychlá)",
        method_undermap = "Pod mapou",
        speed_classic = "Rychlost klasické",
        speed_undermap = "Rychlost pod mapou",
        card_safety = "Bezpečnost",
        card_full = "Plný pytel",
        card_connection = "Připojení",
        auto_farm = "Auto farma",
        avoid_murderer = "Vyhýbat se vrahovi",
        respawn_full = "Respawn při plném pytli",
        kill_all_full = "Zabít všechny při plném pytli (vrah)",
        auto_rejoin = "Auto připojení po vykopnutí",
        pick_gun = "Sebrat zbraň",
        anti_fling = "Anti-Fling (ochrana proti flingu)",
        anti_afk = "Anti-AFK (nevykopne za nečinnost)",
        esp_roles = "Zvýraznění rolí",
        esp_legend = "🔴 Vrah    🔵 Šerif    🟢 Nevinný",
        language = "Jazyk",
        auto_execute = "Automatické spuštění po teleportu",
        menu_hint = "Zobrazit nebo skrýt menu: Left Ctrl",
    },
}

if not Lang[Settings.Language] then
    Settings.Language = "en"
end

-- Чешский словарь: English -> Čeština.
-- Отдельная карта, чтобы не дублировать перевод в 500+ вызовах L():
-- L() сам подставляет перевод, а T() страхует строковые ключи Lang.
local CS_STRINGS = {
    ["A custom sky replaces the game's sky while selected. Choose \"Game default\" to bring it back."] = "Vlastní obloha nahradí oblohu hry, dokud je vybrána. Volbou \"Game default\" ji vrátíš.",
    ["A floating button that opens the menu (handy on mobile)"] = "Plovoucí tlačítko, které otevírá menu (praktické na mobilu)",
    ["About"] = "O skriptu",
    ["Accent"] = "Akcent",
    ["Actions"] = "Akce",
    ["Aim hook"] = "Hák zaměření",
    ["Aimed manual throw of the knife"] = "Ruční hod nožem s mířením",
    ["Aimlock (camera)"] = "Aimlock (kamera)",
    ["Aimlock disabled"] = "Aimlock vypnut",
    ["Aimlock enabled"] = "Aimlock zapnut",
    ["Ambient color"] = "Barva okolí",
    ["Amount"] = "Množství",
    ["An innocent who picked up the sheriff's gun"] = "Nevinný, který sebral šerifovu zbraň",
    ["Animations"] = "Animace",
    ["Anti-AFK (prevent idle kick)"] = "Anti-AFK (nevykopne za nečinnost)",
    ["Anti-Fling (fling protection)"] = "Anti-Fling (ochrana proti flingu)",
    ["Appearance"] = "Vzhled",
    ["Appearance reset"] = "Vzhled obnoven",
    ["Area radius"] = "Poloměr oblasti",
    ["Arrow size"] = "Velikost šipky",
    ["As the murderer, touches everyone with the knife (no teleport)"] = "Jako vrah se nožem dotkne všech (bez teleportu)",
    ["Atmosphere"] = "Atmosféra",
    ["Atmosphere color"] = "Barva atmosféry",
    ["Atmosphere, fog and clouds"] = "Atmosféra, mlha a mraky",
    ["Aura"] = "Aura",
    ["Aura radius"] = "Poloměr aury",
    ["Auto"] = "Auto",
    ["Auto equip gun"] = "Automaticky vzít zbraň",
    ["Auto execute after teleport"] = "Automatické spuštění po teleportu",
    ["Auto farm"] = "Auto farma",
    ["Auto farm disabled"] = "Auto farma vypnuta",
    ["Auto farm enabled"] = "Auto farma zapnuta",
    ["Auto range"] = "Automatický dosah",
    ["Auto rejoin"] = "Automatické připojení",
    ["Auto rejoin on kick"] = "Auto připojení po vykopnutí",
    ["Auto shoot"] = "Automatická střelba",
    ["Auto shoot delay"] = "Prodleva auto střelby",
    ["Auto shoot murderer when bag is full (sheriff)"] = "Auto střelba na vraha při plném pytli (šerif)",
    ["Auto throw"] = "Automatický hod",
    ["Auto throw disabled"] = "Automatický hod vypnut",
    ["Auto throw enabled"] = "Automatický hod zapnut",
    ["Autorun copy saved"] = "Kopie pro autorun uložena",
    ["Avoid murderer"] = "Vyhýbat se vrahovi",
    ["Bag is full: respawning"] = "Pytel je plný: respawn",
    ["Behavior"] = "Chování",
    ["Bhop"] = "Bhop",
    ["Bloom"] = "Bloom",
    ["Bloom intensity"] = "Intenzita bloomu",
    ["Bloom size"] = "Velikost bloomu",
    ["Bloom threshold"] = "Práh bloomu",
    ["blur"] = "rozmazání",
    ["Blur behind menu"] = "Rozmazání za menu",
    ["Blur strength"] = "Síla rozmazání",
    ["Both"] = "Oba",
    ["Bottom"] = "Dole",
    ["Box"] = "Rámeček",
    ["Box color"] = "Barva rámečku",
    ["Box style"] = "Styl rámečku",
    ["Box width"] = "Šířka rámečku",
    ["Boxes"] = "Rámečky",
    ["Brightness"] = "Jas",
    ["Build"] = "Build",
    ["By role"] = "Podle role",
    ["Camera"] = "Kamera",
    ["Camera smoothly follows the murderer"] = "Kamera plynule sleduje vraha",
    ["Center"] = "Střed",
    ["Center dot"] = "Tečka ve středu",
    ["Chams"] = "Chams",
    ["Character effects"] = "Efekty postavy",
    ["Character walk speed (16 is default)"] = "Rychlost chůze postavy (výchozí 16)",
    ["chDot"] = "Tečka zaměřovače",
    ["Checks whether a wall blocks the player"] = "Kontroluje, zda hráče blokuje zeď",
    ["Choose a config first"] = "Nejprve vyber konfiguraci",
    ["chOutline"] = "Obrys zaměřovače",
    ["Classic (fast)"] = "Klasická (rychlá)",
    ["Classic flies straight to coins. Under map flies below the floor and rises to each coin."] = "Klasická letí přímo k mincím. Pod mapou letí pod podlahou a u každé mince vystoupá.",
    ["Classic speed"] = "Rychlost klasické",
    ["Click again to confirm"] = "Klikni znovu pro potvrzení",
    ["Clipboard is not supported"] = "Schránka není podporována",
    ["Cloud color"] = "Barva mraků",
    ["Cloud cover"] = "Pokrytí mraky",
    ["Cloud density"] = "Hustota mraků",
    ["Clouds"] = "Mraky",
    ["Collected"] = "Nasbíráno",
    ["Collects coins automatically while you are alive in a round"] = "Automaticky sbírá mince, dokud jsi naživu v kole",
    ["Color"] = "Barva",
    ["Color correction"] = "Barevná korekce",
    ["Color mode"] = "Barevný režim",
    ["Colors"] = "Barvy",
    ["Combat"] = "Boj",
    ["Combat module loaded"] = "Bojový modul načten",
    ["Config deleted"] = "Konfigurace smazána",
    ["Config loaded"] = "Konfigurace načtena",
    ["Config name"] = "Název konfigurace",
    ["Config saved"] = "Konfigurace uložena",
    ["Configs"] = "Konfigurace",
    ["Connection"] = "Připojení",
    ["Contrast"] = "Kontrast",
    ["Copy Job ID"] = "Kopírovat Job ID",
    ["Corner radius"] = "Poloměr rohů",
    ["Corner size"] = "Velikost rohů",
    ["Corners"] = "Rohy",
    ["Could not delete config"] = "Konfiguraci nelze smazat",
    ["Could not load config"] = "Konfiguraci nelze načíst",
    ["Could not save autorun copy"] = "Kopii pro autorun nelze uložit",
    ["Could not save config"] = "Konfiguraci nelze uložit",
    ["Could not save settings"] = "Nastavení nelze uložit",
    ["Cross"] = "Kříž",
    ["crosshair"] = "zaměřovač",
    ["Cursor = near the crosshair, Closest = by distance"] = "Cursor = u zaměřovače, Closest = podle vzdálenosti",
    ["Custom"] = "Vlastní",
    ["Custom accent"] = "Vlastní akcent",
    ["Custom box color"] = "Vlastní barva rámečku",
    ["Custom chams color"] = "Vlastní barva chams",
    ["Custom color"] = "Vlastní barva",
    ["Custom skeleton color"] = "Vlastní barva kostry",
    ["Custom tracer color"] = "Vlastní barva tras",
    ["Decay color"] = "Barva doznívání",
    ["Delete selected"] = "Smazat vybrané",
    ["Density"] = "Hustota",
    ["Depth of field"] = "Hloubka ostrosti",
    ["Details"] = "Detaily",
    ["Dim hidden players"] = "Ztmavit skryté hráče",
    ["Disable 3D rendering"] = "Vypnout 3D vykreslování",
    ["Disable shadows"] = "Vypnout stíny",
    ["Disconnected: rejoining"] = "Odpojeno: připojuji znovu",
    ["Discord"] = "Discord",
    ["Discord link copied"] = "Odkaz na Discord zkopírován",
    ["Discord link is not set yet"] = "Odkaz na Discord zatím není nastaven",
    ["Discord opened in your browser"] = "Discord otevřen v prohlížeči",
    ["Display name"] = "Zobrazované jméno",
    ["Distance"] = "Vzdálenost",
    ["Distance from the crosshair in pixels"] = "Vzdálenost od zaměřovače v pixelech",
    ["Distance unit"] = "Jednotka vzdálenosti",
    ["Does not shoot through walls"] = "Nestřílí přes zdi",
    ["Dot"] = "Tečka",
    ["Dynamic leads by target speed, Instant throws at the current position"] = "Dynamic vede podle rychlosti cíle, Instant hází na aktuální pozici",
    ["Effects"] = "Efekty",
    ["Effects follow your character and come back after respawn. They use the color mode set on the left."] = "Efekty sledují tvou postavu a po respawnu se vrátí. Používají barevný režim nastavený vlevo.",
    ["Enable ESP"] = "Zapnout ESP",
    ["Enable world changes"] = "Zapnout změny světa",
    ["End point"] = "Koncový bod",
    ["Enemy names"] = "Jména nepřátel",
    ["English"] = "English",
    ["Enter a config name"] = "Zadej název konfigurace",
    ["error"] = "chyba",
    ["ESP"] = "ESP",
    ["Executor does not expose the source — save the file manually"] = "Executor neposkytuje zdrojový kód — ulož soubor ručně",
    ["Exposure"] = "Expozice",
    ["Extra forward boost on jump"] = "Extra zrychlení vpřed při skoku",
    ["Extras"] = "Doplňky",
    ["Fade with distance"] = "Mizí se vzdáleností",
    ["Farm"] = "Farma",
    ["Farm method"] = "Metoda farmy",
    ["Feet"] = "Nohy",
    ["Field of view"] = "Zorné pole",
    ["Fill"] = "Výplň",
    ["Fill and color"] = "Výplň a barva",
    ["Fill opacity"] = "Průhlednost výplně",
    ["Fill transparency"] = "Průhlednost výplně",
    ["Filters"] = "Filtry",
    ["Fire"] = "Střelba",
    ["Fires automatically while the murderer is inside your crosshair radius"] = "Automaticky střílí, dokud je vrah v poloměru zaměřovače",
    ["Fly"] = "Let",
    ["Fly Speed"] = "Rychlost letu",
    ["Focus distance"] = "Vzdálenost ostření",
    ["Fog"] = "Mlha",
    ["Fog color"] = "Barva mlhy",
    ["Fog end"] = "Konec mlhy",
    ["Fog start"] = "Začátek mlhy",
    ["Font"] = "Písmo",
    ["FPS"] = "FPS",
    ["FPS cap"] = "Limit FPS",
    ["FPS graph"] = "Graf FPS",
    ["Full"] = "Plný",
    ["Full bag"] = "Plný pytel",
    ["Full-bag auto shoot disabled"] = "Auto střelba při plném pytli vypnuta",
    ["Full-bag auto shoot enabled"] = "Auto střelba při plném pytli zapnuta",
    ["Full-bag shot origin is placed near the murderer, so walls and obstacles do not block it"] = "Výstřel při plném pytli vychází u vraha, takže ho zdi a překážky neblokují",
    ["Game default"] = "Výchozí hry",
    ["Game effects"] = "Efekty hry",
    ["Game log"] = "Log hry",
    ["gameLog"] = "Log hry",
    ["Gap"] = "Mezera",
    ["General"] = "Obecné",
    ["Glare"] = "Lesk",
    ["Glow and focus"] = "Záře a ostření",
    ["Glow light"] = "Světlo záře",
    ["Gravity"] = "Gravitace",
    ["GUN"] = "ZBRAŇ",
    ["Gun color"] = "Barva zbraně",
    ["Gun ESP"] = "ESP zbraně",
    ["Gun pickup disabled"] = "Sbírání zbraně vypnuto",
    ["Gun pickup enabled"] = "Sbírání zbraně zapnuto",
    ["Haze"] = "Opar",
    ["Head"] = "Hlava",
    ["Head circle"] = "Kroužek na hlavě",
    ["Hero"] = "Hrdina",
    ["Hidden players color"] = "Barva skrytých hráčů",
    ["Highlight dropped gun"] = "Zvýraznit odhozenou zbraň",
    ["Highlights the whole character"] = "Zvýrazní celou postavu",
    ["Indicators"] = "Indikátory",
    ["Infinite Jumps"] = "Nekonečné skoky",
    ["Info"] = "Info",
    ["In-focus radius"] = "Poloměr ostrosti",
    ["Innocent"] = "Nevinný",
    ["Innocents grab the dropped gun when the sheriff dies (works without autofarm)"] = "Nevinní seberou odhozenou zbraň, když šerif zemře (funguje i bez auto farmy)",
    ["Innocents grab the gun when the sheriff dies"] = "Nevinní seberou zbraň, když šerif zemře",
    ["Interface"] = "Rozhraní",
    ["Invisible"] = "Neviditelnost",
    ["Job ID"] = "Job ID",
    ["Job ID copied"] = "Job ID zkopírován",
    ["Join a new server"] = "Připojit se na nový server",
    ["Join our Discord"] = "Náš Discord",
    ["Jump again mid-air when touching a wall"] = "Skok ve vzduchu, když se dotýkáš zdi",
    ["Jump Power"] = "Síla skoku",
    ["Jump power (50 is default)"] = "Síla skoku (výchozí 50)",
    ["kbActiveOnly"] = "Jen aktivní funkce",
    ["Keybinds"] = "Klávesy",
    ["Kill all instantly"] = "Okamžitě zabít všechny",
    ["Kill all when bag is full (murderer)"] = "Zabít všechny při plném pytli (vrah)",
    ["Kill all when full"] = "Zabít všechny při plném pytli",
    ["Kill aura"] = "Aura zabíjení",
    ["Kill aura disabled"] = "Aura zabíjení vypnuta",
    ["Kill aura enabled"] = "Aura zabíjení zapnuta",
    ["Knife"] = "Nůž",
    ["Knife · Throw Aim"] = "Nůž · Míření hodu",
    ["Knife aim"] = "Míření nožem",
    ["Knife Aim (throw)"] = "Míření nožem (hod)",
    ["Knife aim disabled"] = "Míření nožem vypnuto",
    ["Knife aim enabled"] = "Míření nožem zapnuto",
    ["Knife speed"] = "Rychlost nože",
    ["Language"] = "Jazyk",
    ["Last save"] = "Poslední uložení",
    ["launcher"] = "launcher",
    ["Launcher button"] = "Tlačítko launcheru",
    ["Lead time"] = "Doba předstihu",
    ["Length"] = "Délka",
    ["Lighting"] = "Osvětlení",
    ["Lighting technology"] = "Technologie osvětlení",
    ["Line thickness"] = "Tloušťka čar",
    ["Lines"] = "Řádky",
    ["Load selected"] = "Načíst vybranou",
    ["Look"] = "Vzhled",
    ["Makes your character invisible"] = "Udělá tvou postavu neviditelnou",
    ["Master switch: everything below is applied only while it is on, and the game's values are restored when it is off"] = "Hlavní přepínač: vše níže se aplikuje jen když je zapnutý, po vypnutí se hodnoty hry obnoví",
    ["Materials"] = "Materiály",
    ["Max distance"] = "Max. vzdálenost",
    ["Max distance (0 = no limit)"] = "Max. vzdálenost (0 = bez limitu)",
    ["Menu"] = "Menu",
    ["Menu accent"] = "Akcent menu",
    ["Menu key"] = "Klávesa menu",
    ["Meters"] = "Metry",
    ["Misc"] = "Ostatní",
    ["Moon size"] = "Velikost měsíce",
    ["motion"] = "animace",
    ["Mouse"] = "Myš",
    ["Movement"] = "Pohyb",
    ["Murderer"] = "Vrah",
    ["My config"] = "Moje konfigurace",
    ["Name"] = "Jméno",
    ["Name style"] = "Styl jména",
    ["Needs a saved YozoraHub_Autorun.lua file (executor workspace folder). "] = "Vyžaduje uložený soubor YozoraHub_Autorun.lua (složka workspace executoru). ",
    ["Needs an executor that supports setfpscap"] = "Vyžaduje executor s podporou setfpscap",
    ["Needs Auto execute and a saved YozoraHub_Autorun.lua to resume farming"] = "Pro pokračování farmy je potřeba Auto spuštění a uložený YozoraHub_Autorun.lua",
    ["No Clip"] = "No Clip",
    ["No target in range"] = "Žádný cíl v dosahu",
    ["None"] = "Žádný",
    ["not saved yet"] = "zatím neuloženo",
    ["Nothing found"] = "Nic nenalezeno",
    ["Off"] = "Vypnuto",
    ["Off-screen arrows"] = "Šipky mimo obrazovku",
    ["Offset"] = "Posun",
    ["On: left click throws too, like the native knife. Off: only RMB / E / throw key — stray clicks never waste the knife"] = "Zap: hodí i levým kliknutím jako původní nůž. Vyp: jen PPM / E / klávesa hodu — náhodné kliky nůž neztratí",
    ["Only active features"] = "Jen aktivní funkce",
    ["Opacity"] = "Průhlednost",
    ["Outdoor ambient color"] = "Barva venkovního okolí",
    ["Outline"] = "Obrys",
    ["Outline transparency"] = "Průhlednost obrysu",
    ["Override ambient light"] = "Přepsat okolní světlo",
    ["Override brightness"] = "Přepsat jas",
    ["Override exposure"] = "Přepsat expozici",
    ["Override field of view"] = "Přepsat zorné pole",
    ["Override shadow softness"] = "Přepsat měkkost stínů",
    ["Override sky details"] = "Přepsat detaily oblohy",
    ["Override time of day"] = "Přepsat denní dobu",
    ["Panel color"] = "Barva panelu",
    ["Panel positions"] = "Pozice panelů",
    ["Panel positions reset"] = "Pozice panelů obnoveny",
    ["Particle color"] = "Barva částic",
    ["Particle size"] = "Velikost částic",
    ["Per hour"] = "Za hodinu",
    ["Performance"] = "Výkon",
    ["Petals"] = "Okvětní lístky",
    ["Pick up gun"] = "Sebrat zbraň",
    ["Pick up gun (combat)"] = "Sebrat zbraň (boj)",
    ["Pick up gun (farm)"] = "Sebrat zbraň (farma)",
    ["Piercer bullet (through walls)"] = "Průbojná kulka (přes zdi)",
    ["Ping"] = "Ping",
    ["Ping graph"] = "Graf pingu",
    ["Place ID"] = "ID místa",
    ["Players"] = "Hráči",
    ["Points to players who are outside the screen"] = "Ukazuje na hráče mimo obrazovku",
    ["Prediction"] = "Predikce",
    ["Preset"] = "Předvolba",
    ["Prioritize sheriff on throw"] = "Priorita šerifa při hodu",
    ["Profiles"] = "Profily",
    ["Protection"] = "Ochrana",
    ["Rainbow"] = "Duhová",
    ["Rays intensity"] = "Intenzita paprsků",
    ["Rays spread"] = "Rozptyl paprsků",
    ["Rejoin this server"] = "Připojit se na tento server",
    ["Remove the game's atmosphere"] = "Odstranit atmosféru hry",
    ["Remove the game's post effects"] = "Odstranit post-efekty hry",
    ["Reset"] = "Obnovit",
    ["Reset appearance"] = "Obnovit vzhled",
    ["Reset to default"] = "Obnovit výchozí",
    ["Reset to the game's look"] = "Obnovit vzhled hry",
    ["Respawn when bag is full"] = "Respawn při plném pytli",
    ["Respawn when full"] = "Respawn při plném pytli",
    ["Revert/Flux simulate the target's physics (most accurate)"] = "Revert/Flux simulují fyziku cíle (nejpřesnější)",
    ["Ring radius"] = "Poloměr kroužku",
    ["Role"] = "Role",
    ["Role colors"] = "Barvy podle rolí",
    ["Round ended"] = "Kolo skončilo",
    ["Round started"] = "Kolo začalo",
    ["Safety"] = "Bezpečnost",
    ["Saturation"] = "Sytost",
    ["Save autorun copy"] = "Uložit kopii pro autorun",
    ["Save config"] = "Uložit konfiguraci",
    ["Save settings"] = "Uložit nastavení",
    ["Save settings now"] = "Uložit nastavení teď",
    ["Saved configs"] = "Uložené konfigurace",
    ["Scene"] = "Scéna",
    ["Screen"] = "Obrazovka",
    ["Screen stretch"] = "Roztažení obrazovky",
    ["Script"] = "Skript",
    ["Search"] = "Hledat",
    ["Search..."] = "Hledat...",
    ["Server"] = "Server",
    ["Set FPS cap"] = "Nastavit limit FPS",
    ["Settings file"] = "Soubor nastavení",
    ["Settings saved"] = "Nastavení uloženo",
    ["Shadow softness"] = "Měkkost stínů",
    ["Sheriff"] = "Šerif",
    ["Sheriff · Silent Aim"] = "Šerif · Silent Aim",
    ["Shoot the murderer (teleport)"] = "Vystřelit na vraha (teleport)",
    ["Shoot when full"] = "Střílet při plném pytli",
    ["Shoots at the murderer by itself"] = "Sám střílí na vraha",
    ["Shot origin is placed near the target so walls do not block it"] = "Výstřel vychází u cíle, takže ho zdi neblokují",
    ["Shots / Hits"] = "Výstřely / Zásahy",
    ["Show every player through walls"] = "Zobrazit všechny hráče přes zdi",
    ["Show FPS"] = "Zobrazit FPS",
    ["Show ping"] = "Zobrazit ping",
    ["Show sun and moon"] = "Zobrazit slunce a měsíc",
    ["Show time"] = "Zobrazit čas",
    ["Shows player names above them (needs ESP enabled)"] = "Zobrazuje jména hráčů nad nimi (vyžaduje zapnuté ESP)",
    ["Shows players through walls: boxes, names, chams, skeleton and more"] = "Zobrazuje hráče přes zdi: rámečky, jména, chams, kostru a další",
    ["Shows the menu key and the features that are on"] = "Zobrazuje klávesu menu a zapnuté funkce",
    ["Silent aim"] = "Silent aim",
    ["Silent Aim (gun)"] = "Silent Aim (zbraň)",
    ["Silent aim disabled"] = "Silent aim vypnut",
    ["Silent aim enabled"] = "Silent aim zapnut",
    ["Size"] = "Velikost",
    ["Skeleton"] = "Kostra",
    ["Skips coins close to the murderer"] = "Přeskakuje mince blízko vraha",
    ["Sky"] = "Obloha",
    ["Sky details"] = "Detaily oblohy",
    ["Skybox"] = "Skybox",
    ["Smoke"] = "Kouř",
    ["Smoothing"] = "Vyhlazování",
    ["Sound volume"] = "Hlasitost zvuku",
    ["Sparkles"] = "Jiskry",
    ["Speed"] = "Rychlost",
    ["Speed & Jump"] = "Rychlost a skok",
    ["Speed Glitch"] = "Speed Glitch",
    ["Speed graph"] = "Graf rychlosti",
    ["Spin"] = "Otáčení",
    ["Stars"] = "Hvězdy",
    ["Start point"] = "Počáteční bod",
    ["Statistics"] = "Statistiky",
    ["Status"] = "Stav",
    ["Stop under roofs"] = "Zastavit pod střechou",
    ["Stops other players from pushing or flinging you"] = "Zabrání ostatním hráčům tě strkat nebo flingovat",
    ["Studs"] = "Studů",
    ["Style"] = "Styl",
    ["Sun rays"] = "Sluneční paprsky",
    ["Sun size"] = "Velikost slunce",
    ["Takeover"] = "Převzetí",
    ["Takes over the gun and fires straight at the predicted position of the murderer: no executor hooks needed."] = "Převezme zbraň a střílí přímo na předpokládanou pozici vraha: nejsou potřeba háky executoru.",
    ["Takes over the knife and throws it at the predicted point of your aim: right-click, throw key or button."] = "Převezme nůž a hodí ho na předpokládaný bod tvého míření: PPM, klávesa hodu nebo tlačítko.",
    ["Takes over the knife: your throw goes straight to the predicted point (RMB / E / throw key)"] = "Převezme nůž: tvůj hod letí přímo na předpokládaný bod (PPM / E / klávesa hodu)",
    ["Target"] = "Cíl",
    ["Target marker"] = "Značka cíle",
    ["Target mode"] = "Režim cíle",
    ["Text"] = "Text",
    ["Text outline"] = "Obrys textu",
    ["Text size"] = "Velikost textu",
    ["The screen goes black but the game keeps running. Handy for AFK farming."] = "Obrazovka zčerná, ale hra běží dál. Hodí se pro AFK farmu.",
    ["Theme"] = "Motiv",
    ["Thickness"] = "Tloušťka",
    ["Through walls"] = "Přes zdi",
    ["Through walls (full-bag shot)"] = "Přes zdi (výstřel při plném pytli)",
    ["Throw"] = "Hod",
    ["Throw key"] = "Klávesa hodu",
    ["Throw knife now"] = "Hodit nůž teď",
    ["Throw on left click"] = "Hod na levé kliknutí",
    ["Throws the knife at the nearest victim by itself"] = "Sám hází nůž na nejbližší oběť",
    ["Tiancai offset"] = "Tiancai posun",
    ["Time of day"] = "Denní doba",
    ["Tint"] = "Tónování",
    ["Tooltips"] = "Nápovědy",
    ["Top"] = "Nahoře",
    ["Total"] = "Celkem",
    ["Touches everyone who comes into the radius with the knife"] = "Nožem se dotkne každého, kdo vejde do poloměru",
    ["Tracers"] = "Trasy",
    ["Trail"] = "Stopa",
    ["Trigger bot"] = "Trigger bot",
    ["Trigger bot disabled"] = "Trigger bot vypnut",
    ["Trigger bot enabled"] = "Trigger bot zapnut",
    ["Trigger radius"] = "Poloměr spouštění",
    ["T-shape"] = "Tvar T",
    ["Turns off blur, bloom and color effects added by the game"] = "Vypne rozmazání, bloom a barevné efekty přidané hrou",
    ["UI scale"] = "Měřítko UI",
    ["Under map"] = "Pod mapou",
    ["Under map speed"] = "Rychlost pod mapou",
    ["Unload hub"] = "Vyložit hub",
    ["Use role colors"] = "Použít barvy rolí",
    ["Username"] = "Uživatelské jméno",
    ["Version"] = "Verze",
    ["ViewportSize"] = "Velikost okna",
    ["Vignette"] = "Vinětace",
    ["Vignette strength"] = "Síla vinětace",
    ["Visibility check"] = "Kontrola viditelnosti",
    ["Visible target only"] = "Jen viditelný cíl",
    ["Vision"] = "Vidění",
    ["Visuals"] = "Vizuál",
    ["Waiting gun"] = "Čekání na zbraň",
    ["Walk Speed"] = "Rychlost chůze",
    ["Walk through walls and objects"] = "Procházení zdmi a objekty",
    ["Wall check"] = "Kontrola zdi",
    ["Wall Hop"] = "Skok od zdi",
    ["WASD to move, Space up, Shift down"] = "WASD pohyb, Space nahoru, Shift dolů",
    ["watermark"] = "watermark",
    ["Weapon"] = "Zbraň",
    ["Weather"] = "Počasí",
    ["Weather sounds"] = "Zvuky počasí",
    ["When you click, the shot goes straight to the murderer"] = "Po kliknutí letí výstřel přímo na vraha",
    ["Wind"] = "Vítr",
    ["Wind and area"] = "Vítr a oblast",
    ["Wind direction"] = "Směr větru",
    ["Window"] = "Okno",
    ["Window opacity"] = "Průhlednost okna",
    ["With a full bag the sheriff keeps shooting the murderer (auto-equip, prediction)"] = "S plným pytlem šerif stále střílí na vraha (auto-vyzbrojení, predikce)",
    ["wmFps"] = "FPS",
    ["wmPing"] = "Ping",
    ["wmTime"] = "Čas",
    ["Works even when ESP is off"] = "Funguje i při vypnutém ESP",
    ["World"] = "Svět",
    ["World changes"] = "Změny světa",
    ["World gravity (196.2 is default)"] = "Gravitace světa (výchozí 196.2)",
    ["writefile is not supported"] = "writefile není podporován",
    ["X-Ray"] = "X-Ray",
    ["You are not the murderer"] = "Nejsi vrah",
    ["Your executor does not support file access, so named configs are unavailable. The current settings are still saved automatically."] = "Tvůj executor nepodporuje přístup k souborům, pojmenované konfigurace nejsou dostupné. Aktuální nastavení se přesto ukládá automaticky.",
}

-- L("English", "Русский") создаёт строку сразу на трёх языках:
-- чешский берётся из CS_STRINGS по английскому тексту (иначе — английский)
local function L(en, ru, cs)
    return { en = en, ru = ru, cs = cs or CS_STRINGS[en] or en }
end

local function T(key)
    if type(key) == "table" then
        return key[Settings.Language] or key.en or ""
    end
    local set = Lang[Settings.Language] or Lang.en
    local value = set[key]
    if value ~= nil then return value end
    if Settings.Language == "cs" then
        local english = Lang.en[key]
        if english then return CS_STRINGS[english] or english end
    end
    return Lang.en[key] or key
end

-- Задаёт текст и запоминает ключ, чтобы переводить при смене языка
local Localized = {}
local function Loc(obj, prop, key, prefix)
    prefix = prefix or ""
    table.insert(Localized, { Obj = obj, Prop = prop, Key = key, Prefix = prefix })
    obj[prop] = prefix .. T(key)
end

local Notify = function() end -- задаётся внутри BuildUI
local GameLog = function() end -- задаётся внутри BuildUI (лог игры в HUD)

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
do
    local oldGui = PlayerGui:FindFirstChild("YozoraHub_UI")
    if oldGui then oldGui:Destroy() end
    local oldHud = PlayerGui:FindFirstChild("YozoraHub_HUD")
    if oldHud then oldHud:Destroy() end
end

-- ==========================================================
-- Логотип Yozora Hub (PNG 128x128 в base64, записывается в workspace при первом запуске)
-- ==========================================================
-- Если загрузить логотип в Roblox и вписать сюда его ID, будет использован он.
local LOGO_ASSET_ID = ""

local LOGO_B64 = [=[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]=]

local function DecodeBase64(data)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local lookup = {}
    for index = 1, #alphabet do
        lookup[alphabet:byte(index)] = index - 1
    end
    local out, buffer, bits = {}, 0, 0
    for index = 1, #data do
        local value = lookup[data:byte(index)]
        if value then
            buffer = buffer * 64 + value
            bits += 6
            if bits >= 8 then
                bits -= 8
                local divisor = 2 ^ bits
                out[#out + 1] = string.char(math.floor(buffer / divisor))
                buffer = buffer % divisor
            end
        end
    end
    return table.concat(out)
end

local EmbeddedCache = {}

-- Записывает встроенный PNG в workspace и возвращает ссылку на него
-- (nil, если executor не умеет работать с файлами)
local function LoadEmbedded(fileName, b64)
    if EmbeddedCache[fileName] ~= nil then return EmbeddedCache[fileName] or nil end
    EmbeddedCache[fileName] = false
    local getAsset = getcustomasset or getsynasset
    if not (getAsset and writefile and isfile and isfolder and makefolder) then return nil end
    pcall(function()
        if not isfolder("YozoraHub") then makefolder("YozoraHub") end
        local path = "YozoraHub/" .. fileName
        if not isfile(path) then writefile(path, DecodeBase64(b64)) end
        EmbeddedCache[fileName] = getAsset(path)
    end)
    return EmbeddedCache[fileName] or nil
end

local function GetLogo()
    if LOGO_ASSET_ID ~= "" then return "rbxassetid://" .. LOGO_ASSET_ID end
    return LoadEmbedded("logo_v1.png", LOGO_B64)
end

-- ==========================================================
-- Атлас иконок: Material Design Icons (Pictogrammers), белые иконки 64x64 в сетке 10 колонок.
-- Встроен в скрипт и сохраняется в workspace, поэтому не зависит от чужих ассетов.
-- Если загрузить атлас в Roblox и вписать сюда его Image ID, будет использован он.
-- ==========================================================
local ICON_ATLAS_ID = ""

local ICON_ATLAS_B64 = [=[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]=]

local function GetIconAtlas()
    if ICON_ATLAS_ID ~= "" then return "rbxassetid://" .. ICON_ATLAS_ID end
    return LoadEmbedded("icons_v2.png", ICON_ATLAS_B64)
end

-- Весь интерфейс строится внутри функции, чтобы не упереться в лимит локальных переменных
local function BuildUI()
    local Lighting = game:GetService("Lighting")
    local StatsService = game:GetService("Stats")
    local GuiInset = game:GetService("GuiService")
    local TouchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

    do
        local oldBlur = Lighting:FindFirstChild("YozoraHub_Blur")
        if oldBlur then oldBlur:Destroy() end
    end

    -- ==========================================================
    -- 5.1 Настройки внешнего вида (хранятся в Settings.UI)
    -- ==========================================================
    local UI_DEFAULTS = {
        accent = "ff6fae", base = "Carbon", panel = "0e0e0f",
        opacity = 1, uiScale = "Auto", radius = 1, textScale = 1, font = "Montserrat",
        blur = false, motion = true, tooltips = true, launcher = TouchOnly,
        menuKey = "LeftControl", width = 980, height = 660, posX = 0, posY = 0,
        -- HUD
        watermark = true, wmFps = true, wmPing = true, wmTime = false,
        keybinds = false, kbActiveOnly = true,
        crosshair = false, chStyle = "Cross", chSize = 10, chThick = 2, chGap = 4,
        chDot = false, chOutline = true, chColour = "ff6fae",
        fpsGraph = false, pingGraph = false, speedGraph = false, gameLog = false, logLines = 7,
        wmX = -1, wmY = -1, kbX = -1, kbY = -1, gfX = -1, gfY = -1, lgX = -1, lgY = -1,
    }

    -- Новый дизайн (v0.1.1): старые настройки внешнего вида сбрасываются один раз
    if type(Settings.UI) ~= "table" then Settings.UI = {} end
    if Settings.UI.design ~= 2 then
        Settings.UI = { design = 2, menuKey = Settings.UI.menuKey }
    end

    local savePending = false
    local function SaveSoon()
        if savePending then return end
        savePending = true
        task.delay(0.8, function()
            savePending = false
            SaveConfig()
        end)
    end

    local function Pref(key)
        local value = Settings.UI[key]
        if value == nil then return UI_DEFAULTS[key] end
        return value
    end

    local function SetPref(key, value)
        Settings.UI[key] = value
        SaveSoon()
    end

    local function PrefNum(key, lo, hi)
        return math.clamp(tonumber(Pref(key)) or UI_DEFAULTS[key], lo, hi)
    end

    local function PrefBool(key)
        local value = Pref(key)
        if type(value) ~= "boolean" then value = UI_DEFAULTS[key] end
        return value
    end

    -- Привязка виджета к значению: Settings[Setting], Settings.UI[Pref] или собственные Get/Set
    local function Bind(o)
        local function get()
            if o.Get then return o.Get() end
            if o.Setting then return Settings[o.Setting] end
            if o.Pref then return Pref(o.Pref) end
            if o.Esp then return EspOpt(o.Esp) end
            if o.Vis then return VisOpt(o.Vis) end
            return o.Value
        end
        local function set(value)
            if o.Set then o.Set(value)
            elseif o.Setting then Settings[o.Setting] = value; SaveSoon()
            elseif o.Pref then SetPref(o.Pref, value)
            elseif o.Esp then SetEspOpt(o.Esp, value); SaveSoon()
            elseif o.Vis then SetVisOpt(o.Vis, value); SaveSoon()
            else o.Value = value end
        end
        return get, set
    end


    -- ==========================================================
    -- 5.2 Тема (цвета-токены, базовые темы, акценты)
    -- ==========================================================
    local function hex(value) return Color3.fromHex(value) end

    local THEME_BASES = {
        { "Carbon", { Background = "0e0e0f", Sidebar = "151516", Surface = "121213", Surface2 = "1c1c1d",
            Elevated = "232324", Line = "2a2a2c", Text = "f4f4f5", Muted = "8e8e93", Faint = "5b5b60" } },
        { "Sakura", { Background = "181020", Sidebar = "1b1025", Surface = "20142b", Surface2 = "2a1b38",
            Elevated = "362446", Line = "422a4e", Text = "f0e6f0", Muted = "a591af", Faint = "6e5a78" } },
        { "Midnight", { Background = "0c0d10", Sidebar = "0f1014", Surface = "14161b", Surface2 = "1b1e25",
            Elevated = "22252d", Line = "1f2229", Text = "eceef3", Muted = "8a8f9e", Faint = "575c69" } },
        { "Graphite", { Background = "111214", Sidebar = "141517", Surface = "1a1b1e", Surface2 = "232427",
            Elevated = "2b2d31", Line = "2a2c30", Text = "f0f1f3", Muted = "9a9da4", Faint = "62656c" } },
        { "Amoled", { Background = "000000", Sidebar = "040405", Surface = "0b0c0e", Surface2 = "111216",
            Elevated = "181a1f", Line = "16181c", Text = "f2f3f6", Muted = "8f94a1", Faint = "545965" } },
        { "Deep Sea", { Background = "090d13", Sidebar = "0b1119", Surface = "101823", Surface2 = "162131",
            Elevated = "1d2b3e", Line = "1a2433", Text = "e8eef8", Muted = "8794ab", Faint = "55627a" } },
        { "Plum", { Background = "0e0b12", Sidebar = "110d16", Surface = "17121d", Surface2 = "1f1927",
            Elevated = "271f32", Line = "221b2b", Text = "efe9f6", Muted = "9a8fa8", Faint = "625870" } },
        { "Forest", { Background = "0b0f0d", Sidebar = "0d1210", Surface = "121815", Surface2 = "19211d",
            Elevated = "202a25", Line = "1c241f", Text = "e9f0ec", Muted = "8a9a92", Faint = "56645d" } },
    }

    local ACCENT_PRESETS = {
        { "Hot Pink", "ff6fae" }, { "Sakura", "ff80ab" }, { "Rose", "ff5fa2" }, { "Crimson", "d64458" }, { "Ember", "ff7a3d" },
        { "Gold", "f5b94a" }, { "Mint", "3ddc97" }, { "Ocean", "3d9bff" }, { "Violet", "8b6cff" }, { "Ice", "7fe0ff" },
    }

    local Theme = {
        tokens = { Success = hex("3ddc97"), Warning = hex("f5b94a"), Danger = hex("f0506e"),
            Glass = hex("ffffff"), Accent = hex("ff6fae"), OnAccent = hex("ffffff") },
        base = "Carbon",
        registry = setmetatable({}, { __mode = "k" }), -- weak-ключи: убитые объекты уходят сами
        hooks = {},
    }

    function Theme.resolve(role)
        if typeof(role) == "Color3" then return role end
        if type(role) == "function" then return role(Theme.tokens) end
        return Theme.tokens[role] or Theme.tokens.Text
    end

    function Theme.bind(object, property, role)
        local properties = Theme.registry[object]
        if not properties then
            properties = {}
            Theme.registry[object] = properties
        end
        properties[property] = role
        pcall(function() object[property] = Theme.resolve(role) end)
        return object
    end

    function Theme.refresh()
        for object, properties in pairs(Theme.registry) do
            if object.Parent then
                for property, role in pairs(properties) do
                    local ok, value = pcall(Theme.resolve, role)
                    if ok and value ~= nil then
                        pcall(function() object[property] = value end)
                    end
                end
            else
                Theme.registry[object] = nil -- объект уничтожен
            end
        end
        for _, hook in ipairs(Theme.hooks) do pcall(hook) end
    end

    function Theme.updateOnAccent()
        local a = Theme.tokens.Accent
        local luminance = 0.299 * a.R + 0.587 * a.G + 0.114 * a.B
        Theme.tokens.OnAccent = luminance > 0.62 and hex("14091c") or hex("ffffff")
    end

    function Theme.setBase(name)
        for _, base in ipairs(THEME_BASES) do
            if base[1] == name then
                for role, value in pairs(base[2]) do Theme.tokens[role] = hex(value) end
                Theme.base = name
                return true
            end
        end
        return false
    end

    -- "Свой" цвет панели: остальные тона выводятся из выбранного цвета
    function Theme.setPanel(color)
        local h, s, v = color:ToHSV()
        s = math.min(s, 0.9)
        v = math.clamp(v, 0.025, 0.3)
        local function panel(offset, mult)
            return Color3.fromHSV(h, math.clamp(s * (mult or 1), 0, 1), math.clamp(v + offset, 0, 1))
        end
        local t = Theme.tokens
        t.Background, t.Sidebar, t.Surface = panel(0), panel(0.014), panel(0.042)
        t.Surface2, t.Elevated, t.Line = panel(0.08, 0.92), panel(0.112, 0.86), panel(0.096, 0.9)
        t.Text = Color3.fromHSV(h, s * 0.07, 0.95)
        t.Muted = Color3.fromHSV(h, s * 0.16, 0.62)
        t.Faint = Color3.fromHSV(h, s * 0.18, 0.41)
        Theme.base = "Custom"
    end

    local function SafeHex(value, fallback)
        local ok, color = pcall(Color3.fromHex, tostring(value))
        return ok and color or Color3.fromHex(fallback)
    end

    local function LoadTheme()
        local base = Pref("base")
        if base == "Custom" then
            Theme.setPanel(SafeHex(Pref("panel"), UI_DEFAULTS.panel))
        elseif not Theme.setBase(base) then
            Theme.setBase("Sakura")
        end
        Theme.tokens.Accent = SafeHex(Pref("accent"), UI_DEFAULTS.accent)
        Theme.updateOnAccent()
    end
    LoadTheme()

    local function AccentSoft(amount)
        return function(t) return t.Surface2:Lerp(t.Accent, amount) end
    end

    -- ==========================================================
    -- 5.3 Шрифты и текст
    -- ==========================================================
    local W = {
        Regular = Enum.FontWeight.Regular, Medium = Enum.FontWeight.Medium, Semi = Enum.FontWeight.SemiBold,
        Bold = Enum.FontWeight.Bold, Heavy = Enum.FontWeight.ExtraBold,
    }

    local Fonts = {
        families = {
            { "Roboto", "Roboto" }, { "Builder Sans", "BuilderSans" }, { "Montserrat", "Montserrat" },
            { "Nunito", "Nunito" }, { "Ubuntu", "Ubuntu" }, { "Titillium Web", "TitilliumWeb" },
            { "Source Sans", "SourceSansPro" }, { "Roboto Mono", "RobotoMono" }, { "Gotham", "Gotham" },
        },
        name = "Montserrat", id = "Montserrat", cache = {}, textScale = 1,
    }

    function Fonts.face(weight)
        local key = Fonts.id .. "|" .. weight.Name
        if not Fonts.cache[key] then
            local face
            if Fonts.id == "Gotham" then
                -- GothamSemibold в новых дампах может отсутствовать: резолвим с фолбэком
                local family = weight.Value >= 700 and "GothamBold"
                    or (weight.Value >= 600 and "GothamSemibold" or "GothamMedium")
                face = Font.fromEnum(FontByName(family, FontByName("GothamMedium", Enum.Font.Gotham)))
            else
                local ok, value = pcall(Font.new, "rbxasset://fonts/families/" .. Fonts.id .. ".json",
                    weight, Enum.FontStyle.Normal)
                face = ok and value or Font.fromEnum(Enum.Font.GothamMedium)
            end
            Fonts.cache[key] = face
        end
        return Fonts.cache[key]
    end

    local TextReg = setmetatable({}, { __mode = "k" }) -- weak-ключи

    local function ApplyText(object)
        local info = TextReg[object]
        if not info then return end
        pcall(function()
            object.FontFace = Fonts.face(info.weight)
            object.TextSize = math.max(8, math.floor(info.size * Fonts.textScale + 0.5))
        end)
    end

    local function ApplyAllText()
        for object in pairs(TextReg) do
            if object.Parent then ApplyText(object) else TextReg[object] = nil end
        end
    end

    function Fonts.setFamily(name)
        for _, family in ipairs(Fonts.families) do
            if family[1] == name then
                Fonts.name, Fonts.id = family[1], family[2]
                Fonts.cache = {}
                ApplyAllText()
                return true
            end
        end
        return false
    end

    local function NewText(class, props, parent, size, weight, role)
        if props.BackgroundTransparency == nil then props.BackgroundTransparency = 1 end
        props.BorderSizePixel = 0
        local object = New(class, props, parent)
        TextReg[object] = { size = size, weight = weight or W.Medium }
        Theme.bind(object, "TextColor3", role or "Text")
        ApplyText(object)
        return object
    end

    -- ==========================================================
    -- 5.4 Иконки (атлас Lucide) и базовые помощники
    -- ==========================================================
    -- АТЛАС ИКОНОК: свой (см. ICON_ATLAS_B64 вверху файла). Чтобы заменить его, подмени атлас
    -- и эту таблицу: имя = {x, y} (левый верхний угол ячейки), размер ячейки в ICON_CELL.
    local ICON_CELL = 64
    local ICON_DATA = {
        ["coins"] = {0, 0},
        ["user-round"] = {64, 0},
        ["eye"] = {128, 0},
        ["settings"] = {192, 0},
        ["server"] = {256, 0},
        ["shield"] = {320, 0},
        ["shield-check"] = {384, 0},
        ["scan-eye"] = {448, 0},
        ["wifi"] = {512, 0},
        ["backpack"] = {576, 0},
        ["chart-bar"] = {0, 64},
        ["chevron-down"] = {64, 64},
        ["chevron-right"] = {128, 64},
        ["chevron-left"] = {192, 64},
        ["search"] = {256, 64},
        ["x"] = {320, 64},
        ["plus"] = {384, 64},
        ["minus"] = {448, 64},
        ["check"] = {512, 64},
        ["palette"] = {576, 64},
        ["layout-panel-left"] = {0, 128},
        ["sliders-horizontal"] = {64, 128},
        ["rotate-ccw"] = {128, 128},
        ["keyboard"] = {192, 128},
        ["globe"] = {256, 128},
        ["languages"] = {320, 128},
        ["bell"] = {384, 128},
        ["info"] = {448, 128},
        ["zap"] = {512, 128},
        ["skull"] = {576, 128},
        ["swords"] = {0, 192},
        ["crosshair"] = {64, 192},
        ["target"] = {128, 192},
        ["gauge"] = {192, 192},
        ["cpu"] = {256, 192},
        ["folder"] = {320, 192},
        ["folder-open"] = {384, 192},
        ["save"] = {448, 192},
        ["trash"] = {512, 192},
        ["download"] = {576, 192},
        ["upload"] = {0, 256},
        ["sun"] = {64, 256},
        ["moon"] = {128, 256},
        ["star"] = {192, 256},
        ["map-pin"] = {256, 256},
        ["copy"] = {320, 256},
        ["file-plus"] = {384, 256},
        ["power"] = {448, 256},
        ["flower-2"] = {512, 256},
        ["panel-left-close"] = {576, 256},
        ["panel-left-open"] = {0, 320},
        ["panel-left"] = {64, 320},
        ["menu"] = {128, 320},
        ["clock"] = {192, 320},
        ["users"] = {256, 320},
        ["link"] = {320, 320},
        ["external-link"] = {384, 320},
        ["sparkles"] = {448, 320},
        ["ghost"] = {512, 320},
        ["user"] = {576, 320},
        ["puzzle"] = {0, 384},
        ["log-out"] = {64, 384},
        ["refresh-cw"] = {128, 384},
        ["home"] = {192, 384},
        ["crown"] = {256, 384},
        ["package"] = {320, 384},
        ["hand-coins"] = {384, 384},
        ["library"] = {448, 384},
        ["list-plus"] = {512, 384},
        ["toggle-right"] = {576, 384},
        ["wand-sparkles"] = {0, 448},
        ["hud"] = {64, 448},
        ["discord"] = {128, 448},
        ["folders"] = {192, 448},
        ["info-outline"] = {256, 448},
        ["check-bold"] = {320, 448},
    }
    local ICON_ATLAS = GetIconAtlas()

    if ICON_ATLAS then
        task.spawn(function()
            pcall(function() game:GetService("ContentProvider"):PreloadAsync({ ICON_ATLAS }) end)
        end)
    end

    local radiusMult = 1
    local CornerReg = setmetatable({}, { __mode = "k" }) -- weak-ключи

    local function Corner(parent, px)
        local corner = New("UICorner", { CornerRadius = UDim.new(0, math.floor(px * radiusMult + 0.5)) }, parent)
        CornerReg[corner] = px
        return corner
    end

    local function Pill(parent)
        return New("UICorner", { CornerRadius = UDim.new(1, 0) }, parent)
    end

    local function Stroke(parent, role, thickness, transparency)
        local stroke = New("UIStroke", {
            Thickness = thickness or 1, Transparency = transparency or 0,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, parent)
        Theme.bind(stroke, "Color", role or "Line")
        return stroke
    end

    local function Tw(object, goals, duration, style, direction)
        if PrefBool("motion") then
            local tween = TweenService:Create(object, TweenInfo.new(duration or 0.15,
                style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goals)
            tween:Play()
            return tween
        end
        for property, value in pairs(goals) do
            pcall(function() object[property] = value end)
        end
        return nil
    end

    local function Icon(parent, name, size, role)
        local data = ICON_DATA[name]
        local image = New("ImageLabel", {
            Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScaleType = Enum.ScaleType.Fit,
        }, parent)
        Theme.bind(image, "ImageColor3", role or "Muted")

        -- запасной значок, пока картинка не загрузилась (или если её нет)
        local glyph = nil
        local function showGlyph()
            if glyph then return end
            image.ImageTransparency = 1
            glyph = NewText("TextLabel", {
                Size = UDim2.fromScale(1, 1), Text = "•",
                TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
            }, image, size, W.Bold, role or "Muted")
        end

        -- Запасная точка только если атласа или иконки нет совсем.
        -- (Раньше точка включалась по таймеру, если картинка "не загрузилась", но Roblox
        -- не загружает изображения невидимых страниц, поэтому точки появлялись зря.)
        if data and ICON_ATLAS then
            image.Image = ICON_ATLAS
            image.ImageRectOffset = Vector2.new(data[1], data[2])
            image.ImageRectSize = Vector2.new(ICON_CELL, ICON_CELL)
        else
            showGlyph()
        end
        return image
    end

    -- Логотип Yozora Hub (если не удалось загрузить, то значок-цветок)
    local function Logo(parent, size)
        local content = GetLogo()
        if content then
            return New("ImageLabel", {
                Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, BorderSizePixel = 0,
                Image = content, ScaleType = Enum.ScaleType.Fit,
            }, parent)
        end
        return Icon(parent, "flower-2", math.floor(size * 0.7), "Accent")
    end

    local function KeyShortName(name)
        local map = {
            LeftControl = "LCtrl", RightControl = "RCtrl", LeftShift = "LShift", RightShift = "RShift",
            LeftAlt = "LAlt", RightAlt = "RAlt", Return = "Enter", Backquote = "`",
        }
        return map[name] or name
    end

    local UI = { Controls = {}, Rows = {}, Values = {}, LangHooks = {}, Tabs = {}, Capturing = false }



    -- ==========================================================
    -- 5.5 Каркас окна
    -- ==========================================================
    local ScreenGui = New("ScreenGui", {
        Name = "YozoraHub_UI", ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 50,
    }, PlayerGui)

    local MIN_W, MIN_H = 720, 460
    local TOP_H, SUB_H, BOTTOM_H = 56, 34, 40

    local Main = New("Frame", {
        Name = "Main", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, PrefNum("posX", -3000, 3000), 0.5, PrefNum("posY", -3000, 3000)),
        Size = UDim2.fromOffset(PrefNum("width", MIN_W, 1800), PrefNum("height", MIN_H, 1100)),
        BorderSizePixel = 0, ClipsDescendants = true,
    }, ScreenGui)
    Theme.bind(Main, "BackgroundColor3", "Background")
    Corner(Main, 8)
    Stroke(Main, "Line", 1, 0)
    local UiScale = New("UIScale", { Scale = 1 }, Main)


    -- Всплывающий слой (выпадающие списки, палитра): клик вне окна закрывает
    local PopupLayer = New("TextButton", {
        Name = "PopupLayer", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        Text = "", AutoButtonColor = false, Visible = false, ZIndex = 40,
    }, ScreenGui)
    local ActivePopup = nil   -- главное всплывающее окно (шестерёнка, палитра, список)
    local ActiveList = nil    -- список ПОВЕРХ главного окна (дропдаун внутри попапа)

    local function CloseList()
        if ActiveList then
            for _, connection in ipairs(ActiveList.Conns) do connection:Disconnect() end
            ActiveList.Frame:Destroy()
            if TrackSink == ActiveList.Conns then
                -- соединения снова идут в общий массив или в родительский попап
                TrackSink = ActivePopup and ActivePopup.Conns or nil
            end
            ActiveList = nil
        end
    end

    local function ClosePopup()
        CloseList()
        if ActivePopup then
            for _, connection in ipairs(ActivePopup.Conns) do connection:Disconnect() end
            ActivePopup.Frame:Destroy()
            if TrackSink == ActivePopup.Conns then TrackSink = nil end
            ActivePopup = nil
        end
        PopupLayer.Visible = false
    end
    Track(PopupLayer.MouseButton1Click:Connect(function()
        if ActiveList then CloseList() else ClosePopup() end
    end))

    local function OpenPopup(anchor, width, height)
        local scale = UiScale.Scale
        local isSub = ActivePopup ~= nil
        -- если открыт главный попап (шестерёнка) — список открывается СВЕРХУ него,
        -- а не вместо него (иначе дропдауны внутри шестерёнки были невозможны)
        if isSub then CloseList() else ClosePopup() end
        PopupLayer.Visible = true
        local frame = New("Frame", {
            Size = UDim2.fromOffset(width, height), BorderSizePixel = 0, Active = true,
            ZIndex = isSub and 42 or 41,
        }, PopupLayer)
        Theme.bind(frame, "BackgroundColor3", "Elevated")
        Corner(frame, 10)
        Stroke(frame, "Line", 1, 0.1)
        New("UIScale", { Scale = scale }, frame)

        local abs, size, view = anchor.AbsolutePosition, anchor.AbsoluteSize, ScreenGui.AbsoluteSize
        local x = math.clamp(abs.X, 6, math.max(6, view.X - width * scale - 6))
        local y = abs.Y + size.Y + 6
        if y + height * scale > view.Y - 6 then
            y = math.max(6, abs.Y - height * scale - 6)
        end
        frame.Position = UDim2.fromOffset(x / scale, y / scale)

        if isSub then
            ActiveList = { Frame = frame, Conns = {}, Owner = anchor }
            TrackSink = ActiveList.Conns
            return frame, ActiveList
        end
        ActivePopup = { Frame = frame, Conns = {}, Owner = anchor }
        TrackSink = ActivePopup.Conns
        return frame, ActivePopup
    end

    -- Уведомления
    local ToastHolder = New("Frame", {
        Size = UDim2.new(0, 300, 1, -24), AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, -12), BackgroundTransparency = 1, ZIndex = 35,
    }, ScreenGui)
    New("UIListLayout", {
        VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, ToastHolder)
    local ToastScale = New("UIScale", { Scale = 1 }, ToastHolder)
    local KIND_ROLE = { info = "Accent", success = "Success", warning = "Warning", error = "Danger" }

    Notify = function(title, text, kind, duration)
        GameLog(title) -- все уведомления попадают и в лог игры
        local toast = New("CanvasGroup", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BorderSizePixel = 0, GroupTransparency = 1,
        }, ToastHolder)
        Theme.bind(toast, "BackgroundColor3", "Elevated")
        Corner(toast, 10)
        Stroke(toast, "Line", 1, 0.1)

        local bar = New("Frame", { Size = UDim2.new(0, 4, 1, 0), BorderSizePixel = 0 }, toast)
        Theme.bind(bar, "BackgroundColor3", KIND_ROLE[kind or "info"] or "Accent")

        local content = New("Frame", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        }, toast)
        New("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, content)
        New("UIPadding", {
            PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 12),
            PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
        }, content)
        NewText("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = T(title),
            TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, LayoutOrder = 1,
        }, content, 14, W.Bold)
        if text and text ~= "" then
            NewText("TextLabel", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = T(text),
                TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, LayoutOrder = 2,
            }, content, 13, W.Regular, "Muted")
        end

        Tw(toast, { GroupTransparency = 0 }, 0.2)
        task.delay(duration or 4, function()
            if not toast.Parent then return end
            local tween = Tw(toast, { GroupTransparency = 1 }, 0.25)
            task.delay(tween and 0.3 or 0, function()
                if toast.Parent then toast:Destroy() end
            end)
        end)
    end

    -- Подсказки при наведении
    local TipFrame = New("Frame", {
        AutomaticSize = Enum.AutomaticSize.XY, BorderSizePixel = 0, Visible = false, ZIndex = 60,
    }, ScreenGui)
    Theme.bind(TipFrame, "BackgroundColor3", "Elevated")
    Corner(TipFrame, 8)
    Stroke(TipFrame, "Line", 1, 0.1)
    New("UIPadding", {
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7),
    }, TipFrame)
    local TipScale = New("UIScale", { Scale = 1 }, TipFrame)
    local TipLabel = NewText("TextLabel", {
        AutomaticSize = Enum.AutomaticSize.XY, Text = "", TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, TipFrame, 13, W.Regular)
    New("UISizeConstraint", { MaxSize = Vector2.new(260, 400) }, TipLabel)

    local tipToken = 0
    local function HideTip()
        tipToken += 1
        TipFrame.Visible = false
    end

    local function PlaceTip(position)
        local scale = UiScale.Scale
        TipScale.Scale = scale
        TipFrame.Position = UDim2.fromOffset((position.X + 16) / scale, (position.Y + 20) / scale)
    end

    Track(UserInputService.InputChanged:Connect(function(input)
        if TipFrame.Visible and input.UserInputType == Enum.UserInputType.MouseMovement then
            PlaceTip(input.Position)
        end
    end))

    local function AttachTip(guiObject, key)
        Track(guiObject.MouseEnter:Connect(function()
            if not PrefBool("tooltips") or ActivePopup or ActiveList then return end
            tipToken += 1
            local mine = tipToken
            task.delay(0.45, function()
                if mine ~= tipToken then return end
                TipLabel.Text = T(key)
                local mouse = UserInputService:GetMouseLocation() - GuiInset:GetGuiInset()
                PlaceTip(mouse)
                TipFrame.Visible = true
            end)
        end))
        Track(guiObject.MouseLeave:Connect(HideTip))
    end



    -- ==========================================================
    -- 5.6 Верхняя панель: логотип, вкладки, кнопки
    -- ==========================================================
    local TopBar = New("Frame", { Name = "TopBar", Size = UDim2.new(1, 0, 0, TOP_H), BorderSizePixel = 0 }, Main)
    Theme.bind(TopBar, "BackgroundColor3", "Sidebar")
    Corner(TopBar, 8)
    local TopFill = New("Frame", {
        Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -10), BorderSizePixel = 0,
    }, TopBar)
    Theme.bind(TopFill, "BackgroundColor3", "Sidebar")
    local TopLine = New("Frame", {
        Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BorderSizePixel = 0,
    }, TopBar)
    Theme.bind(TopLine, "BackgroundColor3", "Line")

    local BRAND_W = 186
    local Brand = New("Frame", { Size = UDim2.fromOffset(BRAND_W, TOP_H), BackgroundTransparency = 1 }, TopBar)
    local BrandLogo = Logo(Brand, 36)
    BrandLogo.AnchorPoint = Vector2.new(0, 0.5)
    BrandLogo.Position = UDim2.new(0, 14, 0.5, 0)
    local BrandLabel = NewText("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(58, 0), Text = "",
        RichText = true, TextXAlignment = Enum.TextXAlignment.Left,
    }, Brand, 17, W.Bold)
    local function UpdateBrand()
        BrandLabel.Text = ('Yozora <font color="#%s">Hub</font>'):format(Theme.tokens.Accent:ToHex())
    end
    UpdateBrand()
    Theme.hooks[#Theme.hooks + 1] = UpdateBrand

    local TabsRow = New("Frame", {
        Size = UDim2.new(1, -(BRAND_W + 112), 1, 0), Position = UDim2.fromOffset(BRAND_W, 0),
        BackgroundTransparency = 1, ClipsDescendants = true,
    }, TopBar)
    New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
        VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
    }, TabsRow)

    local function TopButton(iconName, fromRight)
        local button = New("TextButton", {
            Size = UDim2.fromOffset(34, 34), AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -fromRight, 0.5, 0), BorderSizePixel = 0, Text = "", AutoButtonColor = false,
        }, TopBar)
        Theme.bind(button, "BackgroundColor3", "Surface2")
        Corner(button, 8)
        Stroke(button, "Line", 1, 0.4)
        local icon = Icon(button, iconName, 18, "Text")
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.Position = UDim2.fromScale(0.5, 0.5)
        Track(button.MouseEnter:Connect(function() Tw(button, { BackgroundTransparency = 0.35 }, 0.1) end))
        Track(button.MouseLeave:Connect(function() Tw(button, { BackgroundTransparency = 0 }, 0.1) end))
        return button
    end
    local CloseButton = TopButton("x", 14)
    local DiscordButton = TopButton("discord", 56)

    -- Подвкладки (строка под верхней панелью, только если у вкладки они есть)
    local SubRowHolder = New("Frame", {
        Size = UDim2.new(1, -36, 0, SUB_H), Position = UDim2.fromOffset(18, TOP_H), BackgroundTransparency = 1,
        Visible = false,
    }, Main)

    -- ==========================================================
    -- 5.7 Нижняя панель и области содержимого
    -- ==========================================================
    local BottomBar = New("Frame", {
        Name = "BottomBar", Size = UDim2.new(1, 0, 0, BOTTOM_H), AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1), BorderSizePixel = 0,
    }, Main)
    Theme.bind(BottomBar, "BackgroundColor3", "Sidebar")
    Corner(BottomBar, 8)
    local BottomFill = New("Frame", { Size = UDim2.new(1, 0, 0, 10), BorderSizePixel = 0 }, BottomBar)
    Theme.bind(BottomFill, "BackgroundColor3", "Sidebar")
    local BottomLine = New("Frame", { Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0 }, BottomBar)
    Theme.bind(BottomLine, "BackgroundColor3", "Line")

    local function BarButton(iconName, x, fromRight)
        local button = New("TextButton", {
            Size = UDim2.fromOffset(30, 28), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
            AnchorPoint = fromRight and Vector2.new(1, 0.5) or Vector2.new(0, 0.5),
            Position = fromRight and UDim2.new(1, -x, 0.5, 0) or UDim2.new(0, x, 0.5, 0),
        }, BottomBar)
        local icon = Icon(button, iconName, 18, "Muted")
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.Position = UDim2.fromScale(0.5, 0.5)
        Track(button.MouseEnter:Connect(function() Theme.bind(icon, "ImageColor3", "Text") end))
        Track(button.MouseLeave:Connect(function() Theme.bind(icon, "ImageColor3", "Muted") end))
        return button, icon
    end
    local SearchButton = BarButton("search", 14, false)
    local SaveButton = BarButton("save", 50, false)
    local FoldersButton = BarButton("folders", 86, false)
    local InfoButton = BarButton("info-outline", 44, true)

    local SearchBox = NewText("TextBox", {
        Size = UDim2.fromOffset(300, 26), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 126, 0.5, 0),
        Text = "", PlaceholderText = "", ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 0, Visible = false,
    }, BottomBar, 13, W.Regular)
    Theme.bind(SearchBox, "BackgroundColor3", "Surface2")
    Theme.bind(SearchBox, "PlaceholderColor3", "Faint")
    Corner(SearchBox, 6)
    Stroke(SearchBox, "Line", 1, 0.2)
    New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8) }, SearchBox)

    local PagesHolder = New("Frame", {
        Size = UDim2.new(1, 0, 1, -(TOP_H + BOTTOM_H)), Position = UDim2.fromOffset(0, TOP_H),
        BackgroundTransparency = 1, ClipsDescendants = true,
    }, Main)

    local SearchPanel = New("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, -(TOP_H + BOTTOM_H)), Position = UDim2.fromOffset(0, TOP_H),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
    }, Main)
    Theme.bind(SearchPanel, "ScrollBarImageColor3", "Accent")
    New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, SearchPanel)
    New("UIPadding", {
        PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14),
    }, SearchPanel)

    -- Ручка изменения размера (правый нижний угол)
    local ResizeGrip = New("TextButton", {
        Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 20,
    }, Main)
    for _, offset in ipairs({ { 9, 13 }, { 13, 9 } }) do
        local dash = New("Frame", {
            Size = UDim2.fromOffset(9, 2), Position = UDim2.fromOffset(offset[1], offset[2]),
            BorderSizePixel = 0, Rotation = -45, ZIndex = 21,
        }, ResizeGrip)
        Theme.bind(dash, "BackgroundColor3", "Faint")
    end

    -- ==========================================================
    -- 5.8 Поведение окна: масштаб, перетаскивание, открытие и закрытие
    -- ==========================================================
    local isOpen = true
    UI.HudPanels = {}

    local function ViewportSize()
        local camera = workspace.CurrentCamera
        return camera and camera.ViewportSize or Vector2.new(1280, 720)
    end

    local SCALE_MODES = { "Auto", "75%", "90%", "100%", "110%", "125%", "150%" }

    local function ApplyScale()
        local mode = tostring(Pref("uiScale"))
        local scale
        local percent = tonumber(mode:match("^(%d+)%%$"))
        if percent then
            scale = percent / 100
        else
            local view, size = ViewportSize(), Main.Size
            local fit = math.min((view.X - 24) / size.X.Offset, (view.Y - 60) / size.Y.Offset)
            scale = math.clamp(fit, 0.4, 1)
        end
        UiScale.Scale = scale
        ToastScale.Scale = scale
    end

    do
        local camera = workspace.CurrentCamera
        if camera then
            Track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                if isOpen then ApplyScale() end
            end))
        end
    end

    local function MakeDraggable(handle)
        local dragging, dragStart, startPos = false, nil, nil
        Track(handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging, dragStart, startPos = true, input.Position, Main.Position
            end
        end))
        Track(UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = (input.Position - dragStart) / UiScale.Scale
                Main.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end))
        Track(UserInputService.InputEnded:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch) then
                dragging = false
                SetPref("posX", Main.Position.X.Offset)
                SetPref("posY", Main.Position.Y.Offset)
            end
        end))
    end
    MakeDraggable(TopBar)
    MakeDraggable(Brand)

    do
        local resizing, startMouse, startSize, startPos = false, nil, nil, nil
        Track(ResizeGrip.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                resizing, startMouse, startSize, startPos = true, input.Position, Main.Size, Main.Position
            end
        end))
        Track(UserInputService.InputChanged:Connect(function(input)
            if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = (input.Position - startMouse) / UiScale.Scale
                local view = ViewportSize() / UiScale.Scale
                local width = math.clamp(startSize.X.Offset + delta.X, MIN_W, math.max(MIN_W, view.X - 10))
                local height = math.clamp(startSize.Y.Offset + delta.Y, MIN_H, math.max(MIN_H, view.Y - 40))
                Main.Size = UDim2.fromOffset(width, height)
                Main.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + (width - startSize.X.Offset) / 2,
                    startPos.Y.Scale, startPos.Y.Offset + (height - startSize.Y.Offset) / 2
                )
            end
        end))
        Track(UserInputService.InputEnded:Connect(function(input)
            if resizing and (input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch) then
                resizing = false
                SetPref("width", Main.Size.X.Offset)
                SetPref("height", Main.Size.Y.Offset)
                SetPref("posX", Main.Position.X.Offset)
                SetPref("posY", Main.Position.Y.Offset)
                ApplyScale()
            end
        end))
    end

    -- Размытие за меню
    local function BlurSet(on)
        local blur = Lighting:FindFirstChild("YozoraHub_Blur")
        if on and PrefBool("blur") then
            if not blur then
                blur = New("BlurEffect", { Name = "YozoraHub_Blur", Size = 0 }, Lighting)
            end
            Tw(blur, { Size = 14 }, 0.25)
        elseif blur then
            Tw(blur, { Size = 0 }, 0.2)
            task.delay(0.35, function()
                if blur.Parent and not (isOpen and PrefBool("blur")) then blur:Destroy() end
            end)
        end
    end

    local function SetPanelsActive()
        for _, panel in ipairs(UI.HudPanels) do
            if panel.Parent then panel.Active = isOpen end
        end
    end

    local function OpenMenu()
        if isOpen then return end
        isOpen = true
        ApplyScale()
        Main.Visible = true
        local target = UiScale.Scale
        UiScale.Scale = target * 0.94
        Tw(UiScale, { Scale = target }, 0.2, Enum.EasingStyle.Back)
        BlurSet(true)
        SetPanelsActive()
    end

    local function CloseMenu()
        if not isOpen then return end
        isOpen = false
        ClosePopup()
        HideTip()
        BlurSet(false)
        SetPanelsActive()
        local target = UiScale.Scale
        Tw(UiScale, { Scale = target * 0.94 }, 0.15)
        task.delay(PrefBool("motion") and 0.16 or 0, function()
            if not isOpen then
                Main.Visible = false
                UiScale.Scale = target
            end
        end)
    end

    local function ToggleMenu()
        if isOpen then CloseMenu() else OpenMenu() end
    end

    Track(CloseButton.MouseButton1Click:Connect(CloseMenu))

    -- Клавиша меню
    local MenuKey = Enum.KeyCode.LeftControl
    local function LoadMenuKey()
        local ok, key = pcall(function() return Enum.KeyCode[tostring(Pref("menuKey"))] end)
        MenuKey = (ok and key) or Enum.KeyCode.LeftControl
    end
    LoadMenuKey()

    Track(UserInputService.InputBegan:Connect(function(input, processed)
        if processed or UI.Capturing then return end
        if input.KeyCode == MenuKey then
            ToggleMenu()
        end
    end))

    -- Кнопка-лаунчер (удобно на телефоне)
    local Launcher = New("TextButton", {
        Name = "Launcher", Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0, 16, 0.5, -23),
        BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 30, Visible = false,
    }, ScreenGui)
    Theme.bind(Launcher, "BackgroundColor3", "Elevated")
    Pill(Launcher)
    Stroke(Launcher, "Accent", 1.5, 0.2)
    do
        local launcherIcon = Logo(Launcher, 34)
        launcherIcon.AnchorPoint = Vector2.new(0.5, 0.5)
        launcherIcon.Position = UDim2.fromScale(0.5, 0.5)

        local pressed, moved, startMouse, startPos = false, 0, nil, nil
        Track(Launcher.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                pressed, moved, startMouse, startPos = true, 0, input.Position, Launcher.Position
            end
        end))
        Track(UserInputService.InputChanged:Connect(function(input)
            if pressed and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - startMouse
                moved = math.max(moved, delta.Magnitude)
                if moved > 6 then
                    Launcher.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                        startPos.Y.Scale, startPos.Y.Offset + delta.Y)
                end
            end
        end))
        Track(UserInputService.InputEnded:Connect(function(input)
            if pressed and (input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch) then
                pressed = false
                if moved < 6 then ToggleMenu() end
            end
        end))
    end

    -- ==========================================================
    -- 5.9 Применение настроек внешнего вида
    -- ==========================================================
    local Appearance = {}

    function Appearance.radius()
        radiusMult = PrefNum("radius", 0, 2)
        for corner, px in pairs(CornerReg) do
            if corner.Parent then
                corner.CornerRadius = UDim.new(0, math.floor(px * radiusMult + 0.5))
            else
                CornerReg[corner] = nil
            end
        end
    end

    function Appearance.text()
        Fonts.textScale = PrefNum("textScale", 0.85, 1.25)
        if not Fonts.setFamily(tostring(Pref("font"))) then
            ApplyAllText()
        end
    end

    function Appearance.opacity()
        Main.BackgroundTransparency = 1 - PrefNum("opacity", 0.5, 1)
    end

    function Appearance.launcher()
        -- на тач-устройствах без клавиатуры лаунчер — единственный способ
        -- открыть меню, поэтому его нельзя выключить совсем
        Launcher.Visible = TouchOnly or PrefBool("launcher")
    end
    function Appearance.blur() if isOpen then BlurSet(true) else BlurSet(false) end end

    function Appearance.theme()
        LoadTheme()
        Theme.refresh()
    end

    function Appearance.all()
        Appearance.theme()
        Appearance.radius()
        Appearance.text()
        ApplyScale()
        Appearance.opacity()
        Appearance.launcher()
        Appearance.blur()
        if UI.LayoutPages then UI.LayoutPages() end
        if Appearance.hud then Appearance.hud() end
    end


    -- ==========================================================
    -- 5.10 Вкладки, страницы, группы
    -- ==========================================================
    local CurrentTab = nil
    local TabMethods, SectionMethods = {}, {}
    TabMethods.__index = TabMethods
    SectionMethods.__index = SectionMethods

    local function RefreshHeader() end -- заголовков у страниц больше нет (оставлено для совместимости)

    local function StyleTab(tab)
        local on = tab.Active
        tab.Button.BackgroundTransparency = on and 0 or 1
        tab.Stroke.Transparency = on and 0.35 or 1
        Theme.bind(tab.Icon, "ImageColor3", on and "Accent" or "Muted")
        Theme.bind(tab.Label, "TextColor3", on and "Text" or "Muted")
    end

    local function StyleSubs(tab)
        for key, pill in pairs(tab.SubPills or {}) do
            local on = key == tab.Sub
            Theme.bind(pill.Label, "TextColor3", on and "Text" or "Muted")
            pill.Bar.Visible = on
        end
    end

    local function ShowSearch(visible)
        SearchPanel.Visible = visible
        PagesHolder.Visible = not visible
    end

    local SelectTab
    SelectTab = function(tab, subKey)
        ClosePopup()
        HideTip()
        CurrentTab = tab
        tab.Sub = subKey or tab.Sub or tab.DefaultSub
        for _, other in ipairs(UI.Tabs) do
            other.Active = other == tab
            StyleTab(other)
            if other.SubRow then other.SubRow.Visible = other == tab end
            for key, page in pairs(other.Pages) do
                page.Scroll.Visible = other == tab and key == tab.Sub
            end
        end
        local top = TOP_H + (tab.Subs and SUB_H or 0)
        PagesHolder.Position = UDim2.fromOffset(0, top)
        PagesHolder.Size = UDim2.new(1, 0, 1, -(top + BOTTOM_H))
        SubRowHolder.Visible = tab.Subs ~= nil
        StyleSubs(tab)
        if SearchBox.Text ~= "" then
            SearchBox.Text = ""
        end
        ShowSearch(false)
    end

    local function CreatePage(parent)
        local scroll = New("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 4, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
            ElasticBehavior = Enum.ElasticBehavior.Never,
        }, parent)
        Theme.bind(scroll, "ScrollBarImageColor3", "Accent")

        -- Ширины задаются в пикселях (см. LayoutPages)
        local holder = New("Frame", {
            Size = UDim2.fromOffset(900, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        }, scroll)
        New("UIPadding", {
            PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18),
            PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 22),
        }, holder)
        local columns = New("Frame", {
            Size = UDim2.fromOffset(864, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        }, holder)
        local layout = New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 18),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, columns)
        local cols = {}
        for index = 1, 3 do
            local frame = New("Frame", {
                Size = UDim2.fromOffset(276, 0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1, LayoutOrder = index,
            }, columns)
            New("UIListLayout", { Padding = UDim.new(0, 24), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
            cols[index] = frame
        end
        return { Scroll = scroll, Holder = holder, Columns = columns, Layout = layout, Cols = cols, Sections = {}, Order = 0 }
    end

    -- Число колонок зависит от ширины окна; ширины считаются в пикселях
    local function LayoutPages()
        local width = Main.Size.X.Offset
        local inner = math.max(260, width - 36)
        local count = width >= 880 and 3 or (width >= 600 and 2 or 1)
        local gap = 18
        local colWidth = math.floor((inner - gap * (count - 1)) / count)
        for _, tab in ipairs(UI.Tabs) do
            for _, page in pairs(tab.Pages) do
                page.Holder.Size = UDim2.fromOffset(width, 0)
                page.Columns.Size = UDim2.fromOffset(inner, 0)
                for index, column in ipairs(page.Cols) do
                    column.Visible = index <= count
                    column.Size = UDim2.fromOffset(index <= count and colWidth or 0, 0)
                end
                for _, section in ipairs(page.Sections) do
                    local target = page.Cols[((section.Col - 1) % count) + 1]
                    if section.Card.Parent ~= target then section.Card.Parent = target end
                end
            end
            tab.Label.Visible = width >= 940 -- на узком окне оставляем только значки
        end
        UI.SearchWidth = inner
        for _, child in ipairs(SearchPanel:GetChildren()) do
            if child:IsA("GuiObject") then
                child.Size = UDim2.fromOffset(inner, child.Size.Y.Offset)
            end
        end
    end
    UI.LayoutPages = LayoutPages
    Track(Main:GetPropertyChangedSignal("Size"):Connect(LayoutPages))

    local function AddTab(def)
        local tab = setmetatable({ key = def.key, def = def, Pages = {}, Subs = def.subs, Active = false }, TabMethods)

        local button = New("TextButton", {
            Size = UDim2.new(0, 0, 0, 36), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
            BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = #UI.Tabs + 1,
        }, TabsRow)
        Theme.bind(button, "BackgroundColor3", "Surface2")
        Corner(button, 8)
        local stroke = Stroke(button, "Line", 1, 1)
        New("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14) }, button)
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
            VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
        }, button)
        local icon = Icon(button, def.icon, 18, "Muted")
        icon.LayoutOrder = 1
        local label = NewText("TextLabel", {
            Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = "", LayoutOrder = 2,
        }, button, 14, W.Medium, "Muted")
        Loc(label, "Text", def.name)

        tab.Button, tab.Icon, tab.Label, tab.Stroke = button, icon, label, stroke
        table.insert(UI.Tabs, tab)

        if def.subs then
            tab.DefaultSub = def.subs[1].key
            tab.Sub = tab.DefaultSub
            tab.SubPills = {}
            tab.SubRow = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, SubRowHolder)
            New("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
                SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
            }, tab.SubRow)
            for index, sub in ipairs(def.subs) do
                tab.Pages[sub.key] = CreatePage(PagesHolder)
                local pill = New("TextButton", {
                    Size = UDim2.new(0, 0, 0, 28), AutomaticSize = Enum.AutomaticSize.X, BorderSizePixel = 0,
                    BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = index,
                }, tab.SubRow)
                New("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, pill)
                local pillLabel = NewText("TextLabel", {
                    Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = "",
                }, pill, 13, W.Medium, "Muted")
                Loc(pillLabel, "Text", sub.name)
                local bar = New("Frame", {
                    Size = UDim2.new(1, -24, 0, 2), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
                    BorderSizePixel = 0, Visible = false,
                }, pill)
                Theme.bind(bar, "BackgroundColor3", "Accent")
                Pill(bar)
                tab.SubPills[sub.key] = { Button = pill, Label = pillLabel, Bar = bar }
                Track(pill.MouseButton1Click:Connect(function() SelectTab(tab, sub.key) end))
            end
        else
            tab.DefaultSub = "main"
            tab.Sub = "main"
            tab.Pages.main = CreatePage(PagesHolder)
        end

        Track(button.MouseEnter:Connect(function()
            if not tab.Active then Tw(button, { BackgroundTransparency = 0.6 }, 0.12) end
        end))
        Track(button.MouseLeave:Connect(function()
            if not tab.Active then Tw(button, { BackgroundTransparency = 1 }, 0.12) end
        end))
        Track(button.MouseButton1Click:Connect(function() SelectTab(tab) end))
        StyleTab(tab)
        return tab
    end

    -- Группа в рамке: заголовок "вырезает" верхнюю границу, как на референсе
    function TabMethods:Section(o)
        local subKey = o.Sub or self.DefaultSub
        local page = self.Pages[subKey]
        page.Order += 1
        local col = math.clamp(o.Col or 1, 1, 3)

        local card = New("Frame", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0,
            LayoutOrder = page.Order,
        }, page.Cols[col])
        Theme.bind(card, "BackgroundColor3", "Surface")
        Corner(card, 6)
        Stroke(card, "Line", 1, 0)

        local title = NewText("TextLabel", {
            Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.fromOffset(14, 0), Text = "", BackgroundTransparency = 0, ZIndex = 3,
        }, card, 14, W.Bold)
        Theme.bind(title, "BackgroundColor3", "Background")
        New("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, title)
        Loc(title, "Text", o.Title)

        local body = New("Frame", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        }, card)
        New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, body)
        New("UIPadding", {
            PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 10),
            PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
        }, body)

        local section = setmetatable({
            Tab = self, Sub = subKey, Body = body, Card = card, Title = o.Title, Col = col, Order = page.Order, Rows = 0,
        }, SectionMethods)
        table.insert(page.Sections, section)
        return section
    end

    -- ==========================================================
    -- 5.11 Виджеты
    -- ==========================================================
    local function Flash(row)
        row.BackgroundTransparency = 0.75
        Tw(row, { BackgroundTransparency = 1 }, 0.9)
    end

    local function NewRow(section, height, o)
        section.Rows += 1
        local row = New("Frame", {
            Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, BorderSizePixel = 0,
            LayoutOrder = section.Rows,
        }, section.Body)
        Theme.bind(row, "BackgroundColor3", "Accent")
        Corner(row, 6)
        if o and o.Text and not section.Popup then
            table.insert(UI.Rows, { Row = row, Section = section, Tab = section.Tab, Sub = section.Sub, Key = o.Text })
        end
        if o and o.Tip then AttachTip(row, o.Tip) end
        return row
    end

    local function RowLabel(row, key, reserve)
        local label = NewText("TextLabel", {
            Size = UDim2.new(1, -reserve, 1, 0), Text = "", TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true,
        }, row, 13, W.Medium)
        Loc(label, "Text", key)
        return label
    end

    local function Register(control)
        table.insert(UI.Controls, control)
        return control
    end

    local function HoverIcon(button, icon)
        Track(button.MouseEnter:Connect(function() Theme.bind(icon, "ImageColor3", "Text") end))
        Track(button.MouseLeave:Connect(function() Theme.bind(icon, "ImageColor3", "Muted") end))
    end

    -- Всплывающее окно с автоматической высотой (шестерёнка у переключателей)
    local function OpenAutoPopup(anchor, width)
        ClosePopup()
        PopupLayer.Visible = true
        local scale = UiScale.Scale
        local frame = New("Frame", {
            Size = UDim2.new(0, width, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0,
            Active = true, ZIndex = 41,
        }, PopupLayer)
        Theme.bind(frame, "BackgroundColor3", "Elevated")
        Corner(frame, 8)
        Stroke(frame, "Line", 1, 0)
        New("UIScale", { Scale = scale }, frame)
        New("UIPadding", {
            PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
        }, frame)
        local body = New("Frame", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        }, frame)
        New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, body)

        local abs, size, view = anchor.AbsolutePosition, anchor.AbsoluteSize, ScreenGui.AbsoluteSize
        local x = math.clamp(abs.X + size.X - width * scale, 6, math.max(6, view.X - width * scale - 6))
        local y = abs.Y + size.Y + 6
        frame.Position = UDim2.fromOffset(x / scale, y / scale)
        ActivePopup = { Frame = frame, Conns = {}, Owner = anchor }
        TrackSink = ActivePopup.Conns
        task.defer(function()
            task.wait()
            if frame.Parent then
                local height = frame.AbsoluteSize.Y
                if y + height > view.Y - 6 then
                    frame.Position = UDim2.fromOffset(x / scale, math.max(6, abs.Y - height - 6) / scale)
                end
            end
        end)
        return body
    end

    local function OpenGear(anchor, build, width)
        if ActivePopup then ClosePopup(); return end
        HideTip()
        local body = OpenAutoPopup(anchor, width or 260)
        local popupSection = setmetatable({ Body = body, Popup = true, Rows = 0 }, SectionMethods)
        build(popupSection)
    end

    function SectionMethods:Toggle(o)
        local get, set = Bind(o)
        local row = NewRow(self, 32, o)
        RowLabel(row, o.Text, o.Gear and 64 or 36)

        local rightOffset = 0
        local overlay = New("TextButton", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 2,
        }, row)

        if o.Gear then
            local gear = New("TextButton", {
                Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
                BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 4,
            }, row)
            local gearIcon = Icon(gear, "settings", 16, "Muted")
            gearIcon.AnchorPoint = Vector2.new(0.5, 0.5)
            gearIcon.Position = UDim2.fromScale(0.5, 0.5)
            HoverIcon(gear, gearIcon)
            Track(gear.MouseButton1Click:Connect(function() OpenGear(gear, o.Gear, o.GearWidth) end))
            rightOffset = 30
        end

        local box = New("Frame", {
            Size = UDim2.fromOffset(20, 20), AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -rightOffset, 0.5, 0), BorderSizePixel = 0, ZIndex = 3,
        }, row)
        Theme.bind(box, "BackgroundColor3", "Surface2")
        Corner(box, 4)
        local boxStroke = Stroke(box, "Line", 1, 0.2)
        local check = Icon(box, "check-bold", 14, "Text")
        check.AnchorPoint = Vector2.new(0.5, 0.5)
        check.Position = UDim2.fromScale(0.5, 0.5)

        local function render()
            local on = get() == true
            check.Visible = on
            Theme.bind(boxStroke, "Color", on and "Accent" or "Line")
        end
        render()

        Track(overlay.MouseButton1Click:Connect(function()
            local value = not (get() == true)
            set(value)
            render()
            if o.Callback then o.Callback(value) end
        end))
        return Register({ Row = row, Sync = render })
    end

    function SectionMethods:Slider(o)
        local get, set = Bind(o)
        local min, max, decimals = o.Min or 0, o.Max or 1, o.Decimals or 0
        local row = NewRow(self, 46, o)
        local label = NewText("TextLabel", {
            Size = UDim2.new(1, -80, 0, 22), Position = UDim2.fromOffset(0, 2), Text = "",
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row, 13, W.Medium)
        Loc(label, "Text", o.Text)
        local valueLabel = NewText("TextLabel", {
            Size = UDim2.fromOffset(80, 22), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2),
            Text = "", TextXAlignment = Enum.TextXAlignment.Right,
        }, row, 12, W.Bold, "Accent")

        local hit = New("TextButton", {
            Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 24), BackgroundTransparency = 1,
            Text = "", AutoButtonColor = false,
        }, row)
        local track = New("Frame", {
            Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 0.5, -2), BorderSizePixel = 0,
        }, hit)
        Theme.bind(track, "BackgroundColor3", "Elevated")
        Pill(track)
        local fill = New("Frame", { Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 }, track)
        Theme.bind(fill, "BackgroundColor3", "Accent")
        Pill(fill)
        local knob = New("Frame", {
            Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
            BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
        }, track)
        Pill(knob)

        local function format(value)
            return ("%." .. decimals .. "f"):format(value) .. (o.Suffix or "")
        end
        local function render()
            local value = math.clamp(tonumber(get()) or min, min, max)
            local rel = (value - min) / math.max(max - min, 1e-9)
            fill.Size = UDim2.new(rel, 0, 1, 0)
            knob.Position = UDim2.new(rel, 0, 0.5, 0)
            valueLabel.Text = format(value)
        end
        render()

        -- Кнопка сброса к значению по умолчанию (появляется, если задан o.Default)
        if o.Default ~= nil then
            label.Size = UDim2.new(1, -118, 0, 22)
            valueLabel.Size = UDim2.fromOffset(60, 22)
            valueLabel.Position = UDim2.new(1, -24, 0, 2)
            local reset = New("TextButton", {
                Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4),
                BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
            }, row)
            local resetIcon = Icon(reset, "rotate-ccw", 13, "Muted")
            resetIcon.AnchorPoint = Vector2.new(0.5, 0.5)
            resetIcon.Position = UDim2.fromScale(0.5, 0.5)
            Track(reset.MouseEnter:Connect(function() Theme.bind(resetIcon, "ImageColor3", "Accent") end))
            Track(reset.MouseLeave:Connect(function() Theme.bind(resetIcon, "ImageColor3", "Muted") end))
            Track(reset.MouseButton1Click:Connect(function()
                set(o.Default)
                render()
                if o.Callback then o.Callback(o.Default) end
                if o.Released then o.Released(o.Default) end
            end))
            AttachTip(reset, L("Reset to default", "Сбросить к значению по умолчанию"))
        end

        local dragging = false
        local function update(x)
            local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
            local value = min + rel * (max - min)
            local step = 10 ^ decimals
            value = math.clamp(math.floor(value * step + 0.5) / step, min, max)
            if value ~= get() then
                set(value)
                render()
                if o.Callback then o.Callback(value) end
            end
        end
        Track(hit.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                update(input.Position.X)
            end
        end))
        Track(UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                update(input.Position.X)
            end
        end))
        Track(UserInputService.InputEnded:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch) then
                dragging = false
                SaveSoon()
                if o.Released then o.Released(get()) end
            end
        end))
        return Register({ Row = row, Sync = render })
    end

    local function NormalizeOptions(list)
        local result = {}
        for _, option in ipairs(list or {}) do
            if type(option) == "table" then
                table.insert(result, { value = option.value, text = option.text or tostring(option.value) })
            else
                table.insert(result, { value = option, text = tostring(option) })
            end
        end
        return result
    end

    -- Кнопка-список (серый прямоугольник справа от подписи)
    function SectionMethods:Dropdown(o)
        local get, set = Bind(o)
        local row = NewRow(self, 36, o)
        RowLabel(row, o.Text, 160)
        local button = New("TextButton", {
            Size = UDim2.fromOffset(150, 26), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
            BorderSizePixel = 0, Text = "", AutoButtonColor = false,
        }, row)
        Theme.bind(button, "BackgroundColor3", "Surface2")
        Corner(button, 5)
        Stroke(button, "Line", 1, 0.5)
        local valueLabel = NewText("TextLabel", {
            Size = UDim2.new(1, -30, 1, 0), Position = UDim2.fromOffset(10, 0), Text = "",
            TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        }, button, 12, W.Medium, "Muted")
        local chevron = Icon(button, "chevron-down", 14, "Text")
        chevron.AnchorPoint = Vector2.new(1, 0.5)
        chevron.Position = UDim2.new(1, -8, 0.5, 0)

        local function options()
            return NormalizeOptions(type(o.Options) == "function" and o.Options() or o.Options)
        end
        local function render()
            local current, text = get(), nil
            for _, option in ipairs(options()) do
                if option.value == current then text = T(option.text); break end
            end
            valueLabel.Text = text or "-"
        end
        render()

        Track(button.MouseButton1Click:Connect(function()
            -- повторный клик по кнопке закрывает только СВОЙ список;
            -- клик по дропдауну внутри открытого попапа открывает список
            -- поверх попапа (раньше это закрывало весь попап — баг)
            if ActiveList and ActiveList.Owner == button then CloseList(); return end
            if ActivePopup and ActivePopup.Owner == button then ClosePopup(); return end
            HideTip()
            local list = options()
            local height = math.min(#list * 30 + 10, 236)
            local frame = OpenPopup(button, math.max(button.AbsoluteSize.X / UiScale.Scale, 150), height)
            local scroll = New("ScrollingFrame", {
                Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), BackgroundTransparency = 1,
                BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
            }, frame)
            Theme.bind(scroll, "ScrollBarImageColor3", "Accent")
            New("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
            local current = get()
            for index, option in ipairs(list) do
                local item = New("TextButton", {
                    Size = UDim2.new(1, 0, 0, 28), BorderSizePixel = 0, Text = "", AutoButtonColor = false,
                    LayoutOrder = index, BackgroundTransparency = option.value == current and 0 or 1,
                }, scroll)
                Theme.bind(item, "BackgroundColor3", "Surface2")
                Corner(item, 5)
                NewText("TextLabel", {
                    Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), Text = T(option.text),
                    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
                }, item, 12, W.Medium, option.value == current and "Accent" or "Text")
                Track(item.MouseEnter:Connect(function()
                    if option.value ~= current then Tw(item, { BackgroundTransparency = 0.5 }, 0.1) end
                end))
                Track(item.MouseLeave:Connect(function()
                    if option.value ~= current then Tw(item, { BackgroundTransparency = 1 }, 0.1) end
                end))
                Track(item.MouseButton1Click:Connect(function()
                    set(option.value)
                    render()
                    -- закрываем только список, не задевая попап шестерёнки под ним
                    if ActiveList then CloseList() else ClosePopup() end
                    if o.Callback then o.Callback(option.value) end
                end))
            end
        end))
        return Register({ Row = row, Sync = render })
    end

    function SectionMethods:Colorpicker(o)
        local row = NewRow(self, 34, o)
        RowLabel(row, o.Text, 60)
        local swatch = New("TextButton", {
            Size = UDim2.fromOffset(40, 20), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
            BorderSizePixel = 0, Text = "", AutoButtonColor = false,
        }, row)
        Corner(swatch, 4)
        Stroke(swatch, "Line", 1, 0.2)
        local function render() swatch.BackgroundColor3 = o.Get() end
        render()

        Track(swatch.MouseButton1Click:Connect(function()
            if ActiveList and ActiveList.Owner == swatch then CloseList(); return end
            if ActivePopup and ActivePopup.Owner == swatch then ClosePopup(); return end
            HideTip()
            local frame, popup = OpenPopup(swatch, 236, 222)
            local h, s, v = o.Get():ToHSV()

            local box = New("Frame", {
                Size = UDim2.fromOffset(216, 128), Position = UDim2.fromOffset(10, 10), BorderSizePixel = 0,
                BackgroundColor3 = Color3.fromHSV(h, 1, 1),
            }, frame)
            Corner(box, 6)
            local white = New("Frame", {
                Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
            }, box)
            Corner(white, 6)
            New("UIGradient", { Transparency = NumberSequence.new(0, 1) }, white)
            local black = New("Frame", {
                Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0,
            }, box)
            Corner(black, 6)
            New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }, black)
            local boxCursor = New("Frame", {
                Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
                BorderSizePixel = 0, ZIndex = 3,
            }, box)
            Pill(boxCursor)
            New("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }, boxCursor)

            local hueBar = New("Frame", {
                Size = UDim2.fromOffset(216, 14), Position = UDim2.fromOffset(10, 148), BorderSizePixel = 0,
                BackgroundColor3 = Color3.new(1, 1, 1),
            }, frame)
            Pill(hueBar)
            local keys = {}
            for index = 0, 6 do
                table.insert(keys, ColorSequenceKeypoint.new(index / 6, Color3.fromHSV(math.min(index / 6, 0.999), 1, 1)))
            end
            New("UIGradient", { Color = ColorSequence.new(keys) }, hueBar)
            local hueCursor = New("Frame", {
                Size = UDim2.fromOffset(6, 20), AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0,
                BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3,
            }, hueBar)
            Corner(hueCursor, 3)
            New("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0.5 }, hueCursor)

            local hexBox = NewText("TextBox", {
                Size = UDim2.fromOffset(216, 30), Position = UDim2.fromOffset(10, 178), Text = "",
                BackgroundTransparency = 0, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Center,
            }, frame, 13, W.Medium)
            Theme.bind(hexBox, "BackgroundColor3", "Surface2")
            Corner(hexBox, 6)

            local function place()
                boxCursor.Position = UDim2.fromScale(s, 1 - v)
                hueCursor.Position = UDim2.fromScale(h, 0.5)
                box.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
            end
            local function apply()
                local color = Color3.fromHSV(h, s, v)
                o.Set(color)
                render()
                hexBox.Text = "#" .. color:ToHex()
                place()
            end
            hexBox.Text = "#" .. o.Get():ToHex()
            place()

            local dragging = nil
            local function updateBox(position)
                s = math.clamp((position.X - box.AbsolutePosition.X) / math.max(box.AbsoluteSize.X, 1), 0, 1)
                v = 1 - math.clamp((position.Y - box.AbsolutePosition.Y) / math.max(box.AbsoluteSize.Y, 1), 0, 1)
                apply()
            end
            local function updateHue(position)
                h = math.clamp((position.X - hueBar.AbsolutePosition.X) / math.max(hueBar.AbsoluteSize.X, 1), 0, 0.999)
                apply()
            end
            Track(box.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = "box"
                    updateBox(input.Position)
                end
            end))
            Track(hueBar.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = "hue"
                    updateHue(input.Position)
                end
            end))
            table.insert(popup.Conns, UserInputService.InputChanged:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch) then
                    if dragging == "box" then updateBox(input.Position) else updateHue(input.Position) end
                end
            end))
            table.insert(popup.Conns, UserInputService.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = nil
                end
            end))
            Track(hexBox.FocusLost:Connect(function()
                local ok, color = pcall(Color3.fromHex, (hexBox.Text:gsub("#", "")))
                if ok and color then
                    h, s, v = color:ToHSV()
                    apply()
                else
                    hexBox.Text = "#" .. Color3.fromHSV(h, s, v):ToHex()
                end
            end))
        end))
        return Register({ Row = row, Sync = render })
    end

    function SectionMethods:Keybind(o)
        local get, set = Bind(o)
        local row = NewRow(self, 36, o)
        RowLabel(row, o.Text, 110)
        local button = New("TextButton", {
            Size = UDim2.fromOffset(96, 26), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
            BorderSizePixel = 0, Text = "", AutoButtonColor = false,
        }, row)
        Theme.bind(button, "BackgroundColor3", "Surface2")
        Corner(button, 5)
        Stroke(button, "Line", 1, 0.5)
        local keyLabel = NewText("TextLabel", {
            Size = UDim2.fromScale(1, 1), Text = "", TextXAlignment = Enum.TextXAlignment.Center,
        }, button, 12, W.Bold, "Accent")
        local function render() keyLabel.Text = KeyShortName(tostring(get())) end
        render()

        Track(button.MouseButton1Click:Connect(function()
            if UI.Capturing then return end
            UI.Capturing = true
            _G.YozoraHub_Capturing = true
            keyLabel.Text = "..."
            local connection
            local function finish()
                if connection then connection:Disconnect() end
                task.defer(function()
                    UI.Capturing = false
                    _G.YozoraHub_Capturing = false
                end)
                render()
            end
            connection = UserInputService.InputBegan:Connect(function(input)
                if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
                if input.KeyCode ~= Enum.KeyCode.Escape and input.KeyCode ~= Enum.KeyCode.Unknown then
                    set(input.KeyCode.Name)
                    if o.Callback then o.Callback(input.KeyCode) end
                end
                finish()
            end)
            task.delay(8, function()
                if UI.Capturing and connection and connection.Connected then finish() end
            end)
        end))
        return Register({ Row = row, Sync = render })
    end

    -- Кнопка: с подписью слева (серый прямоугольник справа) или на всю ширину
    function SectionMethods:Button(o)
        local labelled = o.RowLabel ~= nil
        local row = NewRow(self, labelled and 36 or 34, o.RowLabel and { Text = o.RowLabel, Tip = o.Tip } or o)
        if labelled then RowLabel(row, o.RowLabel, 160) end
        local button = New("TextButton", {
            Size = labelled and UDim2.fromOffset(150, 26) or UDim2.new(1, 0, 0, 28),
            AnchorPoint = labelled and Vector2.new(1, 0.5) or Vector2.new(0.5, 0.5),
            Position = labelled and UDim2.new(1, 0, 0.5, 0) or UDim2.fromScale(0.5, 0.5),
            BorderSizePixel = 0, Text = "", AutoButtonColor = false,
        }, row)
        local accent, danger = o.Style == "Accent", o.Style == "Danger"
        Theme.bind(button, "BackgroundColor3", accent and "Accent" or (danger and "Danger" or "Surface2"))
        Corner(button, 5)
        Stroke(button, "Line", 1, (accent or danger) and 1 or 0.5)
        local inner = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, button)
        New("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8),
        }, inner)
        local textRole = (accent or danger) and "OnAccent" or "Muted"
        if o.Icon then Icon(inner, o.Icon, 14, textRole) end
        local label = NewText("TextLabel", {
            Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Text = "",
        }, inner, 13, W.Semi, textRole)
        Loc(label, "Text", o.Text)

        local armed = false
        Track(button.MouseEnter:Connect(function() Tw(button, { BackgroundTransparency = 0.25 }, 0.1) end))
        Track(button.MouseLeave:Connect(function() Tw(button, { BackgroundTransparency = 0 }, 0.1) end))
        Track(button.MouseButton1Click:Connect(function()
            if o.DoubleClick and not armed then
                armed = true
                label.Text = T(L("Click again to confirm", "Нажми ещё раз для подтверждения"))
                task.delay(2.5, function()
                    if armed then
                        armed = false
                        label.Text = T(o.Text)
                    end
                end)
                return
            end
            armed = false
            label.Text = T(o.Text)
            if o.Callback then o.Callback() end
        end))
        return Register({ Row = row, Sync = function() label.Text = T(o.Text) end })
    end

    function SectionMethods:Paragraph(o)
        self.Rows += 1
        local label = NewText("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = "", TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = self.Rows,
        }, self.Body, 12, W.Regular, "Muted")
        New("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, label)
        Loc(label, "Text", o.Text)
        return label
    end

    function SectionMethods:Divider()
        self.Rows += 1
        local holder = New("Frame", { Size = UDim2.new(1, 0, 0, 9), BackgroundTransparency = 1, LayoutOrder = self.Rows }, self.Body)
        local line = New("Frame", {
            Size = UDim2.new(1, 0, 0, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            BorderSizePixel = 0,
        }, holder)
        Theme.bind(line, "BackgroundColor3", "Line")
    end

    -- Строка "Название: значение" (значение обновляется раз в полсекунды)
    function SectionMethods:Value(o)
        local row = NewRow(self, 28, o)
        local label = NewText("TextLabel", {
            Size = UDim2.fromScale(1, 1), Text = "", TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row, 13, W.Medium, "Muted")
        local function update()
            label.Text = T(o.Text) .. ": " .. tostring(o.Get())
        end
        update()
        table.insert(UI.Values, update)
        return Register({ Row = row, Sync = update })
    end

    function SectionMethods:Input(o)
        local row = NewRow(self, 36, o)
        RowLabel(row, o.Text, 160)
        local box = NewText("TextBox", {
            Size = UDim2.fromOffset(150, 26), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
            Text = "", PlaceholderText = o.Placeholder and T(o.Placeholder) or "", ClearTextOnFocus = false,
            BackgroundTransparency = 0, TextXAlignment = Enum.TextXAlignment.Left,
        }, row, 12, W.Medium)
        Theme.bind(box, "BackgroundColor3", "Surface2")
        Theme.bind(box, "PlaceholderColor3", "Faint")
        Corner(box, 5)
        Stroke(box, "Line", 1, 0.5)
        New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, box)
        Track(box.FocusLost:Connect(function()
            if o.Callback then o.Callback(box.Text) end
        end))
        return Register({
            Row = row, Box = box,
            Sync = function() if o.Placeholder then box.PlaceholderText = T(o.Placeholder) end end,
        })
    end

    -- ==========================================================
    -- 5.12 Поиск (кнопка внизу слева)
    -- ==========================================================
    local function Jump(entry)
        SelectTab(entry.Tab, entry.Sub)
        task.defer(function()
            task.wait(0.06)
            local page = entry.Tab.Pages[entry.Sub]
            if page and entry.Row.Parent then
                local offset = (entry.Row.AbsolutePosition.Y - page.Scroll.AbsolutePosition.Y) / UiScale.Scale
                page.Scroll.CanvasPosition = Vector2.new(0, math.max(0, page.Scroll.CanvasPosition.Y + offset - 40))
                Flash(entry.Row)
            end
        end)
    end

    local function BuildResults(query)
        for _, child in ipairs(SearchPanel:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        local shown = 0
        for _, entry in ipairs(UI.Rows) do
            local title = T(entry.Key)
            local sectionTitle = T(entry.Section.Title)
            if title:lower():find(query, 1, true) or sectionTitle:lower():find(query, 1, true) then
                shown += 1
                if shown > 40 then break end
                local result = New("TextButton", {
                    Size = UDim2.fromOffset(UI.SearchWidth or 700, 48), BorderSizePixel = 0, Text = "",
                    AutoButtonColor = false, LayoutOrder = shown,
                }, SearchPanel)
                Theme.bind(result, "BackgroundColor3", "Surface")
                Corner(result, 6)
                Stroke(result, "Line", 1, 0)
                local icon = Icon(result, entry.Tab.def.icon, 18, "Accent")
                icon.AnchorPoint = Vector2.new(0, 0.5)
                icon.Position = UDim2.new(0, 14, 0.5, 0)
                NewText("TextLabel", {
                    Size = UDim2.new(1, -60, 0, 20), Position = UDim2.fromOffset(44, 6), Text = title,
                    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
                }, result, 13, W.Semi)
                local crumb = T(entry.Tab.def.name)
                if entry.Tab.Subs then
                    for _, sub in ipairs(entry.Tab.Subs) do
                        if sub.key == entry.Sub then crumb = crumb .. "  >  " .. T(sub.name) end
                    end
                end
                NewText("TextLabel", {
                    Size = UDim2.new(1, -60, 0, 16), Position = UDim2.fromOffset(44, 26),
                    Text = crumb .. "  >  " .. sectionTitle, TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                }, result, 11, W.Regular, "Muted")
                Track(result.MouseButton1Click:Connect(function() Jump(entry) end))
            end
        end
        if shown == 0 then
            NewText("TextLabel", {
                Size = UDim2.fromOffset(UI.SearchWidth or 700, 50), Text = T(L("Nothing found", "Ничего не найдено")),
                LayoutOrder = 1,
            }, SearchPanel, 13, W.Medium, "Muted")
        end
    end

    Track(SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local query = (SearchBox.Text:lower():gsub("^%s*(.-)%s*$", "%1"))
        if query == "" then
            ShowSearch(false)
            SubRowHolder.Visible = CurrentTab ~= nil and CurrentTab.Subs ~= nil
            return
        end
        SubRowHolder.Visible = false
        BuildResults(query)
        ShowSearch(true)
    end))

    Track(SearchButton.MouseButton1Click:Connect(function()
        SearchBox.Visible = not SearchBox.Visible
        if SearchBox.Visible then
            SearchBox:CaptureFocus()
        else
            SearchBox.Text = ""
            if CurrentTab then SubRowHolder.Visible = CurrentTab.Subs ~= nil end
        end
    end))


    -- ==========================================================
    -- 5.13 HUD: ватермарк, список функций, графики, лог игры, прицел
    -- ==========================================================
    local HudGui = New("ScreenGui", {
        Name = "YozoraHub_HUD", ResetOnSpawn = false, IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 45,
    }, PlayerGui)

    local HUD_SAMPLES = 40
    local Metrics = { fps = {}, ping = {}, speed = {} }
    local LogBuffer = {}
    local HudPlacers = {}

    -- Перетаскиваемая панель (двигать можно, пока меню открыто)
    local function NewPanel(width, keyX, keyY, defaultPosition)
        local panel = New("Frame", {
            Size = width and UDim2.fromOffset(width, 0) or UDim2.fromOffset(0, 0),
            AutomaticSize = width and Enum.AutomaticSize.Y or Enum.AutomaticSize.XY,
            BorderSizePixel = 0, Visible = false, Active = false,
        }, HudGui)
        Theme.bind(panel, "BackgroundColor3", "Sidebar")
        panel.BackgroundTransparency = 0.12
        Corner(panel, 6)
        Stroke(panel, "Line", 1, 0.1)
        New("UIPadding", {
            PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9),
            PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
        }, panel)
        table.insert(UI.HudPanels, panel)

        local function place()
            local x, y = Pref(keyX), Pref(keyY)
            if x < 0 or y < 0 then x, y = defaultPosition(ViewportSize()) end
            panel.Position = UDim2.fromOffset(x, y)
        end
        place()
        table.insert(HudPlacers, place)

        local dragging, startMouse, startPos = false, nil, nil
        Track(panel.InputBegan:Connect(function(input)
            if not isOpen then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging, startMouse, startPos = true, input.Position, panel.Position
            end
        end))
        Track(UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - startMouse
                panel.Position = UDim2.fromOffset(startPos.X.Offset + delta.X, startPos.Y.Offset + delta.Y)
            end
        end))
        Track(UserInputService.InputEnded:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch) then
                dragging = false
                SetPref(keyX, panel.Position.X.Offset)
                SetPref(keyY, panel.Position.Y.Offset)
            end
        end))
        return panel
    end

    -- Ватермарк
    local Watermark = NewPanel(nil, "wmX", "wmY", function() return 14, 14 end)
    local WatermarkLabel = NewText("TextLabel", {
        Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Text = "", RichText = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, Watermark, 12, W.Semi)

    -- Графики FPS / пинга / скорости (одна панель, внутри три блока)
    local GraphsPanel = NewPanel(168, "gfX", "gfY", function(view) return 14, math.floor(view.Y * 0.35) end)
    New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, GraphsPanel)
    local Graphs = {}
    local function NewGraph(key, order, title, source, prefKey, minScale, suffix)
        local block = New("Frame", {
            Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, LayoutOrder = order, Visible = false,
        }, GraphsPanel)
        local label = NewText("TextLabel", {
            Size = UDim2.new(1, 0, 0, 14), Text = "", RichText = true, TextXAlignment = Enum.TextXAlignment.Left,
        }, block, 11, W.Medium, "Muted")
        local plot = New("Frame", {
            Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 17), BackgroundTransparency = 1,
        }, block)
        local bars = {}
        for index = 1, HUD_SAMPLES do
            local bar = New("Frame", {
                Size = UDim2.fromOffset(3, 1), AnchorPoint = Vector2.new(0, 1),
                Position = UDim2.fromOffset((index - 1) * 4, 28), BorderSizePixel = 0,
            }, plot)
            Theme.bind(bar, "BackgroundColor3", "Accent")
            bars[index] = bar
        end
        Graphs[key] = { block = block, label = label, bars = bars, source = source, pref = prefKey,
            title = title, minScale = minScale, suffix = suffix }
    end
    NewGraph("fps", 1, L("FPS", "FPS"), Metrics.fps, "fpsGraph", 60, "")
    NewGraph("ping", 2, L("Ping", "Пинг"), Metrics.ping, "pingGraph", 100, " ms")
    NewGraph("speed", 3, L("Speed", "Скорость"), Metrics.speed, "speedGraph", 24, " st/s")

    -- Список функций ("Keybinds")
    local KeybindsPanel = NewPanel(180, "kbX", "kbY", function(view) return view.X - 194, 14 end)
    New("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, KeybindsPanel)
    local KeybindsTitle = NewText("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16), Text = "", TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0,
    }, KeybindsPanel, 12, W.Bold, "Accent")
    Loc(KeybindsTitle, "Text", L("Keybinds", "Клавиши"))
    local KeybindLines = {}
    -- 1 строка (Меню) + все пункты ACTIVE_FEATURES (18)
    for index = 1, 19 do
        KeybindLines[index] = NewText("TextLabel", {
            Size = UDim2.new(1, 0, 0, 14), Text = "", RichText = true, TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = index, Visible = false,
        }, KeybindsPanel, 11, W.Medium)
    end
    local ACTIVE_FEATURES = {
        { L("Auto farm", "Автофарм"), function() return Settings.AutoFarm end },
        { "ESP", function() return Settings.ESP end },
        { "Anti-Fling", function() return Settings.AntiFling end },
        { "Anti-AFK", function() return Settings.AntiAFK end },
        { L("Avoid murderer", "Избегать убийцу"), function() return Settings.AvoidMurderer end },
        { L("Pick up gun (farm)", "Подбор пистолета (фарм)"), function() return Settings.PickGun end },
        { L("Respawn when full", "Респавн при полном"), function() return Settings.AutoRespawnFull end },
        { L("Kill all when full", "Убить всех при полном"), function() return Settings.KillAllFull end },
        { L("Shoot when full", "Выстрел при полном"), function() return Settings.ShootMurdererFull end },
        { L("Auto rejoin", "Авто-перезаход"), function() return Settings.AutoRejoin end },
        { L("Silent aim", "Сайлент аим"), function() return CombatOpt("silentAim") end },
        { L("Auto shoot", "Авто-выстрел"), function() return CombatOpt("autoShoot") end },
        { L("Knife aim", "Аим ножа"), function() return CombatOpt("knifeAim") end },
        { L("Auto throw", "Авто-бросок"), function() return CombatOpt("autoThrow") end },
        { L("Pick up gun (combat)", "Подбор пистолета (бой)"), function() return CombatOpt("pickGun") end },
        { L("World changes", "Изменения мира"), function() return VisOpt("worldOn") end },
        { L("Weather", "Погода"), function() return VisOpt("weather") ~= "Off" end },
        { L("Aura", "Аура"), function() return VisOpt("aura") ~= "Off" end },
    }

    -- Лог игры
    local LogPanel = NewPanel(250, "lgX", "lgY", function(view) return 14, view.Y - 190 end)
    New("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, LogPanel)
    local LogTitle = NewText("TextLabel", {
        Size = UDim2.new(1, 0, 0, 16), Text = "", TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0,
    }, LogPanel, 12, W.Bold, "Accent")
    Loc(LogTitle, "Text", L("Game log", "Лог игры"))
    local LogLines = {}
    for index = 1, 12 do
        LogLines[index] = NewText("TextLabel", {
            Size = UDim2.new(1, 0, 0, 14), Text = "", RichText = true, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = index, Visible = false,
        }, LogPanel, 11, W.Regular)
    end

    GameLog = function(text)
        table.insert(LogBuffer, { time = os.date("%H:%M:%S"), text = text })
        if #LogBuffer > 40 then table.remove(LogBuffer, 1) end
        if UI.HudUpdate then UI.HudUpdate() end
    end

    -- Прицел
    local Crosshair = New("Frame", {
        Size = UDim2.fromOffset(0, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        BackgroundTransparency = 1, Visible = false,
    }, HudGui)
    local CrossParts = {}
    for index = 1, 5 do
        local outline = New("Frame", { BorderSizePixel = 0, BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 1 }, Crosshair)
        local bar = New("Frame", { BorderSizePixel = 0, ZIndex = 2 }, Crosshair)
        CrossParts[index] = { bar = bar, outline = outline }
    end

    local function UpdateCrosshair()
        Crosshair.Visible = PrefBool("crosshair")
        if not Crosshair.Visible then return end
        local style = tostring(Pref("chStyle"))
        local size, thick, gap = PrefNum("chSize", 2, 40), PrefNum("chThick", 1, 8), PrefNum("chGap", 0, 30)
        local color = SafeHex(Pref("chColour"), UI_DEFAULTS.chColour)
        local outline = PrefBool("chOutline")
        -- 1 верх, 2 низ, 3 лево, 4 право, 5 точка
        local layout = {
            { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(0, -gap), Size = UDim2.fromOffset(thick, size), on = style == "Cross" },
            { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(0, gap), Size = UDim2.fromOffset(thick, size), on = style == "Cross" or style == "T" },
            { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromOffset(-gap, 0), Size = UDim2.fromOffset(size, thick), on = style == "Cross" or style == "T" },
            { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromOffset(gap, 0), Size = UDim2.fromOffset(size, thick), on = style == "Cross" or style == "T" },
            { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(thick + 1, thick + 1), on = PrefBool("chDot") or style == "Dot" },
        }
        for index, spec in ipairs(layout) do
            local part = CrossParts[index]
            part.bar.AnchorPoint, part.bar.Position, part.bar.Size = spec.AnchorPoint, spec.Position, spec.Size
            part.bar.BackgroundColor3 = color
            part.bar.Visible = spec.on
            part.outline.AnchorPoint = spec.AnchorPoint
            part.outline.Position = spec.Position
            part.outline.Size = UDim2.fromOffset(spec.Size.X.Offset + 2, spec.Size.Y.Offset + 2)
            part.outline.Visible = spec.on and outline
        end
    end

    -- Обновление всех панелей
    local hudTick = 0
    local function UpdateHud()
        local lastFps = Metrics.fps[#Metrics.fps] or 0
        local lastPing = Metrics.ping[#Metrics.ping] or 0
        local accentHex = Theme.tokens.Accent:ToHex()

        Watermark.Visible = PrefBool("watermark")
        if Watermark.Visible then
            local parts = { ('<font color="#%s">Yozora Hub</font>'):format(accentHex) }
            if PrefBool("wmFps") then table.insert(parts, ("%d FPS"):format(math.floor(lastFps + 0.5))) end
            if PrefBool("wmPing") then table.insert(parts, ("%d ms"):format(math.floor(lastPing + 0.5))) end
            if PrefBool("wmTime") then table.insert(parts, os.date("%H:%M:%S")) end
            WatermarkLabel.Text = table.concat(parts, "  |  ")
        end

        local anyGraph = false
        for _, graph in pairs(Graphs) do
            local on = PrefBool(graph.pref)
            graph.block.Visible = on
            if on then
                anyGraph = true
                local peak = graph.minScale
                for _, value in ipairs(graph.source) do peak = math.max(peak, value) end
                local last = graph.source[#graph.source] or 0
                graph.label.Text = ('%s  <font color="#%s">%d%s</font>'):format(T(graph.title), accentHex,
                    math.floor(last + 0.5), graph.suffix)
                local count = #graph.source
                for index, bar in ipairs(graph.bars) do
                    local value = graph.source[count - HUD_SAMPLES + index] or 0
                    bar.Size = UDim2.fromOffset(3, math.max(1, math.floor(value / peak * 28 + 0.5)))
                end
            end
        end
        GraphsPanel.Visible = anyGraph

        KeybindsPanel.Visible = PrefBool("keybinds")
        if KeybindsPanel.Visible then
            local lines = {}
            table.insert(lines, ('%s  <font color="#%s">[%s]</font>'):format(T(L("Menu", "Меню")), accentHex, KeyShortName(MenuKey.Name)))
            for _, feature in ipairs(ACTIVE_FEATURES) do
                local active = feature[2]() == true
                if active or not PrefBool("kbActiveOnly") then
                    table.insert(lines, ('<font color="#%s">%s</font>  %s'):format(
                        active and accentHex or "8e8e93", active and "ON" or "OFF", T(feature[1])))
                end
            end
            for index, line in ipairs(KeybindLines) do
                line.Visible = lines[index] ~= nil
                if lines[index] then line.Text = lines[index] end
            end
        end

        LogPanel.Visible = PrefBool("gameLog")
        if LogPanel.Visible then
            local count = math.clamp(PrefNum("logLines", 3, 12), 3, 12)
            for index, line in ipairs(LogLines) do
                local entry = LogBuffer[#LogBuffer - count + index]
                line.Visible = index <= count and entry ~= nil
                if line.Visible then
                    line.Text = ('<font color="#8e8e93">%s</font>  %s'):format(entry.time, T(entry.text))
                end
            end
        end
    end
    UI.HudUpdate = UpdateHud
    Theme.hooks[#Theme.hooks + 1] = function() UpdateHud() end -- цвет акцента в ватермарке

    function Appearance.hud()
        UpdateCrosshair()
        UpdateHud()
    end

    function Appearance.resetPanels()
        for _, key in ipairs({ "wmX", "wmY", "kbX", "kbY", "gfX", "gfY", "lgX", "lgY", "posX", "posY" }) do
            Settings.UI[key] = nil
        end
        for _, place in ipairs(HudPlacers) do place() end
        Main.Position = UDim2.new(0.5, 0, 0.5, 0)
        SaveSoon()
    end

    -- Сбор метрик (FPS, пинг, скорость) и обновление HUD
    do
        local frames, last = 0, os.clock()
        Track(RunService.Heartbeat:Connect(function() frames += 1 end))
        local function push(list, value)
            table.insert(list, value)
            if #list > HUD_SAMPLES then table.remove(list, 1) end
        end
        task.spawn(function()
            while Alive() and task.wait(0.25) do
                local now = os.clock()
                local fps = frames / math.max(now - last, 0.001)
                frames, last = 0, now
                local ping = 0
                pcall(function() ping = StatsService.Network.ServerStatsItem["Data Ping"]:GetValue() end)
                local speed = 0
                local character = LocalPlayer.Character
                local root = character and character:FindFirstChild("HumanoidRootPart")
                if root then
                    local velocity = root.AssemblyLinearVelocity
                    speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
                end
                push(Metrics.fps, fps)
                push(Metrics.ping, ping)
                push(Metrics.speed, speed)
                hudTick += 1
                if hudTick % 2 == 0 then pcall(UpdateHud) end
            end
        end)
    end


    -- ==========================================================
    -- 5.14 Язык, оформление, профили
    -- ==========================================================
    local function SyncAll()
        for _, control in ipairs(UI.Controls) do
            if control.Sync then pcall(control.Sync) end
        end
    end

    local function ApplyLanguage()
        for index = #Localized, 1, -1 do
            local entry = Localized[index]
            if entry.Obj.Parent then
                entry.Obj[entry.Prop] = entry.Prefix .. T(entry.Key)
            else
                table.remove(Localized, index) -- объект уничтожен
            end
        end
        SearchBox.PlaceholderText = T(L("Search...", "Поиск..."))
        SyncAll()
        for _, update in ipairs(UI.Values) do pcall(update) end
        local query = (SearchBox.Text:lower():gsub("^%s*(.-)%s*$", "%1"))
        if query ~= "" then BuildResults(query) end
        if UI.HudUpdate then UI.HudUpdate() end
    end

    function Appearance.setAccent(color)
        SetPref("accent", color:ToHex())
        Theme.tokens.Accent = color
        Theme.updateOnAccent()
        Theme.refresh()
    end

    local function ResetAppearance()
        Settings.UI = { design = 2, menuKey = Pref("menuKey") }
        SaveSoon()
        LoadMenuKey()
        Appearance.all()
        Appearance.resetPanels()
        SyncAll()
        Notify(L("Appearance reset", "Внешний вид сброшен"), nil, "success")
    end


    -- ---------- Профили настроек (файлы) ----------
    local CONFIG_DIR = "YozoraHub/configs"
    local selectedConfig = nil

    local function FilesSupported()
        -- Проверяем каждую функцию отдельно: false ~= nil даёт true.
        return type(writefile) == "function"
            and type(readfile) == "function"
            and type(listfiles) == "function"
            and type(isfolder) == "function"
            and type(makefolder) == "function"
            and type(delfile) == "function"
    end

    local function EnsureDir()
        pcall(function()
            if not isfolder("YozoraHub") then makefolder("YozoraHub") end
            if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        end)
    end

    local function CleanName(name)
        return (tostring(name):gsub("[^%w%-_ ]", ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end

    local configCache, configCacheAt = nil, 0

    local function ListConfigs()
        -- кэш 2с: Options дропдауна пересобирается на каждом Sync,
        -- а listfiles дёргает ФС каждый раз
        local now = os.clock()
        if configCache and now - configCacheAt < 2 then return configCache end
        local names = {}
        if not FilesSupported() then return names end
        EnsureDir()
        local ok, files = pcall(listfiles, CONFIG_DIR)
        if ok and type(files) == "table" then
            for _, path in ipairs(files) do
                local name = tostring(path):match("([^/\\]+)%.json$")
                if name then table.insert(names, name) end
            end
        end
        table.sort(names)
        configCache, configCacheAt = names, now
        return names
    end

    local function InvalidateConfigCache()
        configCache, configCacheAt = nil, 0
    end

    local configNameBox = nil

    local function SaveProfile(name)
        name = CleanName(name)
        if name == "" then
            Notify(L("Enter a config name", "Введи имя конфига"), nil, "warning")
            return
        end
        EnsureDir()
        local snapshot = Sanitize(Settings)
        snapshot.TotalCoins = nil
        local ok, err = pcall(function()
            writefile(CONFIG_DIR .. "/" .. name .. ".json", HttpService:JSONEncode(snapshot))
        end)
        if ok then
            selectedConfig = name
            InvalidateConfigCache()
        end
        SyncAll()
        if not ok then warn("[Yozora Hub] could not save profile: " .. tostring(err)) end
        Notify(ok and L("Config saved", "Конфиг сохранён") or L("Could not save config", "Не удалось сохранить конфиг"),
            ok and name or tostring(err), ok and "success" or "error")
    end

    local function LoadProfile(name)
        if not name then
            Notify(L("Choose a config first", "Сначала выбери конфиг"), nil, "warning")
            return
        end
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(readfile(CONFIG_DIR .. "/" .. name .. ".json"))
        end)
        if not ok or type(decoded) ~= "table" then
            Notify(L("Could not load config", "Не удалось загрузить конфиг"), name, "error")
            return
        end
        for key, value in pairs(decoded) do
            if key ~= "TotalCoins" and Settings[key] ~= nil and type(value) == type(Settings[key]) then
                Settings[key] = value
            end
        end
        if type(Settings.UI) ~= "table" then Settings.UI = {} end
        if type(Settings.UI.collapsed) ~= "table" then Settings.UI.collapsed = {} end
        if not Lang[Settings.Language] then Settings.Language = "en" end
        FarmSetEnabled(Settings.AutoFarm == true)
        LoadMenuKey()
        Appearance.all()
        ApplyLanguage()
        Visual.changed("weather") -- визуал: применить всё заново, погоду переконфигурировать
        Esp.changed("all")
        SaveSoon()
        Notify(L("Config loaded", "Конфиг загружен"), name, "success")
    end

    local function DeleteProfile(name)
        if not name then
            Notify(L("Choose a config first", "Сначала выбери конфиг"), nil, "warning")
            return
        end
        local ok = pcall(delfile, CONFIG_DIR .. "/" .. name .. ".json")
        if ok then InvalidateConfigCache() end
        if selectedConfig == name then selectedConfig = nil end
        SyncAll()
        Notify(ok and L("Config deleted", "Конфиг удалён") or L("Could not delete config", "Не удалось удалить конфиг"),
            name, ok and "success" or "error")
    end



    -- ==========================================================
    -- 5.15 Вкладки и их содержимое
    -- ==========================================================
    local TeleportServiceUI = game:GetService("TeleportService")

    local TabCombat = AddTab({ key = "combat", name = L("Combat", "Бой"), icon = "crosshair" })
    local TabFarm = AddTab({ key = "farm", name = L("Farm", "Фарм"), icon = "coins" })
    local TabVisuals = AddTab({
        key = "visuals", name = L("Visuals", "Визуал"), icon = "eye",
        subs = {
            { key = "esp", name = L("ESP", "ESP") },
            { key = "boxes", name = L("Boxes", "Рамки") },
            { key = "extras", name = L("Extras", "Дополнительно") },
            { key = "world", name = L("World", "Мир") },
            { key = "sky", name = L("Sky", "Небо") },
            { key = "weather", name = L("Weather", "Погода") },
            { key = "screen", name = L("Screen", "Экран") },
            { key = "effects", name = L("Effects", "Эффекты") },
        },
    })
    local TabMisc = AddTab({
        key = "misc", name = L("Misc", "Прочее"), icon = "settings",
        subs = {
            { key = "general", name = L("General", "Общее") },
            { key = "server", name = L("Server", "Сервер") },
            { key = "interface", name = L("Interface", "Интерфейс") },
            { key = "configs", name = L("Configs", "Конфиги") },
        },
    })
    local TabHud = AddTab({ key = "hud", name = "HUD", icon = "hud" })

    -- Combat
    do
        local combat = TabCombat:Section({ Title = L("Sheriff · Silent Aim", "Шериф · Сайлент Аим"), Col = 1 })
        combat:Paragraph({
            Text = L("Takes over the gun and fires straight at the predicted position of the murderer: no executor hooks needed.",
                "Забирает управление пистолетом и стреляет в предсказанную точку убийцы напрямую: хуки исполнителя не нужны."),
        })
        combat:Toggle({
            Text = L("Silent Aim (gun)", "Сайлент Аим (пистолет)"),
            Get = function() return CombatOpt("silentAim") end,
            Set = function(v) SetCombatOpt("silentAim", v) end,
            Tip = L("When you click, the shot goes straight to the murderer", "Твой клик отправляет выстрел прямо в убийцу"),
            Callback = function(on)
                GameLog(on and L("Silent aim enabled", "Сайлент аим включён") or L("Silent aim disabled", "Сайлент аим выключен"))
            end,
            Gear = function(pop)
                pop:Dropdown({
                    Text = L("Prediction", "Предсказание"),
                    Get = function() return CombatOpt("gunPrediction") end,
                    Set = function(v) SetCombatOpt("gunPrediction", v) end,
                    Options = { "Remi", "Ubuntu", "Electro", "Tiancai", "Revert", "Flux" },
                    Tip = L("Revert/Flux simulate the target's physics (most accurate)",
                        "Revert/Flux симулируют физику цели (самые точные)"),
                })
                pop:Slider({
                    Text = L("Tiancai offset", "Сдвиг Tiancai"),
                    Min = 50, Max = 200,
                    Get = function() return CombatOpt("tiancaiOffset") end,
                    Set = function(v) SetCombatOpt("tiancaiOffset", v) end,
                })
                pop:Toggle({
                    Text = L("Piercer bullet (through walls)", "Piercer (сквозь стены)"),
                    Get = function() return CombatOpt("piercer") end,
                    Set = function(v) SetCombatOpt("piercer", v) end,
                    Tip = L("Shot origin is placed near the target so walls do not block it",
                        "Origin выстрела ставится у самой цели, чтобы стены не мешали"),
                })
                pop:Toggle({
                    Text = L("Auto shoot", "Авто-выстрел"),
                    Get = function() return CombatOpt("autoShoot") end,
                    Set = function(v) SetCombatOpt("autoShoot", v) end,
                    Tip = L("Shoots at the murderer by itself", "Стреляет в убийцу сам"),
                })
                pop:Toggle({
                    Text = L("Auto equip gun", "Авто-экипировка"),
                    Get = function() return CombatOpt("autoEquip") end,
                    Set = function(v) SetCombatOpt("autoEquip", v) end,
                })
                pop:Slider({
                    Text = L("Auto shoot delay", "Задержка авто-выстрела"),
                    Min = 250, Max = 2000, Suffix = " ms",
                    Get = function() return CombatOpt("autoShootDelay") end,
                    Set = function(v) SetCombatOpt("autoShootDelay", v) end,
                })
            end,
        })
        combat:Toggle({
            Text = L("Trigger bot", "Триггер бот"),
            Get = function() return CombatOpt("triggerBot") end,
            Set = function(v) SetCombatOpt("triggerBot", v) end,
            Tip = L("Fires automatically while the murderer is inside your crosshair radius",
                "Стреляет сам, когда убийца в радиусе твоего прицела"),
            Callback = function(on)
                GameLog(on and L("Trigger bot enabled", "Триггер бот включён")
                    or L("Trigger bot disabled", "Триггер бот выключен"))
            end,
            Gear = function(pop)
                pop:Slider({
                    Text = L("Trigger radius", "Радиус триггера"),
                    Min = 10, Max = 200, Suffix = " px",
                    Get = function() return CombatOpt("triggerRadius") end,
                    Set = function(v) SetCombatOpt("triggerRadius", v) end,
                    Tip = L("Distance from the crosshair in pixels", "Расстояние от прицела в пикселях"),
                })
                pop:Toggle({
                    Text = L("Visible target only", "Только видимая цель"),
                    Get = function() return CombatOpt("triggerWall") end,
                    Set = function(v) SetCombatOpt("triggerWall", v) end,
                    Tip = L("Does not shoot through walls", "Не стреляет через стены"),
                })
            end,
        })
        combat:Toggle({
            Text = L("Aimlock (camera)", "Аимлок (камера)"),
            Get = function() return CombatOpt("aimlock") end,
            Set = function(v) SetCombatOpt("aimlock", v) end,
            Tip = L("Camera smoothly follows the murderer", "Камера плавно следит за убийцей"),
            Callback = function(on)
                GameLog(on and L("Aimlock enabled", "Аимлок включён")
                    or L("Aimlock disabled", "Аимлок выключен"))
            end,
        })
        combat:Toggle({
            Text = L("Pick up gun", "Подобрать пистолет"),
            Get = function() return CombatOpt("pickGun") end,
            Set = function(v) SetCombatOpt("pickGun", v) end,
            Tip = L("Innocents grab the dropped gun when the sheriff dies (works without autofarm)",
                "Невиновный подбирает брошенный пистолет, когда шериф погиб (работает без авто-фарма)"),
            Callback = function(on)
                GameLog(on and L("Gun pickup enabled", "Подбор пистолета включён")
                    or L("Gun pickup disabled", "Подбор пистолета выключен"))
            end,
        })
        combat:Button({
            Text = L("Shoot the murderer (teleport)", "Выстрел в убийцу (телепорт)"),
            Callback = function() Combat.shootMurderer() end,
        })
    end

    do
        local knife = TabCombat:Section({ Title = L("Knife · Throw Aim", "Нож · Аим броска"), Col = 2 })
        knife:Paragraph({
            Text = L("Takes over the knife and throws it at the predicted point of your aim: right-click, throw key or button.",
                "Забирает управление ножом и бросает его в предсказанную точку прицела: ПКМ, клавиша броска или кнопка."),
        })
        knife:Toggle({
            Text = L("Knife Aim (throw)", "Аим ножа (бросок)"),
            Get = function() return CombatOpt("knifeAim") end,
            Set = function(v) SetCombatOpt("knifeAim", v) end,
            Tip = L("Takes over the knife: your throw goes straight to the predicted point (RMB / E / throw key)",
                "Забирает управление ножом: твой бросок летит прямо в предсказанную точку (ПКМ / E / клавиша)"),
            Callback = function(on)
                GameLog(on and L("Knife aim enabled", "Аим ножа включён") or L("Knife aim disabled", "Аим ножа выключен"))
            end,
            Gear = function(pop)
                pop:Dropdown({
                    Text = L("Target mode", "Режим цели"),
                    Get = function() return CombatOpt("knifeTarget") end,
                    Set = function(v) SetCombatOpt("knifeTarget", v) end,
                    Options = { "Cursor", "Closest" },
                    Tip = L("Cursor = near the crosshair, Closest = by distance", "Cursor — у прицела, Closest — по дистанции"),
                })
                pop:Toggle({
                    Text = L("Prioritize sheriff on throw", "Приоритет шерифа"),
                    Get = function() return CombatOpt("knifeSheriffFirst") end,
                    Set = function(v) SetCombatOpt("knifeSheriffFirst", v) end,
                })
                pop:Dropdown({
                    Text = L("Prediction", "Предсказание"),
                    Get = function() return CombatOpt("knifePrediction") end,
                    Set = function(v) SetCombatOpt("knifePrediction", v) end,
                    Options = { "Dynamic", "Instant" },
                    Tip = L("Dynamic leads by target speed, Instant throws at the current position",
                        "Dynamic ведёт по скорости цели, Instant бросает в текущую позицию"),
                })
                pop:Slider({
                    Text = L("Max distance", "Макс. дистанция"),
                    Min = 30, Max = 400, Suffix = " st",
                    Get = function() return CombatOpt("knifeMaxDist") end,
                    Set = function(v) SetCombatOpt("knifeMaxDist", v) end,
                })
                pop:Toggle({
                    Text = L("Wall check", "Проверка стен"),
                    Get = function() return CombatOpt("knifeWall") end,
                    Set = function(v) SetCombatOpt("knifeWall", v) end,
                })
                pop:Toggle({
                    Text = L("Target marker", "Маркер цели"),
                    Get = function() return CombatOpt("knifeMarker") end,
                    Set = function(v) SetCombatOpt("knifeMarker", v) end,
                })
                pop:Toggle({
                    Text = L("Throw on left click", "Бросок на ЛКМ"),
                    Get = function() return CombatOpt("knifeLMB") end,
                    Set = function(v) SetCombatOpt("knifeLMB", v) end,
                    Tip = L("On: left click throws too, like the native knife. Off: only RMB / E / throw key — stray clicks never waste the knife",
                        "Вкл: ЛКМ тоже бросает, как родной нож. Выкл: только ПКМ / E / клавиша броска — случайные клики не тратят нож"),
                })
            end,
        })
        knife:Toggle({
            Text = L("Auto throw", "Авто-бросок"),
            Get = function() return CombatOpt("autoThrow") end,
            Set = function(v) SetCombatOpt("autoThrow", v) end,
            Tip = L("Throws the knife at the nearest victim by itself", "Сам бросает нож в ближайшую жертву"),
            Callback = function(on)
                GameLog(on and L("Auto throw enabled", "Авто-бросок включён") or L("Auto throw disabled", "Авто-бросок выключен"))
            end,
            Gear = function(pop)
                pop:Slider({
                    Text = L("Auto range", "Дистанция авто-броска"),
                    Min = 20, Max = 200, Suffix = " st",
                    Get = function() return CombatOpt("autoThrowRange") end,
                    Set = function(v) SetCombatOpt("autoThrowRange", v) end,
                })
            end,
        })
        knife:Keybind({
            Text = L("Throw key", "Клавиша броска"),
            Get = function() return CombatOpt("throwKey") end,
            Set = function(v) SetCombatOpt("throwKey", v) end,
            Callback = function() end,
            Tip = L("Aimed manual throw of the knife", "Ручной бросок ножа с аимом"),
        })
        knife:Button({
            Text = L("Throw knife now", "Бросить нож сейчас"),
            Callback = function() Combat.throwNow() end,
        })
    end

    do
        local killer = TabCombat:Section({ Title = L("Murderer", "Убийца"), Col = 2 })
        killer:Toggle({
            Text = L("Kill all instantly", "Убить всех сразу"),
            Get = function() return CombatOpt("killAll") end,
            Set = function(v) SetCombatOpt("killAll", v) end,
            Tip = L("As the murderer, touches everyone with the knife (no teleport)",
                "Будучи убийцей, касается всех ножом (без телепорта)"),
        })
        killer:Toggle({
            Text = L("Kill aura", "Kill Aura"),
            Get = function() return CombatOpt("killAura") end,
            Set = function(v) SetCombatOpt("killAura", v) end,
            Tip = L("Touches everyone who comes into the radius with the knife",
                "Касается ножом всех, кто подошёл в радиус"),
            Callback = function(on)
                GameLog(on and L("Kill aura enabled", "Kill Aura включена")
                    or L("Kill aura disabled", "Kill Aura выключена"))
            end,
            Gear = function(pop)
                pop:Slider({
                    Text = L("Aura radius", "Радиус ауры"),
                    Min = 5, Max = 30, Suffix = " st",
                    Get = function() return CombatOpt("killAuraRange") end,
                    Set = function(v) SetCombatOpt("killAuraRange", v) end,
                })
            end,
        })
    end

    do
        local status = TabCombat:Section({ Title = L("Status", "Статус"), Col = 3 })
        status:Value({ Text = L("Aim hook", "Хук аима"), Get = function() return Combat.HookName() end })
        status:Value({ Text = L("Target", "Цель"), Get = function() return Combat.TargetName() end })
        status:Value({ Text = L("Lead time", "Упреждение"), Get = function() return Combat.LeadInfo() end })
        status:Value({ Text = L("Shots / Hits", "Выстрелы / попадания"), Get = function() return Combat.ShotsInfo() end })
        status:Value({ Text = L("Knife speed", "Скорость ножа"), Get = function() return Combat.KnifeInfo() end })
    end

    -- Farm
    do
        local stats = TabFarm:Section({ Title = L("Statistics", "Статистика"), Col = 1 })
        stats:Value({ Text = L("Collected", "Собрано"), Get = function() return FormatNumber(Stats.Session) end })
        stats:Value({ Text = L("Per hour", "В час"), Get = function() return FormatNumber(Stats.Rate) end })
        stats:Value({ Text = L("Total", "Всего"), Get = function() return FormatNumber(Settings.TotalCoins) end })
        stats:Value({ Text = L("Status", "Статус"), Get = function() return T("status_" .. Stats.Status) end })

        local farm = TabFarm:Section({ Title = L("Farm", "Фарм"), Col = 2 })
        farm:Toggle({
            Text = L("Auto farm", "Автофарм"), Setting = "AutoFarm",
            Tip = L("Collects coins automatically while you are alive in a round",
                "Автоматически собирает монеты, пока ты жив в раунде"),
            Callback = function(on)
                FarmSetEnabled(on)
                GameLog(on and L("Auto farm enabled", "Автофарм включён") or L("Auto farm disabled", "Автофарм выключен"))
            end,
        })
        farm:Dropdown({
            Text = L("Farm method", "Метод фарма"), Setting = "FarmMethod",
            Tip = L("Classic flies straight to coins. Under map flies below the floor and rises to each coin.",
                "Классический летит прямо к монетам. Под картой летит под полом и поднимается к каждой монете."),
            Options = {
                { value = "classic", text = L("Classic (fast)", "Классический (быстрый)") },
                { value = "undermap", text = L("Under map", "Под картой") },
            },
        })
        farm:Slider({ Text = L("Classic speed", "Скорость классического"), Setting = "SpeedClassic", Min = 8, Max = 24, Suffix = " st/s", Default = 24 })
        farm:Slider({ Text = L("Under map speed", "Скорость под картой"), Setting = "SpeedUnderMap", Min = 8, Max = 22, Suffix = " st/s", Default = 21 })

        local safety = TabFarm:Section({ Title = L("Safety", "Безопасность"), Col = 3 })
        safety:Toggle({
            Text = L("Avoid murderer", "Избегать убийцу"), Setting = "AvoidMurderer",
            Tip = L("Skips coins close to the murderer", "Пропускает монеты рядом с убийцей"),
        })
        safety:Toggle({
            Text = L("Pick up gun", "Подбирать пистолет"), Setting = "PickGun",
            Tip = L("Innocents grab the gun when the sheriff dies", "Невиновный берёт пистолет, когда шериф погиб"),
        })

        local full = TabFarm:Section({ Title = L("Full bag", "Полный мешок"), Col = 3 })
        full:Toggle({ Text = L("Respawn when bag is full", "Авто-респавн при полном мешке"), Setting = "AutoRespawnFull" })
        full:Toggle({
            Text = L("Kill all when bag is full (murderer)", "Убить всех при полном мешке (убийца)"),
            Setting = "KillAllFull",
        })
        full:Toggle({
            Text = L("Auto shoot murderer when bag is full (sheriff)",
                "Авто-выстрел в убийцу при полном мешке (шериф)"),
            Setting = "ShootMurdererFull",
            Tip = L("With a full bag the sheriff keeps shooting the murderer (auto-equip, prediction)",
                "При полном мешке шериф продолжает стрелять в убийцу (авто-экип, предсказание)"),
            Callback = function(on)
                GameLog(on and L("Full-bag auto shoot enabled", "Авто-выстрел при полном мешке включён")
                    or L("Full-bag auto shoot disabled", "Авто-выстрел при полном мешке выключен"))
            end,
        })
        full:Toggle({
            Text = L("Through walls (full-bag shot)", "Сквозь стены (выстрел при полном)"),
            Get = function() return CombatOpt("farmPiercer") end,
            Set = function(v) SetCombatOpt("farmPiercer", v) end,
            Tip = L("Full-bag shot origin is placed near the murderer, so walls and obstacles do not block it",
                "Выстрел при полном мешке бьёт от самой цели: стены и препятствия не мешают"),
        })

        local connection = TabFarm:Section({ Title = L("Connection", "Соединение"), Col = 2 })
        connection:Toggle({
            Text = L("Auto rejoin on kick", "Авто-перезаход при кике"), Setting = "AutoRejoin",
            Tip = L("Needs Auto execute and a saved YozoraHub_Autorun.lua to resume farming",
                "Для продолжения фарма нужен Авто-запуск и сохранённый YozoraHub_Autorun.lua"),
        })
    end

    -- ESP
    do
        local function toggle(section, text, key, tip)
            section:Toggle({ Text = text, Esp = key, Tip = tip })
        end
        local function slider(section, text, key, min, max, decimals, suffix)
            local default = ESP_DEFAULTS[key]
            if type(default) == "number" then default = math.clamp(default, min, max) else default = nil end
            section:Slider({ Text = text, Esp = key, Min = min, Max = max, Decimals = decimals or 0, Suffix = suffix, Default = default })
        end
        local function dropdown(section, text, key, options)
            section:Dropdown({ Text = text, Esp = key, Options = options })
        end
        local function colour(section, text, key)
            section:Colorpicker({
                Text = text,
                Get = function() return EspColour(key) end,
                Set = function(color)
                    SetEspOpt(key, color:ToHex())
                    SaveSoon()
                end,
            })
        end

        -- ESP / Основное
        local main = TabVisuals:Section({ Title = L("ESP", "ESP"), Sub = "esp", Col = 1 })
        main:Toggle({
            Text = L("Enable ESP", "Включить ESP"), Setting = "ESP",
            Tip = L("Shows players through walls: boxes, names, chams, skeleton and more",
                "Показывает игроков сквозь стены: рамки, имена, чамсы, скелет и другое"),
            Callback = function(on) Esp.setEnabled(on) end,
        })
        toggle(main, L("Murderer", "Убийца"), "murderer")
        toggle(main, L("Sheriff", "Шериф"), "sheriff")
        toggle(main, L("Hero", "Герой"), "hero",
            L("An innocent who picked up the sheriff's gun", "Невиновный, который подобрал пистолет шерифа"))
        toggle(main, L("Innocent", "Невиновный"), "innocent")

        local colors = TabVisuals:Section({ Title = L("Role colors", "Цвета ролей"), Sub = "esp", Col = 2 })
        colour(colors, L("Murderer", "Убийца"), "murdererColour")
        colour(colors, L("Sheriff", "Шериф"), "sheriffColour")
        colour(colors, L("Hero", "Герой"), "heroColour")
        colour(colors, L("Innocent", "Невиновный"), "innocentColour")

        local filters = TabVisuals:Section({ Title = L("Filters", "Фильтры"), Sub = "esp", Col = 3 })
        slider(filters, L("Max distance", "Макс. дистанция"), "maxDist", 100, 3000, 0, " st")
        toggle(filters, L("Fade with distance", "Затухание с расстоянием"), "fade")
        toggle(filters, L("Visibility check", "Проверка видимости"), "visCheck",
            L("Checks whether a wall blocks the player", "Проверяет, закрывает ли игрока стена"))
        toggle(filters, L("Dim hidden players", "Приглушать скрытых игроков"), "dimHidden")
        slider(filters, L("Smoothing", "Сглаживание"), "smooth", 0, 90, 0, "%")

        local text = TabVisuals:Section({ Title = L("Text", "Текст"), Sub = "esp", Col = 2 })
        toggle(text, L("Name", "Имя"), "name")
        dropdown(text, L("Name style", "Вид имени"), "nameMode", {
            { value = "Display", text = L("Display name", "Отображаемое имя") },
            { value = "Username", text = L("Username", "Ник") },
            { value = "Both", text = L("Both", "Оба") },
        })
        toggle(text, L("Role", "Роль"), "role")
        toggle(text, L("Weapon", "Оружие"), "weapon")
        toggle(text, L("Distance", "Дистанция"), "distance")
        dropdown(text, L("Distance unit", "Единицы дистанции"), "distUnit", {
            { value = "Studs", text = L("Studs", "Студы") },
            { value = "Meters", text = L("Meters", "Метры") },
        })
        slider(text, L("Text size", "Размер текста"), "textSize", 9, 20, 0, " px")
        toggle(text, L("Text outline", "Обводка текста"), "textOutline")

        -- Box
        local box = TabVisuals:Section({ Title = L("Box", "Рамка"), Sub = "boxes", Col = 1 })
        toggle(box, L("Box", "Рамка"), "box")
        dropdown(box, L("Box style", "Стиль рамки"), "boxStyle", {
            { value = "Corners", text = L("Corners", "Уголки") },
            { value = "Full", text = L("Full", "Полная") },
        })
        slider(box, L("Thickness", "Толщина"), "boxThickness", 1, 4, 0, " px")
        slider(box, L("Corner size", "Размер уголков"), "cornerSize", 6, 60, 0, " px")
        slider(box, L("Box width", "Ширина рамки"), "boxWidth", 30, 80, 0, "%")
        toggle(box, L("Outline", "Обводка"), "boxOutline")

        local fill = TabVisuals:Section({ Title = L("Fill and color", "Заливка и цвет"), Sub = "boxes", Col = 2 })
        toggle(fill, L("Fill", "Заливка"), "boxFill")
        slider(fill, L("Fill opacity", "Прозрачность заливки"), "boxFillAlpha", 0, 60, 0, "%")
        dropdown(fill, L("Box color", "Цвет рамки"), "boxColMode", {
            { value = "Role", text = L("By role", "По роли") },
            { value = "Custom", text = L("Custom", "Свой") },
        })
        colour(fill, L("Custom box color", "Свой цвет рамки"), "boxColour")

        -- Chams
        local chams = TabVisuals:Section({ Title = L("Chams", "Чамсы"), Sub = "boxes", Col = 3 })
        toggle(chams, L("Chams", "Чамсы"), "chams",
            L("Highlights the whole character", "Подсвечивает всего персонажа"))
        slider(chams, L("Fill transparency", "Прозрачность заливки"), "chamsFill", 0, 1, 2)
        slider(chams, L("Outline transparency", "Прозрачность контура"), "chamsOutline", 0, 1, 2)
        toggle(chams, L("Through walls", "Сквозь стены"), "chamsThrough")
        toggle(chams, L("Use role colors", "Цвета по ролям"), "chamsRole")
        colour(chams, L("Custom chams color", "Свой цвет чамсов"), "chamsColour")
        colour(chams, L("Hidden players color", "Цвет скрытых игроков"), "chamsHidden")
        slider(chams, L("Max distance (0 = no limit)", "Макс. дистанция (0 = без лимита)"), "chamsMaxDist", 0, 3000, 0, " st")

        -- Extras
        local skeleton = TabVisuals:Section({ Title = L("Skeleton", "Скелет"), Sub = "extras", Col = 1 })
        toggle(skeleton, L("Skeleton", "Скелет"), "skeleton")
        slider(skeleton, L("Line thickness", "Толщина линий"), "boneThick", 1, 4, 1, " px")
        toggle(skeleton, L("Use role colors", "Цвета по ролям"), "boneRole")
        colour(skeleton, L("Custom skeleton color", "Свой цвет скелета"), "boneColour")
        toggle(skeleton, L("Head circle", "Круг на голове"), "headDot")
        slider(skeleton, L("Max distance (0 = no limit)", "Макс. дистанция (0 = без лимита)"), "skelMaxDist", 0, 1500, 0, " st")

        local tracers = TabVisuals:Section({ Title = L("Tracers", "Трассеры"), Sub = "extras", Col = 2 })
        toggle(tracers, L("Tracers", "Трассеры"), "tracer")
        dropdown(tracers, L("Start point", "Начало линии"), "tracerFrom", {
            { value = "Bottom", text = L("Bottom", "Снизу") },
            { value = "Center", text = L("Center", "Центр") },
            { value = "Top", text = L("Top", "Сверху") },
            { value = "Mouse", text = L("Mouse", "Курсор") },
        })
        dropdown(tracers, L("End point", "Конец линии"), "tracerTo", {
            { value = "Feet", text = L("Feet", "Ноги") },
            { value = "Center", text = L("Center", "Центр") },
            { value = "Head", text = L("Head", "Голова") },
        })
        slider(tracers, L("Thickness", "Толщина"), "tracerThick", 1, 4, 1, " px")
        slider(tracers, L("Opacity", "Непрозрачность"), "tracerAlpha", 0.1, 1, 2)
        toggle(tracers, L("Use role colors", "Цвета по ролям"), "tracerRole")
        colour(tracers, L("Custom tracer color", "Свой цвет трассеров"), "tracerColour")

        local arrows = TabVisuals:Section({ Title = L("Off-screen arrows", "Стрелки за экраном"), Sub = "extras", Col = 3 })
        toggle(arrows, L("Off-screen arrows", "Стрелки за экраном"), "arrows",
            L("Points to players who are outside the screen", "Показывает направление на игроков вне экрана"))
        slider(arrows, L("Ring radius", "Радиус кольца"), "arrowRadius", 80, 400, 0, " px")
        slider(arrows, L("Arrow size", "Размер стрелки"), "arrowSize", 5, 20, 0, " px")

        local gun = TabVisuals:Section({ Title = L("Gun ESP", "ESP пистолета"), Sub = "extras", Col = 3 })
        toggle(gun, L("Highlight dropped gun", "Подсвечивать выпавший пистолет"), "gunEsp",
            L("Works even when ESP is off", "Работает даже при выключенном ESP"))
        colour(gun, L("Gun color", "Цвет пистолета"), "gunColour")
    end

    -- Visuals
    do
        local function toggle(section, text, key, tip)
            section:Toggle({ Text = text, Vis = key, Tip = tip })
        end
        local function slider(section, text, key, min, max, decimals, suffix)
            local default = VIS_DEFAULTS[key]
            if type(default) == "number" then default = math.clamp(default, min, max) else default = nil end
            section:Slider({ Text = text, Vis = key, Min = min, Max = max, Decimals = decimals or 0, Suffix = suffix, Default = default })
        end
        local function dropdown(section, text, key, options, callback)
            section:Dropdown({ Text = text, Vis = key, Options = options, Callback = callback })
        end
        local function colour(section, text, key)
            section:Colorpicker({
                Text = text,
                Get = function() return VisColor(key) end,
                Set = function(color)
                    SetVisOpt(key, color:ToHex())
                    SaveSoon()
                end,
            })
        end
        local function names(list, first)
            local options = {}
            if first then table.insert(options, first) end
            for _, name in ipairs(list) do table.insert(options, { value = name, text = name }) end
            return options
        end

        Visual.refreshUI = function() SyncAll() end

        -- ===== Мир =====
        local look = TabVisuals:Section({ Title = L("Look", "Облик"), Sub = "world", Col = 1 })
        look:Toggle({
            Text = L("Enable world changes", "Включить изменения мира"), Vis = "worldOn",
            Tip = L("Master switch: everything below is applied only while it is on, and the game's values are restored when it is off",
                "Главный переключатель: настройки ниже работают только когда он включён, а при выключении возвращаются значения игры"),
        })
        look:Dropdown({
            Text = L("Preset", "Пресет"),
            Options = names(VIS_PRESET_NAMES, nil),
            Get = function() return VisOpt("preset") end,
            Set = function(name) Visual.applyPreset(name) end,
        })
        look:Button({
            Text = L("Reset to the game's look", "Вернуть вид игры"), Icon = "rotate-ccw",
            Callback = function() Visual.applyPreset("Original") end,
        })
        dropdown(look, L("Lighting technology", "Технология освещения"), "tech", {
            { value = "Game", text = L("Game default", "Как в игре") },
            { value = "Future", text = "Future" }, { value = "ShadowMap", text = "ShadowMap" },
            { value = "Voxel", text = "Voxel" }, { value = "Compatibility", text = "Compatibility" },
        })

        local lighting = TabVisuals:Section({ Title = L("Lighting", "Освещение"), Sub = "world", Col = 1 })
        toggle(lighting, L("Override brightness", "Своя яркость"), "brightOn")
        slider(lighting, L("Brightness", "Яркость"), "brightness", 0, 10, 1)
        toggle(lighting, L("Override time of day", "Своё время суток"), "timeOn")
        slider(lighting, L("Time of day", "Время суток"), "time", 0, 24, 1, " h")
        toggle(lighting, L("Override exposure", "Своя экспозиция"), "exposureOn")
        slider(lighting, L("Exposure", "Экспозиция"), "exposure", -3, 3, 1)
        toggle(lighting, L("Override ambient light", "Свой рассеянный свет"), "ambientOn")
        colour(lighting, L("Ambient color", "Цвет рассеянного света"), "ambient")
        colour(lighting, L("Outdoor ambient color", "Цвет света на улице"), "outdoor")
        toggle(lighting, L("Disable shadows", "Отключить тени"), "noShadows")
        toggle(lighting, L("Override shadow softness", "Своя мягкость теней"), "shadowSoftOn")
        slider(lighting, L("Shadow softness", "Мягкость теней"), "shadowSoft", 0, 1, 2)

        local air = TabVisuals:Section({ Title = L("Atmosphere, fog and clouds", "Атмосфера, туман и облака"), Sub = "world", Col = 2 })
        toggle(air, L("Atmosphere", "Атмосфера"), "atmosOn")
        slider(air, L("Density", "Плотность"), "density", 0, 1, 2)
        slider(air, L("Offset", "Смещение"), "offset", 0, 1, 2)
        slider(air, L("Haze", "Дымка"), "haze", 0, 10, 1)
        slider(air, L("Glare", "Блики"), "glare", 0, 10, 1)
        colour(air, L("Atmosphere color", "Цвет атмосферы"), "atmosColour")
        colour(air, L("Decay color", "Цвет затухания"), "decay")
        air:Divider()
        toggle(air, L("Fog", "Туман"), "fogOn")
        slider(air, L("Fog start", "Начало тумана"), "fogStart", 0, 2000, 0, " st")
        slider(air, L("Fog end", "Конец тумана"), "fogEnd", 50, 5000, 0, " st")
        colour(air, L("Fog color", "Цвет тумана"), "fogColour")
        air:Divider()
        toggle(air, L("Clouds", "Облака"), "cloudsOn")
        slider(air, L("Cloud cover", "Покрытие облаками"), "cloudCover", 0, 1, 2)
        slider(air, L("Cloud density", "Плотность облаков"), "cloudDensity", 0, 1, 2)
        colour(air, L("Cloud color", "Цвет облаков"), "cloudColour")

        local grade = TabVisuals:Section({ Title = L("Color", "Цвет"), Sub = "world", Col = 3 })
        toggle(grade, L("Color correction", "Цветокоррекция"), "gradeOn")
        slider(grade, L("Brightness", "Яркость"), "gradeBright", -0.5, 0.5, 2)
        slider(grade, L("Contrast", "Контраст"), "contrast", -0.5, 1, 2)
        slider(grade, L("Saturation", "Насыщенность"), "saturation", -1, 1, 2)
        colour(grade, L("Tint", "Оттенок"), "tint")

        local glow = TabVisuals:Section({ Title = L("Glow and focus", "Свечение и фокус"), Sub = "world", Col = 3 })
        toggle(glow, L("Bloom", "Свечение (Bloom)"), "bloomOn")
        slider(glow, L("Bloom intensity", "Сила свечения"), "bloomIntensity", 0, 2, 2)
        slider(glow, L("Bloom size", "Размер свечения"), "bloomSize", 0, 56, 0)
        slider(glow, L("Bloom threshold", "Порог свечения"), "bloomThreshold", 0, 3, 2)
        glow:Divider()
        toggle(glow, L("Sun rays", "Лучи солнца"), "raysOn")
        slider(glow, L("Rays intensity", "Сила лучей"), "raysIntensity", 0, 1, 2)
        slider(glow, L("Rays spread", "Разброс лучей"), "raysSpread", 0, 1, 2)
        glow:Divider()
        toggle(glow, L("Depth of field", "Глубина резкости"), "dofOn")
        slider(glow, L("Blur strength", "Сила размытия"), "dofFar", 0, 1, 2)
        slider(glow, L("Focus distance", "Дистанция фокуса"), "dofFocus", 5, 500, 0, " st")
        slider(glow, L("In-focus radius", "Радиус резкости"), "dofRadius", 5, 500, 0, " st")
        glow:Divider()
        toggle(glow, L("Vignette", "Виньетка"), "vignetteOn")
        slider(glow, L("Vignette strength", "Сила виньетки"), "vignette", 0, 85, 0, "%")

        local gameFx = TabVisuals:Section({ Title = L("Game effects", "Эффекты игры"), Sub = "world", Col = 2 })
        toggle(gameFx, L("Remove the game's post effects", "Убрать пост-эффекты игры"), "noPost",
            L("Turns off blur, bloom and color effects added by the game", "Отключает размытие, свечение и цветокоррекцию, добавленные игрой"))
        toggle(gameFx, L("Remove the game's atmosphere", "Убрать атмосферу игры"), "noAtmos")
        dropdown(gameFx, L("Materials", "Материалы"), "materials", {
            { value = "Game", text = L("Game default", "Как в игре") },
            { value = "HD Realistic", text = "HD Realistic" },
            { value = "HD Worn", text = "HD Worn" },
            { value = "HD Wet", text = "HD Wet" },
        })

        -- ===== Небо =====
        local skybox = TabVisuals:Section({ Title = L("Skybox", "Небо"), Sub = "sky", Col = 1 })
        skybox:Dropdown({
            Text = L("Sky", "Небо"), Vis = "sky",
            Options = names(VIS_SKY_NAMES, { value = "Game", text = L("Game default", "Как в игре") }),
        })
        skybox:Paragraph({
            Text = L("A custom sky replaces the game's sky while selected. Choose \"Game default\" to bring it back.",
                "Выбранное небо заменяет небо игры. Выбери «Как в игре», чтобы вернуть прежнее."),
        })

        local details = TabVisuals:Section({ Title = L("Sky details", "Детали неба"), Sub = "sky", Col = 2 })
        toggle(details, L("Override sky details", "Свои детали неба"), "skyDetailsOn")
        slider(details, L("Stars", "Звёзды"), "stars", 0, 20000, 0)
        slider(details, L("Sun size", "Размер солнца"), "sunSize", 1, 120, 0)
        slider(details, L("Moon size", "Размер луны"), "moonSize", 1, 60, 0)
        toggle(details, L("Show sun and moon", "Показывать солнце и луну"), "celestial")

        -- ===== Погода =====
        local weather = TabVisuals:Section({ Title = L("Weather", "Погода"), Sub = "weather", Col = 1 })
        weather:Dropdown({
            Text = L("Scene", "Сцена"),
            Options = names(VIS_SCENE_NAMES, { value = "", text = L("None", "Нет") }),
            Get = function() return VisOpt("scene") end,
            Set = function(name) if name ~= "" then Visual.applyScene(name) end end,
        })
        dropdown(weather, L("Weather", "Погода"), "weather", names(VIS_WEATHER_NAMES, nil))
        slider(weather, L("Amount", "Количество"), "weatherAmount", 0, 100, 0, "%")
        slider(weather, L("Opacity", "Непрозрачность"), "weatherOpacity", 5, 100, 0, "%")
        slider(weather, L("Particle size", "Размер частиц"), "weatherScale", 0.4, 2, 2, "x")
        slider(weather, L("Speed", "Скорость"), "weatherSpeed", 20, 220, 0, "%")

        local wind = TabVisuals:Section({ Title = L("Wind and area", "Ветер и область"), Sub = "weather", Col = 2 })
        slider(wind, L("Area radius", "Радиус области"), "weatherRadius", 15, 70, 0, " st")
        slider(wind, L("Wind", "Ветер"), "weatherWind", 0, 20, 1)
        slider(wind, L("Wind direction", "Направление ветра"), "weatherWindAngle", 0, 360, 0, "°")
        toggle(wind, L("Stop under roofs", "Не падать под крышей"), "weatherShelter")
        toggle(wind, L("Custom color", "Свой цвет"), "weatherColourOn")
        colour(wind, L("Particle color", "Цвет частиц"), "weatherColour")
        toggle(wind, L("Weather sounds", "Звуки погоды"), "weatherSound")
        slider(wind, L("Sound volume", "Громкость звуков"), "weatherVolume", 0, 100, 0, "%")

        -- ===== Экран =====
        local camera = TabVisuals:Section({ Title = L("Camera", "Камера"), Sub = "screen", Col = 1 })
        toggle(camera, L("Override field of view", "Своё поле зрения"), "fovOn")
        slider(camera, L("Field of view", "Поле зрения"), "fov", 30, 120, 0, "°")
        slider(camera, L("Screen stretch", "Растяжение экрана"), "stretch", 0, 100, 0, "%")

        local performance = TabVisuals:Section({ Title = L("Performance", "Производительность"), Sub = "screen", Col = 2 })
        toggle(performance, L("Set FPS cap", "Ограничение FPS"), "fpsOn",
            L("Needs an executor that supports setfpscap", "Нужен executor с поддержкой setfpscap"))
        slider(performance, L("FPS cap", "Лимит FPS"), "fpsCap", 15, 360, 0)
        toggle(performance, L("Disable 3D rendering", "Отключить 3D-рендер"), "noRender",
            L("The screen goes black but the game keeps running. Handy for AFK farming.",
                "Экран станет чёрным, но игра продолжит работать. Удобно для AFK-фарма."))

        -- ===== Эффекты =====
        local aura = TabVisuals:Section({ Title = L("Aura", "Аура"), Sub = "effects", Col = 1 })
        dropdown(aura, L("Aura", "Аура"), "aura", {
            { value = "Off", text = L("Off", "Выкл") },
            { value = "Sparkles", text = L("Sparkles", "Искры") },
            { value = "Petals", text = L("Petals", "Лепестки") },
            { value = "Fire", text = L("Fire", "Огонь") },
            { value = "Smoke", text = L("Smoke", "Дым") },
            { value = "Stars", text = L("Stars", "Звёзды") },
        })
        dropdown(aura, L("Color mode", "Режим цвета"), "auraColMode", {
            { value = "Accent", text = L("Menu accent", "Акцент меню") },
            { value = "Custom", text = L("Custom", "Свой") },
            { value = "Rainbow", text = L("Rainbow", "Радуга") },
        })
        colour(aura, L("Custom color", "Свой цвет"), "auraColour")
        slider(aura, L("Size", "Размер"), "auraSize", 0.4, 3, 2, "x")
        slider(aura, L("Amount", "Количество"), "auraRate", 0.2, 3, 2, "x")

        local extras = TabVisuals:Section({ Title = L("Character effects", "Эффекты персонажа"), Sub = "effects", Col = 2 })
        toggle(extras, L("Glow light", "Свечение вокруг"), "auraGlow")
        toggle(extras, L("Outline", "Контур"), "auraOutline")
        toggle(extras, L("Trail", "Шлейф"), "auraTrail")
        extras:Paragraph({
            Text = L("Effects follow your character and come back after respawn. They use the color mode set on the left.",
                "Эффекты следуют за персонажем и возвращаются после респавна. Цвет берётся из режима слева."),
        })
    end



    -- Misc / General
    do
        local protect = TabMisc:Section({ Title = L("Protection", "Защита"), Sub = "general", Col = 1 })
        protect:Toggle({
            Text = L("Anti-Fling (fling protection)", "Anti-Fling (защита от флинга)"), Setting = "AntiFling",
            Tip = L("Stops other players from pushing or flinging you", "Не даёт другим игрокам толкать и флинговать тебя"),
        })
        protect:Toggle({
            Text = L("Anti-AFK (prevent idle kick)", "Anti-AFK (не кикать за бездействие)"), Setting = "AntiAFK",
        })

        local script = TabMisc:Section({ Title = L("Script", "Скрипт"), Sub = "general", Col = 2 })
        script:Toggle({
            Text = L("Auto execute after teleport", "Автозапуск после телепорта"), Setting = "AutoExecute",
            Tip = L("Needs a saved YozoraHub_Autorun.lua file (executor workspace folder). "
                .. "Use the button below to save it if your executor exposes the script source.",
                "Нужен сохранённый файл YozoraHub_Autorun.lua (в папке workspace экзекутора). "
                .. "Если экзекутор отдаёт исходник скрипта — сохрани кнопкой ниже."),
        })
        script:Button({
            Text = L("Save autorun copy", "Сохранить копию для автозапуска"), Icon = "save",
            Callback = function()
                if not writefile then
                    Notify(L("writefile is not supported", "writefile не поддерживается"), nil, "error")
                    return
                end
                local source = nil
                pcall(function()
                    local s = getcallingscript and getcallingscript()
                    if s and type(s.Source) == "string" and s.Source ~= "" then source = s.Source end
                end)
                if not source then
                    Notify(L("Executor does not expose the source — save the file manually",
                        "Экзекутор не отдаёт исходник — сохрани файл вручную"), SCRIPT_FILE, "warning")
                    return
                end
                local ok, err = pcall(writefile, SCRIPT_FILE, source)
                Notify(ok and L("Autorun copy saved", "Копия для автозапуска сохранена")
                        or L("Could not save autorun copy", "Не удалось сохранить копию"),
                    ok and SCRIPT_FILE or tostring(err), ok and "success" or "error")
            end,
        })
        script:Button({
            Text = L("Unload hub", "Выгрузить скрипт"), Icon = "power", Style = "Danger", DoubleClick = true,
            Callback = function()
                task.defer(function()
                    pcall(FarmSetEnabled, false)
                    pcall(ClearESP)
                    if _G.YozoraHub_Cleanup then pcall(_G.YozoraHub_Cleanup) end
                    _G.YozoraHub_RunId = nil
                    local blur = Lighting:FindFirstChild("YozoraHub_Blur")
                    if blur then blur:Destroy() end
                    pcall(function() HudGui:Destroy() end)
                    ScreenGui:Destroy()
                end)
            end,
        })
    end

    -- Misc / General: игрок (порт функций Player)
    do
        local speed = TabMisc:Section({ Title = L("Speed & Jump", "Скорость и прыжок"), Sub = "general", Col = 2 })
        speed:Slider({
            Text = L("Walk Speed", "Скорость ходьбы"), Min = 0, Max = 200, Decimals = 0, Setting = "PlayerSpeed", Default = 16,
            Tip = L("Character walk speed (16 is default)", "Скорость персонажа (по умолчанию 16)"),
        })
        speed:Slider({
            Text = L("Jump Power", "Сила прыжка"), Min = 0, Max = 300, Decimals = 0, Setting = "PlayerJump", Default = 50,
            Tip = L("Jump power (50 is default)", "Сила прыжка (по умолчанию 50)"),
        })
        speed:Slider({
            Text = L("Gravity", "Гравитация"), Min = 0, Max = 300, Decimals = 1, Setting = "PlayerGravity", Default = 196.2,
            Tip = L("World gravity (196.2 is default)", "Гравитация мира (по умолчанию 196.2)"),
        })

        local movement = TabMisc:Section({ Title = L("Movement", "Движение"), Sub = "general", Col = 3 })
        movement:Toggle({
            Text = L("No Clip", "No Clip (сквозь стены)"), Setting = "NoClip",
            Tip = L("Walk through walls and objects", "Проходить сквозь стены и объекты"),
        })
        movement:Toggle({ Text = L("Infinite Jumps", "Бесконечные прыжки"), Setting = "InfiniteJumps" })
        movement:Toggle({
            Text = L("Wall Hop", "Прыжок от стены"), Setting = "WallHop",
            Tip = L("Jump again mid-air when touching a wall", "Прыжок в воздухе, если рядом стена"),
        })
        movement:Toggle({
            Text = L("Speed Glitch", "Спид-глитч (рывок)"), Setting = "SpeedGlitch",
            Tip = L("Extra forward boost on jump", "Дополнительный рывок вперёд при прыжке"),
        })
        movement:Toggle({ Text = L("Bhop", "Bhop (авто-прыжки)"), Setting = "Bhop" })
        movement:Toggle({ Text = L("Spin", "Вращение"), Setting = "Spin" })
        movement:Toggle({
            Text = L("Fly", "Полёт"), Setting = "Fly",
            Tip = L("WASD to move, Space up, Shift down", "WASD — движение, Space — вверх, Shift — вниз"),
        })
        movement:Slider({ Text = L("Fly Speed", "Скорость полёта"), Min = 5, Max = 200, Decimals = 0, Setting = "FlySpeed", Default = 45 })

        local vision = TabMisc:Section({ Title = L("Vision", "Видимость"), Sub = "general", Col = 3 })
        vision:Toggle({
            Text = L("X-Ray", "X-Ray (сквозь стены)"), Setting = "XRay",
            Tip = L("Show every player through walls", "Показывает всех игроков сквозь стены"),
        })
        vision:Toggle({
            Text = L("Invisible", "Невидимость"), Setting = "Invisible",
            Tip = L("Makes your character invisible", "Делает персонажа невидимым"),
        })
    end

    -- Server
    do
        local server = TabMisc:Section({ Title = L("Server", "Сервер"), Sub = "server", Col = 1 })
        server:Value({ Text = L("Players", "Игроков"), Get = function() return #Players:GetPlayers() .. " / " .. Players.MaxPlayers end })
        server:Value({ Text = L("Place ID", "ID места"), Get = function() return tostring(game.PlaceId) end })
        server:Value({ Text = L("Job ID", "ID сервера"), Get = function()
            local id = tostring(game.JobId)
            return #id > 10 and (id:sub(1, 8) .. "..") or id
        end })

        local actions = TabMisc:Section({ Title = L("Actions", "Действия"), Sub = "server", Col = 2 })
        actions:Button({
            Text = L("Copy Job ID", "Скопировать ID сервера"), Icon = "copy",
            Callback = function()
                local copy = setclipboard or toclipboard
                if copy then
                    pcall(copy, tostring(game.JobId))
                    Notify(L("Job ID copied", "ID сервера скопирован"), nil, "success")
                else
                    Notify(L("Clipboard is not supported", "Буфер обмена не поддерживается"), nil, "warning")
                end
            end,
        })
        actions:Button({
            Text = L("Rejoin this server", "Перезайти на этот сервер"), Icon = "rotate-ccw",
            Callback = function()
                QueueAutorun()
                pcall(function()
                    TeleportServiceUI:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                end)
            end,
        })
        actions:Button({
            Text = L("Join a new server", "Зайти на новый сервер"), Icon = "log-out",
            Callback = function()
                QueueAutorun()
                pcall(function() TeleportServiceUI:Teleport(game.PlaceId, LocalPlayer) end)
            end,
        })
    end



    -- Misc / Interface
    do
        local theme = TabMisc:Section({ Title = L("Theme", "Тема"), Sub = "interface", Col = 1 })
        local accentOptions = {}
        for _, preset in ipairs(ACCENT_PRESETS) do
            table.insert(accentOptions, { value = preset[1], text = preset[1] })
        end
        theme:Dropdown({
            Text = L("Accent", "Акцент"), Options = accentOptions,
            Get = function()
                local current = Theme.tokens.Accent:ToHex():lower()
                for _, preset in ipairs(ACCENT_PRESETS) do
                    if preset[2] == current then return preset[1] end
                end
                return nil
            end,
            Set = function(name)
                for _, preset in ipairs(ACCENT_PRESETS) do
                    if preset[1] == name then Appearance.setAccent(hex(preset[2])) end
                end
            end,
            Callback = function() SyncAll() end,
        })
        theme:Colorpicker({
            Text = L("Custom accent", "Свой акцент"),
            Get = function() return Theme.tokens.Accent end,
            Set = function(color) Appearance.setAccent(color) end,
        })
        local baseOptions = {}
        for _, base in ipairs(THEME_BASES) do table.insert(baseOptions, { value = base[1], text = base[1] }) end
        table.insert(baseOptions, { value = "Custom", text = L("Custom", "Своя") })
        theme:Dropdown({
            Text = L("Colors", "Цвета"), Options = baseOptions,
            Get = function() return Theme.base end,
            Set = function(name)
                if name == "Custom" then
                    Theme.setPanel(SafeHex(Pref("panel"), UI_DEFAULTS.panel))
                    SetPref("base", "Custom")
                    Theme.refresh()
                else
                    SetPref("base", name)
                    Appearance.theme()
                end
            end,
            Callback = function() SyncAll() end,
        })
        theme:Colorpicker({
            Text = L("Panel color", "Цвет панели"),
            Get = function() return Theme.tokens.Background end,
            Set = function(color)
                Theme.setPanel(color)
                SetPref("base", "Custom")
                SetPref("panel", color:ToHex())
                Theme.refresh()
            end,
        })

        local window = TabMisc:Section({ Title = L("Window", "Окно"), Sub = "interface", Col = 2 })
        local fontOptions = {}
        for _, family in ipairs(Fonts.families) do table.insert(fontOptions, family[1]) end
        window:Dropdown({
            Text = L("Font", "Шрифт"), Pref = "font", Options = fontOptions, Callback = function() Appearance.text() end,
        })
        window:Slider({
            Text = L("Text size", "Размер текста"), Pref = "textScale", Min = 0.85, Max = 1.25, Decimals = 2, Suffix = "x",
            Callback = function() Appearance.text() end,
        })
        window:Slider({
            Text = L("Corner radius", "Скругление углов"), Pref = "radius", Min = 0, Max = 2, Decimals = 2, Suffix = "x",
            Callback = function() Appearance.radius() end,
        })
        window:Slider({
            Text = L("Window opacity", "Прозрачность окна"), Pref = "opacity", Min = 0.5, Max = 1, Decimals = 2,
            Callback = function() Appearance.opacity() end,
        })
        window:Toggle({ Text = L("Blur behind menu", "Размытие за меню"), Pref = "blur", Callback = function() Appearance.blur() end })

        local behavior = TabMisc:Section({ Title = L("Behavior", "Поведение"), Sub = "interface", Col = 3 })
        behavior:Toggle({ Text = L("Tooltips", "Подсказки"), Pref = "tooltips" })
        behavior:Toggle({
            Text = L("Launcher button", "Кнопка-лаунчер"), Pref = "launcher", Callback = function() Appearance.launcher() end,
            Tip = L("A floating button that opens the menu (handy on mobile)", "Плавающая кнопка открытия меню (удобно на телефоне)"),
        })
        behavior:Keybind({
            Text = L("Menu key", "Клавиша меню"), Pref = "menuKey", Callback = function() LoadMenuKey() end,
        })
        behavior:Button({
            Text = L("Reset appearance", "Сбросить внешний вид"), Icon = "rotate-ccw", DoubleClick = true,
            Callback = ResetAppearance,
        })
    end

    -- Settings / Configs
    do
        local profiles = TabMisc:Section({ Title = L("Profiles", "Профили"), Sub = "configs", Col = 1 })
        if FilesSupported() then
            local nameControl = profiles:Input({
                Text = L("Config name", "Имя конфига"), Placeholder = L("My config", "Мой конфиг"),
            })
            configNameBox = nameControl.Box
            profiles:Button({
                Text = L("Save config", "Сохранить конфиг"), Icon = "save", Style = "Accent",
                Callback = function()
                    local name = configNameBox and configNameBox.Text or ""
                    if name == "" and selectedConfig then name = selectedConfig end
                    SaveProfile(name)
                end,
            })
            profiles:Divider()
            profiles:Dropdown({
                Text = L("Saved configs", "Сохранённые конфиги"),
                Options = function()
                    local list = {}
                    for _, name in ipairs(ListConfigs()) do table.insert(list, { value = name, text = name }) end
                    return list
                end,
                Get = function() return selectedConfig end,
                Set = function(name) selectedConfig = name end,
            })
            profiles:Button({
                Text = L("Load selected", "Загрузить выбранный"), Icon = "download",
                Callback = function() LoadProfile(selectedConfig) end,
            })
            profiles:Button({
                Text = L("Delete selected", "Удалить выбранный"), Icon = "trash", Style = "Danger", DoubleClick = true,
                Callback = function() DeleteProfile(selectedConfig) end,
            })
        else
            profiles:Paragraph({
                Text = L("Your executor does not support file access, so named configs are unavailable. The current settings are still saved automatically.",
                    "Твой executor не поддерживает работу с файлами, поэтому именные конфиги недоступны. Текущие настройки всё равно сохраняются автоматически."),
            })
        end
    end

    -- Settings / Configs: состояние файла настроек
    do
        local status = TabMisc:Section({ Title = L("Settings file", "Файл настроек"), Sub = "configs", Col = 2 })
        status:Value({
            Text = L("Last save", "Последнее сохранение"),
            Get = function()
                if ConfigStatus.at == 0 then return T(L("not saved yet", "ещё не сохранялось")) end
                if ConfigStatus.ok then return os.date("%H:%M:%S", ConfigStatus.at) end
                return T(L("error", "ошибка"))
            end,
        })
        status:Value({
            Text = L("Details", "Подробности"),
            Get = function() return (ConfigStatus.ok == false and ConfigStatus.text ~= "") and ConfigStatus.text or "-" end,
        })
        status:Button({
            Text = L("Save settings now", "Сохранить настройки сейчас"), Icon = "save",
            Callback = function()
                SaveConfig()
                if ConfigStatus.ok then
                    Notify(L("Settings saved", "Настройки сохранены"), nil, "success")
                else
                    Notify(L("Could not save settings", "Не удалось сохранить настройки"), ConfigStatus.text, "error")
                end
            end,
        })
    end



    -- HUD
    do
        local general = TabHud:Section({ Title = L("General", "Общее"), Col = 1 })
        general:Dropdown({
            Text = L("UI scale", "Масштаб интерфейса"), Pref = "uiScale", Options = SCALE_MODES,
            Callback = function() ApplyScale() end,
        })
        general:Button({
            RowLabel = L("Panel positions", "Положение панелей"), Text = L("Reset", "Сбросить"),
            Callback = function()
                Appearance.resetPanels()
                Notify(L("Panel positions reset", "Положение панелей сброшено"), nil, "success")
            end,
        })

        local watermark = TabHud:Section({ Title = L("Watermark", "Ватермарк"), Col = 1 })
        watermark:Toggle({
            Text = L("Watermark", "Ватермарк"), Pref = "watermark", Callback = function() Appearance.hud() end,
            Gear = function(pop)
                pop:Toggle({ Text = L("Show FPS", "Показывать FPS"), Pref = "wmFps", Callback = function() Appearance.hud() end })
                pop:Toggle({ Text = L("Show ping", "Показывать пинг"), Pref = "wmPing", Callback = function() Appearance.hud() end })
                pop:Toggle({ Text = L("Show time", "Показывать время"), Pref = "wmTime", Callback = function() Appearance.hud() end })
            end,
        })

        local indicators = TabHud:Section({ Title = L("Indicators", "Индикаторы"), Col = 1 })
        indicators:Toggle({
            Text = L("Keybinds", "Список функций"), Pref = "keybinds", Callback = function() Appearance.hud() end,
            Tip = L("Shows the menu key and the features that are on", "Показывает клавишу меню и включённые функции"),
            Gear = function(pop)
                pop:Toggle({ Text = L("Only active features", "Только включённые"), Pref = "kbActiveOnly", Callback = function() Appearance.hud() end })
            end,
        })
        indicators:Toggle({
            Text = L("Crosshair", "Прицел"), Pref = "crosshair", Callback = function() Appearance.hud() end,
            GearWidth = 270,
            Gear = function(pop)
                pop:Dropdown({
                    Text = L("Style", "Стиль"), Pref = "chStyle", Callback = function() Appearance.hud() end,
                    Options = {
                        { value = "Cross", text = L("Cross", "Крест") },
                        { value = "T", text = L("T-shape", "Т-образный") },
                        { value = "Dot", text = L("Dot", "Точка") },
                    },
                })
                pop:Slider({ Text = L("Length", "Длина"), Pref = "chSize", Min = 2, Max = 40, Suffix = " px", Callback = function() Appearance.hud() end })
                pop:Slider({ Text = L("Thickness", "Толщина"), Pref = "chThick", Min = 1, Max = 8, Suffix = " px", Callback = function() Appearance.hud() end })
                pop:Slider({ Text = L("Gap", "Зазор"), Pref = "chGap", Min = 0, Max = 30, Suffix = " px", Callback = function() Appearance.hud() end })
                pop:Toggle({ Text = L("Center dot", "Точка в центре"), Pref = "chDot", Callback = function() Appearance.hud() end })
                pop:Toggle({ Text = L("Outline", "Обводка"), Pref = "chOutline", Callback = function() Appearance.hud() end })
                pop:Colorpicker({
                    Text = L("Color", "Цвет"),
                    Get = function() return SafeHex(Pref("chColour"), UI_DEFAULTS.chColour) end,
                    Set = function(color)
                        SetPref("chColour", color:ToHex())
                        Appearance.hud()
                    end,
                })
            end,
        })

        local info = TabHud:Section({ Title = L("Info", "Информация"), Col = 2 })
        info:Toggle({ Text = L("FPS graph", "График FPS"), Pref = "fpsGraph", Callback = function() Appearance.hud() end })
        info:Toggle({ Text = L("Ping graph", "График пинга"), Pref = "pingGraph", Callback = function() Appearance.hud() end })
        info:Toggle({ Text = L("Speed graph", "График скорости"), Pref = "speedGraph", Callback = function() Appearance.hud() end })
        info:Toggle({
            Text = L("Game log", "Лог игры"), Pref = "gameLog", Callback = function() Appearance.hud() end,
            Gear = function(pop)
                pop:Slider({ Text = L("Lines", "Строк"), Pref = "logLines", Min = 3, Max = 12, Callback = function() Appearance.hud() end })
            end,
        })

        local world = TabHud:Section({ Title = L("World", "Мир"), Col = 2 })
        world:Toggle({
            Text = L("Enemy names", "Имена игроков"), Esp = "name",
            Tip = L("Shows player names above them (needs ESP enabled)", "Показывает имена игроков над ними (нужен включённый ESP)"),
        })

        local appearance = TabHud:Section({ Title = L("Appearance", "Внешний вид"), Col = 3 })
        local colorOptions = {}
        for _, base in ipairs(THEME_BASES) do table.insert(colorOptions, { value = base[1], text = base[1] }) end
        appearance:Dropdown({
            Text = L("Colors", "Цвета"), Options = colorOptions,
            Get = function() return Theme.base end,
            Set = function(name)
                SetPref("base", name)
                Appearance.theme()
            end,
            Callback = function() SyncAll() end,
        })
        appearance:Dropdown({
            Text = L("Language", "Язык"), Setting = "Language",
            Options = { { value = "en", text = "English" }, { value = "ru", text = "Русский" }, { value = "cs", text = "Čeština" } },
            Callback = function() ApplyLanguage() end,
        })
        appearance:Toggle({ Text = L("Animations", "Анимации"), Pref = "motion" })

        local about = TabHud:Section({ Title = L("About", "О скрипте"), Col = 3 })
        about:Value({ Text = L("Version", "Версия"), Get = function() return VERSION end })
        about:Value({ Text = L("Build", "Билд"), Get = function() return BUILD_DATE end })
    end

    -- ==========================================================
    -- 5.16 Нижняя панель, Discord, запуск
    -- ==========================================================
    Track(SaveButton.MouseButton1Click:Connect(function()
        SaveConfig()
        if ConfigStatus.ok then
            Notify(L("Settings saved", "Настройки сохранены"), nil, "success")
        else
            Notify(L("Could not save settings", "Не удалось сохранить настройки"), ConfigStatus.text, "error")
        end
    end))
    Track(FoldersButton.MouseButton1Click:Connect(function() SelectTab(TabMisc, "configs") end))
    Track(InfoButton.MouseButton1Click:Connect(function() SelectTab(TabHud) end))
    Track(DiscordButton.MouseButton1Click:Connect(function()
        if DISCORD_INVITE == "" then
            Notify(L("Discord link is not set yet", "Ссылка на Discord ещё не задана"), nil, "warning")
            return
        end
        -- открываем в браузере, если экзекутор умеет; иначе копируем
        local open = rawget(_G, "requestOpenUrl") or rawget(_G, "openurl") or (fluxus and fluxus.openurl)
        if open then
            pcall(open, DISCORD_INVITE)
            Notify(L("Discord opened in your browser", "Discord открыт в браузере"), DISCORD_INVITE, "success")
            return
        end
        local copy = setclipboard or toclipboard
        if copy then
            pcall(copy, DISCORD_INVITE)
            Notify(L("Discord link copied", "Ссылка на Discord скопирована"), nil, "success")
        else
            Notify(L("Discord", "Discord"), DISCORD_INVITE, "info", 8)
        end
    end))
    for _, tab in ipairs(UI.Tabs) do
        AttachTip(tab.Button, tab.def.name)
    end
    AttachTip(SearchButton, L("Search", "Поиск"))
    AttachTip(SaveButton, L("Save settings", "Сохранить настройки"))
    AttachTip(FoldersButton, L("Configs", "Конфиги"))
    AttachTip(InfoButton, L("About", "О скрипте"))
    AttachTip(DiscordButton, L("Join our Discord", "Наш Discord-сервер"))

    Visual.refreshUI = function() SyncAll() end

    Appearance.all()
    LayoutPages()
    SelectTab(TabFarm)
    ApplyLanguage()

    -- Обновление значений в меню
    task.spawn(function()
        while Alive() and task.wait(0.5) do
            if isOpen then
                for _, update in ipairs(UI.Values) do pcall(update) end
            end
        end
    end)
end

BuildUI()

-- ==========================================
-- 6. Anti-Fling
-- ==========================================
local MAX_HORIZONTAL_SPEED = 60 -- обычная скорость ходьбы ~16
local MAX_UP_SPEED = 80         -- прыжок даёт ~50
local MAX_SPIN = 30
local VOID_MARGIN = 100         -- запас над высотой, на которой игра убивает

local LastSafeCFrame = nil
local lastSafeSave = 0
local AntiFlingCollisionOriginal = setmetatable({}, { __mode = "k" })
local AntiFlingCache = {}   -- [player] = { character = char, parts = {...} }
local AntiFlingScanAt = 0

local function RestoreAntiFlingCollisions()
    for part, original in pairs(AntiFlingCollisionOriginal) do
        pcall(function()
            if part and part.Parent then part.CanCollide = original end
        end)
        AntiFlingCollisionOriginal[part] = nil
    end
end
_G.YozoraHub_AntiFlingRestore = RestoreAntiFlingCollisions

Track(LocalPlayer.CharacterAdded:Connect(function()
    LastSafeCFrame = nil
end))

Track(RunService.Stepped:Connect(function()
    if not Settings.AntiFling then
        RestoreAntiFlingCollisions()
        return
    end

    -- Кэш частей чужих персонажей: пересканируем 5 раз/сек вместо
    -- GetDescendants() на каждом Stepped (нагрузка при большом онлайне).
    -- Пересборка — при смене персонажа, изменении числа детей (новый
    -- аксессуар) или «протухании» закэшированных частей.
    local scanNow = os.clock()
    if scanNow - AntiFlingScanAt > 0.2 then
        AntiFlingScanAt = scanNow
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player ~= LocalPlayer and player.Character or nil
            local cache = character and AntiFlingCache[player]
            if character then
                local rebuild = not cache or cache.character ~= character
                    or #character:GetChildren() ~= cache.childCount
                if not rebuild then
                    for _, part in ipairs(cache.parts) do
                        if not part.Parent then
                            rebuild = true
                            break
                        end
                    end
                end
                if rebuild then
                    local parts = {}
                    for _, part in ipairs(character:GetDescendants()) do
                        if part:IsA("BasePart") then
                            table.insert(parts, part)
                            if AntiFlingCollisionOriginal[part] == nil then
                                AntiFlingCollisionOriginal[part] = part.CanCollide
                            end
                        end
                    end
                    AntiFlingCache[player] = { character = character, parts = parts, childCount = #character:GetChildren() }
                end
            else
                AntiFlingCache[player] = nil
            end
        end
    end
    for player, cache in pairs(AntiFlingCache) do
        if cache.character == player.Character then
            for _, part in ipairs(cache.parts) do
                if part.Parent then
                    if AntiFlingCollisionOriginal[part] == nil then
                        AntiFlingCollisionOriginal[part] = part.CanCollide
                    end
                    if part.CanCollide then part.CanCollide = false end
                end
            end
        else
            AntiFlingCache[player] = nil
        end
    end

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not (root and humanoid and humanoid.Health > 0) then return end

    -- 2. Гасим аномальную скорость и вращение
    local vel = root.AssemblyLinearVelocity
    local horizontal = Vector3.new(vel.X, 0, vel.Z).Magnitude
    if horizontal > MAX_HORIZONTAL_SPEED
        or vel.Y > MAX_UP_SPEED
        or root.AssemblyAngularVelocity.Magnitude > MAX_SPIN then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end

    -- 3. Если всё же улетели к бездне, возвращаем на последнюю безопасную точку
    local now = os.clock()
    if root.Position.Y < workspace.FallenPartsDestroyHeight + VOID_MARGIN then
        if LastSafeCFrame then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = LastSafeCFrame
        end
    elseif humanoid.FloorMaterial ~= Enum.Material.Air and now - lastSafeSave > 0.5 then
        LastSafeCFrame = root.CFrame
        lastSafeSave = now
    end
end))

-- ==========================================
-- 7. Anti-AFK
-- ==========================================
Track(LocalPlayer.Idled:Connect(function()
    if not Settings.AntiAFK then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.zero)
    end)
end))

-- ==========================================
-- 7.5 Игрок: движение, прыжок, полёт, видимость
-- ==========================================
-- Всё обратимо: при выключении тумблера и при выгрузке скрипта значения
-- возвращаются к исходным (кэши с weak-ключами, мёртвые части пропускаются).
do
    local player = LocalPlayer

    local function Character()
        local character = player.Character
        if character and character.Parent then return character end
        return nil
    end

    local function Humanoid(character)
        character = character or Character()
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then return humanoid end
        return nil
    end

    local function Root(character)
        character = character or Character()
        return character and character:FindFirstChild("HumanoidRootPart")
    end

    -- ---------- No Clip ----------
    local noClipOriginal = setmetatable({}, { __mode = "k" })

    local function applyNoClip()
        local character = Character()
        if not character then return end
        for _, item in ipairs(character:GetDescendants()) do
            if item:IsA("BasePart") then
                if noClipOriginal[item] == nil then noClipOriginal[item] = item.CanCollide end
                if item.CanCollide then item.CanCollide = false end
            end
        end
    end

    local function restoreNoClip()
        for part, original in pairs(noClipOriginal) do
            pcall(function()
                if part and part.Parent then part.CanCollide = original end
            end)
            noClipOriginal[part] = nil
        end
    end

    -- ---------- Невидимость ----------
    local invisOriginal = setmetatable({}, { __mode = "k" })

    local function applyInvisible()
        local character = Character()
        if not character then return end
        for _, item in ipairs(character:GetDescendants()) do
            if item:IsA("BasePart") or item:IsA("Decal") then
                if invisOriginal[item] == nil then invisOriginal[item] = item.Transparency end
                if item.Transparency ~= 1 then item.Transparency = 1 end
            end
        end
    end

    local function restoreInvisible()
        for item, original in pairs(invisOriginal) do
            pcall(function()
                if item and item.Parent then item.Transparency = original end
            end)
            invisOriginal[item] = nil
        end
    end

    -- ---------- X-Ray (силуэты сквозь стены) ----------
    local xrayHighlights = {}

    local function destroyHighlight(character)
        local highlight = xrayHighlights[character]
        if highlight then
            pcall(function() highlight:Destroy() end)
            xrayHighlights[character] = nil
        end
    end

    local function xrayTick()
        local seen = {}
        for _, other in ipairs(Players:GetPlayers()) do
            if other ~= player then
                local character = other.Character
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    seen[character] = true
                    local highlight = xrayHighlights[character]
                    if not highlight or highlight.Parent ~= character then
                        destroyHighlight(character)
                        highlight = Instance.new("Highlight")
                        highlight.Name = "YozoraHub_XRay"
                        highlight.FillColor = Color3.fromRGB(0, 200, 255)
                        highlight.FillTransparency = 0.55
                        highlight.OutlineColor = Color3.fromRGB(190, 240, 255)
                        highlight.OutlineTransparency = 0.1
                        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        highlight.Adornee = character
                        highlight.Parent = character
                        xrayHighlights[character] = highlight
                    end
                end
            end
        end
        for character in pairs(xrayHighlights) do
            if not seen[character] then destroyHighlight(character) end
        end
    end

    local function xrayClear()
        for character in pairs(xrayHighlights) do destroyHighlight(character) end
    end

    -- ---------- Полёт ----------
    local flyVelocity, flyGyro, flyPlatformOriginal

    local function flyStop()
        if flyVelocity then pcall(function() flyVelocity:Destroy() end) flyVelocity = nil end
        if flyGyro then pcall(function() flyGyro:Destroy() end) flyGyro = nil end
        local humanoid = Humanoid()
        if humanoid and flyPlatformOriginal ~= nil then
            pcall(function() humanoid.PlatformStand = flyPlatformOriginal end)
        end
        flyPlatformOriginal = nil
    end

    local function flyStep()
        local humanoid, root = Humanoid(), Root()
        if not (humanoid and root) then return end

        if not flyVelocity or flyVelocity.Parent ~= root then
            if flyVelocity then pcall(function() flyVelocity:Destroy() end) end
            if flyGyro then pcall(function() flyGyro:Destroy() end) end
            flyVelocity = Instance.new("BodyVelocity")
            flyVelocity.Name = "YozoraFlyBV"
            flyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            flyVelocity.P = 1250
            flyVelocity.Velocity = Vector3.zero
            flyVelocity.Parent = root
            flyGyro = Instance.new("BodyGyro")
            flyGyro.Name = "YozoraFlyBG"
            flyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
            flyGyro.P = 8000
            flyGyro.D = 800
            flyGyro.CFrame = root.CFrame
            flyGyro.Parent = root
        end

        if flyPlatformOriginal == nil then flyPlatformOriginal = humanoid.PlatformStand end
        humanoid.PlatformStand = true

        local camera = workspace.CurrentCamera
        local move = Vector3.zero
        if camera then
            local forward = camera.CFrame.LookVector
            local right = camera.CFrame.RightVector
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += forward end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= forward end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
            flyGyro.CFrame = camera.CFrame
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then move -= Vector3.yAxis end

        local speed = tonumber(Settings.FlySpeed) or 45
        flyVelocity.Velocity = move.Magnitude > 0.01 and move.Unit * speed or Vector3.zero
    end

    -- ---------- Вращение ----------
    local spinAngle = 0

    local function spinStep(dt)
        local root = Root()
        if not root then return end
        spinAngle = (spinAngle + dt * 6) % (math.pi * 2)
        root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, spinAngle, 0)
    end

    -- ---------- Прыжки: бесконечные, от стены, спид-глитч ----------
    local wallParams = RaycastParams.new()
    wallParams.FilterType = Enum.RaycastFilterType.Exclude

    Track(UserInputService.JumpRequest:Connect(function()
        if not Alive() then return end
        local humanoid, root = Humanoid(), Root()
        if not (humanoid and root) then return end
        if humanoid.FloorMaterial ~= Enum.Material.Air then return end -- только в воздухе

        if Settings.InfiniteJumps then
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            local velocity = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(velocity.X, math.max(velocity.Y, 50), velocity.Z)
        end

        if Settings.WallHop then
            local character = Character()
            wallParams.FilterDescendantsInstances = character and { character } or {}
            local found = false
            for _, direction in ipairs({
                root.CFrame.LookVector, -root.CFrame.LookVector,
                root.CFrame.RightVector, -root.CFrame.RightVector,
            }) do
                if workspace:Raycast(root.Position, direction * 3, wallParams) then
                    found = true
                    break
                end
            end
            if found then
                local velocity = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = Vector3.new(velocity.X, math.max(velocity.Y, 55), velocity.Z)
            end
        end

        if Settings.SpeedGlitch then
            local direction = humanoid.MoveDirection
            if direction.Magnitude > 0.1 then
                root.AssemblyLinearVelocity += direction.Unit * 22
            end
        end
    end))

    -- ---------- Основной цикл ----------
    local state = { noClip = false, invisible = false, xray = false, fly = false }
    local nextNoClip, nextInvisible, nextXray, nextBhop = 0, 0, 0, 0

    local function syncBaseStats()
        local humanoid = Humanoid()
        if humanoid then
            local speed = tonumber(Settings.PlayerSpeed) or 16
            if math.abs(humanoid.WalkSpeed - speed) > 0.01 then humanoid.WalkSpeed = speed end
            local jump = tonumber(Settings.PlayerJump) or 50
            if not humanoid.UseJumpPower then humanoid.UseJumpPower = true end
            if math.abs((humanoid.JumpPower or 0) - jump) > 0.01 then humanoid.JumpPower = jump end
        end
        local gravity = tonumber(Settings.PlayerGravity) or 196.2
        if math.abs(workspace.Gravity - gravity) > 0.01 then workspace.Gravity = gravity end
    end

    Track(RunService.Heartbeat:Connect(function(dt)
        if not Alive() then return end
        local now = os.clock()
        syncBaseStats()

        if Settings.NoClip ~= state.noClip then
            state.noClip = Settings.NoClip
            if not state.noClip then restoreNoClip() end
        end
        if state.noClip and now - nextNoClip > 0.2 then
            nextNoClip = now
            applyNoClip()
        end

        if Settings.Invisible ~= state.invisible then
            state.invisible = Settings.Invisible
            if not state.invisible then restoreInvisible() end
        end
        if state.invisible and now - nextInvisible > 0.25 then
            nextInvisible = now
            applyInvisible()
        end

        if Settings.XRay ~= state.xray then
            state.xray = Settings.XRay
            if not state.xray then xrayClear() end
        end
        if state.xray and now - nextXray > 0.5 then
            nextXray = now
            xrayTick()
        end

        if Settings.Fly then
            flyStep()
        elseif state.fly then
            flyStop()
        end
        state.fly = Settings.Fly

        if Settings.Bhop then
            local humanoid = Humanoid()
            if humanoid and now - nextBhop > 0.12 then
                nextBhop = now
                if humanoid.FloorMaterial ~= Enum.Material.Air then
                    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end
        end

        if Settings.Spin then spinStep(dt) end
    end))

    _G.YozoraHub_PlayerRestore = function()
        restoreNoClip()
        restoreInvisible()
        xrayClear()
        flyStop()
        local humanoid = Humanoid()
        if humanoid then
            pcall(function()
                humanoid.WalkSpeed = 16
                humanoid.UseJumpPower = true
                humanoid.JumpPower = 50
            end)
        end
        pcall(function() workspace.Gravity = 196.2 end)
    end
end

-- ==========================================
-- 8. Состояние раунда (события игры)
-- ==========================================
-- Раунд, мешок и счётчик берём из событий самой игры
-- (ReplicatedStorage.Remotes.Gameplay). Так считаются только монеты,
-- которые сервер реально засчитал, и точно известно, когда мешок полон.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundState = {
    round = false,
    coinsStarted = 0,    -- когда начался сбор монет (0 = ещё не начался)
    knownRound = false,
    forcedFull = false,  -- после нашего респавна мешок считается полным до нового раунда
    collected = {},      -- [тип монеты] = последнее значение счётчика игры
    full = {},           -- [тип монеты] = мешок этого типа полон
    skipped = {}, -- монеты, которые не удалось подобрать
    active = false,      -- мы живы и участвуем в раунде
    firstJump = true,    -- в начале раунда первый прыжок к монете разрешён всегда
    eventsReady = false,
    dirty = false,
    bag = nil, bagItems = {}, bagAt = 0,
    roundCollected = 0,  -- сколько монет засчитано в этом раунде (по событиям игры)
    roundStartedAt = 0,  -- когда начался раунд (0 = неизвестно)
    needFresh = false,   -- после конца раунда запоминаем старые контейнеры монет
    stale = nil,         -- контейнеры, оставшиеся от прошлого раунда (их игнорируем)
}

local ResetMotionHook -- задаётся в секции Auto Farm
local RolesInvalidate -- задаётся в секции ролей

local function RoundStart(coinsStarted)
    RoundState.round = true
    RoundState.skipped = {}
    if not coinsStarted then
        RoundState.collected = {}
    end
    table.clear(RoundState.full)
    RoundState.forcedFull = false
    RoundState.coinsStarted = coinsStarted and os.clock() or 0
    RoundState.knownRound = true
    RoundState.firstJump = true
    RoundState.stale, RoundState.needFresh = nil, false
    -- безопасная позиция прошлого раунда могла быть в опасном месте нового
    LastSafeCFrame = nil
    lastSafeSave = 0
    if not coinsStarted then
        GameLog(L("Round started", "Раунд начался"))
        RoundState.roundCollected = 0
        RoundState.roundStartedAt = os.clock()
        -- роли прошлого раунда устарели: ждём свежие данные
        if RolesInvalidate then RolesInvalidate() end
    elseif RoundState.roundStartedAt == 0 then
        RoundState.roundStartedAt = os.clock()
    end
    if ResetMotionHook then ResetMotionHook() end
end

local function RoundEnd()
    GameLog(L("Round ended", "Раунд закончился"))
    RoundState.round = false
    RoundState.collected = {}
    RoundState.forcedFull = false
    RoundState.coinsStarted = 0
    -- ничего не должно "дожить" до следующего раунда (иначе в начале раунда мешок считался бы полным)
    table.clear(RoundState.full)
    RoundState.roundCollected = 0
    RoundState.roundStartedAt = 0
    RoundState.needFresh = true
    if RolesInvalidate then RolesInvalidate() end
end

local function OnCoinCollected(kind, count, maximum)
    if RoundState.coinsStarted == 0 then
        RoundState.coinsStarted = os.clock()
    end
    if type(kind) == "string" and type(count) == "number" and type(maximum) == "number" then
        RoundState.full[kind] = count >= maximum
    end

    local name = type(kind) == "string" and kind or "Coin"
    local previous = RoundState.collected[name] or 0
    -- зашли посреди раунда: считаем с текущего значения, а не с нуля
    if not RoundState.knownRound and RoundState.collected[name] == nil
        and type(count) == "number" and count > 1 then
        previous = count - 1
    end

    local added = 1
    if type(count) == "number" then
        added = count >= previous and count - previous or count
        RoundState.collected[name] = count
    end
    if added > 0 then
        Stats.Session += added
        Settings.TotalCoins += added
        RoundState.roundCollected += added
        RoundState.dirty = true
    end
    if RoundState.roundStartedAt == 0 then RoundState.roundStartedAt = os.clock() end
end

task.spawn(function()
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 20)
    local gameplay = remotes and remotes:WaitForChild("Gameplay", 20)
    if not gameplay or not Alive() then
        warn("[Yozora Hub] Remotes.Gameplay not found: coin counter works in approximate mode")
        return
    end

    local function listen(name, callback)
        local remote = gameplay:FindFirstChild(name)
        if remote and remote:IsA("RemoteEvent") then
            Track(remote.OnClientEvent:Connect(callback))
            return true
        end
        return false
    end

    listen("RoundStart", function() RoundStart(false) end)
    listen("CoinsStarted", function() RoundStart(true) end)
    listen("RoundEndFade", RoundEnd)
    RoundState.eventsReady = listen("CoinCollected", OnCoinCollected)

    print("[Yozora Hub] Game events: " .. (RoundState.eventsReady and "connected" or "CoinCollected not found"))
end)

-- Запасной признак "мешок полон": значок Full в интерфейсе игры
local function RefreshBag()
    RoundState.bagAt = os.clock()
    RoundState.bagItems = {}
    local main = PlayerGui:FindFirstChild("MainGUI")
    local gameGui = main and main:FindFirstChild("Game")
    RoundState.bag = gameGui and gameGui:FindFirstChild("CoinBags") or nil
    if not RoundState.bag then return end
    for _, item in ipairs(RoundState.bag:GetDescendants()) do
        if item.Name == "Full" and item:IsA("GuiObject")
            and not item:FindFirstAncestorWhichIsA("LuaSourceContainer") then
            table.insert(RoundState.bagItems, item)
        end
    end
end

local function IsBagFull()
    if RoundState.forcedFull then return true end
    if RoundState.coinsStarted == 0 then return false end

    -- все известные типы монет полны (например, и монеты, и конфеты);
    -- флаги приходят только вместе с событием CoinCollected этого раунда
    local any, all = false, true
    for _, full in pairs(RoundState.full) do
        any = true
        if not full then all = false end
    end
    if any and all and RoundState.roundCollected > 0 then return true end

    -- запасной признак по интерфейсу: не раньше чем через 6 секунд после начала сбора и
    -- только если мы уже что-то собрали (или события игры недоступны)
    if os.clock() - RoundState.coinsStarted < 6 then return false end
    if RoundState.eventsReady and RoundState.roundCollected == 0 then return false end
    if not RoundState.bag or not RoundState.bag.Parent or os.clock() - RoundState.bagAt > 2 then
        RefreshBag()
    end
    local bag = RoundState.bag
    if not bag or (bag:IsA("GuiObject") and not bag.Visible) then return false end
    for _, item in ipairs(RoundState.bagItems) do
        if item.Parent and item.Visible then return true end
    end
    return false
end

-- Контейнеры с монетами: дети workspace + всё, что помечено тегом ServerCoinPart
local containers, containersAt = {}, 0

local function GetContainers()
    local now = os.clock()
    if now - containersAt < 0.5 then return containers end
    containersAt = now

    local list, seen = {}, {}
    for _, object in ipairs(workspace:GetChildren()) do
        local container = object:FindFirstChild("CoinContainer")
        if container and not seen[container] then
            seen[container] = true
            table.insert(list, container)
        end
    end
    for _, coin in ipairs(CollectionService:GetTagged("ServerCoinPart")) do
        local container = coin.Parent
        if container and not seen[container] and container ~= workspace
            and container:IsDescendantOf(workspace) then
            seen[container] = true
            table.insert(list, container)
        end
    end
    containers = list
    return list
end

-- Если монеты уже есть на карте, считаем, что раунд идёт
-- (контейнеры, оставшиеся от прошлого раунда после его конца, игнорируем)
task.spawn(function()
    while Alive() and task.wait(0.5) do
        local containers = GetContainers()
        if RoundState.needFresh then
            RoundState.stale = {}
            for _, container in ipairs(containers) do RoundState.stale[container] = true end
            RoundState.needFresh = false
        end
        for _, container in ipairs(containers) do
            local stale = RoundState.stale and RoundState.stale[container]
            if container.Parent and not stale and #container:GetChildren() > 0 then
                if RoundState.coinsStarted == 0 then
                    RoundState.coinsStarted = os.clock()
                end
                if RoundState.roundStartedAt == 0 then
                    RoundState.roundStartedAt = os.clock()
                end
                if not RoundState.round then
                    RoundState.round = true
                    RoundState.firstJump = true
                end
                break
            end
        end
    end
end)

-- Сохраняем общий счётчик раз в 5 секунд, а не при каждой монете
task.spawn(function()
    while Alive() and task.wait(5) do
        if RoundState.dirty then
            RoundState.dirty = false
            SaveConfig()
        end
    end
end)

-- Монет в час (по времени, пока автофарм включён)
task.spawn(function()
    local history, elapsed, last = {}, 0, os.clock()
    while Alive() do
        local now = os.clock()
        if Settings.AutoFarm then
            elapsed += math.min(now - last, 10)
            table.insert(history, { elapsed, Stats.Session })
            while #history > 2 and elapsed - history[1][1] > 3600 do
                table.remove(history, 1)
            end
            local interval = history[#history][1] - history[1][1]
            if interval >= 30 then
                Stats.Rate = math.max(0, math.floor((history[#history][2] - history[1][2]) / interval * 3600 + 0.5))
            end
        end
        task.wait(2)
        last = now
    end
end)

-- ==========================================
-- 9. Роли игроков
-- ==========================================
-- Роли берём у игры (RemoteFunction GetPlayerData), чтобы знать убийцу, даже
-- пока нож лежит в рюкзаке. Если не получилось, определяем по ножу.
local Roles = { data = nil, remote = nil, lastFind = 0, fetched = false, fails = 0, since = os.clock(),
    lastGood = nil, lastGoodAt = 0 }
local function FindRolesRemote()
    if Roles.remote and Roles.remote.Parent then return Roles.remote end
    if os.clock() - Roles.lastFind < 5 then return nil end
    Roles.lastFind = os.clock()
    local remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
    if remote and remote:IsA("RemoteFunction") then
        Roles.remote = remote
        return remote
    end
    return nil
end

-- Данные ролей запрашиваем сразу при запуске и сразу после смены раунда (пока их нет, фарм ждёт)
RolesInvalidate = function()
    Roles.data, Roles.fetched, Roles.since, Roles.fails = nil, false, os.clock(), 0
    -- новый раунд = новые роли: старый кэш не должен переживать смену
    Roles.lastGood, Roles.lastGoodAt = nil, 0
end

-- Некоторые версии игры возвращают обёртку { data = {...} } / { players = {...} }
local function UnwrapRoles(result)
    if type(result) ~= "table" then return nil end
    if type(result.data) == "table" then return result.data end
    if type(result.Players) == "table" then return result.Players end
    if type(result.players) == "table" then return result.players end
    return result
end

task.spawn(function()
    while Alive() do
        if Settings.AutoFarm or Settings.ESP or CombatWanted() then
            local remote = FindRolesRemote()
            if remote then
                local ok, result = pcall(function()
                    return remote:InvokeServer()
                end)
                if ok and type(result) == "table" then
                    Roles.data, Roles.fetched, Roles.fails = UnwrapRoles(result), true, 0
                    Roles.lastGood, Roles.lastGoodAt = Roles.data, os.clock()
                else
                    Roles.fails = (Roles.fails or 0) + 1
                    -- неудача запроса: до 5 с держим последние валидные роли,
                    -- чтобы ESP/фарм не мигали при сбоях сети
                    if Roles.lastGood and os.clock() - Roles.lastGoodAt < 5 then
                        Roles.data = Roles.lastGood
                    else
                        Roles.data = nil
                    end
                end
            else
                Roles.fails = (Roles.fails or 0) + 1
                if Roles.lastGood and os.clock() - Roles.lastGoodAt < 5 then
                    Roles.data = Roles.lastGood
                else
                    Roles.data = nil
                end
            end
        end
        -- бэкофф: пока данных нет, интервал растёт от 0.3с до 3с, чтобы
        -- не долбить ремоут при ошибках; при успехе — раз в 3с
        -- (мгновенные обновления приходят через PlayerDataChanged)
        if Roles.fetched then
            task.wait(3)
        else
            task.wait(math.min(0.3 * ((Roles.fails or 0) + 1), 3))
        end
    end
end)

-- Мгновенное обновление ролей по событию игры: PlayerDataChanged приходит
-- при выдаче/смене ролей — заставляем цикл перезапросить данные сразу
task.spawn(function()
    local ok, gameplay = pcall(function()
        return ReplicatedStorage:WaitForChild("Remotes", 15):WaitForChild("Gameplay", 10)
    end)
    local changed = ok and gameplay and gameplay:FindFirstChild("PlayerDataChanged")
    if changed and changed:IsA("RemoteEvent") then
        Track(changed.OnClientEvent:Connect(function()
            Roles.since = os.clock()
            Roles.fetched = false
        end))
    end
end)

-- Нож В ПЕРСОНАЖЕ (экипирован, не в рюкзаке): во время раунда экипированный
-- нож только у убийцы (ножи-скины в лобби все носят в рюкзаке)
local function CarriesKnife(player)
    local character = player.Character
    if not character then return false end
    local knife = character:FindFirstChild("Knife")
    if knife and knife:IsA("Tool") then return true end
    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") and CollectionService:HasTag(tool, "Weapon_Knife") then
            return true
        end
    end
    return false
end

local function IsMurdererPlayer(player)
    local data = Roles.data
    local role = type(data) == "table" and data[player.Name] or nil
    if role and role.Role then
        return tostring(role.Role):lower():find("murder") ~= nil
    end
    return CarriesKnife(player)
end

-- "unknown" (нет данных) / "none" (не в раунде) / "dead" / "alive"
local function LocalRoleState()
    local data = Roles.data
    if type(data) ~= "table" then
        -- данные ещё не получены: до 8 секунд ждём ("pending"), потом считаем, что ролей нет ("unknown")
        local searching = Roles.remote ~= nil or Roles.lastFind == 0
        if searching and os.clock() - Roles.since < 8 then return "pending", nil end
        return "unknown", nil
    end
    local role = data[LocalPlayer.Name]
    if not role or not role.Role then return "none", nil end
    if role.Dead == true or role.Killed == true then return "dead", role end
    return "alive", role
end

local murdererCache, murdererTime = nil, 0

local function GetMurdererRoot()
    local now = os.clock()
    if now - murdererTime > 0.5 then
        murdererTime = now
        murdererCache = nil
        -- Данные ролей + запасной вариант «экипированный нож = убийца»
        -- (только нож В ПЕРСОНАЖЕ: ножи-скины в рюкзаке есть у всех, а вот
        -- экипированным нож во время раунда держит только убийца)
        local data = Roles.data
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local role = type(data) == "table" and data[player.Name] or nil
                local isMurderer = false
                if type(role) == "table" and role.Role then
                    isMurderer = tostring(role.Role):lower():find("murder") ~= nil
                        and role.Dead ~= true and role.Killed ~= true
                else
                    isMurderer = CarriesKnife(player)
                end
                if isMurderer then
                    murdererCache = player
                    break
                end
            end
        end
    end
    local character = murdererCache and murdererCache.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root and humanoid and humanoid.Health > 0 then
        return root
    end
    return nil
end

-- ==========================================
-- 9a. Combat: аим-движок (Silent Aim, Knife Aim, авто-выстрел)
-- ==========================================
-- Пистолет и нож работают БЕЗ namecall-хуков: на старте захватывается чистая
-- функция FireServer (dummy RemoteEvent), внутри тула отключается родной клиент
-- (GunClient / KnifeClient), и клики обрабатывает движок: предсказанная точка ->
-- прямой вызов FireServer. Авто-выстрел/авто-бросок шлют ремоуты сами по себе.
-- Окно «нож активируется изнутри» (knife:Activate() в KillAll): Tool.Activated
-- от такого Activate не должен считаться кликом игрока и бросать нож сам
local KnifeInternalUntil = 0
do
    if _G.YozoraHub_CombatStop then pcall(_G.YozoraHub_CombatStop) end

    local CoreGuiService = game:GetService("CoreGui")
    local GuiService = game:GetService("GuiService")
    local StatsService = game:GetService("Stats")

    local Engine = {
        alive = true,
        target = nil,         -- текущая цель (Player)
        pending = nil,        -- ожидание ответа GunFired (для статистики)
        echo = 0.12,          -- измеренная задержка выстрела (наш FireServer -> GunFired)
        Llearned = 0.14,      -- выученное упреждение (сек)
        cooldown = 0.9,       -- перезарядка между выстрелами (учится по эху)
        lastAccepted = 0,
        trueAccepted = 0,
        missStreak = 0,
        bypass = false,       -- passthrough для старых хуков (совместимость)
        stats = { fired = 0, hit = 0, missed = 0, thrown = 0 },
        knifeSpeed = 96,      -- скорость брошенного ножа (совместимость сохранений)
        lastThrow = 0,
        throws = 0,
        lastNoTarget = 0,
        tradeOpen = false,    -- кэш: открыт ли трейд-GUI
        tradeOpenAt = 0,
        gunTool = nil,        -- тул пистолета под takeover
        gunConnection = nil,
        gunEquipConnection = nil,
        lastSuppressCheck = 0, -- время последнего свипа подавления GunClient
        knifeTool = nil,      -- тул ножа под takeover
        knifeConnection = nil,
    }

    local function Now()
        return os.clock()
    end

    -- Пинг в секундах
    local function Ping()
        local ok, value = pcall(function()
            return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue()
        end)
        if ok and type(value) == "number" and value == value then
            return math.clamp(value / 1000, 0, 1)
        end
        local ok2, ping = pcall(function() return LocalPlayer:GetNetworkPing() end)
        return (ok2 and type(ping) == "number") and math.clamp(ping, 0, 1) or 0.1
    end

    -- ---------- Захват чистой FireServer (один раз, на старте) ----------
    local rawFireServer = nil
    do
        local ok, fn = pcall(function()
            local dummy = Instance.new("RemoteEvent")
            local fire = dummy.FireServer
            dummy:Destroy()
            return fire
        end)
        if ok and type(fn) == "function" then rawFireServer = fn end
    end

    -- Прямая отправка: сначала захваченной функцией (мимо любых namecall-хуков),
    -- запасной вариант — обычный вызов метода. Вызов синхронный: pcall видит
    -- реальный результат, и при ошибке raw-пути срабатывает фолбэк.
    local function FireRemote(remote, origin, destination)
        if rawFireServer then
            local ok = pcall(rawFireServer, remote, origin, destination)
            if ok then return true end
        end
        Engine.bypass = true
        local ok2 = pcall(function() remote:FireServer(origin, destination) end)
        Engine.bypass = false
        return ok2
    end

    -- ---------- Физ-симуляция (Revert / Flux) ----------
    -- Точная симуляция движения цели: три probe-парта + Blockcast, учёт
    -- ускорения на земле/в воздухе, прыжков, лестниц (TrussPart) и упавших
    -- частей. Портировано из эталонного движка как есть.
    local SIM_INTERVAL = 0.0125
    local SIM_MAX_TIME = 60
    local SIM_PING = 90
    local SIM_OFFSET = Vector3.zero
    local SIM_THIN = Vector3.new(2, 0.002, 1)
    local SIM_LOWER = Vector3.new(0, 2, 0)
    local SIM_UPPER = Vector3.new(0, 1.5, 0)
    local SIM_CAST = Vector3.new(0, 1.001, 0)

    -- Подстройка по горизонтали/вертикали от пинга (Remi)
    local function CalcHorizontal(value, adjustment)
        if value > 0 then return value + (adjustment + 0.075) end
        if value < 0 then return value - (adjustment - 0.075) end
        return value
    end

    local function CalcVertical(value, adjustment)
        if value > 0 then return value + adjustment end
        if value < 0 then return value - adjustment end
        return value
    end

    local function CalcElectroVertical(value)
        if value > 1 then return value - 0.15 end
        if value < -1 then return value + 0.15 end
        if value > 0 then return value + 0.05 end
        if value < 0 then return value - 0.05 end
        return value
    end

    local function SimFlatBlock(part)
        if part.ClassName ~= "Part" or part.Shape ~= Enum.PartType.Block then return false end
        local orientation = part.Orientation
        local x, z = math.abs(orientation.X), math.abs(orientation.Z)
        return (x == 0 or x == 180) and (z == 0 or z == 180)
    end

    local function SimGroundHeight(parts, position, rotation)
        local highest = nil
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        for _, part in ipairs(parts) do
            if SimFlatBlock(part) then
                local height = part.Position.Y + part.Size.Y / 2
                if height < position.Y - 1 and (not highest or highest < height) then
                    highest = height
                    continue
                end
            end
            params.FilterDescendantsInstances = { part }
            local origin = CFrame.new(position.X, position.Y - 1, position.Z) * rotation
            local ok, hit = pcall(function()
                return workspace:Blockcast(origin, SIM_THIN, Vector3.new(0, -2, 0), params)
            end)
            if ok and hit and (not highest or highest < hit.Position.Y) then highest = hit.Position.Y end
        end
        return highest
    end

    local function SimCeilingHeight(parts, position, rotation)
        local lowest = nil
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Include
        for _, part in ipairs(parts) do
            if SimFlatBlock(part) then
                local height = part.Position.Y - part.Size.Y / 2
                if position.Y + 1.9 < height and (not lowest or height < lowest) then
                    lowest = height
                    continue
                end
            end
            params.FilterDescendantsInstances = { part }
            local origin = CFrame.new(position.X, position.Y - 2, position.Z) * rotation
            local ok, hit = pcall(function()
                return workspace:Blockcast(origin, SIM_THIN, Vector3.new(0, 1, 0), params)
            end)
            if ok and hit and (not lowest or hit.Position.Y < lowest) then lowest = hit.Position.Y end
        end
        return lowest
    end

    local function SimAccelerateAxis(value, direction, unitDirection, acceleration, interval)
        local target = direction * 16
        local amount = acceleration * math.abs(direction == 0 and unitDirection or direction) * interval
        if target < value then return math.max(target, value - amount) end
        if value < target then return math.min(target, value + amount) end
        return target
    end

    local function SimColliders(parts, character, localCharacter, probes)
        local result, hasTruss = {}, false
        for _, part in ipairs(parts) do
            local isProbe = part == probes[1] or part == probes[2] or part == probes[3]
            local inTarget = character and part:IsDescendantOf(character)
            local inLocal = localCharacter and part:IsDescendantOf(localCharacter)
            if not isProbe and not inTarget and not inLocal and part.CanCollide then
                result[#result + 1] = part
                if part.ClassName == "TrussPart" then hasTruss = true end
            end
        end
        return result, hasTruss
    end

    local function SimulatePrediction(root, humanoid, hand)
        local character = root.Parent
        local localCharacter = LocalPlayer.Character
        local position, velocity = root.Position, root.AssemblyLinearVelocity
        local direction, destination = humanoid.MoveDirection, humanoid.WalkToPoint
        local handPosition = hand.Position
        local rotation = CFrame.Angles(0, root.Orientation.Y * 0.017453292519943295, 0)
        local horizontal = Vector3.new(1, 0, 1)
        local probes = {}
        do
            local shifts = { -SIM_LOWER, Vector3.zero, SIM_UPPER }
            for index = 1, 3 do
                local probe = Instance.new("Part")
                probe.Name = "\n"
                probe.Transparency = 1
                probe.Size = Vector3.new(2, 2, 1)
                probe.CFrame = CFrame.new(position + shifts[index]) * rotation
                probe.Anchored = true
                probe.Parent = workspace
                probes[index] = probe
            end
        end
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = { probes[1], probes[2], probes[3], character, localCharacter }
        params.FilterType = Enum.RaycastFilterType.Exclude
        if direction == Vector3.zero and destination ~= Vector3.zero then
            local okDir, dirVec = pcall(function()
                return CFrame.lookAt(position * horizontal, destination * horizontal).LookVector
            end)
            if okDir and dirVec then direction = dirVec end
        end

        local floor = workspace.FallenPartsDestroyHeight
        local handHorizontal = Vector2.new(handPosition.X, handPosition.Z)
        local elapsed, acceleration, step = 0, 750, SIM_INTERVAL
        local distance, elevation, previous

        local function moveProbes(target)
            probes[1].Position = target - SIM_LOWER
            probes[2].Position = target
            probes[3].Position = target + SIM_UPPER
        end

        local function contacts(probe)
            local ok, touching = pcall(function() return probe:GetTouchingParts() end)
            if not ok or not touching then return {}, false end
            return SimColliders(touching, character, localCharacter, probes)
        end

        local result = nil
        local okSim = pcall(function()
            while true do
                local adjusted = position + SIM_OFFSET
                distance = (Vector2.new(adjusted.X, adjusted.Z) - handHorizontal).Magnitude
                elevation = math.atan((adjusted.Y - handPosition.Y) / distance)
                -- эхо выстрела движок измеряет реально (FireServer -> GunFired);
                -- до первого измерения используем константу 90 мс, зажимаем в разумный диапазон
                local echoMs = Engine.echo > 0 and math.clamp(Engine.echo * 1000, 20, 500) or SIM_PING
                local duration = echoMs / 1000
                if duration - elapsed <= step then
                    step = duration - elapsed
                else
                    step = SIM_INTERVAL
                end
                previous = adjusted - SIM_OFFSET
                if duration <= elapsed or SIM_MAX_TIME <= elapsed or previous.Y <= floor then break end

                if destination ~= Vector3.zero then
                    local okDir, dirVec = pcall(function()
                        return CFrame.lookAt(root.Position * horizontal, destination * horizontal).LookVector
                    end)
                    if okDir and dirVec then direction = dirVec end
                end
                local dx, dz = direction.X, direction.Z
                position = previous + Vector3.new(
                    (velocity.X * step + acceleration * dx * step ^ 2 / 2),
                    (velocity.Y * step - 196.2 * step ^ 2 / 2),
                    (velocity.Z * step + acceleration * dz * step ^ 2 / 2))

                local unitDir = velocity.Magnitude > 0 and velocity.Unit or Vector3.zero
                local nextX = SimAccelerateAxis(velocity.X, dx, unitDir.X, acceleration, step)
                local afterX = Vector3.new(nextX, velocity.Y, velocity.Z)
                local afterUnit = afterX.Magnitude > 0 and afterX.Unit or Vector3.zero
                local nextZ = SimAccelerateAxis(afterX.Z, dz, afterUnit.Z, acceleration, step)
                velocity = Vector3.new(afterX.X, afterX.Y, nextZ) - Vector3.new(0, 196.2 * step, 0)

                local bottom = workspace:Blockcast(CFrame.new(previous - SIM_CAST) * rotation,
                    SIM_THIN, (previous - SIM_CAST) - (position - SIM_CAST), params)
                local top = workspace:Blockcast(CFrame.new(previous + SIM_CAST) * rotation,
                    SIM_THIN, (previous + SIM_CAST) - (position + SIM_CAST), params)
                if bottom and bottom.Position.Y <= previous.Y then
                    position = Vector3.new(position.X, bottom.Position.Y + 3, position.Z)
                elseif top and previous.Y <= top.Position.Y then
                    position = Vector3.new(position.X, top.Position.Y - 2, position.Z)
                end

                moveProbes(position)
                local middleParts, onTruss = contacts(probes[2])
                if #middleParts > 0 then
                    if onTruss then
                        velocity = Vector3.new(0, 16, 0)
                    else
                        local movement = CFrame.lookAt(previous, position).LookVector.Unit
                        position += Vector3.new(-movement.X, 0, 0)
                        moveProbes(position)
                        if #contacts(probes[2]) > 0 then
                            position += Vector3.new(movement.X, 0, -movement.Z)
                            moveProbes(position)
                            if #contacts(probes[2]) > 0 then position = previous end
                        end
                    end
                end

                moveProbes(position)
                local lowerParts, lowerTruss = contacts(probes[1])
                if not lowerTruss and #lowerParts > 0 and velocity.Y <= step then
                    local ground = SimGroundHeight(lowerParts, position, rotation)
                    acceleration = 142
                    if ground then
                        position = Vector3.new(position.X, ground + 3, position.Z)
                        velocity *= horizontal
                        acceleration = 750
                        if humanoid.Jump then velocity = Vector3.new(velocity.X, 50, velocity.Z) end
                    end
                end

                moveProbes(position)
                local upperParts, upperTruss = contacts(probes[3])
                if not upperTruss and #upperParts > 0 and -step <= velocity.Y then
                    local ceiling = SimCeilingHeight(upperParts, position, rotation)
                    if ceiling then
                        position = Vector3.new(position.X, ceiling - 2, position.Z)
                        velocity *= Vector3.new(1, -1, 1)
                    end
                end
                if #lowerParts == 0 and #upperParts == 0 then acceleration = 142 end
                elapsed += step
            end
            local resultPoint = previous + SIM_OFFSET
            result = Vector3.new(resultPoint.X, distance * math.tan(elevation) + handPosition.Y, resultPoint.Z)
        end)
        for _, probe in ipairs(probes) do
            pcall(function() probe:Destroy() end)
        end
        if not okSim then return nil end
        return result
    end

    -- ---------- Предсказание движения (пистолет) ----------
    -- point = позиция цели + сдвиг по скорости и направлению движения.
    -- Revert / Flux: точная физ-симуляция (Blockcast), остальные — формулы.
    local function PredictMovement(character)
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not root or not humanoid then return nil end
        local velocity = root.AssemblyLinearVelocity
        local move = humanoid.MoveDirection
        local ping = Ping() * 1000
        local mode = CombatOpt("gunPrediction")

        if mode == "Revert" or mode == "Flux" then
            -- симуляция ведётся от руки стреляющего (высота ствола влияет на траекторию)
            local myCharacter = LocalPlayer.Character
            local hand = myCharacter and (myCharacter:FindFirstChild("RightHand")
                or myCharacter:FindFirstChild("Right Arm") or myCharacter:FindFirstChild("Head"))
            hand = hand or root
            local ok, point = pcall(SimulatePrediction, root, humanoid, hand)
            if ok and point then return point end
            -- симуляция не удалась — падаем на формулу Remi
            mode = "Remi"
        end

        if not (0.19 < velocity.Magnitude) then
            return root.Position + move * 0.2
        end
        local unit = velocity.Unit
        local point = root.Position
        if mode == "Ubuntu" then
            local scaled = unit * (1.8 + ping / 15000)
            point += Vector3.new(scaled.X, math.clamp(scaled.Y, -1.8, 1.8), scaled.Z) + move * 0.7
        elseif mode == "Electro" then
            local scaled = unit * 2.05
            point += Vector3.new(scaled.X, CalcElectroVertical(scaled.Y), scaled.Z)
                + move * (0.9 + ping / 1500)
        elseif mode == "Tiancai" then
            local offset = (tonumber(CombatOpt("tiancaiOffset")) or 100) / 100
            local mx = velocity.X / 17 + move.X
            local my = math.clamp(velocity.Y / 17 + move.Y, -2, 2.5)
            local mz = velocity.Z / 17 + move.Z
            point += Vector3.new(mx, my, mz) * offset
        else -- Remi: упреждение по скорости + подстройка осей от пинга + шаг по направлению
            local scaled = unit * 2.225
            local adjustment = ping / 2500
            point += Vector3.new(
                    CalcHorizontal(scaled.X, adjustment),
                    CalcVertical(scaled.Y - 0.5, adjustment),
                    CalcHorizontal(scaled.Z, adjustment))
                + move * 0.8
        end
        return point
    end

    -- Предсказание для ножа: Dynamic (упреждение по скорости) / Instant (текущая позиция)
    local function KnifePredictPoint(character)
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then return nil end
        if CombatOpt("knifePrediction") == "Instant" then return root.Position end
        local velocity = root.AssemblyLinearVelocity
        if velocity.Magnitude < 1 then return root.Position end
        return root.Position + velocity.Unit * 2
    end

    -- ---------- Оружие и цели ----------
    local function EquippedGun()
        local character = LocalPlayer.Character
        return character and character:FindFirstChild("Gun") or nil
    end

    local function AnyGun()
        local equipped = EquippedGun()
        if equipped then return equipped end
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        return backpack and backpack:FindFirstChild("Gun") or nil
    end

    -- Нож может быть скином с другим именем: игра помечает его тегом Weapon_Knife.
    -- ВАЖНО: pcall здесь защищает только вызов HasTag — его УСПЕХ (true) нельзя
    -- использовать как признак «это нож», иначе любой Tool сойдёт за нож
    local function FindKnifeTool(container)
        container = container or LocalPlayer.Character
        if not container then return nil end
        local knife = container:FindFirstChild("Knife")
        if knife and knife:IsA("Tool") then return knife end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                local tagged = false
                pcall(function() tagged = CollectionService:HasTag(tool, "Weapon_Knife") end)
                if tagged then return tool end
            end
        end
        return nil
    end

    local function AnyKnife()
        local equipped = FindKnifeTool()
        if equipped then return equipped end
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        return backpack and FindKnifeTool(backpack) or nil
    end

    -- Готовность: нож есть, но лежит в рюкзаке — экипируем
    local function ReadyKnife()
        local character = LocalPlayer.Character
        if not character then return nil end
        local knife = FindKnifeTool(character)
        if knife then return knife end
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        knife = FindKnifeTool(backpack)
        if knife and knife:IsA("Tool") then
            pcall(function() knife.Parent = character end)
            return FindKnifeTool(character)
        end
        return nil
    end

    local function OwnAlive()
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        return humanoid ~= nil and humanoid.Health > 0
    end

    -- Поиск убийцы (роль из данных игры, запасной вариант — по ножу)
    local sheriffCacheAt, sheriffCacheP, sheriffCacheC = 0, nil, nil

    local function SheriffTarget()
        -- кэш 0.1с: вызывается из каждого кадра триггер-бота и авто-выстрела,
        -- а внутри — обход всех игроков со строковыми проверками ролей
        local now = os.clock()
        if now - sheriffCacheAt < 0.1 then
            if sheriffCacheP and sheriffCacheC and sheriffCacheC.Parent then
                return sheriffCacheP, sheriffCacheC
            end
            return nil
        end
        sheriffCacheAt = now
        local roles = Roles.data
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local role = type(roles) == "table" and roles[player.Name] or nil
                local murderer = false
                if role and role.Role then
                    murderer = tostring(role.Role):lower():find("murder") ~= nil
                        and role.Dead ~= true and role.Killed ~= true
                else
                    murderer = IsMurdererPlayer(player)
                end
                if murderer then
                    local character = player.Character
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    if character and humanoid and humanoid.Health > 0 and character.Parent then
                        sheriffCacheP, sheriffCacheC = player, character
                        return player, character
                    end
                end
            end
        end
        sheriffCacheP, sheriffCacheC = nil, nil
        return nil
    end

    -- ---------- Проверка стен (персонажи исключаются) ----------
    local WallParams = RaycastParams.new()
    WallParams.FilterType = Enum.RaycastFilterType.Exclude

    local function WallBetween(origin, finish)
        local delta = finish - origin
        if delta.Magnitude < 0.001 then return false end
        local filter = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character then table.insert(filter, player.Character) end
        end
        WallParams.FilterDescendantsInstances = filter
        local ok, hit = pcall(function() return workspace:Raycast(origin, delta, WallParams) end)
        return ok and hit ~= nil
    end

    -- Цель ножа: Cursor — у курсора на экране, Closest — по дистанции,
    -- приоритет шерифа/героя, проверка стен
    local function KnifeTarget(origin)
        local mode = CombatOpt("knifeTarget")
        local maxDist = tonumber(CombatOpt("knifeMaxDist")) or 250
        local camera = workspace.CurrentCamera
        -- GetMouseLocation и WorldToViewportPoint живут в одном пространстве
        -- (координаты от верха окна) — GuiInset вычитать НЕ нужно, иначе
        -- цель «съезжает» вниз на высоту верхней панели (36 px)
        local cursor = UserInputService:GetMouseLocation()
        local roles = Roles.data
        local best, bestScore
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local character = player.Character
                local root = character and character:FindFirstChild("HumanoidRootPart")
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                if root and humanoid and humanoid.Health > 0 then
                    local delta = root.Position - origin
                    local distance = delta.Magnitude
                    if distance <= maxDist and distance > 0.5 then
                        local role = type(roles) == "table" and roles[player.Name] or nil
                        local roleName = role and tostring(role.Role or ""):lower() or ""
                        local armed = roleName:find("sheriff") ~= nil or roleName:find("hero") ~= nil
                        if not CombatOpt("knifeWall") or not WallBetween(origin, root.Position) then
                            local score = -distance
                            if mode == "Cursor" and camera then
                                local ok, point = pcall(function()
                                    local p, onScreen = camera:WorldToViewportPoint(root.Position)
                                    return onScreen and Vector2.new(p.X, p.Y) or nil
                                end)
                                score = (ok and point) and -(point - cursor).Magnitude or -math.huge
                            end
                            if CombatOpt("knifeSheriffFirst") and armed then
                                score += 1000
                            end
                            if not best or score > bestScore then
                                best, bestScore = { player = player, character = character }, score
                            end
                        end
                    end
                end
            end
        end
        return best
    end

    -- Прямой бросок ножа (без анимаций: сервер принимает ремоут как есть)
    local function ThrowKnife(point)
        local knife = ReadyKnife()
        local events = knife and knife:FindFirstChild("Events")
        local remote = events and events:FindFirstChild("KnifeThrown")
        local handle = knife and knife:FindFirstChild("Handle")
        if not remote or not handle or not point then return false end
        local ok = FireRemote(remote, handle.CFrame, CFrame.new(point))
        if ok then
            Engine.lastThrow = Now()
            Engine.throws += 1
            Engine.stats.thrown = Engine.throws
        end
        return ok
    end

    -- Ручной аим-бросок (клик/ПКМ/E/клавиша/кнопка)
    local lastManualThrow = 0

    local function ThrowNow()
        if Now() - lastManualThrow < 0.2 then return false end
        lastManualThrow = Now()
        if not IsMurdererPlayer(LocalPlayer) then
            if Now() - Engine.lastNoTarget > 2.5 then
                Engine.lastNoTarget = Now()
                Notify(L("Knife aim", "Аим ножа"), L("You are not the murderer", "Ты не убийца"), "warning")
            end
            return false
        end
        if not OwnAlive() then return false end
        local knife = ReadyKnife()
        local handle = knife and knife:FindFirstChild("Handle")
        if not handle then return false end
        local target = KnifeTarget(handle.Position)
        if not target then
            if Now() - Engine.lastNoTarget > 2.5 then
                Engine.lastNoTarget = Now()
                Notify(L("Knife aim", "Аим ножа"), L("No target in range", "Нет цели в радиусе"), "warning")
            end
            return false
        end
        local ok, point = pcall(KnifePredictPoint, target.character)
        if not ok or not point then return false end
        return ThrowKnife(point)
    end

    -- ---------- Маркер цели ножа ----------
    local KnifeMarker

    local function Marker(character, text)
        local root = CombatOpt("knifeMarker") and character and character:FindFirstChild("HumanoidRootPart")
        if not root then
            if KnifeMarker then KnifeMarker.Enabled = false end
            return
        end
        if not KnifeMarker or not KnifeMarker.Parent then
            local marker = Instance.new("BillboardGui")
            marker.Name = "YozoraHub_KnifeTarget"
            marker.Size = UDim2.fromOffset(90, 26)
            marker.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
            marker.AlwaysOnTop = true
            marker.ResetOnSpawn = false
            local label = Instance.new("TextLabel")
            label.Name = "L"
            label.BackgroundTransparency = 1
            label.Size = UDim2.fromScale(1, 1)
            label.Font = Enum.Font.GothamBold
            label.TextSize = 15
            label.TextColor3 = Color3.fromRGB(255, 120, 70)
            label.TextStrokeTransparency = 0.35
            label.Parent = marker
            local ok = pcall(function() marker.Parent = CoreGuiService end)
            if not ok or not marker.Parent then marker.Parent = PlayerGui end
            KnifeMarker = marker
        end
        KnifeMarker.Adornee = root
        KnifeMarker.Enabled = true
        local label = KnifeMarker:FindFirstChild("L")
        if label then label.Text = text end
    end

    -- Открыт ли трейд-GUI (окна TradeGUI / TradeGUI_Phone
    -- -> Container -> Trade). Кэш 0.25 с, чтобы не опрашивать GUI на каждый запрос игры.
    local function TradeUiOpen()
        local now = Now()
        if now - Engine.tradeOpenAt < 0.25 then
            return Engine.tradeOpen
        end
        Engine.tradeOpenAt = now
        local open = false
        pcall(function()
            local gui = LocalPlayer:FindFirstChild("PlayerGui")
            if not gui then return end
            -- трейд-GUI этой игры: PlayerGui.MainGUI.Inventory (окно трейда живёт
            -- внутри инвентаря)
            local main = gui:FindFirstChild("MainGUI")
            local inventory = main and main:FindFirstChild("Inventory")
            local function visibleFrame(object)
                return object ~= nil and object:IsA("GuiObject")
                    and object.Visible ~= false
                    and object.AbsoluteSize.X > 1 and object.AbsoluteSize.Y > 1
            end
            if visibleFrame(inventory) then
                open = true
            else
                local trading = inventory and inventory:FindFirstChild("Trading")
                if visibleFrame(trading) then
                    open = true
                end
            end
            -- плюс запасные варианты (на случай других версий игры)
            if not open then
                for _, name in ipairs({ "TradeGUI", "TradeGUI_Phone" }) do
                    local screen = gui:FindFirstChild(name)
                    local container = screen and screen.Enabled and screen:FindFirstChild("Container")
                    local trade = container and container:FindFirstChild("Trade")
                    if trade and trade.Visible ~= false then
                        open = true
                        break
                    end
                end
            end
        end)
        Engine.tradeOpen = open
        return open
    end

    -- Настоящая роль убийцы (без fallback по наличию ножа — иначе takeover
    -- срабатывает в лобби, где экипирован нож-скин)
    local function RealMurdererRole()
        local roles = Roles.data
        if type(roles) ~= "table" then return false end
        local role = roles[LocalPlayer.Name]
        if not role or not role.Role then return false end
        if role.Dead == true or role.Killed == true then return false end
        return tostring(role.Role):lower():find("murder") ~= nil
    end

    -- ---------- Takeover: пистолет ----------
    -- Подавляем родной клиент: гасим ВСЕ LocalScript с "Gun" в имени внутри тула
    -- и запрещаем тулзе самой обрабатывать клики (ManualActivationOnly) — иначе
    -- игра стреляет сама (в точку курсора), а наш прямой выстрел игнорируется
    -- gunClients[child] = исходный Enabled (восстанавливаем именно его),
    -- gunManual[gun] = исходный ManualActivationOnly
    local gunClients = {}
    local gunManual = {}
    local gunReady = false

    local function SuppressGunTool(gun)
        if not gun then return end
        for _, child in ipairs(gun:GetChildren()) do
            if child:IsA("LocalScript") and child.Name:lower():find("gun") then
                if gunClients[child] == nil then
                    gunClients[child] = child.Enabled
                end
                pcall(function() child.Enabled = false end)
            end
        end
        if gunManual[gun] == nil then
            gunManual[gun] = gun.ManualActivationOnly
        end
        pcall(function() gun.ManualActivationOnly = true end)
    end

    local function RestoreGunTool(gun)
        if not gun then return end
        for child, original in pairs(gunClients) do
            if child.Parent == gun then
                pcall(function() child.Enabled = original end)
            end
            gunClients[child] = nil
        end
        local original = gunManual[gun]
        if original ~= nil then
            pcall(function() gun.ManualActivationOnly = original end)
        end
        gunManual[gun] = nil
    end

    -- Повторное глушение: игра может включить свой клиент заново при
    -- экипировке/респавне — вызывается по gun.Equipped и в Heartbeat-свипе
    local function ReapplyGunSuppression()
        local gun = Engine.gunTool
        if not gun or gun.Parent ~= LocalPlayer.Character then return end
        for child in pairs(gunClients) do
            if child.Parent ~= gun then gunClients[child] = nil end
        end
        for _, child in ipairs(gun:GetChildren()) do
            if child:IsA("LocalScript") and child.Name:lower():find("gun") then
                if gunClients[child] == nil then
                    gunClients[child] = child.Enabled
                end
                if child.Enabled ~= false then
                    pcall(function() child.Enabled = false end)
                end
            end
        end
        pcall(function()
            if gun.ManualActivationOnly ~= true then gun.ManualActivationOnly = true end
        end)
    end

    -- Выстрел по цели: origin (Piercer у цели / ствол) + предсказанная точка.
    -- forcePiercer: true/false — явное указание (фарм при полном мешке),
    -- nil — берём глобальную настройку Piercer
    local function FireAtTarget(gun, character, forcePiercer)
        local shoot = gun and gun:FindFirstChild("Shoot")
        local handle = gun and gun:FindFirstChild("Handle")
        local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
        if not shoot or not handle or not targetRoot then return false end
        local ok, point = pcall(PredictMovement, character)
        if not ok or not point then return false end
        -- forcePiercer: явное false должно перекрыть глобальную настройку
        local pierce = forcePiercer
        if pierce == nil then pierce = CombatOpt("piercer") end
        local origin = pierce
            and targetRoot.CFrame * CFrame.new(0, 0, 2.5)
            or handle.CFrame
        local sent = FireRemote(shoot, origin, CFrame.new(point))
        if sent then
            Engine.stats.fired += 1
            Engine.pending = { t = Now(), c = character }
        end
        return sent
    end

    local function OnGunActivated(gun)
        if not CombatOpt("silentAim") then return end
        if gunReady then return end
        if not OwnAlive() or not RoundState.round or TradeUiOpen() then return end
        local player, character = SheriffTarget()
        if not player or not character then return end
        local ok, sent = pcall(FireAtTarget, gun, character)
        if ok and sent then
            -- гейт после реального выстрела: промах мимо цели не блокирует клики
            gunReady = true
            task.delay(1, function() gunReady = false end)
        end
    end

    local function DisconnectGun()
        if Engine.gunConnection then
            pcall(function() Engine.gunConnection:Disconnect() end)
            Engine.gunConnection = nil
        end
        if Engine.gunEquipConnection then
            pcall(function() Engine.gunEquipConnection:Disconnect() end)
            Engine.gunEquipConnection = nil
        end
        local tool = Engine.gunTool
        Engine.gunTool = nil
        if tool then RestoreGunTool(tool) end
    end

    local function HookGunTool(gun)
        if not gun or gun == Engine.gunTool then return end
        DisconnectGun()
        SuppressGunTool(gun)
        Engine.gunConnection = gun.Activated:Connect(function()
            OnGunActivated(gun)
        end)
        -- при каждой экипировке игра может включить свой клиент заново — глушим повторно
        Engine.gunEquipConnection = gun.Equipped:Connect(function()
            task.defer(function()
                if CombatOpt("silentAim") and Engine.gunTool == gun then
                    pcall(ReapplyGunSuppression)
                end
            end)
        end)
        Engine.gunTool = gun
    end

    -- ---------- Takeover: нож ----------
    -- Отключаем родной KnifeClient: клики/ПКМ/E обрабатывает движок
    -- knifeClients[knife] = исходный Enabled KnifeClient
    local knifeClients = {}

    -- Аим-бросок по осознанному вводу (ПКМ / E / клавиша / кнопка)
    local function OnKnifeInput()
        if CombatOpt("knifeAim") then
            task.spawn(function() pcall(ThrowNow) end)
        end
    end

    -- ЛКМ по тулзе (Tool.Activated): по умолчанию НЕ бросает — ЛКМ часто
    -- нажимается случайно (двери, монеты), и нож улетал «сам по себе».
    -- Осознанный бросок — ПКМ/E/клавиша; ЛКМ включается настройкой knifeLMB
    local function OnKnifeActivated()
        if os.clock() < KnifeInternalUntil or not CombatOpt("knifeLMB") then return end
        OnKnifeInput()
    end

    local function DisconnectKnife()
        if Engine.knifeConnection then
            pcall(function() Engine.knifeConnection:Disconnect() end)
            Engine.knifeConnection = nil
        end
        local tool = Engine.knifeTool
        Engine.knifeTool = nil
        if tool and knifeClients[tool] ~= nil then
            local original = knifeClients[tool]
            knifeClients[tool] = nil
            local client = tool:FindFirstChild("KnifeClient")
            if client and client:IsA("LocalScript") then
                pcall(function() client.Enabled = original end)
            end
        end
    end

    local function HookKnifeTool(knife)
        if not knife or knife == Engine.knifeTool then return end
        DisconnectKnife()
        local client = knife:FindFirstChild("KnifeClient") or knife:FindFirstChildOfClass("LocalScript")
        if client and client:IsA("LocalScript") then
            knifeClients[knife] = client.Enabled
            pcall(function() client.Enabled = false end)
        end
        Engine.knifeConnection = knife.Activated:Connect(OnKnifeActivated)
        Engine.knifeTool = knife
    end

    -- ---------- Подбор пистолета (невиновный, когда шериф погиб) ----------
    -- Касание брошенного пистолета через firetouchinterest, автономно
    -- (работает без включённого авто-фарма)
    local function PickTouchParts(character)
        local parts = {}
        local head = character:FindFirstChild("Head")
        if head then table.insert(parts, head) end
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Accessory") then
                local handle = child:FindFirstChild("Handle")
                if handle then table.insert(parts, handle) end
            end
        end
        for _, name in ipairs({ "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso" }) do
            local part = character:FindFirstChild(name)
            if part then table.insert(parts, part) end
        end
        return parts
    end

    local function PickTouch(character, drop)
        if not firetouchinterest or not character or not drop or not drop.Parent then return end
        for _, part in ipairs(PickTouchParts(character)) do
            pcall(function()
                firetouchinterest(part, drop, 0)
                firetouchinterest(part, drop, 1)
            end)
        end
    end

    local nextGunPick = 0

    local function PickGunStep(now)
        if now < nextGunPick then return end
        nextGunPick = now + 0.15
        if not CombatOpt("pickGun") then return end
        local _, role = LocalRoleState()
        local isInnocent = role ~= nil and tostring(role.Role) == "Innocent"
            and role.Dead ~= true and role.Killed ~= true
        if not isInnocent or not OwnAlive() then return end
        if HasTool(LocalPlayer, "Gun") then return end
        local drop = Esp.findDrop and Esp.findDrop() or nil
        if drop then
            local character = LocalPlayer.Character
            PickTouch(character, drop)
        end
    end

    -- ---------- Эхо выстрелов (WeaponService.GunFired) ----------
    -- Forward-declare: PersistSave вызывается из OnFired (выше по коду),
    -- а определяется ниже; без этого замыкание цеплялось бы на глобал nil
    local PersistSave

    local function OnFired(tool, start, endpoint, hit)
        local own = false
        pcall(function()
            own = typeof(tool) == "Instance" and LocalPlayer.Character ~= nil
                and tool:IsDescendantOf(LocalPlayer.Character)
        end)
        if not own then return end
        local now = Now()
        Engine.lastAccepted = now
        local pending = Engine.pending
        if pending then
            Engine.pending = nil
            Engine.echo += ((now - pending.t) - Engine.echo) * 0.3
        end
        local success = false
        if pending and typeof(hit) == "Instance" and pending.c then
            pcall(function() success = hit:IsDescendantOf(pending.c) end)
        end
        if success then
            Engine.stats.hit += 1
            Engine.missStreak = 0
            if CombatOpt("calibrate") then
                Engine.Llearned = math.clamp(Engine.Llearned - 0.004, 0.05, 0.45)
                PersistSave(false)
            end
        else
            Engine.stats.missed += 1
            Engine.missStreak += 1
            if CombatOpt("calibrate") and Engine.missStreak >= 2 then
                Engine.Llearned = math.clamp(Engine.Llearned + 0.012, 0.05, 0.45)
                Engine.missStreak = 0
                PersistSave(false)
            end
        end
    end

    task.spawn(function()
        local ok, services = pcall(function()
            return ReplicatedStorage:WaitForChild("ClientServices", 10)
        end)
        local weapons = ok and services and services:WaitForChild("WeaponService", 10)
        local fired = weapons and weapons:WaitForChild("GunFired", 10)
        if not fired or not Alive() or not fired:IsA("RemoteEvent") then return end
        Track(fired.OnClientEvent:Connect(function(...)
            if Alive() then pcall(OnFired, ...) end
        end))
    end)

    -- ---------- Калибровка и сохранение ----------
    local AIM_FILE = "YozoraHub/aim.json"
    local persistAt = 0

    local function PersistLoad()
        if not (isfile and readfile and isfile(AIM_FILE)) then return end
        local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(AIM_FILE)) end)
        if ok and type(decoded) == "table" then
            Engine.Llearned = math.clamp(tonumber(decoded.L) or Engine.Llearned, 0.05, 0.45)
            Engine.cooldown = math.clamp(tonumber(decoded.cooldown) or Engine.cooldown, 0.3, 5)
            Engine.knifeSpeed = math.clamp(tonumber(decoded.knifeSpeed) or Engine.knifeSpeed, 85, 108)
        end
    end

    PersistSave = function(force)
        local now = Now()
        if not force and now - persistAt < 5 then return end
        persistAt = now
        if not writefile then return end
        pcall(function()
            if isfolder and makefolder and not isfolder("YozoraHub") then makefolder("YozoraHub") end
            writefile(AIM_FILE, HttpService:JSONEncode({
                L = Engine.Llearned,
                cooldown = Engine.cooldown,
                knifeSpeed = Engine.knifeSpeed,
            }))
        end)
    end

    -- ---------- Авто-выстрел ----------
    local lastAuto, lastEquip = 0, 0

    local function AutoShootTick(now, force)
        if not force and not CombatOpt("autoShoot") then return end
        local cadence = math.max(0.25, (tonumber(CombatOpt("autoShootDelay")) or 250) / 1000)
        if now - lastAuto < cadence then return end
        lastAuto = now
        if not OwnAlive() then return end
        if not force and (not RoundState.round or TradeUiOpen()) then return end
        local player, character = SheriffTarget()
        if not player or not character then return end
        local own = LocalPlayer.Character
        local humanoid = own and own:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        local gun = EquippedGun()
        if not gun then
            -- Фарм (полный мешок) экипирует пистолет ВСЕГДА — стреляем во что
            -- бы то ни стало. Обычный авто-выстрел — только с «Авто-экипировкой»
            if not force and not CombatOpt("autoEquip") then return end
            if now - lastEquip < 1 then return end
            local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
            local packGun = backpack and backpack:FindFirstChild("Gun")
            if not packGun then return end
            lastEquip = now
            local equipped = false
            pcall(function()
                humanoid:EquipTool(packGun)
                equipped = packGun.Parent == own
            end)
            if not equipped then
                -- запасной вариант: прямая смена родителя тоже экипирует тул
                pcall(function()
                    packGun.Parent = own
                end)
            end
            return
        end
        -- фарм (force) использует свой тумблер «сквозь стены», обычный
        -- авто-выстрел — глобальный Piercer из шестерёнки Сайлент Аима
        local pierce = nil
        if force then pierce = CombatOpt("farmPiercer") end
        pcall(FireAtTarget, gun, character, pierce)
    end

    -- ---------- Авто-бросок ножа ----------
    local function AutoThrowTick(now)
        if not CombatOpt("autoThrow") then return end
        if not OwnAlive() or not IsMurdererPlayer(LocalPlayer) or TradeUiOpen() then return end
        local throwSpeed = 0.7
        local knife = FindKnifeTool()
        if knife then
            throwSpeed = tonumber(knife:GetAttribute("ThrowSpeed")) or 0.7
        end
        local cooldown = math.max(1.45, throwSpeed * 2 + 0.08)
        if now - Engine.lastThrow < cooldown then return end
        local knifeReady = ReadyKnife()
        local handle = knifeReady and knifeReady:FindFirstChild("Handle")
        if not handle then return end
        local target = KnifeTarget(handle.Position)
        if not target then return end
        local root = target.character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        if (root.Position - handle.Position).Magnitude > (tonumber(CombatOpt("autoThrowRange")) or 70) then return end
        local ok, point = pcall(KnifePredictPoint, target.character)
        if ok and point then
            ThrowKnife(point)
        end
    end

    -- ---------- Trigger Bot: выстрел, когда цель у прицела ----------
    -- Работает от твоего прицела: подводишь к убийце в радиус — движок сам
    -- стреляет (не включается вместе с Авто-выстрелом, это другой режим)
    local lastTrigger = 0

    local function TriggerBotTick(now)
        if not CombatOpt("triggerBot") or CombatOpt("autoShoot") then return end
        if gunReady or now - lastTrigger < 0.08 then return end
        if not OwnAlive() or not RoundState.round or TradeUiOpen() then return end
        local player, character = SheriffTarget()
        if not player or not character then return end
        local root = character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local camera = workspace.CurrentCamera
        if not camera then return end
        local ok, point = pcall(function() return camera:WorldToViewportPoint(root.Position) end)
        if not ok or not point or not point.Z or point.Z <= 0 then return end
        -- то же пространство, что и WorldToViewportPoint — без GuiInset
        local cursor = UserInputService:GetMouseLocation()
        local radius = tonumber(CombatOpt("triggerRadius")) or 40
        if (Vector2.new(point.X, point.Y) - cursor).Magnitude > radius then return end
        if CombatOpt("triggerWall") then
            local own = LocalPlayer.Character
            local gun = EquippedGun()
            local originPart = gun and gun:FindFirstChild("Handle")
                or own and (own:FindFirstChild("RightHand") or own:FindFirstChild("Right Arm"))
            if originPart and WallBetween(originPart.Position, root.Position) then return end
        end
        local gun = EquippedGun()
        if not gun or gun.Parent ~= LocalPlayer.Character then return end
        local okShot, sent = pcall(FireAtTarget, gun, character)
        if okShot and sent then
            -- общий гейт с ручным кликом: двойной выстрел невозможен
            gunReady = true
            task.delay(1, function() gunReady = false end)
        end
    end

    -- ---------- Kill Aura: авто-касание ножом всех в радиусе ----------
    local lastKillAura = 0

    local function KillAuraTick(now)
        if not CombatOpt("killAura") then return end
        if now - lastKillAura < 0.35 then return end
        lastKillAura = now
        if not OwnAlive() or not IsMurdererPlayer(LocalPlayer) or TradeUiOpen() then return end
        if not firetouchinterest then return end
        local knife = ReadyKnife()
        local handle = knife and knife:FindFirstChild("Handle")
        if not handle then return end
        local range = tonumber(CombatOpt("killAuraRange")) or 10
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local target = player.Character
                local humanoid = target and target:FindFirstChildOfClass("Humanoid")
                local root = target and target:FindFirstChild("HumanoidRootPart")
                if root and humanoid and humanoid.Health > 0
                    and (root.Position - handle.Position).Magnitude <= range then
                    pcall(function()
                        firetouchinterest(handle, root, 0)
                        firetouchinterest(handle, root, 1)
                    end)
                end
            end
        end
    end

    -- ---------- Маркер цели (обновление) ----------
    local nextMarkerScan = 0

    local function MarkerTick(now)
        if not CombatOpt("knifeAim") or not CombatOpt("knifeMarker") then
            pcall(Marker, nil)
            return
        end
        if now < nextMarkerScan then return end
        nextMarkerScan = now + 0.12
        local knife = FindKnifeTool()
        local handle = knife and knife:FindFirstChild("Handle")
        local target = handle and KnifeTarget(handle.Position) or nil
        if target then
            local player = target.player
            pcall(Marker, target.character, player.DisplayName ~= "" and player.DisplayName or player.Name)
        else
            pcall(Marker, nil)
        end
    end

    -- ---------- Ввод: ПКМ / E с ножом = аим-бросок ----------
    Track(UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if not CombatOpt("knifeAim") then return end
        if not Engine.knifeTool or Engine.knifeTool.Parent ~= LocalPlayer.Character then return end
        if _G.YozoraHub_Capturing then return end
        if UserInputService:GetFocusedTextBox() then return end
        local inputType = input.UserInputType
        if inputType == Enum.UserInputType.MouseButton2
            or (inputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == "E") then
            OnKnifeInput()
        end
    end))

    -- ЛКМ с пистолетом = аим-выстрел (когда Silent Aim включён).
    -- Tool.Activated не всегда срабатывает: часть игр держит клики под
    -- ManualActivationOnly и обрабатывает ввод сама — дублируем на уровне ввода.
    -- Двойной выстрел (Activated + InputBegan) невозможен: гейт gunReady.
    Track(UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if not CombatOpt("silentAim") then return end
        if not Engine.gunTool or Engine.gunTool.Parent ~= LocalPlayer.Character then return end
        if _G.YozoraHub_Capturing then return end
        if UserInputService:GetFocusedTextBox() then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            OnGunActivated(Engine.gunTool)
        end
    end))

    -- Клавиша ручного броска ножа (настраиваемая)
    Track(UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if _G.YozoraHub_Capturing then return end
        if UserInputService:GetFocusedTextBox() then return end
        local key = CombatOpt("throwKey")
        if type(key) == "string" and key ~= "" and input.KeyCode.Name == key then
            task.spawn(function() pcall(ThrowNow) end)
        end
    end))

    -- ---------- Основной цикл ----------
    Track(RunService.Heartbeat:Connect(function()
        if not Alive() then return end
        local ok, err = pcall(function()
            local now = Now()
            AutoShootTick(now)
            TriggerBotTick(now)
            AutoThrowTick(now)
            KillAuraTick(now)
            PickGunStep(now)
            -- ожидание ответа GunFired: если эха нет — сбрасываем
            local pending = Engine.pending
            if pending and not pending.dead then
                if now - pending.t > math.max(0.4, Ping() * 2.2 + 0.2) then
                    pending.dead = true
                    Engine.pending = nil
                end
            end
            -- текущая цель (для статуса)
            local player = SheriffTarget()
            Engine.target = player
            -- takeover пистолета: включён при Silent Aim
            if CombatOpt("silentAim") then
                -- свип подавления: игра могла включить свой клиент заново
                if now - Engine.lastSuppressCheck > 0.25 then
                    Engine.lastSuppressCheck = now
                    pcall(ReapplyGunSuppression)
                end
                local gun = AnyGun()
                if gun and gun ~= Engine.gunTool then
                    pcall(HookGunTool, gun)
                end
            elseif Engine.gunTool then
                pcall(DisconnectGun)
            end
            -- takeover ножа: включён при Knife Aim
            if CombatOpt("knifeAim") then
                local knife = AnyKnife()
                if knife and knife ~= Engine.knifeTool then
                    pcall(HookKnifeTool, knife)
                end
            elseif Engine.knifeTool then
                pcall(DisconnectKnife)
            end
            MarkerTick(now)
        end)
        if not ok then
            local message = tostring(err)
            if message ~= Engine.lastError then
                Engine.lastError = message
                warn("[Yozora Hub] combat error: " .. message)
            end
        end
    end))

    -- ---------- Аимлок: камера плавно тянется к убийце ----------
    Track(RunService.RenderStepped:Connect(function()
        if not CombatOpt("aimlock") then return end
        if not OwnAlive() then return end
        local player, character = SheriffTarget()
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local camera = workspace.CurrentCamera
        if not root or not camera then return end
        local ok, target = pcall(function()
            return CFrame.lookAt(camera.CFrame.Position, root.Position)
        end)
        if ok and target then
            camera.CFrame = camera.CFrame:Lerp(target, 0.55)
        end
    end))

    -- ---------- Публичный API для вкладки Combat ----------
    Combat.throwNow = ThrowNow

    -- Выстрел в убийцу с телепортом: телепортирует на мгновение перед целью
    -- (держится пинг+0.2 с), стреляет и возвращает на место
    Combat.shootMurderer = function()
        task.spawn(function()
            if not OwnAlive() or not RoundState.round or TradeUiOpen() then return end
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not root then return end
            local player, target = SheriffTarget()
            local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
            if not targetRoot then return end
            local oldFrame = root.CFrame
            local finish = os.clock() + math.max(0.3, Ping() * 3 + 0.2)
            local sent = false
            while os.clock() < finish and OwnAlive() do
                pcall(function()
                    root.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 5)
                end)
                RunService.Heartbeat:Wait()
                if not sent then
                    local gun = EquippedGun()
                    if gun and gun.Parent == LocalPlayer.Character then
                        local okShot, fired = pcall(FireAtTarget, gun, target)
                        sent = okShot and fired or false
                    end
                end
            end
            pcall(function()
                root.CFrame = oldFrame
            end)
        end)
    end

    Combat.HookName = function()
        local parts = {}
        if CombatOpt("silentAim") then
            table.insert(parts, Engine.gunTool and T(L("Takeover", "Захват")) or T(L("Waiting gun", "Жду пистолет")))
        end
        if CombatOpt("autoShoot") then
            table.insert(parts, T(L("Auto", "Авто")))
        end
        if CombatOpt("knifeAim") then
            table.insert(parts, Engine.knifeTool and T(L("Knife", "Нож")) or "-")
        end
        if CombatOpt("autoThrow") then
            table.insert(parts, T(L("Throw", "Бросок")))
        end
        if #parts == 0 then return T(L("Off", "Выкл")) end
        return table.concat(parts, " + ")
    end

    Combat.TargetName = function()
        local player = Engine.target
        if player and player.Parent then
            return player.DisplayName ~= "" and player.DisplayName or player.Name
        end
        return "-"
    end

    Combat.LeadInfo = function()
        local lead = math.max(Engine.Llearned, CombatOpt("pingComp") and Ping() or 0)
        return ("%d ms"):format(math.floor(lead * 1000 + 0.5))
    end

    Combat.ShotsInfo = function()
        return ("%d / %d"):format(Engine.stats.fired, Engine.stats.hit)
    end

    Combat.KnifeInfo = function()
        return tostring(Engine.throws)
    end

    -- Форс-выстрел для авто-фарма: «авто-выстрел в убийцу при полном мешке»
    -- (мешок полон + не убийца — фармовый цикл сам решает, когда звать)
    Combat.forceShootTick = function(now)
        pcall(AutoShootTick, now, true)
    end

    -- Тумблер «Убить всех сразу»: читается циклом в секции фарма
    Combat.KillAllEnabled = function()
        return CombatOpt("killAll") == true
    end

    -- Реакция на изменение настроек: takeover включается/выключается
    -- в основном цикле, отдельных действий не требуется
    Combat.changed = function() end

    -- ---------- Запуск и остановка ----------
    PersistLoad()
    GameLog(L("Combat module loaded", "Модуль боя загружен"))

    -- Отладка (вызвать из консоли исполнителя): _G.YozoraHub_CombatDebug()
    _G.YozoraHub_CombatDebug = function()
        local info = {
            rawFireServer = rawFireServer ~= nil,
            gunTakeover = Engine.gunTool ~= nil,
            knifeTakeover = Engine.knifeTool ~= nil,
            rolesKnown = type(Roles.data) == "table",
            round = RoundState.round == true,
            tradeOpen = TradeUiOpen(),
            murderer = RealMurdererRole(),
            alive = OwnAlive(),
            silentAim = CombatOpt("silentAim"),
            knifeAim = CombatOpt("knifeAim"),
            autoThrow = CombatOpt("autoThrow"),
        }
        print("[Yozora Combat] rawFireServer=" .. tostring(info.rawFireServer)
            .. " | gunTakeover=" .. tostring(info.gunTakeover)
            .. " | knifeTakeover=" .. tostring(info.knifeTakeover)
            .. " | rolesKnown=" .. tostring(info.rolesKnown)
            .. " | round=" .. tostring(info.round)
            .. " | tradeOpen=" .. tostring(info.tradeOpen)
            .. " | murderer=" .. tostring(info.murderer)
            .. " | alive=" .. tostring(info.alive)
            .. " | silentAim=" .. tostring(info.silentAim)
            .. " | knifeAim=" .. tostring(info.knifeAim))
        return info
    end

    _G.YozoraHub_CombatStop = function()
        Engine.alive = false
        pcall(DisconnectGun)
        pcall(DisconnectKnife)
        Engine.pending = nil
        Engine.tradeOpen, Engine.tradeOpenAt = false, 0
        if KnifeMarker then
            pcall(function() KnifeMarker:Destroy() end)
            KnifeMarker = nil
        end
    end
end

-- ==========================================
-- 9b. ESP (рисование поверх экрана)
-- ==========================================
-- Рамки, скелет, трассеры, стрелки за экраном и подписи рисуются Frame'ами в отдельном
-- ScreenGui, чамсы это Highlight. Роли берутся из данных игры (секция ролей выше).
do
    if _G.YozoraHub_EspStop then pcall(_G.YozoraHub_EspStop) end

    local ROLE_FIELDS = { Murderer = "murderer", Sheriff = "sheriff", Hero = "hero", Innocent = "innocent" }
    local ROLE_NAMES = {
        Murderer = L("Murderer", "Убийца"), Sheriff = L("Sheriff", "Шериф"),
        Hero = L("Hero", "Герой"), Innocent = L("Innocent", "Невиновный"),
    }
    local WEAPON_NAMES = { Knife = L("Knife", "Нож"), Gun = L("Gun", "Пистолет") }

    local R15_BONES = {
        { "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
        { "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
        { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
        { "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
        { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
    }
    local R6_BONES = {
        { "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
        { "Torso", "Left Leg" }, { "Torso", "Right Leg" },
    }

    local ZERO = Vector2.new(0, 0)
    local BLACK = Color3.new(0, 0, 0)

    local Objects = {}   -- [игрок] = рисунки этого игрока
    local BoundsCache = setmetatable({}, { __mode = "k" })
    local Gui, Folder = nil, nil
    local lastError = nil
    local wasOn = false

    -- ---------- Корневой ScreenGui ----------
    local function Root()
        if Gui and Gui.Parent then return Gui end
        Gui = Instance.new("ScreenGui")
        Gui.Name = "YozoraHub_ESP"
        Gui.ResetOnSpawn = false
        Gui.IgnoreGuiInset = true -- координаты WorldToViewportPoint совпадают с координатами GUI
        Gui.DisplayOrder = 9
        Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        local ok = pcall(function()
            Gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
        end)
        if not ok or not Gui.Parent then
            Gui.Parent = PlayerGui
        end
        Folder = Instance.new("Folder")
        Folder.Name = "YozoraHub_ESP_Chams"
        Folder.Parent = Gui.Parent
        return Gui
    end

    -- ---------- Элементы рисунка ----------
    local function Elem(object, key, z, anchor)
        local frame = object.f[key]
        if not frame then
            frame = Instance.new("Frame")
            frame.BorderSizePixel = 0
            frame.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
            frame.ZIndex = z or 1
            frame.Visible = false
            frame.Parent = object.layer
            object.f[key] = frame
        end
        return frame
    end

    local function TextElem(object, key)
        local label = object.f[key]
        if not label then
            label = Instance.new("TextLabel")
            label.BackgroundTransparency = 1
            label.BorderSizePixel = 0
            label.Font = FontByName("GothamSemibold", Enum.Font.GothamMedium)
            label.TextStrokeColor3 = BLACK
            label.ZIndex = 4
            label.Visible = false
            label.Parent = object.layer
            object.f[key] = label
        end
        return label
    end

    local function GetObject(player)
        local object = Objects[player]
        if object and object.layer.Parent then return object end
        local layer = Instance.new("Frame")
        layer.Name = "P" .. player.UserId
        layer.Size = UDim2.fromScale(1, 1)
        layer.BackgroundTransparency = 1
        layer.BorderSizePixel = 0
        layer.Visible = false
        layer.Parent = Root()
        object = { layer = layer, f = {} }
        Objects[player] = object
        return object
    end

    local function ResetElements(object)
        for _, element in pairs(object.f) do
            if element.Visible then element.Visible = false end
        end
    end

    local function DropChams(object)
        if object.highlight then
            pcall(function() object.highlight:Destroy() end)
            object.highlight = nil
        end
    end

    local function Hide(player)
        local object = Objects[player]
        if object then
            object.layer.Visible = false
            object.rect = nil
            DropChams(object)
        end
    end

    local function Release(player)
        local object = Objects[player]
        if object then
            DropChams(object)
            pcall(function() object.layer:Destroy() end)
            Objects[player] = nil
        end
    end

    local function HideAll()
        for player in pairs(Objects) do Hide(player) end
    end

    -- ---------- Роли и оружие ----------
    local function RoleOf(player, character)
        local data = type(Roles.data) == "table" and Roles.data[player.Name] or nil
        if type(Roles.data) == "table" then
            -- данные игры есть, но записи о игроке нет (неполные данные):
            -- экипированный нож = убийца, иначе не показываем
            if not data or not data.Role then
                return CarriesKnife(player) and "Murderer" or nil
            end
            if data.Dead == true or data.Killed == true then return nil end
            local role = tostring(data.Role)
            if role == "Innocent" and CarriesKnife(player) then
                -- данные говорят «невиновный», но нож в руках — данные устарели
                return "Murderer"
            end
            if role == "Innocent" and HasTool(player, "Gun") then role = "Hero" end
            return ROLE_FIELDS[role] and role or nil
        end
        -- запасной вариант, если данных игры нет: роль по оружию в руках
        if CarriesKnife(player) then return "Murderer" end
        if character:FindFirstChild("Gun") then return "Sheriff" end
        return "Innocent"
    end

    local function WeaponOf(character, role)
        if character:FindFirstChild("Knife") then return "Knife" end
        if character:FindFirstChild("Gun") then return "Gun" end
        if role == "Murderer" then return "Knife" end
        if role == "Sheriff" or role == "Hero" then return "Gun" end
        return nil
    end

    local function NameOf(player)
        local mode = EspOpt("nameMode")
        if mode == "Username" then return player.Name end
        if mode == "Both" and player.DisplayName ~= player.Name then
            return player.DisplayName .. " (@" .. player.Name .. ")"
        end
        return player.DisplayName
    end

    local function DistanceText(distance)
        if EspOpt("distUnit") == "Meters" then
            return ("%d m"):format(math.floor(distance * 0.28 + 0.5))
        end
        return ("%d st"):format(math.floor(distance + 0.5))
    end

    -- ---------- Проекция ----------
    local function Bounds(character, root)
        local now = os.clock()
        local cached = BoundsCache[character]
        if cached and now - cached.at < 0.2 then return cached.top, cached.bottom end

        local top, bottom
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") then
                local half, y = part.Size.Y * 0.5, part.Position.Y
                top = top and math.max(top, y + half) or y + half
                bottom = bottom and math.min(bottom, y - half) or y - half
            end
        end
        local y = root.Position.Y
        cached = { at = now, top = (top or y + 3) - y, bottom = (bottom or y - 3) - y }
        BoundsCache[character] = cached
        return cached.top, cached.bottom
    end

    local function ProjectBox(character, root, camera, viewport)
        local top, bottom = Bounds(character, root)
        local position = root.Position
        local upper = camera:WorldToViewportPoint(Vector3.new(position.X, position.Y + top + 0.12, position.Z))
        local lower = camera:WorldToViewportPoint(Vector3.new(position.X, position.Y + bottom - 0.08, position.Z))
        if upper.Z <= 0.08 or lower.Z <= 0.08 then return nil end

        local height = math.abs(lower.Y - upper.Y)
        if height < 2 or height > viewport.Y * 4 then return nil end
        local width = height * math.clamp(EspOpt("boxWidth") / 100, 0.2, 1)
        local x = (upper.X + lower.X) * 0.5 - width * 0.5
        local y = math.min(upper.Y, lower.Y)
        if x + width < 0 or x > viewport.X or y + height < 0 or y > viewport.Y then return nil end
        if width < 12 then x, width = x - (12 - width) * 0.5, 12 end
        if height < 22 then y, height = y - (22 - height) * 0.5, 22 end
        return { x = x, y = y, w = width, h = height }
    end

    local function Smooth(object, rect, viewport, delta)
        local factor = math.clamp(EspOpt("smooth"), 0, 95) / 100
        local previous = object.rect
        if factor <= 0 or not previous then
            object.rect = rect
            return rect
        end
        local jump = math.abs(rect.x - previous.x) + math.abs(rect.y - previous.y)
        if jump > math.max(viewport.X, viewport.Y) * 0.35 then
            object.rect = rect
            return rect
        end
        local alpha = 1 - factor ^ (math.clamp(delta, 0.001, 0.1) * 60)
        local smoothed = {
            x = previous.x + (rect.x - previous.x) * alpha, y = previous.y + (rect.y - previous.y) * alpha,
            w = previous.w + (rect.w - previous.w) * alpha, h = previous.h + (rect.h - previous.h) * alpha,
        }
        object.rect = smoothed
        return {
            x = math.floor(smoothed.x + 0.5), y = math.floor(smoothed.y + 0.5),
            w = math.max(1, math.floor(smoothed.w + 0.5)), h = math.max(1, math.floor(smoothed.h + 0.5)),
        }
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.IgnoreWater = true

    -- Видимость цели: луч от камеры, прозрачные детали пропускаем
    local function IsVisible(origin, target, character)
        local direction = target.Position - origin
        if direction.Magnitude < 0.05 then return true end
        local ignored = { character, workspace.CurrentCamera }
        if LocalPlayer.Character then table.insert(ignored, LocalPlayer.Character) end
        for _ = 1, 6 do
            rayParams.FilterDescendantsInstances = ignored
            local hit = workspace:Raycast(origin, direction, rayParams)
            if not hit then return true end
            if hit.Instance.Transparency < 0.3 then return false end
            table.insert(ignored, hit.Instance)
        end
        return false
    end

    -- ---------- Рисование ----------
    local function DrawLine(frame, a, b, thickness, color, transparency)
        local delta = b - a
        local length = delta.Magnitude
        if length < 0.5 then return end
        frame.Position = UDim2.fromOffset((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5)
        frame.Size = UDim2.fromOffset(length, thickness)
        frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
        frame.BackgroundColor3 = color
        frame.BackgroundTransparency = transparency
        frame.Visible = true
    end

    local function BoxSegments(style, x, y, w, h, t)
        if style == "Full" then
            return {
                { x, y, w, t }, { x, y + h - t, w, t }, { x, y, t, h }, { x + w - t, y, t, h },
            }
        end
        local len = math.max(4, math.min(EspOpt("cornerSize"), w * 0.5, h * 0.5))
        return {
            { x, y, len, t }, { x, y, t, len }, { x + w - len, y, len, t }, { x + w - t, y, t, len },
            { x, y + h - t, len, t }, { x, y + h - len, t, len },
            { x + w - len, y + h - t, len, t }, { x + w - t, y + h - len, t, len },
        }
    end

    local function DrawBox(object, rect, color, alpha)
        local x, y, w, h = rect.x, rect.y, rect.w, rect.h
        local thickness = math.max(1, math.floor(EspOpt("boxThickness") + 0.5))
        local outline = EspOpt("boxOutline")

        if EspOpt("boxFill") then
            local fill = Elem(object, "fill", 0, ZERO)
            fill.Position = UDim2.fromOffset(x, y)
            fill.Size = UDim2.fromOffset(w, h)
            fill.BackgroundColor3 = color
            fill.BackgroundTransparency = 1 - math.clamp(EspOpt("boxFillAlpha") / 100, 0, 1) * alpha
            fill.Visible = true
        end

        for index, segment in ipairs(BoxSegments(EspOpt("boxStyle"), x, y, w, h, thickness)) do
            if outline then
                local back = Elem(object, "out" .. index, 1, ZERO)
                back.Position = UDim2.fromOffset(segment[1] - 1, segment[2] - 1)
                back.Size = UDim2.fromOffset(segment[3] + 2, segment[4] + 2)
                back.BackgroundColor3 = BLACK
                back.BackgroundTransparency = 1 - 0.65 * alpha
                back.Visible = true
            end
            local line = Elem(object, "seg" .. index, 2, ZERO)
            line.Position = UDim2.fromOffset(segment[1], segment[2])
            line.Size = UDim2.fromOffset(segment[3], segment[4])
            line.BackgroundColor3 = color
            line.BackgroundTransparency = 1 - alpha
            line.Visible = true
        end
    end

    local function DrawText(object, rect, player, role, color, alpha, distance, character)
        local size = math.clamp(EspOpt("textSize"), 8, 24)
        local strokeTransparency = EspOpt("textOutline") and 1 - alpha * 0.6 or 1

        if EspOpt("name") then
            local label = TextElem(object, "name")
            label.AnchorPoint = Vector2.new(0.5, 1)
            label.Position = UDim2.fromOffset(rect.x + rect.w * 0.5, rect.y - 3)
            label.Size = UDim2.fromOffset(240, size + 4)
            label.TextXAlignment = Enum.TextXAlignment.Center
            label.TextSize = size
            label.Text = NameOf(player)
            label.TextColor3 = Color3.fromRGB(250, 250, 250)
            label.TextTransparency = 1 - alpha
            label.TextStrokeTransparency = strokeTransparency
            label.Visible = true
        end

        local parts = {}
        if EspOpt("role") then table.insert(parts, T(ROLE_NAMES[role])) end
        if EspOpt("weapon") then
            local weapon = WeaponOf(character, role)
            if weapon then table.insert(parts, T(WEAPON_NAMES[weapon])) end
        end
        if EspOpt("distance") then table.insert(parts, DistanceText(distance)) end
        if #parts > 0 then
            local label = TextElem(object, "info")
            label.AnchorPoint = Vector2.new(0.5, 0)
            label.Position = UDim2.fromOffset(rect.x + rect.w * 0.5, rect.y + rect.h + 2)
            label.Size = UDim2.fromOffset(260, size + 2)
            label.TextXAlignment = Enum.TextXAlignment.Center
            label.TextSize = math.max(8, size - 2)
            label.Text = table.concat(parts, "  |  ")
            label.TextColor3 = color
            label.TextTransparency = 1 - alpha
            label.TextStrokeTransparency = strokeTransparency
            label.Visible = true
        end
    end

    local function DrawSkeleton(object, character, camera, color, alpha)
        local rig = object.rig
        if not rig or rig.character ~= character or os.clock() - rig.at > 1 then
            local bones = character:FindFirstChild("UpperTorso") and R15_BONES or R6_BONES
            local parts = {}
            for _, pair in ipairs(bones) do
                for _, name in ipairs(pair) do
                    if not parts[name] then parts[name] = character:FindFirstChild(name) end
                end
            end
            rig = { character = character, at = os.clock(), bones = bones, parts = parts }
            object.rig = rig
        end

        local thickness = EspOpt("boneThick")
        local boneColor = EspOpt("boneRole") and color or EspColour("boneColour")
        for index, pair in ipairs(rig.bones) do
            local a, b = rig.parts[pair[1]], rig.parts[pair[2]]
            if a and b and a.Parent and b.Parent then
                local pa, pb = camera:WorldToViewportPoint(a.Position), camera:WorldToViewportPoint(b.Position)
                if pa.Z > 0.08 and pb.Z > 0.08 then
                    DrawLine(Elem(object, "bone" .. index, 3), Vector2.new(pa.X, pa.Y), Vector2.new(pb.X, pb.Y),
                        thickness, boneColor, 1 - alpha)
                end
            end
        end
    end

    local function DrawHeadDot(object, head, camera, color, alpha, height)
        local point = camera:WorldToViewportPoint(head.Position)
        if point.Z <= 0.08 then return end
        local radius = math.max(3, height * 0.07)
        local frame = object.f.head
        if not frame then
            frame = Elem(object, "head", 3)
            frame.BackgroundTransparency = 1
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = frame
            local stroke = Instance.new("UIStroke")
            stroke.Thickness = 1.5
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke.Parent = frame
            object.headStroke = stroke
        end
        frame.Position = UDim2.fromOffset(point.X, point.Y)
        frame.Size = UDim2.fromOffset(radius * 2, radius * 2)
        object.headStroke.Color = color
        object.headStroke.Transparency = 1 - alpha
        frame.Visible = true
    end

    local function DrawTracer(object, camera, viewport, rect, color, alpha)
        local from = viewport * Vector2.new(0.5, 1)
        local mode = EspOpt("tracerFrom")
        if mode == "Center" then from = viewport * 0.5
        elseif mode == "Top" then from = viewport * Vector2.new(0.5, 0)
        elseif mode == "Mouse" then from = UserInputService:GetMouseLocation() end

        local targetY = rect.y + rect.h
        local target = EspOpt("tracerTo")
        if target == "Center" then targetY = rect.y + rect.h * 0.5
        elseif target == "Head" then targetY = rect.y end

        local tracerColor = EspOpt("tracerRole") and color or EspColour("tracerColour")
        DrawLine(Elem(object, "tracer", 2), from, Vector2.new(rect.x + rect.w * 0.5, targetY),
            EspOpt("tracerThick"), tracerColor, 1 - alpha * math.clamp(EspOpt("tracerAlpha"), 0.05, 1))
    end

    -- Стрелка на краю экрана, если игрок за кадром
    local function DrawArrow(object, camera, viewport, position, color, alpha, distance)
        local relative = camera.CFrame:PointToObjectSpace(position)
        local direction = Vector2.new(relative.X, relative.Z)
        if direction.Magnitude < 0.001 then return end
        direction = direction.Unit

        local radius = math.min(EspOpt("arrowRadius"), math.min(viewport.X, viewport.Y) * 0.45)
        local size = EspOpt("arrowSize")
        local tip = viewport * 0.5 + direction * radius
        local perpendicular = Vector2.new(-direction.Y, direction.X)
        local baseCenter = tip - direction * size * 1.4
        DrawLine(Elem(object, "arrowL", 3), tip, baseCenter + perpendicular * size * 0.8, 2, color, 1 - alpha)
        DrawLine(Elem(object, "arrowR", 3), tip, baseCenter - perpendicular * size * 0.8, 2, color, 1 - alpha)

        if EspOpt("distance") then
            local label = TextElem(object, "arrowText")
            label.AnchorPoint = Vector2.new(0.5, 0.5)
            local textPosition = tip - direction * (size * 3)
            label.Position = UDim2.fromOffset(textPosition.X, textPosition.Y)
            label.Size = UDim2.fromOffset(70, 14)
            label.TextXAlignment = Enum.TextXAlignment.Center
            label.TextSize = 11
            label.Text = DistanceText(distance)
            label.TextColor3 = color
            label.TextTransparency = 1 - alpha
            label.TextStrokeTransparency = 1 - alpha * 0.6
            label.Visible = true
        end
    end

    local function UpdateChams(object, character, color, seen, alpha, distance)
        local limit = EspOpt("chamsMaxDist")
        if not EspOpt("chams") or (limit > 0 and distance > limit) then
            DropChams(object)
            return
        end

        local highlight = object.highlight
        if not highlight or not highlight.Parent then
            Root()
            highlight = Instance.new("Highlight")
            highlight.Name = "YozoraHubChams"
            highlight.Parent = Folder
            object.highlight = highlight
        end
        local chamsColor = EspOpt("chamsRole") and color or EspColour("chamsColour")
        if EspOpt("visCheck") and not seen then chamsColor = EspColour("chamsHidden") end
        highlight.Adornee = character
        highlight.DepthMode = EspOpt("chamsThrough") and Enum.HighlightDepthMode.AlwaysOnTop
            or Enum.HighlightDepthMode.Occluded
        highlight.FillColor = chamsColor
        highlight.OutlineColor = chamsColor
        highlight.FillTransparency = 1 - (1 - math.clamp(EspOpt("chamsFill"), 0, 1)) * alpha
        highlight.OutlineTransparency = 1 - (1 - math.clamp(EspOpt("chamsOutline"), 0, 1)) * alpha
    end

    -- ---------- Обновление одного игрока ----------
    local function UpdatePlayer(player, camera, viewport, delta, now)
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and (character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
        if not (humanoid and root) or humanoid.Health <= 0 then
            Hide(player)
            return
        end

        local role = RoleOf(player, character)
        if not role or not EspOpt(ROLE_FIELDS[role]) then
            Hide(player)
            return
        end

        local cameraPosition = camera.CFrame.Position
        local distance = (root.Position - cameraPosition).Magnitude
        local maxDistance = EspOpt("maxDist")
        if distance > maxDistance then
            Hide(player)
            return
        end

        local object = GetObject(player)
        if object.character ~= character then
            object.character, object.rect, object.rig, object.seenAt = character, nil, nil, nil
            DropChams(object)
        end

        local head = character:FindFirstChild("Head") or root
        if EspOpt("visCheck") and (not object.seenAt or now - object.seenAt > 0.12) then
            object.seen = IsVisible(cameraPosition, head, character)
            object.seenAt = now
        end
        local seen = not EspOpt("visCheck") or object.seen ~= false

        local alpha = (EspOpt("visCheck") and EspOpt("dimHidden") and not seen) and 0.72 or 1
        if EspOpt("fade") then
            local start = maxDistance * 0.6
            if distance > start then
                alpha *= math.clamp(1 - (distance - start) / math.max(maxDistance - start, 1), 0.45, 1)
            end
        end

        local color = EspColour(ROLE_FIELDS[role] .. "Colour")
        UpdateChams(object, character, color, seen, alpha, distance)

        local rect = ProjectBox(character, root, camera, viewport)
        ResetElements(object)

        if not rect then
            -- игрок за кадром: рисуем только стрелку (если включена)
            object.rect = nil
            object.layer.Visible = EspOpt("arrows")
            if EspOpt("arrows") then
                DrawArrow(object, camera, viewport, root.Position, color, alpha, distance)
            end
            return
        end

        rect = Smooth(object, rect, viewport, delta)
        object.layer.Visible = true

        if EspOpt("box") then
            local boxColor = EspOpt("boxColMode") == "Custom" and EspColour("boxColour") or color
            DrawBox(object, rect, boxColor, alpha)
        end

        local skeletonLimit = EspOpt("skelMaxDist")
        if EspOpt("skeleton") and rect.h >= 24 and (skeletonLimit <= 0 or distance <= skeletonLimit) then
            DrawSkeleton(object, character, camera, color, alpha)
        end
        if EspOpt("headDot") then DrawHeadDot(object, head, camera, color, alpha, rect.h) end
        if EspOpt("tracer") then DrawTracer(object, camera, viewport, rect, color, alpha) end
        DrawText(object, rect, player, role, color, alpha, distance, character)
    end

    -- ---------- Выпавший пистолет ----------
    -- Обычная (не слабая) таблица: слабые ключи могли терять пистолет через пару секунд
    local gunDrops = {}
    local gunWatching = false
    local gunObject = nil
    local lastDrop, lastDropAt, lastScan = nil, 0, 0

    local function Remember(part)
        if part.Name == "GunDrop" and part:IsA("BasePart") then
            gunDrops[part] = true
        end
    end

    -- Слежение за GunDrop через DescendantAdded: находит пистолет, где бы он ни лежал
    local function FindDrop()
        if not gunWatching then
            gunWatching = true
            Track(workspace.DescendantAdded:Connect(Remember))
            for _, descendant in ipairs(workspace:GetDescendants()) do
                Remember(descendant)
            end
        end

        local now = os.clock()
        for part in pairs(gunDrops) do
            if part.Parent and part:IsDescendantOf(workspace) then
                lastDrop, lastDropAt = part, now
                return part
            end
            gunDrops[part] = nil
        end

        -- запасной поиск раз в 3 секунды, если событие добавления было пропущено
        if now - lastScan > 3 then
            lastScan = now
            for _, descendant in ipairs(workspace:GetDescendants()) do
                Remember(descendant)
            end
            for part in pairs(gunDrops) do
                if part.Parent then
                    lastDrop, lastDropAt = part, now
                    return part
                end
            end
        end

        -- короткая задержка, чтобы подсветка не мигала при кратковременной потере
        if lastDrop and lastDrop.Parent and now - lastDropAt < 1.5 then
            return lastDrop
        end
        return nil
    end

    local function HideGun()
        if gunObject then
            gunObject.layer.Visible = false
            if gunObject.highlight then
                pcall(function() gunObject.highlight:Destroy() end)
                gunObject.highlight = nil
            end
        end
    end

    local function UpdateGun(camera)
        local drop = EspOpt("gunEsp") and FindDrop() or nil
        if not drop then
            HideGun()
            return
        end
        if not gunObject or not gunObject.layer.Parent then
            local layer = Instance.new("Frame")
            layer.Name = "Gun"
            layer.Size = UDim2.fromScale(1, 1)
            layer.BackgroundTransparency = 1
            layer.BorderSizePixel = 0
            layer.Parent = Root()
            gunObject = { layer = layer, f = {} }
        end

        local color = EspColour("gunColour")
        local point = camera:WorldToViewportPoint(drop.Position + Vector3.new(0, 2, 0))
        local label = TextElem(gunObject, "text")
        if point.Z > 0.08 then
            local distance = (drop.Position - camera.CFrame.Position).Magnitude
            label.AnchorPoint = Vector2.new(0.5, 0.5)
            label.Position = UDim2.fromOffset(point.X, point.Y)
            label.Size = UDim2.fromOffset(160, 18)
            label.TextXAlignment = Enum.TextXAlignment.Center
            label.TextSize = 14
            label.Text = T(L("GUN", "ПИСТОЛЕТ")) .. "  " .. DistanceText(distance)
            label.TextColor3 = color
            label.TextStrokeTransparency = 0.4
            label.Visible = true
        else
            label.Visible = false
        end
        gunObject.layer.Visible = true

        if not gunObject.highlight or not gunObject.highlight.Parent then
            Root()
            local highlight = Instance.new("Highlight")
            highlight.Name = "YozoraHubGun"
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillTransparency = 0.4
            highlight.OutlineTransparency = 0
            highlight.Parent = Folder
            gunObject.highlight = highlight
        end
        gunObject.highlight.Adornee = drop
        gunObject.highlight.FillColor = color
        gunObject.highlight.OutlineColor = color
    end

    -- ---------- Главный цикл ----------
    local function Step(delta)
        if not Alive() then return end
        local camera = workspace.CurrentCamera
        if not camera then return end

        local ok, err = pcall(UpdateGun, camera)
        if not ok and err ~= lastError then
            lastError = err
            warn("[Yozora Hub] gun ESP error: " .. tostring(err))
        end

        if not Settings.ESP then
            if wasOn then
                HideAll()
                wasOn = false
            end
            return
        end
        wasOn = true

        local viewport = camera.ViewportSize
        local now = os.clock()
        local present = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                present[player] = true
                local object = Objects[player]
                if not (object and object.retryAt and now < object.retryAt) then
                    local success, problem = pcall(UpdatePlayer, player, camera, viewport, delta, now)
                    if not success then
                        problem = tostring(problem)
                        if problem ~= lastError then
                            lastError = problem
                            warn("[Yozora Hub] ESP error: " .. problem)
                        end
                        local failed = Objects[player]
                        if failed then
                            failed.retryAt = now + 0.5
                            failed.layer.Visible = false
                            DropChams(failed)
                        end
                    elseif object then
                        object.retryAt = nil
                    end
                end
            end
        end
        for player in pairs(Objects) do
            if not present[player] then Release(player) end
        end
    end

    Track((RunService.PreRender or RunService.RenderStepped):Connect(Step))
    Track(Players.PlayerRemoving:Connect(Release))

    function Esp.setEnabled(enabled)
        if not enabled then
            HideAll()
            wasOn = false
        end
    end

    function Esp.clear()
        HideAll()
        HideGun()
        wasOn = false
    end

    Esp.findDrop = FindDrop
    local function Destroy()
        for player in pairs(Objects) do Release(player) end
        HideGun()
        if gunObject then
            pcall(function() gunObject.layer:Destroy() end)
            gunObject = nil
        end
        if Folder then pcall(function() Folder:Destroy() end) end
        if Gui then pcall(function() Gui:Destroy() end) end
        Gui, Folder = nil, nil
    end
    _G.YozoraHub_EspStop = Destroy
end

-- ==========================================
-- 9c. Визуал: мир, небо, погода, экран, материалы, ауры
-- ==========================================
-- Все изменения запоминают исходные значения и возвращают их при выключении или выгрузке скрипта.
do
    if _G.YozoraHub_VisualStop then pcall(_G.YozoraHub_VisualStop) end

    local Lighting = game:GetService("Lighting")
    local MaterialService = game:GetService("MaterialService")
    local PREFIX = "YozoraHub_"

    local SKIES = {
        { name = "Realistic Sky", faces = {18603249071, 18603241716, 18603244510, 18603245276, 18603246382, 18603261859}, celestial = true, stars = 5000, sun = 60, moon = 1.5, sunTex = "", moonTex = "" },
        { name = "Cloudy Day", faces = {679786546, 680029379, 679786832, 679786679, 679786411, 679787023}, celestial = true, stars = 3000, sun = 21, moon = 11 },
        { name = "Mountain Valley", faces = {324014980, 324015477, 324014995, 324014679, 324015013, 324015409}, celestial = true, stars = 3000, sun = 21, moon = 11 },
        { name = "Mirror Clouds", faces = {150335574, 150335585, 150335628, 150335620, 150335610, 150335642}, celestial = true, stars = 1334, sun = 21, moon = 11 },
        { name = "Dark Storm", faces = {5098786959, 5098787359, 5098787913, 5098788567, 5098789278, 5098789770}, celestial = true, stars = 0, sun = 15, moon = 0 },
        { name = "Rain Sky", faces = {4495864450, 4495864887, 4495865458, 4495866035, 4495866584, 4495867486}, celestial = true, stars = 3000, sun = 1, moon = 1, sunTex = "", moonTex = "" },
        { name = "Anime Sky", faces = {15983968922, 15983966825, 15983965025, 15983967420, 15983966246, 15983964246}, celestial = true, stars = 3000, sun = 21, moon = 11 },
        { name = "Anime Ocean", faces = {18351376859, 18351374919, 18351376800, 18351376469, 18351376457, 18351377189}, celestial = true, stars = 3000, sun = 21, moon = 11 },
        { name = "Heavenly Clouds", faces = {81858382098344, 138472117789684, 95687237979398, 84924000207295, 99961685452126, 104038404823203}, celestial = false, stars = 5000, sun = 11, moon = 11, sunTex = "rbxassetid://6196665106", moonTex = "rbxassetid://6444320592" },
        { name = "Rainbow Clouds", faces = {16573631102, 16573631950, 16573632795, 16573633258, 16573633908, 16573634370}, celestial = true, stars = 3000, sun = 21, moon = 11 },
        { name = "Violet Dream", faces = {570557514, 570557775, 570557559, 570557620, 570557672, 570557727}, celestial = false, stars = 3000, sun = 21, moon = 11 },
        { name = "Cartoon Sky", faces = {5333954202, 5333944933, 5333954202, 5333954202, 5333954202, 5333943668}, celestial = true, stars = 3000, sun = 21, moon = 11 },
        { name = "Pastel Sky", faces = {566605702, 566605472, 566605507, 566605542, 566605588, 566605643}, celestial = false, stars = 3000, sun = 21, moon = 11 },
        { name = "Pink Sky", faces = {271042516, 271077243, 271042556, 271042310, 271042467, 271077958}, celestial = false, stars = 1334, sun = 21, moon = 11 },
        { name = "Minecraft Sky", faces = {599982473, 599982473, 599982473, 599982473, 599982473, 599982473}, celestial = true, stars = 3000, sun = 21, moon = 11 },
        { name = "Blood Sky", faces = {108929045660200, 78646480540009, 90546017435179, 109838453114563, 94190734796082, 126944775797063}, celestial = false, stars = 3000, sun = 21, moon = 11 },
        { name = "Moonlit Night", faces = {6285719338, 6285721078, 6285722964, 6285724682, 6285726335, 6285730635}, celestial = false, stars = 3000, sun = 21, moon = 11 },
        { name = "Starry Night", faces = {154185004, 154184960, 154185021, 154184943, 154184972, 154185031}, celestial = false, stars = 0, sun = 21, moon = 11 },
        { name = "Space Sky", faces = {16262356578, 16262358026, 16262360469, 16262362003, 16262363873, 16262366016}, celestial = false, stars = 3000, sun = 21, moon = 11 },
        { name = "Earth Orbit", faces = {166509999, 166510057, 166510116, 166510092, 166510131, 166510114}, celestial = true, stars = 0, sun = 21, moon = 11 },
        { name = "Pink Nebula", faces = {13581437029, 13581439832, 13581447312, 13581443463, 13581452875, 13581450222}, celestial = true, stars = 3000, sun = 21, moon = 11 },
        { name = "Rainbow Galaxy", faces = {3192404459, 3192404459, 3192404459, 3192404459, 3192404459, 3192404459}, celestial = false, stars = 3000, sun = 21, moon = 11 },
        { name = "Clear Blue", faces = {591058823, 591059876, 591058104, 591057861, 591057625, 591059642}, celestial = true, stars = 3000, sun = 21, moon = 11 },
        { name = "Realistic Day", faces = {144933338, 144931530, 144933262, 144933244, 144933299, 144931564}, celestial = true, stars = 1500, sun = 5, moon = 11 },
        { name = "Cumulus", faces = {225469345, 225469349, 225469359, 225469364, 225469372, 225469380}, celestial = false, stars = 0, sun = 21, moon = 11 },
        { name = "Golden Clouds", faces = {252760981, 252763035, 252761439, 252760980, 252760986, 252762652}, celestial = true, stars = 3000, sun = 11, moon = 11 },
        { name = "Golden Haze", faces = {600830446, 600831635, 600832720, 600886090, 600833862, 600835177}, celestial = true, stars = 3000, sun = 21, moon = 11 },
        { name = "Sunset", faces = {169210090, 169210108, 169210121, 169210133, 169210143, 169210149}, celestial = true, stars = 1000, sun = 21, moon = 11 },
        { name = "Fiery Sunset", faces = {458016711, 458016826, 458016532, 458016655, 458016782, 458016792}, celestial = true, stars = 3000, sun = 21, moon = 11 },
        { name = "Amber Dusk", faces = {541743453, 541743443, 541743446, 541743436, 541743435, 541743441}, celestial = true, stars = 3000, sun = 21, moon = 11 },
        { name = "Classic Dusk", faces = {15502525195, 15502522797, 15502524520, 15502522129, 15502523711, 15502526102}, celestial = false, stars = 0, sun = 21, moon = 11 },
        { name = "Rose Dusk", faces = {323494035, 323494368, 323494130, 323494252, 323494067, 323493360}, celestial = false, stars = 0, sun = 21, moon = 11 },
        { name = "Mountain Sunset", faces = {248158002, 248157859, 248158032, 248157792, 248157954, 248158064}, celestial = false, stars = 0, sun = 21, moon = 11 },
        { name = "Overcast", faces = {15063412549, 15063341496, 15063442046, 15063367382, 15063435355, 15063353447}, celestial = true, stars = 3000, sun = 9, moon = 6, atmo = { color = Color3.fromRGB(170, 176, 186), decay = Color3.fromRGB(130, 136, 148), density = 0.3, haze = 1.5 } },
        { name = "Storm", faces = {3030637176, 3030631606, 3030636397, 3030637524, 3030637746, 3030631241}, celestial = false, stars = 0, sun = 21, moon = 11, atmo = { color = Color3.fromRGB(118, 126, 140), decay = Color3.fromRGB(90, 98, 112), density = 0.38, haze = 2.2 } },
        { name = "Foggy Sea", faces = {15876597103, 15876592775, 15876640231, 15876638420, 15876595486, 15876639348}, celestial = false, stars = 0, sun = 21, moon = 11, atmo = { color = Color3.fromRGB(192, 200, 208), decay = Color3.fromRGB(160, 168, 178), density = 0.5, haze = 2.4 } },
        { name = "Whiteout", faces = {16653221738, 16653222701, 16653224051, 16653225849, 16653227200, 16653228333}, celestial = false, stars = 0, sun = 21, moon = 11, atmo = { color = Color3.fromRGB(226, 232, 240), decay = Color3.fromRGB(190, 200, 214), density = 0.46, haze = 2.4 } },
        { name = "Night Mountains", faces = {12064107, 12064152, 12064121, 12063984, 12064115, 12064131}, celestial = false, stars = 0, sun = 21, moon = 11 },
        { name = "Aurora Fjord", faces = {1189339378, 1189340601, 1189339741, 1189339550, 1189339155, 1189340203}, celestial = false, stars = 0, sun = 12, moon = 1.5 },
        { name = "Aurora Lake", faces = {340908398, 340908450, 340908468, 340908504, 340908530, 340908586}, celestial = false, stars = 0, sun = 21, moon = 11 },
        { name = "Aurora Teal", faces = {16207153240, 16207154905, 16207157300, 16207158867, 16207160340, 16207163444}, celestial = false, stars = 0, sun = 21, moon = 11 },
        { name = "City Night", faces = {9758787043, 9758786250, 9758784754, 9758785370, 9758783070, 9758783885}, celestial = false, stars = 0, sun = 21, moon = 11 },
        { name = "Purple Nebula", faces = {14543264135, 14543358958, 14543257810, 14543275895, 14543280890, 14543371676}, celestial = true, stars = 3000, sun = 21, moon = 11 },
        { name = "Neon Dusk", faces = {5084575798, 5084575916, 5103949679, 5103948542, 5103948784, 5084576400}, celestial = true, stars = 3000, sun = 21, moon = 11 },
    }

    local MATERIAL_PACKS = { ["HD Realistic"] = { Concrete = { "10443938843", "10443939759", "10443936610",
    "10443935964", 10 }, Brick = { "11286302911", "11286304351", "11286305553", "", 10 }, Cobblestone = { "9809148719", "9809147846", "9809147255",
    "8474851245", 8 }, Slate = { "11257042356", "11257043180", "11257043424", "", 10 }, Wood = { "10410998493", "10410996854", "10410996270",
    "10410994829", 10 }, WoodPlanks = { "10966335665", "9342344580", "9413505842", "9315036917", 4 }, Metal = { "9718503974", "9718569957",
    "9718503496", "9718503824", 1 }, DiamondPlate = { "10411448016", "10411447332", "10411446173", "10411446410", 10 }, Pebble = { "9238988114",
    "9238996950", "9238997838", "9238989428", 10 }, Marble = { "11257068609", "11257068991", "11257069244", "", 10 }, Granite = { "10443648556",
    "10443646185", "10443646640", "10443646034", 10 }, Pavement = { "11286723960", "11286724430", "11286724743", "", 10 }, Asphalt = { "10443946973",
    "10443947640", "10443945728", "10443943667", 10 }, Fabric = { "11257395053", "11257395673", "11257395332", "", 10 }, Sand = { "11264837385",
    "11264839079", "11264837911", "", 10 } }, ["HD Worn"] = { Concrete = { "10443872402", "10443873501", "10443871824", "10443869736",
    10 }, Brick = { "11286485395", "11286488992", "11286488283", "", 10 }, Cobblestone = { "10438628866", "10438630133", "10438627717",
    "10438625307", 10 }, Slate = { "11257048246", "11257049051", "11257048107", "", 10 }, Wood = { "10410966681", "10410967489", "10410967165",
    "10410965264", 10 }, WoodPlanks = { "10411259989", "10411261300", "10411259790", "10411258647", 10 }, Metal = { "10411439815", "10411439389",
    "10411439482", "10411438561", 10 }, DiamondPlate = { "10411461737", "10411459708", "10411460007", "10411461091", 10 }, Pebble = { "11264912848",
    "11264913303", "11264913449", "", 10 }, Marble = { "11257084331", "11257084469", "11257084659", "", 10 }, Granite = { "10443624631",
    "10443624946", "10443624251", "10443621368", 10 }, Pavement = { "11286615368", "11286615336", "11286615689", "", 10 }, Asphalt = { "10443961930",
    "10443960967", "10443961048", "10443957944", 10 }, Fabric = { "11257368544", "11257368931", "11257368858", "", 10 }, Sand = { "11264963943",
    "11264966098", "11264966925", "", 10 } }, ["HD Wet"] = { Concrete = { "8785389518", "8785388974", "10696235306", "8785389135", 10 },
    Brick = { "11286302911", "11286304351", "11286305553", "", 10 }, Cobblestone = { "9809148719", "", "9781671574", "9781989836", 8 },
    Slate = { "11257042356", "11257043180", "11257043424", "", 10 }, Wood = { "10410998493", "10410996854", "10410996270", "10410994829",
    10 }, WoodPlanks = { "10966178956", "8387480942", "8387481676", "8378675659", 4 }, Metal = { "10434694300", "10434693710", "10434693479",
    "10434693088", 10 }, DiamondPlate = { "10411448016", "10411447332", "10411446173", "10411446410", 10 }, Pebble = { "9812112815", "",
    "9781671574", "9781989836", 6 }, Marble = { "18860609525", "18860610576", "18860611250", "18860609910", 10 }, Granite = { "18820825843",
    "18820831781", "18820832525", "18820830116", 10 }, Pavement = { "9809148719", "", "9781671574", "9781989836", 8 }, Asphalt = { "9812112815",
    "", "9781671574", "9781989836", 6 }, Fabric = { "11257395053", "11257395673", "11257395332", "", 10 }, Sand = { "9812112815", "",
    "9781671574", "9781989836", 6 } } }

    -- ---------- Данные погоды ----------
    local textures, sounds = { streak = "rbxassetid://241868005", streak2 = "rbxassetid://1890057258", drop = "rbxassetid://242096290", ring = "rbxassetid://838367768",
	splash = "rbxassetid://241576804", sheet = "rbxassetid://1742722513", flake = "rbxassetid://5914376718", glow = "rbxassetid://243664672",
	dot = "rbxassetid://9829889760", soft = "rbxassetid://118641183", fine = "rbxassetid://247944275", petal = "rbxassetid://243160943", petal2 = "rbxassetid://243344623",
	leaf = "rbxassetid://5057182105", fog = "rbxassetid://248376121", fog2 = "rbxassetid://292289455" }, { wind = "rbxassetid://9116258071",
	crickets = "rbxassetid://9112764546", night = "rbxassetid://9112835862", fire = "rbxassetid://9112780193", birds = "rbxassetid://9112835056",
	howl = "rbxassetid://9114625552", thunderClose = { "rbxassetid://9120016037", "rbxassetid://9120016021", "rbxassetid://9120016256", "rbxassetid://9120016241" },
	thunderFar = { "rbxassetid://9120016766", "rbxassetid://9120017482", "rbxassetid://9120017674", "rbxassetid://9120016245", "rbxassetid://9120017048" },
	crack = { "rbxassetid://9116282544", "rbxassetid://9116282647", "rbxassetid://9116282646" } };
	
    local recipes = { Snow = { colour = "snowColour", grade = "Snow", wet = false, voices = { { id = sounds.wind, base = 0.5, lo = 0.4, hi = 1,
	wind = true }, { id = sounds.howl, base = 0.35, lo = 0, hi = 0.9, from = 0.6, wind = true } }, layers = { { tex = "soft", y = 12, h = 30,
	reach = 1.25, rate = { 140, 950 }, life = { 8, 11 }, speed = { 0.4, 1.4 }, fall = 2.6, size = { 0.16, 0.3 }, alpha = 0.97, spread = 180,
	drag = 0.75, light = 0.85, glow = 0.15, sway = 0.55, tint = 0 }, { tex = "soft", y = 8, h = 16, reach = 0.55, rate = { 6, 70 }, life = { 6,
	9 }, speed = { 0.3, 1 }, fall = 2.2, size = { 0.3, 0.46 }, alpha = 0.9, spread = 180, drag = 0.75, light = 0.85, glow = 0.12, sway = 0.7,
	tint = 0 }, { tex = "fine", y = 14, h = 34, reach = 1.5, rate = { 40, 300 }, life = { 9, 12 }, speed = { 0.2, 0.8 }, fall = 3, size = { 0.12,
	0.2 }, alpha = 0.9, spread = 180, drag = 0.7, light = 0.8, glow = 0.2, sway = 0.5, tint = 0 }, { tex = "fog", base = "ground", y = 1.8,
	h = 4, reach = 1.5, rate = { 0.1, 1 }, life = { 8, 12 }, speed = { 0.3, 0.9 }, size = { 16, 28 }, alpha = 0.08, spread = 180, light = 1,
	glow = 0, tint = 0, rot = 4, noShelter = true, still = true, drift = 0.4 } } }, Blossom = { colour = "petalColour", wet = false, voices = { { id = sounds.wind,
	base = 0.35, lo = 0.35, hi = 0.8, wind = true }, { id = sounds.birds, base = 0.5, lo = 0.5, hi = 0.5, steady = true } }, layers = { { tex = "petal",
	y = 12, h = 28, reach = 1.4, rate = { 5, 60 }, life = { 10, 14 }, speed = { 0, 0 }, fall = 1.7, size = { 0.42, 0.7 }, alpha = 1,
	spread = 30, drag = 0.6, rot = 150, flutter = true, light = 0.7, glow = 0.05, sway = 2, windK = 1.5, tint = 0 }, { tex = "petal2",
	y = 8, h = 16, reach = 0.7, rate = { 3, 36 }, life = { 8, 11 }, speed = { 0, 0 }, fall = 1.7, size = { 0.34, 0.54 }, alpha = 1,
	spread = 30, drag = 0.6, rot = 170, flutter = true, light = 0.7, glow = 0.05, sway = 1.6, windK = 1.5, tint = 0 } } }, Leaves = { colour = "leafColour",
	wet = false, voices = { { id = sounds.wind, base = 0.55, lo = 0.4, hi = 1, wind = true }, { id = sounds.birds, base = 0.4, lo = 0.4, hi = 0.4,
	steady = true } }, layers = { { tex = "leaf", y = 12, h = 28, reach = 1.4, rate = { 5, 46 }, life = { 10, 14 }, speed = { 0, 0 },
	fall = 2.8, size = { 0.7, 1.15 }, alpha = 1, spread = 30, drag = 0.55, rot = 220, flutter = true, light = 0.75, glow = 0, sway = 2.5,
	windK = 1.9, col = Color3.fromRGB(255, 150, 60), tint = 0 }, { tex = "leaf", y = 10, h = 24, reach = 1.2, rate = { 4, 38 }, life = { 10,
	14 }, speed = { 0, 0 }, fall = 2.8, size = { 0.64, 1.05 }, alpha = 1, spread = 30, drag = 0.55, rot = 200, flutter = true, light = 0.75,
	glow = 0, sway = 2.3, windK = 1.9, col = Color3.fromRGB(235, 90, 50), tint = 0 }, { tex = "leaf", y = 8, h = 18, reach = 0.7,
	rate = { 3, 28 }, life = { 8, 11 }, speed = { 0, 0 }, fall = 2.8, size = { 0.78, 1.25 }, alpha = 1, spread = 30, drag = 0.55, rot = 180,
	flutter = true, light = 0.75, glow = 0, sway = 2, windK = 1.9, col = Color3.fromRGB(255, 205, 80), tint = 0 } } }, Fireflies = { colour = "fireflyColour",
	grade = "Fireflies", wet = false, voices = { { id = sounds.crickets, base = 0.7, lo = 0.7, hi = 0.7, steady = true }, { id = sounds.night,
	base = 0.25, lo = 0.25, hi = 0.25, steady = true } }, layers = { { tex = "glow", base = "ground", y = 3.6, h = 6.5, reach = 1.2, rate = { 1.5,
	16 }, life = { 5, 8 }, speed = { 0.3, 0.9 }, size = { 0.34, 0.6 }, alpha = 1, spread = 180, drag = 0.9, light = 0, glow = 1, sway = 0.9,
	pulse = true, noShelter = true, noWind = true, tint = 0.15 }, { tex = "glow", base = "ground", y = 3.2, h = 5, reach = 0.8, rate = { 0.5,
	6 }, life = { 5, 8 }, speed = { 0.2, 0.6 }, size = { 1.4, 2.1 }, alpha = 0.12, spread = 180, drag = 0.9, light = 0, glow = 1, sway = 0.7,
	pulse = true, noShelter = true, noWind = true, tint = 0.3 }, { tex = "fog", base = "ground", y = 1.6, h = 3, reach = 1.5, rate = { 0.2,
	1.2 }, life = { 9, 13 }, speed = { 0.3, 0.8 }, size = { 16, 26 }, alpha = 0.07, spread = 180, light = 1, glow = 0, tint = 0, rot = 4,
	noShelter = true, still = true, drift = 0.3 } } }, Mist = { colour = "mistColour", wet = false, voices = { { id = sounds.wind, base = 0.25,
	lo = 0.2, hi = 0.5, wind = true }, { id = sounds.birds, base = 0.25, lo = 0.25, hi = 0.25, steady = true } }, layers = { { tex = "fog",
	base = "ground", y = 2, h = 4, reach = 1.7, rate = { 0.6, 4 }, life = { 9, 13 }, speed = { 0.4, 1.1 }, size = { 18, 30 }, alpha = 0.18,
	spread = 180, light = 1, glow = 0, tint = 0, rot = 4, noShelter = true, still = true, drift = 0.5 }, { tex = "fog2", base = "ground",
	y = 4, h = 5, reach = 1.5, rate = { 0.3, 2 }, life = { 10, 14 }, speed = { 0.3, 0.8 }, size = { 22, 36 }, alpha = 0.1, spread = 180,
	light = 1, glow = 0, tint = 0, rot = 3, noShelter = true, still = true, drift = 0.4 }, { tex = "dot", y = 5, h = 10, reach = 0.6,
	rate = { 2, 20 }, life = { 6, 10 }, speed = { 0.1, 0.4 }, size = { 1.6, 2.6 }, alpha = 0.8, spread = 180, drag = 0.8, light = 0,
	glow = 1, sway = 0.5, flicker = true, noShelter = true, noWind = true, tint = 0.2 } } }, Embers = { colour = "emberColour", grade = "Embers",
	wet = false, voices = { { id = sounds.fire, base = 0.7, lo = 0.5, hi = 1, steady = true }, { id = sounds.night, base = 0.2, lo = 0.2, hi = 0.2,
	steady = true } }, layers = { { tex = "glow", base = "ground", y = 4, h = 8, reach = 1, rate = { 4, 44 }, life = { 2.2, 4 }, speed = { 1.6,
	3.4 }, size = { 0.16, 0.34 }, alpha = 1, spread = 35, drag = 0.3, light = 0, glow = 1, sway = 3, lift = 3.4, noShelter = true, fire = true,
	windK = 0.7 }, { tex = "dot", base = "ground", y = 3, h = 6, reach = 0.7, rate = { 6, 70 }, life = { 1.2, 2.4 }, speed = { 2, 4.5 },
	size = { 1.4, 2.4 }, alpha = 1, spread = 40, drag = 0.3, light = 0, glow = 1, sway = 2.2, lift = 3, noShelter = true, fire = true,
	windK = 0.7, flicker = true } } }, Ash = { colour = "ashColour", grade = "Ash", wet = false, voices = { { id = sounds.wind, base = 0.35,
	lo = 0.3, hi = 0.8, wind = true }, { id = sounds.fire, base = 0.3, lo = 0.3, hi = 0.6, steady = true } }, layers = { { tex = "glow", y = 12,
	h = 28, reach = 1.3, rate = { 12, 120 }, life = { 8, 12 }, speed = { 0, 0 }, fall = 1.4, size = { 0.16, 0.3 }, alpha = 0.6, spread = 30,
	drag = 0.55, rot = 40, light = 1, glow = 0, sway = 1.4, tint = 0 }, { tex = "glow", base = "ground", y = 4, h = 8, reach = 0.8, rate = { 1,
	14 }, life = { 2.2, 4 }, speed = { 1.6, 3.4 }, size = { 0.16, 0.3 }, alpha = 1, spread = 35, drag = 0.3, light = 0, glow = 1, sway = 2.6,
	lift = 3.2, noShelter = true, fire = true, col2 = "emberColour", windK = 0.7 } } }, Pollen = { colour = "pollenColour", wet = false, voices = { { id = sounds.wind,
	base = 0.2, lo = 0.2, hi = 0.5, wind = true }, { id = sounds.birds, base = 0.55, lo = 0.55, hi = 0.55, steady = true } }, layers = { { tex = "glow",
	y = 5, h = 11, reach = 0.7, rate = { 2, 26 }, life = { 6, 10 }, speed = { 0.1, 0.4 }, size = { 0.12, 0.24 }, alpha = 0.9, spread = 180,
	drag = 0.8, light = 0, glow = 1, sway = 0.6, flicker = true, noShelter = true, noWind = true, tint = 0.2 }, { tex = "glow", y = 6,
	h = 14, reach = 1.1, rate = { 1, 14 }, life = { 8, 12 }, speed = { 0.1, 0.3 }, size = { 0.6, 1.1 }, alpha = 0.16, spread = 180, drag = 0.8,
	light = 0, glow = 1, sway = 0.5, flicker = true, noShelter = true, noWind = true, tint = 0.3 } } } };
	
    local SCENES = {
        { name = "Misty Morning", sky = "Foggy Sea", look = "Overcast", weather = { kind = "Mist", amount = 70, wind = 2 } },
        { name = "Snow Day", sky = "Whiteout", look = "Overcast", weather = { kind = "Snow", amount = 55, wind = 4 } },
        { name = "Blizzard", sky = "Whiteout", look = "Overcast", weather = { kind = "Snow", amount = 100, wind = 16, speed = 130 } },
        { name = "Winter Night", sky = "Aurora Fjord", look = "Night", weather = { kind = "Snow", amount = 45, wind = 3 } },
        { name = "Cherry Blossom", sky = "Rose Dusk", look = "Dusk", weather = { kind = "Blossom", amount = 62, wind = 5 } },
        { name = "Autumn", sky = "Golden Clouds", look = "Golden Hour", weather = { kind = "Leaves", amount = 58, wind = 7 } },
        { name = "Golden Pollen", sky = "Sunset", look = "Golden Hour", weather = { kind = "Pollen", amount = 62, wind = 2 } },
        { name = "Firefly Night", sky = "Night Mountains", look = "Night", weather = { kind = "Fireflies", amount = 65, wind = 1 } },
        { name = "Bonfire Night", sky = "Classic Dusk", look = "Night", weather = { kind = "Embers", amount = 55, wind = 3 } },
        { name = "Volcano", sky = "Fiery Sunset", look = "Dusk", weather = { kind = "Ash", amount = 70, wind = 5 } },
    }

    -- ---------- Пресеты мира ----------
    local PRESETS = {
        Natural = { gradeOn = true, contrast = 0.1, saturation = 0.08, tint = "fff8ee",
            bloomOn = true, bloomIntensity = 0.2, bloomSize = 22, bloomThreshold = 1.4,
            raysOn = true, raysIntensity = 0.05, vignetteOn = true, vignette = 22 },
        Cinematic = { gradeOn = true, gradeBright = -0.02, contrast = 0.22, saturation = -0.05, tint = "e8f2ff",
            bloomOn = true, bloomIntensity = 0.28, bloomSize = 26, bloomThreshold = 1.3,
            dofOn = true, dofFar = 0.14, dofFocus = 50, dofRadius = 60, vignetteOn = true, vignette = 42,
            exposureOn = true, exposure = -0.1 },
        ["Golden Hour"] = { timeOn = true, time = 17.4, gradeOn = true, contrast = 0.14, saturation = 0.16, tint = "ffe0b4",
            bloomOn = true, bloomIntensity = 0.34, bloomSize = 28, bloomThreshold = 1.2,
            raysOn = true, raysIntensity = 0.12, raysSpread = 0.9,
            atmosOn = true, density = 0.32, offset = 0.1, haze = 1.4, glare = 0.4, atmosColour = "ffd29a", decay = "c9854a" },
        Dusk = { timeOn = true, time = 18.4, gradeOn = true, contrast = 0.18, saturation = 0.18, tint = "ffc8e0",
            bloomOn = true, bloomIntensity = 0.4, bloomSize = 30, bloomThreshold = 1.1,
            atmosOn = true, density = 0.34, haze = 1.6, atmosColour = "f3a8c8", decay = "8a4a78", vignetteOn = true, vignette = 30 },
        Night = { timeOn = true, time = 0, ambientOn = true, ambient = "3c4664", outdoor = "46507a",
            gradeOn = true, contrast = 0.15, saturation = -0.08, tint = "b8cfff",
            bloomOn = true, bloomIntensity = 0.5, bloomSize = 30, bloomThreshold = 1, vignetteOn = true, vignette = 40 },
        Moonlight = { timeOn = true, time = 23.4, ambientOn = true, ambient = "5a6890", outdoor = "6a78a8",
            gradeOn = true, contrast = 0.12, saturation = -0.05, tint = "c6d8ff",
            bloomOn = true, bloomIntensity = 0.42, bloomSize = 28, bloomThreshold = 1.1, raysOn = true, raysIntensity = 0.04 },
        Vivid = { gradeOn = true, contrast = 0.16, saturation = 0.45, tint = "ffffff",
            bloomOn = true, bloomIntensity = 0.24, bloomSize = 24, bloomThreshold = 1.3 },
        Overcast = { gradeOn = true, contrast = 0.04, saturation = -0.2, tint = "e6eef6",
            cloudsOn = true, cloudCover = 0.9, cloudDensity = 0.8, cloudColour = "9aa0aa",
            atmosOn = true, density = 0.38, haze = 2.4, atmosColour = "b8c2cc", decay = "7a8590" },
        Noir = { gradeOn = true, contrast = 0.36, saturation = -1, tint = "ffffff",
            bloomOn = true, bloomIntensity = 0.2, vignetteOn = true, vignette = 55 },
        Neon = { timeOn = true, time = 0, gradeOn = true, contrast = 0.2, saturation = 0.5, tint = "ffb8ff",
            bloomOn = true, bloomIntensity = 0.75, bloomSize = 36, bloomThreshold = 0.9, vignetteOn = true, vignette = 30 },
        Sakura = { timeOn = true, time = 16.5, gradeOn = true, contrast = 0.1, saturation = 0.26, tint = "ffd6e8",
            bloomOn = true, bloomIntensity = 0.5, bloomSize = 30, bloomThreshold = 1.1,
            atmosOn = true, density = 0.3, haze = 1.3, atmosColour = "ffc8e1", decay = "b86a96", vignetteOn = true, vignette = 24 },
        Summer = { timeOn = true, time = 13, brightOn = true, brightness = 3, gradeOn = true, contrast = 0.1, saturation = 0.22, tint = "fff4d6",
            bloomOn = true, bloomIntensity = 0.26, raysOn = true, raysIntensity = 0.08 },
        Autumn = { timeOn = true, time = 16.6, gradeOn = true, contrast = 0.12, saturation = 0.2, tint = "ffc88c",
            bloomOn = true, bloomIntensity = 0.3, atmosOn = true, density = 0.3, haze = 1.5, atmosColour = "e8b27a", decay = "9a6038" },
        Frostbite = { gradeOn = true, contrast = 0.1, saturation = -0.12, tint = "d2e6ff",
            bloomOn = true, bloomIntensity = 0.42, bloomSize = 30, fogOn = true, fogStart = 50, fogEnd = 800, fogColour = "dce8ff" },
        Toxic = { timeOn = true, time = 21, gradeOn = true, contrast = 0.16, saturation = 0.3, tint = "b6ff94",
            bloomOn = true, bloomIntensity = 0.6, bloomSize = 32, fogOn = true, fogStart = 30, fogEnd = 700, fogColour = "6aa83c" },
        Horror = { timeOn = true, time = 0, gradeOn = true, contrast = 0.28, saturation = -0.3, tint = "e8ffe8",
            vignetteOn = true, vignette = 62, fogOn = true, fogStart = 20, fogEnd = 450, fogColour = "141a14" },
        Competitive = { noPost = true, noShadows = true, noAtmos = true, brightOn = true, brightness = 2.5,
            gradeOn = true, contrast = 0.12, saturation = 0.1, tint = "ffffff" },
    }

    local WORLD_KEYS = {
        "worldOn", "preset", "tech", "brightOn", "brightness", "timeOn", "time", "ambientOn", "ambient", "outdoor",
        "exposureOn", "exposure", "noShadows", "shadowSoftOn", "shadowSoft", "fogOn", "fogStart", "fogEnd", "fogColour",
        "atmosOn", "density", "offset", "haze", "glare", "atmosColour", "decay", "noAtmos", "noPost",
        "cloudsOn", "cloudCover", "cloudDensity", "cloudColour", "gradeOn", "gradeBright", "contrast", "saturation", "tint",
        "bloomOn", "bloomIntensity", "bloomSize", "bloomThreshold", "raysOn", "raysIntensity", "raysSpread",
        "dofOn", "dofFar", "dofFocus", "dofRadius", "vignetteOn", "vignette",
    }

    local dirty = true
    local savePending = false
    local function Save()
        if savePending then return end
        savePending = true
        task.delay(0.8, function()
            savePending = false
            SaveConfig()
        end)
    end

    -- ---------- Запоминание и восстановление свойств ----------
    local Saved = {} -- обычная таблица: исходные значения нельзя терять

    local function Remember(object, property)
        local props = Saved[object]
        if props and props[property] then return props[property] end
        local ok, value = pcall(function() return object[property] end)
        if not ok then return nil end
        props = props or {}
        Saved[object] = props
        props[property] = { value = value }
        return props[property]
    end

    local function Release(object, property)
        local props = Saved[object]
        local saved = props and props[property]
        if not saved then return end
        pcall(function()
            local current = object[property]
            -- игра сама изменила значение после нас: уважаем её значение
            if saved.written and current ~= saved.last then saved.value = current end
            object[property] = saved.value
        end)
        props[property] = nil
        if not next(props) then Saved[object] = nil end
    end

    local function Sync(object, property, enabled, value)
        if not object then return end
        if not enabled then
            Release(object, property)
            return
        end
        local saved = Remember(object, property)
        if not saved then return end
        pcall(function()
            local current = object[property]
            if saved.written and current ~= saved.last then saved.value = current end
            saved.written = true
            if current ~= value then object[property] = value end
            saved.last = object[property]
        end)
    end

    local function ReleaseAll()
        for object, props in pairs(Saved) do
            for property in pairs(props) do Release(object, property) end
        end
    end

    -- Объекты игры нужного класса (наши, с префиксом, пропускаем; скрытые нами тоже находим)
    local function Targets(parent, class)
        local list, seen = {}, {}
        if parent then
            for _, child in ipairs(parent:GetChildren()) do
                if child:IsA(class) and child.Name:sub(1, #PREFIX) ~= PREFIX then
                    table.insert(list, child)
                    seen[child] = true
                end
            end
        end
        for object, props in pairs(Saved) do
            if not seen[object] and props.Parent and props.Parent.value == parent and object:IsA(class) then
                table.insert(list, object)
            end
        end
        return list
    end

    -- Наши собственные объекты
    local Owned = {}
    local function Drop(name)
        local object = Owned[name]
        Owned[name] = nil
        if object then pcall(function() object:Destroy() end) end
    end
    local function Ensure(name, class, parent)
        local object = Owned[name]
        if object and object.Parent == parent then return object end
        Drop(name)
        local ok, created = pcall(function()
            local instance = Instance.new(class)
            instance.Name = PREFIX .. name
            instance.Parent = parent
            return instance
        end)
        if not ok then return nil end
        Owned[name] = created
        return created
    end
    local function Configure(name, class, enabled, props)
        if not enabled then
            Drop(name)
            return
        end
        local object = Ensure(name, class, Lighting)
        if not object then return end
        for property, value in pairs(props) do
            pcall(function() object[property] = value end)
        end
        pcall(function() object.Enabled = true end)
    end

    local function ParentForGui()
        local ok, holder = pcall(function() return (gethui and gethui()) or game:GetService("CoreGui") end)
        return ok and holder or PlayerGui
    end

    -- Виньетка
    local VignetteGui, VignetteEdges = nil, {}
    local function Vignette(enabled, amount)
        if not enabled then
            if VignetteGui then pcall(function() VignetteGui:Destroy() end) end
            VignetteGui, VignetteEdges = nil, {}
            return
        end
        if not VignetteGui or not VignetteGui.Parent then
            local gui = Instance.new("ScreenGui")
            gui.Name = PREFIX .. "Vignette"
            gui.ResetOnSpawn = false
            gui.IgnoreGuiInset = true
            gui.DisplayOrder = 5
            local ok = pcall(function() gui.Parent = ParentForGui() end)
            if not ok or not gui.Parent then gui.Parent = PlayerGui end
            VignetteGui, VignetteEdges = gui, {}
            for index = 1, 4 do
                local frame = Instance.new("Frame")
                frame.BorderSizePixel = 0
                frame.Active = false
                frame.BackgroundColor3 = Color3.new(0, 0, 0)
                frame.Size = index <= 2 and UDim2.fromScale(1, 0.28) or UDim2.fromScale(0.23, 1)
                if index == 2 then frame.Position = UDim2.fromScale(0, 0.72) end
                if index == 4 then frame.Position = UDim2.fromScale(0.77, 0) end
                frame.Parent = gui
                local gradient = Instance.new("UIGradient")
                gradient.Rotation = ({ 90, 270, 0, 180 })[index]
                gradient.Parent = frame
                table.insert(VignetteEdges, gradient)
            end
        end
        local transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1 - math.clamp(amount / 100, 0, 0.85)),
            NumberSequenceKeypoint.new(1, 1),
        })
        for _, gradient in ipairs(VignetteEdges) do gradient.Transparency = transparency end
    end

    -- ---------- Мир: освещение, пост-эффекты, атмосфера ----------
    local function WorldApply()
        local on = VisOpt("worldOn")
        local function opt(key) return VisOpt(key) end
        local function color(key) return VisColor(key) end

        local technology = nil
        if on and opt("tech") ~= "Game" then
            pcall(function() technology = Enum.Technology[opt("tech")] end)
        end
        Sync(Lighting, "Technology", technology ~= nil, technology)
        Sync(Lighting, "Brightness", on and opt("brightOn"), opt("brightness"))
        Sync(Lighting, "ClockTime", on and opt("timeOn"), opt("time") % 24)
        Sync(Lighting, "Ambient", on and opt("ambientOn"), color("ambient"))
        Sync(Lighting, "OutdoorAmbient", on and opt("ambientOn"), color("outdoor"))
        Sync(Lighting, "ExposureCompensation", on and opt("exposureOn"), opt("exposure"))
        Sync(Lighting, "GlobalShadows", on and opt("noShadows"), false)
        Sync(Lighting, "ShadowSoftness", on and opt("shadowSoftOn"), opt("shadowSoft"))

        local fog = on and opt("fogOn")
        Sync(Lighting, "FogStart", fog, math.clamp(opt("fogStart"), 0, 99999))
        Sync(Lighting, "FogEnd", fog, math.max(opt("fogEnd"), opt("fogStart") + 1))
        Sync(Lighting, "FogColor", fog, color("fogColour"))

        -- пост-эффекты самой игры
        local camera = workspace.CurrentCamera
        for _, parent in ipairs({ Lighting, camera }) do
            for _, effect in ipairs(Targets(parent, "PostEffect")) do
                Sync(effect, "Enabled", on and opt("noPost"), false)
            end
        end

        -- атмосфера
        local atmosOn = on and opt("atmosOn") and not opt("noAtmos") and not opt("fogOn")
        local atmospheres = Targets(Lighting, "Atmosphere")
        for _, atmosphere in ipairs(atmospheres) do
            Sync(atmosphere, "Parent", on and (opt("noAtmos") or opt("fogOn")), nil)
        end
        local live = {}
        for _, atmosphere in ipairs(atmospheres) do
            if atmosphere.Parent == Lighting then table.insert(live, atmosphere) end
        end
        if atmosOn and #live == 0 then
            local created = Ensure("Air", "Atmosphere", Lighting)
            if created then table.insert(live, created) end
        else
            Drop("Air")
        end
        for _, atmosphere in ipairs(live) do
            local owned = atmosphere.Name:sub(1, #PREFIX) == PREFIX
            local values = {
                Density = opt("density"), Offset = opt("offset"), Haze = opt("haze"), Glare = opt("glare"),
                Color = color("atmosColour"), Decay = color("decay"),
            }
            for property, value in pairs(values) do
                if owned then
                    pcall(function() atmosphere[property] = value end)
                else
                    Sync(atmosphere, property, atmosOn, value)
                end
            end
        end

        -- облака
        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            local cloudsOn = on and opt("cloudsOn")
            local clouds = Targets(terrain, "Clouds")
            if cloudsOn and #clouds == 0 then
                local created = Ensure("Clouds", "Clouds", terrain)
                if created then table.insert(clouds, created) end
            elseif not cloudsOn then
                Drop("Clouds")
            end
            for _, cloud in ipairs(clouds) do
                local owned = cloud.Name:sub(1, #PREFIX) == PREFIX
                local values = {
                    Cover = opt("cloudCover"), Density = opt("cloudDensity"), Color = color("cloudColour"), Enabled = true,
                }
                for property, value in pairs(values) do
                    if owned then
                        pcall(function() cloud[property] = value end)
                    else
                        Sync(cloud, property, cloudsOn, value)
                    end
                end
            end
        end

        -- свои пост-эффекты
        Configure("Color", "ColorCorrectionEffect", on and opt("gradeOn"), {
            Brightness = opt("gradeBright"), Contrast = opt("contrast"), Saturation = opt("saturation"),
            TintColor = color("tint"),
        })
        Configure("Bloom", "BloomEffect", on and opt("bloomOn"), {
            Intensity = opt("bloomIntensity"), Size = opt("bloomSize"), Threshold = opt("bloomThreshold"),
        })
        Configure("Rays", "SunRaysEffect", on and opt("raysOn"), {
            Intensity = opt("raysIntensity"), Spread = opt("raysSpread"),
        })
        Configure("DoF", "DepthOfFieldEffect", on and opt("dofOn"), {
            FarIntensity = opt("dofFar"), FocusDistance = opt("dofFocus"), InFocusRadius = opt("dofRadius"), NearIntensity = 0,
        })
        Vignette(on and opt("vignetteOn"), opt("vignette"))
    end

    -- ---------- Материалы ----------
    local appliedMaterials = "Game"
    local MaterialVariants, MaterialPrevious = {}, {}

    local function MaterialsApply(force)
        local name = VisOpt("materials")
        if name == appliedMaterials and not force then return end
        for material, previous in pairs(MaterialPrevious) do
            pcall(function() MaterialService:SetBaseMaterialOverride(Enum.Material[material], previous) end)
        end
        for _, variant in ipairs(MaterialVariants) do pcall(function() variant:Destroy() end) end
        MaterialPrevious, MaterialVariants = {}, {}
        local pack = MATERIAL_PACKS[name]
        if pack then
            for material, maps in pairs(pack) do
                pcall(function()
                    local variant = Instance.new("MaterialVariant")
                    variant.Name = PREFIX .. material
                    variant.BaseMaterial = Enum.Material[material]
                    for index, property in ipairs({ "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" }) do
                        if maps[index] ~= "" then variant[property] = "rbxassetid://" .. maps[index] end
                    end
                    variant.StudsPerTile = maps[5]
                    variant.Parent = MaterialService
                    table.insert(MaterialVariants, variant)
                    MaterialPrevious[material] = MaterialService:GetBaseMaterialOverride(Enum.Material[material])
                    MaterialService:SetBaseMaterialOverride(Enum.Material[material], variant.Name)
                end)
            end
        end
        appliedMaterials = pack and name or "Game"
    end

    -- ---------- Небо ----------
    local SkyByName = {}
    for _, sky in ipairs(SKIES) do SkyByName[sky.name] = sky end

    local HiddenSkies = {}
    local appliedSky, skyInstance, skyDetailsApplied = nil, nil, false
    local FACE_PROPERTIES = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }

    local function RestoreSkies()
        for sky in pairs(HiddenSkies) do
            pcall(function() sky.Parent = Lighting end)
            HiddenSkies[sky] = nil
        end
    end

    local function SkyApply()
        local name = VisOpt("sky")
        local spec = name ~= "Game" and SkyByName[name] or nil
        local detailsOn = VisOpt("skyDetailsOn")

        if spec then
            for _, sky in ipairs(Lighting:GetChildren()) do
                if sky:IsA("Sky") and sky.Name:sub(1, #PREFIX) ~= PREFIX then
                    HiddenSkies[sky] = true
                    pcall(function() sky.Parent = nil end)
                end
            end
            local sky = Ensure("Sky", "Sky", Lighting)
            if sky and (sky ~= skyInstance or appliedSky ~= name) then
                for index, property in ipairs(FACE_PROPERTIES) do
                    pcall(function() sky[property] = "rbxassetid://" .. spec.faces[index] end)
                end
                pcall(function()
                    sky.CelestialBodiesShown = spec.celestial == true
                    sky.StarCount = spec.stars or 0
                    if spec.sun then sky.SunAngularSize = spec.sun end
                    if spec.moon then sky.MoonAngularSize = spec.moon end
                    if spec.sunTex then sky.SunTextureId = spec.sunTex end
                    if spec.moonTex then sky.MoonTextureId = spec.moonTex end
                end)
                skyInstance, appliedSky = sky, name
            end
            if sky and detailsOn then
                pcall(function()
                    sky.StarCount = VisOpt("stars")
                    sky.SunAngularSize = VisOpt("sunSize")
                    sky.MoonAngularSize = VisOpt("moonSize")
                    sky.CelestialBodiesShown = VisOpt("celestial")
                end)
            end
            if not detailsOn and skyDetailsApplied then
                appliedSky = nil -- вернуть значения неба из выбранного неба при следующем применении
            end
            skyDetailsApplied = detailsOn
        else
            Drop("Sky")
            skyInstance, appliedSky = nil, nil
            RestoreSkies()
            for _, sky in ipairs(Targets(Lighting, "Sky")) do
                Sync(sky, "StarCount", detailsOn, VisOpt("stars"))
                Sync(sky, "SunAngularSize", detailsOn, VisOpt("sunSize"))
                Sync(sky, "MoonAngularSize", detailsOn, VisOpt("moonSize"))
                Sync(sky, "CelestialBodiesShown", detailsOn, VisOpt("celestial"))
            end
        end
    end

    -- ---------- Погода ----------
    local WEATHER_COLORS = {
        snowColour = Color3.fromRGB(255, 255, 255), petalColour = Color3.fromRGB(255, 182, 208),
        leafColour = Color3.fromRGB(230, 140, 60), fireflyColour = Color3.fromRGB(190, 255, 110),
        mistColour = Color3.fromRGB(215, 225, 235), emberColour = Color3.fromRGB(255, 120, 40),
        ashColour = Color3.fromRGB(150, 150, 155), pollenColour = Color3.fromRGB(255, 230, 120),
    }

    local Weather = {
        folder = nil, nodes = {}, voices = {}, kind = nil, builtSound = nil, phase = 0, elapsed = 0,
        visibility = 0, covered = false, probeAt = 0, groundAt = 0, groundY = nil, position = nil,
        envAt = 0, dark = 0, configDirty = true, signature = "", params = nil,
    }

    local function Sequence(points)
        local keys = {}
        for _, point in ipairs(points) do
            table.insert(keys, NumberSequenceKeypoint.new(table.unpack(point)))
        end
        return NumberSequence.new(keys)
    end

    local function WeatherStop()
        if Weather.folder then pcall(function() Weather.folder:Destroy() end) end
        Weather.folder, Weather.nodes, Weather.voices, Weather.kind = nil, {}, {}, nil
        Weather.params = nil
        Weather.visibility = 0
    end

    local function WeatherBuild(camera, kind)
        WeatherStop()
        local recipe = recipes[kind]
        if not recipe then return end
        Weather.kind, Weather.builtSound = kind, VisOpt("weatherSound")
        local folder = Instance.new("Folder")
        folder.Name = PREFIX .. "Weather"
        folder.Parent = camera
        Weather.folder = folder
        for index, layer in ipairs(recipe.layers) do
            local part = Instance.new("Part")
            part.Name = "Volume" .. index
            part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
            part.CastShadow, part.Transparency, part.Massless = false, 1, true
            part.Size = Vector3.new(10, 10, 10)
            part.Parent = folder
            local emitter = Instance.new("ParticleEmitter")
            emitter.Name = "Particles"
            emitter.Enabled, emitter.Rate, emitter.LockedToPart = false, 0, false
            emitter.VelocityInheritance = 0
            emitter.EmissionDirection = layer.lift and Enum.NormalId.Top or Enum.NormalId.Bottom
            pcall(function()
                emitter.Shape = Enum.ParticleEmitterShape.Box
                emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
                emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
            end)
            emitter.Parent = part
            table.insert(Weather.nodes, {
                part = part, emitter = emitter, layer = layer, seed = math.random() * 6.2832, rate = 0,
            })
        end
        if VisOpt("weatherSound") then
            for _, spec in ipairs(recipe.voices or {}) do
                local sound = Instance.new("Sound")
                sound.Name, sound.SoundId, sound.Looped, sound.Volume = "Voice", spec.id, true, 0
                sound.Parent = folder
                pcall(function() sound:Play() end)
                table.insert(Weather.voices, { sound = sound, spec = spec, level = 0 })
            end
        end
        Weather.configDirty = true
    end

    local function WeatherConfigure()
        local recipe = recipes[Weather.kind]
        if not recipe then return end
        local amount = VisOpt("weatherAmount") / 100
        local opacity = VisOpt("weatherOpacity") / 100
        local speed = math.max(VisOpt("weatherSpeed") / 100, 0.1)
        local radius = VisOpt("weatherRadius")
        local scale = VisOpt("weatherScale")
        local color = VisOpt("weatherColourOn") and VisColor("weatherColour") or WEATHER_COLORS[recipe.colour] or Color3.new(1, 1, 1)
        local dark = Weather.dark

        for _, node in ipairs(Weather.nodes) do
            local layer, emitter = node.layer, node.emitter
            node.tile = radius * 2 * layer.reach
            node.part.Size = Vector3.new(node.tile, layer.h, node.tile)
            local rate = (layer.from and amount < layer.from) and 0 or layer.rate[1] + (layer.rate[2] - layer.rate[1]) * amount
            node.rate = rate * 0.8 * (radius / 30) ^ 2
            emitter.Texture = textures[layer.tex]
            local base, tint = layer.col or color, layer.tint or 0.2
            local fire = layer.col2 and WEATHER_COLORS[layer.col2] or color
            if layer.fire then
                emitter.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, fire:Lerp(Color3.fromRGB(255, 246, 210), 0.65)),
                    ColorSequenceKeypoint.new(0.35, fire),
                    ColorSequenceKeypoint.new(1, fire:Lerp(Color3.fromRGB(140, 20, 6), 0.65)),
                })
            else
                emitter.Color = ColorSequence.new(base:Lerp(Color3.new(1, 1, 1), layer.pulse and 0.35 or tint), base)
            end
            emitter.LightInfluence = layer.light or 0.3
            emitter.LightEmission = math.clamp((layer.glow or 0) * (0.4 + 0.6 * dark), 0, 1)
            emitter.Lifetime = NumberRange.new(layer.life[1] / speed, layer.life[2] / speed)
            emitter.Speed = NumberRange.new(layer.speed[1] * speed, layer.speed[2] * speed)
            local low, high = layer.size[1] * scale, layer.size[2] * scale
            local midpoint, spread = (low + high) * 0.5, (high - low) * 0.5
            local sizes = { { 0, midpoint * 0.9, spread }, { 0.2, midpoint, spread }, { 1, midpoint * 0.92, spread } }
            if layer.pulse then
                sizes = { { 0, 0 }, { 0.12, midpoint }, { 0.3, high * 0.45 }, { 0.5, high }, { 0.72, low * 0.5 }, { 0.88, midpoint * 0.8 }, { 1, 0 } }
            end
            if layer.fire then
                sizes = { { 0, midpoint, spread }, { 0.7, midpoint * 0.75, spread * 0.7 }, { 1, midpoint * 0.2, 0 } }
            end
            emitter.Size = Sequence(sizes)
            local alpha = math.clamp(opacity * (layer.alpha or 1) * (0.9 + 0.2 * dark), 0, 1)
            local fade = { { 0, 1 }, { 0.1, 1 - alpha }, { 0.78, 1 - alpha }, { 1, 1 } }
            if layer.pulse or layer.flicker then
                fade = { { 0, 1 }, { 0.1, 1 - alpha }, { 0.3, 1 - alpha * 0.15 }, { 0.5, 1 - alpha * 0.1 },
                    { 0.68, 1 - alpha }, { 0.85, 1 - alpha * 0.25 }, { 1, 1 } }
            end
            emitter.Transparency = Sequence(fade)
            emitter.SpreadAngle = Vector2.new(layer.spread or 5, layer.spread or 5)
            emitter.Drag = layer.drag or 0
            emitter.Rotation = layer.rot and NumberRange.new(0, 360) or NumberRange.new(0)
            emitter.RotSpeed = layer.rot and NumberRange.new(-layer.rot, layer.rot) or NumberRange.new(0)
            emitter.Orientation = Enum.ParticleOrientation.FacingCamera
            emitter.Enabled = true
            pcall(function() emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.None end)
        end
        Weather.configDirty = false
    end

    local function WeatherGust()
        local phase = Weather.phase
        return 0.8 + math.sin(phase * 0.7) * 0.2 + math.sin(phase * 1.9) * 0.08 + math.sin(phase * 0.23 + 1.3) * 0.1
    end

    local function WeatherStep(delta)
        local kind = VisOpt("weather")
        local character = LocalPlayer.Character
        local camera = workspace.CurrentCamera
        local alive = character and character:FindFirstChildOfClass("Humanoid") and character:FindFirstChildOfClass("Humanoid").Health > 0
        if kind == "Off" or not recipes[kind] or not camera then
            if Weather.folder then WeatherStop() end
            return
        end

        Weather.elapsed += math.clamp(delta, 0, 0.1)
        if Weather.elapsed < 1 / 30 then return end
        delta, Weather.elapsed = Weather.elapsed, 0
        Weather.phase += delta

        -- время суток для яркости частиц
        if os.clock() - Weather.envAt > 1 then
            Weather.envAt = os.clock()
            local time, ambient = Lighting.ClockTime, Lighting.OutdoorAmbient
            local day = math.clamp((time - 5.5) / 1.5, 0, 1) * math.clamp((19.5 - time) / 1.5, 0, 1)
            local dark = math.clamp(1 - (ambient.R + ambient.G + ambient.B) / 3 / 0.55, 0, 1)
            local nextDark = math.max(1 - day, dark * 0.8)
            if math.abs(Weather.dark - nextDark) > 0.08 then Weather.configDirty = true end
            Weather.dark = nextDark
        end

        local signature = kind .. "|" .. tostring(VisOpt("weatherSound"))
        if not Weather.folder or Weather.folder.Parent ~= camera or Weather.signature ~= signature then
            Weather.signature = signature
            WeatherBuild(camera, kind)
        end
        if Weather.configDirty then WeatherConfigure() end

        local frame = camera.CFrame
        local focus = frame.Position
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root and (root.Position - focus).Magnitude < 70 then focus = root.Position end
        local look = Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z)
        if look.Magnitude > 0.05 then focus += look.Unit * 4 end
        if Weather.position and (focus - Weather.position).Magnitude > 48 then
            for _, node in ipairs(Weather.nodes) do pcall(function() node.emitter:Clear() end) end
        end
        Weather.position = focus

        -- земля под игроком и навес над ним (params переиспользуем)
        local params = Weather.params
        if not params then
            params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            Weather.params = params
        end
        params.FilterDescendantsInstances = { character, camera }
        local now = os.clock()
        if not Weather.groundY or now - Weather.groundAt > 0.5 then
            local hit = workspace:Raycast(focus + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), params)
            Weather.groundAt, Weather.groundY = now, hit and hit.Position.Y or focus.Y - 3
        end
        if now - Weather.probeAt > 0.25 then
            Weather.probeAt = now
            local covered = false
            if VisOpt("weatherShelter") then
                covered = workspace:Raycast(focus + Vector3.new(0, 0.4, 0), Vector3.new(0, 40, 0), params) ~= nil
            end
            if covered and not Weather.covered then
                for _, node in ipairs(Weather.nodes) do
                    if not node.layer.noShelter then pcall(function() node.emitter:Clear() end) end
                end
            end
            Weather.covered = covered
        end

        for _, node in ipairs(Weather.nodes) do
            local height = node.layer.base == "ground" and Weather.groundY + node.layer.y or focus.Y + node.layer.y
            node.part.CFrame = CFrame.new(focus.X, height, focus.Z)
        end

        local target = VisOpt("weatherAmount") == 0 and 0 or 1
        Weather.visibility += (target - Weather.visibility) * (1 - math.exp(-delta * 5))

        local angle = math.rad(VisOpt("weatherWindAngle"))
        local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
        local sideways = Vector3.new(-direction.Z, 0, direction.X)
        local speed = math.max(VisOpt("weatherSpeed") / 100, 0.1)
        local wind = VisOpt("weatherWind") * 0.3 * WeatherGust() * speed ^ 2
        for _, node in ipairs(Weather.nodes) do
            local layer = node.layer
            local sway = math.sin(Weather.phase * 0.9 + node.seed) * 0.6 + math.sin(Weather.phase * 2.3 + node.seed * 1.7 + 1.7) * 0.4
            local along = math.cos(Weather.phase * 1.3 + node.seed * 0.7) * 0.5
            local force = layer.noWind and Vector3.zero or direction * wind * (layer.windK or 1)
            if layer.still then
                force = direction * (layer.drift or 0.3) * VisOpt("weatherWind") * 0.1
            else
                force += sideways * (layer.sway or 0) * sway + direction * (layer.sway or 0) * along * 0.5
                    + Vector3.new(0, (layer.lift or 0) - (layer.fall or 0), 0)
            end
            node.emitter.Acceleration = force
            local blocked = Weather.covered and not layer.noShelter
            node.emitter.Rate = (blocked or not alive) and 0 or node.rate * Weather.visibility
        end

        -- звук
        local amount = VisOpt("weatherAmount") / 100
        for _, voice in ipairs(Weather.voices) do
            local spec = voice.spec
            local low, high = spec.lo or 0, spec.hi or 1
            local level = low + (high - low) * amount
            if spec.from then level *= math.clamp((amount - spec.from) / 0.2, 0, 1) end
            level *= spec.base or 0.4
            if spec.wind then level *= 0.35 + 0.65 * math.clamp(VisOpt("weatherWind") / 10, 0, 1.4) * WeatherGust() end
            local shelter = Weather.covered and (spec.roof and 1 or 0.45) or (spec.roof and 0 or 1)
            if spec.steady then shelter = 1 end
            level *= VisOpt("weatherVolume") / 100 * shelter
            voice.level += (level - voice.level) * (1 - math.exp(-delta * 3.5))
            voice.sound.Volume = voice.level
        end
    end

    -- ---------- Экран: FOV, растяжение, FPS, 3D ----------
    local fovOriginal, lastFrame, baseFrame, screenCamera = nil, nil, nil, nil
    local fpsApplied, renderApplied = false, false
    local fpsOriginal = nil
    if type(getfpscap) == "function" then
        local ok, value = pcall(getfpscap)
        if ok and type(value) == "number" then fpsOriginal = value end
    end

    local function ScreenStep()
        local camera = workspace.CurrentCamera
        if not camera then return end

        -- камера сменилась: FOV старой возвращаем, оригинал пересчитываем
        if screenCamera ~= camera then
            if screenCamera and fovOriginal then
                pcall(function() screenCamera.FieldOfView = fovOriginal end)
            end
            fovOriginal, lastFrame, baseFrame = nil, nil, nil
            screenCamera = camera
        end

        if VisOpt("fovOn") then
            if not fovOriginal then fovOriginal = camera.FieldOfView end
            camera.FieldOfView = VisOpt("fov")
        elseif fovOriginal then
            camera.FieldOfView = fovOriginal
            fovOriginal = nil
        end

        local stretch = VisOpt("stretch")
        if stretch > 0 then
            local scale = 1 - stretch / 100 * 0.6
            local current = camera.CFrame
            -- если игра не обновила камеру в этом кадре, не накапливаем растяжение
            local base = (lastFrame and current == lastFrame and baseFrame) or current
            camera.CFrame = base * CFrame.new(0, 0, 0, 1, 0, 0, 0, scale, 0, 0, 0, 1)
            lastFrame, baseFrame = camera.CFrame, base
        else
            lastFrame, baseFrame = nil, nil
        end
    end

    local function ScreenApply()
        if setfpscap then
            if VisOpt("fpsOn") then
                pcall(setfpscap, VisOpt("fpsCap"))
                fpsApplied = true
            elseif fpsApplied then
                pcall(setfpscap, fpsOriginal or 60)
                fpsApplied = false
            end
        end
        local noRender = VisOpt("noRender")
        if noRender ~= renderApplied then
            pcall(function() RunService:Set3dRenderingEnabled(not noRender) end)
            renderApplied = noRender
        end
    end

    -- ---------- Ауры вокруг персонажа ----------
    local AURAS = {
        Sparkles = { tex = "rbxasset://textures/particles/sparkles_main.dds", rate = 22, life = { 0.8, 1.6 }, speed = { 0.5, 2 },
            size = { 0.3, 0.6 }, accel = Vector3.new(0, 1.2, 0), glow = 1, rot = 180 },
        Petals = { tex = textures.petal, rate = 12, life = { 2, 3.4 }, speed = { 1, 2.2 },
            size = { 0.4, 0.7 }, accel = Vector3.new(0, -1.6, 0), glow = 0.3, rot = 120 },
        Fire = { tex = "rbxasset://textures/particles/fire_main.dds", rate = 30, life = { 0.6, 1.1 }, speed = { 0.5, 1.5 },
            size = { 0.8, 1.6 }, accel = Vector3.new(0, 3.5, 0), glow = 1, rot = 40 },
        Smoke = { tex = "rbxasset://textures/particles/smoke_main.dds", rate = 14, life = { 1.4, 2.4 }, speed = { 0.3, 1.2 },
            size = { 1.2, 2.4 }, accel = Vector3.new(0, 1.8, 0), glow = 0, rot = 40 },
        Stars = { tex = textures.glow, rate = 16, life = { 1, 2 }, speed = { 0.6, 2.4 },
            size = { 0.35, 0.7 }, accel = Vector3.new(0, 0.6, 0), glow = 1, rot = 0 },
    }

    local Aura = { objects = {}, signature = "", root = nil, hueAt = 0 }

    local function AuraClear()
        for _, object in ipairs(Aura.objects) do pcall(function() object:Destroy() end) end
        Aura.objects, Aura.signature, Aura.root = {}, "", nil
    end

    local function AuraColor()
        local mode = VisOpt("auraColMode")
        if mode == "Rainbow" then return Color3.fromHSV((os.clock() * 0.25) % 1, 0.8, 1) end
        if mode == "Custom" then return VisColor("auraColour") end
        local ok, color = pcall(Color3.fromHex, tostring(Settings.UI and Settings.UI.accent or "ff80ab"))
        return ok and color or Color3.fromRGB(255, 128, 171)
    end

    local function AuraApply()
        local kind, character = VisOpt("aura"), LocalPlayer.Character
        local root = character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso"))
        local wantsAura = kind ~= "Off" and AURAS[kind] ~= nil
        local wantsOutline, wantsTrail, wantsLight = VisOpt("auraOutline"), VisOpt("auraTrail"), VisOpt("auraGlow")
        if not root or not (wantsAura or wantsOutline or wantsTrail or wantsLight) then
            if #Aura.objects > 0 then AuraClear() end
            return
        end

        local signature = table.concat({ kind, tostring(VisOpt("auraSize")), tostring(VisOpt("auraRate")),
            tostring(wantsOutline), tostring(wantsTrail), tostring(wantsLight) }, "|")
        if Aura.root ~= root or Aura.signature ~= signature then
            AuraClear()
            Aura.root, Aura.signature = root, signature
            local size, rate = VisOpt("auraSize"), VisOpt("auraRate")
            if wantsAura then
                local spec = AURAS[kind]
                local emitter = Instance.new("ParticleEmitter")
                emitter.Name = PREFIX .. "Aura"
                emitter.Texture = spec.tex
                emitter.Rate = spec.rate * rate
                emitter.Lifetime = NumberRange.new(spec.life[1], spec.life[2])
                emitter.Speed = NumberRange.new(spec.speed[1], spec.speed[2])
                emitter.Size = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, spec.size[1] * size), NumberSequenceKeypoint.new(0.5, spec.size[2] * size),
                    NumberSequenceKeypoint.new(1, 0),
                })
                emitter.Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.2),
                    NumberSequenceKeypoint.new(0.8, 0.4), NumberSequenceKeypoint.new(1, 1),
                })
                emitter.LightEmission = spec.glow
                emitter.Acceleration = spec.accel
                emitter.SpreadAngle = Vector2.new(180, 180)
                emitter.Rotation = NumberRange.new(0, 360)
                emitter.RotSpeed = NumberRange.new(-spec.rot, spec.rot)
                emitter.LockedToPart = false
                emitter.Shape = Enum.ParticleEmitterShape.Cylinder
                emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
                pcall(function() emitter.ShapePartial = 1 end)
                emitter.Parent = root
                table.insert(Aura.objects, emitter)
            end
            if wantsLight then
                local light = Instance.new("PointLight")
                light.Name = PREFIX .. "AuraLight"
                light.Range, light.Brightness = 10 * size, 2
                light.Parent = root
                table.insert(Aura.objects, light)
            end
            if wantsOutline then
                local highlight = Instance.new("Highlight")
                highlight.Name = PREFIX .. "AuraOutline"
                highlight.FillTransparency, highlight.OutlineTransparency = 1, 0
                highlight.DepthMode = Enum.HighlightDepthMode.Occluded
                highlight.Adornee = character
                highlight.Parent = character
                table.insert(Aura.objects, highlight)
            end
            if wantsTrail then
                local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
                top.Name, bottom.Name = PREFIX .. "TrailTop", PREFIX .. "TrailBottom"
                top.Position, bottom.Position = Vector3.new(0, 1.2, 0), Vector3.new(0, -1.6, 0)
                top.Parent, bottom.Parent = root, root
                local trail = Instance.new("Trail")
                trail.Name = PREFIX .. "Trail"
                trail.Attachment0, trail.Attachment1 = top, bottom
                trail.Lifetime = 0.7 * size
                trail.LightEmission = 0.6
                trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
                trail.Parent = root
                table.insert(Aura.objects, top)
                table.insert(Aura.objects, bottom)
                table.insert(Aura.objects, trail)
            end
        end

        -- цвет обновляем постоянно (радужный меняется со временем)
        if os.clock() - Aura.hueAt > 0.1 then
            Aura.hueAt = os.clock()
            local color = AuraColor()
            for _, object in ipairs(Aura.objects) do
                if object:IsA("ParticleEmitter") then
                    object.Color = ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.35))
                elseif object:IsA("PointLight") then
                    object.Color = color
                elseif object:IsA("Highlight") then
                    object.OutlineColor = color
                elseif object:IsA("Trail") then
                    object.Color = ColorSequence.new(color, color:Lerp(Color3.new(0, 0, 0), 0.4))
                end
            end
        end
    end

    -- ---------- Пресеты и сцены ----------
    local function ApplyPreset(name)
        for _, key in ipairs(WORLD_KEYS) do Settings.VisOpt[key] = nil end
        if name == "Original" then
            Settings.VisOpt.worldOn = false
            Settings.VisOpt.preset = "Original"
        else
            local selected = PRESETS[name]
            if not selected then return end
            for key, value in pairs(selected) do Settings.VisOpt[key] = value end
            Settings.VisOpt.worldOn = true
            Settings.VisOpt.preset = name
        end
        dirty = true
        Save()
        Visual.refreshUI()
    end

    local function ApplyScene(name)
        for _, scene in ipairs(SCENES) do
            if scene.name == name then
                ApplyPreset(scene.look)
                Settings.VisOpt.sky = scene.sky
                Settings.VisOpt.weather = scene.weather.kind
                Settings.VisOpt.weatherAmount = scene.weather.amount or 60
                Settings.VisOpt.weatherWind = scene.weather.wind or 6
                Settings.VisOpt.weatherSpeed = scene.weather.speed or 100
                Settings.VisOpt.scene = name
                Weather.configDirty = true
                dirty = true
                Save()
                Visual.refreshUI()
                return
            end
        end
    end

    Visual.applyPreset = ApplyPreset
    Visual.applyScene = ApplyScene
    Visual.changed = function(key)
        dirty = true
        if type(key) == "string" and key:sub(1, 7) == "weather" then Weather.configDirty = true end
    end

    -- ---------- Главный цикл ----------
    local lastApply, lastError = 0, nil
    local function ApplyAll()
        WorldApply()
        SkyApply()
        MaterialsApply()
        ScreenApply()
        AuraApply()
    end

    Track(RunService.Heartbeat:Connect(function(delta)
        if not Alive() then return end
        local now = os.clock()
        if dirty or now - lastApply > 0.3 then
            dirty, lastApply = false, now
            local ok, err = pcall(ApplyAll)
            if not ok and tostring(err) ~= lastError then
                lastError = tostring(err)
                warn("[Yozora Hub] visual error: " .. lastError)
            end
        end
        local ok, err = pcall(WeatherStep, delta)
        if not ok and tostring(err) ~= lastError then
            lastError = tostring(err)
            warn("[Yozora Hub] weather error: " .. lastError)
        end
    end))
    Track(RunService.RenderStepped:Connect(function()
        pcall(ScreenStep)
    end))

    -- ---------- Возврат всего при выгрузке ----------
    _G.YozoraHub_VisualStop = function()
        ReleaseAll()
        for name in pairs(Owned) do Drop(name) end
        Vignette(false, 0)
        RestoreSkies()
        WeatherStop()
        AuraClear()
        for material, previous in pairs(MaterialPrevious) do
            pcall(function() MaterialService:SetBaseMaterialOverride(Enum.Material[material], previous) end)
        end
        for _, variant in ipairs(MaterialVariants) do pcall(function() variant:Destroy() end) end
        local camera = workspace.CurrentCamera
        if camera and fovOriginal then camera.FieldOfView = fovOriginal end
        if renderApplied then pcall(function() RunService:Set3dRenderingEnabled(true) end) end
        if fpsApplied and setfpscap then
            pcall(setfpscap, fpsOriginal or 60)
            fpsApplied = false
        end
    end

    Visual.refreshUI()
end

-- ==========================================
-- 10. Auto Farm (методы: Classic и Under Map)
-- ==========================================
-- Движок построен по образцу присланного кода: BodyVelocity-мувер, выбор
-- монеты по оценке, штраф рядом с убийцей, подтверждение подбора и пропуск
-- монет, которые не засчитались.
local function Weak()
    return {} -- таблицы сбрасываются при смене раунда (ResetMotionHook), слабые ключи тут не нужны
end

local Motion = {
    phase = "idle", gapT = 4.5, tries = 0, got = 0, fails = 0, learn = {},
    info = Weak(), skip = Weak(), pending = Weak(), att = Weak(),
    blocked = false,
}
local Runtime = { roundAt = 0, gunAt = 0, lastRespawn = 0, respawnPending = false }

local function UnderMapSpeed() return math.clamp(tonumber(Settings.SpeedUnderMap) or 21, 8, 22) end
local function ClassicSpeed() return math.clamp(tonumber(Settings.SpeedClassic) or 24, 8, 24) end

local function ValidCoin(coin)
    if not coin or not coin.Parent or not coin:IsA("BasePart") then return false end
    if not coin:FindFirstChild("TouchInterest") or coin:GetAttribute("Collected") then return false end
    if (RoundState.skipped[coin] or 0) > os.clock() then return false end
    -- монеты типа, чей мешок уже полон (например, конфеты), не берём
    local id = coin:GetAttribute("CoinID")
    if id ~= nil and RoundState.full[id] then return false end
    return true
end

local function SkipCoin(coin)
    RoundState.skipped[coin] = os.clock() + 30
end

-- Касание через firetouchinterest всеми частями персонажа
local function TouchParts(character)
    local parts = {}
    local head = character:FindFirstChild("Head")
    if head then table.insert(parts, head) end
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Accessory") then
            local handle = child:FindFirstChild("Handle")
            if handle then table.insert(parts, handle) end
        end
    end
    for _, name in ipairs({ "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso" }) do
        local part = character:FindFirstChild(name)
        if part then table.insert(parts, part) end
    end
    return parts
end

local function TouchCoin(character, coin)
    if not firetouchinterest or not character or not coin or not coin.Parent then return end
    for _, part in ipairs(TouchParts(character)) do
        pcall(function()
            firetouchinterest(part, coin, 0)
            firetouchinterest(part, coin, 1)
        end)
    end
end

-- ---------- Лучи вниз: где пол и где прятаться ----------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
pcall(function() rayParams.RespectCanCollide = true end)
local rayFilterAt = 0

local function GetRayParams(now)
    if now - rayFilterAt > 1 then
        rayFilterAt = now
        local ignored = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character then table.insert(ignored, player.Character) end
        end
        for _, container in ipairs(GetContainers()) do
            table.insert(ignored, container)
        end
        rayParams.FilterDescendantsInstances = ignored
    end
    return rayParams
end

local function FloorY(position, offset, depth, now)
    local hit = workspace:Raycast(
        position + Vector3.new(0, offset or 0.5, 0),
        Vector3.new(0, -(depth or 50), 0),
        GetRayParams(now)
    )
    return hit and hit.Position.Y or nil
end

-- hide: точка под полом прямо под монетой (пол минус 3.8 студа)
local function CoinInfo(coin, now)
    local cached = Motion.info[coin]
    if cached then return cached end
    local position = coin.Position
    local surface = FloorY(position, 0.5, 40, now) or position.Y - 3
    local hide = Vector3.new(position.X, surface - 3.8, position.Z)
    local info = { surf = surface, hide = hide, exposed = FloorY(hide, 0, 7, now) ~= nil }
    Motion.info[coin] = info
    return info
end

local function HideAt(root, now)
    local floor = FloorY(root.Position, 9, 30, now)
    if not floor then return root.Position end
    local position = root.Position
    return Vector3.new(position.X, math.min(position.Y, floor - 3.8), position.Z)
end

-- ---------- Избегание убийцы (логика из присланного кода) ----------
-- Ближе 24 студов монета почти запрещена (при включённом избегании), до 48 растёт штраф.
local function MurderPenalty(position, murdererPos)
    if not murdererPos then return 0 end
    local distance = (position - murdererPos).Magnitude
    if distance < 24 then return Settings.AvoidMurderer and 1000000 or 300 end
    if distance < 48 then return (48 - distance) * 2 end
    return 0
end

-- Выбор монеты для метода Under Map (учитывает глубину и открытость точки под полом)
local function ChooseCoin(position, murdererPos, now)
    local chosen, lowest
    for _, container in ipairs(GetContainers()) do
        if container.Parent then
            for _, coin in ipairs(container:GetChildren()) do
                if ValidCoin(coin) and (Motion.skip[coin] or 0) < now and not Motion.pending[coin] then
                    local info = CoinInfo(coin, now)
                    local score = (info.hide - position).Magnitude + math.max(0, coin.Position.Y - info.hide.Y) * 1.2
                    if info.exposed then score += 25 end
                    score += MurderPenalty(coin.Position, murdererPos)
                    if not lowest or score < lowest then
                        chosen, lowest = coin, score
                    end
                end
            end
        end
    end
    if chosen and Settings.AvoidMurderer and lowest >= 1000000 then
        return nil, lowest, true -- все монеты слишком близко к убийце
    end
    return chosen, lowest, false
end

-- ---------- Движение ----------
local function Jump(root, destination, forced, now)
    if not forced and (destination - root.Position).Magnitude <= 1000 then return false end
    root.CFrame = CFrame.new(destination)
    root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
    Motion.goT = now
    return true
end

local FarmMovers = setmetatable({}, { __mode = "k" })        -- [root] = { bv, bg } — только СВОИ объекты
local FarmPlatformOriginal = setmetatable({}, { __mode = "k" }) -- [humanoid] = исходный PlatformStand

local function EnsureMover(root, humanoid)
    local entry = FarmMovers[root]
    if not entry then
        entry = {}
        FarmMovers[root] = entry
    end

    local velocity = entry.bv
    if not (velocity and velocity.Parent == root) then
        velocity = Instance.new("BodyVelocity")
        velocity.Name = "YozoraFarmBV"
        velocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        velocity.P = 30000
        velocity.Velocity = Vector3.zero
        velocity.Parent = root
        entry.bv = velocity
    end

    local gyro = entry.bg
    if not (gyro and gyro.Parent == root) then
        gyro = Instance.new("BodyGyro")
        gyro.Name = "YozoraFarmBG"
        gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        gyro.P = 30000
        gyro.CFrame = CFrame.lookAt(
            root.Position,
            root.Position + Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z + 1e-4)
        )
        gyro.Parent = root
        entry.bg = gyro
    end

    -- сохраняем исходный PlatformStand один раз, чтобы вернуть именно его
    if humanoid and not humanoid.PlatformStand and FarmPlatformOriginal[humanoid] == nil then
        FarmPlatformOriginal[humanoid] = false
        pcall(function() humanoid.PlatformStand = true end)
    end
    return velocity, gyro
end

local function Move(root, velocity, gyro, destination, delta, speed)
    local direction = destination - root.Position
    local distance = direction.Magnitude
    velocity.Velocity = distance < 0.05 and Vector3.zero
        or direction.Unit * math.min(speed, distance / math.max(delta, 1 / 60))
    local horizontal = Vector3.new(direction.X, 0, direction.Z)
    if gyro and horizontal.Magnitude > 0.4 then
        gyro.CFrame = CFrame.lookAt(root.Position, root.Position + horizontal.Unit)
    end
    return distance
end

local RestoreFarmCollision = function() end

local function FarmReset(character)
    pcall(RestoreFarmCollision)
    pcall(function()
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        -- уничтожаем только СВОИ объекты (по сохранённым ссылкам), не по имени
        local entry = root and FarmMovers[root]
        if entry then
            if entry.bv then pcall(function() entry.bv:Destroy() end) end
            if entry.bg then pcall(function() entry.bg:Destroy() end) end
            FarmMovers[root] = nil
        end
        if humanoid then
            -- возвращаем PlatformStand только если меняли его сами
            if FarmPlatformOriginal[humanoid] == false and humanoid.PlatformStand then
                humanoid.PlatformStand = false
                if humanoid.Health > 0 then
                    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end
            FarmPlatformOriginal[humanoid] = nil
        end
    end)
    Motion.phase, Motion.coin, Motion.hold = "idle", nil, nil
end

-- Подтверждение подбора: монета "ожидает", пока не исчезнет или не истечёт время
local function UpdatePending(now)
    for coin, entry in pairs(Motion.pending) do
        if type(entry) == "table" then
            if ValidCoin(coin) then
                if now > entry.t then
                    Motion.pending[coin] = nil
                    Motion.gapT, Motion.miss = math.max(1, Motion.gapT - 0.25), (Motion.miss or 0) + 1
                end
            else
                Motion.pending[coin] = nil
                Motion.gapT, Motion.ok = math.min(6, Motion.gapT + 0.08), (Motion.ok or 0) + 1
                -- запасной подсчёт, если события игры недоступны
                if not RoundState.eventsReady and coin:GetAttribute("Collected") then
                    Stats.Session += 1
                    Settings.TotalCoins += 1
                    RoundState.dirty = true
                end
            end
        end
    end
end

-- ---------- Метод 2: Under Map (под картой) ----------
local function FarmUnderMap(o)
    local now, root, velocity, gyro, character = o.time, o.root, o.velocity, o.gyro, o.character
    local murderer, gun = o.murderer, o.gun
    local speed = UnderMapSpeed()
    local coin = Motion.coin
    if gun then coin = gun end

    if not gun then
        if coin and not ValidCoin(coin) then
            if Motion.phase == "rise" and Motion.riseFrom then
                table.insert(Motion.learn, coin.Position.Y - root.Position.Y)
                if #Motion.learn > 60 then table.remove(Motion.learn, 1) end
            end
            Motion.got, Motion.coin, Motion.phase, coin = Motion.got + 1, nil, "go", nil
        end

        if not coin or (Motion.phase == "go" and now - (Motion.pickT or 0) > 0.3) then
            Motion.pickT = now
            local candidate, score, blocked = ChooseCoin(root.Position, murderer, now)
            Motion.blocked = blocked
            if candidate and candidate ~= coin then
                local current
                if coin and ValidCoin(coin) then
                    local info = CoinInfo(coin, now)
                    current = (info.hide - root.Position).Magnitude
                        + math.max(0, coin.Position.Y - info.hide.Y) * 1.2
                        + (info.exposed and 25 or 0)
                        + MurderPenalty(coin.Position, murderer)
                end
                if not current or score + 6 < current then
                    Motion.coin, Motion.phase, Motion.goT, Motion.tries, coin =
                        candidate, "go", now, Motion.tries + 1, candidate
                end
            end
        end
    end

    if not coin then
        Stats.Status = Motion.blocked and "avoiding" or "wait_coins"
        Move(root, velocity, gyro, HideAt(root, now), o.delta, speed)
        Motion.phase = "wait"
        return
    end

    Stats.Status = gun and "picking_gun" or "farming"
    local info = CoinInfo(coin, now)

    -- Фаза "go": летим под пол к точке под монетой
    if Motion.phase ~= "rise" then
        if Motion.phase ~= "go" then
            Motion.phase, Motion.goT = "go", now
        end
        local force = RoundState.firstJump and coin ~= gun
        if force then RoundState.firstJump = false end
        Jump(root, info.hide, force, now)

        local distance = Move(root, velocity, gyro, info.hide, o.delta, speed)
        if distance < 0.7 then
            Motion.phase, Motion.riseFrom, Motion.dwellFrom = "rise", now, nil
            return
        end
        if now - (Motion.goT or now) > distance / math.max(speed, 1) + 4 then
            SkipCoin(coin)
            Motion.coin, Motion.gunTarget, Motion.fails, Motion.phase = nil, nil, Motion.fails + 1, "go"
        end
        return
    end

    -- Фаза "rise": поднимаемся снизу к монете
    -- (избегание включено и убийца ближе 12 студов по горизонтали:
    -- пропускаем монету на 3 секунды)
    if murderer and Settings.AvoidMurderer and coin ~= gun then
        local distance = Vector3.new(coin.Position.X - murderer.X, 0, coin.Position.Z - murderer.Z).Magnitude
        if distance < 12 then
            Motion.skip[coin], Motion.coin, Motion.phase = now + 3, nil, "go"
            return
        end
    end

    local attempts = Motion.att[coin] or 0
    local gap = math.max(0.6, Motion.gapT - 0.45 * attempts)
    local destination = Vector3.new(info.hide.X, math.max(coin.Position.Y - gap, info.hide.Y), info.hide.Z)
    local distance = Move(root, velocity, gyro, destination, o.delta, speed)

    if now - (Motion.touchAt or 0) >= 1 / 30 then
        Motion.touchAt = now
        TouchCoin(character, coin)
    end

    if distance < 0.3 then
        Motion.dwellFrom = Motion.dwellFrom or now
        if now - Motion.dwellFrom >= 0.1 + (coin == gun and 0.25 or 0) then
            Motion.att[coin] = attempts + 1
            if attempts + 1 >= 4 then
                SkipCoin(coin)
                Motion.fails += 1
            else
                Motion.pending[coin] = { t = now + 0.9, gap = gap }
            end
            if coin == gun then Motion.gunTarget = nil end
            Motion.coin, Motion.dwellFrom, Motion.phase = nil, nil, "go"
            return
        end
    end

    if now - (Motion.riseFrom or now) > 1.4 then
        SkipCoin(coin)
        if coin == gun then Motion.gunTarget = nil end
        Motion.coin, Motion.fails, Motion.phase = nil, Motion.fails + 1, "go"
    end
end

-- ---------- Метод 1: Classic / Fast (напрямую к монете) ----------
local function FarmFast(o)
    local now, root, velocity, gyro, character = o.time, o.root, o.velocity, o.gyro, o.character
    local gun, murderer = o.gun, o.murderer
    local speed = ClassicSpeed()
    local coin = Motion.coin

    if coin and coin ~= gun and (not ValidCoin(coin) or Motion.pending[coin]) then
        if not ValidCoin(coin) then Motion.got += 1 end
        Motion.coin, coin = nil, nil
    end

    -- убийца подошёл к нашей монете ближе 24 ст.: бросаем её немедленно,
    -- не дожидаясь перевыбора раз в 0.3 с
    if coin and coin ~= gun and murderer
        and (coin.Position - murderer).Magnitude < 24 then
        Motion.skip[coin] = now + 2
        Motion.coin, coin = nil, nil
    end

    local target = gun
    if not target then
        if not coin or now - (Motion.pickT or 0) > 0.3 then
            Motion.pickT = now
            local best, lowest
            for _, container in ipairs(GetContainers()) do
                if container.Parent then
                    for _, candidate in ipairs(container:GetChildren()) do
                        if ValidCoin(candidate) and (Motion.skip[candidate] or 0) < now
                            and not Motion.pending[candidate] then
                            local score = (candidate.Position - root.Position).Magnitude
                                + MurderPenalty(candidate.Position, murderer)
                            if not lowest or score < lowest then
                                best, lowest = candidate, score
                            end
                        end
                    end
                end
            end

            Motion.blocked = false
            Motion.fleeAnchor = nil
            if best and Settings.AvoidMurderer and lowest >= 1000000 then
                best = nil
                Motion.blocked = true
            end
            if best and best ~= coin and (not coin or lowest + 6 < (coin.Position - root.Position).Magnitude
                + MurderPenalty(coin.Position, murderer)) then
                Motion.coin, Motion.goT, Motion.tries, coin = best, now, Motion.tries + 1, best
            end
        end
        target = coin
    end

    if not target then
        Stats.Status = Motion.blocked and "avoiding" or "wait_coins"
        if Motion.blocked and murderer then
            -- все монеты рядом с убийцей: не стоим на месте, а отходим
            -- от него по горизонтали (стоять рядом с убийцей = смерть).
            -- Отлёт ограничен: якорь ставится при входе в режим, идём от
            -- него на 10 ст.; 3 с без монет — стоим на месте
            if not Motion.fleeAnchor then
                Motion.fleeAnchor = root.Position
                Motion.fleeT = now
            end
            if now - (Motion.fleeT or now) > 3 then
                -- 3 секунды без монет: дальше убегать некуда, стоим
                velocity.Velocity = Vector3.zero
            else
                local away = Vector3.new(root.Position.X - murderer.X, 0, root.Position.Z - murderer.Z)
                away = away.Magnitude > 0.5 and away.Unit or Vector3.new(0, 0, 1)
                Move(root, velocity, gyro, Motion.fleeAnchor + away * 10, o.delta, speed)
            end
        else
            velocity.Velocity = Vector3.zero
        end
        Motion.phase = "wait"
        return
    end

    Stats.Status = gun and "picking_gun" or "farming"
    Motion.phase = "go"
    local force = RoundState.firstJump and target ~= gun
    if force then RoundState.firstJump = false end
    Jump(root, target.Position, force, now)

    local distance = Move(root, velocity, gyro, target.Position, o.delta, speed)
    if distance < 4 then
        TouchCoin(character, target)
    end

    if distance < 1 then
        Motion.dwellFrom = Motion.dwellFrom or now
        if now - Motion.dwellFrom >= (target == gun and 0.25 or 0.05) then
            if target == gun then
                Motion.gunTarget = nil
            else
                Motion.pending[target] = { t = now + 0.9 }
            end
            Motion.coin, Motion.dwellFrom = nil, nil
        end
        return
    end

    Motion.dwellFrom = nil
    if now - (Motion.goT or now) > distance / speed + 4 then
        SkipCoin(target)
        if target == gun then Motion.gunTarget = nil end
        Motion.coin, Motion.fails = nil, Motion.fails + 1
    end
end

-- ---------- Пистолет ----------
local gunDrop, gunDropAt = nil, 0

local function FindGunDrop()
    if gunDrop and gunDrop.Parent then return gunDrop end
    gunDrop = Esp.findDrop and Esp.findDrop() or nil
    return gunDrop
end

-- ---------- Убить всех (роль убийцы) ----------
-- Касаемся ножом каждого живого игрока, без телепорта к ним.
local KILL_PARTS = { "HumanoidRootPart", "UpperTorso", "Torso", "LowerTorso", "Head" }

local function KillAll(character)
    local knife = character:FindFirstChild("Knife")
    if not knife then
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        knife = backpack and backpack:FindFirstChild("Knife")
        if knife and knife:IsA("Tool") then
            knife.Parent = character
        end
    end
    if not knife then return end

    local handle = knife:FindFirstChild("Handle") or knife:FindFirstChildWhichIsA("BasePart")
    if not handle or not firetouchinterest then return end

    for _, player in ipairs(Players:GetPlayers()) do
        local target = player ~= LocalPlayer and player.Character or nil
        local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")
        if targetHumanoid and targetHumanoid.Health > 0 and target:FindFirstChild("HumanoidRootPart") then
            for _, name in ipairs(KILL_PARTS) do
                local part = target:FindFirstChild(name)
                if part then
                    pcall(function()
                        firetouchinterest(handle, part, 0)
                        firetouchinterest(handle, part, 1)
                        firetouchinterest(part, handle, 0)
                        firetouchinterest(part, handle, 1)
                    end)
                end
            end
        end
    end
    -- Activate нужен нативному клиенту (анимация/звук замаха), но он дёргает
    -- Tool.Activated — глушим окно, чтобы хук аима не бросал нож «сам»
    KnifeInternalUntil = os.clock() + 0.15
    pcall(function() knife:Activate() end)
end

-- ---------- Убить всех сразу (тумблер в разделе Боя) ----------
-- Тот же механизм, что «Убить всех при полном мешке»: касаемся ножом
-- каждого живого игрока. Работает независимо от авто-фарма.
local killAllAt = 0
Track(RunService.Heartbeat:Connect(function()
    if not (Combat.KillAllEnabled and Combat.KillAllEnabled()) then return end
    local now = os.clock()
    if now - killAllAt < 0.15 then return end
    local state = LocalRoleState()
    if state == "none" or state == "dead" then return end
    if not IsMurdererPlayer(LocalPlayer) then return end
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    killAllAt = now
    KillAll(character)
end))

-- ---------- Noclip ----------
-- Нужен для обоих методов: пока движок активен, части персонажа не сталкиваются.
local CharParts = {}
local CharCollisionOriginal = setmetatable({}, { __mode = "k" })
local CharacterDescendantConn = nil

RestoreFarmCollision = function()
    for part, original in pairs(CharCollisionOriginal) do
        pcall(function()
            if part and part.Parent then part.CanCollide = original end
        end)
        CharCollisionOriginal[part] = nil
    end
end
_G.YozoraHub_FarmCollisionRestore = RestoreFarmCollision

local function CacheCharacter(character)
    -- Не оставляем старые соединения в общем списке после респавна.
    if CharacterDescendantConn then
        pcall(function() CharacterDescendantConn:Disconnect() end)
        for i = #Connections, 1, -1 do
            if Connections[i] == CharacterDescendantConn then
                table.remove(Connections, i)
                break
            end
        end
        CharacterDescendantConn = nil
    end

    pcall(RestoreFarmCollision)
    table.clear(CharParts)
    if not character then return end

    local function AddPart(d)
        if d:IsA("BasePart") then
            table.insert(CharParts, d)
            CharCollisionOriginal[d] = d.CanCollide
        end
    end

    for _, d in ipairs(character:GetDescendants()) do AddPart(d) end

    CharacterDescendantConn = character.DescendantAdded:Connect(AddPart)
    Track(CharacterDescendantConn)
end

if LocalPlayer.Character then
    CacheCharacter(LocalPlayer.Character)
end
Track(LocalPlayer.CharacterAdded:Connect(CacheCharacter))

Track(RunService.Stepped:Connect(function()
    if Motion.phase == "idle" then return end
    local character = LocalPlayer.Character
    if not character then return end
    for index = #CharParts, 1, -1 do
        local part = CharParts[index]
        -- тулзы при снятии уезжают в рюкзак: детали должны перестать глушиться
        if not part.Parent or not part:IsDescendantOf(character) then
            table.remove(CharParts, index)
        elseif CharCollisionOriginal[part] == nil then
            CharCollisionOriginal[part] = part.CanCollide
        end
        if part.Parent and part:IsDescendantOf(character) and part.CanCollide then
            part.CanCollide = false
        end
    end
end))

-- ---------- Главный цикл ----------
-- Фармим, пока мы живы и участвуем в раунде (если роли известны)
local function CanFarm()
    local state = LocalRoleState()
    if state == "unknown" then return true end
    return state == "alive"
end

local function FarmTick(delta)
    local now = os.clock()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local alive = humanoid ~= nil and humanoid.Health > 0

    if now - Runtime.roundAt >= 0.5 then
        Runtime.roundAt = now
        RoundState.active = alive and CanFarm()
    end

    -- Роль на миг пропала (например, смена фазы): 1.5 с стоим на месте
    if RoundState.round and alive and not RoundState.active and Motion.phase ~= "idle" then
        Motion.cfLost = Motion.cfLost or now
        if now - Motion.cfLost < 1.5 then
            if root and humanoid then
                local velocity = EnsureMover(root, humanoid)
                velocity.Velocity = Vector3.zero
            end
            return
        end
    end
    if not RoundState.round or not alive or RoundState.active then
        Motion.cfLost = nil
    end

    if not RoundState.round then
        Stats.Status = "wait_round"
    elseif not alive then
        Stats.Status = "no_char"
    elseif not RoundState.active then
        local state = LocalRoleState()
        Stats.Status = (state == "pending" or state == "none") and "wait_round" or "spectating"
    end

    if not RoundState.round or not RoundState.active or not alive or not root then
        if Motion.phase ~= "idle" then FarmReset(character) end
        return
    end

    UpdatePending(now)

    local murdererRoot = GetMurdererRoot()
    local murderer = murdererRoot and murdererRoot.Position
    local full = IsBagFull()
    local handled = false
    -- шериф/герой с полным мешком «держит раунд»: не прячется и не
    -- респавнится, пока убийца жив (режим «Авто-выстрел при полном мешке»)
    local holdForKill = false

    if full then
        -- первые 12 секунд раунда не убиваем и не респавнимся (роли и мешок ещё могут быть неточными)
        local settled = RoundState.roundStartedAt == 0 or now - RoundState.roundStartedAt > 12

        -- Убийца: убиваем всех (общий троттлинг с ручным "Kill All",
        -- иначе каждый тик фарма долбит сервер касаниями)
        if settled and Settings.KillAllFull and IsMurdererPlayer(LocalPlayer) then
            Stats.Status = "killing"
            if now - killAllAt >= 0.3 then
                killAllAt = now
                KillAll(character)
            end
            handled = true
        end

        -- Шериф/герой: авто-выстрел в убийцу при полном мешке
        -- (движок сам экипирует пистолет и стреляет)
        if settled and Settings.ShootMurdererFull and not handled
            and not IsMurdererPlayer(LocalPlayer) then
            local murdererChar = murdererRoot and murdererRoot.Parent
            local murdererHumanoid = murdererChar and murdererChar:FindFirstChildOfClass("Humanoid")
            -- держим раунд только если пистолет вообще есть (в руках/рюкзаке)
            -- или его можно подобрать (включён фармовый «Подбирать пистолет»)
            local canGetGun = HasTool(LocalPlayer, "Gun")
            if not canGetGun then
                local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
                canGetGun = (backpack ~= nil and backpack:FindFirstChild("Gun") ~= nil)
                    or Settings.PickGun == true
            end
            holdForKill = canGetGun and murdererHumanoid ~= nil and murdererHumanoid.Health > 0
            if holdForKill and Combat.forceShootTick then
                Combat.forceShootTick(now)
            end
        end

        -- Остальные: сбрасываем персонажа (один раз, с задержкой и проверкой);
        -- шериф/герой ждёт смерти убийцы, вместо респавна
        if settled and not handled and not holdForKill and Settings.AutoRespawnFull
            and not RoundState.forcedFull
            and not Runtime.respawnPending and now - Runtime.lastRespawn > 3 then
            Runtime.respawnPending = true
            task.delay(0.4, function()
                Runtime.respawnPending = false
                if not IsBagFull() or RoundState.forcedFull then return end
                local current = LocalPlayer.Character
                local currentHumanoid = current and current:FindFirstChildOfClass("Humanoid")
                if not currentHumanoid or currentHumanoid.Health <= 0 then return end
                RoundState.active = false
                GameLog(L("Bag is full: respawning", "Мешок полон: респавн"))
                RoundState.forcedFull = true -- до нового раунда считаем мешок полным
                Runtime.lastRespawn = os.clock()
                table.clear(RoundState.full)
                currentHumanoid.Health = 0
            end)
        end
    end

    -- Подбор пистолета (невиновный, когда шериф погиб)
    if now - Runtime.gunAt >= 0.15 then
        Runtime.gunAt = now
        local _, role = LocalRoleState()
        local isInnocent = role ~= nil and tostring(role.Role) == "Innocent"
            and role.Dead ~= true and role.Killed ~= true
        local drop = Settings.PickGun and FindGunDrop() or nil
        local hasGun = HasTool(LocalPlayer, "Gun")

        if not drop or hasGun or not isInnocent then
            Motion.gunTarget, Motion.gunSince = nil, nil
        end
        if drop and not hasGun and isInnocent then
            if Motion.gunSeen ~= drop then
                Motion.gunSeen, Motion.gunSince = drop, now
            end
            TouchCoin(character, drop)
            if now - Motion.gunSince > 0.8 and Motion.gunTarget ~= drop then
                Motion.gunTarget, Motion.info[drop], Motion.phase, Motion.goT = drop, nil, "go", now
            end
        end
    end
    local gun = Motion.gunTarget
    if gun and (not gun.Parent or not Settings.PickGun) then
        Motion.gunTarget, gun = nil, nil
    end

    local method = Settings.FarmMethod == "undermap" and "undermap" or "classic"
    local velocity, gyro = EnsureMover(root, humanoid)
    if method ~= Motion.lastMethod then
        Motion.lastMethod, Motion.coin, Motion.hold, Motion.dwellFrom = method, nil, nil, nil
    end

    -- Мешок полон: прячемся на месте под полом и ждём конца раунда.
    -- Шериф/герой, который держит раунд (стреляет в убийцу), стоит на
    -- поверхности — монеты ему уже не нужны
    if full and not gun then
        Motion.phase, Motion.coin = "full", nil
        if not handled then Stats.Status = "bag_full" end
        if holdForKill then
            Motion.hold = nil
            Move(root, velocity, gyro, root.Position, delta, 0)
            return
        end
        if not Motion.hold or (Motion.hold - root.Position).Magnitude > 60 then
            Motion.hold = HideAt(root, now)
        end
        Move(root, velocity, gyro, Motion.hold, delta, method == "undermap" and UnderMapSpeed() or ClassicSpeed())
        return
    end
    Motion.hold = nil

    local options = {
        time = now, root = root, velocity = velocity, gyro = gyro, character = character,
        delta = delta, gun = gun, murderer = murderer,
    }
    if method == "classic" then
        FarmFast(options)
    else
        FarmUnderMap(options)
    end
end

ResetMotionHook = function()
    Motion.coin, Motion.hold, Motion.gunTarget = nil, nil, nil
    Motion.info, Motion.skip, Motion.pending, Motion.att = Weak(), Weak(), Weak(), Weak()
    if Motion.phase ~= "idle" then
        Motion.phase = "go"
    end
end

FarmSetEnabled = function(enabled)
    RoundState.firstJump = true
    Runtime.roundAt = 0 -- пересчитать "можем ли фармить" на следующем кадре
    if not enabled then
        RoundState.active = false
        FarmReset(LocalPlayer.Character)
    end
end

local lastFarmError = nil
Track(RunService.Heartbeat:Connect(function(delta)
    if not Alive() then return end

    if not Settings.AutoFarm then
        if Motion.phase ~= "idle" then
            FarmReset(LocalPlayer.Character)
        end
        Stats.Status = "off"
        return
    end

    local ok, err = pcall(FarmTick, delta)
    if not ok then
        err = tostring(err)
        if err ~= lastFarmError then
            lastFarmError = err
            warn("[Yozora Hub] farm error: " .. err)
        end
        FarmReset(LocalPlayer.Character)
    end
end))

-- ==========================================
-- 11. Auto rejoin on kick
-- ==========================================
local GuiService = game:GetService("GuiService")
local TeleportService = game:GetService("TeleportService")

-- В этих случаях заходить заново бессмысленно или вредно
local REJOIN_BLOCKED = { "same account", "another device", "different device", "banned", "terminated" }

local rejoin = { busy = false, tries = 0 }

local function OnKick(message)
    if rejoin.busy or not Settings.AutoRejoin then return end

    local text = tostring(message or ""):lower()
    for _, blocked in ipairs(REJOIN_BLOCKED) do
        if text:find(blocked, 1, true) then return end
    end

    rejoin.busy = true
    rejoin.tries = 0 -- новый цикл переподключения: интервалы заново
    GameLog(L("Disconnected: rejoining", "Отключение: перезаход"))
    QueueAutorun() -- чтобы скрипт запустился на новом сервере

    task.spawn(function()
        while Alive() and Settings.AutoRejoin do
            rejoin.tries += 1
            pcall(function()
                if rejoin.tries <= 2 then
                    -- сначала пробуем тот же сервер
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                else
                    TeleportService:Teleport(game.PlaceId, LocalPlayer)
                end
            end)
            -- повторные попытки реже: 10 с, потом 30 с, потом 60 с
            task.wait(rejoin.tries <= 6 and 10 or (rejoin.tries <= 12 and 30 or 60))
        end
        rejoin.busy = false
    end)
end

Track(GuiService.ErrorMessageChanged:Connect(function(message)
    if type(message) ~= "string" then
        message = GuiService:GetErrorMessage()
    end
    if message ~= "" then
        OnKick(message)
    end
end))

-- Запасной вариант: окно ошибки Roblox (нужен доступ к CoreGui)
task.spawn(function()
    local overlay
    pcall(function()
        overlay = game:GetService("CoreGui"):WaitForChild("RobloxPromptGui", 20)
            :WaitForChild("promptOverlay", 20)
    end)
    if not overlay or not Alive() then return end

    Track(overlay.ChildAdded:Connect(function(prompt)
        if prompt.Name ~= "ErrorPrompt" then return end
        task.wait(0.5)
        local message = ""
        pcall(function() message = GuiService:GetErrorMessage() end)
        if message == "" then
            pcall(function()
                for _, label in ipairs(prompt:GetDescendants()) do
                    if label:IsA("TextLabel") and #label.Text > #message then
                        message = label.Text
                    end
                end
            end)
        end
        OnKick(message ~= "" and message or "disconnected")
    end))
end)
