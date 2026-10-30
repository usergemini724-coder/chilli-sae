--[[═══════════════════════════════════════════════════════════════════════════
    SAE — EGG FINDER  +  SERVER BROWSER
    Game   : Steal An Egg (place 107778070777162)
    Build  : keyless, no password, no HWID, no remote loader
    Load   : loadstring(game:HttpGet(".../sae-eggf.lua?v=1"))()
    Tabs   : [EGG FINDER] [SERVERS]
    Keys   : RIGHT-SHIFT = toggle UI      END = unload
═══════════════════════════════════════════════════════════════════════════]]

if _G.SAE_EGGF then
    task.spawn(function()
        pcall(function() _G.SAE_EGGF.unload() end)
    end)
    task.wait(0.2)
end

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local LP = Players.LocalPlayer
local PLACE_ID = game.PlaceId

--─────────────────────────────────────────────────────────────────────────────
-- CONFIG  (tune here if the game renames things)
--─────────────────────────────────────────────────────────────────────────────
local CONFIG = {
    scanInterval  = 0.6,
    maxDistance   = 2500,
    keywords      = { "egg" },
    esp           = true,
    autoTP        = false,
    tpOffset      = 4,
    tpCooldown    = 1.5,
    maxRendered   = 120,
}

local RARITY = {
    common    = Color3.fromRGB(180, 180, 180),
    uncommon  = Color3.fromRGB( 90, 220, 110),
    rare      = Color3.fromRGB( 80, 160, 255),
    epic      = Color3.fromRGB(180, 100, 240),
    legendary = Color3.fromRGB(255, 175, 60),
    mythic    = Color3.fromRGB(255, 80, 120),
    secret    = Color3.fromRGB(255, 240, 120),
    divine    = Color3.fromRGB(140, 255, 240),
    godly     = Color3.fromRGB(255, 120, 255),
}

local state = {
    eggs       = {},          -- [Instance] = { part = BasePart, rarity = string }
    espCache   = {},          -- [Instance] = { billboard, highlight }
    rendered   = 0,
    autoTPOn   = false,
    lastTP     = 0,
    servers    = {},
    currentJob = nil,
    fetching   = false,
    alive      = true,
}

--─────────────────────────────────────────────────────────────────────────────
-- HELPERS
--─────────────────────────────────────────────────────────────────────────────
local function notify(txt, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "SAE Egg Finder",
            Text = tostring(txt),
            Duration = dur or 3,
        })
    end)
end

local function lower(s)
    return string.lower(tostring(s))
end

local function matchesKeyword(name)
    local n = lower(name)
    for _, kw in ipairs(CONFIG.keywords) do
        if string.find(n, kw, 1, true) then return true end
    end
    return false
end

-- egg must sit inside an "egg"-ish container, or carry a Rarity attribute
local function inEggContainer(inst)
    local ok, res = pcall(function()
        local node = inst.Parent
        for _ = 1, 4 do
            if not node or node == Workspace then break end
            if matchesKeyword(node.Name) then return true end
            node = node.Parent
        end
        return false
    end)
    return ok and res or false
end

local function attrRarity(inst)
    local ok, val = pcall(function()
        for _, node in ipairs({ inst, inst.Parent }) do
            if node then
                for _, key in ipairs({ "Rarity", "rarity", "Type", "Tier" }) do
                    local a = node:GetAttribute(key)
                    if type(a) == "string" and RARITY[lower(a)] then return lower(a) end
                end
            end
        end
        return nil
    end)
    return ok and val or nil
end

local function rarityOf(inst)
    local viaAttr = attrRarity(inst)
    if viaAttr then return viaAttr end
    local n = lower(inst.Name)
    for key in pairs(RARITY) do
        if string.find(n, key, 1, true) then return key end
    end
    return "common"
end

local function getPart(inst)
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
    end
    if inst:IsA("Folder") or inst:IsA("Model") then
        return inst:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function isCandidate(inst)
    if not (inst:IsA("BasePart") or inst:IsA("Model")) then return false end
    if not matchesKeyword(inst.Name) then return false end
    if inst == LP.Character then return false end
    local char = LP.Character
    if char and inst:IsDescendantOf(char) then return false end
    if inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid") then return false end
    if not inEggContainer(inst) and not attrRarity(inst) then return false end
    return true
end

local function distTo(part)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not part then return math.huge end
    return (hrp.Position - part.Position).Magnitude
