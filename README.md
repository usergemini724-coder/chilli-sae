# chilli-sae

Rebuild **egg finder** untuk game **Steal An Egg** (place `107778070777162`) — keyless, tanpa password, tanpa HWID, tanpa remote loader Luarmor.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/usergemini724-coder/chilli-sae/main/sae-eggf.lua?v=6"))()
```

Ganti `v=1` → `v=2`, `v=3`, dst tiap habis edit (raw GitHub di-cache CDN ~5 menit).

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
