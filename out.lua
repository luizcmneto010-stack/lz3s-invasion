-- ============================================================
--  lz3s Invasion Menu (v2)
--  Abas: INVASION (inclui Auto Card) | TREASURE | CONFIG
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local VirtualUser       = game:GetService("VirtualUser")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")

-- ===================== NAVEGADOR =====================
local function nav(raiz, ...)
    local atual = raiz
    for _, nome in ipairs({...}) do
        atual = atual:WaitForChild(nome)
    end
    return atual
end

-- ===================== MÓDULOS (INVASION) =====================
local remotes             = require(nav(ReplicatedStorage, "src", "common", "remotes")).remotes
local invasionStore       = require(nav(ReplicatedStorage, "src", "common", "store", "gamemodes", "invasion"))
local getInvasionByPlayer = invasionStore.getInvasionByPlayer
local USER_KEY            = require(nav(ReplicatedStorage, "src", "common", "constants", "core")).USER_KEY

local charm     = require(nav(ReplicatedStorage, "rbxts_include", "node_modules", "@rbxts", "charm", "src"))
local computed  = charm.computed
local subscribe = charm.subscribe

local ok_lobby, lobbyStore = pcall(function()
    return require(nav(ReplicatedStorage, "src", "common", "store", "gamemodes", "lobbies"))
end)
local lobbiesStore     = ok_lobby and lobbyStore.lobbiesStore     or nil
local getLobbyByPlayer = ok_lobby and lobbyStore.getLobbyByPlayer or nil

local ok_jp, joinPromptStore = pcall(function()
    return require(nav(
        game:GetService("StarterPlayer"),
        "app", "common", "components", "pages",
        "invasion", "hud", "join-prompt-store"
    ))
end)
local clearInvasionJoinPrompt = ok_jp and joinPromptStore.clearInvasionJoinPrompt or nil

-- ===================== MÓDULOS (TREASURE) =====================
local getPlayerData = require(nav(ReplicatedStorage, "src", "common", "store", "players", "datastore")).getPlayerData
local TREASURE_HUNT_TILE_COUNT = require(nav(ReplicatedStorage, "src", "common", "content", "events", "treasure-hunt")).TREASURE_HUNT_TILE_COUNT

-- ===================== CONFIG GERAL =====================
local DEBUG_PRINT   = true  -- deixei TRUE pra você ver no console o que o Auto Treasure está fazendo. Pode mudar pra false depois.
local INVASION_NAME = "Dark Matter Invasion"
local MIN_PLAYERS   = 1
local CONFIG_FILE   = "lz3s_invasion_config.json"

local function logf(msg)
    if DEBUG_PRINT then print("[lz3s] " .. tostring(msg)) end
end

-- ===================== ESTADO =====================
local AUTO_START    = false
local AUTO_CARD     = false
local AUTO_ACCEPT   = false
local AUTO_REPLAY   = false
local AUTO_JOIN     = false
local AUTO_TREASURE = false
local AUTO_TP       = false
local BLACK_SCREEN  = false

local CARD_MODO          = "dano"
local CARD_SEC_REINF     = false
local CARD_SEC_BARRICADE = false
local CARD_SEC_ID        = nil -- "reinf" | "barricade" | nil

local KEYBIND_KEYS      = {"RightShift", "K"}
local KEYBIND_RECORDING = false

-- ============================================================
--  ANTI-AFK (sempre ativo, invisível)
-- ============================================================
Players.LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    task.wait(0.1)
    VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    logf("Anti-AFK: ping enviado")
end)

-- ============================================================
--  CRIAR INVASÃO
-- ============================================================
local criandoInvasao = false
local function criarInvasaoManual()
    if criandoInvasao then return end
    criandoInvasao = true
    local ok, p = pcall(function()
        return remotes.invasions.create:request(INVASION_NAME, { friendsOnly = false })
    end)
    if not ok then criandoInvasao = false; return end
    p:andThen(function() criandoInvasao = false end)
     :catch(function() criandoInvasao = false end)
end

-- ============================================================
--  AUTO START
-- ============================================================
local lastStarted = 0
RunService.Heartbeat:Connect(function()
    if not AUTO_START then return end
    if tick() - lastStarted < 3 then return end
    if getLobbyByPlayer == nil then return end
    local ok, lobby = pcall(getLobbyByPlayer, USER_KEY)
    if not ok or lobby == nil or lobby.owner ~= USER_KEY then return end
    local count = 0
    for _ in pairs(lobby.players or {}) do count += 1 end
    if count >= MIN_PLAYERS then
        lastStarted = tick()
        remotes.lobbies.start:fire()
    end
end)

-- ============================================================
--  AUTO CARD (sistema de prioridade)
-- ============================================================
local DANO_PRIO = {
    ["Invasion Espionage"]            = 10,
    ["Invasion Boss Killer III"]      = 9,
    ["Invasion Boss Killer II"]       = 8,
    ["Invasion Boss Killer I"]        = 7,
    ["Invasion Warrior Blessing III"] = 6,
    ["Invasion Battle Momentum"]      = 5,
    ["Invasion Warrior Blessing II"]  = 4,
    ["Invasion Warrior Blessing I"]   = 3,
}
local DROP_PRIO = {
    ["Invasion Overflowing Wealth III"] = 3,
    ["Invasion Overflowing Wealth II"]  = 2,
    ["Invasion Overflowing Wealth I"]   = 1,
}

local jaVotou  = false
local rodadaId = nil

local function assinatura(cards)
    local ids = {}
    for i, item in ipairs(cards) do ids[i] = typeof(item)=="table" and tostring(item.id) or tostring(item) end
    return table.concat(ids, "|")
end