end

--─────────────────────────────────────────────────────────────────────────────
-- ESP
--─────────────────────────────────────────────────────────────────────────────
local function destroyESP(inst)
    local c = state.espCache[inst]
    if not c then return end
    pcall(function() if c.billboard then c.billboard:Destroy() end end)
    pcall(function() if c.highlight then c.highlight:Destroy() end end)
    state.espCache[inst] = nil
end

local function buildESP(inst, part, rarity)
    local col = RARITY[rarity] or RARITY.common

    local hl = Instance.new("Highlight")
    hl.Name = "SAEEggHL"
    hl.FillColor = col
    hl.FillTransparency = 0.65
    hl.OutlineColor = col
    hl.OutlineTransparency = 0.1
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = part
    hl.Parent = part

    local bb = Instance.new("BillboardGui")
    bb.Name = "SAEEggBB"
    bb.Size = UDim2.fromScale(0, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = CONFIG.maxDistance
    bb.Adornee = part
    bb.Parent = part

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromOffset(240, 34)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.TextColor3 = col
    label.TextStrokeTransparency = 0.3
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.Text = inst.Name
    label.Parent = bb

    state.espCache[inst] = { billboard = bb, highlight = hl, label = label }
end

local function updateLabel(inst, part)
    local c = state.espCache[inst]
    if not c or not c.label then return end
    local d = distTo(part)
    if d == math.huge then d = 0 end
    c.label.Text = string.format("%s  [%d]", inst.Name, math.floor(d))
end

--─────────────────────────────────────────────────────────────────────────────
-- SCAN LOOP
--────────────────────────────────────────────────────────────────────────────
local function collectEggs()
    local found = {}
    local ok = pcall(function()
        local roots = { Workspace }
        for _, name in ipairs({ "Eggs", "Egg", "EggFolder", "EggsFolder" }) do
            local direct = Workspace:FindFirstChild(name)
            if direct then roots = { direct } ; break end
        end
        for _, root in ipairs(roots) do
            for _, inst in ipairs(root:GetDescendants()) do
                local good, pass = pcall(isCandidate, inst)
                if good and pass then
                    local part = getPart(inst)
                    if part then found[inst] = { part = part, rarity = rarityOf(inst) } end
                end
            end
            if next(found) then break end
            -- loose retry: whole workspace
            if root == Workspace then
                local loose = {}
                for _, inst in ipairs(Workspace:GetDescendants()) do
                    if (inst:IsA("BasePart") or inst:IsA("Model")) and matchesKeyword(inst.Name) then
                        local part = getPart(inst)
                        if part then loose[inst] = { part = part, rarity = rarityOf(inst) } end
                    end
                end
                found = loose
            end
        end
    end)
    if not ok then return state.eggs end
    return found
end

local function refreshESP()
    local new = collectEggs()
    state.eggs = new

    for inst in pairs(state.espCache) do
        if not new[inst] or not inst.Parent or not CONFIG.esp then destroyESP(inst) end
    end

    if not CONFIG.esp then
        state.rendered = 0
        return
    end

    -- nearest-first ordering so the cap keeps useful entries
    local list = {}
    for inst, data in pairs(new) do
        local d = distTo(data.part)
        if d <= CONFIG.maxDistance then
            table.insert(list, { inst = inst, data = data, d = d })
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)

    for i = 1, math.min(#list, CONFIG.maxRendered) do
        local e = list[i]
        if not state.espCache[e.inst] then
            local ok = pcall(buildESP, e.inst, e.data.part, e.data.rarity)
            if not ok then state.espCache[e.inst] = nil end
        end
    end
    state.rendered = math.min(#list, CONFIG.maxRendered)
end

local function scanLoop()
    while state.alive do
        pcall(refreshESP)
        task.wait(CONFIG.scanInterval)
    end
end

--─────────────────────────────────────────────────────────────────────────────
-- AUTO TELEPORT
--─────────────────────────────────────────────────────────────────────────────
local function teleportToEgg()
    if os.clock() - state.lastTP < CONFIG.tpCooldown then return end
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local best, bestD = nil, math.huge
    for _, data in pairs(state.eggs) do
        if data.part and data.part.Parent then
            local d = distTo(data.part)
            if d < bestD then best, bestD = data.part, d end
        end
    end
    if not best then return end

    state.lastTP = os.clock()
    local target = best.Position + Vector3.new(0, CONFIG.tpOffset, 0)
    pcall(function()
        local tween = TweenService:Create(
            hrp,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { CFrame = CFrame.new(target) }
        )
        tween:Play()
    end)
    hrp.CFrame = CFrame.new(target)  -- hard-set so it survives tween cancellation
end

local function tpLoop()
    while state.alive do
        if state.autoTPOn then pcall(teleportToEgg) end
        task.wait(0.25)
    end
end

--─────────────────────────────────────────────────────────────────────────────
-- SERVER BROWSER
--─────────────────────────────────────────────────────────────────────────────
local function httpGet(url)
    local body
    local ok = pcall(function() body = game:HttpGet(url, true) end)
    if ok and type(body) == "string" and #body > 0 then return body end
    ok = pcall(function() body = request({ Url = url, Method = "GET" }).Body end)
    if ok and type(body) == "string" and #body > 0 then return body end
    return nil
end

local function fetchServers()
    if state.fetching then return end
    state.fetching = true
    local out, cursor, pages = {}, nil, 0

    repeat
        pages = pages + 1
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?limit=100&sortOrder=Desc&excludeFullGames=false%s",
            PLACE_ID,
            cursor and ("&cursor=" .. cursor) or ""
        )
        local raw = httpGet(url)
        if not raw then break end
        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
        if not ok or type(decoded) ~= "table" then break end

        for _, s in ipairs(decoded.data or {}) do
            table.insert(out, {
                id      = s.id,
                playing = tonumber(s.playing) or 0,
                max     = tonumber(s.maxPlayers) or 0,
                ping    = tonumber(s.ping),
            })
        end
        cursor = decoded.nextPageCursor
    until not cursor or pages >= 3

    table.sort(out, function(a, b)
        if a.playing ~= b.playing then return a.playing > b.playing end
        return a.id < b.id
    end)

    state.servers = out
    state.fetching = false
    if #out == 0 then notify("Server list kosong / API diblokir", 4) end
    return out
end

local function joinServer(jobId)
    if not jobId or jobId == "" then return end
    if jobId == state.currentJob then notify("Sudah di server ini", 2) return end
    notify("Menghubungkan ke " .. string.sub(jobId, 1, 8) .. "...", 3)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(PLACE_ID, jobId, LP)
    end)
    if not ok then
        pcall(function()
            TeleportService:TeleportAsync(PLACE_ID, { LP },
                TeleportOptions.new({ ServerInstanceId = jobId }))
        end)
        notify("Fallback TeleportAsync: " .. tostring(err), 4)
    end
