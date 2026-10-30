--[[
    ███████╗ █████╗ ███████╗    E G G F I N D E R
    ██╔════╝██╔══██╗██╔════╝    Steal an Egg — Keyless Edition
    ███████╗███████║█████╗      no key · no login · no hub · no loader
    ╚════██║██╔══██║██╔══╝
    ███████║██║  ██║███████╗    game: 10563114921 / place: 107778070777162
    ╚══════╝╚═╝  ╚═╝╚══════╝
    Author: Asta  ·  build 1.0

    KEYS
      Z            toggle ESP on/off
      RightControl toggle panel
      (panel)      drag header to move

    NOTE
      Uses the executor's Drawing API when available (unlimited, zero-lag).
      Falls back to Highlight + BillboardGui on executors without Drawing
      (those are capped at ~30 highlights, so only the nearest are lit).
--]]

if getgenv and getgenv().SAE_EGGFINDER then
    pcall(function() getgenv().SAE_EGGFINDER.unload() end)
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local LP = Players.LocalPlayer
local HAS_DRAWING = (typeof(Drawing) == "table" and type(Drawing.new) == "function")
local MAX_WALK = 30000

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------
local S = {
    esp = true,
    panel = true,
    own = false,          -- show eggs sitting on my own base
    dist = 800,
    query = "",
    tiers = {},
    tracked = {},         -- [instance] = entry
    hlBudget = 30,
    alive = true,
    conns = {},
}

---------------------------------------------------------------------------
-- rarity table: keyword -> {label, color, tier}
-- longest/most specific keys first, tier 9 = event tier
---------------------------------------------------------------------------
local RARITY = {
    { "secret",     "SECRET",    Color3.fromRGB(0, 255, 210), 8 },
    { "godly",      "GODLY",     Color3.fromRGB(255, 120, 40), 7 },
    { "divine",     "DIVINE",    Color3.fromRGB(255, 215, 0),  7 },
    { "celestial",  "CELESTIAL", Color3.fromRGB(180, 220, 255),7 },
    { "mythic",     "MYTHIC",    Color3.fromRGB(230, 40, 90),  6 },
    { "mythical",   "MYTHIC",    Color3.fromRGB(230, 40, 90),  6 },
    { "angel",      "ANGEL",     Color3.fromRGB(255, 245, 200),6 },
    { "demon",      "DEMON",     Color3.fromRGB(150, 30, 60),  6 },
    { "legendary",  "LEGENDARY", Color3.fromRGB(255, 150, 0),  5 },
    { "epic",       "EPIC",      Color3.fromRGB(170, 70, 255), 4 },
    { "rare",       "RARE",      Color3.fromRGB(60, 150, 255), 3 },
    { "uncommon",   "UNCOMMON",  Color3.fromRGB(70, 210, 110), 2 },
    { "common",     "COMMON",    Color3.fromRGB(150, 155, 165),1 },
    { "basic",      "COMMON",    Color3.fromRGB(150, 155, 165),1 },
    { "event",      "EVENT",     Color3.fromRGB(255, 80, 200), 9 },
    { "hallow",     "EVENT",     Color3.fromRGB(255, 110, 40), 9 },
    { "fantasy",    "FANTASY",   Color3.fromRGB(255, 130, 220),9 },
    { "titan",      "TITAN",     Color3.fromRGB(140, 100, 255),7 },
    { "rift",       "RIFT",      Color3.fromRGB(120, 60, 200), 6 },
    { "enchanted",  "ENCHANTED", Color3.fromRGB(90, 255, 170), 5 },
}
local TIER_DEF = {
    [1] = { "Common",    Color3.fromRGB(150, 155, 165) },
    [2] = { "Uncommon",  Color3.fromRGB(70, 210, 110) },
    [3] = { "Rare",      Color3.fromRGB(60, 150, 255) },
    [4] = { "Epic",      Color3.fromRGB(170, 70, 255) },
    [5] = { "Legendary", Color3.fromRGB(255, 150, 0) },
    [6] = { "Mythic",    Color3.fromRGB(230, 40, 90) },
    [7] = { "Divine",    Color3.fromRGB(255, 215, 0) },
    [8] = { "Secret",    Color3.fromRGB(0, 255, 210) },
    [9] = { "Event",     Color3.fromRGB(255, 80, 200) },
}
for i = 1, 9 do S.tiers[i] = true end

