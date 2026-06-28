-- ============================================================
--  lz3s Invasion Menu
--  INVASION : Criar, Auto Start, Auto Card, Accept, Replay, Join, TP
--  UTILITY  : Black Screen, Anti-AFK (sempre ativo)
--  TREASURE : Auto Treasure
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local VirtualUser       = game:GetService("VirtualUser")

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

-- ===================== CONFIG =====================
local DEBUG_PRINT   = false
local INVASION_NAME = "Dark Matter Invasion"
local MIN_PLAYERS   = 1

local function logf(msg)
    if DEBUG_PRINT then print("[lz3s] " .. msg) end
end

-- ===================== ESTADO =====================
local AUTO_START    = false
local AUTO_CARD     = false
local AUTO_ACCEPT   = false
local AUTO_REPLAY   = false
local AUTO_JOIN     = false
local AUTO_TREASURE = false
local AUTO_TP       = false

local CARD_MODO          = "dano"
local CARD_SEC_REINF     = false
local CARD_SEC_BARRICADE = false

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
--  AUTO TREASURE
-- ============================================================
local DELAY_ENTRE_CAVADAS   = 0.6
local CHECK_INTERVAL_SEM_PA = 2
local treasureRodando       = false

local function getQuantidadeDePas()
    local d = getPlayerData(USER_KEY)
    if d == nil then return 0 end
    local s = d.items and d.items.Shovel
    return s and s.amount or 0
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
    if not ok then return end
    p:andThen(function(r)
        if r and r.reason then logf("Treasure: "..r.reason) end
    end):catch(function() end)
end

local function iniciarLoopTreasure()
    if treasureRodando then return end
    treasureRodando = true
    task.spawn(function()
        while AUTO_TREASURE do
            if getQuantidadeDePas() > 0 then cavarUmaVez(); task.wait(DELAY_ENTRE_CAVADAS)
            else task.wait(CHECK_INTERVAL_SEM_PA) end
        end
        treasureRodando = false
    end)
end

-- ============================================================
--  GUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "lz3sInvasion"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local okGui = pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
if not okGui then ScreenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

-- helpers
local function corner(p, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 10); c.Parent = p
end
local function stroke(p, col, th)
    local s = Instance.new("UIStroke")
    s.Color = col or Color3.fromRGB(80,60,160); s.Thickness = th or 1.5; s.Parent = p
end
local function divider(parent, posY)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,-20,0,1); f.Position = UDim2.fromOffset(10, posY)
    f.BackgroundColor3 = Color3.fromRGB(45,35,80); f.BorderSizePixel = 0; f.Parent = parent
    return posY + 8
end

-- ── Janela principal ──────────────────────────────────────────
local Frame = Instance.new("Frame")
Frame.Name             = "Main"
Frame.Size             = UDim2.fromOffset(260, 100) -- ajustado no final
Frame.Position         = UDim2.new(0, 20, 0.5, -300)
Frame.BackgroundColor3 = Color3.fromRGB(13, 13, 20)
Frame.BorderSizePixel  = 0
Frame.Active           = true
Frame.Draggable        = true
Frame.Parent           = ScreenGui
corner(Frame, 12)
stroke(Frame, Color3.fromRGB(75, 50, 155), 1.5)

-- ── Barra de título ───────────────────────────────────────────
local TitleBar = Instance.new("Frame")
TitleBar.Size             = UDim2.new(1,0,0,36)
TitleBar.BackgroundColor3 = Color3.fromRGB(35, 20, 80)
TitleBar.BorderSizePixel  = 0
TitleBar.Parent           = Frame
corner(TitleBar, 12)

-- patch: quadrados no canto inferior da barra para não ter raio
local patch = Instance.new("Frame")
patch.Size = UDim2.new(1,0,0,12); patch.Position = UDim2.new(0,0,1,-12)
patch.BackgroundColor3 = Color3.fromRGB(35,20,80); patch.BorderSizePixel=0; patch.Parent=TitleBar

