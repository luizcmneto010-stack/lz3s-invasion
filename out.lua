-- ============================================================
--  lz3s Invasion Menu (v2) - COMPLETO COM WEBHOOK CORRIGIDO
--  Abas: INVASION | TREASURE | CAPSULAS | WEBHOOK | CONFIG
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

-- ===================== MÓDULOS =====================
local remotes, invasionStore, getInvasionByPlayer, USER_KEY
local charm, computed, subscribe
local lobbiesStore, getLobbyByPlayer
local clearInvasionJoinPrompt
local getPlayerData, TREASURE_HUNT_TILE_COUNT
local itemsContent, shopsContent

pcall(function()
    remotes = require(nav(ReplicatedStorage, "src", "common", "remotes")).remotes
    invasionStore = require(nav(ReplicatedStorage, "src", "common", "store", "gamemodes", "invasion"))
    getInvasionByPlayer = invasionStore.getInvasionByPlayer
    USER_KEY = require(nav(ReplicatedStorage, "src", "common", "constants", "core")).USER_KEY
    
    charm = require(nav(ReplicatedStorage, "rbxts_include", "node_modules", "@rbxts", "charm", "src"))
    computed = charm.computed
    subscribe = charm.subscribe
    
    local ok_lobby, lobbyStore = pcall(function()
        return require(nav(ReplicatedStorage, "src", "common", "store", "gamemodes", "lobbies"))
    end)
    if ok_lobby then
        lobbiesStore = lobbyStore.lobbiesStore
        getLobbyByPlayer = lobbyStore.getLobbyByPlayer
    end
    
    local ok_jp, joinPromptStore = pcall(function()
        return require(nav(game:GetService("StarterPlayer"), "app", "common", "components", "pages", "invasion", "hud", "join-prompt-store"))
    end)
    if ok_jp then
        clearInvasionJoinPrompt = joinPromptStore.clearInvasionJoinPrompt
    end
    
    getPlayerData = require(nav(ReplicatedStorage, "src", "common", "store", "players", "datastore")).getPlayerData
    TREASURE_HUNT_TILE_COUNT = require(nav(ReplicatedStorage, "src", "common", "content", "events", "treasure-hunt")).TREASURE_HUNT_TILE_COUNT
    
    local ok_items, items = pcall(function()
        return require(nav(ReplicatedStorage, "src", "common", "content", "items", "items")).itemsContent
    end)
    if ok_items then itemsContent = items end
    
    shopsContent = require(nav(ReplicatedStorage, "src", "common", "content", "purchases", "shops")).shopsContent
end)

if not itemsContent then itemsContent = {} end

-- ===================== CONFIG =====================
local DEBUG_PRINT = true
local INVASION_NAME = "Dark Matter Invasion"
local MIN_PLAYERS = 1
local CONFIG_FILE = "lz3s_invasion_config.json"

local function logf(msg)
    if DEBUG_PRINT then 
        print("[lz3s] " .. tostring(msg))
    end
end

-- ============================================================
--  SISTEMA DE WEBHOOK CORRIGIDO
-- ============================================================
local WEBHOOK_URL = ""
local WEBHOOK_ACTIVE = false
local WEBHOOK_CAPS_DROPS = true
local WEBHOOK_INVASION_DROPS = true

local function getItemDisplayName(itemId)
    if itemId == nil then return "?" end
    if itemsContent then
        local content = itemsContent[itemId]
        if content and content.displayName then return content.displayName end
    end
    return tostring(itemId)
end

local function getItemAmount(itemId)
    if itemId == nil then return 0 end
    if not getPlayerData then return 0 end
    local data = getPlayerData(USER_KEY)
    if data == nil or data.items == nil then return 0 end
    local item = data.items[itemId]
    return item and item.amount or 0
end

local function formatItemWithTotal(itemId, amount)
    local name = getItemDisplayName(itemId)
    local total = getItemAmount(itemId)
    if amount and amount > 1 then
        return string.format("**%s** x%d (Total: %d)", name, amount, total)
    end
    return string.format("**%s** (Total: %d)", name, total)
end

local function formatDuration(seconds)
    local minutes = math.floor(seconds / 60)
    local remaining = seconds % 60
    if minutes > 0 then
        return string.format("%dm %ds", minutes, remaining)
    end
    return string.format("%ds", remaining)
end

-- FUNÇÃO PRINCIPAL DE ENVIO DE WEBHOOK CORRIGIDA
local function sendWebhook(embed)
    if not WEBHOOK_ACTIVE then
        logf("Webhook desativado")
        return false
    end
    
    if WEBHOOK_URL == "" or WEBHOOK_URL == nil then
        logf("URL do webhook vazia!")
        return false
    end
    
    -- Verifica se a URL é válida
    if not string.match(WEBHOOK_URL, "^https://discord%.com/api/webhooks/") then
        logf("URL do webhook inválida: " .. WEBHOOK_URL)
        return false
    end
    
    local data = {
        ["embeds"] = {embed},
        ["username"] = "lz3s Bot",
        ["avatar_url"] = "https://i.imgur.com/...png"
    }
    
    local json, err = pcall(function() return HttpService:JSONEncode(data) end)
    if not json then
        logf("Erro ao codificar JSON: " .. tostring(err))
        return false
    end
    
    local request = syn and syn.request or request or http_request
    
    if not request then
        logf("Executador nao suporta HTTP requests")
        return false
    end
    
    local success, response = pcall(function()
        return request({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = json
        })
    end)
    
    if not success then
        logf("Erro ao enviar webhook: " .. tostring(response))
        return false
    end
    
    logf("Webhook enviado com sucesso! Status: " .. tostring(response and response.StatusCode or "unknown"))
    return true
end

local function createEmbed(title, description, color, fields, footer)
    local embed = {
        ["title"] = title,
        ["description"] = description,
        ["color"] = color or 0x7A5AEB,
        ["footer"] = footer or {
            ["text"] = "lz3s Invasion System",
            ["icon_url"] = "https://i.imgur.com/...png"
        },
        ["timestamp"] = os.date("!%Y-%m-%dT%T.000Z")
    }
    
    if fields and #fields > 0 then
        embed["fields"] = fields
    end
    
    return embed
end

-- ============================================================
--  FUNÇÃO DE TESTE DO WEBHOOK
-- ============================================================
local function testWebhook()
    logf("Testando webhook...")
    logf("URL: " .. WEBHOOK_URL)
    logf("Ativo: " .. tostring(WEBHOOK_ACTIVE))
    
    if not WEBHOOK_ACTIVE then
        logf("ERRO: Webhook desativado!")
        criarNotif("info", "❌ Webhook Desativado", "Ative o webhook antes de testar.", 4)
        return false
    end
    
    if WEBHOOK_URL == "" or WEBHOOK_URL == nil then
        logf("ERRO: URL do webhook vazia!")
        criarNotif("info", "❌ URL Vazia", "Configure a URL do webhook primeiro.", 4)
        return false
    end
    
    if not string.match(WEBHOOK_URL, "^https://discord%.com/api/webhooks/") then
        logf("ERRO: URL do webhook inválida! Deve ser uma URL do Discord: https://discord.com/api/webhooks/...")
        criarNotif("info", "❌ URL Inválida", "A URL deve ser do Discord: https://discord.com/api/webhooks/...", 5)
        return false
    end
    
    local embed = createEmbed(
        "🧪 Teste de Webhook",
        "✅ Configuração do webhook está funcionando corretamente!",
        0x00FF00,
        {
            {
                ["name"] = "Status",
                ["value"] = "✅ Conexão estabelecida",
                ["inline"] = true
            },
            {
                ["name"] = "Horário",
                ["value"] = os.date("%H:%M:%S"),
                ["inline"] = true
            },
            {
                ["name"] = "URL",
                ["value"] = "```" .. WEBHOOK_URL .. "```",
                ["inline"] = false
            }
        }
    )
    
    local success = sendWebhook(embed)
    if success then
        logf("Webhook de teste enviado com sucesso!")
        criarNotif("info", "✅ Webhook Teste", "Mensagem enviada com sucesso!", 4)
    else
        logf("Falha ao enviar webhook de teste!")
        criarNotif("info", "❌ Webhook Falhou", "Verifique a URL e tente novamente.", 5)
    end
    return success
end

-- ============================================================
--  INVASION MONITOR
-- ============================================================
local invasionStartTime = nil
local invasionStartName = nil
local invasionParticipantCount = 0
local invasionCards = {}
local invasionDrops = {}
local invasionTreasureDrops = {}
local invasionTotalDigs = 0
local invasionSessionActive = false

local function resetInvasionSession()
    invasionStartTime = nil
    invasionStartName = nil
    invasionParticipantCount = 0
    invasionCards = {}
    invasionDrops = {}
    invasionTreasureDrops = {}
    invasionTotalDigs = 0
    invasionSessionActive = false
end

local function addTreasureDropToSession(itemId, amount)
    if not invasionSessionActive or not WEBHOOK_ACTIVE then return end
    for i, drop in ipairs(invasionTreasureDrops) do
        if drop.id == itemId then
            invasionTreasureDrops[i].amount = (invasionTreasureDrops[i].amount or 0) + (amount or 1)
            return
        end
    end
    table.insert(invasionTreasureDrops, {id = itemId, amount = amount or 1})
    invasionTotalDigs = invasionTotalDigs + 1
end

local function sendInvasionReport()
    if not WEBHOOK_ACTIVE or not WEBHOOK_INVASION_DROPS or not invasionStartTime then return end
    local duration = os.time() - invasionStartTime
    local fields = {}
    table.insert(fields, {["name"] = "⏱️ Duração", ["value"] = formatDuration(duration), ["inline"] = true})
    table.insert(fields, {["name"] = "👥 Participantes", ["value"] = tostring(invasionParticipantCount), ["inline"] = true})
    
    if #invasionCards > 0 then
        table.insert(fields, {["name"] = "🃏 Modificadores", ["value"] = table.concat(invasionCards, "\n"), ["inline"] = false})
    end
    
    if #invasionDrops > 0 then
        local texts = {}
        for _, drop in ipairs(invasionDrops) do
            table.insert(texts, formatItemWithTotal(drop.id, drop.amount))
        end
        table.insert(fields, {["name"] = "📦 Drops da Invasion", ["value"] = table.concat(texts, "\n"), ["inline"] = false})
    end
    
    if #invasionTreasureDrops > 0 then
        local texts = {}
        for _, drop in ipairs(invasionTreasureDrops) do
            table.insert(texts, formatItemWithTotal(drop.id, drop.amount))
        end
        table.insert(fields, {["name"] = "⛏️ Tesouro Cavado (" .. invasionTotalDigs .. "x)", ["value"] = table.concat(texts, "\n"), ["inline"] = false})
    end
    
    local totalStars = getItemAmount("SummerStar")
    if totalStars > 0 then
        table.insert(fields, {["name"] = "⭐ Total de Summer Star", ["value"] = tostring(totalStars), ["inline"] = true})
    end
    
    sendWebhook(createEmbed("🎮 Invasion Concluída!", string.format("**%s** completada em **%s**", invasionStartName or "Invasion", formatDuration(duration)), 0x7A5AEB, fields))
end

if subscribe and getInvasionByPlayer then
    subscribe(computed(function() return getInvasionByPlayer(USER_KEY) end), function(invasion)
        if invasion == nil then
            if invasionSessionActive and WEBHOOK_ACTIVE and WEBHOOK_INVASION_DROPS then sendInvasionReport() end
            resetInvasionSession()
            return
        end
        
        if not invasionSessionActive then
            invasionSessionActive = true
            invasionStartTime = os.time()
            invasionStartName = invasion.name or "Dark Matter Invasion"
            invasionParticipantCount = #(invasion.participants or {})
            invasionCards = {}
            
            if invasion.cards then
                for _, card in ipairs(invasion.cards) do
                    table.insert(invasionCards, getItemDisplayName(card))
                end
            end
            if invasion.cardsDisplayed then
                for _, card in ipairs(invasion.cardsDisplayed) do
                    if type(card) == "string" then
                        local name = getItemDisplayName(card)
                        local found = false
                        for _, existing in ipairs(invasionCards) do
                            if existing == name then found = true; break end
                        end
                        if not found then table.insert(invasionCards, name) end
                    end
                end
            end
        end
        
        if invasion.players and invasion.players[USER_KEY] then
            local playerData = invasion.players[USER_KEY]
            if playerData.drops then
                invasionDrops = {}
                for _, drop in ipairs(playerData.drops) do
                    if drop and drop.id then
                        local found = false
                        for i, existing in ipairs(invasionDrops) do
                            if existing.id == drop.id then
                                invasionDrops[i].amount = (invasionDrops[i].amount or 0) + (drop.amount or 1)
                                found = true
                                break
                            end
                        end
                        if not found then
                            table.insert(invasionDrops, {id = drop.id, amount = drop.amount or 1})
                        end
                    end
                end
            end
        end
    end)