local DECOY = {
    "spawner", "pedestal", "stand", "platform", "sign", "hitbox", "label",
    "display", "text", "billboard", "proximity", "clickdetector", "slot",
    "frame", "spawn", "decor", "model", "holder", "container", "zone",
}
local OWNERKEYS = {
    "owner", "ownerid", "owneruserid", "placedby", "placedbyuserid",
    "userid", "player", "playername", "username", "displayname",
}

local function lower(s)
    return string.lower(tostring(s))
end

local function contains(s, frag)
    return string.find(s, frag, 1, true) ~= nil
end

local function classify(name, inst)
    local n = lower(name)
    local score, tier, label, color = 0, 1, nil, nil

    for _, d in ipairs(DECOY) do
        if contains(n, d) then score = score - 1 end
    end
    if contains(n, "egg") then score = score + 3 end
    for _, r in ipairs(RARITY) do
        if contains(n, r[1]) then
            score = score + 3
            tier, label, color = r[4], r[2], r[3]
            break
        end
    end

    local rar = inst:GetAttribute("Rarity") or inst:GetAttribute("rarity")
    if rar ~= nil then
        score = score + 4
        local rn = lower(rar)
        for _, r in ipairs(RARITY) do
            if contains(rn, r[1]) then
                tier, label, color = r[4], r[2], r[3]
                break
            end
        end
        if not label then label = string.upper(rn) end
    end
    for _, a in ipairs({ "EggName", "EggId", "PetName", "Price", "Cost", "Chance" }) do
        if inst:GetAttribute(a) ~= nil then score = score + 2 break end
    end
    if inst:FindFirstChildOfClass("BillboardGui") then score = score + 2 end

    if score < 3 then return nil end
    if not label then label = string.upper(name) end
    return {
        tier = tier,
        label = label,
        color = color or Color3.fromRGB(200, 200, 200),
    }
end

local function ownerOf(inst)
    local node = inst
    for _ = 1, 5 do
        if not node then break end
        for _, k in ipairs(OWNERKEYS) do
            local v = node:GetAttribute(k) or node:GetAttribute(string.upper(k))
            if type(v) == "string" and v ~= "" and #v < 32 then return v end
            if type(v) == "number" and v > 0 then
                local ok, nm = pcall(function() return Players:GetNameFromUserIdAsync(v) end)
                if ok then return nm end
                return tostring(v)
            end
        end
        local oc = node:FindFirstChild("Owner", true)
        if oc and (oc:IsA("ObjectValue") or oc:IsA("StringValue")) then
            local v = oc.Value
            if typeof(v) == "Instance" and v:IsA("Player") then return v.Name end
            if type(v) == "string" and v ~= "" then return v end
        end
        node = node.Parent
    end
    return nil
end

local function anchorPart(inst)
    if inst:IsA("BasePart") then return inst end
    local p = inst.PrimaryPart
    if p then return p end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function camera()
    return workspace.CurrentCamera
end

local function getHRP()
    local ch = LP.Character
    if not ch then return nil end
    return ch:FindFirstChild("HumanoidRootPart")
end

local function distTo(pos)
    local p = getHRP()
    if not p then return nil end
    return math.floor((p.Position - pos).Magnitude)
end

---------------------------------------------------------------------------
-- ESP engine (Drawing preferred)
---------------------------------------------------------------------------
local function makeEsp(entry, part)
    if HAS_DRAWING then
        local box = Drawing.new("Square")
        box.Thickness = 1.5
        box.Filled = false
        box.Transparency = 1
        local txt = Drawing.new("Text")
        txt.Size = 14
        txt.Center = false
        txt.Outline = true
        txt.OutlineColor = Color3.new(0, 0, 0)
        txt.Transparency = 1
        entry.box, entry.txt = box, txt
        box.Color, txt.Color = entry.color, entry.color
    else
        local hl = Instance.new("Highlight")
        hl.FillTransparency = 0.65
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillColor, hl.OutlineColor = entry.color, entry.color
        hl.Parent = part

        local bb = Instance.new("BillboardGui")
        bb.Size = UDim2.fromOffset(190, 34)
        bb.StudsOffset = Vector3.new(0, 2.6, 0)
        bb.AlwaysOnTop = true
        bb.MaxDistance = 5000
        local lb = Instance.new("TextLabel")
        lb.Size = UDim2.fromScale(1, 1)
        lb.BackgroundTransparency = 1
        lb.Font = Enum.Font.Code
        lb.TextSize = 13
        lb.TextStrokeTransparency = 0
        lb.TextColor3 = entry.color
        lb.Text = ""
        lb.Parent = bb
        bb.Parent = part
        entry.hl, entry.bb = hl, bb
    end
