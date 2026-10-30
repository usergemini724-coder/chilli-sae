--[[═══════════════════════════════════════════════════════════════════════════
    SAE FINDER v8  ·  CLEAN DARK MINIMAL  ·  FULL REBUILD
    Game  : Steal An Egg (place 107778070777162, max 7)
    Load  : loadstring(game:HttpGet(".../sae-eggf.lua?v=8"))()
    Keys  : RIGHT-SHIFT = toggle UI      END = unload
    Tabs  : [FINDER] [SERVERS] [SETTINGS]

    v8 = replace total. Misi: meniru Chilli Finder, keyless.
      · UI baru: clean dark minimal — flat panel, 1 aksen, hover, toast slide,
        toggle knob animasi, tab pill, occupancy BAR di server list
      · FINDER: feed flat Chilli-style (1 baris = 1 egg) + SEARCH BOX baru
      · Filter chips: AUTO · MIN (default Any) · RARITY · MUT · CAP · RESET · CLEAR
        CAP = batas pemain server utk JOIN/AUTO hop (≤2/≤4/≤6/Any-non-full),
        7/7 FULL selalu dibuang di semua mode → "server tidak full" by design
      · Otak akurasi v7 dipertahankan utuh:
        - extractInfo per-depth scoping (label telur tetangga tidak menular)
        - sanity clamp 12x DB base
        - parseMoney koma + suffix lowercase
        - PET_DB 122 pet (wiki snapshot) sebagai fallback value
        - union detection (strict ∪ name ∪ billboard-label) + pending 90s
      · Feed persist di disk executor → tahan teleport/reinject
      · TOP-10 dinamis lintas server = highlight emas (JOIN ≤6/7 = RACE)
      · RESET-WAIT: AUTO hop hanya di jendela ±25s setelah tick reset 300s
      · ZERO telemetry: hanya roblox.com + raw.githubusercontent.com
      · TANPA auto-steal / auto-race / anti-hit — pure finder + join
═══════════════════════════════════════════════════════════════════════════]]

-- unload build lama (v7 maupun v8 sebelumnya)
if _G.SAE_FINDER or _G.SAE_EGGF then
    task.spawn(function()
        pcall(function() if _G.SAE_FINDER then _G.SAE_FINDER.unload() end end)
        pcall(function() if _G.SAE_EGGF then _G.SAE_EGGF.unload() end end)
    end)
    task.wait(0.2)
end

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")
local StarterGui        = game:GetService("StarterGui")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local LP = Players.LocalPlayer
local PLACE_ID = game.PlaceId

--─────────────────────────────────────────────────────────────────────────────
-- CONFIG
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
    resetCycle    = 300,   -- All-Egg Reset ±300s (terverifikasi)
    pendingWindow = 90,
    feedExpiry    = 300,
}

local RARITY_ORDER = { "common", "uncommon", "rare", "epic", "legendary",
                       "cosmic", "mythic", "secret", "eternal", "divine" }
local RARITY = {
    common    = Color3.fromRGB(180, 180, 180),
    uncommon  = Color3.fromRGB( 90, 220, 110),
    rare      = Color3.fromRGB( 80, 160, 255),
    epic      = Color3.fromRGB(180, 100, 240),
    legendary = Color3.fromRGB(255, 175, 60),
    cosmic    = Color3.fromRGB(150,  90, 255),
    mythic    = Color3.fromRGB(255,  80, 120),
    secret    = Color3.fromRGB(255, 240, 120),
    eternal   = Color3.fromRGB(255, 255, 180),
    divine    = Color3.fromRGB( 60, 255, 220),
}

--─────────────────────────────────────────────────────────────────────────────
-- MUTASI (7) — stacking ADDITIF: eff = 1 + Σ(scalar − 1)
--─────────────────────────────────────────────────────────────────────────────
local MUT_MULT = {
    ["Silver"]       = 1.2,
    ["Golden"]       = 2.5,
    ["Rainbow"]      = 3.5,
    ["Bloom"]        = 1.25,
    ["Spirit Bloom"] = 2.5,
    ["Parasite"]     = 3.0,
    ["Fractured"]    = 2.75,
}
local MUT_COLORS = {
    ["Silver"]       = Color3.fromRGB(200, 210, 225),
    ["Golden"]       = Color3.fromRGB(255, 200, 60),
    ["Rainbow"]      = Color3.fromRGB(255, 110, 220),
    ["Bloom"]        = Color3.fromRGB(255, 140, 190),
    ["Spirit Bloom"] = Color3.fromRGB(120, 255, 200),
    ["Parasite"]     = Color3.fromRGB(150, 255,  90),
    ["Fractured"]    = Color3.fromRGB(255, 120,  70),
}
local MUT_TOKENS = {
    { tok = "spirit bloom", can = "Spirit Bloom" },
    { tok = "greatbloom",   can = "Spirit Bloom" },
    { tok = "silver",       can = "Silver"       },
    { tok = "golden",       can = "Golden"       },
    { tok = "rainbow",      can = "Rainbow"      },
    { tok = "parasite",     can = "Parasite"     },
    { tok = "monstrous",    can = "Parasite"     },
    { tok = "fractured",    can = "Fractured"    },
    { tok = "sakura",       can = "Bloom"        },
    { tok = "bloom",        can = "Bloom"        },
    { tok = "boss",         can = "Fractured"    },
}

local function mutEffMult(muts)
    local eff = 1
    for _, m in ipairs(muts or {}) do
        local sc = MUT_MULT[m]
        if sc then eff = eff + (sc - 1) end
    end
    return eff
end

--─────────────────────────────────────────────────────────────────────────────
-- PET DB (fallback value) — snapshot wiki 2026-09-28, 122 slot
--─────────────────────────────────────────────────────────────────────────────
local PET_DB = {
    ["chicken"]={1,"Common"},["dog"]={2,"Common"},["bird"]={8,"Uncommon"},
    ["burrowing owl"]={35,"Rare"},["owl"]={35,"Rare"},["raccoon"]={45,"Rare"},
    ["bear"]={240,"Epic"},["fox"]={180,"Epic"},["brr brr patapim"]={1800,"Legendary"},
    ["frog"]={3,"Common"},["duckling"]={4,"Common"},["catfish"]={12,"Uncommon"},
    ["turtle"]={60,"Rare"},["trulimero trulicina"]={260,"Epic"},["swan"]={320,"Epic"},
    ["axolotl"]={2800,"Legendary"},["leviathan"]={220000,"Cosmic"},
    ["jerboa"]={6,"Common"},["fennec"]={18,"Uncommon"},["camel"]={75,"Rare"},
    ["tob tobi tob tob"]={325,"Epic"},["snake"]={3600,"Legendary"},
    ["sand spider"]={16000,"Mythic"},["scorpion"]={18500,"Mythic"},
    ["royal sphinx"]={280000,"Cosmic"},
    ["chimpanzee"]={90,"Rare"},["toucan"]={110,"Rare"},["crocodile"]={420,"Epic"},
    ["gorilla"]={4800,"Legendary"},["orangutini ananassini"]={5500,"Legendary"},
    ["spider"]={22000,"Mythic"},["tiger"]={28000,"Mythic"},["king snake"]={3500000,"Secret"},
    ["penguin"]={140,"Rare"},["walrus"]={600,"Epic"},["polar bear"]={7000,"Legendary"},
    ["sabertooth tiger"]={35000,"Mythic"},["mammoth"]={42000,"Mythic"},
    ["king mammoth"]={400000,"Cosmic"},["yeti"]={5000000,"Secret"},
    ["ice dragon"]={65000000,"Eternal"},
    ["lava gecko"]={180,"Rare"},["lava frog"]={850,"Epic"},["lavafrog"]={850,"Epic"},
    ["flaming bull"]={9500,"Legendary"},["lava iguana"]={11000,"Legendary"},
    ["chillin chilli"]={55000,"Mythic"},["cerberus"]={8000000,"Secret"},
    ["phoenix"]={85000000,"Eternal"},["lava dragon"]={100000000,"Eternal"},
    ["parrotfish"]={220,"Rare"},["swordfish"]={1100,"Epic"},["shark"]={15000,"Legendary"},
    ["orca"]={80000,"Mythic"},["whale shark"]={700000,"Cosmic"},
    ["beluga whale"]={850000,"Cosmic"},["kraken"]={15000000,"Secret"},
    ["el maja"]={130000000,"Eternal"},
    ["dodo"]={280,"Rare"},["pterodactyl"]={22000,"Legendary"},
    ["ankylosaurus"]={120000,"Mythic"},["triceratops"]={1200000,"Cosmic"},
    ["bronto"]={1500000,"Cosmic"},["t-rex"]={25000000,"Secret"},["trex"]={25000000,"Secret"},
    ["tralaledon"]={32000000,"Secret"},["mosasaurus"]={180000000,"Eternal"},
    ["centapede"]={1500,"Epic"},["cosmic gecko"]={30000,"Legendary"},
    ["cosmic gorilla"]={180000,"Mythic"},["la vacca saturno saturnita"]={2200000,"Cosmic"},
    ["cosmic skeleton boss"]={45000000,"Secret"},["cosmic dragon"]={60000000,"Secret"},
    ["eternal lunar dragon"]={250000000,"Eternal"},["unicorn"]={1000000000,"Divine"},
    ["crane"]={4000,"Epic"},["salamander"]={74000,"Legendary"},
    ["red panda"]={450000,"Mythic"},["snowy owl"]={7500000,"Cosmic"},
    ["koi"]={12000000,"Cosmic"},["stag"]={145000000,"Secret"},
    ["oni tiger"]={600000000,"Eternal"},["kitsune"]={1800000000,"Divine"},
    ["spideron"]={95000,"Legendary"},["crustacia"]={130000,"Legendary"},
    ["bladehide"]={750000,"Mythic"},["mantaris"]={11000000,"Cosmic"},
    ["rhinotaur"]={17500000,"Cosmic"},["mutant shark"]={215000000,"Secret"},
    ["gorilla king"]={880000000,"Eternal"},["nightflame"]={3000000000,"Divine"},
    ["scorpio"]={10000,"Legendary"},["froggo"]={50000,"Mythic"},
    ["crawler"]={1500000,"Cosmic"},["crocodon"]={30000000,"Secret"},
    ["krakenoid"]={500000000,"Eternal"},["dreadscale"]={2000000000,"Divine"},
    ["mecha scorpio"]={45000000,"Secret"},["mecha froggo"]={155000000,"Secret"},
    ["mecha crawler"]={320000000,"Cosmic"},["mecha crocodon"]={680000000,"Eternal"},
    ["mecha krakenoid"]={1000000000,"Eternal"},["mecha dreadscale"]={4000000000,"Divine"},
    ["tung tung sahur"]={100,"Rare"},["bananita dolphinita"]={400,"Epic"},
    ["belula beluga"]={40000,"Mythic"},["mangolini parrochini"]={800000,"Cosmic"},
    ["bomboclat crocolat"]={20000000,"Secret"},["strawberry elephant"]={110000000,"Eternal"},
    ["drilla"]={137000000,"Cosmic"},
    ["rift eye"]={11000,"Legendary"},["void angler"]={30000,"Legendary"},
    ["riftwing"]={220000,"Mythic"},["shardling"]={450000,"Mythic"},
    ["voidmaw"]={50000,"Mythic"},["dreadclaw"]={2200000,"Cosmic"},
    ["shattered ram"]={8000000,"Cosmic"},["ventinal"]={585000,"Cosmic"},
    ["mawbreaker"]={60000000,"Secret"},["shardwing"]={145000000,"Secret"},
    ["wendigo"]={15000000,"Secret"},["shattered drake"]={800000000,"Eternal"},
    ["void serpent"]={900000000,"Eternal"},["world eater"]={500000000,"Eternal"},
    ["shattered colossus"]={3500000000,"Divine"},
}

