# chilli-sae

Rebuild **egg finder** untuk game **Steal An Egg** (place `107778070777162`) — keyless, tanpa password, tanpa HWID, tanpa remote loader Luarmor.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/usergemini724-coder/chilli-sae/main/sae-eggf.lua?v=3"))()
```

Ganti `v=1` → `v=2`, `v=3`, dst tiap habis edit (raw GitHub di-cache CDN ~5 menit).

## Fitur

**Tab FINDER** (ala Chilli Finder, keyless)
- Feed "top recent eggs": nama, badge rarity (golden/rainbow/...), `$value/s`, `xmultiplier`, umur (`3m ago`), tombol `JOIN` per baris
- Feed lokal yang **persist di disk executor** (`chilli_sae_feed.json`) — riwayat lolos teleport karena tiap hop hanya matikan VM, file tetap ada
- `AUTO` — server-hopping otomatis (klik: 5s → 10s → 15s → 30s → OFF); berhenti hop kalau egg lolos filter ada di server sekarang
- `MIN` — filter nilai minimum (Any/1M/100M/1B/10B/100B/1T per detik)
- `RARITY` — filter mutasi (Any/Golden/Rainbow/Mythic/Secret/Divine)
- `CLEAR` — bersihkan feed
- Value & multiplier di-parse dari BillboardGui game; egg dicatat kalau `≥$1M/s` atau bukan common

**Tab ESP**
- ESP: nama egg + jarak meter + highlight per rarity
- Auto-teleport ke egg terdekat (toggle + cooldown 1,5 s)
- Range maksimum bisa diatur (default 2500 m)
- List 14 egg terdekat, tombol `TP` per baris
- Warna rarity: common → godly

**Tab SERVERS**
- Daftar server publik, urut dari yang paling ramai
- Jumlah pemain `playing/maxPlayers` + ping per server
- Warna indikator: hijau (sepi) → kuning → merah (penuh)
- Tombol `JOIN` (TeleportToPlaceInstance, fallback TeleportAsync)
- Info jumlah pemain di server saat ini

## Keybind

| Tombol | Fungsi |
|---|---|
| `RIGHT SHIFT` | Sembunyikan / tampilkan UI |
| `END` | Unload total |

## Kalau egg tidak terdeteksi

Deteksi 3 lapis (v2):

1. **strict** — nama mengandung `egg` DAN berada di folder ber-egg atau punya attribute `Rarity`/`Type`/`Tier`
2. **name** — nama mengandung `egg`, di mana pun
3. **label** — BillboardGui/TextLabel yang teksnya mengandung `egg` (model bernama generik)

Mode aktif tampil di status bar (`mode:strict` dst). Kalau semua gagal, setelah 6 detik script otomatis buang sampel 60 objek ke console (F9) — kirim ke Asta untuk tuning `CONFIG.keywords`.

## Struktur

| Bagian | Isi |
|---|---|
| `CONFIG` | interval scan, range, keyword, cooldown |
| `FILTER` / `feed` | filter finder + feed lokal (`chilli_sae_feed.json`) |
| `extractInfo` | parse nama, `$X/s`, `xN`, mutasi dari label game |
| `RARITY` / `MUT_COLORS` | peta warna rarity & mutasi |
| `collectEggs` / `refreshESP` | deteksi + render, cap `maxRendered` |
| `fetchServers` | `games.roblox.com/v1/games/{placeId}/servers/Public` |
| `pickHopTarget` / `autoLoop` | pemilihan server & hopping otomatis |
| `joinServer` | teleport ke `jobId` |

## Catatan

- Server list publik dibatasi ±300 jobId per fetch; jobId bisa expired kalau diklik lama setelah refresh.
- `TeleportToPlaceInstance` gagal pada server penuh — pakai server yang masih ada slot.
- Tidak ada telemetry, tidak ada API key, tidak ada request ke selain `roblox.com` + `raw.githubusercontent.com`.
