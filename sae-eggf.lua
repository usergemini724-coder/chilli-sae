--[[═══════════════════════════════════════════════════════════════════════════
    SAE — EGG FINDER + SERVER BROWSER  ·  v6
    Game   : Steal An Egg (place 107778070777162)
    Build  : keyless, no password, no HWID, no remote loader
    Load   : loadstring(game:HttpGet(".../sae-eggf.lua?v=6"))()
    Tabs   : [FINDER] [ESP] [SERVERS]
    Keys   : RIGHT-SHIFT = toggle UI      END = unload

    v6 changes
      · UI FINDER diganti total: feed FLAT Chilli-style (1 baris = 1 egg)
        ikon pengganti gambar = kotak warna rarity + inisial (emas = TOP-10)
        badge mutasi + value + x-mult + umur + pemain live x/7 per baris
        JOIN per baris egg, sort TOP dulu lalu value desc

    v5 changes
      · deteksi UNION per-objek (strict+name+label digabung, bukan fallback)
      · pending-watchlist 90s: telur yang datanya telat di-re-parse terus
      · event-driven: DescendantAdded → telur baru masuk di frame dia spawn
      · filter MUTATION & RARITY terpisah (7 mutasi, ladder 10 tier resmi:
        Common<Uncommon<Rare<Epic<Legendary<Cosmic<Mythic<Secret<Eternal<Divine)
      · value fallback dari DB 122 pet (wiki snapshot) → tampil "~$X/s"
      · feed per-server: x/7 pemain, ≤4/7 default, server ★TOP-10 boleh ≤6/7
        (7/7 selalu dibuang), 6/7 ditandai "1 SLOT RACE"
      · sort value desc (terberat dulu), tiebreak pemain tersedikit
      · JOIN pre-check jumlah pemain live (API servers/Public)
      · catatan server >300s (siklus reset All-Egg) auto-dihapus
      · opsi WAIT RESET: AUTO hop hanya di jendela ±25s setelah tick reset 5 menit
      · tanpa gambar pet (anti-lag, by design)
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
    pendingWindow = 90,    -- telur tanpa data dikejar 90 detik
    feedExpiry    = 300,   -- catatan server lebih tua = hapus
}

-- ladder rarity resmi (Cosmic DI TENGAH — khas SAE)
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

--─────────────────────────────────────────────────────────────────────────────
-- MUTASI (7) — display name, nama internal config, multiplier
-- stacking ADDITIF: eff = 1 + Σ(scalar − 1)
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
-- token teks → nama kanonik (urutan panjang dulu biar "spirit bloom" tak kepacak "bloom")
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
    { tok = "boss",         can = "Fractured"    }, -- diproses SETELAH nama pet dibuang
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
-- PET DB (fallback value) — snapshot wiki 2026-09-28, 106 slot + 16 lead
-- [nama-lowercase] = { income_per_detik, "Rarity" }
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
-- STATE
--─────────────────────────────────────────────────────────────────────────────
local state = {
    eggs       = {},          -- [Instance] = { part, rarity, name, value, mult, muts, est, firstSeen, pending, since }
    espCache   = {},
    rendered   = 0,
    autoTPOn   = false,
    lastTP     = 0,
    lastHop    = 0,
    servers    = {},          -- server browser: { {id, playing, max, ping} }
    srvById    = {},          -- [jobId] = server ref (untuk pre-check JOIN)
    srvAt      = 0,           -- waktu fetch terakhir
    currentJob = nil,
    fetching   = false,
    scanMode   = "-",
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
-- FORMAT
--─────────────────────────────────────────────────────────────────────────────
local FILTER = {
    auto       = false,
    interval   = 5,
    minValue   = 0,
    rarity     = "any",   -- ladder lower
    mut        = "any",   -- display lower ("spirit bloom" dll)
    maxPlayers = 4,       -- server biasa ≤4/7; ★TOP ≤6/7; 7/7 selalu buang
    waitReset  = false,   -- hop hanya di jendela setelah tick reset 5 menit
}
local joinServer, joinFinderServer, fetchServers, pickHopTarget, matchesFilters  -- forward

local VALUE_STEPS  = { 0, 1e6, 1e8, 1e9, 1e10, 1e11, 1e12 }
local RARITY_STEPS = { "any", "common", "uncommon", "rare", "epic", "legendary",
                       "cosmic", "mythic", "secret", "eternal", "divine" }
local MUT_STEPS    = { "any", "silver", "golden", "rainbow", "bloom",
                       "spirit bloom", "parasite", "fractured" }

local FEED_FILE = "chilli_sae_feed.json"
local feed = { servers = {}, visited = {} }   -- servers[jobId] = { jobId, ts, lastSeen, players, max, eggs={...} }

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
-- PARSER LABEL → (nama, value, mult, muts, rarity)
-- urutan: cocokkan nama pet dulu (buang dari teks) → baru token mutasi,
-- supaya "Cosmic Skeleton Boss" tidak salah terbaca mutasi Fractured.
--─────────────────────────────────────────────────────────────────────────────
local function parseMoney(text)
    local num, suf = string.match(text, "%$([%d%.]+)%s*(%a?)%s*/s")
    if num then
        local n = tonumber(num) or 0
        local suffixMult = { K = 1e3, M = 1e6, B = 1e9, T = 1e12 }
        n = n * (suffixMult[suf] or 1)
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
    local texts = {}
    if fallbackLabel then table.insert(texts, fallbackLabel) end
    pcall(function()
        local node = part
        for _ = 1, 3 do
            if not node then break end
            for _, ch in ipairs(node:GetDescendants()) do
                if (ch:IsA("TextLabel") or ch:IsA("TextButton")) and ch.Text and #ch.Text > 0 and #ch.Text < 64 then
                    table.insert(texts, ch.Text)
                end
            end
            if #texts > 10 then break end
            node = node.Parent
        end
    end)

    local value, mult, nameTxt
    local muts = {}
    local rarityTxt
    local dbBase, dbRar

    -- gabung teks untuk pencarian nama & mutasi
    local low = lower(table.concat(texts, " | "))

    -- 1) nama pet via DB: kandidat penuh dulu ("cosmic skeleton boss" aman),
    --    lalu varian tanpa kata mutasi ("golden kitsune" → "kitsune")
    for _, t in ipairs(texts) do
        local cand0 = lower(t)
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
            low = blankOut(low, lower(t))
            break
        end
    end

    -- 2) rarity via teks
    for _, r in ipairs(RARITY_ORDER) do
        if string.find(low, r, 1, true) then
            rarityTxt = r
            break
        end
    end

    -- 3) mutasi: token terpanjang dulu, habis match dibuang dari teks
    for _, tk in ipairs(MUT_TOKENS) do
        local found
        low, found = blankOut(low, tk.tok)
        if found then
            local dup = false
            for _, m in ipairs(muts) do if m == tk.can then dup = true end end
            if not dup then table.insert(muts, tk.can) end
        end
    end

    -- 4) value & multiplier per teks
    for _, t in ipairs(texts) do
        local v = parseMoney(t)
        if v and not value then value = v end
        local m = parseMult(t)
        if m and not mult then mult = m end
    end

    -- 5) nama tampilan terbaik (teks tanpa $ / xN yang paling panjang)
    if not nameTxt then
        local score = -1
        for _, t in ipairs(texts) do
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
-- DETEKSI v5 — UNION per-objek (strict ∪ name ∪ label, bukan fallback berlapis)
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

    -- pass 1: nama mengandung keyword (strict bila di container egg / beratribut)
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

    -- pass 2: label Billboard (telur reload 5 menit sering model generik)
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

    -- gabung: yang lama masih hidup dipertahankan datanya
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

