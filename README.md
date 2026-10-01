# rde_phone

🔥 WYRM OS — THE PHONE OPERATING SYSTEM FOR FIVEM OX_CORE SERVERS 📱

# 🐉 rde_phone

[![Version](https://img.shields.io/badge/version-1.0.0-red?style=for-the-badge)](https://github.com/RedDragonElite/rde_phone)
[![License](https://img.shields.io/badge/license-RDE%20Black%20Flag-black?style=for-the-badge)](https://github.com/RedDragonElite/rde_phone/blob/main/LICENSE)
[![FiveM](https://img.shields.io/badge/FiveM-Compatible-blue?style=for-the-badge)](https://fivem.net)
[![ox_core](https://img.shields.io/badge/Framework-ox__core-blue?style=for-the-badge)](https://github.com/overextended/ox_core)
[![Zero Dependency](https://img.shields.io/badge/CDN%20Dependencies-0-purple?style=for-the-badge)](https://github.com/RedDragonElite/rde_phone)
[![Quality](https://img.shields.io/badge/Quality-Production-gold?style=for-the-badge)](https://github.com/RedDragonElite)

**📱 RDE Phone | WYRM OS — Standalone FiveM Phone Framework for ox_core | Zero Dependency | App SDK | Real pma-voice Calls | Production-Ready**

*Built by [Red Dragon Elite](https://rd-elite.com) | Free Forever | No Paywalls | No Legacy*

[📖 Installation](#-installation) • [⚙️ Configuration](#%EF%B8%8F-configuration) • [🌍 Locales](#-locales) • [🧩 App SDK](#-app-sdk) • [📡 Exports](#-exports) • [🐛 Troubleshooting](#-troubleshooting) • [🌐 Docs Site](https://rd-elite.com/Files/FiveM/Docs/rde_phone/) • [🌐 Website](https://rd-elite.com)

---

## 🔥 Why This Destroys Every Other Phone Script

Every other FiveM phone is either NPWD wearing a reskin, or a full React app split across resources via Module Federation — sharing a runtime, loaded via a `remoteEntry.js`, one dependency bump away from breaking every app on the phone at once.

We said no.

| ❌ Other Phone Scripts | ✅ rde_phone |
|---|---|
| Module Federation, shared React tree | Every app is a sandboxed `<iframe>` — plain HTML/CSS/JS |
| One broken app can break the whole phone | A broken app is a broken app, not a broken phone |
| CDN dependencies at runtime | Zero — icons, fonts, and the SDK all ship inside the resource |
| Hardcoded homescreen app list | Real registry — apps register themselves via export, at runtime |
| Build step required to add an app | No package.json, no bundler — save the file, restart, done |
| ESX / QBCore bloat | ox_core only — the future, not the past |
| Hand-translated strings per app | Config-driven i18n, one source of truth for Lua and NUI both |
| Paid or locked down | 100% free forever — RDE Black Flag |

### 🎯 Key Features

- 🧩 **App SDK** — one script tag (`rde-phone-sdk.js`) gives any resource `request()`, `on()`, `notify()`, `t()`, `setViewfinder()` — no NUI callback wiring per app
- 📞 **Real Calls** — full ring → connect → hangup UI symmetric on both caller and callee, real voice via pma-voice's client-side call-channel export, ring timeout auto-resolves to "missed"
- 💬 **SMS** — threads, live delivery, gated by phone possession on the receiving end
- 👤 **Contacts** — tap-to-call / tap-to-message shortcuts straight into the other apps
- 📷 **Camera + 🖼 Gallery** — native `CellCamActivate`/`CreateMobilePhone` engine (same mechanism as the base game's own "Take a Selfie"), `screenshot-basic` capture, zero external image host
- ⚙️ **Settings** — wallpaper presets + custom URL/Gallery photo, ringtone/SMS tone with live preview, live language switch
- 🔔 **Push Notifications** — server-side API that reaches players even when their app isn't open, or the phone is closed entirely
- 🌍 **Multilanguage** — EN / DE out of the box, config-driven for both Lua and NUI
- 🛡 **Server-Authoritative** — phone-item possession checked server-side before the NUI even opens, never trust the client for a feature gate
- ⚙️ **Zero-Config Start** — sensible defaults, tables auto-create, no SQL import needed

---

## 📸 Screenshots

<img width="8474" height="9864" alt="rde_phone_diagram" src="https://github.com/user-attachments/assets/1c611c1b-6d7b-45e4-a39f-92c601959423" />

---

## 📦 Dependencies

```
oxmysql        → https://github.com/overextended/oxmysql
ox_lib         → https://github.com/overextended/ox_lib
ox_core        → https://github.com/overextended/ox_core
ox_inventory   → https://github.com/overextended/ox_inventory
pma-voice      → https://github.com/AvarianKnight/pma-voice   (required for Calls)
```

---

## 🚀 Installation

### Step 1: Clone or download

```bash
cd resources
git clone https://github.com/RedDragonElite/rde_phone.git
```

### Step 2: Add to server.cfg

```
# Dependencies first — order matters!
ensure oxmysql
ensure ox_lib
ensure ox_core
ensure ox_inventory
ensure pma-voice

# The phone itself
ensure rde_phone

# Any resource that registers its own phone app goes after rde_phone
ensure rde_banking
```

### Step 3: Register the phone item

```lua
-- ox_inventory/data/items.lua
['phone'] = {
    label  = 'Phone',
    weight = 190,
    stack  = false,
    close  = true,
    client = {
        export = 'rde_phone.use_phone',
    },
},
```

### Step 4: Configure

Edit `config.lua` — sensible defaults work out of the box. See [Configuration](#%EF%B8%8F-configuration).

### Step 5: Start your server

That's it. No SQL import needed — tables auto-create on first run.

---

## ⚙️ Configuration

`config.lua` is fully self-documented. Key sections:

```lua
-- Core
Config.OpenKey    = 'F1'         -- keybind, only opens if PhoneItem check passes
Config.PhoneItem  = 'phone'      -- ox_inventory item required to open the phone
Config.VoiceSystem = 'pma-voice'

-- Calls
Config.CallChannelBase = 1000    -- pma-voice call channels allocated from here up
Config.RingTimeoutMs   = 30000   -- unanswered call -> auto "missed"

-- Phone numbers
Config.PhoneNumber = {
    prefix = '555',
    length = 4,                  -- 555-XXXX
}

-- Language
Config.DefaultLanguage = 'en'    -- English is the default everywhere; German is opt-in via Settings
```

### Locales (i18n)

```lua
Config.Locales = {
    en = { greeting = 'Hello, %s' },
    de = { greeting = 'Hallo, %s' },
}
```

Every string — Lua-side messages and NUI-side UI text — reads from this exact same table via `Config.GetString(key, ...)` (Lua) and `RDEPhone.t(key, ...)` (NUI). Neither side keeps a second copy.

---

## 🌍 Locales

Currently supported out of the box:

| Code | Language |
|---|---|
| `en` | 🇬🇧 English |
| `de` | 🇩🇪 Deutsch |

Add a new language by adding a table under `Config.Locales` in `config.lua` — no separate locale files, no fxmanifest registration, nothing else to touch.

---

## 🧩 App SDK

The homescreen has **no hardcoded app list** — every icon on it, including the six built-in apps, came from a call to `RegisterPhoneApp`. Any resource can plug in its own app without touching a line of the phone's own code:

```lua
-- server.lua
exports.rde_phone:RegisterPhoneApp({
    slug  = 'my_app',
    title = 'My App',
    icon  = 'sparkles',      -- any Lucide icon name
    color = '#a855f7',       -- optional icon tint
    url   = ('https://cfx-nui-%s/web/phone/index.html'):format(GetCurrentResourceName()),
    order = 70,
})
```

```html
<!-- web/phone/index.html -->
<link rel="stylesheet" href="https://cfx-nui-rde_phone/web/theme/rdui-phone.css" />
<script src="https://cfx-nui-rde_phone/web/sdk/rde-phone-sdk.js"></script>

<script>
  await RDEPhone.ready;
  const contacts = await RDEPhone.request('getContacts');
</script>
```

Full SDK reference, the complete "first app in under 40 lines" walkthrough, the design-system class list, and every real pitfall hit building the six built-in apps and three production ports (`rde_banking`, `rde_carservice`, `rde_bodyguards`) live in the [full developer docs](https://rd-elite.com/Files/FiveM/Docs/rde_phone/).

---

## 📡 Exports

### Server

```lua
-- App registry
exports['rde_phone']:RegisterPhoneApp({ slug = 'my_app', title = 'My App', icon = 'sparkles', url = '...' })
exports['rde_phone']:UnregisterPhoneApp('my_app')

-- Push notifications — reaches a player even with a different app open, or the phone closed
exports['rde_phone']:PushNotification(targetSource, {
    title = 'Bank',
    body  = 'Wire received: $500',
    icon  = 'landmark',
    app   = 'banking',
})
```

### Client

```lua
exports['rde_phone']:use_phone()   -- ox_inventory item export target, opens the phone if held
```

---

## 🗂 Folder Structure

```
rde_phone/
├── fxmanifest.lua
├── config.lua
├── README.md
├── LICENSE
├── server/
│   └── server.lua
├── client/
│   └── client.lua
├── data/
│   └── items.lua
└── web/
    ├── index.html
    ├── js/phone.js
    ├── css/phone.css
    ├── sdk/rde-phone-sdk.js
    ├── theme/rdui-audio.js
    ├── vendor/lucide.js
    └── apps/
        ├── sms/
        ├── calls/
        ├── contacts/
        ├── settings/
        ├── camera/
        └── gallery/
```

---

## 🛡 Security

- Phone-item possession checked **server-side** before the NUI opens — a client-side check here would be trivially bypassable
- Phone number ↔ online-player routing table is self-healing: refreshed on `ox:playerLoaded`, on every `getIdentity`/`startCall`, and reconciled for already-connected players on resource (re)start
- Call state machine (`startCall`/`acceptCall`/`hangup`/`declineCall`) is entirely server-authoritative; the NUI only ever reflects state pushed to it
- Push notifications gated by phone possession, same check as every other phone action

---

## 🐛 Troubleshooting

### "No player with that number" on a call to someone who's definitely online

Older builds registered the phone-number ↔ source map on `playerJoining`, which fires before the character is loaded — `Ox.GetPlayer(source)` was still nil at that point, so the identifier lookup silently failed for every player, every session. Fixed by moving registration to `ox:playerLoaded`, plus a self-heal on every `getIdentity`/`startCall` call and a reconciliation pass on resource start. Make sure you're not running a build older than this fix.

### Incoming calls have no ringtone / SMS tone is silent

Chromium (FiveM's CEF NUI included) creates every `AudioContext` in a `suspended` state until a real click/keydown resumes it. An incoming call auto-opening the phone via a server event isn't a gesture — sounds queued into a suspended context throw no error and just produce nothing. Fixed by resuming the context defensively before every sound, plus a one-time unlock on the first real interaction anywhere in the NUI.

### Call connects, UI shows "Connected," but no voice comes through

pma-voice ships both a server export (`setPlayerCall(source, channel)`) and a client export (`setCallChannel(channel)` / `addPlayerToCall(channel)`, called locally by each participant). Only the client-side path is what actually flips a client's own local voice state — the server export alone leaves it never updating, with nothing in the console to point at. rde_phone's call flow triggers a client event to both participants, and each client calls the pma-voice export on itself. If you're integrating pma-voice yourself elsewhere, use the client export.

### Caller's screen is stuck on "Ringing…" even after the other side answers

Make sure `pma-voice` is `ensure`d **before** `rde_phone` in your `server.cfg`, and that no other phone resource (NPWD, etc.) is still running alongside it — two phone scripts fighting over the same pma-voice call-channel state produces exactly this symptom with no errors anywhere.

### Config changes / new locale keys not showing up after updating

If you're extracting a new release zip over an existing install, some archive tools skip overwriting loose root-level files (`config.lua`, `fxmanifest.lua`) even while correctly refreshing subfolders like `server/`, `client/`, `web/`. Check the file timestamps after extracting — `config.lua` should match the zip's date, not an older one. When in doubt, delete the old `config.lua`/`fxmanifest.lua` and re-extract fresh.

### `attempt to call a nil value` / resource fails to start

Check your load order — `rde_phone` depends on `ox_core`, `ox_lib`, `oxmysql`, and `ox_inventory` all starting *before* it, and `pma-voice` before it if you're using Calls.

---

## 📚 Tech Stack

```
ox_core        → Player & group management
ox_lib         → Callbacks, locale loader
ox_inventory   → Phone item possession
oxmysql        → Async database (auto-create tables)
pma-voice      → Real voice for Calls, client-side call-channel export
screenshot-basic → Camera capture, no external upload service
StateBags      → Realtime per-player phone state sync (rde_phone_<identifier>)
```

---

## 🤝 Contributing

PRs are always welcome.

1. **Fork** the repository
2. **Create** a branch: `git checkout -b feature/your-feature`
3. **Test** on a live server before submitting
4. **Commit**: `git commit -m 'feat: your feature description'`
5. **Push**: `git push origin feature/your-feature`
6. **Open** a Pull Request with a clear description

**Guidelines:**

- ✅ Keep the RDE header in all files
- ✅ Follow existing code style — ox_core, ox_lib, StateBags, statebag-first, server-authoritative
- ✅ Run `luac -p` on every modified `.lua` file before pushing
- ✅ Test on a live server before PR
- ❌ No telemetry, no paywalls, no ESX/QBCore
- ❌ Don't downgrade security — server-side validation stays
- ❌ Don't hardcode user-facing strings — use `Config.GetString()` / `RDEPhone.t()` and add to all locales

---

## 📜 License

**RDE Black Flag Source License v6.66**

```
###################################################################################
#                                                                                 #
#      .:: RED DRAGON ELITE (RDE)  -  BLACK FLAG SOURCE LICENSE v6.66 ::.         #
#                                                                                 #
#   PROJECT:    RDE_PHONE | WYRM OS — STANDALONE PHONE FRAMEWORK FOR OX_CORE      #
#   ARCHITECT:  .:: RDE ⧌ Shin [ △ ᛋᛅᚱᛒᛅᚾᛏᛋ ᛒᛁᛏᛅ ▽ ] ::. | https://rd-elite.com   #
#   ORIGIN:     https://github.com/RedDragonElite                                 #
#                                                                                 #
#   WARNING: THIS CODE IS PROTECTED BY DIGITAL VOODOO AND PURE HATRED FOR LEAKERS #
#                                                                                 #
#   [ THE RULES OF THE GAME ]                                                     #
#                                                                                 #
#   1. // THE "FUCK GREED" PROTOCOL (FREE USE)                                    #
#      You are free to use, edit, and abuse this code on your server.             #
#      Learn from it. Break it. Fix it. That is the hacker way.                   #
#      Cost: 0.00€. If you paid for this, you got scammed by a rat.               #
#                                                                                 #
#   2. // THE TEBEX KILL SWITCH (COMMERCIAL SUICIDE)                              #
#      Listen closely, you parasites:                                             #
#      If I find this script on Tebex, Patreon, or in a paid "Premium Pack":      #
#      > I will DMCA your store into oblivion.                                    #
#      > I will publicly shame your community.                                    #
#      > I hope every customer who bought this from you calls to demand a         #
#        refund, on speaker, in a family group chat, right as your mom picks up.  #
#      SELLING FREE WORK IS THEFT. AND I AM THE JUDGE.                            #
#                                                                                 #
#   3. // THE CREDIT OATH                                                         #
#      Keep this header. If you remove my name, you admit you have no skill.      #
#      You can add "Edited by [YourName]", but never erase the original creator.  #
#      Don't be a skid. Respect the architecture.                                 #
#                                                                                 #
#   4. // THE CURSE OF THE COPY-PASTE                                             #
#      This code uses advanced Statebags, an App SDK, and heavy async logic.      #
#      If you just copy-paste without reading, it WILL break.                     #
#      Don't come crying to my DMs. RTFM or learn to code.                        #
#                                                                                 #
#   ---------------------------------------------------------------------------   #
#   "We build the future on the graves of paid resources."                        #
#   "REJECT MODERN MEDIOCRITY. EMBRACE RDE SUPERIORITY."                          #
#   ---------------------------------------------------------------------------   #
###################################################################################
```

**TL;DR:** ✅ Free forever · ✅ Keep the header · ❌ Don't sell it · ❌ Don't be a skid

---

## ⚡ Related Projects

| Resource | Description |
|---|---|
| [rde_banking](https://github.com/RedDragonElite/rde_banking) | Full banking phone app — first production proof of the App SDK/registry |
| [rde_carservice](https://github.com/RedDragonElite/rde_carservice) | Garage vehicle delivery, phone app ported off NPWD onto rde_phone |
| [rde_bodyguards](https://github.com/RedDragonElite/rde_bodyguards) | Squad orders + public marketplace phone app |
| [awesome-ox-rde](https://github.com/RedDragonElite/awesome-ox-rde) | Curated list of the best ox_core resources |

---

## 🌐 Community & Support

| | |
|---|---|
| 🌍 **Website** | [rd-elite.com](https://rd-elite.com) |
| 📖 **Developer Docs** | [rd-elite.com/Files/FiveM/Docs/rde_phone](https://rd-elite.com/Files/FiveM/Docs/rde_phone/) |
| 🐙 **GitHub** | [github.com/RedDragonElite](https://github.com/RedDragonElite) |

---

**Made with 🔥 and zero patience for Module Federation by [Red Dragon Elite](https://rd-elite.com)**

*The future is ours. We are already inside.*

**REJECT MODERN MEDIOCRITY. EMBRACE RDE SUPERIORITY.**

**RDE FOREVER. SYSTEM FAILURE. ⚡777⚡**

[![Website](https://img.shields.io/badge/Website-Visit-red?style=for-the-badge&logo=google-chrome)](https://rd-elite.com)
[![Docs](https://img.shields.io/badge/Docs-Read-green?style=for-the-badge&logo=readthedocs)](https://rd-elite.com/Files/FiveM/Docs/rde_phone/)
[![GitHub](https://img.shields.io/badge/GitHub-RedDragonElite-black?style=for-the-badge&logo=github)](https://github.com/RedDragonElite)
