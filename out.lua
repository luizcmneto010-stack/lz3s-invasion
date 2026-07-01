-- ============================================================
--  lz3s Invasion Menu (v2 - webhook corrigido)
--  Abas: INVASION | TREASURE | CAPSULAS | CONFIG | WEBHOOK
-- ============================================================

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local VirtualUser       = game:GetService("VirtualUser")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")

local function nav(raiz, ...)
    local atual = raiz
    for _, nome in ipairs({...}) do atual = atual:WaitForChild(nome) end
    return atual
end

local remotes             = require(nav(ReplicatedStorage, "src", "common", "remotes")).remotes
local invasionStore       = require(nav(ReplicatedStorage, "src", "common", "store", "gamemodes", "invasion"))
local getInvasionByPlayer = invasionStore.getInvasionByPlayer
local USER_KEY            = require(nav(ReplicatedStorage, "src", "common", "constants", "core")).USER_KEY

local charm    = require(nav(ReplicatedStorage, "rbxts_include", "node_modules", "@rbxts", "charm", "src"))
local computed = charm.computed
local subscribe = charm.subscribe

local ok_lobby, lobbyStore = pcall(function()
    return require(nav(ReplicatedStorage, "src", "common", "store", "gamemodes", "lobbies"))
end)
local lobbiesStore     = ok_lobby and lobbyStore.lobbiesStore     or nil
local getLobbyByPlayer = ok_lobby and lobbyStore.getLobbyByPlayer or nil

local ok_jp, joinPromptStore = pcall(function()
    return require(nav(game:GetService("StarterPlayer"),
        "app", "common", "components", "pages", "invasion", "hud", "join-prompt-store"))
end)
local clearInvasionJoinPrompt = ok_jp and joinPromptStore.clearInvasionJoinPrompt or nil

local getPlayerData            = require(nav(ReplicatedStorage, "src", "common", "store", "players", "datastore")).getPlayerData
local TREASURE_HUNT_TILE_COUNT = require(nav(ReplicatedStorage, "src", "common", "content", "events", "treasure-hunt")).TREASURE_HUNT_TILE_COUNT

local ok_items, itemsContent = pcall(function()
    return require(nav(ReplicatedStorage, "src", "common", "content", "items", "items")).itemsContent
end)
if not ok_items then itemsContent = {} end

local shopsContent = require(nav(ReplicatedStorage, "src", "common", "content", "purchases", "shops")).shopsContent

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

local NOTIF_ENABLED        = true
local NOTIF_INVASION_DISP  = true
local NOTIF_INVASION_START = true
local NOTIF_INVASION_END   = true
local NOTIF_ENTROU         = true
local NOTIF_TP             = true
local NOTIF_TREASURE       = true

-- ===================== ESTADO (CAPSULAS) =====================
local CAPS_SHOP_NAME   = "Dark Matter Invasion Shop"
local CAPS_ITEM_ID     = "Alien Capsule"
local CAPS_CURRENCY    = "SummerStar"
local CAPS_MAX_PER_REQ = 30000

local capsItemPrice = 50
do
    local ok, shop = pcall(function() return shopsContent[CAPS_SHOP_NAME] end)
    if ok and shop then
        for _, c in pairs(shop.items or {}) do
            if c.id == CAPS_ITEM_ID then capsItemPrice = c.price; break end
        end
    end
end

local capsNpcPath
do
    local ok, path = pcall(function()
        return workspace:WaitForChild("World"):WaitForChild("Map")
            :WaitForChild("Summer Isles"):WaitForChild("Components"):WaitForChild("SummerBaldHero")
    end)
    if ok then capsNpcPath = path end
end

local autoBuyEnabled  = false
local autoBuyLimit    = 0
local autoBuyThread   = nil
local autoOpenEnabled = false
local autoOpenLimit   = 0
local autoOpenThread  = nil
local isBuying        = false

-- ===================== ESTADO (WEBHOOK) =====================
local WEBHOOK_URL         = ""
local WH_CAPSULE_ENABLED  = true
local WH_INVASION_ENABLED = true

local invasionStartTime      = nil
local invasionCardVoteList   = {}
local invasionPasAntesInicio = 0
local _lastInvasionForWH     = nil

-- ============================================================
--  ANTI-AFK
-- ============================================================
Players.LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    task.wait(0.1)
    VirtualUser:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
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
    p:andThen(function() criandoInvasao = false end):catch(function() criandoInvasao = false end)
end

-- ============================================================
--  AUTO START
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
    if startRemote then logf("Auto Start: remote encontrado ("..startRemote.ClassName..")")
    else warn("[lz3s] Auto Start: remote 'lobbies.start' NAO encontrado!") end
end

local lastStarted = 0
RunService.Heartbeat:Connect(function()
    if not AUTO_START then return end
    if tick() - lastStarted < 3 then return end
    if getLobbyByPlayer == nil then return end
    local ok, lobby = pcall(getLobbyByPlayer, USER_KEY)
    if not ok or lobby == nil or lobby.owner ~= USER_KEY then return end
    local count = #(lobby.players or {})
    if count >= MIN_PLAYERS then
        lastStarted = tick()
        if startRemote ~= nil then
            local okF, errF = pcall(function()
                if startRemote:IsA("RemoteEvent") then startRemote:FireServer()
                elseif startRemote:IsA("RemoteFunction") then startRemote:InvokeServer() end
            end)
            if not okF then logf("Auto Start: erro "..tostring(errF)); pcall(function() remotes.lobbies.start:fire() end) end
        else pcall(function() remotes.lobbies.start:fire() end) end
    end
end)

-- ============================================================
--  AUTO CARD
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
        table.insert(invasionCardVoteList, tostring(cardId))
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
local lastJoin     = 0
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

local function buscarPosTurret(invasionFolder)
    local turret = invasionFolder:FindFirstChild("Main Base Turret")
    if turret == nil then
        local ok, result = pcall(function() return invasionFolder:WaitForChild("Main Base Turret", 15) end)
        if ok and result then turret = result end
    end
    if turret == nil then return nil, "Main Base Turret nao encontrado em "..invasionFolder.Name end
    if turret:IsA("Model") then
        local pp = turret.PrimaryPart
        if pp then return pp.Position, nil end
        local bp = turret:FindFirstChildWhichIsA("BasePart", true)
        if bp then return bp.Position, nil end
        local ok2, pivot = pcall(function() return turret:GetPivot().Position end)
        if ok2 then return pivot, nil end
        return nil, "Main Base Turret sem BasePart"
    elseif turret:IsA("BasePart") then
        return turret.Position, nil
    else
        local bp = turret:FindFirstChildWhichIsA("BasePart", true)
        if bp then return bp.Position, nil end
        return nil, "Main Base Turret tipo desconhecido: "..turret.ClassName
    end
end

local function tentarTpParaInvasion(filho)
    local nome = filho.Name
    if not nome:match("^invasion%-.") then return end
    if tpFeitoIds[nome] then return end
    if not AUTO_TP then return end
    task.spawn(function()
        logf("Auto TP: detectei "..nome..", aguardando turret...")
        local pos, err = buscarPosTurret(filho)
        if pos == nil then logf("Auto TP ERRO: "..tostring(err)); return end
        if not AUTO_TP then return end
        local char = Players.LocalPlayer.Character
        if char == nil then
            for _ = 1, 80 do task.wait(0.1); char = Players.LocalPlayer.Character; if char then break end end
        end
        if char == nil then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp == nil then return end
        tpFeitoIds[nome] = true
        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 10, 0))
        logf("Auto TP: teleportado para "..nome)
        if NOTIF_TP then criarNotif("tp", "Auto TP", "Teleportado para a torre!", 4) end
    end)
end

task.spawn(function()
    local mapFolder
    local ok = pcall(function()
        local world = workspace:WaitForChild("World", 30)
        mapFolder = world:WaitForChild("Map", 30)
    end)
    if not ok or mapFolder == nil then warn("[lz3s] Auto TP: workspace.World.Map nao encontrado"); return end
    for _, filho in ipairs(mapFolder:GetChildren()) do tentarTpParaInvasion(filho) end
    mapFolder.ChildAdded:Connect(function(filho) tentarTpParaInvasion(filho) end)
    mapFolder.ChildRemoved:Connect(function(filho)
        if tpFeitoIds[filho.Name] then tpFeitoIds[filho.Name] = nil end
    end)
end)

-- ============================================================
--  AUTO TREASURE
-- ============================================================
local DELAY_ENTRE_CAVADAS   = 0.6
local CHECK_INTERVAL_SEM_PA = 2
local treasureRodando       = false
local avisouSemPas          = false

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

local function getNomeItem(itemId)
    if itemId == nil then return "?" end
    local c = itemsContent[itemId]
    return c and c.displayName or tostring(itemId)
end

local function formatarRecompensa(reward)
    if reward == nil then return "Item desconhecido" end
    local nome = getNomeItem(reward.id or reward)
    local amount = reward.amount
    return (amount and amount > 1) and (nome.." x"..tostring(amount)) or nome
end

local function cavarUmaVez()
    local tile = escolherTileAleatoria()
    if tile == nil then return end
    local ok, p = pcall(function() return remotes.treasureHunt.dig:request(tile) end)
    if not ok then logf("Auto Treasure erro: "..tostring(p)); return end
    p:andThen(function(r)
        if r and r.reason then
            logf("Auto Treasure: "..tostring(r.reason))
        else
            if NOTIF_TREASURE then
                local pasRestantes = getQuantidadeDePas()
                local recompensas = {}
                if r and r.revealed then
                    for _, rev in ipairs(r.revealed) do
                        if rev and rev.reward then table.insert(recompensas, formatarRecompensa(rev.reward)) end
                    end
                elseif r and r.reward then
                    table.insert(recompensas, formatarRecompensa(r.reward))
                end
                local recompensaTexto = #recompensas > 0 and table.concat(recompensas, ", ") or "Recompensa obtida"
                criarNotifTreasure("Tesouro Cavado", recompensaTexto, pasRestantes)
            end
        end
    end):catch(function(err) logf("Auto Treasure promise: "..tostring(err)) end)