local function scanLoop()
    while state.alive do
        pcall(refreshESP)
        task.wait(CONFIG.scanInterval)
    end
end

-- pending-watchlist: telur yang datanya telat muncul (reload 5 menit) dikejar 90s
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

-- event-driven: telur baru masuk di frame dia spawn
Workspace.DescendantAdded:Connect(function(inst)
    if not state.alive then return end
    pcall(function()
        if inst:IsA("BasePart") or inst:IsA("Model") then
            if matchesKeyword(inst.Name) or inEggContainer(inst) then
                addEgg(inst)
            end
        elseif inst:IsA("BillboardGui") and inst.Name ~= "SAEEggBB" then
            task.defer(function()
                if not state.alive or not inst.Parent then return end
                for _, ch in ipairs(inst:GetDescendants()) do
                    if ch:IsA("TextLabel") and ch.Text and (matchesKeyword(ch.Text) or parseMoney(ch.Text)) then
                        local target
                        if inst.Adornee and inst.Adornee:IsA("BasePart") then
                            target = inst.Adornee
                        elseif inst.Parent and inst.Parent:IsA("BasePart") then
                            target = inst.Parent
                        end
                        if target then
                            addEgg(target, {
                                part = target, rarity = rarityOf(target), firstSeen = os.time(),
                                pending = true, since = os.clock(), label = ch.Text, viaLabel = true,
                            })
                        end
                        break
                    end
                end
            end)
        end
    end)
end)

