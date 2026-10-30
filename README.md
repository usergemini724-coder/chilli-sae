# chilli-sae

Rebuild **egg finder** untuk game **Steal An Egg** (place `107778070777162`) — keyless, tanpa password, tanpa HWID, tanpa remote loader Luarmor.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/usergemini724-coder/chilli-sae/main/sae-eggf.lua?v=9"))()
```

Ganti `v=1` → `v=2`, `v=3`, dst tiap habis edit (raw GitHub di-cache CDN ~5 menit).

## v8.1 — solo-swarm tuning (anti-macet jam ramai)

- `AUTO` cycle: **3s / 5s / 10s / 15s / 30s / OFF**
- **AUTOJOIN chip baru**: saat AUTO ON, feed lintas-server yang lolos filter di-**join otomatis** (ambil value terbesar; ★TOP tetap boleh ≤6/7)
- **AUTO hop anti-macet**: fetch semua server publik (filter lokal) · visited 480s→**180s** · kalau CAP ketat bikin 0 kandidat saat jam ramai → **fallback longgar otomatis** (server non-full paling sepi, CAP diabaikan + notify)
- Toast "tidak ada kandidat" hanya muncul kalau benar-benar 0 server non-full di seluruh list

## v8 — full rebuild (clean dark minimal)

- **UI baru**: panel flat gelap 1 aksen hijau, tab pill FINDER/SERVERS/SETTINGS, hover state semua tombol, **toast slide-in** (kanan atas), **toggle knob animasi**, occupancy **BAR** di server list, status dot di topbar (hijau = egg terdeteksi)
- **SEARCH BOX** di FINDER — filter nama pet realtime (min. 2 huruf)
- **CAP filter** (ganti `P<=`): ≤4 / ≤2 / ≤6 / Any — batas pemain untuk JOIN & AUTO hop; **7/7 FULL selalu dibuang** di semua mode ("server tidak full" by design)
- **MIN default = Any** (penyebab feed kosong lama: default MIN $1.00B terlalu ketat)
- Close `×` / minimize `–` = sembunyikan (aman); unload beneran = `END` atau SETTINGS→UNLOAD
- Otak **v7 dipertahankan utuh**: parser per-depth scoping + sanity clamp 12× + PET_DB 122 + union detection + pending 90s + feed persist + TOP-10 dinamis (★ emas, JOIN ≤6/7 = RACE) + RESET-WAIT
- Tanpa auto-steal / auto-race / anti-hit — **pure finder + join**

## Akurasi nilai (warisan v7)

- **Label di-scope per kedalaman folder** — `value`/`rarity`/`mutasi` hanya dibaca dari cakupan setempat nama pet ditemukan; label telur tetangga di folder induk tidak lagi tercatat sebagai nilai telur ini
- **Sanity clamp** — value live > 12× base DB (stack mutasi penuh pun maks ±9×, aditif) = hampir pasti label asing → dibuang, fallback ke estimasi DB (`~$X/s`)
- `parseMoney` mendukung angka ber-koma (`$1,234.5B/s`) dan suffix huruf kecil
- Tangga MIN terverifikasi: Any → $1M → $100M → $1B → $10B → **$100B** → $1T (skala benar: 1e11)

## Fitur v6

**Tab FINDER — feed FLAT Chilli-style (1 baris = 1 egg)**
- Baris = satu egg: **ikon pengganti gambar** (kotak warna rarity + inisial pet; emas `★` = member TOP-10), nama pet, **badge mutasi** (Silver/Golden/Rainbow/Bloom/Spirit Bloom/Parasite/Fractured), `$value/s` hijau (`~` = estimasi DB), `xmult`, umur, **pemain live `x/7`** (hijau ≤4, oranye 5–6 = RACE), tombol `JOIN`
- Sort: member **TOP-10** dulu (baris emas) → value desc → terbaru; maks 30 baris
- JOIN per baris memakai server milik egg itu (pre-check live tetap jalan)
- **2 filter terpisah**: `MUT` (7 mutasi, nama internal Sakura/GreatBloom/Monstrous/Boss ikut dikenali) dan `RARITY` (ladder penuh)
- `MIN` — nilai minimum (Any/1M/100M/1B/10B/100B/1T per detik); `P<=` — batas pemain per server (default 4); `CLEAR`
- **★TOP-10 dinamis**: 10 value terbesar lintas feed (base × mutasi); server yang memuatnya boleh **≤6/7** pemain (badge `1 SLOT RACE` saat 6/7) — server biasa ≤`P<=`/7, **7/7 selalu dibuang**
- Sort: server ★TOP dulu → best value desc → pemain tersedikit; egg per server urut value desc
- **JOIN pre-check live**: cek jumlah pemain via API sebelum teleport (FULL → skip; melanggar batas → skip)
- Catatan server lebih tua dari **300 s** (siklus All-Egg Reset) auto-dihapus
- Feed **persist di disk executor** (`chilli_sae_feed.json`) — lolos teleport
- **Value fallback**: DB 122 pet (snapshot wiki) — label gagal dibaca → estimasi dari base × multiplier mutasi
- `AUTO` — server-hop (5/10/15/30 s), stop saat ada egg lolos filter; opsi **RESET-WAIT**: hop hanya di jendela ±25 s setelah tick reset 5 menit
- Tanpa gambar pet (by design, anti-lag)

**Tab ESP**
- ESP nama + jarak + highlight per rarity (10 tier, Cosmic ungu / Eternal emas-putih / Divine cyan)
- Auto-teleport (cooldown 1,5 s), range diatur (default 2500 m), list 14 egg terdekat + `TP`

**Tab SERVERS**
- Server publik urut populasi, `playing/max` + ping, warna hijau→kuning→merah, `JOIN`

## Engine deteksi (v5)

- **Union per-objek**: nama-egg ∪ atribut ∪ label Billboard digabung — bukan fallback berlapis (telur generik + label tak lagi terlewat)
- **Pending watchlist 90 s**: telur yang labelnya muncul belakangan di-re-parse terus sampai lengkap (mengatasi reload 5 menit)
- **Event-driven**: `Workspace.DescendantAdded` → telur baru masuk di frame dia spawn
- `mode:union` tampil di status bar; 0 egg setelah 6 s → auto-dump 60 sampel ke console (F9)
- `_G.SAE_EGGF.dump()` → kandidat + **atribut instance** ke console & clipboard

## Keybind

| Tombol | Fungsi |
|---|---|
| `RIGHT SHIFT` | Sembunyikan / tampilkan UI |
| `END` | Unload total |

## Catatan

- Server list publik dibatasi ±300 jobId per fetch; refresh jumlah pemain tiap 30 s.
- `TeleportToPlaceInstance` gagal pada server penuh — pre-check JOIN menjaga.
- Tidak ada telemetry, tidak ada API key, tidak ada request ke selain `roblox.com` + `raw.githubusercontent.com`.