end

-- ============================================================
--  CAPSULE MONITOR
-- ============================================================
local function onCapsuleOpen(capsuleId, rewards)
    if not WEBHOOK_ACTIVE or not WEBHOOK_CAPS_DROPS then return end
    local fields = {}
    local totalItems = {}
    
    for _, reward in ipairs(rewards or {}) do
        if reward and reward.id then
            totalItems[reward.id] = (totalItems[reward.id] or 0) + (reward.amount or 1)
        end
    end
    
    local itemTexts = {}
    for id, amount in pairs(totalItems) do
        table.insert(itemTexts, formatItemWithTotal(id, amount))
    end
    
    if #itemTexts > 0 then
        table.insert(fields, {["name"] = "📦 Itens Obtidos", ["value"] = table.concat(itemTexts, "\n"), ["inline"] = false})
    end
    
    table.insert(fields, {["name"] = "📦 Cápsulas Restantes", ["value"] = tostring(getItemAmount(capsuleId)), ["inline"] = true})
    
    sendWebhook(createEmbed(string.format("📦 Abertura de Cápsula: %s", getItemDisplayName(capsuleId)), "Abertura de cápsula concluída!", 0x32CDAA, fields))
end

if remotes and remotes.items and remotes.items.openCapsule then
    local originalOpenCapsule = remotes.items.openCapsule
    remotes.items.openCapsule = function(capsuleId, amount)
        return originalOpenCapsule(capsuleId, amount):andThen(function(result)
            if result and result.success and result.rewards then
                onCapsuleOpen(capsuleId, result.rewards)
            end
            return result
        end)
    end
end

if remotes and remotes.treasureHunt and remotes.treasureHunt.dig then
    local originalDig = remotes.treasureHunt.dig
    remotes.treasureHunt.dig = function(tile)
        return originalDig(tile):andThen(function(result)
            if result and result.reward then
                addTreasureDropToSession(result.reward.id, result.reward.amount)
            end
            return result
        end)
    end
end

-- ============================================================
--  ESTADO
-- ============================================================
local AUTO_START, AUTO_CARD, AUTO_ACCEPT, AUTO_REPLAY, AUTO_JOIN, AUTO_TREASURE, AUTO_TP, BLACK_SCREEN = false, false, false, false, false, false, false, false
local CARD_MODO, CARD_SEC_ID = "dano", nil
local CARD_SEC_REINF, CARD_SEC_BARRICADE = false, false
local KEYBIND_KEYS = {"RightShift", "K"}
local KEYBIND_RECORDING = false
local NOTIF_ENABLED, NOTIF_INVASION_DISP, NOTIF_INVASION_START, NOTIF_INVASION_END, NOTIF_ENTROU, NOTIF_TP, NOTIF_TREASURE = true, true, true, true, true, true, true

-- ============================================================
--  CÁPSULAS
-- ============================================================
local CAPS_SHOP_NAME = "Dark Matter Invasion Shop"
local CAPS_ITEM_ID = "Alien Capsule"
local CAPS_CURRENCY = "SummerStar"
local CAPS_MAX_PER_REQ = 30000
local capsItemPrice = 50

pcall(function()
    local shop = shopsContent[CAPS_SHOP_NAME]
    if shop then
        for _, candidate in pairs(shop.items or {}) do
            if candidate.id == CAPS_ITEM_ID then
                capsItemPrice = candidate.price
                break
            end
        end
    end
end)

local capsNpcPath = nil
pcall(function()
    capsNpcPath = workspace:WaitForChild("World"):WaitForChild("Map"):WaitForChild("Summer Isles"):WaitForChild("Components"):WaitForChild("SummerBaldHero")
end)

local autoBuyEnabled, autoBuyLimit, autoBuyThread = false, 0, nil
local autoOpenEnabled, autoOpenLimit, autoOpenThread = false, 0, nil
local isBuying = false

-- ============================================================
--  ANTI-AFK
-- ============================================================
Players.LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    task.wait(0.1)
    VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
end)

-- ============================================================
--  FUNÇÕES AUXILIARES
-- ============================================================
local function fileFuncsDisponiveis()
    return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

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

local function getQuantidadeDePas()
    local d = getPlayerData(USER_KEY)
    if d == nil or d.items == nil then return 0 end
    local s = d.items.Shovel
    return s and s.amount or 0
end

local function getTilesJaCavadas()
    local d = getPlayerData(USER_KEY)
    if d == nil then return {} end
    local dug = d.treasureHunt and d.treasureHunt.dug
    if dug == nil then return {} end
    local t = {}
    for _, item in pairs(dug) do
        if item and item.index then t[item.index] = true end
    end
    return t
end

-- ============================================================
--  GUI CONSTRUCTION
-- ============================================================
local PALETTE = {
    bg = Color3.fromRGB(16,15,24),
    panel = Color3.fromRGB(22,21,32),
    titlebar = Color3.fromRGB(38,22,84),
    accent = Color3.fromRGB(125,90,235),
    accentDim = Color3.fromRGB(90,65,170),
    toggleOff = Color3.fromRGB(34,33,47),
    toggleOffTx = Color3.fromRGB(150,145,170),
    toggleOnTx = Color3.fromRGB(170,255,195),
    textMain = Color3.fromRGB(225,218,245),
    textDim = Color3.fromRGB(150,142,180),
    danger = Color3.fromRGB(120,35,45),
}

-- Widget helpers
local function createCorner(parent, r) 
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r or 10)
    c.Parent = parent
    return c
end

local function createStroke(parent, col, th)
    local s = Instance.new("UIStroke")
    s.Color = col or Color3.fromRGB(90,70,170)
    s.Thickness = th or 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function divider(parent, posY)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,0,0,1)
    f.Position = UDim2.fromOffset(0, posY)
    f.BackgroundColor3 = Color3.fromRGB(50,40,90)
    f.BackgroundTransparency = 0.3
    f.BorderSizePixel = 0
    f.Parent = parent
    return posY + 10
end

local function sectionHeader(parent, posY, text)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,0,0,20)
    lbl.Position = UDim2.fromOffset(0, posY)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = PALETTE.accent
    lbl.TextSize = 13
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = parent
    return divider(parent, posY + 22)
end

local function miniLabel(parent, posY, text, color)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1,0,0,16)
    l.Position = UDim2.fromOffset(0, posY)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or PALETTE.textDim
    l.TextSize = 11
    l.Font = Enum.Font.GothamBold
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return posY + 18
end

local function infoRow(parent, posY, label, valueFunc)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,24)
    row.Position = UDim2.fromOffset(0, posY)
    row.BackgroundColor3 = Color3.fromRGB(22,21,32)
    row.BorderSizePixel = 0
    row.Parent = parent
    createCorner(row, 6)
    
    local lLbl = Instance.new("TextLabel")
    lLbl.Size = UDim2.new(0.55,0,1,0)
    lLbl.BackgroundTransparency = 1
    lLbl.Text = label
    lLbl.TextColor3 = PALETTE.textDim
    lLbl.TextSize = 11
    lLbl.Font = Enum.Font.Gotham
    lLbl.TextXAlignment = Enum.TextXAlignment.Left
    lLbl.Position = UDim2.fromOffset(8,0)
    lLbl.Parent = row
    
    local vLbl = Instance.new("TextLabel")
    vLbl.Size = UDim2.new(0.45,-8,1,0)
    vLbl.BackgroundTransparency = 1
    vLbl.Text = tostring(valueFunc())
    vLbl.TextColor3 = PALETTE.textMain
    vLbl.TextSize = 11
    vLbl.Font = Enum.Font.GothamBold
    vLbl.TextXAlignment = Enum.TextXAlignment.Right
    vLbl.Position = UDim2.new(0.55,0,0,0)
    vLbl.Parent = row
    
    task.spawn(function()
        while row.Parent do
            vLbl.Text = tostring(valueFunc())
            task.wait(3)
        end
    end)
    return posY + 28
end

local function makeTextBox(parent, posY, placeholder)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1,0,0,34)
    box.Position = UDim2.fromOffset(0, posY)
    box.PlaceholderText = placeholder
    box.Text = ""
    box.Font = Enum.Font.Gotham
    box.TextSize = 13
    box.TextColor3 = Color3.fromRGB(215,210,240)
    box.PlaceholderColor3 = Color3.fromRGB(100,95,125)
    box.BackgroundColor3 = Color3.fromRGB(26,25,38)
    box.BorderSizePixel = 0
    box.Parent = parent
    createCorner(box, 7)
    createStroke(box, Color3.fromRGB(55,45,90), 1)
    return posY + 40, box
end

local function makeButton(parent, posY, label, col, onClick)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,38)
    btn.Position = UDim2.fromOffset(0, posY)
    btn.BackgroundColor3 = col or PALETTE.accentDim
    btn.BorderSizePixel = 0
    btn.Text = label
    btn.TextColor3 = Color3.fromRGB(235,228,255)
    btn.TextSize = 13
    btn.Font = Enum.Font.GothamBold
    btn.Parent = parent
    createCorner(btn, 9)
    btn.MouseButton1Click:Connect(onClick)
    return posY + 44
end

local function makeToggle(parent, posY, label, onToggle)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,38)
    btn.Position = UDim2.fromOffset(0, posY)
    btn.BackgroundColor3 = PALETTE.toggleOff
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Text = ""
    btn.Parent = parent
    createCorner(btn, 9)
    
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,-76,1,0)
    lbl.Position = UDim2.fromOffset(14,0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = PALETTE.toggleOffTx
    lbl.TextSize = 13
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = btn
    
    local pill = Instance.new("Frame")
    pill.Size = UDim2.fromOffset(54,24)
    pill.Position = UDim2.new(1,-66,0.5,-12)
    pill.BackgroundColor3 = Color3.fromRGB(50,48,66)
    pill.BorderSizePixel = 0
    pill.Parent = btn
    createCorner(pill, 12)
    
    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(18,18)
    knob.Position = UDim2.fromOffset(3,3)
    knob.BackgroundColor3 = Color3.fromRGB(170,165,190)
    knob.BorderSizePixel = 0
    knob.Parent = pill
    createCorner(knob, 9)
    
    local on = false
    local function apply(animate)
        local kp = on and UDim2.fromOffset(33,3) or UDim2.fromOffset(3,3)
        local pc = on and PALETTE.accent or Color3.fromRGB(50,48,66)
        local kc = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(170,165,190)
        local bc = on and Color3.fromRGB(26,42,36) or PALETTE.toggleOff
        local lc = on and PALETTE.toggleOnTx or PALETTE.toggleOffTx
        if animate then
            TweenService:Create(knob, TweenInfo.new(0.15), {Position = kp}):Play()
            TweenService:Create(pill, TweenInfo.new(0.15), {BackgroundColor3 = pc}):Play()
            TweenService:Create(knob, TweenInfo.new(0.15), {BackgroundColor3 = kc}):Play()
            TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = bc}):Play()
        else
            knob.Position = kp
            pill.BackgroundColor3 = pc
            knob.BackgroundColor3 = kc
            btn.BackgroundColor3 = bc
        end
        lbl.TextColor3 = lc
    end
    
    local function setState(v, fromExt)
        on = v
        apply(not fromExt)
        if not fromExt then onToggle(on) end
    end
    
    btn.MouseButton1Click:Connect(function() setState(not on) end)
    return posY + 44, setState
end