--─────────────────────────────────────────────────────────────────────────────
-- AUTO TELEPORT (ESP tab)
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

local function tpLoop()
    while state.alive do
        if state.autoTPOn then pcall(teleportToEgg) end
        task.wait(0.25)
    end
end

--─────────────────────────────────────────────────────────────────────────────
-- HTTP + SERVER LIST
--─────────────────────────────────────────────────────────────────────────────
local function httpGet(url)
    local body
    local ok = pcall(function() body = game:HttpGet(url, true) end)
    if ok and type(body) == "string" and #body > 0 then return body end
    ok = pcall(function() body = request({ Url = url, Method = "GET" }).Body end)
    if ok and type(body) == "string" and #body > 0 then return body end
    return nil
end

-- excludeFull=true dipakai AUTO biar server penuh tidak dibuang-buang waktu
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

-- jumlah pemain live: server ini → lokal; server lain → cache API (≤30s)
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

-- JOIN feed dengan pre-check jumlah pemain:
--   7/7 = FULL skip · biasa >4/7 skip · ★TOP ≤6/7 boleh (6/7 = RACE 1 slot)
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
        elseif playing > FILTER.maxPlayers then
            notify("Skip: " .. playing .. "/7 > batas " .. FILTER.maxPlayers .. "/7", 3)
            return
        end
    else
        notify("Data pemain belum ada — JOIN blind", 3)
    end
    joinServer(jobId)
end

-- AUTO hop: prioritas server paling kosong (1/7) yang belum dikunjungi
function pickHopTarget()
    if #state.servers == 0 or os.clock() - state.srvAt > 60 then
        pcall(fetchServers, true)
    end
    local now = os.time()
    local cands = {}
    for _, s in ipairs(state.servers) do
        if s.id ~= game.JobId and s.playing > 0 and s.max > 0 and s.playing < s.max then
            table.insert(cands, s)
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
-- UI SHELL
--────────────────────────────────────────────────────────────────────────────
local C_BG      = Color3.fromRGB(18, 18, 22)
local C_PANEL   = Color3.fromRGB(28, 28, 34)
local C_STROKE  = Color3.fromRGB(58, 58, 70)
local C_TEXT    = Color3.fromRGB(235, 235, 240)
local C_DIM     = Color3.fromRGB(150, 150, 162)
local C_ACCENT  = Color3.fromRGB(120, 220, 150)
local C_GOLD    = Color3.fromRGB(255, 210, 80)

local gui = Instance.new("ScreenGui")
gui.Name = "SAE_EggFinder"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 999

local okParent = pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not okParent or not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(470, 380)
main.Position = UDim2.new(0.5, -235, 0.5, -190)
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
titleLabel.Text = "SAE · EGG FINDER v6"
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