end

local function iniciarLoopTreasure()
    if treasureRodando then return end
    treasureRodando = true
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
                    logf("Auto Treasure: sem pas")
                    criarNotif("treasure", "Sem Pas!", "Compre mais pas para continuar cavando.", 5)
                end
                task.wait(CHECK_INTERVAL_SEM_PA)
            end
        end
        treasureRodando = false
    end)
end

-- ============================================================
--  CÁPSULAS
-- ============================================================
local function capsGetCurrency()
    local d = getPlayerData(USER_KEY)
    if d == nil or d.items == nil then return 0 end
    local e = d.items[CAPS_CURRENCY]
    return e and e.amount or 0
end

local function capsGetOwned()
    local d = getPlayerData(USER_KEY)
    if d == nil or d.items == nil then return 0 end
    local e = d.items[CAPS_ITEM_ID]
    return e and e.amount or 0
end

local function capsGetMaxAffordable()
    if capsItemPrice <= 0 then return 0 end
    return math.floor(capsGetCurrency() / capsItemPrice)
end

local function capsTeleportAndBuy(amount)
    local character = Players.LocalPlayer.Character
    if character == nil then return nil end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart == nil then return nil end
    local originalCFrame = rootPart.CFrame
    if capsNpcPath then
        local ok, npcCF = pcall(function() return capsNpcPath:GetPivot() end)
        if ok then rootPart.CFrame = npcCF * CFrame.new(0, 0, 5); task.wait(0.3) end
    end
    local request = remotes.shops.purchase:request(CAPS_SHOP_NAME, CAPS_ITEM_ID, amount)
    request:andThen(function()
        if rootPart and rootPart.Parent then rootPart.CFrame = originalCFrame end
    end)
    return request
end

local function capsBuyMaxOnce()
    if isBuying then return false end
    local maxAffordable = capsGetMaxAffordable()
    if maxAffordable <= 0 then return false end
    isBuying = true
    local amount = math.min(maxAffordable, CAPS_MAX_PER_REQ)
    local request = capsTeleportAndBuy(amount)
    if request == nil then isBuying = false; return false end
    local success = false
    request:andThen(function(result) success = result == true; isBuying = false end)
             :catch(function() isBuying = false end)
    while isBuying do task.wait(0.1) end
    return success
end

-- ============================================================
--  WEBHOOK — funções core
-- ============================================================
local function wh_getInvTotal(id)
    local d = getPlayerData(USER_KEY)
    if d == nil or d.items == nil then return 0 end
    local e = d.items[id]
    return e and e.amount or 0
end

local function wh_footer()
    return { text = "lz3s Invasion v2" }
end

local http_req = (typeof(syn)=="table" and syn.request)
    or (typeof(request)=="function" and request)
    or (typeof(http_request)=="function" and http_request)
    or nil

local function wh_send(payload)
    if WEBHOOK_URL == "" then return end
    if http_req == nil then logf("Webhook: executor nao suporta HTTP requests"); return end
    task.spawn(function()
        local ok, err = pcall(function()
            http_req({
                Url     = WEBHOOK_URL,
                Method  = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body    = HttpService:JSONEncode(payload),
            })
        end)
        if not ok then logf("Webhook erro: "..tostring(err)) end
    end)
end

local function wh_enviarCapsulas(qtdAberta, resultados)
    if not WH_CAPSULE_ENABLED or WEBHOOK_URL == "" then return end
    local agrupado = {}; local ordem = {}
    if resultados then
        for _, r in ipairs(resultados) do
            local id  = (type(r)=="table" and r.id) or tostring(r)
            local amt = (type(r)=="table" and r.amount) or 1
            if not agrupado[id] then agrupado[id] = 0; table.insert(ordem, id) end
            agrupado[id] = agrupado[id] + amt
        end
    end
    local fields = {}
    for _, id in ipairs(ordem) do
        local gained = agrupado[id]
        local total  = wh_getInvTotal(id)
        table.insert(fields, {
            name   = getNomeItem(id),
            value  = "+"..gained.." obtido — "..total.." no inventario",
            inline = false,
        })
    end
    if #fields == 0 then
        table.insert(fields, { name = "Resultado", value = "Sem itens registrados", inline = false })
    end
    wh_send({ embeds = {{
        title       = "Capsulas Abertas",
        description = tostring(qtdAberta).." "..CAPS_ITEM_ID.." abertas — restam "..tostring(capsGetOwned()).." no inventario",
        color       = 0x50BEC8,
        fields      = fields,
        footer      = wh_footer(),
    }}})
end

local function wh_extrairDropsCapsulas(result)
    if result == nil then return {} end
    local lista = {}
    if result.items then
        for _, item in ipairs(result.items) do if item and item.id then table.insert(lista, item) end end
    elseif result.rewards then
        for _, r in ipairs(result.rewards) do if r and r.id then table.insert(lista, r) end end
    end
    return lista
end

local function capsOpenAmount(amount)
    local owned = capsGetOwned()
    if owned <= 0 or amount <= 0 then return end
    amount = math.min(amount, owned)
    remotes.items.openCapsule:request(CAPS_ITEM_ID, amount):andThen(function(result)
        if result == nil or result.success ~= true then return end
        logf("Capsulas abertas: "..tostring(result.opened or amount))
        local drops = wh_extrairDropsCapsulas(result)
        wh_enviarCapsulas(result.opened or amount, drops)
    end)
end

local function capsOpenAll()
    capsOpenAmount(capsGetOwned())
end

local function capsStartAutoBuyLoop()
    if autoBuyThread ~= nil then return end
    autoBuyThread = task.spawn(function()
        while autoBuyEnabled do
            if autoBuyLimit > 0 and capsGetCurrency() >= autoBuyLimit then capsBuyMaxOnce() end
            task.wait(2)
        end
        autoBuyThread = nil
    end)
end

local function capsStartAutoOpenLoop()
    if autoOpenThread ~= nil then return end
    autoOpenThread = task.spawn(function()
        while autoOpenEnabled do
            if autoOpenLimit > 0 and capsGetOwned() >= autoOpenLimit then capsOpenAll() end
            task.wait(2)
        end
        autoOpenThread = nil
    end)
end

-- ============================================================
--  WEBHOOK — relatório de invasion
-- ============================================================
local function wh_registrarInicioInvasion()
    invasionStartTime      = tick()
    invasionCardVoteList   = {}
    invasionPasAntesInicio = getQuantidadeDePas()
end

local CURRENCY_DROP_NAME = "Summer Star Remnant"

local function somarStarRemnant(invasion)
    if invasion==nil or invasion.players==nil then return 0 end
    local dados = invasion.players[USER_KEY]
    if dados==nil or dados.drops==nil then return 0 end
    local total = 0
    for _, drop in ipairs(dados.drops) do
        if drop and drop.id==CURRENCY_DROP_NAME then total += (drop.amount or 0) end
    end
    return total
end

local function getStarRemnantTotal()
    local ok, d = pcall(getPlayerData, USER_KEY)
    if not ok or d==nil or d.items==nil then return nil end
    local item = d.items[CURRENCY_DROP_NAME]
    return item and item.amount or 0
end

local function wh_enviarRelatorioInvasion(invasion)
    if not WH_INVASION_ENABLED or WEBHOOK_URL == "" then return end
    if invasionStartTime == nil then return end

    local durSecs = math.floor(tick() - invasionStartTime)
    local durTxt  = math.floor(durSecs/60).."m "..(durSecs%60).."s"

    local dropFields = {}
    if invasion and invasion.players then
        local dados = invasion.players[USER_KEY]
        if dados and dados.drops then
            local agrupado = {}; local ordem = {}
            for _, drop in ipairs(dados.drops) do
                if drop and drop.id then
                    if not agrupado[drop.id] then agrupado[drop.id] = 0; table.insert(ordem, drop.id) end
                    agrupado[drop.id] = agrupado[drop.id] + (drop.amount or 1)
                end
            end
            for _, id in ipairs(ordem) do
                table.insert(dropFields, {
                    name   = getNomeItem(id),
                    value  = "+"..agrupado[id].." — "..wh_getInvTotal(id).." no inv.",
                    inline = true,
                })
            end
        end
    end
    if #dropFields == 0 then
        table.insert(dropFields, { name = "Drops", value = "Nenhum item dropado", inline = false })
    end

    local pasUsadas  = math.max(0, invasionPasAntesInicio - getQuantidadeDePas())
    local cartasTxt  = #invasionCardVoteList > 0 and table.concat(invasionCardVoteList, " > ") or "Nenhuma"
    local numJogs    = 0
    if invasion and invasion.players then for _ in pairs(invasion.players) do numJogs += 1 end end
    local starsGanhas = somarStarRemnant(invasion)
    local starTotal   = getStarRemnantTotal() or 0

    local desc = "Concluida\n"
              .. "Duracao: "..durTxt.."\n"
              .. "Jogadores: "..numJogs.."\n"
              .. "Stars: +"..starsGanhas.." — total "..starTotal.."\n"
              .. "Pas cavadas: "..pasUsadas

    local allFields = {{ name = "Cartas votadas", value = cartasTxt, inline = false }}
    for _, f in ipairs(dropFields) do table.insert(allFields, f) end

    wh_send({ embeds = {{
        title       = (invasion and invasion.name or "Invasion").." — Relatorio",
        description = desc,
        color       = 0x50C878,
        fields      = allFields,
        footer      = wh_footer(),
    }}})
    invasionStartTime = nil
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
        WEBHOOK_URL=WEBHOOK_URL,
        WH_CAPSULE_ENABLED=WH_CAPSULE_ENABLED,
        WH_INVASION_ENABLED=WH_INVASION_ENABLED,
    }