local function makeCompactToggle(parent, posY, label, onToggle, startOn)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1,0,0,30)
    btn.Position = UDim2.fromOffset(0, posY)
    btn.BackgroundColor3 = Color3.fromRGB(28,27,40)
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Text = ""
    btn.Parent = parent
    createCorner(btn, 7)
    
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1,-56,1,0)
    lbl.Position = UDim2.fromOffset(12,0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Color3.fromRGB(145,138,170)
    lbl.TextSize = 12
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = btn
    
    local pill = Instance.new("Frame")
    pill.Size = UDim2.fromOffset(42,18)
    pill.Position = UDim2.new(1,-52,0.5,-9)
    pill.BackgroundColor3 = Color3.fromRGB(50,48,66)
    pill.BorderSizePixel = 0
    pill.Parent = btn
    createCorner(pill, 9)
    
    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(14,14)
    knob.Position = UDim2.fromOffset(2,2)
    knob.BackgroundColor3 = Color3.fromRGB(170,165,190)
    knob.BorderSizePixel = 0
    knob.Parent = pill
    createCorner(knob, 7)
    
    local on = startOn or false
    local function apply(animate)
        local kp = on and UDim2.fromOffset(26,2) or UDim2.fromOffset(2,2)
        local pc = on and Color3.fromRGB(125,90,235) or Color3.fromRGB(50,48,66)
        local kc = on and Color3.fromRGB(255,255,255) or Color3.fromRGB(170,165,190)
        local bc = on and Color3.fromRGB(26,42,36) or Color3.fromRGB(28,27,40)
        local lc = on and Color3.fromRGB(170,255,195) or Color3.fromRGB(145,138,170)
        if animate then
            TweenService:Create(knob, TweenInfo.new(0.12), {Position = kp, BackgroundColor3 = kc}):Play()
            TweenService:Create(pill, TweenInfo.new(0.12), {BackgroundColor3 = pc}):Play()
            TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = bc}):Play()
        else
            knob.Position = kp
            knob.BackgroundColor3 = kc
            pill.BackgroundColor3 = pc
            btn.BackgroundColor3 = bc
        end
        lbl.TextColor3 = lc
    end
    
    apply(false)
    local function setState(v, fromExt)
        on = v
        apply(true)
        if not fromExt then onToggle(on) end
    end
    
    btn.MouseButton1Click:Connect(function() setState(not on) end)
    return posY + 34, setState
end

-- ============================================================
--  BUILD GUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "lz3sInvasion"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
if not ScreenGui.Parent then ScreenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

local WINDOW_W, WINDOW_H = 360, 500
local Frame = Instance.new("Frame")
Frame.Name = "Main"
Frame.Size = UDim2.fromOffset(WINDOW_W, WINDOW_H)
Frame.Position = UDim2.new(0,24,0.5,-250)
Frame.BackgroundColor3 = PALETTE.bg
Frame.BorderSizePixel = 0
Frame.ClipsDescendants = true
Frame.Active = true
Frame.Draggable = true
Frame.Parent = ScreenGui
createCorner(Frame, 14)
createStroke(Frame, PALETTE.accentDim, 1.5)

-- TitleBar
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1,0,0,44)
TitleBar.BackgroundColor3 = PALETTE.titlebar
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Frame
createCorner(TitleBar, 14)

local patch = Instance.new("Frame")
patch.Size = UDim2.new(1,0,0,14)
patch.Position = UDim2.new(0,0,1,-14)
patch.BackgroundColor3 = PALETTE.titlebar
patch.BorderSizePixel = 0
patch.Parent = TitleBar

local TitleDot = Instance.new("Frame")
TitleDot.Size = UDim2.fromOffset(8,8)
TitleDot.Position = UDim2.fromOffset(14,18)
TitleDot.BackgroundColor3 = PALETTE.accent
TitleDot.BorderSizePixel = 0
TitleDot.Parent = TitleBar
createCorner(TitleDot, 4)

local TitleLbl = Instance.new("TextLabel")
TitleLbl.Size = UDim2.new(1,-160,1,0)
TitleLbl.Position = UDim2.fromOffset(32,0)
TitleLbl.BackgroundTransparency = 1
TitleLbl.Text = "lz3s Invasion"
TitleLbl.TextColor3 = PALETTE.textMain
TitleLbl.TextSize = 16
TitleLbl.Font = Enum.Font.GothamBold
TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
TitleLbl.Parent = TitleBar

local AfkDot = Instance.new("Frame")
AfkDot.Size = UDim2.fromOffset(8,8)
AfkDot.Position = UDim2.new(1,-96,0.5,-4)
AfkDot.BackgroundColor3 = Color3.fromRGB(90,220,130)
AfkDot.BorderSizePixel = 0
AfkDot.Parent = TitleBar
createCorner(AfkDot, 4)

local AfkLbl = Instance.new("TextLabel")
AfkLbl.Size = UDim2.fromOffset(78,20)
AfkLbl.Position = UDim2.new(1,-84,0.5,-10)
AfkLbl.BackgroundTransparency = 1
AfkLbl.Text = "Anti-AFK"
AfkLbl.TextColor3 = Color3.fromRGB(150,220,170)
AfkLbl.TextSize = 11
AfkLbl.Font = Enum.Font.GothamBold
AfkLbl.TextXAlignment = Enum.TextXAlignment.Left
AfkLbl.Parent = TitleBar

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Size = UDim2.fromOffset(28,28)
MinimizeBtn.Position = UDim2.new(1,-34,0.5,-14)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(50,35,95)
MinimizeBtn.BorderSizePixel = 0
MinimizeBtn.Text = "-"
MinimizeBtn.TextColor3 = PALETTE.textMain
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.TextSize = 16
MinimizeBtn.Parent = TitleBar
createCorner(MinimizeBtn, 7)

-- TabBar
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1,-24,0,36)
TabBar.Position = UDim2.fromOffset(12,54)
TabBar.BackgroundColor3 = PALETTE.panel
TabBar.BorderSizePixel = 0
TabBar.Parent = Frame
createCorner(TabBar, 10)

local tp = Instance.new("UIPadding")
tp.PaddingLeft = UDim.new(0,4)
tp.PaddingRight = UDim.new(0,4)
tp.PaddingTop = UDim.new(0,4)
tp.PaddingBottom = UDim.new(0,4)
tp.Parent = TabBar

local tll = Instance.new("UIListLayout")
tll.FillDirection = Enum.FillDirection.Horizontal
tll.Padding = UDim.new(0,3)
tll.SortOrder = Enum.SortOrder.LayoutOrder
tll.Parent = TabBar

local PagesHolder = Instance.new("ScrollingFrame")
PagesHolder.Size = UDim2.new(1,-24,1,-102)
PagesHolder.Position = UDim2.fromOffset(12,98)
PagesHolder.BackgroundTransparency = 1
PagesHolder.BorderSizePixel = 0
PagesHolder.ScrollBarThickness = 4
PagesHolder.ScrollBarImageColor3 = PALETTE.accentDim
PagesHolder.CanvasSize = UDim2.new(0,0,0,0)
PagesHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
PagesHolder.Parent = Frame

-- ============================================================
--  PAGES
-- ============================================================
local PAGE_DEFS = {
    {key = "INVASION", label = "Invasion"},
    {key = "TREASURE", label = "Treasure"},
    {key = "CAPSULAS", label = "Capsulas"},
    {key = "WEBHOOK", label = "Webhook"},
    {key = "CONFIG", label = "Config"},
}

local pageFrames = {}
local tabButtons = {}
local invasionSetters = {}
local cardModoButtons, cardSecUpdate, treasureSetter
local keybindDisplayLabel

local function selectTab(key)
    for k, f in pairs(pageFrames) do f.Visible = (k == key) end
    for k, b in pairs(tabButtons) do
        if k == key then
            b.BackgroundColor3 = PALETTE.accentDim
            b.TextColor3 = Color3.fromRGB(235,225,255)
        else
            b.BackgroundColor3 = PALETTE.panel
            b.TextColor3 = PALETTE.textDim
        end
    end
end

for i, def in ipairs(PAGE_DEFS) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1/#PAGE_DEFS,-3,1,0)
    btn.LayoutOrder = i
    btn.BackgroundColor3 = PALETTE.panel
    btn.BorderSizePixel = 0
    btn.Text = def.label
    btn.TextColor3 = PALETTE.textDim
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamBold
    btn.Parent = TabBar
    createCorner(btn, 7)
    tabButtons[def.key] = btn
    
    local page = Instance.new("Frame")
    page.Name = def.key
    page.Size = UDim2.new(1,0,0,0)
    page.AutomaticSize = Enum.AutomaticSize.Y
    page.BackgroundTransparency = 1
    page.Visible = false
    page.Parent = PagesHolder
    pageFrames[def.key] = page
    btn.MouseButton1Click:Connect(function() selectTab(def.key) end)
end