--─────────────────────────────────────────────────────────────────────────────
-- STATE + FILTER
--─────────────────────────────────────────────────────────────────────────────
local state = {
    eggs       = {},
    espCache   = {},
    rendered   = 0,
    autoTPOn   = false,
    lastTP     = 0,
    lastHop    = 0,
    servers    = {},
    srvById    = {},
    srvAt      = 0,
    currentJob = nil,
    fetching   = false,
    scanMode   = "-",
    alive      = true,
}

-- FILTER.minValue default 0 = Any (feed cepat terisi; MIN tinggi = kosong)
-- FILTER.capFilter: 4/2/6 = batas pemain, 0 = Any (yang penting bukan 7/7)
local FILTER = {
    auto       = false,
    interval   = 5,
    minValue   = 0,
    rarity     = "any",
    mut        = "any",
    capFilter  = 4,
    waitReset  = false,
    search     = "",
}
local joinServer, joinFinderServer, fetchServers, pickHopTarget, matchesFilters  -- forward

local VALUE_STEPS  = { 0, 1e6, 1e8, 1e9, 1e10, 1e11, 1e12 }
local RARITY_STEPS = { "any", "common", "uncommon", "rare", "epic", "legendary",
                       "cosmic", "mythic", "secret", "eternal", "divine" }
local MUT_STEPS    = { "any", "silver", "golden", "rainbow", "bloom",
                       "spirit bloom", "parasite", "fractured" }
local CAP_STEPS    = { 4, 2, 6, 0 }   -- 0 = Any (non-full saja)

local FEED_FILE = "chilli_sae_feed.json"
local feed = { servers = {}, visited = {} }

