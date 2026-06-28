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
local DEBUG_PRINT   = true
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
local CARD_SEC_ID        = nil

local KEYBIND_KEYS      = {"RightShift", "K"}
local KEYBIND_RECORDING = false

-- flags de notificação (cada tipo pode ser ligado/desligado)
local NOTIF_ENABLED        = true   -- master switch
local NOTIF_INVASION_DISP  = true   -- invasion disponível
local NOTIF_INVASION_START = true   -- invasion começou
local NOTIF_INVASION_END   = true   -- invasion terminou
local NOTIF_ENTROU         = true   -- entrou em uma invasion
local NOTIF_TP             = true   -- tp na torre deu certo
local NOTIF_TREASURE       = true   -- cavada do tesouro

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
--  lobby.players é um ARRAY (não dict), então usa # para contar
--  O remote real fica em remo.src.container["lobbies.start"]
--  e é um RemoteEvent — FireServer() direto
-- ============================================================
local startRemote
do
    local p = ReplicatedStorage:FindFirstChild("rbxts_include")
    p = p and p:FindFirstChild("node_modules")
    p = p and p:FindFirstChild("@rbxts")
    p = p and p:FindFirstChild("remo")
    p = p and p:FindFirstChild("src")
    p = p and p:FindFirstChild("container")
    startRemote = p and p:FindFirstChild("lobbies.start")
    if startRemote then
        logf("Auto Start: remote 'lobbies.start' encontrado (" .. startRemote.ClassName .. ")")
    else
        warn("[lz3s] Auto Start: remote 'lobbies.start' NAO encontrado!")
    end
end