-- ============================================================
--  BUILD PAGE: INVASION
-- ============================================================
local function buildInvasionPage()
    local p = pageFrames["INVASION"]
    local y = 4
    
    y = makeButton(p, y, "Criar invasao", PALETTE.accentDim, function()
        if criandoInvasao then return end
        criandoInvasao = true
        local ok, req = pcall(function() return remotes.invasions.create:request(INVASION_NAME, {friendsOnly = false}) end)
        if ok then req:andThen(function() criandoInvasao = false end):catch(function() criandoInvasao = false end)
        else criandoInvasao = false end
    end)
    y = y + 6
    
    local s1, s2, s3, s4, s5, s6
    y, s1 = makeToggle(p, y, "Auto Start", function(v) AUTO_START = v end)
    invasionSetters.AUTO_START = s1
    y, s2 = makeToggle(p, y, "Auto Accept Replay", function(v) AUTO_ACCEPT = v end)
    invasionSetters.AUTO_ACCEPT = s2
    y, s3 = makeToggle(p, y, "Auto Replay", function(v) AUTO_REPLAY = v end)
    invasionSetters.AUTO_REPLAY = s3
    y, s4 = makeToggle(p, y, "Auto Join Invasion", function(v) AUTO_JOIN = v; triedLobbies = {} end)
    invasionSetters.AUTO_JOIN = s4
    y, s5 = makeToggle(p, y, "Auto TP", function(v) AUTO_TP = v end)
    invasionSetters.AUTO_TP = s5
    
    y = y + 4
    
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.fromOffset(220,30)
    lbl.Position = UDim2.fromOffset(0, y)
    lbl.BackgroundTransparency = 1
    lbl.Text = "Min jogadores p/ Auto Start:  " .. MIN_PLAYERS
    lbl.TextColor3 = PALETTE.textMain
    lbl.TextSize = 12
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = p
    
    local function updLbl() lbl.Text = "Min jogadores p/ Auto Start:  " .. MIN_PLAYERS end
    
    local btnMinus = Instance.new("TextButton")
    btnMinus.Size = UDim2.fromOffset(34,28)
    btnMinus.Position = UDim2.fromOffset(240, y + 1)
    btnMinus.BackgroundColor3 = PALETTE.accentDim
    btnMinus.BorderSizePixel = 0
    btnMinus.Text = "-"
    btnMinus.TextColor3 = Color3.fromRGB(225,210,255)
    btnMinus.TextSize = 18
    btnMinus.Font = Enum.Font.GothamBold
    btnMinus.Parent = p
    createCorner(btnMinus, 7)
    btnMinus.MouseButton1Click:Connect(function() if MIN_PLAYERS > 1 then MIN_PLAYERS = MIN_PLAYERS - 1; updLbl() end end)
    
    local btnPlus = Instance.new("TextButton")
    btnPlus.Size = UDim2.fromOffset(34,28)
    btnPlus.Position = UDim2.fromOffset(278, y + 1)
    btnPlus.BackgroundColor3 = PALETTE.accentDim
    btnPlus.BorderSizePixel = 0
    btnPlus.Text = "+"
    btnPlus.TextColor3 = Color3.fromRGB(225,210,255)
    btnPlus.TextSize = 18
    btnPlus.Font = Enum.Font.GothamBold
    btnPlus.Parent = p
    createCorner(btnPlus, 7)
    btnPlus.MouseButton1Click:Connect(function() if MIN_PLAYERS < 4 then MIN_PLAYERS = MIN_PLAYERS + 1; updLbl() end end)
    
    y = y + 38
    
    y = sectionHeader(p, y, "AUTO CARD")
    y, s6 = makeToggle(p, y, "Auto Card", function(v) AUTO_CARD = v end)
    invasionSetters.AUTO_CARD = s6
    
    y = y + 2
    y = miniLabel(p, y, "Primario:")
    
    local btnD = Instance.new("TextButton")
    btnD.Size = UDim2.new(0.5,-4,0,32)
    btnD.Position = UDim2.fromOffset(0, y)
    btnD.BackgroundColor3 = Color3.fromRGB(95,30,35)
    btnD.BorderSizePixel = 0
    btnD.Text = "Dano (ativo)"
    btnD.TextColor3 = Color3.fromRGB(255,185,185)
    btnD.TextSize = 12
    btnD.Font = Enum.Font.GothamBold
    btnD.Parent = p
    createCorner(btnD, 7)
    
    local btnDr = Instance.new("TextButton")
    btnDr.Size = UDim2.new(0.5,-4,0,32)
    btnDr.Position = UDim2.new(0.5,4,0, y)
    btnDr.BackgroundColor3 = PALETTE.toggleOff
    btnDr.BorderSizePixel = 0
    btnDr.Text = "Drop"
    btnDr.TextColor3 = PALETTE.toggleOffTx
    btnDr.TextSize = 12
    btnDr.Font = Enum.Font.GothamBold
    btnDr.Parent = p
    createCorner(btnDr, 7)
    
    local function updModo()
        if CARD_MODO == "dano" then
            btnD.BackgroundColor3 = Color3.fromRGB(95,30,35)
            btnD.TextColor3 = Color3.fromRGB(255,185,185)
            btnD.Text = "Dano (ativo)"
            btnDr.BackgroundColor3 = PALETTE.toggleOff
            btnDr.TextColor3 = PALETTE.toggleOffTx
            btnDr.Text = "Drop"
        else
            btnDr.BackgroundColor3 = Color3.fromRGB(28,85,55)
            btnDr.TextColor3 = Color3.fromRGB(170,255,195)
            btnDr.Text = "Drop (ativo)"
            btnD.BackgroundColor3 = PALETTE.toggleOff
            btnD.TextColor3 = PALETTE.toggleOffTx
            btnD.Text = "Dano"
        end
    end
    
    btnD.MouseButton1Click:Connect(function() CARD_MODO = "dano"; updModo() end)
    btnDr.MouseButton1Click:Connect(function() CARD_MODO = "drop"; updModo() end)
    cardModoButtons = updModo
    y = y + 38
    
    y = y + 4
    y = miniLabel(p, y, "Secundario (prioridade se aparecer):")
    
    local OPCOES = {{id = nil, label = "Nenhuma"}, {id = "reinf", label = "Warrior Reinforcement"}, {id = "barricade", label = "Barricade Repair"}}
    local btnSec = Instance.new("TextButton")
    btnSec.Size = UDim2.new(1,0,0,32)
    btnSec.Position = UDim2.fromOffset(0, y)
    btnSec.BackgroundColor3 = PALETTE.toggleOff
    btnSec.BorderSizePixel = 0
    btnSec.Text = "Selecionar"
    btnSec.TextColor3 = PALETTE.toggleOffTx
    btnSec.TextSize = 12
    btnSec.Font = Enum.Font.GothamBold
    btnSec.Parent = p
    createCorner(btnSec, 7)
    y = y + 36
    
    local ITEM_H = 32
    local popup = Instance.new("Frame")
    popup.Size = UDim2.new(1,0,0,#OPCOES * ITEM_H + 6)
    popup.Position = UDim2.fromOffset(0, y)
    popup.BackgroundColor3 = Color3.fromRGB(20,19,30)
    popup.BorderSizePixel = 0
    popup.ZIndex = 20
    popup.Visible = false
    popup.Parent = p
    createCorner(popup, 9)
    createStroke(popup, PALETTE.accentDim, 1)
    
    local function updSec()
        if CARD_SEC_ID == nil then
            btnSec.Text = "Selecionar"
            btnSec.BackgroundColor3 = PALETTE.toggleOff
            btnSec.TextColor3 = PALETTE.toggleOffTx
            CARD_SEC_REINF = false
            CARD_SEC_BARRICADE = false
        else
            local nome = CARD_SEC_ID == "reinf" and "Warrior Reinforcement" or "Barricade Repair"
            btnSec.Text = nome .. " (ativo)"
            btnSec.BackgroundColor3 = Color3.fromRGB(30,75,110)
            btnSec.TextColor3 = Color3.fromRGB(165,220,255)
            CARD_SEC_REINF = (CARD_SEC_ID == "reinf")
            CARD_SEC_BARRICADE = (CARD_SEC_ID == "barricade")
        end
    end
    
    for i, op in ipairs(OPCOES) do
        local item = Instance.new("TextButton")
        item.Size = UDim2.new(1,0,0,ITEM_H)
        item.Position = UDim2.fromOffset(0, (i-1) * ITEM_H + 3)
        item.BackgroundTransparency = 1
        item.BorderSizePixel = 0
        item.Text = "  " .. op.label
        item.TextColor3 = Color3.fromRGB(205,198,230)
        item.TextSize = 12
        item.Font = Enum.Font.GothamBold
        item.TextXAlignment = Enum.TextXAlignment.Left
        item.ZIndex = 21
        item.Parent = popup
        item.MouseEnter:Connect(function() item.BackgroundTransparency = 0; item.BackgroundColor3 = Color3.fromRGB(42,33,78) end)
        item.MouseLeave:Connect(function() item.BackgroundTransparency = 1 end)
        item.MouseButton1Click:Connect(function()
            CARD_SEC_ID = op.id
            updSec()
            popup.Visible = false
        end)
    end
    
    btnSec.MouseButton1Click:Connect(function() popup.Visible = not popup.Visible end)
    cardSecUpdate = updSec
end

-- ============================================================
--  BUILD PAGE: TREASURE
-- ============================================================
local function buildTreasurePage()
    local p = pageFrames["TREASURE"]
    local y = 4
    
    y = sectionHeader(p, y, "TREASURE HUNT")
    local set
    y, set = makeToggle(p, y, "Auto Treasure", function(v)
        AUTO_TREASURE = v
        if v then iniciarLoopTreasure() end
    end)
    treasureSetter = set
    
    y = y + 4
    y = miniLabel(p, y, "Cava sozinho enquanto tiver pas.", Color3.fromRGB(160,155,185))
    y = miniLabel(p, y, "Notificacao mostra o item obtido a cada cavada.", Color3.fromRGB(100,185,140))
    
    y = y + 8
    y = sectionHeader(p, y, "INFO AO VIVO")
    y = infoRow(p, y, "Pás restantes", getQuantidadeDePas)
    y = infoRow(p, y, "Tiles ja cavados", function()
        local t = getTilesJaCavadas()
        local c = 0
        for _ in pairs(t) do c = c + 1 end
        return c .. "/" .. TREASURE_HUNT_TILE_COUNT
    end)
end

-- ============================================================
--  BUILD PAGE: CAPSULAS
-- ============================================================
local function buildCapsulasPage()
    local p = pageFrames["CAPSULAS"]
    local y = 4
    
    y = sectionHeader(p, y, "INFORMACOES")
    y = infoRow(p, y, "SummerStar", capsGetCurrency)
    y = infoRow(p, y, "Capsulas no inv.", capsGetOwned)
    y = infoRow(p, y, "Pode comprar", capsGetMaxAffordable)
    y = y + 6
    
    y = sectionHeader(p, y, "COMPRAR")
    y = makeButton(p, y, "Comprar todas agora", Color3.fromRGB(35,120,55), function()
        task.spawn(function() capsBuyMaxOnce() end)
    end)
    y = y + 4
    
    y = miniLabel(p, y, "Auto Compra — limite de SummerStar:", Color3.fromRGB(160,155,185))
    local newY, autoBuyBox = makeTextBox(p, y, "Ex: 5000")
    y = newY
    
    local btnAutoBuy = Instance.new("TextButton")
    btnAutoBuy.Size = UDim2.new(1,0,0,38)
    btnAutoBuy.Position = UDim2.fromOffset(0, y)
    btnAutoBuy.BackgroundColor3 = Color3.fromRGB(80,35,35)
    btnAutoBuy.BorderSizePixel = 0
    btnAutoBuy.Text = "Auto Compra - OFF"
    btnAutoBuy.TextColor3 = Color3.fromRGB(235,228,255)
    btnAutoBuy.TextSize = 13
    btnAutoBuy.Font = Enum.Font.GothamBold
    btnAutoBuy.Parent = p
    createCorner(btnAutoBuy, 9)
    
    btnAutoBuy.MouseButton1Click:Connect(function()
        if not autoBuyEnabled then
            local limit = tonumber(autoBuyBox.Text)
            if limit == nil or limit <= 0 then return end
            autoBuyLimit = math.floor(limit)
            autoBuyEnabled = true
            btnAutoBuy.Text = "Auto Compra - ON (" .. autoBuyLimit .. ")"
            btnAutoBuy.BackgroundColor3 = Color3.fromRGB(30,100,50)
            capsStartAutoBuyLoop()
        else
            autoBuyEnabled = false
            btnAutoBuy.Text = "Auto Compra - OFF"
            btnAutoBuy.BackgroundColor3 = Color3.fromRGB(80,35,35)
        end
    end)
    y = y + 44
    y = y + 6
    
    y = sectionHeader(p, y, "ABRIR")
    y = makeButton(p, y, "Abrir todas agora", Color3.fromRGB(35,75,160), function()
        task.spawn(function() capsOpenAll() end)
    end)
    y = y + 4
    
    y = miniLabel(p, y, "Auto Abertura — limite de capsulas:", Color3.fromRGB(160,155,185))
    local newY2, autoOpenBox = makeTextBox(p, y, "Ex: 10")
    y = newY2
    
    local btnAutoOpen = Instance.new("TextButton")
    btnAutoOpen.Size = UDim2.new(1,0,0,38)
    btnAutoOpen.Position = UDim2.fromOffset(0, y)
    btnAutoOpen.BackgroundColor3 = Color3.fromRGB(80,35,35)
    btnAutoOpen.BorderSizePixel = 0
    btnAutoOpen.Text = "Auto Abertura - OFF"
    btnAutoOpen.TextColor3 = Color3.fromRGB(235,228,255)
    btnAutoOpen.TextSize = 13
    btnAutoOpen.Font = Enum.Font.GothamBold
    btnAutoOpen.Parent = p
    createCorner(btnAutoOpen, 9)
    
    btnAutoOpen.MouseButton1Click:Connect(function()
        if not autoOpenEnabled then
            local limit = tonumber(autoOpenBox.Text)
            if limit == nil or limit <= 0 then return end
            autoOpenLimit = math.floor(limit)
            autoOpenEnabled = true
            btnAutoOpen.Text = "Auto Abertura - ON (" .. autoOpenLimit .. ")"
            btnAutoOpen.BackgroundColor3 = Color3.fromRGB(30,100,50)
            capsStartAutoOpenLoop()
        else
            autoOpenEnabled = false
            btnAutoOpen.Text = "Auto Abertura - OFF"
            btnAutoOpen.BackgroundColor3 = Color3.fromRGB(80,35,35)
        end
    end)
end

-- ============================================================
--  BUILD PAGE: WEBHOOK
-- ============================================================
local function buildWebhookPage()
    local p = pageFrames["WEBHOOK"]
    local y = 4
    
    y = sectionHeader(p, y, "CONFIGURAÇÃO DO WEBHOOK")
    y = miniLabel(p, y, "URL do Webhook:", Color3.fromRGB(160,155,185))
    
    -- Caixa de texto para URL
    local newY, webhookBox = makeTextBox(p, y, "https://discord.com/api/webhooks/...")
    y = newY
    y = y + 4
    
    -- Toggle para ativar
    local _, sWebhook = makeToggle(p, y, "Ativar Webhook", function(v)
        WEBHOOK_ACTIVE = v
        if v then
            WEBHOOK_URL = webhookBox.Text
            logf("Webhook ativado: " .. WEBHOOK_URL)
            criarNotif("info", "Webhook Ativado", "URL configurada e ativada!", 3)
        else
            logf("Webhook desativado")
            criarNotif("info", "Webhook Desativado", "Notificações desativadas.", 2)
        end
    end)
    y = y + 44
    
    -- Botão Salvar URL
    y = makeButton(p, y, "Salvar URL do Webhook", Color3.fromRGB(30,75,140), function()
        local url = webhookBox.Text
        if url == "" or url == nil then
            criarNotif("info", "❌ Erro", "URL não pode estar vazia!", 3)
            return
        end
        
        WEBHOOK_URL = url
        logf("URL salva: " .. WEBHOOK_URL)
        criarNotif("info", "✅ URL Salva", "URL do webhook salva com sucesso!", 3)
        
        -- Mostra status temporário
        local status = Instance.new("TextLabel")
        status.Size = UDim2.new(1,0,0,20)
        status.Position = UDim2.fromOffset(0, y)
        status.BackgroundTransparency = 1
        status.Text = "✓ URL salva: " .. url
        status.TextColor3 = Color3.fromRGB(100,220,130)
        status.TextSize = 11
        status.Font = Enum.Font.Gotham
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.TextTruncate = Enum.TextTruncate.AtEnd
        status.Parent = p
        task.delay(5, function() status:Destroy() end)
    end)
    
    y = y + 6
    y = sectionHeader(p, y, "EVENTOS")
    
    -- Capsula Drops
    local _, sCaps = makeToggle(p, y, "Notificar Capsula Drops", function(v)
        WEBHOOK_CAPS_DROPS = v
        logf("Capsula Drops: " .. tostring(v))
    end, WEBHOOK_CAPS_DROPS)
    y = y + 44
    
    -- Invasion Drops
    local _, sInv = makeToggle(p, y, "Notificar Invasion Drops", function(v)
        WEBHOOK_INVASION_DROPS = v
        logf("Invasion Drops: " .. tostring(v))
    end, WEBHOOK_INVASION_DROPS)
    y = y + 44
    
    -- Status atual
    y = y + 4
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1,0,0,20)
    statusLabel.Position = UDim2.fromOffset(0, y)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Status: " .. (WEBHOOK_ACTIVE and "✅ Ativo" or "❌ Inativo")
    statusLabel.TextColor3 = WEBHOOK_ACTIVE and Color3.fromRGB(100,220,130) or Color3.fromRGB(220,100,100)
    statusLabel.TextSize = 12
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = p
    
    -- Atualiza status periodicamente
    task.spawn(function()
        while statusLabel.Parent do
            statusLabel.Text = "Status: " .. (WEBHOOK_ACTIVE and "✅ Ativo" or "❌ Inativo")
            statusLabel.TextColor3 = WEBHOOK_ACTIVE and Color3.fromRGB(100,220,130) or Color3.fromRGB(220,100,100)
            task.wait(2)
        end
    end)
    y = y + 24
    
    y = y + 6
    y = sectionHeader(p, y, "TESTE")
    
    -- Botão de teste melhorado
    local testBtn = Instance.new("TextButton")
    testBtn.Size = UDim2.new(1,0,0,44)
    testBtn.Position = UDim2.fromOffset(0, y)
    testBtn.BackgroundColor3 = WEBHOOK_ACTIVE and Color3.fromRGB(30,100,50) or Color3.fromRGB(80,40,40)
    testBtn.BorderSizePixel = 0
    testBtn.Text = WEBHOOK_ACTIVE and "🚀 Enviar Teste" or "🔴 Webhook Desativado"
    testBtn.TextColor3 = Color3.fromRGB(235,228,255)
    testBtn.TextSize = 14
    testBtn.Font = Enum.Font.GothamBold
    testBtn.Parent = p
    createCorner(testBtn, 9)
    
    testBtn.MouseButton1Click:Connect(function()
        testWebhook()
    end)
    
    -- Atualiza botão quando estado muda
    task.spawn(function()
        while testBtn.Parent do
            testBtn.Text = WEBHOOK_ACTIVE and "🚀 Enviar Teste" or "🔴 Webhook Desativado"
            testBtn.BackgroundColor3 = WEBHOOK_ACTIVE and Color3.fromRGB(30,100,50) or Color3.fromRGB(80,40,40)
            task.wait(1)
        end
    end)
    
    y = y + 50
    y = miniLabel(p, y, "Clique em 'Enviar Teste' para verificar se o webhook está funcionando.", Color3.fromRGB(130,125,155))
    y = miniLabel(p, y, "A mensagem deve aparecer no canal do Discord configurado.", Color3.fromRGB(100,155,130))
    
    -- Mostra URL atual resumida
    y = y + 8
    local urlDisplay = Instance.new("TextLabel")
    urlDisplay.Size = UDim2.new(1,0,0,16)
    urlDisplay.Position = UDim2.fromOffset(0, y)
    urlDisplay.BackgroundTransparency = 1
    local shortUrl = WEBHOOK_URL ~= "" and WEBHOOK_URL:sub(1, 60) .. "..." or "(nenhuma URL configurada)"
    urlDisplay.Text = "URL: " .. shortUrl
    urlDisplay.TextColor3 = Color3.fromRGB(140,135,165)
    urlDisplay.TextSize = 10
    urlDisplay.Font = Enum.Font.Gotham
    urlDisplay.TextXAlignment = Enum.TextXAlignment.Left
    urlDisplay.TextTruncate = Enum.TextTruncate.AtEnd
    urlDisplay.Parent = p
    
    -- Atualiza URL display
    task.spawn(function()
        while urlDisplay.Parent do
            local url = WEBHOOK_URL or ""
            local shortUrl = url ~= "" and url:sub(1, 60) .. "..." or "(nenhuma URL configurada)"
            urlDisplay.Text = "URL: " .. shortUrl
            task.wait(3)
        end
    end)