end

local function salvarConfig()
    if not fileFuncsDisponiveis() then warn("[lz3s] writefile nao disponivel."); return false end
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
-- ============================================================
local notifGui
local NOTIF_W=280; local NOTIF_H=64; local NOTIF_GAP=8
local NOTIF_PAD_R=14; local NOTIF_PAD_B=14

do
    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
    local ex = pg:FindFirstChild("lz3sNotif")
    if ex then ex:Destroy() end
    notifGui = Instance.new("ScreenGui")
    notifGui.Name="lz3sNotif"; notifGui.IgnoreGuiInset=true
    notifGui.DisplayOrder=998; notifGui.ResetOnSpawn=false; notifGui.Parent=pg
end

local NOTIF_TYPES = {
    invasion = { bar=Color3.fromRGB(120,80,230)  },
    start    = { bar=Color3.fromRGB(80,200,120)  },
    finish   = { bar=Color3.fromRGB(200,160,50)  },
    entrou   = { bar=Color3.fromRGB(60,160,230)  },
    tp       = { bar=Color3.fromRGB(160,90,240)  },
    treasure = { bar=Color3.fromRGB(220,170,40)  },
    capsule  = { bar=Color3.fromRGB(50,190,200)  },
    info     = { bar=Color3.fromRGB(100,100,130) },
}