local function makeTab(text, order, count)
    count = count or 2
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1 / count, -4, 1, 0)
    b.Position = UDim2.new(order / count, order * 4, 0, 0)
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

local tabFind   = makeTab("FINDER", 0, 3)
local tabEgg    = makeTab("ESP", 1, 3)
local tabServer = makeTab("SERVERS", 2, 3)

local pages = Instance.new("Frame")
pages.Size = UDim2.new(1, -24, 1, -110)
pages.Position = UDim2.fromOffset(12, 78)
pages.BackgroundTransparency = 1
pages.Parent = main

local finderPage = Instance.new("Frame")
finderPage.Size = UDim2.fromScale(1, 1)
finderPage.BackgroundTransparency = 1
finderPage.Parent = pages

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
    finderPage.Visible = which == "finder"
    eggPage.Visible = which == "egg"
    srvPage.Visible = which == "srv"
    tabFind.BackgroundColor3 = which == "finder" and C_PANEL or C_BG
    tabFind.TextColor3 = which == "finder" and C_ACCENT or C_DIM
    tabEgg.BackgroundColor3 = which == "egg" and C_PANEL or C_BG
    tabEgg.TextColor3 = which == "egg" and C_ACCENT or C_DIM
    tabServer.BackgroundColor3 = which == "srv" and C_PANEL or C_BG
    tabServer.TextColor3 = which == "srv" and C_ACCENT or C_DIM
end
tabFind.MouseButton1Click:Connect(function() setTab("finder") end)
tabEgg.MouseButton1Click:Connect(function() setTab("egg") end)
tabServer.MouseButton1Click:Connect(function() setTab("srv") end)

--─────────────────────────────────────────────────────────────────────────────
-- FINDER PAGE v5 — feed per-server, 2 filter terpisah, sort value desc
--─────────────────────────────────────────────────────────────────────────────
local btnRow1 = Instance.new("Frame")
btnRow1.Size = UDim2.new(1, 0, 0, 28)
btnRow1.BackgroundTransparency = 1
btnRow1.Parent = finderPage

local btnRow2 = Instance.new("Frame")
btnRow2.Size = UDim2.new(1, 0, 0, 28)
btnRow2.Position = UDim2.fromOffset(0, 30)
btnRow2.BackgroundTransparency = 1
btnRow2.Parent = finderPage

local function makeFilterBtn(text, order, parent, cols)
    cols = cols or 3
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1 / cols, -4, 1, 0)
    b.Position = UDim2.new(order / cols, order * 4, 0, 0)
    b.BackgroundColor3 = C_PANEL
    b.Font = Enum.Font.GothamBold
    b.TextSize = 10
    b.TextColor3 = C_TEXT
    b.Text = text
    b.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 5)
    c.Parent = b
    return b
end

local btnAuto  = makeFilterBtn("AUTO OFF", 0, btnRow1, 4)
local btnMinVal= makeFilterBtn("MIN Any", 1, btnRow1, 4)
local btnRarity= makeFilterBtn("RARITY Any", 2, btnRow1, 4)
local btnMut   = makeFilterBtn("MUT Any", 3, btnRow1, 4)
local btnPlyr  = makeFilterBtn("P<=4", 0, btnRow2, 4)
local btnReset = makeFilterBtn("RESET-WAIT OFF", 1, btnRow2, 4)
local btnClear = makeFilterBtn("CLEAR", 2, btnRow2, 4)

local finderSub = Instance.new("TextLabel")
finderSub.Size = UDim2.new(1, 0, 0, 18)
finderSub.Position = UDim2.fromOffset(0, 60)
finderSub.BackgroundTransparency = 1
finderSub.Font = Enum.Font.GothamBold
finderSub.TextSize = 10
finderSub.TextColor3 = C_DIM
finderSub.TextXAlignment = Enum.TextXAlignment.Left
finderSub.Text = "..."
finderSub.Parent = finderPage