--─────────────────────────────────────────────────────────────────────────────
-- HELPERS
--─────────────────────────────────────────────────────────────────────────────
local notify = function(txt, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "SAE Finder",
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
    for _, key in ipairs(RARITY_ORDER) do
        if string.find(n, key, 1, true) then return key end
    end
    return "common"
end

local function getPart(inst)
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function distTo(part)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not part then return math.huge end
    return (hrp.Position - part.Position).Magnitude
end

--─────────────────────────────────────────────────────────────────────────────
-- FORMAT + FEED STORE
--─────────────────────────────────────────────────────────────────────────────
local function fmtValue(n)
    if not n or n <= 0 then return "-" end
    local units = { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }
    for _, u in ipairs(units) do
        if n >= u[1] then
            local v = n / u[1]
            local s = v >= 100 and string.format("%.0f", v) or string.format("%.2f", v)
            return "$" .. s .. u[2] .. "/s"
        end
    end
    return string.format("$%d/s", math.floor(n))
end

local function fmtAge(ts)
    local d = os.time() - (ts or os.time())
    if d < 0 then d = 0 end
    if d < 60 then return d .. "s" end
    if d < 3600 then return math.floor(d / 60) .. "m" end
    return math.floor(d / 3600) .. "h"
end

local function loadFeed()
    local ok, txt = pcall(readfile, FEED_FILE)
    if ok and type(txt) == "string" and #txt > 2 then
        local okd, dec = pcall(HttpService.JSONDecode, HttpService, txt)
        if okd and type(dec) == "table" then
            feed.servers = dec.servers or {}
            feed.visited = dec.visited or {}
        end
    end
end

local function saveFeed()
    pcall(function()
        writefile(FEED_FILE, HttpService:JSONEncode(feed))
    end)
end

--─────────────────────────────────────────────────────────────────────────────
-- PARSER v7 (dipertahankan utuh — jangan diutak-atik tanpa kalibrasi)
--─────────────────────────────────────────────────────────────────────────────
local function parseMoney(text)
    local num, suf = string.match(text, "%$([%d%,%.]+)%s*(%a?)%s*/s")
    if num then
        num = string.gsub(num, ",", "")
        local n = tonumber(num) or 0
        local suffixMult = { K = 1e3, M = 1e6, B = 1e9, T = 1e12 }
        n = n * (suffixMult[suf] or suffixMult[string.upper(suf or "")] or 1)
        if n > 0 then return n end
    end
    return nil
end

local function parseMult(text)
    local m = string.match(text, "x%s*([%d%.]+)")
    if m then return tonumber(m) end
    return nil
end

local function blankOut(s, pattern)
    local i = string.find(s, pattern, 1, true)
    if not i then return s, false end
    local j = i + #pattern - 1
    return string.sub(s, 1, i - 1) .. string.rep(" ", #pattern) .. string.sub(s, j + 1), true
end

local function extractInfo(inst, part, fallbackLabel)
    -- teks PER LEVEL kedalaman: lvl 0 = milik telur sendiri, lvl naik = folder
    -- induk (rawan label tetangga). Sinyal hanya dibaca dari cakupan setinggi
    -- tempat nama pet ditemukan → label sebelah tidak menular.
    local texts = {}
    if fallbackLabel then table.insert(texts, { t = fallbackLabel, lvl = 0 }) end
    pcall(function()
        local node = part
        for lvl = 0, 3 do
            if not node then break end
            for _, ch in ipairs(node:GetDescendants()) do
                if (ch:IsA("TextLabel") or ch:IsA("TextButton")) and ch.Text and #ch.Text > 0 and #ch.Text < 64 then
                    table.insert(texts, { t = ch.Text, lvl = lvl })
                end
            end
            if #texts > 12 then break end
            node = node.Parent
        end
    end)

    local value, mult, nameTxt
    local muts = {}
    local rarityTxt
    local dbBase, dbRar
    local nameLvl = 3

    for _, it in ipairs(texts) do
        local cand0 = lower(it.t)
        cand0 = string.gsub(cand0, "%s*egg%s*$", "")
        cand0 = string.gsub(cand0, "^big%s+", "")
        local hitName
        if PET_DB[cand0] then
            hitName = cand0
        else
            local cand1 = cand0
            for _, tk in ipairs(MUT_TOKENS) do
                cand1 = string.gsub(cand1, tk.tok .. "%s*", "")
                cand1 = string.gsub(cand1, "%s*" .. tk.tok, "")
            end
            cand1 = string.match(cand1, "^%s*(.-)%s*$") or cand1
            if PET_DB[cand1] then hitName = cand1 end
        end
        if hitName then
            dbBase, dbRar = PET_DB[hitName][1], PET_DB[hitName][2]
            nameTxt = hitName
            nameLvl = it.lvl
            break
        end
    end

    local scoped = {}
    for _, it in ipairs(texts) do
        if it.lvl <= nameLvl then table.insert(scoped, it.t) end
    end
    local low = lower(table.concat(scoped, " | "))

    for _, r in ipairs(RARITY_ORDER) do
        if string.find(low, r, 1, true) then
            rarityTxt = r
            break
        end
    end

    for _, tk in ipairs(MUT_TOKENS) do
        local found
        low, found = blankOut(low, tk.tok)
        if found then
            local dup = false
            for _, m in ipairs(muts) do if m == tk.can then dup = true end end
            if not dup then table.insert(muts, tk.can) end
        end
    end

    for _, t in ipairs(scoped) do
        local v = parseMoney(t)
        if v and not value then value = v end
        local m = parseMult(t)
        if m and not mult then mult = m end
    end

    -- SANITY CLAMP: live > 12x base DB = label asing → buang, pakai estimasi DB
    if value and dbBase and dbBase > 0 and value > dbBase * 12 then
        value = nil
    end

    if not nameTxt then
        local score = -1
        for _, t in ipairs(scoped) do
            if not string.find(t, "%$") and not string.find(t, "x%s*[%d%.]") then
                local letters = 0
                for i = 1, #t do
                    local c = string.sub(t, i, i)
                    if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == " " then
                        letters = letters + 1
                    end
                end
                if letters > score and letters >= 3 then
                    score = letters
                    nameTxt = t
                end
            end
        end
    end

    return nameTxt, value, mult, muts, rarityTxt, dbBase, dbRar
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

local function buildESP(inst, part, rarity, displayName)
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
    label.Text = displayName or inst.Name
    label.Parent = bb

    state.espCache[inst] = { billboard = bb, highlight = hl, label = label }
end

--─────────────────────────────────────────────────────────────────────────────
-- DETEKSI — UNION per-objek (strict ∪ name ∪ billboard-label)
--─────────────────────────────────────────────────────────────────────────────
local function eggEntry(inst)
    local part = getPart(inst)
    if not part then return nil end
    return {
        part = part,
        rarity = rarityOf(inst),
        firstSeen = os.time(),
        pending = true,
        since = os.clock(),
    }
end

local function addEgg(inst, entry)
    if state.eggs[inst] then return end
    local char = LP.Character
    if char and inst:IsDescendantOf(char) then return end
    if inst:IsA("Model") and inst:FindFirstChildOfClass("Humanoid") then return end
    state.eggs[inst] = entry or eggEntry(inst)
end

local function collectEggs()
    local result = {}

    pcall(function()
        for _, inst in ipairs(Workspace:GetDescendants()) do
            local isPart  = inst:IsA("BasePart")
            local isModel = inst:IsA("Model")
            if (isPart or isModel)
            and inst ~= LP.Character then
                if matchesKeyword(inst.Name) then
                    local entry = eggEntry(inst)
                    if entry then
                        entry.strict = inEggContainer(inst) or (attrRarity(inst) ~= nil)
                        result[inst] = entry
                    end
                end
            end
        end
    end)

    pcall(function()
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst:IsA("BillboardGui") and inst.Name ~= "SAEEggBB" then
                local txt
                for _, ch in ipairs(inst:GetDescendants()) do
                    if ch:IsA("TextLabel") and ch.Text and #ch.Text > 2 then
                        txt = ch.Text
                        break
                    end
                end
                if txt and (matchesKeyword(txt) or parseMoney(txt)) then
                    local target
                    if inst.Adornee and inst.Adornee:IsA("BasePart") then
                        target = inst.Adornee
                    elseif inst.Parent and inst.Parent:IsA("BasePart") then
                        target = inst.Parent
                    end
                    if target and not result[target.Parent] and not result[target] then
                        local own = result[target]
                        if not own then
                            own = { part = target, rarity = rarityOf(target), firstSeen = os.time(),
                                    pending = true, since = os.clock(), label = txt, viaLabel = true }
                            result[target] = own
                        else
                            own.label = txt
                            own.viaLabel = true
                        end
                    end
                end
            end
        end
    end)

    if next(result) then
        state.scanMode = "union"
    else
        state.scanMode = "none"
    end
    return result
end

local function resolvePending(inst)
    local data = state.eggs[inst]
    if not data or not data.pending then return end
    if os.clock() - (data.since or 0) > CONFIG.pendingWindow then
        data.pending = false
        return
    end
    local name, value, mult, muts, rarTxt, dbBase, dbRar =
        extractInfo(inst, data.part, data.label)
    if name then data.name = name end
    if rarTxt then data.rarity = rarTxt end
    if not rarTxt and dbRar then data.rarity = lower(dbRar) end
    if muts and #muts > 0 then data.muts = muts end
    if value then
        data.value = value
        data.est = false
    elseif dbBase then
        data.dbBase = dbBase
        data.value = dbBase * mutEffMult(data.muts)
        data.est = true
    end
    if mult then data.mult = mult end
    if data.name and data.value and data.value > 0 then
        data.pending = false
    end
end

local function refreshESP()
    local new = collectEggs()

    for inst in pairs(state.espCache) do
        if not new[inst] or not inst.Parent or not CONFIG.esp then destroyESP(inst) end
    end
    local merged = {}
    for inst, entry in pairs(new) do
        local old = state.eggs[inst]
        if old then
            old.part = entry.part
            if entry.label and not old.label then old.label = entry.label end
            merged[inst] = old
        else
            merged[inst] = entry
        end
    end
    state.eggs = merged

    if not CONFIG.esp then
        state.rendered = 0
        return
    end

    local list = {}
    for inst, data in pairs(state.eggs) do
        local d = distTo(data.part)
        if d <= CONFIG.maxDistance then
            table.insert(list, { inst = inst, data = data, d = d })
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)

    for i = 1, math.min(#list, CONFIG.maxRendered) do
        local e = list[i]
        if not state.espCache[e.inst] then
            local ok = pcall(buildESP, e.inst, e.data.part, e.data.rarity, e.data.name)
            if not ok then state.espCache[e.inst] = nil end
        end
    end
    state.rendered = math.min(#list, CONFIG.maxRendered)
end

local function resolveCurrentEggValue(data)
    local val = data.value
    if not val and data.dbBase then
        val = data.dbBase * mutEffMult(data.muts)
    end
    return val or 0
end

--─────────────────────────────────────────────────────────────────────────────
-- AUTO TELEPORT (ESP assist)
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
    hrp.CFrame = CFrame.new(target)
end

--─────────────────────────────────────────────────────────────────────────────
-- HTTP + SERVERS
--─────────────────────────────────────────────────────────────────────────────
local function httpGet(url)
    local body
    local ok = pcall(function() body = game:HttpGet(url, true) end)
    if ok and type(body) == "string" and #body > 0 then return body end
    ok = pcall(function() body = request({ Url = url, Method = "GET" }).Body end)
    if ok and type(body) == "string" and #body > 0 then return body end
    return nil
end

function fetchServers(excludeFull)
    if state.fetching then return state.servers end
    state.fetching = true
    local out, cursor, pages = {}, nil, 0

    repeat
        pages = pages + 1
        local url = string.format(
            "https://games.roblox.com/v1/games/%d/servers/Public?limit=100&sortOrder=Desc&excludeFullGames=%s%s",
            PLACE_ID,
            excludeFull and "true" or "false",
            cursor and ("&cursor=" .. cursor) or ""
        )
        local raw = httpGet(url)
        if not raw then break end
        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
        if not ok or type(decoded) ~= "table" then break end

        for _, s in ipairs(decoded.data or {}) do
            local ref = {
                id      = s.id,
                playing = tonumber(s.playing) or 0,
                max     = tonumber(s.maxPlayers) or 0,
                ping    = tonumber(s.ping),
            }
            table.insert(out, ref)
            state.srvById[ref.id] = ref
        end
        cursor = decoded.nextPageCursor
    until not cursor or pages >= 3

    table.sort(out, function(a, b)
        if a.playing ~= b.playing then return a.playing > b.playing end
        return a.id < b.id
    end)

    state.servers = out
    state.srvAt = os.clock()
    state.fetching = false
    return out
end

local function getLiveCount(jobId)
    if jobId == game.JobId then
        return #Players:GetPlayers(), Players.MaxPlayers
    end
    local ref = state.srvById[jobId]
    if ref and os.clock() - state.srvAt < 30 then
        return ref.playing, ref.max
    end
    if os.clock() - state.srvAt >= 30 and not state.fetching then
        task.spawn(fetchServers, false)
    end
    if ref then return ref.playing, ref.max end
    return nil, nil
end

function joinServer(jobId)
    if not jobId or jobId == "" then return end
    if jobId == game.JobId then notify("Sudah di server itu", 2) return end
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

-- JOIN pre-check: FULL skip · cap filter · TOP ≤6/7 boleh (RACE)
function joinFinderServer(jobId, isTop)
    if not jobId or jobId == "" then return end
    if jobId == game.JobId then notify("Sudah di server itu", 2) return end

    local playing, max = getLiveCount(jobId)
    if playing then
        if max and playing >= max then
            notify("FULL " .. playing .. "/" .. max .. " — skip", 3)
            return
        end
        if isTop then
            if playing >= 6 then
                notify("RACE! " .. playing .. "/7 — 1 slot, gas cepat", 4)
            end
        elseif FILTER.capFilter > 0 and playing > FILTER.capFilter then
            notify("Skip: " .. playing .. "/7 > batas CAP " .. FILTER.capFilter, 3)
            return
        end
    else
        notify("Data pemain belum ada — JOIN blind", 3)
    end
    joinServer(jobId)
end

-- AUTO hop: hanya server tidak-full + hormati CAP filter, prefer paling sepi
function pickHopTarget()
    if #state.servers == 0 or os.clock() - state.srvAt > 60 then
        pcall(fetchServers, true)
    end
    local now = os.time()
    local cands = {}
    for _, s in ipairs(state.servers) do
        if s.id ~= game.JobId and s.playing > 0 and s.max > 0 and s.playing < s.max then
            if FILTER.capFilter == 0 or s.playing <= FILTER.capFilter then
                table.insert(cands, s)
            end
        end
    end
    table.sort(cands, function(a, b) return a.playing < b.playing end)

    local fallback
    for _, s in ipairs(cands) do
        local last = feed.visited[s.id]
        if not last or now - last > 480 then return s.id end
        if not fallback then fallback = s.id end
    end
    return fallback
end

--─────────────────────────────────────────────────────────────────────────────
-- UI · CLEAN DARK MINIMAL
--─────────────────────────────────────────────────────────────────────────────
local C_BG      = Color3.fromRGB(16, 16, 20)
local C_PANEL   = Color3.fromRGB(24, 24, 30)
local C_PANEL2  = Color3.fromRGB(33, 33, 41)
local C_STROKE  = Color3.fromRGB(45, 45, 55)
local C_TEXT    = Color3.fromRGB(240, 240, 245)
local C_DIM     = Color3.fromRGB(145, 145, 158)
local C_ACCENT  = Color3.fromRGB( 88, 220, 140)
local C_GOLD    = Color3.fromRGB(255, 200, 70)
local C_ROW     = Color3.fromRGB(22, 22, 28)

local gui = Instance.new("ScreenGui")
gui.Name = "SAE_Finder"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999

local okParent = pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not okParent or not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(520, 400)
main.Position = UDim2.new(0.5, -260, 0.5, -200)
main.BackgroundColor3 = C_BG
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = C_STROKE
mainStroke.Thickness = 1
mainStroke.Parent = main

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 10)
mainCorner.Parent = main

-- hover helper (Clean Minimal feel)
local function hoverify(btn, base, hot)
    btn.MouseEnter:Connect(function()
        btn.BackgroundColor3 = hot
    end)
    btn.MouseLeave:Connect(function()
        btn.BackgroundColor3 = base
    end)
end

-- TOPBAR
local topbar = Instance.new("Frame")
topbar.Size = UDim2.new(1, 0, 0, 36)
topbar.BackgroundColor3 = C_PANEL
topbar.BorderSizePixel = 0
topbar.Parent = main

local topCorner = Instance.new("UICorner")
topCorner.CornerRadius = UDim.new(0, 10)
topCorner.Parent = topbar

local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(8, 8)
dot.Position = UDim2.fromOffset(14, 14)
dot.BackgroundColor3 = C_ACCENT
dot.Parent = topbar
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = dot

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -110, 1, 0)
titleLabel.Position = UDim2.fromOffset(30, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 13
titleLabel.TextColor3 = C_TEXT
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "SAE FINDER"
titleLabel.Parent = topbar

local topBtns = Instance.new("Frame")
topBtns.Size = UDim2.fromOffset(64, 24)
topBtns.Position = UDim2.new(1, -72, 0, 6)
topBtns.BackgroundTransparency = 1
topBtns.Parent = topbar

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.fromOffset(28, 24)
minBtn.Position = UDim2.fromOffset(0, 0)
minBtn.BackgroundColor3 = C_PANEL
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 13
minBtn.TextColor3 = C_DIM
minBtn.Text = "–"
minBtn.Parent = topBtns
local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 6)
minCorner.Parent = minBtn
hoverify(minBtn, C_PANEL, C_PANEL2)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 24)
closeBtn.Position = UDim2.fromOffset(32, 0)
closeBtn.BackgroundColor3 = C_PANEL
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.TextColor3 = C_DIM
closeBtn.Text = "×"
closeBtn.Parent = topBtns
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeBtn
hoverify(closeBtn, C_PANEL, Color3.fromRGB(120, 40, 46))