end

local function destroyEsp(entry)
    if entry.box then pcall(function() entry.box:Remove() end) end
    if entry.txt then pcall(function() entry.txt:Remove() end) end
    if entry.hl then pcall(function() entry.hl:Destroy() end) end
    if entry.bb then pcall(function() entry.bb:Destroy() end) end
    entry.box, entry.txt, entry.hl, entry.bb = nil, nil, nil, nil
end

local function newEntry(inst)
    local cls = classify(inst.Name, inst)
    if not cls then return end
    local part = anchorPart(inst)
    if not part then return end
    local entry = {
        inst = inst,
        part = part,
        label = cls.label,
        tier = cls.tier,
        color = cls.color,
        owner = ownerOf(inst),
    }
    S.tracked[inst] = entry
    pcall(makeEsp, entry, part)
end

local function dropEntry(inst)
    local e = S.tracked[inst]
    if not e then return end
    S.tracked[inst] = nil
    destroyEsp(e)
end

---------------------------------------------------------------------------
-- owner / filter helpers
---------------------------------------------------------------------------
local function ownerIsMe(e)
    if not e.owner then return false end
    return e.owner == LP.Name or e.owner == tostring(LP.UserId) or e.owner == LP.DisplayName
end

local function passFilter(e, d)
    if not S.tiers[e.tier] then return false end
    if not S.own and ownerIsMe(e) then return false end
    if S.query ~= "" then
        local hay = lower(e.label) .. " " .. lower(e.inst.Name) .. " " .. lower(e.owner or "")
        if not contains(hay, S.query) then return false end
    end
    if d and d > S.dist then return false end
    return true
end

---------------------------------------------------------------------------
-- world scan
---------------------------------------------------------------------------
local function hasTrackedAncestor(inst)
    local node = inst.Parent
    while node and node ~= workspace do
        if S.tracked[node] then return true end
        node = node.Parent
    end
    return false
end

local function tryAdd(inst)
    if S.tracked[inst] then return end
    if not inst:IsDescendantOf(workspace) then return end
    if LP.Character and inst:IsDescendantOf(LP.Character) then return end
    if hasTrackedAncestor(inst) then return end
    newEntry(inst)
end

local function scanOnce()
    -- tagged eggs first (games that use CollectionService)
    pcall(function()
        for _, tag in ipairs(CollectionService:GetAllTags()) do
            if contains(lower(tag), "egg") then
                for _, inst in ipairs(CollectionService:GetTagged(tag)) do
                    if inst:IsA("Model") or inst:IsA("BasePart") then
                        tryAdd(inst)
                    end
                end
            end
        end
    end)

    -- brute walk with instance budget
    local budget = 30000
    local function walk(parent)
        if budget <= 0 then return end
        for _, d in ipairs(parent:GetChildren()) do
            budget = budget - 1
            if budget <= 0 then return end
            if d:IsA("Model") or d:IsA("BasePart") or d:IsA("Folder") then
                if d:IsA("Model") or d:IsA("BasePart") then
                    tryAdd(d)
                end
                if d:IsA("Model") or d:IsA("Folder") then
                    walk(d)
                end
            end
        end
    end
    walk(workspace)

    -- drop despawned
    for inst, _ in pairs(S.tracked) do
        if not inst.Parent or not inst:IsDescendantOf(workspace) then
            dropEntry(inst)
        end
    end
end

---------------------------------------------------------------------------
-- render loop
---------------------------------------------------------------------------
local function w2s(cam, pos)
    local ok, p, on = pcall(function()
        return cam:WorldToViewportPoint(pos)
    end)
    if not ok then return nil, false end
    return Vector2.new(p.X, p.Y), on
end

local shown = 0