local TitleLbl = Instance.new("TextLabel")
TitleLbl.Size             = UDim2.new(1,-12,1,0)
TitleLbl.Position         = UDim2.fromOffset(12,0)
TitleLbl.BackgroundTransparency = 1
TitleLbl.Text             = "⚔  lz3s Invasion"
TitleLbl.TextColor3       = Color3.fromRGB(215, 195, 255)
TitleLbl.TextSize         = 14
TitleLbl.Font             = Enum.Font.GothamBold
TitleLbl.TextXAlignment   = Enum.TextXAlignment.Left
TitleLbl.Parent           = TitleBar

-- indicador anti-afk no canto direito da barra
local AfkDot = Instance.new("TextLabel")
AfkDot.Size             = UDim2.fromOffset(70, 36)
AfkDot.Position         = UDim2.new(1,-72,0,0)
AfkDot.BackgroundTransparency = 1
AfkDot.Text             = ""
AfkDot.TextColor3       = Color3.fromRGB(120, 210, 130)
AfkDot.TextSize         = 10
AfkDot.Font             = Enum.Font.Gotham
AfkDot.TextXAlignment   = Enum.TextXAlignment.Right
AfkDot.Parent           = TitleBar

-- ── Helpers de widget ─────────────────────────────────────────
local function sectionHeader(parent, posY, text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,-20,0,18); lbl.Position = UDim2.fromOffset(10, posY)
    lbl.BackgroundTransparency = 1
    lbl.Text = text; lbl.TextColor3 = Color3.fromRGB(150,125,210)
    lbl.TextSize = 11; lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = parent
    return divider(parent, posY + 20)
end

local function makeToggle(parent, posY, label, onToggle)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,-20,0,32); btn.Position = UDim2.fromOffset(10, posY)
    btn.BackgroundColor3 = Color3.fromRGB(32,32,45); btn.BorderSizePixel = 0
    btn.Text = label .. "   OFF"; btn.TextColor3 = Color3.fromRGB(140,135,160)
    btn.TextSize = 12; btn.Font = Enum.Font.GothamBold; btn.Parent = parent
    corner(btn, 7)
    local on = false
    local function apply()
        if on then
            btn.Text = label .. "   ON ✓"
            btn.BackgroundColor3 = Color3.fromRGB(28, 95, 50)
            btn.TextColor3 = Color3.fromRGB(160, 255, 175)
        else
            btn.Text = label .. "   OFF"
            btn.BackgroundColor3 = Color3.fromRGB(32,32,45)
            btn.TextColor3 = Color3.fromRGB(140,135,160)
        end
    end
    btn.MouseButton1Click:Connect(function() on = not on; apply(); onToggle(on) end)
    return posY + 36
end

local function makeButton(parent, posY, label, col, onClick)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,-20,0,32); btn.Position = UDim2.fromOffset(10, posY)
    btn.BackgroundColor3 = col or Color3.fromRGB(50,25,90); btn.BorderSizePixel = 0
    btn.Text = label; btn.TextColor3 = Color3.fromRGB(225,210,255)
    btn.TextSize = 12; btn.Font = Enum.Font.GothamBold; btn.Parent = parent
    corner(btn, 7)
    btn.MouseButton1Click:Connect(onClick)
    return posY + 36
end

local function miniLabel(parent, posY, text)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1,-20,0,16); l.Position = UDim2.fromOffset(10, posY)
    l.BackgroundTransparency = 1; l.Text = text
    l.TextColor3 = Color3.fromRGB(120,110,165); l.TextSize = 11
    l.Font = Enum.Font.GothamBold; l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return posY + 18
end

-- ── LAYOUT ────────────────────────────────────────────────────
local y = 44  -- abaixo da barra de título

-- ══════════════════════ SEÇÃO INVASION ══════════════════════
y = sectionHeader(Frame, y, "⚔  INVASION")