-- drag
do
    local dragging, dragStart, startPos = false, nil, nil
    topbar.InputBegan:Connect(function(input)
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

-- TABS
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -24, 0, 30)
tabBar.Position = UDim2.fromOffset(12, 42)
tabBar.BackgroundTransparency = 1
tabBar.Parent = main

local function makeTab(text, order)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1 / 3, -4, 1, 0)
    b.Position = UDim2.new(order / 3, order * 4, 0, 0)
    b.BackgroundColor3 = C_PANEL
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.TextColor3 = C_DIM
    b.Text = text
    b.Parent = tabBar
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 7)
    c.Parent = b
    return b
end

local tabFind   = makeTab("FINDER", 0)
local tabServer = makeTab("SERVERS", 1)
local tabSet    = makeTab("SETTINGS", 2)

local pages = Instance.new("Frame")
pages.Size = UDim2.new(1, -24, 1, -108)
pages.Position = UDim2.fromOffset(12, 78)
pages.BackgroundTransparency = 1
pages.Parent = main

local finderPage = Instance.new("Frame")
finderPage.Size = UDim2.fromScale(1, 1)
finderPage.BackgroundTransparency = 1
finderPage.Parent = pages

local srvPage = Instance.new("Frame")
srvPage.Size = UDim2.fromScale(1, 1)
srvPage.BackgroundTransparency = 1
srvPage.Visible = false
srvPage.Parent = pages

local setPage = Instance.new("Frame")
setPage.Size = UDim2.fromScale(1, 1)
setPage.BackgroundTransparency = 1
setPage.Visible = false
setPage.Parent = pages

-- TOAST SYSTEM (kanan atas, slide-in)
do
    local holder = Instance.new("Frame")
    holder.Name = "SAEToasts"
    holder.Size = UDim2.fromOffset(280, 400)
    holder.Position = UDim2.new(1, -290, 0, 40)
    holder.BackgroundTransparency = 1
    holder.Parent = gui

    local hl2 = Instance.new("UIListLayout")
    hl2.Padding = UDim.new(0, 6)
    hl2.SortOrder = Enum.SortOrder.LayoutOrder
    hl2.VerticalAlignment = Enum.VerticalAlignment.Top
    hl2.Parent = holder

    function toast(txt, dur, accent)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 40)
        f.BackgroundColor3 = C_PANEL2
        f.BorderSizePixel = 0
        f.LayoutOrder = os.clock() * 1000
        f.Parent = holder

        local fc = Instance.new("UICorner")
        fc.CornerRadius = UDim.new(0, 8)
        fc.Parent = f

        local fs = Instance.new("UIStroke")
        fs.Color = accent or C_ACCENT
        fs.Thickness = 1
        fs.Transparency = 0.4
        fs.Parent = f

        local bar = Instance.new("Frame")
        bar.Size = UDim2.fromOffset(3, 24)
        bar.Position = UDim2.fromOffset(8, 8)
        bar.BackgroundColor3 = accent or C_ACCENT
        bar.BorderSizePixel = 0
        bar.Parent = f
        local barC = Instance.new("UICorner")
        barC.CornerRadius = UDim.new(1, 0)
        barC.Parent = bar

        local tl = Instance.new("TextLabel")
        tl.Size = UDim2.new(1, -30, 1, 0)
        tl.Position = UDim2.fromOffset(20, 0)
        tl.BackgroundTransparency = 1
        tl.Font = Enum.Font.Gotham
        tl.TextSize = 11
        tl.TextColor3 = C_TEXT
        tl.TextXAlignment = Enum.TextXAlignment.Left
        tl.TextTruncate = Enum.TextTruncate.AtEnd
        tl.Text = tostring(txt)
        tl.Parent = f

        f.Position = UDim2.new(1, 20, 0, 0)
        TweenService:Create(f, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Position = UDim2.new(0, 0, 0, 0) }):Play()

        task.delay(dur or 3, function()
            if f.Parent then
                local out = TweenService:Create(f, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
                    { Position = UDim2.new(1, 20, 0, 0) })
                out:Play()
                out.Completed:Wait()
                f:Destroy()
            end
        end)
    end

    notify = function(txt, dur, accent)
        pcall(toast, txt, dur, accent)
    end
end

--─────────────────────────────────────────────────────────────────────────────
-- FINDER PAGE
--─────────────────────────────────────────────────────────────────────────────
local chipRow1 = Instance.new("Frame")
chipRow1.Size = UDim2.new(1, 0, 0, 26)
chipRow1.BackgroundTransparency = 1
chipRow1.Parent = finderPage

local chipRow2 = Instance.new("Frame")
chipRow2.Size = UDim2.new(1, 0, 0, 26)
chipRow2.Position = UDim2.fromOffset(0, 28)
chipRow2.BackgroundTransparency = 1
chipRow2.Parent = finderPage

