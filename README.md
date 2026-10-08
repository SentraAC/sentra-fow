<div align="center">

<img src="https://www.sentra.ac/logo.webp" alt="Sentra" width="90" />

# sentra-fow

### Free Fog of War anti-wallhack for your FiveM server — powered by [Sentra Anticheat](https://sentra.ac)

Raycast-based line-of-sight system that **hides players behind walls** from every
client — making wallhack cheats see nothing but empty streets.

[![Website](https://img.shields.io/badge/Website-sentra.ac-ff2b39?style=for-the-badge)](https://sentra.ac)
[![License](https://img.shields.io/badge/License-Free-3fb950?style=for-the-badge)](#license)
[![FiveM](https://img.shields.io/badge/FiveM-Compatible-6441a5?style=for-the-badge)](https://fivem.net)

<br />

[![Watch the demo](https://img.youtube.com/vi/DnDXMf_0X1o/maxresdefault.jpg)](https://www.youtube.com/watch?v=DnDXMf_0X1o)

</div>

---

## ✨ Why sentra-fow?

Wallhacks let cheaters see players through any wall, giving them a massive combat
advantage. sentra-fow stops this at the source — if a player is physically blocked
from view, their ped is **concealed from every client in real time**.

- 🛡️ **Client-side raycasts** — no server CPU cost, each client runs its own checks.
- ⚡ **Instant reveal** — hidden players are rechecked every ~16ms so revealing is seamless.
- 🪟 **Glass-aware** — windows, car glass, and chain-link fences never block visibility.
- 🔄 **Reciprocal visibility** — if they can see you, you see them. No asymmetric blindspots.
- 🔌 **Plug & play** — no framework, no dependencies, drop it in and go.
- 💸 **100% free** — extracted from [Sentra Anticheat](https://sentra.ac) and open-sourced.

---

## 🚀 Quick start

### 1. Install the resource

```
resources/
└── sentra-fow/
    ├── fxmanifest.lua
    ├── client.lua
    └── server.lua
```

### 2. Add to `server.cfg`

```cfg
ensure sentra-fow
```

That's it. No API key, no config file, no dependencies.

---

## ⚙️ How it works

```
 Every tick per nearby player
 ─────────────────────────────────────────────────────────────────
 Camera pos  ──▶  raycast to chest       ──▶  hit solid wall?  ─┐
             ──▶  raycast to 4 sides     ──▶  all blocked?      │
                                                                  ▼
                                              NetworkConcealEntity(ped, true)

 Any raycast clears  ──▶  NetworkConcealEntity(ped, false)  ──▶  instantly visible
```

Side markers are offset based on the target's **velocity** — a sprinting player
gets wider markers so they aren't prematurely hidden while moving.

A **reciprocal visibility relay** runs through the server: when player A reports
"I can see player B", the server tells player B to always render player A. This
prevents edge cases where two players in a fight become invisible to each other.

---

## 🔧 Configuration

All values live at the top of `client.lua`. No separate config file needed.

| Variable | Default | Description |
|---|---|---|
| `OFFSET_BASE` | `1.5` | Base side-marker radius in meters |
| `OFFSET_MAX` | `5.0` | Max side-marker radius at full speed |
| `VEL_MAX` | `7.0` | Speed (m/s) at which marker offset is maxed out |
| `RAYCAST_MARGIN` | `0.5` | Tolerance before a raycast is considered blocked |
| `DISABLE_FOW_IN_INTERIORS` | `true` | Skip FOW when either player is in an interior |
| `VISIBLE_INTERVAL` | `200` | Recheck rate (ms) for already-visible players |
| `SCAN_INTERVAL` | `1000` | How often (ms) new players are detected |
| `SIDES_MAX_DISTANCE` | `100` | Beyond this distance (m) side raycasts are skipped |
| `SEEN_RELEASE_GRACE` | `500` | Grace period (ms) before reporting "I stopped seeing you" |

**Distance-based recheck tiers for hidden players:**

| Distance | Recheck rate |
|---|---|
| < 50m | 32ms |
| > 50m | 64ms |
| > 100m | 128ms |
| > 150m | 256ms |

---

## ✅ Advantages

| | |
|---|---|
| 🖥️ **Zero server load** | All raycast logic runs on each client. The server only relays a tiny visibility signal. |
| ⚡ **Near-instant reveal** | Hidden players are rechecked at 16–32ms. Coming into view feels immediate. |
| 🪟 **Transparent materials** | Glass, car windows, chain-link fences and plastic never block line of sight. |
| 🔄 **Reciprocal fairness** | Neither player in a fight gets an asymmetric vision advantage. |
| 🧹 **Clean restarts** | Concealed state is fully reset every time the resource starts. |
| 🔌 **No dependencies** | Works with any framework — or none at all. |

---

## ❌ Disadvantages

| | |
|---|---|
| ⚠️ **Client-side trust** | The conceal/reveal decision is made on the client. A modified client could bypass `NetworkConcealEntity` and still render hidden peds. |
| 📉 **Raycast overhead** | Up to 5 raycasts per nearby player per tick. Performance degrades in large, dense player groups. |
| 🕐 **State bag dependency** | Real Z position is shared via state bags. This means **FOW breaks completely if `sv_stateBagStrictMode` is enabled** on your server — see the warning below. |
| 🏠 **Interiors are fully disabled** | FOW does not apply inside any interior. This is a forced workaround — certain interior glass and transparent surfaces cannot be reliably distinguished from solid walls by the raycast, causing players to be incorrectly hidden. Until those materials can be identified individually, interiors are excluded entirely. |
| 🔍 **No server verification** | The server does not independently confirm who is behind cover — it only relays the reciprocal visibility signal. |

---

> [!WARNING]
> ## ⚠️ `sv_stateBagStrictMode` incompatibility
>
> sentra-fow uses **state bags** to share each player's real Z position with nearby clients. This is how the system knows exactly where to fire raycasts without relying on the (sometimes unreliable) networked entity position.
>
> If your `server.cfg` contains:
> ```cfg
> set sv_stateBagStrictMode true
> ```
> **FOW will not work.** Strict mode blocks state bag writes from client scripts, so the `realZ` value is never published. Every player will permanently fail the `realZ` check and be kept visible at all times — the system silently does nothing.
>
> **Fix:** either disable strict mode, or add a server-side script that writes `realZ` on behalf of each client and register the key as allowed.

---

## 📁 File structure

```
sentra-fow/
├── fxmanifest.lua   — resource manifest (lua54)
├── client.lua       — FOW logic: raycasts, conceal, reciprocal visibility
└── server.lua       — relay for reciprocal visibility events
```

---

## ⚠️ Limitations of this free release

> [!IMPORTANT]
> **sentra-fow is a free, unsupported snapshot. Read this before using it in production.**
>
> - 🚫 **No updates** — this is a one-time release. Bugs, bypasses and new cheat techniques discovered after release will **not** be patched here.
> - 🚫 **No support** — there is no helpdesk, no Discord support, no issue responses. You're on your own.
> - ⚠️ **Bypasses are possible** — as listed in the disadvantages above, the entire decision is made client-side. A modified client can ignore `NetworkConcealEntity` entirely and render every ped regardless. This is a known, unfixable limitation of a client-only FOW.
> - ⚠️ **No detections** — sentra-fow only hides players. It does **not** detect, flag or punish cheaters in any way.
>
> If any of the above is a dealbreaker for your server, you need the full product.

---

<div align="center">

### Want a version that actually fights back?

**[Sentra Anticheat](https://sentra.ac)** includes a hardened FOW with server-side verification, active cheat detection, automated bans, screenshot capture, Discord logs, and continuous updates against new bypasses.

[![Get Sentra Anticheat](https://img.shields.io/badge/Get%20Sentra%20Anticheat-sentra.ac-ff2b39?style=for-the-badge)](https://sentra.ac)

</div>

---

## License

sentra-fow is a **free module extracted from [Sentra Anticheat](https://sentra.ac)**.
Use it freely, share it, protect your server. ❤️

<div align="center">
<sub>Built by <b>Sentra Anticheat</b> · <a href="https://sentra.ac">sentra.ac</a></sub>
</div>