end

-- ============================================================
--  BUILD PAGE: CONFIG
-- ============================================================
local function buildConfigPage()
    local p = pageFrames["CONFIG"]
    local y = 4
    local blackScreenToggleUpdate
    
    y = sectionHeader(p, y, "BLACK SCREEN")
    
    local btnBS = Instance.new("TextButton")
    btnBS.Size = UDim2.new(1,0,0,38)
    btnBS.Position = UDim2.fromOffset(0, y)
    btnBS.BackgroundColor3 = PALETTE.toggleOff
    btnBS.BorderSizePixel = 0
    btnBS.Text = "Ativar Black Screen - OFF"
    btnBS.TextColor3 = PALETTE.toggleOffTx
    btnBS.TextSize = 13
    btnBS.Font = Enum.Font.GothamBold
    btnBS.Parent = p
    createCorner(btnBS, 9)
    y = y + 44
    
    local function updateBSVisual(v)
        if v then
            btnBS.Text = "Black Screen - ON"
            btnBS.BackgroundColor3 = Color3.fromRGB(26,42,36)
            btnBS.TextColor3 = PALETTE.toggleOnTx
        else
            btnBS.Text = "Ativar Black Screen - OFF"
            btnBS.BackgroundColor3 = PALETTE.toggleOff
            btnBS.TextColor3 = PALETTE.toggleOffTx
        end
    end
    blackScreenToggleUpdate = updateBSVisual
    
    btnBS.MouseButton1Click:Connect(function() setBlackScreen(not BLACK_SCREEN) end)
    y = miniLabel(p, y, "Tela preta com chuva. Botao X fecha.", Color3.fromRGB(160,155,185))
    
    y = y + 8
    y = sectionHeader(p, y, "ANTI-AFK")
    y = miniLabel(p, y, "Sempre ativo.", Color3.fromRGB(160,155,185))
    
    y = y + 8
    y = sectionHeader(p, y, "NOTIFICACOES")
    
    local _, ms = makeCompactToggle(p, y, "Ativar notificacoes", function(v) NOTIF_ENABLED = v end, NOTIF_ENABLED)
    y = y + 34
    
    local NOTIF_DEFS = {
        {key = "NOTIF_INVASION_DISP", label = "Invasion disponivel"},
        {key = "NOTIF_INVASION_START", label = "Invasion comecou"},
        {key = "NOTIF_INVASION_END", label = "Invasion terminou"},
        {key = "NOTIF_ENTROU", label = "Entrou em invasion"},
        {key = "NOTIF_TP", label = "Auto TP na torre"},
        {key = "NOTIF_TREASURE", label = "Cavada do tesouro (item)"},
    }
    
    local notifVars = {
        NOTIF_INVASION_DISP = function(v) NOTIF_INVASION_DISP = v end,
        NOTIF_INVASION_START = function(v) NOTIF_INVASION_START = v end,
        NOTIF_INVASION_END = function(v) NOTIF_INVASION_END = v end,
        NOTIF_ENTROU = function(v) NOTIF_ENTROU = v end,
        NOTIF_TP = function(v) NOTIF_TP = v end,
        NOTIF_TREASURE = function(v) NOTIF_TREASURE = v end,
    }
    
    local notifStart = {
        NOTIF_INVASION_DISP = NOTIF_INVASION_DISP,
        NOTIF_INVASION_START = NOTIF_INVASION_START,
        NOTIF_INVASION_END = NOTIF_INVASION_END,
        NOTIF_ENTROU = NOTIF_ENTROU,
        NOTIF_TP = NOTIF_TP,
        NOTIF_TREASURE = NOTIF_TREASURE,
    }
    
    for _, def in ipairs(NOTIF_DEFS) do
        local newY, setter = makeCompactToggle(p, y, def.label, function(v)
            if notifVars[def.key] then notifVars[def.key](v) end
        end, notifStart[def.key])
        y = newY
    end
    
    y = y + 8
    y = sectionHeader(p, y, "KEYBIND")
    
    keybindDisplayLabel = Instance.new("TextLabel")
    keybindDisplayLabel.Size = UDim2.new(1,0,0,24)
    keybindDisplayLabel.Position = UDim2.fromOffset(0, y)
    keybindDisplayLabel.BackgroundTransparency = 1
    keybindDisplayLabel.Text = "Atual: RightShift + K"
    keybindDisplayLabel.TextColor3 = PALETTE.textMain
    keybindDisplayLabel.TextSize = 13
    keybindDisplayLabel.Font = Enum.Font.GothamBold
    keybindDisplayLabel.TextXAlignment = Enum.TextXAlignment.Left
    keybindDisplayLabel.Parent = p
    y = y + 28
    
    local btnRecord = Instance.new("TextButton")
    btnRecord.Size = UDim2.new(1,0,0,38)
    btnRecord.Position = UDim2.fromOffset(0, y)
    btnRecord.BackgroundColor3 = PALETTE.accentDim
    btnRecord.BorderSizePixel = 0
    btnRecord.Text = "Gravar nova keybind"
    btnRecord.TextColor3 = Color3.fromRGB(235,228,255)
    btnRecord.TextSize = 13
    btnRecord.Font = Enum.Font.GothamBold
    btnRecord.Parent = p
    createCorner(btnRecord, 9)
    y = y + 44
    y = miniLabel(p, y, "Clique, aperte as teclas, clique em Parar.", Color3.fromRGB(160,155,185))
    
    local recordedKeys = {}
    local recordConn = nil
    
    local function keybindParaTexto(keys)
        if keys == nil or #keys == 0 then return "Nenhuma" end
        return table.concat(keys, " + ")
    end
    
    local function pararGravacao()
        KEYBIND_RECORDING = false
        if recordConn then recordConn:Disconnect(); recordConn = nil end
        btnRecord.Text = "Gravar nova keybind"
        btnRecord.BackgroundColor3 = PALETTE.accentDim
        if #recordedKeys > 0 then
            KEYBIND_KEYS = recordedKeys
            keybindDisplayLabel.Text = "Atual: " .. keybindParaTexto(KEYBIND_KEYS)
        end
    end
    
    local function iniciarGravacao()
        KEYBIND_RECORDING = true
        recordedKeys = {}
        btnRecord.Text = "Parar (gravando)"
        btnRecord.BackgroundColor3 = PALETTE.danger
        keybindDisplayLabel.Text = "Atual: (gravando...)"
        recordConn = UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.UserInputType == Enum.UserInputType.Keyboard then
                local kn = input.KeyCode.Name
                local jaTem = false
                for _, k in ipairs(recordedKeys) do
                    if k == kn then jaTem = true; break end
                end
                if not jaTem then
                    table.insert(recordedKeys, kn)
                    keybindDisplayLabel.Text = "Atual: " .. keybindParaTexto(recordedKeys) .. " ..."
                end
            end
        end)
    end
    
    btnRecord.MouseButton1Click:Connect(function()
        if KEYBIND_RECORDING then pararGravacao() else iniciarGravacao() end
    end)
    
    y = y + 6
    y = sectionHeader(p, y, "CONFIGURACAO")
    
    local statusLbl = Instance.new("TextLabel")
    statusLbl.Size = UDim2.new(1,0,0,18)
    statusLbl.Position = UDim2.fromOffset(0, y)
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
    
    y = makeButton(p, y, "Salvar configuracao", Color3.fromRGB(28,95,80), function()
        local ok = salvarConfig()
        mostrarStatus(ok and "Salvo." or "Falha ao salvar.", ok)
    end)
    
    y = makeButton(p, y, "Carregar configuracao", PALETTE.accentDim, function()
        local dados = carregarConfigDoArquivo()
        if dados == nil then mostrarStatus("Nenhuma config encontrada.", false) return end
        aplicarConfig(dados)
        mostrarStatus("Configuracao carregada.", true)
    end)
    
    y = miniLabel(p, y, "Salva toggles, cartas, keybind, webhook e notifs.", Color3.fromRGB(160,155,185))