local lastStarted = 0
RunService.Heartbeat:Connect(function()
    if not AUTO_START then return end
    if tick() - lastStarted < 3 then return end
    if getLobbyByPlayer == nil then return end

    local ok, lobby = pcall(getLobbyByPlayer, USER_KEY)
    if not ok or lobby == nil or lobby.owner ~= USER_KEY then return end

    -- players é array: usa # direto
    local count = #(lobby.players or {})

    logf("Auto Start: lobby encontrado, jogadores: " .. count .. " / min: " .. MIN_PLAYERS)

    if count >= MIN_PLAYERS then
        lastStarted = tick()

        -- Tenta o remote direto primeiro
        if startRemote ~= nil then
            local okFire, errFire = pcall(function()
                if startRemote:IsA("RemoteEvent") then
                    startRemote:FireServer()
                elseif startRemote:IsA("RemoteFunction") then
                    startRemote:InvokeServer()
                end
            end)
            if okFire then
                logf("Auto Start: FireServer() enviado via remote direto!")
            else
                logf("Auto Start: erro no remote direto: " .. tostring(errFire))
                -- fallback para o wrapper
                pcall(function() remotes.lobbies.start:fire() end)
            end
        else
            -- fallback
            pcall(function() remotes.lobbies.start:fire() end)
        end
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
    for i, item in ipairs(cards) do
        ids[i] = typeof(item)=="table" and tostring(item.id) or tostring(item)
    end
    return table.concat(ids, "|")
end

local function escolherCarta(cards)
    local ids = {}
    for _, item in ipairs(cards) do
        table.insert(ids, typeof(item)=="table" and item.id or tostring(item))
    end
    if CARD_SEC_REINF then
        for _, id in ipairs(ids) do
            if id == "Invasion Warrior Reinforcement" then return id end
        end
    end
    if CARD_SEC_BARRICADE then
        for _, id in ipairs(ids) do
            if id == "Invasion Barricade Repair" then return id end
        end
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
--
--  Como funciona:
--  • Varre workspace.World.Map a cada 1s
--  • Procura pasta "invasion-<uuid>" (uuid muda a cada invasion)
--  • Quando acha uma nova, busca "Main Base Turret" dentro dela
--  • Pega a posição do PrimaryPart do turret (ou qualquer BasePart)
--  • Teleporta +10 studs acima e registra o nome pra não repetir
--  • Cada invasion tem UUID único → nova invasion = novo TP
-- ============================================================
local tpFeitoIds = {}

local function buscarPosTurret(invasionFolder)
    -- FindFirstChild primeiro (sem yield se já carregou)
    local turret = invasionFolder:FindFirstChild("Main Base Turret")

    -- Se ainda não carregou, aguarda até 10s
    if turret == nil then
        local ok, result = pcall(function()
            return invasionFolder:WaitForChild("Main Base Turret", 10)
        end)
        if ok and result then turret = result end
    end

    if turret == nil then
        return nil, "Main Base Turret nao encontrado em " .. invasionFolder.Name
    end

    -- Extrai posição
    if turret:IsA("Model") then
        -- Tenta PrimaryPart primeiro
        local pp = turret.PrimaryPart
        if pp then return pp.Position, nil end
        -- Qualquer BasePart descendente
        local bp = turret:FindFirstChildWhichIsA("BasePart", true)
        if bp then return bp.Position, nil end
        -- Último recurso: pivot do model
        local ok2, pivot = pcall(function() return turret:GetPivot().Position end)
        if ok2 then return pivot, nil end
        return nil, "Main Base Turret sem BasePart"
    elseif turret:IsA("BasePart") then
        return turret.Position, nil
    else
        local bp = turret:FindFirstChildWhichIsA("BasePart", true)
        if bp then return bp.Position, nil end
        return nil, "Main Base Turret tipo desconhecido: " .. turret.ClassName
    end
end

task.spawn(function()
    while true do
        task.wait(1)
        if not AUTO_TP then continue end

        local char = Players.LocalPlayer.Character
        if char == nil then continue end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp == nil then continue end

        -- Acessa o Map com proteção total
        local mapFolder
        pcall(function()
            local world = workspace:FindFirstChild("World")
            if world then mapFolder = world:FindFirstChild("Map") end
        end)
        if mapFolder == nil then continue end

        for _, filho in ipairs(mapFolder:GetChildren()) do
            local nome = filho.Name

            -- Filtro: só pastas invasion-<uuid>
            if not nome:match("^invasion%-.") then continue end

            -- Já processou essa invasion
            if tpFeitoIds[nome] then continue end

            -- Processa em task.spawn para não travar o loop caso WaitForChild demore
            task.spawn(function()
                logf("Auto TP: encontrei " .. nome .. ", buscando Main Base Turret...")

                local pos, err = buscarPosTurret(filho)

                if pos == nil then
                    logf("Auto TP ERRO: " .. tostring(err))
                    return
                end

                -- Verifica novamente antes de teleportar
                if not AUTO_TP then return end
                local c2 = Players.LocalPlayer.Character
                if c2 == nil then return end
                local hrp2 = c2:FindFirstChild("HumanoidRootPart")
                if hrp2 == nil then return end

                -- Registra ANTES de teleportar para não disparar duas vezes
                tpFeitoIds[nome] = true

                hrp2.CFrame = CFrame.new(pos + Vector3.new(0, 10, 0))
                logf("Auto TP: teleportado para " .. nome .. " pos=" .. tostring(pos))
                if NOTIF_TP then
                    criarNotif("tp", "Auto TP", "Teleportado para a torre!", 4)
                end
            end)

            -- Só uma invasion por ciclo de 1s
            break
        end
    end
end)

-- ============================================================
--  AUTO TREASURE
-- ============================================================
local DELAY_ENTRE_CAVADAS   = 0.6
local CHECK_INTERVAL_SEM_PA = 2
local treasureRodando       = false
local avisouSemPas          = false  -- evita logar "sem pas" repetidamente a cada 2s

local function getQuantidadeDePas()
    local d = getPlayerData(USER_KEY)
    if d == nil then return 0 end
    local s = d.items and d.items.Shovel
    if s == nil then return 0 end
    return s.amount or 0
end

local function getTilesJaCavadas()
    local d = getPlayerData(USER_KEY)
    if d == nil then return {} end
    local dug = d.treasureHunt and d.treasureHunt.dug
    if dug == nil then return {} end
    local t = {}
    for _, item in pairs(dug) do if item and item.index then t[item.index] = true end end
    return t
end

local function escolherTileAleatoria()
    local cavadas = getTilesJaCavadas()
    local disp = {}
    for i = 1, TREASURE_HUNT_TILE_COUNT do if not cavadas[i] then table.insert(disp, i) end end
    if #disp == 0 then return nil end
    return disp[math.random(1, #disp)]
end

local function cavarUmaVez()
    local tile = escolherTileAleatoria()
    if tile == nil then return end
    local ok, p = pcall(function() return remotes.treasureHunt.dig:request(tile) end)
    if not ok then logf("Auto Treasure erro: " .. tostring(p)); return end
    p:andThen(function(r)
        if r and r.reason then
            logf("Auto Treasure: " .. tostring(r.reason))
        else
            if NOTIF_TREASURE then
                local pasRestantes = getQuantidadeDePas()
                local recompensa = ""
                if r and r.reward then
                    recompensa = " - " .. tostring(r.reward.id or r.reward)
                end
                criarNotif("treasure", "Tesouro Cavado",
                    "Pas restantes: " .. pasRestantes .. recompensa, 4)
            end
        end
    end):catch(function(err) logf("Auto Treasure promise: " .. tostring(err)) end)
end

local function iniciarLoopTreasure()
    if treasureRodando then return end
    treasureRodando = true
    logf("Auto Treasure: loop iniciado")
    task.spawn(function()
        while AUTO_TREASURE do
            local pas = getQuantidadeDePas()
            if pas > 0 then
                avisouSemPas = false
                cavarUmaVez()
                task.wait(DELAY_ENTRE_CAVADAS)
            else
                if not avisouSemPas then
                    avisouSemPas = true
                    logf("Auto Treasure: sem pas, aguardando...")
                end
                task.wait(CHECK_INTERVAL_SEM_PA)
            end
        end
        treasureRodando = false
        logf("Auto Treasure: loop parado")
    end)
end

-- ============================================================
--  PERSISTÊNCIA
-- ============================================================
local function fileFuncsDisponiveis()
    return type(writefile)=="function" and type(readfile)=="function" and type(isfile)=="function"
end

local function montarConfigAtual()
    return {
        AUTO_START=AUTO_START, AUTO_CARD=AUTO_CARD, AUTO_ACCEPT=AUTO_ACCEPT,
        AUTO_REPLAY=AUTO_REPLAY, AUTO_JOIN=AUTO_JOIN, AUTO_TREASURE=AUTO_TREASURE,
        AUTO_TP=AUTO_TP, BLACK_SCREEN=BLACK_SCREEN,
        CARD_MODO=CARD_MODO, CARD_SEC_ID=CARD_SEC_ID,
        MIN_PLAYERS=MIN_PLAYERS, KEYBIND_KEYS=KEYBIND_KEYS,
        NOTIF_ENABLED=NOTIF_ENABLED,
        NOTIF_INVASION_DISP=NOTIF_INVASION_DISP, NOTIF_INVASION_START=NOTIF_INVASION_START,
        NOTIF_INVASION_END=NOTIF_INVASION_END, NOTIF_ENTROU=NOTIF_ENTROU,
        NOTIF_TP=NOTIF_TP, NOTIF_TREASURE=NOTIF_TREASURE,
    }
end

local function salvarConfig()
    if not fileFuncsDisponiveis() then
        warn("[lz3s] writefile não disponível neste executor.")
        return false
    end
    local ok, encoded = pcall(function() return HttpService:JSONEncode(montarConfigAtual()) end)
    if not ok then return false end
    local okW = pcall(function() writefile(CONFIG_FILE, encoded) end)
    return okW
end

local function carregarConfigDoArquivo()
    if not fileFuncsDisponiveis() then return nil end
    local okIs, existe = pcall(function() return isfile(CONFIG_FILE) end)
    if not okIs or not existe then return nil end
    local ok, raw = pcall(function() return readfile(CONFIG_FILE) end)
    if not ok or raw == nil then return nil end
    local okD, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
    if not okD then return nil end
    return decoded
end

-- ============================================================
--  SISTEMA DE NOTIFICAÇÕES
--  Canto inferior direito, empilha de baixo pra cima, slide-in
--  Cada notif tem barra colorida lateral + título + mensagem + progresso
--  Sem emojis/símbolos: usa só formas geométricas simples (ponto/barra)
-- ============================================================
local notifGui
local NOTIF_W     = 280
local NOTIF_H     = 64
local NOTIF_GAP   = 8
local NOTIF_PAD_R = 14
local NOTIF_PAD_B = 14

do
    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
    local ex = pg:FindFirstChild("lz3sNotif")
    if ex then ex:Destroy() end

    notifGui = Instance.new("ScreenGui")
    notifGui.Name           = "lz3sNotif"
    notifGui.IgnoreGuiInset = true
    notifGui.DisplayOrder   = 998
    notifGui.ResetOnSpawn   = false
    notifGui.Parent         = pg
end

-- tipos: cor da barra lateral + cor de fundo do indicador (sem ícones/emoji)
local NOTIF_TYPES = {
    invasion  = { bar=Color3.fromRGB(120,80,230),  ibg=Color3.fromRGB(40,25,80)  },
    start     = { bar=Color3.fromRGB(80,200,120),  ibg=Color3.fromRGB(20,65,35)  },
    finish    = { bar=Color3.fromRGB(200,160,50),  ibg=Color3.fromRGB(65,48,12)  },
    entrou    = { bar=Color3.fromRGB(60,160,230),  ibg=Color3.fromRGB(15,50,75)  },
    tp        = { bar=Color3.fromRGB(160,90,240),  ibg=Color3.fromRGB(45,20,80)  },
    treasure  = { bar=Color3.fromRGB(220,170,40),  ibg=Color3.fromRGB(65,46,8)   },
    info      = { bar=Color3.fromRGB(100,100,130), ibg=Color3.fromRGB(30,30,45)  },
}

local function criarNotif(tipo, titulo, msg, duracao)
    if not NOTIF_ENABLED then return end
    duracao = duracao or 4

    -- empilha as existentes 1 posição acima
    local slots = notifGui:GetChildren()
    for _, slot in ipairs(slots) do
        if slot:IsA("Frame") then
            local targetY = slot.Position.Y.Offset - (NOTIF_H + NOTIF_GAP)
            TweenService:Create(slot, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {
                Position = UDim2.new(1, slot.Position.X.Offset, 1, targetY)
            }):Play()
        end
    end

    local def = NOTIF_TYPES[tipo] or NOTIF_TYPES.info

    -- Frame principal (começa fora da tela à direita)
    local frame = Instance.new("Frame")
    frame.Size             = UDim2.fromOffset(NOTIF_W, NOTIF_H)
    frame.Position         = UDim2.new(1, NOTIF_W + 20, 1, -(NOTIF_PAD_B + NOTIF_H))
    frame.BackgroundColor3 = Color3.fromRGB(18, 17, 26)
    frame.BorderSizePixel  = 0
    frame.ClipsDescendants = false
    frame.Parent           = notifGui
    local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0,10); fc.Parent = frame
    local fs = Instance.new("UIStroke"); fs.Color = Color3.fromRGB(55,45,90); fs.Thickness = 1; fs.Transparency = 0.2; fs.Parent = frame

    -- Barra lateral colorida (substitui ícone)
    local bar = Instance.new("Frame")
    bar.Size             = UDim2.new(0, 4, 1, -16)
    bar.Position         = UDim2.fromOffset(0, 8)
    bar.BackgroundColor3 = def.bar
    bar.BorderSizePixel  = 0
    bar.Parent           = frame
    local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,4); bc.Parent = bar

    -- Indicador simples (quadrado com canto arredondado, cor sólida)
    local iconBg = Instance.new("Frame")
    iconBg.Size             = UDim2.fromOffset(8, 8)
    iconBg.Position         = UDim2.fromOffset(20, 14)
    iconBg.BackgroundColor3 = def.bar
    iconBg.BorderSizePixel  = 0
    iconBg.Parent           = frame
    local ic = Instance.new("UICorner"); ic.CornerRadius = UDim.new(1,0); ic.Parent = iconBg

    -- Título
    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size              = UDim2.new(1,-44,0,18)
    titleLbl.Position          = UDim2.fromOffset(40, 10)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text              = titulo
    titleLbl.TextColor3        = Color3.fromRGB(230,225,250)
    titleLbl.TextSize          = 13
    titleLbl.Font              = Enum.Font.GothamBold
    titleLbl.TextXAlignment    = Enum.TextXAlignment.Left
    titleLbl.TextTruncate      = Enum.TextTruncate.AtEnd
    titleLbl.Parent            = frame

    -- Mensagem
    local msgLbl = Instance.new("TextLabel")
    msgLbl.Size               = UDim2.new(1,-52,0,28)
    msgLbl.Position           = UDim2.fromOffset(40, 28)
    msgLbl.BackgroundTransparency = 1
    msgLbl.Text               = msg
    msgLbl.TextColor3         = Color3.fromRGB(160,155,185)
    msgLbl.TextSize           = 11
    msgLbl.Font               = Enum.Font.Gotham
    msgLbl.TextXAlignment     = Enum.TextXAlignment.Left
    msgLbl.TextYAlignment     = Enum.TextYAlignment.Top
    msgLbl.TextWrapped        = true
    msgLbl.Parent             = frame

    -- Barra de progresso no fundo
    local progBg = Instance.new("Frame")
    progBg.Size             = UDim2.new(1,-16,0,2)
    progBg.Position         = UDim2.new(0,8,1,-6)
    progBg.BackgroundColor3 = Color3.fromRGB(40,38,58)
    progBg.BorderSizePixel  = 0
    progBg.Parent           = frame
    local pgc = Instance.new("UICorner"); pgc.CornerRadius=UDim.new(1,0); pgc.Parent=progBg

    local prog = Instance.new("Frame")
    prog.Size             = UDim2.fromScale(1,1)
    prog.BackgroundColor3 = def.bar
    prog.BorderSizePixel  = 0
    prog.Parent           = progBg
    local prc = Instance.new("UICorner"); prc.CornerRadius=UDim.new(1,0); prc.Parent=prog

    -- Slide-in
    TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Position = UDim2.new(1, -(NOTIF_W + NOTIF_PAD_R), 1, -(NOTIF_PAD_B + NOTIF_H))
    }):Play()

    -- Barra de progresso shrink
    TweenService:Create(prog, TweenInfo.new(duracao, Enum.EasingStyle.Linear), {
        Size = UDim2.fromScale(0, 1)
    }):Play()

    -- Auto-destruir
    task.delay(duracao, function()
        TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Position = UDim2.new(1, NOTIF_W + 20, 1, -(NOTIF_PAD_B + NOTIF_H))
        }):Play()
        task.wait(0.3)
        frame:Destroy()
    end)