end

--─────────────────────────────────────────────────────────────────────────────
-- UI
--────────────────────────────────────────────────────────────────────────────
local C_BG      = Color3.fromRGB(18, 18, 22)
local C_PANEL   = Color3.fromRGB(28, 28, 34)
local C_STROKE  = Color3.fromRGB(58, 58, 70)
local C_TEXT    = Color3.fromRGB(235, 235, 240)
local C_DIM     = Color3.fromRGB(150, 150, 162)
local C_ACCENT  = Color3.fromRGB(120, 220, 150)

local gui = Instance.new("ScreenGui")
gui.Name = "SAE_EggFinder"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999

local okParent = pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not okParent or not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(470, 330)
main.Position = UDim2.new(0.5, -235, 0.5, -165)
main.BackgroundColor3 = C_BG
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = C_STROKE
mainStroke.Thickness = 1
mainStroke.Parent = main

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 8)
mainCorner.Parent = main

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 34)
titleBar.BackgroundColor3 = C_PANEL
titleBar.BorderSizePixel = 0
titleBar.Parent = main

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 8)
titleCorner.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -80, 1, 0)
titleLabel.Position = UDim2.fromOffset(12, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 13
titleLabel.TextColor3 = C_TEXT
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "SAE · EGG FINDER"
titleLabel.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(24, 24)
closeBtn.Position = UDim2.new(1, -32, 0, 5)
closeBtn.BackgroundColor3 = C_PANEL
closeBtn.Text = "×"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.TextColor3 = C_TEXT
closeBtn.Parent = titleBar

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeBtn

-- drag
do
    local dragging, dragStart, startPos = false, nil, nil
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- tabs
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -24, 0, 28)
tabBar.Position = UDim2.fromOffset(12, 42)
tabBar.BackgroundTransparency = 1
tabBar.Parent = main