function criarNotif(tipo, titulo, msg, duracao)
    if not NOTIF_ENABLED then return end
    duracao = duracao or 4
    for _, slot in ipairs(notifGui:GetChildren()) do
        if slot:IsA("Frame") then
            TweenService:Create(slot, TweenInfo.new(0.25,Enum.EasingStyle.Quint), {
                Position = UDim2.new(1, slot.Position.X.Offset, 1, slot.Position.Y.Offset-(NOTIF_H+NOTIF_GAP))
            }):Play()
        end
    end
    local def = NOTIF_TYPES[tipo] or NOTIF_TYPES.info
    local frame = Instance.new("Frame")
    frame.Size=UDim2.fromOffset(NOTIF_W,NOTIF_H)
    frame.Position=UDim2.new(1,NOTIF_W+20,1,-(NOTIF_PAD_B+NOTIF_H))
    frame.BackgroundColor3=Color3.fromRGB(18,17,26); frame.BorderSizePixel=0; frame.Parent=notifGui
    do
        local fc=Instance.new("UICorner"); fc.CornerRadius=UDim.new(0,10); fc.Parent=frame
        local fs=Instance.new("UIStroke"); fs.Color=Color3.fromRGB(55,45,90); fs.Thickness=1; fs.Parent=frame
        local bar=Instance.new("Frame"); bar.Size=UDim2.new(0,4,1,-16); bar.Position=UDim2.fromOffset(0,8)
        bar.BackgroundColor3=def.bar; bar.BorderSizePixel=0; bar.Parent=frame
        Instance.new("UICorner",bar).CornerRadius=UDim.new(0,4)
        local dot=Instance.new("Frame"); dot.Size=UDim2.fromOffset(8,8); dot.Position=UDim2.fromOffset(20,14)
        dot.BackgroundColor3=def.bar; dot.BorderSizePixel=0; dot.Parent=frame
        Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)
        local tLbl=Instance.new("TextLabel"); tLbl.Size=UDim2.new(1,-44,0,18); tLbl.Position=UDim2.fromOffset(40,10)
        tLbl.BackgroundTransparency=1; tLbl.Text=titulo; tLbl.TextColor3=Color3.fromRGB(230,225,250)
        tLbl.TextSize=13; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left
        tLbl.TextTruncate=Enum.TextTruncate.AtEnd; tLbl.Parent=frame
        local mLbl=Instance.new("TextLabel"); mLbl.Size=UDim2.new(1,-52,0,28); mLbl.Position=UDim2.fromOffset(40,28)
        mLbl.BackgroundTransparency=1; mLbl.Text=msg; mLbl.TextColor3=Color3.fromRGB(160,155,185)
        mLbl.TextSize=11; mLbl.Font=Enum.Font.Gotham; mLbl.TextXAlignment=Enum.TextXAlignment.Left
        mLbl.TextWrapped=true; mLbl.Parent=frame
        local pBg=Instance.new("Frame"); pBg.Size=UDim2.new(1,-16,0,2); pBg.Position=UDim2.new(0,8,1,-6)
        pBg.BackgroundColor3=Color3.fromRGB(40,38,58); pBg.BorderSizePixel=0; pBg.Parent=frame
        Instance.new("UICorner",pBg).CornerRadius=UDim.new(1,0)
        local prog=Instance.new("Frame"); prog.Size=UDim2.fromScale(1,1); prog.BackgroundColor3=def.bar
        prog.BorderSizePixel=0; prog.Parent=pBg
        Instance.new("UICorner",prog).CornerRadius=UDim.new(1,0)
        TweenService:Create(frame,TweenInfo.new(0.3,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{
            Position=UDim2.new(1,-(NOTIF_W+NOTIF_PAD_R),1,-(NOTIF_PAD_B+NOTIF_H))
        }):Play()
        TweenService:Create(prog,TweenInfo.new(duracao,Enum.EasingStyle.Linear),{Size=UDim2.fromScale(0,1)}):Play()
    end
    task.delay(duracao, function()
        TweenService:Create(frame,TweenInfo.new(0.25,Enum.EasingStyle.Quint,Enum.EasingDirection.In),{
            Position=UDim2.new(1,NOTIF_W+20,1,-(NOTIF_PAD_B+NOTIF_H))
        }):Play()
        task.wait(0.3); frame:Destroy()
    end)
end

local TNOTIF_W=290; local TNOTIF_H=78

function criarNotifTreasure(titulo, itemTexto, pasRestantes)
    if not NOTIF_ENABLED or not NOTIF_TREASURE then return end
    local duracao = 3.5
    for _, slot in ipairs(notifGui:GetChildren()) do
        if slot:IsA("Frame") then
            TweenService:Create(slot, TweenInfo.new(0.25,Enum.EasingStyle.Quint), {
                Position = UDim2.new(1, slot.Position.X.Offset, 1, slot.Position.Y.Offset-(TNOTIF_H+NOTIF_GAP))
            }):Play()
        end
    end
    local BAR_COLOR  = Color3.fromRGB(220,170,40)
    local ITEM_COLOR = Color3.fromRGB(255,220,80)
    local PAS_COLOR  = Color3.fromRGB(140,215,140)
    local frame = Instance.new("Frame")
    frame.Size=UDim2.fromOffset(TNOTIF_W,TNOTIF_H)
    frame.Position=UDim2.new(1,TNOTIF_W+20,1,-(NOTIF_PAD_B+TNOTIF_H))
    frame.BackgroundColor3=Color3.fromRGB(20,18,10); frame.BorderSizePixel=0; frame.Parent=notifGui
    do
        Instance.new("UICorner",frame).CornerRadius=UDim.new(0,10)
        local fs=Instance.new("UIStroke",frame); fs.Color=Color3.fromRGB(100,75,20); fs.Thickness=1
        local bar=Instance.new("Frame",frame); bar.Size=UDim2.new(0,4,1,-16); bar.Position=UDim2.fromOffset(0,8)
        bar.BackgroundColor3=BAR_COLOR; bar.BorderSizePixel=0; Instance.new("UICorner",bar).CornerRadius=UDim.new(0,4)
        local dot=Instance.new("Frame",frame); dot.Size=UDim2.fromOffset(10,10); dot.Position=UDim2.fromOffset(18,12)
        dot.BackgroundColor3=BAR_COLOR; dot.BorderSizePixel=0; Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)
        local tLbl=Instance.new("TextLabel",frame); tLbl.Size=UDim2.new(1,-44,0,16); tLbl.Position=UDim2.fromOffset(38,8)
        tLbl.BackgroundTransparency=1; tLbl.Text=titulo; tLbl.TextColor3=Color3.fromRGB(240,220,160)
        tLbl.TextSize=12; tLbl.Font=Enum.Font.GothamBold; tLbl.TextXAlignment=Enum.TextXAlignment.Left
        tLbl.TextTruncate=Enum.TextTruncate.AtEnd
        local ct = #itemTexto>30 and itemTexto:sub(1,28).."..." or itemTexto
        local itemLbl=Instance.new("TextLabel",frame); itemLbl.Size=UDim2.new(1,-44,0,20); itemLbl.Position=UDim2.fromOffset(38,26)
        itemLbl.BackgroundTransparency=1; itemLbl.Text=ct; itemLbl.TextColor3=ITEM_COLOR
        itemLbl.TextSize=13; itemLbl.Font=Enum.Font.GothamBold; itemLbl.TextXAlignment=Enum.TextXAlignment.Left
        itemLbl.TextTruncate=Enum.TextTruncate.AtEnd
        local pasLbl=Instance.new("TextLabel",frame); pasLbl.Size=UDim2.new(1,-44,0,14); pasLbl.Position=UDim2.fromOffset(38,50)
        pasLbl.BackgroundTransparency=1; pasLbl.Text="Pas restantes: "..tostring(pasRestantes)
        pasLbl.TextColor3=PAS_COLOR; pasLbl.TextSize=11; pasLbl.Font=Enum.Font.Gotham
        pasLbl.TextXAlignment=Enum.TextXAlignment.Left
        local pBg=Instance.new("Frame",frame); pBg.Size=UDim2.new(1,-16,0,2); pBg.Position=UDim2.new(0,8,1,-5)
        pBg.BackgroundColor3=Color3.fromRGB(50,40,10); pBg.BorderSizePixel=0; Instance.new("UICorner",pBg).CornerRadius=UDim.new(1,0)
        local prog=Instance.new("Frame",pBg); prog.Size=UDim2.fromScale(1,1); prog.BackgroundColor3=BAR_COLOR; prog.BorderSizePixel=0
        Instance.new("UICorner",prog).CornerRadius=UDim.new(1,0)
        TweenService:Create(frame,TweenInfo.new(0.3,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{
            Position=UDim2.new(1,-(TNOTIF_W+NOTIF_PAD_R),1,-(NOTIF_PAD_B+TNOTIF_H))
        }):Play()
        TweenService:Create(prog,TweenInfo.new(duracao,Enum.EasingStyle.Linear),{Size=UDim2.fromScale(0,1)}):Play()
    end
    task.delay(duracao, function()
        TweenService:Create(frame,TweenInfo.new(0.25,Enum.EasingStyle.Quint,Enum.EasingDirection.In),{
            Position=UDim2.new(1,TNOTIF_W+20,1,-(NOTIF_PAD_B+TNOTIF_H))
        }):Play()
        task.wait(0.3); frame:Destroy()
    end)
end

-- ============================================================
--  Watcher: lobbies disponíveis
-- ============================================================
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
                criarNotif("invasion","Invasion disponivel",
                    "Lobby aberto - "..(#(lobby.players or {})).."/".. (lobby.maxPlayers or 4).." jogadores", 5)
            end
        end
        for id in pairs(jaNotifoiLobby) do if all[id]==nil then jaNotifoiLobby[id]=nil end end
    end
end)

-- ============================================================
--  Watcher principal: invasion (notifs + webhook)
--
--  LÓGICA SIMPLES, EM LOOP:
--  1. Fica em loop tentando pegar a invasion atual do jogador
--     (getInvasionByPlayer). Enquanto nao tiver nenhuma, so espera.
--  2. Ao achar uma invasion, pega o id e fica em loop tentando achar
--     o model dela em workspace.World.Map["invasion-"..id].
--  3. Ao achar o model, fica em loop MONITORANDO ele (checando o
--     Parent a cada segundo, e atualizando o snapshot de drops).
--  4. Quando o model.Parent vira nil (foi excluido = invasion
--     acabou de verdade), manda o relatorio pro webhook.
--  5. Espera o jogador sair do store, e volta pro passo 1.
--
--  So manda o webhook quando o MODEL da invasion e excluido.
--  Nunca depende de clicar em Continue.
-- ============================================================

local lastStarQtd       = 0
local _lastInvasionForWH = nil

task.spawn(function()
    while true do
        -- PASSO 1: fica em loop tentando pegar a invasion do jogador
        local invasion = getInvasionByPlayer(USER_KEY)
        while invasion == nil do
            task.wait(1)
            invasion = getInvasionByPlayer(USER_KEY)
        end

        local invasionId = invasion.id
        _lastInvasionForWH = invasion
        lastStarQtd = somarStarRemnant(invasion)
        wh_registrarInicioInvasion()
        logf("Invasion detectada: " .. tostring(invasionId):sub(1,8))

        if NOTIF_ENTROU then
            criarNotif("entrou", "Entrou na invasion", invasion.name or "Dark Matter Invasion", 4)
        end
        if NOTIF_INVASION_START then
            criarNotif("start", "Invasion comecou", "Boa sorte na batalha.", 4)
        end

        -- PASSO 2: fica em loop tentando achar o model dessa invasion no mapa
        local mapFolder
        pcall(function()
            mapFolder = workspace:WaitForChild("World"):WaitForChild("Map")
        end)

        local modelName = "invasion-" .. tostring(invasionId)
        local model = nil
        if mapFolder then
            while model == nil and getInvasionByPlayer(USER_KEY) ~= nil do
                model = mapFolder:FindFirstChild(modelName)
                if model == nil then task.wait(1) end
            end
        end

        if model ~= nil then
            -- PASSO 3: fica em loop monitorando o model ate ele ser excluido
            while model.Parent ~= nil do
                local invAtual = getInvasionByPlayer(USER_KEY)
                if invAtual ~= nil then
                    _lastInvasionForWH = invAtual
                    lastStarQtd = somarStarRemnant(invAtual)
                end
                task.wait(1)
            end

            -- PASSO 4: model foi excluido = invasion acabou de verdade -> manda webhook
            logf("Invasion " .. tostring(invasionId):sub(1,8) .. " finalizada (model excluido)")
            if NOTIF_INVASION_END then
                local msg = "A invasion terminou."
                local total = getStarRemnantTotal()
                if lastStarQtd > 0 then
                    msg = msg .. " Ganhou: " .. lastStarQtd
                    if total ~= nil then msg = msg .. " | Total: " .. total end
                end
                criarNotif("finish", "Invasion encerrada", msg, 7)
            end
            task.wait(1) -- da tempo do servidor consolidar os drops finais
            wh_enviarRelatorioInvasion(_lastInvasionForWH)
        else
            logf("Invasion " .. tostring(invasionId):sub(1,8) .. ": model nunca apareceu, pulando relatorio")
        end

        -- PASSO 5: espera sair completamente do store antes de procurar a proxima
        while getInvasionByPlayer(USER_KEY) ~= nil do task.wait(1) end
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
    local existing  = playerGui:FindFirstChild("AFKScreen")
    if existing then existing:Destroy() end

    blackScreenGui = Instance.new("ScreenGui")
    blackScreenGui.Name="AFKScreen"; blackScreenGui.IgnoreGuiInset=true
    blackScreenGui.DisplayOrder=999; blackScreenGui.ResetOnSpawn=false
    blackScreenGui.Enabled=false; blackScreenGui.Parent=playerGui

    local bg=Instance.new("Frame"); bg.Size=UDim2.new(1,0,1,0)
    bg.BackgroundColor3=Color3.fromRGB(0,0,0); bg.BorderSizePixel=0
    bg.ZIndex=1; bg.ClipsDescendants=true; bg.Parent=blackScreenGui

    local rainContainer=Instance.new("Frame"); rainContainer.Size=UDim2.new(1,0,1,0)
    rainContainer.BackgroundTransparency=1; rainContainer.ZIndex=1; rainContainer.Parent=bg

    local function createRaindrop()
        local drop=Instance.new("Frame"); drop.Size=UDim2.new(0,2,0,math.random(15,35))
        drop.BackgroundColor3=Color3.fromRGB(255,255,255); drop.BackgroundTransparency=0.75
        drop.BorderSizePixel=0; drop.ZIndex=1
        drop.Position=UDim2.new(math.random(0,1000)/1000,0,-0.1,0); drop.Parent=rainContainer
        local tw=TweenService:Create(drop,TweenInfo.new(math.random(15,25)/10,Enum.EasingStyle.Linear),{
            Position=UDim2.new(drop.Position.X.Scale,0,1.1,0)
        }); tw:Play(); tw.Completed:Connect(function() drop:Destroy() end)
    end

    local function startRainLoop()
        if blackScreenRainRunning then return end
        blackScreenRainRunning=true
        task.spawn(function()
            while blackScreenRainRunning do createRaindrop(); task.wait(math.random(15,30)/100) end
        end)
    end

    local title=Instance.new("TextLabel"); title.Size=UDim2.new(0.5,0,0.08,0)
    title.Position=UDim2.new(0.25,0,0.46,0); title.BackgroundTransparency=1
    title.Text="lz3s AFK"; title.TextColor3=Color3.fromRGB(255,255,255)
    title.Font=Enum.Font.Fondamento; title.TextScaled=true; title.ZIndex=2; title.Parent=bg

    task.spawn(function()
        while title.Parent do
            if blackScreenGui.Enabled then
                local fo=TweenService:Create(title,TweenInfo.new(1.8,Enum.EasingStyle.Sine),{TextTransparency=0.35})
                fo:Play(); fo.Completed:Wait()
                local fi=TweenService:Create(title,TweenInfo.new(1.8,Enum.EasingStyle.Sine),{TextTransparency=0})
                fi:Play(); fi.Completed:Wait()
            else task.wait(0.5) end
        end
    end)

    local closeBtn=Instance.new("TextButton"); closeBtn.Size=UDim2.new(0,44,0,44)
    closeBtn.Position=UDim2.new(1,-64,0,20); closeBtn.BackgroundColor3=Color3.fromRGB(30,30,30)
    closeBtn.Text="X"; closeBtn.TextColor3=Color3.fromRGB(255,255,255)
    closeBtn.Font=Enum.Font.GothamBold; closeBtn.TextScaled=true
    closeBtn.ZIndex=3; closeBtn.AutoButtonColor=true; closeBtn.Parent=bg
    local cc=Instance.new("UICorner"); cc.CornerRadius=UDim.new(1,0); cc.Parent=closeBtn
    local cs=Instance.new("UIStroke"); cs.Color=Color3.fromRGB(255,255,255); cs.Thickness=1.2; cs.Transparency=0.3; cs.Parent=closeBtn

    setBlackScreen=function(v)
        BLACK_SCREEN=v; blackScreenGui.Enabled=v
        if v then startRainLoop() else blackScreenRainRunning=false end
        if BLACK_SCREEN_TOGGLE_UPDATE then BLACK_SCREEN_TOGGLE_UPDATE(v) end
    end
    closeBtn.MouseButton1Click:Connect(function() setBlackScreen(false) end)
end

-- ============================================================
--  GUI PRINCIPAL
-- ============================================================
local ScreenGui=Instance.new("ScreenGui")
ScreenGui.Name="lz3sInvasion"; ScreenGui.ResetOnSpawn=false
ScreenGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
local okGui=pcall(function() ScreenGui.Parent=game:GetService("CoreGui") end)
if not okGui then ScreenGui.Parent=Players.LocalPlayer:WaitForChild("PlayerGui") end

local function corner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 10); c.Parent=p; return c end
local function stroke(p,col,th) local s=Instance.new("UIStroke"); s.Color=col or Color3.fromRGB(90,70,170); s.Thickness=th or 1.5; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=p; return s end
local function divider(parent,posY) local f=Instance.new("Frame"); f.Size=UDim2.new(1,0,0,1); f.Position=UDim2.fromOffset(0,posY); f.BackgroundColor3=Color3.fromRGB(50,40,90); f.BackgroundTransparency=0.3; f.BorderSizePixel=0; f.Parent=parent; return posY+10 end

local PALETTE = {
    bg=Color3.fromRGB(16,15,24), panel=Color3.fromRGB(22,21,32), titlebar=Color3.fromRGB(38,22,84),
    accent=Color3.fromRGB(125,90,235), accentDim=Color3.fromRGB(90,65,170),
    toggleOff=Color3.fromRGB(34,33,47), toggleOffTx=Color3.fromRGB(150,145,170),
    toggleOnTx=Color3.fromRGB(170,255,195), textMain=Color3.fromRGB(225,218,245),
    textDim=Color3.fromRGB(150,142,180), danger=Color3.fromRGB(120,35,45),
}

local WINDOW_W=360; local WINDOW_H=460
local Frame=Instance.new("Frame"); Frame.Name="Main"
Frame.Size=UDim2.fromOffset(WINDOW_W,WINDOW_H); Frame.Position=UDim2.new(0,24,0.5,-230)
Frame.BackgroundColor3=PALETTE.bg; Frame.BorderSizePixel=0; Frame.ClipsDescendants=true
Frame.Active=true; Frame.Draggable=true; Frame.Parent=ScreenGui
corner(Frame,14); stroke(Frame,PALETTE.accentDim,1.5)

local TitleBar=Instance.new("Frame"); TitleBar.Size=UDim2.new(1,0,0,44)
TitleBar.BackgroundColor3=PALETTE.titlebar; TitleBar.BorderSizePixel=0; TitleBar.Parent=Frame; corner(TitleBar,14)
do
    local patch=Instance.new("Frame"); patch.Size=UDim2.new(1,0,0,14); patch.Position=UDim2.new(0,0,1,-14)
    patch.BackgroundColor3=PALETTE.titlebar; patch.BorderSizePixel=0; patch.Parent=TitleBar
    local TitleDot=Instance.new("Frame"); TitleDot.Size=UDim2.fromOffset(8,8); TitleDot.Position=UDim2.fromOffset(14,18)
    TitleDot.BackgroundColor3=PALETTE.accent; TitleDot.BorderSizePixel=0; TitleDot.Parent=TitleBar; corner(TitleDot,4)
    local TitleLbl=Instance.new("TextLabel"); TitleLbl.Size=UDim2.new(1,-160,1,0); TitleLbl.Position=UDim2.fromOffset(32,0)
    TitleLbl.BackgroundTransparency=1; TitleLbl.Text="lz3s Invasion"; TitleLbl.TextColor3=PALETTE.textMain
    TitleLbl.TextSize=16; TitleLbl.Font=Enum.Font.GothamBold; TitleLbl.TextXAlignment=Enum.TextXAlignment.Left; TitleLbl.Parent=TitleBar
    local AfkDot=Instance.new("Frame"); AfkDot.Size=UDim2.fromOffset(8,8); AfkDot.Position=UDim2.new(1,-96,0.5,-4)
    AfkDot.BackgroundColor3=Color3.fromRGB(90,220,130); AfkDot.BorderSizePixel=0; AfkDot.Parent=TitleBar; corner(AfkDot,4)
    local AfkLbl=Instance.new("TextLabel"); AfkLbl.Size=UDim2.fromOffset(78,20); AfkLbl.Position=UDim2.new(1,-84,0.5,-10)
    AfkLbl.BackgroundTransparency=1; AfkLbl.Text="Anti-AFK"; AfkLbl.TextColor3=Color3.fromRGB(150,220,170)
    AfkLbl.TextSize=11; AfkLbl.Font=Enum.Font.GothamBold; AfkLbl.TextXAlignment=Enum.TextXAlignment.Left; AfkLbl.Parent=TitleBar
end
local MinimizeBtn=Instance.new("TextButton"); MinimizeBtn.Size=UDim2.fromOffset(28,28)
MinimizeBtn.Position=UDim2.new(1,-34,0.5,-14); MinimizeBtn.BackgroundColor3=Color3.fromRGB(50,35,95)
MinimizeBtn.BorderSizePixel=0; MinimizeBtn.Text="-"; MinimizeBtn.TextColor3=PALETTE.textMain
MinimizeBtn.Font=Enum.Font.GothamBold; MinimizeBtn.TextSize=16; MinimizeBtn.Parent=TitleBar; corner(MinimizeBtn,7)

local TabBar=Instance.new("Frame"); TabBar.Size=UDim2.new(1,-24,0,36); TabBar.Position=UDim2.fromOffset(12,54)
TabBar.BackgroundColor3=PALETTE.panel; TabBar.BorderSizePixel=0; TabBar.Parent=Frame; corner(TabBar,10)
do
    local tp2=Instance.new("UIPadding"); tp2.PaddingLeft=UDim.new(0,4); tp2.PaddingRight=UDim.new(0,4)
    tp2.PaddingTop=UDim.new(0,4); tp2.PaddingBottom=UDim.new(0,4); tp2.Parent=TabBar
    local tll=Instance.new("UIListLayout"); tll.FillDirection=Enum.FillDirection.Horizontal
    tll.Padding=UDim.new(0,3); tll.SortOrder=Enum.SortOrder.LayoutOrder; tll.Parent=TabBar
end

local PagesHolder=Instance.new("ScrollingFrame")
PagesHolder.Size=UDim2.new(1,-24,1,-102); PagesHolder.Position=UDim2.fromOffset(12,98)
PagesHolder.BackgroundTransparency=1; PagesHolder.BorderSizePixel=0
PagesHolder.ScrollBarThickness=4; PagesHolder.ScrollBarImageColor3=PALETTE.accentDim
PagesHolder.CanvasSize=UDim2.new(0,0,0,0); PagesHolder.AutomaticCanvasSize=Enum.AutomaticSize.Y
PagesHolder.Parent=Frame

local PAGE_DEFS = {
    {key="INVASION", label="Invasion"},
    {key="TREASURE", label="Treasure"},
    {key="CAPSULAS", label="Capsulas"},
    {key="CONFIG",   label="Config"},
    {key="WEBHOOK",  label="Webhook"},
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
    btn.TextSize=11; btn.Font=Enum.Font.GothamBold; btn.Parent=TabBar
    corner(btn,7); tabButtons[def.key]=btn
    local page=Instance.new("Frame"); page.Name=def.key
    page.Size=UDim2.new(1,0,0,0); page.AutomaticSize=Enum.AutomaticSize.Y
    page.BackgroundTransparency=1; page.Visible=false; page.Parent=PagesHolder
    pageFrames[def.key]=page
    btn.MouseButton1Click:Connect(function() selectTab(def.key) end)
end

-- widget helpers
local function sectionHeader(parent,posY,text)
    local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,0,20); lbl.Position=UDim2.fromOffset(0,posY)
    lbl.BackgroundTransparency=1; lbl.Text=text; lbl.TextColor3=PALETTE.accent
    lbl.TextSize=13; lbl.Font=Enum.Font.GothamBold; lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=parent
    return divider(parent,posY+22)
end

local function makeToggle(parent,posY,label,onToggle)
    local btn=Instance.new("TextButton"); btn.Size=UDim2.new(1,0,0,38); btn.Position=UDim2.fromOffset(0,posY)
    btn.BackgroundColor3=PALETTE.toggleOff; btn.BorderSizePixel=0; btn.AutoButtonColor=false; btn.Text=""; btn.Parent=parent; corner(btn,9)
    local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,-76,1,0); lbl.Position=UDim2.fromOffset(14,0)
    lbl.BackgroundTransparency=1; lbl.Text=label; lbl.TextColor3=PALETTE.toggleOffTx
    lbl.TextSize=13; lbl.Font=Enum.Font.GothamBold; lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=btn
    local pill=Instance.new("Frame"); pill.Size=UDim2.fromOffset(54,24); pill.Position=UDim2.new(1,-66,0.5,-12)
    pill.BackgroundColor3=Color3.fromRGB(50,48,66); pill.BorderSizePixel=0; pill.Parent=btn; corner(pill,12)
    local knob=Instance.new("Frame"); knob.Size=UDim2.fromOffset(18,18); knob.Position=UDim2.fromOffset(3,3)
    knob.BackgroundColor3=Color3.fromRGB(170,165,190); knob.BorderSizePixel=0; knob.Parent=pill; corner(knob,9)
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
        else knob.Position=kp; pill.BackgroundColor3=pc; knob.BackgroundColor3=kc; btn.BackgroundColor3=bc end
        lbl.TextColor3=lc
    end
    local function setState(v,fromExt) on=v; apply(not fromExt); if not fromExt then onToggle(on) end end
    btn.MouseButton1Click:Connect(function() setState(not on) end)
    return posY+44, setState
end

local function makeCompactToggle(parent,posY,label,onToggle,startOn)
    local btn=Instance.new("TextButton"); btn.Size=UDim2.new(1,0,0,30); btn.Position=UDim2.fromOffset(0,posY)
    btn.BackgroundColor3=Color3.fromRGB(28,27,40); btn.BorderSizePixel=0; btn.AutoButtonColor=false; btn.Text=""; btn.Parent=parent; corner(btn,7)
    local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,-56,1,0); lbl.Position=UDim2.fromOffset(12,0)
    lbl.BackgroundTransparency=1; lbl.Text=label; lbl.TextColor3=Color3.fromRGB(145,138,170)
    lbl.TextSize=12; lbl.Font=Enum.Font.GothamBold; lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=btn
    local pill=Instance.new("Frame"); pill.Size=UDim2.fromOffset(42,18); pill.Position=UDim2.new(1,-52,0.5,-9)
    pill.BackgroundColor3=Color3.fromRGB(50,48,66); pill.BorderSizePixel=0; pill.Parent=btn; corner(pill,9)
    local knob=Instance.new("Frame"); knob.Size=UDim2.fromOffset(14,14); knob.Position=UDim2.fromOffset(2,2)
    knob.BackgroundColor3=Color3.fromRGB(170,165,190); knob.BorderSizePixel=0; knob.Parent=pill; corner(knob,7)
    local on=startOn
    local function apply(animate)
        local kp=on and UDim2.fromOffset(26,2) or UDim2.fromOffset(2,2)
        local pc=on and Color3.fromRGB(125,90,235) or Color3.fromRGB(50,48,66)
        local kc=on and Color3.fromRGB(255,255,255) or Color3.fromRGB(170,165,190)
        local bc=on and Color3.fromRGB(26,42,36) or Color3.fromRGB(28,27,40)
        local lc=on and Color3.fromRGB(170,255,195) or Color3.fromRGB(145,138,170)
        if animate then
            TweenService:Create(knob,TweenInfo.new(0.12),{Position=kp,BackgroundColor3=kc}):Play()
            TweenService:Create(pill,TweenInfo.new(0.12),{BackgroundColor3=pc}):Play()
            TweenService:Create(btn,TweenInfo.new(0.12),{BackgroundColor3=bc}):Play()
        else knob.Position=kp; knob.BackgroundColor3=kc; pill.BackgroundColor3=pc; btn.BackgroundColor3=bc end
        lbl.TextColor3=lc
    end
    apply(false)
    local function setState(v,fromExt) on=v; apply(true); if not fromExt then onToggle(on) end end
    btn.MouseButton1Click:Connect(function() setState(not on) end)
    return posY+34, setState