end

-- ─── Watchers de eventos para disparar notificações ────────────────────────

-- 1. Invasion disponível (lobby aberto de outro jogador apareceu no store)
local jaNotifoiLobby = {}
task.spawn(function()
    while true do
        task.wait(5)
        if not NOTIF_INVASION_DISP then continue end
        if lobbiesStore == nil then continue end
        local ok, all = pcall(function() return lobbiesStore() end)
        if not ok or all == nil then continue end
        for id, lobby in pairs(all) do
            if lobby.type=="invasion" and not lobby.friendsOnly and not jaNotifoiLobby[id] then
                jaNotifoiLobby[id] = true
                criarNotif("invasion", "Invasion disponivel",
                    "Lobby aberto - " .. (#(lobby.players or {})) .. "/" .. (lobby.maxPlayers or 4) .. " jogadores", 5)
            end
        end
        -- limpa ids antigos
        for id in pairs(jaNotifoiLobby) do
            if all[id] == nil then jaNotifoiLobby[id] = nil end
        end
    end
end)

-- 2. Entrou em invasion + 3. Invasion começou + 4. Invasion terminou (ganho + total de Star Remnant)
--
-- Campos reais confirmados no modulo gamemodes/invasion:
--   invasion.state  -> estado geral: comeca em "lobby" (defaultInvasion.state)
--   invasion.phase  -> estado interno (cartas/combate), comeca em "intermission"
--   invasion.players[USER_KEY].drops -> array de rewards acumulados nessa invasion
--
-- Total acumulado no jogo: confirmado via debug (F9) que fica em
--   d.items["Summer Star Remnant"].amount   (mesmo padrao do Shovel)
--
-- "Começou" = invasion.state saiu de "lobby" pra qualquer outra coisa.
-- Isso é mais confiável que usar "phase", porque phase oscila entre
-- intermission/combate varias vezes na mesma invasion (troca de onda,
-- escolha de carta) e dispararia "comecou" de novo a cada oscilacao.
--
-- "Terminou" = invasion vira nil. Como nesse momento o objeto já não
-- existe mais pra consultar os drops, guardamos um snapshot do ganho
-- de "Summer Star Remnant" a cada atualizacao, e usamos esse snapshot
-- na hora de montar a notificacao de fim.
local CURRENCY_DROP_NAME = "Summer Star Remnant"

local function somarStarRemnantGanho(invasion)
    if invasion == nil or invasion.players == nil then return 0 end
    local dados = invasion.players[USER_KEY]
    if dados == nil or dados.drops == nil then return 0 end
    local total = 0
    for _, drop in ipairs(dados.drops) do
        if drop and drop.id == CURRENCY_DROP_NAME then
            total += (drop.amount or 0)
        end
    end
    return total
end

local function getStarRemnantTotal()
    local ok, d = pcall(getPlayerData, USER_KEY)
    if not ok or d == nil or d.items == nil then return nil end
    local item = d.items[CURRENCY_DROP_NAME]
    if item == nil then return nil end
    return item.amount or 0
end

local lastInvasionId     = nil
local lastState          = nil
local startNotifiedId    = nil
local lastStarRemnantQtd = 0

subscribe(computed(function() return getInvasionByPlayer(USER_KEY) end), function(invasion)
    if invasion == nil then
        -- Saiu/terminou
        if lastInvasionId ~= nil and NOTIF_INVASION_END then
            local msg = "A invasion terminou."
            if lastStarRemnantQtd > 0 then
                msg = msg .. " Ganhou: " .. lastStarRemnantQtd
                local total = getStarRemnantTotal()
                if total ~= nil then
                    msg = msg .. " | Total: " .. total
                end
            end
            criarNotif("finish", "Invasion encerrada", msg, 7)
        end
        lastInvasionId     = nil
        lastState          = nil
        startNotifiedId    = nil
        lastStarRemnantQtd = 0
        return
    end

    -- snapshot atualizado a cada tick pra ter o total certo quando a invasion acabar
    lastStarRemnantQtd = somarStarRemnantGanho(invasion)

    -- Entrou numa nova invasion
    if invasion.id ~= lastInvasionId then
        lastInvasionId = invasion.id
        if NOTIF_ENTROU then
            criarNotif("entrou", "Entrou na invasion",
                invasion.name or "Dark Matter Invasion", 4)
        end
    end

    -- Mudanca de state: saiu de "lobby" = começou
    -- (so dispara a primeira vez nessa invasion, mesmo que o state
    -- mude varias vezes depois)
    local state = invasion.state
    if state ~= lastState then
        if lastState == "lobby" and state ~= "lobby" then
            if NOTIF_INVASION_START and startNotifiedId ~= invasion.id then
                startNotifiedId = invasion.id
                criarNotif("start", "Invasion comecou", "Boa sorte na batalha.", 4)
            end
        end
        lastState = state
    end
end)

-- ============================================================
--  BLACK SCREEN
-- ============================================================
local blackScreenGui
local blackScreenRainRunning = false
local setBlackScreen
local BLACK_SCREEN_TOGGLE_UPDATE

do
    local player    = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")

    local existing = playerGui:FindFirstChild("AFKScreen")
    if existing then existing:Destroy() end

    blackScreenGui = Instance.new("ScreenGui")
    blackScreenGui.Name           = "AFKScreen"
    blackScreenGui.IgnoreGuiInset = true
    blackScreenGui.DisplayOrder   = 999
    blackScreenGui.ResetOnSpawn   = false
    blackScreenGui.Enabled        = false
    blackScreenGui.Parent         = playerGui

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1,0,1,0)
    bg.BackgroundColor3 = Color3.fromRGB(0,0,0)
    bg.BorderSizePixel  = 0
    bg.ZIndex           = 1
    bg.ClipsDescendants = true
    bg.Parent           = blackScreenGui

    local rainContainer = Instance.new("Frame")
    rainContainer.Size                = UDim2.new(1,0,1,0)
    rainContainer.BackgroundTransparency = 1
    rainContainer.ZIndex              = 1
    rainContainer.Parent              = bg

    local function createRaindrop()
        local drop = Instance.new("Frame")
        drop.Size                  = UDim2.new(0, 2, 0, math.random(15,35))
        drop.BackgroundColor3      = Color3.fromRGB(255,255,255)
        drop.BackgroundTransparency = 0.75
        drop.BorderSizePixel       = 0
        drop.ZIndex                = 1
        drop.Position              = UDim2.new(math.random(0,1000)/1000, 0, -0.1, 0)
        drop.Parent                = rainContainer
        local tw = TweenService:Create(drop, TweenInfo.new(math.random(15,25)/10, Enum.EasingStyle.Linear), {
            Position = UDim2.new(drop.Position.X.Scale, 0, 1.1, 0)
        })
        tw:Play()
        tw.Completed:Connect(function() drop:Destroy() end)
    end

    local function startRainLoop()
        if blackScreenRainRunning then return end
        blackScreenRainRunning = true
        task.spawn(function()
            while blackScreenRainRunning do
                createRaindrop()
                task.wait(math.random(15,30)/100)
            end
        end)
    end

    local title = Instance.new("TextLabel")
    title.Size               = UDim2.new(0.5,0,0.08,0)
    title.Position           = UDim2.new(0.25,0,0.46,0)
    title.BackgroundTransparency = 1
    title.Text               = "lz3s AFK"
    title.TextColor3         = Color3.fromRGB(255,255,255)
    title.Font               = Enum.Font.Fondamento
    title.TextScaled         = true
    title.ZIndex             = 2
    title.Parent             = bg

    task.spawn(function()
        while title.Parent do
            if blackScreenGui.Enabled then
                local fo = TweenService:Create(title, TweenInfo.new(1.8,Enum.EasingStyle.Sine), {TextTransparency=0.35})
                fo:Play(); fo.Completed:Wait()
                local fi = TweenService:Create(title, TweenInfo.new(1.8,Enum.EasingStyle.Sine), {TextTransparency=0})
                fi:Play(); fi.Completed:Wait()
            else
                task.wait(0.5)
            end
        end
    end)

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size             = UDim2.new(0,44,0,44)
    closeBtn.Position         = UDim2.new(1,-64,0,20)
    closeBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
    closeBtn.Text             = "X"
    closeBtn.TextColor3       = Color3.fromRGB(255,255,255)
    closeBtn.Font             = Enum.Font.GothamBold
    closeBtn.TextScaled       = true
    closeBtn.ZIndex           = 3
    closeBtn.AutoButtonColor  = true
    closeBtn.Parent           = bg
    local cc = Instance.new("UICorner"); cc.CornerRadius=UDim.new(1,0); cc.Parent=closeBtn
    local cs = Instance.new("UIStroke"); cs.Color=Color3.fromRGB(255,255,255); cs.Thickness=1.2; cs.Transparency=0.3; cs.Parent=closeBtn

    setBlackScreen = function(v)
        BLACK_SCREEN = v
        blackScreenGui.Enabled = v
        if v then startRainLoop() else blackScreenRainRunning = false end
        if BLACK_SCREEN_TOGGLE_UPDATE then BLACK_SCREEN_TOGGLE_UPDATE(v) end
    end

    closeBtn.MouseButton1Click:Connect(function() setBlackScreen(false) end)
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

local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 10); c.Parent=p; return c
end
local function stroke(p, col, th)
    local s = Instance.new("UIStroke")
    s.Color=col or Color3.fromRGB(90,70,170); s.Thickness=th or 1.5
    s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=p; return s