local finderList = Instance.new("ScrollingFrame")
finderList.Size = UDim2.new(1, 0, 1, -82)
finderList.Position = UDim2.fromOffset(0, 82)
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

-- TOP-10 DINAMIS: 10 value terbesar lintas feed; server berisi salah satunya = ★TOP
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

-- FINDER v6: feed FLAT Chilli-style — 1 baris = 1 egg, tanpa gambar pet
-- (ikon = kotak warna rarity + inisial; emas = member TOP-10)
local function renderFinder()
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

    -- kumpulkan baris flat: egg lolos filter + server lolos batas pemain
    local rows = {}
    local nEgg, nServer, nTop = 0, 0, 0
    for jobId, srv in pairs(feed.servers) do
        nServer = nServer + 1
        nEgg = nEgg + #(srv.eggs or {})
        if topServers[jobId] then nTop = nTop + 1 end
        local isTopSrv = topServers[jobId] == true
        local live = state.srvById[jobId]
        if live and os.clock() - state.srvAt < 30 then
            srv.players = live.playing
            srv.max = live.max or srv.max
        end
        local players = srv.players or 0
        local cap = srv.max or 7
        if players < cap and (isTopSrv or players <= FILTER.maxPlayers) then
            for _, e in ipairs(srv.eggs or {}) do
                if matchesFilters(e) then
                    table.insert(rows, { e = e, srv = srv, isTop = isTopSrv or topSet[e] == true })
                end
            end
        end
    end

    -- sort: member TOP dulu → value desc → terbaru
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
        row.Size = UDim2.new(1, -6, 0, 36)
        row.BackgroundColor3 = isTop and Color3.fromRGB(45, 37, 18) or Color3.fromRGB(24, 24, 30)
        row.LayoutOrder = i
        row.Parent = finderList
        local rc = Instance.new("UICorner")
        rc.CornerRadius = UDim.new(0, 6)
        rc.Parent = row

        -- ikon pengganti gambar: kotak warna rarity (+ inisial), emas = TOP
        local ic = Instance.new("Frame")
        ic.Size = UDim2.fromOffset(24, 24)
        ic.Position = UDim2.fromOffset(5, 6)
        ic.BackgroundColor3 = isTop and C_GOLD or rarityColor(e.rarity)
        ic.Parent = row
        local icc = Instance.new("UICorner")
        icc.CornerRadius = UDim.new(0, 6)
        icc.Parent = ic
        local icTxt = Instance.new("TextLabel")
        icTxt.Size = UDim2.fromScale(1, 1)
        icTxt.BackgroundTransparency = 1
        icTxt.Font = Enum.Font.GothamBold
        icTxt.TextSize = 12
        icTxt.TextColor3 = Color3.fromRGB(20, 20, 24)
        icTxt.Text = isTop and "*" or string.upper(string.sub(e.name or "?", 1, 1))
        icTxt.Parent = ic

        -- nama pet (baris 1 kiri)
        local nm = Instance.new("TextLabel")
        nm.Size = UDim2.fromOffset(130, 14)
        nm.Position = UDim2.fromOffset(34, 4)
        nm.BackgroundTransparency = 1
        nm.Font = Enum.Font.GothamBold
        nm.TextSize = 11
        nm.TextColor3 = C_TEXT
        nm.TextXAlignment = Enum.TextXAlignment.Left
        nm.TextTruncate = Enum.TextTruncate.AtEnd
        nm.Text = e.name or "?"
        nm.Parent = row

        -- baris 2 kiri: rarity · pemain x/7 (live) · umur
        local pcol = "#78E68C"
        if (srv.players or 0) >= 6 then pcol = "#FF8C3C"
        elseif (srv.players or 0) >= 5 then pcol = "#FFB85C" end
        local rarCap = string.upper(string.sub(e.rarity or "common", 1, 1)) ..
            string.sub(e.rarity or "common", 2)
        local sub = Instance.new("TextLabel")
        sub.Size = UDim2.fromOffset(206, 11)
        sub.Position = UDim2.fromOffset(34, 20)
        sub.BackgroundTransparency = 1
        sub.Font = Enum.Font.Gotham
        sub.TextSize = 9
        sub.TextColor3 = C_DIM
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.TextTruncate = Enum.TextTruncate.AtEnd
        sub.RichText = true
        sub.Text = string.format("%s%s · <font color=\"%s\">%d/%d</font> · %s",
            isTop and "*TOP · " or "", rarCap, pcol,
            srv.players or 0, srv.max or 7, fmtAge(e.ts))
        sub.Parent = row

        -- badge mutasi (zona tengah; muncul hanya kalau ada)
        local muts = mutText(e.muts)
        if muts then
            local pill = Instance.new("TextLabel")
            pill.Size = UDim2.fromOffset(70, 16)
            pill.Position = UDim2.new(1, -246, 0, 4)
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

        -- value (kanan, baris 1) + x-mult (baris 2)
        local val = Instance.new("TextLabel")
        val.Size = UDim2.fromOffset(146, 14)
        val.Position = UDim2.new(1, -196, 0, 4)
        val.BackgroundTransparency = 1
        val.Font = Enum.Font.GothamBold
        val.TextSize = 11
        val.TextColor3 = (eggValue(e) <= 0) and C_DIM or
            (e.est and Color3.fromRGB(110, 180, 125) or Color3.fromRGB(120, 230, 140))
        val.TextXAlignment = Enum.TextXAlignment.Right
        val.Text = eggValue(e) > 0 and ((e.est and "~" or "") .. fmtValue(eggValue(e))) or "$?"
        val.Parent = row

        local xinfo = Instance.new("TextLabel")
        xinfo.Size = UDim2.fromOffset(146, 11)
        xinfo.Position = UDim2.new(1, -196, 0, 20)
        xinfo.BackgroundTransparency = 1
        xinfo.Font = Enum.Font.Gotham
        xinfo.TextSize = 9
        xinfo.TextColor3 = C_DIM
        xinfo.TextXAlignment = Enum.TextXAlignment.Right
        xinfo.Text = (e.mult or 0) > 1 and ("x" .. string.format("%.2f", e.mult)) or ""
        xinfo.Parent = row

        -- JOIN per baris (server milik egg ini)
        local jb = Instance.new("TextButton")
        jb.Size = UDim2.fromOffset(46, 24)
        jb.Position = UDim2.new(1, -51, 0, 6)
        jb.BackgroundColor3 = isTop and C_GOLD or Color3.fromRGB(255, 150, 40)
        jb.Font = Enum.Font.GothamBold
        jb.TextSize = 11
        jb.TextColor3 = Color3.fromRGB(30, 20, 5)
        jb.Text = "JOIN"
        jb.Parent = row
        local jc = Instance.new("UICorner")
        jc.CornerRadius = UDim.new(0, 6)
        jc.Parent = jb
        jb.MouseButton1Click:Connect(function()
            joinFinderServer(srv.jobId, isTop)
        end)
    end