end

-- ============================================================
--  BUILD ALL PAGES
-- ============================================================
buildInvasionPage()
buildTreasurePage()
buildCapsulasPage()
buildWebhookPage()
buildConfigPage()

-- ============================================================
--  FUNÇÕES ADICIONAIS
-- ============================================================
local criandoInvasao = false
local triedLobbies = {}
local lastStarted = 0
local jaVotou = false
local rodadaId = nil

-- ============================================================
--  CAPSULE FUNCTIONS
-- ============================================================
local function capsTeleportAndBuy(amount)
    local character = Players.LocalPlayer.Character
    if character == nil then return nil end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if rootPart == nil then return nil end
    
    local originalCFrame = rootPart.CFrame
    if capsNpcPath then
        local ok, npcCF = pcall(function() return capsNpcPath:GetPivot() end)
        if ok then
            rootPart.CFrame = npcCF * CFrame.new(0, 0, 5)
            task.wait(0.3)
        end
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
    request:andThen(function(result) success = result == true; isBuying = false end):catch(function() isBuying = false end)
    while isBuying do task.wait(0.1) end
    return success
end

local function capsOpenAmount(amount)
    local owned = capsGetOwned()
    if owned <= 0 or amount <= 0 then return end
    amount = math.min(amount, owned)
    remotes.items.openCapsule:request(CAPS_ITEM_ID, amount):andThen(function(result)
        if result and result.success then
            logf("Capsulas abertas: " .. tostring(result.opened or amount))
        end
    end)
end

local function capsOpenAll()
    capsOpenAmount(capsGetOwned())
end

local function capsStartAutoBuyLoop()
    if autoBuyThread ~= nil then return end
    autoBuyThread = task.spawn(function()
        while autoBuyEnabled do
            if autoBuyLimit > 0 and capsGetCurrency() >= autoBuyLimit then
                capsBuyMaxOnce()
            end
            task.wait(2)
        end
        autoBuyThread = nil
    end)
end

local function capsStartAutoOpenLoop()
    if autoOpenThread ~= nil then return end
    autoOpenThread = task.spawn(function()
        while autoOpenEnabled do
            if autoOpenLimit > 0 and capsGetOwned() >= autoOpenLimit then
                capsOpenAll()
            end
            task.wait(2)
        end
        autoOpenThread = nil
    end)
end

-- ============================================================
--  TREASURE FUNCTIONS
-- ============================================================
local treasureRodando = false
local avisouSemPas = false
local DELAY_ENTRE_CAVADAS = 0.6
local CHECK_INTERVAL_SEM_PA = 2

local function escolherTileAleatoria()
    local cavadas = getTilesJaCavadas()
    local disp = {}
    for i = 1, TREASURE_HUNT_TILE_COUNT do
        if not cavadas[i] then table.insert(disp, i) end
    end
    if #disp == 0 then return nil end
    return disp[math.random(1, #disp)]
end

local function formatarRecompensa(reward)
    if reward == nil then return "Item desconhecido" end
    local nome = getItemDisplayName(reward.id or reward)
    local amount = reward.amount
    if amount and amount > 1 then return nome .. " x" .. tostring(amount) end
    return nome
end

local function cavarUmaVez()
    local tile = escolherTileAleatoria()
    if tile == nil then return end
    local ok, req = pcall(function() return remotes.treasureHunt.dig:request(tile) end)
    if not ok then return end
    req:andThen(function(r)
        if r and r.reason then
            logf("Auto Treasure: " .. tostring(r.reason))
        elseif NOTIF_TREASURE then
            local pasRestantes = getQuantidadeDePas()
            local recompensas = {}
            if r and r.revealed then
                for _, rev in ipairs(r.revealed) do
                    if rev and rev.reward then table.insert(recompensas, formatarRecompensa(rev.reward)) end
                end
            elseif r and r.reward then
                table.insert(recompensas, formatarRecompensa(r.reward))
            end
            local texto = #recompensas > 0 and table.concat(recompensas, ", ") or "Recompensa obtida"
            criarNotifTreasure("Tesouro Cavado", texto, pasRestantes)
        end
    end)
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
--  NOTIFICATION SYSTEM
-- ============================================================
local notifGui
local NOTIF_W, NOTIF_H, NOTIF_GAP, NOTIF_PAD_R, NOTIF_PAD_B = 280, 64, 8, 14, 14

pcall(function()
    local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
    local ex = pg:FindFirstChild("lz3sNotif")
    if ex then ex:Destroy() end
    notifGui = Instance.new("ScreenGui")
    notifGui.Name = "lz3sNotif"
    notifGui.IgnoreGuiInset = true
    notifGui.DisplayOrder = 998
    notifGui.ResetOnSpawn = false
    notifGui.Parent = pg
end)

local NOTIF_TYPES = {
    invasion = {bar = Color3.fromRGB(120,80,230), ibg = Color3.fromRGB(40,25,80)},
    start = {bar = Color3.fromRGB(80,200,120), ibg = Color3.fromRGB(20,65,35)},
    finish = {bar = Color3.fromRGB(200,160,50), ibg = Color3.fromRGB(65,48,12)},
    entrou = {bar = Color3.fromRGB(60,160,230), ibg = Color3.fromRGB(15,50,75)},
    tp = {bar = Color3.fromRGB(160,90,240), ibg = Color3.fromRGB(45,20,80)},
    treasure = {bar = Color3.fromRGB(220,170,40), ibg = Color3.fromRGB(65,46,8)},
    capsule = {bar = Color3.fromRGB(50,190,200), ibg = Color3.fromRGB(10,55,60)},
    info = {bar = Color3.fromRGB(100,100,130), ibg = Color3.fromRGB(30,30,45)},
}

function criarNotif(tipo, titulo, msg, duracao)
    if not NOTIF_ENABLED or not notifGui then return end
    duracao = duracao or 4
    
    for _, slot in ipairs(notifGui:GetChildren()) do
        if slot:IsA("Frame") then
            TweenService:Create(slot, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {
                Position = UDim2.new(1, slot.Position.X.Offset, 1, slot.Position.Y.Offset - (NOTIF_H + NOTIF_GAP))
            }):Play()
        end
    end
    
    local def = NOTIF_TYPES[tipo] or NOTIF_TYPES.info
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(NOTIF_W, NOTIF_H)
    frame.Position = UDim2.new(1, NOTIF_W + 20, 1, -(NOTIF_PAD_B + NOTIF_H))
    frame.BackgroundColor3 = Color3.fromRGB(18,17,26)
    frame.BorderSizePixel = 0
    frame.Parent = notifGui
    createCorner(frame, 10)
    createStroke(frame, Color3.fromRGB(55,45,90), 1)
    
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0,4,1,-16)
    bar.Position = UDim2.fromOffset(0,8)
    bar.BackgroundColor3 = def.bar
    bar.BorderSizePixel = 0
    bar.Parent = frame
    createCorner(bar, 4)
    
    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(8,8)
    dot.Position = UDim2.fromOffset(20,14)
    dot.BackgroundColor3 = def.bar
    dot.BorderSizePixel = 0
    dot.Parent = frame
    createCorner(dot, 4)
    
    local tLbl = Instance.new("TextLabel")
    tLbl.Size = UDim2.new(1,-44,0,18)
    tLbl.Position = UDim2.fromOffset(40,10)
    tLbl.BackgroundTransparency = 1
    tLbl.Text = titulo
    tLbl.TextColor3 = Color3.fromRGB(230,225,250)
    tLbl.TextSize = 13
    tLbl.Font = Enum.Font.GothamBold
    tLbl.TextXAlignment = Enum.TextXAlignment.Left
    tLbl.TextTruncate = Enum.TextTruncate.AtEnd
    tLbl.Parent = frame
    
    local mLbl = Instance.new("TextLabel")
    mLbl.Size = UDim2.new(1,-52,0,28)
    mLbl.Position = UDim2.fromOffset(40,28)
    mLbl.BackgroundTransparency = 1
    mLbl.Text = msg
    mLbl.TextColor3 = Color3.fromRGB(160,155,185)
    mLbl.TextSize = 11
    mLbl.Font = Enum.Font.Gotham
    mLbl.TextXAlignment = Enum.TextXAlignment.Left
    mLbl.TextWrapped = true
    mLbl.Parent = frame
    
    local pBg = Instance.new("Frame")
    pBg.Size = UDim2.new(1,-16,0,2)
    pBg.Position = UDim2.new(0,8,1,-6)
    pBg.BackgroundColor3 = Color3.fromRGB(40,38,58)
    pBg.BorderSizePixel = 0
    pBg.Parent = frame
    createCorner(pBg, 4)
    
    local prog = Instance.new("Frame")
    prog.Size = UDim2.fromScale(1,1)
    prog.BackgroundColor3 = def.bar
    prog.BorderSizePixel = 0
    prog.Parent = pBg
    createCorner(prog, 4)
    
    TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Position = UDim2.new(1, -(NOTIF_W + NOTIF_PAD_R), 1, -(NOTIF_PAD_B + NOTIF_H))
    }):Play()
    TweenService:Create(prog, TweenInfo.new(duracao, Enum.EasingStyle.Linear), {Size = UDim2.fromScale(0,1)}):Play()
    
    task.delay(duracao, function()
        TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Position = UDim2.new(1, NOTIF_W + 20, 1, -(NOTIF_PAD_B + NOTIF_H))
        }):Play()
        task.wait(0.3)
        frame:Destroy()
    end)
end

local TNOTIF_W, TNOTIF_H = 290, 78