end
local function divider(parent, posY)
    local f = Instance.new("Frame")
    f.Size=UDim2.new(1,0,0,1); f.Position=UDim2.fromOffset(0,posY)
    f.BackgroundColor3=Color3.fromRGB(50,40,90); f.BackgroundTransparency=0.3
    f.BorderSizePixel=0; f.Parent=parent
    return posY+10
end

local PALETTE = {
    bg          = Color3.fromRGB(16,15,24),
    panel       = Color3.fromRGB(22,21,32),
    titlebar    = Color3.fromRGB(38,22,84),
    accent      = Color3.fromRGB(125,90,235),
    accentDim   = Color3.fromRGB(90,65,170),
    toggleOff   = Color3.fromRGB(34,33,47),
    toggleOffTx = Color3.fromRGB(150,145,170),
    toggleOn    = Color3.fromRGB(30,110,70),
    toggleOnTx  = Color3.fromRGB(170,255,195),
    textMain    = Color3.fromRGB(225,218,245),
    textDim     = Color3.fromRGB(150,142,180),
    danger      = Color3.fromRGB(120,35,45),
    info        = Color3.fromRGB(35,90,120),
}

local WINDOW_W = 360
local WINDOW_H = 460
local Frame = Instance.new("Frame")
Frame.Name             = "Main"
Frame.Size             = UDim2.fromOffset(WINDOW_W,WINDOW_H)
Frame.Position         = UDim2.new(0,24,0.5,-230)
Frame.BackgroundColor3 = PALETTE.bg
Frame.BorderSizePixel  = 0
Frame.ClipsDescendants = true
Frame.Active           = true
Frame.Draggable        = true
Frame.Parent           = ScreenGui
corner(Frame,14); stroke(Frame,PALETTE.accentDim,1.5)

-- Barra de título
local TitleBar = Instance.new("Frame")
TitleBar.Size=UDim2.new(1,0,0,44); TitleBar.BackgroundColor3=PALETTE.titlebar
TitleBar.BorderSizePixel=0; TitleBar.Parent=Frame
corner(TitleBar,14)
local patch=Instance.new("Frame"); patch.Size=UDim2.new(1,0,0,14); patch.Position=UDim2.new(0,0,1,-14)
patch.BackgroundColor3=PALETTE.titlebar; patch.BorderSizePixel=0; patch.Parent=TitleBar

local TitleDot=Instance.new("Frame"); TitleDot.Size=UDim2.fromOffset(8,8)
TitleDot.Position=UDim2.fromOffset(14,18); TitleDot.BackgroundColor3=PALETTE.accent
TitleDot.BorderSizePixel=0; TitleDot.Parent=TitleBar; corner(TitleDot,4)

local TitleLbl=Instance.new("TextLabel"); TitleLbl.Size=UDim2.new(1,-160,1,0)
TitleLbl.Position=UDim2.fromOffset(32,0); TitleLbl.BackgroundTransparency=1
TitleLbl.Text="lz3s Invasion"; TitleLbl.TextColor3=PALETTE.textMain
TitleLbl.TextSize=16; TitleLbl.Font=Enum.Font.GothamBold
TitleLbl.TextXAlignment=Enum.TextXAlignment.Left; TitleLbl.Parent=TitleBar

local AfkDot=Instance.new("Frame"); AfkDot.Size=UDim2.fromOffset(8,8)
AfkDot.Position=UDim2.new(1,-96,0.5,-4); AfkDot.BackgroundColor3=Color3.fromRGB(90,220,130)
AfkDot.BorderSizePixel=0; AfkDot.Parent=TitleBar; corner(AfkDot,4)

local AfkLbl=Instance.new("TextLabel"); AfkLbl.Size=UDim2.fromOffset(78,20)
AfkLbl.Position=UDim2.new(1,-84,0.5,-10); AfkLbl.BackgroundTransparency=1
AfkLbl.Text="Anti-AFK"; AfkLbl.TextColor3=Color3.fromRGB(150,220,170)
AfkLbl.TextSize=11; AfkLbl.Font=Enum.Font.GothamBold
AfkLbl.TextXAlignment=Enum.TextXAlignment.Left; AfkLbl.Parent=TitleBar

local MinimizeBtn=Instance.new("TextButton"); MinimizeBtn.Size=UDim2.fromOffset(28,28)
MinimizeBtn.Position=UDim2.new(1,-34,0.5,-14); MinimizeBtn.BackgroundColor3=Color3.fromRGB(50,35,95)
MinimizeBtn.BorderSizePixel=0; MinimizeBtn.Text="-"; MinimizeBtn.TextColor3=PALETTE.textMain
MinimizeBtn.Font=Enum.Font.GothamBold; MinimizeBtn.TextSize=16; MinimizeBtn.Parent=TitleBar
corner(MinimizeBtn,7)

