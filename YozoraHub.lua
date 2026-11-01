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
local VERSION = "v1.5"
local MENU_KEY = Enum.KeyCode.LeftControl

local Settings = {
    AutoFarm = false,
    ESP = false,
    AntiFling = false,
    AntiAFK = false,
    AvoidMurderer = false,
    AutoRespawnFull = false,
    KillAllFull = false,
    AutoRejoin = false,
    PickGun = false,
    AutoExecute = true,
    FarmMethod = "classic", -- classic | undermap
    SpeedClassic = 24,
    SpeedUnderMap = 21,
    TotalCoins = 0,
    Language = "en",
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
    for _, c in ipairs(Connections) do
        c:Disconnect()
    end
end

local function Alive()
    return _G.YozoraHub_RunId == RunId
end

local function Track(connection)
    table.insert(Connections, connection)
    return connection
end

-- ==========================================
-- 1. Config
-- ==========================================
local function SaveConfig()
    if not writefile then return end
    pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(Settings))
    end)
end

local function LoadConfig()
    if not (isfile and readfile and isfile(CONFIG_FILE)) then return end
    pcall(function()
        local decoded = HttpService:JSONDecode(readfile(CONFIG_FILE))
        if type(decoded) ~= "table" then return end
        for k, v in pairs(decoded) do
            if Settings[k] ~= nil and type(v) == type(Settings[k]) then
                Settings[k] = v
            end
        end
    end)
    -- быстрее ~22-24 студов/с уже подозрительно для античита
    Settings.SpeedClassic = math.clamp(Settings.SpeedClassic, 8, 24)
    Settings.SpeedUnderMap = math.clamp(Settings.SpeedUnderMap, 8, 22)
    if Settings.FarmMethod ~= "classic" and Settings.FarmMethod ~= "undermap" then
        Settings.FarmMethod = "classic"
    end
end

LoadConfig()

-- ==========================================
-- 2. Auto Execute on Teleport
-- ==========================================
local QueueTeleport = queue_on_teleport
    or (syn and syn.queue_on_teleport)
    or (fluxus and fluxus.queue_on_teleport)
    or queueonteleport

local autorunQueued = false

-- Ставит автозапуск в очередь на следующий телепорт (один раз за сессию:
-- повторная постановка дала бы дубли)
local function QueueAutorun()
    if autorunQueued or not QueueTeleport or not Settings.AutoExecute then return end
    autorunQueued = true
    pcall(function()
        if isfile and isfile(SCRIPT_FILE) then
            QueueTeleport(('loadstring(readfile("%s"))()'):format(SCRIPT_FILE))
        elseif _G.YozoraHub_ScriptSource then
            QueueTeleport(_G.YozoraHub_ScriptSource)
        end
    end)
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
-- 4. ESP
-- ==========================================
local COLOR_MURDERER = Color3.fromRGB(255, 45, 45)
local COLOR_SHERIFF = Color3.fromRGB(45, 140, 255)
local COLOR_INNOCENT = Color3.fromRGB(60, 230, 100)

local function HasTool(player, name)
    local character = player.Character
    local backpack = player:FindFirstChildOfClass("Backpack")
    return (character and character:FindFirstChild(name))
        or (backpack and backpack:FindFirstChild(name))
end

local function GetRoleColor(player)
    if HasTool(player, "Knife") then return COLOR_MURDERER end
    if HasTool(player, "Gun") then return COLOR_SHERIFF end
    return COLOR_INNOCENT
end

local function ClearESP()
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local highlight = character and character:FindFirstChild("YozoraHub_ESP")
        if highlight then
            highlight:Destroy()
        end
    end
end

local function UpdateESP()
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if player ~= LocalPlayer and character then
            local highlight = character:FindFirstChild("YozoraHub_ESP")
            if not highlight then
                highlight = New("Highlight", {
                    Name = "YozoraHub_ESP",
                    FillTransparency = 0.5,
                    OutlineTransparency = 0,
                }, character)
            end
            local color = GetRoleColor(player)
            if highlight.FillColor ~= color then
                highlight.FillColor = color
                highlight.OutlineColor = color
            end
        end
    end