local function escolherCarta(cards)
    local ids = {}
    for _, item in ipairs(cards) do table.insert(ids, typeof(item)=="table" and item.id or tostring(item)) end
    if CARD_SEC_REINF then
        for _, id in ipairs(ids) do if id=="Invasion Warrior Reinforcement" then return id end end
    end
    if CARD_SEC_BARRICADE then
        for _, id in ipairs(ids) do if id=="Invasion Barricade Repair" then return id end end
    end
    local tab = CARD_MODO=="dano" and DANO_PRIO or DROP_PRIO
    local best, bestP = nil, -1
    for _, id in ipairs(ids) do
        local p = tab[id]
        if p and p > bestP then bestP = p; best = id end
    end
    return best or ids[math.random(1, #ids)]
end

subscribe(computed(function() return getInvasionByPlayer(USER_KEY) end), function(invasion)
    if not AUTO_CARD or invasion == nil then return end
    local cards = invasion.cardsDisplayed
    if cards == nil or #cards == 0 then jaVotou = false; rodadaId = nil; return end
    if invasion.phase ~= "intermission" then return end
    local sig = assinatura(cards)
    if sig ~= rodadaId then rodadaId = sig; jaVotou = false end
    if jaVotou then return end
    jaVotou = true
    local cardId = escolherCarta(cards)
    task.delay(0.5 + math.random() * 2, function()
        local inv = getInvasionByPlayer(USER_KEY)
        if inv == nil or inv.phase ~= "intermission" then return end
        remotes.invasions.voteCard:fire(cardId)
        logf("Auto Card: " .. tostring(cardId))
    end)
end)

-- ============================================================
--  AUTO ACCEPT REPLAY
-- ============================================================
remotes.invasions.notifyReplay:connect(function(player, invasionId)
    if not AUTO_ACCEPT then return end
    task.delay(0.3, function()
        if clearInvasionJoinPrompt then pcall(clearInvasionJoinPrompt) end
        remotes.invasions.acceptReplay:request(invasionId):andThen(function() end)
    end)
end)

-- ============================================================
--  AUTO REPLAY
-- ============================================================
local replayRemote
do
    local p = ReplicatedStorage:FindFirstChild("rbxts_include")
    p = p and p:FindFirstChild("node_modules")
    p = p and p:FindFirstChild("@rbxts")
    p = p and p:FindFirstChild("remo")
    p = p and p:FindFirstChild("src")
    p = p and p:FindFirstChild("container")
    replayRemote = p and p:FindFirstChild("invasions.replay")
end

task.spawn(function()
    while true do
        task.wait(3)
        if AUTO_REPLAY and replayRemote then
            pcall(function()
                if replayRemote:IsA("RemoteEvent") then replayRemote:FireServer()
                elseif replayRemote:IsA("RemoteFunction") then replayRemote:InvokeServer() end
            end)
        end
    end
end)

-- ============================================================
--  AUTO JOIN
-- ============================================================
local lastJoin = 0
local triedLobbies = {}
RunService.Heartbeat:Connect(function()
    if not AUTO_JOIN then return end
    if tick() - lastJoin < 5 then return end
    if getInvasionByPlayer(USER_KEY) ~= nil then return end
    if lobbiesStore == nil then return end
    local ok, all = pcall(function() return lobbiesStore() end)
    if not ok or all == nil then return end
    for id, lobby in pairs(all) do
        if lobby.type=="invasion" and not lobby.friendsOnly and not triedLobbies[id] then
            local max = lobby.maxPlayers or 4
            local count = #(lobby.players or {})
            if count < max then
                lastJoin = tick(); triedLobbies[id] = true
                task.spawn(function()
                    remotes.lobbies.join:request(id):andThen(function(r)
                        if r ~= true then triedLobbies[id] = nil end
                    end)
                end)
                break
            end
        end
    end
end)

-- ============================================================
--  AUTO TP
-- ============================================================
local tpFeitoIds = {}
task.spawn(function()
    while true do
        task.wait(1)
        if not AUTO_TP then continue end
        local char = Players.LocalPlayer.Character
        if char == nil then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp == nil then continue end
        local ok, mapFolder = pcall(function() return workspace.World.Map end)
        if not ok or mapFolder == nil then continue end
        for _, filho in ipairs(mapFolder:GetChildren()) do
            local nome = filho.Name
            if not nome:match("^invasion%-") then continue end
            if tpFeitoIds[nome] then continue end
            local okAlvo, pos = pcall(function()
                local turret = filho:WaitForChild("Main Base Turret", 5)
                local base_low = turret:WaitForChild("base_low", 5)
                if base_low:IsA("BasePart") then return base_low.Position
                elseif base_low:IsA("Model") then return base_low:GetPivot().Position
                else
                    local p = base_low:FindFirstChildWhichIsA("BasePart", true)
                    if p then return p.Position end
                    error("sem BasePart")
                end
            end)
            if not okAlvo then logf("Auto TP erro: "..tostring(pos)); continue end
            tpFeitoIds[nome] = true
            hrp.CFrame = CFrame.new(pos + Vector3.new(0, 10, 0))
            logf("Auto TP: teleportado em "..nome)
        end
    end
end)

-- ============================================================
--  AUTO TREASURE  (com prints de debug pra achar o bug)
-- ============================================================
local DELAY_ENTRE_CAVADAS   = 0.6
local CHECK_INTERVAL_SEM_PA = 2
local treasureRodando       = false

local function getQuantidadeDePas()
    local d = getPlayerData(USER_KEY)
    if d == nil then
        logf("Auto Treasure: getPlayerData retornou nil")
        return 0
    end
    local s = d.items and d.items.Shovel
    if s == nil then
        logf("Auto Treasure: d.items.Shovel é nil (talvez o nome do item seja outro)")
        return 0
    end
    return s.amount or 0
end

local function getTilesJaCavadas()
    local d = getPlayerData(USER_KEY)
    if d == nil then return {} end
    local dug = d.treasureHunt and d.treasureHunt.dug
    if dug == nil then
        logf("Auto Treasure: d.treasureHunt.dug é nil")
        return {}
    end
    local t = {}
    for _, item in pairs(dug) do if item and item.index then t[item.index] = true end end
    return t
end

local function escolherTileAleatoria()
    local cavadas = getTilesJaCavadas()
    local disp = {}
    for i = 1, TREASURE_HUNT_TILE_COUNT do if not cavadas[i] then table.insert(disp, i) end end
    if #disp == 0 then
        logf("Auto Treasure: nenhuma tile disponível (todas cavadas?)")
        return nil
    end
    return disp[math.random(1, #disp)]
end

local function cavarUmaVez()
    local tile = escolherTileAleatoria()
    if tile == nil then return end
    local ok, p = pcall(function() return remotes.treasureHunt.dig:request(tile) end)
    if not ok then
        logf("Auto Treasure: erro ao chamar remotes.treasureHunt.dig -> " .. tostring(p))
        return
    end
    p:andThen(function(r)
        if r and r.reason then logf("Auto Treasure resultado: " .. tostring(r.reason)) end
    end):catch(function(err)
        logf("Auto Treasure: erro na promise -> " .. tostring(err))
    end)
end

local function iniciarLoopTreasure()
    if treasureRodando then return end
    treasureRodando = true
    logf("Auto Treasure: loop iniciado")
    task.spawn(function()
        while AUTO_TREASURE do
            local pas = getQuantidadeDePas()
            if pas > 0 then
                cavarUmaVez()
                task.wait(DELAY_ENTRE_CAVADAS)
            else
                logf("Auto Treasure: sem pás (Shovel = " .. tostring(pas) .. "), aguardando...")
                task.wait(CHECK_INTERVAL_SEM_PA)
            end
        end
        treasureRodando = false
        logf("Auto Treasure: loop parado")
    end)
end

-- ============================================================
--  PERSISTÊNCIA (writefile/readfile - funções de executor)
-- ============================================================
local function fileFuncsDisponiveis()
    return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

local function montarConfigAtual()
    return {
        AUTO_START    = AUTO_START,
        AUTO_CARD     = AUTO_CARD,
        AUTO_ACCEPT   = AUTO_ACCEPT,
        AUTO_REPLAY   = AUTO_REPLAY,
        AUTO_JOIN     = AUTO_JOIN,
        AUTO_TREASURE = AUTO_TREASURE,
        AUTO_TP       = AUTO_TP,
        BLACK_SCREEN  = BLACK_SCREEN,
        CARD_MODO     = CARD_MODO,
        CARD_SEC_ID   = CARD_SEC_ID,
        MIN_PLAYERS   = MIN_PLAYERS,
        KEYBIND_KEYS  = KEYBIND_KEYS,
    }
end

local function salvarConfig()
    if not fileFuncsDisponiveis() then
        warn("[lz3s] writefile/readfile não disponíveis neste executor — não foi possível salvar.")
        return false
    end
    local dados = montarConfigAtual()
    local ok, encoded = pcall(function() return HttpService:JSONEncode(dados) end)
    if not ok then return false end
    local okWrite = pcall(function() writefile(CONFIG_FILE, encoded) end)
    return okWrite
end

local function carregarConfigDoArquivo()
    if not fileFuncsDisponiveis() then return nil end
    local okIs, existe = pcall(function() return isfile(CONFIG_FILE) end)
    if not okIs or not existe then return nil end
    local ok, raw = pcall(function() return readfile(CONFIG_FILE) end)
    if not ok or raw == nil then return nil end
    local okDecode, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
    if not okDecode then return nil end
    return decoded
end

-- ============================================================
--  BLACK SCREEN (chuva + texto medieval + close no topo)
-- ============================================================
local blackScreenGui
local blackScreenRainRunning = false
local setBlackScreen -- declarada aqui, definida abaixo
local BLACK_SCREEN_TOGGLE_UPDATE -- callback pro botão do menu ficar sincronizado

do
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    local existing = playerGui:FindFirstChild("AFKScreen")
    if existing then existing:Destroy() end

    blackScreenGui = Instance.new("ScreenGui")
    blackScreenGui.Name = "AFKScreen"
    blackScreenGui.IgnoreGuiInset = true
    blackScreenGui.DisplayOrder = 999
    blackScreenGui.ResetOnSpawn = false
    blackScreenGui.Enabled = false
    blackScreenGui.Parent = playerGui

    local background = Instance.new("Frame")
    background.Name = "Background"
    background.Size = UDim2.new(1, 0, 1, 0)
    background.Position = UDim2.new(0, 0, 0, 0)
    background.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    background.BorderSizePixel = 0
    background.ZIndex = 1
    background.ClipsDescendants = true
    background.Parent = blackScreenGui

    local rainContainer = Instance.new("Frame")
    rainContainer.Name = "RainContainer"
    rainContainer.Size = UDim2.new(1, 0, 1, 0)
    rainContainer.BackgroundTransparency = 1
    rainContainer.ZIndex = 1
    rainContainer.Parent = background

    local function createRaindrop()
        local drop = Instance.new("Frame")
        drop.Size = UDim2.new(0, 2, 0, math.random(15, 35))
        drop.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        drop.BackgroundTransparency = 0.75
        drop.BorderSizePixel = 0
        drop.ZIndex = 1
        drop.Position = UDim2.new(math.random(0, 1000) / 1000, 0, -0.1, 0)
        drop.Parent = rainContainer

        local fallTime = math.random(15, 25) / 10
        local tween = TweenService:Create(drop, TweenInfo.new(fallTime, Enum.EasingStyle.Linear), {
            Position = UDim2.new(drop.Position.X.Scale, 0, 1.1, 0)
        })
        tween:Play()
        tween.Completed:Connect(function()
            drop:Destroy()
        end)
    end

    local function startRainLoop()
        if blackScreenRainRunning then return end
        blackScreenRainRunning = true
        task.spawn(function()
            while blackScreenRainRunning do
                createRaindrop()
                task.wait(math.random(15, 30) / 100)
            end
        end)
    end

    local title = Instance.new("TextLabel")
    title.Name = "AFKTitle"
    title.Size = UDim2.new(0.5, 0, 0.08, 0)
    title.Position = UDim2.new(0.25, 0, 0.46, 0)
    title.BackgroundTransparency = 1
    title.Text = "lz3s AFK"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Font = Enum.Font.Fondamento
    title.TextScaled = true
    title.ZIndex = 2
    title.Parent = background

    task.spawn(function()
        while title.Parent do
            if blackScreenGui.Enabled then
                local fadeOut = TweenService:Create(title, TweenInfo.new(1.8, Enum.EasingStyle.Sine), {TextTransparency = 0.35})
                fadeOut:Play()
                fadeOut.Completed:Wait()
                local fadeIn = TweenService:Create(title, TweenInfo.new(1.8, Enum.EasingStyle.Sine), {TextTransparency = 0})
                fadeIn:Play()
                fadeIn.Completed:Wait()
            else
                task.wait(0.5)
            end
        end
    end)

    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.new(0, 44, 0, 44)
    closeButton.Position = UDim2.new(1, -64, 0, 20)
    closeButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    closeButton.Text = "X"
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextScaled = true
    closeButton.ZIndex = 3
    closeButton.AutoButtonColor = true
    closeButton.Parent = background

    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(1, 0)
    closeCorner.Parent = closeButton

    local closeStroke = Instance.new("UIStroke")
    closeStroke.Color = Color3.fromRGB(255, 255, 255)
    closeStroke.Thickness = 1.2
    closeStroke.Transparency = 0.3
    closeStroke.Parent = closeButton

    setBlackScreen = function(v)
        BLACK_SCREEN = v
        blackScreenGui.Enabled = v
        if v then
            startRainLoop()
        else
            blackScreenRainRunning = false
        end
        if BLACK_SCREEN_TOGGLE_UPDATE then BLACK_SCREEN_TOGGLE_UPDATE(v) end
    end

    closeButton.MouseButton1Click:Connect(function()
        setBlackScreen(false)
    end)
end

-- ============================================================
--  GUI PRINCIPAL
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "lz3sInvasion"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local okGui = pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
if not okGui then ScreenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

-- ── helpers visuais ─────────────────────────────────────────
local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 10); c.Parent = p
    return c
end
local function stroke(p, col, th)
    local s = Instance.new("UIStroke")
    s.Color = col or Color3.fromRGB(90,70,170); s.Thickness = th or 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = p
    return s
end
local function divider(parent, posY, width)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(0, width or 1, 0, 1)
    if width == nil then f.Size = UDim2.new(1,0,0,1) end
    f.Position = UDim2.fromOffset(0, posY)
    f.BackgroundColor3 = Color3.fromRGB(50,40,90); f.BackgroundTransparency = 0.3
    f.BorderSizePixel = 0; f.Parent = parent
    return posY + 10
end

local PALETTE = {
    bg          = Color3.fromRGB(16, 15, 24),
    panel       = Color3.fromRGB(22, 21, 32),
    titlebar    = Color3.fromRGB(38, 22, 84),
    accent      = Color3.fromRGB(125, 90, 235),
    accentDim   = Color3.fromRGB(90, 65, 170),
    toggleOff   = Color3.fromRGB(34, 33, 47),
    toggleOffTx = Color3.fromRGB(150, 145, 170),
    toggleOn    = Color3.fromRGB(30, 110, 70),
    toggleOnTx  = Color3.fromRGB(170, 255, 195),
    textMain    = Color3.fromRGB(225, 218, 245),
    textDim     = Color3.fromRGB(150, 142, 180),
    danger      = Color3.fromRGB(120, 35, 45),
    info        = Color3.fromRGB(35, 90, 120),
}

-- ── Janela principal (maior que antes) ───────────────────────
local WINDOW_W = 360
local Frame = Instance.new("Frame")
Frame.Name             = "Main"
Frame.Size             = UDim2.fromOffset(WINDOW_W, 460)
Frame.Position         = UDim2.new(0, 24, 0.5, -230)
Frame.BackgroundColor3 = PALETTE.bg
Frame.BorderSizePixel  = 0
Frame.Active           = true
Frame.Draggable        = true
Frame.Parent           = ScreenGui
corner(Frame, 14)
stroke(Frame, PALETTE.accentDim, 1.5)

-- sombra sutil (UIStroke duplo simulando profundidade)
local shadow = Instance.new("Frame")
shadow.Size = UDim2.new(1, 16, 1, 16)
shadow.Position = UDim2.new(0, -8, 0, -8)
shadow.BackgroundTransparency = 1
shadow.ZIndex = Frame.ZIndex - 1
shadow.Parent = ScreenGui

-- ── Barra de título ───────────────────────────────────────────
local TitleBar = Instance.new("Frame")
TitleBar.Size             = UDim2.new(1,0,0,44)
TitleBar.BackgroundColor3 = PALETTE.titlebar
TitleBar.BorderSizePixel  = 0
TitleBar.Parent           = Frame
corner(TitleBar, 14)

local patch = Instance.new("Frame")
patch.Size = UDim2.new(1,0,0,14); patch.Position = UDim2.new(0,0,1,-14)
patch.BackgroundColor3 = PALETTE.titlebar; patch.BorderSizePixel=0; patch.Parent=TitleBar

local TitleIcon = Instance.new("TextLabel")
TitleIcon.Size = UDim2.fromOffset(28,28)
TitleIcon.Position = UDim2.fromOffset(12,8)
TitleIcon.BackgroundTransparency = 1
TitleIcon.Text = "⚔"
TitleIcon.TextColor3 = PALETTE.accent
TitleIcon.TextSize = 20
TitleIcon.Font = Enum.Font.GothamBold
TitleIcon.Parent = TitleBar

local TitleLbl = Instance.new("TextLabel")
TitleLbl.Size             = UDim2.new(1,-160,1,0)
TitleLbl.Position         = UDim2.fromOffset(42,0)
TitleLbl.BackgroundTransparency = 1
TitleLbl.Text             = "lz3s Invasion"
TitleLbl.TextColor3       = PALETTE.textMain
TitleLbl.TextSize         = 16
TitleLbl.Font             = Enum.Font.GothamBold
TitleLbl.TextXAlignment   = Enum.TextXAlignment.Left
TitleLbl.Parent           = TitleBar

local AfkDot = Instance.new("Frame")
AfkDot.Size = UDim2.fromOffset(8,8)
AfkDot.Position = UDim2.new(1, -96, 0.5, -4)
AfkDot.BackgroundColor3 = Color3.fromRGB(90, 220, 130)
AfkDot.BorderSizePixel = 0
AfkDot.Parent = TitleBar
corner(AfkDot, 4)

local AfkLbl = Instance.new("TextLabel")
AfkLbl.Size = UDim2.fromOffset(78, 20)
AfkLbl.Position = UDim2.new(1, -84, 0.5, -10)
AfkLbl.BackgroundTransparency = 1
AfkLbl.Text = "Anti-AFK"
AfkLbl.TextColor3 = Color3.fromRGB(150, 220, 170)
AfkLbl.TextSize = 11
AfkLbl.Font = Enum.Font.GothamBold
AfkLbl.TextXAlignment = Enum.TextXAlignment.Left
AfkLbl.Parent = TitleBar

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Size = UDim2.fromOffset(28,28)
MinimizeBtn.Position = UDim2.new(1, -34, 0.5, -14)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(50, 35, 95)
MinimizeBtn.BorderSizePixel = 0
MinimizeBtn.Text = "—"
MinimizeBtn.TextColor3 = PALETTE.textMain
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.TextSize = 14
MinimizeBtn.Parent = TitleBar
corner(MinimizeBtn, 7)

-- ── Abas ──────────────────────────────────────────────────────
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -24, 0, 36)
TabBar.Position = UDim2.fromOffset(12, 54)
TabBar.BackgroundColor3 = PALETTE.panel
TabBar.BorderSizePixel = 0
TabBar.Parent = Frame
corner(TabBar, 10)

local TabPadding = Instance.new("UIPadding")
TabPadding.PaddingLeft = UDim.new(0,4)
TabPadding.PaddingRight = UDim.new(0,4)
TabPadding.PaddingTop = UDim.new(0,4)
TabPadding.PaddingBottom = UDim.new(0,4)
TabPadding.Parent = TabBar

local TabListLayout = Instance.new("UIListLayout")
TabListLayout.FillDirection = Enum.FillDirection.Horizontal
TabListLayout.Padding = UDim.new(0, 4)
TabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabListLayout.Parent = TabBar

local PagesHolder = Instance.new("ScrollingFrame")
PagesHolder.Size = UDim2.new(1, -24, 1, -102)
PagesHolder.Position = UDim2.fromOffset(12, 98)
PagesHolder.BackgroundTransparency = 1
PagesHolder.BorderSizePixel = 0
PagesHolder.ScrollBarThickness = 4
PagesHolder.ScrollBarImageColor3 = PALETTE.accentDim
PagesHolder.CanvasSize = UDim2.new(0,0,0,0)
PagesHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
PagesHolder.Parent = Frame

local PAGE_DEFS = {
    {key="INVASION", label="⚔ Invasion"},
    {key="TREASURE", label="💰 Treasure"},
    {key="CONFIG",   label="⚙ Config"},
}
local pageFrames = {}
local tabButtons = {}

local function selectTab(key)
    for k, f in pairs(pageFrames) do f.Visible = (k == key) end
    for k, b in pairs(tabButtons) do
        if k == key then
            b.BackgroundColor3 = PALETTE.accentDim
            b.TextColor3 = Color3.fromRGB(235, 225, 255)
        else
            b.BackgroundColor3 = PALETTE.panel
            b.TextColor3 = PALETTE.textDim
        end
    end
end

for i, def in ipairs(PAGE_DEFS) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1/#PAGE_DEFS, -3, 1, 0)
    btn.LayoutOrder = i
    btn.BackgroundColor3 = PALETTE.panel
    btn.BorderSizePixel = 0
    btn.Text = def.label
    btn.TextColor3 = PALETTE.textDim
    btn.TextSize = 13
    btn.Font = Enum.Font.GothamBold
    btn.Parent = TabBar
    corner(btn, 7)
    tabButtons[def.key] = btn

    local page = Instance.new("Frame")
    page.Name = def.key
    page.Size = UDim2.new(1, 0, 0, 0)
    page.AutomaticSize = Enum.AutomaticSize.Y
    page.BackgroundTransparency = 1
    page.Visible = false
    page.Parent = PagesHolder
    pageFrames[def.key] = page

    btn.MouseButton1Click:Connect(function() selectTab(def.key) end)
end

-- ── Helpers de widget (usam AutomaticSize, então não precisamos calcular y manualmente pros containers, mas ainda usamos posY pra empilhar dentro de cada página) ──
local function sectionHeader(parent, posY, text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,0,0,20); lbl.Position = UDim2.fromOffset(0, posY)
    lbl.BackgroundTransparency = 1
    lbl.Text = text; lbl.TextColor3 = PALETTE.accent
    lbl.TextSize = 13; lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = parent
    return divider(parent, posY + 22)
end

local function makeToggle(parent, posY, label, onToggle, icon)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,38); btn.Position = UDim2.fromOffset(0, posY)
    btn.BackgroundColor3 = PALETTE.toggleOff; btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Text = ""
    btn.Parent = parent
    corner(btn, 9)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -76, 1, 0)
    lbl.Position = UDim2.fromOffset(14, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = (icon and (icon.."  ") or "") .. label
    lbl.TextColor3 = PALETTE.toggleOffTx
    lbl.TextSize = 13
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = btn

    local pill = Instance.new("Frame")
    pill.Size = UDim2.fromOffset(54, 24)
    pill.Position = UDim2.new(1, -66, 0.5, -12)
    pill.BackgroundColor3 = Color3.fromRGB(50,48,66)
    pill.BorderSizePixel = 0
    pill.Parent = btn
    corner(pill, 12)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(18, 18)
    knob.Position = UDim2.fromOffset(3, 3)
    knob.BackgroundColor3 = Color3.fromRGB(170,165,190)
    knob.BorderSizePixel = 0
    knob.Parent = pill
    corner(knob, 9)

    local on = false
    local function apply(animate)
        local targetKnobPos = on and UDim2.fromOffset(33, 3) or UDim2.fromOffset(3, 3)
        local targetPillCol = on and PALETTE.accent or Color3.fromRGB(50,48,66)
        local targetKnobCol = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(170,165,190)
        local targetBtnCol  = on and Color3.fromRGB(26, 42, 36) or PALETTE.toggleOff
        local targetLblCol  = on and PALETTE.toggleOnTx or PALETTE.toggleOffTx
        if animate then
            TweenService:Create(knob, TweenInfo.new(0.15), {Position = targetKnobPos}):Play()
            TweenService:Create(pill, TweenInfo.new(0.15), {BackgroundColor3 = targetPillCol}):Play()
            TweenService:Create(knob, TweenInfo.new(0.15), {BackgroundColor3 = targetKnobCol}):Play()
            TweenService:Create(btn,  TweenInfo.new(0.15), {BackgroundColor3 = targetBtnCol}):Play()
        else
            knob.Position = targetKnobPos
            pill.BackgroundColor3 = targetPillCol
            knob.BackgroundColor3 = targetKnobCol
            btn.BackgroundColor3 = targetBtnCol
        end
        lbl.TextColor3 = targetLblCol
    end

    local function setState(v, fromExternal)
        on = v; apply(not fromExternal)
        if not fromExternal then onToggle(on) end
    end

    btn.MouseButton1Click:Connect(function() setState(not on) end)

    return posY + 44, setState
end

local function makeButton(parent, posY, label, col, onClick)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,38); btn.Position = UDim2.fromOffset(0, posY)
    btn.BackgroundColor3 = col or PALETTE.accentDim; btn.BorderSizePixel = 0
    btn.Text = label; btn.TextColor3 = Color3.fromRGB(235,228,255)
    btn.TextSize = 13; btn.Font = Enum.Font.GothamBold; btn.Parent = parent
    corner(btn, 9)
    btn.MouseButton1Click:Connect(onClick)
    return posY + 44