-- Abas
local TabBar=Instance.new("Frame"); TabBar.Size=UDim2.new(1,-24,0,36)
TabBar.Position=UDim2.fromOffset(12,54); TabBar.BackgroundColor3=PALETTE.panel
TabBar.BorderSizePixel=0; TabBar.Parent=Frame; corner(TabBar,10)
local tp=Instance.new("UIPadding"); tp.PaddingLeft=UDim.new(0,4); tp.PaddingRight=UDim.new(0,4)
tp.PaddingTop=UDim.new(0,4); tp.PaddingBottom=UDim.new(0,4); tp.Parent=TabBar
local tll=Instance.new("UIListLayout"); tll.FillDirection=Enum.FillDirection.Horizontal
tll.Padding=UDim.new(0,4); tll.SortOrder=Enum.SortOrder.LayoutOrder; tll.Parent=TabBar

local PagesHolder=Instance.new("ScrollingFrame")
PagesHolder.Size=UDim2.new(1,-24,1,-102); PagesHolder.Position=UDim2.fromOffset(12,98)
PagesHolder.BackgroundTransparency=1; PagesHolder.BorderSizePixel=0
PagesHolder.ScrollBarThickness=4; PagesHolder.ScrollBarImageColor3=PALETTE.accentDim
PagesHolder.CanvasSize=UDim2.new(0,0,0,0); PagesHolder.AutomaticCanvasSize=Enum.AutomaticSize.Y
PagesHolder.Parent=Frame

local PAGE_DEFS = {
    {key="INVASION", label="Invasion"},
    {key="TREASURE", label="Treasure"},
    {key="CONFIG",   label="Config"},
}
local pageFrames = {}
local tabButtons = {}

local function selectTab(key)
    for k,f in pairs(pageFrames) do f.Visible=(k==key) end
    for k,b in pairs(tabButtons) do
        if k==key then b.BackgroundColor3=PALETTE.accentDim; b.TextColor3=Color3.fromRGB(235,225,255)
        else b.BackgroundColor3=PALETTE.panel; b.TextColor3=PALETTE.textDim end
    end
end

for i,def in ipairs(PAGE_DEFS) do
    local btn=Instance.new("TextButton")
    btn.Size=UDim2.new(1/#PAGE_DEFS,-3,1,0); btn.LayoutOrder=i
    btn.BackgroundColor3=PALETTE.panel; btn.BorderSizePixel=0
    btn.Text=def.label; btn.TextColor3=PALETTE.textDim
    btn.TextSize=13; btn.Font=Enum.Font.GothamBold; btn.Parent=TabBar
    corner(btn,7); tabButtons[def.key]=btn

    local page=Instance.new("Frame"); page.Name=def.key
    page.Size=UDim2.new(1,0,0,0); page.AutomaticSize=Enum.AutomaticSize.Y
    page.BackgroundTransparency=1; page.Visible=false; page.Parent=PagesHolder
    pageFrames[def.key]=page

    btn.MouseButton1Click:Connect(function() selectTab(def.key) end)
end

-- widget helpers
local function sectionHeader(parent,posY,text)
    local lbl=Instance.new("TextLabel")
    lbl.Size=UDim2.new(1,0,0,20); lbl.Position=UDim2.fromOffset(0,posY)
    lbl.BackgroundTransparency=1; lbl.Text=text; lbl.TextColor3=PALETTE.accent
    lbl.TextSize=13; lbl.Font=Enum.Font.GothamBold
    lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=parent
    return divider(parent,posY+22)
end

local function makeToggle(parent,posY,label,onToggle)
    local btn=Instance.new("TextButton")
    btn.Size=UDim2.new(1,0,0,38); btn.Position=UDim2.fromOffset(0,posY)
    btn.BackgroundColor3=PALETTE.toggleOff; btn.BorderSizePixel=0
    btn.AutoButtonColor=false; btn.Text=""; btn.Parent=parent
    corner(btn,9)
    local lbl=Instance.new("TextLabel")
    lbl.Size=UDim2.new(1,-76,1,0); lbl.Position=UDim2.fromOffset(14,0)
    lbl.BackgroundTransparency=1; lbl.Text=label
    lbl.TextColor3=PALETTE.toggleOffTx; lbl.TextSize=13; lbl.Font=Enum.Font.GothamBold
    lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=btn
    local pill=Instance.new("Frame"); pill.Size=UDim2.fromOffset(54,24)
    pill.Position=UDim2.new(1,-66,0.5,-12); pill.BackgroundColor3=Color3.fromRGB(50,48,66)
    pill.BorderSizePixel=0; pill.Parent=btn; corner(pill,12)
    local knob=Instance.new("Frame"); knob.Size=UDim2.fromOffset(18,18)
    knob.Position=UDim2.fromOffset(3,3); knob.BackgroundColor3=Color3.fromRGB(170,165,190)
    knob.BorderSizePixel=0; knob.Parent=pill; corner(knob,9)
    local on=false
    local function apply(animate)
        local kp=on and UDim2.fromOffset(33,3) or UDim2.fromOffset(3,3)
        local pc=on and PALETTE.accent or Color3.fromRGB(50,48,66)
        local kc=on and Color3.fromRGB(255,255,255) or Color3.fromRGB(170,165,190)
        local bc=on and Color3.fromRGB(26,42,36) or PALETTE.toggleOff
        local lc=on and PALETTE.toggleOnTx or PALETTE.toggleOffTx
        if animate then
            TweenService:Create(knob,TweenInfo.new(0.15),{Position=kp}):Play()
            TweenService:Create(pill,TweenInfo.new(0.15),{BackgroundColor3=pc}):Play()
            TweenService:Create(knob,TweenInfo.new(0.15),{BackgroundColor3=kc}):Play()
            TweenService:Create(btn, TweenInfo.new(0.15),{BackgroundColor3=bc}):Play()
        else
            knob.Position=kp; pill.BackgroundColor3=pc; knob.BackgroundColor3=kc; btn.BackgroundColor3=bc
        end
        lbl.TextColor3=lc
    end
    local function setState(v,fromExt)
        on=v; apply(not fromExt); if not fromExt then onToggle(on) end
    end
    btn.MouseButton1Click:Connect(function() setState(not on) end)
    return posY+44, setState
end

-- toggle compacto (usado na lista de notificações), retorna posY e setter
local function makeCompactToggle(parent, posY, label, onToggle, startOn)
    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(1,0,0,30)
    btn.Position         = UDim2.fromOffset(0,posY)
    btn.BackgroundColor3 = Color3.fromRGB(28,27,40)
    btn.BorderSizePixel  = 0
    btn.AutoButtonColor  = false
    btn.Text             = ""
    btn.Parent           = parent
    corner(btn, 7)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,-56,1,0); lbl.Position = UDim2.fromOffset(12,0)
    lbl.BackgroundTransparency=1; lbl.Text=label
    lbl.TextColor3=Color3.fromRGB(145,138,170); lbl.TextSize=12
    lbl.Font=Enum.Font.GothamBold; lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=btn

    local pill = Instance.new("Frame"); pill.Size=UDim2.fromOffset(42,18)
    pill.Position=UDim2.new(1,-52,0.5,-9); pill.BackgroundColor3=Color3.fromRGB(50,48,66)
    pill.BorderSizePixel=0; pill.Parent=btn
    corner(pill, 9)
    local knob=Instance.new("Frame"); knob.Size=UDim2.fromOffset(14,14)
    knob.Position=UDim2.fromOffset(2,2); knob.BackgroundColor3=Color3.fromRGB(170,165,190)
    knob.BorderSizePixel=0; knob.Parent=pill
    corner(knob, 7)

    local on = startOn
    local function apply(animate)
        local kp = on and UDim2.fromOffset(26,2) or UDim2.fromOffset(2,2)
        local pc = on and Color3.fromRGB(125,90,235) or Color3.fromRGB(50,48,66)
        local kc = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(170,165,190)
        local bc = on and Color3.fromRGB(26,42,36) or Color3.fromRGB(28,27,40)
        local lc = on and Color3.fromRGB(170,255,195) or Color3.fromRGB(145,138,170)
        if animate then
            TweenService:Create(knob,TweenInfo.new(0.12),{Position=kp,BackgroundColor3=kc}):Play()
            TweenService:Create(pill,TweenInfo.new(0.12),{BackgroundColor3=pc}):Play()
            TweenService:Create(btn,TweenInfo.new(0.12),{BackgroundColor3=bc}):Play()
        else
            knob.Position=kp; knob.BackgroundColor3=kc; pill.BackgroundColor3=pc; btn.BackgroundColor3=bc
        end
        lbl.TextColor3=lc
    end
    apply(false)

    local function setState(v, fromExt)
        on=v; apply(true); if not fromExt then onToggle(on) end
    end
    btn.MouseButton1Click:Connect(function() setState(not on) end)

    return posY+34, setState