table.insert(S.conns, RunService.RenderStepped:Connect(function()
    if not S.alive then return end
    local cam = camera()
    if not cam then return end

    shown = 0
    local hlUsed = 0
    for inst, e in pairs(S.tracked) do
        local ok, pos = pcall(function() return e.part.Position end)
        if not ok or not inst.Parent then
            dropEntry(inst)
        else
            local d = distTo(pos)
            local visible = S.esp and d ~= nil and passFilter(e, d)
            if visible then
                local sp, on = w2s(cam, pos)
                visible = on and sp ~= nil
                if visible then
                    shown = shown + 1
                    local size = math.clamp(2600 / math.max(d, 1), 16, 110)
                    if HAS_DRAWING then
                        local t = e.label .. "  " .. d .. "m"
                        if e.owner then t = t .. "  @" .. e.owner end
                        e.box.Size = Vector2.new(size, size * 1.25)
                        e.box.Position = Vector2.new(sp.X - size / 2, sp.Y - size / 2)
                        e.box.Visible = true
                        e.txt.Position = Vector2.new(sp.X - size / 2, sp.Y - size / 2 - 20)
                        e.txt.Text = t
                        e.txt.Visible = true
                    else
                        if e.hl and hlUsed < S.hlBudget then
                            e.hl.Enabled = true
                            hlUsed = hlUsed + 1
                        end
                        if e.bb then
                            e.bb.Enabled = true
                            local t = e.label .. "  " .. d .. "m"
                            if e.owner then t = t .. "  @" .. e.owner end
                            e.bb.TextLabel.Text = t
                        end
                    end
                end
            end
            if not visible then
                if e.box then e.box.Visible = false end
                if e.txt then e.txt.Visible = false end
                if e.hl then e.hl.Enabled = false end
                if e.bb then e.bb.Enabled = false end
            end
        end
    end
end))

---------------------------------------------------------------------------
-- teleport
---------------------------------------------------------------------------
local function tpTo(entry)
    local hrp = getHRP()
    if not hrp then return end
    local ok, pos = pcall(function() return entry.part.Position end)
    if not ok then return end
    task.spawn(function()
        local target = CFrame.new(pos + Vector3.new(0, 4, 0))
        hrp.CFrame = target
        task.wait(0.12)
        hrp.CFrame = target
        hrp.AssemblyLinearVelocity = Vector3.zero
    end)
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local C = {
    bg = Color3.fromRGB(16, 18, 26),
    bg2 = Color3.fromRGB(24, 27, 38),
    bg3 = Color3.fromRGB(34, 38, 52),
    stroke = Color3.fromRGB(58, 64, 88),
    text = Color3.fromRGB(230, 232, 240),
    dim = Color3.fromRGB(130, 136, 155),
    accent = Color3.fromRGB(255, 196, 60),
    on = Color3.fromRGB(80, 220, 130),
    off = Color3.fromRGB(70, 74, 92),
}

local parentGui
do
    local ok, ui = pcall(function()
        return gethui and gethui() or nil
    end)
    if ok and ui then parentGui = ui end
end
if not parentGui then parentGui = game:FindFirstChildOfClass("CoreGui") end
if not parentGui then parentGui = LP:FindFirstChildOfClass("PlayerGui") end

local gui = Instance.new("ScreenGui")
gui.Name = "SAE_EggFinder"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9999
gui.IgnoreGuiInset = true
gui.Parent = parentGui

local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local main = mk("Frame", {
    Size = UDim2.fromOffset(300, 470),
    Position = UDim2.fromOffset(40, 60),
    BackgroundColor3 = C.bg,
    BorderSizePixel = 0,
    Active = true,
}, gui)
mk("UICorner", { CornerRadius = UDim.new(0, 10) }, main)
mk("UIStroke", { Color = C.stroke, Thickness = 1 }, main)

local header = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 34),
    BackgroundColor3 = C.bg2,
    BorderSizePixel = 0,
}, main)
mk("UICorner", { CornerRadius = UDim.new(0, 10) }, header)
mk("TextLabel", {
    Size = UDim2.new(1, -40, 1, 0),
    Position = UDim2.fromOffset(12, 0),
    BackgroundTransparency = 1,
    Font = Enum.Font.Code,
    TextSize = 14,
    TextColor3 = C.accent,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "EGG FINDER · KEYLESS",
}, header)
local closeBtn = mk("TextButton", {
    Size = UDim2.fromOffset(24, 24),
    Position = UDim2.new(1, -30, 0, 5),
    BackgroundColor3 = C.bg3,
    Font = Enum.Font.Code,
    TextSize = 14,
    TextColor3 = C.text,
    Text = "X",
}, header)
mk("UICorner", { CornerRadius = UDim.new(0, 6) }, closeBtn)

local body = mk("Frame", {
    Size = UDim2.new(1, -16, 1, -34 - 24),
    Position = UDim2.fromOffset(8, 40),
    BackgroundTransparency = 1,
}, main)