end

local function miniLabel(parent, posY, text, color)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1,0,0,16); l.Position = UDim2.fromOffset(0, posY)
    l.BackgroundTransparency = 1; l.Text = text
    l.TextColor3 = color or PALETTE.textDim; l.TextSize = 11
    l.Font = Enum.Font.GothamBold; l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return posY + 18
end

-- ════════════════════════════════════════════════════════════
--  PÁGINA: INVASION  (toggles + criar + auto card, tudo junto)
-- ════════════════════════════════════════════════════════════
local cardModoButtons
local cardSecUpdate
local invasionSetters = {}

do
    local p = pageFrames["INVASION"]
    local y = 4

    y = makeButton(p, y, "🚀  Criar Invasão", PALETTE.accentDim, criarInvasaoManual)
    y = y + 6

    do
        local _, set = makeToggle(p, y, "Auto Start", function(v) AUTO_START = v end, "▶")
        invasionSetters.AUTO_START = set
        y = y + 44
    end
    do
        local _, set = makeToggle(p, y, "Auto Accept Replay", function(v) AUTO_ACCEPT = v end, "✔")
        invasionSetters.AUTO_ACCEPT = set
        y = y + 44
    end
    do
        local _, set = makeToggle(p, y, "Auto Replay", function(v) AUTO_REPLAY = v end, "↻")
        invasionSetters.AUTO_REPLAY = set
        y = y + 44
    end
    do
        local _, set = makeToggle(p, y, "Auto Join Invasion", function(v) AUTO_JOIN = v; triedLobbies = {} end, "➜")
        invasionSetters.AUTO_JOIN = set
        y = y + 44
    end
    do
        local _, set = makeToggle(p, y, "Auto TP", function(v) AUTO_TP = v end, "⇪")
        invasionSetters.AUTO_TP = set
        y = y + 44
    end

    y = y + 4
    do
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.fromOffset(180,30); lbl.Position = UDim2.fromOffset(0,y)
        lbl.BackgroundTransparency=1; lbl.Text="Min jogadores p/ Auto Start:  "..MIN_PLAYERS
        lbl.TextColor3=PALETTE.textMain; lbl.TextSize=12
        lbl.Font=Enum.Font.Gotham; lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=p

        local function updLbl() lbl.Text = "Min jogadores p/ Auto Start:  "..MIN_PLAYERS end

        local function sideBtn(px, lbText, fn)
            local b = Instance.new("TextButton")
            b.Size=UDim2.fromOffset(30,28); b.Position=UDim2.new(1, px, 0, y+1)
            b.BackgroundColor3=PALETTE.accentDim; b.BorderSizePixel=0
            b.Text=lbText; b.TextColor3=Color3.fromRGB(225,210,255)
            b.TextSize=18; b.Font=Enum.Font.GothamBold; b.Parent=p
            corner(b,7); b.MouseButton1Click:Connect(fn)
        end
        sideBtn(-68,"−",function() if MIN_PLAYERS>1 then MIN_PLAYERS-=1; updLbl() end end)
        sideBtn(-32,"+",function() if MIN_PLAYERS<4 then MIN_PLAYERS+=1; updLbl() end end)
        y = y + 38
    end

    y = y + 6
    y = sectionHeader(p, y, "🃏  AUTO CARD")

    do
        local _, set = makeToggle(p, y, "Auto Card", function(v) AUTO_CARD = v end, "🂠")
        invasionSetters.AUTO_CARD = set
        y = y + 44
    end

    y = y + 2
    y = miniLabel(p, y, "Primário:")
    do
        local btnD = Instance.new("TextButton")
        btnD.Size=UDim2.new(0.5,-4,0,32); btnD.Position=UDim2.fromOffset(0,y)
        btnD.BackgroundColor3=Color3.fromRGB(95,30,35); btnD.BorderSizePixel=0
        btnD.Text="🗡 Dano ✓"; btnD.TextColor3=Color3.fromRGB(255,185,185)
        btnD.TextSize=12; btnD.Font=Enum.Font.GothamBold; btnD.Parent=p
        corner(btnD,7)

        local btnDr = Instance.new("TextButton")
        btnDr.Size=UDim2.new(0.5,-4,0,32); btnDr.Position=UDim2.new(0.5,4,0,y)
        btnDr.BackgroundColor3=PALETTE.toggleOff; btnDr.BorderSizePixel=0
        btnDr.Text="💰 Drop"; btnDr.TextColor3=PALETTE.toggleOffTx
        btnDr.TextSize=12; btnDr.Font=Enum.Font.GothamBold; btnDr.Parent=p
        corner(btnDr,7)

        local function updModo()
            if CARD_MODO=="dano" then
                btnD.BackgroundColor3=Color3.fromRGB(95,30,35); btnD.TextColor3=Color3.fromRGB(255,185,185); btnD.Text="🗡 Dano ✓"
                btnDr.BackgroundColor3=PALETTE.toggleOff; btnDr.TextColor3=PALETTE.toggleOffTx; btnDr.Text="💰 Drop"
            else
                btnDr.BackgroundColor3=Color3.fromRGB(28,85,55); btnDr.TextColor3=Color3.fromRGB(170,255,195); btnDr.Text="💰 Drop ✓"
                btnD.BackgroundColor3=PALETTE.toggleOff; btnD.TextColor3=PALETTE.toggleOffTx; btnD.Text="🗡 Dano"
            end
        end
        btnD.MouseButton1Click:Connect(function() CARD_MODO="dano"; updModo() end)
        btnDr.MouseButton1Click:Connect(function() CARD_MODO="drop"; updModo() end)
        cardModoButtons = updModo
        y = y + 38
    end

    y = y + 4
    y = miniLabel(p, y, "Secundário (prioridade se aparecer):")
    do
        local OPCOES = {
            { id=nil,          label="Nenhuma"               },
            { id="reinf",      label="Warrior Reinforcement" },
            { id="barricade",  label="Barricade Repair"      },
        }

        local btnSec = Instance.new("TextButton")
        btnSec.Size=UDim2.new(1,0,0,32); btnSec.Position=UDim2.fromOffset(0,y)
        btnSec.BackgroundColor3=PALETTE.toggleOff; btnSec.BorderSizePixel=0
        btnSec.Text="Selecionar  ▾"; btnSec.TextColor3=PALETTE.toggleOffTx
        btnSec.TextSize=12; btnSec.Font=Enum.Font.GothamBold; btnSec.Parent=p
        corner(btnSec,7)
        y = y + 36

        local ITEM_H = 32
        local popup = Instance.new("Frame")
        popup.Size=UDim2.new(1,0,0, #OPCOES*ITEM_H+6)
        popup.Position=UDim2.fromOffset(0, y)
        popup.BackgroundColor3=Color3.fromRGB(20,19,30); popup.BorderSizePixel=0
        popup.ZIndex=20; popup.Visible=false; popup.Parent=p
        corner(popup,9); stroke(popup,PALETTE.accentDim,1)

        local function updSec()
            if CARD_SEC_ID==nil then
                btnSec.Text="Selecionar  ▾"
                btnSec.BackgroundColor3=PALETTE.toggleOff
                btnSec.TextColor3=PALETTE.toggleOffTx
                CARD_SEC_REINF=false; CARD_SEC_BARRICADE=false
            else
                local nome = CARD_SEC_ID=="reinf" and "Warrior Reinforcement" or "Barricade Repair"
                btnSec.Text=nome.."  ✓"
                btnSec.BackgroundColor3=Color3.fromRGB(30,75,110)
                btnSec.TextColor3=Color3.fromRGB(165,220,255)
                CARD_SEC_REINF=(CARD_SEC_ID=="reinf"); CARD_SEC_BARRICADE=(CARD_SEC_ID=="barricade")
            end
        end

        for i, op in ipairs(OPCOES) do
            local item = Instance.new("TextButton")
            item.Size=UDim2.new(1,0,0,ITEM_H); item.Position=UDim2.fromOffset(0,(i-1)*ITEM_H+3)
            item.BackgroundTransparency=1; item.BorderSizePixel=0
            item.Text="  "..op.label; item.TextColor3=Color3.fromRGB(205,198,230)
            item.TextSize=12; item.Font=Enum.Font.GothamBold
            item.TextXAlignment=Enum.TextXAlignment.Left
            item.ZIndex=21; item.Parent=popup
            item.MouseEnter:Connect(function() item.BackgroundTransparency=0; item.BackgroundColor3=Color3.fromRGB(42,33,78) end)
            item.MouseLeave:Connect(function() item.BackgroundTransparency=1 end)
            item.MouseButton1Click:Connect(function()
                CARD_SEC_ID=op.id; updSec(); popup.Visible=false
            end)
        end

        btnSec.MouseButton1Click:Connect(function() popup.Visible=not popup.Visible end)
        cardSecUpdate = updSec
        y = y + 8
    end

    y = y + 4
end

-- ════════════════════════════════════════════════════════════
--  PÁGINA: TREASURE
-- ════════════════════════════════════════════════════════════
local treasureSetter
do
    local p = pageFrames["TREASURE"]
    local y = 4

    y = sectionHeader(p, y, "💰  TREASURE HUNT")
    local _, set = makeToggle(p, y, "Auto Treasure", function(v)
        AUTO_TREASURE = v
        if v then iniciarLoopTreasure() end
    end, "⛏")
    treasureSetter = set
    y = y + 44

    y = y + 4
    y = miniLabel(p, y, "Cava automaticamente quando você tem")
    y = miniLabel(p, y, "pás (Shovel) no inventário.")
    y = y + 6
    y = miniLabel(p, y, "Se não funcionar, ative DEBUG_PRINT no", Color3.fromRGB(220,180,120))
    y = miniLabel(p, y, "topo do script e veja o console (F9) pra", Color3.fromRGB(220,180,120))
    y = miniLabel(p, y, "ver qual campo está vindo nil.", Color3.fromRGB(220,180,120))
end

-- ════════════════════════════════════════════════════════════
--  PÁGINA: CONFIG  (Black Screen, Keybind, Salvar/Carregar)
-- ════════════════════════════════════════════════════════════
local keybindDisplayLabel
local setBlackScreenToggleVisual

local function keybindParaTexto(keys)
    if keys == nil or #keys == 0 then return "Nenhuma" end
    return table.concat(keys, " + ")
end

do
    local p = pageFrames["CONFIG"]
    local y = 4

    -- Black Screen
    y = sectionHeader(p, y, "🌑  BLACK SCREEN")
    do
        local btnBS = Instance.new("TextButton")
        btnBS.Size = UDim2.new(1,0,0,38); btnBS.Position = UDim2.fromOffset(0,y)
        btnBS.BackgroundColor3 = PALETTE.toggleOff; btnBS.BorderSizePixel = 0
        btnBS.Text = "🌑  Ativar Black Screen   OFF"
        btnBS.TextColor3 = PALETTE.toggleOffTx
        btnBS.TextSize = 13; btnBS.Font = Enum.Font.GothamBold; btnBS.Parent = p
        corner(btnBS, 9)
        y = y + 44

        local function updateVisual(v)
            if v then
                btnBS.Text = "🌑  Black Screen   ON ✓"
                btnBS.BackgroundColor3 = Color3.fromRGB(26, 42, 36)
                btnBS.TextColor3 = PALETTE.toggleOnTx
            else
                btnBS.Text = "🌑  Ativar Black Screen   OFF"
                btnBS.BackgroundColor3 = PALETTE.toggleOff
                btnBS.TextColor3 = PALETTE.toggleOffTx
            end
        end
        BLACK_SCREEN_TOGGLE_UPDATE = updateVisual
        setBlackScreenToggleVisual = updateVisual

        btnBS.MouseButton1Click:Connect(function()
            setBlackScreen(not BLACK_SCREEN)
        end)
    end

    y = y + 2
    y = miniLabel(p, y, "Tela preta com chuva, texto 'lz3s AFK' e")
    y = miniLabel(p, y, "botão X pra fechar direto na tela.")

    y = y + 8
    y = sectionHeader(p, y, "🟢  ANTI-AFK")
    y = miniLabel(p, y, "Sempre ativo em segundo plano — não")
    y = miniLabel(p, y, "precisa de botão, já está rodando.")

    y = y + 8
    y = sectionHeader(p, y, "⌨  KEYBIND (abrir/fechar GUI)")

    keybindDisplayLabel = Instance.new("TextLabel")
    keybindDisplayLabel.Size = UDim2.new(1,0,0,24)
    keybindDisplayLabel.Position = UDim2.fromOffset(0, y)
    keybindDisplayLabel.BackgroundTransparency = 1
    keybindDisplayLabel.Text = "Atual: " .. keybindParaTexto(KEYBIND_KEYS)
    keybindDisplayLabel.TextColor3 = PALETTE.textMain
    keybindDisplayLabel.TextSize = 13
    keybindDisplayLabel.Font = Enum.Font.GothamBold
    keybindDisplayLabel.TextXAlignment = Enum.TextXAlignment.Left
    keybindDisplayLabel.Parent = p
    y = y + 28

    local btnRecord = Instance.new("TextButton")
    btnRecord.Size = UDim2.new(1,0,0,38); btnRecord.Position = UDim2.fromOffset(0,y)
    btnRecord.BackgroundColor3 = PALETTE.accentDim; btnRecord.BorderSizePixel = 0
    btnRecord.Text = "🎙  Gravar nova keybind"
    btnRecord.TextColor3 = Color3.fromRGB(235,228,255)
    btnRecord.TextSize = 13; btnRecord.Font = Enum.Font.GothamBold; btnRecord.Parent = p
    corner(btnRecord, 9)
    y = y + 44

    y = miniLabel(p, y, "Clique, aperte as teclas em sequência e")
    y = miniLabel(p, y, "clique em 'Parar' pra confirmar.")
    y = y + 6

    local recordedKeys = {}
    local recordConn = nil

    local function pararGravacao()
        KEYBIND_RECORDING = false
        if recordConn then recordConn:Disconnect(); recordConn = nil end
        btnRecord.Text = "🎙  Gravar nova keybind"
        btnRecord.BackgroundColor3 = PALETTE.accentDim
        if #recordedKeys > 0 then
            KEYBIND_KEYS = recordedKeys
            keybindDisplayLabel.Text = "Atual: " .. keybindParaTexto(KEYBIND_KEYS)
        end
    end

    local function iniciarGravacao()
        KEYBIND_RECORDING = true
        recordedKeys = {}
        btnRecord.Text = "⏹  Parar (gravando...)"
        btnRecord.BackgroundColor3 = PALETTE.danger
        keybindDisplayLabel.Text = "Atual: (gravando...)"

        recordConn = UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.UserInputType == Enum.UserInputType.Keyboard then
                local keyName = input.KeyCode.Name
                local jaTem = false
                for _, k in ipairs(recordedKeys) do if k == keyName then jaTem = true end end
                if not jaTem then
                    table.insert(recordedKeys, keyName)
                    keybindDisplayLabel.Text = "Atual: " .. keybindParaTexto(recordedKeys) .. " ..."
                end
            end
        end)
    end

    btnRecord.MouseButton1Click:Connect(function()
        if KEYBIND_RECORDING then pararGravacao() else iniciarGravacao() end
    end)

    y = y + 6
    y = sectionHeader(p, y, "💾  CONFIGURAÇÃO")

    local statusLbl = Instance.new("TextLabel")
    statusLbl.Size = UDim2.new(1,0,0,18)
    statusLbl.Position = UDim2.fromOffset(0,y)
    statusLbl.BackgroundTransparency = 1
    statusLbl.Text = ""
    statusLbl.TextColor3 = Color3.fromRGB(150,225,160)
    statusLbl.TextSize = 11
    statusLbl.Font = Enum.Font.Gotham
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left
    statusLbl.Parent = p
    y = y + 22

    local function mostrarStatus(msg, ok)
        statusLbl.Text = msg
        statusLbl.TextColor3 = ok and Color3.fromRGB(150,225,160) or Color3.fromRGB(235,130,130)
        task.delay(3, function() if statusLbl.Text == msg then statusLbl.Text = "" end end)
    end

    y = makeButton(p, y, "💾  Salvar configuração atual", Color3.fromRGB(28,95,80), function()
        local ok = salvarConfig()
        mostrarStatus(ok and "Configuração salva com sucesso!" or "Falha ao salvar (executor sem writefile).", ok)
    end)

    y = makeButton(p, y, "📂  Carregar configuração salva", PALETTE.accentDim, function()
        local dados = carregarConfigDoArquivo()
        if dados == nil then
            mostrarStatus("Nenhuma configuração encontrada.", false)
            return
        end
        _G.__lz3s_aplicarConfig(dados)
        mostrarStatus("Configuração carregada!", true)
    end)

    y = y + 2
    y = miniLabel(p, y, "'Salvar' grava todos os toggles + keybind.")
    y = miniLabel(p, y, "Ao executar o script de novo, a config")
    y = miniLabel(p, y, "salva é carregada automaticamente.")