end

local function makeButton(parent,posY,label,col,onClick)
    local btn=Instance.new("TextButton")
    btn.Size=UDim2.new(1,0,0,38); btn.Position=UDim2.fromOffset(0,posY)
    btn.BackgroundColor3=col or PALETTE.accentDim; btn.BorderSizePixel=0
    btn.Text=label; btn.TextColor3=Color3.fromRGB(235,228,255)
    btn.TextSize=13; btn.Font=Enum.Font.GothamBold; btn.Parent=parent
    corner(btn,9); btn.MouseButton1Click:Connect(onClick)
    return posY+44
end

local function miniLabel(parent,posY,text,color)
    local l=Instance.new("TextLabel")
    l.Size=UDim2.new(1,0,0,16); l.Position=UDim2.fromOffset(0,posY)
    l.BackgroundTransparency=1; l.Text=text
    l.TextColor3=color or PALETTE.textDim; l.TextSize=11
    l.Font=Enum.Font.GothamBold; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=parent
    return posY+18
end

-- ════════════════════════════════════════════════════════════
--  PÁGINA: INVASION
-- ════════════════════════════════════════════════════════════
local cardModoButtons
local cardSecUpdate
local invasionSetters = {}

do
    local p=pageFrames["INVASION"]; local y=4

    y=makeButton(p,y,"Criar invasao",PALETTE.accentDim,criarInvasaoManual)
    y=y+6

    local _,s1=makeToggle(p,y,"Auto Start",function(v) AUTO_START=v end)
    invasionSetters.AUTO_START=s1; y=y+44
    local _,s2=makeToggle(p,y,"Auto Accept Replay",function(v) AUTO_ACCEPT=v end)
    invasionSetters.AUTO_ACCEPT=s2; y=y+44
    local _,s3=makeToggle(p,y,"Auto Replay",function(v) AUTO_REPLAY=v end)
    invasionSetters.AUTO_REPLAY=s3; y=y+44
    local _,s4=makeToggle(p,y,"Auto Join Invasion",function(v) AUTO_JOIN=v; triedLobbies={} end)
    invasionSetters.AUTO_JOIN=s4; y=y+44
    local _,s5=makeToggle(p,y,"Auto TP",function(v) AUTO_TP=v end)
    invasionSetters.AUTO_TP=s5; y=y+44

    y=y+4
    do
        local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.fromOffset(220,30)
        lbl.Position=UDim2.fromOffset(0,y); lbl.BackgroundTransparency=1
        lbl.Text="Min jogadores p/ Auto Start:  "..MIN_PLAYERS
        lbl.TextColor3=PALETTE.textMain; lbl.TextSize=12; lbl.Font=Enum.Font.Gotham
        lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=p
        local function updLbl() lbl.Text="Min jogadores p/ Auto Start:  "..MIN_PLAYERS end
        -- botões − e + com posição absoluta dentro da página (largura fixa 312px)
        local function makeSideBtn(offX, lbText, fn)
            local b = Instance.new("TextButton")
            b.Size             = UDim2.fromOffset(34, 28)
            b.Position         = UDim2.fromOffset(offX, y + 1)
            b.BackgroundColor3 = PALETTE.accentDim
            b.BorderSizePixel  = 0
            b.Text             = lbText
            b.TextColor3       = Color3.fromRGB(225, 210, 255)
            b.TextSize         = 18
            b.Font             = Enum.Font.GothamBold
            b.Parent           = p
            corner(b, 7)
            b.MouseButton1Click:Connect(fn)
        end
        -- página tem ~312px de largura; botões ficam lado a lado no final
        makeSideBtn(240, "-", function() if MIN_PLAYERS > 1 then MIN_PLAYERS -= 1; updLbl() end end)
        makeSideBtn(278, "+", function() if MIN_PLAYERS < 4 then MIN_PLAYERS += 1; updLbl() end end)
        y=y+38
    end

    y=y+6; y=sectionHeader(p,y,"AUTO CARD")
    local _,s6=makeToggle(p,y,"Auto Card",function(v) AUTO_CARD=v end)
    invasionSetters.AUTO_CARD=s6; y=y+44

    y=y+2; y=miniLabel(p,y,"Primario:")
    do
        local btnD=Instance.new("TextButton"); btnD.Size=UDim2.new(0.5,-4,0,32)
        btnD.Position=UDim2.fromOffset(0,y); btnD.BackgroundColor3=Color3.fromRGB(95,30,35)
        btnD.BorderSizePixel=0; btnD.Text="Dano (ativo)"; btnD.TextColor3=Color3.fromRGB(255,185,185)
        btnD.TextSize=12; btnD.Font=Enum.Font.GothamBold; btnD.Parent=p; corner(btnD,7)
        local btnDr=Instance.new("TextButton"); btnDr.Size=UDim2.new(0.5,-4,0,32)
        btnDr.Position=UDim2.new(0.5,4,0,y); btnDr.BackgroundColor3=PALETTE.toggleOff
        btnDr.BorderSizePixel=0; btnDr.Text="Drop"; btnDr.TextColor3=PALETTE.toggleOffTx
        btnDr.TextSize=12; btnDr.Font=Enum.Font.GothamBold; btnDr.Parent=p; corner(btnDr,7)
        local function updModo()
            if CARD_MODO=="dano" then
                btnD.BackgroundColor3=Color3.fromRGB(95,30,35); btnD.TextColor3=Color3.fromRGB(255,185,185); btnD.Text="Dano (ativo)"
                btnDr.BackgroundColor3=PALETTE.toggleOff; btnDr.TextColor3=PALETTE.toggleOffTx; btnDr.Text="Drop"
            else
                btnDr.BackgroundColor3=Color3.fromRGB(28,85,55); btnDr.TextColor3=Color3.fromRGB(170,255,195); btnDr.Text="Drop (ativo)"
                btnD.BackgroundColor3=PALETTE.toggleOff; btnD.TextColor3=PALETTE.toggleOffTx; btnD.Text="Dano"
            end
        end
        btnD.MouseButton1Click:Connect(function() CARD_MODO="dano"; updModo() end)
        btnDr.MouseButton1Click:Connect(function() CARD_MODO="drop"; updModo() end)
        cardModoButtons=updModo; y=y+38
    end

    y=y+4; y=miniLabel(p,y,"Secundario (prioridade se aparecer):")
    do
        local OPCOES={{id=nil,label="Nenhuma"},{id="reinf",label="Warrior Reinforcement"},{id="barricade",label="Barricade Repair"}}
        local btnSec=Instance.new("TextButton"); btnSec.Size=UDim2.new(1,0,0,32)
        btnSec.Position=UDim2.fromOffset(0,y); btnSec.BackgroundColor3=PALETTE.toggleOff
        btnSec.BorderSizePixel=0; btnSec.Text="Selecionar"; btnSec.TextColor3=PALETTE.toggleOffTx
        btnSec.TextSize=12; btnSec.Font=Enum.Font.GothamBold; btnSec.Parent=p; corner(btnSec,7)
        y=y+36
        local ITEM_H=32
        local popup=Instance.new("Frame"); popup.Size=UDim2.new(1,0,0,#OPCOES*ITEM_H+6)
        popup.Position=UDim2.fromOffset(0,y); popup.BackgroundColor3=Color3.fromRGB(20,19,30)
        popup.BorderSizePixel=0; popup.ZIndex=20; popup.Visible=false; popup.Parent=p
        corner(popup,9); stroke(popup,PALETTE.accentDim,1)
        local function updSec()
            if CARD_SEC_ID==nil then
                btnSec.Text="Selecionar"; btnSec.BackgroundColor3=PALETTE.toggleOff; btnSec.TextColor3=PALETTE.toggleOffTx
                CARD_SEC_REINF=false; CARD_SEC_BARRICADE=false
            else
                local nome=CARD_SEC_ID=="reinf" and "Warrior Reinforcement" or "Barricade Repair"
                btnSec.Text=nome.." (ativo)"; btnSec.BackgroundColor3=Color3.fromRGB(30,75,110); btnSec.TextColor3=Color3.fromRGB(165,220,255)
                CARD_SEC_REINF=(CARD_SEC_ID=="reinf"); CARD_SEC_BARRICADE=(CARD_SEC_ID=="barricade")
            end
        end
        for i,op in ipairs(OPCOES) do
            local item=Instance.new("TextButton"); item.Size=UDim2.new(1,0,0,ITEM_H)
            item.Position=UDim2.fromOffset(0,(i-1)*ITEM_H+3); item.BackgroundTransparency=1
            item.BorderSizePixel=0; item.Text="  "..op.label; item.TextColor3=Color3.fromRGB(205,198,230)
            item.TextSize=12; item.Font=Enum.Font.GothamBold; item.TextXAlignment=Enum.TextXAlignment.Left
            item.ZIndex=21; item.Parent=popup
            item.MouseEnter:Connect(function() item.BackgroundTransparency=0; item.BackgroundColor3=Color3.fromRGB(42,33,78) end)
            item.MouseLeave:Connect(function() item.BackgroundTransparency=1 end)
            item.MouseButton1Click:Connect(function() CARD_SEC_ID=op.id; updSec(); popup.Visible=false end)
        end
        btnSec.MouseButton1Click:Connect(function() popup.Visible=not popup.Visible end)
        cardSecUpdate=updSec; y=y+8
    end
    y=y+4
end

-- ════════════════════════════════════════════════════════════
--  PÁGINA: TREASURE
-- ════════════════════════════════════════════════════════════
local treasureSetter
do
    local p=pageFrames["TREASURE"]; local y=4
    y=sectionHeader(p,y,"TREASURE HUNT")
    local _,set=makeToggle(p,y,"Auto Treasure",function(v) AUTO_TREASURE=v; if v then iniciarLoopTreasure() end end)
    treasureSetter=set; y=y+44
    y=y+4
    y=miniLabel(p,y,"Cava sozinho enquanto tiver pas.",Color3.fromRGB(160,155,185))
end

-- ════════════════════════════════════════════════════════════
--  PÁGINA: CONFIG
-- ════════════════════════════════════════════════════════════
local keybindDisplayLabel
do
    local p=pageFrames["CONFIG"]; local y=4

    y=sectionHeader(p,y,"BLACK SCREEN")
    do
        local btnBS=Instance.new("TextButton"); btnBS.Size=UDim2.new(1,0,0,38)
        btnBS.Position=UDim2.fromOffset(0,y); btnBS.BackgroundColor3=PALETTE.toggleOff
        btnBS.BorderSizePixel=0; btnBS.Text="Ativar Black Screen - OFF"
        btnBS.TextColor3=PALETTE.toggleOffTx; btnBS.TextSize=13; btnBS.Font=Enum.Font.GothamBold; btnBS.Parent=p
        corner(btnBS,9); y=y+44
        local function updateVisual(v)
            if v then btnBS.Text="Black Screen - ON"; btnBS.BackgroundColor3=Color3.fromRGB(26,42,36); btnBS.TextColor3=PALETTE.toggleOnTx
            else btnBS.Text="Ativar Black Screen - OFF"; btnBS.BackgroundColor3=PALETTE.toggleOff; btnBS.TextColor3=PALETTE.toggleOffTx end
        end
        BLACK_SCREEN_TOGGLE_UPDATE=updateVisual
        btnBS.MouseButton1Click:Connect(function() setBlackScreen(not BLACK_SCREEN) end)
    end
    y=miniLabel(p,y,"Tela preta com chuva. Botao X fecha.",Color3.fromRGB(160,155,185))

    y=y+8; y=sectionHeader(p,y,"ANTI-AFK")
    y=miniLabel(p,y,"Sempre ativo.",Color3.fromRGB(160,155,185))

    -- ── Notificações ──────────────────────────────────────────
    y=y+8; y=sectionHeader(p,y,"NOTIFICACOES")

    local notifSetters = {}
    local _, ms = makeCompactToggle(p, y, "Ativar notificacoes", function(v)
        NOTIF_ENABLED = v
        for _, setter in pairs(notifSetters) do
            -- apenas efeito visual: mantém estado individual, só mostra/esconde "habilitado geral"
        end
    end, NOTIF_ENABLED)
    y = y + 34

    local NOTIF_DEFS = {
        { key="NOTIF_INVASION_DISP",  label="Invasion disponivel"  },
        { key="NOTIF_INVASION_START", label="Invasion comecou"     },
        { key="NOTIF_INVASION_END",   label="Invasion terminou"    },
        { key="NOTIF_ENTROU",         label="Entrou em invasion"   },
        { key="NOTIF_TP",             label="Auto TP na torre"     },
        { key="NOTIF_TREASURE",       label="Cavada do tesouro"    },
    }
    local notifVars = {
        NOTIF_INVASION_DISP  = function(v) NOTIF_INVASION_DISP  = v end,
        NOTIF_INVASION_START = function(v) NOTIF_INVASION_START = v end,
        NOTIF_INVASION_END   = function(v) NOTIF_INVASION_END   = v end,
        NOTIF_ENTROU         = function(v) NOTIF_ENTROU         = v end,
        NOTIF_TP             = function(v) NOTIF_TP             = v end,
        NOTIF_TREASURE       = function(v) NOTIF_TREASURE       = v end,
    }
    local notifStartState = {
        NOTIF_INVASION_DISP  = NOTIF_INVASION_DISP,
        NOTIF_INVASION_START = NOTIF_INVASION_START,
        NOTIF_INVASION_END   = NOTIF_INVASION_END,
        NOTIF_ENTROU         = NOTIF_ENTROU,
        NOTIF_TP             = NOTIF_TP,
        NOTIF_TREASURE       = NOTIF_TREASURE,
    }

    for _, def in ipairs(NOTIF_DEFS) do
        local newY, setter = makeCompactToggle(p, y, def.label, function(v)
            if notifVars[def.key] then notifVars[def.key](v) end
        end, notifStartState[def.key])
        notifSetters[def.key] = setter
        y = newY
    end

    y=y+8; y=sectionHeader(p,y,"KEYBIND")
    keybindDisplayLabel=Instance.new("TextLabel"); keybindDisplayLabel.Size=UDim2.new(1,0,0,24)
    keybindDisplayLabel.Position=UDim2.fromOffset(0,y); keybindDisplayLabel.BackgroundTransparency=1
    keybindDisplayLabel.Text="Atual: RightShift + K"; keybindDisplayLabel.TextColor3=PALETTE.textMain
    keybindDisplayLabel.TextSize=13; keybindDisplayLabel.Font=Enum.Font.GothamBold
    keybindDisplayLabel.TextXAlignment=Enum.TextXAlignment.Left; keybindDisplayLabel.Parent=p; y=y+28

    local btnRecord=Instance.new("TextButton"); btnRecord.Size=UDim2.new(1,0,0,38)
    btnRecord.Position=UDim2.fromOffset(0,y); btnRecord.BackgroundColor3=PALETTE.accentDim
    btnRecord.BorderSizePixel=0; btnRecord.Text="Gravar nova keybind"
    btnRecord.TextColor3=Color3.fromRGB(235,228,255); btnRecord.TextSize=13; btnRecord.Font=Enum.Font.GothamBold; btnRecord.Parent=p
    corner(btnRecord,9); y=y+44
    y=miniLabel(p,y,"Clique, aperte as teclas, clique em Parar.",Color3.fromRGB(160,155,185))

    local recordedKeys={}; local recordConn=nil
    local function keybindParaTexto(keys)
        if keys==nil or #keys==0 then return "Nenhuma" end
        return table.concat(keys," + ")
    end
    local function pararGravacao()
        KEYBIND_RECORDING=false
        if recordConn then recordConn:Disconnect(); recordConn=nil end
        btnRecord.Text="Gravar nova keybind"; btnRecord.BackgroundColor3=PALETTE.accentDim
        if #recordedKeys>0 then KEYBIND_KEYS=recordedKeys; keybindDisplayLabel.Text="Atual: "..keybindParaTexto(KEYBIND_KEYS) end
    end
    local function iniciarGravacao()
        KEYBIND_RECORDING=true; recordedKeys={}
        btnRecord.Text="Parar (gravando)"; btnRecord.BackgroundColor3=PALETTE.danger
        keybindDisplayLabel.Text="Atual: (gravando...)"
        recordConn=UserInputService.InputBegan:Connect(function(input,gpe)
            if gpe then return end
            if input.UserInputType==Enum.UserInputType.Keyboard then
                local kn=input.KeyCode.Name; local jaTem=false
                for _,k in ipairs(recordedKeys) do if k==kn then jaTem=true end end
                if not jaTem then table.insert(recordedKeys,kn); keybindDisplayLabel.Text="Atual: "..keybindParaTexto(recordedKeys).." ..." end
            end
        end)
    end
    btnRecord.MouseButton1Click:Connect(function() if KEYBIND_RECORDING then pararGravacao() else iniciarGravacao() end end)

    y=y+6; y=sectionHeader(p,y,"CONFIGURACAO")
    local statusLbl=Instance.new("TextLabel"); statusLbl.Size=UDim2.new(1,0,0,18)
    statusLbl.Position=UDim2.fromOffset(0,y); statusLbl.BackgroundTransparency=1; statusLbl.Text=""
    statusLbl.TextColor3=Color3.fromRGB(150,225,160); statusLbl.TextSize=11; statusLbl.Font=Enum.Font.Gotham
    statusLbl.TextXAlignment=Enum.TextXAlignment.Left; statusLbl.Parent=p; y=y+22
    local function mostrarStatus(msg,ok)
        statusLbl.Text=msg; statusLbl.TextColor3=ok and Color3.fromRGB(150,225,160) or Color3.fromRGB(235,130,130)
        task.delay(3,function() if statusLbl.Text==msg then statusLbl.Text="" end end)
    end
    y=makeButton(p,y,"Salvar configuracao",Color3.fromRGB(28,95,80),function()
        local ok=salvarConfig(); mostrarStatus(ok and "Salvo." or "Falha ao salvar.",ok)
    end)
    y=makeButton(p,y,"Carregar configuracao",PALETTE.accentDim,function()
        local dados=carregarConfigDoArquivo()
        if dados==nil then mostrarStatus("Nenhuma config encontrada.",false); return end
        _G.__lz3s_aplicarConfig(dados); mostrarStatus("Configuracao carregada.",true)
    end)
    y=miniLabel(p,y,"Salva toggles, cartas, keybind e notifs.",Color3.fromRGB(160,155,185))
end

-- ============================================================
--  APLICAR CONFIG
-- ============================================================
_G.__lz3s_aplicarConfig = function(dados)
    if dados==nil then return end
    if dados.MIN_PLAYERS then MIN_PLAYERS=dados.MIN_PLAYERS end
    if dados.CARD_MODO then CARD_MODO=dados.CARD_MODO; if cardModoButtons then cardModoButtons() end end
    CARD_SEC_ID=dados.CARD_SEC_ID; if cardSecUpdate then cardSecUpdate() end
    if dados.KEYBIND_KEYS then
        KEYBIND_KEYS=dados.KEYBIND_KEYS
        if keybindDisplayLabel then keybindDisplayLabel.Text="Atual: "..table.concat(KEYBIND_KEYS," + ") end
    end
    local function applyToggle(setter,val) if setter then setter(val==true,true) end end
    applyToggle(invasionSetters.AUTO_START,  dados.AUTO_START)
    applyToggle(invasionSetters.AUTO_ACCEPT, dados.AUTO_ACCEPT)
    applyToggle(invasionSetters.AUTO_REPLAY, dados.AUTO_REPLAY)
    applyToggle(invasionSetters.AUTO_JOIN,   dados.AUTO_JOIN)
    applyToggle(invasionSetters.AUTO_TP,     dados.AUTO_TP)
    applyToggle(invasionSetters.AUTO_CARD,   dados.AUTO_CARD)
    applyToggle(treasureSetter,              dados.AUTO_TREASURE)
    AUTO_START=dados.AUTO_START==true; AUTO_ACCEPT=dados.AUTO_ACCEPT==true
    AUTO_REPLAY=dados.AUTO_REPLAY==true; AUTO_JOIN=dados.AUTO_JOIN==true
    AUTO_TP=dados.AUTO_TP==true; AUTO_CARD=dados.AUTO_CARD==true
    AUTO_TREASURE=dados.AUTO_TREASURE==true
    if AUTO_TREASURE then iniciarLoopTreasure() end
    if dados.BLACK_SCREEN then setBlackScreen(true) end
    if dados.NOTIF_ENABLED        ~= nil then NOTIF_ENABLED        = dados.NOTIF_ENABLED        end
    if dados.NOTIF_INVASION_DISP  ~= nil then NOTIF_INVASION_DISP  = dados.NOTIF_INVASION_DISP  end
    if dados.NOTIF_INVASION_START ~= nil then NOTIF_INVASION_START = dados.NOTIF_INVASION_START end
    if dados.NOTIF_INVASION_END   ~= nil then NOTIF_INVASION_END   = dados.NOTIF_INVASION_END   end
    if dados.NOTIF_ENTROU         ~= nil then NOTIF_ENTROU         = dados.NOTIF_ENTROU         end
    if dados.NOTIF_TP             ~= nil then NOTIF_TP             = dados.NOTIF_TP             end
    if dados.NOTIF_TREASURE       ~= nil then NOTIF_TREASURE       = dados.NOTIF_TREASURE       end
end

-- ============================================================
--  KEYBIND: abrir/fechar GUI
-- ============================================================
do
    local pressionadas={}
    local function sequenciaCompleta()
        if #KEYBIND_KEYS==0 then return false end
        for _,k in ipairs(KEYBIND_KEYS) do if not pressionadas[k] then return false end end
        return true
    end
    UserInputService.InputBegan:Connect(function(input,gpe)
        if KEYBIND_RECORDING then return end
        if input.UserInputType~=Enum.UserInputType.Keyboard then return end
        pressionadas[input.KeyCode.Name]=true
        if sequenciaCompleta() then ScreenGui.Enabled=not ScreenGui.Enabled end
    end)
    UserInputService.InputEnded:Connect(function(input,gpe)
        if input.UserInputType~=Enum.UserInputType.Keyboard then return end
        pressionadas[input.KeyCode.Name]=nil
    end)
end

-- ============================================================
--  MINIMIZAR
--  Esconde TabBar + PagesHolder e encolhe a janela pra altura
--  da TitleBar. Antes só dava resize no Frame, mas com
--  ClipsDescendants=false isso deixava os elementos internos
--  "vazando" por fora do frame encolhido. Agora:
--  1. ClipsDescendants=true no Frame principal (corta tudo que
--     sair da área visível)
--  2. Esconde explicitamente TabBar e PagesHolder ao minimizar
--  3. Restaura a visibilidade ao expandir de novo
-- ============================================================
do
    local minimized=false
    MinimizeBtn.MouseButton1Click:Connect(function()
        minimized=not minimized
        if minimized then
            TweenService:Create(Frame,TweenInfo.new(0.2),{Size=UDim2.fromOffset(WINDOW_W,44)}):Play()
            TabBar.Visible=false
            PagesHolder.Visible=false
            MinimizeBtn.Text="+"
        else
            TweenService:Create(Frame,TweenInfo.new(0.2),{Size=UDim2.fromOffset(WINDOW_W,WINDOW_H)}):Play()
            TabBar.Visible=true
            PagesHolder.Visible=true
            MinimizeBtn.Text="-"
        end
    end)
end

selectTab("INVASION")

-- Autoload
task.defer(function()
    local dados=carregarConfigDoArquivo()
    if dados~=nil then _G.__lz3s_aplicarConfig(dados); logf("Config carregada automaticamente.") end
end)

print("[lz3s Invasion v2] Carregado! Keybind: RightShift + K para abrir/fechar.")