end

task.spawn(function()
    while Alive() and task.wait(0.3) do
        if Settings.ESP then
            UpdateESP()
        end
    end
end)

-- ==========================================
-- 5. UI
-- ==========================================

-- ---------- Локализация (English / Русский) ----------
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
}

if not Lang[Settings.Language] then
    Settings.Language = "en"
end

local function T(key)
    local set = Lang[Settings.Language] or Lang.en
    return set[key] or Lang.en[key] or key
end

-- Задаёт текст и запоминает ключ, чтобы переводить при смене языка
local Localized = {}
local function Loc(obj, prop, key, prefix)
    prefix = prefix or ""
    table.insert(Localized, { Obj = obj, Prop = prop, Key = key, Prefix = prefix })
    obj[prop] = prefix .. T(key)
end

local C = {
    Bg = Color3.fromRGB(20, 12, 28),
    Sidebar = Color3.fromRGB(27, 16, 37),
    Card = Color3.fromRGB(32, 20, 43),
    Tile = Color3.fromRGB(42, 27, 56),
    Stroke = Color3.fromRGB(66, 42, 78),
    Accent = Color3.fromRGB(255, 128, 171),
    AccentLight = Color3.fromRGB(255, 190, 215),
    Text = Color3.fromRGB(240, 230, 240),
    Muted = Color3.fromRGB(165, 145, 175),
    Off = Color3.fromRGB(62, 43, 74),
}

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local oldGui = PlayerGui:FindFirstChild("YozoraHub_UI")
if oldGui then oldGui:Destroy() end