end

local function makeButton(parent,posY,label,col,onClick)
    local btn=Instance.new("TextButton"); btn.Size=UDim2.new(1,0,0,38); btn.Position=UDim2.fromOffset(0,posY)
    btn.BackgroundColor3=col or PALETTE.accentDim; btn.BorderSizePixel=0
    btn.Text=label; btn.TextColor3=Color3.fromRGB(235,228,255)
    btn.TextSize=13; btn.Font=Enum.Font.GothamBold; btn.Parent=parent
    corner(btn,9); btn.MouseButton1Click:Connect(onClick)
    return posY+44
end

local function miniLabel(parent,posY,text,color)
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,16); l.Position=UDim2.fromOffset(0,posY)
    l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color or PALETTE.textDim
    l.TextSize=11; l.Font=Enum.Font.GothamBold; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=parent
    return posY+18
end

local function makeTextBox(parent,posY,placeholder)
    local box=Instance.new("TextBox"); box.Size=UDim2.new(1,0,0,34); box.Position=UDim2.fromOffset(0,posY)
    box.PlaceholderText=placeholder; box.Text=""; box.Font=Enum.Font.Gotham; box.TextSize=13
    box.TextColor3=Color3.fromRGB(215,210,240); box.PlaceholderColor3=Color3.fromRGB(100,95,125)
    box.BackgroundColor3=Color3.fromRGB(26,25,38); box.BorderSizePixel=0; box.Parent=parent
    corner(box,7); stroke(box,Color3.fromRGB(55,45,90),1)
    return posY+40, box