local function makeChip(text, order, parent, cols)
    cols = cols or 4
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1 / cols, -4, 1, 0)
    b.Position = UDim2.new(order / cols, order * 4, 0, 0)
    b.BackgroundColor3 = C_PANEL
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextColor3 = C_TEXT
    b.Text = text
    b.AutoButtonColor = false
    b.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = b
    hoverify(b, C_PANEL, C_PANEL2)
    return b
end

local btnAuto   = makeChip("AUTO OFF", 0, chipRow1, 4)
local btnMinVal = makeChip("MIN Any", 1, chipRow1, 4)
local btnRarity = makeChip("RARITY Any", 2, chipRow1, 4)
local btnMut    = makeChip("MUT Any", 3, chipRow1, 4)
local btnCap    = makeChip("CAP ≤4", 0, chipRow2, 4)
local btnReset  = makeChip("RESET-WAIT OFF", 1, chipRow2, 4)
local btnClear  = makeChip("CLEAR", 2, chipRow2, 4)

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, 0, 0, 22)
searchBox.Position = UDim2.fromOffset(0, 58)
searchBox.BackgroundColor3 = C_PANEL
searchBox.Font = Enum.Font.Gotham
searchBox.TextSize = 11
searchBox.TextColor3 = C_TEXT
searchBox.PlaceholderText = "  cari pet…  (kosongkan = semua)"
searchBox.PlaceholderColor3 = C_DIM
searchBox.Text = ""
searchBox.ClearTextOnFocus = false
searchBox.Parent = finderPage
local sbC = Instance.new("UICorner")
sbC.CornerRadius = UDim.new(0, 6)
sbC.Parent = searchBox
local sbS = Instance.new("UIStroke")
sbS.Color = C_STROKE
sbS.Thickness = 1
sbS.Parent = searchBox

local renderFinder, renderServers   -- forward (dipakai closure sebelum definisi)

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    FILTER.search = lower(searchBox.Text)
    if #FILTER.search == 0 or #FILTER.search >= 2 then
        pcall(function() renderFinder() end)
    end
end)

local finderSub = Instance.new("TextLabel")
finderSub.Size = UDim2.new(1, 0, 0, 18)
finderSub.Position = UDim2.fromOffset(0, 84)
finderSub.BackgroundTransparency = 1
finderSub.Font = Enum.Font.GothamBold
finderSub.TextSize = 10
finderSub.TextColor3 = C_DIM
finderSub.TextXAlignment = Enum.TextXAlignment.Left
finderSub.Text = "..."
finderSub.Parent = finderPage

local finderList = Instance.new("ScrollingFrame")
finderList.Size = UDim2.new(1, 0, 1, -106)
finderList.Position = UDim2.fromOffset(0, 106)
finderList.BackgroundTransparency = 1
finderList.BorderSizePixel = 0
finderList.ScrollBarThickness = 4
finderList.CanvasSize = UDim2.new()
finderList.AutomaticCanvasSize = Enum.AutomaticSize.Y
finderList.Parent = finderPage

local finderLayout = Instance.new("UIListLayout")
finderLayout.Padding = UDim.new(0, 3)
finderLayout.SortOrder = Enum.SortOrder.LayoutOrder
finderLayout.Parent = finderList

local function rarityColor(rar)
    return RARITY[lower(rar or "")] or RARITY.common
end

local function computeTop()
    local all = {}
    local now = os.time()
    for jobId, srv in pairs(feed.servers) do
        if now - (srv.lastSeen or 0) <= CONFIG.feedExpiry then
            for _, e in ipairs(srv.eggs or {}) do
                if (e.value or 0) > 0 then
                    table.insert(all, { srv = jobId, egg = e })
                end
            end
        end
    end
    table.sort(all, function(a, b) return (a.egg.value or 0) > (b.egg.value or 0) end)

    local topEggs, topServers = {}, {}
    for i = 1, math.min(#all, 10) do
        topEggs[i] = all[i].egg
        topServers[all[i].srv] = true
    end
    return topEggs, topServers
end

local function eggValue(e)
    return e.value or 0
end

local function mutText(muts)
    if not muts or #muts == 0 then return nil end
    return table.concat(muts, "+")
end

local function serverCapOk(players, max, isTop)
    if players >= max then return false end          -- FULL: selalu dibuang
    if isTop then return players <= 6 end            -- ★TOP: ≤6/7 (RACE slot)
    if FILTER.capFilter == 0 then return true end    -- Any (non-full)
    return players <= FILTER.capFilter
end

-- (renderFinder forward dideklarasi di atas — assign tanpa 'local')
function renderFinder()
    for _, ch in ipairs(finderList:GetChildren()) do
        if ch:IsA("Frame") or ch:IsA("TextLabel") then ch:Destroy() end
    end

    local now = os.time()
    for jobId, srv in pairs(feed.servers) do
        if now - (srv.lastSeen or 0) > CONFIG.feedExpiry then
            feed.servers[jobId] = nil
        end
    end

    local topEggs, topServers = computeTop()
    local topSet = {}
    for _, e in ipairs(topEggs) do topSet[e] = true end

    local rows = {}
    local nEgg, nServer, nTop = 0, 0, 0
    for jobId, srv in pairs(feed.servers) do
        nServer = nServer + 1
        nEgg = nEgg + #(srv.eggs or {})
        local isTopSrv = topServers[jobId] == true
        if isTopSrv then nTop = nTop + 1 end
        local live = state.srvById[jobId]
        if live and os.clock() - state.srvAt < 30 then
            srv.players = live.playing
            srv.max = live.max or srv.max
        end
        local players = srv.players or 0
        local cap = srv.max or 7
        if serverCapOk(players, cap, isTopSrv) then
            for _, e in ipairs(srv.eggs or {}) do
                if matchesFilters(e) then
                    table.insert(rows, { e = e, srv = srv, isTop = isTopSrv or topSet[e] == true })
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        local ta, tb = a.isTop and 1 or 0, b.isTop and 1 or 0
        if ta ~= tb then return ta > tb end
        if eggValue(a.e) ~= eggValue(b.e) then return eggValue(a.e) > eggValue(b.e) end
        return (a.e.ts or 0) > (b.e.ts or 0)
    end)

    local here = #Players:GetPlayers()
    finderSub.Text = string.format("%d/%d pemain · %d egg · %d server · TOP %d · mode:%s",
        here, Players.MaxPlayers, nEgg, nServer, nTop, state.scanMode or "-")

    if #rows == 0 then
        local empty = Instance.new("TextLabel")
        empty.Size = UDim2.new(1, 0, 0, 30)
        empty.BackgroundTransparency = 1
        empty.Font = Enum.Font.Gotham
        empty.TextSize = 11
        empty.TextColor3 = C_DIM
        empty.Text = "kosong — nyalakan AUTO untuk server-hopping"
        empty.Parent = finderList
        return
    end

    local maxRows = 30
    for i, item in ipairs(rows) do
        if i > maxRows then break end
        local e, srv, isTop = item.e, item.srv, item.isTop

        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, 38)
        row.BackgroundColor3 = isTop and Color3.fromRGB(46, 38, 18) or C_ROW
        row.LayoutOrder = i
        row.Parent = finderList
        local rc = Instance.new("UICorner")
        rc.CornerRadius = UDim.new(0, 7)
        rc.Parent = row

        local ic = Instance.new("Frame")
        ic.Size = UDim2.fromOffset(26, 26)
        ic.Position = UDim2.fromOffset(6, 6)
        ic.BackgroundColor3 = isTop and C_GOLD or rarityColor(e.rarity)
        ic.Parent = row
        local icc = Instance.new("UICorner")
        icc.CornerRadius = UDim.new(0, 7)
        icc.Parent = ic
        local icTxt = Instance.new("TextLabel")
        icTxt.Size = UDim2.fromScale(1, 1)
        icTxt.BackgroundTransparency = 1
        icTxt.Font = Enum.Font.GothamBold
        icTxt.TextSize = 13
        icTxt.TextColor3 = Color3.fromRGB(18, 18, 22)
        icTxt.Text = isTop and "★" or string.upper(string.sub(e.name or "?", 1, 1))
        icTxt.Parent = ic

        local nm = Instance.new("TextLabel")
        nm.Size = UDim2.fromOffset(150, 14)
        nm.Position = UDim2.fromOffset(38, 4)
        nm.BackgroundTransparency = 1
        nm.Font = Enum.Font.GothamBold
        nm.TextSize = 11
        nm.TextColor3 = C_TEXT
        nm.TextXAlignment = Enum.TextXAlignment.Left
        nm.TextTruncate = Enum.TextTruncate.AtEnd
        nm.Text = e.name or "?"
        nm.Parent = row

        local pcol = "#58DC8C"
        if (srv.players or 0) >= 6 then pcol = "#FF8C3C"
        elseif (srv.players or 0) >= 5 then pcol = "#FFB85C" end
        local rarCap = string.upper(string.sub(e.rarity or "common", 1, 1)) ..
            string.sub(e.rarity or "common", 2)
        local sub = Instance.new("TextLabel")
        sub.Size = UDim2.fromOffset(210, 11)
        sub.Position = UDim2.fromOffset(38, 21)
        sub.BackgroundTransparency = 1
        sub.Font = Enum.Font.Gotham
        sub.TextSize = 9
        sub.TextColor3 = C_DIM
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.TextTruncate = Enum.TextTruncate.AtEnd
        sub.RichText = true
        sub.Text = string.format("%s%s · <font color=\"%s\">%d/%d</font> · %s",
            isTop and "★TOP · " or "", rarCap, pcol,
            srv.players or 0, srv.max or 7, fmtAge(e.ts))
        sub.Parent = row

        local muts = mutText(e.muts)
        if muts then
            local pill = Instance.new("TextLabel")
            pill.Size = UDim2.fromOffset(70, 16)
            pill.Position = UDim2.new(1, -246, 0, 5)
            pill.BackgroundColor3 = Color3.fromRGB(38, 38, 46)
            pill.Font = Enum.Font.GothamBold
            pill.TextSize = 9
            pill.TextColor3 = MUT_COLORS[e.muts[1]] or C_DIM
            pill.TextTruncate = Enum.TextTruncate.AtEnd
            pill.Text = muts
            pill.Parent = row
            local pc = Instance.new("UICorner")
            pc.CornerRadius = UDim.new(0, 8)
            pc.Parent = pill
        end

        local val = Instance.new("TextLabel")
        val.Size = UDim2.fromOffset(150, 14)
        val.Position = UDim2.new(1, -200, 0, 4)
        val.BackgroundTransparency = 1
        val.Font = Enum.Font.GothamBold
        val.TextSize = 11
        val.TextColor3 = (eggValue(e) <= 0) and C_DIM or
            (e.est and Color3.fromRGB(110, 180, 125) or Color3.fromRGB(120, 230, 140))
        val.TextXAlignment = Enum.TextXAlignment.Right
        val.Text = eggValue(e) > 0 and ((e.est and "~" or "") .. fmtValue(eggValue(e))) or "$?"
        val.Parent = row

        local xinfo = Instance.new("TextLabel")
        xinfo.Size = UDim2.fromOffset(150, 11)
        xinfo.Position = UDim2.new(1, -200, 0, 21)
        xinfo.BackgroundTransparency = 1
        xinfo.Font = Enum.Font.Gotham
        xinfo.TextSize = 9
        xinfo.TextColor3 = C_DIM
        xinfo.TextXAlignment = Enum.TextXAlignment.Right
        xinfo.Text = (e.mult or 0) > 1 and ("x" .. string.format("%.2f", e.mult)) or ""
        xinfo.Parent = row

        local jb = Instance.new("TextButton")
        jb.Size = UDim2.fromOffset(46, 26)
        jb.Position = UDim2.new(1, -52, 0, 6)
        jb.BackgroundColor3 = isTop and C_GOLD or Color3.fromRGB(255, 150, 40)
        jb.Font = Enum.Font.GothamBold
        jb.TextSize = 11
        jb.TextColor3 = Color3.fromRGB(30, 20, 5)
        jb.Text = "JOIN"
        jb.AutoButtonColor = false
        jb.Parent = row
        local jc = Instance.new("UICorner")
        jc.CornerRadius = UDim.new(0, 6)
        jc.Parent = jb
        jb.MouseEnter:Connect(function()
            jb.BackgroundColor3 = isTop and Color3.fromRGB(255, 220, 110) or Color3.fromRGB(255, 175, 70)
        end)
        jb.MouseLeave:Connect(function()
            jb.BackgroundColor3 = isTop and C_GOLD or Color3.fromRGB(255, 150, 40)
        end)
        jb.MouseButton1Click:Connect(function()
            joinFinderServer(srv.jobId, isTop)
        end)
    end