local ScreenGui = New("ScreenGui", {
    Name = "YozoraHub_UI",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

local Main = New("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(800, 540),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    BackgroundColor3 = C.Bg,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, ScreenGui)
New("UICorner", { CornerRadius = UDim.new(0, 14) }, Main)
New("UIStroke", { Color = C.Accent, Transparency = 0.55, Thickness = 1.5 }, Main)

-- На маленьких экранах уменьшаем окно
local camera = workspace.CurrentCamera
local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
local UiScale = New("UIScale", {
    Scale = math.clamp(math.min(viewport.X / 840, viewport.Y / 580), 0.5, 1),
}, Main)

local function MakeDraggable(handle, target)
    local dragging, dragStart, startPos = false, nil, nil

    Track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
        end
    end))

    Track(UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = (input.Position - dragStart) / UiScale.Scale
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))

    Track(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

-- ---------- Сайдбар ----------
local SIDEBAR_W = 200

local Sidebar = New("Frame", {
    Name = "Sidebar",
    Size = UDim2.new(0, SIDEBAR_W, 1, 0),
    BackgroundColor3 = C.Sidebar,
    BorderSizePixel = 0,
}, Main)
New("UICorner", { CornerRadius = UDim.new(0, 14) }, Sidebar)
-- выравниваем правый край сайдбара (скругление нужно только слева)
New("Frame", {
    Size = UDim2.new(0, 14, 1, 0),
    Position = UDim2.new(1, -14, 0, 0),
    BackgroundColor3 = C.Sidebar,
    BorderSizePixel = 0,
}, Sidebar)

local Header = New("Frame", {
    Size = UDim2.new(1, 0, 0, 48),
    BackgroundTransparency = 1,
}, Sidebar)
New("TextLabel", {
    Size = UDim2.new(1, -24, 1, 0),
    Position = UDim2.fromOffset(14, 0),
    BackgroundTransparency = 1,
    Text = "🌸 Yozora Hub",
    TextColor3 = C.AccentLight,
    Font = Enum.Font.GothamBold,
    TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Left,
}, Header)
MakeDraggable(Header, Main)

local SearchBox = New("TextBox", {
    Size = UDim2.new(1, -24, 0, 30),
    Position = UDim2.fromOffset(12, 52),
    BackgroundColor3 = C.Tile,
    BorderSizePixel = 0,
    Text = "",
    PlaceholderText = "🔍 " .. T("search"),
    PlaceholderColor3 = C.Muted,
    TextColor3 = C.Text,
    Font = Enum.Font.Gotham,
    TextSize = 14,
    ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
}, Sidebar)
New("UICorner", { CornerRadius = UDim.new(0, 8) }, SearchBox)
New("UIPadding", { PaddingLeft = UDim.new(0, 10) }, SearchBox)

local TabList = New("Frame", {
    Size = UDim2.new(1, 0, 1, -136),
    Position = UDim2.fromOffset(0, 94),
    BackgroundTransparency = 1,
}, Sidebar)
New("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, TabList)
New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, TabList)

New("TextLabel", {
    Size = UDim2.fromOffset(60, 22),
    Position = UDim2.new(0, 14, 1, -33),
    BackgroundTransparency = 1,
    Text = VERSION,
    TextColor3 = C.Muted,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, Sidebar)

local KeyBadge = New("TextLabel", {
    Size = UDim2.fromOffset(46, 22),
    Position = UDim2.new(1, -60, 1, -33),
    BackgroundColor3 = C.Tile,
    BorderSizePixel = 0,
    Text = "LCtrl",
    TextColor3 = C.AccentLight,
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
}, Sidebar)
New("UICorner", { CornerRadius = UDim.new(0, 6) }, KeyBadge)
New("UIStroke", { Color = C.Stroke, Thickness = 1 }, KeyBadge)

-- ---------- Контент ----------
local Content = New("Frame", {
    Size = UDim2.new(1, -SIDEBAR_W, 1, 0),
    Position = UDim2.fromOffset(SIDEBAR_W, 0),
    BackgroundTransparency = 1,
}, Main)

local PageTitle = New("TextLabel", {
    Size = UDim2.new(1, -80, 0, 30),
    Position = UDim2.fromOffset(18, 12),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = C.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 24,
    TextXAlignment = Enum.TextXAlignment.Left,
}, Content)

local PageSubtitle = New("TextLabel", {
    Size = UDim2.new(1, -80, 0, 16),
    Position = UDim2.fromOffset(18, 44),
    BackgroundTransparency = 1,
    Text = "",
    TextColor3 = C.Muted,
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, Content)

-- Иконки рисуем фигурами: символы вроде ✕ или ▾ есть не во всех шрифтах
local function DrawBar(parent, w, h, rotation)
    return New("Frame", {
        Size = UDim2.fromOffset(w, h),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Rotation = rotation or 0,
        BackgroundColor3 = C.Muted,
        BorderSizePixel = 0,
    }, parent)
end

local CloseBtn = New("TextButton", {
    Size = UDim2.fromOffset(30, 30),
    Position = UDim2.new(1, -44, 0, 14),
    BackgroundColor3 = C.Tile,
    BorderSizePixel = 0,
    Text = "",
    TextColor3 = C.Muted,
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    AutoButtonColor = false,
}, Content)
New("UICorner", { CornerRadius = UDim.new(0, 8) }, CloseBtn)
DrawBar(CloseBtn, 12, 2, 45)
DrawBar(CloseBtn, 12, 2, -45)
Track(CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui.Enabled = false -- вернуть меню: Left Ctrl
end))

local PagesHolder = New("Frame", {
    Size = UDim2.new(1, -24, 1, -84),
    Position = UDim2.fromOffset(12, 72),
    BackgroundTransparency = 1,
}, Content)

-- ---------- Вкладки ----------
local Pages = {}
local Sections = {}
local Rows = {}
local CurrentPage = nil

local function SelectPage(page)
    CurrentPage = page
    for _, p in ipairs(Pages) do
        local on = p == page
        p.Scroll.Visible = on
        p.Tab.BackgroundTransparency = on and 0.8 or 1
        p.TabLabel.TextColor3 = on and C.AccentLight or C.Muted
    end
    PageTitle.Text = T(page.TitleKey)
    PageSubtitle.Text = T(page.SubtitleKey)
end

local function CreatePage(icon, key, subtitleKey)
    local scroll = New("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = C.Accent,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, PagesHolder)
    New("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
    New("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, scroll)

    local tab = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = C.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, TabList)
    New("UICorner", { CornerRadius = UDim.new(0, 8) }, tab)
    local tabLabel = New("TextLabel", {
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.fromOffset(12, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.Muted,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, tab)

    Loc(tabLabel, "Text", key, icon .. "  ")
    local page = { Scroll = scroll, Tab = tab, TabLabel = tabLabel, TitleKey = key, SubtitleKey = subtitleKey }
    table.insert(Pages, page)
    Track(tab.MouseButton1Click:Connect(function()
        SelectPage(page)
    end))
    return page
end

-- ---------- Карточки и элементы ----------
local function CreateCard(page, icon, titleKey)
    local card = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.Card,
        BorderSizePixel = 0,
    }, page.Scroll)
    New("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
    New("UIStroke", { Color = C.Stroke, Thickness = 1 }, card)
    New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, card)

    local header = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = 1,
    }, card)
    local titleLabel = New("TextLabel", {
        Size = UDim2.new(1, -50, 1, 0),
        Position = UDim2.fromOffset(14, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, header)
    Loc(titleLabel, "Text", titleKey, icon .. "  ")

    -- значок сворачивания: "−" когда карточка раскрыта, "+" когда свёрнута
    local expandHolder = New("Frame", {
        Size = UDim2.fromOffset(24, 44),
        Position = UDim2.new(1, -34, 0, 0),
        BackgroundTransparency = 1,
    }, header)
    DrawBar(expandHolder, 10, 2)
    local verticalBar = DrawBar(expandHolder, 2, 10)
    verticalBar.Visible = false

    local body = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 2,
    }, card)
    New("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, body)
    New("UIPadding", {
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
        PaddingBottom = UDim.new(0, 10),
    }, body)

    Track(header.MouseButton1Click:Connect(function()
        body.Visible = not body.Visible
        verticalBar.Visible = not body.Visible
    end))

    local section = { Body = body, Card = card, Page = page }
    table.insert(Sections, section)
    return section
end

local function RegisterRow(row, section, key)
    table.insert(Rows, { Row = row, Section = section, Key = key })
end

local SwitchTween = TweenInfo.new(0.15, Enum.EasingStyle.Quad)

local function AddToggle(section, labelKey, key, onChange)
    local row = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    }, section.Body)
    local label = New("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    Loc(label, "Text", labelKey)

    local track = New("Frame", {
        Size = UDim2.fromOffset(42, 22),
        Position = UDim2.new(1, -42, 0.5, -11),
        BackgroundColor3 = C.Off,
        BorderSizePixel = 0,
    }, row)
    New("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
    local knob = New("Frame", {
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, track)
    New("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

    local function render(animate)
        local on = Settings[key]
        local trackColor = on and C.Accent or C.Off
        local knobPos = on and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3)
        if animate then
            TweenService:Create(track, SwitchTween, { BackgroundColor3 = trackColor }):Play()
            TweenService:Create(knob, SwitchTween, { Position = knobPos }):Play()
        else
            track.BackgroundColor3 = trackColor
            knob.Position = knobPos
        end
    end

    render(false)

    Track(row.MouseButton1Click:Connect(function()
        Settings[key] = not Settings[key]
        render(true)
        SaveConfig()
        if onChange then
            onChange(Settings[key])
        end
    end))

    RegisterRow(row, section, labelKey)
end

local function AddSlider(section, labelKey, key, min, max)
    local row = New("Frame", {
        Size = UDim2.new(1, 0, 0, 58),
        BackgroundTransparency = 1,
    }, section.Body)
    local label = New("TextLabel", {
        Size = UDim2.new(1, -50, 0, 24),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    Loc(label, "Text", labelKey)
    local valueLabel = New("TextLabel", {
        Size = UDim2.fromOffset(44, 24),
        Position = UDim2.new(1, -44, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.AccentLight,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, row)

    local hit = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 22),
        Position = UDim2.fromOffset(0, 26),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    }, row)
    local track = New("Frame", {
        Size = UDim2.new(1, 0, 0, 6),
        Position = UDim2.new(0, 0, 0.5, -3),
        BackgroundColor3 = C.Off,
        BorderSizePixel = 0,
    }, hit)
    New("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
    local fill = New("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = C.Accent,
        BorderSizePixel = 0,
    }, track)
    New("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
    local knob = New("Frame", {
        Size = UDim2.fromOffset(14, 14),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = C.AccentLight,
        BorderSizePixel = 0,
    }, track)
    New("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

    local function setVisual(value)
        local rel = (value - min) / (max - min)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, 0, 0.5, 0)
        valueLabel.Text = tostring(value)
    end
    setVisual(Settings[key])

    local dragging = false
    local function update(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local value = math.floor(min + rel * (max - min) + 0.5)
        if value ~= Settings[key] then
            Settings[key] = value
            setVisual(value)
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
            SaveConfig()
        end
    end))

    RegisterRow(row, section, labelKey)
end

-- Переключатель из нескольких вариантов (язык, метод фарма)
local function AddSegmented(section, labelKey, key, options, onChange, stacked)
    local row = New("Frame", {
        Size = UDim2.new(1, 0, 0, stacked and 70 or 46),
        BackgroundTransparency = 1,
    }, section.Body)
    local label = New("TextLabel", {
        Size = stacked and UDim2.new(1, 0, 0, 30) or UDim2.new(1, -190, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.Text,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    Loc(label, "Text", labelKey)

    local group = New("Frame", {
        Size = stacked and UDim2.new(1, 0, 0, 32) or UDim2.fromOffset(180, 32),
        Position = stacked and UDim2.fromOffset(0, 34) or UDim2.new(1, -180, 0.5, -16),
        BackgroundColor3 = C.Tile,
        BorderSizePixel = 0,
    }, row)
    New("UICorner", { CornerRadius = UDim.new(0, 8) }, group)

    local buttons = {}
    local function render()
        for value, btn in pairs(buttons) do
            local on = Settings[key] == value
            btn.BackgroundTransparency = on and 0 or 1
            btn.TextColor3 = on and C.Bg or C.Muted
        end
    end

    for i, option in ipairs(options) do
        local btn = New("TextButton", {
            Size = UDim2.new(1 / #options, -4, 1, -6),
            Position = UDim2.new((i - 1) / #options, 3, 0, 3),
            BackgroundColor3 = C.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = option.text or "",
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            AutoButtonColor = false,
        }, group)
        New("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)
        if option.textKey then
            Loc(btn, "Text", option.textKey)
        end
        buttons[option.value] = btn

        Track(btn.MouseButton1Click:Connect(function()
            if Settings[key] == option.value then return end
            Settings[key] = option.value
            render()
            SaveConfig()
            if onChange then
                onChange(option.value)
            end
        end))
    end

    render()
    RegisterRow(row, section, labelKey)
end

local function AddInfo(section, textKey)
    local label = New("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.Muted,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, section.Body)
    New("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 2) }, label)
    Loc(label, "Text", textKey)
    RegisterRow(label, section, textKey)
end

local function AddStatTile(parent, titleKey, initial)
    local tile = New("Frame", { BackgroundColor3 = C.Tile, BorderSizePixel = 0 }, parent)
    New("UICorner", { CornerRadius = UDim.new(0, 8) }, tile)
    local caption = New("TextLabel", {
        Size = UDim2.new(1, -20, 0, 16),
        Position = UDim2.fromOffset(10, 8),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.Muted,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, tile)
    Loc(caption, "Text", titleKey)
    return New("TextLabel", {
        Size = UDim2.new(1, -20, 0, 26),
        Position = UDim2.fromOffset(10, 24),
        BackgroundTransparency = 1,
        Text = initial,
        TextColor3 = C.AccentLight,
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, tile)
end

-- ---------- Поиск по функциям ----------
local function ApplySearch(query)
    query = (query:lower():gsub("^%s*(.-)%s*$", "%1"))

    local matchedSections = {}
    local firstMatchPage, currentHasMatch = nil, false

    for _, entry in ipairs(Rows) do
        local match = query == "" or T(entry.Key):lower():find(query, 1, true) ~= nil
        entry.Row.Visible = match
        if match then
            matchedSections[entry.Section] = true
            firstMatchPage = firstMatchPage or entry.Section.Page
            if entry.Section.Page == CurrentPage then
                currentHasMatch = true
            end
        end
    end

    for _, section in ipairs(Sections) do
        section.Card.Visible = query == "" or matchedSections[section] == true
    end

    if query ~= "" and not currentHasMatch and firstMatchPage then
        SelectPage(firstMatchPage)
    end
end

Track(SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    ApplySearch(SearchBox.Text)
end))

-- ---------- Содержимое вкладок ----------
local ApplyLanguage -- объявлена заранее: вызывается из переключателя языка

local PageFarm = CreatePage("🤑", "tab_farm", "sub_farm")
local PagePlayer = CreatePage("👤", "tab_player", "sub_player")
local PageVisual = CreatePage("👻", "tab_visual", "sub_visual")
local PageSettings = CreatePage("⚙️", "tab_settings", "sub_settings")

-- Farm
local StatsCard = CreateCard(PageFarm, "📊", "card_stats")
local StatsGrid = New("Frame", {
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
}, StatsCard.Body)
New("UIGridLayout", {
    CellSize = UDim2.new(0.5, -4, 0, 66),
    CellPadding = UDim2.fromOffset(8, 8),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, StatsGrid)
local CollectedValue = AddStatTile(StatsGrid, "stat_collected", "0")
local RateValue = AddStatTile(StatsGrid, "stat_rate", "0")
local TotalValue = AddStatTile(StatsGrid, "stat_total", FormatNumber(Settings.TotalCoins))
local StatusValue = AddStatTile(StatsGrid, "stat_status", T("status_" .. Stats.Status))

local FarmCard = CreateCard(PageFarm, "🤑", "card_farm")
AddToggle(FarmCard, "auto_farm", "AutoFarm", function(on)
    FarmSetEnabled(on)
end)
AddSegmented(FarmCard, "farm_method", "FarmMethod", {
    { value = "classic", textKey = "method_classic" },
    { value = "undermap", textKey = "method_undermap" },
}, nil, true)
AddSlider(FarmCard, "speed_classic", "SpeedClassic", 8, 24)
AddSlider(FarmCard, "speed_undermap", "SpeedUnderMap", 8, 22)

local SafetyCard = CreateCard(PageFarm, "🛡️", "card_safety")
AddToggle(SafetyCard, "avoid_murderer", "AvoidMurderer")
AddToggle(SafetyCard, "pick_gun", "PickGun")

local FullCard = CreateCard(PageFarm, "💰", "card_full")
AddToggle(FullCard, "respawn_full", "AutoRespawnFull")
AddToggle(FullCard, "kill_all_full", "KillAllFull")

local ConnectionCard = CreateCard(PageFarm, "🔗", "card_connection")
AddToggle(ConnectionCard, "auto_rejoin", "AutoRejoin")

-- Player
local ProtectCard = CreateCard(PagePlayer, "🛡️", "card_protect")
AddToggle(ProtectCard, "anti_fling", "AntiFling")
AddToggle(ProtectCard, "anti_afk", "AntiAFK")

-- Visuals
local EspCard = CreateCard(PageVisual, "👻", "card_esp")
AddToggle(EspCard, "esp_roles", "ESP", function(on)
    if not on then ClearESP() end
end)
AddInfo(EspCard, "esp_legend")

-- Settings
local InterfaceCard = CreateCard(PageSettings, "🌐", "card_interface")
AddSegmented(InterfaceCard, "language", "Language", {
    { value = "en", text = "English" },
    { value = "ru", text = "Русский" },
}, function()
    ApplyLanguage()
end)

local ScriptCard = CreateCard(PageSettings, "⚡", "card_script")
AddToggle(ScriptCard, "auto_execute", "AutoExecute")
AddInfo(ScriptCard, "menu_hint")

ApplyLanguage = function()
    for _, entry in ipairs(Localized) do
        entry.Obj[entry.Prop] = entry.Prefix .. T(entry.Key)
    end
    SearchBox.PlaceholderText = "🔍 " .. T("search")
    StatusValue.Text = T("status_" .. Stats.Status)
    if CurrentPage then
        SelectPage(CurrentPage)
    end
    ApplySearch(SearchBox.Text)
end

SelectPage(PageFarm)

-- Обновление статистики в интерфейсе
task.spawn(function()
    while Alive() and task.wait(0.5) do
        CollectedValue.Text = FormatNumber(Stats.Session)
        RateValue.Text = FormatNumber(Stats.Rate)
        TotalValue.Text = FormatNumber(Settings.TotalCoins)
        StatusValue.Text = T("status_" .. Stats.Status)
    end
end)

-- Показ/скрытие меню на Left Ctrl
Track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end -- игнор, если игрок печатает в чат или в поиск
    if input.KeyCode == MENU_KEY then
        ScreenGui.Enabled = not ScreenGui.Enabled
    end
end))

-- ==========================================
-- 6. Anti-Fling
-- ==========================================
local MAX_HORIZONTAL_SPEED = 60 -- обычная скорость ходьбы ~16
local MAX_UP_SPEED = 80         -- прыжок даёт ~50
local MAX_SPIN = 30
local VOID_MARGIN = 100         -- запас над высотой, на которой игра убивает

local LastSafeCFrame = nil
local lastSafeSave = 0

Track(LocalPlayer.CharacterAdded:Connect(function()
    LastSafeCFrame = nil
end))

Track(RunService.Stepped:Connect(function()
    if not Settings.AntiFling then return end

    -- 1. Другие игроки не могут физически толкать нас
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if player ~= LocalPlayer and character then
            for _, part in ipairs(character:GetChildren()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
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
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.zero)
end))

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
    skipped = setmetatable({}, { __mode = "k" }), -- монеты, которые не удалось подобрать
    active = false,      -- мы живы и участвуем в раунде
    firstJump = true,    -- в начале раунда первый прыжок к монете разрешён всегда
    eventsReady = false,
    dirty = false,
    bag = nil, bagItems = {}, bagAt = 0,
}

local ResetMotionHook -- задаётся в секции Auto Farm

local function RoundStart(coinsStarted)
    RoundState.round = true
    RoundState.skipped = setmetatable({}, { __mode = "k" })
    if not coinsStarted then
        RoundState.collected = {}
    end
    table.clear(RoundState.full)
    RoundState.forcedFull = false
    RoundState.coinsStarted = coinsStarted and os.clock() or 0
    RoundState.knownRound = true
    RoundState.firstJump = true
    if ResetMotionHook then ResetMotionHook() end
end

local function RoundEnd()
    RoundState.round = false
    RoundState.collected = {}
    RoundState.forcedFull = false
    RoundState.coinsStarted = 0
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
        RoundState.dirty = true
    end
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

    -- все известные типы монет полны (например, и монеты, и конфеты)
    local any, all = false, true
    for _, full in pairs(RoundState.full) do
        any = true
        if not full then all = false end
    end
    if any and all then return true end

    if os.clock() - RoundState.coinsStarted < 2 then return false end
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
task.spawn(function()
    while Alive() and task.wait(0.5) do
        for _, container in ipairs(GetContainers()) do
            if container.Parent and #container:GetChildren() > 0 then
                if RoundState.coinsStarted == 0 then
                    RoundState.coinsStarted = os.clock()
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
local Roles = { data = nil, remote = nil, lastFind = 0 }

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

task.spawn(function()
    while Alive() and task.wait(1) do
        if Settings.AutoFarm then
            local remote = FindRolesRemote()
            if remote then
                local ok, result = pcall(function()
                    return remote:InvokeServer()
                end)
                Roles.data = (ok and type(result) == "table") and result or nil
            else
                Roles.data = nil
            end
        end
    end
end)

local function IsMurdererPlayer(player)
    local data = Roles.data
    local role = type(data) == "table" and data[player.Name] or nil
    if role and role.Role then
        return tostring(role.Role):lower():find("murder") ~= nil
    end
    return HasTool(player, "Knife") and true or false
end

-- "unknown" (нет данных) / "none" (не в раунде) / "dead" / "alive"
local function LocalRoleState()
    local data = Roles.data
    if type(data) ~= "table" then return "unknown", nil end
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
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and IsMurdererPlayer(player) then
                murdererCache = player
                break
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
-- 10. Auto Farm (методы: Classic и Under Map)
-- ==========================================
-- Движок построен по образцу присланного кода: BodyVelocity-мувер, выбор
-- монеты по оценке, штраф рядом с убийцей, подтверждение подбора и пропуск
-- монет, которые не засчитались.
local function Weak()
    return setmetatable({}, { __mode = "k" })
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

local function EnsureMover(root, humanoid)
    local velocity = root:FindFirstChild("YozoraFarmBV")
    if not velocity then
        velocity = Instance.new("BodyVelocity")
        velocity.Name = "YozoraFarmBV"
        velocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        velocity.P = 30000
        velocity.Velocity = Vector3.zero
        velocity.Parent = root
    end

    local gyro = root:FindFirstChild("YozoraFarmBG")
    if not gyro then
        gyro = Instance.new("BodyGyro")
        gyro.Name = "YozoraFarmBG"
        gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        gyro.P = 30000
        gyro.CFrame = CFrame.lookAt(
            root.Position,
            root.Position + Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z + 1e-4)
        )
        gyro.Parent = root
    end

    if humanoid and not humanoid.PlatformStand then
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

local function FarmReset(character)
    pcall(function()
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if root then
            for _, name in ipairs({ "YozoraFarmBV", "YozoraFarmBG" }) do
                local object = root:FindFirstChild(name)
                if object then object:Destroy() end
            end
        end
        if humanoid and humanoid.PlatformStand then
            humanoid.PlatformStand = false
            if humanoid.Health > 0 then
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
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
    -- (убийца ближе 12 студов по горизонтали: пропускаем монету на 3 секунды)
    if murderer and coin ~= gun then
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
        velocity.Velocity = Vector3.zero
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
    if os.clock() - gunDropAt < 1 then return nil end
    gunDropAt = os.clock()
    local drop = workspace:FindFirstChild("GunDrop")
    if not drop then
        for _, child in ipairs(workspace:GetChildren()) do
            drop = child:FindFirstChild("GunDrop")
            if drop then break end
        end
    end
    gunDrop = drop and drop:IsA("BasePart") and drop or nil
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
    pcall(function() knife:Activate() end)
end

-- ---------- Noclip ----------
-- Нужен для обоих методов: пока движок активен, части персонажа не сталкиваются.
local CharParts = {}

local function CacheCharacter(character)
    CharParts = {}
    for _, d in ipairs(character:GetDescendants()) do
        if d:IsA("BasePart") then
            table.insert(CharParts, d)
        end
    end
    character.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then
            table.insert(CharParts, d)
        end
    end)
end

if LocalPlayer.Character then
    CacheCharacter(LocalPlayer.Character)
end
Track(LocalPlayer.CharacterAdded:Connect(CacheCharacter))

Track(RunService.Stepped:Connect(function()
    if Motion.phase == "idle" then return end
    for _, part in ipairs(CharParts) do
        if part.Parent and part.CanCollide then
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
        Stats.Status = "spectating"
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

    if full then
        -- Убийца: убиваем всех
        if Settings.KillAllFull and IsMurdererPlayer(LocalPlayer) then
            Stats.Status = "killing"
            KillAll(character)
            handled = true
        end

        -- Остальные: сбрасываем персонажа (один раз, с задержкой и проверкой)
        if not handled and Settings.AutoRespawnFull and not RoundState.forcedFull
            and not Runtime.respawnPending and now - Runtime.lastRespawn > 3 then
            Runtime.respawnPending = true
            task.delay(0.4, function()
                Runtime.respawnPending = false
                if not IsBagFull() or RoundState.forcedFull then return end
                local current = LocalPlayer.Character
                local currentHumanoid = current and current:FindFirstChildOfClass("Humanoid")
                if not currentHumanoid or currentHumanoid.Health <= 0 then return end
                RoundState.active = false
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

    -- Мешок полон: прячемся на месте под полом и ждём конца раунда
    if full and not gun then
        Motion.phase, Motion.coin = "full", nil
        if not handled then Stats.Status = "bag_full" end
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
