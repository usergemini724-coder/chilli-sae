# chilli-sae

Rebuild **egg finder** untuk game **Steal An Egg** (place `107778070777162`) — keyless, tanpa password, tanpa HWID, tanpa remote loader Luarmor.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/usergemini724-coder/chilli-sae/main/sae-eggf.lua?v=1"))()
```

Ganti `v=1` → `v=2`, `v=3`, dst tiap habis edit (raw GitHub di-cache CDN ~5 menit).

## Fitur

**Tab EGG FINDER**
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

Egg dideteksi dari **nama objek** yang mengandung `egg` di dalam folder ber-egg, atau objek yang punya attribute `Rarity`/`Type`/`Tier`. Kalau game update dan nama berubah:

1. Jalankan `_G.SAE_EGGF.dump()` di console → daftar kandidat ter-copy ke clipboard
2. Sesuaikan `CONFIG.keywords` di bagian atas file
3. Push sebagai `v+1`

## Struktur

| Bagian | Isi |
|---|---|
| `CONFIG` | interval scan, range, keyword, cooldown |
| `RARITY` | peta warna rarity |
| `collectEggs` / `refreshESP` | deteksi + render, cap `maxRendered` |
| `fetchServers` | `games.roblox.com/v1/games/{placeId}/servers/Public` |
| `joinServer` | teleport ke `jobId` |

## Catatan

- Server list publik dibatasi ±300 jobId per fetch; jobId bisa expired kalau diklik lama setelah refresh.
- `TeleportToPlaceInstance` gagal pada server penuh — pakai server yang masih ada slot.
- Tidak ada telemetry, tidak ada API key, tidak ada request ke selain `roblox.com` + `raw.githubusercontent.com`.