end

-- ============================================================
--  APLICAR CONFIG (autoload + botão Carregar)
-- ============================================================
_G.__lz3s_aplicarConfig = function(dados)
    if dados == nil then return end

    if dados.MIN_PLAYERS then MIN_PLAYERS = dados.MIN_PLAYERS end
    if dados.CARD_MODO then CARD_MODO = dados.CARD_MODO; if cardModoButtons then cardModoButtons() end end
    CARD_SEC_ID = dados.CARD_SEC_ID
    if cardSecUpdate then cardSecUpdate() end

    if dados.KEYBIND_KEYS then
        KEYBIND_KEYS = dados.KEYBIND_KEYS
        if keybindDisplayLabel then
            keybindDisplayLabel.Text = "Atual: " .. keybindParaTexto(KEYBIND_KEYS)
        end
    end

    if invasionSetters.AUTO_START  then invasionSetters.AUTO_START(dados.AUTO_START == true, true) end
    if invasionSetters.AUTO_ACCEPT then invasionSetters.AUTO_ACCEPT(dados.AUTO_ACCEPT == true, true) end
    if invasionSetters.AUTO_REPLAY then invasionSetters.AUTO_REPLAY(dados.AUTO_REPLAY == true, true) end
    if invasionSetters.AUTO_JOIN   then invasionSetters.AUTO_JOIN(dados.AUTO_JOIN == true, true) end
    if invasionSetters.AUTO_TP     then invasionSetters.AUTO_TP(dados.AUTO_TP == true, true) end
    if invasionSetters.AUTO_CARD   then invasionSetters.AUTO_CARD(dados.AUTO_CARD == true, true) end
    if treasureSetter then
        treasureSetter(dados.AUTO_TREASURE == true, true)
    end

    AUTO_START    = dados.AUTO_START == true
    AUTO_ACCEPT   = dados.AUTO_ACCEPT == true
    AUTO_REPLAY   = dados.AUTO_REPLAY == true
    AUTO_JOIN     = dados.AUTO_JOIN == true
    AUTO_TP       = dados.AUTO_TP == true
    AUTO_CARD     = dados.AUTO_CARD == true
    AUTO_TREASURE = dados.AUTO_TREASURE == true
    if AUTO_TREASURE then iniciarLoopTreasure() end

    if dados.BLACK_SCREEN then
        setBlackScreen(true)
    end