y = makeButton(Frame, y, "🚀  Criar Invasão", Color3.fromRGB(55,25,100), criarInvasaoManual)
y = y + 4
y = makeToggle(Frame, y, "Auto Start",         function(v) AUTO_START  = v end)
y = makeToggle(Frame, y, "Auto Accept Replay", function(v) AUTO_ACCEPT = v end)
y = makeToggle(Frame, y, "Auto Replay",        function(v) AUTO_REPLAY = v end)
y = makeToggle(Frame, y, "Auto Join Invasion", function(v) AUTO_JOIN=v; triedLobbies={} end)
y = makeToggle(Frame, y, "Auto TP",            function(v) AUTO_TP = v end)

y = y + 6

-- Min Jogadores
do
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.fromOffset(160,28); lbl.Position = UDim2.fromOffset(10,y)
    lbl.BackgroundTransparency=1; lbl.Text="Min jogadores:  "..MIN_PLAYERS
    lbl.TextColor3=Color3.fromRGB(180,170,215); lbl.TextSize=12
    lbl.Font=Enum.Font.Gotham; lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=Frame

    local function updLbl() lbl.Text = "Min jogadores:  "..MIN_PLAYERS end

    local function sideBtn(px, lbText, fn)
        local b = Instance.new("TextButton")
        b.Size=UDim2.fromOffset(28,24); b.Position=UDim2.fromOffset(px,y+2)
        b.BackgroundColor3=Color3.fromRGB(50,25,90); b.BorderSizePixel=0
        b.Text=lbText; b.TextColor3=Color3.fromRGB(210,170,255)
        b.TextSize=18; b.Font=Enum.Font.GothamBold; b.Parent=Frame
        corner(b,6); b.MouseButton1Click:Connect(fn)
    end
    sideBtn(174,"−",function() if MIN_PLAYERS>1 then MIN_PLAYERS-=1; updLbl() end end)
    sideBtn(206,"+",function() if MIN_PLAYERS<4 then MIN_PLAYERS+=1; updLbl() end end)
    y = y + 36
end

y = y + 4
y = divider(Frame, y)

-- ══════════════════════ SEÇÃO AUTO CARD ══════════════════════
y = sectionHeader(Frame, y, "🃏  AUTO CARD")

y = makeToggle(Frame, y, "Auto Card", function(v) AUTO_CARD = v end)
y = y + 4

-- Primário: Dano / Drop
y = miniLabel(Frame, y, "Primário:")
do
    local btnD = Instance.new("TextButton")
    btnD.Size=UDim2.fromOffset(114,28); btnD.Position=UDim2.fromOffset(10,y)
    btnD.BackgroundColor3=Color3.fromRGB(85,25,25); btnD.BorderSizePixel=0
    btnD.Text="🗡 Dano ✓"; btnD.TextColor3=Color3.fromRGB(255,175,175)
    btnD.TextSize=12; btnD.Font=Enum.Font.GothamBold; btnD.Parent=Frame
    corner(btnD,6)

    local btnDr = Instance.new("TextButton")
    btnDr.Size=UDim2.fromOffset(114,28); btnDr.Position=UDim2.fromOffset(128,y)
    btnDr.BackgroundColor3=Color3.fromRGB(32,32,45); btnDr.BorderSizePixel=0
    btnDr.Text="💰 Drop"; btnDr.TextColor3=Color3.fromRGB(140,135,160)
    btnDr.TextSize=12; btnDr.Font=Enum.Font.GothamBold; btnDr.Parent=Frame
    corner(btnDr,6)

    local function updModo()
        if CARD_MODO=="dano" then
            btnD.BackgroundColor3=Color3.fromRGB(85,25,25); btnD.TextColor3=Color3.fromRGB(255,175,175); btnD.Text="🗡 Dano ✓"
            btnDr.BackgroundColor3=Color3.fromRGB(32,32,45); btnDr.TextColor3=Color3.fromRGB(140,135,160); btnDr.Text="💰 Drop"
        else
            btnDr.BackgroundColor3=Color3.fromRGB(25,75,45); btnDr.TextColor3=Color3.fromRGB(160,255,185); btnDr.Text="💰 Drop ✓"
            btnD.BackgroundColor3=Color3.fromRGB(32,32,45); btnD.TextColor3=Color3.fromRGB(140,135,160); btnD.Text="🗡 Dano"
        end
    end
    btnD.MouseButton1Click:Connect(function() CARD_MODO="dano"; updModo() end)
    btnDr.MouseButton1Click:Connect(function() CARD_MODO="drop"; updModo() end)
    y = y + 32