end

local function syncButtons()
    btnAuto.Text = FILTER.auto and ("AUTO " .. FILTER.interval .. "s") or "AUTO OFF"
    btnAuto.TextColor3 = FILTER.auto and C_ACCENT or C_DIM
    btnMinVal.Text = "MIN " .. (FILTER.minValue > 0 and
        string.gsub(fmtValue(FILTER.minValue), "/s$", "") or "Any")
    btnRarity.Text = "RARITY " .. (FILTER.rarity == "any" and "Any" or FILTER.rarity)
    btnMut.Text = "MUT " .. (FILTER.mut == "any" and "Any" or FILTER.mut)
    btnCap.Text = FILTER.capFilter == 0 and "CAP Any" or ("CAP ≤" .. FILTER.capFilter)
    btnReset.Text = FILTER.waitReset and "RESET-WAIT ON" or "RESET-WAIT OFF"
    btnReset.TextColor3 = FILTER.waitReset and C_ACCENT or C_DIM
end

local minIdx, rarIdx, mutIdx, capIdx = 1, 1, 1, 1
btnMinVal.MouseButton1Click:Connect(function()
    minIdx = minIdx % #VALUE_STEPS + 1
    FILTER.minValue = VALUE_STEPS[minIdx]
    syncButtons()
    pcall(renderFinder)
end)
btnRarity.MouseButton1Click:Connect(function()
    rarIdx = rarIdx % #RARITY_STEPS + 1
    FILTER.rarity = RARITY_STEPS[rarIdx]
    syncButtons()
    pcall(renderFinder)
end)
btnMut.MouseButton1Click:Connect(function()
    mutIdx = mutIdx % #MUT_STEPS + 1
    FILTER.mut = MUT_STEPS[mutIdx]
    syncButtons()
    pcall(renderFinder)
end)
btnCap.MouseButton1Click:Connect(function()
    capIdx = capIdx % #CAP_STEPS + 1
    FILTER.capFilter = CAP_STEPS[capIdx]
    syncButtons()
    pcall(renderFinder)
end)
btnReset.MouseButton1Click:Connect(function()
    FILTER.waitReset = not FILTER.waitReset
    syncButtons()
    notify(FILTER.waitReset and "AUTO menunggu tick reset 5 menit" or "RESET-WAIT off", 3)
end)
btnClear.MouseButton1Click:Connect(function()
    feed.servers = {}
    saveFeed()
    pcall(renderFinder)
    notify("Feed dibersihkan", 2)
end)
btnAuto.MouseButton1Click:Connect(function()
    if not FILTER.auto then
        FILTER.auto = true
        FILTER.interval = 5
    elseif FILTER.interval == 5 then FILTER.interval = 10
    elseif FILTER.interval == 10 then FILTER.interval = 15
    elseif FILTER.interval == 15 then FILTER.interval = 30
    else FILTER.auto = false end
    state.lastHop = 0
    syncButtons()
    notify(FILTER.auto and ("AUTO ON — hop tiap " .. FILTER.interval .. "s") or "AUTO OFF", 3)
end)

--─────────────────────────────────────────────────────────────────────────────
-- SETTINGS PAGE (toggle knob animasi)
--─────────────────────────────────────────────────────────────────────────────
local function makeToggleRow(parent, text, initial, yPos, onChanged)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 32)
    row.Position = UDim2.fromOffset(0, yPos)
    row.BackgroundColor3 = C_PANEL
    row.BorderSizePixel = 0
    row.Parent = parent
    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(0, 7)
    rc.Parent = row

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -80, 1, 0)
    lbl.Position = UDim2.fromOffset(10, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextColor3 = C_TEXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = text
    lbl.Parent = row

    local track = Instance.new("Frame")
    track.Size = UDim2.fromOffset(46, 22)
    track.Position = UDim2.new(1, -56, 0.5, -11)
    track.BackgroundColor3 = initial and C_ACCENT or Color3.fromRGB(55, 55, 66)
    track.BorderSizePixel = 0
    track.Parent = row
    local tc2 = Instance.new("UICorner")
    tc2.CornerRadius = UDim.new(1, 0)
    tc2.Parent = track

    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(16, 16)
    knob.Position = initial and UDim2.new(1, -19, 0.5, -8) or UDim2.fromOffset(3, 3)
    knob.BackgroundColor3 = initial and Color3.fromRGB(14, 30, 20) or C_DIM
    knob.BorderSizePixel = 0
    knob.Parent = track
    local kc2 = Instance.new("UICorner")
    kc2.CornerRadius = UDim.new(1, 0)
    kc2.Parent = knob

    local on = initial
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromScale(1, 1)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Parent = track
    btn.MouseButton1Click:Connect(function()
        on = not on
        TweenService:Create(track, TweenInfo.new(0.15),
            { BackgroundColor3 = on and C_ACCENT or Color3.fromRGB(55, 55, 66) }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Position = on and UDim2.new(1, -19, 0.5, -8) or UDim2.fromOffset(3, 3),
              BackgroundColor3 = on and Color3.fromRGB(14, 30, 20) or C_DIM }):Play()
        if onChanged then onChanged(on) end
    end)
    return row
end

local function makeButtonRow(parent, text, yPos, accent, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 32)
    b.Position = UDim2.fromOffset(0, yPos)
    b.BackgroundColor3 = C_PANEL
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.TextColor3 = accent or C_TEXT
    b.Text = text
    b.AutoButtonColor = false
    b.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 7)
    c.Parent = b
    hoverify(b, C_PANEL, C_PANEL2)
    b.MouseButton1Click:Connect(cb)
    return b