end

-- ============================================================
--  KEYBIND: detectar sequência pra abrir/fechar a GUI
-- ============================================================
do
    local pressionadasAgora = {}

    local function sequenciaCompleta()
        if #KEYBIND_KEYS == 0 then return false end
        for _, k in ipairs(KEYBIND_KEYS) do
            if not pressionadasAgora[k] then return false end
        end
        return true
    end

    UserInputService.InputBegan:Connect(function(input, gpe)
        if KEYBIND_RECORDING then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        pressionadasAgora[input.KeyCode.Name] = true
        if sequenciaCompleta() then
            ScreenGui.Enabled = not ScreenGui.Enabled
        end
    end)

    UserInputService.InputEnded:Connect(function(input, gpe)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        pressionadasAgora[input.KeyCode.Name] = nil
    end)
end

-- ── Minimizar (encolhe pra só a barra de título) ───────────────
do
    local minimized = false
    local expandedSize = Frame.Size
    MinimizeBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            expandedSize = Frame.Size
            TweenService:Create(Frame, TweenInfo.new(0.2), {Size = UDim2.fromOffset(WINDOW_W, 54)}):Play()
            MinimizeBtn.Text = "▢"
        else
            TweenService:Create(Frame, TweenInfo.new(0.2), {Size = expandedSize}):Play()
            MinimizeBtn.Text = "—"
        end
    end)
end

selectTab("INVASION")

-- ============================================================
--  AUTOLOAD: carrega config salva ao executar o script
-- ============================================================
task.defer(function()
    local dados = carregarConfigDoArquivo()
    if dados ~= nil then
        _G.__lz3s_aplicarConfig(dados)
        logf("Config carregada automaticamente.")
    end
end)

print("[lz3s Invasion] Carregado! Arraste pela barra roxa. Abas: Invasion / Treasure / Config.")