end

local function infoRow(parent,posY,label,valueFunc)
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,24); row.Position=UDim2.fromOffset(0,posY)
    row.BackgroundColor3=Color3.fromRGB(22,21,32); row.BorderSizePixel=0; row.Parent=parent; corner(row,6)
    local lLbl=Instance.new("TextLabel"); lLbl.Size=UDim2.new(0.55,0,1,0); lLbl.BackgroundTransparency=1
    lLbl.Text=label; lLbl.TextColor3=PALETTE.textDim; lLbl.TextSize=11; lLbl.Font=Enum.Font.Gotham
    lLbl.TextXAlignment=Enum.TextXAlignment.Left; lLbl.Position=UDim2.fromOffset(8,0); lLbl.Parent=row
    local vLbl=Instance.new("TextLabel"); vLbl.Size=UDim2.new(0.45,-8,1,0); vLbl.BackgroundTransparency=1
    vLbl.Text=tostring(valueFunc()); vLbl.TextColor3=PALETTE.textMain; vLbl.TextSize=11; vLbl.Font=Enum.Font.GothamBold
    vLbl.TextXAlignment=Enum.TextXAlignment.Right; vLbl.Position=UDim2.new(0.55,0,0,0); vLbl.Parent=row
    task.spawn(function()
        while row.Parent do vLbl.Text=tostring(valueFunc()); task.wait(3) end
    end)
    return posY+28
end

-- ════════════════════════════════════════════════════════════
--  PÁGINA: INVASION
-- ════════════════════════════════════════════════════════════
local cardModoButtons; local cardSecUpdate; local invasionSetters={}

do
    local p=pageFrames["INVASION"]; local y=4
    y=makeButton(p,y,"Criar invasao",PALETTE.accentDim,criarInvasaoManual); y=y+6

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
        local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.fromOffset(220,30); lbl.Position=UDim2.fromOffset(0,y)
        lbl.BackgroundTransparency=1; lbl.Text="Min jogadores p/ Auto Start:  "..MIN_PLAYERS
        lbl.TextColor3=PALETTE.textMain; lbl.TextSize=12; lbl.Font=Enum.Font.Gotham
        lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=p
        local function updLbl() lbl.Text="Min jogadores p/ Auto Start:  "..MIN_PLAYERS end
        local bMinus=Instance.new("TextButton"); bMinus.Size=UDim2.fromOffset(34,28); bMinus.Position=UDim2.fromOffset(240,y+1)
        bMinus.BackgroundColor3=PALETTE.accentDim; bMinus.BorderSizePixel=0; bMinus.Text="-"
        bMinus.TextColor3=Color3.fromRGB(225,210,255); bMinus.TextSize=18; bMinus.Font=Enum.Font.GothamBold; bMinus.Parent=p
        corner(bMinus,7); bMinus.MouseButton1Click:Connect(function() if MIN_PLAYERS>1 then MIN_PLAYERS-=1; updLbl() end end)
        local bPlus=Instance.new("TextButton"); bPlus.Size=UDim2.fromOffset(34,28); bPlus.Position=UDim2.fromOffset(278,y+1)
        bPlus.BackgroundColor3=PALETTE.accentDim; bPlus.BorderSizePixel=0; bPlus.Text="+"
        bPlus.TextColor3=Color3.fromRGB(225,210,255); bPlus.TextSize=18; bPlus.Font=Enum.Font.GothamBold; bPlus.Parent=p
        corner(bPlus,7); bPlus.MouseButton1Click:Connect(function() if MIN_PLAYERS<4 then MIN_PLAYERS+=1; updLbl() end end)
        y=y+38
    end

    y=y+6; y=sectionHeader(p,y,"AUTO CARD")
    local _,s6=makeToggle(p,y,"Auto Card",function(v) AUTO_CARD=v end)
    invasionSetters.AUTO_CARD=s6; y=y+44+2

    y=miniLabel(p,y,"Primario:")
    do
        local btnD=Instance.new("TextButton"); btnD.Size=UDim2.new(0.5,-4,0,32); btnD.Position=UDim2.fromOffset(0,y)
        btnD.BackgroundColor3=Color3.fromRGB(95,30,35); btnD.BorderSizePixel=0; btnD.Text="Dano (ativo)"
        btnD.TextColor3=Color3.fromRGB(255,185,185); btnD.TextSize=12; btnD.Font=Enum.Font.GothamBold; btnD.Parent=p; corner(btnD,7)
        local btnDr=Instance.new("TextButton"); btnDr.Size=UDim2.new(0.5,-4,0,32); btnDr.Position=UDim2.new(0.5,4,0,y)
        btnDr.BackgroundColor3=PALETTE.toggleOff; btnDr.BorderSizePixel=0; btnDr.Text="Drop"
        btnDr.TextColor3=PALETTE.toggleOffTx; btnDr.TextSize=12; btnDr.Font=Enum.Font.GothamBold; btnDr.Parent=p; corner(btnDr,7)
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
        local btnSec=Instance.new("TextButton"); btnSec.Size=UDim2.new(1,0,0,32); btnSec.Position=UDim2.fromOffset(0,y)
        btnSec.BackgroundColor3=PALETTE.toggleOff; btnSec.BorderSizePixel=0; btnSec.Text="Selecionar"
        btnSec.TextColor3=PALETTE.toggleOffTx; btnSec.TextSize=12; btnSec.Font=Enum.Font.GothamBold; btnSec.Parent=p; corner(btnSec,7)
        y=y+36
        local ITEM_H=32
        local popup=Instance.new("Frame"); popup.Size=UDim2.new(1,0,0,#OPCOES*ITEM_H+6); popup.Position=UDim2.fromOffset(0,y)
        popup.BackgroundColor3=Color3.fromRGB(20,19,30); popup.BorderSizePixel=0; popup.ZIndex=20; popup.Visible=false; popup.Parent=p
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
            local item=Instance.new("TextButton"); item.Size=UDim2.new(1,0,0,ITEM_H); item.Position=UDim2.fromOffset(0,(i-1)*ITEM_H+3)
            item.BackgroundTransparency=1; item.BorderSizePixel=0; item.Text="  "..op.label
            item.TextColor3=Color3.fromRGB(205,198,230); item.TextSize=12; item.Font=Enum.Font.GothamBold
            item.TextXAlignment=Enum.TextXAlignment.Left; item.ZIndex=21; item.Parent=popup
            item.MouseEnter:Connect(function() item.BackgroundTransparency=0; item.BackgroundColor3=Color3.fromRGB(42,33,78) end)
            item.MouseLeave:Connect(function() item.BackgroundTransparency=1 end)
            item.MouseButton1Click:Connect(function() CARD_SEC_ID=op.id; updSec(); popup.Visible=false end)
        end
        btnSec.MouseButton1Click:Connect(function() popup.Visible=not popup.Visible end)
        cardSecUpdate=updSec
    end
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
    y=y+4; y=miniLabel(p,y,"Cava sozinho enquanto tiver pas.",Color3.fromRGB(160,155,185))
    y=miniLabel(p,y,"Notificacao mostra o item obtido a cada cavada.",Color3.fromRGB(100,185,140))
    y=y+8; y=sectionHeader(p,y,"INFO AO VIVO")
    y=infoRow(p,y,"Pas restantes", getQuantidadeDePas)
    y=infoRow(p,y,"Tiles ja cavados", function()
        local t=getTilesJaCavadas(); local c=0
        for _ in pairs(t) do c=c+1 end
        return c.."/"..TREASURE_HUNT_TILE_COUNT
    end)
end

-- ════════════════════════════════════════════════════════════
--  PÁGINA: CAPSULAS
-- ════════════════════════════════════════════════════════════
do
    local p=pageFrames["CAPSULAS"]; local y=4
    y=sectionHeader(p,y,"INFORMACOES")
    y=infoRow(p,y,"SummerStar", capsGetCurrency)
    y=infoRow(p,y,"Capsulas no inv.", capsGetOwned)
    y=infoRow(p,y,"Pode comprar", capsGetMaxAffordable)
    y=y+6
    y=sectionHeader(p,y,"COMPRAR")
    y=makeButton(p,y,"Comprar todas agora",Color3.fromRGB(35,120,55),function()
        task.spawn(function() capsBuyMaxOnce() end)
    end)
    y=y+4
    y=miniLabel(p,y,"Auto Compra — limite de SummerStar:",Color3.fromRGB(160,155,185))
    local newY,autoBuyBox=makeTextBox(p,y,"Ex: 5000"); y=newY
    do
        local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,38); b.Position=UDim2.fromOffset(0,y)
        b.BackgroundColor3=Color3.fromRGB(80,35,35); b.BorderSizePixel=0
        b.Text="Auto Compra - OFF"; b.TextColor3=Color3.fromRGB(235,228,255)
        b.TextSize=13; b.Font=Enum.Font.GothamBold; b.Parent=p; corner(b,9)
        b.MouseButton1Click:Connect(function()
            if not autoBuyEnabled then
                local limit=tonumber(autoBuyBox.Text)
                if limit==nil or limit<=0 then return end
                autoBuyLimit=math.floor(limit); autoBuyEnabled=true
                b.Text="Auto Compra - ON ("..autoBuyLimit..")"; b.BackgroundColor3=Color3.fromRGB(30,100,50)
                capsStartAutoBuyLoop()
            else
                autoBuyEnabled=false; b.Text="Auto Compra - OFF"; b.BackgroundColor3=Color3.fromRGB(80,35,35)
            end
        end)
        y=y+44
    end
    y=y+6
    y=sectionHeader(p,y,"ABRIR")
    y=makeButton(p,y,"Abrir todas agora",Color3.fromRGB(35,75,160),function()
        task.spawn(function() capsOpenAll() end)
    end)
    y=y+4
    y=miniLabel(p,y,"Auto Abertura — limite de capsulas:",Color3.fromRGB(160,155,185))
    local newY2,autoOpenBox=makeTextBox(p,y,"Ex: 10"); y=newY2
    do
        local b2=Instance.new("TextButton"); b2.Size=UDim2.new(1,0,0,38); b2.Position=UDim2.fromOffset(0,y)
        b2.BackgroundColor3=Color3.fromRGB(80,35,35); b2.BorderSizePixel=0
        b2.Text="Auto Abertura - OFF"; b2.TextColor3=Color3.fromRGB(235,228,255)
        b2.TextSize=13; b2.Font=Enum.Font.GothamBold; b2.Parent=p; corner(b2,9)
        b2.MouseButton1Click:Connect(function()
            if not autoOpenEnabled then
                local limit=tonumber(autoOpenBox.Text)
                if limit==nil or limit<=0 then return end
                autoOpenLimit=math.floor(limit); autoOpenEnabled=true
                b2.Text="Auto Abertura - ON ("..autoOpenLimit..")"; b2.BackgroundColor3=Color3.fromRGB(30,100,50)
                capsStartAutoOpenLoop()
            else
                autoOpenEnabled=false; b2.Text="Auto Abertura - OFF"; b2.BackgroundColor3=Color3.fromRGB(80,35,35)
            end
        end)
        y=y+44
    end