local function makeTab(text, order)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0.5, -4, 1, 0)
    b.Position = UDim2.new(order * 0.5, order * 4, 0, 0)
    b.BackgroundColor3 = C_PANEL
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.TextColor3 = C_DIM
    b.Text = text
    b.Parent = tabBar
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = b
    return b
end

local tabEgg    = makeTab("EGG FINDER", 0)
local tabServer = makeTab("SERVERS", 1)

local pages = Instance.new("Frame")
pages.Size = UDim2.new(1, -24, 1, -110)
pages.Position = UDim2.fromOffset(12, 78)
pages.BackgroundTransparency = 1
pages.Parent = main

local eggPage = Instance.new("Frame")
eggPage.Size = UDim2.fromScale(1, 1)
eggPage.BackgroundTransparency = 1
eggPage.Parent = pages

local srvPage = Instance.new("Frame")
srvPage.Size = UDim2.fromScale(1, 1)
srvPage.BackgroundTransparency = 1
srvPage.Visible = false
srvPage.Parent = pages

local function setTab(which)
    local eggOn = which == "egg"
    eggPage.Visible = eggOn
    srvPage.Visible = not eggOn
    tabEgg.BackgroundColor3 = eggOn and C_PANEL or C_BG
    tabEgg.TextColor3 = eggOn and C_ACCENT or C_DIM
    tabServer.BackgroundColor3 = (not eggOn) and C_PANEL or C_BG
    tabServer.TextColor3 = (not eggOn) and C_ACCENT or C_DIM
end
tabEgg.MouseButton1Click:Connect(function() setTab("egg") end)
tabServer.MouseButton1Click:Connect(function() setTab("srv") end)

--─────────────────────────────────────────────────────────────────────────────
-- SHARED WIDGET HELPERS
--─────────────────────────────────────────────────────────────────────────────
local function makeToggle(parent, text, initial, yPos, onChanged)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 30)
    row.Position = UDim2.fromOffset(0, yPos)
    row.BackgroundColor3 = C_PANEL
    row.BorderSizePixel = 0
    row.Parent = parent
    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(0, 6)
    rc.Parent = row

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -70, 1, 0)
    lbl.Position = UDim2.fromOffset(10, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextColor3 = C_TEXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = text
    lbl.Parent = row

    local stateOn = initial
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(52, 20)
    btn.Position = UDim2.new(1, -62, 0, 5)
    btn.BackgroundColor3 = stateOn and C_ACCENT or Color3.fromRGB(60, 60, 70)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.TextColor3 = Color3.fromRGB(16, 16, 18)
    btn.Text = stateOn and "ON" or "OFF"
    btn.Parent = row
    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 5)
    bc.Parent = btn

    btn.MouseButton1Click:Connect(function()
        stateOn = not stateOn
        btn.Text = stateOn and "ON" or "OFF"
        btn.BackgroundColor3 = stateOn and C_ACCENT or Color3.fromRGB(60, 60, 70)
        if onChanged then onChanged(stateOn) end
    end)
    return row
end

--─────────────────────────────────────────────────────────────────────────────
-- EGG PAGE
--─────────────────────────────────────────────────────────────────────────────
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, 0, 0, 20)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 12
statusLabel.TextColor3 = C_ACCENT
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = "menunggu scan..."
statusLabel.Parent = eggPage

makeToggle(eggPage, "ESP (nama + jarak + highlight)", true, 24, function(on)
    CONFIG.esp = on
end)

makeToggle(eggPage, "Auto-teleport ke egg terdekat", false, 58, function(on)
    state.autoTPOn = on
    notify(on and "Auto-TP aktif" or "Auto-TP nonaktif", 2)
end)

local rangeRow = Instance.new("Frame")
rangeRow.Size = UDim2.new(1, 0, 0, 30)
rangeRow.Position = UDim2.fromOffset(0, 92)
rangeRow.BackgroundColor3 = C_PANEL
rangeRow.Parent = eggPage
local rrC = Instance.new("UICorner")
rrC.CornerRadius = UDim.new(0, 6)
rrC.Parent = rangeRow