end

y = y + 4

-- Secundário: dropdown
y = miniLabel(Frame, y, "Secundário (prioridade se aparecer):")
do
    local OPCOES = {
        { id=nil,          label="Nenhuma"               },
        { id="reinf",      label="Warrior Reinforcement" },
        { id="barricade",  label="Barricade Repair"      },
    }
    local secSel = nil

    local btnSec = Instance.new("TextButton")
    btnSec.Size=UDim2.new(1,-20,0,28); btnSec.Position=UDim2.fromOffset(10,y)
    btnSec.BackgroundColor3=Color3.fromRGB(32,32,45); btnSec.BorderSizePixel=0
    btnSec.Text="Selecionar  ▾"; btnSec.TextColor3=Color3.fromRGB(140,135,160)
    btnSec.TextSize=12; btnSec.Font=Enum.Font.GothamBold; btnSec.Parent=Frame
    corner(btnSec,6)
    y = y + 32

    -- popup
    local ITEM_H = 30
    local popup = Instance.new("Frame")
    popup.Size=UDim2.fromOffset(240, #OPCOES*ITEM_H+6)
    popup.Position=UDim2.fromOffset(10, y-32+30)
    popup.BackgroundColor3=Color3.fromRGB(18,18,28); popup.BorderSizePixel=0
    popup.ZIndex=20; popup.Visible=false; popup.Parent=Frame
    corner(popup,8); stroke(popup,Color3.fromRGB(70,50,140),1)

    local function updSec()
        if secSel==nil then
            btnSec.Text="Selecionar  ▾"
            btnSec.BackgroundColor3=Color3.fromRGB(32,32,45)
            btnSec.TextColor3=Color3.fromRGB(140,135,160)
            CARD_SEC_REINF=false; CARD_SEC_BARRICADE=false
        else
            local nome = secSel=="reinf" and "Warrior Reinforcement" or "Barricade Repair"
            btnSec.Text=nome.."  ✓"
            btnSec.BackgroundColor3=Color3.fromRGB(28,70,105)
            btnSec.TextColor3=Color3.fromRGB(155,215,255)
            CARD_SEC_REINF=(secSel=="reinf"); CARD_SEC_BARRICADE=(secSel=="barricade")
        end
    end

    for i, op in ipairs(OPCOES) do
        local item = Instance.new("TextButton")
        item.Size=UDim2.fromOffset(240,ITEM_H); item.Position=UDim2.fromOffset(0,(i-1)*ITEM_H+3)
        item.BackgroundTransparency=1; item.BorderSizePixel=0
        item.Text="  "..op.label; item.TextColor3=Color3.fromRGB(200,190,230)
        item.TextSize=12; item.Font=Enum.Font.GothamBold
        item.TextXAlignment=Enum.TextXAlignment.Left
        item.ZIndex=21; item.Parent=popup
        item.MouseEnter:Connect(function() item.BackgroundTransparency=0; item.BackgroundColor3=Color3.fromRGB(40,30,75) end)
        item.MouseLeave:Connect(function() item.BackgroundTransparency=1 end)
        item.MouseButton1Click:Connect(function()
            secSel=op.id; updSec(); popup.Visible=false
        end)
    end

    btnSec.MouseButton1Click:Connect(function() popup.Visible=not popup.Visible end)
    y = y + 6
end

y = y + 4
y = divider(Frame, y)

-- ══════════════════════ SEÇÃO TREASURE ══════════════════════
y = sectionHeader(Frame, y, "💰  TREASURE HUNT")
y = makeToggle(Frame, y, "Auto Treasure", function(v) AUTO_TREASURE=v; if v then iniciarLoopTreasure() end end)

y = y + 4
y = divider(Frame, y)

-- ══════════════════════ SEÇÃO UTILITY ══════════════════════
y = sectionHeader(Frame, y, "🛠  UTILITY")

-- Black Screen
do
    -- GUI separada para a tela preta (ZIndex alto)
    local bsGui = Instance.new("ScreenGui")
    bsGui.Name="lz3sBlackScreen"; bsGui.ResetOnSpawn=false
    bsGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    local bsOk = pcall(function() bsGui.Parent=game:GetService("CoreGui") end)
    if not bsOk then bsGui.Parent=Players.LocalPlayer:WaitForChild("PlayerGui") end

    local bsFrame = Instance.new("Frame")
    bsFrame.Size=UDim2.fromScale(1,1); bsFrame.BackgroundColor3=Color3.fromRGB(0,0,0)
    bsFrame.BorderSizePixel=0; bsFrame.ZIndex=100; bsFrame.Visible=false; bsFrame.Parent=bsGui

    local bsLabel = Instance.new("TextLabel")
    bsLabel.Size=UDim2.fromScale(1,1); bsLabel.BackgroundTransparency=1
    bsLabel.Text="lz3s afk"; bsLabel.TextColor3=Color3.fromRGB(255,255,255)
    bsLabel.TextSize=36; bsLabel.Font=Enum.Font.GothamBold
    bsLabel.ZIndex=101; bsLabel.Parent=bsFrame

    -- botão "close" pequeno no canto superior esquerdo da tela preta
    local bsClose = Instance.new("TextButton")
    bsClose.Size=UDim2.fromOffset(60,26); bsClose.Position=UDim2.fromOffset(10,10)
    bsClose.BackgroundColor3=Color3.fromRGB(50,25,90); bsClose.BorderSizePixel=0
    bsClose.Text="✕ close"; bsClose.TextColor3=Color3.fromRGB(220,200,255)
    bsClose.TextSize=12; bsClose.Font=Enum.Font.GothamBold
    bsClose.ZIndex=102; bsClose.Parent=bsFrame
    corner(bsClose,6)

    -- botão no menu para ativar
    local btnBS = Instance.new("TextButton")
    btnBS.Size=UDim2.new(1,-20,0,32); btnBS.Position=UDim2.fromOffset(10,y)
    btnBS.BackgroundColor3=Color3.fromRGB(32,32,45); btnBS.BorderSizePixel=0
    btnBS.Text="🌑  Black Screen   OFF"; btnBS.TextColor3=Color3.fromRGB(140,135,160)
    btnBS.TextSize=12; btnBS.Font=Enum.Font.GothamBold; btnBS.Parent=Frame
    corner(btnBS,7)
    y = y + 36

    local bsOn = false
    local function setBs(v)
        bsOn = v; bsFrame.Visible = v
        if v then
            btnBS.Text="🌑  Black Screen   ON ✓"
            btnBS.BackgroundColor3=Color3.fromRGB(18,18,28)
            btnBS.TextColor3=Color3.fromRGB(200,195,230)
        else
            btnBS.Text="🌑  Black Screen   OFF"
            btnBS.BackgroundColor3=Color3.fromRGB(32,32,45)
            btnBS.TextColor3=Color3.fromRGB(140,135,160)
        end
    end

    btnBS.MouseButton1Click:Connect(function() setBs(not bsOn) end)
    bsClose.MouseButton1Click:Connect(function() setBs(false) end)
end

y = y + 4

-- Ajusta altura final do frame
Frame.Size = UDim2.fromOffset(260, y + 10)

print("[lz3s Invasion] Carregado! Arraste pela barra roxa.")