end

makeToggleRow(setPage, "ESP (nama + jarak + highlight)", true, 0, function(on)
    CONFIG.esp = on
    if not on then
        for inst in pairs(state.espCache) do destroyESP(inst) end
    end
end)

makeToggleRow(setPage, "Auto-teleport ke egg terdekat", false, 38, function(on)
    state.autoTPOn = on
    notify(on and "Auto-TP aktif" or "Auto-TP nonaktif", 2)
end)

local rangeRow = Instance.new("Frame")
rangeRow.Size = UDim2.new(1, 0, 0, 32)
rangeRow.Position = UDim2.fromOffset(0, 76)
rangeRow.BackgroundColor3 = C_PANEL
rangeRow.BorderSizePixel = 0
rangeRow.Parent = setPage
local rrC = Instance.new("UICorner")
rrC.CornerRadius = UDim.new(0, 7)
rrC.Parent = rangeRow

local rangeLbl = Instance.new("TextLabel")
rangeLbl.Size = UDim2.new(1, -80, 1, 0)
rangeLbl.Position = UDim2.fromOffset(10, 0)
rangeLbl.BackgroundTransparency = 1
rangeLbl.Font = Enum.Font.Gotham
rangeLbl.TextSize = 12
rangeLbl.TextColor3 = C_TEXT
rangeLbl.TextXAlignment = Enum.TextXAlignment.Left
rangeLbl.Text = "Range maksimum (m)"
rangeLbl.Parent = rangeRow

local rangeBox = Instance.new("TextBox")
rangeBox.Size = UDim2.fromOffset(56, 22)
rangeBox.Position = UDim2.new(1, -62, 0.5, -11)
rangeBox.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
rangeBox.Font = Enum.Font.GothamBold
rangeBox.TextSize = 11
rangeBox.TextColor3 = C_TEXT
rangeBox.Text = tostring(CONFIG.maxDistance)
rangeBox.Parent = rangeRow
local rbC = Instance.new("UICorner")
rbC.CornerRadius = UDim.new(0, 6)
rbC.Parent = rangeBox
rangeBox.FocusLost:Connect(function()
    local n = tonumber(rangeBox.Text)
    if n and n >= 50 then CONFIG.maxDistance = math.floor(n) else rangeBox.Text = tostring(CONFIG.maxDistance) end
end)

makeButtonRow(setPage, "DEBUG DUMP (console + clipboard)", 118, C_DIM, function()
    if _G.SAE_FINDER and _G.SAE_FINDER.dump then _G.SAE_FINDER.dump() end
end)

makeButtonRow(setPage, "CLEAR FEED", 156, C_DIM, function()
    feed.servers = {}
    saveFeed()
    pcall(renderFinder)
    notify("Feed dibersihkan", 2)
end)

makeButtonRow(setPage, "UNLOAD (END)", 194, Color3.fromRGB(255, 120, 120), function()
    if _G.SAE_FINDER then _G.SAE_FINDER.unload() end
end)

--─────────────────────────────────────────────────────────────────────────────
-- SERVERS PAGE (occupancy bar)
--─────────────────────────────────────────────────────────────────────────────
local srvHead = Instance.new("Frame")
srvHead.Size = UDim2.new(1, 0, 0, 26)
srvHead.BackgroundTransparency = 1
srvHead.Parent = srvPage

local srvInfo = Instance.new("TextLabel")
srvInfo.Size = UDim2.new(1, -80, 1, 0)
srvInfo.BackgroundTransparency = 1
srvInfo.Font = Enum.Font.GothamBold
srvInfo.TextSize = 11
srvInfo.TextColor3 = C_DIM
srvInfo.TextXAlignment = Enum.TextXAlignment.Left
srvInfo.Text = "server saat ini: ..."
srvInfo.Parent = srvHead

local refreshBtn = Instance.new("TextButton")
refreshBtn.Size = UDim2.fromOffset(72, 22)
refreshBtn.Position = UDim2.new(1, -72, 0, 2)
refreshBtn.BackgroundColor3 = C_PANEL
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.TextSize = 11
refreshBtn.TextColor3 = C_ACCENT
refreshBtn.Text = "REFRESH"
refreshBtn.AutoButtonColor = false
refreshBtn.Parent = srvHead
local rfC = Instance.new("UICorner")
rfC.CornerRadius = UDim.new(0, 6)
rfC.Parent = refreshBtn
hoverify(refreshBtn, C_PANEL, C_PANEL2)

local srvList = Instance.new("ScrollingFrame")
srvList.Size = UDim2.new(1, 0, 1, -30)
srvList.Position = UDim2.fromOffset(0, 30)
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

-- (renderServers forward dideklarasi di atas)
function renderServers()
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
        if i > 60 then break end
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -6, 0, 28)
        row.BackgroundColor3 = C_ROW
        row.LayoutOrder = i
        row.Parent = srvList
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = row

        local idlbl = Instance.new("TextLabel")
        idlbl.Size = UDim2.fromOffset(70, 28)
        idlbl.Position = UDim2.fromOffset(8, 0)
        idlbl.BackgroundTransparency = 1
        idlbl.Font = Enum.Font.Code
        idlbl.TextSize = 11
        idlbl.TextColor3 = C_DIM
        idlbl.TextXAlignment = Enum.TextXAlignment.Left
        idlbl.Text = string.sub(s.id, 1, 8)
        idlbl.Parent = row

        -- occupancy bar (Clean Minimal: bar tipis warna status)
        local ratio = (s.max > 0) and (s.playing / s.max) or 0
        local barBG = Instance.new("Frame")
        barBG.Size = UDim2.fromOffset(60, 6)
        barBG.Position = UDim2.fromOffset(84, 11)
        barBG.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
        barBG.BorderSizePixel = 0
        barBG.Parent = row
        local bgC = Instance.new("UICorner")
        bgC.CornerRadius = UDim.new(1, 0)
        bgC.Parent = barBG

        local barFG = Instance.new("Frame")
        barFG.Size = UDim2.new(math.min(ratio, 1), 0, 1, 0)
        barFG.BackgroundColor3 = playerColor(s.playing, s.max)
        barFG.BorderSizePixel = 0
        barFG.Parent = barBG
        local fgC = Instance.new("UICorner")
        fgC.CornerRadius = UDim.new(1, 0)
        fgC.Parent = barFG

        local plbl = Instance.new("TextLabel")
        plbl.Size = UDim2.fromOffset(44, 28)
        plbl.Position = UDim2.fromOffset(150, 0)
        plbl.BackgroundTransparency = 1
        plbl.Font = Enum.Font.GothamBold
        plbl.TextSize = 11
        plbl.TextColor3 = playerColor(s.playing, s.max)
        plbl.Text = string.format("%d/%d", s.playing, s.max)
        plbl.Parent = row

        local pinglbl = Instance.new("TextLabel")
        pinglbl.Size = UDim2.fromOffset(44, 28)
        pinglbl.Position = UDim2.fromOffset(198, 0)
        pinglbl.BackgroundTransparency = 1
        pinglbl.Font = Enum.Font.Gotham
        pinglbl.TextSize = 10
        pinglbl.TextColor3 = C_DIM
        pinglbl.Text = s.ping and (tostring(s.ping) .. "ms") or "-"
        pinglbl.Parent = row

        local jb = Instance.new("TextButton")
        jb.Size = UDim2.fromOffset(44, 20)
        jb.Position = UDim2.new(1, -50, 0, 4)
        jb.BackgroundColor3 = C_PANEL
        jb.Font = Enum.Font.GothamBold
        jb.TextSize = 10
        jb.TextColor3 = C_ACCENT
        jb.Text = "JOIN"
        jb.AutoButtonColor = false
        jb.Parent = row
        local jc = Instance.new("UICorner")
        jc.CornerRadius = UDim.new(0, 5)
        jc.Parent = jb
        jb.MouseEnter:Connect(function() jb.BackgroundColor3 = C_PANEL2 end)
        jb.MouseLeave:Connect(function() jb.BackgroundColor3 = C_PANEL end)
        jb.MouseButton1Click:Connect(function() joinServer(s.id) end)
    end
end

refreshBtn.MouseButton1Click:Connect(function()
    refreshBtn.Text = "..."
    task.spawn(function()
        pcall(fetchServers, false)
        refreshBtn.Text = "REFRESH"
        renderServers()
    end)
end)

--─────────────────────────────────────────────────────────────────────────────
-- TAB SWITCH
--─────────────────────────────────────────────────────────────────────────────
local function setTab(which)
    finderPage.Visible = which == "finder"
    srvPage.Visible = which == "srv"
    setPage.Visible = which == "set"
    tabFind.BackgroundColor3 = which == "finder" and C_PANEL2 or C_PANEL
    tabFind.TextColor3 = which == "finder" and C_ACCENT or C_DIM
    tabServer.BackgroundColor3 = which == "srv" and C_PANEL2 or C_PANEL
    tabServer.TextColor3 = which == "srv" and C_ACCENT or C_DIM
    tabSet.BackgroundColor3 = which == "set" and C_PANEL2 or C_PANEL
    tabSet.TextColor3 = which == "set" and C_ACCENT or C_DIM