local rangeLbl = Instance.new("TextLabel")
rangeLbl.Size = UDim2.new(1, -70, 1, 0)
rangeLbl.Position = UDim2.fromOffset(10, 0)
rangeLbl.BackgroundTransparency = 1
rangeLbl.Font = Enum.Font.Gotham
rangeLbl.TextSize = 12
rangeLbl.TextColor3 = C_TEXT
rangeLbl.TextXAlignment = Enum.TextXAlignment.Left
rangeLbl.Text = "Range maksimum"
rangeLbl.Parent = rangeRow

local rangeBox = Instance.new("TextBox")
rangeBox.Size = UDim2.fromOffset(52, 20)
rangeBox.Position = UDim2.new(1, -62, 0, 5)
rangeBox.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
rangeBox.Font = Enum.Font.GothamBold
rangeBox.TextSize = 11
rangeBox.TextColor3 = C_TEXT
rangeBox.Text = tostring(CONFIG.maxDistance)
rangeBox.Parent = rangeRow
local rbC = Instance.new("UICorner")
rbC.CornerRadius = UDim.new(0, 5)
rbC.Parent = rangeBox
rangeBox.FocusLost:Connect(function()
    local n = tonumber(rangeBox.Text)
    if n and n >= 50 then CONFIG.maxDistance = math.floor(n) else rangeBox.Text = tostring(CONFIG.maxDistance) end
end)

local eggList = Instance.new("ScrollingFrame")
eggList.Size = UDim2.new(1, 0, 1, -128)
eggList.Position = UDim2.fromOffset(0, 128)
eggList.BackgroundTransparency = 1
eggList.BorderSizePixel = 0
eggList.ScrollBarThickness = 4
eggList.CanvasSize = UDim2.new()
eggList.AutomaticCanvasSize = Enum.AutomaticSize.Y
eggList.Parent = eggPage

local eggLayout = Instance.new("UIListLayout")
eggLayout.Padding = UDim.new(0, 3)
eggLayout.SortOrder = Enum.SortOrder.LayoutOrder
eggLayout.Parent = eggList