function criarNotifTreasure(titulo, itemTexto, pasRestantes)
    if not NOTIF_ENABLED or not NOTIF_TREASURE or not notifGui then return end
    local duracao = 3.5
    
    for _, slot in ipairs(notifGui:GetChildren()) do
        if slot:IsA("Frame") then
            TweenService:Create(slot, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {
                Position = UDim2.new(1, slot.Position.X.Offset, 1, slot.Position.Y.Offset - (TNOTIF_H + NOTIF_GAP))
            }):Play()
        end
    end
    
    local BAR_COLOR = Color3.fromRGB(220,170,40)
    local ITEM_COLOR = Color3.fromRGB(255,220,80)
    local PAS_COLOR = Color3.fromRGB(140,215,140)
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(TNOTIF_W, TNOTIF_H)
    frame.Position = UDim2.new(1, TNOTIF_W + 20, 1, -(NOTIF_PAD_B + TNOTIF_H))
    frame.BackgroundColor3 = Color3.fromRGB(20,18,10)
    frame.BorderSizePixel = 0
    frame.Parent = notifGui
    createCorner(frame, 10)
    createStroke(frame, Color3.fromRGB(100,75,20), 1)
    
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0,4,1,-16)
    bar.Position = UDim2.fromOffset(0,8)
    bar.BackgroundColor3 = BAR_COLOR
    bar.BorderSizePixel = 0
    bar.Parent = frame
    createCorner(bar, 4)
    
    local dot = Instance.new("Frame")
    dot.Size = UDim2.fromOffset(10,10)
    dot.Position = UDim2.fromOffset(18,12)
    dot.BackgroundColor3 = BAR_COLOR
    dot.BorderSizePixel = 0
    dot.Parent = frame
    createCorner(dot, 4)
    
    local tLbl = Instance.new("TextLabel")
    tLbl.Size = UDim2.new(1,-44,0,16)
    tLbl.Position = UDim2.fromOffset(38,8)
    tLbl.BackgroundTransparency = 1
    tLbl.Text = titulo
    tLbl.TextColor3 = Color3.fromRGB(240,220,160)
    tLbl.TextSize = 12
    tLbl.Font = Enum.Font.GothamBold
    tLbl.TextXAlignment = Enum.TextXAlignment.Left
    tLbl.TextTruncate = Enum.TextTruncate.AtEnd
    tLbl.Parent = frame
    
    local itemLbl = Instance.new("TextLabel")
    itemLbl.Size = UDim2.new(1,-44,0,20)
    itemLbl.Position = UDim2.fromOffset(38,26)
    itemLbl.BackgroundTransparency = 1
    local textoCurto = #itemTexto > 30 and itemTexto:sub(1,28) .. "…" or itemTexto
    itemLbl.Text = "⬥ " .. textoCurto
    itemLbl.TextColor3 = ITEM_COLOR
    itemLbl.TextSize = 13
    itemLbl.Font = Enum.Font.GothamBold
    itemLbl.TextXAlignment = Enum.TextXAlignment.Left
    itemLbl.TextTruncate = Enum.TextTruncate.AtEnd
    itemLbl.Parent = frame
    
    local pasLbl = Instance.new("TextLabel")
    pasLbl.Size = UDim2.new(1,-44,0,14)
    pasLbl.Position = UDim2.fromOffset(38,50)
    pasLbl.BackgroundTransparency = 1
    pasLbl.Text = "Pás restantes: " .. tostring(pasRestantes)
    pasLbl.TextColor3 = PAS_COLOR
    pasLbl.TextSize = 11
    pasLbl.Font = Enum.Font.Gotham
    pasLbl.TextXAlignment = Enum.TextXAlignment.Left
    pasLbl.Parent = frame
    
    local pBg = Instance.new("Frame")
    pBg.Size = UDim2.new(1,-16,0,2)
    pBg.Position = UDim2.new(0,8,1,-5)
    pBg.BackgroundColor3 = Color3.fromRGB(50,40,10)
    pBg.BorderSizePixel = 0
    pBg.Parent = frame
    createCorner(pBg, 4)
    
    local prog = Instance.new("Frame")
    prog.Size = UDim2.fromScale(1,1)
    prog.BackgroundColor3 = BAR_COLOR
    prog.BorderSizePixel = 0
    prog.Parent = pBg
    createCorner(prog, 4)
    
    TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Position = UDim2.new(1, -(TNOTIF_W + NOTIF_PAD_R), 1, -(NOTIF_PAD_B + TNOTIF_H))
    }):Play()
    TweenService:Create(prog, TweenInfo.new(duracao, Enum.EasingStyle.Linear), {Size = UDim2.fromScale(0,1)}):Play()
    
    task.delay(duracao, function()
        TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
            Position = UDim2.new(1, TNOTIF_W + 20, 1, -(NOTIF_PAD_B + TNOTIF_H))
        }):Play()
        task.wait(0.3)
        frame:Destroy()
    end)
end

-- ============================================================
--  BLACK SCREEN
-- ============================================================
local blackScreenGui, blackScreenRainRunning = nil, false
local setBlackScreen = function() end
local BLACK_SCREEN_TOGGLE_UPDATE = nil

pcall(function()
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
    
    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1,0,1,0)
    bg.BackgroundColor3 = Color3.fromRGB(0,0,0)
    bg.BorderSizePixel = 0
    bg.ZIndex = 1
    bg.ClipsDescendants = true
    bg.Parent = blackScreenGui
    
    local rainContainer = Instance.new("Frame")
    rainContainer.Size = UDim2.new(1,0,1,0)
    rainContainer.BackgroundTransparency = 1
    rainContainer.ZIndex = 1
    rainContainer.Parent = bg
    
    local function createRaindrop()
        local drop = Instance.new("Frame")
        drop.Size = UDim2.new(0,2,0,math.random(15,35))
        drop.BackgroundColor3 = Color3.fromRGB(255,255,255)
        drop.BackgroundTransparency = 0.75
        drop.BorderSizePixel = 0
        drop.ZIndex = 1
        drop.Position = UDim2.new(math.random(0,1000)/1000,0,-0.1,0)
        drop.Parent = rainContainer
        local tw = TweenService:Create(drop, TweenInfo.new(math.random(15,25)/10, Enum.EasingStyle.Linear), {
            Position = UDim2.new(drop.Position.X.Scale,0,1.1,0)
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
    title.Size = UDim2.new(0.5,0,0.08,0)
    title.Position = UDim2.new(0.25,0,0.46,0)
    title.BackgroundTransparency = 1
    title.Text = "lz3s AFK"
    title.TextColor3 = Color3.fromRGB(255,255,255)
    title.Font = Enum.Font.Fondamento
    title.TextScaled = true
    title.ZIndex = 2
    title.Parent = bg
    
    task.spawn(function()
        while title.Parent do
            if blackScreenGui.Enabled then
                local fo = TweenService:Create(title, TweenInfo.new(1.8, Enum.EasingStyle.Sine), {TextTransparency = 0.35})
                fo:Play()
                fo.Completed:Wait()
                local fi = TweenService:Create(title, TweenInfo.new(1.8, Enum.EasingStyle.Sine), {TextTransparency = 0})
                fi:Play()
                fi.Completed:Wait()
            else
                task.wait(0.5)
            end
        end
    end)
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0,44,0,44)
    closeBtn.Position = UDim2.new(1,-64,0,20)
    closeBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextScaled = true
    closeBtn.ZIndex = 3
    closeBtn.AutoButtonColor = true
    closeBtn.Parent = bg
    createCorner(closeBtn, 4)
    createStroke(closeBtn, Color3.fromRGB(255,255,255), 1.2)
    
    setBlackScreen = function(v)
        BLACK_SCREEN = v
        blackScreenGui.Enabled = v
        if v then startRainLoop() else blackScreenRainRunning = false end
        if BLACK_SCREEN_TOGGLE_UPDATE then BLACK_SCREEN_TOGGLE_UPDATE(v) end
    end
    
    closeBtn.MouseButton1Click:Connect(function() setBlackScreen(false) end)
end)

-- ============================================================
--  AUTO START
-- ============================================================
local startRemote = nil
pcall(function()
    local p = ReplicatedStorage:FindFirstChild("rbxts_include")
    p = p and p:FindFirstChild("node_modules")
    p = p and p:FindFirstChild("@rbxts")
    p = p and p:FindFirstChild("remo")
    p = p and p:FindFirstChild("src")
    p = p and p:FindFirstChild("container")
    startRemote = p and p:FindFirstChild("lobbies.start")
end)

RunService.Heartbeat:Connect(function()
    if not AUTO_START then return end
    if tick() - lastStarted < 3 then return end
    if not getLobbyByPlayer then return end
    local ok, lobby = pcall(getLobbyByPlayer, USER_KEY)
    if not ok or not lobby or lobby.owner ~= USER_KEY then return end
    local count = #(lobby.players or {})
    if count >= MIN_PLAYERS then
        lastStarted = tick()
        if startRemote then
            pcall(function()
                if startRemote:IsA("RemoteEvent") then startRemote:FireServer()
                elseif startRemote:IsA("RemoteFunction") then startRemote:InvokeServer() end
            end)
        else
            pcall(function() remotes.lobbies.start:fire() end)
        end
    end
end)

-- ============================================================
--  AUTO CARD
-- ============================================================
local DANO_PRIO = {
    ["Invasion Espionage"] = 10,
    ["Invasion Boss Killer III"] = 9,
    ["Invasion Boss Killer II"] = 8,
    ["Invasion Boss Killer I"] = 7,
    ["Invasion Warrior Blessing III"] = 6,
    ["Invasion Battle Momentum"] = 5,
    ["Invasion Warrior Blessing II"] = 4,
    ["Invasion Warrior Blessing I"] = 3,
}

local DROP_PRIO = {
    ["Invasion Overflowing Wealth III"] = 3,
    ["Invasion Overflowing Wealth II"] = 2,
    ["Invasion Overflowing Wealth I"] = 1,
}