end
tabFind.MouseButton1Click:Connect(function() setTab("finder") end)
tabServer.MouseButton1Click:Connect(function() setTab("srv") end)
tabSet.MouseButton1Click:Connect(function() setTab("set") end)

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
footer.Text = "RSHIFT = sembunyikan · END = unload · v8.0 clean"
footer.Parent = main

--─────────────────────────────────────────────────────────────────────────────
-- LOOPS
--─────────────────────────────────────────────────────────────────────────────
local function scanLoop()
    while state.alive do
        pcall(refreshESP)
        task.wait(CONFIG.scanInterval)
    end
end

local function pendingLoop()
    while state.alive do
        task.wait(1)
        for inst, data in pairs(state.eggs) do
            if data.pending and inst.Parent then
                pcall(resolvePending, inst)
            end
        end
    end
end

local function tpLoop()
    while state.alive do
        if state.autoTPOn then pcall(teleportToEgg) end
        task.wait(0.25)
    end
end

local function statusLoop()
    while state.alive do
        local found = 0
        for _ in pairs(state.eggs) do found = found + 1 end
        local here = #Players:GetPlayers()
        srvInfo.Text = string.format("server saat ini: %d/%d pemain · %s",
            here, Players.MaxPlayers, string.sub(game.JobId or "", 1, 8))
        dot.BackgroundColor3 = found > 0 and C_ACCENT or Color3.fromRGB(220, 170, 80)
        task.wait(0.5)
    end
end

local function listLoop()
    while state.alive do
        if finderPage.Visible then pcall(renderFinder) end
        if srvPage.Visible and #state.servers > 0 then pcall(renderServers) end
        task.wait(1)
    end
end

-- filter egg-level untuk feed/AUTO (min + rarity + mut + search)
function matchesFilters(e)
    if FILTER.minValue > 0 and (eggValue(e) or 0) < FILTER.minValue then return false end
    if FILTER.rarity ~= "any" and lower(e.rarity or "") ~= FILTER.rarity then return false end
    if FILTER.mut ~= "any" then
        local hit = false
        for _, m in ipairs(e.muts or {}) do
            if lower(m) == FILTER.mut then hit = true break end
        end
        if not hit then return false end
    end
    if FILTER.search ~= "" and FILTER.search ~= nil then
        local nm = lower(e.name or "")
        if not string.find(nm, FILTER.search, 1, true) then return false end
    end
    return true
end

-- perekam feed: snapshot egg server ini → feed.servers[jobId]
local function feedLoop()
    while state.alive do
        task.wait(2)
        local job = game.JobId
        if job and job ~= "" then
            local eggs = {}
            local n = 0
            for inst, data in pairs(state.eggs) do
                if inst.Parent and data.part and data.part.Parent then
                    n = n + 1
                    local muts = data.muts or {}
                    local eff = mutEffMult(muts)
                    local val = data.value
                    local est = data.est
                    if not val and data.dbBase then
                        val = data.dbBase * eff
                        est = true
                    end
                    local rar = data.rarity or "common"
                    local p = data.part.Position
                    local posKey = math.floor(p.X / 10) .. "_" .. math.floor(p.Y / 10) .. "_" .. math.floor(p.Z / 10)
                    local key = lower(data.name or inst.Name) .. "|" .. tostring(val) .. "|" ..
                        tostring(#muts) .. "|" .. rar .. "|" .. posKey
                    eggs[key] = {
                        name   = data.name or "?",
                        rarity = rar,
                        muts   = muts,
                        value  = val or 0,
                        est    = est and true or false,
                        mult   = data.mult or 0,
                        dbBase = data.dbBase,
                        ts     = data.firstSeen or os.time(),
                    }
                end
            end

            local old = feed.servers[job]
            local here = #Players:GetPlayers()
            local changed = (not old) or old.eggCount ~= n or here ~= (old.players or -1)

            local list = {}
            for _, e in pairs(eggs) do table.insert(list, e) end

            feed.servers[job] = {
                jobId    = job,
                ts       = old and old.ts or os.time(),
                lastSeen = os.time(),
                players  = here,
                max      = Players.MaxPlayers,
                eggs     = list,
                eggCount = n,
            }

            local now2 = os.time()
            for jid, srv in pairs(feed.servers) do
                if now2 - (srv.lastSeen or 0) > CONFIG.feedExpiry then
                    feed.servers[jid] = nil
                    changed = true
                end
            end

            if changed then
                saveFeed()
                if finderPage.Visible then pcall(renderFinder) end
            end
        end
    end
end

-- AUTO: server-hopping sampai egg lolos filter ketemu
local function autoLoop()
    while state.alive do
        task.wait(0.5)
        if FILTER.auto and os.clock() - (state.lastHop or 0) >= FILTER.interval then
            if FILTER.waitReset and (os.time() % CONFIG.resetCycle) > 25 then
                -- di luar jendela reset: tunggu, feed terus direfresh
            else
                state.lastHop = os.clock()
                local haveMatch = false
                for inst, data in pairs(state.eggs) do
                    if data.part and data.part.Parent then
                        if matchesFilters({
                            value = resolveCurrentEggValue(data),
                            rarity = data.rarity,
                            muts = data.muts,
                            name = data.name,
                        }) then
                            haveMatch = true
                            break
                        end
                    end
                end
                if haveMatch then
                    notify("Target lolos filter ada di server ini!", 4, C_GOLD)
                else
                    local target = pickHopTarget()
                    if target then
                        feed.visited[target] = os.time()
                        feed.visited[game.JobId] = os.time()
                        saveFeed()
                        notify("AUTO: hop ke server baru...", 3)
                        task.wait(0.2)
                        joinServer(target)
                    else
                        notify("AUTO: tidak ada kandidat server — refresh manual", 4)
                        pcall(fetchServers, true)
                    end
                end
            end
        end
    end
end

--─────────────────────────────────────────────────────────────────────────────
-- KEYBINDS + UNLOAD
--─────────────────────────────────────────────────────────────────────────────
local function unload()
    state.alive = false
    for inst in pairs(state.espCache) do destroyESP(inst) end
    pcall(function() gui:Destroy() end)
    _G.SAE_FINDER = nil
    notify("SAE Finder unloaded", 2)
end

UserInputService.InputBegan:Connect(function(input, gep)
    if gep then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
    elseif input.KeyCode == Enum.KeyCode.End then
        unload()
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    main.Visible = false
end)
minBtn.MouseButton1Click:Connect(function()
    main.Visible = false
end)

--─────────────────────────────────────────────────────────────────────────────
-- BOOT
--─────────────────────────────────────────────────────────────────────────────
loadFeed()
setTab("finder")
syncButtons()
pcall(renderFinder)
if PLACE_ID ~= 107778070777162 then
    notify("Bukan place SAE — fitur egg bisa kosong", 5)
else
    notify("SAE Finder v8 siap — FINDER = feed, AUTO = hop.", 4)
end

_G.SAE_FINDER = {
    unload  = unload,
    config  = CONFIG,
    filter  = FILTER,
    state   = state,
    feed    = feed,
    version = "8.0",
    dump    = function()
        local out = {}
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if (inst:IsA("BasePart") or inst:IsA("Model")) and matchesKeyword(inst.Name) then
                local attrs = {}
                pcall(function()
                    for k, v in pairs(inst:GetAttributes()) do
                        table.insert(attrs, k .. "=" .. tostring(v))
                    end
                end)
                table.insert(out, inst.ClassName .. " :: " .. inst:GetFullName() ..
                    (#attrs > 0 and ("  [" .. table.concat(attrs, ",") .. "]") or ""))
            end
        end
        local txt = table.concat(out, "\n")
        print("=== SAE DUMP v8 (" .. #out .. " kandidat) ===\n" .. txt)
        pcall(function() setclipboard(txt) end)
        notify(#out .. " kandidat di-dump ke console & clipboard", 5)
    end,
}

task.spawn(scanLoop)
task.spawn(pendingLoop)
task.spawn(tpLoop)
task.spawn(statusLoop)
task.spawn(listLoop)
task.spawn(feedLoop)
task.spawn(autoLoop)
task.spawn(function()
    task.wait(0.5)
    pcall(fetchServers, false)
    if state.alive then renderServers() end
end)
task.spawn(function()
    while state.alive do
        task.wait(30)
        pcall(fetchServers, false)
    end
end)
task.spawn(function()
    task.wait(6)
    if not state.alive then return end
    local n = 0
    for _ in pairs(state.eggs) do n = n + 1 end
    if n == 0 then
        local out = {}
        pcall(function()
            for _, inst in ipairs(Workspace:GetDescendants()) do
                if (inst:IsA("BasePart") or inst:IsA("Model")) and #out < 60 then
                    table.insert(out, inst.ClassName .. " :: " .. inst:GetFullName())
                end
            end
        end)
        print("[SAE v8] 0 egg terdeteksi — mode:" .. tostring(state.scanMode) ..
            " | sampel objek:\n" .. table.concat(out, "\n"))
        notify("0 egg — buka console (F9), kirim isi ke Asta", 7)
    end
end)