local function renderEggList()
    for _, ch in ipairs(eggList:GetChildren()) do
        if ch:IsA("Frame") then ch:Destroy() end
    end
    local list = {}
    for inst, data in pairs(state.eggs) do
        if inst.Parent and data.part and data.part.Parent then
            local d = distTo(data.part)
            if d <= CONFIG.maxDistance then
                table.insert(list, { inst = inst, part = data.part, rarity = data.rarity, d = d })
            end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)

    for i = 1, math.min(#list, 14) do
        local e = list[i]
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, 22)
        row.BackgroundColor3 = Color3.fromRGB(24, 24, 29)
        row.LayoutOrder = i
        row.Parent = eggList
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 4)
        c.Parent = row

        local dot = Instance.new("Frame")
        dot.Size = UDim2.fromOffset(6, 6)
        dot.Position = UDim2.new(0, 6, 0.5, -3)
        dot.BackgroundColor3 = RARITY[e.rarity] or RARITY.common
        dot.Parent = row
        local dc = Instance.new("UICorner")
        dc.CornerRadius = UDim.new(1, 0)
        dc.Parent = dot

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -80, 1, 0)
        lbl.Position = UDim2.fromOffset(18, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 11
        lbl.TextColor3 = C_TEXT
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextTruncate = Enum.TextTruncate.AtEnd
        lbl.Text = e.inst.Name
        lbl.Parent = row

        local dlbl = Instance.new("TextLabel")
        dlbl.Size = UDim2.fromOffset(40, 22)
        dlbl.Position = UDim2.new(1, -78, 0, 0)
        dlbl.BackgroundTransparency = 1
        dlbl.Font = Enum.Font.GothamBold
        dlbl.TextSize = 11
        dlbl.TextColor3 = C_DIM
        dlbl.Text = string.format("%dm", math.floor(e.d))
        dlbl.Parent = row

        local tp = Instance.new("TextButton")
        tp.Size = UDim2.fromOffset(30, 16)
        tp.Position = UDim2.new(1, -38, 0, 3)
        tp.BackgroundColor3 = C_PANEL
        tp.Font = Enum.Font.GothamBold
        tp.TextSize = 10
        tp.TextColor3 = C_ACCENT
        tp.Text = "TP"
        tp.Parent = row
        local tc = Instance.new("UICorner")
        tc.CornerRadius = UDim.new(0, 4)
        tc.Parent = tp

        tp.MouseButton1Click:Connect(function()
            local char = LP.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and e.part and e.part.Parent then
                hrp.CFrame = CFrame.new(e.part.Position + Vector3.new(0, CONFIG.tpOffset, 0))
            end
        end)
    end
end

--─────────────────────────────────────────────────────────────────────────────
-- SERVER PAGE
--─────────────────────────────────────────────────────────────────────────────
local srvHead = Instance.new("Frame")
srvHead.Size = UDim2.new(1, 0, 0, 24)
srvHead.BackgroundTransparency = 1
srvHead.Parent = srvPage

local srvInfo = Instance.new("TextLabel")
srvInfo.Size = UDim2.new(1, -70, 1, 0)
srvInfo.BackgroundTransparency = 1
srvInfo.Font = Enum.Font.GothamBold
srvInfo.TextSize = 11
srvInfo.TextColor3 = C_DIM
srvInfo.TextXAlignment = Enum.TextXAlignment.Left
srvInfo.Text = "server saat ini: ..."
srvInfo.Parent = srvHead

local refreshBtn = Instance.new("TextButton")
refreshBtn.Size = UDim2.fromOffset(64, 20)
refreshBtn.Position = UDim2.new(1, -64, 0, 2)
refreshBtn.BackgroundColor3 = C_PANEL
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.TextSize = 11
refreshBtn.TextColor3 = C_ACCENT
refreshBtn.Text = "REFRESH"
refreshBtn.Parent = srvHead
local rfC = Instance.new("UICorner")
rfC.CornerRadius = UDim.new(0, 5)
rfC.Parent = refreshBtn

local srvList = Instance.new("ScrollingFrame")
srvList.Size = UDim2.new(1, 0, 1, -28)
srvList.Position = UDim2.fromOffset(0, 28)
srvList.BackgroundTransparency = 1
srvList.BorderSizePixel = 0
srvList.ScrollBarThickness = 4
srvList.CanvasSize = UDim2.new()
srvList.AutomaticCanvasSize = Enum.AutomaticSize.Y
srvList.Parent = srvPage

local srvLayout = Instance.new("UIListLayout")
srvLayout.Padding = UDim.new(0, 3)
srvLayout.SortOrder = Enum.SortOrder.LayoutOrder
srvLayout.Parent = srvList

local function playerColor(playing, max)
    if max <= 0 then return C_DIM end
    local ratio = playing / max
    if ratio >= 1 then return Color3.fromRGB(255, 110, 110) end
    if ratio >= 0.6 then return Color3.fromRGB(255, 190, 90) end
    return C_ACCENT
end

local function renderServers()
    for _, ch in ipairs(srvList:GetChildren()) do
        if ch:IsA("Frame") then ch:Destroy() end
    end
    if #state.servers == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 30)
        empty.BackgroundTransparency = 1
        empty.Font = Enum.Font.Gotham
        empty.TextSize = 11
        empty.TextColor3 = C_DIM
        empty.Text = "belum ada data — tekan REFRESH"
        empty.Parent = srvList
        return
    end

    for i, s in ipairs(state.servers) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, 24)
        row.BackgroundColor3 = Color3.fromRGB(24, 24, 29)
        row.LayoutOrder = i
        row.Parent = srvList
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 4)
        c.Parent = row

        local idlbl = Instance.new("TextLabel")
        idlbl.Size = UDim2.new(1, -130, 1, 0)
        idlbl.Position = UDim2.fromOffset(8, 0)
        idlbl.BackgroundTransparency = 1
        idlbl.Font = Enum.Font.Code
        idlbl.TextSize = 11
        idlbl.TextColor3 = C_DIM
        idlbl.TextXAlignment = Enum.TextXAlignment.Left
        idlbl.Text = string.sub(s.id, 1, 8)
        idlbl.Parent = row

        local plbl = Instance.new("TextLabel")
        plbl.Size = UDim2.fromOffset(46, 24)
        plbl.Position = UDim2.new(1, -112, 0, 0)
        plbl.BackgroundTransparency = 1
        plbl.Font = Enum.Font.GothamBold
        plbl.TextSize = 11
        plbl.TextColor3 = playerColor(s.playing, s.max)
        plbl.Text = string.format("%d/%d", s.playing, s.max)
        plbl.Parent = row

        local pinglbl = Instance.new("TextLabel")
        pinglbl.Size = UDim2.fromOffset(36, 24)
        pinglbl.Position = UDim2.new(1, -64, 0, 0)
        pinglbl.BackgroundTransparency = 1
        pinglbl.Font = Enum.Font.Gotham
        pinglbl.TextSize = 10
        pinglbl.TextColor3 = C_DIM
        pinglbl.Text = s.ping and (tostring(s.ping) .. "ms") or "-"
        pinglbl.Parent = row

        local jb = Instance.new("TextButton")
        jb.Size = UDim2.fromOffset(40, 18)
        jb.Position = UDim2.new(1, -42, 0, 3)
        jb.BackgroundColor3 = C_PANEL
        jb.Font = Enum.Font.GothamBold
        jb.TextSize = 10
        jb.TextColor3 = C_ACCENT
        jb.Text = "JOIN"
        jb.Parent = row
        local jc = Instance.new("UICorner")
        jc.CornerRadius = UDim.new(0, 4)
        jc.Parent = jb
        jb.MouseButton1Click:Connect(function() joinServer(s.id) end)
    end