end

-- ════════════════════════════════════════════════════════════
--  PÁGINA: CONFIG
-- ════════════════════════════════════════════════════════════
local keybindDisplayLabel
do
    local p=pageFrames["CONFIG"]; local y=4
    y=sectionHeader(p,y,"BLACK SCREEN")
    do
        local btnBS=Instance.new("TextButton"); btnBS.Size=UDim2.new(1,0,0,38); btnBS.Position=UDim2.fromOffset(0,y)
        btnBS.BackgroundColor3=PALETTE.toggleOff; btnBS.BorderSizePixel=0; btnBS.Text="Ativar Black Screen - OFF"
        btnBS.TextColor3=PALETTE.toggleOffTx; btnBS.TextSize=13; btnBS.Font=Enum.Font.GothamBold; btnBS.Parent=p; corner(btnBS,9)
        y=y+44
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
    y=y+8; y=sectionHeader(p,y,"NOTIFICACOES")
    local _,_ms=makeCompactToggle(p,y,"Ativar notificacoes",function(v) NOTIF_ENABLED=v end,NOTIF_ENABLED)
    y=y+34
    do
        local NOTIF_DEFS={
            {key="NOTIF_INVASION_DISP", label="Invasion disponivel"},
            {key="NOTIF_INVASION_START",label="Invasion comecou"},
            {key="NOTIF_INVASION_END",  label="Invasion terminou"},
            {key="NOTIF_ENTROU",        label="Entrou em invasion"},
            {key="NOTIF_TP",            label="Auto TP na torre"},
            {key="NOTIF_TREASURE",      label="Cavada do tesouro"},
        }
        local notifVars={
            NOTIF_INVASION_DISP =function(v) NOTIF_INVASION_DISP=v end,
            NOTIF_INVASION_START=function(v) NOTIF_INVASION_START=v end,
            NOTIF_INVASION_END  =function(v) NOTIF_INVASION_END=v end,
            NOTIF_ENTROU        =function(v) NOTIF_ENTROU=v end,
            NOTIF_TP            =function(v) NOTIF_TP=v end,
            NOTIF_TREASURE      =function(v) NOTIF_TREASURE=v end,
        }
        local notifStart={
            NOTIF_INVASION_DISP=NOTIF_INVASION_DISP, NOTIF_INVASION_START=NOTIF_INVASION_START,
            NOTIF_INVASION_END=NOTIF_INVASION_END, NOTIF_ENTROU=NOTIF_ENTROU,
            NOTIF_TP=NOTIF_TP, NOTIF_TREASURE=NOTIF_TREASURE,
        }
        for _,def in ipairs(NOTIF_DEFS) do
            local newY2,_=makeCompactToggle(p,y,def.label,function(v) if notifVars[def.key] then notifVars[def.key](v) end end,notifStart[def.key])
            y=newY2
        end
    end
    y=y+8; y=sectionHeader(p,y,"KEYBIND")
    keybindDisplayLabel=Instance.new("TextLabel"); keybindDisplayLabel.Size=UDim2.new(1,0,0,24); keybindDisplayLabel.Position=UDim2.fromOffset(0,y)
    keybindDisplayLabel.BackgroundTransparency=1; keybindDisplayLabel.Text="Atual: RightShift + K"
    keybindDisplayLabel.TextColor3=PALETTE.textMain; keybindDisplayLabel.TextSize=13; keybindDisplayLabel.Font=Enum.Font.GothamBold
    keybindDisplayLabel.TextXAlignment=Enum.TextXAlignment.Left; keybindDisplayLabel.Parent=p; y=y+28
    do
        local btnRecord=Instance.new("TextButton"); btnRecord.Size=UDim2.new(1,0,0,38); btnRecord.Position=UDim2.fromOffset(0,y)
        btnRecord.BackgroundColor3=PALETTE.accentDim; btnRecord.BorderSizePixel=0; btnRecord.Text="Gravar nova keybind"
        btnRecord.TextColor3=Color3.fromRGB(235,228,255); btnRecord.TextSize=13; btnRecord.Font=Enum.Font.GothamBold; btnRecord.Parent=p; corner(btnRecord,9)
        y=y+44; y=miniLabel(p,y,"Clique, aperte as teclas, clique em Parar.",Color3.fromRGB(160,155,185))
        local recordedKeys={}; local recordConn=nil
        local function keybindParaTexto(keys)
            if keys==nil or #keys==0 then return "Nenhuma" end; return table.concat(keys," + ")
        end
        local function pararGravacao()
            KEYBIND_RECORDING=false; if recordConn then recordConn:Disconnect(); recordConn=nil end
            btnRecord.Text="Gravar nova keybind"; btnRecord.BackgroundColor3=PALETTE.accentDim
            if #recordedKeys>0 then KEYBIND_KEYS=recordedKeys; keybindDisplayLabel.Text="Atual: "..keybindParaTexto(KEYBIND_KEYS) end
        end
        local function iniciarGravacao()
            KEYBIND_RECORDING=true; recordedKeys={}; btnRecord.Text="Parar (gravando)"; btnRecord.BackgroundColor3=PALETTE.danger
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
    end
    y=y+6; y=sectionHeader(p,y,"CONFIGURACAO")
    do
        local statusLbl=Instance.new("TextLabel"); statusLbl.Size=UDim2.new(1,0,0,18); statusLbl.Position=UDim2.fromOffset(0,y)
        statusLbl.BackgroundTransparency=1; statusLbl.Text=""
        statusLbl.TextColor3=Color3.fromRGB(150,225,160); statusLbl.TextSize=11; statusLbl.Font=Enum.Font.Gotham
        statusLbl.TextXAlignment=Enum.TextXAlignment.Left; statusLbl.Parent=p; y=y+22
        local function mostrarStatus(msg,ok2)
            statusLbl.Text=msg; statusLbl.TextColor3=ok2 and Color3.fromRGB(150,225,160) or Color3.fromRGB(235,130,130)
            task.delay(3,function() if statusLbl.Text==msg then statusLbl.Text="" end end)
        end
        y=makeButton(p,y,"Salvar configuracao",Color3.fromRGB(28,95,80),function()
            local ok2=salvarConfig(); mostrarStatus(ok2 and "Salvo." or "Falha ao salvar.",ok2)
        end)
        y=makeButton(p,y,"Carregar configuracao",PALETTE.accentDim,function()
            local dados=carregarConfigDoArquivo()
            if dados==nil then mostrarStatus("Nenhuma config encontrada.",false); return end
            _G.__lz3s_aplicarConfig(dados); mostrarStatus("Configuracao carregada.",true)
        end)
        y=miniLabel(p,y,"Salva toggles, cartas, keybind, notifs e webhook.",Color3.fromRGB(160,155,185))
    end