if subscribe and getInvasionByPlayer then
    subscribe(computed(function() return getInvasionByPlayer(USER_KEY) end), function(invasion)
        if not AUTO_CARD or not invasion then return end
        local cards = invasion.cardsDisplayed
        if not cards or #cards == 0 then jaVotou = false; rodadaId = nil; return end
        if invasion.phase ~= "intermission" then return end
        
        local ids = {}
        for _, item in ipairs(cards) do
            ids[_] = typeof(item) == "table" and tostring(item.id) or tostring(item)
        end
        local sig = table.concat(ids, "|")
        if sig ~= rodadaId then rodadaId = sig; jaVotou = false end
        if jaVotou then return end
        jaVotou = true
        
        local cardIds = {}
        for _, item in ipairs(cards) do
            table.insert(cardIds, typeof(item) == "table" and item.id or tostring(item))
        end
        
        if CARD_SEC_REINF then
            for _, id in ipairs(cardIds) do
                if id == "Invasion Warrior Reinforcement" then
                    task.delay(0.5 + math.random() * 2, function()
                        local inv = getInvasionByPlayer(USER_KEY)
                        if inv and inv.phase == "intermission" then
                            remotes.invasions.voteCard:fire(id)
                        end
                    end)
                    return
                end
            end
        end
        
        if CARD_SEC_BARRICADE then
            for _, id in ipairs(cardIds) do
                if id == "Invasion Barricade Repair" then
                    task.delay(0.5 + math.random() * 2, function()
                        local inv = getInvasionByPlayer(USER_KEY)
                        if inv and inv.phase == "intermission" then
                            remotes.invasions.voteCard:fire(id)
                        end
                    end)
                    return
                end
            end
        end
        
        local tab = CARD_MODO == "dano" and DANO_PRIO or DROP_PRIO
        local best, bestP = nil, -1
        for _, id in ipairs(cardIds) do
            local p = tab[id]
            if p and p > bestP then bestP = p; best = id end
        end
        if not best then best = cardIds[math.random(1, #cardIds)] end
        
        task.delay(0.5 + math.random() * 2, function()
            local inv = getInvasionByPlayer(USER_KEY)
            if inv and inv.phase == "intermission" then
                remotes.invasions.voteCard:fire(best)
                logf("Auto Card: " .. tostring(best))
            end
        end)
    end)
end

-- ============================================================
--  AUTO ACCEPT REPLAY
-- ============================================================
if remotes and remotes.invasions then
    remotes.invasions.notifyReplay:connect(function(player, invasionId)
        if not AUTO_ACCEPT then return end
        task.delay(0.3, function()
            if clearInvasionJoinPrompt then pcall(clearInvasionJoinPrompt) end
            remotes.invasions.acceptReplay:request(invasionId):andThen(function() end)
        end)
    end)
end

-- ============================================================
--  AUTO REPLAY
-- ============================================================
local replayRemote = nil
pcall(function()
    local p = ReplicatedStorage:FindFirstChild("rbxts_include")
    p = p and p:FindFirstChild("node_modules")
    p = p and p:FindFirstChild("@rbxts")
    p = p and p:FindFirstChild("remo")
    p = p and p:FindFirstChild("src")
    p = p and p:FindFirstChild("container")
    replayRemote = p and p:FindFirstChild("invasions.replay")
end)

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

RunService.Heartbeat:Connect(function()
    if not AUTO_JOIN then return end
    if tick() - lastJoin < 5 then return end
    if getInvasionByPlayer and getInvasionByPlayer(USER_KEY) ~= nil then return end
    if not lobbiesStore then return end
    local ok, all = pcall(function() return lobbiesStore() end)
    if not ok or not all then return end
    for id, lobby in pairs(all) do
        if lobby.type == "invasion" and not lobby.friendsOnly and not triedLobbies[id] then
            local max = lobby.maxPlayers or 4
            local count = #(lobby.players or {})
            if count < max then
                lastJoin = tick()
                triedLobbies[id] = true
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
    if not turret then
        local ok, result = pcall(function() return invasionFolder:WaitForChild("Main Base Turret", 15) end)
        if ok and result then turret = result end
    end
    if not turret then return nil, "Main Base Turret nao encontrado" end
    if turret:IsA("Model") then
        local pp = turret.PrimaryPart
        if pp then return pp.Position, nil end
        local bp = turret:FindFirstChildWhichIsA("BasePart", true)
        if bp then return bp.Position, nil end
        local ok2, pivot = pcall(function() return turret:GetPivot().Position end)
        if ok2 then return pivot, nil end
        return nil, "Sem BasePart"
    elseif turret:IsA("BasePart") then
        return turret.Position, nil
    else
        local bp = turret:FindFirstChildWhichIsA("BasePart", true)
        if bp then return bp.Position, nil end
        return nil, "Tipo desconhecido"
    end
end

local function tentarTpParaInvasion(filho)
    local nome = filho.Name
    if not nome:match("^invasion%-.") then return end
    if tpFeitoIds[nome] then return end
    if not AUTO_TP then return end
    
    task.spawn(function()
        local pos, err = buscarPosTurret(filho)
        if not pos then return end
        if not AUTO_TP then return end
        
        local char = Players.LocalPlayer.Character
        if not char then
            for _ = 1, 80 do
                task.wait(0.1)
                char = Players.LocalPlayer.Character
                if char then break end
            end
        end
        if not char then return end
        
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        
        tpFeitoIds[nome] = true
        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 10, 0))
        if NOTIF_TP then criarNotif("tp", "Auto TP", "Teleportado para a torre!", 4) end
    end)
end

task.spawn(function()
    local mapFolder
    local ok = pcall(function()
        local world = workspace:WaitForChild("World", 30)
        mapFolder = world:WaitForChild("Map", 30)
    end)
    if not ok or not mapFolder then return end
    
    for _, filho in ipairs(mapFolder:GetChildren()) do
        tentarTpParaInvasion(filho)
    end
    
    mapFolder.ChildAdded:Connect(function(filho)
        tentarTpParaInvasion(filho)
    end)
    
    mapFolder.ChildRemoved:Connect(function(filho)
        if tpFeitoIds[filho.Name] then
            tpFeitoIds[filho.Name] = nil
        end
    end)
end)

-- ============================================================
--  CONFIG PERSISTENCE
-- ============================================================
local function montarConfigAtual()
    return {
        AUTO_START = AUTO_START,
        AUTO_CARD = AUTO_CARD,
        AUTO_ACCEPT = AUTO_ACCEPT,
        AUTO_REPLAY = AUTO_REPLAY,
        AUTO_JOIN = AUTO_JOIN,
        AUTO_TREASURE = AUTO_TREASURE,
        AUTO_TP = AUTO_TP,
        BLACK_SCREEN = BLACK_SCREEN,
        CARD_MODO = CARD_MODO,
        CARD_SEC_ID = CARD_SEC_ID,
        MIN_PLAYERS = MIN_PLAYERS,
        KEYBIND_KEYS = KEYBIND_KEYS,
        NOTIF_ENABLED = NOTIF_ENABLED,
        NOTIF_INVASION_DISP = NOTIF_INVASION_DISP,
        NOTIF_INVASION_START = NOTIF_INVASION_START,
        NOTIF_INVASION_END = NOTIF_INVASION_END,
        NOTIF_ENTROU = NOTIF_ENTROU,
        NOTIF_TP = NOTIF_TP,
        NOTIF_TREASURE = NOTIF_TREASURE,
        WEBHOOK_URL = WEBHOOK_URL,
        WEBHOOK_ACTIVE = WEBHOOK_ACTIVE,
        WEBHOOK_CAPS_DROPS = WEBHOOK_CAPS_DROPS,
        WEBHOOK_INVASION_DROPS = WEBHOOK_INVASION_DROPS,
    }
end

local function salvarConfig()
    if not fileFuncsDisponiveis() then return false end
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
    if not ok or not raw then return nil end
    local okD, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
    if not okD then return nil end
    return decoded
end

local function aplicarConfig(dados)
    if not dados then return end
    if dados.MIN_PLAYERS then MIN_PLAYERS = dados.MIN_PLAYERS end
    if dados.CARD_MODO then
        CARD_MODO = dados.CARD_MODO
        if cardModoButtons then cardModoButtons() end
    end
    if dados.CARD_SEC_ID ~= nil then
        CARD_SEC_ID = dados.CARD_SEC_ID
        if cardSecUpdate then cardSecUpdate() end
    end
    if dados.KEYBIND_KEYS then
        KEYBIND_KEYS = dados.KEYBIND_KEYS
        if keybindDisplayLabel then
            keybindDisplayLabel.Text = "Atual: " .. table.concat(KEYBIND_KEYS, " + ")
        end
    end
    if dados.WEBHOOK_URL then WEBHOOK_URL = dados.WEBHOOK_URL end
    if dados.WEBHOOK_ACTIVE ~= nil then WEBHOOK_ACTIVE = dados.WEBHOOK_ACTIVE end
    if dados.WEBHOOK_CAPS_DROPS ~= nil then WEBHOOK_CAPS_DROPS = dados.WEBHOOK_CAPS_DROPS end
    if dados.WEBHOOK_INVASION_DROPS ~= nil then WEBHOOK_INVASION_DROPS = dados.WEBHOOK_INVASION_DROPS end
    
    local function applyToggle(setter, val)
        if setter then setter(val == true, true) end
    end
    applyToggle(invasionSetters.AUTO_START, dados.AUTO_START)
    applyToggle(invasionSetters.AUTO_ACCEPT, dados.AUTO_ACCEPT)
    applyToggle(invasionSetters.AUTO_REPLAY, dados.AUTO_REPLAY)
    applyToggle(invasionSetters.AUTO_JOIN, dados.AUTO_JOIN)
    applyToggle(invasionSetters.AUTO_TP, dados.AUTO_TP)
    applyToggle(invasionSetters.AUTO_CARD, dados.AUTO_CARD)
    applyToggle(treasureSetter, dados.AUTO_TREASURE)
    
    AUTO_START = dados.AUTO_START == true
    AUTO_ACCEPT = dados.AUTO_ACCEPT == true
    AUTO_REPLAY = dados.AUTO_REPLAY == true
    AUTO_JOIN = dados.AUTO_JOIN == true
    AUTO_TP = dados.AUTO_TP == true
    AUTO_CARD = dados.AUTO_CARD == true
    AUTO_TREASURE = dados.AUTO_TREASURE == true
    
    if AUTO_TREASURE then iniciarLoopTreasure() end
    if dados.BLACK_SCREEN then setBlackScreen(true) end
    if dados.NOTIF_ENABLED ~= nil then NOTIF_ENABLED = dados.NOTIF_ENABLED end
    if dados.NOTIF_INVASION_DISP ~= nil then NOTIF_INVASION_DISP = dados.NOTIF_INVASION_DISP end
    if dados.NOTIF_INVASION_START ~= nil then NOTIF_INVASION_START = dados.NOTIF_INVASION_START end
    if dados.NOTIF_INVASION_END ~= nil then NOTIF_INVASION_END = dados.NOTIF_INVASION_END end
    if dados.NOTIF_ENTROU ~= nil then NOTIF_ENTROU = dados.NOTIF_ENTROU end
    if dados.NOTIF_TP ~= nil then NOTIF_TP = dados.NOTIF_TP end
    if dados.NOTIF_TREASURE ~= nil then NOTIF_TREASURE = dados.NOTIF_TREASURE end
end

-- ============================================================
--  KEYBIND
-- ============================================================
local pressionadas = {}

local function sequenciaCompleta()
    if #KEYBIND_KEYS == 0 then return false end
    for _, k in ipairs(KEYBIND_KEYS) do
        if not pressionadas[k] then return false end
    end
    return true
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if KEYBIND_RECORDING then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    pressionadas[input.KeyCode.Name] = true
    if sequenciaCompleta() then
        ScreenGui.Enabled = not ScreenGui.Enabled
    end
end)

UserInputService.InputEnded:Connect(function(input, gpe)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    pressionadas[input.KeyCode.Name] = nil
end)

-- ============================================================
--  MINIMIZAR
-- ============================================================
local minimized = false
MinimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        TweenService:Create(Frame, TweenInfo.new(0.2), {Size = UDim2.fromOffset(WINDOW_W, 44)}):Play()
        TabBar.Visible = false
        PagesHolder.Visible = false
        MinimizeBtn.Text = "+"
    else
        TweenService:Create(Frame, TweenInfo.new(0.2), {Size = UDim2.fromOffset(WINDOW_W, WINDOW_H)}):Play()
        TabBar.Visible = true
        PagesHolder.Visible = true
        MinimizeBtn.Text = "-"
    end
end)

-- ============================================================
--  NOTIFICATION WATCHERS
-- ============================================================
local jaNotifoiLobby = {}
local CURRENCY_DROP_NAME = "Summer Star Remnant"
local lastInvasionId, lastState, startNotifiedId, lastStarQtd = nil, nil, nil, 0

task.spawn(function()
    while true do
        task.wait(5)
        if NOTIF_INVASION_DISP and lobbiesStore then
            local ok, all = pcall(function() return lobbiesStore() end)
            if ok and all then
                for id, lobby in pairs(all) do
                    if lobby.type == "invasion" and not lobby.friendsOnly and not jaNotifoiLobby[id] then
                        jaNotifoiLobby[id] = true
                        criarNotif("invasion", "Invasion disponivel", "Lobby aberto - " .. (#(lobby.players or {})) .. "/" .. (lobby.maxPlayers or 4) .. " jogadores", 5)
                    end
                end
                for id in pairs(jaNotifoiLobby) do
                    if all[id] == nil then jaNotifoiLobby[id] = nil end
                end
            end
        end
    end
end)

if subscribe and getInvasionByPlayer then
    subscribe(computed(function() return getInvasionByPlayer(USER_KEY) end), function(invasion)
        if not invasion then
            if lastInvasionId and NOTIF_INVASION_END then
                local msg = "A invasion terminou."
                if lastStarQtd > 0 then
                    msg = msg .. " Ganhou: " .. lastStarQtd
                    local total = (function()
                        local ok, d = pcall(getPlayerData, USER_KEY)
                        if ok and d and d.items then
                            local item = d.items[CURRENCY_DROP_NAME]
                            return item and item.amount or 0
                        end
                        return 0
                    end)()
                    if total > 0 then msg = msg .. " | Total: " .. total end
                end
                criarNotif("finish", "Invasion encerrada", msg, 7)
            end
            lastInvasionId = nil
            lastState = nil
            startNotifiedId = nil
            lastStarQtd = 0
            return
        end
        
        if invasion.players and invasion.players[USER_KEY] then
            local dados = invasion.players[USER_KEY]
            if dados and dados.drops then
                local total = 0
                for _, drop in ipairs(dados.drops) do
                    if drop and drop.id == CURRENCY_DROP_NAME then
                        total = total + (drop.amount or 0)
                    end
                end
                lastStarQtd = total
            end
        end
        
        if invasion.id ~= lastInvasionId then
            lastInvasionId = invasion.id
            if NOTIF_ENTROU then
                criarNotif("entrou", "Entrou na invasion", invasion.name or "Dark Matter Invasion", 4)
            end
        end
        
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
end

-- ============================================================
--  STARTUP
-- ============================================================
selectTab("INVASION")

task.defer(function()
    local dados = carregarConfigDoArquivo()
    if dados then
        aplicarConfig(dados)
        logf("Config carregada automaticamente.")
    end
end)

print("[lz3s Invasion v3] Carregado! Keybind: RightShift + K | Abas: Invasion / Treasure / Capsulas / Webhook / Config")