end

local function syncButtons()
    btnAuto.Text = FILTER.auto and ("AUTO " .. FILTER.interval .. "s") or "AUTO OFF"
    btnAuto.TextColor3 = FILTER.auto and C_ACCENT or C_DIM
    btnMinVal.Text = "MIN " .. (FILTER.minValue > 0 and fmtValue(FILTER.minValue) or "Any")
    btnRarity.Text = "RARITY " .. (FILTER.rarity == "any" and "Any" or FILTER.rarity)
    btnMut.Text = "MUT " .. (FILTER.mut == "any" and "Any" or FILTER.mut)
    btnPlyr.Text = "P<=" .. FILTER.maxPlayers
    btnReset.Text = FILTER.waitReset and "RESET-WAIT ON" or "RESET-WAIT OFF"
    btnReset.TextColor3 = FILTER.waitReset and C_ACCENT or C_DIM
end

local minIdx, rarIdx, mutIdx, plyIdx = 1, 1, 1, 4
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
btnPlyr.MouseButton1Click:Connect(function()
    plyIdx = plyIdx % 6 + 1
    FILTER.maxPlayers = plyIdx
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
-- EGG PAGE (ESP)
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
                table.insert(list, { inst = inst, part = data.part, rarity = data.rarity, name = data.name, d = d })
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
        lbl.Text = e.name or e.inst.Name
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
        pcall(fetchServers, false)
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
footer.Text = "RSHIFT = sembunyikan · END = unload · v6"
footer.Parent = main

--─────────────────────────────────────────────────────────────────────────────
-- LOOPS
--─────────────────────────────────────────────────────────────────────────────
local function statusLoop()
    while state.alive do
        local found = 0
        for _ in pairs(state.eggs) do found = found + 1 end
        local here = #Players:GetPlayers()
        local cap = Players.MaxPlayers
        srvInfo.Text = string.format("server saat ini: %d/%d pemain", here, cap)
        statusLabel.Text = string.format(
            "egg: %d · mode:%s · tampil:%d · auto-tp:%s",
            found, state.scanMode or "-", state.rendered, state.autoTPOn and "ON" or "OFF"
        )
        task.wait(0.5)
    end
end

local function listLoop()
    while state.alive do
        if finderPage.Visible then pcall(renderFinder) end
        if eggPage.Visible then pcall(renderEggList) end
        task.wait(1)
    end
end

-- filter egg-level untuk feed/AUTO
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
    return true
end

-- perekam feed: snapshot egg server ini → feed.servers[jobId] (rebuild = tahan reset 5 menit)
local function feedLoop()
    while state.alive do
        task.wait(2)
        local job = game.JobId
        if job and job ~= "" then
            local eggs, changed = {}, false
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
            if not old or old.eggCount ~= n or here ~= (old.players or -1) then
                changed = true
            end

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

            -- buang server kadaluarsa
            local now = os.time()
            for jid, srv in pairs(feed.servers) do
                if now - (srv.lastSeen or 0) > CONFIG.feedExpiry then
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
            -- RESET-WAIT: hop hanya di jendela ±25s setelah tick reset 5 menit
            if FILTER.waitReset and (os.time() % CONFIG.resetCycle) > 25 then
                -- di luar jendela: tunggu, feed terus direfresh oleh feedLoop
            else
                state.lastHop = os.clock()
                local haveMatch = false
                for inst, data in pairs(state.eggs) do
                    if data.part and data.part.Parent then
                        local eff = mutEffMult(data.muts)
                        local val = data.value
                        if not val and data.dbBase then val = data.dbBase * eff end
                        if matchesFilters({
                            value = val or 0,
                            rarity = data.rarity,
                            muts = data.muts,
                        }) then
                            haveMatch = true
                            break
                        end
                    end
                end
                if haveMatch then
                    notify("Target lolos filter ada di server ini!", 4)
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
loadFeed()
setTab("finder")
syncButtons()
pcall(renderFinder)
if PLACE_ID ~= 107778070777162 then
    notify("Bukan place SAE — fitur egg bisa kosong", 5)
else
    notify("v6 loaded. FINDER = feed per-server + 2 filter. AUTO = hop.", 4)
end

_G.SAE_EGGF = {
    unload  = unload,
    config  = CONFIG,
    state   = state,
    version = "6.0",
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
        print("=== SAE DUMP v5 (" .. #out .. " kandidat) ===\n" .. txt)
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
-- refresh jumlah pemain tiap 30s (x/7 feed tetap segar)
task.spawn(function()
    while state.alive do
        task.wait(30)
        pcall(fetchServers, false)
    end
end)
-- auto-diagnosa: kalau 6 detik masih 0 egg, buang sampel struktur ke console
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
        print("[SAE] 0 egg terdeteksi — mode:" .. tostring(state.scanMode) ..
            " | sampel objek:\n" .. table.concat(out, "\n"))
        notify("0 egg — buka console (F9), kirim isi ke Asta", 7)
    end
end)