end

-- ════════════════════════════════════════════════════════════
--  PÁGINA: WEBHOOK
-- ════════════════════════════════════════════════════════════
local whUrlBox
do
    local p=pageFrames["WEBHOOK"]; local y=4

    local headerLbl=Instance.new("TextLabel"); headerLbl.Size=UDim2.new(1,0,0,20); headerLbl.Position=UDim2.fromOffset(0,y)
    headerLbl.BackgroundTransparency=1; headerLbl.Text="WEBHOOK — DISCORD"
    headerLbl.TextColor3=Color3.fromRGB(80,190,200); headerLbl.TextSize=13; headerLbl.Font=Enum.Font.GothamBold
    headerLbl.TextXAlignment=Enum.TextXAlignment.Left; headerLbl.Parent=p
    divider(p,y+22); y=y+32

    local statusDot=Instance.new("Frame"); statusDot.Size=UDim2.fromOffset(10,10); statusDot.Position=UDim2.new(1,-12,0,y-26)
    statusDot.BackgroundColor3=Color3.fromRGB(200,60,60); statusDot.BorderSizePixel=0; statusDot.Parent=p; corner(statusDot,5)

    y=miniLabel(p,y,"URL do Webhook (Discord):",Color3.fromRGB(160,155,185))
    local newY,box=makeTextBox(p,y,"https://discord.com/api/webhooks/..."); y=newY
    whUrlBox=box

    local btnSalvarUrl=Instance.new("TextButton"); btnSalvarUrl.Size=UDim2.new(1,0,0,36); btnSalvarUrl.Position=UDim2.fromOffset(0,y)
    btnSalvarUrl.BackgroundColor3=Color3.fromRGB(28,90,75); btnSalvarUrl.BorderSizePixel=0
    btnSalvarUrl.Text="Salvar URL"; btnSalvarUrl.TextColor3=Color3.fromRGB(170,255,210)
    btnSalvarUrl.TextSize=13; btnSalvarUrl.Font=Enum.Font.GothamBold; btnSalvarUrl.Parent=p; corner(btnSalvarUrl,9)
    y=y+42

    local whStatusLbl=Instance.new("TextLabel"); whStatusLbl.Size=UDim2.new(1,0,0,16); whStatusLbl.Position=UDim2.fromOffset(0,y)
    whStatusLbl.BackgroundTransparency=1; whStatusLbl.Text=""
    whStatusLbl.TextColor3=Color3.fromRGB(150,225,160); whStatusLbl.TextSize=11; whStatusLbl.Font=Enum.Font.Gotham
    whStatusLbl.TextXAlignment=Enum.TextXAlignment.Left; whStatusLbl.Parent=p; y=y+20

    local function atualizarDotUrl()
        statusDot.BackgroundColor3 = WEBHOOK_URL ~= "" and Color3.fromRGB(80,220,130) or Color3.fromRGB(200,60,60)
    end

    local function mostrarWhStatus(msg,ok2)
        whStatusLbl.Text=msg; whStatusLbl.TextColor3=ok2 and Color3.fromRGB(150,225,160) or Color3.fromRGB(235,130,130)
        task.delay(3,function() if whStatusLbl.Text==msg then whStatusLbl.Text="" end end)
    end

    btnSalvarUrl.MouseButton1Click:Connect(function()
        local url=box.Text:gsub("%s","")
        if url=="" then mostrarWhStatus("URL vazia.",false); return end
        if not (url:match("^https://discord%.com/api/webhooks/") or url:match("^https://discordapp%.com/api/webhooks/")) then
            mostrarWhStatus("URL invalida. Use Discord webhook.",false); return
        end
        WEBHOOK_URL=url; atualizarDotUrl(); salvarConfig()
        mostrarWhStatus("URL salva!",true)
    end)

    y=y+4; divider(p,y); y=y+14

    local lbl2=Instance.new("TextLabel"); lbl2.Size=UDim2.new(1,0,0,16); lbl2.Position=UDim2.fromOffset(0,y)
    lbl2.BackgroundTransparency=1; lbl2.Text="EVENTOS ATIVOS"
    lbl2.TextColor3=PALETTE.accent; lbl2.TextSize=13; lbl2.Font=Enum.Font.GothamBold
    lbl2.TextXAlignment=Enum.TextXAlignment.Left; lbl2.Parent=p; y=y+20

    local newY2,_=makeCompactToggle(p,y,"Drops de Capsulas",function(v) WH_CAPSULE_ENABLED=v end,WH_CAPSULE_ENABLED)
    y=newY2
    y=miniLabel(p,y,"Envia itens obtidos ao abrir capsulas.",Color3.fromRGB(100,185,200))
    local newY3,_=makeCompactToggle(p,y,"Relatorio de Invasion",function(v) WH_INVASION_ENABLED=v end,WH_INVASION_ENABLED)
    y=newY3
    y=miniLabel(p,y,"Envia ao fim: drops, duracao, cartas, pas.",Color3.fromRGB(100,185,200))

    y=y+6; divider(p,y); y=y+14

    y=makeButton(p,y,"Enviar mensagem de teste",Color3.fromRGB(55,40,110),function()
        if WEBHOOK_URL=="" then mostrarWhStatus("Configure a URL primeiro!",false); return end
        wh_send({ embeds={{
            title       = "lz3s Webhook — Teste",
            description = "Webhook configurado!\n"
                       .. (WH_CAPSULE_ENABLED and "OK" or "OFF").." Drops de Capsulas\n"
                       .. (WH_INVASION_ENABLED and "OK" or "OFF").." Relatorio de Invasion",
            color       = 0x7A50EB,
            footer      = wh_footer(),
        }}})
        mostrarWhStatus("Teste enviado! Verifique o Discord.",true)
    end)

    y=miniLabel(p,y,"A URL fica salva no arquivo de config.",Color3.fromRGB(100,95,130))
    atualizarDotUrl()
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
    if dados.WEBHOOK_URL and dados.WEBHOOK_URL~="" then
        WEBHOOK_URL=dados.WEBHOOK_URL
        if whUrlBox then whUrlBox.Text=WEBHOOK_URL end
    end
    if dados.WH_CAPSULE_ENABLED~=nil  then WH_CAPSULE_ENABLED=dados.WH_CAPSULE_ENABLED  end
    if dados.WH_INVASION_ENABLED~=nil then WH_INVASION_ENABLED=dados.WH_INVASION_ENABLED end
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
    if dados.NOTIF_ENABLED~=nil        then NOTIF_ENABLED=dados.NOTIF_ENABLED               end
    if dados.NOTIF_INVASION_DISP~=nil  then NOTIF_INVASION_DISP=dados.NOTIF_INVASION_DISP   end
    if dados.NOTIF_INVASION_START~=nil then NOTIF_INVASION_START=dados.NOTIF_INVASION_START  end
    if dados.NOTIF_INVASION_END~=nil   then NOTIF_INVASION_END=dados.NOTIF_INVASION_END      end
    if dados.NOTIF_ENTROU~=nil         then NOTIF_ENTROU=dados.NOTIF_ENTROU                  end
    if dados.NOTIF_TP~=nil             then NOTIF_TP=dados.NOTIF_TP                          end
    if dados.NOTIF_TREASURE~=nil       then NOTIF_TREASURE=dados.NOTIF_TREASURE              end
end

-- ============================================================
--  KEYBIND
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
    UserInputService.InputEnded:Connect(function(input,_gpe)
        if input.UserInputType~=Enum.UserInputType.Keyboard then return end
        pressionadas[input.KeyCode.Name]=nil
    end)
end

-- ============================================================
--  MINIMIZAR
-- ============================================================
do
    local minimized=false
    MinimizeBtn.MouseButton1Click:Connect(function()
        minimized=not minimized
        if minimized then
            TweenService:Create(Frame,TweenInfo.new(0.2),{Size=UDim2.fromOffset(WINDOW_W,44)}):Play()
            TabBar.Visible=false; PagesHolder.Visible=false; MinimizeBtn.Text="+"
        else
            TweenService:Create(Frame,TweenInfo.new(0.2),{Size=UDim2.fromOffset(WINDOW_W,WINDOW_H)}):Play()
            TabBar.Visible=true; PagesHolder.Visible=true; MinimizeBtn.Text="-"
        end
    end)
end

selectTab("INVASION")

task.defer(function()
    local dados=carregarConfigDoArquivo()
    if dados~=nil then _G.__lz3s_aplicarConfig(dados); logf("Config carregada automaticamente.") end
end)

print("[lz3s Invasion v2] Carregado! Keybind: RightShift + K | Abas: Invasion / Treasure / Capsulas / Config / Webhook")