local status = mk("TextLabel", {
    Size = UDim2.new(1, 0, 0, 18),
    Position = UDim2.new(0, 8, 1, -22),
    BackgroundTransparency = 1,
    Font = Enum.Font.Code,
    TextSize = 12,
    TextColor3 = C.dim,
    TextXAlignment = Enum.TextXAlignment.Left,
    Text = "...",
}, main)

local function checkbox(parent, pos, text, get, set)
    local b = mk("TextButton", {
        Size = UDim2.fromOffset(128, 22),
        Position = pos,
        BackgroundColor3 = C.bg2,
        Font = Enum.Font.Code,
        TextSize = 12,
        TextColor3 = C.text,
        Text = "",
    }, parent)
    mk("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
    local dot = mk("Frame", {
        Size = UDim2.fromOffset(10, 10),
        Position = UDim2.new(0, 8, 0, 6),
        BackgroundColor3 = C.off,
        BorderSizePixel = 0,
    }, b)
    mk("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
    mk("TextLabel", {
        Size = UDim2.new(1, -30, 1, 0),
        Position = UDim2.fromOffset(24, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Code,
        TextSize = 12,
        TextColor3 = C.dim,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = text,
    }, b)
    local function sync()
        dot.BackgroundColor3 = get() and C.on or C.off
    end
    b.MouseButton1Click:Connect(function()
        set(not get())
        sync()
    end)
    sync()
    return sync
end

local function chip(parent, pos, tier)
    local def = TIER_DEF[tier]
    local b = mk("TextButton", {
        Size = UDim2.fromOffset(85, 20),
        Position = pos,
        BackgroundColor3 = C.bg2,
        Font = Enum.Font.Code,
        TextSize = 11,
        TextColor3 = def[2],
        Text = def[1],
    }, parent)
    mk("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
    local function sync()
        if S.tiers[tier] then
            b.BackgroundColor3 = C.bg3
            b.TextColor3 = def[2]
        else
            b.BackgroundColor3 = C.bg2
            b.TextColor3 = C.dim
        end
    end
    b.MouseButton1Click:Connect(function()
        S.tiers[tier] = not S.tiers[tier]
        sync()
    end)
    sync()
end

-- toggles
local syncEsp = checkbox(body, UDim2.fromOffset(0, 0), "ESP", function() return S.esp end, function(v) S.esp = v end)
local syncOwn = checkbox(body, UDim2.fromOffset(136, 0), "Hide my eggs", function() return not S.own end, function(v) S.own = not v end)

-- rarity chips 3x3
local rows = { 0, 25, 50 }
for t = 1, 9 do
    local col = (t - 1) % 3
    local row = rows[math.floor((t - 1) / 3) + 1]
    chip(body, UDim2.fromOffset(col * 92, 30), t)
end

-- distance presets
local dRow = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 22),
    Position = UDim2.fromOffset(0, 82),
    BackgroundTransparency = 1,
}, body)
for i, dv in ipairs({ 300, 800, 1500, 3000, 99999 }) do
    local b = mk("TextButton", {
        Size = UDim2.fromOffset(52, 22),
        Position = UDim2.fromOffset((i - 1) * 56, 0),
        BackgroundColor3 = C.bg2,
        Font = Enum.Font.Code,
        TextSize = 11,
        TextColor3 = C.dim,
        Text = (dv == 99999 and "ALL" or (dv .. "m")),
    }, dRow)
    mk("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
    b.MouseButton1Click:Connect(function()
        S.dist = dv
        for _, o in ipairs(dRow:GetChildren()) do
            if o:IsA("TextButton") then o.BackgroundColor3 = C.bg2 end
        end
        b.BackgroundColor3 = C.bg3
        b.TextColor3 = C.accent
    end)
end

-- search
local search = mk("TextBox", {
    Size = UDim2.new(1, 0, 0, 24),
    Position = UDim2.fromOffset(0, 112),
    BackgroundColor3 = C.bg2,
    Font = Enum.Font.Code,
    TextSize = 12,
    TextColor3 = C.text,
    PlaceholderText = "search egg / owner...",
    Text = "",
    ClearTextOnFocus = false,
}, body)
mk("UICorner", { CornerRadius = UDim.new(0, 6) }, search)
mk("UIPadding", { PaddingLeft = UDim.new(0, 8) }, search)
search:GetPropertyChangedSignal("Text"):Connect(function()
    S.query = lower(search.Text)
end)

-- list
local list = mk("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, -144),
    Position = UDim2.fromOffset(0, 144),
    BackgroundColor3 = C.bg2,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = C.accent,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, body)
mk("UICorner", { CornerRadius = UDim.new(0, 8) }, list)
mk("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, list)
mk("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, list)

local rowTemplate = mk("Frame", {
    Size = UDim2.new(1, -6, 0, 24),
    BackgroundColor3 = C.bg3,
    BorderSizePixel = 0,
}, nil)
mk("UICorner", { CornerRadius = UDim.new(0, 6) }, rowTemplate)
local dotTpl = mk("Frame", {
    Name = "dot",
    Size = UDim2.fromOffset(8, 8),
    Position = UDim2.new(0, 7, 0, 8),
    BorderSizePixel = 0,
}, rowTemplate)
mk("UICorner", { CornerRadius = UDim.new(1, 0) }, dotTpl)
mk("TextLabel", {
    Size = UDim2.new(1, -110, 1, 0),
    Position = UDim2.fromOffset(20, 0),
    BackgroundTransparency = 1,
    Font = Enum.Font.Code,
    TextSize = 12,
    TextColor3 = C.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Name = "Info",
}, rowTemplate)
local tpTpl = mk("TextButton", {
    Size = UDim2.fromOffset(40, 18),
    Position = UDim2.new(1, -46, 0, 3),
    BackgroundColor3 = C.bg2,
    Font = Enum.Font.Code,
    TextSize = 11,
    TextColor3 = C.accent,
    Text = "TP",
}, rowTemplate)
mk("UICorner", { CornerRadius = UDim.new(0, 5) }, tpTpl)

local function refreshList()
    for _, ch in ipairs(list:GetChildren()) do
        if ch:IsA("Frame") then ch:Destroy() end
    end
    local arr = {}
    for inst, e in pairs(S.tracked) do
        local ok, pos = pcall(function() return e.part.Position end)
        if ok and inst.Parent then
            local d = distTo(pos)
            if passFilter(e, d) then
                table.insert(arr, { e = e, d = d or 99999 })
            end
        end
    end
    table.sort(arr, function(a, b) return a.d < b.d end)
    local n = math.min(#arr, 80)
    for i = 1, n do
        local e = arr[i].e
        local row = rowTemplate:Clone()
        row.Parent = list
        row.dot.BackgroundColor3 = e.color
        local info = row.Info
        info.Text = e.label .. "  " .. arr[i].d .. "m"
            .. (e.owner and ("  @" .. e.owner) or "")
        info.TextColor3 = e.color
        row.TP.MouseButton1Click:Connect(function()
            tpTo(e)
        end)
    end
    return #arr
end

---------------------------------------------------------------------------
-- background threads
---------------------------------------------------------------------------
task.spawn(function()
    while S.alive do
        pcall(scanOnce)
        task.wait(1.2)
    end
end)

task.spawn(function()
    while S.alive do
        local ok = pcall(refreshList)
        if ok then
            local cnt = 0
            for _ in pairs(S.tracked) do cnt = cnt + 1 end
            status.Text = string.format("ESP:%s  tracked:%d  shown:%d  range:%s",
                S.esp and "ON" or "OFF", cnt, shown,
                S.dist >= 99999 and "ALL" or (S.dist .. "m"))
        end
        task.wait(0.35)
    end
end)

-- drag
do
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    table.insert(S.conns, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
    table.insert(S.conns, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
end

closeBtn.MouseButton1Click:Connect(function()
    main.Visible = false
end)

-- keybinds
table.insert(S.conns, UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.Z then
        S.esp = not S.esp
        syncEsp()
    elseif input.KeyCode == Enum.KeyCode.RightControl then
        main.Visible = not main.Visible
    end
end))

---------------------------------------------------------------------------
-- unload + export
---------------------------------------------------------------------------
local function unload()
    S.alive = false
    for _, c in ipairs(S.conns) do
        pcall(function() c:Disconnect() end)
    end
    for inst, e in pairs(S.tracked) do
        destroyEsp(e)
        S.tracked[inst] = nil
    end
    pcall(function() gui:Destroy() end)
    if getgenv then getgenv().SAE_EGGFINDER = nil end
end

if getgenv then
    getgenv().SAE_EGGFINDER = {
        unload = unload,
        state = S,
        tp = tpTo,
        debug = { scan = scanOnce, add = tryAdd, classify = classify },
    }
end

print("[SAE-EggFinder] loaded · Drawing=" .. tostring(HAS_DRAWING) .. " · Z=esp RightCtrl=panel")