end

refreshBtn.MouseButton1Click:Connect(function()
    refreshBtn.Text = "..."
    task.spawn(function()
        pcall(fetchServers)
        refreshBtn.Text = "REFRESH"
        renderServers()
    end)
end)

--─────────────────────────────────────────────────────────────────────────────
-- FOOTER
--─────────────────────────────────────────────────────────────────────────────
local footer = Instance.new("TextLabel")
footer.Size = UDim2.new(1, -24, 0, 18)
footer.Position = UDim2.new(0, 12, 1, -24)
footer.BackgroundTransparency = 1
footer.Font = Enum.Font.Gotham
footer.TextSize = 10
footer.TextColor3 = C_DIM
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.Text = "RSHIFT = sembunyikan · END = unload · v1"
footer.Parent = main

--─────────────────────────────────────────────────────────────────────────────
-- STATUS / REFRESH LOOPS
--─────────────────────────────────────────────────────────────────────────────
local function statusLoop()
    while state.alive do
        local found = 0
        for _ in pairs(state.eggs) do found = found + 1 end
        local here = #Players:GetPlayers()
        local cap = Players.MaxPlayers
        srvInfo.Text = string.format("server saat ini: %d/%d pemain", here, cap)
        statusLabel.Text = string.format(
            "egg terdeteksi: %d · tampil: %d · auto-tp: %s",
            found, state.rendered, state.autoTPOn and "ON" or "OFF"
        )
        task.wait(0.5)
    end
end

local function listLoop()
    while state.alive do
        if eggPage.Visible then pcall(renderEggList) end
        task.wait(1)
    end
end

--─────────────────────────────────────────────────────────────────────────────
-- KEYBINDS + UNLOAD
--─────────────────────────────────────────────────────────────────────────────
local function unload()
    state.alive = false
    for inst in pairs(state.espCache) do destroyESP(inst) end
    pcall(function() gui:Destroy() end)
    _G.SAE_EGGF = nil
    notify("Unloaded", 2)
end

local inputConn
inputConn = UserInputService.InputBegan:Connect(function(input, gep)
    if gep then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
    elseif input.KeyCode == Enum.KeyCode.End then
        unload()
    end
end)

closeBtn.MouseButton1Click:Connect(unload)

--────────────────────────────────────────────────────────────────────────────
-- BOOT
--─────────────────────────────────────────────────────────────────────────────
setTab("egg")
if PLACE_ID ~= 107778070777162 then
    notify("Bukan place SAE — fitur egg bisa kosong", 5)
else
    notify("Loaded. Tab SERVERS untuk pindah server.", 4)
end

_G.SAE_EGGF = {
    unload   = unload,
    config   = CONFIG,
    state    = state,
    dump     = function()
        local out = {}
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if (inst:IsA("BasePart") or inst:IsA("Model")) and matchesKeyword(inst.Name) then
                table.insert(out, inst.ClassName .. " :: " .. inst:GetFullName())
            end
        end
        local txt = table.concat(out, "\n")
        print("=== SAE DUMP (" .. #out .. " kandidat) ===\n" .. txt)
        pcall(function() setclipboard(txt) end)
        notify(#out .. " kandidat di-dump ke console & clipboard", 5)
    end,
}

task.spawn(scanLoop)
task.spawn(tpLoop)
task.spawn(statusLoop)
task.spawn(listLoop)
task.spawn(function()
    task.wait(0.5)
    pcall(fetchServers)
    if state.alive then renderServers() end
end)
